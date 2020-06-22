/**

Copyright: dayllenger 2018-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.computed_style;

public import beamui.css.tokenizer : CssToken = Token;
public import beamui.style.property : StyleProperty;
public import beamui.style.types : SpecialCSSType;
import beamui.core.animations;
import beamui.core.editable : TabSize;
import beamui.core.geometry : Insets;
import beamui.core.logger;
import beamui.core.units : Length, LayoutLength;
import beamui.graphics.colors : Color;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables;
import beamui.layout.alignment : Align, AlignItem, Distribution, Stretch;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.decode_css;
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
    // dfmt off
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
            return [
                _borderTopColor != Color.none ? _borderTopColor : _textColor,
                _borderRightColor != Color.none ? _borderRightColor : _textColor,
                _borderBottomColor != Color.none ? _borderBottomColor : _textColor,
                _borderLeftColor != Color.none ? _borderLeftColor : _textColor,
            ];
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

        TextDecor textDecor() const
        {
            const color = _textDecorColor == Color.none ? _textColor : _textDecorColor;
            return TextDecor(_textDecorLine, color, _textDecorStyle);
        }
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
    // dfmt on

    package(beamui) Element element;
    package(beamui) bool isolated;

    private
    {
        /// Inherits value from the parent element
        StaticBitArray!(P.max + 1) _inherited;

        // origins
        int _fontSize = 12;
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
        Color _borderTopColor = Color.none;
        Color _borderRightColor = Color.none;
        Color _borderBottomColor = Color.none;
        Color _borderLeftColor = Color.none;
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
        Color _textColor = Color.black;
        Color _textDecorColor = Color.none;
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

        const(CssToken)[][string] _customProps;
        const(CssToken)[][StyleProperty] _propCache;

        AnimationManager _animations;
    }

    T getPropertyValue(T, SpecialCSSType specialType = SpecialCSSType.none)(string name, lazy T def)
    {
        if (auto p = name in _customProps)
        {
            const(CssToken)[] tokens = *p;
            static if (specialType == SpecialCSSType.none)
                auto res = decode!T(tokens);
            else
                auto res = decode!specialType(tokens);
            return res ? res.val : def;
        }
        return def;
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
        _animations.element = element;

        const customPropsChanged = recomputeCustom(chain, parentStyle);
        recomputeBuiltin(chain, parentStyle);

        if (customPropsChanged)
            element.handleCustomPropertiesChange();
    }

    private bool recomputeCustom(Style[] chain, ComputedStyle* parentStyle)
    {
        import std.range : zip;

        bool hasSome;
        foreach (st; chain)
        {
            if (st._props.customProperties.length)
            {
                hasSome = true;
                break;
            }
        }
        auto previous = _customProps;
        if (hasSome)
        {
            _customProps = null;
            if (parentStyle)
            {
                foreach (name, tokens; parentStyle._customProps)
                    _customProps[name] = tokens;
            }
            foreach (st; chain)
            {
                foreach (name, tokens; st._props.customProperties)
                    _customProps[name] = tokens;
            }
        }
        else
        {
            _customProps = parentStyle ? parentStyle._customProps : null;
        }

        // compare old and new arrays
        if (previous is _customProps)
            return false;
        if (previous.length != _customProps.length)
            return true;
        foreach (a, b; zip(previous.byKeyValue, _customProps.byKeyValue))
        {
            if (a.key != b.key || a.value !is b.value)
                return true;
        }
        return false;
    }

    private void recomputeBuiltin(Style[] chain, ComputedStyle* parentStyle)
    {
        _inherited = _inherited.init;
        StaticBitArray!(StyleProperty.max + 1) modified;

        /// iterate through all built-in properties
        // dfmt off
        static foreach (name; __traits(allMembers, P))
        {
        // dfmt on
        {
            enum ptype = mixin(`P.` ~ name);
            enum bool inheritsByDefault = isInherited(ptype);

            // search in style chain, find nearest written property
            bool inh, set;
            foreach_reverse (st; chain)
            {
                auto plist = &st._props;
                if (!plist.isSet(ptype))
                    continue;

                // actually specified value
                if (auto p = plist.peek!name)
                {
                    _propCache.remove(ptype);
                    auto val = postprocessValue!ptype(*p, parentStyle);
                    if (setProperty!name(val))
                        modified.set(ptype);
                    set = true;
                    break;
                }
                // 'var(--something)'
                if (auto var = plist.getCustomValueName(ptype))
                {
                    if (auto p = var in _customProps)
                    {
                        const(CssToken)[] tokens = *p;
                        if (auto cached = ptype in _propCache)
                        {
                            if (*cached is tokens)
                            {
                                set = true;
                                break;
                            }
                        }
                        _propCache[ptype] = tokens;

                        alias T = typeof(mixin(`PropTypes.` ~ name));
                        enum specialType = getSpecialCSSType(ptype);

                        static if (specialType == SpecialCSSType.none)
                            auto result = decode!T(tokens);
                        else
                            auto result = decode!specialType(tokens);

                        if (result.err)
                            break;
                        if (!sanitizeProperty!ptype(result.val))
                            break;

                        auto val = postprocessValue!ptype(result.val, parentStyle);
                        if (setProperty!name(val))
                            modified.set(ptype);
                        set = true;
                    }
                    break;
                }
                // 'inherit'
                static if (!inheritsByDefault)
                {
                    if (plist.isInherited(ptype))
                    {
                        inh = set = true;
                        break;
                    }
                }
                // 'initial'
                if (plist.isInitial(ptype))
                {
                    _propCache.remove(ptype);
                    if (setProperty!name(getDefaultValue!name()))
                        modified.set(ptype);
                    set = true;
                    break;
                }
            }
            // remember inherited properties
            if (inh || inheritsByDefault && !set)
                _inherited.set(ptype);

            // resolve inherited properties
            if (_inherited[ptype])
            {
                _propCache.remove(ptype);
                auto val = parentStyle ? mixin(`parentStyle._` ~ name) : getDefaultValue!name();
                if (setProperty!name(val))
                    modified.set(ptype);
            }
            else if (!set)
            {
                // if nothing there - return value to defaults
                _propCache.remove(ptype);
                if (setProperty!name(getDefaultValue!name()))
                    modified.set(ptype);
            }
        }
        // dfmt off
        }
        // dfmt on
        // invoke side effects
        foreach (ptype; 0 .. StyleProperty.max + 1)
        {
            if (modified[ptype])
                element.handleStyleChange(cast(StyleProperty)ptype);
        }
        // set inherited properties in descendant elements
        propagateInheritedValues(modified);
    }

    private void propagateInheritedValues(StaticBitArray!(StyleProperty.max + 1) modified)
    {
        foreach (child; element)
        {
            ComputedStyle* st = child.style;
            if (st.isolated)
                continue;

            auto affected = modified & st._inherited;

            static foreach (name; __traits(allMembers, P))
            {
                {
                    enum ptype = mixin(`P.` ~ name);

                    if (affected[ptype])
                    {
                        if (!st.setProperty!name(mixin("_" ~ name)))
                            affected.reset(ptype);
                    }
                }
            }
            // continue recursively
            st.propagateInheritedValues(affected);

            // invoke side effects
            foreach (ptype; 0 .. StyleProperty.max + 1)
            {
                if (affected[ptype])
                    child.handleStyleChange(cast(StyleProperty)ptype);
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
        // dfmt off
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
        // dfmt on
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
        return mixin(`defaults._` ~ name);
    }

    /// Check whether the style can make transition for a CSS property
    bool hasTransitionFor(string property) const
    {
        if (_transitionTimingFunction is null || _transitionDuration <= 0)
            return false;

        const specified = _transitionProperty;
        if (specified == "all" || specified == property)
            return true;

        // dfmt off
        if (specified == "padding")
            return property == "padding-top" || property == "padding-right" ||
                   property == "padding-bottom" || property == "padding-left";

        if (specified == "background")
            return property == "background-color";

        const bprefix = "border-";
        const bplen = bprefix.length;
        if (specified == "border-width")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-width" || rest == "right-width" ||
                   rest == "bottom-width" || rest == "left-width";
        }
        if (specified == "border-color")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-color" || rest == "right-color" ||
                   rest == "bottom-color" || rest == "left-color";
        }
        if (specified == "border")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-width" || rest == "right-width" ||
                   rest == "bottom-width" || rest == "left-width" ||
                   rest == "top-color" || rest == "right-color" ||
                   rest == "bottom-color" || rest == "left-color";
        }

        if (specified == "gap")
            return property == "row-gap" || property == "column-gap";
        // dfmt on
        return false;
    }

    /// Set a property value, taking transitions into account
    private bool setProperty(string name, T)(T newValue)
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
                _animations.cancel(name);
            }
            return false;
        }
        // check animation
        static if (isAnimatable(ptype))
        {
            enum string cssname = getCSSName(ptype);
            if (hasTransitionFor(cssname))
            {
                animateProperty!name(newValue);
                return true;
            }
        }
        // set it directly otherwise
        field = newValue;
        return true;
    }

    private void animateProperty(string name, T)(T end)
    {
        import std.meta : Alias;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`P.` ~ name);

        T begin = field;
        auto tr = new Transition(_transitionDuration, _transitionTimingFunction, _transitionDelay);
        _animations.add(name, _transitionDuration, (double t) {
            field = tr.mix(begin, end, t);
            element.handleStyleChange(ptype);
        });
    }
}

private struct AnimationManager
{
    Element element;
    Animation[string] _map; // key is a property name
    double _prevTs = 0;

    void add(string name, long duration, void delegate(double) handler)
    {
        if (!_map.length)
        {
            auto win = element.window;
            assert(win);
            win.requestAnimationFrame(&process);
        }
        _map[name] = Animation(duration, handler);
    }

    void cancel(string name)
    {
        _map.remove(name);
    }

    void process(double ts)
    {
        if (_prevTs > 0)
            animate(ts - _prevTs);

        if (_map.length)
        {
            _prevTs = ts;
            auto win = element.window;
            assert(win);
            win.requestAnimationFrame(&process);
        }
        else
            _prevTs = 0;
    }

    void animate(double interval)
    {
        bool someAnimationsFinished;
        foreach (name, ref a; _map)
        {
            if (!a.isAnimating)
            {
                a.start();
                element.onAnimationStart(name);
            }
            else
            {
                a.tick(interval);
                if (!a.isAnimating)
                {
                    a.handler = null;
                    someAnimationsFinished = true;
                    element.onAnimationEnd(name);
                }
            }
        }
        if (someAnimationsFinished)
        {
            foreach (k, a; _map)
                if (!a.handler)
                    _map.remove(k);
        }
    }
}
