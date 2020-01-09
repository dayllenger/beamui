/**
Slider controls.

Synopsis:
---
auto slider = new Slider(Orientation.horizontal);
// slider values are stored inside `.data`
slider.data.value = 0;
slider.data.setRange(-50, 50);
slider.onScroll ~= (SliderEvent event) {
    if (event.action == SliderAction.moved)
        Log.d(event.value);
};
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.slider;

import std.math : abs, isFinite, quantize;
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

    Signal!(void delegate()) onChange;

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
            onChange();
        }
    }

    protected void adjustValue() {}
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
                onChange();
            }
        }
    }

    private double _value = 0;

    override protected void adjustValue()
    {
        adjustValue(_value);
    }

    final void adjustValue(ref double v) const
    {
        assert(isFinite(v));

        const mn = _minValue;
        const mx = _maxValue;
        if (v <= mn)
            v = mn;
        else if (v >= mx)
            v = mx;
        else
            v = min(quantize(v - mn, _step) + mn, mx);
    }
}

/// Data component for sliders used to select a range between two values
class RangeSliderData : SliderDataBase
{
    final @property
    {
        /// The first value
        double first() const { return _first; }
        /// The second value
        double second() const { return _second; }
        /// Difference between `second` and `first`. Always >= 0
        double innerRange() const { return _second - _first; }
    }

    private double _first = 0;
    private double _second = 0;

    /// Set two slider values together. If `fst` > `snd`, the first value will push the second
    final void setValues(double fst, double snd)
    {
        const oldFst = _first;
        const oldSnd = _second;
        _second = _maxValue;
        adjustFirst(fst);
        _first = fst;
        adjustSecond(snd);
        _second = snd;
        if (oldFst != fst || oldSnd != snd)
            onChange();
    }

    override protected void adjustValue()
    {
        _first = max(_first, _minValue);
        _second = min(_second, _maxValue);
        adjustFirst(_first);
        adjustSecond(_second);
    }

    final void adjustFirst(ref double v) const
    {
        assert(isFinite(v));

        const mn = _minValue;
        const mx = _second;
        if (v <= mn)
            v = mn;
        else if (v >= mx)
            v = mx;
        else
            v = min(quantize(v - mn, _step) + mn, mx);
    }

    final void adjustSecond(ref double v) const
    {
        assert(isFinite(v));

        const mn = _first;
        const mx = _maxValue;
        if (v <= mn)
            v = mn;
        else if (v >= mx)
            v = mx;
        else
            v = min(quantize(v - mn, _step) + mn, mx);
    }
}

/// Slider action codes for `SliderEvent`
enum SliderAction : ubyte
{
    press,     /// Dragging started
    move,      /// Dragging in progress
    release,   /// Dragging finished
    increase,  /// Increase by step, usually when up/right is pressed
    decrease,  /// Decrease by step, usually when down/left is pressed
    incPage,   /// Increase by page step, usually when pageUp is pressed
    decPage,   /// Decrease by page step, usually when pageDown is pressed
    moveToMin, /// Set to minimum value
    moveToMax, /// Set to maximum value
}

/// Slider event
final class SliderEvent
{
    const SliderAction action;
    const SliderDataBase data;
    /// Value after default event handling
    const double value;
    private double amendment;

    this(SliderAction a, SliderDataBase d, double v)
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
        inout(SliderDataBase) data() inout;

        /// Slider orientation (vertical, horizontal)
        Orientation orientation() const { return _orient; }
        /// ditto
        void orientation(Orientation value)
        {
            if (_orient != value)
            {
                _orient = value;
                if (value == Orientation.horizontal)
                {
                    removeAttribute("vertical");
                    setAttribute("horizontal");
                }
                else
                {
                    removeAttribute("horizontal");
                    setAttribute("vertical");
                }
                requestLayout();
            }
        }
    }

    /// `data.step` factor for incPage/decPage events
    uint pageStep = 5;

    private
    {
        Orientation _orient;

        SliderBar _rangeBefore;
        SliderBar _rangeAfter;
    }

    this(Orientation orient, scope SliderDataBase data)
    {
        assert(data);
        data.onChange ~= &handleDataChange;
        isolateStyle();
        _orient = orient;
        setAttribute(orient == Orientation.horizontal ? "horizontal" : "vertical");
        _rangeBefore = new SliderBar;
        _rangeAfter = new SliderBar;
        _rangeBefore.bindSubItem(this, "range-before");
        _rangeAfter.bindSubItem(this, "range-after");
        addChild(_rangeBefore);
        addChild(_rangeAfter);
    }

    /// Get default slider value for some actions. It doesn't clamp them by default
    protected double getDefaultValue(SliderAction action, double was) const
    {
        switch (action) with (SliderAction)
        {
        case increase:
            return was + data.step;
        case decrease:
            return was - data.step;
        case incPage:
        case decPage:
            const delta = pageStep > 0 ? data.step * pageStep : data.step;
            if (action == incPage)
                return was + delta;
            else
                return was - delta;
        case moveToMin:
            return data.minValue;
        case moveToMax:
            return data.maxValue;
        default:
            return was;
        }
    }

    protected void handleDataChange()
    {
        if (!needLayout)
        {
            layout(box); // redo layout of the slider only
            invalidate();
        }
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        setBox(geom);

        const b = innerBox;
        Box innerArea = b;
        // lay out bars before and after handles
        float spaceBefore = 0;
        float spaceAfter = 0;
        if (_orient == Orientation.horizontal)
        {
            calcSpace(b.w, spaceBefore, spaceAfter);
            innerArea.x += spaceBefore;
            innerArea.w -= spaceBefore + spaceAfter;

            if (spaceBefore > 0)
            {
                _rangeBefore.visibility = Visibility.visible;
                _rangeBefore.layout(Box(b.x, b.y, spaceBefore, b.h));
            }
            else
                _rangeBefore.visibility = Visibility.hidden;
            if (spaceAfter > 0)
            {
                _rangeAfter.visibility = Visibility.visible;
                _rangeAfter.layout(Box(b.x + b.w - spaceAfter, b.y, spaceAfter, b.h));
            }
            else
                _rangeAfter.visibility = Visibility.hidden;
        }
        else // vertical
        {
            calcSpace(b.h, spaceBefore, spaceAfter);
            innerArea.y += spaceAfter;
            innerArea.h -= spaceBefore + spaceAfter;
            // 'before' is on bottom, 'after' is on top
            if (spaceBefore > 0)
            {
                _rangeBefore.visibility = Visibility.visible;
                _rangeBefore.layout(Box(b.x, b.y + b.h - spaceBefore, b.w, spaceBefore));
            }
            else
                _rangeBefore.visibility = Visibility.hidden;
            if (spaceAfter > 0)
            {
                _rangeAfter.visibility = Visibility.visible;
                _rangeAfter.layout(Box(b.x, b.y, b.w, spaceAfter));
            }
            else
                _rangeAfter.visibility = Visibility.hidden;
        }
        // lay out handles and other stuff
        layoutInner(b, innerArea);
    }

    protected void calcSpace(float availableSize, out float spaceBefore, out float spaceAfter);
    protected void layoutInner(Box scrollArea, Box innerArea);

    final protected float offsetAt(float space, double value) const
    {
        if (space <= 0) // no place
            return 0;

        const r = data.range;
        if (r > 0)
        {
            const fr = (value - data.minValue) / r;
            const dist = space * fr;
            return cast(float)dist;
        }
        else // empty range
            return space / 2;
    }

    override protected void drawContent(Painter pr)
    {
        _rangeBefore.draw(pr);
        _rangeAfter.draw(pr);
        drawInner(pr);
    }

    protected void drawInner(Painter pr);

    class SliderHandle : ImageWidget
    {
        Listener!(void delegate(SliderAction)) onAction;
        Listener!(void delegate(double)) onDragging;

        private
        {
            bool _dragging;
            int _dragStartEventPos;
            float _dragStartPos = 0;

            float _start = 0;
            float _span = 0;
        }

        this()
        {
            id = "SLIDER_BUTTON";
            allowsFocus = true;
            allowsHover = true;
        }

        void setScrollRange(float start, float span)
        {
            _start = start;
            _span = span;
        }

        override bool handleKeyEvent(KeyEvent event)
        {
            if (event.action != KeyAction.keyDown)
                return super.handleKeyEvent(event);

            if (event.key == Key.left || event.key == Key.down)
            {
                onAction(SliderAction.decrease);
                return true;
            }
            if (event.key == Key.right || event.key == Key.up)
            {
                onAction(SliderAction.increase);
                return true;
            }
            if (event.key == Key.pageUp)
            {
                onAction(SliderAction.decPage);
                return true;
            }
            if (event.key == Key.pageDown)
            {
                onAction(SliderAction.incPage);
                return true;
            }
            if (event.key == Key.home)
            {
                onAction(SliderAction.moveToMin);
                return true;
            }
            if (event.key == Key.end)
            {
                onAction(SliderAction.moveToMax);
                return true;
            }
            return super.handleKeyEvent(event);
        }

        override bool handleMouseEvent(MouseEvent event)
        {
            if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
            {
                setState(State.pressed);
                if (canFocus)
                    setFocus();
                _dragging = true;
                if (_orient == Orientation.horizontal)
                {
                    _dragStartEventPos = event.x;
                    _dragStartPos = box.x;
                }
                else
                {
                    _dragStartEventPos = event.y;
                    _dragStartPos = box.y;
                }
                onAction(SliderAction.press);
                return true;
            }
            if (event.action == MouseAction.focusIn && _dragging)
            {
                debug (sliders)
                    Log.d("SliderHandle: dragging, focusIn");
                return true;
            }
            if (event.action == MouseAction.focusOut && _dragging)
            {
                debug (sliders)
                    Log.d("SliderHandle: dragging, focusOut");
                return true;
            }
            if (event.action == MouseAction.move && _dragging)
            {
                const bool hor = _orient == Orientation.horizontal;
                const delta = (hor ? event.x : event.y) - _dragStartEventPos;
                debug (sliders)
                    Log.d("SliderHandle: dragging, move delta: ", delta);

                const p = _dragStartPos + delta - _start;
                const offset = hor ? p : _span - p;
                double v = data.minValue;
                if (_span > 0)
                    v += offset * data.range / _span;
                onDragging(v);
                return true;
            }
            if (event.action == MouseAction.buttonUp && event.button == MouseButton.left)
            {
                resetState(State.pressed);
                if (_dragging)
                {
                    onAction(SliderAction.release);
                    _dragging = false;
                }
                return true;
            }
            if (event.action == MouseAction.move && allowsHover)
            {
                if (!(state & State.hovered))
                {
                    debug (sliders)
                        Log.d("SliderHandle: hover");
                    setState(State.hovered);
                }
                return true;
            }
            if (event.action == MouseAction.leave && allowsHover)
            {
                debug (sliders)
                    Log.d("SliderHandle: leave");
                resetState(State.hovered);
                return true;
            }
            if (event.action == MouseAction.cancel && allowsHover)
            {
                debug (sliders)
                    Log.d("SliderHandle: cancel with allowsHover");
                resetState(State.hovered);
                resetState(State.pressed);
                _dragging = false;
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                debug (sliders)
                    Log.d("SliderHandle: cancel");
                resetState(State.pressed);
                _dragging = false;
                return true;
            }
            return false;
        }
    }

    class SliderBar : Widget
    {
        this()
        {
            allowsClick = true;
            allowsFocus = false;
            allowsHover = true;
        }
    }
}

/// Slider widget - either vertical or horizontal
class Slider : AbstractSlider
{
    override @property inout(SliderData) data() inout { return _data; }

    /// Slider event listeners
    Signal!(void delegate(SliderEvent)) onScroll;

    private
    {
        SliderData _data;
        SliderHandle _handle;
    }

    this(Orientation orient = Orientation.horizontal, SliderData data = null)
    {
        if (!data)
            data = new SliderData;
        super(orient, data);
        _data = data;
        _rangeBefore.onClick ~= {
            _handle.setFocus();
            triggerAction(SliderAction.decPage);
        };
        _rangeAfter.onClick ~= {
            _handle.setFocus();
            triggerAction(SliderAction.incPage);
        };
        _handle = new SliderHandle;
        _handle.onAction = &triggerAction;
        _handle.onDragging = &handleDragging;
        addChild(_handle);
    }

    final void triggerAction(SliderAction action)
    {
        const v = getDefaultValue(action, _data.value);
        sendEvent(action, clamp(v, _data.minValue, _data.maxValue));
    }

    final void moveTo(double value)
    {
        _data.adjustValue(value);
        if (_data.value != value)
            sendEvent(SliderAction.move, value);
    }

    private bool insideHandler;
    private void sendEvent(SliderAction a, double v)
    {
        assert(!insideHandler, "Cannot trigger a slider action inside the event handler");

        if (onScroll.assigned)
        {
            auto event = new SliderEvent(a, _data, v);
            insideHandler = true;
            onScroll(event);
            insideHandler = false;
            if (isFinite(event.amendment))
            {
                _data.value = event.amendment;
                return;
            }
        }
        _data.value = v;
    }

    protected void handleDragging(double computedValue)
    {
        moveTo(computedValue);
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        const delta = event.deltaX - event.deltaY;
        if (delta != 0)
        {
            triggerAction(delta > 0 ? SliderAction.increase : SliderAction.decrease);
            return true;
        }
        return super.handleWheelEvent(event);
    }

    private float handleSize = 0;
    override void measure()
    {
        _handle.measure();
        Boundaries bs = _handle.boundaries;
        if (_orient == Orientation.horizontal)
        {
            handleSize = bs.nat.w;
            bs.nat.w = bs.min.w = bs.nat.w * 5;
            bs.max.h = bs.nat.h = bs.min.h = bs.nat.h;
        }
        else
        {
            handleSize = bs.nat.h;
            bs.nat.h = bs.min.h = bs.nat.h * 5;
            bs.max.w = bs.nat.w = bs.min.w = bs.nat.w;
        }
        setBoundaries(bs);
    }

    override protected void calcSpace(float availableSize, out float spaceBefore, out float spaceAfter)
    {
        const space = availableSize - handleSize;
        if (space <= 0)
            return;

        spaceBefore = offsetAt(space, _data.value);
        spaceAfter = space - spaceBefore;
    }

    override protected void layoutInner(Box scrollArea, Box innerArea)
    {
        if (_orient == Orientation.horizontal)
            _handle.setScrollRange(scrollArea.x, scrollArea.w - handleSize);
        else
            _handle.setScrollRange(scrollArea.y, scrollArea.h - handleSize);
        _handle.layout(innerArea);
    }

    override protected void drawInner(Painter pr)
    {
        _handle.draw(pr);
    }
}

/// Slider widget with two handles to select a range between values
class RangeSlider : AbstractSlider
{
    override @property inout(RangeSliderData) data() inout { return _data; }

    /// The first handle event listeners
    Signal!(void delegate(SliderEvent)) onScroll1;
    /// The second handle event listeners
    Signal!(void delegate(SliderEvent)) onScroll2;

    private
    {
        RangeSliderData _data;
        SliderHandle _1stHandle;
        SliderHandle _2ndHandle;
        SliderBar _rangeBetween;
    }

    this(Orientation orient = Orientation.horizontal, RangeSliderData data = null)
    {
        if (!data)
            data = new RangeSliderData;
        super(orient, data);
        _data = data;
        _rangeBefore.onClick ~= {
            _1stHandle.setFocus();
            triggerActionOnFirst(SliderAction.decPage);
        };
        _rangeAfter.onClick ~= {
            _2ndHandle.setFocus();
            triggerActionOnSecond(SliderAction.incPage);
        };
        _1stHandle = new SliderHandle;
        _2ndHandle = new SliderHandle;
        _1stHandle.onAction = &triggerActionOnFirst;
        _2ndHandle.onAction = &triggerActionOnSecond;
        _1stHandle.onDragging = &handleDragging1;
        _2ndHandle.onDragging = &handleDragging2;
        _rangeBetween = new SliderBar;
        _rangeBetween.bindSubItem(this, "range-between");
        addChild(_1stHandle);
        addChild(_2ndHandle);
        addChild(_rangeBetween);
    }

    final void triggerActionOnFirst(SliderAction action)
    {
        const v = getDefaultValue(action, _data.first);
        sendEvent1(action, clamp(v, _data.minValue, _data.second));
    }

    final void triggerActionOnSecond(SliderAction action)
    {
        const v = getDefaultValue(action, _data.second);
        sendEvent2(action, clamp(v, _data.first, _data.maxValue));
    }

    final void moveFirstTo(double value)
    {
        _data.adjustFirst(value);
        if (_data.first != value)
            sendEvent1(SliderAction.move, value);
    }

    final void moveSecondTo(double value)
    {
        _data.adjustSecond(value);
        if (_data.second != value)
            sendEvent2(SliderAction.move, value);
    }

    private bool insideHandler;

    private void sendEvent1(SliderAction a, double v)
    {
        assert(!insideHandler, "Cannot trigger a slider action inside the event handler");

        if (onScroll1.assigned)
        {
            auto event = new SliderEvent(a, _data, v);
            insideHandler = true;
            onScroll1(event);
            insideHandler = false;
            if (isFinite(event.amendment))
            {
                _data.setValues(event.amendment, _data.second);
                return;
            }
        }
        _data.setValues(v, _data.second);
    }

    private void sendEvent2(SliderAction a, double v)
    {
        assert(!insideHandler, "Cannot trigger a slider action inside the event handler");

        if (onScroll2.assigned)
        {
            auto event = new SliderEvent(a, _data, v);
            insideHandler = true;
            onScroll2(event);
            insideHandler = false;
            if (isFinite(event.amendment))
            {
                _data.setValues(_data.first, event.amendment);
                return;
            }
        }
        _data.setValues(_data.first, v);
    }

    protected void handleDragging1(double computedValue)
    {
        moveFirstTo(computedValue);
    }

    protected void handleDragging2(double computedValue)
    {
        moveSecondTo(computedValue);
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        const delta = event.deltaX - event.deltaY;
        if (delta != 0)
        {
            const a = delta > 0 ? SliderAction.increase : SliderAction.decrease;
            // move the closest
            float diff1 = 0, diff2 = 0;
            if (_orient == Orientation.horizontal)
            {
                diff1 = event.x - (_1stHandle.box.x + _1stHandle.box.w / 2);
                diff2 = event.x - (_2ndHandle.box.x + _2ndHandle.box.w / 2);
            }
            else
            {
                diff1 = event.y - (_1stHandle.box.y + _1stHandle.box.h / 2);
                diff2 = event.y - (_2ndHandle.box.y + _2ndHandle.box.h / 2);
            }
            if (abs(diff1) < abs(diff2))
                triggerActionOnFirst(a);
            else
                triggerActionOnSecond(a);
            return true;
        }
        return super.handleWheelEvent(event);
    }

    private float[2] handleSizes = 0;
    override void measure()
    {
        Boundaries bs;
        _1stHandle.measure();
        _2ndHandle.measure();
        const bs1 = _1stHandle.boundaries;
        const bs2 = _2ndHandle.boundaries;
        if (_orient == Orientation.horizontal)
        {
            handleSizes[0] = bs1.nat.w;
            handleSizes[1] = bs2.nat.w;
            bs.addWidth(bs1);
            bs.addWidth(bs2);
            bs.maximizeHeight(bs1);
            bs.maximizeHeight(bs2);
            bs.nat.w = bs.min.w = bs.nat.w * 5;
            bs.max.h = bs.nat.h = bs.min.h = bs.nat.h;
        }
        else
        {
            handleSizes[0] = bs1.nat.h;
            handleSizes[1] = bs2.nat.h;
            bs.maximizeWidth(bs1);
            bs.maximizeWidth(bs2);
            bs.addHeight(bs1);
            bs.addHeight(bs2);
            bs.nat.h = bs.min.h = bs.nat.h * 5;
            bs.max.w = bs.nat.w = bs.min.w = bs.nat.w;
        }
        setBoundaries(bs);
    }

    override protected void calcSpace(float availableSize, out float spaceBefore, out float spaceAfter)
    {
        const space = availableSize - handleSizes[0] - handleSizes[1];
        if (space <= 0)
            return;

        spaceBefore = offsetAt(space, _data.first);
        spaceAfter = space - offsetAt(space, _data.second);
    }

    override protected void layoutInner(Box scrollArea, Box innerArea)
    {
        Box b1 = innerArea;
        Box b2 = innerArea;
        if (_orient == Orientation.horizontal)
        {
            b1.w = handleSizes[0];
            b2.w = handleSizes[1];
            b2.x += innerArea.w - b2.w;
            _1stHandle.setScrollRange(scrollArea.x, scrollArea.w - b1.w - b2.w);
            _2ndHandle.setScrollRange(scrollArea.x + b1.w, scrollArea.w - b1.w - b2.w);
            const between = innerArea.w - (b1.w + b2.w);
            if (between > 0)
            {
                _rangeBetween.visibility = Visibility.visible;
                _rangeBetween.layout(Box(b1.x + b1.w, b1.y, between, b1.h));
            }
            else
                _rangeBetween.visibility = Visibility.hidden;
        }
        else
        {
            b1.h = handleSizes[0];
            b2.h = handleSizes[1];
            b1.y += innerArea.h - b1.h; // the first handle is lower
            _1stHandle.setScrollRange(scrollArea.y + b2.h, scrollArea.h - b1.h - b2.h);
            _2ndHandle.setScrollRange(scrollArea.y, scrollArea.h - b1.h - b2.h);
            const between = innerArea.h - (b1.h + b2.h);
            if (between > 0)
            {
                _rangeBetween.visibility = Visibility.visible;
                _rangeBetween.layout(Box(b1.x, b2.y + b2.h, b1.w, between));
            }
            else
                _rangeBetween.visibility = Visibility.hidden;
        }
        _1stHandle.layout(b1);
        _2ndHandle.layout(b2);
    }

    override protected void drawInner(Painter pr)
    {
        _rangeBetween.draw(pr);
        _1stHandle.draw(pr);
        _2ndHandle.draw(pr);
    }
}

//===============================================================
// Tests

unittest
{
    static import std.math;

    double last;
    bool check(double v)
    {
        return std.math.approxEqual(last, v);
    }

    auto data = new SliderData;
    data.onChange ~= { last = data.value; };

    data.setRange(-10, 10, 0.1);
    assert(check(0));
    data.value = 5;
    assert(check(5));
    data.value = -50;
    assert(check(-10));
    data.value = 50;
    assert(check(10));
    data.value = 7.86;
    assert(check(7.9));

    data.setRange(-200, -100);
    assert(check(-100));
}

unittest
{
    static import std.math;

    double[2] last;
    bool check(double fst, double snd)
    {
        return std.math.approxEqual(last[0], fst) && std.math.approxEqual(last[1], snd);
    }

    auto data = new RangeSliderData;
    data.onChange ~= { last = [data.first, data.second]; };

    data.setRange(-10, 10, 0.1);
    assert(check(0, 0));
    data.setValues(2, 4);
    assert(check(2, 4));
    data.setValues(14, 12);
    assert(check(10, 10));
    data.setValues(11, 12);
    assert(check(10, 10));
    data.setValues(5, 12);
    assert(check(5, 10));
    data.setValues(0, 12);
    assert(check(0, 10));
    data.setValues(-15, 12);
    assert(check(-10, 10));
    data.setValues(5, 0);
    assert(check(5, 5));
    data.setValues(5, -12);
    assert(check(5, 5));
    data.setValues(-11, -12);
    assert(check(-10, -10));
    data.setValues(-14, -12);
    assert(check(-10, -10));

    data.setRange(-200, -100);
    assert(check(-100, -100));
}
