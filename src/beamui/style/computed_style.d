/**

Copyright: dayllenger 2018-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.computed_style;

import beamui.core.animations;
import beamui.core.functions : clamp, eliminate, format;
import beamui.core.geometry : Insets;
import beamui.core.units : Length;
import beamui.graphics.colors : Color, decodeHexColor, decodeTextColor;
import beamui.graphics.drawables : Drawable, BoxShadowDrawable;
import beamui.graphics.fonts;
import beamui.graphics.text;
import beamui.style.style;
import beamui.style.types;
import beamui.widgets.widget : Widget;
debug (styles) import beamui.core.logger;

enum StyleProperty
{
    // layout
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
    alignment,
    spacing,
    rowSpacing,
    columnSpacing,
    // background
    borderColor,
    backgroundColor,
    backgroundImage,
    boxShadow,
    // text
    fontFace,
    fontFamily,
    fontSize,
    fontStyle,
    fontWeight,
    textAlign,
    textDecorationColor,
    textDecorationLine,
    textDecorationStyle,
    textHotkey,
    textOverflow,
    textTransform,
    // colors
    alpha,
    textColor,
    focusRectColor,
    // transitions and animations
    transitionProperty,
    transitionTimingFunction,
    transitionDuration,
    transitionDelay,
}

/// Provides default style values
private static ComputedStyle defaults;

struct ComputedStyle
{
    @property // written mostly at single line for compactness
    {
        /// Widget natural (preferred) width (SIZE_UNSPECIFIED if not set)
        int width() const { return _width.toDevice; }
        /// ditto
        void width(Length value) { setProperty!"width" = value; }
        /// ditto
        void width(int value) { setProperty!"width" = Length.px(value); }
        /// Widget natural (preferred) height (SIZE_UNSPECIFIED if not set)
        int height() const { return _height.toDevice; }
        /// ditto
        void height(Length value) { setProperty!"height" = value; }
        /// ditto
        void height(int value) { setProperty!"height" = Length.px(value); }
        /// Min width style constraint (0, Length.zero or Length.none for no constraint)
        int minWidth() const { return _minWidth.toDevice; }
        /// ditto
        void minWidth(Length value)
        {
            if (value == Length.none)
                value = Length.zero;
            setProperty!"minWidth" = value;
        }
        /// ditto
        void minWidth(int value) { setProperty!"minWidth" = Length.px(value); } // TODO: clamp
        /// Max width style constraint (SIZE_UNSPECIFIED or Length.none if no constraint)
        int maxWidth() const { return _maxWidth.toDevice; }
        /// ditto
        void maxWidth(Length value) { setProperty!"maxWidth" = value; }
        /// ditto
        void maxWidth(int value) { setProperty!"maxWidth" = Length.px(value); }
        /// Min height style constraint (0, Length.zero or Length.none for no constraint)
        int minHeight() const { return _minHeight.toDevice; }
        /// ditto
        void minHeight(Length value)
        {
            if (value == Length.none)
                value = Length.zero;
            setProperty!"minHeight" = value;
        }
        /// ditto
        void minHeight(int value) { setProperty!"minHeight" = Length.px(value); }
        /// Max height style constraint (SIZE_UNSPECIFIED or Length.none if no constraint)
        int maxHeight() const { return _maxHeight.toDevice; }
        /// ditto
        void maxHeight(Length value) { setProperty!"maxHeight" = value; }
        /// ditto
        void maxHeight(int value) { setProperty!"maxHeight" = Length.px(value); }

        /// Padding (between background bounds and content of widget)
        Insets padding() const
        {
            return Insets(_paddingTop.toDevice, _paddingRight.toDevice,
                          _paddingBottom.toDevice, _paddingLeft.toDevice);
        }
        /// ditto
        void padding(Insets value)
        {
            setProperty!"paddingTop" = Length.px(value.top);
            setProperty!"paddingRight" = Length.px(value.right);
            setProperty!"paddingBottom" = Length.px(value.bottom);
            setProperty!"paddingLeft" = Length.px(value.left);
        }
        /// ditto
        void padding(int v)
        {
            setProperty!"paddingTop" = Length.px(v);
            setProperty!"paddingRight" = Length.px(v);
            setProperty!"paddingBottom" = Length.px(v);
            setProperty!"paddingLeft" = Length.px(v);
        }
        /// Top padding value
        int paddingTop() const { return _paddingTop.toDevice; }
        /// ditto
        void paddingTop(int value) { setProperty!"paddingTop" = Length.px(value); }
        /// Right padding value
        int paddingRight() const { return _paddingRight.toDevice; }
        /// ditto
        void paddingRight(int value) { setProperty!"paddingRight" = Length.px(value); }
        /// Bottom padding value
        int paddingBottom() const { return _paddingBottom.toDevice; }
        /// ditto
        void paddingBottom(int value) { setProperty!"paddingBottom" = Length.px(value); }
        /// Left padding value
        int paddingLeft() const { return _paddingLeft.toDevice; }
        /// ditto
        void paddingLeft(int value) { setProperty!"paddingLeft" = Length.px(value); }

        Insets borderWidth() const
        {
            return Insets(_borderTopWidth.toDevice, _borderRightWidth.toDevice,
                          _borderBottomWidth.toDevice, _borderLeftWidth.toDevice);
        }
        /// ditto
        void borderWidth(Insets value)
        {
            setProperty!"borderTopWidth" = Length.px(value.top);
            setProperty!"borderRightWidth" = Length.px(value.right);
            setProperty!"borderBottomWidth" = Length.px(value.bottom);
            setProperty!"borderLeftWidth" = Length.px(value.left);
        }
        /// ditto
        void borderWidth(int v)
        {
            setProperty!"borderTopWidth" = Length.px(v);
            setProperty!"borderRightWidth" = Length.px(v);
            setProperty!"borderBottomWidth" = Length.px(v);
            setProperty!"borderLeftWidth" = Length.px(v);
        }

        int borderTopWidth() const { return _borderTopWidth.toDevice; }
        /// ditto
        void borderTopWidth(int value) { setProperty!"borderTopWidth" = Length.px(value); }

        int borderRightWidth() const { return _borderRightWidth.toDevice; }
        /// ditto
        void borderRightWidth(int value) { setProperty!"borderRightWidth" = Length.px(value); }

        int borderBottomWidth() const { return _borderBottomWidth.toDevice; }
        /// ditto
        void borderBottomWidth(int value) { setProperty!"borderBottomWidth" = Length.px(value); }

        int borderLeftWidth() const { return _borderLeftWidth.toDevice; }
        /// ditto
        void borderLeftWidth(int value) { setProperty!"borderLeftWidth" = Length.px(value); }

        /// Margins (between widget bounds and its background)
        Insets margins() const
        {
            return Insets(_marginTop.toDevice, _marginRight.toDevice,
                          _marginBottom.toDevice, _marginLeft.toDevice);
        }
        /// ditto
        void margins(Insets value)
        {
            setProperty!"marginTop" = Length.px(value.top);
            setProperty!"marginRight" = Length.px(value.right);
            setProperty!"marginBottom" = Length.px(value.bottom);
            setProperty!"marginLeft" = Length.px(value.left);
        }
        /// ditto
        void margins(int v)
        {
            setProperty!"marginTop" = Length.px(v);
            setProperty!"marginRight" = Length.px(v);
            setProperty!"marginBottom" = Length.px(v);
            setProperty!"marginLeft" = Length.px(v);
        }
        /// Top margin value
        int marginTop() const { return _marginTop.toDevice; }
        /// ditto
        void marginTop(int value) { setProperty!"marginTop" = Length.px(value); }
        /// Right margin value
        int marginRight() const { return _marginRight.toDevice; }
        /// ditto
        void marginRight(int value) { setProperty!"marginRight" = Length.px(value); }
        /// Bottom margin value
        int marginBottom() const { return _marginBottom.toDevice; }
        /// ditto
        void marginBottom(int value) { setProperty!"marginBottom" = Length.px(value); }
        /// Left margin value
        int marginLeft() const { return _marginLeft.toDevice; }
        /// ditto
        void marginLeft(int value) { setProperty!"marginLeft" = Length.px(value); }

        /// Alignment (combined vertical and horizontal)
        Align alignment() const { return _alignment; }
        /// ditto
        void alignment(Align value) { setProperty!"alignment" = value; }
        /// Returns horizontal alignment
        Align halign() const { return _alignment & Align.hcenter; }
        /// Returns vertical alignment
        Align valign() const { return _alignment & Align.vcenter; }

        /// Space between items in layouts
        int spacing() const { return _spacing; }
        /// ditto
        void spacing(int value) { setProperty!"spacing" = value; }
        /// Space between rows (vertical)
        int rowSpacing() const { return _rowSpacing; }
        /// ditto
        void rowSpacing(int value) { setProperty!"rowSpacing" = value; }
        /// Space between columns (horizontal)
        int columnSpacing() const { return _columnSpacing; }
        /// ditto
        void columnSpacing(int value) { setProperty!"columnSpacing" = value; }

        /// Color of widget border
        Color borderColor() const { return _borderColor; }
        /// ditto
        void borderColor(Color value) { setProperty!"borderColor" = value; }
        /// Background color of the widget
        Color backgroundColor() const { return _backgroundColor; }
        /// ditto
        void backgroundColor(Color value) { setProperty!"backgroundColor" = value; }
        /// Set background color as ARGB 32 bit value
        void backgroundColor(uint value) { setProperty!"backgroundColor" = Color(value); }
        /// Set background color from string like "#5599CC" or "white"
        void backgroundColor(string colorString)
        {
            Color value = decodeHexColor(colorString, Color.none);
            if (value == Color.none)
                value = decodeTextColor(colorString, Color.transparent);
            setProperty!"backgroundColor" = value;
        }
        /// Background image drawable
        inout(Drawable) backgroundImage() inout { return _backgroundImage; }
        /// ditto
        void backgroundImage(Drawable image) { setProperty!"backgroundImage" = image; }

        inout(BoxShadowDrawable) boxShadow() inout { return _boxShadow; }
        /// ditto
        void boxShadow(BoxShadowDrawable shadow) { setProperty!"boxShadow" = shadow; }

        /// Font face for widget
        string fontFace() const { return _fontFace; }
        /// ditto
        void fontFace(string value) { setProperty!"fontFace" = value; }
        /// Font family for widget
        FontFamily fontFamily() const { return _fontFamily; }
        /// ditto
        void fontFamily(FontFamily value) { setProperty!"fontFamily" = value; }
        /// Font style (italic/normal) for widget
        bool fontItalic() const { return _fontStyle == FontStyle.italic; }
        /// ditto
        void fontItalic(bool italic) { setProperty!"fontStyle" = italic ? FontStyle.italic : FontStyle.normal; }
        /// Font size
        Length fontSize() const { return _fontSize; }
        /// ditto
        void fontSize(Length value)
        {
            if (value == Length.none)
                value = Length.px(12);
            setProperty!"fontSize" = value;
        }
        /// ditto
        void fontSize(int size) { fontSize = Length.px(size); }
        /// Font weight for widget
        ushort fontWeight() const { return _fontWeight; }
        /// ditto
        void fontWeight(ushort value) { setProperty!"fontWeight" = cast(ushort)clamp(value, 100, 900); }

        /// Text alignment - start, center, end, or justify
        TextAlign textAlign() const { return _textAlign; }
        /// ditto
        void textAlign(TextAlign a) { setProperty!"textAlign" = a; }
        /// Text decoration - underline, overline, and so on
        TextDecoration textDecoration() const
        {
            return TextDecoration(_textDecorationColor, _textDecorationLine, _textDecorationStyle);
        }
        /// ditto
        void textDecoration(TextDecoration compound)
        {
            setProperty!"textDecorationColor" = compound.color;
            setProperty!"textDecorationLine" = compound.line;
            setProperty!"textDecorationStyle" = compound.style;
        }
        /// ditto
        void textDecoration(Color color) { setProperty!"textDecorationColor" = color; }
        /// ditto
        void textDecoration(TextDecoration.Line line) { setProperty!"textDecorationLine" = line; }
        /// ditto
        void textDecoration(TextDecoration.Style style) { setProperty!"textDecorationStyle" = style; }
        /// Color of text decoration lines
        Color textDecorationColor() const { return _textDecorationColor; }
        /// Place where text decoration line appears
        TextDecoration.Line textDecorationLine() const { return _textDecorationLine; }
        /// Style of text decoration line - solid, dashed, wavy, and so on
        TextDecoration.Style textDecorationStyle() const { return _textDecorationStyle; }
        /// Controls how text with `&` hotkey marks should be displayed
        TextHotkey textHotkey() const { return _textHotkey; }
        /// ditto
        void textHotkey(TextHotkey value) { setProperty!"textHotkey" = value; }
        /// Specifies how text that doesn't fit and is not displayed should behave
        TextOverflow textOverflow() const { return _textOverflow; }
        /// ditto
        void textOverflow(TextOverflow value) { setProperty!"textOverflow" = value; }
        /// Controls capitalization of text
        TextTransform textTransform() const { return _textTransform; }
        /// ditto
        void textTransform(TextTransform value) { setProperty!"textTransform" = value; }

        /// Widget drawing opacity (0 = opaque .. 255 = transparent)
        ubyte alpha() const { return _alpha; }
        /// ditto
        void alpha(ubyte value) { setProperty!"alpha" = value; }

        /// Text color
        Color textColor() const { return _textColor; }
        /// ditto
        void textColor(Color value) { setProperty!"textColor" = value; }
        /// Set text color as ARGB 32 bit value
        void textColor(uint value) { setProperty!"textColor" = Color(value); }
        /// Set text color from string like "#5599CC" or "white"
        void textColor(string colorString)
        {
            Color value = decodeHexColor(colorString, Color.none);
            if (value == Color.none)
                value = decodeTextColor(colorString, Color(0x0));
            setProperty!"textColor" = value;
        }

        /// Get color to draw focus rectangle, Color.transparent if no focus rect
        Color focusRectColor() const { return _focusRectColor; }
    }

    package(beamui) Widget widget;
    package(beamui) bool isolated;

    private
    {
        import core.bitop : bt, bts, btr;

        enum bits = StyleProperty.max + 1;
        /// Explicitly set to inherit value from parent widget
        size_t[bits / (8 * size_t.sizeof) + 1] inheritBitArray;
        /// Overriden by user
        size_t[bits / (8 * size_t.sizeof) + 1] overridenBitArray;

        // layout
        Length _width = Length.none;
        Length _height = Length.none;
        Length _minWidth = Length.zero;
        Length _maxWidth = Length.none;
        Length _minHeight = Length.zero;
        Length _maxHeight = Length.none;
        Length _paddingTop = Length.zero;
        Length _paddingRight = Length.zero;
        Length _paddingBottom = Length.zero;
        Length _paddingLeft = Length.zero;
        Length _borderTopWidth = Length.zero;
        Length _borderRightWidth = Length.zero;
        Length _borderBottomWidth = Length.zero;
        Length _borderLeftWidth = Length.zero;
        Length _marginTop = Length.zero;
        Length _marginRight = Length.zero;
        Length _marginBottom = Length.zero;
        Length _marginLeft = Length.zero;
        Align _alignment;
        int _spacing = 6;
        int _rowSpacing = 6;
        int _columnSpacing = 6;
        // background
        Color _borderColor = Color.transparent;
        Color _backgroundColor = Color.transparent;
        Drawable _backgroundImage;
        BoxShadowDrawable _boxShadow;
        // text
        string _fontFace = "Arial";
        FontFamily _fontFamily = FontFamily.sans_serif;
        Length _fontSize = Length.px(12);
        FontStyle _fontStyle = FontStyle.normal;
        ushort _fontWeight = 400;
        TextAlign _textAlign = TextAlign.start;
        Color _textDecorationColor = Color(0x000000);
        TextDecoration.Line _textDecorationLine = TextDecoration.Line.none;
        TextDecoration.Style _textDecorationStyle = TextDecoration.Style.solid;
        TextHotkey _textHotkey = TextHotkey.ignore;
        TextOverflow _textOverflow = TextOverflow.clip;
        TextTransform _textTransform = TextTransform.none;
        // colors
        ubyte _alpha = 0;
        Color _textColor = Color(0x000000);
        Color _focusRectColor = Color.transparent;
        // transitions and animations
        string _transitionProperty;
        TimingFunction _transitionTimingFunction;
        uint _transitionDuration;
        uint _transitionDelay;
    }

    ~this()
    {
        if (isOverriden(StyleProperty.boxShadow))
            eliminate(_boxShadow);
        if (isOverriden(StyleProperty.backgroundImage))
            eliminate(_backgroundImage);
    }

    /// Set the property to inherit its value from parent widget
    void inherit(StyleProperty property)
    {
        bts(inheritBitArray.ptr, property);
        bts(overridenBitArray.ptr, property);
    }

    /// Set the property to its initial value
    void initialize(StyleProperty property)
    {
        final switch (property)
        {
            static foreach (name; __traits(allMembers, StyleProperty))
            {
                case mixin(`StyleProperty.` ~ name):
                    setProperty!name = mixin(`defaults._` ~ name); // set by user
                    return;
            }
        }
    }

    /// Resolve style cascading and inheritance, update all properties
    void recompute(Style[] chain)
    {
        debug (styles)
            Log.d("--- Recomputing style for ", typeid(widget), ", id: ", widget.id, " ---");

        // explode shorthands first
        foreach_reverse (st; chain)
        {
            st.explode(ShorthandInsets("margin", "margin-top", "margin-right", "margin-bottom", "margin-left"));
            st.explode(ShorthandInsets("padding", "padding-top", "padding-right", "padding-bottom", "padding-left"));
            st.explode(ShorthandInsets("border-width", "border-top-width", "border-right-width",
                    "border-bottom-width", "border-left-width"));
            st.explode(ShorthandBorder("border", "border-top-width", "border-right-width",
                    "border-bottom-width", "border-left-width", "border-color"));
            st.explode(ShorthandDrawable("background", "background-color", "background-image"));
            st.explode(ShorthandTextDecoration("text-decoration", "text-decoration-color",
                    "text-decoration-line", "text-decoration-style"));
            st.explode(ShorthandTransition("transition", "transition-property", "transition-duration",
                    "transition-timing-function", "transition-delay"));
        }
        // find that we are not tied, being the root of style scope
        Widget parent = widget.parent;
        const bool canInherit = parent && !widget.styleIsolated;
        /// iterate through all properties
        static foreach (name; __traits(allMembers, StyleProperty))
        {{
            alias T = typeof(mixin(`_` ~ name));
            enum ptype = mixin(`StyleProperty.` ~ name);
            enum specialCSSType = getSpecialCSSType(ptype);
            enum cssname = StrHash(getCSSName(ptype));
            enum bool inheritsByDefault = inherited(ptype);

            const setByUser = isOverriden(ptype);
            bool setInStyles;
            // search in style chain if not overriden
            if (!setByUser)
            {
                bool inh;
                // find nearest written property
                foreach_reverse (st; chain)
                {
                    static if (!inheritsByDefault)
                    {
                        if (st.isInherited(cssname))
                        {
                            inh = true;
                            setInStyles = true;
                            break;
                        }
                    }
                    if (st.isInitial(cssname))
                    {
                        setProperty!name(mixin(`defaults._` ~ name), false);
                        setInStyles = true;
                        break;
                    }
                    if (auto p = st.peek!(T, specialCSSType)(cssname))
                    {
                        setProperty!name(*p, false);
                        setInStyles = true;
                        break;
                    }
                }
                // set/reset 'inherit' flag
                if (inh)
                    bts(inheritBitArray.ptr, ptype);
                else
                    btr(inheritBitArray.ptr, ptype);
            }

            const noValue = !setByUser && !setInStyles;
            // resolve inherited properties
            if (inheritsByDefault && noValue || isInherited(ptype))
            {
                if (canInherit)
                    setProperty!name(mixin(`parent.style._` ~ name), false);
                else
                    setProperty!name(mixin(`defaults._` ~ name), false);
            }
            else if (noValue)
            {
                // if nothing there - return value to defaults
                setProperty!name(mixin(`defaults._` ~ name), false);
            }
        }}

        debug (styles)
            Log.d("--- End style recomputing ---");
    }

    private bool isInherited(StyleProperty ptype)
    {
        return bt(inheritBitArray.ptr, ptype) != 0;
    }

    private bool isOverriden(StyleProperty ptype)
    {
        return bt(overridenBitArray.ptr, ptype) != 0;
    }

    private void overrideProperty(StyleProperty ptype)
    {
        bts(overridenBitArray.ptr, ptype);
    }

    /// Check whether the style can make transition for a CSS property
    bool hasTransitionFor(string property) const
    {
        if (_transitionTimingFunction is null || _transitionDuration <= 0)
            return false;
        if (_transitionProperty == "all" || _transitionProperty == property)
            return true;

        if (_transitionProperty == "padding")
            return property == "padding-top" || property == "padding-right" ||
                   property == "padding-bottom" || property == "padding-left";

        if (_transitionProperty == "border-width")
            return property == "border-top-width" || property == "border-right-width" ||
                   property == "border-bottom-width" || property == "border-left-width";

        if (_transitionProperty == "border")
            return property == "border-top-width" || property == "border-right-width" ||
                   property == "border-bottom-width" || property == "border-left-width" ||
                   property == "border-color";

        if (_transitionProperty == "background")
            return property == "background-color";

        return false;
    }

    /// Set a property value, taking transitions into account
    private void setProperty(string name, T)(T newValue, bool byUser = true)
    {
        import std.meta : Alias;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`StyleProperty.` ~ name);

        if (byUser)
            overrideProperty(ptype);

        // do nothing if changed nothing
        if (field is newValue)
        {
            static if (isAnimatable(ptype))
            {
                // cancel possible animation
                widget.cancelAnimation(name);
            }
            return;
        }
        // check animation
        static if (isAnimatable(ptype))
        {
            enum string cssname = getCSSName(ptype);
            if (hasTransitionFor(cssname))
            {
                animateProperty!name(newValue);
                return;
            }
        }
        // set it directly otherwise
        field = newValue;
        // invoke side effects
        widget.handleStyleChange(ptype);
    }

    private void animateProperty(string name, T)(T ending)
    {
        import std.meta : Alias;
        import beamui.core.animations : Transition;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`StyleProperty.` ~ name);

        T starting = field;
        auto tr = new Transition(_transitionDuration, _transitionTimingFunction, _transitionDelay);
        widget.addAnimation(name, tr.duration,
            (double t) {
                field = tr.mix(starting, ending, t);
                widget.handleStyleChange(ptype);
            }
        );
    }
}

/// Get property name how it looks in CSS
string getCSSName(StyleProperty ptype)
{
    final switch (ptype) with (StyleProperty)
    {
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
        case borderTopWidth:    return "border-top-width";
        case borderRightWidth:  return "border-right-width";
        case borderBottomWidth: return "border-bottom-width";
        case borderLeftWidth:   return "border-left-width";
        case marginTop:    return "margin-top";
        case marginRight:  return "margin-right";
        case marginBottom: return "margin-bottom";
        case marginLeft:   return "margin-left";
        case alignment:  return "align";
        case spacing:    return "spacing";
        case rowSpacing: return "row-spacing";
        case columnSpacing: return "column-spacing";
        case borderColor:     return "border-color";
        case backgroundColor: return "background-color";
        case backgroundImage: return "background-image";
        case boxShadow:  return "box-shadow";
        case fontFace:   return "font-face";
        case fontFamily: return "font-family";
        case fontSize:   return "font-size";
        case fontStyle:  return "font-style";
        case fontWeight: return "font-weight";
        case textAlign:  return "text-align";
        case textDecorationColor: return "text-decoration-color";
        case textDecorationLine: return "text-decoration-line";
        case textDecorationStyle: return "text-decoration-style";
        case textHotkey: return "text-hotkey";
        case textOverflow: return "text-overflow";
        case textTransform: return "text-transform";
        case alpha:      return "opacity";
        case textColor:  return "color";
        case focusRectColor: return "focus-rect-color";
        case transitionProperty:       return "transition-property";
        case transitionTimingFunction: return "transition-timing-function";
        case transitionDuration:       return "transition-duration";
        case transitionDelay:          return "transition-delay";
    }
}

private SpecialCSSType getSpecialCSSType(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case backgroundImage:    return SpecialCSSType.image;
        case fontWeight:         return SpecialCSSType.fontWeight;
        case alpha:              return SpecialCSSType.opacity;
        case transitionProperty: return SpecialCSSType.transitionProperty;
        case transitionDuration: return SpecialCSSType.time;
        case transitionDelay:    return SpecialCSSType.time;
        default: return SpecialCSSType.none;
    }
}

/// Returns true whether the property can be animated
bool isAnimatable(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case width: .. case marginLeft:
        case spacing: .. case columnSpacing:
        case borderColor:
        case backgroundColor:
        case textDecorationColor:
        case alpha:
        case textColor:
        case focusRectColor:
            return true;
        default:
            return false;
    }
}

/// Returns true whether the property value implicitly inherits from parent widget
bool inherited(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case fontFace: .. case fontWeight:
        case textAlign:
        case textTransform:
        case textColor:
            return true;
        default:
            return false;
    }
}
