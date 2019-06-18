/**
Scrollbar control.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.scrollbar;

import beamui.widgets.controls;
import beamui.widgets.widget;

/// Component for scroll data. It validates it and reacts on changes
class ScrollData
{
    final @property
    {
        /// Current scroll position, between 0 and `range - page`
        int position() const { return _pos; }
        /// ditto
        void position(int v)
        {
            adjustPos(v);
            if (_pos != v)
            {
                _pos = v;
                changed();
            }
        }
        /// Scroll length (max `position` + `page`). Always >= 0
        int range() const { return _range; }
        /// Page (visible area) size. Always >= 0, may be > `range`
        int page() const { return _page; }
    }

    Signal!(void delegate()) changed;

    private
    {
        int _pos;
        int _range = 100;
        int _page = 10;
    }

    /// Set new `range` and `page` values for scrolling. They must be >= 0
    final void setRange(int range, int page)
    {
        assert(range >= 0);
        assert(page >= 0);

        if (_range != range || _page != page)
        {
            _range = range;
            _page = page;
            adjustPos(_pos);
            changed();
        }
    }

    private void adjustPos(ref int v)
    {
        v = max(0, min(v, _range - _page));
    }
}

/// Scroll bar action codes for `ScrollEvent`
enum ScrollAction : ubyte
{
    pressed,  /// Indicator dragging started
    moved,    /// Dragging in progress
    released, /// Dragging finished
    pageUp,   /// Space above indicator pressed
    pageDown, /// Space below indicator pressed
    lineUp,   /// Up/left button pressed
    lineDown, /// Down/right button pressed
}

/// Scrollbar event
final class ScrollEvent
{
    const ScrollAction action;
    const ScrollData data;
    const int position;
    private int amendment = int.min;

    this(ScrollAction a, ScrollData d, int p)
    {
        action = a;
        data = d;
        position = p;
    }

    /// Set new scrollbar position in an event handler
    void amend(int position)
    {
        amendment = position;
    }
}

/// Scroll bar - either vertical or horizontal
class ScrollBar : WidgetGroup
{
    @property
    {
        /// Scrollbar data component
        inout(ScrollData) data() inout { return _data; }

        /// Scrollbar orientation (vertical, horizontal)
        Orientation orientation() const { return _orient; }
        /// ditto
        void orientation(Orientation value)
        {
            if (_orient != value)
            {
                _orient = value;
                updateDrawables();
                requestLayout();
            }
        }

        /// True if full scroll range is visible, and no need of scrolling at all
        bool fullRangeVisible() const
        {
            return _data.page >= _data.range;
        }
    }

    /// Scroll event listeners
    Signal!(void delegate(ScrollEvent event)) scrolled;

    /// Jump length on lineUp/lineDown events
    uint lineStep;

    private
    {
        ScrollData _data;

        // not _orientation to not intersect with inner buttons _orientation
        Orientation _orient = Orientation.vertical;

        ScrollIndicator _indicator;
        PageScrollButton _pageUp;
        PageScrollButton _pageDown;
        Button _btnBack;
        Button _btnForward;

        Box _scrollArea;
        int _minIndicatorSize;
        int _btnSize;
    }

    this(Orientation orient = Orientation.vertical, ScrollData data = null)
    {
        isolateStyle();
        _data = data ? data : new ScrollData;
        _data.changed ~= &onDataChanged;
        _orient = orient;
        _btnBack = new Button;
        _btnBack.id = "BACK";
        _btnBack.bindSubItem(this, "button");
        _btnForward = new Button;
        _btnForward.id = "FORWARD";
        _btnForward.bindSubItem(this, "button");
        _pageUp = new PageScrollButton("PAGE_UP");
        _pageDown = new PageScrollButton("PAGE_DOWN");
        _indicator = new ScrollIndicator;
        updateDrawables();
        addChildren(_btnBack, _btnForward, _indicator, _pageUp, _pageDown);
        bunch(_btnBack, _btnForward, _indicator, _pageUp, _pageDown).allowsFocus(false);
        _btnBack.clicked ~= { sendScrollEvent(ScrollAction.lineUp); };
        _btnForward.clicked ~= { sendScrollEvent(ScrollAction.lineDown); };
        _pageUp.clicked ~= { sendScrollEvent(ScrollAction.pageUp); };
        _pageDown.clicked ~= { sendScrollEvent(ScrollAction.pageDown); };
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        updateDrawables();
    }

    protected void updateDrawables()
    {
        _btnBack.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_button_up" : "scrollbar_button_left");
        _btnForward.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_button_down" : "scrollbar_button_right");
        _indicator.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_indicator_vertical" : "scrollbar_indicator_horizontal");
    }

    void sendScrollEvent(ScrollAction action)
    {
        if (scrolled.assigned)
        {
            auto event = new ScrollEvent(action, _data, _data.position);
            scrolled(event);
            if (event.amendment >= 0)
            {
                _data.position = event.amendment;
                return;
            }
        }
        _data.position = _data.position + getDefaultOffset(action);
    }

    void sendScrollEvent(int position)
    {
        _data.adjustPos(position);
        if (_data.position == position)
            return;

        if (scrolled.assigned)
        {
            auto event = new ScrollEvent(ScrollAction.moved, _data, position);
            scrolled(event);
            if (event.amendment >= 0)
            {
                _data.position = event.amendment;
                return;
            }
        }
        _data.position = position;
    }

    /// Default slider offset on pageUp/pageDown, lineUp/lineDown actions
    protected int getDefaultOffset(ScrollAction action) const
    {
        double delta = 0;
        switch (action) with (ScrollAction)
        {
        case lineUp:
        case lineDown:
            delta = lineStep > 0 ? lineStep : max(_data.page * 0.1, 1);
            if (action == lineUp)
                delta *= -1;
            break;
        case pageUp:
        case pageDown:
            delta = max(_data.page * 0.75, lineStep, 1);
            if (action == pageUp)
                delta *= -1;
            break;
        default:
            break;
        }
        return cast(int)delta;
    }

    protected void onIndicatorDragging(int initialValue, int currentValue)
    {
        sendScrollEvent(currentValue);
    }

    protected void onDataChanged()
    {
        if (!needLayout)
        {
            layoutButtons();
            invalidate();
        }
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.wheel)
        {
            const delta = event.wheelDelta;
            if (delta != 0)
                sendScrollEvent(delta > 0 ? ScrollAction.lineUp : ScrollAction.lineDown);
            return true;
        }
        return super.onMouseEvent(event);
    }

    protected bool calcButtonSizes(int availableSize, ref int spaceBackSize, ref int spaceForwardSize,
            ref int indicatorSize)
    {
        const r = _data.range;
        if (_data.page >= r)
        {
            // full size
            spaceBackSize = spaceForwardSize = 0;
            indicatorSize = availableSize;
            return false;
        }
        indicatorSize = r > 0 ? _data.page * availableSize / r : 0;
        indicatorSize = max(indicatorSize, _minIndicatorSize);
        if (indicatorSize >= availableSize)
        {
            // full size
            spaceBackSize = spaceForwardSize = 0;
            indicatorSize = availableSize;
            return false;
        }
        const spaceLeft = availableSize - indicatorSize;
        const double before = _data.position;
        const double after = r - before - _data.page;
        assert(before + after > 0);
        spaceBackSize = cast(int)(spaceLeft * before / (before + after));
        spaceForwardSize = spaceLeft - spaceBackSize;
        return true;
    }

    protected void layoutButtons()
    {
        Box ibox = _scrollArea;
        if (_orient == Orientation.vertical)
        {
            int spaceBackSize, spaceForwardSize, indicatorSize;
            bool indicatorVisible = calcButtonSizes(_scrollArea.h, spaceBackSize, spaceForwardSize, indicatorSize);
            ibox.y += spaceBackSize;
            ibox.h -= spaceBackSize + spaceForwardSize;
        }
        else // horizontal
        {
            int spaceBackSize, spaceForwardSize, indicatorSize;
            bool indicatorVisible = calcButtonSizes(_scrollArea.w, spaceBackSize, spaceForwardSize, indicatorSize);
            ibox.x += spaceBackSize;
            ibox.w -= spaceBackSize + spaceForwardSize;
        }
        layoutButtons(ibox);
        updateVisibility();
        cancelLayout();
    }

    protected void layoutButtons(Box ibox)
    {
        _indicator.visibility = Visibility.visible;
        _indicator.layout(ibox);
        // layout pageup-pagedown buttons
        const Box b = _scrollArea;
        if (_orient == Orientation.vertical)
        {
            int top = ibox.y - b.y;
            int bottom = b.y + b.h - (ibox.y + ibox.h);
            if (top > 0)
            {
                _pageUp.visibility = Visibility.visible;
                _pageUp.layout(Box(b.x, b.y, b.w, top));
            }
            else
            {
                _pageUp.visibility = Visibility.hidden;
            }
            if (bottom > 0)
            {
                _pageDown.visibility = Visibility.visible;
                _pageDown.layout(Box(b.x, b.y + b.h - bottom, b.w, bottom));
            }
            else
            {
                _pageDown.visibility = Visibility.hidden;
            }
        }
        else
        {
            int left = ibox.x - b.x;
            int right = b.x + b.w - (ibox.x + ibox.w);
            if (left > 0)
            {
                _pageUp.visibility = Visibility.visible;
                _pageUp.layout(Box(b.x, b.y, left, b.h));
            }
            else
            {
                _pageUp.visibility = Visibility.hidden;
            }
            if (right > 0)
            {
                _pageDown.visibility = Visibility.visible;
                _pageDown.layout(Box(b.x + b.w - right, b.y, right, b.h));
            }
            else
            {
                _pageDown.visibility = Visibility.hidden;
            }
        }
    }

    /// Hide controls when scroll is not possible
    protected void updateVisibility()
    {
        const canScroll = _data.range > _data.page;
        if (canScroll)
        {
            bunch(_btnBack, _btnForward).setState(State.enabled);
            _indicator.visibility = Visibility.visible;
            if (_data.position > 0)
                _pageUp.visibility = Visibility.visible;
            if (_data.position < _data.range - _data.page)
                _pageDown.visibility = Visibility.visible;
        }
        else
        {
            bunch(_btnBack, _btnForward).resetState(State.enabled);
            bunch(_indicator, _pageUp, _pageDown).visibility(Visibility.gone);
        }
    }

    override void cancelLayout()
    {
        bunch(_indicator, _pageUp, _pageDown, _btnBack, _btnForward).cancelLayout();
        super.cancelLayout();
    }

    override void measure()
    {
        Boundaries bs;
        _indicator.measure();
        _btnBack.measure();
        _btnForward.measure();
        const ibs = _indicator.boundaries;
        const bbs = _btnBack.boundaries;
        const fbs = _btnForward.boundaries;
        if (_orient == Orientation.vertical)
        {
            _minIndicatorSize = ibs.nat.h;
            _btnSize = max(bbs.nat.w, fbs.nat.w, bbs.nat.h, fbs.nat.h);
            bs.nat.h = bs.min.h = ibs.nat.h + _btnSize * 4;
            bs.max.w = bs.nat.w = bs.min.w = max(ibs.nat.w, bbs.nat.w, fbs.nat.w);
        }
        else
        {
            _minIndicatorSize = ibs.nat.w;
            _btnSize = max(bbs.nat.w, fbs.nat.w, bbs.nat.h, fbs.nat.h);
            bs.nat.w = bs.min.w = ibs.nat.w + _btnSize * 4;
            bs.max.h = bs.nat.h = bs.min.h = max(ibs.nat.h, bbs.nat.h, fbs.nat.h);
        }
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        geom = innerBox;

        if (_orient == Orientation.vertical)
        {
            // buttons
            _btnBack.layout(Box(geom.x, geom.y, _btnSize, _btnSize));
            _btnForward.layout(Box(geom.x, geom.y + geom.h - _btnSize, _btnSize, _btnSize));
            // indicator
            geom.y += _btnSize;
            geom.h -= _btnSize * 2;
        }
        else // horizontal
        {
            // buttons
            _btnBack.layout(Box(geom.x, geom.y, _btnSize, _btnSize));
            _btnForward.layout(Box(geom.x + geom.w - _btnSize, geom.y, _btnSize, _btnSize));
            // indicator
            geom.x += _btnSize;
            geom.w -= _btnSize * 2;
        }

        _scrollArea = geom;
        _indicator.scrollArea = geom;
        layoutButtons();
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        const saver = ClipRectSaver(buf, innerBox, style.alpha);
        bunch(_btnBack, _btnForward, _pageUp, _pageDown, _indicator).onDraw(buf);
    }

    class ScrollIndicator : ImageWidget
    {
        @property void scrollArea(Box b)
        {
            _scrollArea = b;
        }

        private
        {
            bool _dragging;
            Point _dragStart;
            int _dragStartPos;
            Box _dragStartBox;

            Box _scrollArea;
        }

        this()
        {
            id = "SCROLL_INDICATOR";
            allowsHover = true;
        }

        override bool onMouseEvent(MouseEvent event)
        {
            if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
            {
                setState(State.pressed);
                _dragging = true;
                _dragStart.x = event.x;
                _dragStart.y = event.y;
                _dragStartPos = _data.position;
                _dragStartBox = box;
                sendScrollEvent(ScrollAction.pressed);
                return true;
            }
            if (event.action == MouseAction.focusIn && _dragging)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: dragging, focusIn");
                return true;
            }
            if (event.action == MouseAction.focusOut && _dragging)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: dragging, focusOut");
                return true;
            }
            if (event.action == MouseAction.move && _dragging)
            {
                int delta = _orient == Orientation.vertical ?
                        event.y - _dragStart.y : event.x - _dragStart.x;
                debug (scrollbars)
                    Log.d("ScrollIndicator: dragging, move delta: ", delta);
                Box b = _dragStartBox;
                int offset;
                int space;
                if (_orient == Orientation.vertical)
                {
                    b.y = clamp(b.y + delta, _scrollArea.y, _scrollArea.y + _scrollArea.h - b.h);
                    offset = b.y - _scrollArea.y;
                    space = _scrollArea.h - b.h;
                }
                else
                {
                    b.x = clamp(b.x + delta, _scrollArea.x, _scrollArea.x + _scrollArea.w - b.w);
                    offset = b.x - _scrollArea.x;
                    space = _scrollArea.w - b.w;
                }
                int v;
                if (space > 0)
                    v = offset * max(_data.range - _data.page, 0) / space;
                onIndicatorDragging(_dragStartPos, v);
                return true;
            }
            if (event.action == MouseAction.buttonUp && event.button == MouseButton.left)
            {
                resetState(State.pressed);
                if (_dragging)
                {
                    sendScrollEvent(ScrollAction.released);
                    _dragging = false;
                }
                return true;
            }
            if (event.action == MouseAction.move && allowsHover)
            {
                if (!(state & State.hovered))
                {
                    debug (scrollbars)
                        Log.d("ScrollIndicator: hover");
                    setState(State.hovered);
                }
                return true;
            }
            if (event.action == MouseAction.leave && allowsHover)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: leave");
                resetState(State.hovered);
                return true;
            }
            if (event.action == MouseAction.cancel && allowsHover)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: cancel with allowsHover");
                resetState(State.hovered);
                resetState(State.pressed);
                _dragging = false;
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: cancel");
                resetState(State.pressed);
                _dragging = false;
                return true;
            }
            return false;
        }
    }

    class PageScrollButton : Widget
    {
        this(string ID)
        {
            super(ID);
            allowsClick = true;
            allowsHover = true;
        }
    }
}
