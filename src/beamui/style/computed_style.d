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

private alias P = StyleProperty;

/// Provides default style values for most of properties
private ComputedStyle defaults;

struct ComputedStyle
{
    @property
    {
        string display() const { return _display; }

        LayoutLength width() const { return _width; }
        LayoutLength height() const { return _height; }

        LayoutLength minWidth() const { return _minWidth; }
        LayoutLength minHeight() const { return _minHeight; }

        LayoutLength maxWidth() const { return _maxWidth; }
        LayoutLength maxHeight() const { return _maxHeight; }

        Insets padding() const
        {
            return Insets(_paddingTop, _paddingRight, _paddingBottom, _paddingLeft);
        }
        Insets borderWidth() const
        {
            return Insets(_borderTopWidth, _borderRightWidth, _borderBottomWidth, _borderLeftWidth);
        }
        Insets margins() const
        {
            return Insets(_marginTop, _marginRight, _marginBottom, _marginLeft);
        }

        LayoutLength left() const { return _left; }
        LayoutLength top() const { return _top; }
        LayoutLength right() const { return _right; }
        LayoutLength bottom() const { return _bottom; }

        Align alignment() const { return _alignment; }
        /// Returns horizontal alignment
        Align halign() const { return _alignment & Align.hcenter; }
        /// Returns vertical alignment
        Align valign() const { return _alignment & Align.vcenter; }

        Stretch stretch() const { return _stretch; }

        Distribution[2] placeContent() const { return [_justifyContent, _alignContent]; }
        AlignItem[2] placeItems() const { return [_justifyItems, _alignItems]; }
        AlignItem[2] placeSelf() const { return [_justifySelf, _alignSelf]; }

        LayoutLength rowGap() const { return _rowGap; }
        LayoutLength columnGap() const { return _columnGap; }

        int order() const { return _order; }
        int zIndex() const { return _zIndex; }

        FlexDirection flexDirection() const { return _flexDirection; }
        FlexWrap flexWrap() const { return _flexWrap; }

        float flexGrow() const { return _flexGrow; }
        float flexShrink() const { return _flexShrink; }
        LayoutLength flexBasis() const { return _flexBasis; }

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
        BgPosition backgroundPosition() const { return _bgPosition; }
        BgSize backgroundSize() const { return _bgSize; }
        RepeatStyle backgroundRepeat() const { return _bgRepeat; }
        BoxType backgroundOrigin() const { return _bgOrigin; }
        BoxType backgroundClip() const { return _bgClip; }

        Color[4] borderColor() const
        {
            return [_borderTopColor, _borderRightColor, _borderBottomColor, _borderLeftColor];
        }
        BorderStyle[4] borderStyle() const
        {
            return [_borderTopStyle, _borderRightStyle, _borderBottomStyle, _borderLeftStyle];
        }
        LayoutLength[4] borderRadii() const
        {
            return [_borderTopLeftRadius, _borderTopRightRadius,
                    _borderBottomLeftRadius, _borderBottomRightRadius];
        }

        inout(BoxShadowDrawable) boxShadow() inout { return _boxShadow; }

        string fontFace() const { return _fontFace; }
        FontFamily fontFamily() const { return _fontFamily; }
        bool fontItalic() const { return _fontStyle == FontStyle.italic; }
        ushort fontWeight() const { return _fontWeight; }

        /// Computed font size in device-independent pixels
        int fontSize() const { return _fontSize; }

        TabSize tabSize() const { return _tabSize; }

        TextDecor textDecor() const { return TextDecor(_textDecorLine, _textDecorColor, _textDecorStyle); }
        TextAlign textAlign() const { return _textAlign; }
        Color textColor() const { return _textColor; }
        TextHotkey textHotkey() const { return _textHotkey; }
        TextOverflow textOverflow() const { return _textOverflow; }
        TextTransform textTransform() const { return _textTransform; }

        float letterSpacing() const { return _letterSpacing; }
        float wordSpacing() const { return _wordSpacing; }

        float lineHeight() const { return _lineHeight; }
        LayoutLength textIndent() const { return _textIndent; }

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

        /// Inherits value from the parent element
        size_t[(P.max + 1) / (8 * size_t.sizeof) + 1] inheritBitArray;

        // origins
        int _fontSize = 12;
        Color _textColor = Color.black;
        // layout
        string _display;
        // box model
        LayoutLength _width = LayoutLength.none;
        LayoutLength _height = LayoutLength.none;
        LayoutLength _minWidth = LayoutLength.none;
        LayoutLength _maxWidth = LayoutLength.none;
        LayoutLength _minHeight = LayoutLength.none;
        LayoutLength _maxHeight = LayoutLength.none;
        float _paddingTop = 0;
        float _paddingRight = 0;
        float _paddingBottom = 0;
        float _paddingLeft = 0;
        float _borderTopWidth = 0;
        float _borderRightWidth = 0;
        float _borderBottomWidth = 0;
        float _borderLeftWidth = 0;
        float _marginTop = 0;
        float _marginRight = 0;
        float _marginBottom = 0;
        float _marginLeft = 0;
        // placement
        LayoutLength _left = LayoutLength.none;
        LayoutLength _top = LayoutLength.none;
        LayoutLength _right = LayoutLength.none;
        LayoutLength _bottom = LayoutLength.none;
        Align _alignment;
        LayoutLength _rowGap = LayoutLength.zero;
        LayoutLength _columnGap = LayoutLength.zero;
        int _order = 0;
        int _zIndex = int.min;
        // flexbox-specific
        float _flexGrow = 0;
        float _flexShrink = 1;
        LayoutLength _flexBasis = LayoutLength.none;
        // grid-specific
        TrackSize[] _gridTemplateRows;
        TrackSize[] _gridTemplateColumns;
        GridNamedAreas _gridTemplateAreas;
        TrackSize _gridAutoRows = TrackSize.automatic;
        TrackSize _gridAutoColumns = TrackSize.automatic;
        GridLineName _gridRowStart;
        GridLineName _gridRowEnd;
        GridLineName _gridColumnStart;
        GridLineName _gridColumnEnd;
        // background
        Color _bgColor = Color.transparent;
        Drawable _bgImage;
        BgPosition _bgPosition;
        BgSize _bgSize;
        Color _borderTopColor = Color.transparent;
        Color _borderRightColor = Color.transparent;
        Color _borderBottomColor = Color.transparent;
        Color _borderLeftColor = Color.transparent;
        LayoutLength _borderTopLeftRadius = LayoutLength.zero;
        LayoutLength _borderTopRightRadius = LayoutLength.zero;
        LayoutLength _borderBottomLeftRadius = LayoutLength.zero;
        LayoutLength _borderBottomRightRadius = LayoutLength.zero;
        BoxShadowDrawable _boxShadow;
        Color _focusRectColor = Color.transparent;
        // text
        string _fontFace = "Arial";
        float _letterSpacing = 0;
        float _lineHeight = 14;
        Color _textDecorColor = Color.black;
        LayoutLength _textIndent = LayoutLength.zero;
        float _wordSpacing = 0;
        // effects
        float _opacity = 1;
        // transitions and animations
        string _transitionProperty;
        TimingFunction _transitionTimingFunction;
        uint _transitionDuration;
        uint _transitionDelay;

        // packing
        Stretch _stretch = Stretch.cross;
        Distribution _justifyContent = Distribution.stretch;
        AlignItem _justifyItems = AlignItem.stretch;
        AlignItem _justifySelf = AlignItem.unspecified;
        Distribution _alignContent = Distribution.stretch;
        AlignItem _alignItems = AlignItem.stretch;
        AlignItem _alignSelf = AlignItem.unspecified;
        FlexDirection _flexDirection = FlexDirection.row;
        FlexWrap _flexWrap = FlexWrap.off;
        GridFlow _gridAutoFlow = GridFlow.row;
        RepeatStyle _bgRepeat;
        BoxType _bgOrigin = BoxType.padding;
        BoxType _bgClip = BoxType.border;
        BorderStyle _borderTopStyle = BorderStyle.none;
        BorderStyle _borderRightStyle = BorderStyle.none;
        BorderStyle _borderBottomStyle = BorderStyle.none;
        BorderStyle _borderLeftStyle = BorderStyle.none;
        FontFamily _fontFamily = FontFamily.sans_serif;
        FontStyle _fontStyle = FontStyle.normal;
        ushort _fontWeight = 400;
        TabSize _tabSize = TabSize(4);
        TextAlign _textAlign = TextAlign.start;
        TextDecorLine _textDecorLine = TextDecorLine.none;
        TextDecorStyle _textDecorStyle = TextDecorStyle.solid;
        TextHotkey _textHotkey = TextHotkey.ignore;
        TextOverflow _textOverflow = TextOverflow.clip;
        TextTransform _textTransform = TextTransform.none;
        WhiteSpace _whiteSpace = WhiteSpace.pre;
        BlendMode _mixBlendMode = BlendMode.normal;
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
            return LayoutLength(ll.applyPercent(_fontSize));
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
            return ll.applyPercent(_fontSize);
        else
            return ll.applyPercent(0);
    }

    /// Resolve style cascading and inheritance, update all properties
    void recompute(Style[] chain, ComputedStyle* parentStyle)
    {
        /// iterate through all properties
        static foreach (name; __traits(allMembers, P))
        {{
            enum ptype = mixin(`P.` ~ name);
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
                    setProperty!name(getDefaultValue!name());
                    set = true;
                    break;
                }
                // get value here
                if (auto p = plist.peek!name)
                {
                    setProperty!name(postprocessValue!ptype(*p, parentStyle));
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
                    setProperty!name(getDefaultValue!name());
            }
            else if (!set)
            {
                // if nothing there - return value to defaults
                setProperty!name(getDefaultValue!name());
            }
        }}
        // set inherited properties in descendant elements. TODO: optimize, consider recursive updates
        foreach (child; element)
        {
            ComputedStyle* st = child.style;
            if (!st.isolated)
            {
                static foreach (name; __traits(allMembers, P))
                {{
                    if (st.inherits(mixin(`P.` ~ name)))
                        st.setProperty!name(mixin("_" ~ name));
                }}
            }
        }
    }

    private auto postprocessValue(P ptype, T)(ref T value, ComputedStyle* parentStyle)
    {
        static if (ptype == P.fontSize)
        {
            const Length fs = value;
            const int def = FontManager.defaultFontSize;
            if (!fs.is_rem && !parentStyle && (fs.is_em || fs.is_percent))
            {
                return def;
            }
            else
            {
                const int base = parentStyle ? parentStyle._fontSize : def;
                return cast(int)fs.toLayout.applyPercent(base);
            }
        }
        else static if (false
            || ptype == P.width
            || ptype == P.height
            || ptype == P.minWidth
            || ptype == P.maxWidth
            || ptype == P.minHeight
            || ptype == P.maxHeight
            || ptype == P.left
            || ptype == P.top
            || ptype == P.right
            || ptype == P.bottom
            || ptype == P.rowGap
            || ptype == P.columnGap
            || ptype == P.flexBasis
            || ptype == P.borderTopLeftRadius
            || ptype == P.borderTopRightRadius
            || ptype == P.borderBottomLeftRadius
            || ptype == P.borderBottomRightRadius
            || ptype == P.textIndent
        )
        {
            return applyEM(value);
        }
        else static if (false
            || ptype == P.paddingTop
            || ptype == P.paddingRight
            || ptype == P.paddingBottom
            || ptype == P.paddingLeft
            || ptype == P.borderTopWidth
            || ptype == P.borderRightWidth
            || ptype == P.borderBottomWidth
            || ptype == P.borderLeftWidth
            || ptype == P.marginTop
            || ptype == P.marginRight
            || ptype == P.marginBottom
            || ptype == P.marginLeft
            || ptype == P.letterSpacing
            || ptype == P.lineHeight
            || ptype == P.wordSpacing
        )
        {
            return applyOnlyEM(value);
        }
        else static if (ptype == P.bgPosition)
        {
            return BgPosition(applyEM(value.x), applyEM(value.y));
        }
        else static if (ptype == P.bgSize)
        {
            const t = value.type;
            if (t == BgSizeType.length)
                return BgSize(t, applyEM(value.x), applyEM(value.y));
            else
                return BgSize(t);
        }
        else
            return value;
    }

    private auto getDefaultValue(string name)()
    {
        enum ptype = mixin(`P.` ~ name);

        static if (false
            || ptype == P.borderTopColor
            || ptype == P.borderRightColor
            || ptype == P.borderBottomColor
            || ptype == P.borderLeftColor
            || ptype == P.textDecorColor
        )
        {
            // must be computed before
            return _textColor;
        }
        else
            return mixin(`defaults._` ~ name);
    }

    private bool inherits(P ptype)
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

    /// Set a property value, taking transitions into account
    private void setProperty(string name, T)(T newValue)
    {
        import std.meta : Alias;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`P.` ~ name);

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
        enum ptype = mixin(`P.` ~ name);

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
