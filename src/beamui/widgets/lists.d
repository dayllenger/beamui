/**
List views on data.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.lists;

import beamui.core.signals;
import beamui.core.types : State, StringListValue;
/+
import beamui.widgets.controls;
import beamui.widgets.scrollbar;
import beamui.widgets.text;
import beamui.widgets.widget;
+/
/// List widget adapter provides items for list widgets
abstract class ListAdapter
{
    /// Handles item change
    private Signal!(void delegate()) onChange;

    ~this()
    {
        debug (lists)
            Log.d("Destroying ", getShortClassName(this));
    }
/+
    Widget createSharedItemWidget(out void delegate(int) updater);
+/
    /// Returns number of widgets in list
    @property int itemCount() const;
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
    final void connect(void delegate() handler)
    {
        onChange.connect(handler);
    }
    /// Disconnect adapter change handler
    final void disconnect(void delegate() handler)
    {
        onChange.disconnect(handler);
    }

    /// Notify listeners about list items changes
    void updateViews()
    {
        onChange();
    }
}

/// List adapter providing strings only
abstract class StringListAdapterBase : ListAdapter
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
/+
    override Widget createSharedItemWidget(out void delegate(int) updater)
    {
        auto widget = new Label;
        widget.isolateThisStyle();
        widget.setAttribute("item");
        updater = (i) {
            widget.text = _items[i].str;
            widget.state = _items[i].state;
            widget.cancelLayout();
        };
        return widget;
    }
+/
}

/// List adapter providing strings with icons
class IconStringListAdapter : StringListAdapterBase
{
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
/+
    override Widget createSharedItemWidget(out void delegate(int) updater)
    {
        auto widget = new Panel;
        widget.isolateThisStyle();
        widget.setAttribute("item");
        auto icon = new ImageWidget;
        auto label = new Label;
        label.style.stretch = Stretch.both;
        widget.add(icon, label);
        updater = (i) {
            widget.state = _items[i].state;
            label.text = _items[i].str;
            if (_items[i].iconID)
            {
                icon.visibility = Visibility.visible;
                icon.imageID = _items[i].iconID;
            }
            else
            {
                icon.visibility = Visibility.gone;
            }
        };
        return widget;
    }
+/
}
/+
alias ElemListWidget = ListWidget;
alias ElemStringListWidget = StringListWidget;

class NgListWidget : NgWidgetGroup
{
    ListAdapter adapter;
    Orientation orientation = Orientation.vertical;

    bool selectOnHover;

    void delegate(int) onItemClick;
    void delegate(int) onSelect;

    static NgListWidget make(ListAdapter adapter = null)
    {
        NgListWidget w = arena.make!NgListWidget;
        w.adapter = adapter;
        return w;
    }

    this()
    {
        allowsFocus = true;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemListWidget;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemListWidget el = fastCast!ElemListWidget(element);
        el.adapter = adapter;
        el.orientation = orientation;
        el.selectOnHover = selectOnHover;
        el.onItemClick.clear();
        el.onSelect.clear();
        if (onItemClick)
            el.onItemClick ~= onItemClick;
        if (onSelect)
            el.onSelect ~= onSelect;
    }
}

class NgStringListWidget : NgListWidget
{
    static NgStringListWidget make(StringListAdapterBase adapter)
        in(adapter)
    {
        NgStringListWidget w = arena.make!NgStringListWidget;
        w.adapter = adapter;
        return w;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemStringListWidget;
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
            _adapter.maybe.disconnect(&handleChildListChange);
            if (_adapter && _ownAdapter)
                destroy(_adapter);
            _adapter = adapter;
            _adapter.maybe.connect(&handleChildListChange);
            _ownAdapter = false;

            if (_itemWidget)
            {
                assert(_hiddenChildren.removeValue(_itemWidget));
                destroy(_itemWidget);
            }
            _itemWidget = _adapter.createSharedItemWidget(_itemWidgetUpdater);
            _itemWidget.parent = this;
            _hiddenChildren.append(_itemWidget);
            handleChildListChange();
            assert(_itemWidgetUpdater);
        }
        /// Set adapter, which will be owned by list (destroy will be called for adapter on widget destroy)
        void ownAdapter(ListAdapter adapter)
        {
            if (_adapter is adapter)
                return; // no changes
            _adapter.maybe.disconnect(&handleChildListChange);
            if (_adapter && _ownAdapter)
                destroy(_adapter);
            _adapter = adapter;
            _adapter.maybe.connect(&handleChildListChange);
            _ownAdapter = true;

            if (_itemWidget)
            {
                assert(_hiddenChildren.removeValue(_itemWidget));
                destroy(_itemWidget);
            }
            _itemWidget = _adapter.createSharedItemWidget(_itemWidgetUpdater);
            _itemWidget.parent = this;
            _hiddenChildren.append(_itemWidget);
            handleChildListChange();
            assert(_itemWidgetUpdater);
        }

        /// Returns number of widgets in list
        int itemCount() const
        {
            return _adapter ? _adapter.itemCount : childCount;
        }

        /// Selected item index
        int selectedItemIndex() const { return _selectedItemIndex; }
        /// ditto
        void selectedItemIndex(int index)
        {
            selectItem(index);
        }

        final protected float scrollPosition() const
        {
            return _scrollbar.data.position;
        }

        final protected void scrollPosition(float v)
        {
            _scrollbar.data.position = v;
        }
    }

    /// Handle selection change
    Signal!(void delegate(int)) onSelect;
    /// Handle item click / activation (e.g. Space or Enter key pressed and mouse double clicked)
    Signal!(void delegate(int)) onItemClick;

    /// Policy for `measure`: when true, it considers items' total size
    bool sumItemSizes;

    private
    {
        Widget _itemWidget;
        void delegate(int) _itemWidgetUpdater;
        int _lastItemIndex = -1; // TODO: reset when clear or replace?

        Buf!Box _itemBoxes;
        bool _needScrollbar;
        ScrollBar _scrollbar;

        /// Client area (without scrollbar and padding)
        Box _clientBox;
        /// Total height of all items for vertical orientation, or width for horizontal
        float _totalSize = 0;
        /// Item with `hovered` state, -1 if no such item
        int _hoverItemIndex = -1;
        /// Item with `selected` state, -1 if no such item
        int _selectedItemIndex = -1;

        Orientation _orientation = Orientation.vertical;
        /// When true, mouse hover selects underlying item
        bool _selectOnHover;
        /// If true, generate `onItemClick` on mouse down instead mouse up event
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
        _scrollbar.parent = this;
        _hiddenChildren.append(_scrollbar);
    }

    ~this()
    {
        _adapter.maybe.disconnect(&handleChildListChange);
        debug (lists)
            Log.d("Destroying List ", _id);
        if (_adapter && _ownAdapter)
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
    int itemByPosition(float offset) const
    {
        if (_itemBoxes.length == 0)
            return 0;
        // binary search
        int start = 0;
        int end = cast(int)_itemBoxes.length - 1;
        if (_orientation == Orientation.vertical)
        {
            while (start < end)
            {
                const mid = (start + end) / 2;
                const Box ib = _itemBoxes[mid];
                if (offset < ib.y + ib.h)
                {
                    if (offset < ib.y)
                        end = mid;
                    else
                        return mid;
                }
                else
                    start = mid + 1;
            }
        }
        else
        {
            while (start < end)
            {
                const mid = (start + end) / 2;
                const Box ib = _itemBoxes[mid];
                if (offset < ib.x + ib.w)
                {
                    if (offset < ib.x)
                        end = mid;
                    else
                        return mid;
                }
                else
                    start = mid + 1;
            }
        }
        return start;
    }

    /// Returns list item widget by item index
    inout(Widget) itemWidget(int index) inout
    {
        if (0 <= index && index < itemCount)
        {
            if (_adapter)
            {
                if (_lastItemIndex != index)
                {
                    with (caching(this))
                    {
                        _lastItemIndex = index;
                        _itemWidgetUpdater(index);
                    }
                }
                return _itemWidget;
            }
            return child(index);
        }
        return null;
    }

    /// Returns true if item with corresponding index is enabled
    bool itemEnabled(int index)
    {
        if (0 <= index && index < itemCount)
        {
            if (_adapter)
                return (_adapter.itemState(index) & State.enabled) != 0;
            else
                return (child(index).state & State.enabled) != 0;
        }
        return false;
    }

    protected void setHoverItem(int index)
    {
        if (_hoverItemIndex == index)
            return;
        if (_hoverItemIndex != -1)
        {
            if (_adapter)
                _adapter.resetItemState(_hoverItemIndex, State.hovered);
            else
                child(_hoverItemIndex).resetState(State.hovered);
            invalidate();
        }
        _hoverItemIndex = index;
        if (_hoverItemIndex != -1)
        {
            if (_adapter)
                _adapter.setItemState(_hoverItemIndex, State.hovered);
            else
                child(_hoverItemIndex).setState(State.hovered);
            invalidate();
        }
    }

    /// Item list has changed
    override protected void handleChildListChange()
    {
        needToRecalculateSize = true;
        needToRecalculateItemSizes = true;
        requestLayout();
    }

    /// Override to handle change of selection
    protected void handleSelection(int index, int previouslySelectedItem = -1)
    {
        onSelect(index);
    }

    /// Override to handle mouse up on item
    protected void handleItemClick(int index)
    {
        onItemClick(index);
    }

    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
        updateSelectedItemFocus();
    }

    protected void updateSelectedItemFocus()
    {
        const idx = _selectedItemIndex;
        if (idx == -1)
            return;

        if (_adapter)
        {
            if ((_adapter.itemState(idx) & State.focused) != (state & State.focused))
            {
                if (state & State.focused)
                    _adapter.setItemState(idx, State.focused);
                else
                    _adapter.resetItemState(idx, State.focused);
                invalidate();
            }
        }
        else
        {
            if ((child(idx).state & State.focused) != (state & State.focused))
            {
                if (state & State.focused)
                    child(idx).setState(State.focused);
                else
                    child(idx).resetState(State.focused);
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

        Rect viewrc = Rect(0, 0, _clientBox.w, _clientBox.h);
        Rect scrolledrc = Rect(itemBox(itemIndex));
        if (viewrc.contains(scrolledrc)) // completely visible
            return;

        float delta = 0;
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
                    handleSelection(_selectedItemIndex, index);
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
            if (_adapter)
                _adapter.resetItemState(_selectedItemIndex, State.selected | State.focused);
            else
                child(_selectedItemIndex).resetState(State.selected | State.focused);
            invalidate();
        }
        _selectedItemIndex = index;
        if (_selectedItemIndex != -1)
        {
            makeSelectionVisible();
            if (_adapter)
                _adapter.setItemState(_selectedItemIndex, State.selected | (state & State.focused));
            else
                child(_selectedItemIndex).setState(State.selected | (state & State.focused));
            invalidate();
        }
        return true;
    }

    /// List navigation using keys
    override bool handleKeyEvent(KeyEvent event)
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
            if (event.action == KeyAction.keyDown)
            {
                if (itemEnabled(_selectedItemIndex))
                {
                    handleItemClick(_selectedItemIndex);
                }
            }
            return true;
        }
        return super.handleKeyEvent(event);
    }

    override bool handleMouseEvent(MouseEvent event)
    {
        debug (lists)
            Log.d("mouse event: ", id, " ", event.action, "  (", event.x, ",", event.y, ")");
        if (event.action == MouseAction.leave || event.action == MouseAction.cancel)
        {
            setHoverItem(-1);
            return true;
        }
        if (event.action == MouseAction.buttonDown)
            setFocus();

        if (itemCount == 0)
            return true;
        if (itemCount > _itemBoxes.length)
            return true; // layout not yet called

        // same as in drawContent()
        const b = innerBox;
        const bool vert = _orientation == Orientation.vertical;
        const scrollOffset = scrollPosition;
        const int start = itemByPosition(scrollOffset);
        const int end = itemByPosition(scrollOffset + (vert ? b.h : b.w));
        // expand a bit to enable scroll by dragging outside the box
        foreach (i; max(start - 2, 0) .. min(end + 2, itemCount))
        {
            Box ib = _itemBoxes[i];
            ib.x += b.x;
            ib.y += b.y;
            (vert ? ib.y : ib.x) -= scrollOffset;
            if (ib.contains(event.x, event.y))
            {
                if (_adapter)
                {
                    auto wt = itemWidget(i);
                    assert(wt);
                    wt.handleMouseEvent(event);
                }
                if (event.alteredByButton(MouseButton.left) ||
                    event.alteredByButton(MouseButton.right) ||
                    _selectOnHover)
                {
                    if (_selectedItemIndex != i && itemEnabled(i))
                    {
                        int prevSelection = _selectedItemIndex;
                        selectItem(i);
                        setHoverItem(-1);
                        handleSelection(_selectedItemIndex, prevSelection);
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
                            handleItemClick(i);
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

    override bool handleWheelEvent(WheelEvent event)
    {
        // delegate wheel event processing to the scrollbar
        if (_needScrollbar) // visible
        {
            return _scrollbar.handleWheelEvent(event);
        }
        return super.handleWheelEvent(event);
    }

    // TODO: fully test this optimization
    // this and other little hacks allow to use millions of items in list
    private bool needToRecalculateSize;
    private bool needToRecalculateItemSizes;
    private Boundaries cachedBoundaries;

    override protected Boundaries computeBoundaries()
    {
        if (!needToRecalculateSize)
            return cachedBoundaries;

        Boundaries bs;
        // measure children
        float p = 0;
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
        return bs;
    }

    override protected void arrangeContent()
    {
        Box inner = innerBox;

        // measure children
        // calc item rectangles
        // layout() will be called on draw

        _itemBoxes.resize(itemCount);
        _needScrollbar = false;

        const vertical = _orientation == Orientation.vertical;
        float p = 0;
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
        float sbsz = 0; // scrollbar size
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

    override protected void drawContent(Painter pr)
    {
        // draw scrollbar
        if (_needScrollbar)
            _scrollbar.draw(pr);

        if (itemCount == 0)
            return;

        // draw items
        pr.clipIn(BoxI.from(_clientBox));
        const b = innerBox;
        const bool vert = _orientation == Orientation.vertical;
        const scrollOffset = scrollPosition;
        const int start = itemByPosition(scrollOffset);
        const int end = itemByPosition(scrollOffset + (vert ? b.h : b.w));
        foreach (i; start .. end + 1)
        {
            Widget w = itemWidget(i);
            if (w is null || w.visibility != Visibility.visible)
                continue;

            Box ib = _itemBoxes[i];
            ib.x += b.x;
            ib.y += b.y;
            (vert ? ib.y : ib.x) -= scrollOffset;

            w.layout(ib);
            w.draw(pr);
        }
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

    override bool handleKeyEvent(KeyEvent event)
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

        return super.handleKeyEvent(event);
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
            onSelect(indices[0]);
            return true;
        }

        return false; // did not find term
    }
}
+/
