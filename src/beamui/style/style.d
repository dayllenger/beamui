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

import beamui.core.animations : TimingFunction;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types;
import beamui.core.units;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.graphics.fonts;
import beamui.style.types;

/// All style properties in one place
struct StyleProperties
{
    // layout
    Dimension width = Dimension.none;
    Dimension height = Dimension.none;
    Dimension minWidth = Dimension.zero;
    Dimension maxWidth = Dimension.none;
    Dimension minHeight = Dimension.zero;
    Dimension maxHeight = Dimension.none;
    int weight = 1;
    Align alignment = Align.topleft;
    Dimension marginTop = Dimension.zero;
    Dimension marginRight = Dimension.zero;
    Dimension marginBottom = Dimension.zero;
    Dimension marginLeft = Dimension.zero;
    Dimension paddingTop = Dimension.zero;
    Dimension paddingRight = Dimension.zero;
    Dimension paddingBottom = Dimension.zero;
    Dimension paddingLeft = Dimension.zero;
    // background
    uint borderColor = COLOR_UNSPECIFIED;
    Dimension borderWidthTop = Dimension.zero;
    Dimension borderWidthRight = Dimension.zero;
    Dimension borderWidthBottom = Dimension.zero;
    Dimension borderWidthLeft = Dimension.zero;
    uint backgroundColor = COLOR_TRANSPARENT;
    Drawable backgroundImage;
    BoxShadowDrawable boxShadow;
    // text
    string fontFace = "Arial";
    FontFamily fontFamily = FontFamily.sans_serif;
    Dimension fontSize = Dimension.pt(9);
    FontStyle fontStyle = FontStyle.normal;
    ushort fontWeight = 400;
    TextFlag textFlags = TextFlag.unspecified;
    int maxLines = 1;
    // colors
    ubyte alpha = 0;
    uint textColor = 0x000000;
    uint focusRectColor = COLOR_UNSPECIFIED;
    // transitions and animations
    string transitionProperty;
    TimingFunction transitionTimingFunction;
    uint transitionDuration;
    uint transitionDelay;
}

/// Style - holds properties for a single selector
final class Style
{
    // generate getters and setters
    static foreach (i; 0 .. StyleProperties.tupleof.length)
    {
        mixin(format(`

            @property inout(%2$s) %1$s() inout
            {
                return properties.%1$s;
            }

            @property Style %1$s(%2$s value)
            {
                properties.%1$s = value;
                written[%3$s] = true;
                return this;
            }
            `, StyleProperties.tupleof[i].stringof, typeof(StyleProperties.tupleof[i]).stringof, i)
        );
    }

    //===================================================
    // shorthands

    Style margins(Dimension[] list...)
    in
    {
        assert(list !is null);
        assert(0 < list.length && list.length <= 4);
    }
    body
    {
        // [all], [vertical horizontal], [top horizontal bottom], [top right bottom left]
        marginTop = list[0];
        marginRight = list[list.length > 1 ? 1 : 0];
        marginBottom = list[list.length > 2 ? 2 : 0];
        marginLeft = list[list.length == 4 ? 3 : list.length == 1 ? 0 : 1];
        return this;
    }

    Style padding(Dimension[] list...)
    in
    {
        assert(list !is null);
        assert(0 < list.length && list.length <= 4);
    }
    body
    {
        paddingTop = list[0];
        paddingRight = list[list.length > 1 ? 1 : 0];
        paddingBottom = list[list.length > 2 ? 2 : 0];
        paddingLeft = list[list.length == 4 ? 3 : list.length == 1 ? 0 : 1];
        return this;
    }

    Style borderWidth(Dimension[] list...)
    in
    {
        assert(list !is null);
        assert(0 < list.length && list.length <= 4);
    }
    body
    {
        borderWidthTop = list[0];
        borderWidthRight = list[list.length > 1 ? 1 : 0];
        borderWidthBottom = list[list.length > 2 ? 2 : 0];
        borderWidthLeft = list[list.length == 4 ? 3 : list.length == 1 ? 0 : 1];
        return this;
    }

    //===================================================

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

    /// Print all style properties (for debugging purposes)
    debug void printStats() const
    {
        Log.d("--- Style stats ---");
        static foreach (i, p; [
            "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
            "weight", "alignment", "marginTop", "marginRight", "marginBottom", "marginLeft",
            "paddingTop", "paddingRight", "paddingBottom", "paddingLeft",
            "borderColor", "borderWidthTop", "borderWidthRight", "borderWidthBottom", "borderWidthLeft",
            "backgroundColor", "backgroundImage", "boxShadow",
            "fontFace", "fontFamily", "fontSize", "fontStyle", "fontWeight",
            "textFlags", "maxLines",
            "alpha", "textColor", "focusRectColor"])
        {{
            static if (is(typeof(mixin("Style." ~ p)) == class)) // print only type of drawable
                enum msg = p ~ " ? typeid(this." ~ p ~ ").name : `-`";
            else
                enum msg = p;

            Log.d(written[i] ? p ~ " (o): " : p ~ ": ", mixin(msg));
        }}
    }

    debug @property static int instanceCount() { return _instanceCount; }

package (beamui.style):

    /// Propeties container
    StyleProperties properties;
    /// This is a bitmap that indicates which style properties are written in this style rule
    bool[StyleProperties.tupleof.length] written;

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

    this() pure
    {
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created style, count: ", _instanceCount);
    }

    ~this()
    {
        foreach (s; stateStyles)
            eliminate(s.s);
        destroy(stateStyles);
        stateStyles = null;

        eliminate(properties.backgroundImage);
        eliminate(properties.boxShadow);

        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed style, count: ", _instanceCount);
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
