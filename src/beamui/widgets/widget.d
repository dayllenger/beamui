/**
Contains declaration of Widget class - base for all widgets.

Synopsis:
---
import beamui.widgets.widget;

auto w = new Widget("id1");
// access attributes as properties
w.padding = 10;
w.backgroundColor = 0xAAAA00;
// same, but using chained method call
auto w = new Widget("id1").padding(10).backgroundColor(0xFFFF00).
---

Copyright: Vadim Lopatin 2014-2018, Andrzej Kilijański 2017-2018, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.widget;

public
{
    import beamui.core.actions;
    import beamui.core.collections;
    import beamui.core.config;
    import beamui.core.functions;
    import beamui.core.i18n;
    import beamui.core.logger;
    import beamui.core.ownership;
    import beamui.core.signals;
    import beamui.core.types;
    import beamui.core.units;

    import beamui.graphics.colors;
    import beamui.graphics.drawables;
    import beamui.graphics.drawbuf;
    import beamui.graphics.fonts;

    import beamui.style.theme : currentTheme;
    import beamui.style.types;

    import beamui.widgets.popup : PopupAlign;
}
import std.string : capitalize;
import beamui.core.animations;
import beamui.dml.annotations;
import beamui.platforms.common.platform;
import beamui.style.style;
import beamui.widgets.menu;

/// Widget visibility
enum Visibility : ubyte
{
    /// Visible on screen (default)
    visible,
    /// Not visible, but occupies a space in layout. Does not receive mouse or key events.
    invisible,
    /// Completely hidden, as not has been added
    gone
}

/// Orientation of e.g. layouts
enum Orientation : ubyte
{
    horizontal,
    vertical
}

enum FocusReason : ubyte
{
    tabFocus,
    unspecified
}

/// Focus movement options
enum FocusMovement
{
    /// No focus movement
    none,
    /// Next focusable (Tab)
    next,
    /// Previous focusable (Shift+Tab)
    previous,
    /// Move to nearest above
    up,
    /// Move to nearest below
    down,
    /// Move to nearest at left
    left,
    /// Move to nearest at right
    right,
}

/// Standard mouse cursor types
enum CursorType
{
    none,
    /// When set in widget means to use parent's cursor, in Window.overrideCursorType() disable overriding.
    notSet,
    arrow,
    ibeam,
    wait,
    crosshair,
    waitArrow,
    sizeNWSE,
    sizeNESW,
    sizeWE,
    sizeNS,
    sizeAll,
    no,
    hand
}

/// Base class for all widgets.
@dmlwidget class Widget
{
private:
    /// Widget id
    string _id;

    /// Style class list
    bool[string] styleClasses; // value means nothing
    struct StyleSubItemInfo
    {
        Object parent;
        string subName;
    }
    /// Structure needed when this widget is subitem of another
    StyleSubItemInfo* subInfo;
    /// If true, the style will be recomputed on next usage
    bool _needToRecomputeStyle = true;

    /// Widget state (set of flags from State enum)
    State _state = State.normal;
    /// Widget visibility: either visible, invisible, gone
    Visibility _visibility = Visibility.visible; // visible by default

    /// Current widget box set by layout()
    Box _box;
    /// True to force layout
    bool _needLayout = true;
    /// True to force redraw
    bool _needDraw = true;
    /// Parent widget
    Widget _parent;
    /// Window (to be used for top level widgets only!)
    Window _window;

    /// Does widget need to track mouse hover
    bool _trackHover;

    bool* _isDestroyed;

    // computed style properties
    // layout
    @forCSS("width") @animatable
        Dimension _width = Dimension.none;
    @forCSS("height") @animatable
        Dimension _height = Dimension.none;
    @forCSS("min-width") @animatable
        Dimension _minWidth = Dimension.zero;
    @forCSS("max-width") @animatable
        Dimension _maxWidth = Dimension.none;
    @forCSS("min-height") @animatable
        Dimension _minHeight = Dimension.zero;
    @forCSS("max-height") @animatable
        Dimension _maxHeight = Dimension.none;

    static foreach (side; ["top", "right", "bottom", "left"])
    {
        @forCSS("padding-" ~ side) @animatable
        mixin("Dimension  _padding" ~ side.capitalize ~ " = Dimension.zero;");

        @forCSS("border-" ~ side ~ "-width") @animatable
        mixin("Dimension  _borderWidth" ~ side.capitalize ~ " = Dimension.zero;");
    }
    // background
    @forCSS("border-color") @animatable
        Color _borderColor = Color.transparent;
    @forCSS("background-color") @animatable
        Color _backgroundColor = Color.transparent;
    @forCSS("background-image", SpecialCSSType.image)
        Drawable _backgroundImage;
    @forCSS("box-shadow")
        BoxShadowDrawable _boxShadow;
    // text
    @forCSS("font-face")
        string _fontFace = "Arial";
    @forCSS("font-family")
        FontFamily _fontFamily = FontFamily.sans_serif;
    @forCSS("font-size")
        Dimension _fontSize = Dimension.pt(9);
    @forCSS("font-style")
        FontStyle _fontStyle = FontStyle.normal;
    @forCSS("font-weight", SpecialCSSType.fontWeight)
        ushort _fontWeight = 400;
    @forCSS("text-flags")
        TextFlag _textFlags = TextFlag.unspecified;
    // colors
    @forCSS("opacity", SpecialCSSType.opacity) @animatable
        ubyte _alpha = 0;
    @forCSS("color") @animatable
        Color _textColor = Color(0x000000);
    @forCSS("focus-rect-color") @animatable
        Color _focusRectColor = Color.transparent;
    // transitions and animations
    @forCSS("transition-property", SpecialCSSType.transitionProperty)
        string _transitionProperty;
    @forCSS("transition-timing-function")
        TimingFunction _transitionTimingFunction;
    @forCSS("transition-duration", SpecialCSSType.time)
        uint _transitionDuration;
    @forCSS("transition-delay", SpecialCSSType.time)
        uint _transitionDelay;

    @shorthandInsets("padding", "padding-top", "padding-right", "padding-bottom", "padding-left")
    @shorthandInsets("border-width", "border-top-width", "border-right-width",
                     "border-bottom-width", "border-left-width")
    @shorthandBorder("border", "border-top-width", "border-right-width",
                     "border-bottom-width", "border-left-width", "border-color")
    @shorthandDrawable("background", "background-color", "background-image")
    @shorthandTransition("transition", "transition-property", "transition-duration",
                         "transition-timing-function", "transition-delay")
    static bool shorthandsForCSS;

    Background _background;
    FontRef _font;

    Animation[string] animations; // key is a property name

public:

    /// Empty parameter list constructor - for usage by factory
    this()
    {
        this(null);
    }
    /// Create with ID parameter
    this(string ID)
    {
        _isDestroyed = new bool;
        _id = ID;
        _background = new Background;
        debug _instanceCount++;
        debug (resalloc)
            Log.fd("Created widget `%s` %s, count: %s", _id, this.classinfo.name, _instanceCount);
    }

    debug
    {
        private static __gshared int _instanceCount;
        /// Number of created widget objects, not yet destroyed - for debug purposes
        static @property int instanceCount() { return _instanceCount; }
    }

    ~this()
    {
        debug _instanceCount--;
        debug (resalloc)
            Log.fd("Destroyed widget `%s` %s, count: %s", _id, this.classinfo.name, _instanceCount);
        debug if (APP_IS_SHUTTING_DOWN)
            onResourceDestroyWhileShutdown(_id, this.classinfo.name);

        animations.clear();

        if (ownProperties !is null)
        {
            if (isOwned("_boxShadow"))
                eliminate(_boxShadow);
            if (isOwned("_backgroundImage"))
                eliminate(_backgroundImage);
            if (isOwned("_transitionTimingFunction"))
                eliminate(_transitionTimingFunction);
            ownProperties.clear();
        }

        _font.clear();
        eliminate(_background);

        eliminate(subInfo);
        eliminate(_popupMenu);
        if (_isDestroyed !is null)
            *_isDestroyed = true;
    }

    /// Flag for WeakRef that indicates widget destruction
    final @property const(bool*) isDestroyed() const
    {
        return _isDestroyed;
    }

    //===============================================================
    // Widget ID

    /// Widget id, null if not set
    @property string id() const { return _id; }
    /// ditto
    @property Widget id(string id)
    {
        if (_id != id)
        {
            _id = id;
            invalidateStyles();
        }
        return this;
    }
    /// Compare widget id with specified value, returns true if matches
    bool compareID(string id) const
    {
        return (_id !is null) && id == _id;
    }

    //===============================================================
    // State

    /// Widget state (set of flags from State enum)
    @property State state() const
    {
        if ((_state & State.parent) != 0 && _parent !is null)
            return _parent.state;
        if (focusGroupFocused)
            return _state | State.windowFocused; // TODO:
        return _state;
    }
    /// ditto
    @property Widget state(State newState)
    {
        if ((_state & State.parent) != 0 && _parent !is null)
            return _parent.state(newState);
        if (newState != _state)
        {
            State oldState = _state;
            _state = newState;
            // need to recompute the style
            invalidateStyles();
            // notify focus changes
            if ((oldState & State.focused) && !(newState & State.focused))
            {
                handleFocusChange(false);
                focusChanged(this, false);
            }
            else if (!(oldState & State.focused) && (newState & State.focused))
            {
                handleFocusChange(true, cast(bool)(newState & State.keyboardFocused));
                focusChanged(this, true);
            }
            // notify checked changes
            if ((oldState & State.checked) && !(newState & State.checked))
            {
                handleCheckChange(false);
                checkChanged(this, false);
            }
            else if (!(oldState & State.checked) && (newState & State.checked))
            {
                handleCheckChange(true);
                checkChanged(this, true);
            }
        }
        return this;
    }
    /// Add state flags (set of flags from State enum)
    @property Widget setState(State stateFlagsToSet)
    {
        return state(state | stateFlagsToSet);
    }
    /// Remove state flags (set of flags from State enum)
    @property Widget resetState(State stateFlagsToUnset)
    {
        return state(state & ~stateFlagsToUnset);
    }
    /// Override to handle focus changes
    protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
    }
    /// Override to handle check changes
    protected void handleCheckChange(bool checked)
    {
    }

    //===============================================================
    // Style

    mixin SupportCSS;

    /// Check whether widget has certain style class
    bool hasStyleClass(string name) const
    {
        return (name in styleClasses) !is null;
    }
    /// Add style classes to the widget
    Widget addStyleClasses(string[] names...)
    {
        foreach (name; names)
        {
            assert(name.length);
            styleClasses[name] = false;
        }
        invalidateStyles();
        return this;
    }
    /// Remove style classes from the widget
    Widget removeStyleClasses(string[] names...)
    {
        foreach (name; names)
        {
            assert(name.length);
            styleClasses.remove(name);
        }
        invalidateStyles();
        return this;
    }
    /// Toggle style class on the widget - remove if present, add if not
    Widget toggleStyleClass(string name)
    {
        assert(name.length);
        bool present = styleClasses.remove(name);
        if (!present)
            styleClasses[name] = false;
        invalidateStyles();
        return this;
    }
    /// Shorthand to set one style class to the widget
    @property Widget style(string name)
    {
        assert(name.length);
        styleClasses.clear();
        styleClasses[name] = false;
        invalidateStyles();
        return this;
    }

    /// Set this widget to be a subitem in stylesheet
    Widget bindSubItem(Object parent, string subName)
    {
        assert(parent && subName);
        subInfo = new StyleSubItemInfo(parent, subName);
        _needToRecomputeStyle = true;
        return this;
    }

    /// Signals when styles are being recomputed. Used for mixing properties in the widget.
    Listener!(void delegate(Style[] chain)) stylesRecomputed;

    /// Recompute styles, only if needed
    protected void updateStyles() inout
    {
        if (_needToRecomputeStyle)
        {
            Widget wt = cast(Widget)this;
            wt._needToRecomputeStyle = false;
            Style[] chain = selectStyleChain();
            wt.recomputeStyle(chain);
            if (wt.stylesRecomputed.assigned)
                wt.stylesRecomputed(chain);
        }
    }

    /// Get a style chain for this widget from current theme, least specific styles first
    Style[] selectStyleChain() const
    {
        static Style[] chain;
        size_t count;
        foreach (style; currentTheme.styles)
        {
            if (matchSelector(style.selector))
            {
                if (chain.length <= count)
                    chain.length += 4;
                chain[count] = style;
                count++;
            }
        }
        sort(chain[0 .. count]);
        return chain[0 .. count];
    }

    /// Match this widget with selector
    bool matchSelector(ref const(Selector) sel) const
    {
        if (sel.universal)
            return matchContextSelector(sel);
        // subitemness
        if (!subInfo && sel.subitem)
            return false;
        if (subInfo)
        {
            if (!sel.subitem || subInfo.subName != sel.subitem)
                return false;
            // match parent
            if (auto wt = cast(Widget)subInfo.parent)
            {
                Selector ps = cast(Selector)sel;
                ps.subitem = null;
                return wt.matchSelector(ps);
            }
            else // not a widget
            {
                // check only type and state
                TypeInfo_Class type = typeid(subInfo.parent);
                if (sel.type != getShortClassName(type))
                    return false;
                if ((sel.specifiedState & state) != sel.enabledState)
                    return false;
                return true;
            }
        }
        // state
        if ((sel.specifiedState & state) != sel.enabledState)
            return false;
        // id
        if (sel.id && (!_id || _id != sel.id))
            return false;
        // type
        if (sel.type)
        {
            TypeInfo_Class type = typeid(this);
            while (sel.type != getShortClassName(type))
            {
                type = type.base; // support inheritance
                if (type is typeid(Object))
                    return false;
            }
        }
        // class
        foreach (name; sel.classes)
        {
            if ((name in styleClasses) is null)
                return false;
        }
        return matchContextSelector(sel);
    }

    private bool matchContextSelector(ref const(Selector) sel) const
    {
        if (sel.previous)
        {
            if (!_parent)
                return false;
            final switch (sel.combinator) with (Selector.Combinator)
            {
            case descendant:
                Widget p = cast(Widget)_parent;
                while (p)
                {
                    if (p.matchSelector(*sel.previous))
                        return true;
                    p = p._parent;
                }
                return false;
            case child:
                return _parent.matchSelector(*sel.previous);
            case next:
                int n = (cast(Widget)_parent).childIndex(cast(Widget)this) - 1; // FIXME
                if (n >= 0)
                    return _parent.child(n).matchSelector(*sel.previous);
                else
                    return false;
            case subsequent:
                int n = (cast(Widget)_parent).childIndex(cast(Widget)this); // FIXME
                if (n >= 0)
                {
                    foreach (i; 0 .. n)
                        if (_parent.child(i).matchSelector(*sel.previous))
                            return true;
                }
                return false;
            }
        }
        else
            return true;
    }

    private void invalidateStyles()
    {
        if (_parent)
        {
            int start = _parent.childIndex(this);
            if (start >= 0)
            {
                foreach (i; start .. _parent.childCount)
                    _parent.child(i).invalidateStylesRecursively();
            }
            else
                invalidateStylesRecursively();
        }
        else
            invalidateStylesRecursively();
    }

    private void invalidateStylesRecursively()
    {
        _needToRecomputeStyle = true;
        foreach (i; 0 .. childCount)
        {
            child(i).invalidateStylesRecursively();
        }
    }

    private void needToRecomputeStateStyle()
    {
        _needToRecomputeStyle = true;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item && item._state & State.parent)
            {
                item.needToRecomputeStateStyle();
            }
        }
    }

    /// Handle theme change: e.g. reload some themed resources
    void onThemeChanged()
    {
        // default implementation: call recursive for children
        foreach (i; 0 .. childCount)
            child(i).onThemeChanged();

        _needToRecomputeStyle = true;
    }

    //===============================================================
    // Style related properties

    @property
    {
        enum FOCUS_RECT_PADDING = 2;
        /// Padding (between background bounds and content of widget)
        Insets padding() const
        {
            updateStyles();
            // get max padding from style padding and background drawable padding
            Insets p = Insets(_paddingTop.toDevice, _paddingRight.toDevice,
                              _paddingBottom.toDevice, _paddingLeft.toDevice);
            Insets bp = _background.padding;
            if (p.left < bp.left)
                p.left = bp.left;
            if (p.right < bp.right)
                p.right = bp.right;
            if (p.top < bp.top)
                p.top = bp.top;
            if (p.bottom < bp.bottom)
                p.bottom = bp.bottom;

            if ((focusable || ((state & State.parent) && parent.focusable)) && focusRectColor != Color.transparent)
            {
                // add two pixels to padding when focus rect is required
                // one pixel for focus rect, one for additional space
                p.add(Insets(FOCUS_RECT_PADDING));
            }
            return p;
        }
        /// ditto
        Widget padding(Insets value)
        {
            setProperty!"_paddingTop" = Dimension(value.top);
            setProperty!"_paddingRight" = Dimension(value.right);
            setProperty!"_paddingBottom" = Dimension(value.bottom);
            setProperty!"_paddingLeft" = Dimension(value.left);
            return this;
        }
        /// ditto
        Widget padding(int v)
        {
            return padding = Insets(v);
        }
        private alias paddingTop_effect = requestLayout;
        private alias paddingRight_effect = requestLayout;
        private alias paddingBottom_effect = requestLayout;
        private alias paddingLeft_effect = requestLayout;

        ///
        Insets borderWidth() const
        {
            updateStyles();
            return Insets(_borderWidthTop.toDevice, _borderWidthRight.toDevice,
                          _borderWidthBottom.toDevice, _borderWidthLeft.toDevice);
        }
        Widget borderWidth(Insets value)
        {
            setProperty!"_borderWidthTop" = Dimension(value.top);
            setProperty!"_borderWidthRight" = Dimension(value.right);
            setProperty!"_borderWidthBottom" = Dimension(value.bottom);
            setProperty!"_borderWidthLeft" = Dimension(value.left);
            return this;
        }
        private void borderWidthTop_effect(Dimension value)
        {
            _background.border.size.top = value.toDevice;
            requestLayout();
        }
        private void borderWidthRight_effect(Dimension value)
        {
            _background.border.size.right = value.toDevice;
            requestLayout();
        }
        private void borderWidthBottom_effect(Dimension value)
        {
            _background.border.size.bottom = value.toDevice;
            requestLayout();
        }
        private void borderWidthLeft_effect(Dimension value)
        {
            _background.border.size.left = value.toDevice;
            requestLayout();
        }
        /// Color of widget border
        Color borderColor() const
        {
            updateStyles();
            return _borderColor;
        }
        /// ditto
        Widget borderColor(Color value)
        {
            setProperty!"_borderColor" = value;
            return this;
        }
        private void borderColor_effect(Color value)
        {
            _background.border.color = value;
            invalidate();
        }

        /// Background color of the widget
        Color backgroundColor() const
        {
            updateStyles();
            return _backgroundColor;
        }
        /// ditto
        Widget backgroundColor(Color value)
        {
            setProperty!"_backgroundColor" = value;
            return this;
        }
        /// Set background color as ARGB 32 bit value
        Widget backgroundColor(uint value)
        {
            return backgroundColor = Color(value);
        }
        /// Set background color from string like "#5599CC" or "white"
        Widget backgroundColor(string colorString)
        {
            Color value = decodeHexColor(colorString, Color.none);
            if (value == Color.none)
                value = decodeTextColor(colorString, Color.transparent);
            return backgroundColor = value;
        }
        private void backgroundColor_effect(Color value)
        {
            _background.color = value;
            invalidate();
        }

        /// Background image drawable
        const(Drawable) backgroundImage() const
        {
            updateStyles();
            return _backgroundImage;
        }
        /// ditto
        Widget backgroundImage(Drawable image)
        {
            setProperty!"_backgroundImage" = image;
            return this;
        }
        private void backgroundImage_effect(Drawable image)
        {
            _background.image = image;
            invalidate();
        }

        ///
        inout(BoxShadowDrawable) boxShadow() inout
        {
            updateStyles();
            return _boxShadow;
        }
        /// ditto
        Widget boxShadow(BoxShadowDrawable shadow)
        {
            setProperty!"_boxShadow" = shadow;
            return this;
        }
        private void boxShadow_effect(BoxShadowDrawable shadow)
        {
            _background.shadow = shadow;
            invalidate();
        }

        /// Get widget standard background. The background object has the same lifetime as the widget.
        inout(Background) background() inout
        {
            updateStyles();
            return _background;
        }

        /// Widget drawing alpha value (0 = opaque .. 255 = transparent)
        ubyte alpha() const
        {
            updateStyles();
            return _alpha;
        }
        /// ditto
        Widget alpha(ubyte value)
        {
            setProperty!"_alpha" = value;
            return this;
        }
        private alias alpha_effect = invalidate;

        /// Text color
        Color textColor() const
        {
            updateStyles();
            return _textColor;
        }
        /// ditto
        Widget textColor(Color value)
        {
            setProperty!"_textColor" = value;
            return this;
        }
        /// Se text color as ARGB 32 bit value
        Widget textColor(uint value)
        {
            return textColor = Color(value);
        }
        /// Set text color from string like "#5599CC" or "white"
        Widget textColor(string colorString)
        {
            Color value = decodeHexColor(colorString, Color.none);
            if (value == Color.none)
                value = decodeTextColor(colorString, Color(0x0));
            return textColor = value;
        }
        private alias textColor_effect = invalidate;

        /// Get color to draw focus rectangle, Color.transparent if no focus rect should be drawn
        Color focusRectColor() const
        {
            updateStyles();
            return _focusRectColor;
        }

        /// Text flags (bit set of TextFlag enum values)
        TextFlag textFlags() const
        {
            updateStyles();
            TextFlag res = _textFlags;
            if (res == TextFlag.parent)
            {
                if (parent)
                    res = parent.textFlags;
                else
                    res = TextFlag.unspecified;
            }
            if (res & TextFlag.underlineHotkeysOnAlt)
            {
                uint modifiers = 0;
                if (window !is null)
                    modifiers = window.keyboardModifiers;
                bool altPressed = (modifiers & (KeyFlag.alt | KeyFlag.lalt | KeyFlag.ralt)) != 0;
                if (!altPressed)
                {
                    res = (res & ~(TextFlag.underlineHotkeysOnAlt | TextFlag.underlineHotkeys)) | TextFlag.hotkeys;
                }
                else
                {
                    res |= TextFlag.underlineHotkeys;
                }
            }
            return res;
        }
        /// ditto
        Widget textFlags(TextFlag value)
        {
            setProperty!"_textFlags" = value;
            return this;
        }
        private void textFlags_effect(TextFlag newValue, TextFlag oldValue)
        {
            bool oldHotkeys = (oldValue & TextFlag.hotkeys) != 0;
            bool newHotkeys = (newValue & TextFlag.hotkeys) != 0;
            handleFontChanged();
            if (oldHotkeys != newHotkeys)
                requestLayout();
            else
                invalidate();
        }

        /// Font face for widget
        string fontFace() const
        {
            updateStyles();
            return _fontFace;
        }
        /// ditto
        Widget fontFace(string value)
        {
            setProperty!"_fontFace" = value;
            return this;
        }
        /// Font family for widget
        FontFamily fontFamily() const
        {
            updateStyles();
            return _fontFamily;
        }
        /// ditto
        Widget fontFamily(FontFamily value)
        {
            setProperty!"_fontFamily" = value;
            return this;
        }
        /// Font style (italic/normal) for widget
        bool fontItalic() const
        {
            updateStyles();
            return _fontStyle == FontStyle.italic;
        }
        /// ditto
        Widget fontItalic(bool italic)
        {
            setProperty!"_fontStyle" = italic ? FontStyle.italic : FontStyle.normal;
            return this;
        }
        /// Font size in pixels
        int fontSize() const
        {
            updateStyles();
            if (!parent && (_fontSize.is_em || _fontSize.is_percent))
                return 12;
            int res = _fontSize.toDevice;
            if (_fontSize.is_em)
                return parent.fontSize * res / 100;
            if (_fontSize.is_percent)
                return parent.fontSize * res / 10000;
            return res;
        }
        /// ditto
        Widget fontSize(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.pt(9);
            setProperty!"_fontSize" = value;
            return this;
        }
        /// ditto
        Widget fontSize(int size)
        {
            fontSize = Dimension(size);
            return this;
        }
        /// Font weight for widget
        ushort fontWeight() const
        {
            updateStyles();
            return _fontWeight;
        }
        /// ditto
        Widget fontWeight(ushort value)
        {
            value = cast(ushort)clamp(value, 100, 900);
            setProperty!"_fontWeight" = value;
            return this;
        }
        private void fontFace_effect()
        {
            _font.clear();
            handleFontChanged();
            requestLayout();
        }
        private alias fontFamily_effect = fontFace_effect;
        private alias fontStyle_effect = fontFace_effect;
        private alias fontSize_effect = fontFace_effect;
        private alias fontWeight_effect = fontFace_effect;

        /// Returns font set for widget using style or set manually
        FontRef font() const
        {
            updateStyles();
            Widget wt = cast(Widget)this;
            if (!wt._font.isNull)
                return wt._font;
            wt._font = FontManager.instance.getFont(fontSize, fontWeight, fontItalic, fontFamily, fontFace);
            return wt._font;
        }

        /// Widget content text (override to support this)
        dstring text() const
        {
            return "";
        }
        /// ditto
        Widget text(dstring s)
        {
            return this;
        }
    }

    /// Override to handle font changes
    protected void handleFontChanged()
    {
    }

    //===============================================================
    // Layout and drawing related properties/methods

    @property
    {
        /// Returns true if layout is required for widget and its children
        bool needLayout() const { return _needLayout; }
        /// Returns true if redraw is required for widget and its children
        bool needDraw() const
        {
            // we need to be sure that the style is updated
            // it might set _needDraw or _needLayout flag
            updateStyles();
            return _needDraw;
        }
        /// Returns true is widget is being animated - need to call animate() and redraw
        bool animating() const
        {
            return animations.length > 0;
        }

        /// Check whether the widget can make transition for a property
        bool hasTransitionFor(string property) const
        {
            if (_transitionTimingFunction is null || _transitionDuration <= 0)
                return false;
            if (_transitionProperty == "all" || _transitionProperty == property)
                return true;

            if (_transitionProperty == "margin")
                return property == "margin-top" || property == "margin-right" ||
                       property == "margin-bottom" || property == "margin-left";

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
        /// Experimental API
        protected auto transitionDuration() const { return _transitionDuration; }
        /// Experimental API
        protected auto transitionTimingFunction() const { return _transitionTimingFunction; }
        /// Experimental API
        protected auto transitionDelay() const { return _transitionDelay; }

        /// Get current widget box in pixels (computed and set in layout())
        ref const(Box) box() const { return _box; }
        /// Set widget box value and indicate that layout process is done (for usage in subclass layout())
        final protected void box(ref Box b)
        {
            _box = b;
            _needLayout = false;
        }

        /// Widget hard width (SIZE_UNSPECIFIED if not set)
        int width() const
        {
            updateStyles();
            return _width.toDevice;
        }
        /// ditto
        Widget width(Dimension value)
        {
            setProperty!"_width" = value;
            return this;
        }
        /// ditto
        Widget width(int value)
        {
            return width = Dimension(value);
        }
        /// Widget hard height (SIZE_UNSPECIFIED if not set)
        int height() const
        {
            updateStyles();
            return _height.toDevice;
        }
        /// ditto
        Widget height(Dimension value)
        {
            setProperty!"_height" = value;
            return this;
        }
        /// ditto
        Widget height(int value)
        {
            return height = Dimension(value);
        }
        /// Min width style constraint (0, Dimension.zero or Dimension.none for no constraint)
        int minWidth() const
        {
            updateStyles();
            return _minWidth.toDevice;
        }
        /// ditto
        Widget minWidth(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.zero;
            setProperty!"_minWidth" = value;
            return this;
        }
        /// ditto
        Widget minWidth(int value) // TODO: clamp
        {
            return minWidth = Dimension(value);
        }
        /// Max width style constraint (SIZE_UNSPECIFIED or Dimension.none if no constraint)
        int maxWidth() const
        {
            updateStyles();
            return _maxWidth.toDevice;
        }
        /// ditto
        Widget maxWidth(Dimension value)
        {
            setProperty!"_maxWidth" = value;
            return this;
        }
        /// ditto
        Widget maxWidth(int value)
        {
            return maxWidth = Dimension(value);
        }
        /// Min height style constraint (0, Dimension.zero or Dimension.none for no constraint)
        int minHeight() const
        {
            updateStyles();
            return _minHeight.toDevice;
        }
        /// ditto
        Widget minHeight(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.zero;
            setProperty!"_minHeight" = value;
            return this;
        }
        /// ditto
        Widget minHeight(int value)
        {
            return minHeight = Dimension(value);
        }
        /// Max height style constraint (SIZE_UNSPECIFIED or Dimension.none if no constraint)
        int maxHeight() const
        {
            updateStyles();
            return _maxHeight.toDevice;
        }
        /// ditto
        Widget maxHeight(Dimension value)
        {
            setProperty!"_maxHeight" = value;
            return this;
        }
        /// ditto
        Widget maxHeight(int value)
        {
            return maxHeight = Dimension(value);
        }
        /// Layout weight (while resizing to fill parent, widget will be resized proportionally to this value)
        int layoutWeight() const
        {
            return 0;
        }
        /// ditto
        Widget layoutWeight(int value)
        {
            return this;
        }

        /// Widget visibility (visible, invisible, gone)
        Visibility visibility() const { return _visibility; }
        /// ditto
        Widget visibility(Visibility newVisibility)
        {
            if (_visibility != newVisibility)
            {
                if (_visibility == Visibility.gone || newVisibility == Visibility.gone)
                {
                    if (parent)
                        parent.requestLayout();
                    else
                        requestLayout();
                }
                else
                    invalidate();
                _visibility = newVisibility;
            }
            return this;
        }
    }

    /// Experimental API
    protected bool hasAnimation(string name)
    {
        return (name in animations) !is null;
    }
    /// Experimental API
    protected void addAnimation(string name, long duration, void delegate(double) handler)
    {
        assert(name && duration > 0 && handler);
        animations[name] = Animation(duration * ONE_SECOND / 1000, handler);
    }
    /// Experimental API
    protected void cancelAnimation(string name)
    {
        animations.remove(name);
    }

    /// Animate widget; interval is time left from previous draw, in hnsecs (1/10000000 of second)
    void animate(long interval)
    {
        bool someAnimationsFinished;
        foreach (ref a; animations)
        {
            if (!a.isAnimating)
            {
                a.start();
            }
            else
            {
                a.tick(interval);
                if (!a.isAnimating)
                {
                    a.handler = null;
                    someAnimationsFinished = true;
                }
            }
        }
        if (someAnimationsFinished)
        {
            foreach (k, a; animations)
                if (a.handler is null)
                    animations.remove(k);
        }
    }

    /// Returns true if point is inside of this widget
    bool isPointInside(int x, int y)
    {
        return _box.isPointInside(x, y);
    }

    //===============================================================
    // State related properties and methods

    private
    {
        bool _clickable;
        bool _checkable;
        bool _checked;
        bool _focusable;
    }

    @property
    {
        /// True if state has State.enabled flag set
        bool enabled() const
        {
            return (state & State.enabled) != 0;
        }
        /// ditto
        Widget enabled(bool flag)
        {
            flag ? setState(State.enabled) : resetState(State.enabled);
            return this;
        }

        /// When true, user can click this control, and signals `clicked`
        bool clickable() const { return _clickable; }
        /// ditto
        Widget clickable(bool flag)
        {
            _clickable = flag;
            return this;
        }

        bool canClick() const
        {
            return _clickable && enabled && visible;
        }

        /// When true, control supports `checked` state
        bool checkable() const { return _checkable; }
        /// ditto
        Widget checkable(bool flag)
        {
            _checkable = flag;
            return this;
        }

        bool canCheck() const
        {
            return _checkable && enabled && visible;
        }

        /// Checked state
        bool checked() const
        {
            return (state & State.checked) != 0;
        }
        /// ditto
        Widget checked(bool flag)
        {
            if (flag != checked)
            {
                if (flag)
                    setState(State.checked);
                else
                    resetState(State.checked);
                invalidate();
            }
            return this;
        }

        /// Whether widget can be focused
        bool focusable() const { return _focusable; }
        /// ditto
        Widget focusable(bool flag)
        {
            _focusable = flag;
            return this;
        }

        bool focused() const
        {
            return (window !is null && window.focusedWidget is this && (state & State.focused));
        }

        /// Mouse movement processing flag (when true, widget will change `hover` state while mouse is moving)
        bool trackHover() const
        {
            return _trackHover && !TOUCH_MODE;
        }
        /// ditto
        Widget trackHover(bool v)
        {
            _trackHover = v;
            return this;
        }

        /// Override and return true to track key events even when not focused
        bool wantsKeyTracking() const
        {
            return false;
        }
    }

    void requestActionsUpdate() // TODO
    {
    }

    /// Returns mouse cursor type for widget
    CursorType getCursorType(int x, int y)
    {
        return CursorType.arrow;
    }

    //===============================================================
    // Tooltips

    private dstring _tooltipText;
    /// Tooltip text - when not empty, widget will show tooltips automatically.
    /// For advanced tooltips - override hasTooltip and createTooltip methods.
    @property dstring tooltipText() { return _tooltipText; }
    /// ditto
    @property Widget tooltipText(dstring text)
    {
        _tooltipText = text;
        return this;
    }
    /// Returns true if widget has tooltip to show
    @property bool hasTooltip()
    {
        return tooltipText.length > 0;
    }

    /**
    Will be called from window once tooltip request timer expired.

    If null is returned, popup will not be shown; you can change alignment and position of popup here.
    */
    Widget createTooltip(int mouseX, int mouseY, ref PopupAlign alignment, ref int x, ref int y)
    {
        // default implementation supports tooltips when tooltipText property is set
        import beamui.widgets.text;

        return _tooltipText ? new Label(_tooltipText).id("tooltip") : null;
    }

    /// Schedule tooltip
    void scheduleTooltip(long delay = 300, PopupAlign alignment = PopupAlign.point,
                         int x = int.min, int y = int.min)
    {
        if (auto w = window)
            w.scheduleTooltip(weakRef(this), delay, alignment, x, y);
    }

    //===============================================================
    // About focus

    private bool _focusGroup;
    /**
    Focus group flag for container widget.

    When focus group is set for some parent widget, focus from one of containing widgets can be moved
    using keyboard only to one of other widgets containing in it and cannot bypass bounds of focusGroup.
    If focused widget doesn't have any parent with focusGroup == true,
    focus may be moved to any focusable within window.
    */
    @property bool focusGroup() { return _focusGroup; }
    /// ditto
    @property Widget focusGroup(bool flag)
    {
        _focusGroup = flag;
        return this;
    }

    @property bool focusGroupFocused() const
    {
        Widget w = focusGroupWidget();
        return (w._state & State.windowFocused) != 0;
    }

    protected bool setWindowFocusedFlag(bool flag)
    {
        if (flag)
        {
            if ((_state & State.windowFocused) == 0)
            {
                _state |= State.windowFocused;
                invalidate();
                return true;
            }
        }
        else
        {
            if ((_state & State.windowFocused) != 0)
            {
                _state &= ~State.windowFocused;
                invalidate();
                return true;
            }
        }
        return false;
    }

    @property Widget focusGroupFocused(bool flag)
    {
        Widget w = focusGroupWidget();
        w.setWindowFocusedFlag(flag);
        while (w.parent)
        {
            w = w.parent;
            if (w.parent is null || w.focusGroup)
            {
                w.setWindowFocusedFlag(flag);
            }
        }
        return this;
    }

    /// Find nearest parent of this widget with focusGroup flag, returns topmost parent if no focusGroup flag set to any of parents.
    Widget focusGroupWidget() inout
    {
        Widget p = cast(Widget)this;
        while (p)
        {
            if (!p.parent || p.focusGroup)
                break;
            p = p.parent;
        }
        return p;
    }

    private static class TabOrderInfo
    {
        Widget widget;
        uint tabOrder;
        uint childOrder;
        Box box;

        this(Widget widget)
        {
            this.widget = widget;
            this.tabOrder = widget.thisOrParentTabOrder();
            this.box = widget.box;
        }

        static if (BACKEND_GUI)
        {
            static enum NEAR_THRESHOLD = 10;
        }
        else
        {
            static enum NEAR_THRESHOLD = 1;
        }
        bool nearX(TabOrderInfo v)
        {
            return box.x - NEAR_THRESHOLD <= v.box.x && v.box.x <= box.x + NEAR_THRESHOLD;
        }

        bool nearY(TabOrderInfo v)
        {
            return box.y - NEAR_THRESHOLD <= v.box.y && v.box.y <= box.y + NEAR_THRESHOLD;
        }

        override int opCmp(Object obj) const
        {
            TabOrderInfo v = cast(TabOrderInfo)obj;
            if (tabOrder != 0 && v.tabOrder != 0)
            {
                if (tabOrder < v.tabOrder)
                    return -1;
                if (tabOrder > v.tabOrder)
                    return 1;
            }
            // place items with tabOrder 0 after items with tabOrder non-0
            if (tabOrder != 0)
                return -1;
            if (v.tabOrder != 0)
                return 1;
            if (childOrder < v.childOrder)
                return -1;
            if (childOrder > v.childOrder)
                return 1;
            return 0;
        }
        /// Less predicate for Left/Right sorting
        static bool lessHorizontal(TabOrderInfo obj1, TabOrderInfo obj2)
        {
            if (obj1.nearY(obj2))
                return obj1.box.x < obj2.box.x;
            else
                return obj1.box.y < obj2.box.y;
        }
        /// Less predicate for Up/Down sorting
        static bool lessVertical(TabOrderInfo obj1, TabOrderInfo obj2)
        {
            if (obj1.nearX(obj2))
                return obj1.box.y < obj2.box.y;
            else
                return obj1.box.x < obj2.box.x;
        }

        override string toString() const
        {
            return widget.id;
        }
    }

    private void findFocusableChildren(ref TabOrderInfo[] results, Rect clipRect, Widget currentWidget)
    {
        if (visibility != Visibility.visible)
            return;
        Box b = _box;
        applyPadding(b);
        Rect rc = b;
        if (!rc.intersects(clipRect))
            return; // out of clip rectangle
        if (canFocus || this is currentWidget)
        {
            results ~= new TabOrderInfo(this);
            return;
        }
        rc.intersect(clipRect);
        foreach (i; 0 .. childCount)
        {
            child(i).findFocusableChildren(results, rc, currentWidget);
        }
    }

    /// Find all focusables belonging to the same focusGroup as this widget (does not include current widget).
    /// Usually to be called for focused widget to get possible alternatives to navigate to
    private TabOrderInfo[] findFocusables(Widget currentWidget)
    {
        TabOrderInfo[] result;
        Widget group = focusGroupWidget();
        group.findFocusableChildren(result, Rect(group.box), currentWidget);
        for (ushort i = 0; i < result.length; i++)
            result[i].childOrder = i + 1;
        sort(result);
        return result;
    }

    private ushort _tabOrder;
    /// Tab order - hint for focus movement using Tab/Shift+Tab
    @property ushort tabOrder() { return _tabOrder; }
    /// ditto
    @property Widget tabOrder(ushort tabOrder)
    {
        _tabOrder = tabOrder;
        return this;
    }

    private int thisOrParentTabOrder()
    {
        if (_tabOrder)
            return _tabOrder;
        if (!parent)
            return 0;
        return parent.thisOrParentTabOrder;
    }

    /// Call on focused widget, to find best
    private Widget findNextFocusWidget(FocusMovement direction)
    {
        if (direction == FocusMovement.none)
            return this;
        TabOrderInfo[] focusables = findFocusables(this);
        if (!focusables.length)
            return null;
        int myIndex = -1;
        for (int i = 0; i < focusables.length; i++)
        {
            if (focusables[i].widget is this)
            {
                myIndex = i;
                break;
            }
        }
        debug (focus)
            Log.d("findNextFocusWidget myIndex=", myIndex, " of focusables: ", focusables);
        if (myIndex == -1)
            return null; // not found myself
        if (focusables.length == 1)
            return focusables[0].widget; // single option - use it
        if (direction == FocusMovement.next)
        {
            // move forward
            int index = myIndex + 1;
            if (index >= focusables.length)
                index = 0;
            return focusables[index].widget;
        }
        else if (direction == FocusMovement.previous)
        {
            // move back
            int index = myIndex - 1;
            if (index < 0)
                index = cast(int)focusables.length - 1;
            return focusables[index].widget;
        }
        else
        {
            // Left, Right, Up, Down
            if (direction == FocusMovement.left || direction == FocusMovement.right)
            {
                sort!(TabOrderInfo.lessHorizontal)(focusables);
            }
            else
            {
                sort!(TabOrderInfo.lessVertical)(focusables);
            }
            myIndex = 0;
            for (int i = 0; i < focusables.length; i++)
            {
                if (focusables[i].widget is this)
                {
                    myIndex = i;
                    break;
                }
            }
            int index = myIndex;
            if (direction == FocusMovement.left || direction == FocusMovement.up)
            {
                index--;
                if (index < 0)
                    index = cast(int)focusables.length - 1;
            }
            else
            {
                index++;
                if (index >= focusables.length)
                    index = 0;
            }
            return focusables[index].widget;
        }
    }

    bool handleMoveFocusUsingKeys(KeyEvent event)
    {
        if (!focused || !visible)
            return false;
        if (event.action != KeyAction.keyDown)
            return false;
        FocusMovement direction = FocusMovement.none;
        uint flags = event.flags & (KeyFlag.shift | KeyFlag.control | KeyFlag.alt);
        switch (event.keyCode) with (KeyCode)
        {
        case left:
            if (flags == 0)
                direction = FocusMovement.left;
            break;
        case right:
            if (flags == 0)
                direction = FocusMovement.right;
            break;
        case up:
            if (flags == 0)
                direction = FocusMovement.up;
            break;
        case down:
            if (flags == 0)
                direction = FocusMovement.down;
            break;
        case tab:
            if (flags == 0)
                direction = FocusMovement.next;
            else if (flags == KeyFlag.shift)
                direction = FocusMovement.previous;
            break;
        default:
            break;
        }
        if (direction == FocusMovement.none)
            return false;
        Widget nextWidget = findNextFocusWidget(direction);
        if (!nextWidget)
            return false;
        nextWidget.setFocus(FocusReason.tabFocus);
        return true;
    }

    /// Returns true if this widget and all its parents are visible
    @property bool visible() const
    {
        if (visibility != Visibility.visible)
            return false;
        if (parent is null)
            return true;
        return parent.visible;
    }

    /// Returns true if widget is focusable and visible and enabled
    @property bool canFocus() const
    {
        return focusable && visible && enabled;
    }

    /// Set focus to this widget or suitable focusable child, returns previously focused widget
    Widget setFocus(FocusReason reason = FocusReason.unspecified)
    {
        if (window is null)
            return null;
        if (!visible)
            return window.focusedWidget;
        invalidate();
        if (!canFocus)
        {
            Widget w = findFocusableChild(true);
            if (!w)
                w = findFocusableChild(false);
            if (w)
                return window.setFocus(weakRef(w), reason);
            // try to find focusable child
            return window.focusedWidget;
        }
        return window.setFocus(weakRef(this), reason);
    }
    /// Search children for first focusable item, returns null if not found
    Widget findFocusableChild(bool defaultOnly)
    {
        foreach (i; 0 .. childCount)
        {
            Widget w = child(i);
            if (w.canFocus && (!defaultOnly || (w.state & State.default_) != 0))
                return w;
            w = w.findFocusableChild(defaultOnly);
            if (w !is null)
                return w;
        }
        if (canFocus)
            return this;
        return null;
    }

    //===============================================================
    // Signals

    /// On click event listener
    Signal!(void delegate(Widget)) clicked;

    /// Checked state change event listener
    Signal!(void delegate(Widget, bool)) checkChanged;

    /// Focus state change event listener
    Signal!(void delegate(Widget, bool)) focusChanged;

    /// Key event listener, must return true if event is processed by handler
    Signal!(bool delegate(Widget, KeyEvent)) keyEvent;

    /// Mouse event listener, must return true if event is processed by handler
    Signal!(bool delegate(Widget, MouseEvent)) mouseEvent;

    //===============================================================
    // Events

    /// Called to process click and notify listeners
    protected void handleClick()
    {
        if (clicked.assigned)
            clicked(this);
    }

    /// Set new timer to call a delegate after specified interval (for recurred notifications, return true from the handler)
    /// Note: This function will safely cancel the timer if widget is destroyed.
    ulong setTimer(long intervalMillis, bool delegate() handler)
    {
        if (auto w = window)
        {
            bool* destroyed = _isDestroyed;
            return w.setTimer(intervalMillis, {
                // cancel timer on widget destruction
                return !(*destroyed) ? handler() : false;
            });
        }
        return 0; // no window - no timer
    }

    /// Cancel timer - pass value returned from setTimer() as timerID parameter
    void cancelTimer(ulong timerID)
    {
        if (auto w = window)
            w.cancelTimer(timerID);
    }

    /// Process key event, return true if event is processed
    bool onKeyEvent(KeyEvent event)
    {
        if (keyEvent.assigned && keyEvent(this, event))
            return true; // processed by external handler
        // handle focus navigation using keys
        if (focused && handleMoveFocusUsingKeys(event))
            return true;
        if (canClick)
        {
            // support onClick event initiated by Space or Return keys
            if (event.keyCode == KeyCode.space || event.keyCode == KeyCode.enter)
            {
                if (event.action == KeyAction.keyDown)
                {
                    setState(State.pressed);
                    return true;
                }
                if (event.action == KeyAction.keyUp)
                {
                    if (state & State.pressed)
                    {
                        resetState(State.pressed);
                        handleClick();
                    }
                    return true;
                }
            }
        }
        return false;
    }

    /// Process mouse event; return true if event is processed by widget.
    bool onMouseEvent(MouseEvent event)
    {
        if (mouseEvent.assigned && mouseEvent(this, event))
            return true; // processed by external handler
        debug (mouse)
            Log.fd("onMouseEvent '%s': %s  (%s, %s)", id, event.action, event.x, event.y);
        // support click
        if (canClick)
        {
            if (event.button == MouseButton.left)
            {
                if (event.action == MouseAction.buttonDown)
                {
                    setState(State.pressed);
                    if (canFocus)
                        setFocus();
                    return true;
                }
                if (event.action == MouseAction.buttonUp)
                {
                    if (state & State.pressed)
                    {
                        resetState(State.pressed);
                        handleClick();
                    }
                    return true;
                }
            }
            if (event.action == MouseAction.focusIn)
            {
                setState(State.pressed);
                return true;
            }
            if (event.action == MouseAction.focusOut)
            {
                resetState(State.pressed);
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                resetState(State.pressed);
                resetState(State.hovered);
                return true;
            }
        }
        if (event.action == MouseAction.move && !event.hasModifiers && hasTooltip)
        {
            scheduleTooltip(200);
        }
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.right)
        {
            if (canShowPopupMenu(event.x, event.y))
            {
                if (canFocus)
                    setFocus();
                showPopupMenu(event.x, event.y);
                return true;
            }
        }
        if (canFocus && event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            setFocus();
            return true;
        }
        if (trackHover)
        {
            if (event.action == MouseAction.focusOut || event.action == MouseAction.cancel)
            {
                if ((state & State.hovered))
                {
                    debug (mouse)
                        Log.d("Hover off ", id);
                    resetState(State.hovered);
                }
                return true;
            }
            if (event.action == MouseAction.move)
            {
                if (!(state & State.hovered))
                {
                    debug (mouse)
                        Log.d("Hover ", id);
                    if (!TOUCH_MODE)
                        setState(State.hovered);
                }
                return true;
            }
            if (event.action == MouseAction.leave)
            {
                debug (mouse)
                    Log.d("Leave ", id);
                resetState(State.hovered);
                return true;
            }
        }
        return false;
    }

    /// Handle custom event
    bool onEvent(CustomEvent event)
    {
        if (auto runnable = cast(RunnableEvent)event)
        {
            // handle runnable
            runnable.run();
            return true;
        }
        // override to handle more events
        return false;
    }

    /// Execute delegate later in UI thread if this widget will be still available (can be used to modify UI from background thread, or just to postpone execution of action)
    void executeInUiThread(void delegate() runnable)
    {
        if (!window)
            return;
        auto event = new RunnableEvent(CUSTOM_RUNNABLE, weakRef(this), runnable);
        window.postEvent(event);
    }

    //===============================================================
    // Layout, measurement, drawing methods

    /// Request relayout of widget and its children
    void requestLayout()
    {
        _needLayout = true;
    }
    /// Cancel relayout of widget
    void cancelLayout()
    {
        _needLayout = false;
    }
    /// Request redraw
    void invalidate()
    {
        _needDraw = true;
    }
    /// Indicate that drawing is done
    protected void drawn()
    {
        _needDraw = false;
    }

    /// Measure widget - compute minimal, natural and maximal sizes for the widget
    Boundaries computeBoundaries()
    out (result)
    {
        assert(result.max.w >= result.nat.w && result.nat.w >= result.min.w);
        assert(result.max.h >= result.nat.h && result.nat.h >= result.min.h);
    }
    body
    {
        auto bs = Boundaries(computeMinSize, computeNaturalSize, computeMaxSize);
        applyStyle(bs);
        return bs;
    }

    /// Calculate minimum size of widget content
    Size computeMinSize()
    {
        return Size(0, 0);
    }

    /// Calculate natural (preferred) size of widget content
    Size computeNaturalSize()
    {
        return Size(0, 0);
    }

    /// Calculate maximum size of widget content
    Size computeMaxSize()
    {
        return Size.none;
    }

    /// Helper function: apply padding and min-max style properties to boundaries
    protected void applyStyle(ref Boundaries bs)
    {
        Size p = padding.size;
        bs.min.w = max(bs.min.w, minWidth);
        bs.min.h = max(bs.min.h, minHeight);
        bs.max.w = max(min(bs.max.w + p.w, maxWidth), bs.min.w);
        bs.max.h = max(min(bs.max.h + p.h, maxHeight), bs.min.h);
        bs.nat.w = clamp(bs.nat.w + p.w, bs.min.w, bs.max.w);
        bs.nat.h = clamp(bs.nat.h + p.h, bs.min.h, bs.max.h);
    }

    bool widthDependsOnHeight;
    bool heightDependsOnWidth;

    int heightForWidth(int width) // TODO: add `in` contract with assert(heightDependsOnWidth) to all overriden methods?
    {
        return 0;
    }

    int widthForHeight(int height)
    {
        return 0;
    }

    /// Set widget box and lay out widget contents
    void layout(Box geometry)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        _box = geometry;
    }

    /// Draw widget at its position to a buffer
    void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        Box b = _box;
        auto saver = ClipRectSaver(buf, b, alpha);

        auto bg = background;
        bg.drawTo(buf, b);

        if (state & State.focused)
        {
            drawFocusRect(buf);
        }
        _needDraw = false;
    }

    /// Draw focus rectangle, if enabled in styles
    void drawFocusRect(DrawBuf buf)
    {
        Color[1] cs = [focusRectColor];
        if (cs[0] != Color.transparent)
        {
            Box b = _box;
            b.shrink(Insets(FOCUS_RECT_PADDING));
            buf.drawFocusRect(Rect(b), cs);
        }
    }

    /// Helper function: applies padding to a box
    void applyPadding(ref Box b)
    {
        b.shrink(padding);
    }

    /// Applies alignment to a box for content of size `sz`
    static void applyAlign(ref Box b, Size sz, Align ha, Align va) // TODO: unittest
    {
        if (ha == Align.right)
        {
            b.x += b.w - sz.w;
            b.w = sz.w;
        }
        else if (ha == Align.hcenter)
        {
            int dx = (b.w - sz.w) / 2;
            b.x += dx;
            b.w = sz.w;
        }
        else
        {
            b.w = sz.w;
        }
        if (va == Align.bottom)
        {
            b.y += b.h - sz.h;
            b.h = sz.h;
        }
        else if (va == Align.vcenter)
        {
            int dy = (b.h - sz.h) / 2;
            b.y += dy;
            b.h = sz.h;
        }
        else
        {
            b.h = sz.h;
        }
    }

    //===============================================================
    // Popup (contextual) menu support

    private Menu _popupMenu;
    /// Popup (contextual menu), associated with this widget
    @property Menu popupMenu() { return _popupMenu; }
    /// ditto
    @property Widget popupMenu(Menu popupMenu)
    {
        _popupMenu = popupMenu;
        return this;
    }

    /// Returns true if widget can show popup menu (e.g. by mouse right click at point x,y)
    bool canShowPopupMenu(int x, int y)
    {
        if (_popupMenu is null)
            return false;
        if (_popupMenu.openingSubmenu.assigned)
            if (!_popupMenu.openingSubmenu(_popupMenu))
                return false;
        return true;
    }
    /// Shows popup menu at (x,y)
    void showPopupMenu(int x, int y)
    {
        // if preparation signal handler assigned, call it; don't show popup if false is returned from handler
        if (_popupMenu.openingSubmenu.assigned)
            if (!_popupMenu.openingSubmenu(_popupMenu))
                return;

        import beamui.widgets.popup;

        auto popup = window.showPopup(_popupMenu, weakRef(this), PopupAlign.point | PopupAlign.right, x, y);
        popup.ownContent = false;
    }

    //===============================================================
    // Widget hierarhy methods

    /// Returns number of children of this widget
    @property int childCount() const
    {
        return 0;
    }
    /// Returns child by index
    inout(Widget) child(int index) inout
    {
        return null;
    }
    /// Add child, returns added item
    Widget addChild(Widget item)
    {
        assert(false, "addChild: this widget does not support having children");
    }
    /// Add child, returns added item
    Widget addChildren(Widget[] items)
    {
        foreach (item; items)
        {
            addChild(item);
        }
        return this;
    }
    /// Insert child before given index, returns inserted item
    Widget insertChild(int index, Widget item)
    {
        assert(false, "insertChild: this widget does not support having children");
    }
    /// Remove child by index, returns removed item
    Widget removeChild(int index)
    {
        assert(false, "removeChild: this widget does not support having children");
    }
    /// Remove child by ID, returns removed item
    Widget removeChild(string id)
    {
        assert(false, "removeChild: this widget does not support having children");
    }
    /// Remove child, returns removed item
    Widget removeChild(Widget child)
    {
        assert(false, "removeChild: this widget does not support having children");
    }
    /// Remove all children and optionally destroy them
    void removeAllChildren(bool destroyThem = true)
    {
        // override
    }
    /// Returns index of widget in child list, -1 if there is no child with this ID
    int childIndex(string id)
    {
        return -1;
    }
    /// Returns index of widget in child list, -1 if passed widget is not a child of this widget
    int childIndex(Widget item)
    {
        return -1;
    }

    /// Returns true if item is child of this widget (when deepSearch == true - returns true if item is this widget or one of children inside children tree).
    bool isChild(Widget item, bool deepSearch = true)
    {
        if (deepSearch)
        {
            // this widget or some widget inside children tree
            if (item is this)
                return true;
            foreach (i; 0 .. childCount)
            {
                if (child(i).isChild(item))
                    return true;
            }
        }
        else
        {
            // only one of children
            foreach (i; 0 .. childCount)
            {
                if (item is child(i))
                    return true;
            }
        }
        return false;
    }

    /// Find child of specified type T by id, returns null if not found or cannot be converted to type T
    T childByID(T = typeof(this))(string id, bool deepSearch = true)
    {
        if (deepSearch)
        {
            // search everywhere inside child tree
            if (compareID(id))
            {
                T found = cast(T)this;
                if (found)
                    return found;
            }
            // lookup children
            for (int i = childCount - 1; i >= 0; i--)
            {
                Widget res = child(i).childByID(id);
                if (res !is null)
                {
                    T found = cast(T)res;
                    if (found)
                        return found;
                }
            }
        }
        else
        {
            // search only across children of this widget
            for (int i = childCount - 1; i >= 0; i--)
            {
                Widget w = child(i);
                if (id == w.id)
                {
                    T found = cast(T)w;
                    if (found)
                        return found;
                }
            }
        }
        // not found
        return null;
    }

    /// Parent widget, null for top level widget
    @property Widget parent() const
    {
        return _parent ? cast(Widget)_parent : null;
    }
    /// ditto
    @property Widget parent(Widget parent)
    {
        _parent = parent;
        return this;
    }
    /// Returns window (if widget or its parent is attached to window)
    @property Window window() const
    {
        Widget p = cast(Widget)this;
        while (p !is null)
        {
            if (p._window !is null)
                return cast(Window)p._window;
            p = p.parent;
        }
        return null;
    }
    /// Set window (to be used for top level widget from Window implementation).
    package(beamui) @property void window(Window window)
    {
        _window = window;
    }

    //===============================================================
    // ML Loader support

    /// Set string property value, for ML loaders
    bool setStringProperty(string name, string value)
    {
        mixin(generatePropertySetters("id", "backgroundColor", "textColor", "fontFace"));
        if (name == "text")
        {
            text = tr(value);
            return true;
        }
        if (name == "tooltipText")
        {
            tooltipText = tr(value);
            return true;
        }
        return false;
    }

    /// Set dstring property value, for ML loaders
    bool setDstringProperty(string name, dstring value)
    {
        if (name == "text")
        {
            text = value;
            return true;
        }
        if (name == "tooltipText")
        {
            tooltipText = value;
            return true;
        }
        return false;
    }

    /// StringListValue list values
    bool setStringListValueListProperty(string propName, StringListValue[] values)
    {
        return false;
    }

    /// Set bool property value, for ML loaders
    bool setBoolProperty(string name, bool value)
    {
        mixin(generatePropertySetters("enabled", "clickable", "checkable", "focusable", "checked", "fontItalic"));
        return false;
    }

    /// Set double property value, for ML loaders
    bool setDoubleProperty(string name, double value)
    {
        if (name == "alpha")
        {
            int n = cast(int)(value * 255);
            return setIntProperty(name, n);
        }
        return false;
    }

    /// Set int property value, for ML loaders
    bool setIntProperty(string name, int value)
    {
        mixin(generatePropertySetters("width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
                "layoutWeight", "textColor", "backgroundColor", "fontSize"));
        if (name == "alpha")
        {
            alpha = cast(ubyte)clamp(value, 0, 255);
            return true;
        }
        if (name == "padding")
        { // use same value for all sides
            padding = Insets(value);
            return true;
        }
        return false;
    }

    /// Set Insets property value, for ML loaders
    bool setInsetsProperty(string name, Insets value)
    {
        mixin(generatePropertySetters("padding"));
        return false;
    }
}

/// Widget list holder
alias WidgetList = Collection!(Widget, true);

/**
    Base class for widgets which have children.

    Added children will correctly handle destruction of parent widget and theme change.

    If your widget has subwidgets which do not need to catch mouse and key events, focus, etc,
    you may not use this class. You may inherit directly from the Widget class
    and add code for subwidgets to destructor, onThemeChanged, and onDraw (if needed).
*/
class WidgetGroup : Widget
{
    /// Empty parameter list constructor - for usage by factory
    this()
    {
        super(null);
    }
    /// Create with ID parameter
    this(string ID)
    {
        super(ID);
    }

    private WidgetList _children;

    override @property int childCount() const
    {
        return cast(int)_children.count;
    }

    override inout(Widget) child(int index) inout
    {
        return _children[index];
    }

    override Widget addChild(Widget item)
    {
        assert(item !is null, "Widget must exist");
        _children.append(item);
        return item.parent(this);
    }

    override Widget insertChild(int index, Widget item)
    {
        assert(item !is null, "Widget must exist");
        _children.insert(index, item);
        return item.parent(this);
    }

    override Widget removeChild(int index)
    {
        Widget result = _children.remove(index);
        assert(result !is null);
        result.parent = null;
        return result;
    }

    override Widget removeChild(string id)
    {
        int index = cast(int)_children.indexOf(id);
        if (index < 0)
            return null;
        return removeChild(index);
    }

    override Widget removeChild(Widget child)
    {
        int index = cast(int)_children.indexOf(child);
        if (index < 0)
            return null;
        return removeChild(index);
    }

    override void removeAllChildren(bool destroyThem = true)
    {
        _children.clear(destroyThem);
    }

    override int childIndex(string id)
    {
        return cast(int)_children.indexOf(id);
    }

    override int childIndex(Widget item)
    {
        return cast(int)_children.indexOf(item);
    }

    /// Replace one child with another. DOES NOT destroy the old item
    void replaceChild(Widget oldChild, Widget newChild)
    {
        assert(newChild !is null && oldChild !is null, "Widgets must exist");
        _children.replace(oldChild, newChild);
        oldChild.parent = null;
        newChild.parent = this;
    }
}

/// WidgetGroup with default drawing of children (just draw all children)
class WidgetGroupDefaultDrawing : WidgetGroup
{
    /// Empty parameter list constructor - for usage by factory
    this()
    {
        super(null);
    }
    /// Create with ID parameter
    this(string ID)
    {
        super(ID);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = _box;
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);
        foreach (widget; _children)
        {
            widget.onDraw(buf);
        }
    }
}

/// Helper for locating items in list, tree, table or other controls by typing their name
struct TextTypingShortcutHelper
{
    /// Expiration time for entered text; after timeout collected text will be cleared
    int timeoutMillis = 800;
    private long _lastUpdateTimeStamp;
    private dchar[] _text;

    /// Cancel text collection (next typed text will be collected from scratch)
    void cancel()
    {
        _text.length = 0;
        _lastUpdateTimeStamp = 0;
    }
    /// Returns collected text string - use it for lookup
    @property dstring text()
    {
        return _text.dup;
    }
    /// Pass key event here; returns true if search text is updated and you can move selection using it
    bool onKeyEvent(KeyEvent event)
    {
        long ts = currentTimeMillis;
        if (_lastUpdateTimeStamp && ts - _lastUpdateTimeStamp > timeoutMillis)
            cancel();
        if (event.action == KeyAction.text)
        {
            _text ~= event.text;
            _lastUpdateTimeStamp = ts;
            return _text.length > 0;
        }
        if (event.action == KeyAction.keyDown || event.action == KeyAction.keyUp)
        {
            switch (event.keyCode) with (KeyCode)
            {
            case left:
            case right:
            case up:
            case down:
            case home:
            case end:
            case tab:
            case pageUp:
            case pageDown:
            case backspace:
                cancel();
                break;
            default:
                break;
            }
        }
        return false;
    }

    /// Cancel text typing on some mouse events, if necessary
    void onMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.buttonUp || event.action == MouseAction.buttonDown)
            cancel();
    }
}

/// Helper to handle animation progress.
/// NOT USED
struct AnimationHelper
{
    private long _timeElapsed;
    private long _maxInterval;
    private int _maxProgress;

    /// Start new animation interval
    void start(long maxInterval, int maxProgress)
    {
        _timeElapsed = 0;
        _maxInterval = maxInterval;
        _maxProgress = maxProgress;
        assert(_maxInterval > 0);
        assert(_maxProgress > 0);
    }
    /// Adds elapsed time; returns animation progress in interval 0..maxProgress while timeElapsed is between 0 and maxInterval; when interval exceeded, progress is maxProgress
    int animate(long time)
    {
        _timeElapsed += time;
        return progress();
    }
    /// Restart with same max interval and progress
    void restart()
    {
        if (!_maxInterval)
        {
            _maxInterval = ONE_SECOND;
        }
        _timeElapsed = 0;
    }
    /// Returns time elapsed since start
    @property long elapsed()
    {
        return _timeElapsed;
    }
    /// Get current time interval
    @property long interval()
    {
        return _maxInterval;
    }
    /// Override current time interval, retaining the same progress %
    @property void interval(long newInterval)
    {
        int p = getProgress(10000);
        _maxInterval = newInterval;
        _timeElapsed = p * newInterval / 10000;
    }
    /// Returns animation progress in interval 0..maxProgress while timeElapsed is between 0 and maxInterval; when interval exceeded, progress is maxProgress
    @property int progress()
    {
        return getProgress(_maxProgress);
    }
    /// Returns animation progress in interval 0..maxProgress while timeElapsed is between 0 and maxInterval; when interval exceeded, progress is maxProgress
    int getProgress(int maxProgress)
    {
        if (finished)
            return maxProgress;
        if (_timeElapsed <= 0)
            return 0;
        return cast(int)(_timeElapsed * maxProgress / _maxInterval);
    }
    /// Returns true if animation is finished
    @property bool finished()
    {
        return _timeElapsed >= _maxInterval;
    }
}

mixin template SupportCSS(BaseClass = Widget)
{
    import beamui.style.style : Style;

    static if (is(typeof(this) == BaseClass))
    {
        /// Resolve style cascading and update all properties
        protected void recomputeStyle(Style[] chain)
        {
            recomputeStyleImpl(chain);
        }

        /// This is a bitmap that indicates which properties are overriden by the user
        private bool[string] ownProperties;

        protected void ownProperty(string name)
        {
            ownProperties[name] = true;
        }

        protected bool isOwned(string property)
        {
            return ownProperties.get(property, false);
        }
    }
    else
    {
        override protected void recomputeStyle(Style[] chain)
        {
            super.recomputeStyle(chain);
            recomputeStyleImpl(chain);
        }
    }

    private void recomputeStyleImpl(Style[] chain)
    {
        import std.array : split;
        import std.traits : getUDAs;

        alias This = typeof(this);

        // explode shorthands first
        static if (__traits(hasMember, This, "shorthandsForCSS"))
        {
            import std.meta : AliasSeq;

            alias shorthands = AliasSeq!(__traits(getAttributes, shorthandsForCSS));
            static if (shorthands.length > 0)
            {
                foreach_reverse (st; chain)
                {
                    static foreach (uda; shorthands)
                    {
                        st.explode!uda();
                    }
                }
            }
        }

        static if (is(This == struct))
        {
            static This def;
        }
        // iterate through all properties
        static foreach (field; This.tupleof)
        {{
            alias udas = getUDAs!(field, forCSS);
            static if (udas.length > 0) // filter out
            {
                enum var = split(field.stringof, '.')[$ - 1]; // this._smth -> _smth
                // do nothing if property is overriden
                if (!isOwned(var))
                {
                    // find nearest written property in style chain
                    bool set;
                    foreach_reverse (st; chain)
                    {
                        if (auto p = st.peek!(typeof(field), udas[0].specialType)(udas[0].name))
                        {
                            setProperty!var(*p, false);
                            set = true;
                            break;
                        }
                    }
                    if (!set)
                    {
                        // if nothing there - return value to its default
                        // there is segfault with struct initializers, so do it simpler with static struct
                        static if (!is(This == struct))
                        {
                            This def = cast(This)typeid(This).initializer.ptr;
                        }
                        setProperty!var(mixin("def." ~ var), false);
                    }
                }
            }
        }}
    }

    /// Set a property value, taking transitions into account
    private void setProperty(string var, T)(T value, bool fromOutside = true)
    {
        import std.meta : Alias;
        import std.traits : getUDAs, hasUDA, isMutable, isSomeFunction;

        alias field = Alias!(mixin(var));
        static assert(isMutable!(typeof(field)), "Should be a mutable field: " ~ var);
        static assert(!isSomeFunction!field, "Should be a field: " ~ var);
        static assert(hasUDA!(field, forCSS), "The field " ~ var ~ " is not for CSS");

        enum name = var[0] == '_' ? var[1 .. $] : var;
        enum sideEffectName = name ~ "_effect";
        enum bool hasSideEffects = __traits(hasMember, typeof(this), sideEffectName);
        static if (hasSideEffects)
        {
            enum s1 = sideEffectName ~ "(T.init)";
            enum s2 = sideEffectName ~ "(T.init, T.init)";
            enum bool effects1 = __traits(compiles, mixin(s1));
            enum bool effects2 = __traits(compiles, mixin(s2));
        }

        if (fromOutside)
            ownProperty(var);

        T current = field;

        // check animation
        static if (hasUDA!(field, animatable))
        {
            import beamui.core.animations : Animation, Transition;

            // do nothing if changed nothing
            if (current is value)
            {
                // cancel possible animation
                if (hasAnimation(var))
                    cancelAnimation(var);
                return;
            }

            string cssName = getUDAs!(field, forCSS)[0].name;
            if (hasTransitionFor(cssName))
            {
                auto tr = new Transition(transitionDuration,
                                         transitionTimingFunction,
                                         transitionDelay);
                addAnimation(var, tr.duration, delegate(double t) {
                        static if (hasSideEffects && effects2)
                            T old = field;
                        field = tr.mix(current, value, t);
                        static if (hasSideEffects)
                        {
                            static if (effects2)
                                mixin(sideEffectName ~ "(field, old);");
                            else static if (effects1)
                                mixin(sideEffectName ~ "(field);");
                            else
                                mixin(sideEffectName ~ "();");
                        }
                });
                return;
            }
        }
        if (current is value)
            return;
        // set it directly otherwise
        field = value;
        static if (hasSideEffects)
        {
            static if (effects2)
                mixin(sideEffectName ~ "(value, current);");
            else static if (effects1)
                mixin(sideEffectName ~ "(value);");
            else
                mixin(sideEffectName ~ "();");
        }
    }
}

/// Use in mixin to set this object property with name propName with value of variable value if variable name matches propName
string generatePropertySetter(string propName)
{
    return format(`
        if (name == "%s") { %s = value; return true; }
    `, propName, propName);
}

/// Use in mixin to set this object properties with names from parameter list with value of variable value if variable name matches propName
string generatePropertySetters(string[] propNames...)
{
    string res;
    foreach (propName; propNames)
        res ~= generatePropertySetter(propName);
    return res;
}

/// Use in mixin for method override to set this object properties with names from parameter list with value of variable value if variable name matches propName
string generatePropertySettersMethodOverride(string methodName, string typeName, string[] propNames...)
{
    string res = format(`
    override bool %s(string name, %s value)
    {
    `, methodName, typeName);
    foreach (propName; propNames)
        res ~= generatePropertySetter(propName);
    res ~= format(`
        return super.%s(name, value);
    }`, methodName);
    return res;
}

__gshared bool TOUCH_MODE = false;
