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

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.slider;

import std.math : abs, isFinite, quantize;
import beamui.widgets.controls;
import beamui.widgets.widget;

struct SliderRange
{
    @property
    {
        /// Slider range min value
        double minValue() const { return _minValue; }
        /// Slider range max value. Always >= `minValue`
        double maxValue() const { return _maxValue; }
        /// Step between values. Always > 0
        double step() const { return _step; }
    }

    private double _minValue = 0;
    private double _maxValue = 100;
    private double _step = 1;

    /** Make new range of min, max, and step values for a slider.

        `min` must be <= `max`, `step` must be > 0.
    */
    this(double min, double max, double step = 1)
        in(isFinite(min))
        in(isFinite(max))
        in(isFinite(step))
        in(min <= max)
        in(step > 0)
    {
        _minValue = min;
        _maxValue = max;
        _step = step;
    }
}

/// Base class for sliders
abstract class AbstractSlider : Widget
{
    protected SliderRange range;
    /// Slider orientation (vertical, horizontal)
    protected Orientation orientation;

    /// Step multiplier for incPage/decPage events
    uint pageStep = 5;

    this()
    {
        isolateStyle = true;
    }

    /// Get default slider value for some actions. It doesn't clamp them by default
    protected double getDefaultValue(SliderAction action, double previous) const
    {
        switch (action) with (SliderAction)
        {
        case increase:
            return previous + range._step;
        case decrease:
            return previous - range._step;
        case incPage:
        case decPage:
            const delta = pageStep > 0 ? range._step * pageStep : range._step;
            if (action == incPage)
                return previous + delta;
            else
                return previous - delta;
        case moveToMin:
            return range._minValue;
        case moveToMax:
            return range._maxValue;
        default:
            return previous;
        }
    }

    override protected void build()
    {
        if (orientation == Orientation.horizontal)
            setAttribute("horizontal");
        else
            setAttribute("vertical");
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemAbstractSlider el = fastCast!ElemAbstractSlider(element);
        el.orientation = orientation;
    }
}

/// Single-value slider widget - either vertical or horizontal
class Slider : AbstractSlider
{
    protected double value = 0;
    protected void delegate(double) onChange;

    /// Slider event listener
    void delegate(SliderAction, double) onScroll;

    static Slider make(
        double value,
        void delegate(double) onChange,
        SliderRange range,
        Orientation orientation = Orientation.horizontal,
    )
        in(isFinite(value))
    {
        Slider w = arena.make!Slider;
        w.range = range;
        w.orientation = orientation;
        w.value = w.adjustValue(value);
        w.onChange = onChange;
        return w;
    }

    private double adjustValue(double v) const
        in(isFinite(v))
    {
        const mn = range._minValue;
        const mx = range._maxValue;
        if (v <= mn)
            return mn;
        else if (v >= mx)
            return mx;
        else
            return min(quantize(v - mn, range._step) + mn, mx);
    }

    private void triggerAction(SliderAction action)
    {
        const v = clamp(getDefaultValue(action, value), range._minValue, range._maxValue);
        if (onScroll)
            onScroll(action, v);
        if (value != v && onChange)
            onChange(v);
    }

    private void moveTo(double v)
    {
        v = adjustValue(v);
        if (value != v)
        {
            if (onScroll)
                onScroll(SliderAction.move, v);
            if (onChange)
                onChange(v);
        }
    }

    protected alias enabled = typeof(super).enabled;

    override protected void build()
    {
        super.build();
        enabled = onChange || onScroll;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemSlider;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemSlider el = fastCast!ElemSlider(element);
        el.setData(value, range);
        el.onAction.clear();
        el.onDragging.clear();
        if (enabled)
        {
            el.onAction ~= &triggerAction;
            el.onDragging ~= &moveTo;
        }
    }
}

/// Slider widget with two handles to select a numeric range
class RangeSlider : AbstractSlider
{
    protected double first = 0;
    protected double second = 0;
    protected void delegate(double, double) onChange;

    /// The first handle event listener
    void delegate(SliderAction, double) onScroll1;
    /// The second handle event listener
    void delegate(SliderAction, double) onScroll2;

    /// If `first` > `second`, the first value will push the second
    static RangeSlider make(
        double first,
        double second,
        void delegate(double, double) onChange,
        SliderRange range,
        Orientation orientation = Orientation.horizontal,
    )
        in(isFinite(first))
        in(isFinite(second))
    {
        RangeSlider w = arena.make!RangeSlider;
        w.range = range;
        w.orientation = orientation;
        w.second = range._maxValue;
        w.first = w.adjustFirst(max(first, range._minValue));
        w.second = w.adjustSecond(min(second, range._maxValue));
        w.onChange = onChange;
        return w;
    }

    private double adjustFirst(double v) const
        in(isFinite(v))
    {
        const mn = range._minValue;
        const mx = second;
        if (v <= mn)
            return mn;
        else if (v >= mx)
            return mx;
        else
            return min(quantize(v - mn, range._step) + mn, mx);
    }

    private double adjustSecond(double v) const
        in(isFinite(v))
    {
        const mn = first;
        const mx = range._maxValue;
        if (v <= mn)
            return mn;
        else if (v >= mx)
            return mx;
        else
            return min(quantize(v - mn, range._step) + mn, mx);
    }

    private void triggerActionOnFirst(SliderAction action)
    {
        const v = clamp(getDefaultValue(action, first), range._minValue, second);
        if (onScroll1)
            onScroll1(action, v);
        if (first != v && onChange)
            onChange(v, second);
    }

    private void triggerActionOnSecond(SliderAction action)
    {
        const v = clamp(getDefaultValue(action, second), first, range._maxValue);
        if (onScroll2)
            onScroll2(action, v);
        if (second != v && onChange)
            onChange(first, v);
    }

    private void moveFirstTo(double v)
    {
        v = adjustFirst(v);
        if (first != v)
        {
            if (onScroll1)
                onScroll1(SliderAction.move, v);
            if (onChange)
                onChange(v, second);
        }
    }

    private void moveSecondTo(double v)
    {
        v = adjustSecond(v);
        if (second != v)
        {
            if (onScroll2)
                onScroll2(SliderAction.move, v);
            if (onChange)
                onChange(first, v);
        }
    }

    protected alias enabled = typeof(super).enabled;

    override protected void build()
    {
        super.build();
        enabled = onChange || onScroll1 || onScroll2;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemRangeSlider;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemRangeSlider el = fastCast!ElemRangeSlider(element);
        el.setData(first, second, range);
        el.onAction1.clear();
        el.onAction2.clear();
        el.onDragging1.clear();
        el.onDragging2.clear();
        if (enabled)
        {
            el.onAction1 ~= &triggerActionOnFirst;
            el.onAction2 ~= &triggerActionOnSecond;
            el.onDragging1 ~= &moveFirstTo;
            el.onDragging2 ~= &moveSecondTo;
        }
    }
}

/// Slider action codes
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

abstract class ElemAbstractSlider : ElemGroup
{
    @property
    {
        Orientation orientation() const { return _orient; }
        /// ditto
        void orientation(Orientation value)
        {
            if (_orient == value)
                return;
            _orient = value;
            requestLayout();
        }
    }

    private
    {
        double _minValue = 0;
        double _maxValue = 100;
        Orientation _orient;

        SliderBar _rangeBefore;
        SliderBar _rangeAfter;
    }

    this()
    {
        _rangeBefore = new SliderBar;
        _rangeAfter = new SliderBar;
        _rangeBefore.setAttribute("range-before");
        _rangeAfter.setAttribute("range-after");
        _rangeBefore.parent = this;
        _rangeAfter.parent = this;
        _hiddenChildren.append(_rangeBefore);
        _hiddenChildren.append(_rangeAfter);
    }

    protected void handleDataChange()
    {
        if (!needLayout)
        {
            layout(box); // redo layout of the slider only
            invalidate();
        }
    }

    override protected void arrangeContent()
    {
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

        const r = _maxValue - _minValue;
        if (r > 0)
        {
            const fr = (value - _minValue) / r;
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

    class SliderHandle : ElemImage
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
                if (allowsFocus)
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
                double v = _minValue;
                if (_span > 0)
                    v += offset * (_maxValue - _minValue) / _span;
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

    static class SliderBar : Element
    {
        this()
        {
            allowsClick = true;
            allowsFocus = false;
            allowsHover = true;
        }
    }
}

class ElemSlider : ElemAbstractSlider
{
    Signal!(void delegate(SliderAction)) onAction;
    Signal!(void delegate(double)) onDragging;

    private
    {
        double _value = 0;

        SliderHandle _handle;
    }

    this()
    {
        _rangeBefore.onClick ~= {
            _handle.setFocus();
            onAction(SliderAction.decPage);
        };
        _rangeAfter.onClick ~= {
            _handle.setFocus();
            onAction(SliderAction.incPage);
        };
        _handle = new SliderHandle;
        _handle.onAction = &onAction.emit;
        _handle.onDragging = &onDragging.emit;
        _handle.parent = this;
        _hiddenChildren.append(_handle);
    }

    final void setData(double value, ref const SliderRange range)
    {
        if (_value == value && _minValue == range._minValue && _maxValue == range._maxValue)
            return;

        assert(range._minValue <= value && value <= range._maxValue);
        _value = value;
        _minValue = range._minValue;
        _maxValue = range._maxValue;
        handleDataChange();
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        const delta = event.deltaX - event.deltaY;
        if (delta != 0)
        {
            onAction(delta > 0 ? SliderAction.increase : SliderAction.decrease);
            return true;
        }
        return super.handleWheelEvent(event);
    }

    private float handleSize = 0;
    override protected Boundaries computeBoundaries()
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
        return bs;
    }

    override protected void calcSpace(float availableSize, out float spaceBefore, out float spaceAfter)
    {
        const space = availableSize - handleSize;
        if (space <= 0)
            return;

        spaceBefore = offsetAt(space, _value);
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

class ElemRangeSlider : ElemAbstractSlider
{
    Signal!(void delegate(SliderAction)) onAction1;
    Signal!(void delegate(SliderAction)) onAction2;
    Signal!(void delegate(double)) onDragging1;
    Signal!(void delegate(double)) onDragging2;

    private
    {
        double _first = 0;
        double _second = 0;

        SliderHandle _1stHandle;
        SliderHandle _2ndHandle;
        SliderBar _rangeBetween;
    }

    this()
    {
        _rangeBefore.onClick ~= {
            _1stHandle.setFocus();
            onAction1(SliderAction.decPage);
        };
        _rangeAfter.onClick ~= {
            _2ndHandle.setFocus();
            onAction2(SliderAction.incPage);
        };
        _1stHandle = new SliderHandle;
        _2ndHandle = new SliderHandle;
        _1stHandle.onAction = &onAction1.emit;
        _2ndHandle.onAction = &onAction2.emit;
        _1stHandle.onDragging = &onDragging1.emit;
        _2ndHandle.onDragging = &onDragging2.emit;
        _rangeBetween = new SliderBar;
        _rangeBetween.setAttribute("range-between");
        _1stHandle.parent = this;
        _2ndHandle.parent = this;
        _rangeBetween.parent = this;
        _hiddenChildren.append(_1stHandle);
        _hiddenChildren.append(_2ndHandle);
        _hiddenChildren.append(_rangeBetween);
    }

    final void setData(double first, double second, ref const SliderRange range)
    {
        if (_first == first && _second == second && _minValue == range._minValue && _maxValue == range._maxValue)
            return;

        assert(range._minValue <= first && first <= second && second <= range._maxValue);
        _minValue = range._minValue;
        _maxValue = range._maxValue;
        _first = first;
        _second = second;
        handleDataChange();
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
                onAction1(a);
            else
                onAction2(a);
            return true;
        }
        return super.handleWheelEvent(event);
    }

    private float[2] handleSizes = 0;
    override protected Boundaries computeBoundaries()
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
        return bs;
    }

    override protected void calcSpace(float availableSize, out float spaceBefore, out float spaceAfter)
    {
        const space = availableSize - handleSizes[0] - handleSizes[1];
        if (space <= 0)
            return;

        spaceBefore = offsetAt(space, _first);
        spaceAfter = space - offsetAt(space, _second);
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

    static double from(double v, SliderRange r)
    {
        const w = Slider.make(v, null, r);
        return w.value;
    }

    static bool eq(double a, double b)
    {
        return std.math.approxEqual(a, b);
    }

    const r = SliderRange(-10, 10, 0.1);
    assert(eq(0, from(0, r)));
    assert(eq(5, from(5, r)));
    assert(eq(-10, from(-50, r)));
    assert(eq(10, from(50, r)));
    assert(eq(7.9, from(7.86, r)));

    assert(eq(-100, from(19, SliderRange(-200, -100))));
}

unittest
{
    static import std.math;

    static double[2] from(double fst, double snd, SliderRange r)
    {
        const w = RangeSlider.make(fst, snd, null, r);
        return [w.first, w.second];
    }

    static bool eq(double a0, double a1, double[2] b)
    {
        return std.math.approxEqual(a0, b[0]) && std.math.approxEqual(a1, b[1]);
    }

    const r = SliderRange(-10, 10, 0.1);
    assert(eq(0, 0, from(0, 0, r)));
    assert(eq(2, 4, from(2, 4, r)));
    assert(eq(10, 10, from(14, 12, r)));
    assert(eq(10, 10, from(11, 12, r)));
    assert(eq(5, 10, from(5, 12, r)));
    assert(eq(0, 10, from(0, 12, r)));
    assert(eq(-10, 10, from(-15, 12, r)));
    assert(eq(5, 5, from(5, 0, r)));
    assert(eq(5, 5, from(5, -12, r)));
    assert(eq(-10, -10, from(-11, -12, r)));
    assert(eq(-10, -10, from(-14, -12, r)));

    assert(eq(-100, -100, from(-10, 10, SliderRange(-200, -100))));
}
