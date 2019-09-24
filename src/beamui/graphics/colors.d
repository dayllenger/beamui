/**
Color type and useful color related operations.

Copyright: Vadim Lopatin 2015, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.colors;

nothrow:

import std.string : strip;
import std.traits : isIntegral;
import beamui.core.functions : clamp, collectException, to;
import beamui.core.logger;
import beamui.core.parseutils;
import beamui.core.types;
import beamui.text.glyph : SubpixelRenderingMode;

alias ARGB8 = uint;

/// Represents RGBA color with one byte per channel
struct Color
{
    align(1) nothrow:

    ubyte r, g, b;
    ubyte a; /// 0 - opaque, 255 - transparent

    /// Special color constant to identify value as not a color (to use default/parent value instead)
    enum none = Color(0xFFDEADFF);

    enum transparent = Color(0xFFFFFFFF);
    enum black = Color(0x000000);
    enum white = Color(0xFFFFFF);

    /// Make a color from hex value
    this(ARGB8 hex)
    {
        r = (hex >> 16) & 0xFF;
        g = (hex >> 8) & 0xFF;
        b = (hex >> 0) & 0xFF;
        a = (hex >> 24) & 0xFF;
    }
    /// Make an opaque color from 3 integer components
    this(T)(T red, T green, T blue) if (isIntegral!T)
    {
        r = cast(ubyte)(red & 0xFF);
        g = cast(ubyte)(green & 0xFF);
        b = cast(ubyte)(blue & 0xFF);
    }
    /// Make a color from 4 integer components
    this(T)(T red, T green, T blue, T alpha) if (isIntegral!T)
    {
        r = cast(ubyte)(red & 0xFF);
        g = cast(ubyte)(green & 0xFF);
        b = cast(ubyte)(blue & 0xFF);
        a = cast(ubyte)(alpha & 0xFF);
    }

    /// Make a color from HSL representation. `h`, `s`, and `l` must be in [0, 1] range
    static Color fromHSLA(float h, float s, float l, uint a)
    {
        assert(0 <= h && h <= 1);
        assert(0 <= s && s <= 1);
        assert(0 <= l && l <= 1);

        if (s == 0) // achromatic
        {
            const v = cast(uint)(l * 255);
            return Color(v, v, v, a);
        }

        static float hue2rgb(float p, float q, float t)
        {
            if (t < 0)
                t += 1;
            if (t > 1)
                t -= 1;
            if (t < 1.0f / 6)
                return p + (q - p) * 6 * t;
            if (t < 1.0f / 2)
                return q;
            if (t < 2.0f / 3)
                return p + (q - p) * (2.0f / 3 - t) * 6;
            return p;
        }

        const q = l < 0.5f ? l * (1 + s) : l + s - l * s;
        const p = 2 * l - q;
        const r = hue2rgb(p, q, h + 1.0f / 3);
        const g = hue2rgb(p, q, h);
        const b = hue2rgb(p, q, h - 1.0f / 3);
        return Color(cast(uint)(r * 255), cast(uint)(g * 255), cast(uint)(b * 255), a);
    }

    @property
    {
        /// Get the "hexadecimal" 32-bit 0xAARRGGBB representation
        ARGB8 hex() const
        {
            pragma(inline, true);
            return (cast(uint)a << 24) | (cast(uint)r << 16) | (cast(uint)g << 8) | (cast(uint)b);
        }

        /// True if the color has the alpha value meaning full opacity
        bool isOpaque() const
        {
            pragma(inline, true);
            return a == 0;
        }
        /// True if the color has the alpha value meaning complete transparency
        bool isFullyTransparent() const
        {
            pragma(inline, true);
            return a == 0xFF;
        }
    }

    /// Convert to 1-byte grayscale color
    ubyte toGray() const
    {
        return ((r + g * 2 + b) >> 2) & 0xFF;
    }

    /// Apply additional alpha to the color
    void addAlpha(uint alpha)
    {
        a = cast(ubyte)blendAlpha(a, alpha);
    }

    /// Blend two colors using alpha
    static Color blend(Color dst, Color src, uint alpha)
    {
        const dstalpha = dst.a;
        if (dstalpha > 0x80)
            return src;
        const ialpha = 255 - alpha;
        const r = ((src.r * ialpha + dst.r * alpha) >> 8) & 0xFF;
        const g = ((src.g * ialpha + dst.g * alpha) >> 8) & 0xFF;
        const b = ((src.b * ialpha + dst.b * alpha) >> 8) & 0xFF;
        return Color(r, g, b);
    }

    /// Linearly interpolate between two colors
    static Color mix(Color c1, Color c2, double factor)
    {
        assert(0 <= factor && factor <= 1);
        if (c1 == c2)
            return c1;

        const alpha = cast(uint)(factor * 255);
        const ialpha = 255 - alpha;
        const r = ((c1.r * ialpha + c2.r * alpha) >> 8) & 0xFF;
        const g = ((c1.g * ialpha + c2.g * alpha) >> 8) & 0xFF;
        const b = ((c1.b * ialpha + c2.b * alpha) >> 8) & 0xFF;
        const a = ((c1.a * ialpha + c2.a * alpha) >> 8) & 0xFF;
        return Color(r, g, b, a);
    }
}

/// Represents RGBA color with floating point channels in [0, 1] range
struct ColorF
{
    nothrow:

    float r = 0;
    float g = 0;
    float b = 0;
    float a = 0;

    enum transparent = ColorF(0, 0, 0, 0);
    enum black = ColorF(0, 0, 0, 1);
    enum white = ColorF(1, 1, 1, 1);

    this(float r, float g, float b, float a = 255.0f)
    {
        this.r = r;
        this.g = g;
        this.b = b;
        this.a = a;
    }

    this(Color ucolor)
    {
        r = ucolor.r / 255.0f;
        g = ucolor.g / 255.0f;
        b = ucolor.b / 255.0f;
        a = (255 - ucolor.a) / 255.0f;
    }
}

/** Standard colors.

    Contributed by zhaopuming, refer to $(LINK http://rapidtables.com/web/color/RGB_Color.htm#color%20table)
*/
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
uint makeRGBA(T)(T r, T g, T b, T a)
{
    return (cast(uint)a << 24) | (cast(uint)r << 16) | (cast(uint)g << 8) | (cast(uint)b);
}

/// Decode color string in one of formats: #RGB #ARGB #RRGGBB #AARRGGBB
Result!Color decodeHexColor(string s)
{
    collectException(strip(s), s);
    if (s.length != 4 && s.length != 5 && s.length != 7 && s.length != 9)
        return Err!Color;
    if (s[0] != '#')
        return Err!Color;

    uint value = 0;
    foreach (i; 1 .. s.length)
    {
        const digit = parseHexDigit(s[i]);
        if (digit == uint.max)
            return Err!Color;
        value = (value << 4) | digit;
        if (s.length < 7) // double the same digit for short forms
            value = (value << 4) | digit;
    }
    return Ok(Color(value));
}

/// Decode named color either from `NamedColor` enum, `@null`, `none`, or `transparent`
Result!Color decodeTextColor(string s)
{
    collectException(strip(s), s);
    if (s == "@null" || s == "none" || s == "transparent")
        return Ok(Color.transparent);

    try
    {
        Color c = to!NamedColor(s);
        return Ok(c);
    }
    catch (Exception e) // not a named color
    {
        debug Log.e("Unknown color value: ", s);
        return Err!Color;
    }
}

/// Convert opacity [0.0, 1.0] color to [0, 255] alpha color (0 - opaque, 255 - transparent)
ubyte opacityToAlpha(float a)
{
    return 255 - cast(ubyte)(clamp(a, 0.0, 1.0) * 255);
}

/// Blend two RGB pixels using alpha
uint blendARGB(uint dst, uint src, uint alpha)
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
int subpixelComponentIndex(int x0, SubpixelRenderingMode mode)
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
void blendSubpixel(ubyte* dst, ubyte* src, uint alpha, int x0, SubpixelRenderingMode mode)
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
uint blendAlpha(uint a1, uint a2)
{
    if (!a1)
        return a2;
    if (!a2)
        return a1;
    return (((a1 ^ 0xFF) * (a2 ^ 0xFF)) >> 8) ^ 0xFF;
}

/// Blend two RGB pixels using alpha
ubyte blendGray(ubyte dst, ubyte src, uint alpha)
{
    uint ialpha = 256 - alpha;
    return cast(ubyte)(((src * ialpha + dst * alpha) >> 8) & 0xFF);
}
