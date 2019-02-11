/**


Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.units;

import std.math : isNaN;
import beamui.core.geometry;

/// Supported types of distance measurement unit
enum LengthUnit
{
    // absolute
    device,
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

/// Represents length with specified measurement unit
struct Length
{
    private float value;
    private LengthUnit type;

    /// Zero length
    enum Length zero = Length.device(0);
    /// Unspecified length
    enum Length none = Length.device(SIZE_UNSPECIFIED!int);

    /// Construct with some value and type
    this(float value, LengthUnit type)
    {
        this.value = value;
        this.type = type;
    }

    /// Construct with raw device pixels
    static Length device(int value)
    {
        return Length(value != SIZE_UNSPECIFIED!int ? value : float.nan, LengthUnit.device);
    }
    static Length cm(float value)
    {
        return Length(value, LengthUnit.cm);
    }
    static Length mm(float value)
    {
        return Length(value, LengthUnit.mm);
    }
    static Length inch(float value)
    {
        return Length(value, LengthUnit.inch);
    }
    static Length pt(float value)
    {
        return Length(value, LengthUnit.pt);
    }
    static Length px(float value)
    {
        return Length(value, LengthUnit.px);
    }
    static Length em(float value)
    {
        return Length(value, LengthUnit.em);
    }
    static Length percent(float value)
    {
        return Length(value, LengthUnit.percent);
    }

    bool is_em() const
    {
        return type == LengthUnit.em;
    }

    bool is_percent() const
    {
        return type == LengthUnit.percent;
    }

    /// For absolute units - converts them to device pixels, for relative - multiplies by 100
    int toDevice() const
    {
        if (value.isNaN)
            return SIZE_UNSPECIFIED!int;

        if (type == LengthUnit.device)
            return cast(int)value;

        if (type == LengthUnit.cm)
            return cast(int)(value * screenDPI / 2.54);
        if (type == LengthUnit.mm)
            return cast(int)(value * screenDPI / 25.4);
        if (type == LengthUnit.inch)
            return cast(int)(value * screenDPI);
        if (type == LengthUnit.pt)
            return cast(int)(value * screenDPI / 72);

        if (type == LengthUnit.px)
            return cast(int)(value * devicePixelRatio);

        if (type == LengthUnit.em)
            return cast(int)(value * 100);
        if (type == LengthUnit.percent)
            return cast(int)(value * 100);

        return 0;
    }

    /// Convert to device independent pixels. Relative units are returned as is
    float toDIPs() const
    {
        if (value.isNaN)
            return SIZE_UNSPECIFIED!float;

        if (type == LengthUnit.device)
            return value / devicePixelRatio;

        if (type == LengthUnit.cm)
            return value * dipsPerInch / 2.54;
        if (type == LengthUnit.mm)
            return value * dipsPerInch / 25.4;
        if (type == LengthUnit.inch)
            return value * dipsPerInch;
        if (type == LengthUnit.pt)
            return value * dipsPerInch / 72;

        if (type == LengthUnit.px)
            return value;

        if (type == LengthUnit.em || type == LengthUnit.percent)
            return value;

        return 0;
    }

    /// Convert device-independent pixels to physical device pixels (of current window)
    static int dipToDevice(float dips)
    {
        return cast(int)(dips * devicePixelRatio);
    }

    bool opEquals(Length u) const
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
    /// Returns `Length.none` if cannot parse.
    static Length parse(string value, string unit)
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
float parseAngle(string value, string unit)
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
///
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

//===============================================================
// DPI handling

/// Called by window
package(beamui) void setupDPI(float dpi, float dpr)
{
    assert(dpi > 0 && dpr > 0);

    if (!overriden)
    {
        screenDPI = dpi;
        devicePixelRatio = dpr;
        dipsPerInch = dpi / dpr;
    }
}

/// Call to disable automatic screen DPI detection, use provided one instead
/// (pass 0 to disable override and use value detected by platform)
void overrideDPI(float dpi, float dpr)
{
    if (dpi <= 0 || dpr <= 0)
    {
        overriden = false;
        return;
    }

    import std.algorithm : clamp;
    dpi = clamp(dpi, 10, 1000);
    dpr = clamp(dpr, 0.1, 10);

    screenDPI = dpi;
    devicePixelRatio = dpr;
    dipsPerInch = dpi / dpr;
    overriden = true;
}

private bool overriden;
private float screenDPI = 96;
private float devicePixelRatio = 1;
private float dipsPerInch = 96;

//===============================================================
