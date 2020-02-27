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

alias ElemGroupBox = GroupBox;

class NgGroupBox : NgPanel
{
    dstring caption;

    static NgGroupBox make(dstring caption)
    {
        NgGroupBox w = arena.make!NgGroupBox;
        w.caption = caption;
        return w;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemGroupBox;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemGroupBox el = fastCast!ElemGroupBox(element);
        el._caption.text = caption;
    }
}

class GroupBox : Panel
{
    private Label _caption;

    this(dstring caption = ""d)
    {
        _caption = new Label(caption);
        _caption.isolateThisStyle();
        _caption.setAttribute("caption");
        _caption.state = State.parent;
        _caption.parent = this;
        _hiddenChildren.append(_caption);
    }

    this(dstring caption, Orientation orientation)
    {
        _caption = new Label(caption);
        _caption.isolateThisStyle();
        _caption.setAttribute("caption");
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
        float _topFrameHeight = 0;
        float _topFrameLeft = 0;
        float _topFrameRight = 0;
        float _captionHeight = 0;
        float _topHeight = 0;
        float _frameLeft = 0;
        float _frameRight = 0;
        float _frameBottom = 0;
    }

    protected void calcFrame()
    {
        const Insets cp = _caption.padding;
        const int captFontHeight = _caption.font.height;
        _captionHeight = cp.top + cp.bottom + captFontHeight;

        const upLeftDrawable = currentTheme.getDrawable("group_box_frame_up_left");
        const upRightDrawable = currentTheme.getDrawable("group_box_frame_up_right");
        const upLeftW = !upLeftDrawable.isNull ? upLeftDrawable.width : 0;
        const upLeftH = !upLeftDrawable.isNull ? upLeftDrawable.height : 0;
        const upRightW = !upRightDrawable.isNull ? upRightDrawable.width : 0;
        const upRightH = !upRightDrawable.isNull ? upRightDrawable.height : 0;
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

    override protected Boundaries computeBoundaries()
    {
        auto bs = super.computeBoundaries();
        _caption.measure();
        // expand if the caption is bigger than the content
        // frame is already calculated
        const cw = _caption.natSize.w;
        const w = cw + _topFrameLeft + _topFrameRight - _frameLeft - _frameRight;
        bs.nat.w = max(bs.nat.w, w);
        return bs;
    }

    override protected void arrangeContent()
    {
        super.arrangeContent();
        const geom = box;
        // layout the caption
        const cw = _caption.natSize.w;
        const cwinv = geom.w - _topFrameLeft - _topFrameRight;
        Box b = Box(geom.x + _topFrameLeft, geom.y, min(cw, cwinv), _captionHeight);
        _caption.layout(b);
    }

    override protected void drawContent(Painter pr)
    {
        super.drawContent(pr);

        _caption.draw(pr);

        // correct top of the frame to be exactly at the center of the caption
        float dh = 0;
        if (_topFrameHeight < _captionHeight)
            dh = snapToDevicePixels((_captionHeight - _topFrameHeight) / 2);

        const b = box;
        DrawableRef upLeftDrawable = currentTheme.getDrawable("group_box_frame_up_left");
        if (!upLeftDrawable.isNull)
        {
            upLeftDrawable.drawTo(pr, Box(b.x, b.y + dh, _topFrameLeft, _topHeight - dh));
        }
        DrawableRef upRightDrawable = currentTheme.getDrawable("group_box_frame_up_right");
        if (!upRightDrawable.isNull)
        {
            const cw = _caption.box.w;
            upRightDrawable.drawTo(pr, Box(b.x + _topFrameLeft + cw, b.y + dh, b.w - _topFrameLeft - cw, _topHeight - dh));
        }

        DrawableRef bottomDrawable = currentTheme.getDrawable("group_box_frame_bottom");
        if (!bottomDrawable.isNull)
        {
            bottomDrawable.drawTo(pr, Box(b.x, b.y + _topHeight, b.w, b.h - _topHeight));
        }
    }
}
