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
    Length x = Length.percent(0);
    Length y = Length.percent(0);
}

struct BgSizeRaw
{
    BgSizeType type;
    Length x;
    Length y;
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
