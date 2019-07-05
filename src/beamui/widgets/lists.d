/**
List views on data.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.lists;

import beamui.core.signals;
import beamui.layout.linear;
import beamui.widgets.controls;
import beamui.widgets.scrollbar;
import beamui.widgets.text;
import beamui.widgets.widget;

/// List widget adapter provides items for list widgets
interface ListAdapter
{
    /// Returns number of widgets in list
    @property int itemCount() const;
    /// Returns list item widget by item index
    inout(Widget) itemWidget(int index) inout;
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
    ListAdapter connect(void delegate() handler);
    /// Disconnect adapter change handler
    ListAdapter disconnect(void delegate() handler);

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
    private Signal!(void delegate()) adapterChanged;

    override ListAdapter connect(void delegate() handler)
    {
        adapterChanged.connect(handler);
        return this;
    }

    override ListAdapter disconnect(void delegate() handler)
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

    inout(Widget) itemWidget(int index) inout
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
        adapterChanged();
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
    @property ref const(WidgetList) widgets() { return _widgets; }

    override @property int itemCount() const
    {
        return cast(int)_widgets.count;
    }

    override inout(Widget) itemWidget(int index) inout
    {
        return _widgets[index];
    }

    override State itemState(int index) const
    {
        return _widgets[index].state;
    }

    override State setItemState(int index, State flags)
    {
        return _widgets[index].setState(flags);
    }

    override State resetItemState(int index, State flags)
    {
        return _widgets[index].resetState(flags);
    }

    /// Add or insert item
    void add(Widget item, int index = -1)
    {
        if (index >= 0)
            _widgets.insert(index, item);
        else
            _widgets.append(item);
        updateViews();
    }
    /// Remove item and destroy it
    void remove(int index)
    {
        destroy(_widgets.remove(index));
        updateViews();
    }

    override void clear()
    {
        _widgets.clear();
        updateViews();
    }

    override void onThemeChanged()
    {
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
    private
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

    /// Init with array of `StringListValue`
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
    void add(dstring str, int index = -1)
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
    }

    /// Remove item by index
    void remove(int index)
    {
        if (index < 0 || index >= _items.length)
            return;
        _items.linearRemove(_items[index .. index + 1]);
        updateViews();
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
    @property void items(dstring[] values)
    {
        _items.length = values.length;
        foreach (i; 0 .. _items.length)
            _items[i] = Item(values[i]);
        updateViews();
    }

    /// Replace items collection
    @property void items(StringListValue[] values)
    {
        _items.length = values.length;
        foreach (i; 0 .. _items.length)
            _items[i] = Item(values[i].label, values[i].intID, values[i].stringID, values[i].iconID);
        updateViews();
    }

    override @property int itemCount() const
    {
        return cast(int)_items.length;
    }

    override int itemID(int index) const
    {
        return index >= 0 && index < _items.length ? _items[index].intID : 0;
    }

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
    private Label _widget;

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

    /// Init with array of `StringListValue`
    this(StringListValue[] items)
    {
        super(items);
    }

    ~this()
    {
        eliminate(_widget);
    }

    override inout(Widget) itemWidget(int index) inout
    {
        if (_widget && index == _lastItemIndex)
            return _widget;
        with (caching(this))
        {
            if (_widget is null)
            {
                _widget = new Label;
                _widget.bindSubItem(this, "item");
            }
            // update widget
            _widget.text = _items[index].str;
            _widget.state = _items[index].state;
            _widget.cancelLayout();
            _lastItemIndex = index;
        }
        return _widget;
    }

    override void onThemeChanged()
    {
        _widget.maybe.onThemeChanged();
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
    private
    {
        Row _widget;
        Label _label;
        ImageWidget _icon;
    }

    /// Create empty string list adapter
    this()
    {
        super();
    }

    /// Init with array of `StringListValue`
    this(StringListValue[] items)
    {
        super(items);
    }

    ~this()
    {
        eliminate(_widget);
    }

    override inout(Widget) itemWidget(int index) inout
    {
        if (_widget && index == _lastItemIndex)
            return _widget;
        with (caching(this))
        {
            if (_widget is null)
            {
                _widget = new Row;
                _widget.bindSubItem(this, "item");
                _icon = new ImageWidget;
                _icon.id = "icon";
                _label = new Label;
                _label.id = "label";
                _label.style.stretch = Stretch.both;
                _widget.add(_icon, _label);
            }
            // update widget
            _widget.state = _items[index].state;
            _label.text = _items[index].str;
            if (_items[index].iconID)
            {
                _icon.visibility = Visibility.visible;
                _icon.imageID = _items[index].iconID;
            }
            else
            {
                _icon.visibility = Visibility.gone;
            }
            _lastItemIndex = index;
        }
        return _widget;
    }

    override void onThemeChanged()
    {
        _widget.maybe.onThemeChanged();
    }

    override State setItemState(int index, State flags)
    {
        State res = super.setItemState(index, flags);
        if (_widget !is null && _lastItemIndex == index)
        {
            _widget.state = res;
            _label.state = res;
        }
        return res;
    }

    override State resetItemState(int index, State flags)
    {
        State res = super.resetItemState(index, flags);
        if (_widget !is null && _lastItemIndex == index)
        {
            _widget.state = res;
            _label.state = res;
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
        Orientation orientation() const { return _orientation; }
        /// ditto
        void orientation(Orientation value)
        {
            _orientation = value;
            _scrollbar.orientation = value;
            requestLayout();
        }

        /// When true, mouse hover selects underlying item
        bool selectOnHover() const { return _selectOnHover; }
        /// ditto
        void selectOnHover(bool select)
        {
            _selectOnHover = select;
        }

        /// List adapter
        inout(ListAdapter) adapter() inout { return _adapter; }
        /// ditto
        void adapter(ListAdapter adapter)
        {
            if (_adapter is adapter)
                return; // no changes
            _adapter.maybe.disconnect(&onAdapterChange);
            if (_adapter !is null && _ownAdapter)
                destroy(_adapter);
            _adapter = adapter;
            _adapter.maybe.connect(&onAdapterChange);
            _ownAdapter = false;
            onAdapterChange();
        }
        /// Set adapter, which will be owned by list (destroy will be called for adapter on widget destroy)
        void ownAdapter(ListAdapter adapter)
        {
            if (_adapter is adapter)
                return; // no changes
            _adapter.maybe.disconnect(&onAdapterChange);
            if (_adapter !is null && _ownAdapter)
                destroy(_adapter);
            _adapter = adapter;
            _adapter.maybe.connect(&onAdapterChange);
            _ownAdapter = true;
            onAdapterChange();
        }

        /// Returns number of widgets in list
        int itemCount() const
        {
            return _adapter ? _adapter.itemCount : 0;
        }

        /// Selected item index
        int selectedItemIndex() const { return _selectedItemIndex; }
        /// ditto
        void selectedItemIndex(int index)
        {
            selectItem(index);
        }

        final protected int scrollPosition() const
        {
            return _scrollbar.data.position;
        }

        final protected void scrollPosition(int v)
        {
            _scrollbar.data.position = v;
        }
    }

    /// Handle selection change
    Signal!(void delegate(int)) itemSelected;
    /// Handle item click / activation (e.g. Space or Enter key pressed and mouse double clicked)
    Signal!(void delegate(int)) itemClicked;

    /// Policy for `measure`: when true, it considers items' total size
    bool sumItemSizes;

    private
    {
        Buf!Box _itemBoxes;
        bool _needScrollbar;
        ScrollBar _scrollbar;

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
        allowsFocus = true;
        _scrollbar = new ScrollBar(orientation);
        _scrollbar.visibility = Visibility.gone;
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
    Box itemBoxNoScroll(int index) const
    {
        if (index < 0 || index >= _itemBoxes.length)
            return Box.init;
        return _itemBoxes[index];
    }

    /// Returns box for item (scrolled)
    Box itemBox(int index) const
    {
        if (index < 0 || index >= _itemBoxes.length)
            return Box.init;
        Box res = itemBoxNoScroll(index);
        if (_orientation == Orientation.horizontal)
            res.x -= scrollPosition;
        else
            res.y -= scrollPosition;
        return res;
    }

    /// Returns item index by 0-based offset from top/left of list content
    int itemByPosition(int pos) const
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
    protected void onAdapterChange()
    {
        needToRecalculateSize = true;
        needToRecalculateItemSizes = true;
        requestLayout();
    }

    /// Override to handle change of selection
    protected void onSelectionChanged(int index, int previouslySelectedItem = -1)
    {
        itemSelected(index);
    }

    /// Override to handle mouse up on item
    protected void onItemClicked(int index)
    {
        itemClicked(index);
    }

    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
        updateSelectedItemFocus();
    }

    protected void updateSelectedItemFocus()
    {
        if (_selectedItemIndex != -1)
        {
            if ((_adapter.itemState(_selectedItemIndex) & State.focused) != (state & State.focused))
            {
                if (state & State.focused)
                    _adapter.setItemState(_selectedItemIndex, State.focused);
                else
                    _adapter.resetItemState(_selectedItemIndex, State.focused);
                invalidate();
            }
        }
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

    private bool _makeSelectionVisibleOnNextLayout;
    /// Ensure item is visible
    void makeItemVisible(int itemIndex)
    {
        if (itemIndex < 0 || itemIndex >= itemCount)
            return; // no selection

        Rect viewrc = Rect(0, 0, _clientBox.width, _clientBox.height);
        Rect scrolledrc = Rect(itemBox(itemIndex));
        if (viewrc.contains(scrolledrc)) // completely visible
            return;

        int delta;
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
        scrollPosition = scrollPosition + delta;
    }

    /// Move selection
    bool moveSelection(int direction, bool wrapAround = true)
    {
        if (itemCount <= 0)
            return false;
        int maxAttempts = itemCount - 1;
        int index = _selectedItemIndex;
        if (index < 0)
        {
            // no previous selection
            if (direction > 0)
                index = -1;
            else
                index = wrapAround ? 0 : itemCount - 1;
        }
        foreach (i; 0 .. maxAttempts)
        {
            int newIndex = .wrapAround(index + direction, 0, itemCount - 1);
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
            int movement = disabledItemsSkipDirection > 0 ? 1 : -1;
            index = wrapAround(index + movement, 0, itemCount - 1);
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
            _adapter.setItemState(_selectedItemIndex, State.selected | (state & State.focused));
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
                if (event.key == Key.down)
                    navigationDelta = 1;
                else if (event.key == Key.up)
                    navigationDelta = -1;
            }
            else
            {
                if (event.key == Key.right)
                    navigationDelta = 1;
                else if (event.key == Key.left)
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
            if (event.key == Key.home)
            {
                // select first enabled item on Home key
                selectItem(0, 1);
                return true;
            }
            else if (event.key == Key.end)
            {
                // select last enabled item on End key
                selectItem(itemCount - 1, -1);
                return true;
            }
            else if (event.key == Key.pageDown)
            {
                // TODO
            }
            else if (event.key == Key.pageUp)
            {
                // TODO
            }
        }
        if (event.key == Key.space || event.key == Key.enter)
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
        if (event.action == MouseAction.wheel)
        {
            if (_needScrollbar) // visible
            {
                return _scrollbar.onMouseEvent(event);
            }
            else
            {
                const a = event.wheelDelta > 0 ? ScrollAction.lineUp : ScrollAction.lineDown;
                _scrollbar.triggerAction(a);
                return true;
            }
        }
        if (event.action == MouseAction.buttonDown)
            setFocus();

        if (itemCount == 0)
            return true;
        if (itemCount > _itemBoxes.length)
            return true; // layout not yet called

        const b = innerBox;
        // same as in onDraw
        const bool vert = _orientation == Orientation.vertical;
        const int scrollOffset = scrollPosition;
        const int start = findViewportIndex();
        foreach (i; start .. itemCount)
        {
            Box ib = _itemBoxes[i];
            ib.x += b.x;
            ib.y += b.y;
            (vert ? ib.y : ib.x) -= scrollOffset;
            if (ib.contains(event.x, event.y))
            {
                if (_adapter && _adapter.wantMouseEvents)
                {
                    auto itemWidget = _adapter.itemWidget(i);
                    if (itemWidget)
                    {
                        Widget oldParent = itemWidget.parent;
                        itemWidget.parent = this;
                        if (event.action == MouseAction.move && event.noKeyMods && event.noMouseMods &&
                            itemWidget.hasTooltip)
                        {
                            itemWidget.scheduleTooltip(200);
                        }
                        //itemWidget.onMouseEvent(event);
                        itemWidget.parent = oldParent;
                    }
                }
                debug (lists)
                    Log.d("mouse event action=", event.action, " button=", event.button, " flags=", event.flags);
                if (event.alteredByButton(MouseButton.left) ||
                    event.alteredByButton(MouseButton.right) ||
                    _selectOnHover)
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

    // TODO: fully test this optimization
    // this and other little hacks allow to use millions of items in list
    private bool needToRecalculateSize;
    private bool needToRecalculateItemSizes;
    private Boundaries cachedBoundaries;

    override void measure()
    {
        if (!needToRecalculateSize)
        {
            setBoundaries(cachedBoundaries);
            return;
        }

        Boundaries bs;
        // measure children
        int p;
        foreach (i; 0 .. itemCount)
        {
            Widget wt = itemWidget(i);
            if (wt is null || wt.visibility == Visibility.gone)
                continue;

            wt.measure();
            Boundaries wbs = wt.boundaries;
            if (_orientation == Orientation.vertical)
            {
                bs.maximizeWidth(wbs);
                if (sumItemSizes)
                    bs.addHeight(wbs);
                p += wbs.nat.h;
            }
            else
            {
                bs.maximizeHeight(wbs);
                if (sumItemSizes)
                    bs.addWidth(wbs);
                p += wbs.nat.w;
            }
        }
        _totalSize = p;
        cachedBoundaries = bs;
        needToRecalculateSize = false;
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        Box inner = innerBox;

        // measure children
        // calc item rectangles
        // layout() will be called on draw

        _itemBoxes.resize(itemCount);
        _needScrollbar = false;

        const vertical = _orientation == Orientation.vertical;
        int p;
        foreach (i; 0 .. itemCount)
        {
            Widget wt = itemWidget(i);
            if (wt is null || wt.visibility == Visibility.gone)
            {
                _itemBoxes.unsafe_ref(i).w = 0;
                _itemBoxes.unsafe_ref(i).h = 0;
                continue;
            }

            wt.measure();
            const wnat = wt.natSize;
            if (vertical)
            {
                _itemBoxes[i] = Box(0, p, inner.w, wnat.h);
                p += wnat.h;
                if (p > inner.h)
                {
                    _needScrollbar = true;
                    break;
                }
            }
            else
            {
                _itemBoxes[i] = Box(p, 0, wnat.w, inner.h);
                p += wnat.w;
                if (p > inner.w)
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

            _scrollbar.measure();
            const sbnat = _scrollbar.natSize;
            if (vertical)
            {
                sbsz = sbnat.w;
                inner.w -= sbsz;
            }
            else
            {
                sbsz = sbnat.h;
                inner.h -= sbsz;
            }

            // recalculate with scrollbar
            if (needToRecalculateItemSizes)
            {
                p = 0;
                foreach (i; 0 .. itemCount)
                {
                    Widget wt = itemWidget(i);
                    if (wt is null || wt.visibility == Visibility.gone)
                    {
                        _itemBoxes.unsafe_ref(i).w = 0;
                        _itemBoxes.unsafe_ref(i).h = 0;
                        continue;
                    }

                    wt.measure();
                    const wnat = wt.natSize;
                    if (vertical)
                    {
                        _itemBoxes[i] = Box(0, p, inner.w, wnat.h);
                        p += wnat.h;
                    }
                    else
                    {
                        _itemBoxes[i] = Box(p, 0, wnat.w, inner.h);
                        p += wnat.w;
                    }
                }
                needToRecalculateItemSizes = false;
            }
            else
            {
                foreach (i; 0 .. itemCount)
                {
                    if (vertical)
                    {
                        _itemBoxes.unsafe_ref(i).w = inner.w;
                    }
                    else
                    {
                        _itemBoxes.unsafe_ref(i).h = inner.h;
                    }
                }
            }
        }
        else
        {   // hide scrollbar
            _scrollbar.visibility = Visibility.gone;
        }
        _clientBox = inner;

        // update scrollbar and lay out
        if (_needScrollbar)
        {
            _scrollbar.data.setRange(_totalSize, vertical ? _clientBox.h : _clientBox.w);
            if (_itemBoxes.length > 0)
                _scrollbar.lineStep = vertical ? _itemBoxes[0].h : _itemBoxes[0].w;

            Box sbb = inner;
            if (vertical)
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
        const b = innerBox;
        const saver = ClipRectSaver(buf, b, style.alpha);

        // draw scrollbar
        if (_needScrollbar)
            _scrollbar.onDraw(buf);

        if (itemCount == 0)
            return;

        // draw items
        const bool vert = _orientation == Orientation.vertical;
        const int scrollOffset = scrollPosition;
        const int start = findViewportIndex();
        bool started;
        foreach (i; start .. itemCount)
        {
            Box ib = _itemBoxes[i];
            ib.x += b.x;
            ib.y += b.y;
            (vert ? ib.y : ib.x) -= scrollOffset;
            if (Rect(ib).intersects(Rect(b)))
            {
                Widget w = itemWidget(i);
                if (w is null || w.visibility != Visibility.visible)
                    continue;
                w.layout(ib);
                w.onDraw(buf);
                started = true;
            }
            else if (started)
                break;
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

    /// Fast bisect to find where is the viewport
    private int findViewportIndex()
    {
        int start = 0;
        int end = itemCount - 1;
        const bool vert = _orientation == Orientation.vertical;
        const int offset = scrollPosition;
        while (true)
        {
            const Box ib1 = _itemBoxes[start];
            const Box ib2 = _itemBoxes[end];
            if (vert)
            {
                if (offset - ib1.y < ib2.y + ib2.h - offset)
                {
                    end -= (end - start) / 2;
                }
                else
                {
                    start += (end - start) / 2;
                }
            }
            else
            {
                if (offset - ib1.x < ib2.x + ib2.w - offset)
                {
                    end -= (end - start) / 2;
                }
                else
                {
                    start += (end - start) / 2;
                }
            }
            if (end - start < 5)
                break;
        }
        return start;
    }
}

class StringListWidget : ListWidget
{
    import core.time : Duration, msecs;
    import std.datetime.stopwatch : StopWatch;

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
    @property dstring selectedItem() const
    {
        if (_selectedItemIndex < 0 || _selectedItemIndex >= _adapter.itemCount)
            return "";
        return (cast(StringListAdapter)adapter).item(_selectedItemIndex);
    }

    private Buf!dchar _searchString;
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

            Duration timePassed = _stopWatch.peek;
            if (timePassed > 500.msecs)
                _searchString.clear();

            _searchString ~= event.text;
            _stopWatch.reset;

            if (selectClosestMatch(_searchString[]))
            {
                invalidate();
                return true;
            }
        }

        return super.onKeyEvent(event);
    }

    private bool selectClosestMatch(const dchar[] term)
    {
        import std.uni : toLower;

        if (term.length == 0)
            return false;

        auto adptr = cast(StringListAdapter)adapter;

        // perfect match or best match
        Buf!int indices;
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
            itemSelected(indices[0]);
            return true;
        }

        return false; // did not find term
    }
}
