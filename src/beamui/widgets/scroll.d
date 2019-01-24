/**
Base implementation for widgets with scrolling capabilities.

Synopsis:
---
import beamui.widgets.scroll;

// Scroll view example

auto scrollContent = new Column;
with (scrollContent) {
    padding = 10;
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

/**
    Abstract scrollable widget (used as a base for other widgets with scrolling)

    Provides scroll bars and basic scrolling functionality.
 */
class ScrollAreaBase : WidgetGroup
{
    @property
    {
        /// Mode of the vertical scrollbar
        ScrollBarMode vscrollbarMode() const { return _vscrollbarMode; }
        /// ditto
        void vscrollbarMode(ScrollBarMode m)
        {
            _vscrollbarMode = m;
        }
        /// Mode of the horizontal scrollbar
        ScrollBarMode hscrollbarMode() const { return _hscrollbarMode; }
        /// ditto
        void hscrollbarMode(ScrollBarMode m)
        {
            _hscrollbarMode = m;
        }

        /// Horizontal scrollbar control
        ScrollBar hscrollbar() { return _hscrollbar; }
        /// ditto
        void hscrollbar(ScrollBar hbar)
        {
            if (_hscrollbar)
            {
                removeChild(_hscrollbar);
                destroy(_hscrollbar);
                _hscrollbar = null;
                _hscrollbarMode = ScrollBarMode.hidden;
            }
            if (hbar)
            {
                _hscrollbar = hbar;
                _hscrollbarMode = ScrollBarMode.external;
            }
        }
        /// Vertical scrollbar control
        ScrollBar vscrollbar() { return _vscrollbar; }
        /// ditto
        void vscrollbar(ScrollBar vbar)
        {
            if (_vscrollbar)
            {
                removeChild(_vscrollbar);
                destroy(_vscrollbar);
                _vscrollbar = null;
                _vscrollbarMode = ScrollBarMode.hidden;
            }
            if (vbar)
            {
                _vscrollbar = vbar;
                _vscrollbarMode = ScrollBarMode.external;
            }
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
        Size fullContentSize() const
        {
            // override it
            return Size(0, 0);
        }

        /// Get full content size in pixels including widget borders / padding
        Size fullContentSizeWithBorders() const
        {
            return fullContentSize + padding.size;
        }
    }

    private
    {
        ScrollBarMode _vscrollbarMode;
        ScrollBarMode _hscrollbarMode;
        ScrollBar _vscrollbar;
        ScrollBar _hscrollbar;
        Size _sbsz;

        Box _clientBox;
        Point _scrollPos;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        _hscrollbarMode = hscrollbarMode;
        _vscrollbarMode = vscrollbarMode;
        _hscrollbar = new ScrollBar(Orientation.horizontal);
        _vscrollbar = new ScrollBar(Orientation.vertical);
        _hscrollbar.id = "hscrollbar";
        _vscrollbar.id = "vscrollbar";
        _hscrollbar.scrolled ~= &onScrollEvent;
        _vscrollbar.scrolled ~= &onScrollEvent;
        addChild(_hscrollbar);
        addChild(_vscrollbar);
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.wheel)
        {
            if (event.flags == MouseFlag.shift)
            {
                if (_hscrollbar)
                {
                    _hscrollbar.sendScrollEvent(event.wheelDelta > 0 ? ScrollAction.lineUp : ScrollAction.lineDown);
                    return true; // TODO: return false when nothing to scroll
                }
            }
            else if (event.flags == 0)
            {
                if (_vscrollbar)
                {
                    _vscrollbar.sendScrollEvent(event.wheelDelta > 0 ? ScrollAction.lineUp : ScrollAction.lineDown);
                    return true;
                }
            }
        }
        return super.onMouseEvent(event);
    }

    /// Handle scroll event
    protected void onScrollEvent(AbstractSlider source, ScrollEvent event)
    {
        if (source.orientation == Orientation.horizontal)
            onHScroll(event);
        else
            onVScroll(event);
    }

    /// Process horizontal scrollbar event
    void onHScroll(ScrollEvent event)
    {
    }

    /// Process vertical scrollbar event
    void onVScroll(ScrollEvent event)
    {
    }

    void makeBoxVisible(Box b, bool alignHorizontally = true, bool alignVertically = true)
    {
        Box visible = Box(_scrollPos, _clientBox.size);
        if (b.isInsideOf(visible))
            return;

        Point oldp = _scrollPos;
        if (alignHorizontally && visible.x + visible.w < b.x + b.w)
            _scrollPos.x = b.x + b.w - visible.w;
        if (alignHorizontally && b.x < visible.x)
            _scrollPos.x = b.x;
        if (alignVertically && visible.y + visible.h < b.y + b.h)
            _scrollPos.y = b.y + b.h - visible.h;
        if (alignVertically && b.y < visible.y)
            _scrollPos.y = b.y;

        if (_scrollPos != oldp)
            requestLayout();
    }

    override Size computeMinSize()
    {
        // override to set minimum scrollwidget size
        return Size(200, 150);
    }

    override Boundaries computeBoundaries()
    {
        Boundaries bs;
        // do first measure to get scrollbar widths
        if (_hscrollbar && _hscrollbarMode == ScrollBarMode.visible || _hscrollbarMode == ScrollBarMode.automatic)
        {
            _sbsz.h = _hscrollbar.computeBoundaries().nat.h;
        }
        if (_vscrollbar && _vscrollbarMode == ScrollBarMode.visible || _vscrollbarMode == ScrollBarMode.automatic)
        {
            _sbsz.w = _vscrollbar.computeBoundaries().nat.w;
        }
        bs.min = computeMinSize() + _sbsz;
        bs.nat = bs.min;

        applyStyle(bs);
        return bs;
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
        else
            _hscrollbar.cancelLayout();
        if (needVScroll)
        {
            Box b = Box(inner.x + inner.w - _sbsz.w, inner.y, _sbsz.w, sz.h - hsbh);
            _vscrollbar.layout(b);
        }
        else
            _vscrollbar.cancelLayout();
    }

    /// Show or hide scrollbars
    protected void updateScrollBarsVisibility(const Size clientSize)
    {
        // do not touch external scrollbars
        bool hupdate = _hscrollbar && _hscrollbarMode != ScrollBarMode.external;
        bool vupdate = _vscrollbar && _vscrollbarMode != ScrollBarMode.external;
        if (!hupdate && !vupdate)
            return;
        bool hvisible = _hscrollbarMode == ScrollBarMode.visible;
        bool vvisible = _vscrollbarMode == ScrollBarMode.visible;
        if (!hvisible || !vvisible)
        {
            // full content size and bar widths are known here
            Size contentSize = fullContentSize;
            bool xExceeds = clientSize.w < contentSize.w;
            bool yExceeds = clientSize.h < contentSize.h;
            if (_hscrollbarMode == ScrollBarMode.automatic && _vscrollbarMode == ScrollBarMode.automatic)
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
            else if (_hscrollbarMode == ScrollBarMode.automatic)
            {
                // only horizontal scroll bar is in auto mode
                hvisible = xExceeds || vvisible && clientSize.w - _vscrollbar.box.w < contentSize.w;

            }
            else if (_vscrollbarMode == ScrollBarMode.automatic)
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
        needHScroll = _hscrollbar && _hscrollbarMode != ScrollBarMode.external &&
                _hscrollbar.visibility == Visibility.visible;
        needVScroll = _vscrollbar && _vscrollbarMode != ScrollBarMode.external &&
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

    /// Update scrollbar positions
    protected void updateScrollBars()
    {
        bool needHScroll;
        bool needVScroll;
        needToShowScrollbars(needHScroll, needVScroll);

        if (needHScroll)
            updateHScrollBar();
        if (needVScroll)
            updateVScrollBar();
    }

    /// Update horizontal scrollbar widget position
    protected void updateHScrollBar()
    {
        // default implementation: use fullContentSize, _clientBox, override it if necessary
        _hscrollbar.data.setRange(0, fullContentSize.w);
        _hscrollbar.data.pageSize = _clientBox.w;
        _hscrollbar.data.position = _scrollPos.x;
    }

    /// Update verticat scrollbar widget position
    protected void updateVScrollBar()
    {
        // default implementation: use fullContentSize, _clientBox, override it if necessary
        _vscrollbar.data.setRange(0, fullContentSize.h);
        _vscrollbar.data.pageSize = _clientBox.h;
        _vscrollbar.data.position = _scrollPos.y;
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
        auto saver = ClipRectSaver(buf, b, alpha);
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

/**
    Shows content of a widget with optional scrolling (directly usable class)

    If size of content widget exceeds available space, allows to scroll it.
 */
class ScrollArea : ScrollAreaBase
{
    @property Widget contentWidget() { return _contentWidget; }
    /// ditto
    @property void contentWidget(Widget newContent)
    {
        if (_contentWidget)
        {
            removeChild(childIndex(_contentWidget));
            destroy(_contentWidget);
        }
        _contentWidget = newContent;
        addChild(_contentWidget);
        requestLayout();
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

    protected void scrollTo(int x, int y)
    {
        Size sz = fullContentSize;
        _scrollPos.x = max(0, min(x, sz.w - _clientBox.w));
        _scrollPos.y = max(0, min(y, sz.h - _clientBox.h));
        updateScrollBars();
        requestLayout();
//         invalidate();
    }

    override void onHScroll(ScrollEvent event)
    {
        if (event.action == ScrollAction.sliderMoved || event.action == ScrollAction.sliderReleased)
        {
            scrollTo(event.position, scrollPos.y);
        }
        else if (event.action == ScrollAction.pageUp)
        {
            scrollTo(scrollPos.x - _clientBox.w * 3 / 4, scrollPos.y);
        }
        else if (event.action == ScrollAction.pageDown)
        {
            scrollTo(scrollPos.x + _clientBox.w * 3 / 4, scrollPos.y);
        }
        else if (event.action == ScrollAction.lineUp)
        {
            scrollTo(scrollPos.x - _clientBox.w / 10, scrollPos.y);
        }
        else if (event.action == ScrollAction.lineDown)
        {
            scrollTo(scrollPos.x + _clientBox.w / 10, scrollPos.y);
        }
    }

    override void onVScroll(ScrollEvent event)
    {
        if (event.action == ScrollAction.sliderMoved || event.action == ScrollAction.sliderReleased)
        {
            scrollTo(scrollPos.x, event.position);
        }
        else if (event.action == ScrollAction.pageUp)
        {
            scrollTo(scrollPos.x, scrollPos.y - _clientBox.h * 3 / 4);
        }
        else if (event.action == ScrollAction.pageDown)
        {
            scrollTo(scrollPos.x, scrollPos.y + _clientBox.h * 3 / 4);
        }
        else if (event.action == ScrollAction.lineUp)
        {
            scrollTo(scrollPos.x, scrollPos.y - _clientBox.h / 10);
        }
        else if (event.action == ScrollAction.lineDown)
        {
            scrollTo(scrollPos.x, scrollPos.y + _clientBox.h / 10);
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

    override Boundaries computeBoundaries()
    {
        if (_contentWidget)
        {
            _fullContentSize = _contentWidget.computeBoundaries().nat;
        }
        return super.computeBoundaries();
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

    override protected void updateScrollBars()
    {
        correctScrollPos();
        super.updateScrollBars();
    }

    override protected void drawClient(DrawBuf buf)
    {
        _contentWidget.maybe.onDraw(buf);
    }
}
