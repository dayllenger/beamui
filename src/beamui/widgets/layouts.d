/**
Common layouts implementation.

Synopsis:
---
import beamui.widgets.layouts;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
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

        /// Space between items
        int spacing() const
        {
            updateStyles();
            return _spacing;
        }
        /// ditto
        void spacing(int value)
        {
            setProperty!"_spacing" = value;
        }
        private alias spacing_effect = requestLayout;
    }

    static struct Cell
    {
        @property
        {
            /// Widget occupies all available width in layout
            bool fillWidth() const { return _fillWidth; }
            /// ditto
            ref Cell fillWidth(bool b)
            {
                _fillWidth = b;
                return this;
            }
            /// Widget occupies all available height in layout
            bool fillHeight() const { return _fillHeight; }
            /// ditto
            ref Cell fillHeight(bool b)
            {
                _fillHeight = b;
                return this;
            }

            /// Alignment (combined vertical and horizontal)
            Align alignment() const { return _alignment; }
            /// ditto
            ref Cell alignment(Align value)
            {
                setProperty!"_alignment" = value;
                return this;
            }
            /// Returns horizontal alignment
            Align halign() const
            {
                return _alignment & Align.hcenter;
            }
            /// Returns vertical alignment
            Align valign() const
            {
                return _alignment & Align.vcenter;
            }

            /// Margins (between widget bounds and its background)
            Insets margins() const
            {
                return Insets(_marginTop.toDevice, _marginRight.toDevice,
                              _marginBottom.toDevice, _marginLeft.toDevice);
            }
            /// ditto
            ref Cell margins(Insets value)
            {
                setProperty!"_marginTop" = Dimension(value.top);
                setProperty!"_marginRight" = Dimension(value.right);
                setProperty!"_marginBottom" = Dimension(value.bottom);
                setProperty!"_marginLeft" = Dimension(value.left);
                return this;
            }
            /// ditto
            ref Cell margins(int v)
            {
                return margins = Insets(v);
            }
        }

        private // TODO: effects
        {
            bool _fillWidth;
            bool _fillHeight;
            @forCSS("align") Align _alignment;
            @forCSS("margin-top") Dimension _marginTop = Dimension.zero;
            @forCSS("margin-right") Dimension _marginRight = Dimension.zero;
            @forCSS("margin-bottom") Dimension _marginBottom = Dimension.zero;
            @forCSS("margin-left") Dimension _marginLeft = Dimension.zero;

            @shorthandInsets("margin", "margin-top", "margin-right", "margin-bottom", "margin-left")
            static bool shorthandsForCSS;
        }

        mixin SupportCSS!Cell;
    }

    private
    {
        Orientation _orientation = Orientation.vertical;
        @forCSS("spacing") @animatable int _spacing = 6;

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

    mixin SupportCSS;

    /// Add a widget to the layout next to the last item.
    /// Returns: Cell reference, that allows to adjust layout properties for this widget.
    ref Cell add(Widget item)
    {
        super.addChild(item);
        Cell* cell = createDefaultCell();
        _cells ~= cell;
        item.stylesRecomputed = &cell.recomputeStyleImpl;
        requestLayout();
        return *cell;
    }

    /// Add a spacer
    LinearLayout addSpacer()
    {
        super.addChild(new Spacer);
        _cells ~= new Cell(true, true);
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
        Cell* cell = createDefaultCell();
        _cells ~= cell;
        item.stylesRecomputed = &cell.recomputeStyleImpl;
        requestLayout();
        return item;
    }

    override Widget insertChild(int index, Widget item)
    {
        super.insertChild(index, item);
        Cell* cell = createDefaultCell();
        _cells.insertBefore(_cells[index .. $], cell);
        item.stylesRecomputed = &cell.recomputeStyleImpl;
        requestLayout();
        return item;
    }

    override Widget removeChild(int index)
    {
        Widget result = super.removeChild(index);
        _cells.linearRemove(_cells[index .. index + 1]);
        result.stylesRecomputed.clear();
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

    private Cell* createDefaultCell() const
    {
        if (_orientation == Orientation.vertical)
            return new Cell(true, false);
        else
            return new Cell(false, true);
    }

    //===============================================================

    override Boundaries computeBoundaries()
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
            auto bs = Boundaries();
            applyStyle(bs);
            return bs;
        }
        // has items
        Boundaries bs;
        foreach (ref item; items)
        {
            Boundaries wbs = item.wt.computeBoundaries();
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
        int space = spacing * (cast(int)items.length - 1);
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
        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        if (items.length > 0)
        {
            applyPadding(geom);
            if (_orientation == Orientation.horizontal)
                doLayout!`w`(geom);
            else
                doLayout!`h`(geom);
        }
    }

    private void doLayout(string dim)(Box geom)
    {
        // TODO: layout weight, percent
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
                if (item.wt.widthDependsOnHeight)
                    item.bs.nat.w = item.wt.widthForHeight(item.result.h - m.height) + m.width;
            }
            else
            {
                item.fill = c.fillHeight;
                item.result.w = c.fillWidth ? min(geom.w, item.bs.max.w) : item.bs.nat.w;
                if (item.wt.heightDependsOnWidth)
                    item.bs.nat.h = item.wt.heightForWidth(item.result.w - m.width) + m.height;
            }
        }
        int gaps = spacing * (cast(int)items.length - 1);
        allocateSpace!dim(items, mixin("geom." ~ dim) - gaps);
        // apply resizers
        foreach (i; 1 .. items.length - 1)
        {
            auto resizer = cast(Resizer)items[i].wt;
            if (resizer)
            {
                LayoutItem* left  = &items[i - 1];
                LayoutItem* right = &items[i + 1];

                int lmin = mixin("left.bs.min." ~ dim);
                int rmin = mixin("right.bs.min." ~ dim);
                int lresult = mixin("left.result." ~ dim);
                int rresult = mixin("right.result." ~ dim);
                int delta = clamp(resizer.delta, -(lresult - lmin), rresult - rmin);
                resizer._delta = delta;
                mixin("left.result." ~ dim)  = lresult + delta;
                mixin("right.result." ~ dim) = rresult - delta;
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
            pen += mixin("sz." ~ dim) + _spacing;
        }
    }
}

void allocateSpace(string dim)(ref Array!LayoutItem items, int parentSize)
{
    int extraSize = distribute!dim(items, parentSize);
    if (extraSize > 0)
        expand!dim(items, extraSize);
}

int distribute(string dim)(ref Array!LayoutItem items, int bounds)
{
    int min;
    int nat;
    foreach (const ref item; items)
    {
        min += mixin("item.bs.min." ~ dim);
        nat += mixin("item.bs.nat." ~ dim);
    }

    if (bounds >= nat)
    {
        foreach (ref item; items)
        {
            mixin("item.result." ~ dim) = mixin("item.bs.nat." ~ dim);
        }
        return bounds - nat;
    }
    else
    {
        static int[2][] indices;
        static size_t len;

        len = items.length;
        if (indices.length < len)
            indices.length = len;
        foreach (i; 0 .. len)
        {
            Boundaries* bs = &items[i].bs;
            indices[i][0] = cast(int)i;
            indices[i][1] = mixin("bs.nat." ~ dim) - mixin("bs.min." ~ dim);
        }
        // sort indices by difference between min and nat sizes
        sort!((a, b) => a[1] < b[1])(indices[0 .. len]);

        // iterate
        int available = bounds - min;
        foreach (i; 0 .. len)
        {
            size_t j = indices[i][0];
            auto item = &items[j];
            int diff = indices[i][1];
            if (diff < available)
            {
                mixin("item.result." ~ dim) = mixin("item.bs.nat." ~ dim);
                available -= diff;
            }
            else
            {
                mixin("item.result." ~ dim) = mixin("item.bs.min." ~ dim) + available;
                available = 0;
            }
        }
        return 0;
    }
}

void expand(string dim)(ref Array!LayoutItem items, int extraSize)
{
    assert(extraSize > 0);

    int fillCount;
    foreach (const ref item; items)
    {
        if (item.fill)
            fillCount++;
    }
    if (fillCount > 0)
    {
        int perWidgetSize = extraSize / fillCount;
        foreach (ref item; items)
        {
            if (item.fill)
            {
                int diff = mixin("item.bs.max." ~ dim) - mixin("item.result." ~ dim);
                // widget is bounded by max, treat as a fixed widget
                if (perWidgetSize > diff)
                {
                    mixin("item.result." ~ dim) = mixin("item.bs.max." ~ dim);
                    extraSize -= diff;
                    item.fill = false;
                    fillCount--;
                }
            }
        }
        if (fillCount > 0)
        {
            perWidgetSize = max(extraSize, 0) / fillCount; // FIXME: max needed?
            // correction for perfect results
            int error = extraSize - perWidgetSize * fillCount;
            int front = error / 2;
            int rear = fillCount - error + front;
            int i;
            foreach (ref item; items)
            {
                if (item.fill)
                {
                    int sz = perWidgetSize;
                    // apply correction
                    if (i < front || i >= rear)
                        sz++;
                    i++;
                    mixin("item.result." ~ dim) += sz;
                }
            }
        }
    }
}

/// Shortcut for LinearLayout with horizontal orientation
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
        this.spacing = spacing;
    }
}

/// Shortcut for LinearLayout with vertical orientation
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
        this.spacing = spacing;
    }
}

/// Place all children into same place (usually, only one child should be visible at a time)
class FrameLayout : WidgetGroupDefaultDrawing
{
    override Boundaries computeBoundaries()
    {
        Boundaries bs;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility == Visibility.gone)
                continue;

            Boundaries wbs = item.computeBoundaries();
            bs.maximizeWidth(wbs);
            bs.maximizeHeight(wbs);
        }
        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        applyPadding(geom);
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility == Visibility.visible)
            {
                item.layout(geom);
            }
        }
    }

    /// Make one of children (with specified ID) visible, for the rest, set visibility to otherChildrenVisibility
    bool showChild(string ID, Visibility otherChildrenVisibility = Visibility.invisible, bool updateFocus = false)
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

        /// Space between rows (vertical)
        int rowSpacing() const
        {
            updateStyles();
            return _rowSpacing;
        }
        /// ditto
        void rowSpacing(int value)
        {
            setProperty!"_rowSpacing" = value;
        }

        /// Space between columns (horizontal)
        int columnSpacing() const
        {
            updateStyles();
            return _colSpacing;
        }
        /// ditto
        void columnSpacing(int value)
        {
            setProperty!"_colSpacing" = value;
        }
        private alias rowSpacing_effect = requestLayout;
        private alias colSpacing_effect = requestLayout;
    }

    /// Set int property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setIntProperty", "int", "colCount"));

    private
    {
        Array!LayoutItem _cells;
        Array!LayoutItem _rows;
        Array!LayoutItem _cols;

        int _colCount = 1;

        @forCSS("row-spacing") @animatable int _rowSpacing = 6;
        @forCSS("column-spacing") @animatable int _colSpacing = 6;
    }

    mixin SupportCSS;

    protected int rowSpace() const
    {
        int c = rowCount;
        return c > 1 ? _rowSpacing * (c - 1) : 0;
    }

    protected int colSpace() const
    {
        int c = colCount;
        return c > 1 ? _colSpacing * (c - 1) : 0;
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

    override Boundaries computeBoundaries()
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
                Boundaries wbs = item.computeBoundaries();
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
        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        applyPadding(geom);

        allocateSpace!`h`(_rows, geom.h - rowSpace);
        allocateSpace!`w`(_cols, geom.w - colSpace);
        int ypen = 0;
        foreach (y; 0 .. rowCount)
        {
            int h = row(y).result.h;
            int xpen = 0;
            foreach (x; 0 .. colCount)
            {
                int w = col(x).result.w;
                Box wb = Box(geom.x + xpen, geom.y + ypen, w, h);

                cell(x, y).wt.maybe.layout(wb);
                xpen += w + _colSpacing;
            }
            ypen += h + _rowSpacing;
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

    Put it between other items in LinearLayout to allow resizing its siblings.
    While dragging, it will resize previous and next children in layout.
*/
class Resizer : Widget
{
    /// Orientation: vertical to resize vertically, horizontal to resize horizontally
    @property Orientation orientation() { return _orientation; }

    @property bool validProps()
    {
        return _previousWidget && _nextWidget;
    }

    Signal!(void delegate(Resizer, ResizerEventType, int dragDelta)) resized;

    private
    {
        Orientation _orientation;
        Widget _previousWidget;
        Widget _nextWidget;
    }

    this(Orientation orient = Orientation.vertical)
    {
        _orientation = orient;
        trackHover = true;
    }

    override CursorType getCursorType(int x, int y)
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
    @property int delta() { return _delta; } // TODO: make setter?

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
                resized(this, ResizerEventType.startDragging, 0);
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
                resized(this, ResizerEventType.dragging, _delta - _dragStartDelta);
            return true;
        }
        if (event.action == MouseAction.move && trackHover)
        {
            if (!(state & State.hovered))
            {
                setState(State.hovered);
            }
            return true;
        }
        if (event.action == MouseAction.buttonUp && event.button == MouseButton.left ||
                !event.lbutton.isDown && _dragging)
        {
            resetState(State.pressed);
            if (_dragging)
            {
                _dragging = false;
                if (resized.assigned)
                    resized(this, ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        if (event.action == MouseAction.leave && trackHover)
        {
            resetState(State.hovered);
            return true;
        }
        if (event.action == MouseAction.cancel && trackHover)
        {
            resetState(State.hovered);
            resetState(State.pressed);
            if (_dragging)
            {
                _dragging = false;
                if (resized.assigned)
                    resized(this, ResizerEventType.endDragging, _delta - _dragStartDelta);
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
                    resized(this, ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        return false;
    }
}
