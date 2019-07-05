/**

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.free;

import beamui.widgets.widget;

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
            {
                item.cancelLayout();
                continue;
            }
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
