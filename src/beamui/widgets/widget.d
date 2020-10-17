/**
Contains core classes and ancillary types of the widget system.

Copyright: Vadim Lopatin 2014-2018, Andrzej Kilijański 2017-2018, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.widget;

public
{
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
    import beamui.events.event;
    import beamui.events.keyboard;
    import beamui.events.pointer;
    import beamui.events.wheel;
    import beamui.graphics.bitmap;
    import beamui.graphics.colors : Color, NamedColor;
    import beamui.graphics.drawables;
    import beamui.graphics.painter : LayerInfo, Painter, PaintSaver;
    import beamui.layout.alignment : Align, AlignItem, Distribution, Stretch;
    import beamui.platforms.common.platform : setState;
    import beamui.style.theme : WindowTheme;
    import beamui.widgets.popup : PopupAlign;
}
package
{
    import beamui.style.computed_style;
    import beamui.text.fonts;
}
import std.algorithm.mutation : swap, SwapStrategy;
import std.math : isFinite;
import beamui.core.memory : Arena;
import beamui.graphics.compositing : BlendMode;
import beamui.platforms.common.platform;
import beamui.style.selector;
import beamui.style.style;
import beamui.style.types : SingleTransformKind;
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
enum FocusMovement : ubyte
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
enum CursorType : ubyte
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

enum DependentSize : ubyte
{
    none,
    width,
    height,
}

struct WidgetKey
{
    size_t computed = size_t.max;

    this(T)(T anyValue) if (!is(T : WidgetKey))
    {
        // avoid the situation when the key is set to some existing index
        computed = ~hashOf(anyValue) - 1;
    }

    ref WidgetKey opAssign(T)(T anyValue) if (!is(T : WidgetKey))
    {
        computed = WidgetKey(anyValue).computed;
        return this;
    }

    bool opCast(To : bool)() const
    {
        return computed != size_t.max;
    }
}

struct WidgetAttributes
{
    private string[string] _map; // TODO: rewrite to something faster

    bool has(string name) const
    {
        return (name in _map) !is null;
    }

    /** Set a style class of the `name`.

        Note: the name must have non-zero length.
    */
    void opIndex(string name)
    in (name.length)
    {
        _map[name] = null;
    }

    /** Set a custom attribute of the `name` and `value`.

        Note: the name must have non-zero length.
    */
    void opIndexAssign(string value, string name)
    in (name.length)
    {
        _map[name] = value;
    }
}

/** Creates a widget using a fast memory allocator.

    The first way to use it is more declarative and appropriate
    in writing widget hierarchies:
    ---
    render((Control c) {
        // this function is called immediately.
        // it's sole purpose is to setup widget properties.
        // it's more flexible than named arguments could be.
        c.text = "Fire";
        c.onClick = &fire;
    })
    ---

    The second way is simpler and gives more control:
    ---
    Control c = render!Control;
    c.text = "Fire";
    c.onClick = &fire;
    ---

    You may also create an alias and use UFCS:
    ---
    alias wgt = render;

    (Control c) {
        c.text = "Fire";
        c.onClick = &fire;
    }.wgt
    ---

    You may create widgets using `new` operator or any other method,
    if your task requires so, but in 99.9% of cases you should use
    this function. It's fast and deterministic.
*/
W render(W : Widget)()
{
    return Widget.arena.make!W;
}
/// ditto
W render(W : Widget)(scope void delegate(W) conf)
in (conf)
{
    auto w = Widget.arena.make!W;
    conf(w);
    return w;
}

/// Base class for all widgets
class Widget
{
    WidgetKey key;
    string id;
    WidgetAttributes attributes;

    /// True if the widget can be focused
    bool allowsFocus;
    /// True if the widget will change `hovered` state while mouse pointer is moving upon it
    bool allowsHover;
    /// True if the widget should be interactive and catch mouse and key events
    bool enabled = true;
    bool visible = true;
    bool inheritState;

    /** Focus group flag for container widget.

        When focus group is set for some parent widget, focus from one of containing widgets can be moved
        using keyboard only to one of other widgets containing in it and cannot bypass bounds of `focusGroup`.
        If focused widget doesn't have any parent with `focusGroup == true`,
        focus may be moved to any focusable within window.
    */
    bool focusGroup;
    /// Tab order - hint for focus movement using Tab/Shift+Tab
    ushort tabOrder;

    string namespace = "beamui";
    /// Isolate inheritance of style properties for the widget sub-tree (including this widget)
    bool isolateStyle;

    bool delegate(KeyEvent) onKeyEvent;
    bool delegate(MouseEvent) onMouseEvent;
    bool delegate(WheelEvent) onWheelEvent;
    // experimental
    void delegate(string) onAnimationStart;
    void delegate(string) onAnimationEnd;

    dstring tooltip;

    private
    {
        static BuildContext _ctx;

        InlineStyle* _style;

        Widget _parent;
        WidgetID _widgetID;

        WidgetState _state;
        Element _element;
    }

    final void style(ref InlineStyle st)
    {
        if (!_style)
            _style = _ctx.arena.make!InlineStyle;
        *_style = st;
    }

    final WeakRef!(const(Element)*) elementRef() const
    in (_element, "The element hasn't mounted yet")
    {
        return weakRef(&_element);
    }

    //===============================================================

    static protected Arena* arena()
    {
        version (unittest)
        {
            if (!_ctx.arena)
                _ctx.arena = new Arena;
        }
        else
            assert(_ctx.arena, "Widget allocator is used outside the build function");
        return _ctx.arena;
    }

    /// May return `null`
    final protected Element mountChild(Widget child, size_t index, bool append = true)
    {
        if (!child)
            return null;

        child._parent = this;
        const wid = child._widgetID = child.computeID(this, index);

        // find or create widget state object using the currently bound state store
        WidgetState st = child._state = _ctx.stateStore.fetch(wid, child);
        // propagate state age
        if (_state.childrenTTL == 0)
            st.age = _state.age;
        else
            st.age = _ctx.stateStore.age + _state.childrenTTL;

        // find or create the element
        Element el = child._element = _ctx.elemStore.fetch(wid, child);
        if (el)
        {
            assert(_element, "Must have a parent element");
            // reparent the element silently
            el._parent = _element;
            // continue
            child.mountRecursively();
            if (append)
                _element.addChild(el);
        }
        else
        {
            // no element
            child.mountRecursivelyWithoutElement();
        }
        return el;
    }

    private WidgetID computeID(Widget parent, size_t index)
    in (parent, "Widget must have a parent")
    {
        import std.digest.murmurhash : MurmurHash3;

        MurmurHash3!128 hasher;

        // compute the element ID; it always depends on the widget type
        const type = cast(void*)this.classinfo;
        hasher.put((cast(ubyte*)&type)[0 .. size_t.sizeof]);
        // if the widget has a CSS id, it is unique
        if (id.length)
        {
            hasher.put(cast(ubyte[])id);
        }
        else
        {
            // use the parent ID, so IDs form a tree structure
            hasher.put(parent._widgetID.value);
            // also use either the key or, as a last resort, the index
            const k = key ? key.computed : index;
            hasher.put((cast(ubyte*)&k)[0 .. size_t.sizeof]);
        }
        return WidgetID(hasher.finish());
    }

    private void mountRecursively()
    {
        _element._buildInProgress = true;

        // clear the old element tree structure
        Element[] prevItems = arena.allocArray!Element(_element.childCount);
        foreach (i, ref el; prevItems)
            el = _element.child(cast(int)i);
        _element.removeAllChildren(false);
        // finish widget configuration
        build();
        // update the element with the data, continue for child widgets
        updateElement(_element);

        if (_element.childCount || prevItems.length)
            _element.diffChildren(prevItems);

        _element._buildInProgress = false;
    }

    private void mountRecursivelyWithoutElement()
    {
        build();
        foreach (i, item; this)
        {
            mountChild(item, i);
        }
    }

    protected inout(S) use(S : WidgetState)() inout
    in (_state, "The state hasn't mounted yet")
    out (s; s, "The widget state has another type: " ~ _state.classinfo.name)
    {
        return cast(inout(S))_state;
    }

    final protected inout(Widget) parent() inout
    {
        return _parent;
    }

    final protected inout(Window) window() inout
    {
        Widget p = cast()this;
        while (p)
        {
            if (p._element && p._element._window)
                return cast(inout)p._element._window;
            p = p._parent;
        }
        assert(0, "The element hasn't mounted yet");
    }

    //===============================================================
    // Internal methods to implement in subclasses

    int opApply(scope int delegate(size_t, Widget) callback)
    {
        return 0;
    }

    protected void build()
    {
    }

    protected WidgetState createState()
    out (st; st)
    {
        return new WidgetState;
    }

    protected Element createElement()
    {
        return new Element;
    }

    protected void updateElement(Element el)
    in (el)
    {
        el.id = id;

        if (el.attributes != attributes._map)
        {
            el.attributes = attributes._map;
            el.invalidateStyles();
        }

        el.allowsFocus = allowsFocus;
        el.allowsHover = allowsHover;
        el.applyFlags(StateFlags.enabled, enabled);
        el.visibility = visible ? Visibility.visible : Visibility.hidden;

        if (inheritState)
            el._stateFlags |= StateFlags.parent;
        else
            el._stateFlags &= ~StateFlags.parent;

        el.focusGroup = focusGroup;
        el.tabOrder = tabOrder;

        if (!namespace.length)
            namespace = _parent.namespace;
        if (el._namespace != namespace)
        {
            el._namespace = namespace;
            el.invalidateStyles();
        }
        if (el._style.isolated != isolateStyle)
        {
            el._style.isolated = isolateStyle;
            el.invalidateStyles();
        }

        el._inlineStyle = _style;

        el.onKeyEvent.clear();
        el.onMouseEvent.clear();
        el.onWheelEvent.clear();
        el.onAnimationStart.clear();
        el.onAnimationEnd.clear();

        if (onKeyEvent)
            el.onKeyEvent ~= onKeyEvent;
        if (onMouseEvent)
            el.onMouseEvent ~= onMouseEvent;
        if (onWheelEvent)
            el.onWheelEvent ~= onWheelEvent;
        if (onAnimationStart)
            el.onAnimationStart ~= onAnimationStart;
        if (onAnimationEnd)
            el.onAnimationEnd ~= onAnimationEnd;

        el.tooltipText = tooltip;
    }
}
// dfmt off
struct WidgetPair(A : Widget, B : Widget)
{
    A a;
    B b;

    this(A a, B b)
    {
        this.a = a;
        this.b = b;
    }

    this(TA : A, TB : B)(scope void delegate(TA) confA, scope void delegate(TB) confB)
    {
        a = render(confA);
        b = render(confB);
    }
}
// dfmt on
abstract class WidgetWrapperOf(W : Widget) : Widget
{
    protected W _content;

    final WidgetWrapperOf!W wrap(W content)
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

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        mountChild(_content, 0);
    }
}

abstract class WidgetGroupOf(W : Widget) : Widget
{
    protected W[] _children;

    final WidgetGroupOf!W wrap(W[] items...)
    {
        if (items.length == 0)
            return this;

        _children = arena.allocArray!W(items.length);
        _children[] = items[];
        return this;
    }

    final WidgetGroupOf!W wrap(uint count, scope W delegate(uint) generator)
    {
        if (count == 0 || !generator)
            return this;

        _children = arena.allocArray!W(count);
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

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        foreach (i, item; this)
        {
            mountChild(item, i);
        }
    }
}

/** Panel is a widget group with some layout.

    Layout type is controlled via `display` style property. By default, without specified layout,
    panel places all children on top of each other inside its padding box.
*/
class Panel : WidgetGroupOf!Widget
{
    override protected Element createElement()
    {
        return new ElemPanel;
    }
}

class WidgetState
{
    protected uint childrenTTL;
    private ulong age = ulong.max; // no one dies by default
}

/** Base class for all elements.

    All products of `measure` and `layout` are in device-independent pixels.
*/
class Element
{
private:
    /// Style namespace
    string _namespace = "beamui";
    /// Type of the widget instantiated this element
    TypeInfo_Class widgetType;
    /// Widget id
    string _id;
    /// Custom attributes map
    string[string] attributes;

    /// Widget state
    StateFlags _stateFlags = StateFlags.normal;
    /// Widget visibility: either visible, hidden, gone
    Visibility _visibility = Visibility.visible; // visible by default

    DependentSize _dependentSize;
    /// Current element boundaries set by `measure`
    Boundaries _boundaries;
    /// Current element box set by `layout`
    Box _box;
    /// Current box without padding and border
    Box _innerBox;
    /// Absolute position of this coordinate system origin
    Point _origin;
    /// Parent element
    Element _parent;
    /// Window (to be used for top level widgets only!)
    Window _window;

    /// Defines what kind of style recalculation is needed. Higher stages include lower ones
    enum StyleInvalidation : ubyte
    {
        none,
        recompute,
        match,
    }

    StyleInvalidation _styleInvalidation = StyleInvalidation.match;
    /// True to force layout
    bool _needLayout = true;
    /// True to force redraw
    bool _needDraw = true;

    bool* _destructionFlag;

    InlineStyle* _inlineStyle;
    ComputedStyle _style;

    Background _background;
    Overlay _overlay;
    FontRef _font;

    static Background _sharedBackground;
    static Overlay _sharedOverlay;

protected:
    ElementList _hiddenChildren;

public:

    /// Empty parameter list constructor - for usage by factory
    this()
    {
        if (!_sharedBackground)
        {
            _sharedBackground = new Background;
            _sharedOverlay = new Overlay;
        }
        _background = _sharedBackground;
        _overlay = _sharedOverlay;
        _destructionFlag = new bool;
        _style.element = this;
        debug const count = debugPlusInstance();
        debug (resalloc)
            Log.fd("Created element (count: %s): %s", count, dbgname());
    }

    ~this()
    {
        debug const count = debugMinusInstance();
        debug (resalloc)
            Log.fd("Destroyed element (count: %s): %s", count, dbgname());

        if (_background !is _sharedBackground)
            destroy(_background);
        if (_overlay !is _sharedOverlay)
            destroy(_overlay);
        _font.clear();
        // eliminate(_popupMenu);

        if (_destructionFlag) // may be `null` if constructor of a subclass fails
            *_destructionFlag = true;
    }

    mixin DebugInstanceCount;

    /// Flag for `WeakRef` that indicates element destruction
    final @property const(bool*) destructionFlag() const
    {
        return _destructionFlag;
    }

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
    @property string id() const
    {
        return _id;
    }
    /// ditto
    @property void id(string id)
    {
        if (_id != id)
        {
            _id = id;
            invalidateStyles();
        }
    }
    /// Compare element id with specified value, returns true if matches
    bool compareID(string id) const
    {
        return (_id !is null) && id == _id;
    }

    //===============================================================
    // State

    /// Set of widget state flags
    @property StateFlags stateFlags() const
    {
        if ((_stateFlags & StateFlags.parent) != 0 && _parent !is null)
            return _parent.stateFlags;
        return _stateFlags;
    }
    /// ditto
    @property void stateFlags(StateFlags newState)
    {
        if ((_stateFlags & StateFlags.parent) != 0 && _parent !is null)
            return _parent.stateFlags(newState);
        if (newState != _stateFlags)
        {
            const oldState = _stateFlags;
            _stateFlags = newState;
            // need to recompute the style
            invalidateStyles();
            // notify focus changes
            if ((oldState & StateFlags.focused) && !(newState & StateFlags.focused))
            {
                handleFocusChange(false);
                onFocusChange(false);
            }
            else if (!(oldState & StateFlags.focused) && (newState & StateFlags.focused))
            {
                handleFocusChange(true, cast(bool)(newState & StateFlags.keyboardFocused));
                onFocusChange(true);
            }
        }
    }
    /// Set or unset `stateFlags` (a disjunction of `StateFlags` options). Returns new state
    StateFlags applyFlags(StateFlags flags, bool set)
    {
        const st = set ? (stateFlags | flags) : (stateFlags & ~flags);
        stateFlags = st;
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

    /// Returns true if the element has a custom attribute of the `name`
    bool hasAttribute(string name) const
    {
        return (name in attributes) !is null;
    }

    /** Remove the custom attribute by `name` from the element. Does nothing if no such attribute.

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

    //===============================================================
    // Style

    /// Computed style of this element. Allows to query and mutate its properties
    final @property inout(ComputedStyle)* style() inout
    {
        updateStyles();
        return &_style;
    }

    /// Signals when styles are being recomputed. Used for mixing properties in the element
    Listener!(void delegate(Style[] chain)) onStyleUpdate;

    /// Recompute styles, only if needed
    package(beamui) void updateStyles(WindowTheme theme = null) inout
    {
        if (_styleInvalidation == StyleInvalidation.none)
            return;

        debug (styles)
            Log.d("--- Updating style for ", dbgname, " ---");

        with (caching(this))
        {
            bool recompute = _styleInvalidation == StyleInvalidation.recompute;
            _styleInvalidation = StyleInvalidation.none;

            if (!recompute)
            {
                if (!theme)
                {
                    if (auto w = window)
                        theme = w.theme;
                    else
                        return;
                }
                Style[] chain = selectStyleChain(theme);
                // assuming that style recomputation purely depends on style chain,
                // it may not change from previous update
                if (!chain.length || cast(size_t[])_cachedChain[] != cast(size_t[])chain)
                {
                    recompute = true;
                    // copy
                    _cachedChain.clear();
                    _cachedChain ~= chain;
                }
            }
            if (recompute)
            {
                // get parent style
                auto pstyle = _parent && !_style.isolated ? _parent.style : null;
                // important: we should not use the shared array from `selectStyleChain` func
                _style.recompute(_cachedChain.unsafe_slice, _inlineStyle, pstyle);
                onStyleUpdate(_cachedChain.unsafe_slice);
            }
        }

        debug (styles)
            Log.d("--- end ---");
    }

    private Buf!Style _cachedChain;

    /// Get a style chain for this element from `theme`, least specific styles first
    Style[] selectStyleChain(WindowTheme theme)
    {
        import std.algorithm : SwapStrategy;

        if (!theme)
            return null;

        static Buf!Style tmpchain;
        tmpchain.clear();
        // we can skip half of work if the state is normal,
        // and much more work if we select by class name
        const normalState = stateFlags == StateFlags.normal;
        TypeInfo_Class type = widgetType ? cast()widgetType : typeid(this);
        selectByBaseClasses(theme, tmpchain, type, normalState);
        // sort by specificity
        sort!("a < b", SwapStrategy.stable)(tmpchain.unsafe_slice);
        return tmpchain.unsafe_slice;
    }

    private void selectByBaseClasses(WindowTheme theme, ref Buf!Style tmpchain, TypeInfo_Class type, bool normalState)
    {
        string tag;
        if (type !is typeid(Object))
        {
            // iterate on base classes in reverse order.
            // this will define a specificity order on classes
            selectByBaseClasses(theme, tmpchain, type.base, normalState);
            // extract short class name
            const name = type.name;
            int i = cast(int)name.length;
            while (i > 0 && name[i - 1] != '.')
                i--;
            tag = name[i .. $];
        }
        // it will get selectors without any tag first
        Style[] list = theme.getStyles(_namespace, tag, normalState);
        foreach (style; list)
        {
            if (matchSelectorImpl(style.selector, false))
                tmpchain ~= style;
        }
    }

    /// Match this element with a selector
    bool matchSelector(ref const Selector sel) const
    {
        return matchSelectorImpl(sel, true);
    }

    private bool matchSelectorImpl(ref const Selector sel, bool withType) const
    {
        if (sel.universal)
            return matchContextSelector(sel);
        // type
        if (withType && sel.type.length)
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
        if (sel.id.length && _id != sel.id)
            return false;
        // state
        if ((sel.specifiedState & stateFlags) != sel.enabledState)
            return false;
        // tree-structural
        if (sel.position != Selector.TreePosition.none)
        {
            if (sel.position == Selector.TreePosition.root)
            {
                if (!_window) // criterion: only root elements have set window
                    return false;
            }
            else if (sel.position == Selector.TreePosition.empty)
            {
                if (childCount > 0)
                    return false;
            }
        }
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
        return matchContextSelector(sel);
    }

    private bool matchContextSelector(ref const Selector sel) const
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
                if (p.matchSelector(*subselector))
                    return true;
                p = p._parent;
            }
            return false;
        case child:
            // match with the direct parent
            return _parent.matchSelector(*subselector);
        case next:
            // match with the previous sibling
            const n = _parent.childIndex(this) - 1;
            if (n >= 0)
                return _parent.child(n).matchSelector(*subselector);
            else
                return false;
        case subsequent:
            // match with any of previous siblings
            const n = _parent.childIndex(this);
            if (n >= 0)
            {
                foreach (i; 0 .. n)
                    if (_parent.child(i).matchSelector(*subselector))
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
            if (auto w = window) // useless when no parent
                w.needStyleRecalculation = true;
        }
    }

    private void invalidateStylesRecursively()
    {
        _styleInvalidation = StyleInvalidation.match;
        foreach (Element el; this)
            el.invalidateStylesRecursively();
    }

    /// Handle theme change: e.g. reload some themed resources
    void handleThemeChange()
    {
        _styleInvalidation = StyleInvalidation.match;

        // default implementation: call recursive for children
        foreach (Element el; this)
            el.handleThemeChange();
    }

    package(beamui) void handleDPIChange()
    {
        // invalidate styles to resolve length units with new DPI
        _styleInvalidation = max(_styleInvalidation, StyleInvalidation.recompute);

        // continue recursively
        foreach (Element el; this)
            el.handleDPIChange();
    }

    //===============================================================
    // Style related properties

    @property
    {
        enum FOCUS_RECT_PADDING = 2;
        /// Padding (between background bounds and content of element)
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
                    (allowsFocus || ((stateFlags & StateFlags.parent) && parent.allowsFocus)))
            {
                // add two pixels to padding when focus rect is required
                // one pixel for focus rect, one for additional space
                p.add(Insets(FOCUS_RECT_PADDING));
            }
            return p;
        }

        /// Set the element background (takes ownership on the object)
        void background(Background obj)
        in (obj)
        {
            if (_background !is _sharedBackground)
                destroy(_background);
            _background = obj;
        }

        /// Set the element overlay (takes ownership on the object)
        void overlay(Overlay obj)
        in (obj)
        {
            if (_overlay !is _sharedOverlay)
                destroy(_overlay);
            _overlay = obj;
        }

        /// Returns font set for element using style or set manually
        FontRef font() const
        {
            const st = style;
            with (caching(this))
            {
                if (!_font.isNull)
                    return _font;

                const family = FontFamily.both(st.fontFamily, st.fontFace);
                const sel = FontSelector(family, st.fontSize, st.fontItalic, st.fontWeight);
                _font = FontManager.instance.getFont(sel);
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
                    if ((modifiers & KeyMods.alt) != 0) // Alt pressed
                        return TextHotkey.underline;
                }
                return TextHotkey.hidden;
            }
            return result;
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
        case bgColor: .. case bgClip:
        case borderTopColor: .. case borderLeftColor:
        case borderTopStyle: .. case borderLeftStyle:
        case borderTopLeftRadius: .. case borderBottomRightRadius:
        case boxShadow:
        case focusRectColor:
        case textAlign:
        case textColor:
        case textDecorColor:
        case textDecorLine:
        case textDecorStyle:
        case textOverflow:
        case opacity:
        case mixBlendMode:
            invalidate();
            break;
        case fontSize:
        case fontFace: .. case fontWeight:
            _font.clear();
            requestLayout();
            break;
        default:
            break;
        }

        if (_parent)
            _parent.handleChildStyleChange(p, _visibility);
    }

    protected void handleChildStyleChange(StyleProperty p, Visibility v)
    {
    }

    void handleCustomPropertiesChange()
    {
    }

    //===============================================================
    // Animation

    // TODO: some sort of Web Animations API

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
        /** True if the element is interactive.

            Corresponds to `StateFlags.enabled` state flag.
        */
        bool enabled() const
        {
            return (stateFlags & StateFlags.enabled) != 0;
        }

        /// True if this element and all its parents are visible
        bool visible() const
        {
            if (visibility != Visibility.visible)
                return false;
            if (parent is null)
                return true;
            return parent.visible;
        }

        /// True if this element is currently focused
        bool focused() const
        {
            if (auto w = window)
                return this is w.focusedElement.get && (stateFlags & StateFlags.focused);
            else
                return false;
        }
        // dfmt off
        /// True if the element supports click by mouse button or enter/space key
        bool allowsClick() const { return _allowsClick; }
        /// ditto
        void allowsClick(bool flag) { _allowsClick = flag; }
        /// True if the element can be focused
        bool allowsFocus() const { return _allowsFocus; }
        /// ditto
        void allowsFocus(bool flag) { _allowsFocus = flag; }
        /// True if the element will change `hovered` state while mouse pointer is moving upon it
        bool allowsHover() const { return _allowsHover && !TOUCH_MODE; }
        /// ditto
        void allowsHover(bool v) { _allowsHover = v; }
        // dfmt on

        /// True if the element allows click, and it's visible and enabled
        bool canClick() const
        {
            return _allowsClick && enabled && visible;
        }
        /// True if the element allows focus, and it's visible and enabled
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

    /// Returns mouse cursor type for the element
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
    @property dstring tooltipText()
    {
        return _tooltipText;
    }
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

    bool focusGroup;
    ushort tabOrder;

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

    static private class TabOrderInfo
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

    private int thisOrParentTabOrder() const
    {
        if (tabOrder)
            return tabOrder;
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

    /// Set focus to this element or suitable focusable child, returns previously focused element
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
            if (el.canFocus && (!defaultOnly || (el.stateFlags & StateFlags.default_) != 0))
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

    Signal!(void delegate(string)) onAnimationStart;
    Signal!(void delegate(string)) onAnimationEnd;

    //===============================================================
    // Events

    /// Called to process click before `onClick` signal, override to do it
    protected void handleClick()
    {
    }

    /// Set new timer to call a delegate after specified interval (for recurred notifications, return true from the handler)
    /// Note: This function will safely cancel the timer if element is destroyed.
    ulong setTimer(long intervalMillis, bool delegate() handler)
    {
        if (auto w = window)
        {
            bool* destroyed = _destructionFlag;
            return w.setTimer(intervalMillis, {
                // cancel timer on destruction
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
                    applyFlags(StateFlags.pressed, true);
                    return true;
                }
                if (event.action == KeyAction.keyUp)
                {
                    if (stateFlags & StateFlags.pressed)
                    {
                        applyFlags(StateFlags.pressed, false);
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
                    applyFlags(StateFlags.pressed, true);
                    if (_allowsFocus)
                        setFocus();
                    return true;
                }
                if (event.action == MouseAction.buttonUp)
                {
                    if (stateFlags & StateFlags.pressed)
                    {
                        applyFlags(StateFlags.pressed, false);
                        handleClick();
                        onClick();
                    }
                    return true;
                }
            }
            if (event.action == MouseAction.focusIn)
            {
                applyFlags(StateFlags.pressed, true);
                return true;
            }
            if (event.action == MouseAction.focusOut)
            {
                applyFlags(StateFlags.pressed, false);
                return true;
            }
            if (event.action == MouseAction.cancel)
            {
                applyFlags(StateFlags.pressed | StateFlags.hovered, false);
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
                if (stateFlags & StateFlags.hovered)
                {
                    debug (mouse)
                        Log.d("Hover off ", id);
                    applyFlags(StateFlags.hovered, false);
                }
                return true;
            }
            if (event.action == MouseAction.move)
            {
                if (!(stateFlags & StateFlags.hovered))
                {
                    debug (mouse)
                        Log.d("Hover ", id);
                    if (!TOUCH_MODE)
                        applyFlags(StateFlags.hovered, true);
                }
                return true;
            }
            if (event.action == MouseAction.leave)
            {
                debug (mouse)
                    Log.d("Leave ", id);
                applyFlags(StateFlags.hovered, false);
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

    // dfmt off
    final @property
    {
        /// Returns true if layout is required for element and its children
        bool needLayout() const { return _needLayout; }
        /// Returns true if redraw is required for element and its children
        bool needDraw() const { return _needDraw; }

        /// Defines whether element width/height depends on its height/width
        DependentSize dependentSize() const { return _dependentSize; }
        /// Indicate from subclass that element width/height depends on its height/width
        protected void dependentSize(DependentSize value) { _dependentSize = value; }

        /** Element boundaries (min, nat, and max sizes).

            Available after `measure` call.
        */
        ref const(Boundaries) boundaries() const { return _boundaries; }
        /** Minimal size constraint.

            Available after `measure` call.
        */
        Size minSize() const { return _boundaries.min; }
        /** Natural (preferred) size.

            Available after `measure` call.
        */
        Size natSize() const { return _boundaries.nat; }
        /** Maximal size constraint.

            Available after `measure` call.
        */
        Size maxSize() const { return _boundaries.max; }

        /** Element's rectangle, relative to `parent.origin`.

            Available after `layout` call.
        */
        ref const(Box) box() const { return _box; }
        /** Content box, i.e. `box` without padding and borders, relative to `origin`.

            Available after `layout` call.
        */
        ref const(Box) innerBox() const { return _innerBox; }
        /** Global position of `box.pos`.

            Available after window relayout.
        */
        Point origin() const { return _origin; }
    }
    // dfmt on

    @property
    {
        /// Widget visibility (visible, hidden, gone)
        Visibility visibility() const
        {
            return _visibility;
        }
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

    /// Returns true if the point (in absolute coordinates) is inside of this element
    bool contains(float x, float y) const
    {
        return Box(_origin, _box.size).contains(x, y);
    }

    /// Request relayout of element and its children
    final void requestLayout()
    {
        // bubble up so containers (and window) always know if some descendant requires relayout
        Element p = this;
        while (p && !p._needLayout)
        {
            p._needLayout = true;
            p = p._parent;
        }
    }
    /// Request redraw
    final void invalidate()
    {
        Element p = this;
        while (p && !p._needDraw)
        {
            p._needDraw = true;
            p = p._parent;
        }
    }

    /** Measure element - compute minimal, natural and maximal sizes of the border box.

        This method calls `computeBoundaries` to get raw size information,
        applies `padding` and styling such as min-width to it, fixes overflows,
        and assigns the result to `boundaries`.

        Measurement should be doable when widget has `Visibility.gone`.

        This method may return early without calling `computeBoundaries`
        if no elements in the sub-tree requested layout.
    */
    final void measure()
    {
        if (!_needLayout)
            return;

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

    /** ...

        Get `font` in this method.
    */
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

    /** Set element box and lay out element contents.

        It computes `innerBox`, shrink padding if necessary, and calls
        `arrangeContent` to lay out the rest.

        If you need a custom layout logic, in 99% of situations you should
        override `arrangeContent` method instead of this one.
    */
    void layout(Box geometry)
    {
        const requested = _needLayout;
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        alias b = geometry;
        assert(isFinite(b.x) && isFinite(b.y));
        assert(isFinite(b.w) && isFinite(b.h));
        const sb = snapToDevicePixels(b);
        if (!requested && _box == sb)
            return;
        _box = sb;

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
        const isb = snapToDevicePixels(Box(0, 0, b.w, b.h).shrinked(p));
        if (!requested && _innerBox == isb)
            return;
        _innerBox = isb;

        arrangeContent();
    }

    /// Called from `layout`, after `box` and `innerBox` were set
    protected void arrangeContent()
    {
    }

    /// Calculate global positions for all elements, participating in layout
    final void setOrigin(Point parentOrigin)
    {
        if (visibility != Visibility.gone)
        {
            parentOrigin += _box.pos;
            _origin = parentOrigin;
            foreach (Element el; this)
                el.setOrigin(parentOrigin);
        }
    }

    /// Draw element at its position
    final void draw(Painter pr)
    {
        _needDraw = false;
        if (visibility != Visibility.visible)
            return;

        updateStyles();
        const opacity = _style.opacity;
        if (opacity < 0.001f)
            return;

        Insets outset;
        if (auto shadow = _style.boxShadow)
        {
            const sz = shadow.blurSize;
            outset.left = max(sz - shadow.offsetX, 0);
            outset.top = max(sz - shadow.offsetY, 0);
            outset.right = max(sz + shadow.offsetX, 0);
            outset.bottom = max(sz + shadow.offsetY, 0);
        }
        if (pr.quickReject(_box.expanded(outset)))
            return; // clipped out

        // begin a layer if needed
        const blendMode = _style.mixBlendMode;
        PaintSaver svOuter;
        if (opacity < 0.999f || blendMode != BlendMode.normal)
            pr.beginLayer(svOuter, LayerInfo(opacity, blendMode));
        else
            pr.save(svOuter);

        const transform = _style.transform;
        if (transform.kind != SingleTransformKind.none)
        {
            const origin = _box.middle;
            pr.translate(origin.x, origin.y);
            pr.transform(transform.toMatrix(_box.w, _box.h));
            pr.translate(-origin.x, -origin.y);
        }

        // draw the background first
        const borderColor = _style.borderColor;
        const borderStyle = _style.borderStyle;
        const borderWidth = _style.borderWidth;
        const borderRadii = _style.borderRadii;
        _background.color = _style.backgroundColor;
        _background.image = _style.backgroundImage;
        _background.position = _style.backgroundPosition;
        _background.size = _style.backgroundSize;
        _background.origin = _style.backgroundOrigin;
        _background.clip = _style.backgroundClip;
        _background.border = Border(
                BorderSide(borderWidth.top, borderStyle[0], borderColor[0]),
                BorderSide(borderWidth.right, borderStyle[1], borderColor[1]),
                BorderSide(borderWidth.bottom, borderStyle[2], borderColor[2]),
                BorderSide(borderWidth.left, borderStyle[3], borderColor[3]),
        );
        _background.radii = BorderRadii(
                Size(borderRadii[0].applyPercent(box.w), borderRadii[0].applyPercent(box.h)),
                Size(borderRadii[1].applyPercent(box.w), borderRadii[1].applyPercent(box.h)),
                Size(borderRadii[2].applyPercent(box.w), borderRadii[2].applyPercent(box.h)),
                Size(borderRadii[3].applyPercent(box.w), borderRadii[3].applyPercent(box.h)),
        );
        _background.shadow = _style.boxShadow;
        _background.stylePadding = _style.padding;
        _background.drawTo(pr, _box);
        // draw contents
        {
            PaintSaver sv;
            pr.save(sv);
            pr.translate(_box.x, _box.y);
            drawContent(pr);
        }
        // draw the overlay
        _overlay.focusRectColor = (stateFlags & StateFlags.focused) ? _style.focusRectColor : Color.transparent;
        _overlay.drawTo(pr, _box);
    }

    protected void drawContent(Painter pr)
    {
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

        auto popup = window.showPopup(_popupMenu);
        popup.anchor = weakRef(this);
        popup.alignment = PopupAlign.point | PopupAlign.right;
        popup.point = Point(x, y);
        popup.ownContent = false;
    }
    +/
    //===============================================================
    // Widget hierarhy methods

    package(beamui) bool _buildInProgress;
    private enum _treeRebuildMessage = "Cannot alter element tree out of the build process";

    /// Returns number of children of this element
    @property int childCount() const
    {
        return 0;
    }
    /// Returns child by index
    inout(Element) child(int index) inout
    {
        return null;
    }

    void diffChildren(Element[] oldItems)
    out (; _buildInProgress, _treeRebuildMessage)
    {
        assert(false, "diffChildren: this element cannot have children");
    }

    /// Add a child and return it
    Element addChild(Element item)
    out (; _buildInProgress, _treeRebuildMessage)
    {
        assert(false, "addChild: this element cannot have children");
    }
    /// Insert child before given index, returns inserted item
    Element insertChild(int index, Element item)
    out (; _buildInProgress, _treeRebuildMessage)
    {
        assert(false, "insertChild: this element cannot have children");
    }
    /// Remove child by index, returns removed item
    Element removeChild(int index)
    out (; _buildInProgress, _treeRebuildMessage)
    {
        assert(false, "removeChild: this element cannot have children");
    }
    /// Remove child by ID, returns removed item
    Element removeChild(string id)
    out (; _buildInProgress, _treeRebuildMessage)
    {
        assert(false, "removeChild: this element cannot have children");
    }
    /// Remove child, returns removed item
    Element removeChild(Element child)
    out (; _buildInProgress, _treeRebuildMessage)
    {
        assert(false, "removeChild: this element cannot have children");
    }
    /// Remove all children and optionally destroy them
    void removeAllChildren(bool destroyThem = true)
    out (; _buildInProgress, _treeRebuildMessage)
    {
        // override
    }
    /// Returns index of element in child list, -1 if there is no child with this ID
    int childIndex(string id) const
    {
        return -1;
    }
    /// Returns index of element in child list, -1 if passed element is not a child of this element
    int childIndex(const Element item) const
    {
        return -1;
    }

    /** Returns true if item is child of this element.

        When `deepSearch == true`, returns true if item is this element
        or one of children inside children tree.
    */
    bool isChild(Element item, bool deepSearch = true)
    {
        // the contract is that any element in the tree must have a parent
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
            // search only across children of this element
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

    /// Parent element, `null` for top level element
    @property inout(Element) parent() inout
    {
        return _parent;
    }
    /// ditto
    @property void parent(Element element)
    {
        if (_visibility != Visibility.gone)
        {
            if (_parent)
                _parent.requestLayout();
            if (element)
                element.requestLayout();
        }
        _parent = element;
        invalidateStyles();
    }
    /// Returns window (if element or its parent is attached to window)
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
    /// Set window (to be used for top level element from Window implementation).
    package(beamui) @property void window(Window window)
    {
        _window = window;
    }
}

/// Element list holder
alias ElementList = Collection!(Element, true);

/** Base class for elements which have an array of children.
*/
abstract class ElemGroup : Element
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

    override void diffChildren(Element[] oldItems)
    {
        if (!_children.count && !oldItems.length)
            return;

        const limit = min(_children.count, oldItems.length);
        size_t unchanged = limit;
        foreach (i; 0 .. limit)
        {
            if (_children[i]!is oldItems[i])
            {
                unchanged = i;
                break;
            }
        }
        if (unchanged != oldItems.length || _children.count != oldItems.length)
        {
            _styleInvalidation = StyleInvalidation.match;
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
        // handle :empty pseudo-class
        if (!oldItems.length && _children.count || oldItems.length && !_children.count)
        {
            invalidateStylesRecursively();
        }
    }

    override Element addChild(Element item)
    {
        assert(item, "Element must exist");
        assert(item.parent is this);
        _children.append(item);
        return item;
    }

    override Element insertChild(int index, Element item)
    {
        assert(item, "Element must exist");
        assert(item.parent is this);
        _children.insert(index, item);
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

/** Element group with some layout.

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
    private bool zIndexTouched;

    ~this()
    {
        if (_layout)
            _layout.onDetach();
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
            if (_layout)
                _layout.onDetach();
            _layout = obj;
            if (obj)
                obj.onSetup(this);
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
            if (_layout)
                _layout.onStyleChange(p);
        }
    }

    override protected void handleChildStyleChange(StyleProperty p, Visibility v)
    {
        if (v != Visibility.gone && _layout)
        {
            _layout.onChildStyleChange(p);
            if (p == StyleProperty.zIndex)
                zIndexTouched = true;
        }
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
        if (!zIndexTouched)
        {
            foreach (item; preparedItems.unsafe_slice)
                item.draw(pr);
        }
        else
        {
            static Buf!Element sorted;
            sorted.clear();
            sorted ~= preparedItems.unsafe_slice;

            // apply paint order
            sort!((a, b) => a.style.zIndex < b.style.zIndex, SwapStrategy.stable)(sorted.unsafe_slice);

            foreach (item; sorted.unsafe_slice)
                item.draw(pr);
        }
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

/** An integer identifier to map temporal widgets onto persistent state.

    It is unique inside the window and stable between rebuilds of the widget tree.
*/
package(beamui) struct WidgetID
{
    ubyte[16] value;
}

package(beamui) struct StateStore
{
    private WidgetState[WidgetID] map;
    private ulong age;

    private this(int);
    @disable this(this);

    ~this()
    {
        eliminate(map);
    }

    WidgetState fetch(WidgetID id, Widget caller)
    in (id != WidgetID.init)
    in (caller)
    {
        WidgetState st;
        if (auto p = id in map)
        {
            st = *p;
        }
        else
        {
            map[id] = st = caller.createState();
        }
        return st;
    }

    void clearExpired()
    {
        Buf!WidgetID keys;
        foreach (id, st; map)
        {
            if (st.age < age)
            {
                Log.d(st.childrenTTL);
                destroy(st);
                keys ~= id;
            }
        }
        foreach (k; keys)
            map.remove(k);

        age++;
    }
}

/// Contains every alive element of the window by `WidgetID`
package(beamui) struct ElementStore
{
    static uint instantiations;

    private Element[WidgetID] map;

    private this(int);
    @disable this(this);

    ~this()
    {
        eliminate(map);
    }

    Element fetch(WidgetID id, Widget caller)
    in (id != WidgetID.init)
    in (caller)
    {
        Element el;
        if (auto p = id in map)
        {
            el = *p;
        }
        else
        {
            map[id] = el = caller.createElement();
            if (el)
                el.widgetType = typeid(caller);
            instantiations++;
        }
        return el;
    }
}

package(beamui) struct BuildContext
{
    Arena* arena;
    StateStore* stateStore;
    ElementStore* elemStore;
}

// to access from the window
package(beamui) void setBuildContext(BuildContext ctx)
{
    Widget._ctx = ctx;
}

package(beamui) void mountRoot(Widget wt, WidgetState st, Element el)
{
    wt._state = st;
    wt._element = el;
    wt.mountRecursively();
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

//===============================================================
// Tests

unittest
{
    assert(WidgetKey(size_t.max) == WidgetKey.init);
    assert(WidgetKey(0) != WidgetKey.init);
    assert(WidgetKey(1) != WidgetKey.init);
    assert(WidgetKey(0).computed != 0);
    assert(WidgetKey(1).computed != 1);
}
