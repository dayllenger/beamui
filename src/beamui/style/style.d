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
    private
    {
        /// Decoded properties, stored as variants
        Variant[string] properties;
        /// Raw properties right from CSS parser
        CSS.Token[][string] rawProperties;

        /// State descriptor
        struct StateStyle
        {
            Style s;
            State specified;
            State enabled;
        }
        /// State styles like :pressed or :not(enabled)
        StateStyle[] stateStyles;

        debug static __gshared int _instanceCount;
    }

    this() pure
    {
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created style, count: ", _instanceCount);
    }

    debug @property static int instanceCount() { return _instanceCount; }

    ~this()
    {
        foreach (s; stateStyles)
            eliminate(s.s);
        destroy(stateStyles);
        stateStyles = null;

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
                bool err;
                // decode and put
                static if (specialType != SpecialCSSType.none)
                    T value = decode!specialType(*p, err);
                else
                    T value = decode!T(*p, err);
                if (!err)
                {
                    Variant v = Variant(value);
                    properties[name] = v;
                    return v.peek!T;
                }
                else
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
            Color color = Color.none;
            Dimension width = Dimension.none;
            decodeBorder(*p, color, width);

            if (width != Dimension.none)
            {
                properties[sh.topWidth] = Variant(width);
                properties[sh.rightWidth] = Variant(width);
                properties[sh.bottomWidth] = Variant(width);
                properties[sh.leftWidth] = Variant(width);
            }
            if (color != Color.none)
                properties[sh.color] = Variant(color);

            rawProperties.remove(sh.name);
        }
    }

    void explode(shorthandDrawable sh)()
    {
        if (auto p = sh.name in rawProperties)
        {
            Color color;
            Drawable image;
            decodeBackground(*p, color, image);

            if (color != Color.none)
                properties[sh.color] = Variant(color);
            properties[sh.image] = Variant(image);

            rawProperties.remove(sh.name);
        }
    }

    void explode(shorthandInsets sh)()
    {
        if (auto p = sh.name in rawProperties)
        {
            if (auto list = decodeInsets(*p))
            {
                // [all], [vertical horizontal], [top horizontal bottom], [top right bottom left]
                properties[sh.top]    = Variant(list[0]);
                properties[sh.right]  = Variant(list[list.length > 1 ? 1 : 0]);
                properties[sh.bottom] = Variant(list[list.length > 2 ? 2 : 0]);
                properties[sh.left]   = Variant(list[list.length == 4 ? 3 : list.length == 1 ? 0 : 1]);
            }
            rawProperties.remove(sh.name);
        }
    }

    void explode(shorthandTransition sh)()
    {
        if (auto p = sh.name in rawProperties)
        {
            string prop;
            TimingFunction func = cast(TimingFunction)TimingFunction.linear;
            uint dur = uint.max;
            uint del = uint.max;
            decodeTransition(*p, prop, func, dur, del);

            if (prop)
                properties[sh.property] = Variant(prop);
            properties[sh.timingFunction] = Variant(func);
            if (dur != uint.max)
                properties[sh.duration] = Variant(dur);
            if (del != uint.max)
                properties[sh.delay] = Variant(del);

            rawProperties.remove(sh.name);
        }
    }

    void setRawProperty(string name, CSS.Token[] tokens)
    {
        rawProperties[name] = tokens;
    }

    /// Find substyle based on widget state (e.g. focused, pressed, ...)
    inout(Style) forState(State state) inout
    {
        if (state == State.normal)
            return this;
        foreach (s; stateStyles)
        {
            if ((s.specified & state) == s.enabled)
                return s.s;
        }
        // not found - fallback to normal
        return this;
    }

    /// Find exact existing state style or create new if no matched styles found
    Style getOrCreateState(State specified, State enabled)
    {
        import core.bitop : popcnt;

        if (specified == State.unspecified)
            return this;
        foreach (s; stateStyles)
            if (s.specified == specified && s.enabled == enabled)
                return s.s;
        // not found
        debug (styles)
            Log.d("Creating substate: ", specified);

        auto s = new Style;
        stateStyles ~= StateStyle(s, specified, enabled);
        // sort state styles by state value and its bit count
        stateStyles.sort!((a, b) => a.specified * a.specified * popcnt(a.specified) >
                                    b.specified * b.specified * popcnt(b.specified));
        return s;
    }
}
