/**
Linear layout implementation.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.layout.linear;

nothrow:

import beamui.layout.alignment : ignoreAutoMargin;
import beamui.widgets.widget;

private struct LayoutItem
{
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

        // fill item array
        Boundaries bs;
        foreach (i; 0 .. items.length)
        {
            LayoutItem item;
            // measure items
            Element el = elements[i];
            el.measure();
            Boundaries wbs = el.boundaries;
            // add margins
            const Size msz = ignoreAutoMargin(el.style.margins).size;
            wbs.min += msz;
            wbs.nat += msz;
            wbs.max += msz;
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
            items[i] = item;
        }
        return bs;
    }

    void arrange(Box box)
    {
        if (items.length > 0)
        {
            if (_orientation == Orientation.horizontal)
                doLayout!(true, `w`)(box);
            else
                doLayout!(false, `h`)(box);
        }
    }

    private void doLayout(bool horiz, string dim)(Box geom)
    {
        // setup fill
        foreach (i; 0 .. items.length)
        {
            LayoutItem* item = &items.unsafe_ref(i);
            const st = elements[i].style;
            const Insets m = ignoreAutoMargin(st.margins);

            item.fill = st.placeSelf[0] == AlignItem.stretch;
            static if (horiz)
            {
                item.result.h = min(geom.h, item.bs.max.h);
                if (elements[i].dependentSize == DependentSize.width)
                    item.bs.nat.w = elements[i].widthForHeight(item.result.h - m.height) + m.width;
            }
            else
            {
                item.result.w = min(geom.w, item.bs.max.w);
                if (elements[i].dependentSize == DependentSize.height)
                    item.bs.nat.h = elements[i].heightForWidth(item.result.w - m.width) + m.height;
            }
        }
        allocateSpace!dim(items.unsafe_slice, geom.pick!dim);

        // apply resizers
        foreach (i; 1 .. cast(int)items.length - 1)
        {
            if (auto resizer = cast(ElemResizer)elements[i])
            {
                resizer._orientation = _orientation;

                LayoutItem* left  = &items.unsafe_slice[i - 1];
                LayoutItem* right = &items.unsafe_slice[i + 1];

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
        if (auto resizer = cast(ElemResizer)elements[0])
            resizer._orientation = _orientation;
        if (auto resizer = cast(ElemResizer)elements[$ - 1])
            resizer._orientation = _orientation;

        // lay out items
        float pen = 0;
        foreach (i; 0 .. items.length)
        {
            const Insets m = ignoreAutoMargin(elements[i].style.margins);
            const Size sz = items[i].result;
            Box b = Box(geom.x + m.left, geom.y + m.top, sz.w - m.width, sz.h - m.height);
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
