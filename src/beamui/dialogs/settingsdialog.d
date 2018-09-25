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
import beamui.platforms.common.platform;
import beamui.widgets.combobox;
import beamui.widgets.controls;
import beamui.widgets.editors;
import beamui.widgets.layouts;
import beamui.widgets.lists;
import beamui.widgets.menu;
import beamui.widgets.styles;
import beamui.widgets.tree;

/// Item on settings page
class SettingsItem
{
    /// Setting path, e.g. "editor/tabSize"
    @property string id()
    {
        return _id;
    }

    @property dstring label()
    {
        return _label;
    }

    protected
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
        cb.fillW().minWidth(60.pt);
        Setting setting = settings.settingByPath(_id, SettingType.FALSE);
        cb.checked = setting.boolean ^ _inverse;
        cb.checkChanged = (Widget source, bool checked) { setting.boolean = checked ^ _inverse; };
        return [cb];
    }
}

/// ComboBox based setting with string keys
class StringComboBoxItem : SettingsItem
{
    protected StringListValue[] _items;

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
        cb.fillW().minWidth(60.pt);
        Setting setting = settings.settingByPath(_id, SettingType.STRING);
        string itemID = setting.str;
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
        cb.itemSelected = delegate(Widget source, int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _items.length)
                setting.str = _items[itemIndex].stringID;
        };
        return [lbl, cb];
    }
}

/// ComboBox based setting with int keys
class IntComboBoxItem : SettingsItem
{
    protected StringListValue[] _items;

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
        cb.fillW().minWidth(60.pt);
        auto setting = settings.settingByPath(_id, SettingType.INTEGER);
        long itemID = setting.integer;
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
        cb.itemSelected = delegate(Widget source, int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _items.length)
                setting.integer = _items[itemIndex].intID;
        };
        return [lbl, cb];
    }
}

/// ComboBox based setting with floating point keys (actualy, fixed point digits after period is specidied by divider constructor parameter)
class FloatComboBoxItem : SettingsItem
{
    protected StringListValue[] _items;
    protected long _divider;

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
        cb.fillW().minWidth(60.pt);
        auto setting = settings.settingByPath(_id, SettingType.FLOAT);
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
        cb.itemSelected = delegate(Widget source, int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _items.length)
                setting.floating = _items[itemIndex].intID / cast(double)_divider;
        };
        return [lbl, cb];
    }
}

class NumberEditItem : SettingsItem
{
    protected int _minValue;
    protected int _maxValue;
    protected int _defaultValue;

    this(string id, dstring label, int minValue = int.max, int maxValue = int.max, int defaultValue = 0)
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
        ed.fillW().minWidth(60.pt);
        auto setting = settings.settingByPath(_id, SettingType.INTEGER);
        int n = cast(int)setting.integerDef(_defaultValue);
        if (_minValue != int.max && n < _minValue)
            n = _minValue;
        if (_maxValue != int.max && n > _maxValue)
            n = _maxValue;
        setting.integer = cast(long)n;
        ed.text = toUTF32(to!string(n));
        ed.contentChanged = delegate(EditableContent content) {
            long v = parseLong(toUTF8(content.text), long.max);
            if (v != long.max)
            {
                if ((_minValue == int.max || v >= _minValue) && (_maxValue == int.max || v <= _maxValue))
                {
                    setting.integer = v;
                    ed.textColor = 0x000000;
                }
                else
                {
                    ed.textColor = 0xFF0000;
                }
            }
        };
        return [lbl, ed];
    }
}

class StringEditItem : SettingsItem
{
    string _defaultValue;

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
        ed.fillW().minWidth(60.pt);
        auto setting = settings.settingByPath(_id, SettingType.STRING);
        string value = setting.strDef(_defaultValue);
        setting.str = value;
        ed.text = toUTF32(value);
        ed.contentChanged = delegate(EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

class FileNameEditItem : SettingsItem
{
    string _defaultValue;

    this(string id, dstring label, string defaultValue)
    {
        super(id, label);
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        import beamui.dialogs.filedlg;

        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new FileNameEditLine;
        ed.id = _id ~ "-filename-edit";
        ed.minWidth = 60.pt;
        auto setting = settings.settingByPath(_id, SettingType.STRING);
        string value = setting.strDef(_defaultValue);
        setting.str = value;
        ed.text = toUTF32(value);
        ed.contentChanged = delegate(EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

class ExecutableFileNameEditItem : SettingsItem
{
    string _defaultValue;

    this(string id, dstring label, string defaultValue)
    {
        super(id, label);
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        import beamui.dialogs.filedlg;

        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new FileNameEditLine;
        ed.id = _id ~ "-filename-edit";
        ed.addFilter(FileFilterEntry(tr("Executable files"), "*.exe", true));
        ed.fillW().minWidth(60.pt);
        auto setting = settings.settingByPath(_id, SettingType.STRING);
        string value = setting.strDef(_defaultValue);
        setting.str = value;
        ed.text = toUTF32(value);
        ed.contentChanged = delegate(EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

class PathNameEditItem : SettingsItem
{
    string _defaultValue;

    this(string id, dstring label, string defaultValue)
    {
        super(id, label);
        _defaultValue = defaultValue;
    }

    override Widget[] createWidgets(Setting settings)
    {
        import beamui.dialogs.filedlg;

        auto lbl = new Label(_label);
        lbl.id = _id ~ "-label";
        auto ed = new DirEditLine;
        ed.id = _id ~ "-path-edit";
        ed.addFilter(FileFilterEntry(tr("All files"), "*.*"));
        ed.fillW().minWidth(60.pt);
        auto setting = settings.settingByPath(_id, SettingType.STRING);
        string value = setting.strDef(_defaultValue);
        setting.str = value;
        ed.text = toUTF32(value);
        ed.contentChanged = delegate(EditableContent content) {
            string value = toUTF8(content.text);
            setting.str = value;
        };
        return [lbl, ed];
    }
}

/// Settings page - item of settings tree, can edit several settings
class SettingsPage
{
    @property string id()
    {
        return _id;
    }

    @property dstring label()
    {
        return _label;
    }

    @property int childCount()
    {
        return cast(int)_children.length;
    }

    protected
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
    NumberEditItem addNumberEdit(string id, dstring label, int minValue = int.max,
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
        auto res = new Column;
        res.id = _id;
        if (itemCount > 0)
        {
            auto caption = new Label(_label);
            caption.id = "prop-body-caption-" ~ _id;
            caption.bindSubItem(this, "title");
            res.addChild(caption);
            TableLayout tbl;
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
                        tbl = new TableLayout;
                        tbl.fillW();
                        tbl.colCount = 2;
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
    @property bool isRoot()
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
    protected
    {
        TreeWidget _tree;
        FrameLayout _frame;
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
        _tree.itemSelected = &onTreeItemSelected;
        _frame = new FrameLayout;
        _frame.bindSubItem(this, "page");
        _frame.fillW();
        createControls(_layout, _tree.items);
        auto content = new Row(2);
        content.addChild(_tree);
        content.addResizer();
        content.addChild(_frame);
        content.fillWH();
        addChild(content);
        addChild(createButtonsPanel([ACTION_APPLY, ACTION_CANCEL], 0, 0));
        if (_layout.childCount > 0)
            _tree.selectItem(_layout.child(0).id);
    }

    void onTreeItemSelected(TreeItems source, TreeItem selectedItem, bool activated)
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
