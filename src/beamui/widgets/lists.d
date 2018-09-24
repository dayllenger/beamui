/**
This module contains list widgets implementation.

Similar to lists implementation in Android UI API.

Synopsis:
---
import beamui.widgets.lists;
---

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.lists;

import beamui.core.signals;
import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.scrollbar;
import beamui.widgets.widget;

/// Slot type for `adapterChanged`
alias onAdapterChangeHandler = void delegate(ListAdapter source);

/// List widget adapter provides items for list widgets
interface ListAdapter
{
    /// Returns number of widgets in list
    @property int itemCount() const;
    /// Returns list item widget by item index
    Widget itemWidget(int index);
    /// Returns list item's state flags
    State itemState(int index) const;
    /// Set one or more list item's state flags, returns updated state
    State setItemState(int index, State flags);
    /// Reset one or more list item's state flags, returns updated state
    State resetItemState(int index, State flags);
    /// Returns integer item id by index (if supported)
    int itemID(int index) const;
    /// Returns string item id by index (if supported)
    string itemStringID(int index) const;

    /// Remove all items
    void clear();

    /// Connect adapter change handler
    ListAdapter connect(onAdapterChangeHandler handler);
    /// Disconnect adapter change handler
    ListAdapter disconnect(onAdapterChangeHandler handler);

    /// Called when theme is changed
    void onThemeChanged();

    /// Returns true to receive mouse events
    @property bool wantMouseEvents();
    /// Returns true to receive keyboard events
    @property bool wantKeyEvents();
}

/// List adapter for simple list of widget instances
class ListAdapterBase : ListAdapter
{
    /// Handle items change
    protected Signal!onAdapterChangeHandler adapterChanged;

    override ListAdapter connect(onAdapterChangeHandler handler)
    {
        adapterChanged.connect(handler);
        return this;
    }

    override ListAdapter disconnect(onAdapterChangeHandler handler)
    {
        adapterChanged.disconnect(handler);
        return this;
    }

    override int itemID(int index) const
    {
        return 0;
    }

    override string itemStringID(int index) const
    {
        return null;
    }

    override @property int itemCount() const
    {
        // override it
        return 0;
    }

    Widget itemWidget(int index)
    {
        // override it
        return null;
    }

    override State itemState(int index) const
    {
        // override it
        return State.normal;
    }

    override State setItemState(int index, State flags)
    {
        return State.unspecified;
    }

    override State resetItemState(int index, State flags)
    {
        return State.unspecified;
    }

    override void clear()
    {
    }

    /// Notify listeners about list items changes
    void updateViews()
    {
        adapterChanged(this);
    }

    /// Called when theme is changed
    void onThemeChanged()
    {
    }

    override @property bool wantMouseEvents()
    {
        return false;
    }

    override @property bool wantKeyEvents()
    {
        return false;
    }
}

/// List adapter for simple list of widget instances
class WidgetListAdapter : ListAdapterBase
{
    private WidgetList _widgets;
    /// List of widgets to display
    @property ref const(WidgetList) widgets()
    {
        return _widgets;
    }
    /// Returns number of widgets in list
    override @property int itemCount() const
    {
        return _widgets.count;
    }

    override Widget itemWidget(int index)
    {
        return _widgets.get(index);
    }

    override State itemState(int index) const
    {
        return _widgets.get(index).state;
    }

    override State setItemState(int index, State flags)
    {
        return _widgets.get(index).setState(flags).state;
    }

    override State resetItemState(int index, State flags)
    {
        return _widgets.get(index).resetState(flags).state;
    }
    /// Add or insert item
    WidgetListAdapter add(Widget item, int index = -1)
    {
        _widgets.insert(item, index);
        updateViews();
        return this;
    }
    /// Remove item and destroy it
    WidgetListAdapter remove(int index)
    {
        auto item = _widgets.remove(index);
        eliminate(item);
        updateViews();
        return this;
    }

    override void clear()
    {
        _widgets.clear();
        updateViews();
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        foreach (w; _widgets)
            w.onThemeChanged();
    }

    ~this()
    {
        debug (lists)
            Log.d("Destroying WidgetListAdapter");
    }

    override @property bool wantMouseEvents()
    {
        return true;
    }
}

/// List adapter providing strings only
class StringListAdapterBase : ListAdapterBase
{
    protected
    {
        import std.container.array;

        struct Item
        {
            dstring str;
            int intID;
            string stringID;
            string iconID;
            State state = State.enabled;
        }
        Array!Item _items;
        int _lastItemIndex = -1; // TODO: reset when clear or replace?
    }

    /// Create empty string list adapter
    this()
    {
    }

    /// Init with array of unicode strings
    this(dstring[] values)
    {
        _items.length = values.length;
        foreach (i; 0 .. _items.length)
            _items[i].str = values[i];
    }

    /// Init with array of StringListValue
    this(StringListValue[] values)
    {
        _items.length = values.length;
        foreach (i; 0 .. _items.length)
            _items[i] = Item(values[i].label, values[i].intID, values[i].stringID, values[i].iconID);
    }

    override void clear()
    {
        _items.clear();
        updateViews();
    }

    /// Add new item
    StringListAdapterBase add(dstring str, int index = -1)
    {
        Item item;
        item.str = str;
        if (index < 0 || index >= _items.length)
        {
            _items ~= item;
        }
        else
        {
            _items.insertBefore(_items[index .. $], item);
        }
        updateViews();
        return this;
    }

    /// Remove item by index
    StringListAdapterBase remove(int index)
    {
        if (index < 0 || index >= _items.length)
            return this;
        _items.linearRemove(_items[index .. index + 1]);
        updateViews();
        return this;
    }

    /// Find item, returns its index or -1 if not found
    int find(dstring str) const
    {
        import std.algorithm : countUntil;

        return cast(int)_items[].countUntil!(a => a.str == str);
    }

    /// Access to items by index
    @property dstring item(int index) const
    {
        return index >= 0 && index < _items.length ? _items[index].str : null;
    }

    /// Replace items collection
    @property StringListAdapterBase items(dstring[] values)
    {
        _items.length = values.length;
        foreach (i; 0 .. _items.length)
            _items[i] = Item(values[i]);
        updateViews();
        return this;
    }

    /// Replace items collection
    @property StringListAdapterBase items(StringListValue[] values)
    {
        _items.length = values.length;
        foreach (i; 0 .. _items.length)
            _items[i] = Item(values[i].label, values[i].intID, values[i].stringID, values[i].iconID);
        updateViews();
        return this;
    }

    /// Returns number of widgets in list
    override @property int itemCount() const
    {
        return cast(int)_items.length;
    }

    /// Returns integer item id by index (if supported)
    override int itemID(int index) const
    {
        return index >= 0 && index < _items.length ? _items[index].intID : 0;
    }

    /// Returns string item id by index (if supported)
    override string itemStringID(int index) const
    {
        return index >= 0 && index < _items.length ? _items[index].stringID : null;
    }

    override State itemState(int index) const
    {
        if (index < 0 || index >= _items.length)
            return State.unspecified;
        return _items[index].state;
    }

    override State setItemState(int index, State flags)
    {
        _items[index].state |= flags;
        return _items[index].state;
    }

    override State resetItemState(int index, State flags)
    {
        _items[index].state &= ~flags;
        return _items[index].state;
    }
}

/// List adapter providing strings only
class StringListAdapter : StringListAdapterBase
{
    protected Label _widget;

    /// Create empty string list adapter
    this()
    {
        super();
    }

    /// Init with array of unicode strings
    this(dstring[] items)
    {
        super(items);
    }

    /// Init with array of StringListValue
    this(StringListValue[] items)
    {
        super(items);
    }

    ~this()
    {
        eliminate(_widget);
    }

    override Widget itemWidget(int index)
    {
        if (_widget is null)
        {
            _widget = new Label;
            _widget.bindSubItem(this, "item");
        }
        else
        {
            if (index == _lastItemIndex)
                return _widget;
        }
        // update widget
        _widget.text = _items[index].str;
        _widget.state = _items[index].state;
        _widget.cancelLayout();
        _lastItemIndex = index;
        return _widget;
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        if (_widget)
            _widget.onThemeChanged();
    }

    override State setItemState(int index, State flags)
    {
        State res = super.setItemState(index, flags);
        if (_widget !is null && _lastItemIndex == index)
            _widget.state = res;
        return res;
    }

    override State resetItemState(int index, State flags)
    {
        State res = super.resetItemState(index, flags);
        if (_widget !is null && _lastItemIndex == index)
            _widget.state = res;
        return res;
    }
}

/// List adapter providing strings with icons
class IconStringListAdapter : StringListAdapterBase
{
    protected
    {
        Row _widget;
        Label _textWidget;
        ImageWidget _iconWidget;
    }

    /// Create empty string list adapter
    this()
    {
        super();
    }

    /// Init with array of StringListValue
    this(StringListValue[] items)
    {
        super(items);
    }

    ~this()
    {
        eliminate(_widget);
    }

    override Widget itemWidget(int index)
    {
        if (_widget is null)
        {
            _widget = new Row;
            _widget.bindSubItem(this, "item");
            _textWidget = new Label;
            _textWidget.id = "label";
            _iconWidget = new ImageWidget;
            _iconWidget.id = "icon";
            _widget.addChild(_iconWidget);
            _widget.addChild(_textWidget);
        }
        else
        {
            if (index == _lastItemIndex)
                return _widget;
        }
        // update widget
        _widget.text = _items[index].str;
        _widget.state = _items[index].state;
        if (_items[index].iconID)
        {
            _iconWidget.visibility = Visibility.visible;
            _iconWidget.imageID = _items[index].iconID;
        }
        else
        {
            _iconWidget.visibility = Visibility.gone;
        }
        _lastItemIndex = index;
        return _widget;
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        if (_widget)
            _widget.onThemeChanged();
    }

    override State setItemState(int index, State flags)
    {
        State res = super.setItemState(index, flags);
        if (_widget !is null && _lastItemIndex == index)
        {
            _widget.state = res;
            _textWidget.state = res;
        }
        return res;
    }

    override State resetItemState(int index, State flags)
    {
        State res = super.resetItemState(index, flags);
        if (_widget !is null && _lastItemIndex == index)
        {
            _widget.state = res;
            _textWidget.state = res;
        }
        return res;
    }
}

/// List widget
class ListWidget : WidgetGroup
{
    @property
    {
        /// List orientation (vertical, horizontal)
        Orientation orientation()
        {
            return _orientation;
        }
        /// ditto
        ListWidget orientation(Orientation value)
        {
            _orientation = value;
            _scrollbar.orientation = value;
            requestLayout();
            return this;
        }

        /// When true, mouse hover selects underlying item
        bool selectOnHover()
        {
            return _selectOnHover;
        }
        /// ditto
        ListWidget selectOnHover(bool select)
        {
            _selectOnHover = select;
            return this;
        }

        /// List adapter
        ListAdapter adapter()
        {
            return _adapter;
        }
        /// ditto
        ListWidget adapter(ListAdapter adapter)
        {
            if (_adapter is adapter)
                return this; // no changes
            _adapter.maybe.disconnect(&onAdapterChange);
            if (_adapter !is null && _ownAdapter)
                destroy(_adapter);
            _adapter = adapter;
            _adapter.maybe.connect(&onAdapterChange);
            _ownAdapter = false;
            onAdapterChange(_adapter);
            return this;
        }
        /// Set adapter, which will be owned by list (destroy will be called for adapter on widget destroy)
        ListWidget ownAdapter(ListAdapter adapter)
        {
            if (_adapter is adapter)
                return this; // no changes
            _adapter.maybe.disconnect(&onAdapterChange);
            if (_adapter !is null && _ownAdapter)
                destroy(_adapter);
            _adapter = adapter;
            _adapter.maybe.connect(&onAdapterChange);
            _ownAdapter = true;
            onAdapterChange(_adapter);
            return this;
        }

        /// Returns number of widgets in list
        int itemCount()
        {
            return _adapter ? _adapter.itemCount : 0;
        }

        /// Selected item index
        int selectedItemIndex()
        {
            return _selectedItemIndex;
        }
        /// ditto
        void selectedItemIndex(int index)
        {
            selectItem(index);
        }
    }

    /// Handle selection change
    Signal!(void delegate(Widget, int)) itemSelected;
    /// Handle item click / activation (e.g. Space or Enter key pressed and mouse double clicked)
    Signal!(void delegate(Widget, int)) itemClicked;

    /// Policy for `computeBoundaries`: when true, it considers items' overall size
    bool sumItemSizes;

    protected
    {
        Box[] _itemBoxes;
        bool _needScrollbar;
        ScrollBar _scrollbar;

        /// First visible item index
        int _firstVisibleItem;
        /// Scroll position - offset of scroll area
        int _scrollPosition;
        /// Maximum scroll position
        int _maxScrollPosition;
        /// Client area (without scrollbar and padding)
        Box _clientBox;
        /// Total height of all items for vertical orientation, or width for horizontal
        int _totalSize;
        /// Item with `hovered` state, -1 if no such item
        int _hoverItemIndex = -1;
        /// Item with `selected` state, -1 if no such item
        int _selectedItemIndex = -1;

        Orientation _orientation = Orientation.vertical;
        /// When true, mouse hover selects underlying item
        bool _selectOnHover;
        /// If true, generate itemClicked on mouse down instead mouse up event
        bool _clickOnButtonDown;

        ListAdapter _adapter;
        /// When true, need to destroy adapter on list destroy
        bool _ownAdapter;
    }

    /// Create with orientation parameter
    this(Orientation orientation = Orientation.vertical)
    {
        _orientation = orientation;
        focusable = true;
        _scrollbar = new ScrollBar(orientation);
        _scrollbar.visibility = Visibility.gone;
        _scrollbar.scrolled = &onScrollEvent;
        addChild(_scrollbar);
    }

    ~this()
    {
        _adapter.maybe.disconnect(&onAdapterChange);
        debug (lists)
            Log.d("Destroying List ", _id);
        if (_adapter !is null && _ownAdapter)
            destroy(_adapter);
        _adapter = null;
    }

    /// Returns box for item (not scrolled, first item starts at 0,0)
    Box itemBoxNoScroll(int index)
    {
        if (index < 0 || index >= _itemBoxes.length)
            return Box.init;
        return _itemBoxes[index];
    }

    /// Returns box for item (scrolled)
    Box itemBox(int index)
    {
        if (index < 0 || index >= _itemBoxes.length)
            return Box.init;
        Box res = itemBoxNoScroll(index);
        if (_orientation == Orientation.horizontal)
            res.x -= _scrollPosition;
        else
            res.y -= _scrollPosition;
        return res;
    }

    /// Returns item index by 0-based offset from top/left of list content
    int itemByPosition(int pos)
    {
        return 0;
    }

    /// Returns list item widget by item index
    Widget itemWidget(int index)
    {
        return _adapter ? _adapter.itemWidget(index) : null;
    }

    /// Returns true if item with corresponding index is enabled
    bool itemEnabled(int index)
    {
        if (_adapter !is null && index >= 0 && index < itemCount)
            return (_adapter.itemState(index) & State.enabled) != 0;
        return false;
    }

    protected void setHoverItem(int index)
    {
        if (_hoverItemIndex == index)
            return;
        if (_hoverItemIndex != -1)
        {
            _adapter.resetItemState(_hoverItemIndex, State.hovered);
            invalidate();
        }
        _hoverItemIndex = index;
        if (_hoverItemIndex != -1)
        {
            _adapter.setItemState(_hoverItemIndex, State.hovered);
            invalidate();
        }
    }

    /// Item list has changed
    protected void onAdapterChange(ListAdapter source)
    {
        requestLayout();
    }

    /// Override to handle change of selection
    protected void onSelectionChanged(int index, int previouslySelectedItem = -1)
    {
        itemSelected(this, index);
    }

    /// Override to handle mouse up on item
    protected void onItemClicked(int index)
    {
        itemClicked(this, index);
    }

    /// Allow to override state for update of items
    // previously used to treat main menu items with opened submenu as focused
    protected @property State overrideStateForItem()
    {
        return state;
    }

    protected void updateSelectedItemFocus()
    {
        if (_selectedItemIndex != -1)
        {
            if ((_adapter.itemState(_selectedItemIndex) & State.focused) != (overrideStateForItem & State.focused))
            {
                if (overrideStateForItem & State.focused)
                    _adapter.setItemState(_selectedItemIndex, State.focused);
                else
                    _adapter.resetItemState(_selectedItemIndex, State.focused);
                invalidate();
            }
        }
    }

    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
        updateSelectedItemFocus();
    }

    /// Ensure selected item is visible (scroll if necessary)
    void makeSelectionVisible()
    {
        if (_selectedItemIndex < 0)
            return; // no selection
        if (needLayout)
        {
            _makeSelectionVisibleOnNextLayout = true;
            return;
        }
        makeItemVisible(_selectedItemIndex);
    }

    protected bool _makeSelectionVisibleOnNextLayout;
    /// Ensure item is visible
    void makeItemVisible(int itemIndex)
    {
        if (itemIndex < 0 || itemIndex >= itemCount)
            return; // no selection

        Rect viewrc = Rect(0, 0, _clientBox.width, _clientBox.height);
        Rect scrolledrc = Rect(itemBox(itemIndex));
        if (scrolledrc.isInsideOf(viewrc)) // completely visible
            return;
        int delta = 0;
        if (_orientation == Orientation.vertical)
        {
            if (scrolledrc.top < viewrc.top)
                delta = scrolledrc.top - viewrc.top;
            else if (scrolledrc.bottom > viewrc.bottom)
                delta = scrolledrc.bottom - viewrc.bottom;
        }
        else
        {
            if (scrolledrc.left < viewrc.left)
                delta = scrolledrc.left - viewrc.left;
            else if (scrolledrc.right > viewrc.right)
                delta = scrolledrc.right - viewrc.right;
        }
        int newPosition = _scrollPosition + delta;
        _scrollbar.position = newPosition;
        _scrollPosition = newPosition;
        invalidate();
    }

    /// Move selection
    bool moveSelection(int direction, bool wrapAround = true)
    {
        if (itemCount <= 0)
            return false;
        int maxAttempts = itemCount - 1;
        int index = _selectedItemIndex;
        foreach (i; 0 .. maxAttempts)
        {
            int newIndex = 0;
            if (index < 0)
            {
                // no previous selection
                if (direction > 0)
                    newIndex = wrapAround ? 0 : itemCount - 1;
                else
                    newIndex = wrapAround ? itemCount - 1 : 0;
            }
            else
            {
                // step
                newIndex = index + direction;
            }
            if (newIndex < 0)
                newIndex = wrapAround ? itemCount - 1 : 0;
            else if (newIndex >= itemCount)
                newIndex = wrapAround ? 0 : itemCount - 1;
            if (newIndex != index)
            {
                if (selectItem(newIndex))
                {
                    onSelectionChanged(_selectedItemIndex, index);
                    return true;
                }
                index = newIndex;
            }
        }
        return true;
    }

    bool selectItem(int index, int disabledItemsSkipDirection)
    {
        debug (lists)
            debug Log.d("selectItem ", index, " skipDirection=", disabledItemsSkipDirection);
        if (index == -1 || disabledItemsSkipDirection == 0)
            return selectItem(index);
        int maxAttempts = itemCount;
        foreach (i; 0 .. maxAttempts)
        {
            if (selectItem(index))
                return true;
            index += disabledItemsSkipDirection > 0 ? 1 : -1;
            if (index < 0)
                index = itemCount - 1;
            if (index >= itemCount)
                index = 0;
        }
        return false;
    }

    bool selectItem(int index)
    {
        debug (lists)
            Log.d("selectItem ", index);
        if (_selectedItemIndex == index)
        {
            updateSelectedItemFocus();
            makeSelectionVisible();
            return true;
        }
        if (index != -1 && !itemEnabled(index))
            return false;
        if (_selectedItemIndex != -1)
        {
            _adapter.resetItemState(_selectedItemIndex, State.selected | State.focused);
            invalidate();
        }
        _selectedItemIndex = index;
        if (_selectedItemIndex != -1)
        {
            makeSelectionVisible();
            _adapter.setItemState(_selectedItemIndex, State.selected | (overrideStateForItem & State.focused));
            invalidate();
        }
        return true;
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        _scrollbar.onThemeChanged();
        foreach (i; 0 .. itemCount)
        {
            Widget w = itemWidget(i);
            w.onThemeChanged();
        }
        _adapter.maybe.onThemeChanged();
    }

    /// Handle scroll event
    protected void onScrollEvent(AbstractSlider source, ScrollEvent event)
    {
        int newPosition = _scrollPosition;
        if (event.action == ScrollAction.sliderMoved)
        {
            // scroll
            newPosition = event.position;
        }
        else
        {
            // use default handler for page/line up/down events
            newPosition = event.defaultUpdatePosition();
        }
        if (_scrollPosition != newPosition)
        {
            _scrollPosition = clamp(newPosition, 0, _maxScrollPosition);
            invalidate();
        }
    }

    /// List navigation using keys
    override bool onKeyEvent(KeyEvent event)
    {
        if (itemCount == 0)
            return false;
        int navigationDelta = 0;
        if (event.action == KeyAction.keyDown)
        {
            if (orientation == Orientation.vertical)
            {
                if (event.keyCode == KeyCode.down)
                    navigationDelta = 1;
                else if (event.keyCode == KeyCode.up)
                    navigationDelta = -1;
            }
            else
            {
                if (event.keyCode == KeyCode.right)
                    navigationDelta = 1;
                else if (event.keyCode == KeyCode.left)
                    navigationDelta = -1;
            }
        }
        if (navigationDelta != 0)
        {
            moveSelection(navigationDelta);
            return true;
        }
        if (event.action == KeyAction.keyDown)
        {
            if (event.keyCode == KeyCode.home)
            {
                // select first enabled item on Home key
                selectItem(0, 1);
                return true;
            }
            else if (event.keyCode == KeyCode.end)
            {
                // select last enabled item on End key
                selectItem(itemCount - 1, -1);
                return true;
            }
            else if (event.keyCode == KeyCode.pageDown)
            {
                // TODO
            }
            else if (event.keyCode == KeyCode.pageUp)
            {
                // TODO
            }
        }
        if (event.keyCode == KeyCode.space || event.keyCode == KeyCode.enter)
        {
            if (event.action == KeyAction.keyDown && enabled)
            {
                if (itemEnabled(_selectedItemIndex))
                {
                    onItemClicked(_selectedItemIndex);
                }
            }
            return true;
        }
        return super.onKeyEvent(event);
        //if (_selectedItemIndex != -1 && event.action == KeyAction.keyUp && (event.keyCode == KeyCode.SPACE || event.keyCode == KeyCode.enter)) {
        //    itemClicked(_selectedItemIndex);
        //    return true;
        //}
        //if (navigationDelta != 0) {
        //    int p = _selectedItemIndex;
        //    if (p < 0) {
        //        if (navigationDelta < 0)
        //            p = itemCount - 1;
        //        else
        //            p = 0;
        //    } else {
        //        p += navigationDelta;
        //        if (p < 0)
        //            p = itemCount - 1;
        //        else if (p >= itemCount)
        //            p = 0;
        //    }
        //    setHoverItem(-1);
        //    selectItem(p);
        //    return true;
        //}
        //return false;
    }

    override bool onMouseEvent(MouseEvent event)
    {
        debug (lists)
            Log.d("onMouseEvent ", id, " ", event.action, "  (", event.x, ",", event.y, ")");
        if (event.action == MouseAction.leave || event.action == MouseAction.cancel)
        {
            setHoverItem(-1);
            return true;
        }
        // delegate processing of mouse wheel to scrollbar widget
        if (event.action == MouseAction.wheel && _needScrollbar)
        {
            return _scrollbar.onMouseEvent(event);
        }
        // support onClick
        Point scrollOffset;
        if (_orientation == Orientation.vertical)
        {
            scrollOffset.y = _scrollPosition;
        }
        else
        {
            scrollOffset.x = _scrollPosition;
        }
        if (event.action == MouseAction.wheel)
        {
            _scrollbar.maybe.sendScrollEvent(event.wheelDelta > 0 ? ScrollAction.lineUp : ScrollAction.lineDown);
            return true;
        }
        if (event.action == MouseAction.buttonDown && (event.flags & (MouseFlag.lbutton || MouseFlag.rbutton)))
            setFocus();
        if (itemCount > _itemBoxes.length)
            return true; // layout not yet called. TODO: investigate this case
        Box b = _box;
        applyMargins(b);
        applyPadding(b);
        foreach (i; 0 .. itemCount)
        {
            Box ib = _itemBoxes[i];
            ib.x += b.x - scrollOffset.x;
            ib.y += b.y - scrollOffset.y;
            if (ib.isPointInside(event.x, event.y)) // TODO: optimize for long lists
            {
                if (_adapter && _adapter.wantMouseEvents)
                {
                    auto itemWidget = _adapter.itemWidget(i);
                    if (itemWidget)
                    {
                        Widget oldParent = itemWidget.parent;
                        itemWidget.parent = this;
                        if (event.action == MouseAction.move && event.noModifiers && itemWidget.hasTooltip)
                        {
                            itemWidget.scheduleTooltip(200);
                        }
                        //itemWidget.onMouseEvent(event);
                        itemWidget.parent = oldParent;
                    }
                }
                debug (lists)
                    Log.d("mouse event action=", event.action, " button=", event.button, " flags=", event.flags);
                if ((event.flags & (MouseFlag.lbutton || MouseFlag.rbutton)) || _selectOnHover)
                {
                    if (_selectedItemIndex != i && itemEnabled(i))
                    {
                        int prevSelection = _selectedItemIndex;
                        selectItem(i);
                        setHoverItem(-1);
                        onSelectionChanged(_selectedItemIndex, prevSelection);
                    }
                }
                else
                {
                    if (itemEnabled(i))
                        setHoverItem(i);
                }
                if (event.button == MouseButton.left || event.button == MouseButton.right)
                {
                    if ((_clickOnButtonDown && event.action == MouseAction.buttonDown) ||
                            (!_clickOnButtonDown && event.action == MouseAction.buttonUp))
                    {
                        if (itemEnabled(i))
                        {
                            onItemClicked(i);
                            if (_clickOnButtonDown)
                                event.doNotTrackButtonDown = true;
                        }
                    }
                }
                return true;
            }
        }
        return true;
    }

    override Boundaries computeBoundaries()
    {
        Boundaries bs;
        // measure children
        foreach (i; 0 .. itemCount)
        {
            Widget wt = itemWidget(i);
            if (wt is null || wt.visibility == Visibility.gone)
                continue;

            Boundaries wbs = wt.computeBoundaries();
            if (_orientation == Orientation.vertical)
            {
                bs.maximizeWidth(wbs);
                if (sumItemSizes)
                    bs.addHeight(wbs);
            }
            else
            {
                bs.maximizeHeight(wbs);
                if (sumItemSizes)
                    bs.addWidth(wbs);
            }
        }

        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        _box = geom;
        applyPadding(geom);

        // measure children
        // calc item rectangles
        // layout() will be called on draw

        if (_itemBoxes.length < itemCount)
            _itemBoxes.length = itemCount;

        int p;
        _needScrollbar = false;
        foreach (i; 0 .. itemCount)
        {
            Widget wt = itemWidget(i);
            if (wt is null || wt.visibility == Visibility.gone)
            {
                _itemBoxes[i].w = _itemBoxes[i].h = 0;
                continue;
            }

            Boundaries wbs = wt.computeBoundaries();
            if (_orientation == Orientation.vertical)
            {
                _itemBoxes[i].x = 0;
                _itemBoxes[i].y = p;
                _itemBoxes[i].w = geom.w;
                _itemBoxes[i].h = wbs.nat.h;
                p += wbs.nat.h;
                if (p > geom.h)
                {
                    _needScrollbar = true;
                    break;
                }
            }
            else // horizontal
            {
                _itemBoxes[i].x = p;
                _itemBoxes[i].y = 0;
                _itemBoxes[i].w = wbs.nat.w;
                _itemBoxes[i].h = geom.h;
                p += wbs.nat.w;
                if (p > geom.w)
                {
                    _needScrollbar = true;
                    break;
                }
            }
        }
        int sbsz; // scrollbar size
        if (_needScrollbar)
        {
            _scrollbar.visibility = Visibility.visible;

            Boundaries sbbs = _scrollbar.computeBoundaries();
            if (_orientation == Orientation.vertical)
            {
                sbsz = sbbs.nat.w;
                geom.w -= sbsz;
            }
            else
            {
                sbsz = sbbs.nat.h;
                geom.h -= sbsz;
            }

            // recalculate with scrollbar
            p = 0;
            foreach (i; 0 .. itemCount)
            {
                Widget wt = itemWidget(i);
                if (wt is null || wt.visibility == Visibility.gone)
                {
                    _itemBoxes[i].w = _itemBoxes[i].h = 0;
                    continue;
                }

                Boundaries wbs = wt.computeBoundaries();
                if (_orientation == Orientation.vertical)
                {
                    _itemBoxes[i].x = 0;
                    _itemBoxes[i].y = p;
                    _itemBoxes[i].w = geom.w;
                    _itemBoxes[i].h = wbs.nat.h;
                    p += wbs.nat.h;
                }
                else
                {
                    _itemBoxes[i].x = p;
                    _itemBoxes[i].y = 0;
                    _itemBoxes[i].w = wbs.nat.w;
                    _itemBoxes[i].h = geom.h;
                    p += wbs.nat.w;
                }
            }
        }
        else
        {   // hide scrollbar
            _scrollbar.visibility = Visibility.gone;
        }
        _clientBox = geom;
        _totalSize = p;

        // maximum scroll position
        if (_orientation == Orientation.vertical)
            _maxScrollPosition = max(_totalSize - _clientBox.height, 0);
        else
            _maxScrollPosition = max(_totalSize - _clientBox.width, 0);
        _scrollPosition = clamp(_scrollPosition, 0, _maxScrollPosition);
        // update scrollbar parameters
        if (_needScrollbar)
        {
            if (_orientation == Orientation.vertical)
            {
                _scrollbar.setRange(0, p);
                _scrollbar.pageSize = _clientBox.height;
                _scrollbar.position = _scrollPosition;
            }
            else
            {
                _scrollbar.setRange(0, p);
                _scrollbar.pageSize = _clientBox.width;
                _scrollbar.position = _scrollPosition;
            }
        }

        // lay out scrollbar
        if (_needScrollbar)
        {
            Box sbb = geom;
            if (_orientation == Orientation.vertical)
            {
                sbb.x += sbb.w;
                sbb.w = sbsz;
            }
            else
            {
                sbb.y += sbb.h;
                sbb.h = sbsz;
            }
            _scrollbar.layout(sbb);
        }
        else
            _scrollbar.cancelLayout();

        if (_makeSelectionVisibleOnNextLayout)
        {
            makeSelectionVisible();
            _makeSelectionVisibleOnNextLayout = false;
        }
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = _box;
        applyMargins(b);
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);
        // draw scrollbar
        if (_needScrollbar)
            _scrollbar.onDraw(buf);

        Point scrollOffset;
        if (_orientation == Orientation.vertical)
        {
            scrollOffset.y = _scrollPosition;
        }
        else
        {
            scrollOffset.x = _scrollPosition;
        }
        // draw items
        foreach (i; 0 .. itemCount)
        {
            Box ib = _itemBoxes[i];
            ib.x += b.x - scrollOffset.x;
            ib.y += b.y - scrollOffset.y;
            if (Rect(ib).intersects(Rect(b))) // TODO: optimize for long lists
            {
                Widget w = itemWidget(i);
                if (w is null || w.visibility != Visibility.visible)
                    continue;
                w.layout(ib);
                w.onDraw(buf);
            }
        }
    }

    override bool isChild(Widget item, bool deepSearch = true)
    {
        if (_adapter && _adapter.wantMouseEvents)
        {
            foreach (i; 0 .. itemCount)
            {
                auto itemWidget = _adapter.itemWidget(i);
                if (itemWidget is item)
                    return true;
            }
        }
        return super.isChild(item, deepSearch);
    }
}

class StringListWidget : ListWidget
{
    // Will be errored after other compilers will overtake phobos version 2.076
    version (DigitalMars)
    {
        import std.datetime.stopwatch : StopWatch;
    }
    else
    {
        import std.datetime : dto = to, StopWatch;
    }
    import core.time : dur;

    @property void items(dstring[] items)
    {
        _selectedItemIndex = -1;
        ownAdapter = new StringListAdapter(items);
        if (items.length > 0)
        {
            selectedItemIndex = 0;
        }
        requestLayout();
    }

    @property void items(StringListValue[] items)
    {
        _selectedItemIndex = -1;
        ownAdapter = new StringListAdapter(items);
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
        return (cast(StringListAdapter)adapter).item(_selectedItemIndex);
    }

    private dstring _searchString;
    private StopWatch _stopWatch;

    this()
    {
        super();
    }

    this(dstring[] items)
    {
        super();
        ownAdapter = new StringListAdapter(items);
    }

    this(StringListValue[] items)
    {
        super();
        ownAdapter = new StringListAdapter(items);
    }

    override bool setStringListValueListProperty(string propName, StringListValue[] values)
    {
        if (propName == "items")
        {
            items = values;
            return true;
        }
        return false;
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (itemCount == 0)
            return false;

        // accept user input and try to find a match in the list.
        if (event.action == KeyAction.text)
        {
            if (!_stopWatch.running)
            {
                _stopWatch.start;
            }

            version (DigitalMars)
            {
                auto timePassed = _stopWatch.peek; //.to!("seconds", float)(); // dtop is std.datetime.to

                if (timePassed > dur!"msecs"(500))
                    _searchString = ""d;
            }
            else
            {
                auto timePassed = _stopWatch.peek.dto!("seconds", float)(); // dtop is std.datetime.to

                if (timePassed > 0.5)
                    _searchString = ""d;
            }
            _searchString ~= to!dchar(event.text.toUTF8);
            _stopWatch.reset;

            if (selectClosestMatch(_searchString))
            {
                invalidate();
                return true;
            }
        }

        return super.onKeyEvent(event);
    }

    private bool selectClosestMatch(dstring term)
    {
        import std.uni : toLower;

        if (term.length == 0)
            return false;

        auto adptr = cast(StringListAdapter)adapter;

        // perfect match or best match
        int[] indices;
        foreach (int itemIndex; 0 .. adptr.itemCount)
        {
            dstring item = adptr.item(itemIndex);

            if (item == term)
            {
                // perfect match
                indices ~= itemIndex;
                break;
            }
            else
            {
                // term approximate to something
                bool addItem = true;
                foreach (int termIndex; 0 .. cast(int)term.length)
                {
                    if (termIndex < item.length)
                    {
                        if (toLower(term[termIndex]) != toLower(item[termIndex]))
                        {
                            addItem = false;
                            break;
                        }
                    }
                }

                if (addItem)
                {
                    indices ~= itemIndex;
                }
            }
        }

        // return best match
        if (indices.length > 0)
        {
            selectItem(indices[0]);
            itemSelected(this, indices[0]);
            return true;
        }

        return false; // did not find term
    }
}
