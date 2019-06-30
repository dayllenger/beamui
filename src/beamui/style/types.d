/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.types;

import beamui.core.types : State;
import beamui.core.units : Length;
import beamui.graphics.drawables : BgSizeType;

/// Align option bit constants
enum Align : uint
{
    /// Alignment is not specified
    unspecified = 0,
    /// Horizontally align to the left of box
    left = 1,
    /// Horizontally align to the right of box
    right = 2,
    /// Horizontally align to the center of box
    hcenter = 1 | 2,
    /// Vertically align to the top of box
    top = 4,
    /// Vertically align to the bottom of box
    bottom = 8,
    /// Vertically align to the center of box
    vcenter = 4 | 8,
    /// Align to the center of box (vcenter | hcenter)
    center = vcenter | hcenter,
    /// Align to the top left corner of box (left | top)
    topleft = left | top,
}

/// Text drawing flag bits
enum TextFlag : uint
{
    /// Not set
    unspecified = 0,
    /// Text contains hot key prefixed with & char (e.g. "&File")
    hotkeys = 1,
    /// Underline hot key when drawing
    underlineHotkeys = hotkeys | 2,
    /// Underline hot key when Alt is pressed
    underlineHotkeysOnAlt = hotkeys | 4,
    /// Underline text when drawing
    underline = 8,
    /// Strikethrough text when drawing
    strikeThrough = 16, // TODO:
    /// Use text flags from parent widget
    parent = 32
}

struct BgPositionRaw
{
    Length x = Length.percent(50);
    Length y = Length.percent(50);

    static BgPositionRaw mix(BgPositionRaw a, BgPositionRaw b, double factor)
    {
        const x = a.x * (1 - factor) + b.x * factor;
        const y = a.y * (1 - factor) + b.y * factor;
        return BgPositionRaw(x, y);
    }
}

struct BgSizeRaw
{
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
    import std.algorithm.searching : canFind;
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
                if (a.str.length == 0 || canFind!(ch => isWhite(ch))(a.str))
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
    opacity, /// ubyte
    time, /// uint
    transitionProperty, /// string
}

struct ShorthandBorder
{
    size_t name;
    size_t topWidth;
    size_t rightWidth;
    size_t bottomWidth;
    size_t leftWidth;
    size_t color;
}

struct ShorthandDrawable
{
    size_t name;
    size_t color;
    size_t image;
}

struct ShorthandInsets
{
    size_t name;
    size_t top;
    size_t right;
    size_t bottom;
    size_t left;
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
