/**
Scrollbar control.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.scrollbar;

import std.math : isFinite;
import beamui.widgets.controls;
import beamui.widgets.widget;

/** Scroll bar - either vertical or horizontal.

    CSS_nodes:
    ---
    ScrollBar
    ├── .button-back
    ├── .button-forward
    ├── ScrollIndicator
    ├── PageScrollButton
    ╰── PageScrollButton
    ---
*/
class ScrollBar : Widget
{
    /// Scrollbar orientation, horizontal by default
    Orientation orientation;
    /// Allows to explicitly control scrollbar position
    float position;
    ScrollData data;

    /** Scroll event listener. Carries scroll position after the default handling.

        Return false if you want to discard this change (if any) and handle
        it manually, setting `position`.
    */
    bool delegate(ScrollAction, float) onScroll;

    override protected Element createElement()
    {
        return new ElemScrollBar(data ? data : new ScrollData);
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemScrollBar el = fastCast!ElemScrollBar(element);
        el.orientation = orientation;
        el.onScroll.clear();
        if (onScroll)
            el.onScroll ~= onScroll;

        if (!data)
            data = el.data;
        el.data = data;
        if (isFinite(position))
            data.position = position;
    }
}

/// Component for scroll data. It validates it and reacts on changes
class ScrollData
{
    final @property
    {
        /// Current scroll position, between 0 and `range - page`
        float position() const { return _pos; }
        /// ditto
        void position(float v)
        {
            adjustPos(v);
            if (_pos == v)
                return;
            _pos = v;
            onChange();
        }
        /// Scroll length (max `position` + `page`). Always >= 0
        float range() const { return _range; }
        /// Page (visible area) size. Always >= 0, may be > `range`
        float page() const { return _page; }
    }

    Signal!(void delegate()) onChange;

    private
    {
        float _pos = 0;
        float _range = 100;
        float _page = 10;
    }

    /// Set new `range` and `page` values for scrolling. They must be >= 0
    final void setRange(float range, float page)
        in(range >= 0)
        in(page >= 0)
    {
        if (_range != range || _page != page)
        {
            _range = range;
            _page = page;
            adjustPos(_pos);
            onChange();
        }
    }

    private void adjustPos(ref float v)
        in(isFinite(v))
    {
        v = max(0, min(v, _range - _page));
    }
}

/// Scroll bar action codes
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

class ElemScrollBar : ElemGroup
{
    @property
    {
        /// Scrollbar data component
        inout(ScrollData) data() inout { return _data; }
        /// ditto
        void data(ScrollData obj)
            in(obj)
        {
            if (_data is obj)
                return;
            _data.onChange -= &handleDataChange;
            _data = obj;
            _data.onChange ~= &handleDataChange;
        }

        Orientation orientation() const { return _orient; }
        /// ditto
        void orientation(Orientation value)
        {
            if (_orient == value)
                return;
            _orient = value;
            updateDrawables();
            requestLayout();
        }

        /// True if full scroll range is visible, and no need of scrolling at all
        bool fullRangeVisible() const
        {
            return _data.page >= _data.range;
        }
    }

    Signal!(bool delegate(ScrollAction, float)) onScroll;

    /// Jump length on lineUp/lineDown events
    float lineStep = 0;

    private
    {
        ScrollData _data;

        Orientation _orient = Orientation.vertical;

        ScrollIndicator _indicator;
        Element _pageUp;
        Element _pageDown;
        ElemImage _btnBack;
        ElemImage _btnForward;

        Box _scrollArea;
        float _minIndicatorSize = 0;
        float _btnSize = 0;
    }

    this(ScrollData data)
        in(data)
    {
        _data = data;
        _data.onChange ~= &handleDataChange;
        _btnBack = new ElemImage;
        _btnForward = new ElemImage;
        _btnBack.setAttribute("button-back");
        _btnForward.setAttribute("button-forward");
        _btnBack.allowsClick = true;
        _btnBack.allowsHover = true;
        _btnForward.allowsClick = true;
        _btnForward.allowsHover = true;
        _pageUp = new PageScrollButton;
        _pageDown = new PageScrollButton;
        _indicator = new ScrollIndicator;
        updateDrawables();

        _hiddenChildren.reserve(5);
        foreach (el; tup(_btnBack, _btnForward, _indicator, _pageUp, _pageDown))
        {
            el.parent = this;
            _hiddenChildren.append(el);
        }

        _btnBack.onClick ~= { triggerAction(ScrollAction.lineUp); };
        _btnForward.onClick ~= { triggerAction(ScrollAction.lineDown); };
        _pageUp.onClick ~= { triggerAction(ScrollAction.pageUp); };
        _pageDown.onClick ~= { triggerAction(ScrollAction.pageDown); };
    }

    ~this()
    {
        _data.onChange -= &handleDataChange;
    }

    override void handleThemeChange()
    {
        super.handleThemeChange();
        updateDrawables();
    }

    protected void updateDrawables()
    {
        const vert = _orient == Orientation.vertical;
        _btnBack.drawable = currentTheme.getDrawable(vert ?
            "scrollbar_button_up" : "scrollbar_button_left");
        _btnForward.drawable = currentTheme.getDrawable(vert ?
            "scrollbar_button_down" : "scrollbar_button_right");
        _indicator.drawable = currentTheme.getDrawable(vert ?
            "scrollbar_indicator_vertical" : "scrollbar_indicator_horizontal");
    }

    final void triggerAction(ScrollAction action)
    {
        float pos = _data.position + getDefaultOffset(action);
        _data.adjustPos(pos);
        sendEvent(action, pos);
    }

    final void moveTo(float position)
    {
        _data.adjustPos(position);
        if (_data.position != position)
            sendEvent(ScrollAction.moved, position);
    }

    private bool insideHandler;
    private void sendEvent(ScrollAction a, float pos)
    {
        assert(!insideHandler, "Cannot trigger a scrollbar action inside the event handler");

        if (onScroll.assigned)
        {
            insideHandler = true;
            const done = !onScroll(a, pos);
            insideHandler = false;
            if (done)
                return;
        }
        _data.position = pos;
    }

    /// Default scroll offset on pageUp/pageDown, lineUp/lineDown actions
    protected float getDefaultOffset(ScrollAction action) const
    {
        float delta = 0;
        switch (action) with (ScrollAction)
        {
        case lineUp:
        case lineDown:
            delta = lineStep > 0 ? lineStep : max(_data.page * 0.1f, 1);
            if (action == lineUp)
                delta *= -1;
            break;
        case pageUp:
        case pageDown:
            delta = max(_data.page * 0.75f, lineStep, 1);
            if (action == pageUp)
                delta *= -1;
            break;
        default:
            break;
        }
        return delta;
    }

    protected void handleIndicatorDragging(float initialValue, float currentValue)
    {
        moveTo(currentValue);
    }

    protected void handleDataChange()
    {
        if (!needLayout)
        {
            layoutButtons();
            invalidate();
        }
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        const delta = _orient == Orientation.horizontal ? event.deltaX : event.deltaY;
        if (delta != 0)
        {
            triggerAction(delta > 0 ? ScrollAction.lineDown : ScrollAction.lineUp);
            return true;
        }
        return super.handleWheelEvent(event);
    }

    protected bool calcButtonSizes(float availableSize, ref float spaceBackSize, ref float spaceForwardSize,
            ref float indicatorSize)
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
        const before = _data.position;
        const after = r - before - _data.page;
        assert(before + after > 0);
        spaceBackSize = spaceLeft * before / (before + after);
        spaceForwardSize = spaceLeft - spaceBackSize;
        return true;
    }

    protected void layoutButtons()
    {
        Box ibox = _scrollArea;
        if (_orient == Orientation.vertical)
        {
            float spaceBackSize = 0, spaceForwardSize = 0, indicatorSize = 0;
            bool indicatorVisible = calcButtonSizes(_scrollArea.h, spaceBackSize, spaceForwardSize, indicatorSize);
            ibox.y += spaceBackSize;
            ibox.h -= spaceBackSize + spaceForwardSize;
        }
        else // horizontal
        {
            float spaceBackSize = 0, spaceForwardSize = 0, indicatorSize = 0;
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
            const top = ibox.y - b.y;
            const bottom = b.y + b.h - (ibox.y + ibox.h);
            if (top > 0)
            {
                _pageUp.visibility = Visibility.visible;
                _pageUp.layout(Box(b.x, b.y, b.w, top));
            }
            else
                _pageUp.visibility = Visibility.hidden;
            if (bottom > 0)
            {
                _pageDown.visibility = Visibility.visible;
                _pageDown.layout(Box(b.x, b.y + b.h - bottom, b.w, bottom));
            }
            else
                _pageDown.visibility = Visibility.hidden;
        }
        else
        {
            const left = ibox.x - b.x;
            const right = b.x + b.w - (ibox.x + ibox.w);
            if (left > 0)
            {
                _pageUp.visibility = Visibility.visible;
                _pageUp.layout(Box(b.x, b.y, left, b.h));
            }
            else
                _pageUp.visibility = Visibility.hidden;
            if (right > 0)
            {
                _pageDown.visibility = Visibility.visible;
                _pageDown.layout(Box(b.x + b.w - right, b.y, right, b.h));
            }
            else
                _pageDown.visibility = Visibility.hidden;
        }
    }

    /// Hide controls when scroll is not possible
    protected void updateVisibility()
    {
        const canScroll = _data.range > _data.page;
        if (canScroll)
        {
            _indicator.visibility = Visibility.visible;
            const up = _data.position > 0;
            const down = _data.position < _data.range - _data.page;
            _pageUp.visibility = up ? Visibility.visible : Visibility.hidden;
            _pageDown.visibility = down ? Visibility.visible : Visibility.hidden;
        }
        else
        {
            foreach (Element el; tup(_indicator, _pageUp, _pageDown))
                el.visibility = Visibility.gone;
        }
        _btnBack.applyState(State.enabled, canScroll);
        _btnForward.applyState(State.enabled, canScroll);
    }

    override void cancelLayout()
    {
        foreach (Element el; tup(_indicator, _pageUp, _pageDown, _btnBack, _btnForward))
            el.cancelLayout();
        super.cancelLayout();
    }

    override protected Boundaries computeBoundaries()
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
        return bs;
    }

    override protected void arrangeContent()
    {
        Box geom = innerBox;
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

    override protected void drawContent(Painter pr)
    {
        foreach (Element el; tup(_btnBack, _btnForward, _pageUp, _pageDown, _indicator))
            el.draw(pr);
    }

    class ScrollIndicator : ElemImage
    {
        @property void scrollArea(Box b)
        {
            _scrollArea = b;
        }

        private
        {
            bool _dragging;
            Point _dragStart;
            float _dragStartPos = 0;
            Box _dragStartBox;

            Box _scrollArea;
        }

        this()
        {
            allowsHover = true;
        }

        override bool handleMouseEvent(MouseEvent event)
        {
            if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
            {
                applyState(State.pressed, true);
                _dragging = true;
                _dragStart.x = event.x;
                _dragStart.y = event.y;
                _dragStartPos = _data.position;
                _dragStartBox = box;
                triggerAction(ScrollAction.pressed);
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
                const delta = _orient == Orientation.vertical ?
                        event.y - _dragStart.y : event.x - _dragStart.x;
                debug (scrollbars)
                    Log.d("ScrollIndicator: dragging, move delta: ", delta);
                Box b = _dragStartBox;
                float offset = 0;
                float space = 0;
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
                float v = 0;
                if (space > 0)
                    v = offset * max(_data.range - _data.page, 0) / space;
                handleIndicatorDragging(_dragStartPos, v);
                return true;
            }
            if (event.action == MouseAction.buttonUp && event.button == MouseButton.left)
            {
                applyState(State.pressed, false);
                if (_dragging)
                {
                    triggerAction(ScrollAction.released);
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
                    applyState(State.hovered, true);
                }
                return true;
            }
            if (event.action == MouseAction.leave && allowsHover)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: leave");
                applyState(State.hovered, false);
                return true;
            }
            if (event.action == MouseAction.cancel && allowsHover)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: cancel with allowsHover");
                applyState(State.hovered, false);
                applyState(State.pressed, false);
                _dragging = false;
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                debug (scrollbars)
                    Log.d("ScrollIndicator: cancel");
                applyState(State.pressed, false);
                _dragging = false;
                return true;
            }
            return false;
        }
    }

    class PageScrollButton : Element
    {
        this()
        {
            allowsClick = true;
            allowsHover = true;
        }
    }
}
