/**
Group Box widget.

Copyright: Vadim Lopatin 2016, dayllenger 2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.groupbox;

import beamui.widgets.text;
import beamui.widgets.widget;

abstract class GroupBoxBase : Panel
{
    abstract Widget buildCaption() out(w; w);

protected:

    override Element createElement()
    {
        return new ElemGroupBox;
    }

    override void updateElement(Element element)
    {
        super.updateElement(element);

        ElemGroupBox el = fastCast!ElemGroupBox(element);
        el.caption = mountChild(buildCaption(), 0, false);
    }
}

/** Group box is a panel (column usually) with a frame and a caption.

    CSS_nodes:
    ---
    GroupBox
    │   ╰── Label.caption
    ╰── *items*
    ---
*/
class GroupBox : GroupBoxBase
{
    /// Groupbox caption text
    dstring caption;

protected:

    static class State : WidgetState
    {
        Label caption;

        this()
        {
            // no need to recreate this widget every build
            caption = new Label;
            caption.key = "__caption__";
            caption.attributes["caption"];
            caption.namespace = null;
        }
    }

    override State createState()
    {
        return new State;
    }

    override void build()
    {
        use!State.caption.text = caption;
    }

    override Widget buildCaption()
    {
        return use!State.caption;
    }
}

class ElemGroupBox : ElemPanel
{
    @property
    {
        void caption(Element el)
        {
            assert(el);
            if (_caption is el)
                return;
            _hiddenChildren.replace(_caption, el);
            _caption = el;
        }
    }

    private
    {
        Element _caption;

        DrawableRef _drFrameTopLeft;
        DrawableRef _drFrameTopRight;
        DrawableRef _drFrameBottom;
    }

    override void handleCustomPropertiesChange()
    {
        auto pick = (string name) => DrawableRef(style.getPropertyValue!(Drawable, SpecialCSSType.image)(name, null));
        _drFrameTopLeft = pick("--frame-top-left");
        _drFrameTopRight = pick("--frame-top-right");
        _drFrameBottom = pick("--frame-bottom");
    }

    override @property
    {
        Insets padding() const
        {
            // get default padding
            Insets p = super.padding;
            // correct padding based on frame drawables and caption
            (cast()this).calcFrame(); // hack
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
        assert(_caption);
        const Insets cp = _caption.padding;
        const int captFontHeight = _caption.font.height;
        _captionHeight = cp.top + cp.bottom + captFontHeight;

        const upLeftW = !_drFrameTopLeft.isNull ? _drFrameTopLeft.width : 0;
        const upLeftH = !_drFrameTopLeft.isNull ? _drFrameTopLeft.height : 0;
        const upRightW = !_drFrameTopRight.isNull ? _drFrameTopRight.width : 0;
        const upRightH = !_drFrameTopRight.isNull ? _drFrameTopRight.height : 0;
        _topFrameHeight = max(upLeftH, upRightH);
        _topFrameLeft = upLeftW;
        _topFrameRight = upRightW;
        _topHeight = max(_captionHeight, _topFrameHeight);

        const Insets dp = !_drFrameBottom.isNull ? _drFrameBottom.padding : Insets(0);
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
        if (!_drFrameTopLeft.isNull)
        {
            _drFrameTopLeft.drawTo(pr, Box(b.x, b.y + dh, _topFrameLeft, _topHeight - dh));
        }
        if (!_drFrameTopRight.isNull)
        {
            const cw = _caption.box.w;
            _drFrameTopRight.drawTo(pr, Box(b.x + _topFrameLeft + cw, b.y + dh, b.w - _topFrameLeft - cw, _topHeight - dh));
        }
        if (!_drFrameBottom.isNull)
        {
            _drFrameBottom.drawTo(pr, Box(b.x, b.y + _topHeight, b.w, b.h - _topHeight));
        }
    }
}
