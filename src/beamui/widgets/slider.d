/**
Slider controls.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.slider;

import std.math : isFinite, quantize;
import beamui.widgets.controls;
import beamui.widgets.widget;

/// Component for slider data. It validates it and reacts on changes
class SliderData
{
    final @property
    {
        /// Slider current value
        double value() const { return _value; }
        /// ditto
        void value(double v)
        {
            adjustValue(v);
            if (_value != v)
            {
                _value = v;
                changed();
            }
        }
        /// Slider range min value
        double minValue() const { return _minValue; }
        /// Slider range max value
        double maxValue() const { return _maxValue; }
        /// Step between values. Always > 0
        double step() const { return _step; }
        /// The difference between max and min values. Always >= 0
        double range() const { return _maxValue - _minValue; }
        /// Page size (visible area size in scrollbars). Always >= 0, may be > `range`
        double pageSize() const { return _pageSize; }
        /// ditto
        void pageSize(double v)
        {
            assert(isFinite(v));
            v = max(v, 0);
            if (_pageSize != v)
            {
                _pageSize = v;
                adjustValue(_value);
                changed();
            }
        }
    }

    Signal!(void delegate()) changed;

    private
    {
        double _value = 0;
        double _minValue = 0;
        double _maxValue = 100;
        double _step = 1;
        double _pageSize = 0;
    }

    /** Set new range (min, max, and step values for slider).

        `min` must not be more than `max`, `step` must be more than 0.
    */
    final void setRange(double min, double max, double step = 1)
    {
        assert(isFinite(min));
        assert(isFinite(max));
        assert(isFinite(step));
        assert(min <= max);
        assert(step > 0);

        if (_minValue != min || _maxValue != max || _step != step)
        {
            _minValue = min;
            _maxValue = max;
            _step = step;
            adjustValue(_value);
            changed();
        }
    }

    private void adjustValue(ref double v)
    {
        assert(isFinite(v));

        if (v > _minValue)
        {
            const uplim = max(_maxValue - _pageSize, _minValue);
            v = min(quantize(v - _minValue, _step) + _minValue, uplim);
        }
        else
            v = _minValue;
    }
}

/// Slider action codes for `SliderEvent`
enum SliderAction : ubyte
{
    pressed,  /// Indicator dragging started
    moved,    /// Dragging in progress
    released, /// Dragging finished
    pageUp,   /// Space above indicator pressed
    pageDown, /// Space below indicator pressed
    lineUp,   /// Up/left button pressed
    lineDown, /// Down/right button pressed
}

/// Slider event
final class SliderEvent
{
    const SliderAction action;
    const SliderData data;
    const double value;
    private double amendment;

    this(SliderAction a, SliderData d, double v)
    {
        action = a;
        data = d;
        value = v;
    }

    /// Set new slider value in an event handler
    void amend(double value)
    {
        amendment = value;
    }
}

/// Base class for sliders
abstract class AbstractSlider : WidgetGroup
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
    Signal!(void delegate(SliderEvent event)) scrolled;

    private
    {
        SliderData _data;

        // not _orientation to not intersect with inner buttons _orientation
        Orientation _orient = Orientation.vertical;

        SliderButton _indicator;
        SliderBar _rangeBefore;
        SliderBar _rangeAfter;

        Box _scrollArea;
        int _minIndicatorSize;
    }

    this(Orientation orient, SliderData data)
    {
        assert(data);
        data.changed ~= &onDataChanged;
        _data = data;
        _orient = orient;
        isolateStyle();
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

    void sendScrollEvent(SliderAction action)
    {
        if (scrolled.assigned)
        {
            auto event = new SliderEvent(action, _data, _data.value);
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
        _data.adjustValue(value);
        if (_data.value == value)
            return;

        if (scrolled.assigned)
        {
            auto event = new SliderEvent(SliderAction.moved, _data, value);
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
    protected double getDefaultOffset(SliderAction action) const
    {
        double delta = 0;
        switch (action) with (SliderAction)
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
        if (event.action == MouseAction.wheel)
        {
            const delta = event.wheelDelta;
            if (delta != 0)
                sendScrollEvent(delta > 0 ? SliderAction.lineDown : SliderAction.lineUp);
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
                _rangeBefore.visibility = Visibility.visible;
                _rangeBefore.layout(Box(b.x, b.y, b.w, top));
            }
            else
            {
                _rangeBefore.visibility = Visibility.hidden;
            }
            if (bottom > 0)
            {
                _rangeAfter.visibility = Visibility.visible;
                _rangeAfter.layout(Box(b.x, b.y + b.h - bottom, b.w, bottom));
            }
            else
            {
                _rangeAfter.visibility = Visibility.hidden;
            }
        }
        else
        {
            int left = ibox.x - b.x;
            int right = b.x + b.w - (ibox.x + ibox.w);
            if (left > 0)
            {
                _rangeBefore.visibility = Visibility.visible;
                _rangeBefore.layout(Box(b.x, b.y, left, b.h));
            }
            else
            {
                _rangeBefore.visibility = Visibility.hidden;
            }
            if (right > 0)
            {
                _rangeAfter.visibility = Visibility.visible;
                _rangeAfter.layout(Box(b.x + b.w - right, b.y, right, b.h));
            }
            else
            {
                _rangeAfter.visibility = Visibility.hidden;
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
        bunch(_indicator, _rangeBefore, _rangeAfter).cancelLayout();
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
            allowsFocus = true;
            allowsHover = true;
        }

        override bool onMouseEvent(MouseEvent event)
        {
            if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
            {
                setState(State.pressed);
                if (canFocus)
                    setFocus();
                _dragging = true;
                _dragStart.x = event.x;
                _dragStart.y = event.y;
                _dragStartValue = _data.value;
                _dragStartBox = box;
                sendScrollEvent(SliderAction.pressed);
                return true;
            }
            if (event.action == MouseAction.focusIn && _dragging)
            {
                debug (sliders)
                    Log.d("SliderButton: dragging, focusIn");
                return true;
            }
            if (event.action == MouseAction.focusOut && _dragging)
            {
                debug (sliders)
                    Log.d("SliderButton: dragging, focusOut");
                return true;
            }
            if (event.action == MouseAction.move && _dragging)
            {
                int delta = _orient == Orientation.vertical ?
                        event.y - _dragStart.y : event.x - _dragStart.x;
                debug (sliders)
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
                    sendScrollEvent(SliderAction.released);
                    _dragging = false;
                }
                return true;
            }
            if (event.action == MouseAction.move && allowsHover)
            {
                if (!(state & State.hovered))
                {
                    debug (sliders)
                        Log.d("SliderButton: hover");
                    setState(State.hovered);
                }
                return true;
            }
            if (event.action == MouseAction.leave && allowsHover)
            {
                debug (sliders)
                    Log.d("SliderButton: leave");
                resetState(State.hovered);
                return true;
            }
            if (event.action == MouseAction.cancel && allowsHover)
            {
                debug (sliders)
                    Log.d("SliderButton: cancel with allowsHover");
                resetState(State.hovered);
                resetState(State.pressed);
                _dragging = false;
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                debug (sliders)
                    Log.d("SliderButton: cancel");
                resetState(State.pressed);
                _dragging = false;
                return true;
            }
            return false;
        }
    }

    class SliderBar : Widget
    {
        this(string ID)
        {
            super(ID);
            allowsClick = true;
            allowsFocus = false;
            allowsHover = true;
        }
    }
}

/// Slider widget - either vertical or horizontal
class Slider : AbstractSlider
{
    this(Orientation orient = Orientation.horizontal, SliderData data = null)
    {
        super(orient, data ? data : new SliderData);
        _rangeBefore = new SliderBar("RANGE_BEFORE");
        _rangeAfter = new SliderBar("RANGE_AFTER");
        _indicator = new SliderButton;
        updateDrawables();
        addChildren(_indicator, _rangeBefore, _rangeAfter);
        _rangeBefore.bindSubItem(this, "range-before");
        _rangeAfter.bindSubItem(this, "range-after");
        _rangeBefore.clicked ~= { sendScrollEvent(SliderAction.pageUp); };
        _rangeAfter.clicked ~= { sendScrollEvent(SliderAction.pageDown); };
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
            bunch(_rangeBefore, _rangeAfter).visibility(Visibility.visible);
        }
        else
        {
            bunch(_rangeBefore, _rangeAfter).visibility(Visibility.gone);
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
        const saver = ClipRectSaver(buf, b, style.alpha);
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
        bunch(_rangeBefore, _rangeAfter, _indicator).onDraw(buf);

        drawn();
    }
}
