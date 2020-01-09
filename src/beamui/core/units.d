/**


Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.units;

nothrow:

import beamui.core.geometry : isDefinedSize, isValidSize, SIZE_UNSPECIFIED;

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
    rem,
    percent
}

/// Represents length with specified measurement unit
struct Length
{
    nothrow:

    private float value = SIZE_UNSPECIFIED!float;
    private LengthUnit type = LengthUnit.device;

    /// Zero length
    enum Length zero = Length.device(0);
    /// Unspecified length
    enum Length none = Length.init;

    /// Construct with some value and type
    this(float value, LengthUnit type)
    {
        assert(isValidSize(value));
        this.value = value;
        this.type = type;
    }

    /// Construct with raw device pixels
    static Length device(int value)
    {
        float f = isDefinedSize(value) ? value : SIZE_UNSPECIFIED!float;
        return Length(f, LengthUnit.device);
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
    static Length rem(float value)
    {
        return Length(value, LengthUnit.rem);
    }
    static Length percent(float value)
    {
        return Length(value, LengthUnit.percent);
    }

    bool is_em() const
    {
        return type == LengthUnit.em;
    }

    bool is_rem() const
    {
        return type == LengthUnit.rem;
    }

    bool is_percent() const
    {
        return type == LengthUnit.percent;
    }

    /// For absolute units - converts them to device pixels, for relative - multiplies by 100
    int toDevice() const
    {
        if (value == SIZE_UNSPECIFIED!float)
            return SIZE_UNSPECIFIED!int;

        final switch (type) with (LengthUnit)
        {
            case device:  return cast(int) value;
            case px:      return cast(int)(value * devicePixelRatio);
            case em:
            case rem:
            case percent: return cast(int)(value * 100);
            case cm:      return cast(int)(value * screenDPI / 2.54);
            case mm:      return cast(int)(value * screenDPI / 25.4);
            case inch:    return cast(int)(value * screenDPI);
            case pt:      return cast(int)(value * screenDPI / 72);
        }
    }

    /// Convert to layout length, which represents device-independent pixels or percentage
    LayoutLength toLayout() const
    {
        if (value == SIZE_UNSPECIFIED!float)
            return LayoutLength(SIZE_UNSPECIFIED!float);

        final switch (type) with (LengthUnit)
        {
            case device:  return LayoutLength(value / devicePixelRatio);
            case px:      return LayoutLength(value);
            case em:
            case rem:     return LayoutLength.percent(value * 100);
            case percent: return LayoutLength.percent(value);
            case cm:      return LayoutLength(value * dipsPerInch / 2.54);
            case mm:      return LayoutLength(value * dipsPerInch / 25.4);
            case inch:    return LayoutLength(value * dipsPerInch);
            case pt:      return LayoutLength(value * dipsPerInch / 72);
        }
    }

    /// Convert device-independent pixels to physical device pixels (of current window)
    static int dipToDevice(float dips)
    {
        assert(isDefinedSize(dips));
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
        else if (unit == "rem")
            type = LengthUnit.rem;
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

/// Layout length can be either in device-independent pixels or in percents
struct LayoutLength
{
    nothrow:

    private float value = SIZE_UNSPECIFIED!float;
    private bool percentage;

    /// Zero length
    enum LayoutLength zero = LayoutLength(0);
    /// Unspecified length
    enum LayoutLength none = LayoutLength(SIZE_UNSPECIFIED!float);

    /// Construct from pixels
    this(float px)
    {
        if (isDefinedSize(px))
        {
            assert(px < SIZE_UNSPECIFIED!int);
            value = px;
        }
    }
    /// Construct from percent
    static LayoutLength percent(float p)
    {
        assert(isDefinedSize(p));
        assert(p < SIZE_UNSPECIFIED!int);

        LayoutLength ret;
        ret.value = p;
        ret.percentage = true;
        return ret;
    }

    /// True if size is finite, i.e. not `SIZE_UNSPECIFIED`
    bool isDefined() const
    {
        return value != SIZE_UNSPECIFIED!float;
    }

    /// True if contains percent value
    bool isPercent() const
    {
        return percentage;
    }

    /// If this is percent, return % of `base`, otherwise return stored pixel value
    float applyPercent(float base) const
    {
        assert(isDefinedSize(base));

        if (value == SIZE_UNSPECIFIED!float)
            return SIZE_UNSPECIFIED!float;
        if (percentage)
            return value * base / 100;
        else
            return value;
    }
}

unittest
{
    {
        LayoutLength len;
        assert(!len.isPercent);
        assert(len.applyPercent(50) == SIZE_UNSPECIFIED!int);
    }
    {
        LayoutLength len = SIZE_UNSPECIFIED!float;
        assert(!len.isPercent);
        assert(len.applyPercent(50) == SIZE_UNSPECIFIED!int);
    }
    for (float f = -10; f < 10; f += 0.3)
    {
        LayoutLength len = f;
        assert(!len.isPercent);
        assert(len.applyPercent(1234) == cast(int)f);
    }
    for (float f = -200; f < 200; f += 35)
    {
        auto len = LayoutLength.percent(f);
        assert(len.isPercent);
        assert(len.applyPercent(50) == cast(int)f / 2);
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

import std.math : round;
import beamui.core.geometry : BoxF, PointF, RectF;

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
    import beamui.core.math : clamp;

    if (dpi <= 0 || dpr <= 0)
    {
        overriden = false;
        return;
    }

    dpi = clamp(dpi, 10, 1000);
    dpr = clamp(dpr, 0.1, 10);

    screenDPI = dpi;
    devicePixelRatio = dpr;
    dipsPerInch = dpi / dpr;
    overriden = true;
}

float snapToDevicePixels(float f)
{
    return round(f * devicePixelRatio) / devicePixelRatio;
}

PointF snapToDevicePixels(PointF pt)
{
    pt.x = round(pt.x * devicePixelRatio) / devicePixelRatio;
    pt.y = round(pt.y * devicePixelRatio) / devicePixelRatio;
    return pt;
}

RectF snapToDevicePixels(RectF r)
{
    r.left = round(r.left * devicePixelRatio) / devicePixelRatio;
    r.top = round(r.top * devicePixelRatio) / devicePixelRatio;
    r.right = round(r.right * devicePixelRatio) / devicePixelRatio;
    r.bottom = round(r.bottom * devicePixelRatio) / devicePixelRatio;
    return r;
}

BoxF snapToDevicePixels(BoxF box)
{
    return BoxF(snapToDevicePixels(RectF(box)));
}

private bool overriden;
private float screenDPI = 96;
private float devicePixelRatio = 1;
private float dipsPerInch = 96;

//===============================================================
