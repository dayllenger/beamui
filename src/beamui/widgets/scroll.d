/**
This module contains base implementation of scrolling capabilities for widgets


ScrollAreaBase - abstract scrollable widget (used as a base for other widgets with scrolling)

ScrollArea - widget which can scroll its content (directly usable class)


Synopsis:
---
import beamui.widgets.scroll;

// Scroll view example
auto scroll = new ScrollArea;
auto scrollContent = new Column;
scrollContent.padding = RectOffset(10);

auto table2 = new TableLayout;
table2.colCount = 2;
// headers
table2.addChild((new Label("Parameter Name"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new Label("Edit Box to edit parameter"d)).alignment(Align.left | Align.vcenter));
// row 1
table2.addChild((new Label("Parameter 1 name"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Text 1"d)).fillW());
// row 2
table2.addChild((new Label("Parameter 2 name bla bla"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Some text for parameter 2 blah blah blah"d)).fillW());
// row 3
table2.addChild((new Label("Param 3"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Parameter 3 value"d)).fillW());
// row 4
table2.addChild((new Label("Param 4"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Parameter 4 value shdjksdfh hsjdfas hdjkf hdjsfk ah"d)).fillW());
// row 5
table2.addChild((new Label("Param 5 - edit text here - blah blah blah"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Parameter 5 value"d)).fillW());
// row 6
table2.addChild((new Label("Param 6 - just to fill content widget"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Parameter 5 value"d)).fillW());
// row 7
table2.addChild((new Label("Param 7 - just to fill content widget"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Parameter 5 value"d)).fillW());
// row 8
table2.addChild((new Label("Param 8 - just to fill content widget"d)).alignment(Align.right | Align.vcenter));
table2.addChild((new EditLine("Parameter 5 value"d)).fillW());
scrollContent.addChild(table2);

scrollContent.addChild(new Label("Now - some buttons"d));
scrollContent.addChild(new Button("Close"d, "fileclose"));
scrollContent.addChild(new Button("Open"d, "fileopen"));
scrollContent.addChild(new Label("And checkboxes"d));
scrollContent.addChild(new CheckBox("CheckBox 1"d));
scrollContent.addChild(new CheckBox("CheckBox 2"d));

scroll.contentWidget = scrollContent;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.scroll;

import beamui.widgets.controls;
import beamui.widgets.scrollbar;
import beamui.widgets.widget;

/// Scroll bar visibility mode
enum ScrollBarMode
{
    /// Always invisible
    invisible,
    /// Always visible
    visible,
    /// Automatically show/hide scrollbar depending on content size
    automatic,
    /// Scrollbar is provided by external control outside this widget
    external,
}

/**
    Abstract scrollable widget

    Provides scroll bars and basic scrolling functionality.
 */
class ScrollAreaBase : WidgetGroup
{
    @property
    {
        /// Mode of the vertical scrollbar
        ScrollBarMode vscrollbarMode() const
        {
            return _vscrollbarMode;
        }
        /// ditto
        void vscrollbarMode(ScrollBarMode m)
        {
            _vscrollbarMode = m;
        }
        /// Mode of the horizontal scrollbar
        ScrollBarMode hscrollbarMode() const
        {
            return _hscrollbarMode;
        }
        /// ditto
        void hscrollbarMode(ScrollBarMode m)
        {
            _hscrollbarMode = m;
        }

        /// Horizontal scrollbar control
        ScrollBar hscrollbar()
        {
            return _hscrollbar;
        }
        /// ditto
        void hscrollbar(ScrollBar hbar)
        {
            if (_hscrollbar)
            {
                removeChild(_hscrollbar);
                destroy(_hscrollbar);
                _hscrollbar = null;
                _hscrollbarMode = ScrollBarMode.invisible;
            }
            if (hbar)
            {
                _hscrollbar = hbar;
                _hscrollbarMode = ScrollBarMode.external;
            }
        }
        /// Vertical scrollbar control
        ScrollBar vscrollbar()
        {
            return _vscrollbar;
        }
        /// ditto
        void vscrollbar(ScrollBar vbar)
        {
            if (_vscrollbar)
            {
                removeChild(_vscrollbar);
                destroy(_vscrollbar);
                _vscrollbar = null;
                _vscrollbarMode = ScrollBarMode.invisible;
            }
            if (vbar)
            {
                _vscrollbar = vbar;
                _vscrollbarMode = ScrollBarMode.external;
            }
        }

        /// Inner area, excluding additional controls like scrollbars
        Box clientBox() const
        {
            return _clientBox;
        }

        /// Scroll offset in pixels
        Point scrollPos()
        {
            return _scrollPos;
        }

        /// Get full content size in pixels
        Size fullContentSize()
        {
            // override it
            return Size(0, 0);
        }

        /// Get full content size in pixels including widget borders / padding
        Size fullContentSizeWithBorders()
        {
            return fullContentSize + padding.size;
        }
    }

    protected
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
        _hscrollbar.scrolled = &onScrollEvent;
        _vscrollbar.scrolled = &onScrollEvent;
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
                    return true;
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
    protected bool onScrollEvent(AbstractSlider source, ScrollEvent event)
    {
        if (source.orientation == Orientation.horizontal)
        {
            return onHScroll(event);
        }
        else
        {
            return onVScroll(event);
        }
    }

    /// Process horizontal scrollbar event
    bool onHScroll(ScrollEvent event)
    {
        return true;
    }

    /// Process vertical scrollbar event
    bool onVScroll(ScrollEvent event)
    {
        return true;
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
        bs.min = computeMinSize();
        // do first measure to get scrollbar widths
        if (_hscrollbar && _hscrollbarMode == ScrollBarMode.visible || _hscrollbarMode == ScrollBarMode.automatic)
        {
            _sbsz.h = _hscrollbar.computeBoundaries().nat.h;
        }
        if (_vscrollbar && _vscrollbarMode == ScrollBarMode.visible || _vscrollbarMode == ScrollBarMode.automatic)
        {
            _sbsz.w = _vscrollbar.computeBoundaries().nat.w;
        }
        bs.min = bs.min + _sbsz;
        bs.nat = bs.min;

        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        _box = geom;
        applyPadding(geom);

        Size sz = geom.size;
        updateScrollBarsVisibility(sz);
        bool needHScroll;
        bool needVScroll;
        needToShowScrollbars(needHScroll, needVScroll);

        // client area
        _clientBox = geom;
        if (needHScroll)
            _clientBox.h -= _sbsz.h;
        if (needVScroll)
            _clientBox.w -= _sbsz.w;

        handleClientBoxLayout(_clientBox);

        // update scrollbar button positions before laying out
        updateScrollBars();

        // lay out scrollbars
        int vsbw = needVScroll ? _sbsz.w : 0;
        int hsbh = needHScroll ? _sbsz.h : 0;
        if (needHScroll)
        {
            Box b = Box(geom.x, geom.y + geom.h - _sbsz.h, sz.w - vsbw, _sbsz.h);
            _hscrollbar.layout(b);
        }
        if (needVScroll)
        {
            Box b = Box(geom.x + geom.w - _sbsz.w, geom.y, _sbsz.w, sz.h - hsbh);
            _vscrollbar.layout(b);
        }
    }

    /// Show or hide scrollbars
    protected void updateScrollBarsVisibility(in Size clientSize)
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
        _hscrollbar.setRange(0, fullContentSize.w);
        _hscrollbar.pageSize = _clientBox.w;
        _hscrollbar.position = _scrollPos.x;
    }

    /// Update verticat scrollbar widget position
    protected void updateVScrollBar()
    {
        // default implementation: use fullContentSize, _clientBox, override it if necessary
        _vscrollbar.setRange(0, fullContentSize.h);
        _vscrollbar.pageSize = _clientBox.h;
        _vscrollbar.position = _scrollPos.y;
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
        _needDraw = false;
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = _box;
        applyMargins(b);

        auto saver = ClipRectSaver(buf, b, alpha);
        DrawableRef bg = backgroundDrawable;
        if (!bg.isNull)
        {
            bg.drawTo(buf, b, state);
        }
        applyPadding(b);
        // draw scrollbars
        _hscrollbar.maybe.onDraw(buf);
        _vscrollbar.maybe.onDraw(buf);
        {
            // apply clipping
            auto saver2 = ClipRectSaver(buf, _clientBox, alpha);
            drawClient(buf);
        }
        {
            // no clipping for drawing of extended area
            Box clipb = b;
            clipb.h = _clientBox.h;
            auto saver3 = ClipRectSaver(buf, clipb, alpha);
            drawExtendedArea(buf);
        }
    }
}

/**
    Widget which can show content of widget group with optional scrolling

    If size of content widget exceeds available space, allows to scroll it.
 */
class ScrollArea : ScrollAreaBase
{
    @property Widget contentWidget()
    {
        return _contentWidget;
    }
    @property ScrollArea contentWidget(Widget newContent)
    {
        if (_contentWidget)
        {
            removeChild(childIndex(_contentWidget));
            destroy(_contentWidget);
        }
        _contentWidget = newContent;
        addChild(_contentWidget);
        requestLayout();
        return this;
    }

    override @property Size fullContentSize()
    {
        return _fullContentSize;
    }

    protected Widget _contentWidget;
    /// Size of content widget
    protected Size _fullContentSize;

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

    override bool onHScroll(ScrollEvent event)
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
        return true;
    }

    override bool onVScroll(ScrollEvent event)
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
        return true;
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
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        if (_contentWidget)
        {
            Box cb = Box(_clientBox.pos - _scrollPos, _fullContentSize);
            if (_contentWidget.fillsWidth)
                cb.w = max(cb.w, _clientBox.w);
            if (_contentWidget.fillsHeight)
                cb.h = max(cb.h, _clientBox.h);
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
