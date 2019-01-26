/**
Group Box widget.

Group box is linear layout with frame and caption for grouping controls.

Synopsis:
---
import beamui.widgets.groupbox;
---

Copyright: Vadim Lopatin 2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.groupbox;

import beamui.widgets.layouts;
import beamui.widgets.text;
import beamui.widgets.widget;

class GroupBox : LinearLayout
{
    private Label _caption;

    this(dstring caption = ""d, Orientation orientation = Orientation.vertical)
    {
        super(orientation);
        _caption = new Label(caption);
        _caption.bindSubItem(this, "caption");
        _caption.parent = this;
    }

    ~this()
    {
        eliminate(_caption);
    }

    override @property
    {
        /// Get groupbox caption text
        dstring text() const
        {
            return _caption.text;
        }
        /// Set caption to show
        void text(dstring s)
        {
            _caption.text = s;
            requestLayout();
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
        Insets cp = _caption.padding;
        int captFontHeight = _caption.font.height;
        _captionHeight = cp.top + cp.bottom + captFontHeight;

        DrawableRef upLeftDrawable = currentTheme.getDrawable("group_box_frame_up_left");
        DrawableRef upRightDrawable = currentTheme.getDrawable("group_box_frame_up_right");
        _topFrameHeight = max(!upLeftDrawable.isNull ? upLeftDrawable.height : 0,
                !upRightDrawable.isNull ? upRightDrawable.height : 0);
        _topFrameLeft = !upLeftDrawable.isNull ? upLeftDrawable.width : 0;
        _topFrameRight = !upRightDrawable.isNull ? upRightDrawable.width : 0;

        _frameLeft = _frameRight = _frameBottom = 0;
        DrawableRef bottomDrawable = currentTheme.getDrawable("group_box_frame_bottom");
        if (!bottomDrawable.isNull)
        {
            Insets dp = bottomDrawable.padding;
            _frameLeft = dp.left;
            _frameRight = dp.right;
            _frameBottom = dp.bottom;
        }
        _topHeight = max(_captionHeight, _topFrameHeight);
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        _caption.onThemeChanged();
    }

    override Boundaries computeBoundaries()
    {
        Boundaries bs = super.computeBoundaries();
        int cw = _caption.computeBoundaries().nat.w;
        // expand if the caption is bigger than the content
        // frame is already calculated
        int w = cw + _topFrameLeft + _topFrameRight;
        bs.nat.w = min(max(bs.nat.w, w), bs.max.w);
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        // layout the caption
        int cw = _caption.computeBoundaries().nat.w;
        int cwinv = geom.w - _topFrameLeft - _topFrameRight;
        Box b = Box(geom.x + _topFrameLeft, geom.y, min(cw, cwinv), _captionHeight);
        _caption.layout(b);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = box;

        _caption.onDraw(buf);

        // correct top of the frame to be exactly at the center of the caption
        int dh = 0;
        if (_topFrameHeight < _captionHeight)
            dh = (_captionHeight - _topFrameHeight) / 2;

        DrawableRef upLeftDrawable = currentTheme.getDrawable("group_box_frame_up_left");
        if (!upLeftDrawable.isNull)
        {
            upLeftDrawable.drawTo(buf, Box(b.x, b.y + dh, _topFrameLeft, _topHeight - dh));
        }
        DrawableRef upRightDrawable = currentTheme.getDrawable("group_box_frame_up_right");
        if (!upRightDrawable.isNull)
        {
            int cw = _caption.box.w;
            upRightDrawable.drawTo(buf, Box(b.x + _topFrameLeft + cw, b.y + dh, b.w - _topFrameLeft - cw, _topHeight - dh));
        }

        DrawableRef bottomDrawable = currentTheme.getDrawable("group_box_frame_bottom");
        if (!bottomDrawable.isNull)
        {
            bottomDrawable.drawTo(buf, Box(b.x, b.y + _topHeight, b.w, b.h - _topHeight));
        }
    }
}
