/**
Slider controls.

Synopsis:
---
auto slider = new Slider(Orientation.horizontal);
// slider values are stored inside `.data`
slider.data.value = 0;
slider.data.setRange(-50, 50);
slider.scrolled ~= (SliderEvent event) {
    if (event.action == SliderAction.moved)
        Log.d(event.value);
};
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.slider;

import std.math : isFinite, quantize;
import beamui.widgets.controls;
import beamui.widgets.widget;

/// Base for slider data components. They validate data and react on changes
class SliderDataBase
{
    final @property
    {
        /// Slider range min value
        double minValue() const { return _minValue; }
        /// Slider range max value. Always >= `minValue`
        double maxValue() const { return _maxValue; }
        /// Step between values. Always > 0
        double step() const { return _step; }
        /// The difference between max and min values. Always >= 0
        double range() const { return _maxValue - _minValue; }
    }

    Signal!(void delegate()) changed;

    private
    {
        double _minValue = 0;
        double _maxValue = 100;
        double _step = 1;
    }

    /** Set new range (min, max, and step values for slider).

        `min` must be <= `max`, `step` must be > 0.
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
            adjustValue();
            changed();
        }
    }

    void adjustValue() {}
}

/// Component for slider data
class SliderData : SliderDataBase
{
    final @property
    {
        /// Single current value
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
    }

    private double _value = 0;

    override void adjustValue()
    {
        adjustValue(_value);
    }

    final void adjustValue(ref double v)
    {
        assert(isFinite(v));

        const mn = _minValue;
        const mx = _maxValue;
        v = v > mn ? min(quantize(v - mn, _step) + mn, mx) : mn;
    }
}

/// Data component for sliders used to select a range between two values
class RangeSliderData : SliderDataBase
{
    final @property
    {
        /// The first value
        double first() const { return _first; }
        /// ditto
        void first(double v)
        {
            adjustFirst(v);
            if (_first != v)
            {
                _first = v;
                changed();
            }
        }
        /// The second value
        double second() const { return _second; }
        /// ditto
        void second(double v)
        {
            adjustSecond(v);
            if (_second != v)
            {
                _second = v;
                changed();
            }
        }
        /// Difference between `second` and `first`. Always >= 0
        double innerRange() const { return _second - _first; }
    }

    private double _first = 0;
    private double _second = 0;

    override void adjustValue()
    {
        _second = max(_second, _first);
    }

    final void adjustFirst(ref double v)
    {
    }

    final void adjustSecond(ref double v)
    {
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

    /// `data.step` factor for pageDown/pageUp events
    uint pageStep = 5;

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
            delta = _data.step;
            if (action == lineUp)
                delta *= -1;
            break;
        case pageUp:
        case pageDown:
            delta = pageStep > 0 ? _data.step * pageStep : _data.step;
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

    protected bool calcButtonSizes(int availableSize, ref int spaceBefore, ref int spaceAfter,
            ref int indicatorSize)
    {
        const r = _data.range;
        if (r == 0)
        {
            // full size
            spaceBefore = spaceAfter = 0;
            indicatorSize = availableSize;
            return false;
        }
        indicatorSize = max(_minIndicatorSize, 0);
        if (indicatorSize >= availableSize)
        {
            // full size
            spaceBefore = spaceAfter = 0;
            indicatorSize = availableSize;
            return false;
        }
        const spaceLeft = availableSize - indicatorSize;
        const before = _data.value - _data.minValue;
        const after = r - before;
        assert(before + after > 0);
        spaceBefore = cast(int)(spaceLeft * before / (before + after));
        spaceAfter = spaceLeft - spaceBefore;
        return true;
    }

    protected void layoutButtons()
    {
        Box ibox = _scrollArea;
        if (_orient == Orientation.vertical)
        {
            int spaceBefore, spaceAfter, indicatorSize;
            bool indicatorVisible = calcButtonSizes(_scrollArea.h, spaceBefore, spaceAfter, indicatorSize);
            ibox.y += spaceBefore;
            ibox.h -= spaceBefore + spaceAfter;
        }
        else // horizontal
        {
            int spaceBefore, spaceAfter, indicatorSize;
            bool indicatorVisible = calcButtonSizes(_scrollArea.w, spaceBefore, spaceAfter, indicatorSize);
            ibox.x += spaceBefore;
            ibox.w -= spaceBefore + spaceAfter;
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

        override bool onKeyEvent(KeyEvent event)
        {
            if (event.action != KeyAction.keyDown)
                return super.onKeyEvent(event);

            if (event.key == Key.left || event.key == Key.down)
            {
                sendScrollEvent(SliderAction.lineUp);
                return true;
            }
            if (event.key == Key.right || event.key == Key.up)
            {
                sendScrollEvent(SliderAction.lineDown);
                return true;
            }
            if (event.key == Key.pageDown)
            {
                sendScrollEvent(SliderAction.pageDown);
                return true;
            }
            if (event.key == Key.pageUp)
            {
                sendScrollEvent(SliderAction.pageUp);
                return true;
            }
            if (event.key == Key.home)
            {
                sendScrollEvent(_data.minValue);
                return true;
            }
            if (event.key == Key.end)
            {
                sendScrollEvent(_data.maxValue);
                return true;
            }
            return super.onKeyEvent(event);
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
                    v += offset * _data.range / space;
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
        _rangeBefore.visibility = _data.value > _data.minValue ? Visibility.visible : Visibility.gone;
        _rangeAfter.visibility  = _data.value < _data.maxValue ? Visibility.visible : Visibility.gone;
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
