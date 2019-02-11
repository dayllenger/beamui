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
    import beamui.graphics.fonts;

    import beamui.style.theme : currentTheme;
    import beamui.style.types;

    import beamui.widgets.popup : PopupAlign;
}
package import beamui.style.computed_style;
import std.string : capitalize;
import beamui.core.animations;
import beamui.graphics.text : TextHotkey;
import beamui.platforms.common.platform;
import beamui.style.style;
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

    /// Style class list
    bool[string] styleClasses; // value means nothing
    struct StyleSubItemInfo
    {
        const(Object) parent;
        string subName;
    }
    /// Structure needed when this widget is subitem of another
    StyleSubItemInfo* subInfo;
    /// If true, the style will be recomputed on next usage
    bool _needToRecomputeStyle = true;

    /// Widget state (set of flags from State enum)
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
                focusChanged(false);
            }
            else if (!(oldState & State.focused) && (newState & State.focused))
            {
                handleFocusChange(true, cast(bool)(newState & State.keyboardFocused));
                focusChanged(true);
            }
            // notify checked changes
            if ((oldState & State.checked) && !(newState & State.checked))
            {
                handleToggling(false);
                toggled(false);
            }
            else if (!(oldState & State.checked) && (newState & State.checked))
            {
                handleToggling(true);
                toggled(true);
            }
        }
    }
    /// Add state flags (set of flags from State enum). Returns new state
    State setState(State stateFlagsToSet)
    {
        State st = state | stateFlagsToSet;
        state = st;
        return st;
    }
    /// Remove state flags (set of flags from State enum). Returns new state
    State resetState(State stateFlagsToUnset)
    {
        State st = state & ~stateFlagsToUnset;
        state = st;
        return st;
    }
    /// Override to handle focus changes
    protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
    }
    /// Override to handle check changes
    protected void handleToggling(bool checked)
    {
    }

    //===============================================================
    // Style

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
    void toggleStyleClass(string name)
    {
        assert(name.length);
        bool present = styleClasses.remove(name);
        if (!present)
            styleClasses[name] = false;
        invalidateStyles();
    }
    /// Shorthand to set one style class to the widget
    @property void style(string name)
    {
        assert(name.length);
        styleClasses.clear();
        styleClasses[name] = false;
        invalidateStyles();
    }

    /// Set this widget to be a subitem in stylesheet
    void bindSubItem(const(Object) parent, string subName)
    {
        assert(parent && subName);
        subInfo = new StyleSubItemInfo(parent, subName);
        _needToRecomputeStyle = true;
    }

    /// Signals when styles are being recomputed. Used for mixing properties in the widget.
    Listener!(void delegate(Style[] chain)) stylesRecomputed;

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
                const len = cast(uint)chain.length;
                // assume that style recomputation is purely depends on style chain
                // it may not change from previous update
                if (cast(size_t[])cachedChain[0 .. cachedChainLen] != cast(size_t[])chain)
                {
                    // copy
                    if (cachedChain.length < len)
                        cachedChain.length = len;
                    cachedChainLen = len;
                    cachedChain[0 .. len] = chain[];
                    // important: we cannot use shared array from `selectStyleChain` func
                    _style.recompute(cachedChain[0 .. len]);
                }
                if (stylesRecomputed.assigned)
                    stylesRecomputed(cachedChain[0 .. len]);
            }
        }
    }
    private Style[] cachedChain;
    private uint cachedChainLen;

    /// Get a style chain for this widget from current theme, least specific styles first
    Style[] selectStyleChain()
    {
        static Style[] tmpchain;
        // first find our scope
        const Widget closure = findStyleScopeRoot();
        // we can skip half of work if the state is normal
        Style[] list = (state == State.normal) ? currentTheme.normalStyles : currentTheme.allStyles;
        size_t count;
        foreach (style; list)
        {
            if (matchSelector(style.selector, closure))
            {
                if (tmpchain.length <= count)
                    tmpchain.length += 4;
                tmpchain[count] = style;
                count++;
            }
        }
        sort(tmpchain[0 .. count]);
        return tmpchain[0 .. count];
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
        // class
        foreach (name; sel.classes)
        {
            if ((name in styleClasses) is null)
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
                (focusable || ((state & State.parent) && parent.focusable)))
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

        /// Text flags (bit set of TextFlag enum values)
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
                    const uint modifiers = w.keyboardModifiers;
                    if ((modifiers & (KeyFlag.alt | KeyFlag.lalt | KeyFlag.ralt)) != 0)
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
    void handleStyleChange(StyleProperty ptype)
    {
        switch (ptype) with (StyleProperty)
        {
        case borderTopWidth:
            _background.border.size.top = _style.borderTopWidth;
            break;
        case borderRightWidth:
            _background.border.size.right = _style.borderRightWidth;
            break;
        case borderBottomWidth:
            _background.border.size.bottom = _style.borderBottomWidth;
            break;
        case borderLeftWidth:
            _background.border.size.left = _style.borderLeftWidth;
            break;
        case borderColor:
            _background.border.color = _style.borderColor;
            break;
        case backgroundColor:
            _background.color = _style.backgroundColor;
            break;
        case backgroundImage:
            _background.image = _style.backgroundImage;
            break;
        case boxShadow:
            _background.shadow = _style.boxShadow;
            break;
        default:
            break;
        }

        switch (ptype) with (StyleProperty)
        {
        case width: .. case alignment:
        case textHotkey:
        case textOverflow:
        case textTransform:
            requestLayout();
            break;
        case borderColor: .. case boxShadow:
        case textAlign:
        case textDecorationColor:
        case textDecorationLine:
        case textDecorationStyle:
        case alpha: .. case focusRectColor:
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
    }

    /// Override to handle font changes
    protected void handleFontChange()
    {
    }

    //===============================================================
    // Animation

    /// Returns true is widget is being animated - need to call animate() and redraw
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
        bool _clickable;
        bool _checkable;
        bool _focusable;
        bool _trackHover;
    }

    @property
    {
        /// True if state has State.enabled flag set
        bool enabled() const
        {
            return (state & State.enabled) != 0;
        }
        /// ditto
        void enabled(bool flag)
        {
            flag ? setState(State.enabled) : resetState(State.enabled);
        }

        /// When true, user can click this control, and signals `clicked`
        bool clickable() const { return _clickable; }
        /// ditto
        void clickable(bool flag)
        {
            _clickable = flag;
        }

        bool canClick() const
        {
            return _clickable && enabled && visible;
        }

        /// When true, control supports `checked` state
        bool checkable() const { return _checkable; }
        /// ditto
        void checkable(bool flag)
        {
            _checkable = flag;
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
        void checked(bool flag)
        {
            if (flag != checked)
            {
                if (flag)
                    setState(State.checked);
                else
                    resetState(State.checked);
                invalidate();
            }
        }

        /// Whether widget can be focused
        bool focusable() const { return _focusable; }
        /// ditto
        void focusable(bool flag)
        {
            _focusable = flag;
        }

        bool focused() const
        {
            if (auto w = window)
                return w.focusedWidget is this && (state & State.focused);
            else
                return false;
        }

        /// When true, widget will change `hover` state while mouse is moving upon it
        bool trackHover() const
        {
            return _trackHover && !TOUCH_MODE;
        }
        /// ditto
        void trackHover(bool v)
        {
            _trackHover = v;
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
    /// Tooltip text - when not empty, widget will show tooltips automatically.
    /// For advanced tooltips - override hasTooltip and createTooltip methods.
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

    /**
    Will be called from window once tooltip request timer expired.

    If null is returned, popup will not be shown; you can change alignment and position of popup here.
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
    /**
    Focus group flag for container widget.

    When focus group is set for some parent widget, focus from one of containing widgets can be moved
    using keyboard only to one of other widgets containing in it and cannot bypass bounds of focusGroup.
    If focused widget doesn't have any parent with focusGroup == true,
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

    /// Find nearest parent of this widget with focusGroup flag, returns topmost parent if no focusGroup flag set to any of parents.
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

    private void findFocusableChildren(ref TabOrderInfo[] results, Rect clipRect, Widget currentWidget)
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
    Signal!(void delegate()) clicked;

    /// Checked state change event listener
    Signal!(void delegate(bool)) toggled;

    /// Focus state change event listener
    Signal!(void delegate(bool)) focusChanged;

    /// Key event listener, must return true if event is processed by handler
    Signal!(bool delegate(KeyEvent)) keyEvent;

    /// Mouse event listener, must return true if event is processed by handler
    Signal!(bool delegate(MouseEvent)) mouseEvent;

    //===============================================================
    // Events

    /// Called to process click and notify listeners
    protected void handleClick()
    {
        clicked();
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
        if (keyEvent.assigned && keyEvent(event))
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
        if (mouseEvent.assigned && mouseEvent(event))
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
        /// Set widget box value and indicate that layout process is done (for usage in subclass' `layout`)
        final protected void box(ref Box b)
        {
            _box = b;
            _innerBox = b.shrinked(padding);
            _needLayout = false;
        }
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

    /// Returns true if point is inside of this widget
    bool isPointInside(int x, int y)
    {
        return _box.isPointInside(x, y);
    }

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

    /** Measure widget - compute minimal, natural and maximal sizes for the widget

        Override this method only when you make completely new algorithm
        and don't intend to call `super.measure()`.
        But if you only need to adjust widget boundaries, e.g. add some width,
        then override `onMeasure` method.
    */
    void measure()
    {
        setBoundaries(Boundaries());
    }

    /// Callback to adjust widget boundaries; called after measure and before applying style to them
    protected void onMeasure(ref Boundaries bs)
    {
    }

    /// Set widget boundaries, checking their validity and applying
    /// padding and min-max style properties
    final protected void setBoundaries(Boundaries bs)
    {
        const Size p = padding.size; // updates style
        onMeasure(bs);
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

        _box = geometry;
        _innerBox = geometry.shrinked(padding);
    }

    /// Draw widget at its position to a buffer
    void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        Box b = _box;
        auto saver = ClipRectSaver(buf, b, style.alpha);

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
        Color[1] cs = [style.focusRectColor];
        if (cs[0] != Color.transparent)
        {
            Box b = _box;
            b.shrink(Insets(FOCUS_RECT_PADDING));
            buf.drawFocusRect(Rect(b), cs);
        }
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
    /// Add child, returns added item
    Widget addChild(Widget item)
    {
        assert(false, "addChild: this widget does not support having children");
    }
    /// Add several children
    void addChildren(Widget[] items...)
    {
        foreach (item; items)
        {
            addChild(item);
        }
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
    @property void parent(Widget parent)
    {
        _parent = parent;
        invalidateStyles();
    }
    /// Returns window (if widget or its parent is attached to window)
    @property Window window() const
    {
        Widget p = cast()this;
        while (p)
        {
            if (p._window)
                return cast()p._window;
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
        item.parent = this;
        return item;
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

    override int childIndex(string id) const
    {
        return cast(int)_children.indexOf(id);
    }

    override int childIndex(const Widget item) const
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
        Box b = _innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);
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
    @property dstring text() const
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
