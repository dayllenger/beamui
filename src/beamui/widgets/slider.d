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
