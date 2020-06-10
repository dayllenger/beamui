/**

Copyright: dayllenger 2018-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.computed_style;

public import beamui.style.property : StyleProperty;
import beamui.core.animations;
import beamui.core.editable : TabSize;
import beamui.core.functions : clamp, eliminate, format;
import beamui.core.geometry : Insets, isDefinedSize;
import beamui.core.types : Result, Ok;
import beamui.core.units : Length, LayoutLength;
import beamui.graphics.colors : Color, decodeHexColor, decodeTextColor;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables;
import beamui.layout.alignment;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.property;
import beamui.style.style;
import beamui.style.types;
import beamui.text.fonts;
import beamui.text.style;
import beamui.widgets.widget : CursorType, Element;

/// Provides default style values for most of properties
private ComputedStyle defaults;

struct ComputedStyle
{
    @property
    {
        string display() const { return _display; }

        LayoutLength width() const { return applyEM(_width); }
        LayoutLength height() const { return applyEM(_height); }

        LayoutLength minWidth() const { return applyEM(_minWidth); }
        LayoutLength minHeight() const { return applyEM(_minHeight); }

        LayoutLength maxWidth() const { return applyEM(_maxWidth); }
        LayoutLength maxHeight() const { return applyEM(_maxHeight); }

        Insets padding() const
        {
            return Insets(applyOnlyEM(_paddingTop), applyOnlyEM(_paddingRight),
                          applyOnlyEM(_paddingBottom), applyOnlyEM(_paddingLeft));
        }
        Insets borderWidth() const
        {
            return Insets(applyOnlyEM(_borderTopWidth), applyOnlyEM(_borderRightWidth),
                          applyOnlyEM(_borderBottomWidth), applyOnlyEM(_borderLeftWidth));
        }
        Insets margins() const
        {
            return Insets(applyOnlyEM(_marginTop), applyOnlyEM(_marginRight),
                          applyOnlyEM(_marginBottom), applyOnlyEM(_marginLeft));
        }

        LayoutLength left() const { return applyEM(_left); }
        LayoutLength top() const { return applyEM(_top); }
        LayoutLength right() const { return applyEM(_right); }
        LayoutLength bottom() const { return applyEM(_bottom); }

        Align alignment() const { return _alignment; }
        /// Returns horizontal alignment
        Align halign() const { return _alignment & Align.hcenter; }
        /// Returns vertical alignment
        Align valign() const { return _alignment & Align.vcenter; }

        Stretch stretch() const { return _stretch; }

        Distribution[2] placeContent() const { return [_justifyContent, _alignContent]; }
        AlignItem[2] placeItems() const { return [_justifyItems, _alignItems]; }
        AlignItem[2] placeSelf() const { return [_justifySelf, _alignSelf]; }

        LayoutLength rowGap() const { return applyEM(_rowGap); }
        LayoutLength columnGap() const { return applyEM(_columnGap); }

        int order() const { return _order; }
        int zIndex() const { return _zIndex; }

        FlexDirection flexDirection() const { return _flexDirection; }
        FlexWrap flexWrap() const { return _flexWrap; }

        float flexGrow() const { return _flexGrow; }
        float flexShrink() const { return _flexShrink; }
        LayoutLength flexBasis() const { return applyEM(_flexBasis); }

        const(TrackSize[]) gridTemplateRows() const { return _gridTemplateRows; }
        const(TrackSize[]) gridTemplateColumns() const { return _gridTemplateColumns; }
        const(GridNamedAreas) gridTemplateAreas() const { return _gridTemplateAreas; }

        GridFlow gridAutoFlow() const { return _gridAutoFlow; }
        TrackSize gridAutoRows() const { return _gridAutoRows; }
        TrackSize gridAutoColumns() const { return _gridAutoColumns; }

        /// (row-start, column-start, row-end, column-end)
        GridLineName[4] gridArea() const { return [_gridRowStart, _gridColumnStart, _gridRowEnd, _gridColumnEnd]; }

        Color backgroundColor() const { return _bgColor; }
        inout(Drawable) backgroundImage() inout { return _bgImage; }

        BgPosition backgroundPosition() const
        {
            return BgPosition(applyEM(_bgPosition.x), applyEM(_bgPosition.y));
        }
        BgSize backgroundSize() const
        {
            const t = _bgSize.type;
            if (t == BgSizeType.length)
                return BgSize(t, applyEM(_bgSize.x), applyEM(_bgSize.y));
            else
                return BgSize(t);
        }

        RepeatStyle backgroundRepeat() const { return _bgRepeat; }
        BoxType backgroundOrigin() const { return _bgOrigin; }
        BoxType backgroundClip() const { return _bgClip; }

        Color[4] borderColor() const
        {
            return [_borderTopColor, _borderRightColor,
                    _borderBottomColor, _borderLeftColor];
        }
        BorderStyle[4] borderStyle() const
        {
            return [_borderTopStyle, _borderRightStyle,
                    _borderBottomStyle, _borderLeftStyle];
        }
        LayoutLength[4] borderRadii() const
        {
            return [applyEM(_borderTopLeftRadius), applyEM(_borderTopRightRadius),
                    applyEM(_borderBottomLeftRadius), applyEM(_borderBottomRightRadius)];
        }

        inout(BoxShadowDrawable) boxShadow() inout { return _boxShadow; }

        string fontFace() const { return _fontFace; }
        FontFamily fontFamily() const { return _fontFamily; }
        bool fontItalic() const { return _fontStyle == FontStyle.italic; }
        ushort fontWeight() const { return _fontWeight; }

        /// Computed font size in device-independent pixels
        int fontSize() const
        {
            const Length fs = _fontSize;
            const Element p = element.parent;
            const int def = FontManager.defaultFontSize;
            if (!fs.is_rem && (!p || isolated) && (fs.is_em || fs.is_percent))
                return def;
            const LayoutLength ll = fs.toLayout;
            const int base = p && !fs.is_rem ? p.style.fontSize : def;
            return cast(int)ll.applyPercent(base);
        }

        TabSize tabSize() const { return _tabSize; }

        TextDecor textDecor() const
        {
            return TextDecor(_textDecorLine, _textDecorColor, _textDecorStyle);
        }
        TextAlign textAlign() const { return _textAlign; }
        Color textColor() const { return _textColor; }
        TextHotkey textHotkey() const { return _textHotkey; }
        TextOverflow textOverflow() const { return _textOverflow; }
        TextTransform textTransform() const { return _textTransform; }

        float letterSpacing() const { return applyOnlyEM(_letterSpacing); }
        float wordSpacing() const { return applyOnlyEM(_wordSpacing); }

        float lineHeight() const { return applyOnlyEM(_lineHeight); }
        LayoutLength textIndent() const { return applyEM(_textIndent); }

        bool wordWrap() const { return _whiteSpace == WhiteSpace.preWrap; }

        /// Get color to draw focus rectangle, `Color.transparent` if no focus rect
        Color focusRectColor() const { return _focusRectColor; }

        float opacity() const { return _opacity; }
        BlendMode mixBlendMode() const { return _mixBlendMode; }

        CursorType cursor() const { return _cursor; }
    }

    package(beamui) Element element;
    package(beamui) bool isolated;

    private
    {
        import core.bitop : bt, bts, btr;

        enum bits = StyleProperty.max + 1;
        /// Inherits value from the parent element
        size_t[bits / (8 * size_t.sizeof) + 1] inheritBitArray;

        // layout
        string _display;
        // box model
        Length _width = Length.none;
        Length _height = Length.none;
        Length _minWidth = Length.none;
        Length _maxWidth = Length.none;
        Length _minHeight = Length.none;
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
        // placement
        Length _left = Length.none;
        Length _top = Length.none;
        Length _right = Length.none;
        Length _bottom = Length.none;
        Align _alignment;
        Stretch _stretch = Stretch.cross;
        Distribution _justifyContent = Distribution.stretch;
        AlignItem _justifyItems = AlignItem.stretch;
        AlignItem _justifySelf = AlignItem.unspecified;
        Distribution _alignContent = Distribution.stretch;
        AlignItem _alignItems = AlignItem.stretch;
        AlignItem _alignSelf = AlignItem.unspecified;
        Length _rowGap = Length.zero;
        Length _columnGap = Length.zero;
        int _order = 0;
        int _zIndex = int.min;
        // flexbox-specific
        FlexDirection _flexDirection = FlexDirection.row;
        FlexWrap _flexWrap = FlexWrap.off;
        float _flexGrow = 0;
        float _flexShrink = 1;
        Length _flexBasis = Length.none;
        // grid-specific
        TrackSize[] _gridTemplateRows;
        TrackSize[] _gridTemplateColumns;
        GridNamedAreas _gridTemplateAreas;
        GridFlow _gridAutoFlow = GridFlow.row;
        TrackSize _gridAutoRows = TrackSize.automatic;
        TrackSize _gridAutoColumns = TrackSize.automatic;
        GridLineName _gridRowStart;
        GridLineName _gridRowEnd;
        GridLineName _gridColumnStart;
        GridLineName _gridColumnEnd;
        // background
        Color _bgColor = Color.transparent;
        Drawable _bgImage;
        BgPositionRaw _bgPosition;
        BgSizeRaw _bgSize;
        RepeatStyle _bgRepeat;
        BoxType _bgOrigin = BoxType.padding;
        BoxType _bgClip = BoxType.border;
        BorderStyle _borderTopStyle = BorderStyle.none;
        BorderStyle _borderRightStyle = BorderStyle.none;
        BorderStyle _borderBottomStyle = BorderStyle.none;
        BorderStyle _borderLeftStyle = BorderStyle.none;
        Length _borderTopLeftRadius = Length.zero;
        Length _borderTopRightRadius = Length.zero;
        Length _borderBottomLeftRadius = Length.zero;
        Length _borderBottomRightRadius = Length.zero;
        BoxShadowDrawable _boxShadow;
        // text
        string _fontFace = "Arial";
        FontFamily _fontFamily = FontFamily.sans_serif;
        Length _fontSize = Length.rem(1);
        FontStyle _fontStyle = FontStyle.normal;
        ushort _fontWeight = 400;
        Length _letterSpacing = Length.zero;
        Length _lineHeight = Length.rem(1.2);
        TabSize _tabSize;
        TextAlign _textAlign = TextAlign.start;
        TextDecorLine _textDecorLine = TextDecorLine.none;
        TextDecorStyle _textDecorStyle = TextDecorStyle.solid;
        TextHotkey _textHotkey = TextHotkey.ignore;
        Length _textIndent = Length.zero;
        TextOverflow _textOverflow = TextOverflow.clip;
        TextTransform _textTransform = TextTransform.none;
        WhiteSpace _whiteSpace = WhiteSpace.pre;
        Length _wordSpacing = Length.zero;
        // colors
        Color _textColor = Color.black;
        Color _focusRectColor = Color.transparent;
        // depend on text color
        Color _borderTopColor = Color.transparent;
        Color _borderRightColor = Color.transparent;
        Color _borderBottomColor = Color.transparent;
        Color _borderLeftColor = Color.transparent;
        Color _textDecorColor = Color.black;
        // effects
        float _opacity = 1;
        BlendMode _mixBlendMode = BlendMode.normal;
        // transitions and animations
        string _transitionProperty;
        TimingFunction _transitionTimingFunction;
        uint _transitionDuration;
        uint _transitionDelay;
        // misc
        CursorType _cursor = CursorType.automatic;
    }

    private LayoutLength applyEM(Length value) const
    {
        const LayoutLength ll = value.toLayout;
        if (value.is_rem)
        {
            const int def = FontManager.defaultFontSize;
            return LayoutLength(ll.applyPercent(def));
        }
        else if (value.is_em)
            return LayoutLength(ll.applyPercent(fontSize));
        else
            return ll;
    }

    /// ...without percent
    private float applyOnlyEM(Length value) const
    {
        const LayoutLength ll = value.toLayout;
        if (value.is_rem)
        {
            const int def = FontManager.defaultFontSize;
            return ll.applyPercent(def);
        }
        else if (value.is_em)
            return ll.applyPercent(fontSize);
        else
            return ll.applyPercent(0);
    }

    /// Resolve style cascading and inheritance, update all properties
    void recompute(Style[] chain, ComputedStyle* parentStyle)
    {
        /// iterate through all properties
        static foreach (name; __traits(allMembers, StyleProperty))
        {{
            enum ptype = mixin(`StyleProperty.` ~ name);
            enum bool inheritsByDefault = isInherited(ptype);

            // search in style chain, find nearest written property
            bool inh, set;
            foreach_reverse (st; chain)
            {
                auto plist = &st._props;

                static if (!inheritsByDefault)
                {
                    if (plist.isInherited(ptype))
                    {
                        inh = set = true;
                        break;
                    }
                }
                if (plist.isInitial(ptype))
                {
                    setDefault!name();
                    set = true;
                    break;
                }
                // get value here
                if (auto p = plist.peek!name)
                {
                    setProperty!name(*p);
                    set = true;
                    break;
                }
            }
            // set/reset 'inherit' flag
            if (inh || inheritsByDefault && !set)
                bts(inheritBitArray.ptr, ptype);
            else
                btr(inheritBitArray.ptr, ptype);

            // resolve inherited properties
            if (inherits(ptype))
            {
                if (parentStyle)
                    setProperty!name(mixin(`parentStyle._` ~ name));
                else
                    setDefault!name();
            }
            else if (!set)
            {
                // if nothing there - return value to defaults
                setDefault!name();
            }
        }}
        // set inherited properties in descendant elements. TODO: optimize, consider recursive updates
        foreach (child; element)
        {
            ComputedStyle* st = child.style;
            if (!st.isolated)
            {
                static foreach (name; __traits(allMembers, StyleProperty))
                {{
                    if (st.inherits(mixin(`StyleProperty.` ~ name)))
                        st.setProperty!name(mixin("_" ~ name));
                }}
            }
        }
    }

    private bool inherits(StyleProperty ptype)
    {
        return bt(inheritBitArray.ptr, ptype) != 0;
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

        if (_transitionProperty == "background")
            return property == "background-color";

        const bprefix = "border-";
        const bplen = bprefix.length;
        if (_transitionProperty == "border-width")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-width" || rest == "right-width" ||
                   rest == "bottom-width" || rest == "left-width";
        }
        if (_transitionProperty == "border-color")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-color" || rest == "right-color" ||
                   rest == "bottom-color" || rest == "left-color";
        }
        if (_transitionProperty == "border")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-width" || rest == "right-width" ||
                   rest == "bottom-width" || rest == "left-width" ||
                   rest == "top-color" || rest == "right-color" ||
                   rest == "bottom-color" || rest == "left-color";
        }

        if (_transitionProperty == "gap")
            return property == "row-gap" || property == "column-gap";

        return false;
    }

    private void setDefault(string name)()
    {
        enum ptype = mixin(`StyleProperty.` ~ name);

        static if (
            ptype == StyleProperty.borderTopColor ||
            ptype == StyleProperty.borderRightColor ||
            ptype == StyleProperty.borderBottomColor ||
            ptype == StyleProperty.borderLeftColor ||
            ptype == StyleProperty.textDecorColor)
        {
            // must be computed before
            setProperty!name(_textColor);
        }
        else
            setProperty!name(mixin(`defaults._` ~ name));
    }

    /// Set a property value, taking transitions into account
    private void setProperty(string name, T)(T newValue)
    {
        import std.meta : Alias;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`StyleProperty.` ~ name);

        // do nothing if changed nothing
        if (field is newValue)
        {
            static if (isAnimatable(ptype))
            {
                // cancel possible animation
                element.cancelAnimation(name);
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
        element.handleStyleChange(ptype);
    }

    private void animateProperty(string name, T)(T ending)
    {
        import std.meta : Alias;
        import beamui.core.animations : Transition;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`StyleProperty.` ~ name);

        T starting = field;
        auto tr = new Transition(_transitionDuration, _transitionTimingFunction, _transitionDelay);
        element.addAnimation(name, tr.duration,
            (double t) {
                field = tr.mix(starting, ending, t);
                element.handleStyleChange(ptype);
            }
        );
    }
}
