/**


Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.units;

import beamui.core.config;
import beamui.core.geometry;

/// Use in styles to specify size in points (1/72 inch)
enum int SIZE_IN_POINTS_FLAG = 1 << 28;
/// Use in styles to specify size in percents * 100 (e.g. 0 == 0%, 10000 == 100%, 100 = 1%)
enum int SIZE_IN_PERCENTS_FLAG = 1 << 27;

/// Supported types of distance measurement unit
enum LengthUnit
{
    // absolute
    device = 0,
    cm,
    mm,
    inch,
    pt,
    // semi-absolute
    px,
    // relative
    em,
    percent
}

alias Dimension = Length;

/// Represents length with specified measurement unit
struct Length
{
    private float value;
    private LengthUnit type;

    /// Zero value
    enum Length zero = Length(0);
    /// Unspecified value
    enum Length none = Length(SIZE_UNSPECIFIED);

    /// Construct with raw device pixels
    this(int devicePixels) pure
    {
        if (devicePixels != SIZE_UNSPECIFIED)
            value = cast(float)devicePixels;
    }
    /// Construct with some value and type
    this(float value, LengthUnit type) pure
    {
        this.value = value;
        this.type = type;
    }

    /// Length.unit(value) syntax
    static Length opDispatch(string op)(float value)
    {
        return mixin("Length(value, LengthUnit." ~ op ~ ")");
    }

    bool is_em() const pure
    {
        return type == LengthUnit.em;
    }

    bool is_percent() const pure
    {
        return type == LengthUnit.percent;
    }

    /// For absolute units - converts them to device pixels, for relative - multiplies by 100
    int toDevice() const
    {
        import std.math : isNaN;

        if (value.isNaN)
            return SIZE_UNSPECIFIED;

        if (type == LengthUnit.device)
            return cast(int)value;

        if (type == LengthUnit.cm)
            return cast(int)(value * SCREEN_DPI / 2.54);
        if (type == LengthUnit.mm)
            return cast(int)(value * SCREEN_DPI / 25.4);
        if (type == LengthUnit.inch)
            return cast(int)(value * SCREEN_DPI);
        if (type == LengthUnit.pt)
            return cast(int)(value * SCREEN_DPI / 72);

        if (type == LengthUnit.px)
            return cast(int)value; // TODO: low-dpi/hi-dpi

        if (type == LengthUnit.em)
            return cast(int)(value * 100);
        if (type == LengthUnit.percent)
            return cast(int)(value * 100);

        return 0;
    }

    bool opEquals(Length u) const pure
    {
        // workaround for NaN != NaN
        return this is u;
    }

    Length opBinary(string op : "+")(Length u) const
    {
        if (type != u.type) // FIXME: different types
            return this;
        else
            return Length(value + u.value, type);
    }

    Length opBinary(string op : "*")(double factor) const
    {
        return Length(value * factor, type);
    }

    /// Parse pair (value, unit), where value is a real number, unit is: cm, mm, in, pt, px, em, %.
    /// Returns Length.none if cannot parse.
    static Length parse(string value, string unit) pure
    {
        import std.conv : to;

        if (!value.length || !unit.length)
            return Length.none;

        LengthUnit type;
        if (unit == "cm")
            type = LengthUnit.cm;
        else if (unit == "mm")
            type = LengthUnit.mm;
        else if (unit == "in")
            type = LengthUnit.inch;
        else if (unit == "pt")
            type = LengthUnit.pt;
        else if (unit == "px")
            type = LengthUnit.px;
        else if (unit == "em")
            type = LengthUnit.em;
        else if (unit == "%")
            type = LengthUnit.percent;
        else
            return Length.none;

        try
        {
            float v = to!float(value);
            return Length(v, type);
        }
        catch (Exception e)
        {
            return Length.none;
        }
    }
}

/// Parse angle with deg, grad, rad or turn unit. Returns an angle in radians, or NaN if cannot parse.
float parseAngle(string value, string unit) pure
{
    import std.conv : to;
    import std.math : PI;

    if (!value.length || !unit.length)
        return float.nan;

    float angle;
    try
    {
        angle = to!float(value);
    }
    catch (Exception e)
    {
        return float.nan;
    }

    if (unit == "rad")
        return angle;
    else if (unit == "deg")
        return angle * PI / 180;
    else if (unit == "grad")
        return angle * PI / 200;
    else if (unit == "turn")
        return angle * PI * 2;
    else
        return float.nan;
}

unittest
{
    import std.math : approxEqual;

    assert(parseAngle("120.5", "deg").approxEqual(2.10312, 1e-5));
    assert(parseAngle("15", "grad").approxEqual(0.23562, 1e-5));
    assert(parseAngle("-27.7", "rad").approxEqual(-27.7, 1e-5));
    assert(parseAngle("2", "turn").approxEqual(12.56637, 1e-5));
}

/// Number of hnsecs (those we use in animations, for example) in one second
enum long ONE_SECOND = 10_000_000L;

nothrow @nogc:

/// Convert custom size to pixels (sz can be either pixels, or points if SIZE_IN_POINTS_FLAG bit set)
int toPixels(int sz)
{
    if (sz > 0 && (sz & SIZE_IN_POINTS_FLAG) != 0)
    {
        return pt(sz ^ SIZE_IN_POINTS_FLAG);
    }
    return sz;
}

/// Convert custom size Point to pixels (sz can be either pixels, or points if SIZE_IN_POINTS_FLAG bit set)
Point toPixels(const Point p)
{
    return Point(toPixels(p.x), toPixels(p.y));
}

/// Convert custom size Rect to pixels (sz can be either pixels, or points if SIZE_IN_POINTS_FLAG bit set)
Rect toPixels(const Rect r)
{
    return Rect(toPixels(r.left), toPixels(r.top), toPixels(r.right), toPixels(r.bottom));
}

/// Convert custom size Insets to pixels (sz can be either pixels, or points if SIZE_IN_POINTS_FLAG bit set)
Insets toPixels(const Insets ins)
{
    return Insets(toPixels(ins.top), toPixels(ins.right), toPixels(ins.bottom), toPixels(ins.left));
}

/// Make size value with SIZE_IN_POINTS_FLAG set
int makePointSize(int pt) pure
{
    return pt | SIZE_IN_POINTS_FLAG;
}

/// Make size value with SIZE_IN_PERCENTS_FLAG set
int makePercentSize(int percent) pure
{
    return (percent * 100) | SIZE_IN_PERCENTS_FLAG;
}

/// Make size value with SIZE_IN_PERCENTS_FLAG set
int makePercentSize(double percent) pure
{
    return cast(int)(percent * 100) | SIZE_IN_PERCENTS_FLAG;
}
alias percent = makePercentSize;

/// Returns true for SIZE_UNSPECIFIED
bool isSpecialSize(int sz) pure
{
    // don't forget to update if more special constants added
    return (sz & SIZE_UNSPECIFIED) != 0;
}

/// Returns true if size has SIZE_IN_PERCENTS_FLAG bit set
bool isPercentSize(int size) pure
{
    return (size & SIZE_IN_PERCENTS_FLAG) != 0;
}

/// Apply percent to `base` or return `p` unchanged if it is not a percent size
int applyPercent(int p, int base) pure
{
    if (isPercentSize(p))
        return cast(int)(cast(long)(p & ~SIZE_IN_PERCENTS_FLAG) * base / 10000);
    else
        return p;
}

/// Screen dots per inch
private __gshared int PRIVATE_SCREEN_DPI = 96;
/// Value to override detected system DPI, 0 to disable overriding
private __gshared int PRIVATE_SCREEN_DPI_OVERRIDE = 0;

/// Get current screen DPI used for scaling while drawing
@property int SCREEN_DPI()
{
    return PRIVATE_SCREEN_DPI_OVERRIDE ? PRIVATE_SCREEN_DPI_OVERRIDE : PRIVATE_SCREEN_DPI;
}

/// Get screen DPI detection override value, if non 0 - this value is used instead of DPI detected by platform, if 0, value detected by platform will be used
@property int overrideScreenDPI()
{
    return PRIVATE_SCREEN_DPI_OVERRIDE;
}

/// Call to disable automatic screen DPI detection, use provided one instead (pass 0 to disable override and use value detected by platform)
@property void overrideScreenDPI(int dpi = 96)
{
    static if (!BACKEND_CONSOLE)
    {
        if ((dpi >= 72 && dpi <= 500) || dpi == 0)
            PRIVATE_SCREEN_DPI_OVERRIDE = dpi;
    }
}

/// Set screen DPI detected by platform
@property void SCREEN_DPI(int dpi)
{
    static if (BACKEND_CONSOLE)
    {
        PRIVATE_SCREEN_DPI = dpi;
    }
    else
    {
        if (dpi >= 72 && dpi <= 500)
        {
            if (PRIVATE_SCREEN_DPI != dpi)
            {
                // changed DPI
                PRIVATE_SCREEN_DPI = dpi;
            }
        }
    }
}

/// Returns DPI detected by platform w/o override
@property int systemScreenDPI()
{
    return PRIVATE_SCREEN_DPI;
}

/// One point is 1/72 of inch
enum POINTS_PER_INCH = 72;

/// Convert length in points (1/72in units) to pixels according to SCREEN_DPI
int pt(int p)
{
    return p * SCREEN_DPI / POINTS_PER_INCH;
}

/// Convert rectangle coordinates in points (1/72in units) to pixels according to SCREEN_DPI
Rect pt(Rect rc)
{
    return Rect(rc.left.pt, rc.top.pt, rc.right.pt, rc.bottom.pt);
}

/// Convert points (1/72in units) to pixels according to SCREEN_DPI
int pixelsToPoints(int px)
{
    return px * POINTS_PER_INCH / SCREEN_DPI;
}
