/**
Settings container, loader and saver.

Uses JSON by default, can be written/read to/from this format.

Map here is ordered, and can be indexed by number.

Has a lot of methods for convenient storing/accessing of settings.

Synopsis:
---
import beamui.core.settings;
---

Copyright: Vadim Lopatin 2015-2016, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.settings;

import std.datetime : SysTime;
import std.file;
import std.json;
import std.path;
import beamui.core.logger;

///
unittest
{
    // create an empty setting
    auto s = new Setting;
    assert(s.isNull);
    // now it returns only default values
    assert(s.str is null);
    assert(s.integer == 0);
    assert(s.integerDef(25) == 25);
    assert(s.boolean == false);
    assert(s.strMap is null);
    // and so on.

    // let's make a settings tree
    Setting p = s.add("properties");
    Setting pos = p.add("position");
    Setting font = p.add("font");
    pos.add("x").integer = 100;
    pos.add("y").integer = 50;
    font.add("size").integer = 15;
    font.add("style").str = "italic";
    assert(s["properties"]["position"][0].integer == 100);

    // you can add a whole array
    Setting arr = s.add("values");
    arr.intArray = [0, 1, 4, 9, 16, 25];
    assert(arr.length == 6);
    assert(arr[4].integer == 16);

    // indexing never returns null - rather it returns a special dummy setting, which cannot be modified
    assert(s[4].isset == false);
    s["key"].integer = 50;
    assert(s["key"].integerDef(1) == 1);

    // second `add` replaces existing item
    Setting prev = pos["x"];
    pos.add("x").integer = 300;
    assert(prev !is pos["x"]);
    // but when you need just to change the value or the type, use indexing
    pos["x"].integer = 200;

    // initialize an item with default value
    pos.setup("z").integer = 100;
    // which does nothing if item is already present
    pos.setup("x").integer = 100;
    assert(pos["x"].integer == 200);
}

/// Settings object with file information
class SettingsFile
{
    protected Setting _setting;
    protected string _filename;
    protected SysTime _lastModificationTime;
    protected bool _loaded;

    @property Setting setting()
    {
        return _setting;
    }

    @property Setting copySettings()
    {
        return _setting.clone();
    }
    /// Replace setting object
    void replaceSetting(Setting s)
    {
        _setting = s;
    }

    @property void applySettings(Setting settings)
    {
        // TODO copy only changed settings
        _setting = settings;
        //_setting.apply(settings);
    }

    alias setting this;

    /// Create settings file object; if filename is provided, attempts to load settings from file
    this(string filename = null)
    {
        _setting = new Setting;
        _filename = filename;
        if (_filename)
        {
            string dir = dirName(_filename);
            if (load())
            {
                // loaded ok
            }
            else
            {
            }
        }
    }

    static int limitInt(long value, int minvalue, int maxvalue)
    {
        if (value < minvalue)
            return minvalue;
        if (value > maxvalue)
            return maxvalue;
        return cast(int)value;
        // remove clamp to support older compilers
        //return clamp(cast(int)value, minvalue, maxvalue);
    }

    static string limitString(string value, const string[] values)
    in
    {
        assert(values.length > 0);
    }
    body
    {
        foreach (v; values)
            if (v == value)
                return value;
        return values[0];
    }

    @property bool loaded()
    {
        return _loaded;
    }

    /// Filename
    @property string filename()
    {
        return _filename;
    }
    /// Filename
    @property void filename(string fn)
    {
        _filename = fn;
    }

    protected bool updateModificationTime()
    {
        if (_filename is null)
            return false;
        try
        {
            if (!_filename.exists || !_filename.isFile)
                return false;
            SysTime accTime;
            getTimes(_filename, accTime, _lastModificationTime);
            return true;
        }
        catch (Exception e)
        {
            return false;
        }
    }

    /// Load settings from file
    bool load(string filename = null)
    {
        if (filename !is null)
            _filename = filename;
        assert(_filename !is null);
        if (updateModificationTime())
        {
            bool res = _setting.load(_filename);
            if (res)
                _loaded = true;
            afterLoad();
            return res;
        }
        return false;
    }

    /// Save settings to file
    bool save(string filename = null, bool pretty = true)
    {
        if (filename !is null)
            _filename = filename;
        assert(_filename);
        string dir = dirName(_filename);
        if (!dir.exists)
        {
            try
            {
                mkdirRecurse(dir);
            }
            catch (Exception e)
            {
                return false;
            }
        }
        else if (!dir.isDir)
        {
            Log.d("", dir, " is file");
            return false;
        }
        bool res = _setting.save(_filename, pretty);
        res = updateModificationTime() || res;
        afterSave();
        return res;
    }

    /// Override to add default values if missing
    void updateDefaults()
    {
    }

    /// Override to do something after loading - e.g. set defaults
    void afterLoad()
    {
    }

    /// Override to do something after saving
    void afterSave()
    {
    }

    bool merge(string json)
    {
        try
        {
            Setting setting = new Setting;
            setting.fromJSON(json);
            _setting.apply(setting);
        }
        catch (Exception e)
        {
            Log.e("SettingsFile.merge - failed to parse json", e);
            return false;
        }
        return true;
    }
}

/// Setting object
final class Setting
{
    private union Store
    {
        string str;
        long integer;
        double floating;
        bool boolean;
        SettingArray array;
        SettingMap map;
    }
    private enum SettingType
    {
        str,
        integer,
        floating,
        boolean,
        object,
        array,
        nothing
    }

    private Store store;
    private SettingType type = SettingType.nothing;

    private Setting _parent;
    private bool _changed;

    private static __gshared Setting dummy = new Setting;

    /// Array
    private static struct SettingArray
    {
        Setting[] list;

        @property bool empty() const
        {
            return list.length == 0;
        }

        Setting set(size_t index, Setting value, Setting parent = null)
        {
            if (index < 0)
                index = list.length;
            if (index >= list.length)
            {
                size_t oldlen = list.length;
                list.length = index + 1;
                foreach (i; oldlen .. index)
                    list[i] = new Setting; // insert null items in holes
            }
            list[index] = value;
            value.parent = parent;
            return value;
        }
        /// Get item by index, returns null if index out of bounds
        Setting get(size_t index)
        {
            if (index < 0 || index >= list.length)
                return null;
            return list[index];
        }
        /// Remove by index, returns removed value
        Setting remove(size_t index)
        {
            Setting res = get(index);
            if (!res)
                return null;
            foreach (i; index .. list.length - 1)
                list[i] = list[i + 1];
            list[$ - 1] = null;
            list.length--;
            return res;
        }

        @property size_t length() const
        {
            return list.length;
        }
        /// Deep copy
        void copyFrom(ref SettingArray v)
        {
            list.length = v.list.length;
            foreach (i; 0 .. v.list.length)
            {
                list[i] = v.list[i].clone();
            }
        }
    }

    /// Ordered map
    private static struct SettingMap
    {
        Setting[] list;
        size_t[string] map;

        @property bool empty() inout
        {
            return list.length == 0;
        }
        /// Get item by index, returns null if index out of bounds
        Setting get(size_t index)
        {
            if (index < 0 || index >= list.length)
                return null;
            return list[index];
        }
        /// Get item by key, returns null if key is not found
        Setting get(string key)
        {
            auto p = (key in map);
            if (!p)
                return null;
            return list[*p];
        }

        Setting set(string key, Setting value, Setting parent)
        {
            value.parent = parent;
            auto p = (key in map);
            if (p)
            {
                // key is found
                list[*p] = value;
            }
            else
            {
                // new value
                list ~= value;
                map[key] = list.length - 1;
            }
            return value;
        }

        /// Remove by index, returns removed value
        Setting remove(size_t index)
        {
            Setting res = get(index);
            if (!res)
                return null;
            foreach (i; index .. list.length - 1)
                list[i] = list[i + 1];
            list[$ - 1] = null;
            list.length--;
            string key;
            foreach (k, ref v; map)
            {
                if (v == index)
                {
                    key = k;
                }
                else if (v > index)
                {
                    v--;
                }
            }
            if (key)
                map.remove(key);
            return res;
        }
        /// Returns key for index
        string keyByIndex(size_t index)
        {
            foreach (k, ref v; map)
            {
                if (v == index)
                {
                    return k;
                }
            }
            return null;
        }
        /// Remove by key, returns removed value
        Setting remove(string key)
        {
            auto p = (key in map);
            if (!p)
                return null;
            return remove(*p);
        }

        @property int length()
        {
            return cast(int)list.length;
        }
        /// Deep copy
        void copyFrom(SettingMap* v)
        {
            list.length = v.list.length;
            foreach (i; 0 .. v.list.length)
            {
                list[i] = v.list[i].clone();
            }
            destroy(map);
            foreach (key, value; v.map)
                map[key] = value;
        }
    }

    /// True if setting has been changed
    @property bool changed()
    {
        return _changed;
    }

    /// Parent setting
    @property inout(Setting) parent() inout
    {
        return _parent;
    }
    /// ditto
    @property Setting parent(Setting v)
    {
        _parent = v;
        return v;
    }

    //===============================================================
    // Type checks

    @property const
    {
        bool isString()
        {
            return type == SettingType.str;
        }

        bool isInteger()
        {
            return type == SettingType.integer;
        }

        bool isFloating()
        {
            return type == SettingType.floating;
        }

        bool isBoolean()
        {
            return type == SettingType.boolean;
        }

        bool isArray()
        {
            return type == SettingType.array;
        }

        bool isObject()
        {
            return type == SettingType.object;
        }

        bool isNull()
        {
            return type == SettingType.nothing;
        }
        /// Check whether this setting exists
        bool isset()
        {
            return this !is null && this !is dummy;
        }
    }

    /// Returns true whether this setting has equal type as the parameter
    bool compareType(Setting s)
    {
        return type == s.type;
    }

    //===============================================================
    // Utility

    /// Clear setting value and set the new type
    void clear(SettingType newType)
    {
        if (!isset)
            return;
        if (newType != type)
        {
            clear();
            type = newType;
        }
        clear();
    }
    /// Clear setting value
    void clear()
    {
        if (!isset)
            return;
        final switch (type) with (SettingType)
        {
        case str:
            store.str = store.str.init;
            break;
        case integer:
            store.integer = store.integer.init;
            break;
        case floating:
            store.floating = store.floating.init;
            break;
        case boolean:
            store.boolean = store.boolean.init;
            break;
        case array:
            store.array = store.array.init;
            break;
        case object:
            store.map = store.map.init;
            break;
        case nothing:
            break;
        }
    }

    void apply(Setting settings)
    {
        if (!isset)
            return;
        if (settings.isObject)
        {
            foreach (key, value; settings.map)
            {
                this[key] = value;
            }
        }
    }

    /// Deep copy of settings
    Setting clone()
    {
        if (!isset)
            return dummy;
        auto res = new Setting;
        res.clear(type);
        final switch (type) with (SettingType)
        {
        case str:
            res.store.str = store.str;
            break;
        case integer:
            res.store.integer = store.integer;
            break;
        case floating:
            res.store.floating = store.floating;
            break;
        case boolean:
            res.store.boolean = store.boolean;
            break;
        case array:
            res.store.array.copyFrom(store.array);
            break;
        case object:
            res.store.map.copyFrom(&store.map);
            break;
        case nothing:
            break;
        }
        res._changed = false;
        return res;
    }

    /// Get number of elements for array or map, returns 0 for other types
    @property size_t length() const
    {
        if (isArray)
            return store.array.list.length;
        else if (isObject)
            return store.map.list.length;
        else
            return 0;
    }

    /// Add and return an empty setting for array by an integer index
    Setting add(size_t index)
    {
        if (!isset)
            return dummy;
        if (!isArray)
            clear(SettingType.array);
        auto s = new Setting;
        store.array.set(index, s, this);
        return s;
    }
    /// Add and return an empty setting for object by a string key
    Setting add(string key)
    {
        if (!isset)
            return dummy;
        if (!isObject)
            clear(SettingType.object);
        auto s = new Setting;
        store.map.set(key, s, this);
        return s;
    }

    /// Add and return an empty setting for array by an integer index only if it's not present
    Setting setup(size_t index)
    {
        if (!isset)
            return dummy;
        if (this[index].isset)
            return dummy;
        else
            return add(index);
    }
    /// Add and return an empty setting for object by a string key only if it's not present
    Setting setup(string key)
    {
        if (!isset)
            return dummy;
        if (this[key].isset)
            return dummy;
        else
            return add(key);
    }

    /// Remove array or object item by an index.
    /// Returns removed item or null if index is out of bounds or setting is neither array nor object.
    Setting remove(size_t index)
    {
        if (!isset)
            return null;
        if (isArray)
            return store.array.remove(index);
        else if (isObject)
            return store.map.remove(index);
        else
            return null;
    }
    /// Remove object item by a key.
    /// Returns removed item or null if is not found or setting is not an object
    Setting remove(string key)
    {
        if (!isset)
            return null;
        if (isObject)
            return store.map.remove(key);
        else
            return null;
    }

    //===============================================================
    // Value getters and setters

    // basic

    /// String value of this setting. Getter returns null if setting holds wrong type.
    @property string str() const
    {
        return isString ? store.str : null;
    }
    /// ditto
    @property string str(string value)
    {
        if (!isset)
            return value;
        if (!isString)
            clear(SettingType.str);
        return store.str = value;
    }
    /// Get string value of this setting or `defaultValue` if setting holds wrong type
    string strDef(string defaultValue) const
    {
        return isString ? store.str : defaultValue;
    }

    /// Long value of this setting. Getter returns 0 if setting holds wrong type.
    @property long integer() const
    {
        return isInteger ? store.integer : 0;
    }
    /// ditto
    @property long integer(long value)
    {
        if (!isset)
            return value;
        if (!isInteger)
            clear(SettingType.integer);
        return store.integer = value;
    }
    /// Get long value of this setting or `defaultValue` if setting holds wrong type
    long integerDef(long defaultValue) const
    {
        return isInteger ? store.integer : defaultValue;
    }

    /// Double value of this setting. Getter returns 0.0 if setting holds wrong type.
    @property double floating() const
    {
        return isFloating ? store.floating : 0;
    }
    /// ditto
    @property double floating(double value)
    {
        if (!isset)
            return value;
        if (!isFloating)
            clear(SettingType.floating);
        return store.floating = value;
    }
    /// Get double value of this setting or `defaultValue` if setting holds wrong type
    double floatingDef(double defaultValue) const
    {
        return isFloating ? store.floating : defaultValue;
    }

    /// Bool value of this setting. Getter returns false if setting holds wrong type.
    @property bool boolean() const
    {
        return isBoolean ? store.boolean : false;
    }
    /// ditto
    @property bool boolean(bool value)
    {
        if (!isset)
            return value;
        if (!isBoolean)
            clear(SettingType.boolean);
        return store.boolean = value;
    }
    /// Get bool value of this setting or `defaultValue` if setting holds wrong type
    bool booleanDef(bool defaultValue) const
    {
        return isBoolean ? store.boolean : defaultValue;
    }

    // complex

    /// Items as a string array
    @property string[] strArray()
    {
        if (isArray || isObject)
        {
            string[] res;
            foreach (i; 0 .. length)
                res ~= this[i].str;
            return res;
        }
        else
            return null;
    }
    /// ditto
    @property string[] strArray(string[] list)
    {
        if (!isset)
            return list;
        clear(SettingType.array);
        foreach (item; list)
        {
            auto s = new Setting;
            s.str = item;
            this[length] = s;
        }
        return list;
    }

    /// Items as an int array
    @property int[] intArray()
    {
        if (isArray || isObject)
        {
            int[] res;
            foreach (i; 0 .. length)
                res ~= cast(int)this[i].integer;
            return res;
        }
        else
            return null;
    }
    /// ditto
    @property int[] intArray(int[] list)
    {
        if (!isset)
            return list;
        clear(SettingType.array);
        foreach (item; list)
        {
            auto s = new Setting;
            s.integer = cast(long)item;
            this[length] = s;
        }
        return list;
    }

    /// Items as a Setting array
    @property Setting[] array()
    {
        if (isArray || isObject)
        {
            Setting[] res;
            foreach (i; 0 .. length)
                res ~= this[i];
            return res;
        }
        else
            return null;
    }
    /// ditto
    @property Setting[] array(Setting[] list)
    {
        if (!isset)
            return list;
        clear(SettingType.array);
        foreach (s; list)
        {
            this[length] = s;
        }
        return list;
    }

    /// Items as a string[string] map
    @property string[string] strMap()
    {
        if (isObject)
        {
            string[string] res;
            foreach (key, value; store.map.map)
            {
                Setting v = store.map.get(value);
                res[key] = v ? v.str : null;
            }
            return res;
        }
        else
            return null;
    }
    /// ditto
    @property string[string] strMap(string[string] list)
    {
        if (!isset)
            return list;
        clear(SettingType.object);
        foreach (key, value; list)
        {
            auto s = new Setting;
            s.str = value;
            this[length] = s;
        }
        return list;
    }

    /// Items as an int[string] map
    @property int[string] intMap()
    {
        if (isObject)
        {
            int[string] res;
            foreach (key, value; store.map.map)
                res[key] = cast(int)this[value].integer;
            return res;
        }
        else
            return null;
    }
    /// ditto
    @property int[string] intMap(int[string] list)
    {
        if (!isset)
            return list;
        clear(SettingType.object);
        foreach (key, value; list)
        {
            auto s = new Setting;
            s.integer = cast(long)value;
            this[length] = s;
        }
        return list;
    }

    /// Items as a Setting[string] map
    @property Setting[string] map()
    {
        if (isObject)
        {
            Setting[string] res;
            foreach (key, value; store.map.map)
                res[key] = this[value];
            return res;
        }
        else
            return null;
    }
    /// ditto
    @property Setting[string] map(Setting[string] list)
    {
        if (!isset)
            return list;
        clear(SettingType.object);
        foreach (key, value; list)
        {
            this[key] = value;
        }
        return list;
    }

    //===============================================================
    // Operators

    /// To iterate using foreach
    int opApply(int delegate(ref Setting) dg)
    {
        int result = 0;
        if (isArray)
        {
            for (int i = 0; i < store.array.list.length; i++)
            {
                result = dg(store.array.list[i]);
                if (result)
                    break;
            }
        }
        else if (isObject)
        {
            for (int i = 0; i < store.map.list.length; i++)
            {
                result = dg(store.map.list[i]);
                if (result)
                    break;
            }
        }
        return result;
    }

    /// To iterate over object using foreach (key, value; map)
    int opApply(int delegate(ref string, ref Setting) dg)
    {
        int result = 0;
        if (isObject)
        {
            for (int i = 0; i < store.map.list.length; i++)
            {
                string key = store.map.keyByIndex(i);
                result = dg(key, store.map.list[i]);
                if (result)
                    break;
            }
        }
        return result;
    }

    /// To iterate using foreach_reverse
    int opApplyReverse(int delegate(ref Setting) dg)
    {
        int result = 0;
        if (isArray)
        {
            for (int i = cast(int)store.array.list.length - 1; i >= 0; i--)
            {
                result = dg(store.array.list[i]);
                if (result)
                    break;
            }
        }
        else if (isObject)
        {
            for (int i = cast(int)store.map.list.length - 1; i >= 0; i--)
            {
                result = dg(store.map.list[i]);
                if (result)
                    break;
            }
        }
        return result;
    }

    /// For array or object returns item by index, null if index is out of bounds or setting is neither array nor object
    Setting opIndex(size_t index)
    {
        Setting res;
        if (isArray)
            res = store.array.get(index);
        else if (isObject)
            res = store.map.get(index);
        return res ? res : dummy;
    }
    /// For object returns item by key, null if not found or this setting is not an object
    Setting opIndex(string key)
    {
        Setting res;
        if (isObject)
            res = store.map.get(key);
        return res ? res : dummy;
    }

    /// Assign setting to array by integer index
    Setting opIndexAssign(Setting value, size_t index)
    {
        if (!isset)
            return dummy;
        if (!isArray)
            clear(SettingType.array);
        store.array.set(index, value, this);
        return value;
    }
    /// Assign setting to object by string key
    Setting opIndexAssign(Setting value, string key)
    {
        if (!isset)
            return dummy;
        if (!isObject)
            clear(SettingType.object);
        store.map.set(key, value, this);
        return value;
    }

    //===============================================================
    // Path selectors

    /// Returns setting by path like "editors/sourceEditor/tabSize", creates object tree "editors/sourceEditor" and object of specified type if part of path does not exist.
    Setting settingByPath(string path, bool createIfNotExist = true)
    {
        if (!isset)
            return dummy;
        if (!isObject)
            clear(SettingType.object);
        string part1, part2;
        if (splitKey(path, part1, part2))
        {
            auto s = this[part1];
            if (!s.isset)
            {
                s = new Setting;
                s.clear(SettingType.object);
                this[part1] = s;
            }
            return s.settingByPath(part2);
        }
        else
        {
            auto s = this[path];
            if (!s.isset && createIfNotExist)
            {
                s = new Setting;
                this[path] = s;
            }
            return s;
        }
    }

    /// Get (or optionally create) object (map) by slash delimited path (e.g. key1/subkey2/subkey3)
    Setting objectByPath(string path, bool createIfNotExist = false)
    {
        if (!isset)
            return dummy;
        if (!isObject)
        {
            if (!createIfNotExist)
                return dummy;
            // do we need to allow this conversion to object?
            clear(SettingType.object);
        }
        string part1, part2;
        if (splitKey(path, part1, part2))
        {
            auto s = this[part1];
            if (!s.isset)
            {
                if (!createIfNotExist)
                    return dummy;
                s = new Setting;
                s.clear(SettingType.object);
                this[part1] = s;
            }
            return s.objectByPath(part2, createIfNotExist);
        }
        else
        {
            auto s = this[path];
            if (!s.isset)
            {
                if (!createIfNotExist)
                    return dummy;
                s = new Setting;
                s.clear(SettingType.object);
                this[path] = s;
            }
            return s;
        }
    }

    private static bool splitKey(string key, ref string part1, ref string part2)
    {
        int dashPos = -1;
        for (int i = 0; i < key.length; i++)
        {
            if (key[i] == '/')
            {
                dashPos = i;
                break;
            }
        }
        if (dashPos >= 0)
        {
            // path
            part1 = key[0 .. dashPos];
            part2 = key[dashPos + 1 .. $];
            return true;
        }
        return false;
    }

    //===============================================================
    // File save/load

    /// Load JSON from file; returns true if loaded successfully
    bool load(string filename)
    {
        try
        {
            fromJSON(readText(filename));
            return true;
        }
        catch (Exception e)
        {
            Log.e("exception while loading settings file: ", e);
            return false;
        }
    }

    /// Save to file
    bool save(string filename, bool pretty = true)
    {
        try
        {
            write(filename, toJSON(pretty));
            return true;
        }
        catch (Exception e)
        {
            Log.e("exception while saving settings file: ", e);
            return false;
        }
    }

    /// Deserialize from JSON
    void fromJSON(string source)
    {
        clear(SettingType.nothing);
        JSONValue value = parseJSON(source, JSONOptions.specialFloatLiterals);
        applyJSON(value);
    }

    private void applyJSON(ref JSONValue value)
    {
        switch (value.type)
        {
        case JSONType.null_:
            // do nothing - we already have null value
            break;
        case JSONType.string:
            this.str = value.str;
            break;
        case JSONType.integer:
            this.integer = value.integer;
            break;
        case JSONType.uinteger:
            this.integer = value.uinteger;
            break;
        case JSONType.float_:
            this.floating = value.floating;
            break;
        case JSONType.true_:
            this.boolean = true;
            break;
        case JSONType.false_:
            this.boolean = false;
            break;
        case JSONType.array:
            clear(SettingType.array);
            foreach (size_t i, val; value)
            {
                auto s = new Setting;
                s.applyJSON(val);
                this[store.array.length] = s;
            }
            break;
        case JSONType.object:
            clear(SettingType.object);
            foreach (string key, val; value)
            {
                auto s = new Setting;
                s.applyJSON(val);
                this[key] = s;
            }
            break;
        default:
            break;
        }
    }

    /// Serialize to JSON
    string toJSON(bool pretty = false)
    {
        JSONValue root = makeJSON();
        return std.json.toJSON(root, pretty, JSONOptions.specialFloatLiterals);
    }

    private JSONValue makeJSON()
    {
        final switch (type) with (SettingType)
        {
        case str:
            return JSONValue(store.str);
        case integer:
            return JSONValue(store.integer);
        case floating:
            return JSONValue(store.floating);
        case boolean:
            return JSONValue(store.boolean);
        case nothing:
            return JSONValue(null);
        case array:
            JSONValue value;
            foreach (i; 0 .. store.array.length)
            {
                value ~= store.array.get(i).makeJSON();
            }
            return value;
        case object:
            JSONValue[string] obj;
            foreach (i; 0 .. store.map.length)
            {
                string key = store.map.keyByIndex(i);
                obj[key] = store.map.get(i).makeJSON();
            }
            return JSONValue(obj);
        }
    }
}
