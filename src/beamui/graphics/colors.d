/**
This module contains declaration of useful color related operations.

In beamui, colors are represented as 32 bit uint AARRGGBB values.

Synopsis:
---
import beamui.graphics.colors;
---

Copyright: Vadim Lopatin 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.colors;

import std.string : strip;
import std.traits : isIntegral;
import beamui.core.functions : clamp, to;
import beamui.core.logger;
import beamui.core.parseutils;
import beamui.core.types;

alias ARGB = uint;

/// The main color data type, library-wide used
struct Color
{
    /// Internal color representation
    private ARGB data;

    /// Special color constant to identify value as not a color (to use default/parent value instead)
    enum none = Color(0xFFDEADFF);
    /// Transparent color constant
    enum transparent = Color(0xFFFFFFFF);

pure nothrow @nogc:

    /// Make a color from hex value
    this(uint argb8)
    {
        data = argb8;
    }
    /// Make an opaque color from 3 integer components
    this(T)(T r, T g, T b) if (isIntegral!T)
    {
        data = (cast(uint)r << 16) | (cast(uint)g << 8) | (cast(uint)b);
    }
    /// Make a color from 4 integer components
    this(T)(T r, T g, T b, T a) if (isIntegral!T)
    {
        data = (cast(uint)a << 24) | (cast(uint)r << 16) | (cast(uint)g << 8) | (cast(uint)b);
    }

    /// Red component
    @property uint red() const
    {
        return (data >> 16) & 0xFF;
    }
    /// ditto
    @property void red(uint r)
    {
        data = (data & 0xFF00FFFF) | (r << 16);
    }
    /// Green component
    @property uint green() const
    {
        return (data >> 8) & 0xFF;
    }
    /// ditto
    @property void green(uint g)
    {
        data = (data & 0xFFFF00FF) | (g << 8);
    }
    /// Blue component
    @property uint blue() const
    {
        return (data >> 0) & 0xFF;
    }
    /// ditto
    @property void blue(uint b)
    {
        data = (data & 0xFFFFFF00) | (b << 0);
    }
    /// Alpha component (0=opaque .. 255=transparent)
    @property uint alpha() const
    {
        return (data >> 24) & 0xFF;
    }
    /// ditto
    @property void alpha(uint a)
    {
        data = (data & 0xFFFFFF) | (a << 24);
    }

    /// Get the "hexadecimal" 32-bit representation
    @property ARGB hex() const
    {
        return data;
    }

    /// Fills 3-vector with the values of red, green and blue channel in [0 .. 1] range
    void rgbf(ref float r, ref float g, ref float b) const
    {
        r = ((data >> 16) & 255) / 255.0;
        g = ((data >> 8) & 255) / 255.0;
        b = ((data >> 0) & 255) / 255.0;
    }
    /// Fills 4-vector with the values of red, green, blue and alpha channel in [0 .. 1] range
    void rgbaf(ref float r, ref float g, ref float b, ref float a) const
    {
        r = ((data >> 16) & 255) / 255.0;
        g = ((data >> 8) & 255) / 255.0;
        b = ((data >> 0) & 255) / 255.0;
        a = (((data >> 24) & 255) ^ 255) / 255.0;
    }

    ubyte toGray() const
    {
        uint srcr = (data >> 16) & 0xFF;
        uint srcg = (data >> 8) & 0xFF;
        uint srcb = (data >> 0) & 0xFF;
        return ((srcr + srcg + srcg + srcb) >> 2) & 0xFF;
    }

    /// Returns true if the color has the alpha value meaning complete transparency
    bool isFullyTransparent() const
    {
        return (data >> 24) == 0xFF;
    }

    //===============================================================

    /// Applies additional alpha to the color
    void addAlpha(uint a)
    {
        a = blendAlpha(this.alpha, a);
        this.alpha = a;
    }

    /// Blend two colors using alpha
    static Color blend(Color dst, Color src, uint alpha)
    {
        uint dstalpha = dst.alpha;
        if (dstalpha > 0x80)
            return src;
        uint ialpha = 255 - alpha;
        uint r = ((src.red * ialpha + dst.red * alpha) >> 8) & 0xFF;
        uint g = ((src.green * ialpha + dst.green * alpha) >> 8) & 0xFF;
        uint b = ((src.blue * ialpha + dst.blue * alpha) >> 8) & 0xFF;
        return Color(r, g, b);
    }
}

/// Color constants enum, contributed by zhaopuming
/// Refer to http://rapidtables.com/web/color/RGB_Color.htm#color%20table
/// #275
enum NamedColor : Color
{
    maroon = Color(0x800000),
    dark_red = Color(0x8B0000),
    brown = Color(0xA52A2A),
    firebrick = Color(0xB22222),
    crimson = Color(0xDC143C),
    red = Color(0xFF0000),
    tomato = Color(0xFF6347),
    coral = Color(0xFF7F50),
    indian_red = Color(0xCD5C5C),
    light_coral = Color(0xF08080),
    dark_salmon = Color(0xE9967A),
    salmon = Color(0xFA8072),
    light_salmon = Color(0xFFA07A),
    orange_red = Color(0xFF4500),
    dark_orange = Color(0xFF8C00),
    orange = Color(0xFFA500),
    gold = Color(0xFFD700),
    dark_golden_rod = Color(0xB8860B),
    golden_rod = Color(0xDAA520),
    pale_golden_rod = Color(0xEEE8AA),
    dark_khaki = Color(0xBDB76B),
    khaki = Color(0xF0E68C),
    olive = Color(0x808000),
    yellow = Color(0xFFFF00),
    yellow_green = Color(0x9ACD32),
    dark_olive_green = Color(0x556B2F),
    olive_drab = Color(0x6B8E23),
    lawn_green = Color(0x7CFC00),
    chart_reuse = Color(0x7FFF00),
    green_yellow = Color(0xADFF2F),
    dark_green = Color(0x006400),
    green = Color(0x008000),
    forest_green = Color(0x228B22),
    lime = Color(0x00FF00),
    lime_green = Color(0x32CD32),
    light_green = Color(0x90EE90),
    pale_green = Color(0x98FB98),
    dark_sea_green = Color(0x8FBC8F),
    medium_spring_green = Color(0x00FA9A),
    spring_green = Color(0x00FF7F),
    sea_green = Color(0x2E8B57),
    medium_aqua_marine = Color(0x66CDAA),
    medium_sea_green = Color(0x3CB371),
    light_sea_green = Color(0x20B2AA),
    dark_slate_gray = Color(0x2F4F4F),
    teal = Color(0x008080),
    dark_cyan = Color(0x008B8B),
    aqua = Color(0x00FFFF),
    cyan = Color(0x00FFFF),
    light_cyan = Color(0xE0FFFF),
    dark_turquoise = Color(0x00CED1),
    turquoise = Color(0x40E0D0),
    medium_turquoise = Color(0x48D1CC),
    pale_turquoise = Color(0xAFEEEE),
    aqua_marine = Color(0x7FFFD4),
    powder_blue = Color(0xB0E0E6),
    cadet_blue = Color(0x5F9EA0),
    steel_blue = Color(0x4682B4),
    corn_flower_blue = Color(0x6495ED),
    deep_sky_blue = Color(0x00BFFF),
    dodger_blue = Color(0x1E90FF),
    light_blue = Color(0xADD8E6),
    sky_blue = Color(0x87CEEB),
    light_sky_blue = Color(0x87CEFA),
    midnight_blue = Color(0x191970),
    navy = Color(0x000080),
    dark_blue = Color(0x00008B),
    medium_blue = Color(0x0000CD),
    blue = Color(0x0000FF),
    royal_blue = Color(0x4169E1),
    blue_violet = Color(0x8A2BE2),
    indigo = Color(0x4B0082),
    dark_slate_blue = Color(0x483D8B),
    slate_blue = Color(0x6A5ACD),
    medium_slate_blue = Color(0x7B68EE),
    medium_purple = Color(0x9370DB),
    dark_magenta = Color(0x8B008B),
    dark_violet = Color(0x9400D3),
    dark_orchid = Color(0x9932CC),
    medium_orchid = Color(0xBA55D3),
    purple = Color(0x800080),
    thistle = Color(0xD8BFD8),
    plum = Color(0xDDA0DD),
    violet = Color(0xEE82EE),
    magenta = Color(0xFF00FF),
    fuchsia = Color(0xFF00FF),
    orchid = Color(0xDA70D6),
    medium_violet_red = Color(0xC71585),
    pale_violet_red = Color(0xDB7093),
    deep_pink = Color(0xFF1493),
    hot_pink = Color(0xFF69B4),
    light_pink = Color(0xFFB6C1),
    pink = Color(0xFFC0CB),
    antique_white = Color(0xFAEBD7),
    beige = Color(0xF5F5DC),
    bisque = Color(0xFFE4C4),
    blanched_almond = Color(0xFFEBCD),
    wheat = Color(0xF5DEB3),
    corn_silk = Color(0xFFF8DC),
    lemon_chiffon = Color(0xFFFACD),
    light_golden_rod_yellow = Color(0xFAFAD2),
    light_yellow = Color(0xFFFFE0),
    saddle_brown = Color(0x8B4513),
    sienna = Color(0xA0522D),
    chocolate = Color(0xD2691E),
    peru = Color(0xCD853F),
    sandy_brown = Color(0xF4A460),
    burly_wood = Color(0xDEB887),
    tan = Color(0xD2B48C),
    rosy_brown = Color(0xBC8F8F),
    moccasin = Color(0xFFE4B5),
    navajo_white = Color(0xFFDEAD),
    peach_puff = Color(0xFFDAB9),
    misty_rose = Color(0xFFE4E1),
    lavender_blush = Color(0xFFF0F5),
    linen = Color(0xFAF0E6),
    old_lace = Color(0xFDF5E6),
    papaya_whip = Color(0xFFEFD5),
    sea_shell = Color(0xFFF5EE),
    mint_cream = Color(0xF5FFFA),
    slate_gray = Color(0x708090),
    light_slate_gray = Color(0x778899),
    light_steel_blue = Color(0xB0C4DE),
    lavender = Color(0xE6E6FA),
    floral_white = Color(0xFFFAF0),
    alice_blue = Color(0xF0F8FF),
    ghost_white = Color(0xF8F8FF),
    honeydew = Color(0xF0FFF0),
    ivory = Color(0xFFFFF0),
    azure = Color(0xF0FFFF),
    snow = Color(0xFFFAFA),
    black = Color(0x000000),
    dim_gray = Color(0x696969),
    gray = Color(0x808080),
    dark_gray = Color(0xA9A9A9),
    silver = Color(0xC0C0C0),
    light_gray = Color(0xD3D3D3),
    gainsboro = Color(0xDCDCDC),
    white_smoke = Color(0xF5F5F5),
    white = Color(0xFFFFFF),
}

/// Make hex color from 4 components
uint makeRGBA(T)(T r, T g, T b, T a) pure nothrow
{
    return (cast(uint)a << 24) | (cast(uint)r << 16) | (cast(uint)g << 8) | (cast(uint)b);
}

/// Decode color string in one of formats: #RGB #ARGB #RRGGBB #AARRGGBB
Color decodeHexColor(string s, Color defValue = Color(0x0)) pure
{
    s = strip(s);
    if (s.length != 4 && s.length != 5 && s.length != 7 && s.length != 9)
        return defValue;
    if (s[0] != '#')
        return defValue;
    uint value = 0;
    foreach (i; 1 .. s.length)
    {
        uint digit = parseHexDigit(s[i]);
        if (digit == uint.max)
            return defValue;
        value = (value << 4) | digit;
        if (s.length < 7) // double the same digit for short forms
            value = (value << 4) | digit;
    }
    return Color(value);
}

/// Decode named color either from `Color` enum, `@null`, `none`, or `transparent`
Color decodeTextColor(string s, Color defValue = Color(0x0)) pure
{
    s = strip(s);
    if (s == "@null" || s == "none" || s == "transparent")
        return Color.transparent;

    try
    {
        Color c = to!NamedColor(s);
        return c;
    }
    catch (Exception e) // not a named color
    {
        debug Log.e("Unknown color value: ", s);
        return defValue;
    }
}

/// Convert opacity [0.0, 1.0] color to [0, 255] alpha color (0 - opaque, 255 - transparent)
ubyte opacityToAlpha(float a) pure nothrow @nogc
{
    return 255 - cast(ubyte)(clamp(a, 0.0, 1.0) * 255);
}

/// Blend two RGB pixels using alpha
uint blendARGB(uint dst, uint src, uint alpha) pure nothrow @nogc
{
    uint dstalpha = dst >> 24;
    if (dstalpha > 0x80)
        return src;
    uint srcr = (src >> 16) & 0xFF;
    uint srcg = (src >> 8) & 0xFF;
    uint srcb = (src >> 0) & 0xFF;
    uint dstr = (dst >> 16) & 0xFF;
    uint dstg = (dst >> 8) & 0xFF;
    uint dstb = (dst >> 0) & 0xFF;
    uint ialpha = 255 - alpha;
    uint r = ((srcr * ialpha + dstr * alpha) >> 8) & 0xFF;
    uint g = ((srcg * ialpha + dstg * alpha) >> 8) & 0xFF;
    uint b = ((srcb * ialpha + dstb * alpha) >> 8) & 0xFF;
    return (r << 16) | (g << 8) | b;
}

immutable int[3] COMPONENT_OFFSET_BGR = [2, 1, 0];
immutable int[3] COMPONENT_OFFSET_RGB = [0, 1, 2];
immutable int COMPONENT_OFFSET_ALPHA = 3;
int subpixelComponentIndex(int x0, SubpixelRenderingMode mode) pure nothrow @nogc
{
    switch (mode) with (SubpixelRenderingMode)
    {
    case rgb:
        return COMPONENT_OFFSET_BGR[x0];
    case bgr:
    default:
        return COMPONENT_OFFSET_BGR[x0];
    }
}

/// Blend subpixel using alpha
void blendSubpixel(ubyte* dst, ubyte* src, uint alpha, int x0, SubpixelRenderingMode mode) pure nothrow @nogc
{
    uint dstalpha = dst[COMPONENT_OFFSET_ALPHA];
    int offset = subpixelComponentIndex(x0, mode);
    uint srcr = src[offset];
    dst[COMPONENT_OFFSET_ALPHA] = 0;
    if (dstalpha > 0x80)
    {
        dst[offset] = cast(ubyte)srcr;
        return;
    }
    uint dstr = dst[offset];
    uint ialpha = 256 - alpha;
    uint r = ((srcr * ialpha + dstr * alpha) >> 8) & 0xFF;
    dst[offset] = cast(ubyte)r;
}

/// Blend two alpha values 0..255 (255 is fully transparent, 0 is opaque)
uint blendAlpha(uint a1, uint a2) pure nothrow @nogc
{
    if (!a1)
        return a2;
    if (!a2)
        return a1;
    return (((a1 ^ 0xFF) * (a2 ^ 0xFF)) >> 8) ^ 0xFF;
}

/// Blend two RGB pixels using alpha
ubyte blendGray(ubyte dst, ubyte src, uint alpha) pure nothrow @nogc
{
    uint ialpha = 256 - alpha;
    return cast(ubyte)(((src * ialpha + dst * alpha) >> 8) & 0xFF);
}

/// NOT USED
struct ColorTransformHandler
{
    void initialize(ref ColorTransform transform)
    {

    }

    uint transform(uint color)
    {
        return color;
    }
}

/// NOT USED
uint transformComponent(int src, int addBefore, int multiply, int addAfter) pure nothrow @nogc
{
    int add1 = (cast(int)(addBefore << 1)) - 0x100;
    int add2 = (cast(int)(addAfter << 1)) - 0x100;
    int mul = cast(int)(multiply << 2);
    int res = (((src + add1) * mul) >> 8) + add2;
    if (res < 0)
        res = 0;
    else if (res > 255)
        res = 255;
    return cast(uint)res;
}

/// NOT USED
uint transformRGBA(uint src, uint addBefore, uint multiply, uint addAfter) pure nothrow @nogc
{
    uint a = transformComponent(src >> 24, addBefore >> 24, multiply >> 24, addAfter >> 24);
    uint r = transformComponent((src >> 16) & 0xFF, (addBefore >> 16) & 0xFF, (multiply >> 16) & 0xFF,
            (addAfter >> 16) & 0xFF);
    uint g = transformComponent((src >> 8) & 0xFF, (addBefore >> 8) & 0xFF, (multiply >> 8) & 0xFF,
            (addAfter >> 8) & 0xFF);
    uint b = transformComponent(src & 0xFF, addBefore & 0xFF, multiply & 0xFF, addAfter & 0xFF);
    return (a << 24) | (r << 16) | (g << 8) | b;
}

/// NOT USED
immutable uint COLOR_TRANSFORM_OFFSET_NONE = 0x80808080;
/// NOT USED
immutable uint COLOR_TRANSFORM_MULTIPLY_NONE = 0x40404040;

/// NOT USED
struct ColorTransform
{
    uint addBefore = COLOR_TRANSFORM_OFFSET_NONE;
    uint multiply = COLOR_TRANSFORM_MULTIPLY_NONE;
    uint addAfter = COLOR_TRANSFORM_OFFSET_NONE;

    @property bool empty() const
    {
        return addBefore == COLOR_TRANSFORM_OFFSET_NONE &&
            multiply == COLOR_TRANSFORM_MULTIPLY_NONE && addAfter == COLOR_TRANSFORM_OFFSET_NONE;
    }

    uint transform(uint color)
    {
        return transformRGBA(color, addBefore, multiply, addAfter);
    }
}
