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
import beamui.core.types : State;
import beamui.core.units : Dimension;
import CSS = beamui.css.tokenizer;
import beamui.graphics.colors : Color;
import beamui.graphics.drawables : Drawable;
import beamui.graphics.text : TextDecoration;
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
    T* peek(T, SpecialCSSType specialType = SpecialCSSType.none)(StrHash name)
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
                T value = void;
                // decode and put
                static if (specialType != SpecialCSSType.none)
                    bool success = decode!specialType(*p, value);
                else
                    bool success = decode(*p, value);
                if (success)
                {
                    properties[name] = Variant(value);
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
            Color color = void;
            Dimension width = void;
            if (decodeBorder(*p, color, width))
            {
                tryToSet(sh.topWidth, Variant(width));
                tryToSet(sh.rightWidth, Variant(width));
                tryToSet(sh.bottomWidth, Variant(width));
                tryToSet(sh.leftWidth, Variant(width));
                tryToSet(sh.color, Variant(color));
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
            Color color = void;
            Drawable image = void;
            if (decodeBackground(*p, color, image))
            {
                tryToSet(sh.color, Variant(color));
                tryToSet(sh.image, Variant(image));
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
            Dimension[] list = void;
            if (decodeInsets(*p, list))
            {
                // [all], [vertical horizontal], [top horizontal bottom], [top right bottom left]
                tryToSet(sh.top, Variant(list[0]));
                tryToSet(sh.right, Variant(list[list.length > 1 ? 1 : 0]));
                tryToSet(sh.bottom, Variant(list[list.length > 2 ? 2 : 0]));
                tryToSet(sh.left, Variant(list[list.length == 4 ? 3 : list.length == 1 ? 0 : 1]));
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
            TextDecoration value = void;
            if (decode(*p, value))
            {
                tryToSet(sh.color, Variant(value.color));
                tryToSet(sh.line, Variant(value.line));
                tryToSet(sh.style, Variant(value.style));
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
            string prop = void;
            TimingFunction func = void;
            uint dur = void;
            uint del = void;
            if (decodeTransition(*p, prop, func, dur, del))
            {
                tryToSet(sh.property, Variant(prop));
                tryToSet(sh.timingFunction, Variant(func));
                tryToSet(sh.duration, Variant(dur));
                tryToSet(sh.delay, Variant(del));
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

    private void tryToSet(string name, lazy Variant v)
    {
        const hash = StrHash(name);
        if (hash !in rawProperties)
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
