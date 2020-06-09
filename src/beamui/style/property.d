/**

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.property;

import beamui.core.animations : TimingFunction;
import beamui.core.editable : TabSize;
import beamui.core.units : Length;
import beamui.graphics.colors : Color;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables : BorderStyle, BoxShadowDrawable, BoxType, Drawable, RepeatStyle;
import beamui.layout.alignment : Align, AlignItem, Distribution, Stretch;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.types;
import beamui.text.fonts : FontFamily, FontStyle;
import beamui.text.style;
import beamui.widgets.widget : CursorType;

/// Enumeration of all supported style properties. NOTE: DON'T use `case .. case` slices on them,
/// because order may be changed in the future.
enum StyleProperty
{
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
    borderTopStyle,
    borderRightStyle,
    borderBottomStyle,
    borderLeftStyle,
    borderTopLeftRadius,
    borderTopRightRadius,
    borderBottomLeftRadius,
    borderBottomRightRadius,
    boxShadow,
    // text
    fontFace,
    fontFamily,
    fontSize,
    fontStyle,
    fontWeight,
    letterSpacing,
    lineHeight,
    tabSize,
    textAlign,
    textDecorLine,
    textDecorStyle,
    textHotkey,
    textIndent,
    textOverflow,
    textTransform,
    whiteSpace,
    wordSpacing,
    // colors
    textColor,
    focusRectColor,
    // depend on text color, so must be computed after
    borderTopColor,
    borderRightColor,
    borderBottomColor,
    borderLeftColor,
    textDecorColor,
    // effects
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
    // layout
    string display;
    // box model
    Length width;
    Length height;
    Length minWidth;
    Length maxWidth;
    Length minHeight;
    Length maxHeight;
    Length paddingTop;
    Length paddingRight;
    Length paddingBottom;
    Length paddingLeft;
    Length borderTopWidth;
    Length borderRightWidth;
    Length borderBottomWidth;
    Length borderLeftWidth;
    Length marginTop;
    Length marginRight;
    Length marginBottom;
    Length marginLeft;
    // placement
    Length left;
    Length top;
    Length right;
    Length bottom;
    Align alignment;
    Stretch stretch;
    Distribution justifyContent;
    AlignItem justifyItems;
    AlignItem justifySelf;
    Distribution alignContent;
    AlignItem alignItems;
    AlignItem alignSelf;
    Length rowGap;
    Length columnGap;
    int order;
    int zIndex;
    // flexbox-specific
    FlexDirection flexDirection;
    FlexWrap flexWrap;
    float flexGrow;
    float flexShrink;
    Length flexBasis;
    // grid-specific
    // TrackSize[] gridTemplateRows;
    // TrackSize[] gridTemplateColumns;
    GridNamedAreas gridTemplateAreas;
    GridFlow gridAutoFlow;
    TrackSize gridAutoRows;
    TrackSize gridAutoColumns;
    GridLineName gridRowStart;
    GridLineName gridRowEnd;
    GridLineName gridColumnStart;
    GridLineName gridColumnEnd;
    // background
    Color bgColor;
    Drawable bgImage;
    BgPositionRaw bgPosition;
    BgSizeRaw bgSize;
    RepeatStyle bgRepeat;
    BoxType bgOrigin;
    BoxType bgClip;
    BorderStyle borderTopStyle;
    BorderStyle borderRightStyle;
    BorderStyle borderBottomStyle;
    BorderStyle borderLeftStyle;
    Length borderTopLeftRadius;
    Length borderTopRightRadius;
    Length borderBottomLeftRadius;
    Length borderBottomRightRadius;
    BoxShadowDrawable boxShadow;
    // text
    string fontFace;
    FontFamily fontFamily;
    Length fontSize;
    FontStyle fontStyle;
    ushort fontWeight;
    Length letterSpacing;
    Length lineHeight;
    TabSize tabSize;
    TextAlign textAlign;
    TextDecorLine textDecorLine;
    TextDecorStyle textDecorStyle;
    TextHotkey textHotkey;
    Length textIndent;
    TextOverflow textOverflow;
    TextTransform textTransform;
    WhiteSpace whiteSpace;
    Length wordSpacing;
    // colors
    Color textColor;
    Color focusRectColor;
    // depend on text color
    Color borderTopColor;
    Color borderRightColor;
    Color borderBottomColor;
    Color borderLeftColor;
    Color textDecorColor;
    // effects
    float opacity;
    BlendMode mixBlendMode;
    // transitions and animations
    string transitionProperty;
    TimingFunction transitionTimingFunction;
    uint transitionDuration;
    uint transitionDelay;
    // misc
    CursorType cursor;
}

package union BuiltinPropertyValue
{
    Align _Align;
    AlignItem _AlignItem;
    BgPositionRaw _BgPositionRaw;
    BgSizeRaw _BgSizeRaw;
    BlendMode _BlendMode;
    BorderStyle _BorderStyle;
    BoxShadowDrawable _BoxShadowDrawable;
    BoxType _BoxType;
    Color _Color;
    CursorType _CursorType;
    Distribution _Distribution;
    Drawable _Drawable;
    FlexDirection _FlexDirection;
    FlexWrap _FlexWrap;
    float _float;
    FontFamily _FontFamily;
    FontStyle _FontStyle;
    GridFlow _GridFlow;
    GridLineName _GridLineName;
    GridNamedAreas _GridNamedAreas;
    int _int;
    Length _Length;
    RepeatStyle _RepeatStyle;
    Stretch _Stretch;
    string _string;
    TabSize _TabSize;
    TextAlign _TextAlign;
    TextDecorLine _TextDecorLine;
    TextDecorStyle _TextDecorStyle;
    TextHotkey _TextHotkey;
    TextOverflow _TextOverflow;
    TextTransform _TextTransform;
    TimingFunction _TimingFunction;
    TrackSize _TrackSize;
    uint _uint;
    ushort _ushort;
    WhiteSpace _WhiteSpace;
}

package struct StylePropertyList
{
    enum Pointer : ubyte { none, inherit, initial, some }

    BuiltinPropertyValue[] values;
    Pointer[StyleProperty.max + 1] pointers;

    void set(T)(StyleProperty ptype, T v)
    {
        import std.traits : Unqual;

        BuiltinPropertyValue value;
        mixin("value._" ~ (Unqual!T).stringof) = v;

        if (!pointers[ptype])
        {
            values ~= value;
            pointers[ptype] = cast(Pointer)values.length;
        }
        else
        {
            values[pointers[ptype] - Pointer.some] = value;
        }
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

/// Checks bounds, like disallowed negative values
package bool sanitizeProperty(StyleProperty ptype, T)(ref const T value)
{
    with (StyleProperty)
    {
        static if (ptype == fontSize)
            return value.toLayout.applyPercent(100) >= 1;
        else static if (ptype == bgSize)
            return value.x.toLayout.applyPercent(100) >= 0 && value.y.toLayout.applyPercent(100) >= 0;
        else static if (
            ptype == width ||
            ptype == height ||
            ptype == minWidth ||
            ptype == maxWidth ||
            ptype == minHeight ||
            ptype == maxHeight ||
            ptype == flexBasis ||
            ptype == lineHeight
        )
            return value.toLayout.applyPercent(100) >= 0;
        else static if (
            ptype == paddingTop ||
            ptype == paddingRight ||
            ptype == paddingBottom ||
            ptype == paddingLeft ||
            ptype == borderTopWidth ||
            ptype == borderRightWidth ||
            ptype == borderBottomWidth ||
            ptype == borderLeftWidth ||
            ptype == borderTopLeftRadius ||
            ptype == borderTopRightRadius ||
            ptype == borderBottomLeftRadius ||
            ptype == borderBottomRightRadius ||
            ptype == rowGap ||
            ptype == columnGap
        )
            return value !is Length.none && value.toLayout.applyPercent(100) >= 0;
        else static if (
            ptype == flexGrow ||
            ptype == flexShrink
        )
            return value >= 0;
        else static if (
            ptype == justifyItems ||
            ptype == alignItems
        )
            return value != AlignItem.unspecified;
        else
            return true;
    }
}

package SpecialCSSType getSpecialCSSType(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case zIndex:     return SpecialCSSType.zIndex;
        case bgImage:    return SpecialCSSType.image;
        case fontWeight: return SpecialCSSType.fontWeight;
        case opacity:    return SpecialCSSType.opacity;
        case transitionProperty: return SpecialCSSType.transitionProperty;
        case transitionDuration: return SpecialCSSType.time;
        case transitionDelay:    return SpecialCSSType.time;
        default: return SpecialCSSType.none;
    }
}

/// Get property name how it looks in CSS
string getCSSName(StyleProperty ptype)
{
    final switch (ptype) with (StyleProperty)
    {
        case display: return "display";
        case width:     return "width";
        case height:    return "height";
        case minWidth:  return "min-width";
        case maxWidth:  return "max-width";
        case minHeight: return "min-height";
        case maxHeight: return "max-height";
        case paddingTop:    return "padding-top";
        case paddingRight:  return "padding-right";
        case paddingBottom: return "padding-bottom";
        case paddingLeft:   return "padding-left";
        case marginTop:    return "margin-top";
        case marginRight:  return "margin-right";
        case marginBottom: return "margin-bottom";
        case marginLeft:   return "margin-left";
        case left:   return "left";
        case top:    return "top";
        case right:  return "right";
        case bottom: return "bottom";
        case alignment: return "align";
        case stretch:   return "stretch";
        case justifyContent: return "justify-content";
        case justifyItems:   return "justify-items";
        case justifySelf:    return "justify-self";
        case alignContent:   return "align-content";
        case alignItems:     return "align-items";
        case alignSelf:      return "align-self";
        case rowGap:    return "row-gap";
        case columnGap: return "column-gap";
        case order:  return "order";
        case zIndex: return "z-index";
        case flexDirection: return "flex-direction";
        case flexWrap:      return "flex-wrap";
        case flexGrow:      return "flex-grow";
        case flexShrink:    return "flex-shrink";
        case flexBasis:     return "flex-basis";
        case gridTemplateRows:    return "grid-template-rows";
        case gridTemplateColumns: return "grid-template-columns";
        case gridTemplateAreas:   return "grid-template-areas";
        case gridAutoFlow:    return "grid-auto-flow";
        case gridAutoRows:    return "grid-auto-rows";
        case gridAutoColumns: return "grid-auto-columns";
        case gridRowStart:    return "grid-row-start";
        case gridRowEnd:      return "grid-row-end";
        case gridColumnStart: return "grid-column-start";
        case gridColumnEnd:   return "grid-column-end";
        case bgColor:    return "background-color";
        case bgImage:    return "background-image";
        case bgPosition: return "background-position";
        case bgSize:     return "background-size";
        case bgRepeat:   return "background-repeat";
        case bgOrigin:   return "background-origin";
        case bgClip:     return "background-clip";
        case borderTopWidth:    return "border-top-width";
        case borderRightWidth:  return "border-right-width";
        case borderBottomWidth: return "border-bottom-width";
        case borderLeftWidth:   return "border-left-width";
        case borderTopColor:    return "border-top-color";
        case borderRightColor:  return "border-right-color";
        case borderBottomColor: return "border-bottom-color";
        case borderLeftColor:   return "border-left-color";
        case borderTopStyle:    return "border-top-style";
        case borderRightStyle:  return "border-right-style";
        case borderBottomStyle: return "border-bottom-style";
        case borderLeftStyle:   return "border-left-style";
        case borderTopLeftRadius: return "border-top-left-radius";
        case borderTopRightRadius: return "border-top-right-radius";
        case borderBottomLeftRadius: return "border-bottom-left-radius";
        case borderBottomRightRadius: return "border-bottom-right-radius";
        case boxShadow:  return "box-shadow";
        case fontFace:   return "font-face";
        case fontFamily: return "font-family";
        case fontSize:   return "font-size";
        case fontStyle:  return "font-style";
        case fontWeight: return "font-weight";
        case letterSpacing: return "letter-spacing";
        case lineHeight:    return "line-height";
        case tabSize:       return "tab-size";
        case textAlign:     return "text-align";
        case textDecorColor: return "text-decoration-color";
        case textDecorLine:  return "text-decoration-line";
        case textDecorStyle: return "text-decoration-style";
        case textHotkey:    return "text-hotkey";
        case textIndent:    return "text-indent";
        case textOverflow:  return "text-overflow";
        case textTransform: return "text-transform";
        case whiteSpace:    return "white-space";
        case wordSpacing:   return "word-spacing";
        case textColor:      return "color";
        case focusRectColor: return "focus-rect-color";
        case opacity:        return "opacity";
        case mixBlendMode:   return "mix-blend-mode";
        case transitionProperty:       return "transition-property";
        case transitionTimingFunction: return "transition-timing-function";
        case transitionDuration:       return "transition-duration";
        case transitionDelay:          return "transition-delay";
        case cursor: return "cursor";
    }
}

/// Returns true whether the property can be animated
bool isAnimatable(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case width: .. case marginLeft:
        case left: .. case bottom:
        case rowGap:
        case columnGap:
        case bgColor:
        case bgPosition:
        case bgSize:
        case letterSpacing:
        case lineHeight:
        case wordSpacing:
        case textColor:
        case focusRectColor:
        case borderTopColor: .. case borderLeftColor:
        case textDecorColor:
        case opacity:
            return true;
        default:
            return false;
    }
}

/// Returns true whether the property value implicitly inherits from parent widget
bool isInherited(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case fontFace: .. case fontWeight:
        case letterSpacing:
        case lineHeight:
        case tabSize:
        case textAlign:
        case textIndent:
        case textTransform:
        case whiteSpace:
        case wordSpacing:
        case textColor:
        case cursor:
            return true;
        default:
            return false;
    }
}
