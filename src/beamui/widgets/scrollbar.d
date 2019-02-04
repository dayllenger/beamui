/**
Simple scrollbar-like controls.

Synopsis:
---
import beamui.widgets.scrollbar;

auto slider = new Slider(Orientation.horizontal);
// slider values are stored inside of `.data`
slider.data.minValue = -50;
slider.data.maxValue = 50;
slider.data.position = 0;
slider.scrolled ~= (AbstractSlider source, ScrollEvent event) {
    if (event.action == ScrollAction.sliderMoved)
        Log.d(source.data.position);
};
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.scrollbar;

import beamui.widgets.controls;
import beamui.widgets.widget;

/// Slider component
class SliderData
{
    @property
    {
        /// Slider range min value
        int minValue() const { return _minValue; }
        /// ditto
        void minValue(int value)
        {
            if (_minValue != value)
            {
                _minValue = value;
                changed();
            }
        }
        /// Slider range max value
        int maxValue() const { return _maxValue; }
        /// ditto
        void maxValue(int value)
        {
            if (_maxValue != value)
            {
                _maxValue = value;
                changed();
            }
        }
        /// Page size (visible area size)
        int pageSize() const { return _pageSize; }
        /// ditto
        void pageSize(int value)
        {
            if (_pageSize != value)
            {
                _pageSize = value;
                changed();
            }
        }
        /// Slider position
        int position() const { return _position; }
        /// ditto
        void position(int value)
        {
            value = clamp(value, _minValue, _maxValue);
            if (_position != value)
            {
                _position = value;
                changed();
            }
        }
    }

    Signal!(void delegate()) changed;

    private
    {
        int _minValue = 0;
        int _maxValue = 100;
        int _pageSize = 30;
        int _position = 20;
    }

    /// Set new range (min and max values for slider)
    void setRange(int min, int max)
    {
        if (_minValue != min || _maxValue != max)
        {
            _minValue = min;
            _maxValue = max;
            changed();
        }
    }
}

/// Base class for widgets like scrollbars and sliders
class AbstractSlider : WidgetGroup
{
    @property
    {
        /// Slider data component
        inout(SliderData) data() inout { return _data; }

        /// Slider orientation (vertical, horizontal)
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
    }

    /// Scroll event listeners
    Signal!(void delegate(AbstractSlider source, ScrollEvent event)) scrolled;

    private
    {
        SliderData _data;

        // not _orientation to not intersect with inner buttons _orientation
        Orientation _orient = Orientation.vertical;

        SliderButton _indicator;
        PageScrollButton _pageUp;
        PageScrollButton _pageDown;

        Box _scrollArea;
        int _minIndicatorSize;
    }

    this()
    {
        _data = new SliderData;
        _data.changed ~= &onDataChanged;
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        updateDrawables();
    }

    protected void updateDrawables()
    {
        // override
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (visibility != Visibility.visible)
            return false;
        if (event.action == MouseAction.wheel)
        {
            int delta = event.wheelDelta;
            if (delta > 0)
                sendScrollEvent(ScrollAction.lineUp);
            else if (delta < 0)
                sendScrollEvent(ScrollAction.lineDown);
            return true;
        }
        return super.onMouseEvent(event);
    }

    bool sendScrollEvent(ScrollAction action)
    {
        return sendScrollEvent(action, _data.position);
    }

    bool sendScrollEvent(ScrollAction action, int pos)
    {
        if (!scrolled.assigned)
            return false;
        auto event = new ScrollEvent(action, _data.minValue, _data.maxValue, _data.pageSize, pos);
        scrolled(this, event);
        if (event.positionChanged)
            _data.position = event.position;
        return true;
    }

    protected void onDataChanged()
    {
        if (!needLayout)
            layoutButtons();
    }

    protected bool onIndicatorDragging(int initialPosition, int currentPosition)
    {
        _data.position = currentPosition;
        return sendScrollEvent(ScrollAction.sliderMoved, currentPosition);
    }

    override void cancelLayout()
    {
        bunch(_indicator, _pageUp, _pageDown).cancelLayout();
        super.cancelLayout();
    }

    /// Hide controls when scroll is not possible
    protected void updateState()
    {
        // override
    }

    protected bool calcButtonSizes(int availableSize, ref int spaceBackSize, ref int spaceForwardSize,
            ref int indicatorSize)
    {
        int dv = _data.maxValue - _data.minValue;
        if (_data.pageSize >= dv)
        {
            // full size
            spaceBackSize = spaceForwardSize = 0;
            indicatorSize = availableSize;
            return false;
        }
        dv = max(dv, 0);
        indicatorSize = max(dv ? _data.pageSize * availableSize / dv : 0, _minIndicatorSize);
        if (indicatorSize >= availableSize)
        {
            // full size
            spaceBackSize = spaceForwardSize = 0;
            indicatorSize = availableSize;
            return false;
        }
        int spaceLeft = availableSize - indicatorSize;
        int topv = max(_data.position - _data.minValue, 0);
        int bottomv = max(dv - (_data.position + _data.pageSize - _data.minValue), 0);
        spaceBackSize = cast(int)(cast(long)spaceLeft * topv / (topv + bottomv));
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
            layoutButtons(ibox);
        }
        else // horizontal
        {
            int spaceBackSize, spaceForwardSize, indicatorSize;
            bool indicatorVisible = calcButtonSizes(_scrollArea.w, spaceBackSize, spaceForwardSize, indicatorSize);
            ibox.x += spaceBackSize;
            ibox.w -= spaceBackSize + spaceForwardSize;
            layoutButtons(ibox);
        }
        updateState();
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

    class SliderButton : Button
    {
        bool _dragging;
        Point _dragStart;
        int _dragStartPosition;
        Box _dragStartBox;

        Box _scrollArea;

        this()
        {
            id = "SLIDER_BUTTON";
        }

        @property void scrollArea(Box b)
        {
            _scrollArea = b;
        }

        override bool onMouseEvent(MouseEvent event)
        {
            if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
            {
                setState(State.pressed);
                _dragging = true;
                _dragStart.x = event.x;
                _dragStart.y = event.y;
                _dragStartPosition = _data.position;
                _dragStartBox = box;
                sendScrollEvent(ScrollAction.sliderPressed);
                return true;
            }
            if (event.action == MouseAction.focusIn && _dragging)
            {
                debug (scrollbars)
                    Log.d("SliderButton: dragging, focusIn");
                return true;
            }
            if (event.action == MouseAction.focusOut && _dragging)
            {
                debug (scrollbars)
                    Log.d("SliderButton: dragging, focusOut");
                return true;
            }
            if (event.action == MouseAction.move && _dragging)
            {
                int delta = _orient == Orientation.vertical ?
                        event.y - _dragStart.y : event.x - _dragStart.x;
                debug (scrollbars)
                    Log.d("SliderButton: dragging, move delta: ", delta);
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
                layoutButtons(b);
                int position = cast(int)(space > 0 ? _data.minValue +
                    cast(long)offset * (_data.maxValue - _data.minValue - _data.pageSize) / space : 0);
                invalidate();
                onIndicatorDragging(_dragStartPosition, position);
                return true;
            }
            if (event.action == MouseAction.buttonUp && event.button == MouseButton.left)
            {
                resetState(State.pressed);
                if (_dragging)
                {
                    sendScrollEvent(ScrollAction.sliderReleased);
                    _dragging = false;
                }
                return true;
            }
            if (event.action == MouseAction.move && trackHover)
            {
                if (!(state & State.hovered))
                {
                    debug (scrollbars)
                        Log.d("SliderButton: hover");
                    setState(State.hovered);
                }
                return true;
            }
            if (event.action == MouseAction.leave && trackHover)
            {
                debug (scrollbars)
                    Log.d("SliderButton: leave");
                resetState(State.hovered);
                return true;
            }
            if (event.action == MouseAction.cancel && trackHover)
            {
                debug (scrollbars)
                    Log.d("SliderButton: cancel with trackHover");
                resetState(State.hovered);
                resetState(State.pressed);
                _dragging = false;
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                debug (scrollbars)
                    Log.d("SliderButton: cancel");
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
            trackHover = true;
            clickable = true;
        }
    }
}

/// Scroll bar - either vertical or horizontal
class ScrollBar : AbstractSlider
{
    private
    {
        Button _btnBack;
        Button _btnForward;

        int _btnSize;
    }

    this(Orientation orient = Orientation.vertical)
    {
        _orient = orient;
        _btnBack = new Button;
        _btnBack.id = "BACK";
        _btnBack.bindSubItem(this, "button");
        _btnForward = new Button;
        _btnForward.id = "FORWARD";
        _btnForward.bindSubItem(this, "button");
        _pageUp = new PageScrollButton("PAGE_UP");
        _pageDown = new PageScrollButton("PAGE_DOWN");
        _indicator = new SliderButton;
        updateDrawables();
        addChild(_btnBack);
        addChild(_btnForward);
        addChild(_indicator);
        addChild(_pageUp);
        addChild(_pageDown);
        bunch(_btnBack, _btnForward, _indicator, _pageUp, _pageDown).focusable(false);
        _btnBack.clicked ~= (Widget w) { sendScrollEvent(ScrollAction.lineUp); };
        _btnForward.clicked ~= (Widget w) { sendScrollEvent(ScrollAction.lineDown); };
        _pageUp.clicked ~= (Widget w) { sendScrollEvent(ScrollAction.pageUp); };
        _pageDown.clicked ~= (Widget w) { sendScrollEvent(ScrollAction.pageDown); };
    }

    /// True if full scroll range is visible, and no need of scrolling at all
    @property bool fullRangeVisible()
    {
        return _data.pageSize >= _data.maxValue - _data.minValue;
    }

    override protected void updateDrawables()
    {
        _btnBack.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_button_up" : "scrollbar_button_left");
        _btnForward.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_button_down" : "scrollbar_button_right");
        _indicator.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_indicator_vertical" : "scrollbar_indicator_horizontal");
    }

    override protected void updateState()
    {
        bool canScroll = _data.maxValue - _data.minValue > _data.pageSize;
        if (canScroll)
        {
            bunch(_btnBack, _btnForward).setState(State.enabled);
            _indicator.visibility = Visibility.visible;
            if (_data.position > _data.minValue)
                _pageUp.visibility = Visibility.visible;
            if (_data.position < _data.maxValue)
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
        bunch(_btnBack, _btnForward).cancelLayout();
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
}

/// Slider widget - either vertical or horizontal
class Slider : AbstractSlider
{
    this(Orientation orient = Orientation.horizontal)
    {
        _orient = orient;
        _data.pageSize = 1;
        _pageUp = new PageScrollButton("PAGE_UP");
        _pageDown = new PageScrollButton("PAGE_DOWN");
        _indicator = new SliderButton;
        updateDrawables();
        addChild(_indicator);
        addChild(_pageUp);
        addChild(_pageDown);
        bunch(_indicator, _pageUp, _pageDown).focusable(false);
        _pageUp.clicked ~= (Widget w) { sendScrollEvent(ScrollAction.pageUp); };
        _pageDown.clicked ~= (Widget w) { sendScrollEvent(ScrollAction.pageDown); };
    }

    override protected void updateDrawables()
    {
        _indicator.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_indicator_vertical" : "scrollbar_indicator_horizontal");
    }

    override protected void updateState()
    {
        bool canScroll = _data.maxValue - _data.minValue > _data.pageSize;
        if (canScroll)
        {
            bunch(_indicator, _pageUp, _pageDown).visibility(Visibility.visible);
        }
        else
        {
            bunch(_indicator, _pageUp, _pageDown).visibility(Visibility.gone);
        }
    }

    override void measure()
    {
        _indicator.measure();
        Boundaries bs = _indicator.boundaries;
        if (_orient == Orientation.vertical)
        {
            _minIndicatorSize = bs.nat.h;
            bs.nat.h = bs.min.h = bs.nat.h * 5;
            bs.max.w = bs.nat.w = bs.min.w = bs.nat.w;
        }
        else
        {
            _minIndicatorSize = bs.nat.w;
            bs.nat.w = bs.min.w = bs.nat.w * 5;
            bs.max.h = bs.nat.h = bs.min.h = bs.nat.h;
        }
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        geom = innerBox;

        _scrollArea = geom;
        _indicator.scrollArea = geom;
        layoutButtons();
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        Box b = box;
        auto saver = ClipRectSaver(buf, b, style.alpha);
        auto bg = background;
        {
            if (_orient == Orientation.vertical)
            {
                int dw = bg.width;
                b.x += (b.w - dw) / 2;
                b.w = dw;
            }
            else
            {
                int dh = bg.height;
                b.y += (b.h - dh) / 2;
                b.h = dh;
            }
            bg.drawTo(buf, b);
        }
        if (state & State.focused)
        {
            drawFocusRect(buf);
        }
        bunch(_pageUp, _pageDown, _indicator).onDraw(buf);

        drawn();
    }
}
