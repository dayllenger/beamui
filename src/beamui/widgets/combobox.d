/**
Combo Box controls, simple and editable.

Synopsis:
---
import beamui.widgets.combobox;

// creation of simple combo box
auto cbox = new ComboBox("combo1", ["value 1"d, "value 2"d, "value 3"d]);

// select first item
cbox.selectedItemIndex = 0;

// get selected item text
writeln(cbox.text);
---

Copyright: Vadim Lopatin 2014-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.combobox;

import std.algorithm;
import beamui.widgets.controls;
import beamui.widgets.editors;
import beamui.widgets.layouts;
import beamui.widgets.lists;
import beamui.widgets.popup;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Abstract ComboBox
class ComboBoxBase : Row
{
    /// Selected item index
    @property int selectedItemIndex() const { return _selectedItemIndex; }
    /// ditto
    @property void selectedItemIndex(int index)
    {
        if (_selectedItemIndex == index)
            return;
        if (_selectedItemIndex != -1 && _adapter.itemCount > _selectedItemIndex)
        {
            _adapter.resetItemState(_selectedItemIndex, State.selected | State.focused | State.hovered);
        }
        _selectedItemIndex = index;
        itemSelected(this, index);
    }

    override @property bool enabled() const
    {
        return super.enabled;
    }
    override @property void enabled(bool flag)
    {
        super.enabled = flag;
        _button.enabled = flag;
    }

    /// Handle item click
    Signal!(void delegate(Widget, int)) itemSelected;

    private
    {
        Widget _body;
        Button _button;
        ListAdapter _adapter;
        bool _ownAdapter;
        int _selectedItemIndex;
    }

    this(ListAdapter adapter, bool ownAdapter = true)
    {
        _adapter = adapter;
        _ownAdapter = ownAdapter;
        trackHover = true;
        initialize();
    }

    protected void initialize()
    {
        _body = createSelectedItemWidget();
        _body.clicked ~= &onClick;
        _body.state = State.parent;
        _button = createButton();
        _button.focusable = false;
        _body.focusable = false;
        focusable = true;
        add(_body).setFillWidth(true);
        add(_button);
    }

    protected Widget createSelectedItemWidget()
    {
        Widget res;
        if (_adapter && _selectedItemIndex < _adapter.itemCount)
        {
            res = _adapter.itemWidget(_selectedItemIndex);
            res.id = "COMBOBOX_BODY";
        }
        else
        {
            res = new Widget("COMBOBOX_BODY");
        }
        return res;
    }

    protected void onClick(Widget source)
    {
        if (enabled && !_popup)
        {
            showPopup();
        }
    }

    protected Button createButton()
    {
        auto res = new Button(null, "scrollbar_btn_down");
        res.id = "COMBOBOX_BUTTON";
        res.bindSubItem(this, "button");
        res.clicked ~= &onClick;
        return res;
    }

    protected ListWidget createPopup()
    {
        auto list = new ListWidget;
        list.id = "POPUP_LIST";
        list.bindSubItem(this, "list");
        list.adapter = _adapter;
        list.selectedItemIndex = _selectedItemIndex;
        list.sumItemSizes = true;
        return list;
    }

    private Popup _popup;
    private ListWidget _popupList;

    protected void popupClosed()
    {
    }

    protected void showPopup()
    {
        if (!_adapter || !_adapter.itemCount)
            return; // don't show empty popup
        _popupList = createPopup();
        _popup = window.showPopup(_popupList, WeakRef!Widget(this), PopupAlign.below | PopupAlign.fitAnchorSize);
        _popup.popupClosed ~= (Popup source, bool b) {
            _popup = null;
            _popupList = null;
        };
        _popupList.itemSelected ~= (Widget source, int index) {
            selectedItemIndex = index;
            if (_popup !is null)
            {
                _popup.close();
                _popup = null;
                popupClosed();
            }
        };
        _popupList.setFocus();
    }

    void setAdapter(ListAdapter adapter, bool ownAdapter = true)
    {
        if (_adapter)
        {
            if (_ownAdapter)
                destroy(_adapter);
            removeAllChildren();
        }
        _adapter = adapter;
        _ownAdapter = ownAdapter;
        initialize();
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        bunch(_body.maybe, _adapter.maybe, _button.maybe).onThemeChanged();
    }
}

/// ComboBox with list of strings
class ComboBox : ComboBoxBase
{
    this()
    {
        super(new StringListAdapter, true);
    }

    this(dstring[] items)
    {
        super(new StringListAdapter(items), true);
    }

    this(StringListValue[] items)
    {
        super(new StringListAdapter(items), true);
    }

    ~this()
    {
        eliminate(_adapter);
    }

    @property void items(dstring[] items)
    {
        _selectedItemIndex = -1;
        setAdapter(new StringListAdapter(items));
        if (items.length > 0)
        {
            if (selectedItemIndex == -1 || selectedItemIndex > items.length)
                selectedItemIndex = 0;
        }
        requestLayout();
    }

    @property void items(StringListValue[] items)
    {
        _selectedItemIndex = -1;
        if (auto a = cast(StringListAdapter)_adapter)
            a.items = items;
        else
            setAdapter(new StringListAdapter(items));
        if (items.length > 0)
        {
            selectedItemIndex = 0;
        }
        requestLayout();
    }

    /// Get selected item as text
    @property dstring selectedItem()
    {
        if (_selectedItemIndex < 0 || _selectedItemIndex >= _adapter.itemCount)
            return "";
        return adapter.item(_selectedItemIndex);
    }

    @property inout(StringListAdapter) adapter() inout
    {
        return cast(inout(StringListAdapter))_adapter;
    }

    override @property dstring text() const
    {
        return _body.text;
    }

    override @property void text(dstring txt)
    {
        int idx = adapter.find(txt);
        if (idx >= 0)
        {
            selectedItemIndex = idx;
        }
        else
        {
            // not found
            _selectedItemIndex = -1;
            _body.text = txt;
        }
    }

    override @property int selectedItemIndex() const
    {
        return super.selectedItemIndex;
    }
    override @property void selectedItemIndex(int index)
    {
        _body.text = adapter.item(index);
        super.selectedItemIndex = index;
    }

    override void initialize()
    {
        super.initialize();
        _body.focusable = false;
        _body.clickable = true;
        focusable = true;
        clickable = true;
        clicked ~= &onClick;
    }

    override protected Widget createSelectedItemWidget()
    {
        auto res = new Label;
        res.id = "COMBOBOX_BODY";
        res.bindSubItem(this, "body");
        res.clickable = true;
        int minItemWidth;
        foreach (i; 0 .. _adapter.itemCount)
        {
            Widget item = _adapter.itemWidget(i);
            Size sz = item.computeBoundaries().min;
            minItemWidth = max(minItemWidth, sz.w);
        }
        res.minWidth = minItemWidth;
        return res;
    }
}

/// ComboBox with list of strings
class IconTextComboBox : ComboBoxBase
{
    this(StringListValue[] items = null)
    {
        super(new IconStringListAdapter(items), true);
    }

    ~this()
    {
        eliminate(_adapter);
    }

    @property void items(StringListValue[] items)
    {
        _selectedItemIndex = -1;
        if (auto a = cast(IconStringListAdapter)_adapter)
            a.items = items;
        else
            setAdapter(new IconStringListAdapter(items));
        if (items.length > 0)
        {
            selectedItemIndex = 0;
        }
        requestLayout();
    }

    /// Get selected item as text
    @property dstring selectedItem() const
    {
        if (_selectedItemIndex < 0 || _selectedItemIndex >= _adapter.itemCount)
            return "";
        return adapter.item(_selectedItemIndex);
    }

    @property inout(IconStringListAdapter) adapter() inout
    {
        return cast(inout(IconStringListAdapter))_adapter;
    }

    override @property dstring text() const
    {
        return _body.text;
    }

    override @property void text(dstring txt)
    {
        int idx = adapter.find(txt);
        if (idx >= 0)
        {
            selectedItemIndex = idx;
        }
        else
        {
            // not found
            _selectedItemIndex = -1;
            _body.text = txt;
        }
    }

    override @property int selectedItemIndex() const
    {
        return super.selectedItemIndex;
    }
    override @property void selectedItemIndex(int index)
    {
        _body.text = adapter.item(index);
        super.selectedItemIndex = index;
    }

    override void initialize()
    {
        super.initialize();
        _body.focusable = false;
        _body.clickable = true;
        focusable = true;
        clickable = true;
        clicked ~= &onClick;
    }

    override protected Widget createSelectedItemWidget()
    {
        auto res = new Label;
        res.id = "COMBOBOX_BODY";
        res.bindSubItem(this, "body");
        res.clickable = true;
        int minItemWidth;
        foreach (i; 0 .. _adapter.itemCount)
        {
            Widget item = _adapter.itemWidget(i);
            Size sz = item.computeBoundaries().min;
            minItemWidth = max(minItemWidth, sz.w);
        }
        res.minWidth = minItemWidth;
        return res;
    }
}

/// Editable ComboBox with list of strings
class ComboEdit : ComboBox
{
    @property bool readOnly() const
    {
        return _edit.readOnly;
    }
    /// ditto
    @property void readOnly(bool ro)
    {
        _edit.readOnly = ro;
    }

    private EditLine _edit;

    this(dstring[] items = null)
    {
        super(items);
        postInit();
    }

    protected void postInit()
    {
        focusable = false;
        clickable = false;
        _edit.focusable = true;
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (event.keyCode == KeyCode.down && enabled)
        {
            if (event.action == KeyAction.keyDown)
            {
                showPopup();
            }
            return true;
        }
        if ((event.keyCode == KeyCode.space || event.keyCode == KeyCode.enter) && readOnly && enabled)
        {
            if (event.action == KeyAction.keyDown)
            {
                showPopup();
            }
            return true;
        }
        if (_edit.onKeyEvent(event))
            return true;
        return super.onKeyEvent(event);
    }

    override protected void popupClosed()
    {
        _edit.setFocus();
    }

    override protected void handleClick()
    {
        _edit.setFocus();
    }

    override protected Widget createSelectedItemWidget()
    {
        auto res = new EditLine("COMBOBOX_BODY");
        res.bindSubItem(this, "body");
        res.readOnly = false;
        _edit = res;
        postInit();
        //_edit.focusable = true;
        return res;
    }
}
