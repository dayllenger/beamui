/**
Widget style, that contains named properties and is associated with selector.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.style;

import std.variant : Variant;
import beamui.core.animations : TimingFunction;
import beamui.core.functions;
import beamui.core.types : Result, State;
import beamui.core.units : Length;
import CSS = beamui.css.tokenizer;
import beamui.graphics.colors : Color;
import beamui.graphics.drawables : BorderStyle, Drawable;
import beamui.style.decode_css;
import beamui.style.types;

/// Holds string hash and can compute it at compile time for faster CSS name lookup
struct StrHash
{
    immutable size_t value;
    alias value this;

    this(string str)
    {
        value = hashOf(str);
    }
}

/// Style - holds properties for a single selector
final class Style
{
    /// Style rule selector
    @property ref const(Selector) selector() const { return _selector; }

    private
    {
        const(Selector) _selector;
        /// Decoded properties, stored as variants
        Variant[size_t] properties;
        /// Raw properties right from CSS parser
        const(CSS.Token)[][size_t] rawProperties;

        enum Meta { inherit, initial }
        Meta[size_t] metaProperties;

        debug static __gshared int _instanceCount;
    }

    /// Create style with some selector
    this(const Selector selector)
    {
        _selector = selector;
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created style, count: ", _instanceCount);
    }

    debug @property static int instanceCount() { return _instanceCount; }

    ~this()
    {
        if (properties !is null)
        {
            foreach (ref v; properties)
            {
                if (v.convertsTo!Object)
                    destroy(v.get!Object);
                destroy(v);
            }
            destroy(properties);
        }

        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed style, count: ", _instanceCount);
    }

    /// Returns true whether CSS property is set to `inherit`
    bool isInherited(StrHash name)
    {
        if (auto p = name in metaProperties)
            return *p == Meta.inherit;
        else
            return false;
    }

    /// Returns true whether CSS property is set to `initial`
    bool isInitial(StrHash name)
    {
        if (auto p = name in metaProperties)
            return *p == Meta.initial;
        else
            return false;
    }

    /// Try to find a property in this style by exact type and CSS name hash
    T* peek(T, SpecialCSSType specialType = SpecialCSSType.none)(StrHash name,
        scope bool delegate(ref const(T)) sanitizer)
    {
        if (auto p = name in properties)
        {
            // has property with this name, try to get with this type
            return p.peek!T;
        }
        else
        {
            // not computed yet - search in sources
            if (auto p = name in rawProperties)
            {
                // decode and put
                static if (specialType != SpecialCSSType.none)
                    Result!T result = decode!specialType(*p);
                else
                    Result!T result = decode!T(*p);
                if (!result.err)
                {
                    if (sanitizer && !sanitizer(result.val))
                    {
                        logInvalidValue(*p);
                        rawProperties.remove(name);
                        return null;
                    }
                    properties[name] = Variant(result.val);
                    return (name in properties).peek!T;
                }
                else // skip and forget
                {
                    rawProperties.remove(name);
                    return null;
                }
            }
            // not found
            return null;
        }
    }

    /// Find a shorthand color property, split it into components and decode
    void explode(ref immutable ShorthandColors sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto res = decode!Color(*p))
            {
                auto v = Variant(res.val);
                tryToSetShorthandPart(sh.top, false, v);
                tryToSetShorthandPart(sh.right, false, v);
                tryToSetShorthandPart(sh.bottom, false, v);
                tryToSetShorthandPart(sh.left, false, v);
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.top] = *p;
            metaProperties[sh.right] = *p;
            metaProperties[sh.bottom] = *p;
            metaProperties[sh.left] = *p;
            metaProperties.remove(sh.name);
        }
    }
    /// Find a shorthand drawable (background, usually) property, split it into components and decode
    void explode(ref immutable ShorthandDrawable sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto res = decodeBackground(*p))
            {
                Result!Color color = res.val[0];
                Result!Drawable image = res.val[1];
                tryToSetShorthandPart(sh.color, color.err, Variant(color.val));
                tryToSetShorthandPart(sh.image, image.err, Variant(image.val));
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.color] = *p;
            metaProperties[sh.image] = *p;
            metaProperties.remove(sh.name);
        }
    }
    /// Find a shorthand insets (margin, padding, border-width) property, split it into components and decode
    void explode(ref immutable ShorthandInsets sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            Length[] list = decodeInsets(*p);
            if (list.length > 0)
            {
                // [all], [vertical horizontal], [top horizontal bottom], [top right bottom left]
                tryToSetShorthandPart(sh.top, false, Variant(list[0]));
                tryToSetShorthandPart(sh.right, false, Variant(list[list.length > 1 ? 1 : 0]));
                tryToSetShorthandPart(sh.bottom, false, Variant(list[list.length > 2 ? 2 : 0]));
                tryToSetShorthandPart(sh.left, false, Variant(list[list.length == 4 ? 3 : list.length == 1 ? 0 : 1]));
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.top] = *p;
            metaProperties[sh.right] = *p;
            metaProperties[sh.bottom] = *p;
            metaProperties[sh.left] = *p;
            metaProperties.remove(sh.name);
        }
    }
    /// Find a shorthand border property, split it into components and decode
    void explode(ref immutable ShorthandBorder sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto res = decodeBorder(*p))
            {
                auto wv = Variant(res.val[0].val);
                auto sv = Variant(res.val[1]);
                auto cv = Variant(res.val[2].val);
                const wreset = res.val[0].err;
                const creset = res.val[2].err;
                tryToSetShorthandPart(sh.topWidth, wreset, wv);
                tryToSetShorthandPart(sh.topStyle, false, sv);
                tryToSetShorthandPart(sh.topColor, creset, cv);
                tryToSetShorthandPart(sh.rightWidth, wreset, wv);
                tryToSetShorthandPart(sh.rightStyle, false, sv);
                tryToSetShorthandPart(sh.rightColor, creset, cv);
                tryToSetShorthandPart(sh.bottomWidth, wreset, wv);
                tryToSetShorthandPart(sh.bottomStyle, false, sv);
                tryToSetShorthandPart(sh.bottomColor, creset, cv);
                tryToSetShorthandPart(sh.leftWidth, wreset, wv);
                tryToSetShorthandPart(sh.leftStyle, false, sv);
                tryToSetShorthandPart(sh.leftColor, creset, cv);
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.topWidth] = *p;
            metaProperties[sh.topStyle] = *p;
            metaProperties[sh.topColor] = *p;
            metaProperties[sh.rightWidth] = *p;
            metaProperties[sh.rightStyle] = *p;
            metaProperties[sh.rightColor] = *p;
            metaProperties[sh.bottomWidth] = *p;
            metaProperties[sh.bottomStyle] = *p;
            metaProperties[sh.bottomColor] = *p;
            metaProperties[sh.leftWidth] = *p;
            metaProperties[sh.leftStyle] = *p;
            metaProperties[sh.leftColor] = *p;
            metaProperties.remove(sh.name);
        }
    }
    /// Find a shorthand border style property, split it into components and decode
    void explode(ref immutable ShorthandBorderStyle sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto res = decode!BorderStyle(*p))
            {
                auto v = Variant(res.val);
                tryToSetShorthandPart(sh.top, false, v);
                tryToSetShorthandPart(sh.right, false, v);
                tryToSetShorthandPart(sh.bottom, false, v);
                tryToSetShorthandPart(sh.left, false, v);
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.top] = *p;
            metaProperties[sh.right] = *p;
            metaProperties[sh.bottom] = *p;
            metaProperties[sh.left] = *p;
            metaProperties.remove(sh.name);
        }
    }
    /// Find a shorthand border side property, split it into components and decode
    void explode(ref immutable ShorthandBorderSide sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto res = decodeBorder(*p))
            {
                tryToSetShorthandPart(sh.width, res.val[0].err, Variant(res.val[0].val));
                tryToSetShorthandPart(sh.style, false, Variant(res.val[1]));
                tryToSetShorthandPart(sh.color, res.val[2].err, Variant(res.val[2].val));
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.width] = *p;
            metaProperties[sh.style] = *p;
            metaProperties[sh.color] = *p;
            metaProperties.remove(sh.name);
        }
    }
    /// Find a shorthand text decoration property, split it into components and decode
    void explode(ref immutable ShorthandTextDecor sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto res = decodeTextDecor(*p))
            {
                auto line = res.val[0];
                auto color = res.val[1];
                auto style = res.val[2];
                tryToSetShorthandPart(sh.line, false, Variant(line));
                tryToSetShorthandPart(sh.color, color.err, Variant(color.val));
                tryToSetShorthandPart(sh.style, style.err, Variant(style.val));
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.line] = *p;
            metaProperties[sh.color] = *p;
            metaProperties[sh.style] = *p;
            metaProperties.remove(sh.name);
        }
    }
    /// Find a shorthand transition property, split it into components and decode
    void explode(ref immutable ShorthandTransition sh)
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto res = decodeTransition(*p))
            {
                auto prop = res.val[0];
                auto dur = res.val[1];
                auto tfunc = res.val[2];
                auto delay = res.val[3];
                tryToSetShorthandPart(sh.property, prop.err, Variant(prop.val));
                tryToSetShorthandPart(sh.duration, dur.err, Variant(dur.val));
                tryToSetShorthandPart(sh.timingFunction, tfunc.err, Variant(tfunc.val));
                tryToSetShorthandPart(sh.delay, delay.err, Variant(delay.val));
            }
            rawProperties.remove(sh.name);
        }
        if (auto p = sh.name in metaProperties)
        {
            metaProperties[sh.property] = *p;
            metaProperties[sh.timingFunction] = *p;
            metaProperties[sh.duration] = *p;
            metaProperties[sh.delay] = *p;
            metaProperties.remove(sh.name);
        }
    }

    private void tryToSetShorthandPart(size_t hash, bool initial, lazy Variant v)
    {
        if (initial)
        {
            if (hash !in metaProperties)
                metaProperties[hash] = Meta.initial;
        }
        else if (hash !in rawProperties)
            properties[hash] = v;
    }

    package void setRawProperty(string name, const CSS.Token[] tokens)
    {
        assert(tokens.length > 0);

        const hash = StrHash(name);
        if (tokens.length == 1 && tokens[0].type == CSS.TokenType.ident)
        {
            switch (tokens[0].text)
            {
                case "inherit": metaProperties[hash] = Meta.inherit; return;
                case "initial": metaProperties[hash] = Meta.initial; return;
                default: break;
            }
        }
        // usual value
        rawProperties[hash] = tokens;
    }

    /// Ability to compare styles by their selector specificity
    override int opCmp(Object o) const
    {
        assert(cast(Style)o);
        import std.algorithm.comparison : cmp;

        const(uint[]) a = selector.specificity;
        const(uint[]) b = (cast(Style)o).selector.specificity;
        return cmp(a, b);
    }
}
