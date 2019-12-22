/**
Contains declaration of Widget class - base for all widgets.

Synopsis:
---
auto w = new Widget("id1");
// modify widget style
w.style.padding = 10;
w.style.backgroundColor = 0xAAAA00;
---

Copyright: Vadim Lopatin 2014-2018, Andrzej Kilijański 2017-2018, dayllenger 2018-2019
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

    import beamui.layout.alignment;

    import beamui.style.theme : currentTheme;

    import beamui.text.fonts;

    import beamui.widgets.popup : PopupAlign;
}
package import beamui.style.computed_style;
import beamui.core.animations;
import beamui.platforms.common.platform;
import beamui.style.style;
import beamui.style.types : Selector, TextFlag;
import beamui.text.style : TextHotkey;
import beamui.widgets.menu;

/// Widget visibility
enum Visibility : ubyte
{
    /// Visible on screen (default)
    visible,
    /// Not visible, but occupies a space in layout. Does not receive mouse or key events.
    hidden,
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

enum DependentSize
{
    none,
    width,
    height,
}

/// Base class for all widgets.
class Widget
{
private:
    /// Widget id
    string _id;

    /// Custom attributes map
    string[string] attributes;

    struct StyleSubItemInfo
    {
        const(Object) parent;
        string subName;
    }
    /// Structure needed when this widget is subitem of another
    StyleSubItemInfo* subInfo;
    /// If true, the style will be recomputed on next usage
    bool _needToRecomputeStyle = true;

    /// Widget state
    State _state = State.normal;
    /// Widget visibility: either visible, hidden, gone
    Visibility _visibility = Visibility.visible; // visible by default

    DependentSize _dependentSize;
    /// Current widget boundaries set by `measure`
    Boundaries _boundaries;
    /// Current widget box set by `layout`
    Box _box;
    /// Current box without padding and border
    Box _innerBox;
    /// True to force layout
    bool _needLayout = true;
    /// True to force redraw
    bool _needDraw = true;
    /// Parent widget
    Widget _parent;
    /// Window (to be used for top level widgets only!)
    Window _window;

    bool* _isDestroyed;

    ComputedStyle _style;

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
        _style.widget = this;
        _background = new Background;
        debug _instanceCount++;
        debug (resalloc)
            Log.fd("Created widget (count: %s): %s", _instanceCount, dbgname());
    }

    debug
    {
        private __gshared int _instanceCount;
        /// Number of created widget objects, not yet destroyed - for debug purposes
        static @property int instanceCount() { return _instanceCount; }
    }

    ~this()
    {
        debug _instanceCount--;
        debug (resalloc)
            Log.fd("Destroyed widget (count: %s): %s", _instanceCount, dbgname());
        debug if (APP_IS_SHUTTING_DOWN)
            onResourceDestroyWhileShutdown("widget", dbgname());

        animations.clear();

        _font.clear();
        eliminate(_background);

        eliminate(subInfo);
        eliminate(_popupMenu);
        if (_isDestroyed !is null)
            *_isDestroyed = true;
    }

    /// Flag for `WeakRef` that indicates widget destruction
    final @property const(bool*) isDestroyed() const
    {
        return _isDestroyed;
    }

    /// Pretty printed name for debugging purposes
    debug string dbgname() const
    {
        string s = getShortClassName(this);
        if (_id.length)
            s ~= '#' ~ id;
        if (subInfo)
            s ~= " as " ~ getShortClassName(subInfo.parent) ~ "::" ~ subInfo.subName;
        return s;
    }

    //===============================================================
    // Widget ID

    /// Widget id, `null` if not set
    @property string id() const { return _id; }
    /// ditto
    @property void id(string id)
    {
        if (_id != id)
        {
            _id = id;
            invalidateStyles();
        }
    }
    /// Chained version of `id`
    final Widget setID(string id)
    {
        this.id = id;
        return this;
    }
    /// Compare widget id with specified value, returns true if matches
    bool compareID(string id) const
    {
        return (_id !is null) && id == _id;
    }

    //===============================================================
    // State

    /// Widget state (set of flags from `State` enum)
    @property State state() const
    {
        if ((_state & State.parent) != 0 && _parent !is null)
            return _parent.state;
        if (focusGroupFocused)
            return _state | State.windowFocused; // TODO:
        return _state;
    }
    /// ditto
    @property void state(State newState)
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
                onFocusChange(false);
            }
            else if (!(oldState & State.focused) && (newState & State.focused))
            {
                handleFocusChange(true, cast(bool)(newState & State.keyboardFocused));
                onFocusChange(true);
            }
            // notify checked changes
            if ((oldState & State.checked) && !(newState & State.checked))
            {
                handleToggling(false);
                onToggle(false);
            }
            else if (!(oldState & State.checked) && (newState & State.checked))
            {
                handleToggling(true);
                onToggle(true);
            }
        }
    }
    /// Add state flags (set of flags from `State` enum). Returns new state
    State setState(State stateFlagsToSet)
    {
        State st = state | stateFlagsToSet;
        state = st;
        return st;
    }
    /// Remove state flags (set of flags from `State` enum). Returns new state
    State resetState(State stateFlagsToUnset)
    {
        State st = state & ~stateFlagsToUnset;
        state = st;
        return st;
    }

    /// Called to process focus changes before `onFocusChange` signal, override to do it
    protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
    }
    /// Called to process checked state changes before `onToggle` signal, override to do it
    protected void handleToggling(bool checked)
    {
    }

    //===============================================================
    // Attributes

    /** Returns a value of a custom attribute by its name, `null` if no such attribute.

        Note: the name must have non-zero length.
    */
    string getAttribute(string name) const
    {
        assert(name.length > 0);
        return attributes.get(name, null);
    }

    /// Returns true if the widget has a custom attribute of the `name`
    bool hasAttribute(string name) const
    {
        return (name in attributes) !is null;
    }

    /** Remove the custom attribute by `name` from the widget. Does nothing if no such attribute.

        Note: the name must have non-zero length.
    */
    void removeAttribute(string name)
    {
        assert(name.length > 0);
        if (attributes.remove(name))
            invalidateStyles();
    }

    /** Add a custom attribute of the `name` or change its value if already exists.

        Note: the name must have non-zero length.
    */
    void setAttribute(string name)
    {
        assert(name.length > 0);
        if (auto p = name in attributes)
        {
            if (*p) // if has some value - erase it
            {
                *p = null;
                invalidateStyles();
            }
        }
        else
        {
            attributes[name] = null;
            invalidateStyles();
        }
    }
    /// ditto
    void setAttribute(string name, string value)
    {
        assert(name.length > 0);
        if (auto p = name in attributes)
            *p = value;
        else
            attributes[name] = value;
        invalidateStyles();
    }

    /** Toggle a custom attribute on the widget - remove if present, add if not.

        Note: the name must have non-zero length.
    */
    void toggleAttribute(string name)
    {
        assert(name.length);
        if (!attributes.remove(name))
            attributes[name] = null;
        invalidateStyles();
    }

    //===============================================================
    // Style

    /// Set this widget to be a subitem in stylesheet
    void bindSubItem(const(Object) parent, string subName)
    {
        assert(parent && subName);
        subInfo = new StyleSubItemInfo(parent, subName);
        _needToRecomputeStyle = true;
    }

    /// Signals when styles are being recomputed. Used for mixing properties in the widget.
    Listener!(void delegate(Style[] chain)) onStyleUpdate;

    /// Computed style of this widget. Allows to query and mutate its properties
    final @property inout(ComputedStyle)* style() inout
    {
        updateStyles();
        return &_style;
    }

    /// Defines whether widget style is encapsulated, and cascading and inheritance
    /// in this subtree is independent from outer world
    final @property bool styleIsolated() const
    {
        return _style.isolated;
    }
    /// Enable style encapsulation, so cascading and inheritance
    /// in this subtree will become independent from outer world
    final void isolateStyle()
    {
        _style.isolated = true;
        invalidateStyles();
    }

    /// Recompute styles, only if needed
    protected void updateStyles() inout
    {
        if (_needToRecomputeStyle)
        {
            with (caching(this))
            {
                _needToRecomputeStyle = false;
                Style[] chain = selectStyleChain();
                // assume that style recomputation is purely depends on style chain
                // it may not change from previous update
                if (cast(size_t[])cachedChain[] != cast(size_t[])chain)
                {
                    // copy
                    cachedChain.clear();
                    cachedChain ~= chain;
                    // important: we cannot use shared array from `selectStyleChain` func
                    _style.recompute(cachedChain.unsafe_slice);
                }
                if (onStyleUpdate.assigned)
                    onStyleUpdate(cachedChain.unsafe_slice);
            }
        }
    }
    private Buf!Style cachedChain;

    /// Get a style chain for this widget from current theme, least specific styles first
    Style[] selectStyleChain()
    {
        static Buf!Style tmpchain;
        tmpchain.clear();
        // first find our scope
        const Widget closure = findStyleScopeRoot();
        // we can skip half of work if the state is normal
        Style[] list = (state == State.normal) ? currentTheme.normalStyles : currentTheme.allStyles;
        foreach (style; list)
            if (matchSelector(style.selector, closure))
                tmpchain ~= style;
        sort(tmpchain.unsafe_slice);
        return tmpchain.unsafe_slice;
    }

    /// Match this widget with selector
    bool matchSelector(ref const(Selector) sel) const
    {
        return matchSelector(sel, findStyleScopeRoot());
    }

    private const(Widget) findStyleScopeRoot() const
    {
        Widget p = cast()_parent;
        while (p)
        {
            if (p.styleIsolated)
                return p;
            p = p._parent;
        }
        return null;
    }

    private bool matchSelector(ref const(Selector) sel, const(Widget) closure) const
    {
        if (this is closure)
            return matchSelector(sel, null);
        if (sel.universal)
            return matchContextSelector(sel, closure);
        // subitemness
        if (!subInfo && sel.subitem)
            return false;
        if (subInfo)
        {
            if (!sel.subitem || subInfo.subName != sel.subitem)
                return false;
            // match state
            if ((sel.specifiedState & state) != sel.enabledState)
                return false;
            // match parent
            if (auto wt = cast(Widget)subInfo.parent)
            {
                Selector ps = cast(Selector)sel;
                ps.subitem = null;
                ps.specifiedState = State.init;
                ps.enabledState = State.init;
                return wt.matchSelector(ps, closure);
            }
            else // not a widget
            {
                // check only type
                TypeInfo_Class type = typeid(subInfo.parent);
                return equalShortClassName(type, sel.type);
            }
        }
        // enclosed elements cannot be styled via simple selectors
        if (closure && !sel.previous)
            return false;
        // type
        if (sel.type)
        {
            TypeInfo_Class type = typeid(this);
            while (!equalShortClassName(type, sel.type))
            {
                type = type.base; // support inheritance
                if (type is typeid(Object))
                    return false;
            }
        }
        // id
        if (sel.id && (!_id || _id != sel.id))
            return false;
        // state
        if ((sel.specifiedState & state) != sel.enabledState)
            return false;
        // classes
        foreach (name; sel.classes)
        {
            auto p = name in attributes;
            if (!p || (*p)) // skip also attributes with values
                return false;
        }
        // attributes
        foreach (ref attr; sel.attributes)
        {
            if (auto p = attr.name in attributes)
            {
                if (!attr.match(*p))
                    return false;
            }
            else
                return false;
        }
        return matchContextSelector(sel, closure);
    }

    private bool matchContextSelector(ref const(Selector) sel, const(Widget) closure) const
    {
        const Selector* subselector = sel.previous;
        if (!subselector) // exhausted
            return true;
        if (!_parent) // doesn't match because top-level
            return false;

        final switch (sel.combinator) with (Selector.Combinator)
        {
            case descendant:
                // match with any of parent widgets
                Widget p = cast()_parent;
                while (p)
                {
                    if (p.matchSelector(*subselector, closure))
                        return true;
                    if (p is closure)
                        break;
                    p = p._parent;
                }
                return false;
            case child:
                // match with the only parent
                return _parent.matchSelector(*subselector, closure);
            case next:
                // match with the previous sibling
                const n = _parent.childIndex(this) - 1;
                if (n >= 0)
                    return _parent.child(n).matchSelector(*subselector, closure);
                else
                    return false;
            case subsequent:
                // match with any of previous siblings
                const n = _parent.childIndex(this);
                if (n >= 0)
                {
                    foreach (i; 0 .. n)
                        if (_parent.child(i).matchSelector(*subselector, closure))
                            return true;
                }
                return false;
        }
    }

    private void invalidateStyles()
    {
        invalidateStylesRecursively();
        if (_parent)
        {
            int start = _parent.childIndex(this);
            if (start >= 0)
            {
                foreach (i; start + 1 .. _parent.childCount)
                    _parent.child(i).invalidateStylesRecursively();
            }
            needUpdate(); // useless when no parent
        }
    }

    private void invalidateStylesRecursively()
    {
        _needToRecomputeStyle = true;
        foreach (i; 0 .. childCount)
        {
            child(i).invalidateStylesRecursively();
        }
    }

    /// Handle theme change: e.g. reload some themed resources
    void handleThemeChange()
    {
        // default implementation: call recursive for children
        foreach (i; 0 .. childCount)
            child(i).handleThemeChange();

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
            Insets p = _style.padding;
            Insets bp = _background.padding;
            if (p.left < bp.left)
                p.left = bp.left;
            if (p.right < bp.right)
                p.right = bp.right;
            if (p.top < bp.top)
                p.top = bp.top;
            if (p.bottom < bp.bottom)
                p.bottom = bp.bottom;

            if (style.focusRectColor != Color.transparent &&
                (allowsFocus || ((state & State.parent) && parent.allowsFocus)))
            {
                // add two pixels to padding when focus rect is required
                // one pixel for focus rect, one for additional space
                p.add(Insets(FOCUS_RECT_PADDING));
            }
            return p;
        }

        /// Get widget standard background. The background object has the same lifetime as the widget.
        inout(Background) background() inout
        {
            updateStyles();
            return _background;
        }

        /// Text flags (bit set of `TextFlag` enum values)
        TextFlag textFlags() const
        {
            return TextFlag.unspecified;
        }

        /// Returns font set for widget using style or set manually
        FontRef font() const
        {
            updateStyles();
            with (caching(this))
            {
                if (!_font.isNull)
                    return _font;
                _font = FontManager.instance.getFont(_style.fontSize, _style.fontWeight,
                        _style.fontItalic, _style.fontFamily, _style.fontFace);
                return _font;
            }
        }

        /// Returns computed text hotkey flag: `underlineOnAlt` is resolved to `underline` or `hidden`
        TextHotkey textHotkey() const
        {
            updateStyles();
            TextHotkey result = _style.textHotkey;
            if (result == TextHotkey.underlineOnAlt)
            {
                if (auto w = window)
                {
                    const modifiers = w.keyboardModifiers;
                    if ((modifiers & KeyMods.alt) != 0)
                        // Alt pressed
                        return TextHotkey.underline;
                }
                return TextHotkey.hidden;
            }
            return result;
        }

        /// Widget content text (override to support this)
        dstring text() const
        {
            return "";
        }
        /// ditto
        void text(dstring s)
        {
        }
    }

    /// Handle changes of style properties (e.g. invalidate)
    void handleStyleChange(StyleProperty p)
    {
        switch (p) with (StyleProperty)
        {
        case bgColor:
            _background.color = _style.backgroundColor;
            break;
        case bgImage:
            _background.image = _style.backgroundImage;
            break;
        case borderTopWidth:
            _background.border.top.thickness = _style.borderTopWidth;
            break;
        case borderRightWidth:
            _background.border.right.thickness = _style.borderRightWidth;
            break;
        case borderBottomWidth:
            _background.border.bottom.thickness = _style.borderBottomWidth;
            break;
        case borderLeftWidth:
            _background.border.left.thickness = _style.borderLeftWidth;
            break;
        case borderTopColor:
            _background.border.top.color = _style.borderTopColor;
            break;
        case borderRightColor:
            _background.border.right.color = _style.borderRightColor;
            break;
        case borderBottomColor:
            _background.border.bottom.color = _style.borderBottomColor;
            break;
        case borderLeftColor:
            _background.border.left.color = _style.borderLeftColor;
            break;
        case borderTopStyle:
            _background.border.top.style = _style.borderTopStyle;
            break;
        case borderRightStyle:
            _background.border.right.style = _style.borderRightStyle;
            break;
        case borderBottomStyle:
            _background.border.bottom.style = _style.borderBottomStyle;
            break;
        case borderLeftStyle:
            _background.border.left.style = _style.borderLeftStyle;
            break;
        case boxShadow:
            _background.shadow = _style.boxShadow;
            break;
        default:
            break;
        }

        switch (p) with (StyleProperty)
        {
        case width: .. case maxHeight:
        case paddingTop: .. case paddingLeft:
        case borderTopWidth: .. case borderLeftWidth:
        case marginTop: .. case marginLeft:
        case letterSpacing:
        case lineHeight:
        case tabSize:
        case textHotkey:
        case textIndent:
        case textOverflow:
        case textTransform:
        case wordSpacing:
            requestLayout();
            break;
        case zIndex:
        case bgColor: .. case bgClip:
        case borderTopColor: .. case borderLeftColor:
        case borderTopStyle: .. case borderLeftStyle:
        case borderTopLeftRadius: .. case borderBottomRightRadius:
        case boxShadow:
        case textAlign:
        case textDecorColor:
        case textDecorLine:
        case textDecorStyle:
        case alpha:
        case textColor:
        case focusRectColor:
            invalidate();
            break;
        case fontFace: .. case fontWeight:
            _font.clear();
            handleFontChange();
            requestLayout();
            break;
        // transitionProperty
        // transitionTimingFunction
        // transitionDuration
        // transitionDelay
        default:
            break;
        }

        if (_parent)
            _parent.handleChildStyleChange(p, _visibility);
    }

    protected void handleChildStyleChange(StyleProperty p, Visibility v)
    {
    }

    /// Override to handle font changes
    protected void handleFontChange()
    {
    }

    //===============================================================
    // Animation

    /// Returns true is widget is being animated - need to call `animate()` and redraw
    @property bool animating() const
    {
        return animations.length > 0;
    }

    /// Experimental API
    bool hasAnimation(string name)
    {
        return (name in animations) !is null;
    }
    /// Experimental API
    void addAnimation(string name, long duration, void delegate(double) handler)
    {
        assert(name && duration > 0 && handler);
        animations[name] = Animation(duration * ONE_SECOND / 1000, handler);
        needUpdate();
    }
    /// Experimental API
    void cancelAnimation(string name)
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

    //===============================================================
    // State related properties and methods

    private
    {
        bool _allowsClick;
        bool _allowsFocus;
        bool _allowsHover;
        bool _allowsToggle;
    }

    @property
    {
        /** True if the widget is interactive.

            Corresponds to `State.enabled` state flag.
        */
        bool enabled() const
        {
            return (state & State.enabled) != 0;
        }
        /// ditto
        void enabled(bool flag)
        {
            flag ? setState(State.enabled) : resetState(State.enabled);
        }

        /** True if the widget is somehow checked, as a checkbox or button.

            Corresponds to `State.checked` state flag.
        */
        bool checked() const
        {
            return (state & State.checked) != 0;
        }
        /// ditto
        void checked(bool flag)
        {
            flag ? setState(State.checked) : resetState(State.checked);
        }

        /// True if this widget and all its parents are visible
        bool visible() const
        {
            if (visibility != Visibility.visible)
                return false;
            if (parent is null)
                return true;
            return parent.visible;
        }

        /// True if this widget is currently focused
        bool focused() const
        {
            if (auto w = window)
                return w.focusedWidget is this && (state & State.focused);
            else
                return false;
        }

        /// True if the widget supports click by mouse button or enter/space key
        bool allowsClick() const { return _allowsClick; }
        /// ditto
        void allowsClick(bool flag)
        {
            _allowsClick = flag;
        }
        /// True if the widget can be focused
        bool allowsFocus() const { return _allowsFocus; }
        /// ditto
        void allowsFocus(bool flag)
        {
            _allowsFocus = flag;
        }
        /// True if the widget will change `hover` state while mouse pointer is moving upon it
        bool allowsHover() const
        {
            return _allowsHover && !TOUCH_MODE;
        }
        /// ditto
        void allowsHover(bool v)
        {
            _allowsHover = v;
        }
        /// True if the widget supports `checked` state
        bool allowsToggle() const { return _allowsToggle; }
        /// ditto
        void allowsToggle(bool flag)
        {
            _allowsToggle = flag;
        }

        /// True if the widget allows click, and it's visible and enabled
        bool canClick() const
        {
            return _allowsClick && enabled && visible;
        }
        /// True if the widget allows focus, and it's visible and enabled
        bool canFocus() const
        {
            return _allowsFocus && enabled && visible;
        }
        /// True if the widget allows toggle, and it's visible and enabled
        bool canToggle() const
        {
            return _allowsToggle && enabled && visible;
        }

        /// Override and return true to track key events even when not focused
        bool wantsKeyTracking() const
        {
            return false;
        }
    }

    /// Chained version of `enabled`
    final Widget setEnabled(bool flag)
    {
        enabled = flag;
        return this;
    }
    /// Chained version of `checked`
    final Widget setChecked(bool flag)
    {
        checked = flag;
        return this;
    }

    void requestActionsUpdate() // TODO
    {
    }

    /// Returns mouse cursor type for widget
    CursorType getCursorType(int x, int y) const
    {
        return CursorType.arrow;
    }

    //===============================================================
    // Tooltips

    private dstring _tooltipText;
    /** Tooltip text - when not empty, widget will show tooltips automatically.

        For advanced tooltips - override `hasTooltip` and `createTooltip` methods.
    */
    @property dstring tooltipText() { return _tooltipText; }
    /// ditto
    @property void tooltipText(dstring text)
    {
        _tooltipText = text;
    }
    /// Returns true if widget has tooltip to show
    @property bool hasTooltip()
    {
        return tooltipText.length > 0;
    }

    /** Will be called from window once tooltip request timer expired.

        If `null` is returned, popup will not be shown; you can change alignment and position of popup here.
    */
    Widget createTooltip(int mouseX, int mouseY, ref PopupAlign alignment, ref int x, ref int y)
    {
        // default implementation supports tooltips when tooltipText property is set
        import beamui.widgets.text;

        return _tooltipText ? new Label(_tooltipText).setID("tooltip") : null;
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
    /** Focus group flag for container widget.

        When focus group is set for some parent widget, focus from one of containing widgets can be moved
        using keyboard only to one of other widgets containing in it and cannot bypass bounds of `focusGroup`.
        If focused widget doesn't have any parent with `focusGroup == true`,
        focus may be moved to any focusable within window.
    */
    @property bool focusGroup() const { return _focusGroup; }
    /// ditto
    @property void focusGroup(bool flag)
    {
        _focusGroup = flag;
    }

    @property bool focusGroupFocused() const
    {
        const w = focusGroupWidget();
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

    @property void focusGroupFocused(bool flag)
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
    }

    /// Find nearest parent of this widget with `focusGroup` flag. Returns topmost parent if no `focusGroup` flag set to any of parents
    inout(Widget) focusGroupWidget() inout
    {
        Widget p = cast()this;
        while (p)
        {
            if (!p.parent || p.focusGroup)
                break;
            p = p.parent;
        }
        return cast(inout)p;
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

    private void findFocusableChildren(ref Buf!TabOrderInfo results, Rect clipRect, Widget currentWidget)
    {
        if (visibility != Visibility.visible)
            return;

        Rect rc = _innerBox;
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

    /// Find all focusables belonging to the same `focusGroup` as this widget (does not include current widget).
    /// Usually to be called for focused widget to get possible alternatives to navigate to
    private Buf!TabOrderInfo findFocusables(Widget currentWidget)
    {
        Buf!TabOrderInfo result;
        Widget group = focusGroupWidget();
        group.findFocusableChildren(result, Rect(group.box), currentWidget);
        for (ushort i = 0; i < result.length; i++)
            result.unsafe_ref(i).childOrder = i + 1;
        sort(result.unsafe_slice);
        return result;
    }

    private ushort _tabOrder;
    /// Tab order - hint for focus movement using Tab/Shift+Tab
    @property ushort tabOrder() const { return _tabOrder; }
    /// ditto
    @property void tabOrder(ushort tabOrder)
    {
        _tabOrder = tabOrder;
    }

    private int thisOrParentTabOrder() const
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
        auto focusables = findFocusables(this);
        if (focusables.length == 0)
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
            return focusables.unsafe_ref(0).widget; // single option - use it
        if (direction == FocusMovement.next)
        {
            // move forward
            int index = myIndex + 1;
            if (index >= focusables.length)
                index = 0;
            return focusables.unsafe_ref(index).widget;
        }
        else if (direction == FocusMovement.previous)
        {
            // move back
            int index = myIndex - 1;
            if (index < 0)
                index = cast(int)focusables.length - 1;
            return focusables.unsafe_ref(index).widget;
        }
        else
        {
            // Left, Right, Up, Down
            if (direction == FocusMovement.left || direction == FocusMovement.right)
            {
                sort!(TabOrderInfo.lessHorizontal)(focusables.unsafe_slice);
            }
            else
            {
                sort!(TabOrderInfo.lessVertical)(focusables.unsafe_slice);
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
            return focusables.unsafe_ref(index).widget;
        }
    }

    bool handleMoveFocusUsingKeys(KeyEvent event)
    {
        if (!focused || !visible)
            return false;
        if (event.action != KeyAction.keyDown)
            return false;

        FocusMovement direction = FocusMovement.none;
        const bool noMods = event.noModifiers;
        const bool shift = event.alteredBy(KeyMods.shift);
        switch (event.key)
        {
        case Key.left:
            if (noMods)
                direction = FocusMovement.left;
            break;
        case Key.right:
            if (noMods)
                direction = FocusMovement.right;
            break;
        case Key.up:
            if (noMods)
                direction = FocusMovement.up;
            break;
        case Key.down:
            if (noMods)
                direction = FocusMovement.down;
            break;
        case Key.tab:
            if (noMods)
                direction = FocusMovement.next;
            else if (shift)
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
    /// Search children for first focusable item, returns `null` if not found
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
    Signal!(void delegate()) onClick;

    /// Checked state change event listener
    Signal!(void delegate(bool)) onToggle;

    /// Focus state change event listener
    Signal!(void delegate(bool)) onFocusChange;

    /// Fires on key events, return true to prevent further widget actions
    Signal!(bool delegate(KeyEvent)) onKeyEvent;

    /// Fires on mouse events, return true to prevent further widget actions
    Signal!(bool delegate(MouseEvent)) onMouseEvent;

    /// Fires on mouse/touchpad scroll events, return true to prevent further widget actions
    Signal!(bool delegate(WheelEvent)) onWheelEvent;

    //===============================================================
    // Events

    /// Called to process click before `onClick` signal, override to do it
    protected void handleClick()
    {
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

    /// Cancel timer - pass value returned from `setTimer()` as `timerID` parameter
    void cancelTimer(ulong timerID)
    {
        if (auto w = window)
            w.cancelTimer(timerID);
    }

    /// Process key event, return true if event is processed
    bool handleKeyEvent(KeyEvent event)
    {
        // handle focus navigation using keys
        if (focused && handleMoveFocusUsingKeys(event))
            return true;
        if (canClick)
        {
            // support onClick event initiated by Space or Return keys
            if (event.key == Key.space || event.key == Key.enter)
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
                        onClick();
                    }
                    return true;
                }
            }
        }
        return false;
    }

    /// Process mouse event; return true if event is processed by widget
    bool handleMouseEvent(MouseEvent event)
    {
        debug (mouse)
            Log.fd("mouse event, '%s': %s  (%s, %s)", id, event.action, event.x, event.y);
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
                        onClick();
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
                resetState(State.pressed | State.hovered);
                return true;
            }
        }
        if (event.action == MouseAction.move && event.noKeyMods && event.noMouseMods && hasTooltip)
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
        if (allowsHover)
        {
            if (event.action == MouseAction.focusOut || event.action == MouseAction.cancel)
            {
                if (state & State.hovered)
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

    /// Process wheel event, return true if the event is processed
    bool handleWheelEvent(WheelEvent event)
    {
        return false;
    }

    /// Handle custom event
    bool handleEvent(CustomEvent event)
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

    /** Execute delegate later in UI thread if this widget will be still available.

        Can be used to modify UI from background thread, or just to postpone execution of action.
    */
    void executeInUiThread(void delegate() runnable)
    {
        if (!window)
            return;
        auto event = new RunnableEvent(CUSTOM_RUNNABLE, weakRef(this), runnable);
        window.postEvent(event);
    }

    //===============================================================
    // Layout, measurement, drawing methods and properties

    @property
    {
        /// Returns true if layout is required for widget and its children
        bool needLayout() const
        {
            // we need to be sure that the style is updated
            // it might set _needDraw or _needLayout flag
            updateStyles();
            return _needLayout;
        }
        /// Returns true if redraw is required for widget and its children
        bool needDraw() const
        {
            updateStyles();
            return _needDraw;
        }

        /// Defines whether widget width/height depends on its height/width
        final DependentSize dependentSize() const { return _dependentSize; }
        /// Indicate from subclass that widget width/height depends on its height/width
        final protected void dependentSize(DependentSize value)
        {
            _dependentSize = value;
        }
        /// Get current widget boundaries (min, nat and max sizes, computed in `measure`)
        final ref const(Boundaries) boundaries() const { return _boundaries; }
        /// Get widget minimal size (computed in `measure`)
        final Size minSize() const { return _boundaries.min; }
        /// Get widget natural (preferred) size (computed in `measure`)
        final Size natSize() const { return _boundaries.nat; }
        /// Get widget maximal size (computed in `measure`)
        final Size maxSize() const { return _boundaries.max; }

        /// Get current widget full box in device-independent pixels (computed and set in `layout`)
        ref const(Box) box() const { return _box; }
        /// Get current widget box without padding and borders (computed and set in `layout`)
        ref const(Box) innerBox() const { return _innerBox; }

        /// Widget visibility (visible, hidden, gone)
        Visibility visibility() const { return _visibility; }
        /// ditto
        void visibility(Visibility newVisibility)
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
        }
    }

    /// Returns true if the point is inside of this widget
    bool contains(int x, int y) const
    {
        return _box.contains(x, y);
    }

    /// Tell the window (if some), that the widget may be invalidated
    private void needUpdate()
    {
        if (auto w = window)
            w.needUpdate = true;
    }
    /// Request relayout of widget and its children
    void requestLayout()
    {
        _needLayout = true;
        needUpdate();
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
        needUpdate();
    }

    /** Measure widget - compute minimal, natural and maximal sizes for the widget

        Override this method only when you make completely new algorithm
        and don't intend to call `super.measure()`.
        But if you only need to adjust widget boundaries, e.g. add some width,
        then override `adjustBoundaries` method.
    */
    void measure()
    {
        setBoundaries(Boundaries());
    }

    /// Callback to adjust widget boundaries; called after measure and before applying style to them
    protected void adjustBoundaries(ref Boundaries bs)
    {
    }

    /// Set widget boundaries, checking their validity and applying
    /// padding and min-max style properties
    final protected void setBoundaries(Boundaries bs)
    {
        const Size p = padding.size; // updates style
        adjustBoundaries(bs);
        bs.min.w = max(bs.min.w, _style.minWidth.applyPercent(0));
        bs.min.h = max(bs.min.h, _style.minHeight.applyPercent(0));
        bs.max.w = max(min(bs.max.w + p.w, _style.maxWidth.applyPercent(0)), bs.min.w);
        bs.max.h = max(min(bs.max.h + p.h, _style.maxHeight.applyPercent(0)), bs.min.h);
        const w = _style.width.applyPercent(0);
        const h = _style.height.applyPercent(0);
        if (isDefinedSize(w))
            bs.nat.w = w;
        else
            bs.nat.w += p.w;
        if (isDefinedSize(h))
            bs.nat.h = h;
        else
            bs.nat.h += p.h;
        bs.nat.w = clamp(bs.nat.w, bs.min.w, bs.max.w);
        bs.nat.h = clamp(bs.nat.h, bs.min.h, bs.max.h);
        assert(bs.max.w >= bs.nat.w && bs.nat.w >= bs.min.w);
        assert(bs.max.h >= bs.nat.h && bs.nat.h >= bs.min.h);
        _boundaries = bs;
    }

    /// Returns natural height for the given width
    int heightForWidth(int width)
    {
        return _boundaries.nat.h;
    }
    /// Returns natural width for the given height
    int widthForHeight(int height)
    {
        return _boundaries.nat.w;
    }

    /// Set widget box and lay out widget contents
    void layout(Box geometry)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        setBox(geometry);
    }

    /// Set widget `box`, compute `innerBox`, and shrink padding if necessary
    /// (for usage in subclass' `layout`)
    final protected void setBox(ref const Box b)
    {
        _needLayout = false;
        // shrink padding when appropriate
        Insets p = padding;
        if (_boundaries.nat.w > b.w)
        {
            const pdiff = p.width - (b.w - _boundaries.min.w);
            if (pdiff > 0)
            {
                const pdiff2 = pdiff / 2;
                p.left -= pdiff2;
                p.right -= pdiff - pdiff2;
                if (p.left < 0)
                {
                    p.right += p.left;
                    p.left = 0;
                }
                else if (p.right < 0)
                {
                    p.left += p.right;
                    p.right = 0;
                }
            }
        }
        if (_boundaries.nat.h > b.h)
        {
            const pdiff = p.height - (b.h - _boundaries.min.h);
            if (pdiff > 0)
            {
                const pdiff2 = pdiff / 2;
                p.top -= pdiff2;
                p.bottom -= pdiff - pdiff2;
                if (p.top < 0)
                {
                    p.bottom += p.top;
                    p.top = 0;
                }
                else if (p.bottom < 0)
                {
                    p.top += p.bottom;
                    p.bottom = 0;
                }
            }
        }
        _box = b;
        _innerBox = b.shrinked(p);
    }

    /// Draw widget at its position to a buffer
    final void draw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        const b = _box;
        const saver = ClipRectSaver(buf, b, style.alpha);

        background.drawTo(buf, b);

        drawContent(buf);

        if (state & State.focused)
            drawFocusRect(buf);

        _needDraw = false;
    }

    protected void drawContent(DrawBuf buf)
    {
    }

    /// Draw focus rectangle, if enabled in styles
    protected void drawFocusRect(DrawBuf buf)
    {
        const Color c = style.focusRectColor;
        if (!c.isFullyTransparent)
        {
            Box b = _box;
            b.shrink(Insets(FOCUS_RECT_PADDING));
            buf.drawFocusRect(Rect(b), c);
        }
    }

    /** Just draw all children. Used as default behaviour in some widgets.

        Example:
        ---
        override protected void drawContent(DrawBuf buf)
        {
            drawAllChildren(buf);
        }
        ---
    */
    protected void drawAllChildren(DrawBuf buf)
    {
        const count = childCount;
        if (count == 0 || visibility != Visibility.visible)
            return;

        const b = _innerBox;
        const saver = ClipRectSaver(buf, b, style.alpha);
        foreach (i; 0 .. count)
            child(i).draw(buf);
    }

    //===============================================================
    // Popup (contextual) menu support

    private Menu _popupMenu;
    /// Popup (contextual menu), associated with this widget
    @property Menu popupMenu() { return _popupMenu; }
    /// ditto
    @property void popupMenu(Menu popupMenu)
    {
        _popupMenu = popupMenu;
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

    /// Add a child. Returns the added item with its original type
    T addChild(T)(T item) if (is(T : Widget))
    {
        addChildImpl(item);
        return item;
    }
    /// Append several children
    final void add(Widget first, Widget[] next...)
    {
        addChildImpl(first);
        foreach (item; next)
            addChildImpl(item);
    }
    /// Append several children, skipping `null` widgets
    final void addSome(Widget first, Widget[] next...)
    {
        if (first)
            addChildImpl(first);
        foreach (item; next)
            if (item)
                addChildImpl(item);
    }
    protected void addChildImpl(Widget item)
    {
        assert(false, "addChild: this widget does not support having children");
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
    int childIndex(string id) const
    {
        return -1;
    }
    /// Returns index of widget in child list, -1 if passed widget is not a child of this widget
    int childIndex(const Widget item) const
    {
        return -1;
    }

    /** Returns true if item is child of this widget.

        When `deepSearch == true`, returns true if item is this widget
        or one of children inside children tree.
    */
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

    /// Find child of specified type `T` by id, returns `null` if not found or cannot be converted to type `T`
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

    /// Parent widget, `null` for top level widget
    @property inout(Widget) parent() inout { return _parent; }
    /// ditto
    @property void parent(Widget widget)
    {
        if (_visibility != Visibility.gone)
        {
            if (_parent)
                _parent.requestLayout();
            if (widget)
                widget.requestLayout();
        }
        _parent = widget;
        invalidateStyles();
    }
    /// Returns window (if widget or its parent is attached to window)
    @property inout(Window) window() inout
    {
        Widget p = cast()this;
        while (p)
        {
            if (p._window)
                return cast(inout)p._window;
            p = p.parent;
        }
        return null;
    }
    /// Set window (to be used for top level widget from Window implementation).
    package(beamui) @property void window(Window window)
    {
        _window = window;
    }
}

/// Widget list holder
alias WidgetList = Collection!(Widget, true);

/** Base class for widgets which have children.

    Added children will correctly handle destruction of parent widget and theme change.

    If your widget has subwidgets which do not need to catch mouse and key events, focus, etc,
    you may not use this class. You may inherit directly from the Widget class
    and add code for subwidgets to destructor, `handleThemeChange`, and `draw` (if needed).
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

    override protected void addChildImpl(Widget item)
    {
        assert(item !is null, "Widget must exist");
        _children.append(item);
        item.parent = this;
    }

    override Widget insertChild(int index, Widget item)
    {
        assert(item !is null, "Widget must exist");
        _children.insert(index, item);
        item.parent = this;
        return item;
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
        return index >= 0 ? removeChild(index) : null;
    }

    override Widget removeChild(Widget child)
    {
        if (child)
        {
            int index = cast(int)_children.indexOf(child);
            if (index >= 0)
                return removeChild(index);
        }
        return null;
    }

    override void removeAllChildren(bool destroyThem = true)
    {
        _children.clear(destroyThem);
    }

    override int childIndex(string id) const
    {
        return cast(int)_children.indexOf(id);
    }

    override int childIndex(const Widget item) const
    {
        return cast(int)_children.indexOf(item);
    }

    /// Replace one child with another. It DOES NOT destroy the old item
    void replaceChild(Widget oldChild, Widget newChild)
    {
        assert(newChild !is null && oldChild !is null, "Widgets must exist");
        _children.replace(oldChild, newChild);
        oldChild.parent = null;
        newChild.parent = this;
    }
}

interface ILayout
{
    void onSetup(Widget host);
    void onDetach();
    void onStyleChange(StyleProperty p);
    void onChildStyleChange(StyleProperty p);

    void prepare(ref Buf!Widget list);
    Boundaries measure();
    void arrange(Box box);
}

/** Panel is a widget group with some layout.

    By default, without specified layout, it places all children to fill its
    inner frame (usually, only one child should be visible at a time, see
    `showChild` method).
*/
class Panel : WidgetGroup
{
    import beamui.layout.factory : createLayout;

    private string _kind;
    private ILayout _layout;
    private Buf!Widget preparedItems;

    this()
    {
        super();
    }

    /// Create a panel with `id` and, perhaps, several style classes
    this(string id, string[] classes...)
    {
        super(id);
        foreach (a; classes)
        {
            if (a.length)
                setAttribute(a);
        }
    }

    ~this()
    {
        _layout.maybe.onDetach();
    }

    /** Get the layout object to adjust some properties. May be `null`.

        Example:
        ---
        if (TableLayout t = panel.getLayout!TableLayout)
            t.colCount = 2;
        ---
    */
    T getLayout(T)() if (is(T : ILayout))
    {
        return cast(T)_layout;
    }

    private void setLayout(string kind)
    {
        if (_kind == kind)
            return;

        _kind = kind;

        ILayout obj;
        if (kind.length)
        {
            obj = createLayout(kind);
            debug if (!obj)
                Log.fw("Layout of kind '%s' is null", kind);
        }
        if (_layout || obj)
        {
            _layout.maybe.onDetach();
            _layout = obj;
            obj.maybe.onSetup(this);
            requestLayout();
        }
    }

    override void handleStyleChange(StyleProperty p)
    {
        if (p == StyleProperty.display)
        {
            setLayout(_style.display);
        }
        else
        {
            super.handleStyleChange(p);
            _layout.maybe.onStyleChange(p);
        }
    }

    override protected void handleChildStyleChange(StyleProperty p, Visibility v)
    {
        if (v != Visibility.gone && _layout)
            _layout.onChildStyleChange(p);
    }

    override void measure()
    {
        updateStyles();

        preparedItems.clear();
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.visibility != Visibility.gone)
                preparedItems ~= item;
            else
                item.cancelLayout();
        }
        // now we can safely work with items
        Boundaries bs;
        if (_layout)
        {
            _layout.prepare(preparedItems);
            bs = _layout.measure();
        }
        else
        {
            foreach (item; preparedItems.unsafe_slice)
            {
                item.measure();
                bs.maximize(item.boundaries);
            }
        }
        setBoundaries(bs);
    }

    override void layout(Box geometry)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        setBox(geometry);

        if (_layout)
        {
            _layout.arrange(_innerBox);
        }
        else
        {
            foreach (item; preparedItems.unsafe_slice)
            {
                item.layout(_innerBox);
            }
        }
    }

    override protected void drawContent(DrawBuf buf)
    {
        if (preparedItems.length > 0)
        {
            const b = _innerBox;
            const saver = ClipRectSaver(buf, b, style.alpha);
            foreach (item; preparedItems.unsafe_slice)
                item.draw(buf);
        }
    }

    /// Make one child (with specified ID) visible, set `othersVisibility` to the rest
    bool showChild(string ID, Visibility othersVisibility = Visibility.hidden, bool updateFocus = false)
    {
        bool found;
        Widget foundWidget;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            if (item.compareID(ID))
            {
                item.visibility = Visibility.visible;
                foundWidget = item;
                found = true;
            }
            else
                item.visibility = othersVisibility;
        }
        if (found && updateFocus)
            foundWidget.setFocus();
        return found;
    }
}

/// Helper for locating items in list, tree, table or other controls by typing their name
struct TextTypingShortcutHelper
{
    nothrow:

    /// Expiration time for entered text; after timeout collected text will be cleared
    int timeoutMillis = 800;
    private long _lastUpdateTimeStamp;
    private Buf!dchar _text;

    /// Cancel text collection (next typed text will be collected from scratch)
    void cancel()
    {
        _text.clear();
        _lastUpdateTimeStamp = 0;
    }
    /// Returns collected text string - use it for lookup
    @property dstring text() const
    {
        return _text[].idup;
    }
    /// Pass key event here; returns true if search text is updated and you can move selection using it
    bool handleKeyEvent(KeyEvent event)
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
            switch (event.key) with (Key)
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
    void handleMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.buttonUp || event.action == MouseAction.buttonDown)
            cancel();
    }
}

/// Helper to handle animation progress.
/// NOT USED
struct AnimationHelper
{
    nothrow:

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
    @property long elapsed() const
    {
        return _timeElapsed;
    }
    /// Get current time interval
    @property long interval() const
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
    @property int progress() const
    {
        return getProgress(_maxProgress);
    }
    /// Returns animation progress in interval 0..maxProgress while timeElapsed is between 0 and maxInterval; when interval exceeded, progress is maxProgress
    int getProgress(int maxProgress) const
    {
        if (finished)
            return maxProgress;
        if (_timeElapsed <= 0)
            return 0;
        return cast(int)(_timeElapsed * maxProgress / _maxInterval);
    }
    /// Returns true if animation is finished
    @property bool finished() const
    {
        return _timeElapsed >= _maxInterval;
    }
}

__gshared bool TOUCH_MODE = false;
