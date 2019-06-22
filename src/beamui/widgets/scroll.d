/**
Base for widgets with scrolling capabilities.

Synopsis:
---
// Scroll view example

auto scrollContent = new Column;
with (scrollContent) {
    style.padding = 10;
    add(new Label("Some buttons"d),
        new Button("Close"d, "fileclose"),
        new Button("Open"d, "fileopen"),
        new Label("And checkboxes"d),
        new CheckBox("CheckBox 1"d),
        new CheckBox("CheckBox 2"d),
        new CheckBox("CheckBox 3"d),
        new CheckBox("CheckBox 4"d).setChecked(true),
        new CheckBox("CheckBox 5"d).setChecked(true));
}
// create a scroll view with invisible horizontal and automatic vertical scrollbars
auto scroll = new ScrollArea(ScrollBarMode.hidden, ScrollBarMode.automatic);
// assign
scroll.contentWidget = scrollContent;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.scroll;

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
    leftCorner,
    rightCorner,
    up,
    down,
    pageUp,
    pageDown,
    topCorner,
    bottomCorner,
}

/** Abstract scrollable widget (used as a base for other widgets with scrolling).

    Provides scroll bars and basic scrolling functionality.
 */
class ScrollAreaBase : WidgetGroup
{
    @property
    {
        /// Mode of the horizontal scrollbar
        ScrollBarMode hscrollbarMode() const { return _hmode; }
        /// ditto
        void hscrollbarMode(ScrollBarMode m)
        {
            if (_hmode != m)
            {
                _hmode = m;
                requestLayout();
                if (m != Mode.hidden)
                {
                    _hscrollbar = new ScrollBar(Orientation.horizontal, _hdata);
                    _hscrollbar.id = "hscrollbar";
                    _hscrollbar.scrolled ~= &onHScroll;
                    addChild(_hscrollbar);
                }
            }
        }
        /// Mode of the vertical scrollbar
        ScrollBarMode vscrollbarMode() const { return _vmode; }
        /// ditto
        void vscrollbarMode(ScrollBarMode m)
        {
            if (_vmode != m)
            {
                _vmode = m;
                requestLayout();
                if (m != Mode.hidden)
                {
                    _vscrollbar = new ScrollBar(Orientation.vertical, _vdata);
                    _vscrollbar.id = "vscrollbar";
                    _vscrollbar.scrolled ~= &onVScroll;
                    addChild(_vscrollbar);
                }
            }
        }

        /// Horizontal scrollbar control. Can be `null`, and can be set to another scrollbar or `null`
        const(ScrollBar) hscrollbar() const { return _hscrollbar; }
        /// ditto
        void hscrollbar(ScrollBar bar)
        {
            if (_hscrollbar !is bar)
                requestLayout();
            if (_hscrollbar)
            {
                removeChild(_hscrollbar);
                destroy(_hscrollbar);
                _hscrollbar = null;
            }
            if (bar)
            {
                _hscrollbar = bar;
                _hmode = Mode.external;
                bar.lineStep = _hlineStep;
                // swap the data
                destroy(_hdata);
                _hdata = bar.data;
                updateHScrollBar(_hdata);
            }
            else
                _hmode = Mode.hidden;
        }
        /// Vertical scrollbar control. Can be `null`, and can be set to another scrollbar or `null`
        const(ScrollBar) vscrollbar() const { return _vscrollbar; }
        /// ditto
        void vscrollbar(ScrollBar bar)
        {
            if (_vscrollbar !is bar)
                requestLayout();
            if (_vscrollbar)
            {
                removeChild(_vscrollbar);
                destroy(_vscrollbar);
                _vscrollbar = null;
            }
            if (bar)
            {
                _vscrollbar = bar;
                _vmode = Mode.external;
                bar.lineStep = _vlineStep;
                // swap the data
                destroy(_vdata);
                _vdata = bar.data;
                updateVScrollBar(_vdata);
            }
            else
                _vmode = Mode.hidden;
        }

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
        ScrollBar _hscrollbar;
        ScrollBar _vscrollbar;
        ScrollData _hdata;
        ScrollData _vdata;
        uint _hlineStep;
        uint _vlineStep;
        Size _sbsz;

        Box _clientBox;
        Point _scrollPos;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        _hdata = new ScrollData;
        _vdata = new ScrollData;
        this.hscrollbarMode = hscrollbarMode;
        this.vscrollbarMode = vscrollbarMode;
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
        _hscrollbar.maybe.triggerAction(ScrollAction.lineUp);
    }

    final void scrollRight()
    {
        _hscrollbar.maybe.triggerAction(ScrollAction.lineDown);
    }

    final void scrollPageLeft()
    {
        _hscrollbar.maybe.triggerAction(ScrollAction.pageUp);
    }

    final void scrollPageRight()
    {
        _hscrollbar.maybe.triggerAction(ScrollAction.pageDown);
    }

    final void scrollLeftCorner()
    {
        _hscrollbar.maybe.moveTo(0);
    }

    final void scrollRightCorner()
    {
        _hscrollbar.maybe.moveTo(_hdata.range);
    }

    final void scrollUp()
    {
        _vscrollbar.maybe.triggerAction(ScrollAction.lineUp);
    }

    final void scrollDown()
    {
        _vscrollbar.maybe.triggerAction(ScrollAction.lineDown);
    }

    final void scrollPageUp()
    {
        _vscrollbar.maybe.triggerAction(ScrollAction.pageUp);
    }

    final void scrollPageDown()
    {
        _vscrollbar.maybe.triggerAction(ScrollAction.pageDown);
    }

    final void scrollTopCorner()
    {
        _vscrollbar.maybe.moveTo(0);
    }

    final void scrollBottomCorner()
    {
        _vscrollbar.maybe.moveTo(_vdata.range);
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
                case leftCorner:  h.moveTo(0); return;
                case rightCorner: h.moveTo(_hdata.range); return;
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
                case topCorner:    v.moveTo(0); return;
                case bottomCorner: v.moveTo(_vdata.range); return;
                default: break;
            }
        }
    }

    /// Process horizontal scroll event
    protected void onHScroll(ScrollEvent event)
    {
    }

    /// Process vertical scroll event
    protected void onVScroll(ScrollEvent event)
    {
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.wheel)
        {
            const a = event.wheelDelta > 0 ? ScrollAction.lineUp : ScrollAction.lineDown;
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
        return super.onMouseEvent(event);
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

    override void measure()
    {
        Boundaries bs;
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
        bs.min = _sbsz;
        bs.nat = _sbsz;
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;

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

        handleClientBoxLayout(_clientBox);

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
    protected void handleClientBoxLayout(ref Box clb)
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

        bool needHScroll;
        bool needVScroll;
        needToShowScrollbars(needHScroll, needVScroll);

        if (needHScroll)
            updateHScrollBar(_hdata);
        if (needVScroll)
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

    protected void drawClient(DrawBuf buf)
    {
        // override it
    }

    protected void drawExtendedArea(DrawBuf buf)
    {
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = box;
        auto saver = ClipRectSaver(buf, b, style.alpha);
        auto bg = background;
        bg.drawTo(buf, b);

        // draw scrollbars
        _hscrollbar.maybe.onDraw(buf);
        _vscrollbar.maybe.onDraw(buf);
        {
            // apply clipping
            auto saver2 = ClipRectSaver(buf, _clientBox, 0);
            drawClient(buf);
        }
        {
            // no clipping for drawing of extended area
            Box clipb = innerBox;
            clipb.h = _clientBox.h;
            auto saver3 = ClipRectSaver(buf, clipb, 0);
            drawExtendedArea(buf);
        }
    }
}

/** Shows content of a widget with optional scrolling (directly usable class).

    If the size of the content widget exceeds available space, it allows to scroll it.
 */
class ScrollArea : ScrollAreaBase
{
    @property inout(Widget) contentWidget() inout { return _contentWidget; }
    /// ditto
    @property void contentWidget(Widget widget)
    {
        if (_contentWidget !is widget)
            requestLayout();
        if (_contentWidget)
        {
            removeChild(_contentWidget);
            destroy(_contentWidget);
        }
        if (widget)
        {
            _contentWidget = widget;
            addChild(widget);
        }
    }

    override @property Size fullContentSize() const { return _fullContentSize; }

    private Widget _contentWidget;
    /// Size of content widget
    private Size _fullContentSize;

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
    }

//     protected void scrollTo(int x, int y)
//     {
//         Size sz = fullContentSize;
//         _scrollPos.x = max(0, min(x, sz.w - _clientBox.w));
//         _scrollPos.y = max(0, min(y, sz.h - _clientBox.h));
//         updateScrollBars();
//         requestLayout();
// //         invalidate();
//     }

    override protected void onHScroll(ScrollEvent event)
    {
        if (event.position != _scrollPos.x)
        {
            _scrollPos.x = event.position;
            requestLayout();
        }
    }

    override protected void onVScroll(ScrollEvent event)
    {
        if (event.position != _scrollPos.y)
        {
            _scrollPos.y = event.position;
            requestLayout();
        }
    }

    void makeWidgetVisible(Widget widget, bool alignHorizontally = true, bool alignVertically = true)
    {
        if (!widget || !widget.visibility == Visibility.gone)
            return;
        if (!_contentWidget || !_contentWidget.isChild(widget))
            return;
        Box wbox = widget.box;
        Box cbox = _contentWidget.box;
        wbox.x -= cbox.x;
        wbox.y -= cbox.y;
        makeBoxVisible(wbox, alignHorizontally, alignVertically);
    }

    override void measure()
    {
        if (_contentWidget)
        {
            _contentWidget.measure();
            _fullContentSize = _contentWidget.natSize;
        }
        super.measure();
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        if (_contentWidget)
        {
            Box cb = Box(_clientBox.pos - _scrollPos, _fullContentSize);
            /+ TODO: add some behaviour for the content widget like alignment or fill
            if (_contentWidget.fillsWidth)
                cb.w = max(cb.w, _clientBox.w);
            if (_contentWidget.fillsHeight)
                cb.h = max(cb.h, _clientBox.h);
            +/
            _contentWidget.layout(cb);
        }
    }

    override protected void drawClient(DrawBuf buf)
    {
        _contentWidget.maybe.onDraw(buf);
    }
}
