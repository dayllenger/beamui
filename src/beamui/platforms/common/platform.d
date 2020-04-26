/**
Common Platform definitions.

Platform is abstraction layer for application.

Copyright: Vadim Lopatin 2014-2017, Roman Chistokhodov 2017, Andrzej Kilijański 2017-2018, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.common.platform;

public import beamui.graphics.drawables : imageCache;
public import beamui.widgets.widget : CursorType, Element;
import std.algorithm.mutation : swap;
import std.datetime.stopwatch : Duration, StopWatch, dur;
import beamui.core.animations;
import beamui.core.asyncsocket;
import beamui.core.memory : Arena;
import beamui.core.settings;
import beamui.core.stdaction : initStandardActions, ACTION_OK;
import beamui.graphics.iconprovider;
import beamui.graphics.painter;
import beamui.graphics.resources;
import beamui.platforms.common.timer;
import beamui.style.theme;
import beamui.widgets.popup;
import beamui.widgets.widget;

/// Window creation flags
enum WindowOptions : uint
{
    /// Window can be resized
    resizable = 1,
    /// Window should be shown in fullscreen mode
    fullscreen = 2,
    /// Modal window - grabs input focus
    modal = 4,
    /// Window without decorations
    borderless = 8,
    /// Expand window size if main widget good looking size is greater than one defined in window constructor
    expanded = 16,
    /// Window will be centered on parent window
    centered = 32
}

/// Window states
enum WindowState
{
    /// State is unknown (not supported by platform?), as well for using in `setWindowState` when only want to activate window or change its size/position
    unspecified,
    /// Normal state
    normal,
    /// Window is maximized
    maximized,
    /// Window is maximized
    minimized,
    /// Fullscreen mode (supported not on all platforms)
    fullscreen,
    /// Application is paused (e.g. on Android)
    paused,
    /// Window is hidden
    hidden,
    /// Closed
    closed,
}

/// Dialog display modes - used to configure dialogs should be showed as a popup or window
enum DialogDisplayMode : uint
{
    /// Show all types of dialogs in windows
    allTypesOfDialogsInWindow = 0,
    /// Show file dialogs in popups
    fileDialogInPopup = 1,
    /// Show message boxes in popups
    messageBoxInPopup = 2,
    /// Show input boxes in popups
    inputBoxInPopup = 4,
    /// Show settings dialogs in popups
    settingsDialogInPopup = 8,
    /// Show user dialogs in popups - flag for user dialogs
    userDialogInPopup = 16,
    /// Show all types of dialogs in popups
    allTypesOfDialogsInPopup = fileDialogInPopup |
        messageBoxInPopup | inputBoxInPopup | settingsDialogInPopup | userDialogInPopup
}

/** Protected event list

    References to posted messages can be stored here at least to keep live reference and avoid GC.
    As well, on some platforms it's easy to send id to message queue, but not pointer.
*/
class EventList
{
    import core.sync.mutex;

    private Mutex _mutex;
    private Collection!CustomEvent _events;

    this()
    {
        _mutex = new Mutex;
    }

    ~this()
    {
        eliminate(_mutex);
    }

    /// Put event into queue, returns event's unique id
    long put(CustomEvent event)
    {
        _mutex.lock();
        scope (exit)
            _mutex.unlock();
        _events.pushBack(event);
        return event.uniqueID;
    }
    /// Returns next event
    CustomEvent get()
    {
        _mutex.lock();
        scope (exit)
            _mutex.unlock();
        return _events.popFront();
    }
    /// Returns event by unique id
    CustomEvent get(uint uniqueID)
    {
        _mutex.lock();
        scope (exit)
            _mutex.unlock();
        foreach (i, e; _events)
        {
            if (e.uniqueID == uniqueID)
            {
                _events.remove(i);
                return e;
            }
        }
        // not found
        return null;
    }
}

private class RootWidget : Widget
{
    void mountContent(Widget content, RootElement root)
        in(root)
    {
        if (content)
        {
            Element elem = mountChild(content, root, 0);
            if (root._content is elem)
                return;

            if (root._content)
                root._content.parent = null;
            root._content = elem;
            elem.parent = root;
        }
        else
        {
            if (root._content)
            {
                root._content.parent = null;
                root._content = null;
            }
        }
    }
}

private class RootElement : Element
{
    private Element _content;

    this(Window window)
        in(window)
    {
        this.window = window;
    }

    override protected Boundaries computeBoundaries()
    {
        if (_content)
        {
            _content.measure();
            return _content.boundaries;
        }
        return Boundaries();
    }

    override protected void arrangeContent()
    {
        if (_content)
            _content.layout(innerBox);
    }

    override protected void drawContent(Painter pr)
    {
        if (_content)
            _content.draw(pr);
    }

    override @property int childCount() const
    {
        return _content ? 1 : 0;
    }

    override inout(Element) child(int index) inout
    {
        assert(_content);
        return _content;
    }
}

/**
    Window abstraction layer. Widgets can be shown only inside window.
*/
class Window : CustomEventTarget
{
    @property
    {
        /// Returns parent window
        inout(Window) parentWindow() inout { return _parent; }

        /// Get window behaviour options
        WindowOptions options() const { return _options; }

        /// Window background color
        Color backgroundColor() const { return _backgroundColor; }
        /// ditto
        void backgroundColor(Color color)
        {
            _backgroundColor = color;
        }

        /// Get current window width (in device-independent pixels)
        int width() const { return _w; }
        /// Assign current window width
        protected void width(int value) { _w = value; }

        /// Get current window height (in device-independent pixels)
        int height() const { return _h; }
        /// Assign current window height
        protected void height(int value) { _h = value; }

        /// Minimum window size, use `setMinMaxSizes` to set
        SizeI minSize() const { return _minSize; }
        /// Maximum window size, use `setMinMaxSizes` to set
        SizeI maxSize() const { return _maxSize; }

        /// Current window DPI (dots per inch) value
        float screenDPI() const { return _screenDPI; }
        /// Current window ratio between physical and logical (device-independent) pixels
        float devicePixelRatio() const { return _devicePixelRatio; }

        protected int physicalWidth() const
        {
            return cast(int)(_w * _devicePixelRatio);
        }
        protected int physicalHeight() const
        {
            return cast(int)(_h * _devicePixelRatio);
        }

        /// Get the root element of the window. Never `null`. Contains top element as the first child
        inout(Element) rootElement() inout { return _rootElement; }

        /// Get current key modifiers
        KeyMods keyboardModifiers() const { return _keyboardModifiers; }

        /// Returns current window state
        WindowState windowState() const { return _windowState; }

        /// Returns window rectangle on screen (includes window frame and title)
        BoxI windowRect() const
        {
            if (_windowRect != BoxI.none)
                return _windowRect;
            // fake window rectangle -- at position 0,0
            return BoxI(0, 0, _w, _h);
        }
    }

    /// Blinking caret position (empty rect if no blinking caret)
    Rect caretRect;
    /// Blinking caret is in replace mode if true, insert mode if false
    bool caretReplace;

    protected
    {
        WindowState _windowState = WindowState.normal;
        BoxI _windowRect = BoxI.none;
    }

    private
    {
        int _w;
        int _h;
        float _screenDPI = 96;
        float _devicePixelRatio = 1;

        Color _backgroundColor = Color.white;
        EventList _eventList;
        WindowOptions _options;

        SizeI _minSize;
        SizeI _maxSize = SizeI(10_000, 10_000);
        /// Minimal good looking content size
        SizeI _natSize;

        Window[] _children;
        Window _parent;

        RootElement _rootElement;
        alias _mainWidget = _rootElement; // FIXME: it's not the only root
        ElementStore _elementStore;
        Arena[2] _widgetArenas;
        Widget delegate() _mainBuilder;

        KeyMods _keyboardModifiers;

        CursorType _overridenCursorType = CursorType.automatic;

        Animation[] animations;
        ulong animationUpdateTimerID;

        Painter _painter;
        PainterHead _painterHead;
    }

    this(Window parent, WindowOptions options)
    {
        _parent = parent;
        _options = options;
        _children.reserve(10);
        _eventList = new EventList;
        _timerQueue = new TimerQueue;
        _mainWidget = new RootElement(this);
        _painter = new Painter(_painterHead);
        if (currentTheme)
            _backgroundColor = currentTheme.getColor("window_background", Color.white);
    }

    ~this()
    {
        debug Log.d("Destroying window");

        if (_parent)
        {
            _parent._children = _parent._children.remove!(w => w is this);
            _parent = null;
        }

        onClose();

        if (auto t = timerThread)
            t.stop();

        eliminate(_mainWidget);
        eliminate(_popups);
        // eliminate(_tooltip.popup);

        eliminate(_timerQueue);
        eliminate(_eventList);
        eliminate(_painter);

        static if (USE_OPENGL)
            destroyContext();
    }

    /// Save window state to setting object
    void saveWindowState(Setting setting)
    {
        if (!setting)
            return;
        const WindowState state = windowState;
        const BoxI rect = windowRect;
        if (state == WindowState.fullscreen || state == WindowState.minimized ||
                state == WindowState.maximized || state == WindowState.normal)
        {
            setting.add("windowState").integer = state;
            if (rect.w > 0 && rect.h > 0)
            {
                setting.add("windowPositionX").integer = rect.x;
                setting.add("windowPositionY").integer = rect.y;
                setting.add("windowWidth").integer = rect.w;
                setting.add("windowHeight").integer = rect.h;
            }
        }
    }

    /// Restore window state from setting object
    bool restoreWindowState(Setting setting)
    {
        if (!setting)
            return false;
        const state = cast(WindowState)setting["windowState"].integerDef(WindowState.unspecified);
        BoxI rect;
        rect.x = cast(int)setting["windowPositionX"].integer;
        rect.y = cast(int)setting["windowPositionY"].integer;
        const w = cast(int)setting["windowWidth"].integer;
        const h = cast(int)setting["windowHeight"].integer;
        if (w <= 0 || h <= 0)
            return false;
        rect.w = w;
        rect.h = h;
        if (correctWindowPositionOnScreen(rect) && (state == WindowState.fullscreen ||
                state == WindowState.minimized || state == WindowState.maximized || state == WindowState.normal))
        {
            setWindowState(state, false, rect);
            return true;
        }
        return false;
    }

    /// Check if window position is inside screen bounds, try to correct if needed. Returns true if position is ok
    bool correctWindowPositionOnScreen(ref BoxI rect)
    {
        // override to apply screen size bounds
        return true;
    }

    //===============================================================
    // Abstract methods: override in platform implementation

    /// Get window title (caption)
    abstract @property dstring title() const;
    /// Set window title
    abstract @property void title(dstring caption);
    /// Set window icon
    abstract @property void icon(Bitmap icon);

    /// Show window
    abstract protected void show();
    /// Request window redraw
    abstract void invalidate();
    /// Close window
    abstract void close();
    /// Destroy all the resources after close message
    abstract protected void cleanup();

    //===============================================================

    /// Window state change signal
    Signal!(void delegate(WindowState state, BoxI rect)) onWindowStateChange;

    /// Update and signal window state and/or size/positon changes - for using in platform inplementations
    protected void handleWindowStateChange(WindowState newState, BoxI newWindowRect = BoxI.none)
    {
        bool signalWindow;
        if (newState != WindowState.unspecified && newState != _windowState)
        {
            _windowState = newState;
            debug (state)
                Log.d("Window ", windowCaption, " has new state - ", newState);
            signalWindow = true;
        }
        if (newWindowRect != BoxI.none && newWindowRect != _windowRect)
        {
            _windowRect = newWindowRect;
            debug (state)
                Log.d("Window ", windowCaption, " rect changed - ", newWindowRect);
            signalWindow = true;
        }

        if (signalWindow && onWindowStateChange.assigned)
            onWindowStateChange(newState, newWindowRect);
    }

    /// Change window state, position, or size; returns true if successful, false if not supported by platform
    bool setWindowState(WindowState newState, bool activate = false, BoxI newWindowRect = BoxI.none)
    {
        // override for particular platforms
        return false;
    }
    /// Maximize window
    bool maximize(bool activate = false)
    {
        return setWindowState(WindowState.maximized, activate);
    }
    /// Minimize window
    bool minimize()
    {
        return setWindowState(WindowState.minimized);
    }
    /// Restore window if maximized/minimized/hidden
    bool restore(bool activate = false)
    {
        return setWindowState(WindowState.normal, activate);
    }
    /// Restore window if maximized/minimized/hidden
    bool hide()
    {
        return setWindowState(WindowState.hidden);
    }
    /// Just activate window
    bool activate()
    {
        return setWindowState(WindowState.unspecified, true);
    }
    /// Change window position only
    bool move(int x, int y, bool activate = false)
    {
        return setWindowState(WindowState.unspecified, activate, BoxI(x, y, int.min, int.min));
    }
    /// Change window size only
    bool resize(int w, int h, bool activate = false)
    {
        return setWindowState(WindowState.unspecified, activate, BoxI(int.min, int.min, w, h));
    }
    /// Set window rectangle
    bool moveAndResize(BoxI rc, bool activate = false)
    {
        return setWindowState(WindowState.unspecified, activate, rc);
    }

    package (beamui) void addModalChild(Window w)
    {
        _children ~= w;
    }

    package (beamui) @property bool hasVisibleModalChild()
    {
        foreach (w; _children)
        {
            if (w.options & WindowOptions.modal && w._windowState != WindowState.hidden)
                return true;

            if (w.hasVisibleModalChild)
                return true;
        }
        return false;
    }

    package (beamui) void restoreModalChilds()
    {
        foreach (w; _children)
        {
            if (w.options & WindowOptions.modal && w._windowState != WindowState.hidden)
            {
                if (w._windowState == WindowState.maximized)
                    w.activate();
                else
                    w.restore(true);
            }

            w.restoreModalChilds();
        }
    }

    package (beamui) void minimizeModalChilds()
    {
        foreach (w; _children)
        {
            if (w.options & WindowOptions.modal && w._windowState != WindowState.hidden)
            {
                w.minimize();
            }

            w.minimizeModalChilds();
        }
    }

    package (beamui) void restoreParentWindows()
    {
        Window[] tmp;
        Window w = this;
        while (true)
        {
            if (w is null)
                break;

            tmp ~= w;
            w = w._parent;
        }

        foreach_reverse (tw; tmp)
            tw.restore(true);
    }

    package (beamui) void minimizeParentWindows()
    {
        Window[] tmp;
        Window w = this;
        while (true)
        {
            if (w is null)
                break;

            tmp ~= w;
            w = w._parent;
        }

        foreach_reverse (tw; tmp)
            tw.minimize();
    }

    /// Set or override the window minimum and maximum sizes. Use a negative value to left it unchanged
    final void setMinMaxSizes(int minW, int minH, int maxW, int maxH)
    {
        if (minW < 0)
            minW = _minSize.w;
        if (minH < 0)
            minH = _minSize.h;
        if (maxW < 0)
            maxW = _maxSize.w;
        if (maxH < 0)
            maxH = _maxSize.h;
        const newmin = SizeI(minW, minH);
        const newmax = SizeI(max(maxW, minW), max(maxH, minH));
        if (_minSize != newmin || _maxSize != newmax)
        {
            _minSize = newmin;
            _maxSize = newmax;
            handleSizeHintsChange();
        }
    }

    protected void handleSizeHintsChange()
    {
        // override to support
    }

    final protected void setDPI(float dpi, float dpr)
    {
        debug
        {
            if (_screenDPI != dpi)
                Log.d("Window DPI changed from ", _screenDPI, " to ", dpi);
            if (_devicePixelRatio != dpr)
                Log.d("Window pixel ratio changed from ", _devicePixelRatio, " to ", dpr);
        }
        if (_screenDPI != dpi || _devicePixelRatio != dpr)
        {
            _screenDPI = dpi;
            _devicePixelRatio = dpr;
            dispatchDPIChange();
        }
    }

    /// Called before layout and redraw. Widgets and painter use global DPI and DPR values
    /// to make proper scaling and unit conversion, but these values are per-window
    private void setupGlobalDPI()
    {
        import u = beamui.core.units;

        u.setupDPI(_screenDPI, _devicePixelRatio);
    }

    private void dispatchDPIChange()
    {
        if (!_mainWidget)
            return; // at window creation

        setupGlobalDPI();
        _mainWidget.handleDPIChange();
        foreach (p; _popups)
            p.handleDPIChange();
/+
        if (Widget p = _tooltip.popup)
            p.handleDPIChange();
+/
    }

    /// Set the minimal window size and resize the window if needed; called from `show()`
    protected void adjustSize()
        in(_mainWidget)
    {
        setupGlobalDPI();
        _mainWidget.measure();
        const bs = _mainWidget.boundaries;
        // some sane constraints
        _minSize.w = clamp(cast(int)bs.min.w, _minSize.w, _maxSize.w);
        _minSize.h = clamp(cast(int)bs.min.h, _minSize.h, _maxSize.h);
        _natSize.w = clamp(cast(int)bs.nat.w, _minSize.w, _maxSize.w);
        _natSize.h = clamp(cast(int)bs.nat.h, _minSize.h, _maxSize.h);
        handleSizeHintsChange();
        // expand
        int w, h;
        if (options & WindowOptions.expanded)
        {
            w = max(_windowRect.w, _natSize.w);
            h = max(_windowRect.h, _natSize.h);
        }
        else
        {
            w = max(_windowRect.w, _minSize.w);
            h = max(_windowRect.h, _minSize.h);
        }
        resize(w, h);
    }

    /// Adjust window position during `show()`
    protected void adjustPosition()
    {
        if (options & WindowOptions.centered)
            centerOnParentWindow();
    }

    /// Center window on parent window, do nothing if there is no parent window
    void centerOnParentWindow()
    {
        if (parentWindow)
        {
            const BoxI parentRect = parentWindow.windowRect;
            const int newx = parentRect.x + (parentRect.w - _windowRect.w) / 2;
            const int newy = parentRect.y + (parentRect.h - _windowRect.h) / 2;
            move(newx, newy);
        }
    }

    protected void handleResize(int width, int height)
    {
        if (_w == width && _h == height)
            return;
        _w = width;
        _h = height;
        // fix window rect for platforms that don't set it yet
        _windowRect.w = width;
        _windowRect.h = height;

        debug (layout)
            Log.d("handleResize ", _w, "x", _h);

        // resize changes only window's width and height,
        // so it is quite legitimate to not measure again
        layout();
        update(true);
    }

    //===============================================================
    // Popups, tooltips

    private ElemPopup[] _popups;
/+
    protected static struct TooltipInfo
    {
        Popup popup;
        ulong timerID;
        WeakRef!Element owner;
        float x = float.max;
        float y = float.max;
        PopupAlign alignment;
    }

    private TooltipInfo _tooltip;

    /// Schedule tooltip for widget be shown with specified delay
    void scheduleTooltip(WeakRef!Element owner, long delay, PopupAlign alignment = PopupAlign.point,
                         float x = float.max, float y = float.max)
    {
        if (_tooltip.owner.get !is owner.get)
        {
            debug (tooltips)
                Log.d("schedule tooltip");
            _tooltip.alignment = alignment;
            _tooltip.x = x;
            _tooltip.y = y;
            _tooltip.owner = owner;
            _tooltip.timerID = setTimer(delay, &handleTooltipTimer);
        }
    }

    /// Called when tooltip timer is expired
    private bool handleTooltipTimer()
    {
        debug (tooltips)
            Log.d("tooltip timer");
        _tooltip.timerID = 0;
        if (Element owner = _tooltip.owner.get)
        {
            const x = _tooltip.x == float.max ? _lastMouseX : _tooltip.x;
            const y = _tooltip.y == float.max ? _lastMouseY : _tooltip.y;
            Element el = owner.createTooltip(x, y);
            if (el)
            {
                Popup p = showTooltip(el);
                p.anchor = _tooltip.owner;
                p.alignment = _tooltip.alignment;
                p.point = Point(x, y);
            }
            else
                _tooltip.owner.nullify();
        }
        return false;
    }

    /// Show tooltip immediately
    Popup showTooltip(Element content)
        in(content)
    {
        const noTooltipBefore = _tooltip.popup is null;
        hideTooltip();

        debug (tooltips)
            Log.d("show tooltip");

        auto res = new Popup(content, this);
        res.id = "tooltip-popup";
        // default behaviour is to place tooltip under the mouse cursor
        res.alignment = PopupAlign.point;
        res.point = Point(_lastMouseX, _lastMouseY);

        // add a smooth fade-in transition when there is no tooltip already shown
        if (noTooltipBefore)
        {
            auto tr = Transition(100, TimingFunction.easeIn);
            res.style.opacity = 0;
            // may be destroyed
            auto popup = weakRef(res);
            addAnimation(tr.duration, (double t) {
                if (Element p = popup.get)
                    p.style.opacity = tr.mix(0.0f, 1.0f, t);
            });
        }

        _tooltip.popup = res;
        return res;
    }
+/
    /// Hide tooltip if shown and cancel tooltip timer if set
    void hideTooltip()
    {
/+
        if (_tooltip.popup)
        {
            debug (tooltips)
                Log.d("destroy tooltip");
            destroy(_tooltip.popup);
            _tooltip.popup = null;
            _tooltip.owner.nullify();
            _mainWidget.invalidate();
        }
        if (_tooltip.timerID)
        {
            debug (tooltips)
                Log.d("cancel tooltip timer");
            cancelTimer(_tooltip.timerID);
            _tooltip.timerID = 0;
            _tooltip.owner.nullify();
        }
+/
    }
/+
    /// Show new popup
    Popup showPopup(Element content)
        in(content)
    {
        auto res = new Popup(content, this);

        // add a smooth fade-in transition
        auto tr = Transition(150, TimingFunction.easeIn);
        res.style.opacity = 0;
        // may be destroyed
        auto popup = weakRef(res);
        addAnimation(tr.duration, (double t) {
            if (Element p = popup.get)
                p.style.opacity = tr.mix(0.0f, 1.0f, t);
        });

        _popups ~= res;
        setFocus(weakRef(content));
        _mainWidget.requestLayout();
        update();
        return res;
    }

    /// Remove popup
    bool removePopup(Popup popup)
    {
        if (!popup)
            return false;
        for (int i = 0; i < _popups.length; i++)
        {
            Popup p = _popups[i];
            if (p is popup)
            {
                for (int j = i; j < _popups.length - 1; j++)
                    _popups[j] = _popups[j + 1];
                _popups.length--;
                destroy(p);
                // force redraw
                _mainWidget.invalidate();
                return true;
            }
        }
        return false;
    }

    /// Returns last modal popup widget, or `null` if no modal popups opened
    Popup modalPopup()
    {
        foreach_reverse (p; _popups)
        {
            if (p.modal)
                return p;
        }
        return null;
    }
+/
    //===============================================================

    private Listener!(void delegate(string[])) _filesDropped;
    /// Set handler for files dropped to app window
    @property void onFileDrop(void delegate(string[]) handler)
    {
        _filesDropped = handler;
    }

    /// Called when user dragged file(s) to application window
    void handleDroppedFiles(string[] filenames)
    {
        if (_filesDropped.assigned)
            _filesDropped(filenames);
    }

    /// Handler to ask whether it is allowed for window to close itself
    Listener!(bool delegate()) allowClose;
    /// Handler for window closing
    Listener!(void delegate()) onClose;

    /// Returns true if there is some modal window opened above this window, and this window should not process mouse/key input and should not allow closing
    @property bool hasModalWindowsAbove()
    {
        return platform.hasModalWindowsAbove(this);
    }

    /// Call `allowClose` handler if set to check if system may close window
    bool canClose()
    {
        if (hasModalWindowsAbove)
            return false;
        bool result = allowClose.assigned ? allowClose() : true;
        if (!result)
            update(true); // redraw window if it was decided to not close immediately
        return result;
    }

    /// Returns true if `el` is child of either the main element, one of popups, or the tooltip
    bool isChild(Element el)
    {
        if (_mainWidget.isChild(el))
            return true;
        foreach (p; _popups)
            if (p.isChild(el))
                return true;
/+
        if (_tooltip.popup && _tooltip.popup.isChild(el))
            return true;
+/
        return false;
    }

    /**
    Allows queue destroy of widget.

    Sometimes when you have very complicated UI with dynamic create/destroy lists of widgets calling simple destroy()
    on widget makes segmentation fault.

    Usually because you destroy widget that on some stage call another that tries to destroy widget that calls it.
    When the control flow returns widget not exist and you have seg. fault.

    This function use internally $(LINK2 $(DDOX_ROOT_DIR)beamui/core/events/QueueDestroyEvent.html, QueueDestroyEvent).
    */
    void queueWidgetDestroy(Element widgetToDestroy)
    {
        auto ev = new QueueDestroyEvent(widgetToDestroy);
        postEvent(ev);
    }

    //===============================================================
    // Focused widget

    private WeakRef!Element _focusedElement;
    private State _focusStateToApply = State.focused;
    /// Returns current focused widget
    @property inout(WeakRef!Element) focusedElement() inout { return _focusedElement; }

    /// Change focus to widget
    Element setFocus(WeakRef!Element target, FocusReason reason = FocusReason.unspecified)
    {
        State targetState = State.focused;
        if (reason == FocusReason.tabFocus)
            targetState |= State.keyboardFocused;
        _focusStateToApply = targetState;

        Element oldFocus = _focusedElement.get;
        Element newFocus = target.get;
        if (oldFocus is newFocus)
            return oldFocus;
        if (oldFocus)
        {
            oldFocus.applyState(targetState, false);
            oldFocus.focusGroupFocused(false);
        }
        if (!newFocus || isChild(newFocus))
        {
            if (newFocus)
            {
                // when calling this, window.focusedElement is still previously focused widget
                debug (focus)
                    Log.d("new focus: ", newFocus.dbgname);
                newFocus.applyState(targetState, true);
            }
            _focusedElement = weakRef(newFocus);
            if (newFocus)
                newFocus.focusGroupFocused(true);
            // after focus change, ask for actions update automatically
            //requestActionsUpdate();
        }
        return _focusedElement.get;
    }

    protected Element applyFocus()
    {
        Element el = _focusedElement.get;
        if (el)
        {
            el.applyState(_focusStateToApply, true);
            update();
        }
        return el;
    }

    protected Element removeFocus()
    {
        Element el = _focusedElement.get;
        if (el)
        {
            el.applyState(_focusStateToApply, false);
            update();
        }
        return el;
    }

    /// Is this window focused?
    abstract @property bool isActive() const;

    /// Window activate/deactivate signal
    Signal!(void delegate(bool isWindowActive)) onWindowActivityChange;

    protected void handleWindowActivityChange(bool isWindowActive)
    {
        if (isWindowActive)
            applyFocus();
        else
            removeFocus();
        onWindowActivityChange(isWindowActive);
    }

    //===============================================================
    // Events and actions

    /// Call an action, considering action context
    bool call(Action action)
    {
        if (action)
        {
            const context = action.context;
            if (context == ActionContext.application)
            {
                return action.call(el => true);
            }
            else if (context == ActionContext.window)
            {
                return action.call(el => el && el.window is this);
            }
            else // widget or widget tree
            {
                Element focus = focusedElement.get;
                if (action.call(el => el is focus)) // try focused first
                {
                    return true;
                }
                else if (context == ActionContext.widgetTree)
                {
                   return action.call(el => el && el.isChild(focus));
                }
                else
                    return false;
            }
        }
        return false;
    }

    /// Dispatch keyboard event
    bool dispatchKeyEvent(KeyEvent event)
    {
        if (hasModalWindowsAbove || !_firstDrawCalled)
            return false;
        bool res;
        hideTooltip();
        if (event.action == KeyAction.keyDown || event.action == KeyAction.keyUp)
        {
            _keyboardModifiers = event.allModifiers;
            if (event.key == Key.alt || event.key == Key.lalt || event.key == Key.ralt)
            {
                debug (keys)
                    Log.d("Alt key: keyboardModifiers = ", _keyboardModifiers);
                _mainWidget.invalidate();
                res = true;
            }
        }
        if (event.action == KeyAction.text)
        {
            // filter text
            if (event.text.length < 1)
                return res;
            dchar ch = event.text[0];
            if (ch < ' ' || ch == 0x7F) // filter out control symbols
                return res;
        }
        Element focus = focusedElement.get;
        // Popup modal = modalPopup();
        // if (!modal || modal.isChild(focus))
        {
            // process shortcuts
            if (event.action == KeyAction.keyDown)
            {
                auto a = Action.findByShortcut(event.key, event.allModifiers);
                if (call(a))
                    return true;
            }
            // raise from the disabled subtree
            Element p = focus;
            while (p)
            {
                if (p.enabled)
                    p = p.parent;
                else
                    focus = p = p.parent;
            }
            while (focus)
            {
                if (handleKeyEvent(weakRef(focus), event))
                    return true; // processed by focused widget or its parent in focus group
                if (focus.focusGroup)
                    break;
                focus = focus.parent;
            }
        }
        // Element dest = modal ? modal : _mainWidget;
        Element dest = _mainWidget;
        if (dispatchKeyEvent(dest, event))
            return res;
        else
            return handleKeyEvent(weakRef(dest), event) || res;
    }

    /// Dispatch key event to widgets which have `wantsKeyTracking == true`
    protected bool dispatchKeyEvent(Element root, KeyEvent event)
    {
        // route key events to enabled visible widgets only
        if (root.visibility != Visibility.visible || !root.enabled)
            return false;
        if (root.wantsKeyTracking)
        {
            if (handleKeyEvent(weakRef(root), event))
                return true;
        }
        foreach (Element el; root)
        {
            if (dispatchKeyEvent(el, event))
                return true;
        }
        return false;
    }

    private int _lastMouseX;
    private int _lastMouseY;
    /// Dispatch mouse event to window content widgets
    bool dispatchMouseEvent(MouseEvent event)
    {
        if (hasModalWindowsAbove || !_firstDrawCalled)
            return false;
/+
        // check tooltip
        if (event.action == MouseAction.move)
        {
            import std.math : abs;

            if (_tooltip.popup && _tooltip.popup.contains(event.x, event.y))
            {
                // freely move mouse inside of tooltip
                return true;
            }
            const threshold = 3;
            if (abs(_lastMouseX - event.x) > threshold || abs(_lastMouseY - event.y) > threshold)
                hideTooltip();
            _lastMouseX = event.x;
            _lastMouseY = event.y;
        }
        if (event.action == MouseAction.buttonDown)
        {
            if (_tooltip.popup)
            {
                hideTooltip();
            }
        }
+/
        debug (mouse)
            Log.fd("dispatchMouseEvent %s (%s, %s)", event.action, event.x, event.y);

        bool res;
        const currentButtons = event.mouseMods;
        if (_mouseCapture)
        {
            // try to forward message directly to active widget
            if (event.action == MouseAction.move)
            {
                debug (mouse)
                    Log.d("dispatchMouseEvent: Move, buttons state: ", currentButtons);
                if (!_mouseCapture.get.contains(event.x, event.y))
                {
                    if (currentButtons != _mouseCaptureButtons)
                    {
                        debug (mouse)
                            Log.d("dispatchMouseEvent: Move, buttons state changed from ",
                                    _mouseCaptureButtons, " to ", currentButtons, ", cancelling capture");
                        return dispatchCancel(event);
                    }
                    // point is no more inside of captured widget
                    if (!_mouseCaptureFocusedOut)
                    {
                        // sending FocusOut message
                        event.changeAction(MouseAction.focusOut);
                        _mouseCaptureFocusedOut = true;
                        _mouseCaptureButtons = currentButtons;
                        _mouseCaptureFocusedOutTrackMovements = sendAndCheckOverride(_mouseCapture, event);
                        return true;
                    }
                    else if (_mouseCaptureFocusedOutTrackMovements)
                    {
                        // pointer is outside, but we still need to track pointer
                        return sendAndCheckOverride(_mouseCapture, event);
                    }
                    // don't forward message
                    return true;
                }
                else
                {
                    // point is inside widget
                    if (_mouseCaptureFocusedOut)
                    {
                        _mouseCaptureFocusedOut = false;
                        if (currentButtons != _mouseCaptureButtons)
                            return dispatchCancel(event);
                        event.changeAction(MouseAction.focusIn); // back in after focus out
                    }
                    return sendAndCheckOverride(_mouseCapture, event);
                }
            }
            else if (event.action == MouseAction.leave)
            {
                if (!_mouseCaptureFocusedOut)
                {
                    // sending FocusOut message
                    event.changeAction(MouseAction.focusOut);
                    _mouseCaptureFocusedOut = true;
                    _mouseCaptureButtons = event.mouseMods;
                    return sendAndCheckOverride(_mouseCapture, event);
                }
                else
                {
                    debug (mouse)
                        Log.d("dispatchMouseEvent: mouseCaptureFocusedOut + Leave - cancelling capture");
                    return dispatchCancel(event);
                }
            }
            else if (event.action == MouseAction.buttonDown || event.action == MouseAction.buttonUp)
            {
                if (!_mouseCapture.get.contains(event.x, event.y))
                {
                    if (currentButtons != _mouseCaptureButtons)
                    {
                        debug (mouse)
                            Log.d("dispatchMouseEvent: ButtonUp/ButtonDown; buttons state changed from ",
                                    _mouseCaptureButtons, " to ", currentButtons, " - cancelling capture");
                        return dispatchCancel(event);
                    }
                }
            }
            // other messages
            res = sendAndCheckOverride(_mouseCapture, event);
            if (currentButtons == MouseMods.none)
            {
                // disable capturing - no more buttons pressed
                debug (mouse)
                    Log.d("unsetting active widget");
                clearMouseCapture();
            }
            return res;
        }

        bool processed;
        if (event.action == MouseAction.move || event.action == MouseAction.leave)
        {
            processed = checkRemoveTracking(event);
        }
        // Popup modal = modalPopup();
        bool cursorIsSet = _overridenCursorType != CursorType.automatic;
        if (!res)
        {
/+
            bool insideOneOfPopups;
            foreach_reverse (p; _popups)
            {
                if (p is modal)
                    break;
                if (p.contains(event.x, event.y))
                    insideOneOfPopups = true;
            }
            foreach_reverse (p; _popups)
            {
                if (p is modal)
                    break;
                if (insideOneOfPopups)
                {
                    if (dispatchMouseEvent(p, event, cursorIsSet))
                        return true;
                }
                else
                {
                    if (p.handleMouseEventOutside(event))
                        return true;
                }
            }
            res = dispatchMouseEvent(modal ? modal : _mainWidget, event, cursorIsSet);
+/
            res = dispatchMouseEvent(_mainWidget, event, cursorIsSet);
        }
        return res || processed || _mainWidget.needDraw;
    }

    protected bool dispatchMouseEvent(Element root, MouseEvent event, ref bool cursorIsSet)
    {
        auto dest = weakRef(performHitTest(root, event.x, event.y, true));
        while (dest)
        {
            if (event.action == MouseAction.move && !cursorIsSet)
            {
                CursorType cursor = dest.get.style.cursor;
                if (cursor == CursorType.automatic)
                    cursor = dest.get.getCursorType(event.x, event.y);
                if (cursor != CursorType.automatic)
                {
                    setCursorType(cursor);
                    cursorIsSet = true;
                }
            }
            if (sendAndCheckOverride(dest, event))
            {
                debug (mouse)
                    Log.d("MouseEvent is processed");
                if (event.action == MouseAction.buttonDown && !_mouseCapture && !event.doNotTrackButtonDown)
                {
                    debug (mouse)
                        Log.d("Setting active widget");
                    setMouseCapture(dest, event);
                }
                else if (event.action == MouseAction.move)
                {
                    addTracking(dest);
                }
                return true;
            }
            // bubble up if not destroyed
            if (dest)
                dest = weakRef(dest.get.parent);
        }
        return false;
    }

    /// Elements that track `move` events
    private WeakRef!Element[] _mouseTrackingElements;
    private void addTracking(WeakRef!Element element)
    {
        if (!element)
            return;
        foreach (el; _mouseTrackingElements)
            if (element is el)
                return;
        _mouseTrackingElements ~= element;
        debug (mouse)
            Log.d("addTracking: ", element.dbgname, ", items after: ", _mouseTrackingElements.length);
    }

    private bool checkRemoveTracking(MouseEvent event)
    {
        bool res;
        foreach_reverse (ref el; _mouseTrackingElements)
        {
            if (!el)
                continue;
            if (event.action == MouseAction.leave || !el.get.contains(event.x, event.y))
            {
                // send Leave message
                auto leaveEvent = new MouseEvent(event);
                leaveEvent.changeAction(MouseAction.leave);
                res = handleMouseEvent(el, leaveEvent) || res;
                debug (mouse)
                    Log.d("removeTracking of ", el.dbgname);
                el.nullify();
            }
        }
        _mouseTrackingElements = _mouseTrackingElements.remove!(a => !a);
        debug (mouse)
            Log.d("removeTracking, items after: ", _mouseTrackingElements.length);
        return res;
    }

    /// Element that tracks all events after processed `buttonDown`
    private WeakRef!Element _mouseCapture;
    private MouseMods _mouseCaptureButtons;
    private bool _mouseCaptureFocusedOut;
    /// Does current capture widget want to receive move events even if pointer left it
    private bool _mouseCaptureFocusedOutTrackMovements;

    protected void setMouseCapture(WeakRef!Element el, MouseEvent event)
    {
        if (!el)
            return;
        _mouseCapture = el;
        _mouseCaptureButtons = event.mouseMods;
        captureMouse(true);
    }

    protected void clearMouseCapture()
    {
        _mouseCapture.nullify();
        _mouseCaptureFocusedOut = false;
        _mouseCaptureFocusedOutTrackMovements = false;
        _mouseCaptureButtons = MouseMods.none;
        captureMouse(false);
    }

    /// Platform-dependent mouse capturing
    protected void captureMouse(bool enabled)
    {
    }

    protected bool dispatchCancel(MouseEvent event)
    {
        event.changeAction(MouseAction.cancel);
        const res = handleMouseEvent(_mouseCapture, event);
        clearMouseCapture();
        return res;
    }

    protected bool sendAndCheckOverride(WeakRef!Element element, MouseEvent event)
    {
        if (!element)
            return false;
        const res = handleMouseEvent(element, event);
        if (event.trackingWidget && _mouseCapture !is event.trackingWidget)
        {
            setMouseCapture(event.trackingWidget, event);
        }
        return res;
    }

    /// Returns true if mouse is currently captured
    bool isMouseCaptured() const
    {
        return !!_mouseCapture;
    }

    /// Dispatch wheel event to window content widgets
    void dispatchWheelEvent(WheelEvent event)
    {
        if (hasModalWindowsAbove || !_firstDrawCalled)
            return;

        hideTooltip();

        if (_mouseCapture)
        {
            // try to forward message directly to active widget
            handleWheelEvent(_mouseCapture, event);
            if (event.mouseMods == MouseMods.none)
            {
                // disable capturing - no more buttons pressed
                debug (mouse)
                    Log.d("unsetting active widget");
                clearMouseCapture();
            }
            return;
        }
/+
        if (Element modal = modalPopup())
        {
            dispatchWheelEvent(modal, event);
            return;
        }
+/
        foreach_reverse (p; _popups)
        {
            if (dispatchWheelEvent(p, event))
                return;
        }
        dispatchWheelEvent(_mainWidget, event);
    }

    protected bool dispatchWheelEvent(Element root, WheelEvent event)
    {
        auto dest = weakRef(performHitTest(root, event.x, event.y, true));
        while (dest)
        {
            if (handleWheelEvent(dest, event))
                return true;
            // bubble up if not destroyed
            if (dest)
                dest = weakRef(dest.get.parent);
        }
        return false;
    }

    private static bool handleKeyEvent(WeakRef!Element weak, KeyEvent e)
    {
        Element el = weak.get;
        if (el.onKeyEvent.assigned && el.onKeyEvent(e))
            return true;  // processed by external handler
        else if (!weak)
            return false; // destroyed in the handler, but not processed
        else
            return el.handleKeyEvent(e);
    }

    private static bool handleMouseEvent(WeakRef!Element weak, MouseEvent e)
    {
        Element el = weak.get;
        if (el.onMouseEvent.assigned && el.onMouseEvent(e))
            return true;
        else if (!weak)
            return false;
        else
            return el.handleMouseEvent(e);
    }

    private static bool handleWheelEvent(WeakRef!Element weak, WheelEvent e)
    {
        Element el = weak.get;
        if (el.onWheelEvent.assigned && el.onWheelEvent(e))
            return true;
        else if (!weak)
            return false;
        else
            return el.handleWheelEvent(e);
    }

    /// Handle theme change: e.g. reload some themed resources
    void dispatchThemeChange()
    {
        _mainWidget.handleThemeChange();
        foreach (p; _popups)
            p.handleThemeChange();
/+
        if (auto p = _tooltip.popup)
            p.handleThemeChange();
+/
        if (currentTheme)
        {
            _backgroundColor = currentTheme.getColor("window_background", Color.white);
        }
        invalidate();
    }

    /// Post event to handle in UI thread (this method can be used from background thread)
    void postEvent(CustomEvent event)
    {
        // override to post event into window message queue
        _eventList.put(event);
    }

    /// Post task to execute in UI thread (this method can be used from background thread)
    void executeInUiThread(void delegate() runnable)
    {
        auto event = new RunnableEvent(CUSTOM_RUNNABLE, WeakRef!Element(null), runnable);
        postEvent(event);
    }

    /// Creates async socket
    AsyncSocket createAsyncSocket(AsyncSocketCallback callback)
    {
        return new AsyncClientConnection(new AsyncSocketCallbackProxy(callback, &executeInUiThread));
    }

    /// Remove event from queue by unique id if not yet dispatched (this method can be used from background thread)
    void cancelEvent(uint uniqueID)
    {
        CustomEvent ev = _eventList.get(uniqueID);
        if (ev)
        {
            //destroy(ev);
        }
    }

    /// Remove event from queue by unique id if not yet dispatched and dispatch it
    void handlePostedEvent(uint uniqueID)
    {
        CustomEvent ev = _eventList.get(uniqueID);
        if (ev)
        {
            dispatchCustomEvent(ev);
        }
    }

    /// Handle all events from queue, if any (call from UI thread only)
    void handlePostedEvents()
    {
        while (true)
        {
            CustomEvent e = _eventList.get();
            if (!e)
                break;
            dispatchCustomEvent(e);
        }
    }

    /// Dispatch custom event
    bool dispatchCustomEvent(CustomEvent event)
    {
        if (auto dest = event.destinationWidget.get)
        {
            return dest.handleEvent(event);
        }
        else
        {
            // no destination widget, can be runnable
            if (auto runnable = cast(RunnableEvent)event)
            {
                // handle runnable
                runnable.run();
                return true;
            }
        }
        return false;
    }

    /// Override cursor for the entire window. Set to `CursorType.automatic` to use widget cursors back
    final void overrideCursorType(CursorType cursor)
    {
        _overridenCursorType = cursor;
        setCursorType(cursor);
    }

    /// Set cursor type for window
    protected void setCursorType(CursorType cursor)
    {
        // override to support different mouse cursors
    }

    //===============================================================
    // Timers

    private TimerQueue _timerQueue;
    private TimerThread timerThread;

    /**
    Schedule timer for timestamp in milliseconds - post timer event when finished.

    Platform timers are implemented using timer thread by default, but it is possible
    to use platform timers - override this method, calculate an interval and set the timer there.
    When timer expires and platform receives its event, call `window.handleTimer()`.
    */
    protected void scheduleSystemTimer(long timestamp)
    {
        if (!timerThread)
            timerThread = new TimerThread(&postTimerEvent);

        timerThread.notifyOn(timestamp);
    }

    /// Push a timer event into the platform-specific event queue. Called from another thread.
    protected void postTimerEvent()
    {
    }

    /// Poll expired timers; returns true if update is needed
    bool pollTimers()
    {
        bool res = _timerQueue.notify();
        if (res)
            update();
        return res;
    }

    /// System timer interval expired - notify queue
    protected void handleTimer()
    {
        debug (timers)
            Log.d("window.handleTimer");
        bool res = _timerQueue.notify();
        if (res)
        {
            // check if update needed and redraw if so
            debug (timers)
                Log.d("before update");
            update();
            debug (timers)
                Log.d("after update");
        }
        debug (timers)
            Log.d("schedule next timer");
        long nextTimestamp = _timerQueue.nextTimestamp();
        if (nextTimestamp > 0)
        {
            scheduleSystemTimer(nextTimestamp);
        }
    }

    /** Set timer with a delegate, that will be called after interval expiration; returns timer id.

        Note: You must cancel the timer if you destroy object this handler belongs to.
    */
    ulong setTimer(long intervalMillis, bool delegate() handler)
    {
        assert(handler !is null);
        ulong res = _timerQueue.add(intervalMillis, handler);
        long nextTimestamp = _timerQueue.nextTimestamp();
        if (nextTimestamp > 0)
        {
            scheduleSystemTimer(nextTimestamp);
        }
        return res;
    }

    /// Cancel previously scheduled widget timer (for `timerID` pass value returned from `setTimer`)
    void cancelTimer(ulong timerID)
    {
        _timerQueue.cancelTimer(timerID);
    }

    //===============================================================
    // Update logic, called after various events

    // set by widgets themselves
    package(beamui) bool needUpdate;
    private bool _animationActive;

    /// Request update for window (unless `force` is true, update will be performed only if layout, redraw or animation is required)
    void update(bool force = false)
    {
        if (needRebuild)
            rebuild();

        bool needDraw = false;
        bool needLayout = false;
        _animationActive = false;
        if (force || checkUpdateNeeded(needDraw, needLayout, _animationActive))
        {
            debug (redraw)
                Log.d("Requesting update");
            invalidate();
        }
    }

    /// Check content widgets for necessary redraw and/or layout
    private bool checkUpdateNeeded(out bool needDraw, out bool needLayout, out bool animationActive)
    {
        animationActive = animations.length > 0;
        // skip costly update if no one notified
        if (!needUpdate)
            return animationActive;

        checkUpdateNeeded(_mainWidget, needDraw, needLayout, animationActive);
        foreach (p; _popups)
            checkUpdateNeeded(p, needDraw, needLayout, animationActive);
/+
        if (auto p = _tooltip.popup)
            checkUpdateNeeded(p, needDraw, needLayout, animationActive);
+/
        const ret = needDraw || needLayout || animationActive;
        debug (redraw)
        {
            if (ret)
            {
                Log.d("needed:"
                    ~ (needDraw ? " draw" : null)
                    ~ (needLayout ? " layout" : null)
                    ~ (animationActive ? " animation" : null));
            }
        }
        return ret;
    }
    /// Check content widgets for necessary redraw and/or layout
    private void checkUpdateNeeded(Element root, ref bool needDraw, ref bool needLayout, ref bool animationActive)
    {
        assert(root);

        if (root.visibility == Visibility.gone)
            return;

        needLayout = needLayout || root.needLayout;
        debug (redraw)
        {
            if (root.needLayout)
                Log.fd("Need layout: %s, parent: %s", root.dbgname,
                    root.parent ? getShortClassName(root.parent) : "null");
        }
        if (root.visibility == Visibility.hidden)
            return;
        needDraw = needDraw || root.needDraw;
        animationActive = animationActive || root.animating;
        if (needDraw && needLayout && animationActive)
            return;
        // check recursively
        foreach (Element el; root)
            checkUpdateNeeded(el, needDraw, needLayout, animationActive);
    }

    //===============================================================
    // Tree rebuild

    // experimental
    final void show(Widget delegate() builder)
    {
        _mainBuilder = builder;
        rebuild(); // the first build
        _rootElement.setFocus();
        show();
    }

    private void rebuild()
    {
        if (!_mainBuilder)
        {
            needRebuild = false;
            return;
        }

        debug
        {
            StopWatch sw;
            sw.start();
        }

        // prepare allocators and the cache
        swap(_widgetArenas[0], _widgetArenas[1]);
        _widgetArenas[0].clear();
        setBuildContext(BuildContext(this, &_widgetArenas[0], &_elementStore));

        // rebuild and diff
        RootWidget root = render!RootWidget;
        Widget content = _mainBuilder();
        // skip mount and update of the root, mount the child immediately
        root.mountContent(content, _rootElement);
        needRebuild = false;

        debug
        {
            sw.stop();
            const elapsed = sw.peek().total!`usecs` / 1000.0f;
            if (elapsed > PERFORMANCE_LOGGING_THRESHOLD_MS)
                Log.fd("rebuild took: %.1f ms", elapsed);
        }
    }

    //===============================================================
    // Animations

    void addAnimation(long duration, void delegate(double) handler)
    {
        assert(duration > 0 && handler);
        animations ~= Animation(duration * ONE_SECOND / 1000, handler);
    }

    private void animate(long interval)
    {
        // process global animations
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
            animations = animations.remove!(a => a.handler is null);

        // process widget ones
        animate(_mainWidget, interval);
        foreach (p; _popups)
            animate(p, interval);
/+
        if (auto p = _tooltip.popup)
            animate(p, interval);
+/
    }

    private void animate(Element root, long interval)
    {
        assert(root);

        if (root.visibility != Visibility.visible)
            return;

        foreach (Element el; root)
            animate(el, interval);
        if (root.animating)
            root.animate(interval);
    }

    // will be called periodically to update animations
    private bool animationTimerHandler()
    {
        needUpdate = true;
        invalidate();
        return true;
    }

    //===============================================================
    // Layout and hit-testing

    /// Request layout for main widget and popups
    void requestLayout()
    {
        _mainWidget.requestLayout();
        foreach (p; _popups)
            p.requestLayout();
/+
        if (auto p = _tooltip.popup)
            p.requestLayout();
+/
    }

    /// Measure main widget, popups and tooltip
    private void measure()
    {
        debug (layout)
        {
            StopWatch sw;
            sw.start();
        }

        setupGlobalDPI();
        // TODO: set minimum window size
        _mainWidget.measure();
        foreach (p; _popups)
            p.measure();
/+
        if (auto tp = _tooltip.popup)
            tp.measure();
+/
        debug (layout)
        {
            sw.stop();
            const elapsed = sw.peek().total!`usecs` / 1000.0f;
            if (elapsed > PERFORMANCE_LOGGING_THRESHOLD_MS)
                Log.fd("measure took: %.1f ms", elapsed);
        }
    }

    /// Lay out main widget, popups and tooltip
    private void layout()
    {
        debug (layout)
        {
            StopWatch sw;
            sw.start();
        }

        setupGlobalDPI();
        _mainWidget.layout(Box(0, 0, _w, _h));
        foreach (p; _popups)
        {
            const sz = p.natSize;
            p.layout(Box(0, 0, sz.w, sz.h));
        }
/+
        if (auto tp = _tooltip.popup)
        {
            const sz = tp.natSize;
            tp.layout(Box(0, 0, sz.w, sz.h));
        }
+/
        debug (layout)
        {
            sw.stop();
            const elapsed = sw.peek().total!`usecs` / 1000.0f;
            if (elapsed > PERFORMANCE_LOGGING_THRESHOLD_MS)
                Log.fd("layout took: %.1f ms", elapsed);
        }
    }

    /// Find topmost visible widget at the (x, y) position in global coordinates. `null` if none
    private Element performHitTest(Element root, float x, float y, bool enabledOnly)
    {
        // this hit test assumes that widgets never leave parent's bounds.
        // this makes it somewhat logarithmic
        if (root.visibility != Visibility.visible)
            return null;
        if (enabledOnly && !root.enabled)
            return null;
        if (!root.contains(x, y))
            return null;
        foreach_reverse (el; root)
        {
            if (auto hit = performHitTest(el, x, y, enabledOnly))
                return hit;
        }
        return root;
    }

    //===============================================================
    // Painting

    /// OpenGL-specific routines
    static if (USE_OPENGL)
    {
        /// Try to create an OpenGL context with specified version
        abstract protected bool createContext(int major, int minor);
        /// Destroy OpenGL context, if exists
        abstract protected void destroyContext();
        /// Make window OpenGL context to be current
        abstract protected void bindContext();
        /// Swap buffers at the end of frame
        abstract protected void swapBuffers();

        /// Override to perform some actions after GL context and backend creation
        protected void handleGLReadiness()
        {
        }

        final protected void drawUsingOpenGL(ref PaintEngine engine)
        {
            import beamui.graphics.gl.glpainter : GLPaintEngine;

            bindContext();
            if (!engine)
                engine = new GLPaintEngine(platform._glSharedData);
            draw(engine);
            swapBuffers();
        }
    }

    enum PERFORMANCE_LOGGING_THRESHOLD_MS = 1;

    /// Set when first draw is called: don't handle mouse/key input until draw (layout) is called
    private bool _firstDrawCalled;
    private long lastDrawTs;

    final protected void draw(PaintEngine engine)
        in(engine)
    {
        _firstDrawCalled = true;

        _painterHead.beginFrame(engine, physicalWidth, physicalHeight, _backgroundColor);
        try
        {
            static import std.datetime;

            setupGlobalDPI();

            // check if we need to relayout
            bool needDraw;
            bool needLayout;
            bool animationActive;
            checkUpdateNeeded(needDraw, needLayout, animationActive);

            const long ts = std.datetime.Clock.currStdTime;
            if (animationActive && lastDrawTs != 0)
            {
                animate(ts - lastDrawTs);
                // layout required flag could be changed during animate - check again
                checkUpdateNeeded(needDraw, needLayout, animationActive);
                // do update every 16 milliseconds
                if (animationUpdateTimerID == 0)
                    animationUpdateTimerID = setTimer(16, &animationTimerHandler);
            }
            lastDrawTs = ts;

            if (needLayout)
            {
                measure();
                layout();
            }

            debug (redraw)
            {
                StopWatch sw;
                sw.start();
            }

            // draw main widget
            _mainWidget.draw(_painter);
            // draw popups
/+
            const modal = modalPopup();
            foreach (p; _popups)
            {
                if (p is modal)
                {
                    // TODO: get shadow color from theme
                    _painter.fillRect(0, 0, width, height, Color(0, 0x20));
                }
                p.draw(_painter);
            }
            // and draw tooltip
            if (auto p = _tooltip.popup)
                p.draw(_painter);
+/
            debug (redraw)
            {
                sw.stop();
                const elapsed = sw.peek().total!`usecs` / 1000.0f;
                if (elapsed > PERFORMANCE_LOGGING_THRESHOLD_MS)
                    Log.fd("drawing took: %.1f ms", elapsed);
            }
            // cancel animations' update if they are expired
            if (!animationActive && animationUpdateTimerID)
            {
                cancelTimer(animationUpdateTimerID);
                animationUpdateTimerID = 0;
            }

            needUpdate = false;
        }
        catch (Exception e)
        {
            Log.e("Exception inside window.draw: ", e);
        }
        _painterHead.endFrame();
    }
}

/// Convenient window storage to use in specific platforms
struct WindowMap(W : Window, ID)
{
    private W[] list;
    private W[ID] map;
    private ID[W] reverseMap;
    private W[] toDestroy;

    ~this()
    {
        foreach (w; list)
            destroy(w);
        destroy(list);
        destroy(map);
        destroy(reverseMap);
        destroy(toDestroy);
    }

    /// Add window to the map
    void add(W w, ID id)
    {
        list ~= w;
        map[id] = w;
        reverseMap[w] = id;
    }

    /// Remove window from the map and defer its destruction until `purge` call
    void remove(W w)
    {
        if (auto id = w in reverseMap)
        {
            reverseMap.remove(w);
            map.remove(*id);
            list = list.remove!(a => a is w);
            toDestroy ~= w;
            (cast(Window)w).cleanup();
        }
    }

    /// Destroy removed window objects planned for destroy
    void purge()
    {
        if (toDestroy.length > 0)
        {
            foreach (w; toDestroy)
                destroy(w);
            toDestroy.length = 0;
        }
    }

    /// Returns number of currently existing windows
    @property size_t count() const
    {
        return list.length;
    }

    /// The first added existing window, `null` if no windows
    @property W first()
    {
        return list.length > 0 ? list[0] : null;
    }
    /// The last added existing window, `null` if no windows
    @property W last()
    {
        return list.length > 0 ? list[$ - 1] : null;
    }

    /// Returns window instance by ID
    W opIndex(ID id)
    {
        return map.get(id, null);
    }
    /// Returns ID of the window
    ID opIndex(W w)
    {
        return reverseMap.get(w, ID.init);
    }

    /// Check window existence by ID with `in` operator
    bool opBinaryRight(string op : "in")(ID id)
    {
        return (id in map) !is null;
    }

    /// `foreach` support
    int opApply(scope int delegate(size_t i, W w) callback)
    {
        int result;
        foreach (i; 0 .. list.length)
        {
            result = callback(i, list[i]);
            if (result)
                break;
        }
        return result;
    }
    /// ditto
    int opApply(scope int delegate(W w) callback)
    {
        int result;
        foreach (i; 0 .. list.length)
        {
            result = callback(list[i]);
            if (result)
                break;
        }
        return result;
    }
}

/** Platform abstraction layer.

    Represents application. Holds set of windows.
*/
class Platform
{
    private static __gshared Platform _instance;

    /// Platform singleton instance
    static @property Platform instance() { return _instance; }
    /// ditto
    static @property void instance(Platform instance)
    {
        debug Log.d(instance ? "Setting platform" : "Destroying platform");
        eliminate(_instance);
        _instance = instance;
    }

    @property
    {
        /// Returns application UI language code
        string uiLanguage() const { return _conf.lang; }

        /// Get name of currently active theme
        string uiTheme() const { return _conf.theme; }
        /// Set application UI theme - will relayout content of all windows if theme has been changed
        void uiTheme(string name)
        {
            if (_conf.theme != name)
            {
                _conf.theme = setupTheme(name);
                handleThemeChange();
            }
        }

        /// How dialogs should be displayed - as popup or window
        DialogDisplayMode uiDialogDisplayMode() const { return _conf.dialogDisplayModes; }

        /// Default icon for newly created windows
        string defaultWindowIcon() const { return _conf.defaultWindowIcon; }

        IconProviderBase iconProvider()
        {
            if (_iconProvider is null)
            {
                try
                {
                    _iconProvider = new NativeIconProvider;
                }
                catch (Exception e)
                {
                    Log.e("Error while creating icon provider\n", e);
                    Log.d("Could not create native icon provider, fallbacking to the dummy one");
                    _iconProvider = new DummyIconProvider;
                }
            }
            return _iconProvider;
        }
        /// ditto
        IconProviderBase iconProvider(IconProviderBase provider)
        {
            _iconProvider = provider;
            return _iconProvider;
        }

        static if (USE_OPENGL)
        {
            /// OpenGL context major version (may be not equal to version set by user)
            int GLVersionMajor() const { return _conf.GLVersionMajor; }
            /// OpenGL context minor version (may be not equal to version set by user)
            int GLVersionMinor() const { return _conf.GLVersionMinor; }
        }
    }

    private
    {
        AppConf _conf;
        IconProviderBase _iconProvider;
    }

    this(ref AppConf conf)
    {
        _conf = conf;

        if (conf.lang != "en")
        {
            Log.v("Loading '", conf.lang, "' language file");
            loadTranslator(conf.lang);
        }
        setupTheme(conf.theme);
    }

    ~this()
    {
        eliminate(_iconProvider);
        static if (USE_OPENGL)
            eliminate(_glSharedData);
    }

    /** Starts application message loop.

        When returned from this method, application is shutting down.
    */
    abstract int enterMessageLoop();

    //===============================================================
    // Window routines

    /** Create a window.

    Params:
        title  = window title text
        parent = parent Window, or `null` if no parent
        options  = combination of `WindowOptions`
        width  = window width
        height = window height

    Note: Window w/o `resizable` nor `fullscreen` will be created with a size based on measurement of its content widget.
    */
    abstract Window createWindow(dstring title, Window parent = null,
            WindowOptions options = WindowOptions.resizable | WindowOptions.expanded,
            uint width = 0, uint height = 0);

    /** Close a window.

        Closes window earlier created with createWindow()
    */
    abstract void closeWindow(Window w);

    /** Returns true if there is some modal window opened above this window.

        This window should not process mouse/key input and should not allow closing.
    */
    bool hasModalWindowsAbove(Window w)
    {
        // may override in platform specific class
        return w ? w.hasVisibleModalChild : false;
    }

    /// Iterate over all windows
    abstract protected int opApply(scope int delegate(size_t, Window) callback);

    //===============================================================

    /// Check has clipboard text
    abstract bool hasClipboardText(bool mouseBuffer = false);
    /// Retrieve text from clipboard (under Linux, when `mouseBuffer` is true, use mouse selection clipboard)
    abstract dstring getClipboardText(bool mouseBuffer = false);
    /// Set text to clipboard (under Linux, when `mouseBuffer` is true, use mouse selection clipboard)
    abstract void setClipboardText(dstring text, bool mouseBuffer = false);

    /// Reload current theme. Useful to quickly edit and test a theme
    final void reloadTheme()
    {
        Log.v("Reloading theme ", _conf.theme);
        auto theme = loadTheme(_conf.theme);
        if (!theme)
        {
            Log.e("Cannot reload theme ", _conf.theme);
            return;
        }
        currentTheme = theme;
        handleThemeChange();
    }

    /** Call to disable automatic screen DPI detection, to use provided one instead.

        Pass 0 to disable override and use value detected by windows.
    */
    final void overrideDPI(float dpi, float dpr)
    {
        .overrideDPI(dpi, dpr);
        handleDPIChange();
    }

    /// Open url in external browser
    static void openURL(string url)
    {
        import ps = std.process;

        if (url.length)
            ps.browse(url);
    }

    /// Show directory or file in OS file manager (explorer, finder, etc...)
    static bool showInFileManager(string pathName)
    {
        static import fm = beamui.core.filemanager;

        return fm.showInFileManager(pathName);
    }

    /// Handle theme change, e.g. reload some themed resources
    private void handleThemeChange()
    {
        static if (BACKEND_GUI)
        {
            imageCache.clear();
        }
        foreach (i, w; this)
        {
            w.dispatchThemeChange();
            w.invalidate();
        }
    }

    private void handleDPIChange()
    {
        foreach (i, w; this)
        {
            w.dispatchDPIChange();
            w.invalidate();
        }
    }

    private string setupTheme(string name)
    {
        Theme theme = loadTheme(name);
        if (name != "default")
        {
            if (!theme)
            {
                Log.e("Cannot load theme `", name, "` - will use default theme");
                theme = loadTheme("default");
            }
            else
            {
                Log.i("Applying loaded theme ", name);
            }
        }
        assert(theme);
        currentTheme = theme;
        return theme.name;
    }

    static if (USE_OPENGL)
    {
        import beamui.graphics.gl.gl : loadGLAPI;
        import beamui.graphics.gl.glpainter : GLSharedData;

        private GLSharedData _glSharedData;

        void createGLContext(Window window)
        {
            if (!openglEnabled)
                return;

            if (_glSharedData)
            {
                if (window.createContext(_conf.GLVersionMajor, _conf.GLVersionMinor))
                {
                    window.bindContext();
                    window.handleGLReadiness();
                }
                else
                    assert(0, "GL: failed to create context");
                return;
            }
            // the first initialization
            const major = clamp(_conf.GLVersionMajor, 3, 4);
            const minor = clamp(_conf.GLVersionMinor, 0, major == 3 ? 3 : 6);
            bool success = createGLContext(window, major, minor);
            if (!success)
            {
                const ver = major * 10 + minor;
                if (ver > 43)
                    success = createGLContext(window, 4, 3);
                if (!success && ver > 40)
                    success = createGLContext(window, 4, 0);
                if (!success && ver > 32)
                    success = createGLContext(window, 3, 2);
                if (!success && ver > 30)
                    success = createGLContext(window, 3, 0);
            }
            if (success)
            {
                window.bindContext();
                success = loadGLAPI();
            }
            else
                Log.e("GL: failed to create a context");

            if (success)
            {
                _glSharedData = new GLSharedData;
                window.handleGLReadiness();
            }
            else
            {
                disableOpenGL();
                _conf.GLVersionMajor = 0;
                _conf.GLVersionMinor = 0;
            }
        }

        private bool createGLContext(Window w, int major, int minor)
        {
            Log.i("GL: trying to create ", major, ".", minor, " context");
            const success = w.createContext(major, minor);
            if (success)
            {
                Log.i("GL: created successfully");
                // set final version
                _conf.GLVersionMajor = major;
                _conf.GLVersionMinor = minor;
            }
            return success;
        }
    }
}

/// Get current platform object instance
@property Platform platform()
{
    return Platform.instance;
}

private bool needRebuild = true;

void setState(T)(ref T currentValue, T newValue)
{
    if (currentValue !is newValue)
    {
        currentValue = newValue;
        needRebuild = true;
    }
}

static if (USE_OPENGL)
private __gshared bool _openglEnabled = true;

/// Check if hardware acceleration is enabled
bool openglEnabled()
{
    static if (USE_OPENGL)
        return _openglEnabled;
    else
        return false;
}
/// Disable OpenGL acceleration on app initialization in case of failure
void disableOpenGL()
{
    static if (USE_OPENGL)
    {
        _openglEnabled = false;
        Log.w("OpenGL was disabled");
    }
}

static if (BACKEND_GUI)
{
    version (Windows)
    {
        package (beamui) void setAppDPIAwareOnWindows()
        {
            import core.sys.windows.windows;

            // TODO: SetProcessDpiAwareness + PROCESS_PER_MONITOR_DPI_AWARE
            // call SetProcessDPIAware to support HI DPI - fix by Kapps
            auto ulib = LoadLibraryA("user32.dll");
            alias SetProcessDPIAwareFunc = int function();
            auto setDpiFunc = cast(SetProcessDPIAwareFunc)GetProcAddress(ulib, "SetProcessDPIAware");
            if (setDpiFunc) // should never fail, but just in case...
                setDpiFunc();
        }
    }
}

/// Holds initial application settings
struct AppConf
{
    /// UI language, e.g. "en", "fr", "ru" (requires app restart to change)
    string lang = "en";
    /// Name of initial UI theme
    string theme = "default";
    /// Default icon for newly created windows (requires app restart to change)
    string defaultWindowIcon = "beamui-logo";

    /// How dialogs should be displayed - as popup or window (requires app restart to change)
    DialogDisplayMode dialogDisplayModes =
        DialogDisplayMode.messageBoxInPopup |
        DialogDisplayMode.inputBoxInPopup;

    /// OpenGL context major version (requires app restart to change)
    int GLVersionMajor = 3;
    /// OpenGL context minor version (requires app restart to change)
    int GLVersionMinor = 2;
}

/// Manages UI library (de)initialization
struct GuiApp
{
    import beamui.core.stdaction;
    import beamui.platforms.common.startup;
    import beamui.widgets.editors;

    /// Holds initial application settings
    AppConf conf;

    /// Initialize the whole UI toolkit
    bool initialize()
    {
        if (Platform.instance)
        {
            Log.e("Cannot initialize GUI twice");
            return false;
        }

        initLogs();

        if (!initFontManager())
        {
            Log.e("******************************************************************");
            Log.e("No font files found!!!");
            Log.e("Currently, only hardcoded font paths implemented.");
            Log.e("Probably you can modify startup.d to add some fonts for your system.");
            Log.e("******************************************************************");
            return false;
        }
        initResourceManagers();

        Platform.instance = initPlatform(conf);
        if (!Platform.instance)
            return false;

        initStandardActions();
        initStandardEditorActions();
        return true;
    }

    @disable this(this);

    ~this()
    {
        Platform.instance = null;
        releaseResourcesOnAppExit();
    }
}

// to remove import
extern (C) Platform initPlatform(AppConf);
