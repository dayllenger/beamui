module beamui.core.animations;

import std.math;

struct Animation
{
    /// Duration is in hnsecs
    long duration;
    /// Handler is invoked every tick
    void delegate(double) handler;
    // elapsed time fraction in [0, 1] range
    private double t;

    @property bool isAnimating() const
    {
        return !t.isNaN;
    }

    void start()
    {
        t = 0;
    }

    void stop()
    {
        t = double.nan;
    }

    void tick(long interval)
    in
    {
        assert(isAnimating);
    }
    body
    {
        t += cast(double)interval / cast(double)duration;
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
        import beamui.graphics.colors;

        double x = timingFunction.get(t);
        static if (is(T == Color))
            // temporary solution
            return Color(blendARGB(a.hex, b.hex, 255 - cast(uint)(t * 255)));
        else
            return cast(T)(a * (1 - x) + b * x);
    }
}

interface TimingFunction
{
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
    double get(double t) const
    {
        return t;
    }
}

class CubicBezierTimingFunction : TimingFunction
{
    private
    {
        // coefficients
        double ax, bx, cx;
        double ay, by, cy;
    }

pure nothrow @nogc:

    /// Initialize with cubic bezier control points
    this(double x1, double y1, double x2, double y2)
    {
        // calculate the polynomial coefficients
        // P0 is (0,0), P1 is (x1,y1), P2 is (x2,x3) and P3 is (1,1)
        cx = 3.0 * x1;
        bx = 3.0 * (x2 - x1) - cx;
        ax = 1.0 - cx - bx;

        cy = 3.0 * y1;
        by = 3.0 * (y2 - y1) - cy;
        ay = 1.0 - cy - by;
    }

    /// Get x curve value by parameter
    double sampleCurveX(double t) const
    {
        return ((ax * t + bx) * t + cx) * t;
    }

    /// Get y curve value by parameter
    double sampleCurveY(double t) const
    {
        return ((ay * t + by) * t + cy) * t;
    }

    /// Evaluate y for a given x. `x` must be in [0, 1] range.
    double get(double x) const
    in
    {
        assert(0.0 <= x && x <= 1.0);
    }
    body
    {
        return sampleCurveY(solveCurveX(x));
    }

    /// Find parametric value t for a given x. `x` must be in [0, 1] range.
    double solveCurveX(double x) const
    in
    {
        assert(0.0 <= x && x <= 1.0);
    }
    body
    {
        enum epsilon = 1e-7;

        // TODO
        return x;
    }
}
