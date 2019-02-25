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
import beamui.graphics.drawables : Drawable;
import beamui.style.decode_css;
import beamui.style.types;
import beamui.text.style : TextDecoration;

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

    /// Find a shorthand border property, split it into components and decode
    void explode(ShorthandBorder sh)
    {
        const name = StrHash(sh.name);
        if (auto p = name in rawProperties)
        {
            if (auto res = decodeBorder(*p))
            {
                auto color = res.val[0];
                auto width = res.val[1];
                tryToSetShorthandPart(sh.topWidth, width.err, Variant(width.val));
                tryToSetShorthandPart(sh.rightWidth, width.err, Variant(width.val));
                tryToSetShorthandPart(sh.bottomWidth, width.err, Variant(width.val));
                tryToSetShorthandPart(sh.leftWidth, width.err, Variant(width.val));
                tryToSetShorthandPart(sh.color, color.err, Variant(color.val));
            }
            rawProperties.remove(name);
        }
        if (auto p = name in metaProperties)
        {
            metaProperties[StrHash(sh.topWidth)] = *p;
            metaProperties[StrHash(sh.rightWidth)] = *p;
            metaProperties[StrHash(sh.bottomWidth)] = *p;
            metaProperties[StrHash(sh.leftWidth)] = *p;
            metaProperties[StrHash(sh.color)] = *p;
            metaProperties.remove(name);
        }
    }
    /// Find a shorthand drawable (background, usually) property, split it into components and decode
    void explode(ShorthandDrawable sh)
    {
        const name = StrHash(sh.name);
        if (auto p = name in rawProperties)
        {
            if (auto res = decodeBackground(*p))
            {
                Result!Color color = res.val[0];
                Result!Drawable image = res.val[1];
                tryToSetShorthandPart(sh.color, color.err, Variant(color.val));
                tryToSetShorthandPart(sh.image, image.err, Variant(image.val));
            }
            rawProperties.remove(name);
        }
        if (auto p = name in metaProperties)
        {
            metaProperties[StrHash(sh.color)] = *p;
            metaProperties[StrHash(sh.image)] = *p;
            metaProperties.remove(name);
        }
    }
    /// Find a shorthand insets (margin, padding, border-width) property, split it into components and decode
    void explode(ShorthandInsets sh)
    {
        const name = StrHash(sh.name);
        if (auto p = name in rawProperties)
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
            rawProperties.remove(name);
        }
        if (auto p = name in metaProperties)
        {
            metaProperties[StrHash(sh.top)] = *p;
            metaProperties[StrHash(sh.right)] = *p;
            metaProperties[StrHash(sh.bottom)] = *p;
            metaProperties[StrHash(sh.left)] = *p;
            metaProperties.remove(name);
        }
    }
    /// Find a shorthand text decoration property, split it into components and decode
    void explode(ShorthandTextDecoration sh)
    {
        const name = StrHash(sh.name);
        if (auto p = name in rawProperties)
        {
            if (auto res = decodeTextDecoration(*p))
            {
                auto line = res.val[0];
                auto color = res.val[1];
                auto style = res.val[2];
                tryToSetShorthandPart(sh.line, false, Variant(line));
                tryToSetShorthandPart(sh.color, color.err, Variant(color.val));
                tryToSetShorthandPart(sh.style, style.err, Variant(style.val));
            }
            rawProperties.remove(name);
        }
        if (auto p = name in metaProperties)
        {
            metaProperties[StrHash(sh.color)] = *p;
            metaProperties[StrHash(sh.line)] = *p;
            metaProperties[StrHash(sh.style)] = *p;
            metaProperties.remove(name);
        }
    }
    /// Find a shorthand transition property, split it into components and decode
    void explode(ShorthandTransition sh)
    {
        const name = StrHash(sh.name);
        if (auto p = name in rawProperties)
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
            rawProperties.remove(name);
        }
        if (auto p = name in metaProperties)
        {
            metaProperties[StrHash(sh.property)] = *p;
            metaProperties[StrHash(sh.timingFunction)] = *p;
            metaProperties[StrHash(sh.duration)] = *p;
            metaProperties[StrHash(sh.delay)] = *p;
            metaProperties.remove(name);
        }
    }

    private void tryToSetShorthandPart(string name, bool initial, lazy Variant v)
    {
        const hash = StrHash(name);
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
