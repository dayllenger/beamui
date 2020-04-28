/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.types;

@safe:

import beamui.core.types : State;
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

/// CSS element selector
struct Selector
{
    nothrow:

    import std.ascii : isWhite;
    import std.string : indexOf;

    /// Name of a widget or custom name
    string type;
    /// ID, `#id` from CSS
    string id;
    /// List of style classes, `.class` from CSS
    string[] classes;
    /// State that is specified as `:pseudo-class`
    State specifiedState;
    /// State that is enabled, e.g. `pressed|focused` in `:pressed:focused:not(checked)`
    State enabledState;
    /// Subitem, `::pseudo-element` from CSS
    string subitem;

    /// Attribute matcher
    struct Attr
    {
        enum Pattern
        {
            invalid,
            whatever, /// [attr]
            exact, /// [attr=value]
            include, /// [attr~=value]
            dash, /// [attr|=value]
            prefix, /// [attr^=value]
            suffix, /// [attr$=value]
            substring, /// [attr*=value]
        }
        string name;
        private string str;
        private Pattern pattern;

        bool match(string value) const
        {
            final switch (pattern) with (Pattern)
            {
            case invalid:
                return false;
            case whatever:
                return true;
            case exact:
                return str == value;
            case include:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                {
                    const i = indexOf(value, str);
                    if (i == -1)
                        return false;
                    if (i > 0 && !isWhite(value[i - 1]))
                        return false;
                    if (i + str.length < value.length && !isWhite(value[i + str.length]))
                        return false;
                    return true;
                }
                else
                    return false;
            case dash:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                    return value[str.length] == '-' && value[0 .. str.length] == str;
                else
                    return false;
            case prefix:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                    return value[0 .. str.length] == str;
                else
                    return false;
            case suffix:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                    return value[$ - str.length .. $] == str;
                else
                    return false;
            case substring:
                return indexOf(value, str) != -1;
            }
        }
    }
    /// List of attributes, `[attr]` variations from CSS
    Attr[] attributes;

    /// Check if attribute selectors can match something
    void validateAttrs()
    {
        foreach (ref a; attributes) with (Attr.Pattern)
        {
            if (a.pattern == include)
            {
                if (a.str.length > 0)
                {
                    foreach (ch; a.str)
                    {
                        if (isWhite(ch))
                        {
                            a.pattern = invalid;
                            break;
                        }
                    }
                }
                else
                    a.pattern = invalid;
            }
            if (a.pattern == prefix || a.pattern == suffix || a.pattern == substring)
            {
                if (a.str.length == 0)
                    a.pattern = invalid;
            }
        }
    }

    /// Combinator in complex selectors
    enum Combinator
    {
        descendant,
        child,
        next,
        subsequent
    }
    /// ditto
    Combinator combinator;
    /// Points to previous selector in the complex
    Selector* previous;

    /// True if this is a universal selector without id, state, etc.
    bool universal;

    /// Compute `universal` property
    void calculateUniversality()
    {
        universal = !type && !id && !classes && specifiedState == State.init && !subitem && !attributes;
    }

    /**
    Selector specificity.

    0 - the number of ID selectors,
    1 - the number of class and attribute selectors,
    2 - special rating of state selectors,
    3 - the number of type selectors and pseudo-elements
    */
    uint[4] specificity;

    /// Calculate specificity of this selector
    void calculateSpecificity()
    {
        import core.bitop : popcnt; // bit count

        Selector* s = &this;
        while (s)
        {
            if (s.universal)
            {
                s = s.previous;
                continue;
            }
            if (s.id)
                specificity[0]++;
            if (s.classes)
                specificity[1] += cast(uint)s.classes.length;
            if (s.attributes)
                specificity[1] += cast(uint)s.attributes.length;
            State st = s.specifiedState;
            if (st != State.init)
                specificity[2] += st * st * popcnt(st);
            if (s.type)
                specificity[3]++;
            if (s.subitem)
                specificity[3]++;
            s = s.previous;
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
