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
class LinearLayout : WidgetGroupDefaultDrawing
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

    static struct Cell
    {
        @property // at single line for compactness
        {
            /// Widget occupies all available width in layout
            bool fillWidth() const { return _fillWidth; }
            /// ditto
            void fillWidth(bool flag) { _fillWidth = flag; }
            /// Widget occupies all available height in layout
            bool fillHeight() const { return _fillHeight; }
            /// ditto
            void fillHeight(bool flag) { _fillHeight = flag; }

            /// Alignment (combined vertical and horizontal)
            Align alignment() const { return widget.style.alignment; }
            /// ditto
            void alignment(Align value) { widget.style.alignment = value; }
            /// Returns horizontal alignment
            Align halign() const { return widget.style.alignment & Align.hcenter; }
            /// Returns vertical alignment
            Align valign() const { return widget.style.alignment & Align.vcenter; }

            /// Margins (between widget bounds and its background)
            Insets margins() const { return widget.style.margins; }
            /// ditto
            void margins(Insets value) { widget.style.margins = value; }
            /// ditto
            void margins(int v) { widget.style.margins = v; }
            /// Top margin value
            int marginTop() const { return widget.style.marginTop; }
            /// ditto
            void marginTop(int value) { widget.style.marginTop = value; }
            /// Right margin value
            int marginRight() const { return widget.style.marginRight; }
            /// ditto
            void marginRight(int value) { widget.style.marginRight = value; }
            /// Bottom margin value
            int marginBottom() const { return widget.style.marginBottom; }
            /// ditto
            void marginBottom(int value) { widget.style.marginBottom = value; }
            /// Left margin value
            int marginLeft() const { return widget.style.marginLeft; }
            /// ditto
            void marginLeft(int value) { widget.style.marginLeft = value; }
        }

        /// Chained version of `fillWidth`
        Cell* setFillWidth(bool flag) { _fillWidth = flag; return &this; }
        /// Chained version of `fillHeight`
        Cell* setFillHeight(bool flag) { _fillHeight = flag; return &this; }
        /// Chained version of `alignment`
        Cell* setAlignment(Align value) { widget.style.alignment = value; return &this; }
        /// Chained version of `margins`
        Cell* setMargins(Insets value) { widget.style.margins = value; return &this; }
        /// ditto
        Cell* setMargins(int v) { widget.style.margins = v; return &this; }

        private
        {
            Widget widget;
            bool _fillWidth;
            bool _fillHeight;
        }
    }

    private
    {
        Orientation _orientation = Orientation.vertical;

        /// Array of cells, synchronized with the list of children
        Array!(Cell*) _cells;
        /// Temporary layout item list
        Array!LayoutItem items;
    }

    /// Create with orientation
    this(Orientation orientation = Orientation.vertical)
    {
        _orientation = orientation;
    }

    /// Returns cell pointer by specified index. Index must be in range
    Cell* cell(size_t i)
    {
        return _cells[i];
    }
    /// Returns cell pointer by specified widget. Widget must be in the layout
    Cell* cell(Widget item)
    {
        return _cells[childIndex(item)];
    }

    /// Add widgets to the layout next to the last item.
    /// Returns: Last cell pointer (not `null`), that allows to adjust layout properties for this widget.
    Cell* add(Widget first, Widget[] next...)
    {
        addChild(first);
        foreach (item; next)
            addChild(item);
        return _cells.back;
    }

    /// Same as `add`, but skips null widgets. May return `null` cell
    Cell* addSome(Widget first, Widget[] next...)
    {
        size_t prevLength = _cells.length;
        if (first)
            addChild(first);
        foreach (item; next)
            if (item)
                addChild(item);
        return _cells.length > prevLength ? _cells.back : null;
    }

    /// Add a spacer
    LinearLayout addSpacer()
    {
        auto item = new Spacer;
        super.addChild(item);
        _cells ~= new Cell(item, true, true);
        return this;
    }

    /// Add a resizer
    LinearLayout addResizer()
    {
        add(new Resizer);
        return this;
    }

    override Widget addChild(Widget item)
    {
        super.addChild(item);
        Cell* cell = createDefaultCell(item);
        _cells ~= cell;
        requestLayout();
        return item;
    }

    override Widget insertChild(int index, Widget item)
    {
        super.insertChild(index, item);
        Cell* cell = createDefaultCell(item);
        _cells.insertBefore(_cells[index .. $], cell);
        requestLayout();
        return item;
    }

    override Widget removeChild(int index)
    {
        Widget result = super.removeChild(index);
        _cells.linearRemove(_cells[index .. index + 1]);
        requestLayout();
        return result;
    }

    override Widget removeChild(string id)
    {
        return super.removeChild(id);
    }

    override Widget removeChild(Widget child)
    {
        return super.removeChild(child);
    }

    override void removeAllChildren(bool destroyThem = true)
    {
        super.removeAllChildren(destroyThem);
        _cells.clear();
        requestLayout();
    }

    override void replaceChild(Widget oldChild, Widget newChild)
    {
        super.replaceChild(oldChild, newChild);
        foreach (ref c; _cells)
        {
            if (c.widget is oldChild)
            {
                c.widget = newChild;
                break;
            }
        }
    }

    private Cell* createDefaultCell(Widget item) const
    {
        if (_orientation == Orientation.vertical)
            return new Cell(item, true, false);
        else
            return new Cell(item, false, true);
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        if (ptype == StyleProperty.spacing)
            requestLayout();
    }

    //===============================================================

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
            Size m = _cells[item.index].margins.size;
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
        int space = style.spacing * (cast(int)items.length - 1);
        if (_orientation == Orientation.horizontal)
        {
            bs.max.w += space;
            bs.nat.w += space;
            bs.min.w += space;
        }
        else
        {
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
            Cell* c = _cells[item.index];
            Insets m = c.margins;
            static if (horiz)
            {
                item.fill = c.fillWidth;
                item.result.h = c.fillHeight ? min(geom.h, item.bs.max.h) : item.bs.nat.h;
                if (item.wt.dependentSize == DependentSize.width)
                    item.bs.nat.w = item.wt.widthForHeight(item.result.h - m.height) + m.width;
            }
            else
            {
                item.fill = c.fillHeight;
                item.result.w = c.fillWidth ? min(geom.w, item.bs.max.w) : item.bs.nat.w;
                if (item.wt.dependentSize == DependentSize.height)
                    item.bs.nat.h = item.wt.heightForWidth(item.result.w - m.width) + m.height;
            }
        }
        const int spacing = style.spacing;
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

                int lmin = left.bs.min.pick!dim;
                int rmin = right.bs.min.pick!dim;
                int lresult = left.result.pick!dim;
                int rresult = right.result.pick!dim;
                int delta = clamp(resizer.delta, -(lresult - lmin), rresult - rmin);
                resizer._delta = delta;
                left.result.pick!dim  = lresult + delta;
                right.result.pick!dim = rresult - delta;
            }
        }
        // lay out items
        int pen;
        foreach (ref item; items)
        {
            Cell* c = _cells[item.index];
            Insets m = c.margins;
            Size sz = item.result;
            Box res = Box(geom.x + m.left, geom.y + m.top, geom.w, geom.h);
            static if (horiz)
            {
                res.x += pen;
                applyAlign(res, sz, Align.unspecified, c.valign);
            }
            else
            {
                res.y += pen;
                applyAlign(res, sz, c.halign, Align.unspecified);
            }
            res.w -= m.width;
            res.h -= m.height;
            item.wt.layout(res);
            pen += sz.pick!dim + spacing;
        }
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
        style.spacing = spacing;
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
        style.spacing = spacing;
    }
}

/// Place all children into same place (usually, only one child should be visible at a time)
class FrameLayout : WidgetGroupDefaultDrawing
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
            Boundaries wbs = item.boundaries;
            bs.maximizeWidth(wbs);
            bs.maximizeHeight(wbs);
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
            {
                item.layout(inner);
            }
        }
    }

    /// Make one of children (with specified ID) visible, for the rest, set visibility to `otherChildrenVisibility`
    bool showChild(string ID, Visibility otherChildrenVisibility = Visibility.hidden, bool updateFocus = false)
    {
        bool found;
        Widget foundWidget;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.compareID(ID))
            {
                item.visibility = Visibility.visible;
                item.requestLayout();
                foundWidget = item;
                found = true;
            }
            else
            {
                item.visibility = otherChildrenVisibility;
            }
        }
        if (foundWidget !is null && updateFocus)
            foundWidget.setFocus();
        return found;
    }
}

/// Place children at specified coordinates
class FreeLayout : WidgetGroupDefaultDrawing
{
    static struct Cell
    {
        int x, y;

        private Size size;
    }
    private Array!(Cell*) _cells;

    /// Returns cell pointer by specified index. Index must be in range
    Cell* cell(size_t i)
    {
        return _cells[i];
    }
    /// Returns cell pointer by specified widget. Widget must be in the layout
    Cell* cell(Widget item)
    {
        return _cells[childIndex(item)];
    }

    /// Add a widget at specific position upper the added last item
    /// Returns: Last cell pointer (not `null`), that allows to adjust layout properties for this widget.
    Cell* add(Widget item, int x, int y)
    {
        addChild(item);
        Cell* c = _cells.back;
        c.x = x;
        c.y = y;
        return c;
    }

    override Widget addChild(Widget item)
    {
        super.addChild(item);
        _cells ~= new Cell;
        requestLayout();
        return item;
    }

    override Widget insertChild(int index, Widget item)
    {
        super.insertChild(index, item);
        _cells.insertBefore(_cells[index .. $], new Cell);
        requestLayout();
        return item;
    }

    override Widget removeChild(int index)
    {
        Widget result = super.removeChild(index);
        _cells.linearRemove(_cells[index .. index + 1]);
        requestLayout();
        return result;
    }

    override Widget removeChild(string id)
    {
        return super.removeChild(id);
    }

    override Widget removeChild(Widget child)
    {
        return super.removeChild(child);
    }

    override void removeAllChildren(bool destroyThem = true)
    {
        super.removeAllChildren(destroyThem);
        _cells.clear();
        requestLayout();
    }

    //===============================================================

    override void measure()
    {
        Boundaries bs;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility == Visibility.gone)
                continue;
            Cell* c = _cells[i];
            item.measure();
            Boundaries wbs = item.boundaries;
            c.size = wbs.nat;
            wbs.min.w += c.x;
            wbs.min.h += c.y;
            wbs.nat.w += c.x;
            wbs.nat.h += c.y;
            wbs.max.w += c.x;
            wbs.max.h += c.y;
            bs.maximizeWidth(wbs);
            bs.maximizeHeight(wbs);
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
            {
                Cell* c = _cells[i];
                item.layout(Box(inner.x + c.x, inner.y + c.y, c.size.w, c.size.h));
            }
        }
    }
}

/// Layout children as table with rows and columns
class TableLayout : WidgetGroupDefaultDrawing
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

    protected int rowSpace() const
    {
        int c = rowCount;
        return c > 1 ? style.rowSpacing * (c - 1) : 0;
    }

    protected int colSpace() const
    {
        int c = colCount;
        return c > 1 ? style.columnSpacing * (c - 1) : 0;
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

        if (ptype == StyleProperty.rowSpacing || ptype == StyleProperty.columnSpacing)
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

        Size space = Size(rowSpace, colSpace);
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

        allocateSpace!`h`(_rows, inner.h - rowSpace);
        allocateSpace!`w`(_cols, inner.w - colSpace);

        const int rowSpacing = style.rowSpacing;
        const int colSpacing = style.columnSpacing;
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
                xpen += w + colSpacing;
            }
            ypen += h + rowSpacing;
        }
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
