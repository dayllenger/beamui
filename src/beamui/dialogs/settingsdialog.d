/**


Copyright: Vadim Lopatin 2014-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.settingsdialog;

import std.file;
import std.path;
import beamui.core.files;
import beamui.core.i18n;
import beamui.core.parseutils;
import beamui.core.settings;
import beamui.core.stdaction;
import beamui.dialogs.dialog;
import beamui.layout.linear : Resizer;
import beamui.layout.table;
import beamui.platforms.common.platform;
import beamui.widgets.combobox;
import beamui.widgets.controls;
import beamui.widgets.editors;
import beamui.widgets.lists;
import beamui.widgets.menu;
import beamui.widgets.text;
import beamui.widgets.tree;
import beamui.widgets.widget;

/// Item on settings page
class SettingsItem
{
    /// Setting path, e.g. "editor/tabSize"
    @property string id() const { return _id; }

    @property dstring label() const { return _label; }

    private
    {
        string _id;
        dstring _label;
        SettingsPage _page;
    }

    this(string id, dstring label)
    {
        _id = id;
        _label = label;
    }

    /// Create setting widget
    Widget[] createWidgets(Setting settings)
    {
        auto res = new Label(_label);
        res.id = _id;
        return [res];
    }
}

/// Checkbox setting
class CheckboxItem : SettingsItem
{
    private bool _inverse;

    this(string id, dstring label, bool inverse = false)
    {
        super(id, label);
        _inverse = inverse;
    }

    override Widget[] createWidgets(Setting settings)
    {
        auto cb = new CheckBox(_label);
        cb.id = _id;
        cb.style.minWidth = 60;
        Setting setting = settings.settingByPath(_id);
        cb.checked = setting.boolean = setting.boolean ^ _inverse;
        cb.onToggle ~= (bool checked) { setting.boolean = checked ^ _inverse; };
        return [cb];
    }
}

/// ComboBox based setting with string keys
class StringComboBoxItem : SettingsItem
{
    private StringListValue[] _items;

    this(string id, dstring label, StringListValue[] items)
    {
        super(id, label);
        _items = items;
    }

    override Widget[] createWidgets(Setting settings)
    {
        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto cb = new ComboBox(_items);
        cb.id = _id;
        cb.style.minWidth = 60;
        Setting setting = settings.settingByPath(_id);
        string itemID = setting.str = setting.str;
        int index = -1;
        foreach (i; 0 .. cast(int)_items.length)
        {
            if (_items[i].stringID == itemID)
            {
                index = i;
                break;
            }
        }
        if (index >= 0)
            cb.selectedItemIndex = index;
        cb.onSelect ~= (int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _items.length)
                setting.str = _items[itemIndex].stringID;
        };
        return [lbl, cb];
    }
}

/// ComboBox based setting with int keys
class IntComboBoxItem : SettingsItem
{
    private StringListValue[] _items;

    this(string id, dstring label, StringListValue[] items)
    {
        super(id, label);
        _items = items;
    }

    override Widget[] createWidgets(Setting settings)
    {
        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto cb = new ComboBox(_items);
        cb.id = _id;
        cb.style.minWidth = 60;
        auto setting = settings.settingByPath(_id);
        long itemID = setting.integer = setting.integer;
        int index = -1;
        foreach (i; 0 .. cast(int)_items.length)
        {
            if (_items[i].intID == itemID)
            {
                index = i;
                break;
            }
        }
        if (index >= 0)
            cb.selectedItemIndex = index;
        cb.onSelect ~= (int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _items.length)
                setting.integer = _items[itemIndex].intID;
        };
        return [lbl, cb];
    }
}

/// ComboBox based setting with floating point keys (actualy, fixed point digits after period is specidied by divider constructor parameter)
class FloatComboBoxItem : SettingsItem
{
    private StringListValue[] _items;
    private long _divider;

    this(string id, dstring label, StringListValue[] items, long divider = 1000)
    {
        super(id, label);
        _items = items;
        _divider = divider;
    }

    override Widget[] createWidgets(Setting settings)
    {
        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto cb = new ComboBox(_items);
        cb.id = _id;
        cb.style.minWidth = 60;
        auto setting = settings.settingByPath(_id);
        setting.floating = setting.floating;
        long itemID = cast(long)(setting.floating * _divider + 0.5f);
        int index = -1;
        foreach (i; 0 .. cast(int)_items.length)
        {
            if (_items[i].intID == itemID)
            {
                index = i;
                break;
            }
        }
        if (index >= 0)
            cb.selectedItemIndex = index;
        if (index < 0)
        {
            debug Log.d("FloatComboBoxItem : item ", itemID, " is not found for value ", setting.floating);
        }
        cb.onSelect ~= (int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _items.length)
                setting.floating = _items[itemIndex].intID / cast(double)_divider;
        };
        return [lbl, cb];
    }
}

class NumberEditItem : SettingsItem
{
    private int _minValue;
    private int _maxValue;
    private int _defaultValue;

    this(string id, dstring label, int minValue = int.min, int maxValue = int.max, int defaultValue = 0)
    {
        super(id, label);
        _minValue = minValue;
        _maxValue = maxValue;
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new EditLine(_label);
        ed.id = _id ~ "-edit";
        ed.style.minWidth = 60;
        auto setting = settings.settingByPath(_id);
        int n = cast(int)setting.integerDef(_defaultValue);
        n = clamp(n, _minValue, _maxValue);
        setting.integer = cast(long)n;
        ed.text = to!dstring(n);
        ed.onContentChange ~= (EditableContent content) {
            long v = parseLong(toUTF8(content.text), long.max);
            if (v != long.max)
            {
                if (_minValue <= v && v <= _maxValue)
                {
                    setting.integer = v;
                    ed.style.textColor = 0x000000;
                }
                else
                {
                    ed.style.textColor = 0xFF0000;
                }
            }
        };
        return [lbl, ed];
    }
}

class StringEditItem : SettingsItem
{
    private string _defaultValue;

    this(string id, dstring label, string defaultValue)
    {
        super(id, label);
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new EditLine;
        ed.id = _id ~ "-edit";
        ed.style.minWidth = 60;
        auto setting = settings.settingByPath(_id);
        string value = setting.str = setting.strDef(_defaultValue);
        ed.text = toUTF32(value);
        ed.onContentChange ~= (EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

class FileNameEditItem : SettingsItem
{
    private string _defaultValue;

    this(string id, dstring label, string defaultValue)
    {
        super(id, label);
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        import beamui.dialogs.filedialog;

        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new FileNameEditLine;
        ed.id = _id ~ "-filename-edit";
        ed.style.minWidth = 60;
        auto setting = settings.settingByPath(_id);
        string value = setting.str = setting.strDef(_defaultValue);
        ed.text = toUTF32(value);
        ed.onContentChange ~= (EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

class ExecutableFileNameEditItem : SettingsItem
{
    private string _defaultValue;

    this(string id, dstring label, string defaultValue)
    {
        super(id, label);
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        import beamui.dialogs.filedialog;

        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new FileNameEditLine;
        ed.id = _id ~ "-filename-edit";
        ed.addFilter(FileFilterEntry(tr("Executable files"), "*.exe", true));
        ed.style.minWidth = 60;
        auto setting = settings.settingByPath(_id);
        string value = setting.str = setting.strDef(_defaultValue);
        ed.text = toUTF32(value);
        ed.onContentChange ~= (EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

class PathNameEditItem : SettingsItem
{
    private string _defaultValue;

    this(string id, dstring label, string defaultValue)
    {
        super(id, label);
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        import beamui.dialogs.filedialog;

        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new DirEditLine;
        ed.id = _id ~ "-path-edit";
        ed.addFilter(FileFilterEntry(tr("All files"), "*.*"));
        ed.style.minWidth = 60;
        auto setting = settings.settingByPath(_id);
        string value = setting.str = setting.strDef(_defaultValue);
        ed.text = toUTF32(value);
        ed.onContentChange ~= (EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

/// Settings page - item of settings tree, can edit several settings
class SettingsPage
{
    @property string id() const { return _id; }

    @property dstring label() const { return _label; }

    @property int childCount() const
    {
        return cast(int)_children.length;
    }

    private
    {
        SettingsPage _parent;
        SettingsPage[] _children;
        SettingsItem[] _items;
        string _id;
        dstring _label;
    }

    this(string id, dstring label)
    {
        _id = id;
        _label = label;
    }

    /// Returns child page by index
    SettingsPage child(int index)
    {
        return _children[index];
    }

    SettingsPage addChild(SettingsPage item)
    {
        _children ~= item;
        item._parent = this;
        return item;
    }

    SettingsPage addChild(string id, dstring label)
    {
        return addChild(new SettingsPage(id, label));
    }

    @property int itemCount()
    {
        return cast(int)_items.length;
    }

    /// Returns page item by index
    SettingsItem item(int index)
    {
        return _items[index];
    }

    SettingsItem addItem(SettingsItem item)
    {
        _items ~= item;
        item._page = this;
        return item;
    }

    /// Add checkbox (boolean value) for setting
    CheckboxItem addCheckbox(string id, dstring label, bool inverse = false)
    {
        auto res = new CheckboxItem(id, label, inverse);
        addItem(res);
        return res;
    }

    /// Add EditLine to edit number
    NumberEditItem addNumberEdit(string id, dstring label, int minValue = int.min,
            int maxValue = int.max, int defaultValue = 0)
    {
        auto res = new NumberEditItem(id, label, minValue, maxValue, defaultValue);
        addItem(res);
        return res;
    }

    /// Add EditLine to edit string
    StringEditItem addStringEdit(string id, dstring label, string defaultValue = "")
    {
        auto res = new StringEditItem(id, label, defaultValue);
        addItem(res);
        return res;
    }

    /// Add EditLine to edit filename
    FileNameEditItem addFileNameEdit(string id, dstring label, string defaultValue = "")
    {
        auto res = new FileNameEditItem(id, label, defaultValue);
        addItem(res);
        return res;
    }

    /// Add EditLine to edit filename
    PathNameEditItem addDirNameEdit(string id, dstring label, string defaultValue = "")
    {
        auto res = new PathNameEditItem(id, label, defaultValue);
        addItem(res);
        return res;
    }

    /// Add EditLine to edit executable file name
    ExecutableFileNameEditItem addExecutableFileNameEdit(string id, dstring label, string defaultValue = "")
    {
        auto res = new ExecutableFileNameEditItem(id, label, defaultValue);
        addItem(res);
        return res;
    }

    StringComboBoxItem addStringComboBox(string id, dstring label, StringListValue[] items)
    {
        auto res = new StringComboBoxItem(id, label, items);
        addItem(res);
        return res;
    }

    IntComboBoxItem addIntComboBox(string id, dstring label, StringListValue[] items)
    {
        auto res = new IntComboBoxItem(id, label, items);
        addItem(res);
        return res;
    }

    FloatComboBoxItem addFloatComboBox(string id, dstring label, StringListValue[] items, long divider = 1000)
    {
        auto res = new FloatComboBoxItem(id, label, items, divider);
        addItem(res);
        return res;
    }

    /// Create page widget (default implementation creates empty page)
    Widget createWidget(Setting settings)
    {
        auto res = new Panel(_id);
        res.style.display = "column";
        if (itemCount > 0)
        {
            auto caption = new Label(_label);
            caption.id = "prop-body-caption-" ~ _id;
            caption.bindSubItem(this, "title");
            res.addChild(caption);
            Panel tbl;
            foreach (i; 0 .. itemCount)
            {
                SettingsItem v = item(i);
                Widget[] w = v.createWidgets(settings);
                if (w.length == 1)
                {
                    tbl = null;
                    res.addChild(w[0]);
                }
                else if (w.length == 2)
                {
                    if (!tbl)
                    {
                        tbl = new Panel;
                        tbl.style.display = "table";
                        if (TableLayout t = tbl.getLayout!TableLayout)
                            t.colCount = 2;
                        res.addChild(tbl);
                    }
                    tbl.addChild(w[0]);
                    tbl.addChild(w[1]);
                }

            }
        }
        return res;
    }

    /// Returns true if this page is root page
    @property bool isRoot() const
    {
        return !_parent;
    }

    TreeItem createTreeItem()
    {
        return new TreeItem(_id, _label);
    }
}

class SettingsDialog : Dialog
{
    private
    {
        TreeWidget _tree;
        Panel _frame;
        Setting _settings;
        SettingsPage _layout;
    }

    this(dstring caption, Window parent, Setting settings, SettingsPage layout, bool popup =
        (platform.uiDialogDisplayMode & DialogDisplayMode.settingsDialogInPopup) ==
            DialogDisplayMode.settingsDialogInPopup)
    {
        super(caption, parent, DialogFlag.modal | DialogFlag.resizable | (popup ? DialogFlag.popup : 0));
        _settings = settings;
        _layout = layout;
    }

    override void initialize()
    {
        import beamui.widgets.scroll;

        _tree = new TreeWidget(ScrollBarMode.automatic, ScrollBarMode.automatic);
        _tree.bindSubItem(this, "tree");
        _tree.onSelect ~= &handleTreeItemSelection;
        _frame = new Panel;
        _frame.bindSubItem(this, "page");
        createControls(_layout, _tree.items);
        auto content = new Panel;
        content.setAttribute("content");
        content.add(_tree, new Resizer, _frame);
        add(content, createButtonsPanel([ACTION_APPLY, ACTION_CANCEL], 0, 0));
        if (_layout.childCount > 0)
            _tree.selectItem(_layout.child(0).id);
    }

    void handleTreeItemSelection(TreeItem selectedItem, bool activated)
    {
        if (!selectedItem)
            return;
        _frame.showChild(selectedItem.id);
    }

    void createControls(SettingsPage page, TreeItem base)
    {
        TreeItem item = base;
        if (!page.isRoot)
        {
            item = page.createTreeItem();
            base.addChild(item);
            Widget widget = page.createWidget(_settings);
            _frame.addChild(widget);
        }
        if (page.childCount > 0)
        {
            foreach (i; 0 .. page.childCount)
            {
                createControls(page.child(i), item);
            }
        }
    }
}
