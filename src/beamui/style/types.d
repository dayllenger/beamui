/**

Copyright: dayllenger 2018-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.types;

@safe:

import beamui.core.linalg : Mat2x3, Vec2;
import beamui.core.units : LayoutLength, Length;
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

enum SingleTransformKind : ubyte
{
    none,
    translate,
    rotate,
    scale,
    skew,
}

struct SingleTransformRaw
{
    SingleTransformKind kind;
    Length a = Length.zero;
    Length b = Length.zero;
}

struct SingleTransform
{
    SingleTransformKind kind;
    LayoutLength a = LayoutLength.zero;
    LayoutLength b = LayoutLength.zero;

    Mat2x3 toMatrix(float width, float height) const nothrow
    {
        final switch (kind) with (SingleTransformKind)
        {
        case none:
            return Mat2x3.identity;
        case translate:
            return Mat2x3.translation(Vec2(a.applyPercent(width), b.applyPercent(height)));
        case rotate:
            return Mat2x3.rotation(a.applyPercent(0));
        case scale:
            return Mat2x3.scaling(Vec2(a.applyPercent(width), b.applyPercent(height)));
        case skew:
            return Mat2x3.skewing(Vec2(a.applyPercent(0), b.applyPercent(0)));
        }
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

struct StaticBitArray(uint bitCount)
{
    import core.bitop : bt, btr, bts;

    private size_t[bitCount / (8 * size_t.sizeof) + 1] _data;

    void set(uint bit) @trusted
    in (bit < bitCount)
    {
        bts(_data.ptr, bit);
    }

    void reset(uint bit) @trusted
    in (bit < bitCount)
    {
        btr(_data.ptr, bit);
    }

    bool opIndex(uint bit) const @trusted
    in (bit < bitCount)
    {
        return bt(_data.ptr, bit) != 0;
    }

    StaticBitArray opBinary(string op)(ref const StaticBitArray rhs) if (op == "&" || op == "|" || op == "^")
    {
        auto ret = this;
        mixin(`ret._data[] ` ~ op ~ `= rhs._data[];`);
        return ret;
    }
}
