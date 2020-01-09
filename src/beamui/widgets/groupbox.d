/**
Group Box widget.

Group box is linear layout with frame and caption for grouping controls.

Copyright: Vadim Lopatin 2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.groupbox;

import beamui.widgets.text;
import beamui.widgets.widget;

class GroupBox : Panel
{
    private Label _caption;

    this(dstring caption = ""d)
    {
        _caption = new Label(caption);
        _caption.bindSubItem(this, "caption");
        _caption.state = State.parent;
        _caption.parent = this;
        _hiddenChildren.append(_caption);
    }

    this(dstring caption, Orientation orientation)
    {
        _caption = new Label(caption);
        _caption.bindSubItem(this, "caption");
        _caption.state = State.parent;
        _caption.parent = this;
        _hiddenChildren.append(_caption);
        style.display = orientation == Orientation.vertical ? "column" : "row";
    }

    override @property
    {
        /// Groupbox caption text to show
        dstring text() const
        {
            return _caption.text;
        }
        /// ditto
        void text(dstring s)
        {
            _caption.text = s;
        }

        Insets padding() const
        {
            // get default padding
            Insets p = super.padding;
            // correct padding based on frame drawables and caption
            (cast(GroupBox)this).calcFrame(); // hack
            p.top = max(p.top, _topHeight);
            p.left = max(p.left, _frameLeft);
            p.right = max(p.right, _frameRight);
            p.bottom = max(p.bottom, _frameBottom);
            return p;
        }
    }

    private
    {
        int _topFrameHeight;
        int _topFrameLeft;
        int _topFrameRight;
        int _captionHeight;
        int _topHeight;
        int _frameLeft;
        int _frameRight;
        int _frameBottom;
    }

    protected void calcFrame()
    {
        const Insets cp = _caption.padding;
        const int captFontHeight = _caption.font.height;
        _captionHeight = cp.top + cp.bottom + captFontHeight;

        const upLeftDrawable = currentTheme.getDrawable("group_box_frame_up_left");
        const upRightDrawable = currentTheme.getDrawable("group_box_frame_up_right");
        const int upLeftW = !upLeftDrawable.isNull ? upLeftDrawable.width : 0;
        const int upLeftH = !upLeftDrawable.isNull ? upLeftDrawable.height : 0;
        const int upRightW = !upRightDrawable.isNull ? upRightDrawable.width : 0;
        const int upRightH = !upRightDrawable.isNull ? upRightDrawable.height : 0;
        _topFrameHeight = max(upLeftH, upRightH);
        _topFrameLeft = upLeftW;
        _topFrameRight = upRightW;
        _topHeight = max(_captionHeight, _topFrameHeight);

        const bottomDrawable = currentTheme.getDrawable("group_box_frame_bottom");
        const Insets dp = !bottomDrawable.isNull ? bottomDrawable.padding : Insets(0);
        _frameLeft = dp.left;
        _frameRight = dp.right;
        _frameBottom = dp.bottom;
    }

    override protected void adjustBoundaries(ref Boundaries bs)
    {
        _caption.measure();
        // expand if the caption is bigger than the content
        // frame is already calculated
        const int cw = _caption.natSize.w;
        const int w = cw + _topFrameLeft + _topFrameRight - _frameLeft - _frameRight;
        bs.nat.w = max(bs.nat.w, w);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        // layout the caption
        const int cw = _caption.natSize.w;
        const int cwinv = geom.w - _topFrameLeft - _topFrameRight;
        Box b = Box(geom.x + _topFrameLeft, geom.y, min(cw, cwinv), _captionHeight);
        _caption.layout(b);
    }

    override protected void drawContent(Painter pr)
    {
        super.drawContent(pr);

        _caption.draw(pr);

        // correct top of the frame to be exactly at the center of the caption
        int dh;
        if (_topFrameHeight < _captionHeight)
            dh = (_captionHeight - _topFrameHeight) / 2;

        const b = box;
        DrawableRef upLeftDrawable = currentTheme.getDrawable("group_box_frame_up_left");
        if (!upLeftDrawable.isNull)
        {
            upLeftDrawable.drawTo(pr, Box(b.x, b.y + dh, _topFrameLeft, _topHeight - dh));
        }
        DrawableRef upRightDrawable = currentTheme.getDrawable("group_box_frame_up_right");
        if (!upRightDrawable.isNull)
        {
            int cw = _caption.box.w;
            upRightDrawable.drawTo(pr, Box(b.x + _topFrameLeft + cw, b.y + dh, b.w - _topFrameLeft - cw, _topHeight - dh));
        }

        DrawableRef bottomDrawable = currentTheme.getDrawable("group_box_frame_bottom");
        if (!bottomDrawable.isNull)
        {
            bottomDrawable.drawTo(pr, Box(b.x, b.y + _topHeight, b.w, b.h - _topHeight));
        }
    }
}
