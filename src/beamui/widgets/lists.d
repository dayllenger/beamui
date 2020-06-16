/**
List views on data.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.lists;

import beamui.widgets.controls : ImageWidget;
import beamui.widgets.scrollbar;
import beamui.widgets.text : Label;
import beamui.widgets.widget;

/// Vertical or horizontal view on list data, with one scrollbar
class ListView : Widget
{
    /// List orientation, vertical by default
    Orientation orientation = Orientation.vertical;
    /// When true, mouse hover selects underlying item
    bool selectOnHover;
    /// Number of widgets in the list
    uint itemCount;

    Widget delegate(int) itemBuilder;

    /// Handle selection change
    void delegate(int) onSelect;
    /// Handle item click / activation (e.g. Space or Enter key pressed and mouse double clicked)
    void delegate(int) onItemClick;

    protected Widget[] _items;

    this()
    {
        allowsFocus = true;
    }

    /** Create a standard item widget from a string or `StringListValue`.

        CSS_nodes:
        ---
        // text only
        Label.item
        ---
        ---
        // StringListValue
        Panel.item
        ├── ImageWidget?
        ╰── Label
        ---
    */
    Widget item(dstring text)
    {
        Label item = render!Label;
        item.text = text;
        item.attributes["item"];
        return item;
    }
    /// ditto
    Widget item(StringListValue value)
    {
        Panel item = render!Panel;
        item.attributes["item"];

        Label label = render!Label;
        label.text = value.label;
        label.namespace = null;

        ImageWidget icon;
        if (value.iconID.length)
        {
            icon = render!ImageWidget;
            icon.imageID = value.iconID;
            icon.namespace = null;
        }
        return item.wrap(icon, label);
    }

    static protected class State : WidgetState
    {
        this()
        {
            childrenTTL = 100;
        }
    }

    override protected void build()
    {
        if (!itemCount || !itemBuilder)
            return;

        _items = arena.allocArray!Widget(itemCount);
        foreach (i; 0 .. itemCount)
            _items[i] = itemBuilder(i);
    }

    override int opApply(scope int delegate(size_t, Widget) callback)
    {
        foreach (i, item; _items)
        {
            if (const result = callback(i, item))
                return result;
        }
        return 0;
    }

    override protected WidgetState createState()
    {
        return new State;
    }

    override protected Element createElement()
    {
        return new ElemListView;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemListView el = fastCast!ElemListView(element);
        el.orientation = orientation;
        el.selectOnHover = selectOnHover;

        el.onSelect.clear();
        el.onItemClick.clear();
        if (onSelect)
            el.onSelect ~= onSelect;
        if (onItemClick)
            el.onItemClick ~= onItemClick;

        foreach (i, item; this)
        {
            mountChild(item, i);
        }
    }
}

class ElemListView : ElemGroup
{
    @property
    {
        Orientation orientation() const { return _orientation; }
        /// ditto
        void orientation(Orientation value)
        {
            if (_orientation == value)
                return;
            _orientation = value;
            _scrollbar.orientation = value;
            requestLayout();
        }

        /// Returns number of widgets in list
        int itemCount() const
        {
            return childCount;
        }

        /// Selected item index
        int selectedItemIndex() const { return _selectedItemIndex; }

        final protected inout(ScrollData) scrollData() inout { return _scrolldata; }
    }

    Signal!(void delegate(int)) onSelect;
    Signal!(void delegate(int)) onItemClick;

    bool selectOnHover;
    /// Policy for `measure`: when true, it considers items' total size
    bool sumItemSizes;

    private
    {
        Orientation _orientation = Orientation.vertical;
        /// If true, generate `onItemClick` on mouse down instead mouse up event
        bool _clickOnButtonDown;

        Buf!Box _itemBoxes;
        bool _needScrollbar;
        ScrollData _scrolldata;
        ElemScrollBar _scrollbar;

        /// Client area (without scrollbar and padding)
        Box _clientBox;
        /// Total height of all items for vertical orientation, or width for horizontal
        float _totalSize = 0;
        /// Item with `hovered` state, -1 if no such item
        int _hoverItemIndex = -1;
        /// Item with `selected` state, -1 if no such item
        int _selectedItemIndex = -1;
    }

    this()
    {
        _scrolldata = new ScrollData;
        _scrollbar = new ElemScrollBar(_scrolldata);
        _scrollbar.orientation = orientation;
        _scrollbar.visibility = Visibility.gone;
        _scrollbar.parent = this;
        _hiddenChildren.append(_scrollbar);
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
            res.x -= _scrolldata.position;
        else
            res.y -= _scrolldata.position;
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

    /// Returns list item element by item index
    inout(Element) itemElement(int index) inout
    {
        return child(index);
    }

    /// Returns true if item with corresponding index is enabled
    bool itemEnabled(int index)
    {
        return (child(index).stateFlags & StateFlags.enabled) != 0;
    }

    protected void setHoverItem(int index)
    {
        if (_hoverItemIndex == index)
            return;
        if (_hoverItemIndex != -1)
        {
            child(_hoverItemIndex).applyFlags(StateFlags.hovered, false);
            invalidate();
        }
        _hoverItemIndex = index;
        if (_hoverItemIndex != -1)
        {
            child(_hoverItemIndex).applyFlags(StateFlags.hovered, true);
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

        if ((child(idx).stateFlags & StateFlags.focused) != (stateFlags & StateFlags.focused))
        {
            child(idx).applyFlags(StateFlags.focused, (stateFlags & StateFlags.focused) != 0);
            invalidate();
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
        _scrolldata.position = _scrolldata.position + delta;
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
            child(_selectedItemIndex).applyFlags(StateFlags.selected | StateFlags.focused, false);
            invalidate();
        }
        _selectedItemIndex = index;
        if (_selectedItemIndex != -1)
        {
            makeSelectionVisible();
            child(_selectedItemIndex).applyFlags(StateFlags.selected | (stateFlags & StateFlags.focused), true);
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
        const b = Box(origin + innerBox.pos, innerBox.size);
        const bool vert = _orientation == Orientation.vertical;
        const scrollOffset = _scrolldata.position;
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
                if (event.alteredByButton(MouseButton.left) ||
                    event.alteredByButton(MouseButton.right) ||
                    selectOnHover)
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
            Element el = itemElement(i);
            if (el is null || el.visibility == Visibility.gone)
                continue;

            el.measure();
            Boundaries wbs = el.boundaries;
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
            Element el = itemElement(i);
            if (el is null || el.visibility == Visibility.gone)
            {
                _itemBoxes.unsafe_ref(i).w = 0;
                _itemBoxes.unsafe_ref(i).h = 0;
                continue;
            }

            el.measure();
            const wnat = el.natSize;
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
                    Element el = itemElement(i);
                    if (el is null || el.visibility == Visibility.gone)
                    {
                        _itemBoxes.unsafe_ref(i).w = 0;
                        _itemBoxes.unsafe_ref(i).h = 0;
                        continue;
                    }

                    el.measure();
                    const wnat = el.natSize;
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
        _clientBox = inner;

        // update scrollbar and lay out
        if (_needScrollbar)
        {
            _scrolldata.setRange(_totalSize, vertical ? _clientBox.h : _clientBox.w);
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
            _scrollbar.visibility = Visibility.visible;
            _scrollbar.layout(sbb);
        }
        else
        {   // hide scrollbar
            _scrollbar.visibility = Visibility.gone;
        }

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
        const scrollOffset = _scrolldata.position;
        const int start = itemByPosition(scrollOffset);
        const int end = itemByPosition(scrollOffset + (vert ? b.h : b.w));
        foreach (i; start .. end + 1)
        {
            Element el = itemElement(i);
            if (el is null || el.visibility != Visibility.visible)
                continue;

            Box ib = _itemBoxes[i];
            ib.x += b.x;
            ib.y += b.y;
            (vert ? ib.y : ib.x) -= scrollOffset;

            el.layout(ib);
            el.draw(pr);
        }
    }
}
/+
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
