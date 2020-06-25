/**


Copyright: Vadim Lopatin 2014-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.settingsdialog;
/+
import std.file;
import std.path;
import beamui.core.files;
import beamui.core.i18n;
import beamui.core.parseutils;
import beamui.core.stdaction;
import beamui.dialogs.dialog;
import beamui.layout.linear : Resizer;
import beamui.platforms.common.platform;
import beamui.widgets.combobox;
import beamui.widgets.lists;
import beamui.widgets.menu;
import beamui.widgets.tree;
+/
import beamui.core.settings;
import beamui.dialogs.filedialog;
import beamui.widgets.controls;
import beamui.widgets.editors : TextField;
import beamui.widgets.text : Label;
import beamui.widgets.widget;

/// Item on settings page
class SettingsItem : WidgetWrapperOf!Widget
{
    /// Setting path, e.g. "editor/tabSize"
    string path;
    dstring title;

    protected Setting settings;

    override protected Element createElement()
    {
        return new ElemPanel;
    }
}

/// Checkbox setting (boolean value)
class CheckboxItem : SettingsItem
{
    bool defaultValue;

    override protected void build()
    {
        assert(settings);
        Setting item = settings.settingByPath(path);

        CheckBox cb = render!CheckBox;
        cb.checked = item.booleanDef(defaultValue);
        cb.onToggle = (v) {
            item.boolean = v;
            setState(v, !v);
        };
        wrap(cb);
    }
}
/+
/// ComboBox based setting with string keys
class StringComboBoxItem : SettingsItem
{
    private StringListValue[] _items;

    override Widget[] createWidgets(Setting settings)
    {
        auto cb = new ComboBox(_items);
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
        return cb;
    }
}

/// ComboBox based setting with int keys
class IntComboBoxItem : SettingsItem
{
    private StringListValue[] _items;

    override Widget[] createWidgets(Setting settings)
    {
        auto cb = new ComboBox(_items);
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
    }
}

/// ComboBox based setting with floating point keys (actualy, fixed point digits after period is specidied by divider constructor parameter)
class FloatComboBoxItem : SettingsItem
{
    private StringListValue[] _items;
    private long _divider = 1000;

    override Widget[] createWidgets(Setting settings)
    {
        auto cb = new ComboBox(_items);
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
    }
}
+/
class IntegerEditItem : SettingsItem
{
    long defaultValue;
    long minValue = long.min;
    long maxValue = long.max;

    static protected class State : WidgetState
    {
        bool valid = true;
    }

    override protected State createState()
    {
        return new State;
    }

    override protected void build()
    {
        assert(settings);
        Setting item = settings.settingByPath(path);
        State st = use!State;

        TextField ed = render!TextField;
        if (st.valid)
            ed.text = to!dstring(item.integerDef(defaultValue));
        else
            ed.attributes["error"];

        ed.onChange = (str) {
            try
            {
                item.integer = clamp(to!long(str), minValue, maxValue);
                setState(st.valid, true);
                setState(str, null);
            }
            catch (Exception e)
            {
                setState(st.valid, false);
            }
        };
        wrap(ed);
    }
}

class StringEditItem : SettingsItem
{
    string defaultValue;

    override protected void build()
    {
        assert(settings);
        Setting item = settings.settingByPath(path);

        TextField ed = render!TextField;
        ed.text = toUTF32(item.strDef(defaultValue));
        ed.onChange = (str) {
            item.str = toUTF8(str);
            setState(str, null);
        };
        wrap(ed);
    }
}
/+
/// Field to edit a file name
class FileNameEditItem : SettingsItem
{
    private string _defaultValue;

    override Widget[] createWidgets(Setting settings)
    {
        auto ed = new FileNameField;
        auto setting = settings.settingByPath(_id);
        string value = setting.str = setting.strDef(_defaultValue);
        ed.text = toUTF32(value);
        ed.onChange ~= (dstring str) { setting.str = toUTF8(str); };
    }
}

/// Field to edit an executable file name
class ExecutableFileNameEditItem : SettingsItem
{
    private string _defaultValue;

    override Widget[] createWidgets(Setting settings)
    {
        auto ed = new FileNameField;
        ed.addFilter(FileFilterEntry(tr("Executable files"), "*.exe", true));
        auto setting = settings.settingByPath(_id);
        string value = setting.str = setting.strDef(_defaultValue);
        ed.text = toUTF32(value);
        ed.onChange ~= (dstring str) { setting.str = toUTF8(str); };
    }
}

class PathNameEditItem : SettingsItem
{
    private string _defaultValue;

    override Widget[] createWidgets(Setting settings)
    {
        auto ed = new DirField;
        ed.addFilter(FileFilterEntry(tr("All files"), "*.*"));
        auto setting = settings.settingByPath(_id);
        string value = setting.str = setting.strDef(_defaultValue);
        ed.text = toUTF32(value);
        ed.onChange ~= (dstring str) { setting.str = toUTF8(str); };
    }
}

/// Settings page - item of settings tree, can edit several settings
class SettingsPage
{
    private
    {
        SettingsPage _parent;
        SettingsPage[] _children;
        SettingsItem[] _items;
        string _id;
        dstring _label;
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
+/
class SettingsPage : Panel
{
    dstring title;
    Setting settings;
    SettingsItem[] items;

    override protected void build()
    {
        wrap(
            render((Label t) {
                t.text = title;
            }),
            render((SettingsList list) {
                list.settings = settings;
                list.items = items;
            }),
        );
    }
}

class SettingsList : Panel
{
    Setting settings;
    SettingsItem[] items;

    override protected void build()
    {
        wrap(cast(uint)items.length * 2, delegate Widget(i) {
            if (i % 2 == 0)
            {
                Label label = render!Label;
                label.text = items[i / 2].title;
                return label;
            }
            else
            {
                auto item = items[i / 2];
                item.settings = settings;
                return item;
            }
        });
    }
}
/+
class SettingsDialog : Dialog
{
    private
    {
        TreeWidget _tree;
        Panel _frame;
        Setting _settings;
        SettingsPage _pageTree;
    }

    this(dstring caption, Window parent, Setting settings, SettingsPage pageTree, bool popup =
        (platform.uiDialogDisplayMode & DialogDisplayMode.settingsDialogInPopup) ==
            DialogDisplayMode.settingsDialogInPopup)
    {
        super(caption, parent, DialogFlag.modal | DialogFlag.resizable | (popup ? DialogFlag.popup : 0));
        _settings = settings;
        _pageTree = pageTree;
    }

    override void initialize()
    {
        auto content = new Panel(null, "content");
            auto treeFrame = new Panel(null, "tree");
                _tree = new TreeWidget;
            _frame = new Panel(null, "page");

        add(content, createButtonsPanel([ACTION_APPLY, ACTION_CANCEL], 0, 0));
        content.add(treeFrame, new Resizer, _frame);
        treeFrame.addChild(_tree);
        createControls(_pageTree, _tree.items);

        _tree.onSelect ~= &handleTreeItemSelection;
        if (_pageTree.childCount > 0)
            _tree.selectItem(_pageTree.child(0).id);
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
+/
