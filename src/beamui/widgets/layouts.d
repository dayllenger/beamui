/**
This module contains common layouts implementations.

LinearLayout - either horizontal or vertical layout.

Row - shortcut for LinearLayout with horizontal orientation.

Column - shortcut for LinearLayout with vertical orientation.

FrameLayout - children occupy the same place, usually one one is visible at a time.

TableLayout - children aligned into rows and columns.

Resizer - widget to resize sibling widgets in a layout.

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
        LinearLayout orientation(Orientation value)
        {
            if (_orientation != value)
            {
                _orientation = value;
                requestLayout();
            }
            return this;
        }

        /// Space between items
        int spacing() const { return _spacing; }
        /// ditto
        LinearLayout spacing(int value)
        {
            if (_spacing != value)
            {
                _spacing = value;
                requestLayout();
            }
            return this;
        }
    }

    private
    {
        Orientation _orientation = Orientation.vertical;
        int _spacing = 6;

        /// Temporary layout item list
        Array!LayoutItem items;
    }

    /// Create with orientation
    this(Orientation orientation = Orientation.vertical)
    {
        _orientation = orientation;
    }

    /// Add a spacer
    LinearLayout addSpacer()
    {
        addChild(new Spacer);
        return this;
    }

    /// Add a resizer
    LinearLayout addResizer()
    {
        addChild(new Resizer);
        return this;
    }

    override Boundaries computeBoundaries()
    {
        // fill items array
        items.length = 0;
        foreach (i; 0 .. childCount)
        {
            Widget wt = child(i);
            if (wt.visibility != Visibility.gone)
                items ~= LayoutItem(wt);
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
        foreach (ref it; items)
        {
            Boundaries wbs = it.wt.computeBoundaries();
            it.bs = wbs;
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

        layed();
    }

    private void doLayout(string dim)(Box geom)
    {
        // TODO: layout weight, percent
        enum horiz = dim == `w`;

        // expand in secondary direction
        foreach (ref it; items)
        {
            static if (horiz)
            {
                it.fill = it.wt.fillsWidth;
                it.result.h = min(geom.h, it.bs.max.h);
                if (it.wt.widthDependsOnHeight)
                    it.bs.nat.w = it.wt.widthForHeight(it.result.h);
            }
            else
            {
                it.fill = it.wt.fillsHeight;
                it.result.w = min(geom.w, it.bs.max.w);
                if (it.wt.heightDependsOnWidth)
                    it.bs.nat.h = it.wt.heightForWidth(it.result.w);
            }
        }
        int space = spacing * (cast(int)items.length - 1);
        layoutItems!dim(items, mixin("geom." ~ dim) - space);
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
        foreach (ref it; items)
        {
            static if (horiz)
            {
                Box res = Box(geom.x + pen, geom.y, it.result.w, it.result.h);
                it.wt.layout(res);
                pen += res.w + _spacing;
            }
            else
            {
                Box res = Box(geom.x, geom.y + pen, it.result.w, it.result.h);
                it.wt.layout(res);
                pen += res.h + _spacing;
            }
        }
    }
}

void layoutItems(string dim)(ref Array!LayoutItem items, int parentSize)
{
    int extraSize = distribute!dim(items, parentSize);
    if (extraSize > 0)
    {
        int fillCount;
        foreach (const ref it; items)
        {
            if (it.fill)
                fillCount++;
        }
        if (fillCount > 0)
        {
            int perWidgetSize = extraSize / fillCount;
            foreach (ref it; items)
            {
                int diff = mixin("it.bs.max." ~ dim) -
                        mixin("it.result." ~ dim);
                // widget is bounded by max, treat as a fixed widget
                if (perWidgetSize > diff)
                {
                    mixin("it.result." ~ dim) = mixin("it.bs.max." ~ dim);
                    extraSize -= diff;
                    it.fill = false;
                    fillCount--;
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
                foreach (ref it; items)
                {
                    if (it.fill)
                    {
                        int sz = perWidgetSize;
                        // apply correction
                        if (i < front || i >= rear)
                            sz++;
                        i++;
                        mixin("it.result." ~ dim) += sz;
                    }
                }
            }
        }
    }
}

int distribute(string dim)(ref Array!LayoutItem items, int bounds)
{
    int min;
    int nat;
    foreach (const ref it; items)
    {
        min += mixin("it.bs.min." ~ dim);
        nat += mixin("it.bs.nat." ~ dim);
    }

    if (bounds >= nat)
    {
        foreach (ref it; items)
        {
            mixin("it.result." ~ dim) = mixin("it.bs.nat." ~ dim);
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
            auto it = &items[i];
            indices[i][0] = cast(int)i;
            indices[i][1] = mixin("it.bs.nat." ~ dim) - mixin("it.bs.min." ~ dim);
        }
        // sort indices by difference between min and nat sizes
        sort!((a, b) => a[1] < b[1])(indices[0 .. len]);

        // iterate
        int available = bounds - min;
        foreach (i; 0 .. len)
        {
            size_t j = indices[i][0];
            auto it = &items[j];
            int diff = indices[i][1];
            if (diff < available)
            {
                mixin("it.result." ~ dim) = mixin("it.bs.nat." ~ dim);
                available -= diff;
            }
            else
            {
                mixin("it.result." ~ dim) = mixin("it.bs.min." ~ dim) + available;
                available = 0;
            }
        }
        return 0;
    }
}

/// Arranges children horizontally
class Row : LinearLayout
{
    /// Create with spacing parameter
    this(int spacing = 6)
    {
        super(Orientation.horizontal);
        this.spacing = spacing;
    }
}

/// Arranges children vertically
class Column : LinearLayout
{
    /// Create with spacing parameter
    this(int spacing = 6)
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

        layed();
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
        TableLayout colCount(int count)
        {
            if (_colCount != count)
            {
                _colCount = count;
                requestLayout();
            }
            return this;
        }
        /// Number of rows
        int rowCount() const
        {
            return (childCount + (_colCount - 1)) / _colCount * _colCount;
        }

        /// Space between rows (vertical)
        int rowSpacing() const { return _rowSpacing; }
        /// ditto
        TableLayout rowSpacing(int value)
        {
            if (_rowSpacing != value)
            {
                _rowSpacing = value;
                requestLayout();
            }
            return this;
        }

        /// Space between columns (horizontal)
        int colSpacing() const { return _colSpacing; }
        /// ditto
        TableLayout colSpacing(int value)
        {
            if (_colSpacing != value)
            {
                _colSpacing = value;
                requestLayout();
            }
            return this;
        }
    }

    /// Set int property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setIntProperty", "int", "colCount"));

    private
    {
        Array!LayoutItem _cells;
        Array!LayoutItem _rows;
        Array!LayoutItem _cols;

        int _colCount = 1;

        int _rowSpacing = 6;
        int _colSpacing = 6;
    }

    this(int rowSpacing = 6, int colSpacing = 6)
    {
        _rowSpacing = rowSpacing;
        _colSpacing = colSpacing;
    }

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
            if (cell.wt)
                row.fill |= cell.wt.fillsHeight;
        }

        static void applyCellToCol(ref LayoutItem column, ref LayoutItem cell)
        {
            column.bs.maximizeWidth(cell.bs);
            column.bs.addHeight(cell.bs);
            column.result.w = column.bs.nat.w;
            if (cell.wt)
                column.fill |= cell.wt.fillsWidth;
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
        bs.min = bs.min + space;
        bs.nat = bs.nat + space;
        bs.max = bs.max + space;
        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        applyPadding(geom);

        layoutItems!`h`(_rows, geom.h - rowSpace);
        layoutItems!`w`(_cols, geom.w - colSpace);
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

        layed();
    }
}

/// Spacer to fill empty space in layouts
class Spacer : Widget
{
    this()
    {
        fillWH();
    }
}

/// Horizontal spacer to fill empty space in horizontal layouts
class HSpacer : Widget
{
    this()
    {
        fillW();
    }
}

/// Vertical spacer to fill empty space in vertical layouts
class VSpacer : Widget
{
    this()
    {
        fillH();
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
        if (validProps)
        {
            if (_orientation == Orientation.vertical)
            {
                fillsWidth = true;
                fillsHeight = false;
            }
            else
            {
                fillsWidth = false;
                fillsHeight = true;
            }
        }
        else
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

        layed();
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
