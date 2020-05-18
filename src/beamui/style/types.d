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

/// margin, padding, border-width
struct ShorthandInsets
{
    size_t name;
    size_t top;
    size_t right;
    size_t bottom;
    size_t left;
}

struct ShorthandPair(T)
{
    size_t name;
    size_t first;
    size_t second;
}

struct ShorthandFlexFlow
{
    size_t name;
    size_t dir;
    size_t wrap;
}

struct ShorthandFlex
{
    size_t name;
    size_t grow;
    size_t shrink;
    size_t basis;
}

struct ShorthandGridArea
{
    size_t name;
    size_t rowStart;
    size_t rowEnd;
    size_t columnStart;
    size_t columnEnd;
}

struct ShorthandGridLine
{
    size_t name;
    size_t start;
    size_t end;
}

/// background, usually
struct ShorthandDrawable
{
    size_t name;
    size_t color;
    size_t image;
}

struct ShorthandColors
{
    size_t name;
    size_t top;
    size_t right;
    size_t bottom;
    size_t left;
}

struct ShorthandBorder
{
    size_t name;
    size_t topWidth;
    size_t topStyle;
    size_t topColor;
    size_t rightWidth;
    size_t rightStyle;
    size_t rightColor;
    size_t bottomWidth;
    size_t bottomStyle;
    size_t bottomColor;
    size_t leftWidth;
    size_t leftStyle;
    size_t leftColor;
}

struct ShorthandBorderStyle
{
    size_t name;
    size_t top;
    size_t right;
    size_t bottom;
    size_t left;
}

struct ShorthandBorderSide
{
    size_t name;
    size_t width;
    size_t style;
    size_t color;
}

struct ShorthandTextDecor
{
    size_t name;
    size_t line;
    size_t color;
    size_t style;
}

struct ShorthandTransition
{
    size_t name;
    size_t property;
    size_t duration;
    size_t timingFunction;
    size_t delay;
}
