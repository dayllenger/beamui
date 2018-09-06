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

/// Popup behavior flags
enum PopupFlags : uint
{
    /// Close popup when mouse is moved outside this popup
    closeOnMouseMoveOutside = 1,
    /// Close popup when mouse button clicked outside of its bounds
    closeOnClickOutside = 2,
    /// Modal popup - keypresses and mouse events can be routed to this popup only
    modal = 4,
}

/// Popup widget container
class Popup : LinearLayout
{
    PopupAnchor anchor;
    PopupFlags flags;

    /// Popup close signal
    Signal!(void delegate(Popup)) popupClosed;

    this(Widget content, Window window)
    {
        id = "POPUP";
        _window = window;
        addChild(content);
    }

    /// Close and destroy popup
    void close()
    {
        popupClosed(this);
        window.removePopup(this);
    }

    /// Called for mouse activity outside shown popup bounds
    bool onMouseEventOutside(MouseEvent event)
    {
        if (visibility != Visibility.visible)
            return false;
        if (flags & PopupFlags.closeOnClickOutside)
        {
            if (event.action == MouseAction.buttonUp)
            {
                // clicked outside - close popup
                close();
                return true;
            }
        }
        if (flags & PopupFlags.closeOnMouseMoveOutside)
        {
            if (event.action == MouseAction.move || event.action == MouseAction.wheel)
            {
                int threshold = 3;
                if (event.x < _box.x - threshold || event.x > _box.x + _box.w + threshold ||
                        event.y < _box.y - threshold || event.y > _box.y + _box.h + threshold)
                {
                    Log.d("Closing popup due to PopupFlags.closeOnMouseMoveOutside flag");
                    close();
                    return false;
                }
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
