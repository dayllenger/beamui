module beamui.core.animations;

import std.math;

struct Animation
{
    /// Duration is in milliseconds
    double duration = 0;
    /// Handler is invoked every tick
    void delegate(double) handler;
    // elapsed time fraction in [0, 1] range
    private double t;

    @property bool isAnimating() const
    {
        return duration > 0 && handler && !isNaN(t);
    }

    void start()
    {
        t = 0;
    }

    void stop()
    {
        t = double.nan;
    }

    void tick(double interval)
        in(isFinite(interval))
        in(isAnimating)
    {
        t += interval / duration;
        if (t < 1.0)
        {
            handler(t);
        }
        else
        {
            handler(1.0);
            stop();
        }
    }
}

struct Transition
{
    // duration and delay are in msecs
    uint duration;
    const(TimingFunction) timingFunction;
    uint delay;

    T mix(T)(T a, T b, double t)
    {
        const double x = timingFunction.get(t);
        static if (__traits(compiles, T.mix(a, b, x)))
            return T.mix(a, b, x);
        else
            return cast(T)(a * (1 - x) + b * x);
    }
}

interface TimingFunction
{
    nothrow:

    static const
    {
        TimingFunction linear = new LinearTimingFunction;
        TimingFunction ease = new CubicBezierTimingFunction(0.25, 0.1, 0.25, 1);
        TimingFunction easeIn = new CubicBezierTimingFunction(0.42, 0, 1, 1);
        TimingFunction easeOut = new CubicBezierTimingFunction(0, 0, 0.58, 1);
        TimingFunction easeInOut = new CubicBezierTimingFunction(0.42, 0, 0.58, 1);
    }
    // steps are not supported yet

    double get(double t) const;
}

class LinearTimingFunction : TimingFunction
{
    nothrow:

    double get(double t) const
    {
        return t;
    }
}

class CubicBezierTimingFunction : TimingFunction
{
    nothrow:

    private
    {
        // coefficients
        double ax, bx, cx;
        double ay, by, cy;
    }

    /// Initialize with cubic bezier control points
    this(double x1, double y1, double x2, double y2)
    {
        // calculate the polynomial coefficients
        // implicit P0 = (0,0), P1 = (x1,y1), P2 = (x2,y2), P3 = (1,1)
        cx = 3.0 * x1;
        bx = 3.0 * (x2 - x1) - cx;
        ax = 1.0 - cx - bx;

        cy = 3.0 * y1;
        by = 3.0 * (y2 - y1) - cy;
        ay = 1.0 - cy - by;
    }

    /// Evaluate y for a given x. `x` must be in [0, 1] range.
    double get(double x) const
    {
        assert(0.0 <= x && x <= 1.0);
        return sampleCurveY(solveCurveX(x));
    }

    /// Get x curve value by parameter
    double sampleCurveX(double t) const
    {
        // ax * t^3 + bx * t^2 + cx * t
        return ((ax * t + bx) * t + cx) * t;
    }
    /// Get y curve value by parameter
    double sampleCurveY(double t) const
    {
        return ((ay * t + by) * t + cy) * t;
    }
    double sampleCurveDerivativeX(double t) const
    {
        return (3.0 * ax * t + 2.0 * bx) * t + cx;
    }
    double sampleCurveDerivativeY(double t) const
    {
        return (3.0 * ay * t + 2.0 * by) * t + cy;
    }

    /// Find parametric value t for a given x. `x` must be in [0, 1] range.
    double solveCurveX(const double x) const
    {
        assert(0.0 <= x && x <= 1.0);
        enum epsilon = 1e-7;

        // try fast Newton's method
        double t = x;
        foreach (i; 0 .. 8)
        {
            const x2 = sampleCurveX(t) - x;
            if (abs(x2) < epsilon)
                return t;
            const dx = sampleCurveDerivativeX(t);
            if (abs(dx) < 1e-6)
                break;
            t -= x2 / dx;
        }

        // fall back to the slow bisection method
        double lo = 0.0;
        double hi = 1.0;
        t = x;

        while (lo < hi)
        {
            const x2 = sampleCurveX(t) - x;
            if (abs(x2) < epsilon)
                return t;
            if (x2 < 0)
                lo = t;
            else
                hi = t;
            t = (hi - lo) / 2.0 + lo;
        }

        return t;
    }
}
