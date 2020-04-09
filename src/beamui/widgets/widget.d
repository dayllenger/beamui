/**
Contains core classes and ancillary types of the widget system.

Copyright: Vadim Lopatin 2014-2018, Andrzej Kilijański 2017-2018, dayllenger 2018-2020
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
    import beamui.core.geometry;
    import beamui.core.i18n;
    import beamui.core.logger;
    import beamui.core.ownership;
    import beamui.core.signals;
    import beamui.core.types;
    import beamui.core.units;

    import beamui.graphics.bitmap;
    import beamui.graphics.colors;
    import beamui.graphics.drawables;
    import beamui.graphics.painter;

    import beamui.layout.alignment;

    import beamui.style.theme : currentTheme;

    import beamui.text.fonts;

    // import beamui.widgets.popup : PopupAlign;
}
package import beamui.style.computed_style;
import std.math : isFinite;
import beamui.core.animations;
import beamui.core.memory : Arena;
import beamui.graphics.compositing : BlendMode;
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
    // general
    automatic,
    arrow,
    none,
    // links
    pointer,
    // status
    contextMenu,
    help,
    progress,
    wait,
    // selection
    cell,
    crosshair,
    text,
    textVertical,
    // drag and drop
    shortcut,
    copy,
    move,
    noDrop,
    notAllowed,
    grab,
    grabbing,
    // resizing
    resizeE,
    resizeN,
    resizeNE,
    resizeNW,
    resizeS,
    resizeSE,
    resizeSW,
    resizeW,
    resizeEW,
    resizeNS,
    resizeNESW,
    resizeNWSE,
    resizeCol,
    resizeRow,
    // scrolling
    scrollAll,
    // zooming
    zoomIn,
    zoomOut,
}

enum DependentSize
{
    none,
    width,
    height,
}

interface IState
{
}

struct WidgetAttributes
{
    private string[string] _map;

    bool has(string name) const
    {
        return (name in _map) !is null;
    }

    void set(string name, string value = null)
        in(name)
    {
        _map[name] = value;
    }
}

W render(W : Widget)()
{
    return Widget.arena.make!W;
}

W render(W : Widget)(scope void delegate(W) conf)
    in(conf)
{
    auto w = Widget.arena.make!W;
    conf(w);
    return w;
}

/// Base class for all widgets
class Widget
{
    uint key = uint.max;
    string id;
    WidgetAttributes attributes;

    bool allowsFocus;
    bool allowsHover;
    /// True if the widget should be interactive and catch mouse and key events
    bool enabled = true;
    bool visible = true;
    bool inheritState;

    bool isolateStyle;
    bool isolateThisStyle;

    bool delegate(KeyEvent) onKeyEvent;
    bool delegate(MouseEvent) onMouseEvent;
    bool delegate(WheelEvent) onWheelEvent;

    dstring tooltip;

    private
    {
        static Arena* _arena;
        static ElementStore* _store;

        ElementID _elementID;
        Widget _parent;

        IState* _statePtr;
    }

    //===============================================================

    protected static Arena* arena()
    {
        version (unittest)
        {
            if (!_arena)
                _arena = new Arena;
        }
        else
            assert(_arena, "Widget allocator is used outside the build function");
        return _arena;
    }

    private Element mount(Widget parent, Element parentElem, size_t index)
    {
        // compute the element ID; it always depends on the widget type
        const typeHash = hashOf(this.classinfo.name);
        ulong mainHash;
        // if the widget has a CSS id, it is unique
        if (id.length)
        {
            mainHash = hashOf(id);
        }
        else
        {
            // use the parent ID, so IDs form a tree structure
            assert(parent, "Widget must have either a string ID or a parent");
            // also use either the key or, as a last resort, the index
            const ulong[2] values = [parent._elementID.value, key != uint.max ? ~key : index];
            mainHash = hashOf(values);
        }
        _elementID = ElementID(typeHash ^ mainHash);
        _parent = parent;
        // find or create the element using the currently bound element store
        Element root = _store.fetch(_elementID, this);
        _statePtr = &root._localState;
        // reparent the element silently
        root._parent = parentElem;
        // clear the old element tree structure
        Element[] prevItems = arena.allocArray!Element(root.childCount);
        foreach (i, ref el; prevItems)
            el = root.child(cast(int)i);
        root.removeAllChildren(false);
        // finish widget configuration
        build();
        // update the element with the data, continue for child widgets
        updateElement(root);

        if (root.childCount || prevItems.length)
            root.diffChildren(prevItems);
        return root;
    }

    final protected Element mountChild(Widget child, Element thisElem, size_t index)
        in(child)
    {
        return child.mount(this, thisElem, index);
    }

    protected S useState(S : IState)()
        in(_statePtr, "The element hasn't mounted yet")
    {
        S s;
        if (*_statePtr)
        {
            s = cast(S)*_statePtr;
            assert(s, "The widget state instance cannot change its type");
        }
        else
        {
            *_statePtr = s = new S;
        }
        return s;
    }

    final protected inout(Widget) parent() inout { return _parent; }

    //===============================================================
    // Internal methods to implement in subclasses

    int opApply(scope int delegate(size_t, Widget) callback)
    {
        return 0;
    }

    protected void build()
    {
    }

    protected Element createElement()
        out(el; el)
    {
        return new Element;
    }

    protected void updateElement(Element el)
        in(el)
    {
        el.id = id;

        if (el.attributes != attributes._map)
        {
            el.attributes = attributes._map;
            el.invalidateStyles();
        }

        el.allowsFocus = allowsFocus;
        el.allowsHover = allowsHover;
        el.applyState(State.enabled, enabled);
        el.visibility = visible ? Visibility.visible : Visibility.hidden;

        if (inheritState)
            el._state |= State.parent;
        else
            el._state &= ~State.parent;

        if (el._style.isolated != isolateStyle)
        {
            el._style.isolated = isolateStyle;
            el.invalidateStyles();
        }
        if (el._thisStyleIsolated != isolateThisStyle)
        {
            el._thisStyleIsolated = isolateThisStyle;
            el.invalidateStyles();
        }

        el.onKeyEvent.clear();
        el.onMouseEvent.clear();
        el.onWheelEvent.clear();
        if (onKeyEvent)
            el.onKeyEvent ~= onKeyEvent;
        if (onMouseEvent)
            el.onMouseEvent ~= onMouseEvent;
        if (onWheelEvent)
            el.onWheelEvent ~= onWheelEvent;

        el.tooltipText = tooltip;
    }
}

abstract class WidgetWrapper : Widget
{
    protected Widget _content;

    final Widget wrap(lazy Widget content)
    {
        _content = content;
        return this;
    }

    override protected int opApply(scope int delegate(size_t, Widget) callback)
    {
        if (const result = callback(0, _content))
            return result;
        return 0;
    }

    override protected Element createElement()
    {
        return new ElemGroup;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        if (_content)
            el.addChild(mountChild(_content, el, 0));
    }
}

abstract class WidgetGroup : Widget
{
    protected Widget[] _children;

    final Widget wrap(Widget[] items...)
    {
        if (items.length == 0)
            return this;

        _children = arena.allocArray!Widget(items.length);
        _children[] = items[];
        return this;
    }

    final Widget wrap(uint count, scope Widget delegate(uint) generator)
    {
        if (count == 0 || !generator)
            return this;

        _children = arena.allocArray!Widget(count);
        foreach (i; 0 .. count)
            _children[i] = generator(i);
        return this;
    }

    override int opApply(scope int delegate(size_t, Widget) callback)
    {
        foreach (i, item; _children)
        {
            if (const result = callback(i, item))
                return result;
        }
        return 0;
    }

    override protected Element createElement()
    {
        return new ElemGroup;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        foreach (i, item; this)
        {
            if (item)
                el.addChild(mountChild(item, el, i));
        }
    }
}

class Panel : WidgetGroup
{
    override protected Element createElement()
    {
        return new ElemPanel;
    }
}

/// Base class for all elements
class Element
{
private:
    /// Type of the widget instantiated this element
    TypeInfo_Class widgetType;
    /// Widget id
    string _id;
    /// Custom attributes map
    string[string] attributes;
    /// See `isolateThisStyle`
    bool _thisStyleIsolated;
    /// If true, the style will be recomputed on next usage
    bool _needToRecomputeStyle = true;

    IState _localState;

    /// Widget state
    State _state = State.normal;
    /// Widget visibility: either visible, hidden, gone
    Visibility _visibility = Visibility.visible; // visible by default

    DependentSize _dependentSize;
    /// Current element boundaries set by `measure`
    Boundaries _boundaries;
    /// Current element box set by `layout`
    Box _box;
    /// Current box without padding and border
    Box _innerBox;
    /// True to force layout
    bool _needLayout = true;
    /// True to force redraw
    bool _needDraw = true;
    /// Parent element
    Element _parent;
    /// Window (to be used for top level widgets only!)
    Window _window;

    bool* _destructionFlag;

    ComputedStyle _style;

    Background _background;
    FontRef _font;

    Animation[string] animations; // key is a property name

protected:
    ElementList _hiddenChildren;

public:

    /// Empty parameter list constructor - for usage by factory
    this()
    {
        _destructionFlag = new bool;
        _style.element = this;
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

        animations.clear();

        _font.clear();
        eliminate(_background);
        // eliminate(_popupMenu);

        *_destructionFlag = true;
    }

    /// Flag for `WeakRef` that indicates widget destruction
    final @property const(bool*) destructionFlag() const { return _destructionFlag; }

    /// Pretty printed name for debugging purposes
    debug string dbgname() const
    {
        string s = getShortClassName(this);
        if (_id.length)
            s ~= '#' ~ id;
        foreach (k, v; attributes)
            if (!v.length) // style class
                s ~= '.' ~ k;
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
    final Element setID(string id)
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
            const oldState = _state;
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
        }
    }
    /// Set or unset `state` flags (a disjunction of `State` options). Returns new state
    State applyState(State flags, bool set)
    {
        const st = set ? (state | flags) : (state & ~flags);
        state = st;
        return st;
    }

    /// Called to process focus changes before `onFocusChange` signal, override to do it
    protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
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

    /// Computed style of this widget. Allows to query and mutate its properties
    final @property inout(ComputedStyle)* style() inout
    {
        updateStyles();
        return &_style;
    }

    /** Enable style encapsulation for the subtree only.

        Cascading and inheritance in this subtree will become independent from
        the outer world. Still, the widget will be accessible via simple selectors.
    */
    final void isolateStyle()
    {
        _style.isolated = true;
        invalidateStyles();
    }
    /** Enable style encapsulation for this widget only.

        This particular widget will not be accessible via simple selectors.
    */
    final void isolateThisStyle()
    {
        _thisStyleIsolated = true;
        invalidateStyles();
    }

    /// Signals when styles are being recomputed. Used for mixing properties in the widget.
    Listener!(void delegate(Style[] chain)) onStyleUpdate;

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
        const Element closure = findStyleScopeRoot();
        // we can skip half of work if the state is normal
        Style[] list = (state == State.normal) ? currentTheme.normalStyles : currentTheme.allStyles;
        foreach (style; list)
            if (matchSelector(style.selector, closure))
                tmpchain ~= style;
        sort(tmpchain.unsafe_slice);
        return tmpchain.unsafe_slice;
    }

    /// Match this widget with a selector
    bool matchSelector(ref const Selector sel) const
    {
        return matchSelector(sel, findStyleScopeRoot());
    }

    private const(Element) findStyleScopeRoot() const
    {
        Element p = cast()_parent;
        while (p)
        {
            if (p._style.isolated)
                return p;
            p = p._parent;
        }
        return null;
    }

    private bool matchSelector(ref const Selector sel, const Element closure) const
    {
        if (this is closure) // get the enclosing scope root and restart
            return matchSelector(sel, findStyleScopeRoot());
        if (sel.universal)
            return matchContextSelector(sel, closure);
        // enclosed elements cannot be styled via simple selectors
        if ((closure || _thisStyleIsolated) && !sel.previous)
            return false;
        // type
        if (sel.type)
        {
            TypeInfo_Class type = widgetType ? cast()widgetType : typeid(this);
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
        if (sel.classes.length && !attributes)
            return false;
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

    private bool matchContextSelector(ref const Selector sel, const Element closure) const
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
                Element p = cast()_parent;
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
                // match with the direct parent
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
        foreach (Element el; this)
            el.invalidateStylesRecursively();
    }

    /// Handle theme change: e.g. reload some themed resources
    void handleThemeChange()
    {
        // default implementation: call recursive for children
        foreach (Element el; this)
            el.handleThemeChange();

        _needToRecomputeStyle = true;
    }

    package(beamui) void handleDPIChange()
    {
        // recompute styles to resolve length units with new DPI
        if (_needToRecomputeStyle)
        {
            _needToRecomputeStyle = false;
            cachedChain.clear();
            cachedChain ~= selectStyleChain();
        }
        _style.recompute(cachedChain.unsafe_slice);
        if (onStyleUpdate.assigned)
            onStyleUpdate(cachedChain.unsafe_slice);

        // continue recursively
        foreach (Element el; this)
            el.handleDPIChange();
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
            Insets p = _style.padding;
            p.add(_style.borderWidth);
            // background image may increase padding
            if (auto bg = _style.backgroundImage)
            {
                const bp = bg.padding;
                p.top = max(p.top, bp.top);
                p.right = max(p.right, bp.right);
                p.bottom = max(p.bottom, bp.bottom);
                p.left = max(p.left, bp.left);
            }
            if (_style.focusRectColor != Color.transparent &&
                (allowsFocus || ((state & State.parent) && parent.allowsFocus)))
            {
                // add two pixels to padding when focus rect is required
                // one pixel for focus rect, one for additional space
                p.add(Insets(FOCUS_RECT_PADDING));
            }
            return p;
        }

        /// Set the widget background (takes ownership on the object)
        void background(Background obj)
            in(obj)
        {
            destroy(_background);
            _background = obj;
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
        case width: .. case maxHeight:
        case paddingTop: .. case paddingLeft:
        case borderTopWidth: .. case borderLeftWidth:
        case marginTop: .. case marginLeft:
        case letterSpacing:
        case lineHeight:
        case tabSize:
        case textHotkey:
        case textIndent:
        case textTransform:
        case whiteSpace:
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
        case textColor:
        case textOverflow:
        case focusRectColor:
        case opacity:
        case mixBlendMode:
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
                return this is w.focusedElement.get && (state & State.focused);
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
    CursorType getCursorType(float x, float y) const
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
/+
    /** Will be called from window once tooltip request timer expired.

        May return `null` if no tooltip to show.
        It's up to widget, to show tooltips outside or not.
    */
    Element createTooltip(float x, float y)
    {
        // default implementation supports tooltips when tooltipText property is set
        import beamui.widgets.text : Label;

        if (_tooltipText && contains(x, y))
            return new Label(_tooltipText).setID("tooltip");
        return null;
    }

    /// Schedule tooltip
    void scheduleTooltip(long delay = 300, PopupAlign alignment = PopupAlign.point,
                         float x = float.max, float y = float.max)
    {
        if (auto w = window)
            w.scheduleTooltip(weakRef(this), delay, alignment, x, y);
    }
+/
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
        const el = focusGroupElement();
        return (el._state & State.windowFocused) != 0;
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
        Element el = focusGroupElement();
        el.setWindowFocusedFlag(flag);
        while (el.parent)
        {
            el = el.parent;
            if (el.parent is null || el.focusGroup)
            {
                el.setWindowFocusedFlag(flag);
            }
        }
    }

    /// Find nearest parent of this widget with `focusGroup` flag.
    /// Returns topmost parent if no `focusGroup` flag set to any of parents
    inout(Element) focusGroupElement() inout
    {
        Element p = cast()this;
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
        Element element;
        uint tabOrder;
        uint childOrder;
        Box box;

        this(Element element)
        {
            this.element = element;
            this.tabOrder = element.thisOrParentTabOrder();
            this.box = element.box;
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
            return element.id;
        }
    }

    private void findFocusableChildren(ref Buf!TabOrderInfo results, Rect clipRect, Element current)
    {
        if (visibility != Visibility.visible)
            return;

        Rect rc = _innerBox;
        if (!rc.intersects(clipRect))
            return; // out of clip rectangle
        if (canFocus || this is current)
        {
            results ~= new TabOrderInfo(this);
            return;
        }
        rc.intersect(clipRect);
        foreach (Element el; this)
            el.findFocusableChildren(results, rc, current);
    }

    /// Find all focusables belonging to the same `focusGroup` as this widget (does not include current widget).
    /// Usually to be called for focused widget to get possible alternatives to navigate to
    private Buf!TabOrderInfo findFocusables(Element current)
    {
        Buf!TabOrderInfo result;
        Element group = focusGroupElement();
        group.findFocusableChildren(result, Rect(group.box), current);
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
    private Element findNextFocusWidget(FocusMovement direction)
    {
        if (direction == FocusMovement.none)
            return this;
        auto focusables = findFocusables(this);
        if (focusables.length == 0)
            return null;
        int myIndex = -1;
        for (int i = 0; i < focusables.length; i++)
        {
            if (focusables[i].element is this)
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
            return focusables.unsafe_ref(0).element; // single option - use it
        if (direction == FocusMovement.next)
        {
            // move forward
            int index = myIndex + 1;
            if (index >= focusables.length)
                index = 0;
            return focusables.unsafe_ref(index).element;
        }
        else if (direction == FocusMovement.previous)
        {
            // move back
            int index = myIndex - 1;
            if (index < 0)
                index = cast(int)focusables.length - 1;
            return focusables.unsafe_ref(index).element;
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
                if (focusables[i].element is this)
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
            return focusables.unsafe_ref(index).element;
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
        Element nextOne = findNextFocusWidget(direction);
        if (!nextOne)
            return false;
        nextOne.setFocus(FocusReason.tabFocus);
        return true;
    }

    /// Set focus to this widget or suitable focusable child, returns previously focused widget
    Element setFocus(FocusReason reason = FocusReason.unspecified)
    {
        if (window is null)
            return null;
        if (!visible)
            return window.focusedElement.get;
        invalidate();
        if (!canFocus)
        {
            Element el = findFocusableChild(true);
            if (!el)
                el = findFocusableChild(false);
            if (el)
                return window.setFocus(weakRef(el), reason);
            // try to find focusable child
            return window.focusedElement.get;
        }
        return window.setFocus(weakRef(this), reason);
    }
    /// Search children for first focusable item, returns `null` if not found
    Element findFocusableChild(bool defaultOnly)
    {
        foreach (Element el; this)
        {
            if (el.canFocus && (!defaultOnly || (el.state & State.default_) != 0))
                return el;
            el = el.findFocusableChild(defaultOnly);
            if (el !is null)
                return el;
        }
        if (canFocus)
            return this;
        return null;
    }

    //===============================================================
    // Signals

    /// On click event listener
    Signal!(void delegate()) onClick;

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
            bool* destroyed = _destructionFlag;
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

    /** Process key event, return true if event is processed.

        Hidden and disabled widgets should not receive these events.
    */
    bool handleKeyEvent(KeyEvent event)
    {
        // handle focus navigation using keys
        if (focused && handleMoveFocusUsingKeys(event))
            return true;
        if (_allowsClick)
        {
            // support onClick event initiated by Space or Return keys
            if (event.key == Key.space || event.key == Key.enter)
            {
                if (event.action == KeyAction.keyDown)
                {
                    applyState(State.pressed, true);
                    return true;
                }
                if (event.action == KeyAction.keyUp)
                {
                    if (state & State.pressed)
                    {
                        applyState(State.pressed, false);
                        handleClick();
                        onClick();
                    }
                    return true;
                }
            }
        }
        return false;
    }

    /** Process mouse event; return true if event is processed by widget.

        Hidden and disabled widgets should not receive these events.
    */
    bool handleMouseEvent(MouseEvent event)
    {
        debug (mouse)
            Log.fd("mouse event, '%s': %s  (%s, %s)", id, event.action, event.x, event.y);
        // support click
        if (_allowsClick)
        {
            if (event.button == MouseButton.left)
            {
                if (event.action == MouseAction.buttonDown)
                {
                    applyState(State.pressed, true);
                    if (_allowsFocus)
                        setFocus();
                    return true;
                }
                if (event.action == MouseAction.buttonUp)
                {
                    if (state & State.pressed)
                    {
                        applyState(State.pressed, false);
                        handleClick();
                        onClick();
                    }
                    return true;
                }
            }
            if (event.action == MouseAction.focusIn)
            {
                applyState(State.pressed, true);
                return true;
            }
            if (event.action == MouseAction.focusOut)
            {
                applyState(State.pressed, false);
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                applyState(State.pressed | State.hovered, false);
                return true;
            }
        }
/+
        if (event.action == MouseAction.move && event.noKeyMods && event.noMouseMods && hasTooltip)
        {
            scheduleTooltip(600);
        }
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.right)
        {
            if (canShowPopupMenu(event.x, event.y))
            {
                if (_allowsFocus)
                    setFocus();
                showPopupMenu(event.x, event.y);
                return true;
            }
        }
+/
        if (_allowsFocus && event.action == MouseAction.buttonDown && event.button == MouseButton.left)
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
                    applyState(State.hovered, false);
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
                        applyState(State.hovered, true);
                }
                return true;
            }
            if (event.action == MouseAction.leave)
            {
                debug (mouse)
                    Log.d("Leave ", id);
                applyState(State.hovered, false);
                return true;
            }
        }
        return false;
    }

    /** Process wheel event, return true if the event is processed.

        Hidden and disabled widgets should not receive these events.
    */
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
    bool contains(float x, float y) const
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

    /** Measure element - compute minimal, natural and maximal sizes of the border box.

        This method calls `computeBoundaries` to get raw size information,
        applies `padding` and styling such as min-width to it, fixes overflows,
        and assigns the result to `boundaries`.

        This method may return early without calling `computeBoundaries`
        if no elements in the sub-tree requested layout.
    */
    final void measure()
    {
        const Size p = padding.size; // updates style
        Boundaries bs = computeBoundaries();
        assert(isFinite(bs.min.w) && isFinite(bs.min.h));
        assert(isFinite(bs.nat.w) && isFinite(bs.nat.h));
        // ignore percentages here - the parent layout will compute them itself
        const minw = _style.minWidth;
        const minh = _style.minHeight;
        const maxw = _style.maxWidth;
        const maxh = _style.maxHeight;
        const w = _style.width;
        const h = _style.height;
        // the content-based min size doesn't need to include padding.
        // if the size is specified in styles, use it
        if (minw.isDefined)
        {
            bs.min.w = minw.applyPercent(0);
            bs.nat.w = max(bs.nat.w, bs.min.w - p.w, 0);
        }
        else
        {
            bs.min.w = max(bs.min.w, 0);
            bs.nat.w = max(bs.nat.w, bs.min.w);
        }
        if (minh.isDefined)
        {
            bs.min.h = minh.applyPercent(0);
            bs.nat.h = max(bs.nat.h, bs.min.h - p.h, 0);
        }
        else
        {
            bs.min.h = max(bs.min.h, 0);
            bs.nat.h = max(bs.nat.h, bs.min.h);
        }
        // use the smallest of content-based and specified max sizes
        bs.max.w += p.w;
        bs.max.h += p.h;
        if (!maxw.isPercent)
            bs.max.w = min(bs.max.w, maxw.applyPercent(0));
        if (!maxh.isPercent)
            bs.max.h = min(bs.max.h, maxh.applyPercent(0));
        // min size is more important
        bs.max.w = max(bs.max.w, bs.min.w);
        bs.max.h = max(bs.max.h, bs.min.h);
        // if the preferred size is specified in styles, use it
        if (w.isDefined && !w.isPercent)
            bs.nat.w = w.applyPercent(0);
        else
            bs.nat.w += p.w;
        if (h.isDefined && !h.isPercent)
            bs.nat.h = h.applyPercent(0);
        else
            bs.nat.h += p.h;
        bs.nat.w = clamp(bs.nat.w, bs.min.w, bs.max.w);
        bs.nat.h = clamp(bs.nat.h, bs.min.h, bs.max.h);
        // done
        _boundaries = bs;
    }

    protected Boundaries computeBoundaries()
    {
        return Boundaries.init;
    }

    /// Returns natural height for the given width
    float heightForWidth(float width)
    {
        return _boundaries.nat.h;
    }
    /// Returns natural width for the given height
    float widthForHeight(float height)
    {
        return _boundaries.nat.w;
    }

    /** Set widget box and lay out widget contents.

        It computes `innerBox`, shrink padding if necessary, and calls
        `arrangeContent` to lay out the rest.

        If you need a custom layout logic, in 99% of situations you should
        override `arrangeContent` method instead of this one.
    */
    void layout(Box geometry)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        alias b = geometry;
        assert(isFinite(b.x) && isFinite(b.y));
        assert(isFinite(b.w) && isFinite(b.h));
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
        _box = snapToDevicePixels(b);
        _innerBox = snapToDevicePixels(b.shrinked(p));
        arrangeContent();
    }

    /// Called from `layout`, after `box` and `innerBox` were set
    protected void arrangeContent()
    {
    }

    /// Draw widget at its position
    final void draw(Painter pr)
    {
        _needDraw = false;
        if (visibility != Visibility.visible)
            return;

        const b = _box;
        if (pr.quickReject(b))
            return; // clipped out

        updateStyles();
        const opacity = _style.opacity;
        if (opacity < 0.001f)
            return;
        // begin a layer if needed
        const blendMode = _style.mixBlendMode;
        PaintSaver lsv;
        if (opacity < 0.999f || blendMode != BlendMode.normal)
            pr.beginLayer(lsv, opacity, blendMode);

        // draw the background first
        _background.color = _style.backgroundColor;
        _background.image = _style.backgroundImage;
        _background.position = _style.backgroundPosition;
        _background.size = _style.backgroundSize;
        _background.origin = _style.backgroundOrigin;
        _background.clip = _style.backgroundClip;
        _background.border = Border(
            BorderSide(
                _style.borderTopWidth,
                _style.borderTopStyle,
                _style.borderTopColor,
            ),
            BorderSide(
                _style.borderRightWidth,
                _style.borderRightStyle,
                _style.borderRightColor,
            ),
            BorderSide(
                _style.borderBottomWidth,
                _style.borderBottomStyle,
                _style.borderBottomColor,
            ),
            BorderSide(
                _style.borderLeftWidth,
                _style.borderLeftStyle,
                _style.borderLeftColor,
            ),
        );
        {
            const tl = _style.borderTopLeftRadius;
            const tr = _style.borderTopRightRadius;
            const bl = _style.borderBottomLeftRadius;
            const br = _style.borderBottomRightRadius;
            _background.radii = BorderRadii(
                Size(tl.applyPercent(box.w), tl.applyPercent(box.h)),
                Size(tr.applyPercent(box.w), tr.applyPercent(box.h)),
                Size(bl.applyPercent(box.w), bl.applyPercent(box.h)),
                Size(br.applyPercent(box.w), br.applyPercent(box.h)),
            );
        }
        _background.shadow = _style.boxShadow;
        _background.stylePadding = _style.padding;
        _background.drawTo(pr, b);
        // draw contents
        {
            PaintSaver sv;
            pr.save(sv);
            drawContent(pr);
        }
        // draw an additional frame
        if (state & State.focused)
            drawFocusRect(pr);
    }

    protected void drawContent(Painter pr)
    {
    }

    /// Draw focus rectangle, if enabled in styles
    protected void drawFocusRect(Painter pr)
    {
        const Color c = style.focusRectColor;
        if (!c.isFullyTransparent)
        {
            RectI rc = RectI(BoxI.from(_box));
            rc.shrink(FOCUS_RECT_PADDING, FOCUS_RECT_PADDING);
            drawDottedLineH(pr, rc.left, rc.right, rc.top, c);
            drawDottedLineH(pr, rc.left, rc.right, rc.bottom - 1, c);
            drawDottedLineV(pr, rc.left, rc.top + 1, rc.bottom - 1, c);
            drawDottedLineV(pr, rc.right - 1, rc.top + 1, rc.bottom - 1, c);
        }
    }

    /** Just draw all children. Used as default behaviour in some widgets.

        Example:
        ---
        override protected void drawContent(Painter pr)
        {
            drawAllChildren(pr);
        }
        ---
    */
    protected void drawAllChildren(Painter pr)
    {
        if (visibility != Visibility.visible)
            return;

        foreach (i; 0 .. childCount)
            child(i).draw(pr);
    }

    //===============================================================
    // Popup (contextual) menu support
/+
    private Menu _popupMenu;
    /// Popup (contextual menu), associated with this widget
    @property Menu popupMenu() { return _popupMenu; }
    /// ditto
    @property void popupMenu(Menu popupMenu)
    {
        _popupMenu = popupMenu;
    }

    /// Returns true if widget can show popup menu (e.g. by mouse right click at point x,y)
    bool canShowPopupMenu(float x, float y)
    {
        if (_popupMenu is null)
            return false;
        if (_popupMenu.openingSubmenu.assigned)
            if (!_popupMenu.openingSubmenu(_popupMenu))
                return false;
        return true;
    }
    /// Shows popup menu at (x,y)
    void showPopupMenu(float x, float y)
    {
        // if preparation signal handler assigned, call it; don't show popup if false is returned from handler
        if (_popupMenu.openingSubmenu.assigned)
            if (!_popupMenu.openingSubmenu(_popupMenu))
                return;

        import beamui.widgets.popup;

        auto popup = window.showPopup(_popupMenu, weakRef(this), PopupAlign.point | PopupAlign.right, x, y);
        popup.ownContent = false;
    }
+/
    //===============================================================
    // Widget hierarhy methods

    /// Returns number of children of this widget
    @property int childCount() const
    {
        return 0;
    }
    /// Returns child by index
    inout(Element) child(int index) inout
    {
        return null;
    }

    protected void diffChildren(Element[] oldItems)
    {
        assert(0);
    }

    /// Add a child. Returns the added item with its original type
    T addChild(T)(T item) if (is(T : Element))
    {
        addChildImpl(item);
        return item;
    }
    /// Append several children
    final void add(Element first, Element[] next...)
    {
        addChildImpl(first);
        foreach (item; next)
            addChildImpl(item);
    }
    /// Append several children, skipping `null` widgets
    final void addSome(Element first, Element[] next...)
    {
        if (first)
            addChildImpl(first);
        foreach (item; next)
            if (item)
                addChildImpl(item);
    }
    protected void addChildImpl(Element item)
    {
        assert(false, "addChild: this widget does not support having children");
    }

    /// Insert child before given index, returns inserted item
    Element insertChild(int index, Element item)
    {
        assert(false, "insertChild: this widget does not support having children");
    }
    /// Remove child by index, returns removed item
    Element removeChild(int index)
    {
        assert(false, "removeChild: this widget does not support having children");
    }
    /// Remove child by ID, returns removed item
    Element removeChild(string id)
    {
        assert(false, "removeChild: this widget does not support having children");
    }
    /// Remove child, returns removed item
    Element removeChild(Element child)
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
    int childIndex(const Element item) const
    {
        return -1;
    }

    /** Returns true if item is child of this widget.

        When `deepSearch == true`, returns true if item is this widget
        or one of children inside children tree.
    */
    bool isChild(Element item, bool deepSearch = true)
    {
        // the contract is that any widget in the tree must have a parent
        if (deepSearch)
        {
            Element p = item;
            while (p)
            {
                if (this is p)
                    return true;
                p = p.parent;
            }
            return false;
        }
        else
            return this is item.parent;
    }

    /// Find child of specified type `T` by id, returns `null` if not found or cannot be converted to type `T`
    T childByID(T = typeof(this))(string id, bool deepSearch = true)
    {
        if (deepSearch)
        {
            // search everywhere inside child tree
            if (compareID(id))
            {
                if (T found = cast(T)this)
                    return found;
            }
            // lookup children
            foreach (Element el; this)
            {
                if (T found = el.childByID!T(id))
                    return found;
            }
        }
        else
        {
            // search only across children of this widget
            foreach (Element el; this)
            {
                if (el.compareID(id))
                {
                    if (T found = cast(T)el)
                        return found;
                }
            }
        }
        // not found
        return null;
    }

    final int opApply(scope int delegate(Element) callback)
    {
        foreach (i; 0 .. childCount)
        {
            if (const result = callback(child(i)))
                return result;
        }
        foreach (el; _hiddenChildren.unsafe_slice)
        {
            if (const result = callback(el))
                return result;
        }
        return 0;
    }

    final int opApplyReverse(scope int delegate(Element) callback)
    {
        foreach_reverse (i; 0 .. childCount)
        {
            if (const result = callback(child(i)))
                return result;
        }
        foreach_reverse (el; _hiddenChildren.unsafe_slice)
        {
            if (const result = callback(el))
                return result;
        }
        return 0;
    }

    /// Parent widget, `null` for top level widget
    @property inout(Element) parent() inout { return _parent; }
    /// ditto
    @property void parent(Element widget)
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
        Element p = cast()this;
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

/// Element list holder
alias ElementList = Collection!(Element, true);

/** Base class for widgets which have children.

    Added children will correctly handle destruction of parent widget and theme change.

    If your widget has subwidgets which do not need to catch mouse and key events, focus, etc,
    you may not use this class. You may inherit directly from the Widget class
    and add code for subwidgets to destructor, `handleThemeChange`, and `draw` (if needed).
*/
class ElemGroup : Element
{
    private ElementList _children;

    override @property int childCount() const
    {
        return cast(int)_children.count;
    }

    override inout(Element) child(int index) inout
    {
        return _children[index];
    }

    override protected void diffChildren(Element[] oldItems)
    {
        if (!_children.count && !oldItems.length)
            return;

        const limit = min(_children.count, oldItems.length);
        size_t unchanged = limit;
        foreach (i; 0 .. limit)
        {
            if (_children[i] !is oldItems[i])
            {
                unchanged = i;
                break;
            }
        }
        if (unchanged != oldItems.length || _children.count != oldItems.length)
        {
            _needToRecomputeStyle = true;
            requestLayout();
            foreach (i; unchanged .. _children.count)
            {
                Element el = _children[i];
                assert(el && el._parent is this);
                el.invalidateStylesRecursively();
                el.requestLayout();
            }
            handleChildListChange();
        }
    }

    override protected void addChildImpl(Element item)
    {
        assert(item, "Element must exist");
        _children.append(item);
        item.parent = this;
        handleChildListChange();
    }

    override Element insertChild(int index, Element item)
    {
        assert(item, "Element must exist");
        _children.insert(index, item);
        item.parent = this;
        handleChildListChange();
        return item;
    }

    override Element removeChild(int index)
    {
        Element result = _children.remove(index);
        assert(result);
        result.parent = null;
        handleChildListChange();
        return result;
    }

    override Element removeChild(string id)
    {
        int index = cast(int)_children.indexOf(id);
        return index >= 0 ? removeChild(index) : null;
    }

    override Element removeChild(Element child)
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
        handleChildListChange();
    }

    override int childIndex(string id) const
    {
        return cast(int)_children.indexOf(id);
    }

    override int childIndex(const Element item) const
    {
        return cast(int)_children.indexOf(item);
    }

    /// Replace one child with another. It DOES NOT destroy the old item
    void replaceChild(Element oldChild, Element newChild)
    {
        assert(newChild && oldChild, "Elements must exist");
        _children.replace(oldChild, newChild);
        oldChild.parent = null;
        newChild.parent = this;
        handleChildListChange();
    }

    protected void handleChildListChange()
    {
    }
}

interface ILayout
{
    void onSetup(Element host);
    void onDetach();
    void onStyleChange(StyleProperty p);
    void onChildStyleChange(StyleProperty p);

    void prepare(ref Buf!Element list);
    Boundaries measure();
    void arrange(Box box);
}

/** Panel is a widget group with some layout.

    By default, without specified layout, it places all children to fill its
    inner frame (usually, only one child should be visible at a time, see
    `showChild` method).
*/
class ElemPanel : ElemGroup
{
    import beamui.layout.factory : createLayout;

    private string _kind;
    private ILayout _layout;
    private Buf!Element preparedItems;

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

    override protected Boundaries computeBoundaries()
    {
        updateStyles();

        preparedItems.clear();
        foreach (i; 0 .. childCount)
        {
            Element item = child(i);
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
        return bs;
    }

    override protected void arrangeContent()
    {
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

    override protected void drawContent(Painter pr)
    {
        foreach (item; preparedItems.unsafe_slice)
            item.draw(pr);
    }

    /// Make one child (with specified ID) visible, set `othersVisibility` to the rest
    bool showChild(string ID, Visibility othersVisibility = Visibility.hidden, bool updateFocus = false)
    {
        bool found;
        Element foundItem;
        foreach (i; 0 .. childCount)
        {
            Element item = child(i);
            if (item.compareID(ID))
            {
                item.visibility = Visibility.visible;
                foundItem = item;
                found = true;
            }
            else
                item.visibility = othersVisibility;
        }
        if (found && updateFocus)
            foundItem.setFocus();
        return found;
    }
}

/** An integer identifier to map temporal widgets onto persistent elements.

    It is unique inside the window and stable between rebuilds of the widget tree.
*/
struct ElementID
{
    ulong value;
}

/// Contains every alive element of the window by `ElementID`
struct ElementStore
{
    static uint instantiations;

    private Element[ElementID] map;

    private this(int);
    @disable this(this);

    ~this()
    {
        eliminate(map);
    }

    Element fetch(ElementID id, Widget caller)
        in(id.value)
        in(caller)
    {
        Element el;
        if (auto p = id in map)
        {
            el = *p;
        }
        else
        {
            map[id] = el = caller.createElement();
            el.widgetType = typeid(caller);
            instantiations++;
        }
        return el;
    }

    void clear()
    {
        eliminate(map);
    }
}

// to access from the window
package(beamui) void setCurrentArenaAndStore(ref Arena arena, ref ElementStore store)
{
    Widget._arena = &arena;
    Widget._store = &store;
}

package(beamui) Element mountRoot(Widget root)
{
    return root.mount(null, null, 0);
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
