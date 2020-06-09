/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.types;

@safe:

import beamui.core.units : Length;
import beamui.graphics.drawables : BgSizeType;

enum WhiteSpace : ubyte
{
    pre,
    preWrap,
}

struct BgPositionRaw
{
    nothrow:

    Length x = Length.percent(0);
    Length y = Length.percent(0);

    static BgPositionRaw mix(BgPositionRaw a, BgPositionRaw b, double factor)
    {
        const x = a.x * (1 - factor) + b.x * factor;
        const y = a.y * (1 - factor) + b.y * factor;
        return BgPositionRaw(x, y);
    }
}

struct BgSizeRaw
{
    nothrow:

    BgSizeType type;
    Length x;
    Length y;

    static BgSizeRaw mix(BgSizeRaw a, BgSizeRaw b, double factor)
    {
        if (a.type == BgSizeType.length && b.type == BgSizeType.length)
        {
            const x = a.x * (1 - factor) + b.x * factor;
            const y = a.y * (1 - factor) + b.y * factor;
            return BgSizeRaw(b.type, x, y);
        }
        else
            return b;
    }
}

enum SpecialCSSType
{
    none,
    fontWeight, /// ushort
    image, /// Drawable
    opacity, /// float
    time, /// uint
    transitionProperty, /// string
    zIndex, /// int
}
