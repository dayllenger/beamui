/**


Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.units;

import beamui.core.config;
import beamui.core.types;

/// Use in styles to specify size in points (1/72 inch)
enum int SIZE_IN_POINTS_FLAG = 1 << 28;
/// Use in styles to specify size in percents * 100 (e.g. 0 == 0%, 10000 == 100%, 100 = 1%)
enum int SIZE_IN_PERCENTS_FLAG = 1 << 27;

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

/// Convert custom size RectOffset to pixels (sz can be either pixels, or points if SIZE_IN_POINTS_FLAG bit set)
RectOffset toPixels(const RectOffset ro)
{
    return RectOffset(toPixels(ro.left), toPixels(ro.top), toPixels(ro.right), toPixels(ro.bottom));
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
