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
import beamui.core.functions;
import beamui.core.types : State;
import CSS = beamui.css.tokenizer;
import beamui.style.decode_css : decode, isSupportedByCSS;
import beamui.style.types : SpecialCSSType;

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

//         eliminate(properties.backgroundImage);
//         eliminate(properties.boxShadow);

        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed style, count: ", _instanceCount);
    }

    /// Try to find a property in this style by exact type and CSS name
    T* peek(T, SpecialCSSType specialType = SpecialCSSType.none)(string name)
    if (isSupportedByCSS!T || specialType != SpecialCSSType.none)
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
                T value = decode!(T, specialType)(*p, err);
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
