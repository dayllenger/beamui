/**
Linear layout implementation.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.layout.linear;

nothrow:

import std.math : isFinite;
import beamui.layout.alignment : ignoreAutoMargin;
import beamui.widgets.widget;

private struct LayoutItem
{
    Insets margins;
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
        Orientation orientation() const
        {
            return _orientation;
        }
        /// ditto
        void orientation(Orientation value)
        {
            if (_orientation != value)
            {
                _orientation = value;
                if (host)
                    host.requestLayout();
            }
        }
    }

    private
    {
        Orientation _orientation = Orientation.vertical;

        Element host;
        Element[] elements;
        /// Temporary layout item list
        Buf!LayoutItem items;
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
        items.clear();
    }

    void onStyleChange(StyleProperty p)
    {
    }

    void onChildStyleChange(StyleProperty p)
    {
        if (p == StyleProperty.justifySelf)
            host.requestLayout();
    }

    void prepare(ref Buf!Element list)
    {
        elements = list.unsafe_slice;
        items.resize(list.length);
    }

    Boundaries measure()
    {
        if (items.length == 0)
            return Boundaries.init;

        Boundaries bs;
        foreach (i; 0 .. items.length)
        {
            // measure items
            Element el = elements[i];
            el.measure();
            Boundaries wbs = el.boundaries;
            // add margins
            const Size msz = ignoreAutoMargin(el.style.margins).size;
            wbs.min += msz;
            wbs.nat += msz;
            wbs.max += msz;
            // compute container min-nat-max sizes
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
        return bs;
    }

    void arrange(Box box)
    {
        if (items.length > 0)
        {
            if (_orientation == Orientation.horizontal)
            {
                fillItemArray!(true)(box);
                doLayout!(true, `w`)(box);
            }
            else
            {
                fillItemArray!(false)(box);
                doLayout!(false, `h`)(box);
            }
        }
    }

    private void fillItemArray(bool horiz)(Box box)
    {
        foreach (i; 0 .. items.length)
        {
            LayoutItem item;

            // gather style properties for each item
            Element el = elements[i];
            const st = el.style;
            const minw = st.minWidth;
            const minh = st.minHeight;
            const maxw = st.maxWidth;
            const maxh = st.maxHeight;
            item.margins = ignoreAutoMargin(st.margins);
            item.fill = st.placeSelf[0] == AlignItem.stretch;

            // resolve percent sizes, combine them with boundaries
            Boundaries bs = el.boundaries;
            if (minw.isPercent)
                bs.min.w = minw.applyPercent(box.w);
            if (minh.isPercent)
                bs.min.h = minw.applyPercent(box.h);
            if (maxw.isPercent)
                bs.max.w = min(bs.max.w, maxw.applyPercent(box.w));
            if (maxh.isPercent)
                bs.max.h = min(bs.max.h, maxh.applyPercent(box.h));

            bs.max.w = max(bs.max.w, bs.min.w);
            bs.max.h = max(bs.max.h, bs.min.h);

            const msz = item.margins.size;
            // determine preferred main size, calculate cross size
            static if (horiz)
            {
                item.result.h = min(box.h, bs.max.h);
                if (el.dependentSize == DependentSize.width)
                {
                    bs.nat.w = el.widthForHeight(item.result.h - msz.h);
                }
                else
                {
                    const w = st.width;
                    if (w.isPercent)
                        bs.nat.w = w.applyPercent(box.w);
                }
            }
            else
            {
                item.result.w = min(box.w, bs.max.w);
                if (el.dependentSize == DependentSize.height)
                {
                    bs.nat.h = el.heightForWidth(item.result.w - msz.w);
                }
                else
                {
                    const h = st.height;
                    if (h.isPercent)
                        bs.nat.h = h.applyPercent(box.h);
                }
            }

            bs.nat.w = clamp(bs.nat.w, bs.min.w, bs.max.w);
            bs.nat.h = clamp(bs.nat.h, bs.min.h, bs.max.h);
            bs.min += msz;
            bs.nat += msz;
            bs.max += msz;
            assert(isFinite(bs.min.w) && isFinite(bs.min.h));
            assert(isFinite(bs.nat.w) && isFinite(bs.nat.h));
            item.bs = bs;

            items[i] = item;
        }
    }

    private void doLayout(bool horiz, string dim)(Box box)
    {
        allocateSpace!dim(items.unsafe_slice, box.pick!dim);

        // apply resizers
        foreach (i; 1 .. cast(int)items.length - 1)
        {
            if (auto resizer = cast(ElemResizer)elements[i])
            {
                resizer._orientation = _orientation;

                LayoutItem* left = &items.unsafe_slice[i - 1];
                LayoutItem* right = &items.unsafe_slice[i + 1];

                const lmin = left.bs.min.pick!dim;
                const rmin = right.bs.min.pick!dim;
                const lresult = left.result.pick!dim;
                const rresult = right.result.pick!dim;
                const delta = clamp(resizer.delta, -(lresult - lmin), rresult - rmin);
                resizer._delta = cast(int)delta;
                left.result.pick!dim = lresult + delta;
                right.result.pick!dim = rresult - delta;
            }
        }
        if (auto resizer = cast(ElemResizer)elements[0])
            resizer._orientation = _orientation;
        if (auto resizer = cast(ElemResizer)elements[$ - 1])
            resizer._orientation = _orientation;

        // lay out items
        float pen = 0;
        foreach (i; 0 .. items.length)
        {
            const Insets m = items[i].margins;
            const Size sz = items[i].result;
            Box b = Box(box.x + m.left, box.y + m.top, sz.w - m.width, sz.h - m.height);
            static if (horiz)
            {
                b.x += pen;
                pen += sz.w;
            }
            else
            {
                b.y += pen;
                pen += sz.h;
            }
            elements[i].layout(b);
        }
    }
}

private ref auto pick(string dim, T)(ref T s)
{
    return __traits(getMember, s, dim);
}

private struct TmpItem
{
    size_t index;
    float base = 0;
    float bound = 0;
}

private void allocateSpace(string dim)(LayoutItem[] items, float totalSize)
{
    float occupiedSize = 0;
    foreach (ref item; items)
    {
        occupiedSize += item.bs.nat.pick!dim;
        // set to natural size by default
        item.result.pick!dim = item.bs.nat.pick!dim;
    }

    if (totalSize > occupiedSize)
    {
        static Buf!TmpItem filling;
        filling.clear();

        // gather all filling items into the array
        foreach (i, ref const item; items)
        {
            const nat = item.bs.nat.pick!dim;
            const max = item.bs.max.pick!dim;
            if (item.fill)
                filling ~= TmpItem(i, nat, max);
        }
        // distribute space between them
        int flexibleItemCount = filling.length;
        float freeSpace = totalSize - occupiedSize;
        while (flexibleItemCount > 0 && freeSpace > 0)
        {
            const spacePerItem = freeSpace / flexibleItemCount;
            freeSpace = 0;
            foreach (ref item; filling.unsafe_slice)
            {
                if (item.base < item.bound)
                {
                    item.base += spacePerItem;
                    if (item.base > item.bound)
                    {
                        flexibleItemCount--;
                        freeSpace += item.base - item.bound;
                    }
                }
            }
        }
        // set final values
        foreach (item; filling[])
            items[item.index].result.pick!dim = min(item.base, item.bound);
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
    // dfmt off
    /// Orientation: vertical to resize vertically, horizontal to resize horizontally
    @property Orientation orientation() const { return _orientation; }
    /// Resizer offset from initial position
    @property int delta() const { return _delta; }
    // dfmt on

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
                applyFlags(StateFlags.pressed, true);
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
            applyFlags(StateFlags.hovered, true);
            return true;
        }
        if (event.action == MouseAction.buttonUp && event.button == MouseButton.left ||
                !event.alteredByButton(MouseButton.left) && _dragging)
        {
            applyFlags(StateFlags.pressed, false);
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
            applyFlags(StateFlags.hovered, false);
            return true;
        }
        if (event.action == MouseAction.cancel && allowsHover)
        {
            applyFlags(StateFlags.hovered | StateFlags.pressed, false);
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
            applyFlags(StateFlags.pressed, false);
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
