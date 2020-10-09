/**

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.property;

import beamui.core.animations : TimingFunction;
import beamui.core.editable : TabSize;
import beamui.core.units : Length;
import beamui.css.tokenizer : Token;
import beamui.graphics.colors : Color;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables : BorderStyle, BoxShadowDrawable, BoxType, Drawable, RepeatStyle;
import beamui.layout.alignment : Align, AlignItem, Distribution, Stretch;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.types;
import beamui.text.fonts : GenericFontFamily, FontStyle;
import beamui.text.style;
import beamui.widgets.widget : CursorType;

/// Enumeration of all supported style properties. NOTE: DON'T use `case .. case` slices on them,
/// because order may be changed in the future.
enum StyleProperty
{
    // origins
    fontSize,
    // layout
    display,
    // box model
    width,
    height,
    minWidth,
    maxWidth,
    minHeight,
    maxHeight,
    paddingTop,
    paddingRight,
    paddingBottom,
    paddingLeft,
    borderTopWidth,
    borderRightWidth,
    borderBottomWidth,
    borderLeftWidth,
    marginTop,
    marginRight,
    marginBottom,
    marginLeft,
    // placement
    left,
    top,
    right,
    bottom,
    alignment,
    stretch,
    justifyContent,
    justifyItems,
    justifySelf,
    alignContent,
    alignItems,
    alignSelf,
    rowGap,
    columnGap,
    order,
    zIndex,
    // flexbox-specific
    flexDirection,
    flexWrap,
    flexGrow,
    flexShrink,
    flexBasis,
    // grid-specific
    gridTemplateRows,
    gridTemplateColumns,
    gridTemplateAreas,
    gridAutoFlow,
    gridAutoRows,
    gridAutoColumns,
    gridRowStart,
    gridRowEnd,
    gridColumnStart,
    gridColumnEnd,
    // background
    bgColor,
    bgImage,
    bgPosition,
    bgSize,
    bgRepeat,
    bgOrigin,
    bgClip,
    borderTopColor,
    borderRightColor,
    borderBottomColor,
    borderLeftColor,
    borderTopStyle,
    borderRightStyle,
    borderBottomStyle,
    borderLeftStyle,
    borderTopLeftRadius,
    borderTopRightRadius,
    borderBottomLeftRadius,
    borderBottomRightRadius,
    boxShadow,
    focusRectColor,
    // text
    fontFace,
    fontFamily,
    fontStyle,
    fontWeight,
    letterSpacing,
    lineHeight,
    tabSize,
    textAlign,
    textColor,
    textDecorColor,
    textDecorLine,
    textDecorStyle,
    textHotkey,
    textIndent,
    textOverflow,
    textTransform,
    whiteSpace,
    wordSpacing,
    // effects
    transform,
    opacity,
    mixBlendMode,
    // transitions and animations
    transitionProperty,
    transitionTimingFunction,
    transitionDuration,
    transitionDelay,
    // misc
    cursor,
}

package struct PropTypes
{
    Align alignment;
    AlignItem alignItems;
    AlignItem alignSelf;
    AlignItem justifyItems;
    AlignItem justifySelf;
    BgPositionRaw bgPosition;
    BgSizeRaw bgSize;
    BlendMode mixBlendMode;
    BorderStyle borderBottomStyle;
    BorderStyle borderLeftStyle;
    BorderStyle borderRightStyle;
    BorderStyle borderTopStyle;
    BoxShadowDrawable boxShadow;
    BoxType bgClip;
    BoxType bgOrigin;
    Color bgColor;
    Color borderBottomColor;
    Color borderLeftColor;
    Color borderRightColor;
    Color borderTopColor;
    Color focusRectColor;
    Color textColor;
    Color textDecorColor;
    CursorType cursor;
    Distribution alignContent;
    Distribution justifyContent;
    Drawable bgImage;
    FlexDirection flexDirection;
    FlexWrap flexWrap;
    float flexGrow;
    float flexShrink;
    float opacity;
    GenericFontFamily fontFamily;
    FontStyle fontStyle;
    GridFlow gridAutoFlow;
    GridLineName gridColumnEnd;
    GridLineName gridColumnStart;
    GridLineName gridRowEnd;
    GridLineName gridRowStart;
    GridNamedAreas gridTemplateAreas;
    int order;
    int zIndex;
    Length borderBottomLeftRadius;
    Length borderBottomRightRadius;
    Length borderBottomWidth;
    Length borderLeftWidth;
    Length borderRightWidth;
    Length borderTopLeftRadius;
    Length borderTopRightRadius;
    Length borderTopWidth;
    Length bottom;
    Length columnGap;
    Length flexBasis;
    Length fontSize;
    Length height;
    Length left;
    Length letterSpacing;
    Length lineHeight;
    Length marginBottom;
    Length marginLeft;
    Length marginRight;
    Length marginTop;
    Length maxHeight;
    Length maxWidth;
    Length minHeight;
    Length minWidth;
    Length paddingBottom;
    Length paddingLeft;
    Length paddingRight;
    Length paddingTop;
    Length right;
    Length rowGap;
    Length textIndent;
    Length top;
    Length width;
    Length wordSpacing;
    RepeatStyle bgRepeat;
    SingleTransformRaw transform;
    Stretch stretch;
    string display;
    string fontFace;
    string transitionProperty;
    TabSize tabSize;
    TextAlign textAlign;
    TextDecorLine textDecorLine;
    TextDecorStyle textDecorStyle;
    TextHotkey textHotkey;
    TextOverflow textOverflow;
    TextTransform textTransform;
    TimingFunction transitionTimingFunction;
    TrackSize gridAutoColumns;
    TrackSize gridAutoRows;
    TrackSize[] gridTemplateColumns;
    TrackSize[] gridTemplateRows;
    uint transitionDelay;
    uint transitionDuration;
    ushort fontWeight;
    WhiteSpace whiteSpace;
}

private union BuiltinPropertyValue
{
    import std.meta : AliasSeq;

    // dfmt off
    static foreach (T; AliasSeq!(
        Align,
        AlignItem,
        BgPositionRaw,
        BgSizeRaw,
        BlendMode,
        BorderStyle,
        BoxShadowDrawable,
        BoxType,
        Color,
        CursorType,
        Distribution,
        Drawable,
        FlexDirection,
        FlexWrap,
        float,
        GenericFontFamily,
        FontStyle,
        GridFlow,
        GridLineName,
        GridNamedAreas,
        int,
        Length,
        RepeatStyle,
        SingleTransformRaw,
        Stretch,
        string,
        TabSize,
        TextAlign,
        TextDecorLine,
        TextDecorStyle,
        TextHotkey,
        TextOverflow,
        TextTransform,
        TimingFunction,
        TrackSize,
        TrackSize[],
        uint,
        ushort,
        WhiteSpace,
    ))
    {
        mixin(`T ` ~ T.mangleof ~ `;`);
    }
    // dfmt on
}

package struct StylePropertyList
{
    import std.traits : Unqual;

    private enum Pointer : ubyte
    {
        none,
        inherit,
        initial,
        some
    }

    private BuiltinPropertyValue[] values;
    private Pointer[StyleProperty.max + 1] pointers;
    private StaticBitArray!(StyleProperty.max + 1) pointsToVarName;
    const(Token)[][string] customProperties;

    /// Try to get value of a property by exact name. Returns a pointer to it or `null`
    auto peek(string name)()
    {
        alias T = typeof(mixin(`PropTypes.` ~ name));
        enum ptype = mixin(`StyleProperty.` ~ name);

        const ptr = pointers[ptype];
        if (ptr >= Pointer.some && !pointsToVarName[ptype])
            return mixin(`&values[ptr - Pointer.some].` ~ Unqual!T.mangleof);
        return null;
    }

    string getCustomValueName(StyleProperty property)
    {
        if (pointsToVarName[property])
        {
            const v = &values[pointers[property] - Pointer.some];
            return mixin(`v.` ~ string.mangleof);
        }
        return null;
    }

    /// Returns true if `property` is set to something
    bool isSet(StyleProperty property) const
    {
        return pointers[property] != Pointer.none;
    }
    /// Returns true if `property` is set to 'inherit'
    bool isInherited(StyleProperty property) const
    {
        return pointers[property] == Pointer.inherit;
    }
    /// Returns true if `property` is set to 'initial'
    bool isInitial(StyleProperty property) const
    {
        return pointers[property] == Pointer.initial;
    }

    void set(T)(StyleProperty ptype, T v)
    {
        BuiltinPropertyValue value;
        mixin("value." ~ (Unqual!T).mangleof) = v;

        if (pointers[ptype] < Pointer.some)
        {
            pointers[ptype] = cast(Pointer)(values.length + Pointer.some);
            values ~= value;
        }
        else
        {
            values[pointers[ptype] - Pointer.some] = value;
        }
    }

    void setToVarName(StyleProperty ptype, string value)
    {
        set(ptype, value);
        pointsToVarName.set(ptype);
    }

    void inherit(StyleProperty property)
    {
        pointers[property] = Pointer.inherit;
    }

    void initialize(StyleProperty property)
    {
        pointers[property] = Pointer.initial;
    }
}

/// `--something`
package bool isVarName(string name)
{
    return name.length >= 2 && name[0] == '-' && name[1] == '-';
}

/// Checks bounds, like disallowed negative values
package bool sanitizeProperty(StyleProperty ptype, T)(ref const T value)
{
    alias P = StyleProperty;
    // dfmt off
    static if (ptype == P.fontSize)
        return value.toLayout.applyPercent(100) >= 1;
    else static if (ptype == P.bgSize)
        return value.x.toLayout.applyPercent(100) >= 0 && value.y.toLayout.applyPercent(100) >= 0;
    else static if (false
        || ptype == P.width
        || ptype == P.height
        || ptype == P.minWidth
        || ptype == P.maxWidth
        || ptype == P.minHeight
        || ptype == P.maxHeight
        || ptype == P.flexBasis
        || ptype == P.lineHeight
    )
        return value.toLayout.applyPercent(100) >= 0;
    else static if (false
        || ptype == P.paddingTop
        || ptype == P.paddingRight
        || ptype == P.paddingBottom
        || ptype == P.paddingLeft
        || ptype == P.borderTopWidth
        || ptype == P.borderRightWidth
        || ptype == P.borderBottomWidth
        || ptype == P.borderLeftWidth
        || ptype == P.borderTopLeftRadius
        || ptype == P.borderTopRightRadius
        || ptype == P.borderBottomLeftRadius
        || ptype == P.borderBottomRightRadius
        || ptype == P.rowGap
        || ptype == P.columnGap
    )
        return value !is Length.none && value.toLayout.applyPercent(100) >= 0;
    else static if (ptype == P.transform)
        return value.a !is Length.none && value.b !is Length.none;
    else static if (ptype == P.flexGrow || ptype == P.flexShrink)
        return value >= 0;
    else static if (ptype == P.justifyItems || ptype == P.alignItems)
        return value != AlignItem.unspecified;
    else
        return true;
    // dfmt on
}

package SpecialCSSType getSpecialCSSType(StyleProperty ptype)
{
    // dfmt off
    switch (ptype) with (StyleProperty)
    {
        case bgImage:    return SpecialCSSType.image;
        case fontWeight: return SpecialCSSType.fontWeight;
        case opacity:    return SpecialCSSType.opacity;
        case transitionProperty: return SpecialCSSType.transitionProperty;
        case transitionDuration: return SpecialCSSType.time;
        case transitionDelay:    return SpecialCSSType.time;
        default: return SpecialCSSType.none;
    }
    // dfmt on
}

/// Get property name how it looks in CSS
string getCSSName(StyleProperty ptype)
{
    // dfmt off
    final switch (ptype) with (StyleProperty)
    {
        case alignContent: return "align-content";
        case alignItems: return "align-items";
        case alignment: return "align";
        case alignSelf: return "align-self";
        case bgClip: return "background-clip";
        case bgColor: return "background-color";
        case bgImage: return "background-image";
        case bgOrigin: return "background-origin";
        case bgPosition: return "background-position";
        case bgRepeat: return "background-repeat";
        case bgSize: return "background-size";
        case borderBottomColor: return "border-bottom-color";
        case borderBottomLeftRadius: return "border-bottom-left-radius";
        case borderBottomRightRadius: return "border-bottom-right-radius";
        case borderBottomStyle: return "border-bottom-style";
        case borderBottomWidth: return "border-bottom-width";
        case borderLeftColor: return "border-left-color";
        case borderLeftStyle: return "border-left-style";
        case borderLeftWidth: return "border-left-width";
        case borderRightColor: return "border-right-color";
        case borderRightStyle: return "border-right-style";
        case borderRightWidth: return "border-right-width";
        case borderTopColor: return "border-top-color";
        case borderTopLeftRadius: return "border-top-left-radius";
        case borderTopRightRadius: return "border-top-right-radius";
        case borderTopStyle: return "border-top-style";
        case borderTopWidth: return "border-top-width";
        case bottom: return "bottom";
        case boxShadow: return "box-shadow";
        case columnGap: return "column-gap";
        case cursor: return "cursor";
        case display: return "display";
        case flexBasis: return "flex-basis";
        case flexDirection: return "flex-direction";
        case flexGrow: return "flex-grow";
        case flexShrink: return "flex-shrink";
        case flexWrap: return "flex-wrap";
        case focusRectColor: return "focus-rect-color";
        case fontFace: return "font-face";
        case fontFamily: return "font-family";
        case fontSize: return "font-size";
        case fontStyle: return "font-style";
        case fontWeight: return "font-weight";
        case gridAutoColumns: return "grid-auto-columns";
        case gridAutoFlow: return "grid-auto-flow";
        case gridAutoRows: return "grid-auto-rows";
        case gridColumnEnd: return "grid-column-end";
        case gridColumnStart: return "grid-column-start";
        case gridRowEnd: return "grid-row-end";
        case gridRowStart: return "grid-row-start";
        case gridTemplateAreas: return "grid-template-areas";
        case gridTemplateColumns: return "grid-template-columns";
        case gridTemplateRows: return "grid-template-rows";
        case height: return "height";
        case justifyContent: return "justify-content";
        case justifyItems: return "justify-items";
        case justifySelf: return "justify-self";
        case left: return "left";
        case letterSpacing: return "letter-spacing";
        case lineHeight: return "line-height";
        case marginBottom: return "margin-bottom";
        case marginLeft: return "margin-left";
        case marginRight: return "margin-right";
        case marginTop: return "margin-top";
        case maxHeight: return "max-height";
        case maxWidth: return "max-width";
        case minHeight: return "min-height";
        case minWidth: return "min-width";
        case mixBlendMode: return "mix-blend-mode";
        case opacity: return "opacity";
        case order: return "order";
        case paddingBottom: return "padding-bottom";
        case paddingLeft: return "padding-left";
        case paddingRight: return "padding-right";
        case paddingTop: return "padding-top";
        case right: return "right";
        case rowGap: return "row-gap";
        case stretch: return "stretch";
        case tabSize: return "tab-size";
        case textAlign: return "text-align";
        case textColor: return "color";
        case textDecorColor: return "text-decoration-color";
        case textDecorLine: return "text-decoration-line";
        case textDecorStyle: return "text-decoration-style";
        case textHotkey: return "text-hotkey";
        case textIndent: return "text-indent";
        case textOverflow: return "text-overflow";
        case textTransform: return "text-transform";
        case top: return "top";
        case transform: return "transform";
        case transitionDelay: return "transition-delay";
        case transitionDuration: return "transition-duration";
        case transitionProperty: return "transition-property";
        case transitionTimingFunction: return "transition-timing-function";
        case whiteSpace: return "white-space";
        case width: return "width";
        case wordSpacing: return "word-spacing";
        case zIndex: return "z-index";
    }
    // dfmt on
}

/// Returns true whether the property can be animated
bool isAnimatable(StyleProperty ptype)
{
    // dfmt off
    switch (ptype) with (StyleProperty)
    {
        case width: .. case marginLeft:
        case left: .. case bottom:
        case rowGap:
        case columnGap:
        case bgColor:
        case bgPosition:
        case bgSize:
        case borderTopColor: .. case borderLeftColor:
        case focusRectColor:
        case letterSpacing:
        case lineHeight:
        case textColor:
        case textDecorColor:
        case wordSpacing:
        case opacity:
            return true;
        default:
            return false;
    }
    // dfmt on
}

/// Returns true whether the property value implicitly inherits from parent widget
bool isInherited(StyleProperty ptype)
{
    // dfmt off
    switch (ptype) with (StyleProperty)
    {
        case fontSize:
        case fontFace: .. case fontWeight:
        case letterSpacing:
        case lineHeight:
        case tabSize:
        case textAlign:
        case textColor:
        case textIndent:
        case textTransform:
        case whiteSpace:
        case wordSpacing:
        case cursor:
            return true;
        default:
            return false;
    }
    // dfmt on
}
