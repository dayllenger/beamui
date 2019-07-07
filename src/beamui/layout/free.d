/**

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.free;

import beamui.style.computed_style : StyleProperty;
import beamui.widgets.widget;

/// Place children at specified coordinates
class FreeLayout : ILayout
{
    private Widget host;
    private Widget[] items;

    void onSetup(Widget host)
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
        with (StyleProperty) {
            if (p == left || p == right || p == top || p == bottom)
                host.requestLayout();
        }
    }

    void prepare(ref Buf!Widget list)
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
        foreach (item; items)
        {
            const st = item.style;
            const LayoutLength left = st.left;
            const LayoutLength top = st.top;
            const LayoutLength right = st.right;
            const LayoutLength bottom = st.bottom;
            Box b;
            b.size = item.natSize;
            if (left.isDefined)
                b.x = left.applyPercent(box.w);
            if (right.isDefined)
            {
                const x1 = box.w - right.applyPercent(box.w);
                if (left.isDefined)
                    b.w = x1 - b.x;
                else
                    b.x = x1 - b.w;
            }
            if (top.isDefined)
                b.y = top.applyPercent(box.h);
            if (bottom.isDefined)
            {
                const y1 = box.h - bottom.applyPercent(box.h);
                if (top.isDefined)
                    b.h = y1 - b.y;
                else
                    b.y = y1 - b.h;
            }
            b.x += box.x;
            b.y += box.y;
            b.w = max(b.w, 0);
            b.h = max(b.h, 0);
            item.layout(b);
        }
    }
}
