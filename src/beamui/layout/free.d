/**
Free layout places each item independently.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.free;

import beamui.core.collections : Buf;
import beamui.core.geometry;
import beamui.core.math;
import beamui.core.units : LayoutLength;
import beamui.layout.alignment : AlignItem, alignItem, ignoreAutoMargin, Segment;
import beamui.style.computed_style : StyleProperty;
import beamui.widgets.widget : Element, ILayout;

/// Places items into specified rooms
class FreeLayout : ILayout
{
    private Element host;
    private Element[] items;

    void onSetup(Element host)
    {
        this.host = host;
    }

    void onDetach()
    {
        host = null;
        items = null;
    }

    void onStyleChange(StyleProperty p)
    {
        if (p == StyleProperty.justifyItems || p == StyleProperty.alignItems)
            host.requestLayout();
    }

    void onChildStyleChange(StyleProperty p)
    {
        switch (p) with (StyleProperty)
        {
        case left:
        case top:
        case right:
        case bottom:
        case justifySelf:
        case alignSelf:
            host.requestLayout();
            break;
        default:
            break;
        }
    }

    void prepare(ref Buf!Element list)
    {
        items = list.unsafe_slice;
    }

    Boundaries measure()
    {
        Boundaries bs;
        foreach (item; items)
        {
            item.measure();
            bs.maximize(item.boundaries);
        }
        return bs;
    }

    void arrange(Box box)
    {
        AlignItem[2] defaultAlignment = host.style.placeItems;
        foreach (item; items)
        {
            const st = item.style;
            const LayoutLength left = st.left;
            const LayoutLength top = st.top;
            const LayoutLength right = st.right;
            const LayoutLength bottom = st.bottom;
            const Insets m = ignoreAutoMargin(st.margins);
            const bs = item.boundaries;

            Box room = Box(0, 0, bs.nat.w, bs.nat.h);
            if (left.isDefined)
                room.x = left.applyPercent(box.w);
            if (right.isDefined)
            {
                const x1 = box.w - right.applyPercent(box.w);
                if (left.isDefined)
                    room.w = max(x1 - room.x, 0);
                else
                    room.x = x1 - bs.nat.w - m.width;
            }
            if (top.isDefined)
                room.y = top.applyPercent(box.h);
            if (bottom.isDefined)
            {
                const y1 = box.h - bottom.applyPercent(box.h);
                if (top.isDefined)
                    room.h = max(y1 - room.y, 0);
                else
                    room.y = y1 - bs.nat.h - m.height;
            }

            AlignItem[2] a = st.placeSelf;
            if (a[0] == AlignItem.unspecified)
                a[0] = defaultAlignment[0];
            if (a[1] == AlignItem.unspecified)
                a[1] = defaultAlignment[1];
            const hseg = alignItem(Segment(0, bs.nat.w), Segment(room.x + m.left, room.w - m.width), a[0]);
            const vseg = alignItem(Segment(0, bs.nat.h), Segment(room.y + m.top, room.h - m.height), a[1]);
            Box b;
            b.x = hseg.pos + box.x;
            b.y = vseg.pos + box.y;
            b.w = clamp(hseg.size, bs.min.w, bs.max.w);
            b.h = clamp(vseg.size, bs.min.h, bs.max.h);
            item.layout(b);
        }
    }
}
