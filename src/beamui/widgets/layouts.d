/**
Common layouts implementation.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.layouts;

public import beamui.widgets.widget;
import std.container.array;

/// Helper for layouts
struct LayoutItem
{
    Widget wt;
    int index = -1;

    Boundaries bs;
    bool fill;
    Size result;
}

/// Arranges items either vertically or horizontally
class LinearLayout : WidgetGroup
{
    @property
    {
        /// Linear layout orientation (vertical, horizontal)
        Orientation orientation() const { return _orientation; }
        /// ditto
        void orientation(Orientation value)
        {
            if (_orientation != value)
            {
                _orientation = value;
                requestLayout();
            }
        }
    }

    private
    {
        Orientation _orientation = Orientation.vertical;

        /// Temporary layout item list
        Array!LayoutItem items;
    }

    /// Create with orientation
    this(Orientation orientation = Orientation.vertical)
    {
        _orientation = orientation;
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        if (ptype == StyleProperty.rowGap || ptype == StyleProperty.columnGap)
            requestLayout();
    }

    override void measure()
    {
        // fill items array
        items.length = 0;
        foreach (i; 0 .. childCount)
        {
            Widget wt = child(i);
            if (wt.visibility != Visibility.gone)
                items ~= LayoutItem(wt, i);
        }
        // now we can safely work with items

        if (items.length == 0)
        {
            super.measure(); // do default computation
            return;
        }

        // has items
        Boundaries bs;
        foreach (ref item; items)
        {
            item.wt.measure();
            Boundaries wbs = item.wt.boundaries;
            // add margins
            Size m = item.wt.style.margins.size;
            Boundaries ms = Boundaries(m, m, m);
            wbs.addWidth(ms);
            wbs.addHeight(ms);
            item.bs = wbs;
            if (_orientation == Orientation.horizontal)
            {
                bs.addWidth(wbs);
                bs.maximizeHeight(wbs);
            }
            else
            {
                bs.maximizeWidth(wbs);
                bs.addHeight(wbs);
            }
        }
        if (_orientation == Orientation.horizontal)
        {
            const gap = style.columnGap.applyPercent(bs.nat.w);
            const space = gap * (cast(int)items.length - 1);
            bs.max.w += space;
            bs.nat.w += space;
            bs.min.w += space;
        }
        else
        {
            const gap = style.rowGap.applyPercent(bs.nat.h);
            const space = gap * (cast(int)items.length - 1);
            bs.max.h += space;
            bs.nat.h += space;
            bs.min.h += space;
        }
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        if (items.length > 0)
        {
            if (_orientation == Orientation.horizontal)
                doLayout!`w`(innerBox);
            else
                doLayout!`h`(innerBox);
        }
    }

    private void doLayout(string dim)(Box geom)
    {
        // TODO: percent
        enum horiz = dim == `w`;

        // setup fill
        foreach (ref item; items)
        {
            const wstyle = item.wt.style;
            const stretch = wstyle.stretch;
            const bool main = stretch == Stretch.main || stretch == Stretch.both;
            const bool cross = stretch == Stretch.cross || stretch == Stretch.both;
            const Insets m = wstyle.margins;
            static if (horiz)
            {
                item.fill = main;
                item.result.h = cross ? min(geom.h, item.bs.max.h) : item.bs.nat.h;
                if (item.wt.dependentSize == DependentSize.width)
                    item.bs.nat.w = item.wt.widthForHeight(item.result.h - m.height) + m.width;
            }
            else
            {
                item.fill = main;
                item.result.w = cross ? min(geom.w, item.bs.max.w) : item.bs.nat.w;
                if (item.wt.dependentSize == DependentSize.height)
                    item.bs.nat.h = item.wt.heightForWidth(item.result.w - m.width) + m.height;
            }
        }
        static if (horiz)
            const int spacing = style.columnGap.applyPercent(geom.w);
        else
            const int spacing = style.rowGap.applyPercent(geom.h);
        int gaps = spacing * (cast(int)items.length - 1);
        allocateSpace!dim(items, geom.pick!dim - gaps);
        // apply resizers
        foreach (i; 1 .. items.length - 1)
        {
            auto resizer = cast(Resizer)items[i].wt;
            if (resizer)
            {
                LayoutItem* left  = &items[i - 1];
                LayoutItem* right = &items[i + 1];

                const lmin = left.bs.min.pick!dim;
                const rmin = right.bs.min.pick!dim;
                const lresult = left.result.pick!dim;
                const rresult = right.result.pick!dim;
                const delta = clamp(resizer.delta, -(lresult - lmin), rresult - rmin);
                resizer._delta = delta;
                left.result.pick!dim  = lresult + delta;
                right.result.pick!dim = rresult - delta;
            }
        }
        // lay out items
        int pen;
        foreach (ref item; items)
        {
            const wstyle = item.wt.style;
            const Insets m = wstyle.margins;
            const Size sz = item.result;
            Box res = Box(geom.x + m.left, geom.y + m.top, geom.w, geom.h);
            static if (horiz)
            {
                res.x += pen;
                applyAlign(res, sz, Align.unspecified, wstyle.valign);
            }
            else
            {
                res.y += pen;
                applyAlign(res, sz, wstyle.halign, Align.unspecified);
            }
            res.w -= m.width;
            res.h -= m.height;
            item.wt.layout(res);
            pen += sz.pick!dim + spacing;
        }
    }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        drawAllChildren(buf);
    }
}

private ref auto pick(string dim, T)(ref T s)
{
    return __traits(getMember, s, dim);
}

void allocateSpace(string dim)(ref Array!LayoutItem items, int totalSize)
{
    int min;
    int nat;
    foreach (const ref item; items)
    {
        min += item.bs.min.pick!dim;
        nat += item.bs.nat.pick!dim;
    }

    if (totalSize == nat)
    {
        foreach (ref item; items)
            item.result.pick!dim = item.bs.nat.pick!dim;
    }
    else if (totalSize <= min)
    {
        foreach (ref item; items)
            item.result.pick!dim = item.bs.min.pick!dim;
    }
    else if (totalSize > nat)
        expand!dim(items, totalSize - nat);
    else
        shrink!dim(items, totalSize - min);
}

private struct Item
{
    size_t index;
    int bound, base;
}
private Item[] storage;

private void expand(string dim)(ref Array!LayoutItem items, const int extraSize)
{
    assert(extraSize > 0);

    const len = items.length;
    if (storage.length < len)
        storage.length = len;

    // gather all filling items into the array, set sizes for fixed ones
    int fillCount;
    foreach (i; 0 .. len)
    {
        auto item = &items[i];
        const nat = item.bs.nat.pick!dim;
        const max = item.bs.max.pick!dim;
        if (item.fill)
            storage[fillCount++] = Item(i, max, nat);
        else
            item.result.pick!dim = nat;
    }

    if (fillCount > 0)
    {
        Item[] filling = storage[0 .. fillCount];
        // do fill
        expandImpl(filling, extraSize);
        // set final values
        foreach (const ref item; filling)
        {
            items[item.index].result.pick!dim = item.base;
        }
    }
}

private void expandImpl(Item[] filling, int extraSize)
{
    // check the simplest case
    if (filling.length == 1)
    {
        filling[0].base = min(filling[0].base + extraSize, filling[0].bound);
        return;
    }

    // sort items by their natural size
    sort!((a, b) => a.base < b.base)(filling);
    // we add space to the smallest first, so last items may get nothing
    int volume;
    int end;
    for (end = 1; end < filling.length; end++)
    {
        int v;
        foreach (j; 0 .. end)
        {
            v += min(filling[end].base, filling[j].bound) - filling[j].base;
        }
        if (v <= extraSize)
            volume = v;
        else
            break;
    }
    const upto = filling[end - 1].base;
    int skip;
    foreach (ref item; filling[0 .. end - 1])
    {
        item.base = min(upto, item.bound);
        // skip already bounded by max
        if (item.base == item.bound)
            skip++;
    }
    extraSize -= volume;
    if (extraSize > 0)
    {
        // after sorting all items in filling[skip .. end] will have the same size
        // we need to add equal amounts of space to them
        addSpaceToItems(filling[0 .. end], skip, extraSize);
    }
}

private void addSpaceToItems(Item[] items, const int skip, int extraSize)
{
    assert(extraSize > 0);
    assert(items.length > 0);

    // sort by available space to add
    sort!((a, b) => a.bound - a.base < b.bound - b.base)(items);

    int start = skip;
    const end = cast(int)items.length;
    foreach (i; start .. end)
    {
        const perItemSize = extraSize / (end - start);
        const bound = items[i].bound;
        const diff = bound - items[i].base;
        // item is bounded, treat as a fixed one
        if (diff <= perItemSize)
        {
            items[i].base = bound;
            extraSize -= diff;
            start++;
        }
        else
            break;
    }
    addSpaceEvenly(items[start .. end], extraSize);
}

private void addSpaceEvenly(Item[] items, const int extraSize)
{
    assert(extraSize > 0);

    const divisor = cast(int)items.length;
    if (divisor == 0)
        return;

    const perItemSize = extraSize / divisor;
    // correction for perfect results
    const error = extraSize - perItemSize * divisor;
    const front = error / 2;
    const rear = divisor - error + front;
    int i;
    foreach (ref item; items)
    {
        // apply correction
        int sz = perItemSize;
        if (i < front || i >= rear)
            sz++;
        i++;
        item.base += sz;
    }
}

private void shrink(string dim)(ref Array!LayoutItem items, int available)
{
    assert(available > 0);

    const len = items.length;
    if (storage.length < len)
        storage.length = len;
    foreach (i; 0 .. len)
    {
        const bs = &items[i].bs;
        storage[i] = Item(i, bs.nat.pick!dim, bs.min.pick!dim);
    }

    Item[] shrinking = storage[0 .. len];
    // check the simplest case
    if (len == 1)
    {
        shrinking[0].base += available;
    }
    else
    {
        addSpaceToItems(shrinking, 0, available);
    }
    // write values
    foreach (const ref item; shrinking)
    {
        items[item.index].result.pick!dim = item.base;
    }
}

/// Shortcut for `LinearLayout` with horizontal orientation
class Row : LinearLayout
{
    this()
    {
        super(Orientation.horizontal);
    }
    /// Create with spacing parameter
    this(int spacing)
    {
        super(Orientation.horizontal);
        style.rowGap = spacing;
        style.columnGap = spacing;
    }
}

/// Shortcut for `LinearLayout` with vertical orientation
class Column : LinearLayout
{
    this()
    {
        super(Orientation.vertical);
    }
    /// Create with spacing parameter
    this(int spacing)
    {
        super(Orientation.vertical);
        style.rowGap = spacing;
        style.columnGap = spacing;
    }
}

/// Place all children into same place (usually, only one child should be visible at a time)
class FrameLayout : WidgetGroup
{
    override void measure()
    {
        Boundaries bs;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility == Visibility.gone)
                continue;

            item.measure();
            bs.maximize(item.boundaries);
        }
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        const inner = innerBox;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility == Visibility.visible)
                item.layout(inner);
            else
                item.cancelLayout();
        }
    }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        drawAllChildren(buf);
    }
}

/// Place children at specified coordinates
class FreeLayout : WidgetGroup
{
    override void measure()
    {
        Boundaries bs;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility == Visibility.gone)
                continue;

            item.measure();
            bs.maximize(item.boundaries);
        }
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        const inner = innerBox;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility != Visibility.visible)
                continue;

            const st = item.style;
            const LayoutLength left = st.left;
            const LayoutLength top = st.top;
            const LayoutLength right = st.right;
            const LayoutLength bottom = st.bottom;
            Box b;
            b.size = item.natSize;
            if (left.isDefined)
                b.x = left.applyPercent(inner.w);
            if (right.isDefined)
            {
                const x1 = inner.w - right.applyPercent(inner.w);
                if (left.isDefined)
                    b.w = x1 - b.x;
                else
                    b.x = x1 - b.w;
            }
            if (top.isDefined)
                b.y = top.applyPercent(inner.h);
            if (bottom.isDefined)
            {
                const y1 = inner.h - bottom.applyPercent(inner.h);
                if (left.isDefined)
                    b.h = y1 - b.y;
                else
                    b.y = y1 - b.h;
            }
            b.x += inner.x;
            b.y += inner.y;
            b.w = max(b.w, 0);
            b.h = max(b.h, 0);
            item.layout(b);
        }
    }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        drawAllChildren(buf);
    }
}

/// Layout children as table with rows and columns
class TableLayout : WidgetGroup
{
    @property
    {
        /// Number of columns
        int colCount() const { return _colCount; }
        /// ditto
        void colCount(int count)
        {
            if (_colCount != count)
            {
                _colCount = count;
                requestLayout();
            }
        }
        /// Number of rows
        int rowCount() const
        {
            return (childCount + (_colCount - 1)) / _colCount * _colCount;
        }
    }

    private
    {
        Array!LayoutItem _cells;
        Array!LayoutItem _rows;
        Array!LayoutItem _cols;

        int _colCount = 1;
    }

    protected int rowSpace(int gap) const
    {
        int c = rowCount;
        return c > 1 ? gap * (c - 1) : 0;
    }

    protected int colSpace(int gap) const
    {
        int c = colCount;
        return c > 1 ? gap * (c - 1) : 0;
    }

    protected ref LayoutItem cell(int col, int row)
    {
        return _cells[row * colCount + col];
    }

    protected ref LayoutItem row(int r)
    {
        return _rows[r];
    }

    protected ref LayoutItem col(int c)
    {
        return _cols[c];
    }

    protected void initialize(int rc, int cc)
    {
        _cells.length = rc * cc;
        _rows.length = rc;
        _cols.length = cc;
        _cells[] = LayoutItem();
        _rows[] = LayoutItem();
        _cols[] = LayoutItem();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        if (ptype == StyleProperty.rowGap || ptype == StyleProperty.columnGap)
            requestLayout();
    }

    override void measure()
    {
        int rc = rowCount;
        int cc = colCount;
        initialize(rc, cc);

        // measure cells
        foreach (int i; 0 .. rc * cc)
        {
            if (i < childCount)
            {
                Widget item = child(i);
                item.measure();
                Boundaries wbs = item.boundaries;
                _cells[i].wt = item;
                _cells[i].bs = wbs;
            }
        }

        static void applyCellToRow(ref LayoutItem row, ref LayoutItem cell)
        {
            row.bs.addWidth(cell.bs);
            row.bs.maximizeHeight(cell.bs);
            row.result.h = row.bs.nat.h;
//             if (cell.wt)
//                 row.fill |= cell.wt.fillsHeight;
        }

        static void applyCellToCol(ref LayoutItem column, ref LayoutItem cell)
        {
            column.bs.maximizeWidth(cell.bs);
            column.bs.addHeight(cell.bs);
            column.result.w = column.bs.nat.w;
//             if (cell.wt)
//                 column.fill |= cell.wt.fillsWidth;
        }

        Boundaries bs;
        // calc total row sizes
        foreach (y; 0 .. rc)
        {
            foreach (x; 0 .. cc)
            {
                applyCellToRow(row(y), cell(x, y));
            }
            bs.addHeight(row(y).bs);
        }
        // calc total column sizes
        foreach (x; 0 .. cc)
        {
            foreach (y; 0 .. rc)
            {
                applyCellToCol(col(x), cell(x, y));
            }
            bs.addWidth(col(x).bs);
        }

        const colgap = style.columnGap.applyPercent(bs.nat.w);
        const rowgap = style.columnGap.applyPercent(bs.nat.h);
        const space = Size(colSpace(colgap), rowSpace(rowgap));
        bs.min += space;
        bs.nat += space;
        bs.max += space;
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        const inner = innerBox;

        const colgap = style.columnGap.applyPercent(inner.w);
        const rowgap = style.columnGap.applyPercent(inner.h);
        allocateSpace!`w`(_cols, inner.w - colSpace(colgap));
        allocateSpace!`h`(_rows, inner.h - rowSpace(rowgap));

        int ypen = 0;
        foreach (y; 0 .. rowCount)
        {
            int h = row(y).result.h;
            int xpen = 0;
            foreach (x; 0 .. colCount)
            {
                int w = col(x).result.w;
                Box wb = Box(inner.x + xpen, inner.y + ypen, w, h);

                cell(x, y).wt.maybe.layout(wb);
                xpen += w + colgap;
            }
            ypen += h + rowgap;
        }
    }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        drawAllChildren(buf);
    }
}

/// Spacer to fill empty space in layouts
class Spacer : Widget
{
    this()
    {
    }
}

enum ResizerEventType
{
    startDragging,
    dragging,
    endDragging
}

/**
    Resizer control.

    Put it between other items in `LinearLayout` to allow resizing its siblings.
    While dragging, it will resize previous and next children in layout.
*/
class Resizer : Widget
{
    /// Orientation: vertical to resize vertically, horizontal to resize horizontally
    @property Orientation orientation() const { return _orientation; }

    @property bool validProps() const
    {
        return _previousWidget && _nextWidget;
    }

    Signal!(void delegate(ResizerEventType, int dragDelta)) resized;

    private
    {
        Orientation _orientation;
        Widget _previousWidget;
        Widget _nextWidget;
    }

    this(Orientation orient = Orientation.vertical)
    {
        _orientation = orient;
        allowsHover = true;
    }

    override CursorType getCursorType(int x, int y) const
    {
        if (_orientation == Orientation.vertical)
            return CursorType.sizeNS;
        else
            return CursorType.sizeWE;
    }

    protected void updateProps()
    {
        _previousWidget = null;
        _nextWidget = null;
        auto parentLayout = cast(LinearLayout)parent;
        if (parentLayout)
        {
            _orientation = parentLayout.orientation;
            int index = parentLayout.childIndex(this);
            _previousWidget = parentLayout.child(index - 1);
            _nextWidget = parentLayout.child(index + 1);
        }
        if (!validProps)
        {
            _previousWidget = null;
            _nextWidget = null;
        }
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        updateProps();
    }

    /// Resizer offset from initial position
    @property int delta() const { return _delta; } // TODO: make setter?

    private
    {
        bool _dragging;
        int _dragStartPosition;
        int _dragStartDelta;
        int _delta;
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            setState(State.pressed);
            _dragging = true;
            _dragStartPosition = _orientation == Orientation.vertical ? event.y : event.x;
            _dragStartDelta = _delta;
            if (resized.assigned)
                resized(ResizerEventType.startDragging, 0);
            return true;
        }
        if (event.action == MouseAction.focusIn && _dragging)
        {
            return true;
        }
        if (event.action == MouseAction.focusOut && _dragging)
        {
            return true;
        }
        if (event.action == MouseAction.move && _dragging)
        {
            _delta = _dragStartDelta + (_orientation == Orientation.vertical ? event.y : event.x) - _dragStartPosition;
            requestLayout();
            if (resized.assigned)
                resized(ResizerEventType.dragging, _delta - _dragStartDelta);
            return true;
        }
        if (event.action == MouseAction.move && allowsHover)
        {
            if (!(state & State.hovered))
            {
                setState(State.hovered);
            }
            return true;
        }
        if (event.action == MouseAction.buttonUp && event.button == MouseButton.left ||
            !event.alteredByButton(MouseButton.left) && _dragging)
        {
            resetState(State.pressed);
            if (_dragging)
            {
                _dragging = false;
                if (resized.assigned)
                    resized(ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        if (event.action == MouseAction.leave && allowsHover)
        {
            resetState(State.hovered);
            return true;
        }
        if (event.action == MouseAction.cancel && allowsHover)
        {
            resetState(State.hovered);
            resetState(State.pressed);
            if (_dragging)
            {
                _dragging = false;
                if (resized.assigned)
                    resized(ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        if (event.action == MouseAction.cancel)
        {
            resetState(State.pressed);
            if (_dragging)
            {
                _dragging = false;
                if (resized.assigned)
                    resized(ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        return false;
    }
}
