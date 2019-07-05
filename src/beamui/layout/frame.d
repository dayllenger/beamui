/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.layout.frame;

import beamui.widgets.widget;

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
