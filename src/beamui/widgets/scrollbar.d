/**
Simple scrollbar-like controls.

Synopsis:
---
auto slider = new Slider(Orientation.horizontal);
// slider values are stored inside of `.data`
slider.data.value = 0;
slider.data.setRange(-50, 50);
slider.scrolled ~= (ScrollEvent event) {
    if (event.action == ScrollAction.moved)
        Log.d(event.value);
};
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.scrollbar;

public import beamui.widgets.slider : SliderData;
import std.math : isFinite, quantize;
import beamui.widgets.controls;
import beamui.widgets.widget;

class ScrollData
{
    final @property
    {
        /// Scrollbar current position, in [0, 1] range
        double position() const { return _position; }
        /// ditto
        void position(double v)
        {
            adjustPos(v);
            if (_position != v)
            {
                _position = v;
                changed();
            }
        }
        /// Page size (visible area size), in [0, 1] range
        double pageSize() const { return _pageSize; }
        /// ditto
        void pageSize(double v)
        {
            assert(isFinite(v));
            v = clamp(v, 0, 1);
            if (_pageSize != v)
            {
                _pageSize = v;
                adjustPos(_position);
                changed();
            }
        }
        /// Step between positions, in [0, 1] range
        double step() const { return _step; }
        /// ditto
        void step(double v)
        {
            assert(isFinite(v));
            v = clamp(v, 0, 1);
            if (_step != v)
            {
                _step = v;
                adjustPos(_position);
                changed();
            }
        }
    }

    Signal!(void delegate()) changed;

    private
    {
        double _position = 0;
        double _pageSize = 1;
        double _step = 0;
    }

    private void adjustPos(ref double v, bool snap = false)
    {
        assert(isFinite(v));

        if (!snap || _step == 0)
            v = clamp(v, 0, 1);
        else
            v = v > 0 ? min(quantize(v, _step), 1) : 0;
    }
}

/// Scroll bar / slider action codes for `ScrollEvent`
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

/// Slider/scrollbar event
final class ScrollEvent
{
    const ScrollAction action;
    const SliderData data;
    const double value;
    private double amendment;

    this(ScrollAction a, SliderData d, double v)
    {
        action = a;
        data = d;
        value = v;
    }

    /// Set new slider value in an event handler
    void amend(int value)
    {
        amendment = value;
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
    Signal!(void delegate(ScrollEvent event)) scrolled;

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
        isolateStyle();
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

    void sendScrollEvent(ScrollAction action)
    {
        if (scrolled.assigned)
        {
            auto event = new ScrollEvent(action, _data, _data.value);
            scrolled(event);
            if (isFinite(event.amendment))
            {
                _data.value = event.amendment;
                return;
            }
        }
        _data.value = _data.value + getDefaultOffset(action);
    }

    void sendScrollEvent(double value)
    {
        if (_data.value == value)
            return;

        if (scrolled.assigned)
        {
            auto event = new ScrollEvent(ScrollAction.moved, _data, value);
            scrolled(event);
            if (isFinite(event.amendment))
            {
                _data.value = event.amendment;
                return;
            }
        }
        _data.value = value;
    }

    /// Default slider offset on pageUp/pageDown, lineUp/lineDown actions
    protected double getDefaultOffset(ScrollAction action) const
    {
        double delta = 0;
        switch (action) with (ScrollAction)
        {
        case lineUp:
        case lineDown:
            delta = max(_data.pageSize / 20, 1);
            if (action == lineUp)
                delta *= -1;
            break;
        case pageUp:
        case pageDown:
            delta = max(_data.pageSize * 3 / 4, 1);
            if (action == pageUp)
                delta *= -1;
            break;
        default:
            break;
        }
        return delta;
    }

    protected void onDataChanged()
    {
        if (!needLayout)
        {
            layoutButtons();
            invalidate();
        }
    }

    protected void onIndicatorDragging(double initialValue, double currentValue)
    {
        sendScrollEvent(currentValue);
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (visibility != Visibility.visible)
            return false;
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
        if (_data.pageSize >= r)
        {
            // full size
            spaceBackSize = spaceForwardSize = 0;
            indicatorSize = availableSize;
            return false;
        }
        indicatorSize = r > 0 ? cast(int)(_data.pageSize * availableSize / r) : 0;
        indicatorSize = max(indicatorSize, _minIndicatorSize);
        if (indicatorSize >= availableSize)
        {
            // full size
            spaceBackSize = spaceForwardSize = 0;
            indicatorSize = availableSize;
            return false;
        }
        const spaceLeft = availableSize - indicatorSize;
        const topv = _data.value - _data.minValue;
        const bottomv = r - topv - _data.pageSize;
        assert(topv + bottomv > 0);
        spaceBackSize = cast(int)(spaceLeft * topv / (topv + bottomv));
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
        // override
    }

    override void cancelLayout()
    {
        bunch(_indicator, _pageUp, _pageDown).cancelLayout();
        super.cancelLayout();
    }

    class SliderButton : ImageWidget
    {
        @property void scrollArea(Box b)
        {
            _scrollArea = b;
        }

        private
        {
            bool _dragging;
            Point _dragStart;
            double _dragStartValue;
            Box _dragStartBox;

            Box _scrollArea;
        }

        this()
        {
            id = "SLIDER_BUTTON";
        }

        override bool onMouseEvent(MouseEvent event)
        {
            if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
            {
                setState(State.pressed);
                _dragging = true;
                _dragStart.x = event.x;
                _dragStart.y = event.y;
                _dragStartValue = _data.value;
                _dragStartBox = box;
                sendScrollEvent(ScrollAction.pressed);
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
                double v = _data.minValue;
                if (space > 0)
                    v += offset * max(_data.range - _data.pageSize, 0) / space;
                onIndicatorDragging(_dragStartValue, v);
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
                        Log.d("SliderButton: hover");
                    setState(State.hovered);
                }
                return true;
            }
            if (event.action == MouseAction.leave && allowsHover)
            {
                debug (scrollbars)
                    Log.d("SliderButton: leave");
                resetState(State.hovered);
                return true;
            }
            if (event.action == MouseAction.cancel && allowsHover)
            {
                debug (scrollbars)
                    Log.d("SliderButton: cancel with allowsHover");
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
            allowsClick = true;
            allowsHover = true;
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
        bunch(_btnBack, _btnForward, _indicator, _pageUp, _pageDown).allowsFocus(false);
        _btnBack.clicked ~= { sendScrollEvent(ScrollAction.lineUp); };
        _btnForward.clicked ~= { sendScrollEvent(ScrollAction.lineDown); };
        _pageUp.clicked ~= { sendScrollEvent(ScrollAction.pageUp); };
        _pageDown.clicked ~= { sendScrollEvent(ScrollAction.pageDown); };
    }

    /// True if full scroll range is visible, and no need of scrolling at all
    @property bool fullRangeVisible() const
    {
        return _data.pageSize >= _data.range;
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

    override protected void updateVisibility()
    {
        const canScroll = _data.range > _data.pageSize;
        if (canScroll)
        {
            bunch(_btnBack, _btnForward).setState(State.enabled);
            _indicator.visibility = Visibility.visible;
            if (_data.value > _data.minValue)
                _pageUp.visibility = Visibility.visible;
            if (_data.value < _data.maxValue)
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
        _pageUp = new PageScrollButton("PAGE_UP");
        _pageDown = new PageScrollButton("PAGE_DOWN");
        _indicator = new SliderButton;
        updateDrawables();
        addChild(_indicator);
        addChild(_pageUp);
        addChild(_pageDown);
        bunch(_indicator, _pageUp, _pageDown).allowsFocus(false);
        _pageUp.clicked ~= { sendScrollEvent(ScrollAction.pageUp); };
        _pageDown.clicked ~= { sendScrollEvent(ScrollAction.pageDown); };
    }

    override protected void updateDrawables()
    {
        _indicator.drawable = currentTheme.getDrawable(_orient == Orientation.vertical ?
            "scrollbar_indicator_vertical" : "scrollbar_indicator_horizontal");
    }

    override protected void updateVisibility()
    {
        const canScroll = _data.range > _data.pageSize;
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
