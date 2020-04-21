/**
Combo Box controls, simple and editable.

Synopsis:
---
dstring[] list = ["value 1", "value 2", "value 3"];

// creation of simple combo box
auto cbox = new ComboBox(list);

// select the first item
cbox.selectedItemIndex = 0;

// get selected item text
writeln(cbox.text);
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.combobox;
/+
import beamui.widgets.controls;
import beamui.widgets.editors;
import beamui.widgets.lists;
import beamui.widgets.popup;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Abstract ComboBox
abstract class ComboBoxBase : Panel
{
    @property
    {
        /// Selected item index
        int selectedItemIndex() const { return _selectedItemIndex; }
        /// ditto
        void selectedItemIndex(int index)
        {
            if (_selectedItemIndex == index)
                return;
            if (_selectedItemIndex != -1 && _adapter.itemCount > _selectedItemIndex)
            {
                _adapter.resetItemState(_selectedItemIndex, State.selected | State.focused | State.hovered);
            }
            _selectedItemIndex = index;
            if (_popupList)
                _popupList.selectItem(index);
            onSelect(index);
        }
    }

    /// Triggers on item selection and passes integer index of the item
    Signal!(void delegate(int)) onSelect;

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
        isolateStyle();
        allowsHover = true;
        initialize();
    }

    ~this()
    {
        if (_ownAdapter)
            eliminate(_adapter);
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

    protected void initialize()
    {
        _body = createSelectedItemWidget();
        _body.setAttribute("body");
        _body.allowsFocus = false;
        _body.onClick ~= &handleClick;

        _button = createButton();
        _button.setAttribute("button");
        _button.allowsFocus = false;
        _button.onClick ~= &handleClick;

        add(_body, _button);
        allowsFocus = true;
    }

    protected Widget createSelectedItemWidget();

    protected Button createButton()
    {
        return new Button(null, "scrollbar_btn_down");
    }

    protected ListWidget createPopup()
    {
        auto list = new ListWidget;
        list.adapter = _adapter;
        list.selectedItemIndex = _selectedItemIndex;
        list.sumItemSizes = true;
        return list;
    }

    private bool _popupShown;
    private ListWidget _popupList;

    protected void showPopup()
    {
        if (!_adapter || !_adapter.itemCount)
            return; // don't show empty popup

        _popupShown = true;
        _popupList = createPopup();
        Popup popup = window.showPopup(_popupList);
        popup.setAttribute("combobox");
        popup.anchor = WeakRef!Widget(this);
        popup.alignment = PopupAlign.below | PopupAlign.fitAnchorSize;
        popup.onPopupClose ~= (bool b) {
            _popupShown = false;
            _popupList = null;
            removeAttribute("opened");
            handlePopupClose();
        };
        setAttribute("opened");
        _popupList.onItemClick ~= (int index) {
            selectedItemIndex = index;
            if (popup)
                popup.close();
        };
        _popupList.onKeyEvent ~= (KeyEvent e) {
            if (e.action == KeyAction.keyDown && e.key == Key.escape && e.noModifiers)
            {
                if (popup)
                {
                    popup.close();
                    return true;
                }
            }
            return false;
        };
        _popupList.setFocus();
    }

    protected void handlePopupClose()
    {
        setFocus();
    }

    override protected void handleClick()
    {
        if (!_popupShown)
        {
            showPopup();
        }
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        const delta = event.deltaY > 0 ? 1 : -1;
        const oldIndex = selectedItemIndex;
        const newIndex = clamp(oldIndex + delta, 0, _adapter.itemCount - 1);
        selectedItemIndex = newIndex;
        return oldIndex != newIndex;
    }
}

/// ComboBox with list of strings
class ComboBox : ComboBoxBase
{
    @property
    {
        void items(dstring[] items)
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

        void items(StringListValue[] items)
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
        dstring selectedItem()
        {
            if (_selectedItemIndex < 0 || _selectedItemIndex >= _adapter.itemCount)
                return null;
            return adapter.item(_selectedItemIndex);
        }

        inout(StringListAdapter) adapter() inout
        {
            return cast(inout(StringListAdapter))_adapter;
        }

        override dstring text() const
        {
            return _body.text;
        }
        override void text(dstring txt)
        {
            const idx = adapter.find(txt);
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

        override int selectedItemIndex() const
        {
            return super.selectedItemIndex;
        }
        override void selectedItemIndex(int index)
        {
            _body.text = adapter.item(index);
            super.selectedItemIndex = index;
        }
    }

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

    override void initialize()
    {
        super.initialize();
        _body.allowsFocus = false;
        _body.allowsClick = true;
        allowsFocus = true;
        allowsClick = true;
    }

    override protected Widget createSelectedItemWidget()
    {
        auto label = new Label;
        label.allowsClick = true;
        return label;
    }
}

/// ComboBox with list of strings
class IconTextComboBox : ComboBoxBase
{
    @property
    {
        void items(StringListValue[] items)
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
        dstring selectedItem() const
        {
            if (_selectedItemIndex < 0 || _selectedItemIndex >= _adapter.itemCount)
                return null;
            return adapter.item(_selectedItemIndex);
        }

        inout(IconStringListAdapter) adapter() inout
        {
            return cast(inout(IconStringListAdapter))_adapter;
        }

        override dstring text() const
        {
            return _body.text;
        }
        override void text(dstring txt)
        {
            const idx = adapter.find(txt);
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

        override int selectedItemIndex() const
        {
            return super.selectedItemIndex;
        }
        override void selectedItemIndex(int index)
        {
            _body.text = adapter.item(index);
            super.selectedItemIndex = index;
        }
    }

    this(StringListValue[] items = null)
    {
        super(new IconStringListAdapter(items), true);
    }

    override void initialize()
    {
        super.initialize();
        _body.allowsFocus = false;
        _body.allowsClick = true;
        allowsFocus = true;
        allowsClick = true;
    }

    override protected Widget createSelectedItemWidget()
    {
        auto label = new Label;
        label.allowsClick = true;
        return label;
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
    }

    override void initialize()
    {
        super.initialize();
        _edit.allowsFocus = true;
        allowsClick = false;
        allowsFocus = false;
    }

    override protected Widget createSelectedItemWidget()
    {
        _edit = new EditLine;
        return _edit;
    }

    override bool handleKeyEvent(KeyEvent event)
    {
        if (event.key == Key.down)
        {
            if (event.action == KeyAction.keyDown)
            {
                showPopup();
            }
            return true;
        }
        if ((event.key == Key.space || event.key == Key.enter) && readOnly)
        {
            if (event.action == KeyAction.keyDown)
            {
                showPopup();
            }
            return true;
        }
        if (_edit.handleKeyEvent(event))
            return true;
        return super.handleKeyEvent(event);
    }
}
+/
