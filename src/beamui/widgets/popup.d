/**
This module contains popup widgets implementation.

Popups appear above other widgets inside window.

Useful for popup menus, notification popups, etc.

Synopsis:
---
import beamui.widgets.popup;
---

Copyright: Vadim Lopatin 2014-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.popup;

import beamui.platforms.common.platform;
import beamui.widgets.layouts;
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

struct PopupAnchor
{
    Widget widget;
    int x;
    int y;
    PopupAlign alignment = PopupAlign.center;
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
class Popup : LinearLayout
{
    PopupAnchor anchor;
    PopupClosePolicy closePolicy = PopupClosePolicy.onPressOutside;
    /// Modal popup - keypresses and mouse events can be routed to this popup only
    bool modal;

    /// Popup close signal
    Signal!(void delegate(Popup, bool byEvent)) popupClosed;

    this(Widget content, Window window)
    {
        id = "POPUP";
        _window = window;
        addChild(content);
    }

    /// Close and destroy popup
    void close()
    {
        popupClosed(this, closedByEvent);
        window.removePopup(this);
    }

    private bool closedByEvent;
    /// Called for mouse activity outside shown popup bounds
    bool onMouseEventOutside(MouseEvent event)
    {
        with (PopupClosePolicy)
        {
            if (closePolicy == none || visibility != Visibility.visible)
                return false;
            if (closePolicy & onPressOutside && event.action == MouseAction.buttonDown ||
                closePolicy & onReleaseOutside && event.action == MouseAction.buttonUp)
            {
                if (closePolicy & anchor && this.anchor.widget &&
                    this.anchor.widget.isPointInside(event.x, event.y))
                    return false;

                closedByEvent = true;
                scope (exit)
                    closedByEvent = false;

                close();
                return true;
            }
        }
        return false;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        // geom position here is (0, 0) and size is a natural size of the popup

        assert(_window);
        Box windowBox = Box(0, 0, _window.width, _window.height);

        // align by anchor and try to fit the window
        geom.w = min(geom.w, windowBox.w);
        geom.h = min(geom.h, windowBox.h);
        Point p;

        // aligned simply to a point
        if (anchor.alignment & PopupAlign.point)
        {
            p.x = anchor.x;
            p.y = anchor.y;
            if (anchor.alignment & PopupAlign.center)
            {
                // center around the point
                p.x -= geom.w / 2;
                p.y -= geom.h / 2;
            }
            else if (anchor.alignment & PopupAlign.above)
            {
                // raise up
                p.y -= geom.h;
            }
        }
        else // aligned to a widget (or the window if null)
        {
            Box anchorbox;
            if (anchor.widget !is null)
                anchorbox = anchor.widget.box;
            else
                anchorbox = windowBox;

            p = anchorbox.pos;
            if (anchor.alignment & PopupAlign.center)
            {
                // center around the center of anchor widget
                p.x = anchorbox.middlex - geom.w / 2;
                p.y = anchorbox.middley - geom.h / 2;
            }
            else
            {
                if (anchor.alignment & PopupAlign.below)
                {
                    p.y = anchorbox.y + anchorbox.h;
                }
                else if (anchor.alignment & PopupAlign.above)
                {
                    p.y = anchorbox.y - geom.h;
                }
                if (anchor.alignment & PopupAlign.right)
                {
                    p.x = anchorbox.x + anchorbox.w;
                }
            }
            if (anchor.alignment & PopupAlign.fitAnchorSize)
            {
                geom.w = max(geom.w, anchorbox.w);
            }
        }
        geom.pos = p;
        geom.moveToFit(windowBox);
        super.layout(geom);
    }
}
