/**

Synopsis:
---
import beamui.style.style;
---

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
import beamui.style.decode_css;
import beamui.style.types;

/// Style - holds properties for a single selector
final class Style
{
    /// Style rule selector
    @property ref const(Selector) selector() const { return _selector; }

    private
    {
        Selector _selector;
        /// Decoded properties, stored as variants
        Variant[string] properties;
        /// Raw properties right from CSS parser
        CSS.Token[][string] rawProperties;

        debug static __gshared int _instanceCount;
    }

    /// Create style with some selector
    this(Selector selector)
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

    /// Try to find a property in this style by exact type and CSS name
    T* peek(T, SpecialCSSType specialType = SpecialCSSType.none)(string name)
    {
        if (auto p = name in properties)
        {
            // has property with this name, try to get with this type
            return (*p).peek!T;
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
                    Variant v = Variant(value);
                    properties[name] = v;
                    return v.peek!T;
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

    void explode(shorthandBorder sh)()
    {
        if (auto p = sh.name in rawProperties)
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
            rawProperties.remove(sh.name);
        }
    }

    void explode(shorthandDrawable sh)()
    {
        if (auto p = sh.name in rawProperties)
        {
            Color color = void;
            Drawable image = void;
            if (decodeBackground(*p, color, image))
            {
                tryToSet(sh.color, Variant(color));
                tryToSet(sh.image, Variant(image));
            }
            rawProperties.remove(sh.name);
        }
    }

    void explode(shorthandInsets sh)()
    {
        if (auto p = sh.name in rawProperties)
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
            rawProperties.remove(sh.name);
        }
    }

    void explode(shorthandTransition sh)()
    {
        if (auto p = sh.name in rawProperties)
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
            rawProperties.remove(sh.name);
        }
    }

    private void tryToSet(string name, lazy Variant v)
    {
        if (name !in rawProperties)
            properties[name] = v;
    }

    void setRawProperty(string name, CSS.Token[] tokens)
    {
        rawProperties[name] = tokens;
    }

    override int opCmp(Object o) const
    {
        assert(cast(Style)o);
        import std.algorithm.comparison : cmp;

        const(uint[]) a = selector.specificity;
        const(uint[]) b = (cast(Style)o).selector.specificity;
        return cmp(a, b);
    }
}
