/**
Linear layout implementation.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.layout.linear;

nothrow:

import std.container.array;
import beamui.widgets.widget;

/// Helper for layouts
struct LayoutItem
{
    Element el;

    Boundaries bs;
    bool fill;
    Size result;
}

/// Arranges items either vertically or horizontally
class LinearLayout : ILayout
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
                host.maybe.requestLayout();
            }
        }
    }

    private
    {
        Orientation _orientation = Orientation.vertical;

        Element host;
        /// Temporary layout item list
        Array!LayoutItem items;
    }

    /// Create with orientation
    this(Orientation orientation = Orientation.vertical)
    {
        _orientation = orientation;
    }

    void onSetup(Element host)
    {
        this.host = host;
    }

    void onDetach()
    {
        host = null;
        items.length = 0;
    }

    void onStyleChange(StyleProperty p)
    {
        if (p == StyleProperty.rowGap || p == StyleProperty.columnGap)
            host.requestLayout();
    }

    void onChildStyleChange(StyleProperty p)
    {
        if (p == StyleProperty.alignment || p == StyleProperty.stretch)
            host.requestLayout();
    }

    void prepare(ref Buf!Element list)
    {
        items.length = 0;
        // fill items array
        foreach (el; list.unsafe_slice)
        {
            items ~= LayoutItem(el);
        }
    }

    Boundaries measure()
    {
        if (items.length == 0)
            return Boundaries();

        // has items
        Boundaries bs;
        foreach (ref item; items)
        {
            item.el.measure();
            Boundaries wbs = item.el.boundaries;
            // add margins
            Size m = item.el.style.margins.size;
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
            const gap = host.style.columnGap.applyPercent(bs.nat.w);
            const space = gap * (cast(int)items.length - 1);
            bs.max.w += space;
            bs.nat.w += space;
            bs.min.w += space;
        }
        else
        {
            const gap = host.style.rowGap.applyPercent(bs.nat.h);
            const space = gap * (cast(int)items.length - 1);
            bs.max.h += space;
            bs.nat.h += space;
            bs.min.h += space;
        }
        return bs;
    }

    void arrange(Box box)
    {
        if (items.length > 0)
        {
            if (_orientation == Orientation.horizontal)
                doLayout!`w`(box);
            else
                doLayout!`h`(box);
        }
    }

    private void doLayout(string dim)(Box geom)
    {
        enum horiz = dim == `w`;

        // setup fill
        foreach (ref item; items)
        {
            const wstyle = item.el.style;
            const stretch = wstyle.stretch;
            const bool main = stretch == Stretch.main || stretch == Stretch.both;
            const bool cross = stretch == Stretch.cross || stretch == Stretch.both;
            const Insets m = wstyle.margins;
            static if (horiz)
            {
                item.fill = main;
                item.result.h = cross ? min(geom.h, item.bs.max.h) : item.bs.nat.h;
                if (item.el.dependentSize == DependentSize.width)
                    item.bs.nat.w = item.el.widthForHeight(item.result.h - m.height) + m.width;
            }
            else
            {
                item.fill = main;
                item.result.w = cross ? min(geom.w, item.bs.max.w) : item.bs.nat.w;
                if (item.el.dependentSize == DependentSize.height)
                    item.bs.nat.h = item.el.heightForWidth(item.result.w - m.width) + m.height;
            }
        }
        static if (horiz)
            const spacing = host.style.columnGap.applyPercent(geom.w);
        else
            const spacing = host.style.rowGap.applyPercent(geom.h);
        float gaps = spacing * (cast(int)items.length - 1);
        allocateSpace!dim(items, geom.pick!dim - gaps);
        // apply resizers
        foreach (i; 1 .. cast(int)items.length - 1)
        {
            if (auto resizer = cast(ElemResizer)items[i].el)
            {
                resizer._orientation = _orientation;

                LayoutItem* left  = &items[i - 1];
                LayoutItem* right = &items[i + 1];

                const lmin = left.bs.min.pick!dim;
                const rmin = right.bs.min.pick!dim;
                const lresult = left.result.pick!dim;
                const rresult = right.result.pick!dim;
                const delta = clamp(resizer.delta, -(lresult - lmin), rresult - rmin);
                resizer._delta = cast(int)delta;
                left.result.pick!dim  = lresult + delta;
                right.result.pick!dim = rresult - delta;
            }
        }
        if (auto resizer = cast(ElemResizer)items.front.el)
            resizer._orientation = _orientation;
        if (auto resizer = cast(ElemResizer)items.back.el)
            resizer._orientation = _orientation;
        // lay out items
        float pen = 0;
        foreach (ref item; items)
        {
            const wstyle = item.el.style;
            const Insets m = wstyle.margins;
            const Size sz = item.result;
            Box res = Box(geom.x + m.left, geom.y + m.top, geom.w, geom.h);
            static if (horiz)
            {
                res.x += pen;
                res = alignBox(res, sz, wstyle.valign);
            }
            else
            {
                res.y += pen;
                res = alignBox(res, sz, wstyle.halign);
            }
            res.w -= m.width;
            res.h -= m.height;
            item.el.layout(res);
            pen += sz.pick!dim + spacing;
        }
    }
}

private ref auto pick(string dim, T)(ref T s)
{
    return __traits(getMember, s, dim);
}

void allocateSpace(string dim)(ref Array!LayoutItem items, float totalSize)
{
    float min = 0;
    float nat = 0;
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
    float bound = 0;
    float base = 0;
}
private Item[] storage;

private void expand(string dim)(ref Array!LayoutItem items, const float extraSize)
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

private void expandImpl(Item[] filling, float extraSize)
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
    float volume = 0;
    int end;
    for (end = 1; end < filling.length; end++)
    {
        float v = 0;
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

private void addSpaceToItems(Item[] items, const int skip, float extraSize)
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

private void addSpaceEvenly(Item[] items, const float extraSize)
{
    assert(extraSize > 0);

    const divisor = cast(int)items.length;
    if (divisor == 0)
        return;

    const perItemSize = extraSize / divisor;
    foreach (ref item; items)
    {
        item.base += perItemSize;
    }
}

private void shrink(string dim)(ref Array!LayoutItem items, const float available)
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

/// Spacer to fill empty space in layouts
class Spacer : Widget
{
}

class Resizer : Widget
{
    this()
    {
        allowsHover = true;
    }

    override protected Element createElement()
    {
        return new ElemResizer;
    }
}

enum ResizerEventType
{
    startDragging,
    dragging,
    endDragging
}

/** Resizer control.

    Put it between other items in a panel with `row` or `column` layout kind
    to enable resizing of its siblings. While dragging, it will resize previous
    and next children in the layout.

    Also it can be utilized per se, by connecting to `onResize` signal.
*/
class ElemResizer : Element
{
    /// Orientation: vertical to resize vertically, horizontal to resize horizontally
    @property Orientation orientation() const { return _orientation; }

    /// Resizer offset from initial position
    @property int delta() const { return _delta; }

    Signal!(void delegate(ResizerEventType, int dragDelta)) onResize;

    private Orientation _orientation;

    this(Orientation orient = Orientation.vertical)
    {
        _orientation = orient;
        allowsHover = true;
    }

    override CursorType getCursorType(float x, float y) const
    {
        if (_orientation == Orientation.vertical)
            return CursorType.resizeRow;
        else
            return CursorType.resizeCol;
    }

    private
    {
        bool _dragging;
        int _dragStartPosition;
        int _dragStartDelta;
        int _delta;
    }

    override bool handleMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            if (!event.doubleClick)
            {
                applyState(State.pressed, true);
                _dragging = true;
                _dragStartPosition = _orientation == Orientation.vertical ? event.y : event.x;
                _dragStartDelta = _delta;
                if (onResize.assigned)
                    onResize(ResizerEventType.startDragging, 0);
            }
            else
            {
                if (_delta != 0)
                {
                    const delta = -_delta;
                    _delta = 0;
                    requestLayout();
                    if (onResize.assigned)
                    {
                        onResize(ResizerEventType.startDragging, 0);
                        onResize(ResizerEventType.dragging, delta);
                        onResize(ResizerEventType.endDragging, 0);
                    }
                }
            }
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
            const pos = _orientation == Orientation.vertical ? event.y : event.x;
            const delta = _dragStartDelta + pos - _dragStartPosition;
            if (_delta != delta)
            {
                _delta = delta;
                requestLayout();
                if (onResize.assigned)
                    onResize(ResizerEventType.dragging, delta - _dragStartDelta);
            }
            return true;
        }
        if (event.action == MouseAction.move && allowsHover)
        {
            applyState(State.hovered, true);
            return true;
        }
        if (event.action == MouseAction.buttonUp && event.button == MouseButton.left ||
            !event.alteredByButton(MouseButton.left) && _dragging)
        {
            applyState(State.pressed, false);
            if (_dragging)
            {
                _dragging = false;
                if (onResize.assigned)
                    onResize(ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        if (event.action == MouseAction.leave && allowsHover)
        {
            applyState(State.hovered, false);
            return true;
        }
        if (event.action == MouseAction.cancel && allowsHover)
        {
            applyState(State.hovered | State.pressed, false);
            if (_dragging)
            {
                _dragging = false;
                if (onResize.assigned)
                    onResize(ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        if (event.action == MouseAction.cancel)
        {
            applyState(State.pressed, false);
            if (_dragging)
            {
                _dragging = false;
                if (onResize.assigned)
                    onResize(ResizerEventType.endDragging, _delta - _dragStartDelta);
            }
            return true;
        }
        return false;
    }
}
