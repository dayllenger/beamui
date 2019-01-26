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
import beamui.graphics.text : TextAlign;
import beamui.style.style;
import beamui.style.types;
import beamui.widgets.widget : Widget;

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
    textFlags,
    textAlign,
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

struct ComputedStyle
{
    @property // written mostly at single line for compactness
    {
        /// Widget natural (preferred) width (SIZE_UNSPECIFIED if not set)
        int width() const { return _width.toDevice; }
        /// ditto
        void width(Length value) { setProperty!"width" = value; }
        /// ditto
        void width(int value) { setProperty!"width" = Length(value); }
        /// Widget natural (preferred) height (SIZE_UNSPECIFIED if not set)
        int height() const { return _height.toDevice; }
        /// ditto
        void height(Length value) { setProperty!"height" = value; }
        /// ditto
        void height(int value) { setProperty!"height" = Length(value); }
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
        void minWidth(int value) { setProperty!"minWidth" = Length(value); } // TODO: clamp
        /// Max width style constraint (SIZE_UNSPECIFIED or Length.none if no constraint)
        int maxWidth() const { return _maxWidth.toDevice; }
        /// ditto
        void maxWidth(Length value) { setProperty!"maxWidth" = value; }
        /// ditto
        void maxWidth(int value) { setProperty!"maxWidth" = Length(value); }
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
        void minHeight(int value) { setProperty!"minHeight" = Length(value); }
        /// Max height style constraint (SIZE_UNSPECIFIED or Length.none if no constraint)
        int maxHeight() const { return _maxHeight.toDevice; }
        /// ditto
        void maxHeight(Length value) { setProperty!"maxHeight" = value; }
        /// ditto
        void maxHeight(int value) { setProperty!"maxHeight" = Length(value); }

        /// Padding (between background bounds and content of widget)
        Insets padding() const
        {
            return Insets(_paddingTop.toDevice, _paddingRight.toDevice,
                          _paddingBottom.toDevice, _paddingLeft.toDevice);
        }
        /// ditto
        void padding(Insets value)
        {
            setProperty!"paddingTop" = Length(value.top);
            setProperty!"paddingRight" = Length(value.right);
            setProperty!"paddingBottom" = Length(value.bottom);
            setProperty!"paddingLeft" = Length(value.left);
        }
        /// ditto
        void padding(int v)
        {
            setProperty!"paddingTop" = Length(v);
            setProperty!"paddingRight" = Length(v);
            setProperty!"paddingBottom" = Length(v);
            setProperty!"paddingLeft" = Length(v);
        }
        /// Top padding value
        int paddingTop() const { return _paddingTop.toDevice; }
        /// ditto
        void paddingTop(int value) { setProperty!"paddingTop" = Length(value); }
        /// Right padding value
        int paddingRight() const { return _paddingRight.toDevice; }
        /// ditto
        void paddingRight(int value) { setProperty!"paddingRight" = Length(value); }
        /// Bottom padding value
        int paddingBottom() const { return _paddingBottom.toDevice; }
        /// ditto
        void paddingBottom(int value) { setProperty!"paddingBottom" = Length(value); }
        /// Left padding value
        int paddingLeft() const { return _paddingLeft.toDevice; }
        /// ditto
        void paddingLeft(int value) { setProperty!"paddingLeft" = Length(value); }

        Insets borderWidth() const
        {
            return Insets(_borderTopWidth.toDevice, _borderRightWidth.toDevice,
                          _borderBottomWidth.toDevice, _borderLeftWidth.toDevice);
        }
        /// ditto
        void borderWidth(Insets value)
        {
            setProperty!"borderTopWidth" = Length(value.top);
            setProperty!"borderRightWidth" = Length(value.right);
            setProperty!"borderBottomWidth" = Length(value.bottom);
            setProperty!"borderLeftWidth" = Length(value.left);
        }
        /// ditto
        void borderWidth(int v)
        {
            setProperty!"borderTopWidth" = Length(v);
            setProperty!"borderRightWidth" = Length(v);
            setProperty!"borderBottomWidth" = Length(v);
            setProperty!"borderLeftWidth" = Length(v);
        }

        int borderTopWidth() const { return _borderTopWidth.toDevice; }
        /// ditto
        void borderTopWidth(int value) { setProperty!"borderTopWidth" = Length(value); }

        int borderRightWidth() const { return _borderRightWidth.toDevice; }
        /// ditto
        void borderRightWidth(int value) { setProperty!"borderRightWidth" = Length(value); }

        int borderBottomWidth() const { return _borderBottomWidth.toDevice; }
        /// ditto
        void borderBottomWidth(int value) { setProperty!"borderBottomWidth" = Length(value); }

        int borderLeftWidth() const { return _borderLeftWidth.toDevice; }
        /// ditto
        void borderLeftWidth(int value) { setProperty!"borderLeftWidth" = Length(value); }

        /// Margins (between widget bounds and its background)
        Insets margins() const
        {
            return Insets(_marginTop.toDevice, _marginRight.toDevice,
                          _marginBottom.toDevice, _marginLeft.toDevice);
        }
        /// ditto
        void margins(Insets value)
        {
            setProperty!"marginTop" = Length(value.top);
            setProperty!"marginRight" = Length(value.right);
            setProperty!"marginBottom" = Length(value.bottom);
            setProperty!"marginLeft" = Length(value.left);
        }
        /// ditto
        void margins(int v)
        {
            setProperty!"marginTop" = Length(v);
            setProperty!"marginRight" = Length(v);
            setProperty!"marginBottom" = Length(v);
            setProperty!"marginLeft" = Length(v);
        }
        /// Top margin value
        int marginTop() const { return _marginTop.toDevice; }
        /// ditto
        void marginTop(int value) { setProperty!"marginTop" = Length(value); }
        /// Right margin value
        int marginRight() const { return _marginRight.toDevice; }
        /// ditto
        void marginRight(int value) { setProperty!"marginRight" = Length(value); }
        /// Bottom margin value
        int marginBottom() const { return _marginBottom.toDevice; }
        /// ditto
        void marginBottom(int value) { setProperty!"marginBottom" = Length(value); }
        /// Left margin value
        int marginLeft() const { return _marginLeft.toDevice; }
        /// ditto
        void marginLeft(int value) { setProperty!"marginLeft" = Length(value); }

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
        /// Font size in pixels
        int fontSize() const
        {
            // if (!parent && (_fontSize.is_em || _fontSize.is_percent))
            //     return 12;
            int res = _fontSize.toDevice;
            // if (_fontSize.is_em)
            //     return parent.fontSize * res / 100;
            // if (_fontSize.is_percent)
            //     return parent.fontSize * res / 10000;
            return res;
        }
        /// ditto
        void fontSize(Length value)
        {
            if (value == Length.none)
                value = Length.px(12);
            setProperty!"fontSize" = value;
        }
        /// ditto
        void fontSize(int size) { fontSize = Length(size); }
        /// Font weight for widget
        ushort fontWeight() const { return _fontWeight; }
        /// ditto
        void fontWeight(ushort value) { setProperty!"fontWeight" = cast(ushort)clamp(value, 100, 900); }

        /// Text flags (bit set of TextFlag enum values)
        TextFlag textFlags() const { return _textFlags; }
        /// ditto
        void textFlags(TextFlag value) { setProperty!"textFlags" = value; }
        /// Text alignment - start, center, end, or justify
        TextAlign textAlign() const { return _textAlign; }
        /// ditto
        void textAlign(TextAlign a) { setProperty!"textAlign" = a; }

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

    private
    {
        /// This is a bitmap that indicates which properties are overriden by the user
        bool[StyleProperty] ownProperties;

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
        TextFlag _textFlags = TextFlag.unspecified;
        TextAlign _textAlign = TextAlign.start;
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
        if (ownProperties !is null)
        {
            if (isOwned(StyleProperty.boxShadow))
                eliminate(_boxShadow);
            if (isOwned(StyleProperty.backgroundImage))
                eliminate(_backgroundImage);
            ownProperties.clear();
        }
    }

    /// Resolve style cascading and inheritance, update all properties
    void recompute(Style[] chain)
    {
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
            st.explode(ShorthandTransition("transition", "transition-property", "transition-duration",
                    "transition-timing-function", "transition-delay"));
        }

        static ComputedStyle defaults;

        static string setup(string name, string type, string specialCSSType = "SpecialCSSType.none")
        {
            return q{
            {
                enum ptype = StyleProperty.%s;
                // do nothing if property is overriden
                if (!isOwned(ptype))
                {
                    // find nearest written property in style chain
                    bool set;
                    foreach_reverse (st; chain)
                    {
                        enum string cssname = getCSSName(ptype);
                        if (auto p = st.peek!(%s, %s)(cssname))
                        {
                            setProperty!"%s"(*p, false);
                            set = true;
                            break;
                        }
                    }
                    // now it is "cascaded value" in CSS slang
                    if (!set)
                    {
                        // if nothing there - return value to defaults
                        // there is segfault with struct initializers, so it's simpler to go with static var
                        setProperty!"%s"(defaults._%s, false);
                    }
                    // now it is "specified value"
                }
            }
            }.format(name, type, specialCSSType, name, name, name);
        }

        mixin(setup("width", "Length"));
        mixin(setup("height", "Length"));
        mixin(setup("minWidth", "Length"));
        mixin(setup("maxWidth", "Length"));
        mixin(setup("minHeight", "Length"));
        mixin(setup("maxHeight", "Length"));
        mixin(setup("paddingTop", "Length"));
        mixin(setup("paddingRight", "Length"));
        mixin(setup("paddingBottom", "Length"));
        mixin(setup("paddingLeft", "Length"));
        mixin(setup("borderTopWidth", "Length"));
        mixin(setup("borderRightWidth", "Length"));
        mixin(setup("borderBottomWidth", "Length"));
        mixin(setup("borderLeftWidth", "Length"));
        mixin(setup("marginTop", "Length"));
        mixin(setup("marginRight", "Length"));
        mixin(setup("marginBottom", "Length"));
        mixin(setup("marginLeft", "Length"));
        mixin(setup("alignment", "Align"));
        mixin(setup("spacing", "int"));
        mixin(setup("rowSpacing", "int"));
        mixin(setup("columnSpacing", "int"));

        mixin(setup("borderColor", "Color"));
        mixin(setup("backgroundColor", "Color"));
        mixin(setup("backgroundImage", "Drawable", "SpecialCSSType.image"));
        mixin(setup("boxShadow", "BoxShadowDrawable"));

        mixin(setup("fontFace", "string"));
        mixin(setup("fontFamily", "FontFamily"));
        mixin(setup("fontSize", "Length"));
        mixin(setup("fontStyle", "FontStyle"));
        mixin(setup("fontWeight", "ushort", "SpecialCSSType.fontWeight"));
        mixin(setup("textFlags", "TextFlag"));
        mixin(setup("textAlign", "TextAlign"));

        mixin(setup("alpha", "ubyte", "SpecialCSSType.opacity"));
        mixin(setup("textColor", "Color"));
        mixin(setup("focusRectColor", "Color"));

        mixin(setup("transitionProperty", "string", "SpecialCSSType.transitionProperty"));
        mixin(setup("transitionTimingFunction", "TimingFunction"));
        mixin(setup("transitionDuration", "uint", "SpecialCSSType.time"));
        mixin(setup("transitionDelay", "uint", "SpecialCSSType.time"));
    }

    private void ownProperty(StyleProperty ptype)
    {
        ownProperties[ptype] = true;
    }

    private bool isOwned(StyleProperty ptype)
    {
        return (ptype in ownProperties) !is null;
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
        enum ptype = __traits(getMember, StyleProperty, name);

        if (byUser)
            ownProperty(ptype);

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
        enum ptype = __traits(getMember, StyleProperty, name);

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
        case textFlags:  return "text-flags";
        case textAlign:  return "text-align";
        case alpha:      return "opacity";
        case textColor:  return "color";
        case focusRectColor: return "focus-rect-color";
        case transitionProperty:       return "transition-property";
        case transitionTimingFunction: return "transition-timing-function";
        case transitionDuration:       return "transition-duration";
        case transitionDelay:          return "transition-delay";
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
        case alpha:
        case textColor:
        case focusRectColor:
            return true;
        default:
            return false;
    }
}
