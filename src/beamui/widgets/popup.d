/**
Popup container widget.

Popups appear above other widgets inside window.

Useful for popup menus, notification popups, etc.

Copyright: Vadim Lopatin 2014-2016, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.popup;

import beamui.platforms.common.platform;
import beamui.widgets.widget;

/// Popup alignment option flags
enum PopupAlign : uint
{
    /// Center popup around anchor widget center
    center = 1,
    /// Place popup below anchor widget close to lower bound
    below = 2,
    /// Place popup above anchor widget close to top bound
    above = 4,
    /// Place popup below anchor widget close to right bound (when no space enough, align near left bound)
    right = 8,
    /// Align to specified point
    point = 16,
    /// If popup content size is less than anchor's size, increase it to anchor size
    fitAnchorSize = 32,
}

/// Popup close policy defines when we want to close popup
enum PopupClosePolicy : uint // TODO: on(Press|Release)OutsideParent, onEscapeKey
{
    /// Close manually
    none = 0,
    /// Close popup when mouse button pressed outside of its bounds
    onPressOutside = 1,
    /// Close popup when mouse button clicked outside of its bounds
    onReleaseOutside = 2,
    /// Exclude anchor widget from the above 'outside'
    anchor = 4,
}

/// Popup widget container
class Popup : Widget
{
    /// Modal popup - keypresses and mouse events can be routed to this popup only
    bool modal;

    Widget anchor;
    PopupAlign alignment = PopupAlign.center;
    Point point;

    protected Widget _content;

    final Widget wrap(Widget content)
    {
        _content = content;
        return this;
    }

    override protected int opApply(scope int delegate(size_t, Widget) callback)
    {
        if (const result = callback(0, _content))
            return result;
        return 0;
    }

    override protected Element createElement()
    {
        return new ElemPopup;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPopup el = fastCast!ElemPopup(element);
        el.modal = modal;

        el.anchor = anchor ? anchor.elementRef : el._anchor.init;
        el.alignment = alignment;
        el.point = point;

        el._content = mountChild(_content, 0, false);
    }
}

class ElemPopup : Element
{
    @property
    {
        bool modal() const { return _modal; }
        /// ditto
        void modal(bool flag)
        {
            if (_modal == flag)
                return;
            _modal = flag;
            invalidate();
        }

        void anchor(WeakRef!(const(Element)*) wr)
        {
            if (_anchor is wr)
                return;
            _anchor = wr;
            requestLayout();
        }

        PopupAlign alignment() const { return _alignment; }
        /// ditto
        void alignment(PopupAlign pa)
        {
            if (_alignment == pa)
                return;
            _alignment = pa;
            requestLayout();
        }

        Point point() const { return _point; }
        /// ditto
        void point(Point pt)
        {
            if (_point == pt)
                return;
            _point = pt;
            requestLayout();
        }
    }

    private
    {
        bool _modal;

        WeakRef!(const(Element)*) _anchor;
        PopupAlign _alignment;
        Point _point;

        Element _content;
    }
/+
    PopupClosePolicy closePolicy = PopupClosePolicy.onPressOutside;
    /// Should popup destroy the content widget on close?
    bool ownContent = true;

    /// Popup close signal
    Signal!(void delegate(bool byEvent)) onPopupClose;

    /// Close and destroy popup
    void close()
    {
        onPopupClose(closedByEvent);
        if (!ownContent)
        {
            content.parent = null;
            _hiddenChildren.remove(0);
        }
        window.removePopup(this);
    }

    private bool closedByEvent;
    /// Called for mouse activity outside shown popup bounds
    bool handleMouseEventOutside(MouseEvent event)
    {
        with (PopupClosePolicy)
        {
            if (closePolicy == none || visibility != Visibility.visible)
                return false;
            if (closePolicy & onPressOutside && event.action == MouseAction.buttonDown ||
                closePolicy & onReleaseOutside && event.action == MouseAction.buttonUp)
            {
                if (closePolicy & anchor)
                {
                    const Element a = this.anchor.get;
                    if (a && a.contains(event.x, event.y))
                        return false;
                }

                closedByEvent = true;
                scope (exit)
                    closedByEvent = false;

                close();
                return true;
            }
        }
        return false;
    }
+/
    override protected Boundaries computeBoundaries()
    {
        auto bs = super.computeBoundaries();
        if (_content)
        {
            _content.measure();
            bs.maximize(_content.boundaries);
        }
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        // geom position here is (0, 0) and size is a natural size of the popup

        Window win = window;
        assert(win);
        Box windowBox = Box(0, 0, win.width, win.height);

        // align by anchor and try to fit the window
        geom.w = min(geom.w, windowBox.w);
        geom.h = min(geom.h, windowBox.h);
        Point p;

        // aligned simply to a point
        if (_alignment & PopupAlign.point)
        {
            p = _point;
            if (_alignment & PopupAlign.center)
            {
                // center around the point
                p.x -= geom.w / 2;
                p.y -= geom.h / 2;
            }
            else if (_alignment & PopupAlign.above)
            {
                // raise up
                p.y -= geom.h;
            }
        }
        else // aligned to a widget
        {
            Box anchorbox;
            if (_anchor && *_anchor.get)
                anchorbox = Box(_anchor.get.origin, _anchor.get.box.size);
            else
                anchorbox = windowBox;

            p = anchorbox.pos;
            if (_alignment & PopupAlign.center)
            {
                // center around the center of anchor widget
                p.x = anchorbox.middleX - geom.w / 2;
                p.y = anchorbox.middleY - geom.h / 2;
            }
            else
            {
                if (_alignment & PopupAlign.below)
                {
                    p.y = anchorbox.y + anchorbox.h;
                }
                else if (_alignment & PopupAlign.above)
                {
                    p.y = anchorbox.y - geom.h;
                }
                if (_alignment & PopupAlign.right)
                {
                    p.x = anchorbox.x + anchorbox.w;
                }
            }
            if (_alignment & PopupAlign.fitAnchorSize)
            {
                geom.w = max(geom.w, anchorbox.w);
            }
        }
        geom.pos = p;
        geom.moveToFit(windowBox);

        super.layout(geom);
    }

    override protected void arrangeContent()
    {
        if (_content)
            _content.layout(innerBox);
    }

    override protected void drawContent(Painter pr)
    {
        if (_content)
            _content.draw(pr);
    }

    final override @property int childCount() const
    {
        return _content ? 1 : 0;
    }

    final override inout(Element) child(int index) inout
    {
        assert(_content);
        return _content;
    }

    final override void diffChildren(Element[] oldItems)
    {
        assert(oldItems.length <= 1);
        diffContent(oldItems.length > 0 ? oldItems[0] : null);
    }

    private void diffContent(Element old)
    {
        if (_content is old)
            return;

        if (old)
            old.parent = null;

        if (_content)
        {
            assert(_content.parent is this);
            _content.requestLayout();
        }
        else
            requestLayout();
    }
}
