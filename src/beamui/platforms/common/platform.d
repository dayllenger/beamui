/**
This module contains common Plaform definitions.

Platform is abstraction layer for application.


Synopsis:
---
import beamui.platforms.common.platform;
---

Copyright: Vadim Lopatin 2014-2017, Roman Chistokhodov 2017, Andrzej Kilijański 2017-2018, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.common.platform;

import beamui.core.asyncsocket;
import beamui.core.collections;
import beamui.core.config;
import beamui.core.events;
import beamui.core.stdaction;
import beamui.graphics.drawbuf;
import beamui.graphics.iconprovider;
import beamui.graphics.resources;
import beamui.widgets.popup;
import beamui.widgets.scrollbar;
import beamui.widgets.widget;

/// Entry point - declare such function to use as main for beamui app
extern (C) int UIAppMain(string[] args);

/// Window creation flags
enum WindowFlag : uint
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
    /// State is unknown (not supported by platform?), as well for using in setWindowState when only want to activate window or change its size/position
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
enum DialogDisplayMode : ulong
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

/// Protected event list
/// References to posted messages can be stored here at least to keep live reference and avoid GC
/// As well, on some platforms it's easy to send id to message queue, but not pointer
class EventList
{
    import core.sync.mutex;

    protected Mutex _mutex;
    protected Collection!CustomEvent _events;

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
        for (int i = 0; i < _events.length; i++)
        {
            if (_events[i].uniqueID == uniqueID)
            {
                return _events.remove(i);
            }
        }
        // not found
        return null;
    }
}

class TimerInfo
{
    protected
    {
        ulong _id;
        long _interval;
        long _nextTimestamp;
        Widget _targetWidget;
    }

    static __gshared ulong nextID;

    this(Widget targetWidget, long intervalMillis)
    {
        _id = ++nextID;
        assert(intervalMillis >= 0 && intervalMillis < 7 * 24 * 60 * 60 * 1000L);
        _targetWidget = targetWidget;
        _interval = intervalMillis;
        _nextTimestamp = currentTimeMillis + _interval;
    }

    @property
    {
        /// Unique ID of timer
        ulong id() const
        {
            return _id;
        }
        /// Timer interval, milliseconds
        long interval() const
        {
            return _interval;
        }
        /// Next timestamp to invoke timer at, as per currentTimeMillis()
        long nextTimestamp() const
        {
            return _nextTimestamp;
        }
        /// Widget to route timer event to
        Widget targetWidget()
        {
            return _targetWidget;
        }
        /// Returns true if timer is not yet cancelled
        bool valid() const
        {
            return _targetWidget !is null;
        }
    }

    /// Cancel timer
    void cancel()
    {
        _targetWidget = null;
    }
    /// Cancel timer
    void notify()
    {
        if (_targetWidget)
        {
            _nextTimestamp = currentTimeMillis + _interval;
            if (!_targetWidget.onTimer(_id))
            {
                _targetWidget = null;
            }
        }
    }

    override bool opEquals(Object obj) const
    {
        TimerInfo b = cast(TimerInfo)obj;
        if (!b)
            return false;
        return b._nextTimestamp == _nextTimestamp;
    }

    override int opCmp(Object obj)
    {
        TimerInfo b = cast(TimerInfo)obj;
        if (!b)
            return false;
        if (valid && !b.valid)
            return -1;
        if (!valid && b.valid)
            return 1;
        if (!valid && !b.valid)
            return 0;
        if (_nextTimestamp < b._nextTimestamp)
            return -1;
        if (_nextTimestamp > b._nextTimestamp)
            return 1;
        return 0;
    }
}

/**
    Window abstraction layer. Widgets can be shown only inside window.
*/
class Window : CustomEventTarget
{
    @property
    {
        /// Get window behaviour flags
        WindowFlag flags() const
        {
            return _flags;
        }

        /// Window background color
        uint backgroundColor() const
        {
            return _backgroundColor;
        }
        /// ditto
        void backgroundColor(uint color)
        {
            _backgroundColor = color;
        }

        /// Get current window width
        int width() const
        {
            return _w;
        }

        /// Get current window height
        int height() const
        {
            return _h;
        }

        uint keyboardModifiers() const
        {
            return _keyboardModifiers;
        }

        /// Get main widget of the window
        inout(Widget) mainWidget() inout
        {
            return _mainWidget;
        }
        /// Assign main widget to the window. Destroys previous main widget
        void mainWidget(Widget widget)
        {
            if (_mainWidget)
            {
                _mainWidget.window = null;
                destroy(_mainWidget);
            }
            _mainWidget = widget;
            if (_mainWidget)
                _mainWidget.window = this;
        }

        /// Returns parent window
        Window parentWindow()
        {
            return _parent;
        }

        /// Returns current window override cursor type or NotSet if not overriding.
        CursorType overrideCursorType() const
        {
            return _overrideCursorType;
        }
        /// Allow override cursor for entire window. Set to CursorType.notSet to remove cursor type overriding.
        void overrideCursorType(CursorType newCursorType)
        {
            _overrideCursorType = newCursorType;
            setCursorType(newCursorType);
        }

        /// Blinking caret position (empty rect if no blinking caret)
        Rect caretRect() const
        {
            return _caretRect;
        }
        /// ditto
        void caretRect(Rect rc)
        {
            _caretRect = rc;
        }

        /// Blinking caret is in replace mode if true, insert mode if false
        bool caretReplace() const
        {
            return _caretReplace;
        }
        /// ditto
        void caretReplace(bool flag)
        {
            _caretReplace = flag;
        }

        /// Returns current window state
        WindowState windowState() const
        {
            return _windowState;
        }

        /// Returns window rectangle on screen (includes window frame and title)
        Box windowRect() const
        {
            if (_windowRect != Box.none)
                return _windowRect;
            // fake window rectangle -- at position 0,0
            return Box(0, 0, _w, _h);
        }
    }

    protected
    {
        int _w;
        int _h;
        uint _keyboardModifiers;
        uint _backgroundColor;
        Widget _mainWidget;
        EventList _eventList;
        WindowFlag _flags;
        /// Minimal content size
        Size _minContentSize;
        /// Minimal good looking content size
        Size _goodContentSize;

        Window[] _children;
        Window _parent;

        Rect _caretRect;
        bool _caretReplace;

        WindowState _windowState = WindowState.normal;
        Box _windowRect = Box.none;

        /// Keep overrided cursor type to `notSet` to get cursor from widget
        CursorType _overrideCursorType = CursorType.notSet;
    }

    this()
    {
        _eventList = new EventList;
        _timerQueue = new TimerQueue;
        _backgroundColor = 0xFFFFFF;
        if (currentTheme)
            _backgroundColor = currentTheme.getColor("window_background");
    }

    ~this()
    {
        debug Log.d("Destroying window");

        if (_parent)
        {
            _parent._children = _parent._children.remove!(w => w is this);
            _parent = null;
        }

        if (_onClose)
            _onClose();
        eliminate(_tooltip.popup);
        eliminate(_popups);
        eliminate(_mainWidget);
        eliminate(_timerQueue);
        eliminate(_eventList);
    }

    import beamui.core.settings;

    /// Save window state to setting object
    void saveWindowState(Setting setting)
    {
        if (!setting)
            return;
        WindowState state = windowState;
        Box rect = windowRect;
        if (state == WindowState.fullscreen || state == WindowState.minimized ||
                state == WindowState.maximized || state == WindowState.normal)
        {
            //
            setting.setInteger("windowState", state);
            if (rect.width > 0 && rect.height > 0)
            {
                setting.setInteger("windowPositionX", rect.x);
                setting.setInteger("windowPositionY", rect.y);
                setting.setInteger("windowWidth", rect.width);
                setting.setInteger("windowHeight", rect.height);
            }
        }
    }

    /// Restore window state from setting object
    bool restoreWindowState(Setting setting)
    {
        if (!setting)
            return false;
        WindowState state = cast(WindowState)setting.getInteger("windowState", WindowState.unspecified);
        Box rect;
        rect.x = cast(int)setting.getInteger("windowPositionX", WindowState.unspecified);
        rect.y = cast(int)setting.getInteger("windowPositionY", 0);
        int w = cast(int)setting.getInteger("windowWidth", 0);
        int h = cast(int)setting.getInteger("windowHeight", 0);
        if (w <= 0 || h <= 0)
            return false;
        rect.width = w;
        rect.height = h;
        if (correctWindowPositionOnScreen(rect) && (state == WindowState.fullscreen ||
                state == WindowState.minimized || state == WindowState.maximized || state == WindowState.normal))
        {
            setWindowState(state, false, rect);
            return true;
        }
        return false;
    }

    /// Check if window position is inside screen bounds, try to correct if needed. Returns true if position is ok
    bool correctWindowPositionOnScreen(ref Box rect)
    {
        // override to apply screen size bounds
        return true;
    }

    //===============================================================
    // Abstract methods: override in platform implementation

    /// Show window
    abstract void show();
    /// Get window title (caption)
    abstract @property dstring title() const;
    /// Set window title
    abstract @property void title(dstring caption);
    /// Set window icon
    abstract @property void icon(DrawBufRef icon);
    /// Request window redraw
    abstract void invalidate();
    /// Close window
    abstract void close();

    //===============================================================

    /// Window state change signal
    Signal!(void delegate(Window, WindowState state, Box rect)) windowStateChanged;

    /// Update and signal window state and/or size/positon changes - for using in platform inplementations
    protected void handleWindowStateChange(WindowState newState, Box newWindowRect = Box.none)
    {
        bool signalWindow = false;
        if (newState != WindowState.unspecified && newState != _windowState)
        {
            _windowState = newState;
            debug (state)
                Log.d("Window ", windowCaption, " has new state - ", newState);
            signalWindow = true;
        }
        if (newWindowRect != Box.none && newWindowRect != _windowRect)
        {
            _windowRect = newWindowRect;
            debug (state)
                Log.d("Window ", windowCaption, " rect changed - ", newWindowRect);
            signalWindow = true;
        }

        if (signalWindow && windowStateChanged.assigned)
            windowStateChanged(this, newState, newWindowRect);
    }

    /// Change window state, position, or size; returns true if successful, false if not supported by platform
    bool setWindowState(WindowState newState, bool activate = false, Box newWindowRect = Box.none)
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
    bool move(Point topLeft, bool activate = false)
    {
        return setWindowState(WindowState.unspecified, activate, Box(topLeft.x, topLeft.y, int.min, int.min));
    }
    /// Change window size only
    bool resize(Size sz, bool activate = false)
    {
        return setWindowState(WindowState.unspecified, activate, Box(int.min, int.min, sz.w, sz.h));
    }
    /// Set window rectangle
    bool moveAndResize(Box rc, bool activate = false)
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
            if (w.flags & WindowFlag.modal && w._windowState != WindowState.hidden)
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
            if (w.flags & WindowFlag.modal && w._windowState != WindowState.hidden)
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
            if (w.flags & WindowFlag.modal && w._windowState != WindowState.hidden)
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

    /// Set or override the window minimum size
    void setMinimumSize(Size minSize) // TODO x11 win32
    {
        // override to support
    }

    /// Set or override the window maximum size
    void setMaximumSize(Size maxSize) // TODO x11 win32
    {
        // override to support
    }

    /// Set the minimal window size and resize the window if needed; called from show()
    protected void adjustSize()
    {
        assert(_mainWidget !is null);
        Boundaries bs = _mainWidget.computeBoundaries();
        _minContentSize = bs.min;
        _goodContentSize = bs.nat;
        // some sane constraints
        _minContentSize = Size(clamp(_minContentSize.w, 0, 10000), clamp(_minContentSize.h, 0, 10000));
        _goodContentSize = Size(clamp(_goodContentSize.w, 0, 10000), clamp(_goodContentSize.h, 0, 10000));
        setMaximumSize(Size(10000, 10000));
        // set minimum and then resize
        setMinimumSize(_minContentSize);
        Size sz;
        if (flags & WindowFlag.expanded)
        {
            sz.w = max(_windowRect.w, _goodContentSize.w);
            sz.h = max(_windowRect.h, _goodContentSize.h);
        }
        else
        {
            sz.w = max(_windowRect.w, _minContentSize.w);
            sz.h = max(_windowRect.h, _minContentSize.h);
        }
        resize(sz);
    }

    /// Adjust window position during show()
    protected void adjustPosition()
    {
        if (flags & WindowFlag.centered)
            centerOnParentWindow();
    }

    /// Center window on parent window, do nothing if there is no parent window
    void centerOnParentWindow()
    {
        if (parentWindow)
        {
            Box parentRect = parentWindow.windowRect;
            Point newPos;
            newPos.x = parentRect.x + (parentRect.width - _windowRect.width) / 2;
            newPos.y = parentRect.y + (parentRect.height - _windowRect.height) / 2;
            move(newPos);
        }
    }

    /// Request layout for main widget and popups
    void requestLayout()
    {
        _mainWidget.maybe.requestLayout();
        foreach (p; _popups)
            p.requestLayout();
        _tooltip.popup.maybe.requestLayout();
    }

    /// Measure and layout main widget, popups and tooltip
    void layout()
    {
        if (_mainWidget)
        {
            Boundaries bs = _mainWidget.computeBoundaries();
            // TODO: set minimum window size
            _mainWidget.maybe.layout(Box(0, 0, _w, _h));
        }
        foreach (p; _popups)
        {
            Boundaries bs = p.computeBoundaries();
            p.layout(Box(0, 0, bs.nat.w, bs.nat.h));
        }
        if (auto tp = _tooltip.popup)
        {
            Boundaries bs = tp.computeBoundaries();
            tp.layout(Box(0, 0, bs.nat.w, bs.nat.h));
        }
    }

    void onResize(int width, int height)
    {
        if (_w == width && _h == height)
            return;
        _w = width;
        _h = height;
        // fix window rect for platforms that don't set it yet
        _windowRect.width = width;
        _windowRect.height = height;
        if (_mainWidget)
        {
            debug (resizing)
            {
                Log.d("onResize ", _w, "x", _h);
                long layoutStart = currentTimeMillis;
            }
            layout();
            debug (resizing)
            {
                long layoutEnd = currentTimeMillis;
                Log.d("resize: layout took ", layoutEnd - layoutStart, " ms");
            }
        }
        update(true);
    }

    protected Popup[] _popups;

    protected static struct TooltipInfo
    {
        Popup popup;
        ulong timerID;
        Widget ownerWidget;
        int x;
        int y;
        PopupAlign alignment;
    }

    protected TooltipInfo _tooltip;

    /// Schedule tooltip for widget be shown with specified delay
    void scheduleTooltip(Widget ownerWidget, long delay, PopupAlign alignment = PopupAlign.below, int x = 0, int y = 0)
    {
        debug (tooltips)
            Log.d("schedule tooltip");
        _tooltip.alignment = alignment;
        _tooltip.x = x;
        _tooltip.y = y;
        _tooltip.ownerWidget = ownerWidget;
        _tooltip.timerID = setTimer(ownerWidget, delay);
    }

    /// Call when tooltip timer is expired
    private bool onTooltipTimer()
    {
        debug (tooltips)
            Log.d("onTooltipTimer");
        _tooltip.timerID = 0;
        if (isChild(_tooltip.ownerWidget))
        {
            debug (tooltips)
                Log.d("onTooltipTimer: create tooltip");
            Widget w = _tooltip.ownerWidget.createTooltip(_lastMouseX, _lastMouseY,
                    _tooltip.alignment, _tooltip.x, _tooltip.y);
            if (w)
                showTooltip(w, _tooltip.ownerWidget, _tooltip.alignment, _tooltip.x, _tooltip.y);
        }
        return false;
    }

    /// Show tooltip immediately
    Popup showTooltip(Widget content, Widget anchor = null,
            PopupAlign alignment = PopupAlign.center, int x = 0, int y = 0)
    {
        hideTooltip();
        debug (tooltips)
            Log.d("show tooltip");
        if (!content)
            return null;
        auto res = new Popup(content, this);
        res.anchor = PopupAnchor(anchor !is null ? anchor : _mainWidget, x, y, alignment);
        _tooltip.popup = res;
        return res;
    }

    /// Hide tooltip if shown and cancel tooltip timer if set
    void hideTooltip()
    {
        debug (tooltips)
            Log.d("hide tooltip");
        if (_tooltip.popup)
        {
            debug (tooltips)
                Log.d("destroy tooltip");
            destroy(_tooltip.popup);
            _tooltip.popup = null;
            _mainWidget.maybe.invalidate();
        }
        if (_tooltip.timerID)
            cancelTimer(_tooltip.timerID);
    }

    /// Show new popup
    Popup showPopup(Widget content, Widget anchor = null,
            PopupAlign alignment = PopupAlign.center, int x = 0, int y = 0)
    {
        auto res = new Popup(content, this);
        res.anchor = PopupAnchor(anchor/+anchor !is null ? anchor : _mainWidget+/, x, y, alignment); // TODO: test all cases
        _popups ~= res;
        setFocus(content);
        _mainWidget.maybe.requestLayout();
        update(false);
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

    /// Returns last modal popup widget, or null if no modal popups opened
    Popup modalPopup()
    {
        foreach_reverse (p; _popups)
        {
            if (p.flags & PopupFlags.modal)
                return p;
        }
        return null;
    }

    /// Called when user dragged file(s) to application window
    void handleDroppedFiles(string[] filenames)
    {
        //Log.d("handleDroppedFiles(", filenames, ")");
        if (_onFilesDropped)
            _onFilesDropped(filenames);
    }

    protected void delegate(string[]) _onFilesDropped;
    /// Get handler for files dropped to app window
    @property void delegate(string[]) onFilesDropped()
    {
        return _onFilesDropped;
    }
    /// Set handler for files dropped to app window
    @property Window onFilesDropped(void delegate(string[]) handler)
    {
        _onFilesDropped = handler;
        return this;
    }

    protected bool delegate() _onCanClose;
    /// Get handler for closing of app (it must return true to allow immediate close, false to cancel close or close window later)
    @property bool delegate() onCanClose()
    {
        return _onCanClose;
    }
    /// Set handler for closing of app (it must return true to allow immediate close, false to cancel close or close window later)
    @property Window onCanClose(bool delegate() handler)
    {
        _onCanClose = handler;
        return this;
    }

    protected void delegate() _onClose;
    /// Get handler for closing of window
    @property void delegate() onClose()
    {
        return _onClose;
    }
    /// Set handler for closing of window
    @property Window onClose(void delegate() handler)
    {
        _onClose = handler;
        return this;
    }

    /// Returns true if there is some modal window opened above this window, and this window should not process mouse/key input and should not allow closing
    @property bool hasModalWindowsAbove()
    {
        return platform.hasModalWindowsAbove(this);
    }

    /// Call onCanClose handler if set to check if system may close window
    bool handleCanClose()
    {
        if (hasModalWindowsAbove)
            return false;
        if (!_onCanClose)
            return true;
        bool res = _onCanClose();
        if (!res)
            update(true); // redraw window if it was decided to not close immediately
        return res;
    }

    /// Returns true if widget is child of either main widget, one of popups or window scrollbar
    bool isChild(Widget w)
    {
        if (_mainWidget && _mainWidget.isChild(w))
            return true;
        foreach (p; _popups)
            if (p.isChild(w))
                return true;
        if (_tooltip.popup && _tooltip.popup.isChild(w))
            return true;
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
    void queueWidgetDestroy(Widget widgetToDestroy)
    {
        auto ev = new QueueDestroyEvent(widgetToDestroy);
        postEvent(ev);
    }

    private void animate(Widget root, long interval)
    {
        if (root is null)
            return;
        if (root.visibility != Visibility.visible)
            return;
        foreach (i; 0 .. root.childCount)
            animate(root.child(i), interval);
        if (root.animating)
            root.animate(interval);
    }

    private void animate(long interval)
    {
        animate(_mainWidget, interval);
        foreach (p; _popups)
            p.animate(interval);
        _tooltip.popup.maybe.animate(interval);
    }

    /// OpenGL-specific routines
    static if (USE_OPENGL)
    {
        /// Make window OpenGL context to be current
        abstract protected void bindContext();
        /// Swap buffers at the end of frame
        abstract protected void swapBuffers();

        protected void drawUsingOpenGL(ref DrawBuf buf) // TODO: move drawbufs to the base class?
        {
            import derelict.opengl3.gl;
            import derelict.opengl3.gl3;
            import beamui.graphics.gldrawbuf;

            bindContext();
            glDisable(GL_DEPTH_TEST);
            glViewport(0, 0, _w, _h);
            float a = 1.0f;
            float r = ((_backgroundColor >> 16) & 255) / 255.0f;
            float g = ((_backgroundColor >> 8) & 255) / 255.0f;
            float b = ((_backgroundColor >> 0) & 255) / 255.0f;
            glClearColor(r, g, b, a);
            glClear(GL_COLOR_BUFFER_BIT);
            if (!buf)
                buf = new GLDrawBuf(_w, _h);
            else
                buf.resize(_w, _h);
            buf.beforeDrawing();
            static if (false)
            {
                // for testing the render
                buf.fillRect(Rect(100, 100, 200, 200), 0x704020);
                buf.fillRect(Rect(40, 70, 100, 120), 0x000000);
                buf.fillRect(Rect(80, 80, 150, 150), 0x80008000); // green
                drawableCache.get("exit").drawTo(buf, Rect(300, 100, 364, 164));
                drawableCache.get("computer").drawTo(buf, Rect(300, 200, 564, 264));
                drawableCache.get("folder").drawTo(buf, Rect(300, 0, 400, 50));
                drawableCache.get("user-home").drawTo(buf, Rect(0, 0, 100, 50));
                FontRef fnt = currentTheme.root.font;
                fnt.drawText(buf, 40, 40, "Some Text 1234567890 !@#$^*", 0x80FF0000);
            }
            else
            {
                onDraw(buf);
            }
            buf.afterDrawing();
            swapBuffers();
        }
    }

    enum PERFORMANCE_LOGGING_THRESHOLD_MS = 2;

    /// Set when first draw is called: don't handle mouse/key input until draw (layout) is called
    protected bool _firstDrawCalled = false;
    private long lastDrawTs;
    void onDraw(DrawBuf buf)
    {
        _firstDrawCalled = true;
        static import std.datetime;

        try
        {
            bool needDraw = false;
            bool needLayout = false;
            bool animationActive = false;
            checkUpdateNeeded(needDraw, needLayout, animationActive);
            if (needLayout || animationActive)
                needDraw = true;
            long ts = std.datetime.Clock.currStdTime;
            if (animationActive && lastDrawTs != 0)
            {
                animate(ts - lastDrawTs);
                // layout required flag could be changed during animate - check again
                checkUpdateNeeded(needDraw, needLayout, animationActive);
            }
            lastDrawTs = ts;
            if (needLayout)
            {
                debug (redraw)
                    long layoutStart = currentTimeMillis;
                layout();
                debug (redraw)
                {
                    long layoutEnd = currentTimeMillis;
                    if (layoutEnd - layoutStart > PERFORMANCE_LOGGING_THRESHOLD_MS)
                        Log.d("layout took ", layoutEnd - layoutStart, " ms");
                }
                //checkUpdateNeeded(needDraw, needLayout, animationActive);
            }
            debug (redraw)
                long drawStart = currentTimeMillis;
            // draw main widget
            _mainWidget.onDraw(buf);

            Popup modal = modalPopup();

            // draw popups
            foreach (p; _popups)
            {
                if (p is modal)
                {
                    // TODO: get shadow color from theme
                    buf.fillRect(Rect(0, 0, buf.width, buf.height), 0xD0404040);
                }
                p.onDraw(buf);
            }

            _tooltip.popup.maybe.onDraw(buf);

            debug (redraw)
            {
                long drawEnd = currentTimeMillis;
                if (drawEnd - drawStart > PERFORMANCE_LOGGING_THRESHOLD_MS)
                    Log.d("draw took ", drawEnd - drawStart, " ms");
            }
            if (animationActive)
                scheduleAnimation();
        }
        catch (Exception e)
        {
            Log.e("Exception inside window.onDraw: ", e);
        }
    }

    /// After drawing, call to schedule redraw if animation is active
    void scheduleAnimation()
    {
        // override if necessary
    }

    protected void setCaptureWidget(Widget w, MouseEvent event)
    {
        _mouseCaptureWidget = w;
        _mouseCaptureButtons = event.flags & (MouseFlag.lbutton | MouseFlag.rbutton | MouseFlag.mbutton);
    }

    protected Widget _focusedWidget;
    protected auto _focusStateToApply = State.focused;
    /// Returns current focused widget
    @property Widget focusedWidget()
    {
        if (!isChild(_focusedWidget))
            _focusedWidget = null;
        return _focusedWidget;
    }

    /// Change focus to widget
    Widget setFocus(Widget newFocus, FocusReason reason = FocusReason.unspecified)
    {
        if (!isChild(_focusedWidget))
            _focusedWidget = null;
        Widget oldFocus = _focusedWidget;
        auto targetState = State.focused;
        if (reason == FocusReason.tabFocus)
            targetState = State.focused | State.keyboardFocused;
        _focusStateToApply = targetState;
        if (oldFocus is newFocus)
            return oldFocus;
        if (oldFocus !is null)
        {
            oldFocus.resetState(targetState);
            if (oldFocus)
                oldFocus.focusGroupFocused(false);
        }
        if (newFocus is null || isChild(newFocus))
        {
            if (newFocus !is null)
            {
                // when calling, setState(focused), window.focusedWidget is still previously focused widget
                debug (focus)
                    Log.d("new focus: ", newFocus.id);
                newFocus.setState(targetState);
            }
            _focusedWidget = newFocus;
            if (_focusedWidget)
                _focusedWidget.focusGroupFocused(true);
            // after focus change, ask for actions update automatically
            //requestActionsUpdate();
        }
        return _focusedWidget;
    }

    protected Widget applyFocus()
    {
        if (!isChild(_focusedWidget))
            _focusedWidget = null;
        if (_focusedWidget)
        {
            _focusedWidget.setState(_focusStateToApply);
            update();
        }
        return _focusedWidget;
    }

    protected Widget removeFocus()
    {
        if (!isChild(_focusedWidget))
            _focusedWidget = null;
        if (_focusedWidget)
        {
            _focusedWidget.resetState(_focusStateToApply);
            update();
        }
        return _focusedWidget;
    }

    @property bool isActive()
    {
        return true;
    }

    /// Window activate/deactivate signal
    Signal!(void delegate(Window, bool isWindowActive)) windowActivityChanged;

    protected void handleWindowActivityChange(bool isWindowActive)
    {
        if (isWindowActive)
            applyFocus();
        else
            removeFocus();
        windowActivityChanged(this, isWindowActive);
    }

    /// Call an action, considering action context
    bool call(Action action)
    {
        if (action)
        {
            Widget focus = focusedWidget;
            auto context = action.context;
            return action.call((Widget wt) {
                if (context == ActionContext.application)
                {
                    return true;
                }
                else if (wt)
                {
                    if (context == ActionContext.window && wt.window is this ||
                        context == ActionContext.widgetTree && wt.isChild(focus) ||
                        context == ActionContext.widget && wt is focus)
                    {
                        return true;
                    }
                }
                return false;
            });
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
        Popup modal = modalPopup();
        if (event.action == KeyAction.keyDown || event.action == KeyAction.keyUp)
        {
            _keyboardModifiers = event.flags;
            if (event.keyCode == KeyCode.alt || event.keyCode == KeyCode.lalt || event.keyCode == KeyCode.ralt)
            {
                debug (keys)
                    Log.d("Alt key: keyboardModifiers = ", _keyboardModifiers);
                if (_mainWidget)
                {
                    _mainWidget.invalidate();
                    res = true;
                }
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
        Widget focus = focusedWidget;
        if (!modal || modal.isChild(focus))
        {
            // process shortcuts
            if (event.action == KeyAction.keyDown)
            {
                auto a = Action.findByShortcut(event.keyCode, event.flags);
                if (call(a))
                    return true;
            }
            while (focus)
            {
                if (focus.onKeyEvent(event))
                    return true; // processed by focused widget
                if (focus.focusGroup)
                    break;
                focus = focus.parent;
            }
        }
        if (modal)
        {
            if (dispatchKeyEvent(modal, event))
                return res;
            return modal.onKeyEvent(event) || res;
        }
        else if (_mainWidget)
        {
            if (dispatchKeyEvent(_mainWidget, event))
                return res;
            return _mainWidget.onKeyEvent(event) || res;
        }
        return res;
    }

    /// Dispatch key event to widgets which have wantsKeyTracking == true
    protected bool dispatchKeyEvent(Widget root, KeyEvent event)
    {
        if (root.visibility != Visibility.visible)
            return false;
        if (root.wantsKeyTracking)
        {
            if (root.onKeyEvent(event))
                return true;
        }
        foreach (i; 0 .. root.childCount)
        {
            Widget w = root.child(i);
            if (dispatchKeyEvent(w, event))
                return true;
        }
        return false;
    }

    protected bool dispatchMouseEvent(Widget root, MouseEvent event, ref bool cursorIsSet)
    {
        // only route mouse events to visible widgets
        if (root.visibility != Visibility.visible)
            return false;
        if (!root.isPointInside(event.x, event.y))
            return false;
        // offer event to children first
        foreach (i; 0 .. root.childCount)
        {
            Widget child = root.child(i);
            if (dispatchMouseEvent(child, event, cursorIsSet))
                return true;
        }

        if (event.action == MouseAction.move && !cursorIsSet)
        {
            CursorType cursorType = root.getCursorType(event.x, event.y);
            if (cursorType != CursorType.notSet)
            {
                setCursorType(cursorType);
                cursorIsSet = true;
            }
        }
        // if not processed by children, offer event to root
        if (sendAndCheckOverride(root, event))
        {
            debug (mouse)
                Log.d("MouseEvent is processed");
            if (event.action == MouseAction.buttonDown && _mouseCaptureWidget is null && !event.doNotTrackButtonDown)
            {
                debug (mouse)
                    Log.d("Setting active widget");
                setCaptureWidget(root, event);
            }
            else if (event.action == MouseAction.move)
            {
                addTracking(root);
            }
            return true;
        }
        return false;
    }

    /// Widget which tracks Move events
    protected Widget[] _mouseTrackingWidgets;
    private void addTracking(Widget w)
    {
        foreach (mtw; _mouseTrackingWidgets)
            if (w is mtw)
                return;
        _mouseTrackingWidgets ~= w;
        debug (mouse)
            Log.d("addTracking: ", w.id, ", items after: ", _mouseTrackingWidgets.length);
    }

    private bool checkRemoveTracking(MouseEvent event)
    {
        bool res;
        foreach_reverse (ref w; _mouseTrackingWidgets)
        {
            if (!isChild(w))
            {
                w = null;
                continue;
            }
            if (event.action == MouseAction.leave || !w.isPointInside(event.x, event.y))
            {
                // send Leave message
                auto leaveEvent = new MouseEvent(event);
                leaveEvent.changeAction(MouseAction.leave);
                res = w.onMouseEvent(leaveEvent) || res;
                debug (mouse)
                    Log.d("removeTracking of ", w.id);
                w = null;
            }
        }
        _mouseTrackingWidgets = _mouseTrackingWidgets.efilter!(a => a !is null);
        debug (mouse)
            Log.d("removeTracking, items after: ", _mouseTrackingWidgets.length);
        return res;
    }

    /// Widget which tracks all events after processed ButtonDown
    protected Widget _mouseCaptureWidget;
    protected ushort _mouseCaptureButtons;
    protected bool _mouseCaptureFocusedOut;
    /// Does current capture widget want to receive move events even if pointer left it
    protected bool _mouseCaptureFocusedOutTrackMovements;

    protected void clearMouseCapture()
    {
        _mouseCaptureWidget = null;
        _mouseCaptureFocusedOut = false;
        _mouseCaptureFocusedOutTrackMovements = false;
        _mouseCaptureButtons = 0;
    }

    protected bool dispatchCancel(MouseEvent event)
    {
        event.changeAction(MouseAction.cancel);
        bool res = _mouseCaptureWidget.onMouseEvent(event);
        clearMouseCapture();
        return res;
    }

    protected bool sendAndCheckOverride(Widget widget, MouseEvent event)
    {
        if (!isChild(widget))
            return false;
        bool res = widget.onMouseEvent(event);
        if (event.trackingWidget !is null && _mouseCaptureWidget !is event.trackingWidget)
        {
            setCaptureWidget(event.trackingWidget, event);
        }
        return res;
    }

    /// Returns true if mouse is currently captured
    bool isMouseCaptured()
    {
        return (_mouseCaptureWidget !is null && isChild(_mouseCaptureWidget));
    }

    /// Handle theme change: e.g. reload some themed resources
    void dispatchThemeChanged()
    {
        _mainWidget.maybe.onThemeChanged();
        foreach (p; _popups)
            p.onThemeChanged();
        _tooltip.popup.maybe.onThemeChanged();
        if (currentTheme)
        {
            _backgroundColor = currentTheme.getColor("window_background");
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
        auto event = new RunnableEvent(CUSTOM_RUNNABLE, null, runnable);
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
        if (event.destinationWidget)
        {
            if (!isChild(event.destinationWidget))
            {
                //Event is sent to widget which does not exist anymore
                return false;
            }
            return event.destinationWidget.onEvent(event);
        }
        else
        {
            // no destination widget
            RunnableEvent runnable = cast(RunnableEvent)event;
            if (runnable)
            {
                // handle runnable
                runnable.run();
                return true;
            }
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
        // ignore events if there is no root
        if (!_mainWidget)
            return false;

        bool actualChange = true;
        if (event.action == MouseAction.move)
        {
            actualChange = (_lastMouseX != event.x || _lastMouseY != event.y);
            _lastMouseX = event.x;
            _lastMouseY = event.y;
        }
        if (actualChange)
            hideTooltip();

        Popup modal = modalPopup();

        // check if _mouseCaptureWidget and _mouseTrackingWidget still exist in child of root widget
        if (_mouseCaptureWidget !is null && (!isChild(_mouseCaptureWidget) || (modal &&
                !modal.isChild(_mouseCaptureWidget))))
        {
            clearMouseCapture();
        }

        debug (mouse)
            Log.fd("dispatchMouseEvent %s (%s, %s)", event.action, event.x, event.y);

        bool res;
        ushort currentButtons = event.flags & (MouseFlag.lbutton | MouseFlag.rbutton | MouseFlag.mbutton);
        if (_mouseCaptureWidget !is null)
        {
            // try to forward message directly to active widget
            if (event.action == MouseAction.move)
            {
                debug (mouse)
                    Log.d("dispatchMouseEvent: Move, buttons state: ", currentButtons);
                if (!_mouseCaptureWidget.isPointInside(event.x, event.y))
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
                        _mouseCaptureFocusedOutTrackMovements = sendAndCheckOverride(_mouseCaptureWidget, event);
                        return true;
                    }
                    else if (_mouseCaptureFocusedOutTrackMovements)
                    {
                        // pointer is outside, but we still need to track pointer
                        return sendAndCheckOverride(_mouseCaptureWidget, event);
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
                    return sendAndCheckOverride(_mouseCaptureWidget, event);
                }
            }
            else if (event.action == MouseAction.leave)
            {
                if (!_mouseCaptureFocusedOut)
                {
                    // sending FocusOut message
                    event.changeAction(MouseAction.focusOut);
                    _mouseCaptureFocusedOut = true;
                    _mouseCaptureButtons = event.flags & (MouseFlag.lbutton | MouseFlag.rbutton | MouseFlag.mbutton);
                    return sendAndCheckOverride(_mouseCaptureWidget, event);
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
                if (!_mouseCaptureWidget.isPointInside(event.x, event.y))
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
            res = sendAndCheckOverride(_mouseCaptureWidget, event);
            if (!currentButtons)
            {
                // usable capturing - no more buttons pressed
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

        bool cursorIsSet = overrideCursorType != CursorType.notSet;

        if (!res)
        {
            bool insideOneOfPopups;
            foreach_reverse (p; _popups)
            {
                if (p.isPointInside(event.x, event.y))
                {
                    if (p !is modal)
                        insideOneOfPopups = true;
                }
                if (p is modal)
                    break;
            }
            foreach_reverse (p; _popups)
            {
                if (p is modal)
                    break;
                if (!insideOneOfPopups)
                {
                    if (event.action == MouseAction.buttonDown)
                        return true; // mouse button down should do nothing when click outside when popup visible
                    if (p.onMouseEventOutside(event))
                        return true; // mouse button up should do nothing when click outside when popup visible
                }
                else
                {
                    if (dispatchMouseEvent(p, event, cursorIsSet))
                        return true;
                }
            }
            if (!modal)
                res = dispatchMouseEvent(_mainWidget, event, cursorIsSet);
            else
                res = dispatchMouseEvent(modal, event, cursorIsSet);
        }
        return res || processed || _mainWidget.needDraw;
    }

    /// Set cursor type for window
    protected void setCursorType(CursorType cursorType)
    {
        // override to support different mouse cursors
    }

    /// Check content widgets for necessary redraw and/or layout
    bool checkUpdateNeeded(ref bool needDraw, ref bool needLayout, ref bool animationActive)
    {
        needDraw = needLayout = animationActive = false;
        if (_mainWidget is null)
            return false;
        checkUpdateNeeded(_mainWidget, needDraw, needLayout, animationActive);
        foreach (p; _popups)
            checkUpdateNeeded(p, needDraw, needLayout, animationActive);
        if (_tooltip.popup)
            checkUpdateNeeded(_tooltip.popup, needDraw, needLayout, animationActive);
        return needDraw || needLayout || animationActive;
    }
    /// Check content widgets for necessary redraw and/or layout
    protected void checkUpdateNeeded(Widget root, ref bool needDraw, ref bool needLayout, ref bool animationActive)
    {
        if (root is null)
            return;
        if (root.visibility != Visibility.visible)
            return;
        needDraw = root.needDraw || needDraw;
        if (!needLayout)
        {
            needLayout = root.needLayout;
            debug (redraw)
                if (needLayout)
                    Log.fd("Need layout: %s, id: %s, parent: %s",
                        root.classinfo.name, root.id, root.parent ? root.parent.classinfo.name : "null");
        }
        if (root.animating && root.visible)
            animationActive = true; // check animation only for visible widgets
        foreach (i; 0 .. root.childCount)
            checkUpdateNeeded(root.child(i), needDraw, needLayout, animationActive);
    }

    protected bool _animationActive;

    @property bool isAnimationActive()
    {
        return _animationActive;
    }

    /// Request update for window (unless force is true, update will be performed only if layout, redraw or animation is required).
    void update(bool force = false)
    {
        if (_mainWidget is null)
            return;
        bool needDraw = false;
        bool needLayout = false;
        _animationActive = false;
        if (force || checkUpdateNeeded(needDraw, needLayout, _animationActive))
        {
            debug (redraw)
                Log.d("Requesting update");
            invalidate();
        }
        debug (redraw)
            Log.d("checkUpdateNeeded returned needDraw: ", needDraw, ", needLayout: ", needLayout,
                    ", animationActive: ", _animationActive);
    }

    /// Show message box with specified title and message
    void showMessageBox(dstring title, dstring message, Action[] actions = [ACTION_OK],
            int defaultActionIndex = 0, void delegate(const Action result) handler = null)
    {
        import beamui.dialogs.msgbox;

        auto dlg = new MessageBox(title, message, this, actions, defaultActionIndex, handler);
        dlg.show();
    }

    void showInputBox(dstring title, dstring message, dstring initialText, void delegate(dstring result) handler)
    {
        import beamui.dialogs.inputbox;

        auto dlg = new InputBox(title, message, this, initialText, handler);
        dlg.show();
    }

    protected TimerQueue _timerQueue;

    /// Schedule timer for interval in milliseconds - call window.onTimer when finished
    protected void scheduleSystemTimer(long intervalMillis)
    {
        //debug Log.d("override scheduleSystemTimer to support timers");
    }

    /// Poll expired timers; returns true if update is needed
    bool pollTimers()
    {
        bool res = _timerQueue.notify();
        if (res)
            update(false);
        return res;
    }

    /// System timer interval expired - notify queue
    protected void onTimer()
    {
        debug (timers)
            Log.d("window.onTimer");
        bool res = _timerQueue.notify();
        if (res)
        {
            // check if update needed and redraw if so
            debug (timers)
                Log.d("before update");
            update(false);
            debug (timers)
                Log.d("after update");
        }
        debug (timers)
            Log.d("schedule next timer");
        long nextInterval = _timerQueue.nextIntervalMillis();
        if (nextInterval > 0)
        {
            scheduleSystemTimer(nextInterval);
        }
    }

    /// Set timer for destination widget - destination.onTimer() will be called after interval expiration; returns timer id
    ulong setTimer(Widget destination, long intervalMillis)
    {
        if (!isChild(destination))
        {
            Log.e("setTimer() is called not for child widget of window");
            return 0;
        }
        ulong res = _timerQueue.add(destination, intervalMillis);
        long nextInterval = _timerQueue.nextIntervalMillis();
        if (nextInterval > 0)
        {
            scheduleSystemTimer(intervalMillis);
        }
        return res;
    }

    /// Cancel previously scheduled widget timer (for timerID pass value returned from setTimer)
    void cancelTimer(ulong timerID)
    {
        _timerQueue.cancelTimer(timerID);
    }

    /// Timers queue
    private class TimerQueue
    {
        protected TimerInfo[] _queue;
        /// Add new timer, returns timer id
        ulong add(Widget destination, long intervalMillis)
        {
            TimerInfo item = new TimerInfo(destination, intervalMillis);
            _queue ~= item;
            sort(_queue);
            return item.id;
        }
        /// Cancel timer
        void cancelTimer(ulong timerID)
        {
            if (!_queue.length)
                return;
            for (int i = cast(int)_queue.length - 1; i >= 0; i--)
            {
                if (_queue[i].id == timerID)
                {
                    _queue[i].cancel();
                    break;
                }
            }
        }
        /// Returns interval if millis of next scheduled event or -1 if no events queued
        long nextIntervalMillis()
        {
            if (!_queue.length || !_queue[0].valid)
                return -1;
            long delta = _queue[0].nextTimestamp - currentTimeMillis;
            if (delta < 1)
                delta = 1;
            return delta;
        }

        private void cleanup()
        {
            if (!_queue.length)
                return;
            sort(_queue);
            size_t newsize = _queue.length;
            for (int i = cast(int)_queue.length - 1; i >= 0; i--)
            {
                if (!_queue[i].valid)
                {
                    newsize = i;
                }
            }
            if (_queue.length > newsize)
                _queue.length = newsize;
        }

        private TimerInfo[] expired()
        {
            if (!_queue.length)
                return null;
            long ts = currentTimeMillis;
            TimerInfo[] res;
            for (int i = 0; i < _queue.length; i++)
            {
                if (_queue[i].nextTimestamp <= ts)
                    res ~= _queue[i];
            }
            return res;
        }
        /// Returns true if at least one widget was notified
        bool notify()
        {
            bool res = false;
            checkValidWidgets();
            TimerInfo[] list = expired();
            if (list)
            {
                for (int i = 0; i < list.length; i++)
                {
                    if (_queue[i].id == _tooltip.timerID)
                    {
                        // special case for tooltip timer
                        onTooltipTimer();
                        _queue[i].cancel();
                        res = true;
                    }
                    else
                    {
                        Widget w = _queue[i].targetWidget;
                        if (w && !isChild(w))
                            _queue[i].cancel();
                        else
                        {
                            _queue[i].notify();
                            res = true;
                        }
                    }
                }
            }
            cleanup();
            return res;
        }

        private void checkValidWidgets()
        {
            for (int i = 0; i < _queue.length; i++)
            {
                Widget w = _queue[i].targetWidget;
                if (w && !isChild(w))
                    _queue[i].cancel();
            }
            cleanup();
        }
    }
}

/**
    Platform abstraction layer.

    Represents application. Holds set of windows.
*/
class Platform
{
    static __gshared Platform _instance;
    static void setInstance(Platform instance)
    {
        eliminate(_instance);
        _instance = instance;
    }

    static @property Platform instance()
    {
        return _instance;
    }

    /**
    Create a window
    Args:
        title = window title text
        parent = parent Window, or null if no parent
        flags = WindowFlag bit set, combination of Resizable, Modal, Fullscreen
        width = window width
        height = window height

    Window w/o `resizable` nor `fullscreen` will be created with a size based on measurement of its content widget
    */
    abstract Window createWindow(dstring title, Window parent,
            WindowFlag flags = WindowFlag.resizable, uint width = 0, uint height = 0);

    static if (USE_OPENGL)
    {
        /**
        OpenGL context major version.

        Note: if the version is invalid or not supported, this value will be set to supported one.
        */
        int GLVersionMajor = 3;
        /**
        OpenGL context minor version.

        Note: if the version is invalid or not supported, this value will be set to supported one.
        */
        int GLVersionMinor = 2;
    }
    /**
    Close a window.

    Closes window earlier created with createWindow()
     */
    abstract void closeWindow(Window w);
    /**
    Starts application message loop.

    When returned from this method, application is shutting down.
     */
    abstract int enterMessageLoop();
    /// Check has clipboard text
    abstract bool hasClipboardText(bool mouseBuffer = false);
    /// Retrieve text from clipboard (when mouseBuffer == true, use mouse selection clipboard - under linux)
    abstract dstring getClipboardText(bool mouseBuffer = false);
    /// Set text to clipboard (when mouseBuffer == true, use mouse selection clipboard - under linux)
    abstract void setClipboardText(dstring text, bool mouseBuffer = false);

    /// Call request layout for all windows
    abstract void requestLayout();

    protected
    {
        string _uiLanguage;
        string _themeName;
        ulong _uiDialogDisplayMode = DialogDisplayMode.messageBoxInPopup | DialogDisplayMode.inputBoxInPopup;

        /// Default icon for new created windows
        string _defaultWindowIcon = "beamui-logo";
        IconProviderBase _iconProvider;
    }

    ~this()
    {
        eliminate(_iconProvider);
    }

    @property
    {
        /// Returns currently selected UI language code
        string uiLanguage()
        {
            return _uiLanguage;
        }
        /// Set UI language (e.g. "en", "fr", "ru") - will relayout content of all windows if language has been changed
        Platform uiLanguage(string langCode)
        {
            if (_uiLanguage == langCode)
                return this;
            _uiLanguage = langCode;

            Log.v("Loading language file");
            loadTranslator(langCode);

            Log.v("Calling onThemeChanged");
            onThemeChanged();
            requestLayout();
            return this;
        }

        /// Get name of currently active theme
        string uiTheme()
        {
            return _themeName;
        }
        /// Set application UI theme - will relayout content of all windows if theme has been changed
        void uiTheme(string name)
        {
            if (_themeName == name)
                return;

            Log.v("uiTheme setting new theme ", name);
            Theme theme;
            if (name != "default")
                theme = loadTheme(name);
            else
                theme = createDefaultTheme();
            if (!theme)
            {
                Log.e("Cannot load theme `", name, "` - will use default theme");
                theme = createDefaultTheme();
            }
            else
            {
                Log.i("Applying loaded theme ", name);
            }
            _themeName = theme.name;
            currentTheme = theme;
            onThemeChanged();
            requestLayout();
        }

        /// Returns how dialogs should be displayed - as popup or window
        ulong uiDialogDisplayMode()
        {
            return _uiDialogDisplayMode;
        }
        /// Set how dialogs should be displayed - as popup or window - use DialogDisplayMode enumeration
        Platform uiDialogDisplayMode(ulong newDialogDisplayMode)
        {
            _uiDialogDisplayMode = newDialogDisplayMode;
            return this;
        }

        /// Returns list of resource directories
        string[] resourceDirs()
        {
            return resourceList.resourceDirs;
        }
        /// Set list of directories to load resources from
        void resourceDirs(string[] dirs)
        {
            // TODO: this function is reserved
            resourceList.resourceDirs = dirs;
        }

        /// Set default icon for new created windows
        void defaultWindowIcon(string newIcon)
        {
            _defaultWindowIcon = newIcon;
        }
        /// Get default icon for new created windows
        string defaultWindowIcon()
        {
            return _defaultWindowIcon;
        }

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

        IconProviderBase iconProvider(IconProviderBase provider)
        {
            _iconProvider = provider;
            return _iconProvider;
        }
    }

    /// Reload current theme. Useful to quickly edit and test a theme
    void reloadTheme()
    {
        Log.v("Reloading theme ", _themeName);
        auto theme = loadTheme(_themeName);
        if (!theme)
        {
            Log.e("Cannot reload theme ", _themeName);
            return;
        }
        currentTheme = theme;
        onThemeChanged();
        requestLayout();
    }

    /// Set uiLanguage and themeID to default (en, theme_default) if not set yet
    protected void setDefaultLanguageAndThemeIfNecessary()
    {
        if (!_uiLanguage)
        {
            Log.v("setDefaultLanguageAndThemeIfNecessary : setting UI language");
            uiLanguage = "en";
        }
        if (!_themeName)
        {
            Log.v("setDefaultLanguageAndThemeIfNecessary : setting UI theme");
            uiTheme = "default";
        }
    }

    /// Returns true if there is some modal window opened above this window,
    /// And this window should not process mouse/key input and should not allow closing
    bool hasModalWindowsAbove(Window w)
    {
        // may override in platform specific class
        return w ? w.hasVisibleModalChild : false;
    }

    /// Open url in external browser
    static void openURL(string url)
    {
        import std.process;

        browse(url);
    }

    /// Show directory or file in OS file manager (explorer, finder, etc...)
    bool showInFileManager(string pathName)
    {
        static import fm = beamui.core.filemanager;

        return fm.showInFileManager(pathName);
    }

    /// Handle theme change, e.g. reload some themed resources
    void onThemeChanged()
    {
        // override and call dispatchThemeChange for all windows
        drawableCache.clear();
        static if (BACKEND_GUI)
        {
            imageCache.clear();
        }
        currentTheme.maybe.onThemeChanged();
    }
}

/// Get current platform object instance
@property Platform platform()
{
    return Platform.instance;
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
        glyphDestroyCallback = null;
        Log.w("OpenGL was disabled");
    }
}

static if (BACKEND_CONSOLE)
{
    // to remove import
    extern (C) int beamuimain(string[] args);
}
else
{
    version (Windows)
    {
        // to remove import
        extern (Windows) int beamuiWinMain(void* hInstance, void* hPrevInstance, char* lpCmdLine, int nCmdShow);
        extern (Windows) int beamuiWinMainProfile(string[] args);
    }
    else
    {
        // to remove import
        extern (C) int beamuimain(string[] args);
    }
}

/// Put "mixin APP_ENTRY_POINT;" to main module of your beamui-based app
mixin template APP_ENTRY_POINT()
{
    version (unittest)
    {
        // no main in unit tests
    }
    else
    {
        static if (BACKEND_CONSOLE)
        {
            int main(string[] args)
            {
                return beamuimain(args);
            }
        }
        else
        {
            /// Workaround for link issue when WinMain is located in library
            version (Windows)
            {
                version (ENABLE_PROFILING)
                {
                    int main(string[] args)
                    {
                        return beamuiWinMainProfile(args);
                    }
                }
                else
                {
                    extern (Windows) int WinMain(void* hInstance, void* hPrevInstance, char* lpCmdLine, int nCmdShow)
                    {
                        try
                        {
                            int res = beamuiWinMain(hInstance, hPrevInstance, lpCmdLine, nCmdShow);
                            return res;
                        }
                        catch (Exception e)
                        {
                            Log.e("Exception: ", e);
                            return 1;
                        }
                    }
                }
            }
            else
            {
                version (Android)
                {
                }
                else
                {
                    int main(string[] args)
                    {
                        return beamuimain(args);
                    }
                }
            }
        }
    }
}

/// Initialize font manager on startup
extern (C) bool initFontManager();
/// Initialize logging (for win32 - to file ui.log, for other platforms - stderr; log level is TRACE for debug builds, and WARN for release builds)
extern (C) void initLogs();
/// Call this when all resources are supposed to be freed to report counts of non-freed resources by type
extern (C) void releaseResourcesOnAppExit();
/// Call this on application initialization
extern (C) void initResourceManagers();
