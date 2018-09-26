/**
This module contains implementation of settings container.

Similar to JSON, can be written/read to/from JSON.

Difference from usual JSON implementations: map (object) is ordered - will be written in the same order as read (or created).

Has a lot of methods for convenient storing/accessing of settings.


Synopsis:
---
import beamui.core.settings;

auto s = new Setting;
---

Copyright: Vadim Lopatin 2015-2016, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.settings;

import std.datetime : SysTime;
import std.file;
import std.math : pow;
import std.path;
import std.range;
import std.utf : encode;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.parseutils;

/// Settings object whith file information
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
            setting.parseJSON(json);
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
    }

    //===============================================================
    // Utility

    /// Clear setting value and set the new type
    void clear(SettingType newType)
    {
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
        if (!isArray)
            clear(SettingType.array);
        auto s = new Setting;
        store.array.set(index, s, this);
        return s;
    }
    /// Add and return an empty setting for object by a string key
    Setting add(string key)
    {
        if (!isObject)
            clear(SettingType.object);
        auto s = new Setting;
        store.map.set(key, s, this);
        return s;
    }

    /// Add and return an empty setting for array by an integer index only if it's not present
    Setting addDef(size_t index)
    {
        if (this[index] is null)
            return add(index);
        else
            return null;
    }
    /// Add and return an empty setting for object by a string key only if it's not present
    Setting addDef(string key)
    {
        if (this[key] is null)
            return add(key);
        else
            return null;
    }

    /// Remove array or object item by an index.
    /// Returns removed item or null if index is out of bounds or setting is neither array nor object.
    Setting remove(size_t index)
    {
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
        if (isArray)
            return store.array.get(index);
        else if (isObject)
            return store.map.get(index);
        else
            return null;
    }
    /// For object returns item by key, null if not found or this setting is not an object
    Setting opIndex(string key)
    {
        if (isObject)
            return store.map.get(key);
        else
            return null;
    }

    /// Assign setting to array by integer index
    Setting opIndexAssign(Setting value, size_t index)
    {
        if (!isArray)
            clear(SettingType.array);
        store.array.set(index, value, this);
        return value;
    }
    /// Assign setting to object by string key
    Setting opIndexAssign(Setting value, string key)
    {
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
        if (!isObject)
            clear(SettingType.object);
        string part1, part2;
        if (splitKey(path, part1, part2))
        {
            auto s = this[part1];
            if (!s)
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
            if (!s && createIfNotExist)
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
        if (!isObject)
        {
            if (!createIfNotExist)
                return null;
            // do we need to allow this conversion to object?
            clear(SettingType.object);
        }
        string part1, part2;
        if (splitKey(path, part1, part2))
        {
            auto s = this[part1];
            if (!s)
            {
                if (!createIfNotExist)
                    return null;
                s = new Setting;
                s.clear(SettingType.object);
                this[part1] = s;
            }
            return s.objectByPath(part2, createIfNotExist);
        }
        else
        {
            auto s = this[path];
            if (!s)
            {
                if (!createIfNotExist)
                    return null;
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
    // JSON

    /// Serialize to json
    string toJSON(bool pretty = false)
    {
        Buf buf;
        toJSON(buf, 0, pretty);
        return buf.get();
    }

    private static struct Buf
    {
        char[] buffer;
        int pos;
        string get()
        {
            return buffer[0 .. pos].dup;
        }

        void reserve(size_t size)
        {
            if (pos + size >= buffer.length)
                buffer.length = buffer.length ? 4096 : (pos + size + 4096) * 2;
        }

        void append(char ch)
        {
            buffer[pos++] = ch;
        }

        void append(string s)
        {
            foreach (ch; s)
                buffer[pos++] = ch;
        }

        void appendEOL()
        {
            append('\n');
        }

        void appendTabs(int level)
        {
            reserve(level * 4 + 1024);
            foreach (i; 0 .. level)
            {
                buffer[pos++] = ' ';
                buffer[pos++] = ' ';
                buffer[pos++] = ' ';
                buffer[pos++] = ' ';
            }
        }

        void appendHex(uint ch)
        {
            buffer[pos++] = '\\';
            buffer[pos++] = 'u';
            for (int i = 3; i >= 0; i--)
            {
                uint d = (ch >> (4 * i)) & 0x0F;
                buffer[pos++] = "0123456789abcdef"[d];
            }
        }

        void appendJSONString(string s)
        {
            reserve(s.length * 3 + 8);
            if (s is null)
            {
                append("null");
            }
            else
            {
                append('\"');
                foreach (ch; s)
                {
                    switch (ch)
                    {
                    case '\\':
                        buffer[pos++] = '\\';
                        buffer[pos++] = '\\';
                        break;
                    case '\"':
                        buffer[pos++] = '\\';
                        buffer[pos++] = '\"';
                        break;
                    case '\r':
                        buffer[pos++] = '\\';
                        buffer[pos++] = 'r';
                        break;
                    case '\n':
                        buffer[pos++] = '\\';
                        buffer[pos++] = 'n';
                        break;
                    case '\b':
                        buffer[pos++] = '\\';
                        buffer[pos++] = 'b';
                        break;
                    case '\t':
                        buffer[pos++] = '\\';
                        buffer[pos++] = 't';
                        break;
                    case '\f':
                        buffer[pos++] = '\\';
                        buffer[pos++] = 'f';
                        break;
                    default:
                        if (ch < ' ')
                        {
                            appendHex(ch);
                        }
                        else
                        {
                            buffer[pos++] = ch;
                        }
                        break;
                    }
                }
                append('\"');
            }
        }
    }

    void toJSON(ref Buf buf, int level, bool pretty)
    {
        buf.reserve(1024);
        final switch (type) with (SettingType)
        {
        case str:
            buf.appendJSONString(store.str);
            break;
        case integer:
            buf.append(to!string(store.integer));
            break;
        case floating:
            buf.append(to!string(store.floating));
            break;
        case boolean:
            buf.append(store.boolean ? "true" : "false");
            break;
        case nothing:
            buf.append("null");
            break;
        case array:
            buf.append('[');
            if (pretty && store.array.length > 0)
                buf.appendEOL();
            foreach (i; 0 .. store.array.length)
            {
                if (pretty)
                    buf.appendTabs(level + 1);
                store.array.get(i).toJSON(buf, level + 1, pretty);
                if (i >= store.array.length - 1)
                    break;
                buf.append(',');
                if (pretty)
                    buf.appendEOL();
            }
            if (pretty)
            {
                buf.appendEOL();
                buf.appendTabs(level);
            }
            buf.append(']');
            break;
        case object:
            buf.append('{');
            if (store.map.length)
            {
                if (pretty)
                    buf.appendEOL();
                for (int i = 0;; i++)
                {
                    string key = store.map.keyByIndex(i);
                    if (pretty)
                        buf.appendTabs(level + 1);
                    buf.appendJSONString(key);
                    buf.append(':');
                    if (pretty)
                        buf.append(' ');
                    store.map.get(i).toJSON(buf, level + 1, pretty);
                    if (i >= store.map.length - 1)
                        break;
                    buf.append(',');
                    if (pretty)
                        buf.appendEOL();
                }
            }
            if (pretty)
            {
                buf.appendEOL();
                buf.appendTabs(level);
            }
            buf.append('}');
            break;
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

    private static struct JsonParser
    {
        string json;
        int pos;

        void initialize(string s)
        {
            json = s;
            pos = 0;
        }
        /// Returns current char
        @property char peek()
        {
            return pos < json.length ? json[pos] : 0;
        }
        /// Returns fragment of text in current position
        @property string currentContext()
        {
            if (pos >= json.length)
                return "end of file";
            string res = json[pos .. $];
            if (res.length > 100)
                res.length = 100;
            return res;
        }
        /// Skips current char, returns next one (or null if eof)
        @property char nextChar()
        {
            if (pos + 1 < json.length)
            {
                return json[++pos];
            }
            else
            {
                if (pos < json.length)
                    pos++;
            }
            return 0;
        }

        void error(string msg)
        {
            string context;
            // calculate error position line and column
            int line = 1;
            int col = 1;
            int lineStart = 0;
            foreach (int i; 0 .. pos)
            {
                char ch = json[i];
                if (ch == '\r')
                {
                    if (i < json.length - 1 && json[i + 1] == '\n')
                        i++;
                    line++;
                    col = 1;
                    lineStart = i + 1;
                }
                else if (ch == '\n')
                {
                    if (i < json.length - 1 && json[i + 1] == '\r')
                        i++;
                    line++;
                    col = 1;
                    lineStart = i + 1;
                }
            }
            int contextStart = pos;
            int contextEnd = pos;
            for (; contextEnd < json.length; contextEnd++)
            {
                if (json[contextEnd] == '\r' || json[contextEnd] == '\n')
                    break;
            }
            if (contextEnd - contextStart < 3)
            {
                for (int i = 0; i < 3 && contextStart > 0; contextStart--, i++)
                {
                    if (json[contextStart - 1] == '\r' || json[contextStart - 1] == '\n')
                        break;
                }
            }
            else if (contextEnd > contextStart + 10)
                contextEnd = contextStart + 10;
            if (contextEnd > contextStart && contextEnd < json.length)
                context = "near `" ~ json[contextStart .. contextEnd] ~ "` ";
            else if (pos >= json.length)
                context = "at end of file";
            throw new Exception("JSON parsing error in (" ~ to!string(line) ~ ":" ~ to!string(
                    col) ~ ") " ~ context ~ ": " ~ msg);
        }

        static bool isAlpha(char ch)
        {
            static import std.ascii;

            return std.ascii.isAlpha(ch) || ch == '_';
        }

        static bool isAlNum(char ch)
        {
            static import std.ascii;

            return std.ascii.isAlphaNum(ch) || ch == '_';
        }
        /// Skip spaces and comments, return next available character
        @property char skipSpaces()
        {
            static import std.ascii;

            for (; pos < json.length; pos++)
            {
                char ch = json[pos];
                char nextch = pos + 1 < json.length ? json[pos + 1] : 0;

                if (ch == '#' || (ch == '/' && nextch == '/') || (ch == '-' && nextch == '-'))
                {
                    // skip one line comment // or # or --
                    pos++;
                    for (; pos < json.length; pos++)
                    {
                        ch = json[pos];
                        if (ch == '\n')
                            break;
                    }
                    continue;
                }
                else if (ch == '/' && nextch == '*')
                {
                    // skip multiline /* */ comment
                    pos += 2;
                    for (; pos < json.length; pos++)
                    {
                        ch = json[pos];
                        nextch = pos + 1 < json.length ? json[pos + 1] : 0;
                        if (ch == '*' && nextch == '/')
                        {
                            pos += 2;
                            break;
                        }
                    }
                    continue;
                }
                else if (ch == '\\' && nextch == '\n')
                {
                    // continue to next line
                    pos += 2;
                    continue;
                }
                if (!std.ascii.isWhite(ch))
                    break;
            }
            return peek;
        }

        string parseUnicodeChar()
        {
            if (pos >= json.length - 3)
                error("unexpected end of file while parsing unicode character entity inside string");
            dchar ch = 0;
            foreach (i; 0 .. 4)
            {
                uint d = parseHexDigit(nextChar);
                if (d == uint.max)
                    error("error while parsing unicode character entity inside string");
                ch = (ch << 4) | d;
            }
            char[4] buf;
            size_t sz = encode(buf, ch);
            return buf[0 .. sz].dup;
        }

        @property string parseString()
        {
            char[] res;
            char ch = peek;
            char quoteChar = ch;
            if (ch != '\"' && ch != '`')
                error("cannot parse string");
            while (true)
            {
                ch = nextChar;
                if (!ch)
                    error("unexpected end of file while parsing string");
                if (ch == quoteChar)
                {
                    nextChar;
                    return cast(string)res;
                }
                if (ch == '\\' && quoteChar != '`')
                {
                    // escape sequence
                    ch = nextChar;
                    switch (ch)
                    {
                    case 'n':
                        res ~= '\n';
                        break;
                    case 'r':
                        res ~= '\r';
                        break;
                    case 'b':
                        res ~= '\b';
                        break;
                    case 'f':
                        res ~= '\f';
                        break;
                    case '\\':
                        res ~= '\\';
                        break;
                    case '/':
                        res ~= '/';
                        break;
                    case '\"':
                        res ~= '\"';
                        break;
                    case 'u':
                        res ~= parseUnicodeChar();
                        break;
                    default:
                        error("unexpected escape sequence in string");
                        break;
                    }
                }
                else
                {
                    res ~= ch;
                }
            }
        }

        @property string parseIdent()
        {
            char ch = peek;
            if (ch == '\"' || ch == '`')
            {
                return parseString;
            }
            char[] res;
            if (isAlpha(ch))
            {
                res ~= ch;
                while (true)
                {
                    ch = nextChar;
                    if (isAlNum(ch))
                    {
                        res ~= ch;
                    }
                    else
                    {
                        break;
                    }
                }
            }
            else
                error("cannot parse ident");
            return cast(string)res;
        }

        bool parseKeyword(string ident)
        {
            // returns true if parsed ok
            if (pos + ident.length > json.length)
                return false;
            foreach (i; 0 .. ident.length)
            {
                if (ident[i] != json[pos + i])
                    return false;
            }
            if (pos + ident.length < json.length)
            {
                char ch = json[pos + ident.length];
                if (isAlNum(ch))
                    return false;
            }
            pos += ident.length;
            return true;
        }

        // parse long, ulong or double
        void parseNumber(Setting res)
        {
            import std.ascii : isDigit;

            char ch = peek;
            int sign = 1;
            if (ch == '-')
            {
                sign = -1;
                ch = nextChar;
            }
            if (!isDigit(ch))
                error("cannot parse number");
            long n = 0;
            while (isDigit(ch))
            {
                n = n * 10 + (ch - '0');
                ch = nextChar;
            }
            if (ch == '.' || ch == 'e' || ch == 'E')
            {
                // floating
                ulong n2 = 0;
                ulong n2_div = 1;
                if (ch == '.')
                {
                    ch = nextChar;
                    while (isDigit(ch))
                    {
                        n2 = n2 * 10 + (ch - '0');
                        n2_div *= 10;
                        ch = nextChar;
                    }
                    if (isAlpha(ch) && ch != 'e' && ch != 'E')
                        error("error while parsing number");
                }
                int shift = 0;
                int shiftSign = 1;
                if (ch == 'e' || ch == 'E')
                {
                    ch = nextChar;
                    if (ch == '-')
                    {
                        shiftSign = -1;
                        ch = nextChar;
                    }
                    if (!isDigit(ch))
                        error("error while parsing number");
                    while (isDigit(ch))
                    {
                        shift = shift * 10 + (ch - '0');
                        ch = nextChar;
                    }
                }
                if (isAlpha(ch))
                    error("error while parsing number");
                double v = cast(double)n;
                if (n2) // part after period
                    v += cast(double)n2 / n2_div;
                if (sign < 0)
                    v = -v;
                if (shift)
                { // E part - pow10
                    double p = pow(10.0, shift);
                    if (shiftSign > 0)
                        v *= p;
                    else
                        v /= p;
                }
                res.floating = v;
            }
            else
            {
                // integer
                if (isAlpha(ch))
                    error("cannot parse number");

                res.integer = n * sign;
            }
        }
    }

    private void parseMap(ref JsonParser parser)
    {
        clear(SettingType.object);
        int startPos = parser.pos;
        //Log.v("parseMap at context ", parser.currentContext);
        char ch = parser.peek;
        parser.nextChar; // skip initial {
        if (ch != '{')
        {
            Log.e("expected { at ", parser.currentContext);
        }
        while (true)
        {
            ch = parser.skipSpaces;
            if (ch == '}')
            {
                parser.nextChar;
                break;
            }
            string key = parser.parseIdent;
            ch = parser.skipSpaces;
            if (ch != ':')
                parser.error("no : char after object field name");
            parser.nextChar;
            this[key] = (new Setting).parseJSON(parser);
            //Log.v("context before skipSpaces: ", parser.currentContext);
            ch = parser.skipSpaces;
            //Log.v("context after skipSpaces: ", parser.currentContext);
            if (ch == ',')
            {
                parser.nextChar;
                parser.skipSpaces;
            }
            else if (ch != '}')
            {
                parser.error(
                        "unexpected character when waiting for , or } while parsing object; { position is " ~ to!string(
                        startPos));
            }
        }
    }

    private void parseArray(ref JsonParser parser)
    {
        clear(SettingType.array);
        parser.nextChar; // skip initial [
        while (true)
        {
            char ch = parser.skipSpaces;
            if (ch == ']')
            {
                parser.nextChar;
                break;
            }
            auto value = new Setting;
            value.parseJSON(parser);
            this[store.array.length] = value;
            ch = parser.skipSpaces;
            if (ch == ',')
            {
                parser.nextChar;
                parser.skipSpaces;
            }
            else if (ch != ']')
            {
                parser.error("unexpected character when waiting for , or ] while parsing array");
            }
        }
    }

    private Setting parseJSON(ref JsonParser parser)
    {
        static import std.ascii;

        char ch = parser.skipSpaces;
        if (ch == '\"')
        {
            this.str = parser.parseString();
        }
        else if (ch == '[')
        {
            parseArray(parser);
        }
        else if (ch == '{')
        {
            parseMap(parser);
        }
        else if (parser.parseKeyword("null"))
        {
            // do nothing - we already have null value
        }
        else if (parser.parseKeyword("true"))
        {
            this.boolean = true;
        }
        else if (parser.parseKeyword("false"))
        {
            this.boolean = false;
        }
        else if (ch == '-' || std.ascii.isDigit(ch))
        {
            parser.parseNumber(this);
        }
        else
        {
            parser.error("cannot parse JSON value");
        }
        return this;
    }

    void parseJSON(string s)
    {
        clear(SettingType.nothing);
        JsonParser parser;
        parser.initialize(normalizeEOLs(s));
        parseJSON(parser);
    }

    /// Load JSON from file; returns true if loaded successfully
    bool load(string filename)
    {
        try
        {
            string s = readText(filename);
            parseJSON(s);
            return true;
        }
        catch (Exception e)
        {
            // Failed
            Log.e("exception while parsing json: ", e);
            return false;
        }
    }
}
