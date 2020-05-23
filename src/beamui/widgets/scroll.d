/**
Base for widgets with scrolling capabilities.

Synopsis:
---
// Scroll view example

// Assume we have some parent widget
auto frame = new Panel;

// We create a scroll area with no horizontal scrollbar and with
// an automatically visible/hidden vertical scrollbar.
auto scroll = new ScrollArea(ScrollBarMode.hidden, ScrollBarMode.automatic);

// ScrollArea may have only one child. To put a single widget (e.g. an image)
// into the scroll, you can assign it to `contentWidget` directly. Otherwise,
// you will need a container.
auto scrollContent = new Panel;

// The widget hierarchy should be like:
// frame -> ScrollArea -> contents
frame.add(scroll);
scroll.contentWidget = scrollContent;

// Now, add some content
with (scrollContent) {
    style.display = "column";
    style.padding = 10;
    add(new Label("Some buttons"d),
        new Button("Close"d, "fileclose"),
        new Button("Open"d, "fileopen"),
        new Label("And checkboxes"d),
        new CheckBox("CheckBox 1"d),
        new CheckBox("CheckBox 2"d),
        new CheckBox("CheckBox 3"d),
        new CheckBox("CheckBox 4"d).setChecked(true),
        new CheckBox("CheckBox 5"d).setChecked(true),
    );
}
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.scroll;

import beamui.layout.alignment : alignBox;
import beamui.widgets.scrollbar;
import beamui.widgets.widget;

/// Scroll bar visibility mode
enum ScrollBarMode
{
    /// Always hidden
    hidden,
    /// Always visible
    visible,
    /// Automatically show/hide scrollbar depending on content size
    automatic,
    /// Scrollbar is provided by external control outside this widget
    external,
}

/// Scroll action codes for scrolling areas
enum ScrollAreaAction
{
    left,
    right,
    pageLeft,
    pageRight,
    leftEdge,
    rightEdge,
    up,
    down,
    pageUp,
    pageDown,
    topEdge,
    bottomEdge,
}

/** Abstract scrollable widget (used as a base for other widgets with scrolling).

    Provides scroll bars and basic scrolling functionality.
 */
abstract class ScrollAreaBase : Widget
{
    /// Visibility policy for the horizontal scrollbar
    ScrollBarMode hscrollbarMode;
    /// Visibility policy for the vertical scrollbar
    ScrollBarMode vscrollbarMode;

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemScrollAreaBase el = fastCast!ElemScrollAreaBase(element);
        ElemScrollBar hbar, vbar;
        if (hscrollbarMode != ScrollBarMode.hidden)
        {
            ScrollBar sb = render!ScrollBar;
            sb.namespace = null;
            sb.orientation = Orientation.horizontal;
            sb.data = el._hdata;
            sb.onScroll = &el.handleHScroll;
            hbar = fastCast!ElemScrollBar(mountChild(sb, el, 0));
            el.addChild(hbar);
        }
        if (vscrollbarMode != ScrollBarMode.hidden)
        {
            ScrollBar sb = render!ScrollBar;
            sb.namespace = null;
            sb.orientation = Orientation.vertical;
            sb.data = el._vdata;
            sb.onScroll = &el.handleVScroll;
            vbar = fastCast!ElemScrollBar(mountChild(sb, el, 1));
            el.addChild(vbar);
        }
        el.setScrollBars(hscrollbarMode, vscrollbarMode, hbar, vbar);
    }
}

abstract class ElemScrollAreaBase : ElemGroup
{
    @property
    {
        ScrollBarMode hscrollbarMode() const { return _hmode; }
        /// ditto
        protected void hscrollbarMode(ScrollBarMode m)
        {
            if (_hmode == m)
                return;
            _hmode = m;
            requestLayout();
        }

        ScrollBarMode vscrollbarMode() const { return _vmode; }
        /// ditto
        protected void vscrollbarMode(ScrollBarMode m)
        {
            if (_vmode == m)
                return;
            _vmode = m;
            requestLayout();
        }

        /// Horizontal scrollbar control. Can be `null`
        const(ElemScrollBar) hscrollbar() const { return _hscrollbar; }

        /// Vertical scrollbar control. Can be `null`
        const(ElemScrollBar) vscrollbar() const { return _vscrollbar; }

        /// Inner area, excluding additional controls like scrollbars
        ref const(Box) clientBox() const { return _clientBox; }
        /// ditto
        protected ref Box clientBox() { return _clientBox; }

        /// Scroll offset in pixels
        Point scrollPos() const { return _scrollPos; }
        /// ditto
        protected ref Point scrollPos() { return _scrollPos; }

        /// Get full content size in pixels
        abstract Size fullContentSize() const;

        /// Get full content size in pixels including widget borders / padding
        Size fullContentSizeWithBorders() const
        {
            return fullContentSize + padding.size;
        }
    }

    private
    {
        alias Mode = ScrollBarMode;

        Mode _hmode;
        Mode _vmode;
        ElemScrollBar _hscrollbar;
        ElemScrollBar _vscrollbar;
        ScrollData _hdata;
        ScrollData _vdata;
        uint _hlineStep;
        uint _vlineStep;
        Size _sbsz;

        Box _clientBox;
        Point _scrollPos;
    }

    this()
    {
        _hdata = new ScrollData;
        _vdata = new ScrollData;
    }

    private void setScrollBars(ScrollBarMode hm, ScrollBarMode vm, ElemScrollBar hbar, ElemScrollBar vbar)
    {
        if (_hmode == hm && _vmode == vm && _hscrollbar is hbar && _vscrollbar is vbar)
            return;

        _hmode = hm;
        _vmode = vm;
        _hscrollbar = hbar;
        _vscrollbar = vbar;
        if (hbar)
        {
            hbar.lineStep = _hlineStep;
            updateHScrollBar(_hdata);
        }
        if (vbar)
        {
            vbar.lineStep = _vlineStep;
            updateVScrollBar(_vdata);
        }
        requestLayout();
    }

    void setScrollSteps(uint hor, uint vert)
    {
        _hlineStep = hor;
        _vlineStep = vert;
        if (auto h = _hscrollbar)
            h.lineStep = hor;
        if (auto v = _vscrollbar)
            v.lineStep = vert;
    }

    final void scrollLeft()
    {
        if (auto h = _hscrollbar)
            h.triggerAction(ScrollAction.lineUp);
    }

    final void scrollRight()
    {
        if (auto h = _hscrollbar)
            h.triggerAction(ScrollAction.lineDown);
    }

    final void scrollPageLeft()
    {
        if (auto h = _hscrollbar)
            h.triggerAction(ScrollAction.pageUp);
    }

    final void scrollPageRight()
    {
        if (auto h = _hscrollbar)
            h.triggerAction(ScrollAction.pageDown);
    }

    final void scrollLeftEdge()
    {
        if (auto h = _hscrollbar)
            h.moveTo(0);
    }

    final void scrollRightEdge()
    {
        if (auto h = _hscrollbar)
            h.moveTo(_hdata.range);
    }

    final void scrollUp()
    {
        if (auto v = _vscrollbar)
            v.triggerAction(ScrollAction.lineUp);
    }

    final void scrollDown()
    {
        if (auto v = _vscrollbar)
            v.triggerAction(ScrollAction.lineDown);
    }

    final void scrollPageUp()
    {
        if (auto v = _vscrollbar)
            v.triggerAction(ScrollAction.pageUp);
    }

    final void scrollPageDown()
    {
        if (auto v = _vscrollbar)
            v.triggerAction(ScrollAction.pageDown);
    }

    final void scrollTopEdge()
    {
        if (auto v = _vscrollbar)
            v.moveTo(0);
    }

    final void scrollBottomEdge()
    {
        if (auto v = _vscrollbar)
            v.moveTo(_vdata.range);
    }

    final void scroll(ScrollAreaAction action)
    {
        if (auto h = _hscrollbar)
        {
            switch (action) with (ScrollAreaAction)
            {
                case left:        h.triggerAction(ScrollAction.lineUp);   return;
                case right:       h.triggerAction(ScrollAction.lineDown); return;
                case pageLeft:    h.triggerAction(ScrollAction.pageUp);   return;
                case pageRight:   h.triggerAction(ScrollAction.pageDown); return;
                case leftEdge:    h.moveTo(0); return;
                case rightEdge:   h.moveTo(_hdata.range); return;
                default: break;
            }
        }
        if (auto v = _vscrollbar)
        {
            switch (action) with (ScrollAreaAction)
            {
                case up:           v.triggerAction(ScrollAction.lineUp);   return;
                case down:         v.triggerAction(ScrollAction.lineDown); return;
                case pageUp:       v.triggerAction(ScrollAction.pageUp);   return;
                case pageDown:     v.triggerAction(ScrollAction.pageDown); return;
                case topEdge:      v.moveTo(0); return;
                case bottomEdge:   v.moveTo(_vdata.range); return;
                default: break;
            }
        }
    }

    /// Process horizontal scroll event. Return false to discard the event
    protected bool handleHScroll(ScrollAction action, float position)
    {
        return true;
    }

    /// Process vertical scroll event. Return false to discard the event
    protected bool handleVScroll(ScrollAction action, float position)
    {
        return true;
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        if (event.deltaX != 0 && _hscrollbar)
        {
            const a = event.deltaX > 0 ? ScrollAction.lineDown : ScrollAction.lineUp;
            _hscrollbar.triggerAction(a);
            return true;
        }
        if (event.deltaY != 0)
        {
            const a = event.deltaY > 0 ? ScrollAction.lineDown : ScrollAction.lineUp;
            if (event.keyMods == KeyMods.shift)
            {
                if (_hscrollbar)
                {
                    _hscrollbar.triggerAction(a);
                    return true;
                }
            }
            else if (event.noKeyMods)
            {
                if (_vscrollbar)
                {
                    _vscrollbar.triggerAction(a);
                    return true;
                }
            }
        }
        return super.handleWheelEvent(event);
    }

    void makeBoxVisible(Box b, bool alignHorizontally = true, bool alignVertically = true)
    {
        const visible = Box(_scrollPos, _clientBox.size);
        if (visible.contains(b))
            return;

        const oldp = _scrollPos;
        if (alignHorizontally)
        {
            if (visible.x + visible.w < b.x + b.w)
                _scrollPos.x = b.x + b.w - visible.w;
            if (b.x < visible.x)
                _scrollPos.x = b.x;
        }
        if (alignVertically)
        {
            if (visible.y + visible.h < b.y + b.h)
                _scrollPos.y = b.y + b.h - visible.h;
            if (b.y < visible.y)
                _scrollPos.y = b.y;
        }
        if (_scrollPos != oldp)
            requestLayout();
    }

    override protected Boundaries computeBoundaries()
    {
        // do first measure to get scrollbar widths
        if (_hscrollbar && (_hmode == Mode.visible || _hmode == Mode.automatic))
        {
            _hscrollbar.measure();
            _sbsz.h = _hscrollbar.natSize.h;
        }
        if (_vscrollbar && (_vmode == Mode.visible || _vmode == Mode.automatic))
        {
            _vscrollbar.measure();
            _sbsz.w = _vscrollbar.natSize.w;
        }
        return Boundaries(_sbsz, _sbsz);
    }

    override protected void arrangeContent()
    {
        const inner = innerBox;
        const sz = inner.size;
        updateScrollBarsVisibility(sz);
        bool needHScroll;
        bool needVScroll;
        needToShowScrollbars(needHScroll, needVScroll);

        // client area
        _clientBox = inner;
        if (needHScroll)
            _clientBox.h -= _sbsz.h;
        if (needVScroll)
            _clientBox.w -= _sbsz.w;

        adjustClientBox(_clientBox);

        // update scrollbar button positions before laying out
        updateScrollBars();

        // lay out scrollbars
        const vsbw = needVScroll ? _sbsz.w : 0;
        const hsbh = needHScroll ? _sbsz.h : 0;
        if (needHScroll)
        {
            Box b = Box(inner.x, inner.y + inner.h - _sbsz.h, sz.w - vsbw, _sbsz.h);
            _hscrollbar.layout(b);
        }
        else if (_hscrollbar)
            _hscrollbar.cancelLayout();
        if (needVScroll)
        {
            Box b = Box(inner.x + inner.w - _sbsz.w, inner.y, _sbsz.w, sz.h - hsbh);
            _vscrollbar.layout(b);
        }
        else if (_vscrollbar)
            _vscrollbar.cancelLayout();
    }

    /// Show or hide scrollbars
    protected void updateScrollBarsVisibility(const Size clientSize)
    {
        // do not touch external scrollbars
        const bool hupdate = _hscrollbar && _hmode != Mode.external;
        const bool vupdate = _vscrollbar && _vmode != Mode.external;
        if (!hupdate && !vupdate)
            return;
        bool hvisible = _hmode == Mode.visible;
        bool vvisible = _vmode == Mode.visible;
        if (!hvisible || !vvisible)
        {
            // full content size and bar widths are known here
            const Size contentSize = fullContentSize;
            const bool xExceeds = clientSize.w < contentSize.w;
            const bool yExceeds = clientSize.h < contentSize.h;
            if (_hmode == Mode.automatic && _vmode == Mode.automatic)
            {
                if (xExceeds && yExceeds)
                {
                    // none fits, need both scrollbars
                    hvisible = vvisible = true;
                }
                else if (!xExceeds && !yExceeds)
                {
                    // everything fits, nothing to do
                }
                else if (yExceeds)
                {
                    // only X fits, check counting vertical scrollbar
                    hvisible = clientSize.w - _vscrollbar.box.w < contentSize.w;
                    vvisible = true;
                }
                else
                {
                    // only Y fits, check counting horizontal scrollbar
                    vvisible = clientSize.h - _hscrollbar.box.h < contentSize.h;
                    hvisible = true;
                }
            }
            else if (_hmode == Mode.automatic)
            {
                // only horizontal scroll bar is in auto mode
                hvisible = xExceeds || vvisible && clientSize.w - _vscrollbar.box.w < contentSize.w;

            }
            else if (_vmode == Mode.automatic)
            {
                // only vertical scroll bar is in auto mode
                vvisible = yExceeds || hvisible && clientSize.h - _hscrollbar.box.h < contentSize.h;
            }
        }
        if (hupdate)
        {
            _hscrollbar.visibility = hvisible ? Visibility.visible : Visibility.gone;
        }
        if (vupdate)
        {
            _vscrollbar.visibility = vvisible ? Visibility.visible : Visibility.gone;
        }
    }

    /// Determine whether scrollbars are needed or not
    protected void needToShowScrollbars(out bool needHScroll, out bool needVScroll)
    {
        needHScroll = _hscrollbar && _hmode != Mode.external &&
                _hscrollbar.visibility == Visibility.visible;
        needVScroll = _vscrollbar && _vmode != Mode.external &&
                _vscrollbar.visibility == Visibility.visible;
    }

    /// Override to support modification of client rect after change, e.g. apply offset
    protected void adjustClientBox(ref Box clb)
    {
    }

    /// Ensure scroll position is inside min/max area
    protected void correctScrollPos()
    {
        // move back after window or widget resize
        // need to move it to the right-bottom corner
        Size csz = fullContentSize;
        _scrollPos.x = clamp(csz.w - _clientBox.w, 0, _scrollPos.x);
        _scrollPos.y = clamp(csz.h - _clientBox.h, 0, _scrollPos.y);
    }

    /// Update scrollbar data - ranges, positions, etc.
    protected void updateScrollBars()
    {
        correctScrollPos();

        updateHScrollBar(_hdata);
        updateVScrollBar(_vdata);
    }

    /** Update horizontal scrollbar data - range, position, etc.

        Default implementation is intended to scroll full contents
        inside the client box, override it if necessary.
    */
    protected void updateHScrollBar(ScrollData data)
    {
        data.setRange(fullContentSize.w, _clientBox.w);
        data.position = _scrollPos.x;
    }

    /** Update vertical scrollbar data - range, position, etc.

        Default implementation is intended to scroll full contents
        inside the client box, override it if necessary.
    */
    protected void updateVScrollBar(ScrollData data)
    {
        data.setRange(fullContentSize.h, _clientBox.h);
        data.position = _scrollPos.y;
    }

    final override protected void drawContent(Painter pr)
    {
        // draw scrollbars
        if (auto h = _hscrollbar)
            h.draw(pr);
        if (auto v = _vscrollbar)
            v.draw(pr);
        {
            PaintSaver sv;
            pr.save(sv);
            // apply clipping
            pr.clipIn(BoxI.from(_clientBox));
            drawClient(pr);
        }
        {
            // add the client box to the extended area clip
            Box clipb = innerBox;
            clipb.h = _clientBox.h;
            pr.clipIn(BoxI.from(clipb));
            drawExtendedArea(pr);
        }
    }

    protected void drawClient(Painter pr)
    {
        // override it
    }

    protected void drawExtendedArea(Painter pr)
    {
        // override it
    }
}

/** Shows content of a widget with optional scrolling.

    If the size of the content widget exceeds available space, it allows
    to scroll it. If the widget fits, `ScrollArea` can stretch and align it,
    using the respective style properties.

    CSS_nodes:
    ---
    ScrollArea
    ├── ScrollBar?
    ├── ScrollBar?
    ╰── *content*
    ---
 */
class ScrollArea : ScrollAreaBase
{
    protected Widget _content;

    this()
    {
        hscrollbarMode = ScrollBarMode.automatic;
        vscrollbarMode = ScrollBarMode.automatic;
    }

    final Widget wrap(lazy Widget content)
    {
        _content = content;
        return this;
    }

    override protected Element createElement()
    {
        return new ElemScrollArea;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemScrollArea el = fastCast!ElemScrollArea(element);
        if (_content)
        {
            el._content = mountChild(_content, el, 2);
            el.addChild(el._content);
        }
        else
            el._content = null;
    }
}

class ElemScrollArea : ElemScrollAreaBase
{
    @property
    {
        inout(Element) content() inout { return _content; }

        override Size fullContentSize() const { return _fullContentSize; }
    }

    private Element _content;
    /// Size of content widget
    private Size _fullContentSize;

//     protected void scrollTo(int x, int y)
//     {
//         Size sz = fullContentSize;
//         _scrollPos.x = max(0, min(x, sz.w - _clientBox.w));
//         _scrollPos.y = max(0, min(y, sz.h - _clientBox.h));
//         updateScrollBars();
//         requestLayout();
// //         invalidate();
//     }

    override protected bool handleHScroll(ScrollAction action, float position)
    {
        if (_scrollPos.x != position)
        {
            _scrollPos.x = position;
            requestLayout();
        }
        return true;
    }

    override protected bool handleVScroll(ScrollAction action, float position)
    {
        if (_scrollPos.y != position)
        {
            _scrollPos.y = position;
            requestLayout();
        }
        return true;
    }

    void makeWidgetVisible(Element elem, bool alignHorizontally = true, bool alignVertically = true)
    {
        if (!elem || !elem.visibility == Visibility.gone)
            return;
        if (!_content || !_content.isChild(elem))
            return;
        const cbox = _content.box;
        Box wbox = elem.box;
        wbox.x -= cbox.x;
        wbox.y -= cbox.y;
        makeBoxVisible(wbox, alignHorizontally, alignVertically);
    }

    override protected void handleChildStyleChange(StyleProperty p, Visibility v)
    {
        if (v != Visibility.gone)
        {
            if (p == StyleProperty.alignment || p == StyleProperty.stretch)
                requestLayout();
        }
    }

    override protected Boundaries computeBoundaries()
    {
        if (_content)
        {
            _content.measure();
            _fullContentSize = _content.natSize;
        }
        return super.computeBoundaries();
    }

    override protected void arrangeContent()
    {
        super.arrangeContent();

        if (_content && _content.visibility != Visibility.gone)
        {
            const stretch = _content.style.stretch;
            const scrolled = Box(_clientBox.pos - _scrollPos, _clientBox.size);
            Size sz = _fullContentSize;
            Align a;
            if (_clientBox.w > sz.w)
            {
                if (stretch == Stretch.cross || stretch == Stretch.both)
                    sz.w = scrolled.w;
                else
                    a |= _content.style.halign;
            }
            if (_clientBox.h > sz.h)
            {
                if (stretch == Stretch.main || stretch == Stretch.both)
                    sz.h = scrolled.h;
                else
                    a |= _content.style.valign;
            }
            _content.layout(alignBox(scrolled, sz, a));
        }
    }

    override protected void drawClient(Painter pr)
    {
        if (auto el = _content)
            el.draw(pr);
    }
}
