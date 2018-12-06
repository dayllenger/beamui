/**
Common Platform definitions.

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

import beamui.core.animations;
import beamui.core.asyncsocket;
import beamui.core.stdaction;
import beamui.graphics.iconprovider;
import beamui.graphics.resources;
import beamui.platforms.common.timer;
import beamui.style.theme;
import beamui.widgets.popup;
import beamui.widgets.widget;

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

/// Protected event list
/// References to posted messages can be stored here at least to keep live reference and avoid GC
/// As well, on some platforms it's easy to send id to message queue, but not pointer
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

/**
    Window abstraction layer. Widgets can be shown only inside window.
*/
class Window : CustomEventTarget
{
    @property
    {
        /// Get window behaviour flags
        WindowFlag flags() const { return _flags; }
        /// Assign window behaviour flags
        protected void flags(WindowFlag value) { _flags = value; }

        /// Window background color
        Color backgroundColor() const { return _backgroundColor; }
        /// ditto
        void backgroundColor(Color color)
        {
            _backgroundColor = color;
        }

        /// Get current window width
        int width() const { return _w; }
        /// Assign current window width
        protected void width(int value) { _w = value; }

        /// Get current window height
        int height() const { return _h; }
        /// Assign current window height
        protected void height(int value) { _h = value; }

        /// Get main widget of the window
        inout(Widget) mainWidget() inout { return _mainWidget; }
        /// Assign main widget to the window. Must not be null. Destroys previous main widget.
        void mainWidget(Widget widget)
        {
            assert(widget, "Assigned null main widget");
            if (_mainWidget)
            {
                _mainWidget.window = null;
                destroy(_mainWidget);
            }
            _mainWidget = widget;
            widget.window = this;
        }

        /// Returns parent window
        Window parentWindow() { return _parent; }
        /// Assign parent window
        protected void parentWindow(Window w) { _parent = w; }

        /// Returns current window override cursor type or NotSet if not overriding.
        CursorType overrideCursorType() const { return _overrideCursorType; }
        /// Allow override cursor for entire window. Set to CursorType.notSet to remove cursor type overriding.
        void overrideCursorType(CursorType newCursorType)
        {
            _overrideCursorType = newCursorType;
            setCursorType(newCursorType);
        }

        /// Get current key modifiers
        uint keyboardModifiers() const { return _keyboardModifiers; }

        /// Blinking caret position (empty rect if no blinking caret)
        Rect caretRect() const { return _caretRect; }
        /// ditto
        void caretRect(Rect rc)
        {
            _caretRect = rc;
        }

        /// Blinking caret is in replace mode if true, insert mode if false
        bool caretReplace() const { return _caretReplace; }
        /// ditto
        void caretReplace(bool flag)
        {
            _caretReplace = flag;
        }

        /// Returns current window state
        WindowState windowState() const { return _windowState; }

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
        WindowState _windowState = WindowState.normal;
        Box _windowRect = Box.none;
    }

    private
    {
        int _w;
        int _h;
        Color _backgroundColor = Color(0xFFFFFF);
        Widget _mainWidget;
        EventList _eventList;
        WindowFlag _flags;
        /// Minimal content size
        Size _minContentSize;
        /// Minimal good looking content size
        Size _goodContentSize;

        Window[] _children;
        Window _parent;

        uint _keyboardModifiers;

        Rect _caretRect;
        bool _caretReplace;

        /// Keep overrided cursor type to `notSet` to get cursor from widget
        CursorType _overrideCursorType = CursorType.notSet;

        Animation[] animations;
        ulong animationUpdateTimerID;
    }


    this()
    {
        _children.reserve(10);
        _eventList = new EventList;
        _timerQueue = new TimerQueue;
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

        closing();

        timerThread.maybe.stop();
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
            setting.add("windowState").integer = state;
            if (rect.width > 0 && rect.height > 0)
            {
                setting.add("windowPositionX").integer = rect.x;
                setting.add("windowPositionY").integer = rect.y;
                setting.add("windowWidth").integer = rect.width;
                setting.add("windowHeight").integer = rect.height;
            }
        }
    }

    /// Restore window state from setting object
    bool restoreWindowState(Setting setting)
    {
        if (!setting)
            return false;
        WindowState state = cast(WindowState)setting["windowState"].integerDef(WindowState.unspecified);
        Box rect;
        rect.x = cast(int)setting["windowPositionX"].integer;
        rect.y = cast(int)setting["windowPositionY"].integer;
        int w = cast(int)setting["windowWidth"].integer;
        int h = cast(int)setting["windowHeight"].integer;
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

    /// Get window title (caption)
    abstract @property dstring title() const;
    /// Set window title
    abstract @property void title(dstring caption);
    /// Set window icon
    abstract @property void icon(DrawBufRef icon);

    /// Show window
    abstract void show();
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
        _mainWidget.requestLayout();
        foreach (p; _popups)
            p.requestLayout();
        _tooltip.popup.maybe.requestLayout();
    }

    /// Measure and layout main widget, popups and tooltip
    void layout()
    {
        {
            Boundaries bs = _mainWidget.computeBoundaries();
            // TODO: set minimum window size
            _mainWidget.layout(Box(0, 0, _w, _h));
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
        update(true);
    }

    //===============================================================
    // Popups, tooltips, message and input boxes

    private Popup[] _popups;

    protected static struct TooltipInfo
    {
        Popup popup;
        ulong timerID;
        WeakRef!Widget ownerWidget;
        int x;
        int y;
        PopupAlign alignment;
    }

    private TooltipInfo _tooltip;

    /// Schedule tooltip for widget be shown with specified delay
    void scheduleTooltip(WeakRef!Widget ownerWidget, long delay, PopupAlign alignment = PopupAlign.point,
                         int x = int.min, int y = int.min)
    {
        if (_tooltip.ownerWidget.get !is ownerWidget.get)
        {
            debug (tooltips)
                Log.d("schedule tooltip");
            _tooltip.alignment = alignment;
            _tooltip.x = x;
            _tooltip.y = y;
            _tooltip.ownerWidget = ownerWidget;
            _tooltip.timerID = setTimer(delay, &onTooltipTimer);
        }
    }

    /// Call when tooltip timer is expired
    private bool onTooltipTimer()
    {
        debug (tooltips)
            Log.d("onTooltipTimer");
        _tooltip.timerID = 0;
        if (_tooltip.ownerWidget)
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
    Popup showTooltip(Widget content, WeakRef!Widget anchor = null,
            PopupAlign alignment = PopupAlign.center, int x = int.min, int y = int.min)
    {
        bool noTooltipBefore = _tooltip.popup is null;
        hideTooltip();

        debug (tooltips)
            Log.d("show tooltip");
        if (!content)
            return null;
        auto res = new Popup(content, this);
        res.id = "tooltip-popup";
        // default behaviour is to place tooltip under the mouse cursor
        if (x == int.min)
            x = _lastMouseX;
        if (y == int.min)
            y = _lastMouseY;
        res.anchor = PopupAnchor(anchor, x, y, alignment);

        // add a smooth fade-in transition when there is no tooltip already shown
        if (noTooltipBefore)
        {
            auto tr = Transition(100, TimingFunction.easeIn);
            // may be destroyed
            auto popup = weakRef(res);
            popup.alpha = 255;
            addAnimation(tr.duration, (double t) {
                if (popup)
                    popup.alpha = cast(ubyte)tr.mix(255, 0, t);
            });
        }

        _tooltip.popup = res;
        return res;
    }

    /// Hide tooltip if shown and cancel tooltip timer if set
    void hideTooltip()
    {
        if (_tooltip.popup)
        {
            debug (tooltips)
                Log.d("destroy tooltip");
            destroy(_tooltip.popup);
            _tooltip.popup = null;
            _tooltip.ownerWidget.nullify();
            _mainWidget.invalidate();
        }
        if (_tooltip.timerID)
        {
            debug (tooltips)
                Log.d("cancel tooltip timer");
            cancelTimer(_tooltip.timerID);
            _tooltip.timerID = 0;
            _tooltip.ownerWidget.nullify();
        }
    }

    /// Show new popup
    Popup showPopup(Widget content, WeakRef!Widget anchor = null,
            PopupAlign alignment = PopupAlign.center, int x = 0, int y = 0)
    {
        auto res = new Popup(content, this);
        res.anchor = PopupAnchor(anchor, x, y, alignment);

        // add a smooth fade-in transition
        auto tr = Transition(150, TimingFunction.easeIn);
        // may be destroyed
        auto popup = weakRef(res);
        popup.alpha = 255;
        addAnimation(tr.duration, (double t) {
            if (popup)
                popup.alpha = cast(ubyte)tr.mix(255, 0, t);
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

    /// Returns last modal popup widget, or null if no modal popups opened
    Popup modalPopup()
    {
        foreach_reverse (p; _popups)
        {
            if (p.modal)
                return p;
        }
        return null;
    }

    /// Show message box with specified title and message
    void showMessageBox(dstring title, dstring message, Action[] actions = [ACTION_OK],
            int defaultActionIndex = 0, void delegate(const Action result) handler = null)
    {
        import beamui.dialogs.messagebox;

        auto dlg = new MessageBox(title, message, this, actions, defaultActionIndex, handler);
        dlg.show();
    }

    void showInputBox(dstring title, dstring message, dstring initialText, void delegate(dstring result) handler)
    {
        import beamui.dialogs.inputbox;

        auto dlg = new InputBox(title, message, this, initialText, handler);
        dlg.show();
    }

    //===============================================================

    private Listener!(void delegate(string[])) _filesDropped;
    /// Set handler for files dropped to app window
    @property void onFilesDropped(void delegate(string[]) handler)
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
    Listener!(void delegate()) closing;

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

    /// Returns true if widget is child of either main widget, one of popups or window scrollbar
    bool isChild(Widget w)
    {
        if (_mainWidget.isChild(w))
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

    void addAnimation(long duration, void delegate(double) handler)
    {
        assert(duration > 0 && handler);
        animations ~= Animation(duration * ONE_SECOND / 1000, handler);
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
            animations = animations.efilter!(a => a.handler !is null);

        // process widget ones
        animate(_mainWidget, interval);
        foreach (p; _popups)
            animate(p, interval);
        if (auto p = _tooltip.popup)
            animate(p, interval);
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
            float r, g, b;
            _backgroundColor.rgbf(r, g, b);
            glClearColor(r, g, b, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            if (!buf)
                buf = new GLDrawBuf(_w, _h);
            else
                buf.resize(_w, _h);
            buf.beforeDrawing();
            static if (false)
            {
                // testing the render
                buf.fillRect(Rect(100, 100, 200, 200), 0x704020);
                buf.fillRect(Rect(40, 70, 100, 120), 0x000000);
                buf.fillRect(Rect(80, 80, 150, 150), 0x80008000); // green
                auto dr1 = new ImageDrawable(imageCache.get("exit"));
                auto dr2 = new ImageDrawable(imageCache.get("computer"));
                auto dr3 = new ImageDrawable(imageCache.get("folder"));
                auto dr4 = new ImageDrawable(imageCache.get("user-home"));
                dr1.drawTo(buf, Box(100, 300, 64, 64));
                dr2.drawTo(buf, Box(200, 300, 64, 64));
                dr3.drawTo(buf, Box(300, 300, 80, 60));
                dr4.drawTo(buf, Box(400, 300, 80, 60));
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
    private bool _firstDrawCalled;
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
                // do update every 16 milliseconds
                if (animationUpdateTimerID == 0)
                    animationUpdateTimerID = setTimer(16, { invalidate(); return true; });
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
            }

            debug (redraw)
                long drawStart = currentTimeMillis;

            // draw main widget
            _mainWidget.onDraw(buf);

            // draw popups
            Popup modal = modalPopup();
            foreach (p; _popups)
            {
                if (p is modal)
                {
                    // TODO: get shadow color from theme
                    buf.fillRect(Rect(0, 0, buf.width, buf.height), Color(0xD0404040));
                }
                p.onDraw(buf);
            }

            // and draw tooltip
            _tooltip.popup.maybe.onDraw(buf);

            debug (redraw)
            {
                long drawEnd = currentTimeMillis;
                if (drawEnd - drawStart > PERFORMANCE_LOGGING_THRESHOLD_MS)
                    Log.d("draw took ", drawEnd - drawStart, " ms");
            }
            // cancel animations' update if they are expired
            if (!animationActive && animationUpdateTimerID)
            {
                cancelTimer(animationUpdateTimerID);
                animationUpdateTimerID = 0;
            }
        }
        catch (Exception e)
        {
            Log.e("Exception inside window.onDraw: ", e);
        }
    }

    //===============================================================
    // Focused widget

    private WeakRef!Widget _focusedWidget;
    private State _focusStateToApply = State.focused;
    /// Returns current focused widget
    @property WeakRef!Widget focusedWidget() { return _focusedWidget; }

    /// Change focus to widget
    Widget setFocus(WeakRef!Widget newFocus, FocusReason reason = FocusReason.unspecified)
    {
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
        if (_focusedWidget)
        {
            _focusedWidget.setState(_focusStateToApply);
            update();
        }
        return _focusedWidget;
    }

    protected Widget removeFocus()
    {
        if (_focusedWidget)
        {
            _focusedWidget.resetState(_focusStateToApply);
            update();
        }
        return _focusedWidget;
    }

    /// Is this window focused?
    abstract @property bool isActive() const;

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
                return action.call(wt => true);
            }
            else if (context == ActionContext.window)
            {
                return action.call(wt => wt && wt.window is this);
            }
            else // widget or widget tree
            {
                Widget focus = focusedWidget;
                if (action.call(wt => wt is focus)) // try focused first
                {
                    return true;
                }
                else if (context == ActionContext.widgetTree)
                {
                   return action.call(wt => wt && wt.isChild(focus));
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
        Popup modal = modalPopup();
        if (event.action == KeyAction.keyDown || event.action == KeyAction.keyUp)
        {
            _keyboardModifiers = event.flags;
            if (event.keyCode == KeyCode.alt || event.keyCode == KeyCode.lalt || event.keyCode == KeyCode.ralt)
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
        else
        {
            if (dispatchKeyEvent(_mainWidget, event))
                return res;
            return _mainWidget.onKeyEvent(event) || res;
        }
    }

    /// Dispatch key event to widgets which have wantsKeyTracking == true
    protected bool dispatchKeyEvent(Widget root, KeyEvent event)
    {
        // route key events to visible widgets only
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

    private int _lastMouseX;
    private int _lastMouseY;
    /// Dispatch mouse event to window content widgets
    bool dispatchMouseEvent(MouseEvent event)
    {
        if (hasModalWindowsAbove || !_firstDrawCalled)
            return false;

        // check tooltip
        if (event.action == MouseAction.move)
        {
            import std.math : abs;

            if (_tooltip.popup && _tooltip.popup.isPointInside(event.x, event.y))
            {
                // freely move mouse inside of tooltip
                return true;
            }
            int threshold = 3;
            if (abs(_lastMouseX - event.x) > threshold || abs(_lastMouseY - event.y) > threshold)
                hideTooltip();
            _lastMouseX = event.x;
            _lastMouseY = event.y;
        }
        if (event.action == MouseAction.buttonDown || event.action == MouseAction.wheel)
        {
            if (_tooltip.popup)
            {
                hideTooltip();
            }
        }

        Popup modal = modalPopup();

        // check if _mouseCaptureWidget still exist
        if (_mouseCaptureWidget.isNull)
        {
            clearMouseCapture();
        }

        debug (mouse)
            Log.fd("dispatchMouseEvent %s (%s, %s)", event.action, event.x, event.y);

        bool res;
        ushort currentButtons = event.flags & (MouseFlag.lbutton | MouseFlag.rbutton | MouseFlag.mbutton);
        if (_mouseCaptureWidget)
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
                if (insideOneOfPopups)
                {
                    if (dispatchMouseEvent(WeakRef!Widget(p), event, cursorIsSet))
                        return true;
                }
                else
                {
                    if (p.onMouseEventOutside(event))
                        return true;
                }
            }
            if (!modal)
                res = dispatchMouseEvent(weakRef(_mainWidget), event, cursorIsSet);
            else
                res = dispatchMouseEvent(WeakRef!Widget(modal), event, cursorIsSet);
        }
        return res || processed || _mainWidget.needDraw;
    }

    protected bool dispatchMouseEvent(WeakRef!Widget root, MouseEvent event, ref bool cursorIsSet)
    {
        // route mouse events to visible widgets only
        if (root.visibility != Visibility.visible)
            return false;
        if (!root.isPointInside(event.x, event.y))
            return false;
        // offer event to children first
        foreach (i; 0 .. root.childCount)
        {
            Widget child = root.child(i);
            if (dispatchMouseEvent(weakRef(child), event, cursorIsSet))
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
        // if not processed by children, offer event to the root
        if (sendAndCheckOverride(root, event))
        {
            debug (mouse)
                Log.d("MouseEvent is processed");
            if (event.action == MouseAction.buttonDown && _mouseCaptureWidget.isNull && !event.doNotTrackButtonDown)
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
    private WeakRef!Widget[] _mouseTrackingWidgets;
    private void addTracking(WeakRef!Widget w)
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
            if (w.isNull)
                continue;
            if (event.action == MouseAction.leave || !w.isPointInside(event.x, event.y))
            {
                // send Leave message
                auto leaveEvent = new MouseEvent(event);
                leaveEvent.changeAction(MouseAction.leave);
                res = w.onMouseEvent(leaveEvent) || res;
                debug (mouse)
                    Log.d("removeTracking of ", w.id);
                w.nullify();
            }
        }
        _mouseTrackingWidgets = _mouseTrackingWidgets.efilter!(a => !a.isNull);
        debug (mouse)
            Log.d("removeTracking, items after: ", _mouseTrackingWidgets.length);
        return res;
    }

    /// Widget which tracks all events after processed ButtonDown
    private WeakRef!Widget _mouseCaptureWidget;
    private ushort _mouseCaptureButtons;
    private bool _mouseCaptureFocusedOut;
    /// Does current capture widget want to receive move events even if pointer left it
    private bool _mouseCaptureFocusedOutTrackMovements;

    protected void setCaptureWidget(WeakRef!Widget w, MouseEvent event)
    {
        _mouseCaptureWidget = w;
        _mouseCaptureButtons = event.flags & (MouseFlag.lbutton | MouseFlag.rbutton | MouseFlag.mbutton);
    }

    protected void clearMouseCapture()
    {
        _mouseCaptureWidget.nullify();
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

    protected bool sendAndCheckOverride(WeakRef!Widget widget, MouseEvent event)
    {
        if (widget.isNull)
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
        return !_mouseCaptureWidget.isNull;
    }

    /// Handle theme change: e.g. reload some themed resources
    void dispatchThemeChanged()
    {
        _mainWidget.onThemeChanged();
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
        auto event = new RunnableEvent(CUSTOM_RUNNABLE, WeakRef!Widget(null), runnable);
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

    //===============================================================

    /// Set cursor type for window
    protected void setCursorType(CursorType cursorType)
    {
        // override to support different mouse cursors
    }

    /// Check content widgets for necessary redraw and/or layout
    bool checkUpdateNeeded(out bool needDraw, out bool needLayout, out bool animationActive)
    {
        animationActive = animations.length > 0;

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

    private bool _animationActive;

    @property bool isAnimationActive() { return _animationActive; }

    /// Request update for window (unless force is true, update will be performed only if layout, redraw or animation is required).
    void update(bool force = false)
    {
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

    //===============================================================
    // Timers

    private TimerQueue _timerQueue;
    private TimerThread timerThread;

    /**
    Schedule timer for timestamp in milliseconds - post timer event when finished.

    Platform timers are implemented using timer thread by default, but it is possible
    to use platform timers - override this method, calculate an interval and set the timer there.
    When timer expires and platform receives its event, call `window.onTimer()`.
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

    /// Set timer with a delegate, that will be called after interval expiration; returns timer id
    /// Node: You must cancel the timer if you destroy object this handler belongs to.
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

    /// Cancel previously scheduled widget timer (for timerID pass value returned from setTimer)
    void cancelTimer(ulong timerID)
    {
        _timerQueue.cancelTimer(timerID);
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
    @property size_t count()
    {
        return list.length;
    }

    /// The first added existing window, null if no windows
    @property W first()
    {
        return list.length > 0 ? list[0] : null;
    }
    /// The last added existing window, null if no windows
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

/**
    Platform abstraction layer.

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

    private
    {
        string _uiLanguage;
        string _themeName;
        DialogDisplayMode _uiDialogDisplayMode =
            DialogDisplayMode.messageBoxInPopup | DialogDisplayMode.inputBoxInPopup;

        /// Default icon for new created windows
        string _defaultWindowIcon = "beamui-logo";
        IconProviderBase _iconProvider;
    }

    ~this()
    {
        eliminate(_iconProvider);
    }

    /**
    Starts application message loop.

    When returned from this method, application is shutting down.
     */
    abstract int enterMessageLoop();

    //===============================================================
    // Window routines

    /**
    Create a window.
    Params:
        title  = window title text
        parent = parent Window, or null if no parent
        flags  = WindowFlag bit set, combination of Resizable, Modal, Fullscreen
        width  = window width
        height = window height

    Note: Window w/o `resizable` nor `fullscreen` will be created with a size based on measurement of its content widget.
    */
    abstract Window createWindow(dstring title, Window parent,
            WindowFlag flags = WindowFlag.resizable, uint width = 0, uint height = 0);
    /**
    Close a window.

    Closes window earlier created with createWindow()
     */
    abstract void closeWindow(Window w);

    /**
    Returns true if there is some modal window opened above this window.

    This window should not process mouse/key input and should not allow closing.
    */
    bool hasModalWindowsAbove(Window w)
    {
        // may override in platform specific class
        return w ? w.hasVisibleModalChild : false;
    }

    /// Call request layout for all windows
    abstract void requestLayout();

    //===============================================================

    /// Check has clipboard text
    abstract bool hasClipboardText(bool mouseBuffer = false);
    /// Retrieve text from clipboard (when mouseBuffer == true, use mouse selection clipboard - under linux)
    abstract dstring getClipboardText(bool mouseBuffer = false);
    /// Set text to clipboard (when mouseBuffer == true, use mouse selection clipboard - under linux)
    abstract void setClipboardText(dstring text, bool mouseBuffer = false);

    @property
    {
        /// Returns currently selected UI language code
        string uiLanguage() { return _uiLanguage; }
        /// Set UI language (e.g. "en", "fr", "ru") - will relayout content of all windows if language has been changed
        void uiLanguage(string langCode)
        {
            if (_uiLanguage == langCode)
                return;
            _uiLanguage = langCode;

            Log.v("Loading language file");
            loadTranslator(langCode);

            Log.v("Calling onThemeChanged");
            onThemeChanged();
            requestLayout();
        }

        /// Get name of currently active theme
        string uiTheme() { return _themeName; }
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

        /// How dialogs should be displayed - as popup or window
        DialogDisplayMode uiDialogDisplayMode() { return _uiDialogDisplayMode; }
        /// ditto
        void uiDialogDisplayMode(DialogDisplayMode value)
        {
            _uiDialogDisplayMode = value;
        }

        /// Returns list of resource directories
        string[] resourceDirs()
        {
            return resourceList.resourceDirs;
        }
        /// ditto
        void resourceDirs(string[] dirs)
        {
            // TODO: this function is reserved
            resourceList.resourceDirs = dirs;
        }

        /// Default icon for newly created windows
        string defaultWindowIcon() { return _defaultWindowIcon; }
        /// ditto
        void defaultWindowIcon(string newIcon)
        {
            _defaultWindowIcon = newIcon;
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
        /// ditto
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
        static if (BACKEND_GUI)
        {
            imageCache.clear();
        }
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

static if (BACKEND_GUI)
{
    version (Windows)
    {
        package (beamui) void setAppDPIAwareOnWindows()
        {
            import core.sys.windows.windows;
            // call SetProcessDPIAware to support HI DPI - fix by Kapps
            auto ulib = LoadLibraryA("user32.dll");
            alias SetProcessDPIAwareFunc = int function();
            auto setDpiFunc = cast(SetProcessDPIAwareFunc)GetProcAddress(ulib, "SetProcessDPIAware");
            if (setDpiFunc) // should never fail, but just in case...
                setDpiFunc();
        }
    }
}

// to remove import
extern (C) int initializeGUI();
extern (C) void deinitializeGUI();

/// Put "mixin APP_ENTRY_POINT;" to main module of your beamui based app
mixin template APP_ENTRY_POINT()
{
    version (unittest)
    {
        // no main in unit tests
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
                int result = initializeGUI();
                scope (exit)
                {
                    deinitializeGUI();
                    Log.d("Exiting main");
                }
                if (result == 0)
                {
                    try
                    {
                        Log.i("Entering UIAppMain: ", args);
                        result = UIAppMain(args);
                    }
                    catch (Exception e)
                    {
                        Log.e("Abnormal UIAppMain termination");
                        Log.e("UIAppMain exception: ", e);
                        result = -1;
                    }
                }
                return result;
            }
        }
    }
}
