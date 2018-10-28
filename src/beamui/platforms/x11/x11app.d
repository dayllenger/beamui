/**


Copyright: Vadim Lopatin 2014-2017, Roman Chistokhodov 2017, Andrzej Kilijański 2017-2018, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, Roman Chistokhodov
*/
module beamui.platforms.x11.x11app;

import beamui.core.config;

static if (BACKEND_X11):
import core.stdc.config : c_ulong, c_long;
import core.stdc.string;
import std.stdio;
import std.string;
import std.utf;
import x11.X;
import x11.Xatom;
import x11.Xlib;
import x11.Xtos;
import x11.Xutil;
import beamui.core.events;
import beamui.core.files;
import beamui.core.functions : toUTF8;
import beamui.core.logger;
import beamui.graphics.drawbuf;
import beamui.widgets.widget;
import beamui.platforms.common.platform;
static if (USE_OPENGL)
{
    import derelict.opengl3.gl;
    import derelict.opengl3.glx;
    import derelict.opengl3.glxext;
    import beamui.graphics.glsupport;

    private __gshared derelict.util.xtypes.XVisualInfo* x11visual;
    private __gshared Colormap x11cmap;
}

alias XWindow = x11.Xlib.Window;
alias DWindow = beamui.platforms.common.platform.Window;

private struct MwmHints
{
    int flags;
    int functions;
    int decorations;
    int input_mode;
    int status;
}

private enum
{
    MWM_HINTS_FUNCTIONS = (1L << 0),
    MWM_HINTS_DECORATIONS = (1L << 1),

    MWM_FUNC_ALL = (1L << 0),
    MWM_FUNC_RESIZE = (1L << 1),
    MWM_FUNC_MOVE = (1L << 2),
    MWM_FUNC_MINIMIZE = (1L << 3),
    MWM_FUNC_MAXIMIZE = (1L << 4),
    MWM_FUNC_CLOSE = (1L << 5)
}

private __gshared
{
    Display* x11display;
    Display* x11display2;
    int x11screen;
    XIM xim;

    Cursor[CursorType.hand + 1] x11cursors;

    Atom atom_UTF8_STRING;
    Atom atom_CLIPBOARD;
    Atom atom_TARGETS;

    Atom atom_WM_PROTOCOLS;
    Atom atom_WM_DELETE_WINDOW;

    Atom atom_NET_WM_ICON;
    Atom atom_NET_WM_NAME;
    Atom atom_NET_WM_ICON_NAME;

    Atom atom_NET_WM_STATE;
    Atom atom_NET_WM_STATE_MODAL;
    Atom atom_NET_WM_STATE_MAXIMIZED_VERT;
    Atom atom_NET_WM_STATE_MAXIMIZED_HORZ;
    Atom atom_NET_WM_STATE_HIDDEN;
    Atom atom_NET_WM_STATE_FULLSCREEN;

    Atom atom_MOTIF_WM_HINTS;

    Atom atom_beamui_TIMER_EVENT;
    Atom atom_beamui_TASK_EVENT;
    Atom atom_beamui_CLOSE_WINDOW_EVENT;
    Atom atom_beamui_CLIPBOARD_BUFFER;
    Atom atom_beamui_REDRAW_EVENT;
}

void setupX11Atoms()
{
    assert(x11display !is null, "X Connection must be established before getting atoms");
    //TODO: not sure which atoms should be taken with or without onlyIfExists flag
    atom_UTF8_STRING = XInternAtom(x11display, "UTF8_STRING", True);
    atom_CLIPBOARD = XInternAtom(x11display, "CLIPBOARD", True);
    atom_TARGETS = XInternAtom(x11display, "TARGETS", True);
    atom_WM_PROTOCOLS = XInternAtom(x11display, "WM_PROTOCOLS", False);
    atom_WM_DELETE_WINDOW = XInternAtom(x11display, "WM_DELETE_WINDOW", False);
    atom_NET_WM_ICON = XInternAtom(x11display, "_NET_WM_ICON", True);
    atom_NET_WM_NAME = XInternAtom(x11display, "_NET_WM_NAME", True);
    atom_NET_WM_ICON_NAME = XInternAtom(x11display, "_NET_WM_ICON_NAME", True);
    atom_NET_WM_STATE = XInternAtom(x11display, "_NET_WM_STATE", True);
    atom_NET_WM_STATE_MODAL = XInternAtom(x11display, "_NET_WM_STATE_MODAL", True);
    atom_NET_WM_STATE_MAXIMIZED_VERT = XInternAtom(x11display, "_NET_WM_STATE_MAXIMIZED_VERT", True);
    atom_NET_WM_STATE_MAXIMIZED_HORZ = XInternAtom(x11display, "_NET_WM_STATE_MAXIMIZED_HORZ", True);
    atom_NET_WM_STATE_HIDDEN = XInternAtom(x11display, "_NET_WM_STATE_HIDDEN", True);
    atom_NET_WM_STATE_FULLSCREEN = XInternAtom(x11display, "_NET_WM_STATE_FULLSCREEN", True);
    atom_MOTIF_WM_HINTS = XInternAtom(x11display, "_MOTIF_WM_HINTS", True);

    atom_beamui_TIMER_EVENT = XInternAtom(x11display, "beamui_TIMER_EVENT", False);
    atom_beamui_TASK_EVENT = XInternAtom(x11display, "beamui_TASK_EVENT", False);
    atom_beamui_CLOSE_WINDOW_EVENT = XInternAtom(x11display, "beamui_CLOSE_WINDOW_EVENT", False);
    atom_beamui_CLIPBOARD_BUFFER = XInternAtom(x11display, "beamui_CLIPBOARD_BUFFER", False);
    atom_beamui_REDRAW_EVENT = XInternAtom(x11display, "beamui_REDRAW_EVENT", False);
}

// Cursor font constants
enum
{
    XC_X_cursor = 0,
    XC_arrow = 2,
    XC_based_arrow_down = 4,
    XC_based_arrow_up = 6,
    XC_boat = 8,
    XC_bogosity = 10,
    XC_bottom_left_corner = 12,
    XC_bottom_right_corner = 14,
    XC_bottom_side = 16,
    XC_bottom_tee = 18,
    XC_box_spiral = 20,
    XC_center_ptr = 22,
    XC_circle = 24,
    XC_clock = 26,
    XC_coffee_mug = 28,
    XC_cross = 30,
    XC_cross_reverse = 32,
    XC_crosshair = 34,
    XC_diamond_cross = 36,
    XC_dot = 38,
    XC_dotbox = 40,
    XC_double_arrow = 42,
    XC_draft_large = 44,
    XC_draft_small = 46,
    XC_draped_box = 48,
    XC_exchange = 50,
    XC_fleur = 52,
    XC_gobbler = 54,
    XC_gumby = 56,
    XC_hand1 = 58,
    XC_hand2 = 60,
    XC_heart = 62,
    XC_icon = 64,
    XC_iron_cross = 66,
    XC_left_ptr = 68,
    XC_left_side = 70,
    XC_left_tee = 72,
    XC_leftbutton = 74,
    XC_ll_angle = 76,
    XC_lr_angle = 78,
    XC_man = 80,
    XC_middlebutton = 82,
    XC_mouse = 84,
    XC_pencil = 86,
    XC_pirate = 88,
    XC_plus = 90,
    XC_question_arrow = 92,
    XC_right_ptr = 94,
    XC_right_side = 96,
    XC_right_tee = 98,
    XC_rightbutton = 100,
    XC_rtl_logo = 102,
    XC_sailboat = 104,
    XC_sb_down_arrow = 106,
    XC_sb_h_double_arrow = 108,
    XC_sb_left_arrow = 110,
    XC_sb_right_arrow = 112,
    XC_sb_up_arrow = 114,
    XC_sb_v_double_arrow = 116,
    XC_shuttle = 118,
    XC_sizing = 120,
    XC_spider = 122,
    XC_spraycan = 124,
    XC_star = 126,
    XC_target = 128,
    XC_tcross = 130,
    XC_top_left_arrow = 132,
    XC_top_left_corner = 134,
    XC_top_right_corner = 136,
    XC_top_side = 138,
    XC_top_tee = 140,
    XC_trek = 142,
    XC_ul_angle = 144,
    XC_umbrella = 146,
    XC_ur_angle = 148,
    XC_watch = 150,
    XC_xterm = 152,
}

private GC createGC(Display* display, XWindow win)
{
    GC gc; /* handle of newly created GC.  */
    uint valuemask = GCFunction | GCBackground | GCForeground | GCPlaneMask; /* which values in 'values' to  */
    /* check when creating the GC.  */
    XGCValues values; /* initial values for the GC.   */
    values.plane_mask = AllPlanes;
    int screen_num = DefaultScreen(display);
    values.function_ = GXcopy;
    values.background = WhitePixel(display, screen_num);
    values.foreground = BlackPixel(display, screen_num);

    gc = XCreateGC(display, win, valuemask, &values);
    if (!gc)
    {
        Log.e("X11: Cannot create GC");
        return null;
    }

    uint line_width = 2; /* line width for the GC.       */
    int line_style = LineSolid; /* style for lines drawing and  */
    int cap_style = CapButt; /* style of the line's edje and */
    int join_style = JoinBevel; /*  joined lines.        */

    /* define the style of lines that will be drawn using this GC. */
    XSetLineAttributes(display, gc, line_width, line_style, cap_style, join_style);

    /* define the fill style for the GC. to be 'solid filling'. */
    XSetFillStyle(display, gc, FillSolid);

    return gc;
}

final class X11Window : DWindow
{
    private
    {
        X11Platform _platform;

        XWindow _win;
        GC _gc;
        __gshared XIC xic;
        static if (USE_OPENGL)
            GLXContext _glc;

        dstring _title;
        DrawBuf _drawbuf;

        int _cachedWidth, _cachedHeight;
    }

    this(X11Platform platform, dstring caption, DWindow parent, WindowFlag flags, uint width = 0, uint height = 0)
    {
        _platform = platform;
        _title = caption;
        _windowState = WindowState.hidden;

        _children.reserve(10);
        _parent = parent;
        if (_parent)
            _parent.addModalChild(this);

        _cachedWidth = _w = width > 0 ? width : 500;
        _cachedHeight = _h = height > 0 ? height : 300;
        _flags = flags;

        create();

        if (platform.defaultWindowIcon.length != 0)
            this.icon = imageCache.get(platform.defaultWindowIcon);
    }

    ~this()
    {
        debug Log.d("Destroying X11 window");
        static if (USE_OPENGL)
        {
            if (_glc)
            {
                glXDestroyContext(x11display, _glc);
                _glc = null;
            }
        }
        eliminate(_drawbuf);
        if (_gc)
        {
            XFreeGC(x11display, _gc);
            _gc = null;
        }
        if (_win)
        {
            XDestroyWindow(x11display, _win);
            _win = 0;
        }
    }

    private void create()
    {
        Log.d("Creating X11 window of size ", _w, "x", _h);

        XSetWindowAttributes attrs;
        // attribute mask - only events and colormap for glx
        uint mask = CWEventMask;
        // set event mask which determines events received by the client
        attrs.event_mask = KeyPressMask | KeyReleaseMask | ButtonPressMask | ButtonReleaseMask |
            EnterWindowMask | LeaveWindowMask | PointerMotionMask | ButtonMotionMask | ExposureMask |
            VisibilityChangeMask | FocusChangeMask | KeymapStateMask | StructureNotifyMask | PropertyChangeMask;
        // TODO: think about `override_redirect` flag for popup windows
        // https://tronche.com/gui/x/xlib/window/attributes/override-redirect.html

        Visual* visual = DefaultVisual(x11display, x11screen);
        int depth = DefaultDepth(x11display, x11screen);
        static if (USE_OPENGL)
        {
            if (openglEnabled)
            {
                mask |= CWColormap;
                attrs.colormap = x11cmap;
                visual = cast(Visual*)x11visual.visual;
                depth = x11visual.depth;
            }
        }

        _win = XCreateWindow(x11display, DefaultRootWindow(x11display), 0, 0, _w, _h, 0,
                depth, InputOutput, visual, mask, &attrs);
        if (!_win)
        {
            Log.e("X11: Failed to create window"); // TODO: print error
            return;
        }

        this.title = _title;

        XSetWMProtocols(x11display, _win, &atom_WM_DELETE_WINDOW, 1);

        auto classHint = XAllocClassHint();
        if (classHint)
        {
            classHint.res_name = _platform._classname;
            classHint.res_class = _platform._classname;
            XSetClassHint(x11display, _win, classHint);
            XFree(classHint);
        }

        if (!(flags & WindowFlag.resizable))
        {
            XSizeHints sizeHints;
            sizeHints.min_width = width;
            sizeHints.min_height = height;
            sizeHints.max_width = width;
            sizeHints.max_height = height;
            sizeHints.flags = PMaxSize | PMinSize;
            XSetWMNormalHints(x11display, _win, &sizeHints);
        }
        if (flags & WindowFlag.fullscreen)
        {
            if (atom_NET_WM_STATE_FULLSCREEN != None)
            {
                changeWindowState(_NET_WM_STATE_ADD, atom_NET_WM_STATE_FULLSCREEN);
            }
            else
                Log.w("Missing _NET_WM_STATE_FULLSCREEN atom");
        }
        if (flags & WindowFlag.borderless)
        {
            if (atom_MOTIF_WM_HINTS != None)
            {
                MwmHints hints;
                hints.flags = MWM_HINTS_DECORATIONS;
                XChangeProperty(x11display, _win, atom_MOTIF_WM_HINTS, atom_MOTIF_WM_HINTS, 32,
                        PropModeReplace, cast(ubyte*)&hints, hints.sizeof / 4);
            }
        }
        if (flags & WindowFlag.modal)
        {
            if (auto p = cast(X11Window)parentWindow)
            {
                XSetTransientForHint(x11display, _win, p._win);
            }
            else
            {
                Log.w("Top-level modal window");
            }
            if (atom_NET_WM_STATE_MODAL != None)
            {
                changeWindowState(_NET_WM_STATE_ADD, atom_NET_WM_STATE_MODAL);
            }
            else
            {
                Log.w("Missing _NET_WM_STATE_MODAL atom");
            }
        }

        // create a Graphics Context
        _gc = createGC(x11display, _win);

        static if (USE_OPENGL)
        {
            if (openglEnabled)
            {
                // find top level GL context to share objects
                X11Window w = this;
                while (w.parentWindow !is null)
                {
                    w = cast(X11Window)w.parentWindow;
                }
                GLXContext topLevelContext = w._glc;
                // create context
                _glc = glXCreateContext(x11display, x11visual, topLevelContext, GL_TRUE);
                if (!_glc)
                    disableOpenGL();
                else
                {
                    bindContext();
                    if (!initGLSupport(_platform.GLVersionMajor < 3))
                        disableOpenGL();
                    if (!openglEnabled && _glc)
                    {
                        glXDestroyContext(x11display, _glc);
                        _glc = null;
                    }
                    else
                    {
                        // TODO: find the extension, deactivate vsync
                        //glXSwapIntervalEXT(x11display, cast(uint)_win, 0);
                    }
                }
            }
        }
        Log.i(openglEnabled ? "OpenGL is enabled" : "OpenGL is disabled");

        handleWindowStateChange(WindowState.unspecified, Box(0, 0, _w, _h));
    }

    override protected void handleWindowStateChange(WindowState newState, Box newWindowRect = Box.none)
    {
        super.handleWindowStateChange(newState, newWindowRect);
    }

    private void changeWindowState(int action, Atom firstProperty, Atom secondProperty = None) nothrow
    {
        XEvent ev;
        ev.xclient = XClientMessageEvent.init;
        ev.xclient.type = ClientMessage;
        ev.xclient.window = _win;
        ev.xclient.message_type = atom_NET_WM_STATE;
        ev.xclient.format = 32;
        ev.xclient.data.l[0] = action;
        ev.xclient.data.l[1] = firstProperty;
        if (secondProperty != None)
            ev.xclient.data.l[2] = secondProperty;
        ev.xclient.data.l[3] = 0;
        XSendEvent(x11display, RootWindow(x11display, x11screen), false,
                SubstructureNotifyMask | SubstructureRedirectMask, &ev);
    }

    private enum
    {
        _NET_WM_STATE_REMOVE = 0,
        _NET_WM_STATE_ADD,
        _NET_WM_STATE_TOGGLE
    }

    override bool setWindowState(WindowState newState, bool activate = false, Box newWindowRect = Box.none)
    {
        if (_win == None)
            return false;

        bool result;
        switch (newState)
        {
        case WindowState.maximized:
            if (atom_NET_WM_STATE != None &&
                    atom_NET_WM_STATE_MAXIMIZED_HORZ != None && atom_NET_WM_STATE_MAXIMIZED_VERT != None)
            {
                changeWindowState(_NET_WM_STATE_ADD, atom_NET_WM_STATE_MAXIMIZED_HORZ,
                        atom_NET_WM_STATE_MAXIMIZED_VERT);
                result = true;
            }
            break;
        case WindowState.minimized:
            if (XIconifyWindow(x11display, _win, x11screen))
                result = true;
            break;
        case WindowState.hidden:
            XUnmapWindow(x11display, _win);
            result = true;
            break;
        case WindowState.normal:
            if (atom_NET_WM_STATE != None && atom_NET_WM_STATE_MAXIMIZED_HORZ != None &&
                    atom_NET_WM_STATE_MAXIMIZED_VERT != None && atom_NET_WM_STATE_HIDDEN != None)
            {
                changeWindowState(_NET_WM_STATE_REMOVE, atom_NET_WM_STATE_MAXIMIZED_HORZ,
                        atom_NET_WM_STATE_MAXIMIZED_VERT);
                changeWindowState(_NET_WM_STATE_REMOVE, atom_NET_WM_STATE_HIDDEN);
                changeWindowState(_NET_WM_STATE_REMOVE, atom_NET_WM_STATE_FULLSCREEN);
                result = true;
            }
            break;
        case WindowState.fullscreen:
            if (atom_NET_WM_STATE != None && atom_NET_WM_STATE_FULLSCREEN != None)
            {
                changeWindowState(_NET_WM_STATE_ADD, atom_NET_WM_STATE_FULLSCREEN);
                result = true;
            }
            break;
        default:
            break;
        }

        // change size and/or position
        bool rectChanged;
        if (newWindowRect != Box.none && (newState == WindowState.normal ||
                newState == WindowState.unspecified))
        {
            // change position
            if (newWindowRect.x != int.min && newWindowRect.y != int.min)
            {
                XMoveWindow(x11display, _win, newWindowRect.x, newWindowRect.y);
                rectChanged = true;
                result = true;
            }

            // change size
            if (newWindowRect.w != int.min && newWindowRect.h != int.min)
            {
                if (!(flags & WindowFlag.resizable))
                {
                    XSizeHints sizeHints;
                    sizeHints.min_width = newWindowRect.width;
                    sizeHints.min_height = newWindowRect.height;
                    sizeHints.max_width = newWindowRect.width;
                    sizeHints.max_height = newWindowRect.height;
                    sizeHints.flags = PMaxSize | PMinSize;
                    XSetWMNormalHints(x11display, _win, &sizeHints);
                }
                XResizeWindow(x11display, _win, newWindowRect.w, newWindowRect.h);
                rectChanged = true;
                result = true;
            }
        }

        if (activate)
        {
            XMapRaised(x11display, _win);
            result = true;
        }
        XFlush(x11display);

        //needed here to make _windowRect and _windowState valid
        //example: change size by resizeWindow() and make some calculations using windowRect
        if (rectChanged)
        {
            handleWindowStateChange(newState, Box(
                newWindowRect.x == int.min ? _windowRect.x : newWindowRect.x,
                newWindowRect.y == int.min ? _windowRect.y : newWindowRect.y,
                newWindowRect.w == int.min ? _windowRect.w : newWindowRect.w,
                newWindowRect.h == int.min ? _windowRect.h : newWindowRect.h));
        }
        else
            handleWindowStateChange(newState, Box.none);

        return result;
    }

    private bool _isActive;
    override @property bool isActive() const { return _isActive; }

    override protected void handleWindowActivityChange(bool isWindowActive)
    {
        _isActive = isWindowActive;
        super.handleWindowActivityChange(isWindowActive);
    }

    //===============================================================

    override @property dstring title() const { return _title; }

    override @property void title(dstring caption)
    {
        _title = caption;
        auto captionc = caption.toUTF8;
        auto captionz = cast(ubyte*)captionc.toStringz;
        XTextProperty nameProperty;
        nameProperty.value = captionz;
        nameProperty.encoding = atom_UTF8_STRING;
        nameProperty.format = 8;
        nameProperty.nitems = cast(uint)captionc.length;
        XStoreName(x11display, _win, cast(char*)captionz); // this may not support unicode
        XSetWMName(x11display, _win, &nameProperty);
        XChangeProperty(x11display, _win, atom_NET_WM_NAME, atom_UTF8_STRING, 8, PropModeReplace,
                captionz, cast(int)captionc.length);
        //XFlush(x11display); //TODO: not sure if XFlush is required
    }

    override @property void icon(DrawBufRef buf)
    {
        ColorDrawBuf ic = cast(ColorDrawBuf)buf.get;
        if (!ic)
        {
            Log.e("Trying to set null icon for window");
            return;
        }
        immutable int iconw = 32;
        immutable int iconh = 32;
        auto iconDraw = new ColorDrawBuf(iconw, iconh);
        scope (exit)
            destroy(iconDraw);
        iconDraw.fill(Color(0xFF000000));
        iconDraw.drawRescaled(Rect(0, 0, iconw, iconh), ic, Rect(0, 0, ic.width, ic.height));
        iconDraw.invertAndPreMultiplyAlpha();
        c_long[] propData = new c_long[2 + iconw * iconh];
        propData[0] = iconw;
        propData[1] = iconh;
        auto iconData = iconDraw.scanLine(0);
        foreach (i; 0 .. iconw * iconh)
        {
            propData[i + 2] = iconData[i];
        }
        XChangeProperty(x11display, _win, atom_NET_WM_ICON, XA_CARDINAL, 32, PropModeReplace,
                cast(ubyte*)propData.ptr, cast(int)propData.length);
    }

    override void show()
    {
        Log.d("X11Window.show - ", _title);

        if (!mainWidget)
        {
            Log.e("Window is shown without main widget");
            mainWidget = new Widget;
        }
        adjustSize();
        adjustPosition();

        mainWidget.setFocus();

        XMapRaised(x11display, _win);
        XFlush(x11display);
    }

    private uint _lastRedrawEventCode;

    override void invalidate()
    {
        XEvent ev;
        ev.xclient = XClientMessageEvent.init;
        ev.xclient.type = ClientMessage;
        ev.xclient.message_type = atom_beamui_REDRAW_EVENT;
        ev.xclient.window = _win;
        ev.xclient.display = x11display;
        ev.xclient.format = 32;
        ev.xclient.data.l[0] = ++_lastRedrawEventCode;
        XSendEvent(x11display, _win, false, StructureNotifyMask, &ev);
        XFlush(x11display);
    }

    override void close()
    {
        Log.d("X11Window.close()");
        _platform.closeWindow(this);
    }

    //===============================================================

    private CursorType _lastCursorType = CursorType.none;

    override protected void setCursorType(CursorType cursorType)
    {
        if (_lastCursorType != cursorType)
        {
            debug (x11)
                Log.d("changing cursor to ", cursorType);
            _lastCursorType = cursorType;
            XDefineCursor(x11display, _win, x11cursors[cursorType]);
            XFlush(x11display);
        }
    }

    private void redraw()
    {
        _lastRedrawEventCode = 0;
        //Use values cached by ConfigureNotify to avoid XGetWindowAttributes call.
        //XWindowAttributes attrs;
        //XGetWindowAttributes(x11display, _win, &attrs);
        //Log.d(format("XGetWindowAttributes reported size %d, %d", attrs.width, attrs.height));
        immutable width = _cachedWidth;
        immutable height = _cachedHeight;
        if (width > 0 && height > 0)
            onResize(width, height);
        debug (x11)
            Log.d(format("redraw(%d, %d)", width, height));
        if (openglEnabled)
        {
            static if (USE_OPENGL)
                drawUsingOpenGL(_drawbuf);
        }
        else
            drawUsingBitmap();
    }

    private void drawUsingBitmap()
    {
        if (_w > 0 && _h > 0)
        {
            // prepare drawbuf
            if (!_drawbuf)
                _drawbuf = new ColorDrawBuf(_w, _h);
            else
                _drawbuf.resize(_w, _h);
            _drawbuf.resetClipping();
            // draw widgets into buffer
            _drawbuf.fill(backgroundColor);
            onDraw(_drawbuf);
            // draw buffer on X11 window
            XImage img;
            img.width = _drawbuf.width;
            img.height = _drawbuf.height;
            img.xoffset = 0;
            img.format = ZPixmap;
            img.data = cast(char*)(cast(ColorDrawBuf)_drawbuf).scanLine(0);
            img.bitmap_unit = 32;
            img.bitmap_pad = 32;
            img.bitmap_bit_order = LSBFirst;
            img.depth = 24;
            img.chars_per_line = _drawbuf.width * 4;
            img.bits_per_pixel = 32;
            img.red_mask = 0xFF0000;
            img.green_mask = 0x00FF00;
            img.blue_mask = 0x0000FF;
            XInitImage(&img);
            //XSetClipOrigin(x11display, _gc, 0, 0);
            XPutImage(x11display, _win, _gc, //DefaultGC(x11display, DefaultScreen(x11display)),
                    &img, 0, 0, 0, 0, _drawbuf.width, _drawbuf.height);
            //XFlush(x11display); // no need to XFlush since it will be called in event loop
        }
    }

    static if (USE_OPENGL)
    {
        override void bindContext()
        {
            glXMakeCurrent(x11display, cast(uint)_win, _glc);
        }

        override void swapBuffers()
        {
            glXSwapBuffers(x11display, cast(uint)_win);
        }
    }

    //===============================================================

    private ButtonDetails _lbutton;
    private ButtonDetails _mbutton;
    private ButtonDetails _rbutton;

    // x11 gives flags from time prior event so if left button is pressed there is not Button1Mask
    private ushort convertMouseFlags(uint x11Flags, MouseButton btn, bool pressed)
    {
        ushort res = 0;
        if (btn == MouseButton.left)
        {
            if (pressed)
                res |= MouseFlag.lbutton;
            else
                res &= ~MouseFlag.lbutton;
        }
        else if (x11Flags & Button1Mask)
            res |= MouseFlag.lbutton;

        if (btn == MouseButton.middle)
        {
            if (pressed)
                res |= MouseFlag.mbutton;
            else
                res &= ~MouseFlag.mbutton;
        }
        else if (x11Flags & Button2Mask)
            res |= MouseFlag.mbutton;

        if (btn == MouseButton.right)
        {
            if (pressed)
                res |= MouseFlag.rbutton;
            else
                res &= ~MouseFlag.rbutton;
        }
        else if (x11Flags & Button3Mask)
            res |= MouseFlag.rbutton;

        return res;
    }

    private MouseButton convertMouseButton(uint x11Button)
    {
        if (x11Button == Button1)
            return MouseButton.left;
        if (x11Button == Button2)
            return MouseButton.middle;
        if (x11Button == Button3)
            return MouseButton.right;
        return MouseButton.none;
    }

    private ushort lastFlags;
    private short lastx, lasty;
    private uint _keyFlags;

    private void processMouseEvent(MouseAction action, uint x11Button, uint x11Flags, int x, int y)
    {
        MouseEvent event;
        if (action == MouseAction.wheel)
        {
            // handle wheel
            short wheelDelta = cast(short)y;
            if (_keyFlags & KeyFlag.shift)
                lastFlags |= MouseFlag.shift;
            else
                lastFlags &= ~MouseFlag.shift;
            if (_keyFlags & KeyFlag.control)
                lastFlags |= MouseFlag.control;
            else
                lastFlags &= ~MouseFlag.control;
            if (_keyFlags & KeyFlag.alt)
                lastFlags |= MouseFlag.alt;
            else
                lastFlags &= ~MouseFlag.alt;
            if (wheelDelta)
                event = new MouseEvent(action, MouseButton.none, lastFlags, lastx, lasty, wheelDelta);
        }
        else
        {
            MouseButton btn = convertMouseButton(x11Button);
            lastFlags = convertMouseFlags(x11Flags, btn, action == MouseAction.buttonDown);

            if (_keyFlags & KeyFlag.shift)
                lastFlags |= MouseFlag.shift;
            if (_keyFlags & KeyFlag.control)
                lastFlags |= MouseFlag.control;
            if (_keyFlags & KeyFlag.alt)
                lastFlags |= MouseFlag.alt;
            lastx = cast(short)x;
            lasty = cast(short)y;
            event = new MouseEvent(action, btn, lastFlags, lastx, lasty);
        }
        if (event)
        {
            ButtonDetails* pbuttonDetails;
            if (event.button == MouseButton.left)
                pbuttonDetails = &_lbutton;
            else if (event.button == MouseButton.right)
                pbuttonDetails = &_rbutton;
            else if (event.button == MouseButton.middle)
                pbuttonDetails = &_mbutton;
            if (pbuttonDetails)
            {
                if (action == MouseAction.buttonDown)
                {
                    pbuttonDetails.down(cast(short)x, cast(short)y, lastFlags);
                }
                else if (action == MouseAction.buttonUp)
                {
                    pbuttonDetails.up(cast(short)x, cast(short)y, lastFlags);
                }
            }
            event.lbutton = _lbutton;
            event.rbutton = _rbutton;
            event.mbutton = _mbutton;

            bool res = dispatchMouseEvent(event);
            if (res)
            {
                debug (mouse)
                    Log.d("Calling update() after mouse event");
                update();
            }
        }
    }

    private uint convertKeyCode(uint x11Key)
    {
        import x11.keysymdef;

        alias KeyCode = beamui.core.events.KeyCode;
        switch (x11Key)
        {
        case XK_0: return KeyCode.alpha0;
        case XK_1: return KeyCode.alpha1;
        case XK_2: return KeyCode.alpha2;
        case XK_3: return KeyCode.alpha3;
        case XK_4: return KeyCode.alpha4;
        case XK_5: return KeyCode.alpha5;
        case XK_6: return KeyCode.alpha6;
        case XK_7: return KeyCode.alpha7;
        case XK_8: return KeyCode.alpha8;
        case XK_9: return KeyCode.alpha9;
        case XK_A: case XK_a: return KeyCode.A;
        case XK_B: case XK_b: return KeyCode.B;
        case XK_C: case XK_c: return KeyCode.C;
        case XK_D: case XK_d: return KeyCode.D;
        case XK_E: case XK_e: return KeyCode.E;
        case XK_F: case XK_f: return KeyCode.F;
        case XK_G: case XK_g: return KeyCode.G;
        case XK_H: case XK_h: return KeyCode.H;
        case XK_I: case XK_i: return KeyCode.I;
        case XK_J: case XK_j: return KeyCode.J;
        case XK_K: case XK_k: return KeyCode.K;
        case XK_L: case XK_l: return KeyCode.L;
        case XK_M: case XK_m: return KeyCode.M;
        case XK_N: case XK_n: return KeyCode.N;
        case XK_O: case XK_o: return KeyCode.O;
        case XK_P: case XK_p: return KeyCode.P;
        case XK_Q: case XK_q: return KeyCode.Q;
        case XK_R: case XK_r: return KeyCode.R;
        case XK_S: case XK_s: return KeyCode.S;
        case XK_T: case XK_t: return KeyCode.T;
        case XK_U: case XK_u: return KeyCode.U;
        case XK_V: case XK_v: return KeyCode.V;
        case XK_W: case XK_w: return KeyCode.W;
        case XK_X: case XK_x: return KeyCode.X;
        case XK_Y: case XK_y: return KeyCode.Y;
        case XK_Z: case XK_z: return KeyCode.Z;
        case XK_F1: return KeyCode.F1;
        case XK_F2: return KeyCode.F2;
        case XK_F3: return KeyCode.F3;
        case XK_F4: return KeyCode.F4;
        case XK_F5: return KeyCode.F5;
        case XK_F6: return KeyCode.F6;
        case XK_F7: return KeyCode.F7;
        case XK_F8: return KeyCode.F8;
        case XK_F9: return KeyCode.F9;
        case XK_F10: return KeyCode.F10;
        case XK_F11: return KeyCode.F11;
        case XK_F12: return KeyCode.F12;
        case XK_F13: return KeyCode.F13;
        case XK_F14: return KeyCode.F14;
        case XK_F15: return KeyCode.F15;
        case XK_F16: return KeyCode.F16;
        case XK_F17: return KeyCode.F17;
        case XK_F18: return KeyCode.F18;
        case XK_F19: return KeyCode.F19;
        case XK_F20: return KeyCode.F20;
        case XK_F21: return KeyCode.F21;
        case XK_F22: return KeyCode.F22;
        case XK_F23: return KeyCode.F23;
        case XK_F24: return KeyCode.F24;
        case XK_BackSpace:
            return KeyCode.backspace;
        case XK_space:
            return KeyCode.space;
        case XK_Tab:
            return KeyCode.tab;
        case XK_Return:
        case XK_KP_Enter:
            return KeyCode.enter;
        case XK_Escape:
            return KeyCode.escape;
        case XK_KP_Delete:
        case XK_Delete:
            return KeyCode.del;
        case XK_Insert:
        case XK_KP_Insert:
            return KeyCode.ins;
        case XK_KP_Home:
        case XK_Home:
            return KeyCode.home;
        case XK_KP_Page_Up:
        case XK_Page_Up:
            return KeyCode.pageUp;
        case XK_KP_End:
        case XK_End:
            return KeyCode.end;
        case XK_KP_Page_Down:
        case XK_Page_Down:
            return KeyCode.pageDown;
        case XK_KP_Left:
        case XK_Left:
            return KeyCode.left;
        case XK_KP_Right:
        case XK_Right:
            return KeyCode.right;
        case XK_KP_Up:
        case XK_Up:
            return KeyCode.up;
        case XK_KP_Down:
        case XK_Down:
            return KeyCode.down;
        case XK_Control_L:
            return KeyCode.lcontrol;
        case XK_Shift_L:
            return KeyCode.lshift;
        case XK_Alt_L:
            return KeyCode.lalt;
        case XK_Control_R:
            return KeyCode.rcontrol;
        case XK_Shift_R:
            return KeyCode.rshift;
        case XK_Alt_R:
            return KeyCode.ralt;
        case XK_slash:
        case XK_KP_Divide:
            return KeyCode.divide;
        default:
            return 0x10000 | x11Key;
        }
    }

    private uint convertKeyFlags(uint x11Keymod)
    {
        uint res;
        if (x11Keymod & ControlMask)
            res |= KeyFlag.control;
        if (x11Keymod & ShiftMask)
            res |= KeyFlag.shift;
        if (x11Keymod & LockMask)
            res |= KeyFlag.alt;
        return res;
    }

    private bool processKeyEvent(KeyAction action, uint x11Key, uint x11Keymod)
    {
        debug (keys)
            Log.fd("processKeyEvent %s, X11 key: 0x%08x, X11 flags: 0x%08x", action, keyCode, flags);

        uint keyCode = convertKeyCode(x11Key);
        uint flags = convertKeyFlags(x11Keymod);

        alias KeyCode = beamui.core.events.KeyCode;
        if (action == KeyAction.keyDown)
        {
            switch (keyCode)
            {
            case KeyCode.alt:
                flags |= KeyFlag.alt;
                break;
            case KeyCode.ralt:
                flags |= KeyFlag.alt | KeyFlag.ralt;
                break;
            case KeyCode.lalt:
                flags |= KeyFlag.alt | KeyFlag.lalt;
                break;
            case KeyCode.control:
                flags |= KeyFlag.control;
                break;
            case KeyCode.rcontrol:
                flags |= KeyFlag.control | KeyFlag.rcontrol;
                break;
            case KeyCode.lcontrol:
                flags |= KeyFlag.control | KeyFlag.lcontrol;
                break;
            case KeyCode.shift:
                flags |= KeyFlag.shift;
                break;
            case KeyCode.rshift:
                flags |= KeyFlag.shift | KeyFlag.rshift;
                break;
            case KeyCode.lshift:
                flags |= KeyFlag.shift | KeyFlag.lshift;
                break;
            default:
                break;
            }
        }
        _keyFlags = flags;

        debug (keys)
            Log.fd("processKeyEvent %s, converted key: 0x%08x, converted flags: 0x%08x", action, keyCode, flags);

        bool res = dispatchKeyEvent(new KeyEvent(action, keyCode, flags));
        //            if ((keyCode & 0x10000) && (keyCode & 0xF000) != 0xF000) {
        //                dchar[1] text;
        //                text[0] = keyCode & 0xFFFF;
        //                res = dispatchKeyEvent(new KeyEvent(KeyAction.text, keyCode, flags, cast(dstring)text)) || res;
        //            }
        if (res)
        {
            debug (redraw)
                Log.d("Calling update() after key event");
            update();
        }
        return res;
    }

    private bool processTextInput(dstring ds, uint x11Keymod)
    {
        uint flags = convertKeyFlags(x11Keymod);
        bool res = dispatchKeyEvent(new KeyEvent(KeyAction.text, 0, flags, ds));
        if (res)
        {
            debug (keys)
                Log.d("Calling update() after text event");
            update();
        }
        return res;
    }

    //===============================================================

    override void postEvent(CustomEvent event)
    {
        super.postEvent(event);
        XEvent ev;
        ev.xclient = XClientMessageEvent.init;
        ev.xclient.type = ClientMessage;
        ev.xclient.window = _win;
        ev.xclient.display = x11display2;
        ev.xclient.message_type = atom_beamui_TASK_EVENT;
        ev.xclient.format = 32;
        ev.xclient.data.l[0] = event.uniqueID;
        XLockDisplay(x11display2);
        XSendEvent(x11display2, _win, false, StructureNotifyMask, &ev);
        XFlush(x11display2);
        XUnlockDisplay(x11display2);
    }

    override protected void postTimerEvent()
    {
        XEvent ev;
        ev.xclient = XClientMessageEvent.init;
        ev.xclient.type = ClientMessage;
        ev.xclient.message_type = atom_beamui_TIMER_EVENT;
        ev.xclient.window = _win;
        ev.xclient.display = x11display2;
        ev.xclient.format = 32;
        XLockDisplay(x11display2);
        XSendEvent(x11display2, _win, false, StructureNotifyMask, &ev);
        XFlush(x11display2);
        XUnlockDisplay(x11display2);
    }

    override protected void onTimer()
    {
        super.onTimer();
    }
}

final class X11Platform : Platform
{
    this()
    {
        import std.file : thisExePath;
        import std.path : baseName;

        _classname = (baseName(thisExePath()) ~ "\0").dup.ptr;
    }

    private X11Window[XWindow] _windowMap;
    private char* _classname;

    override DWindow createWindow(dstring windowCaption, DWindow parent,
            WindowFlag flags = WindowFlag.resizable, uint width = 0, uint height = 0)
    {
        int newwidth = width;
        int newheight = height;
        auto window = new X11Window(this, windowCaption, parent, flags, newwidth, newheight);
        _windowMap[window._win] = window;
        return window;
    }

    X11Window getWindow(XWindow windowID)
    {
        return _windowMap.get(windowID, null);
    }

    override void closeWindow(DWindow w)
    {
        auto window = cast(X11Window)w;
        XEvent ev;
        ev.xclient = XClientMessageEvent.init;
        ev.xclient.type = ClientMessage;
        ev.xclient.message_type = atom_beamui_CLOSE_WINDOW_EVENT;
        ev.xclient.window = window._win;
        ev.xclient.display = x11display2;
        ev.xclient.format = 32;
        Log.d("Sending close window event");
        XLockDisplay(x11display2);
        XSendEvent(x11display2, window._win, false, StructureNotifyMask, &ev);
        XFlush(x11display2);
        XUnlockDisplay(x11display2);
    }

    bool allWindowsClosed()
    {
        return _windowMap.length == 0;
    }

    private int numberOfPendingEvents(int msecs = 10)
    {
        import core.sys.posix.sys.select;

        int x11displayFd = ConnectionNumber(x11display);
        fd_set fdSet;
        FD_ZERO(&fdSet);
        FD_SET(x11displayFd, &fdSet);
        scope (exit)
            FD_ZERO(&fdSet);

        int eventsInQueue = XEventsQueued(x11display, QueuedAlready);
        if (!eventsInQueue)
        {
            import core.stdc.errno;

            int selectResult;
            do
            {
                timeval timeout;
                timeout.tv_usec = msecs;
                selectResult = select(x11displayFd + 1, &fdSet, null, null, &timeout);
            }
            while (selectResult == -1 && errno == EINTR);
            if (selectResult < 0)
            {
                Log.e("X11: display fd select error");
            }
            else if (selectResult == 1)
            {
                //Log.d("X11: XPending");
                eventsInQueue = XPending(x11display);
            }
        }
        return eventsInQueue;
    }

    override int enterMessageLoop()
    {
        Log.d("entering message loop");

        while (!allWindowsClosed())
        {
            pumpEvents();
        }
        return 0;
    }

    private void pumpEvents()
    {
        XFlush(x11display);
        // Note: only events we set the mask for are detected!
        while (numberOfPendingEvents())
        {
            if (allWindowsClosed())
                break;
            XEvent event;
            XNextEvent(x11display, &event);
            processXEvent(event);
        }
    }

    private void processXEvent(ref XEvent event)
    {
        XComposeStatus compose;
        switch (event.type)
        {
        case ConfigureNotify:
            if (auto w = getWindow(event.xconfigure.window))
            {
                w._cachedWidth = event.xconfigure.width;
                w._cachedHeight = event.xconfigure.height;
                w.handleWindowStateChange(WindowState.unspecified, Box(event.xconfigure.x,
                        event.xconfigure.y, event.xconfigure.width, event.xconfigure.height));
            }
            else
                Log.e("ConfigureNotify: Window not found");
            break;
        case PropertyNotify:
            if (event.xproperty.atom == atom_NET_WM_STATE && event.xproperty.state == PropertyNewValue)
            {
                if (auto w = getWindow(event.xproperty.window))
                {
                    Atom type;
                    int format;
                    ubyte* properties;
                    c_ulong dataLength, overflow;
                    if (XGetWindowProperty(x11display, event.xproperty.window, atom_NET_WM_STATE,
                            0, int.max / 4, False, AnyPropertyType, &type, &format, &dataLength,
                            &overflow, &properties) == 0)
                    {
                        scope (exit)
                            XFree(properties);
                        // check for minimized
                        bool minimized = false;
                        for (int i = 0; i < dataLength; i++)
                        {
                            if (((cast(c_ulong*)properties)[i]) == atom_NET_WM_STATE_HIDDEN)
                            {
                                w.handleWindowStateChange(WindowState.minimized);
                                minimized = true;
                            }
                        }
                        if (!minimized)
                        {
                            bool maximizedH = false;
                            bool maximizedV = false;
                            for (int i = 0; i < dataLength; i++)
                            {
                                if (((cast(c_ulong*)properties)[i]) == atom_NET_WM_STATE_MAXIMIZED_VERT)
                                    maximizedV = true;
                                if (((cast(c_ulong*)properties)[i]) == atom_NET_WM_STATE_MAXIMIZED_HORZ)
                                    maximizedH = true;
                            }

                            if (maximizedV && maximizedH)
                                w.handleWindowStateChange(WindowState.maximized);
                            else
                                w.handleWindowStateChange(WindowState.normal);
                        }
                    }
                }
            }
            break;
        case MapNotify:
            if (auto w = getWindow(event.xmap.window))
            {
                w.handleWindowStateChange(WindowState.normal);
            }
            break;
        case UnmapNotify:
            if (auto w = getWindow(event.xunmap.window))
            {
                w.handleWindowStateChange(WindowState.hidden);
            }
            break;
        case Expose:
            if (event.xexpose.count == 0) // the last expose event
            {
                if (auto w = getWindow(event.xexpose.window))
                {
                    w.invalidate();
                }
                else
                    Log.e("Expose: Window not found");
            }
            break;
        case KeyPress:
            debug (x11)
                Log.d("X11: KeyPress event");
            if (auto w = getWindow(event.xkey.window))
            {
                char[100] buf;
                KeySym ks;
                Status s;
                if (!w.xic)
                {
                    w.xic = XCreateIC(xim, XNInputStyle, XIMPreeditNothing | XIMStatusNothing,
                            XNClientWindow, w._win, 0);
                    if (!w.xic)
                    {
                        Log.e("Cannot create input context");
                    }
                }

                if (!w.xic)
                    XLookupString(&event.xkey, buf.ptr, buf.length - 1, &ks, &compose);
                else
                {
                    Xutf8LookupString(w.xic, &event.xkey, buf.ptr, cast(int)buf.length - 1, &ks, &s);
                    if (s != XLookupChars && s != XLookupBoth)
                        XLookupString(&event.xkey, buf.ptr, buf.length - 1, &ks, &compose);
                }
                foreach (ref ch; buf)
                {
                    if (ch == 255 || ch < 32 || ch == 127)
                        ch = 0;
                }
                string txt = fromStringz(buf.ptr).dup;
                import std.utf;

                dstring dtext;
                try
                {
                    if (txt.length)
                        dtext = toUTF32(txt);
                }
                catch (UTFException e)
                {
                    // ignore, invalid text
                }
                debug (x11)
                    Log.d("X11: KeyPress event bytes: ", txt.length, ", text: ", txt, ", dtext: ", dtext);
                if (dtext.length)
                {
                    w.processTextInput(dtext, event.xkey.state);
                }
                else
                {
                    w.processKeyEvent(KeyAction.keyDown, cast(uint)ks, //event.xkey.keycode,
                            event.xkey.state);
                }
            }
            else
                Log.e("KeyPress: Window not found");
            break;
        case KeyRelease:
            debug (x11)
                Log.d("X11: KeyRelease event");
            if (auto w = getWindow(event.xkey.window))
            {
                char[100] buf;
                KeySym ks;
                XLookupString(&event.xkey, buf.ptr, buf.length - 1, &ks, &compose);
                w.processKeyEvent(KeyAction.keyUp, cast(uint)ks, //event.xkey.keycode,
                        event.xkey.state);
            }
            else
                Log.e("KeyRelease: Window not found");
            break;
        case ButtonPress:
            debug (x11)
                Log.d("X11: ButtonPress event");
            if (auto w = getWindow(event.xbutton.window))
            {
                if (event.xbutton.button == 4 || event.xbutton.button == 5)
                {
                    w.processMouseEvent(MouseAction.wheel, 0, 0, 0, event.xbutton.button == 4 ? 1 : -1);
                }
                else
                {
                    w.processMouseEvent(MouseAction.buttonDown, event.xbutton.button,
                            event.xbutton.state, event.xbutton.x, event.xbutton.y);
                }
            }
            else
                Log.e("ButtonPress: Window not found");
            break;
        case ButtonRelease:
            debug (x11)
                Log.d("X11: ButtonRelease event");
            if (auto w = getWindow(event.xbutton.window))
            {
                w.processMouseEvent(MouseAction.buttonUp, event.xbutton.button,
                        event.xbutton.state, event.xbutton.x, event.xbutton.y);
            }
            else
                Log.e("ButtonRelease: Window not found");
            break;
        case MotionNotify:
            debug (x11)
                Log.d("X11: MotionNotify event");
            if (auto w = getWindow(event.xmotion.window))
            {
                w.processMouseEvent(MouseAction.move, 0, event.xmotion.state, event.xmotion.x, event.xmotion.y);
            }
            else
                Log.e("MotionNotify: Window not found");
            break;
        case EnterNotify:
            debug (x11)
                Log.d("X11: EnterNotify event");
            if (auto w = getWindow(event.xcrossing.window))
            {
                w.processMouseEvent(MouseAction.move, 0, event.xmotion.state, event.xcrossing.x, event.xcrossing.y);
            }
            else
            {
                Log.e("EnterNotify: Window not found");
            }
            break;
        case LeaveNotify:
            debug (x11)
                Log.d("X11: LeaveNotify event");
            if (auto w = getWindow(event.xcrossing.window))
            {
                w.processMouseEvent(MouseAction.leave, 0, event.xcrossing.state, event.xcrossing.x, event.xcrossing.y);
            }
            else
                Log.e("LeaveNotify: Window not found");
            break;
        case CreateNotify:
            debug (x11)
                Log.d("X11: CreateNotify event");
            X11Window w = getWindow(event.xcreatewindow.window);
            if (!w)
                Log.e("CreateNotify: Window not found");
            break;
        case DestroyNotify:
            debug (x11)
                Log.d("X11: DestroyNotify event");
            break;
        case ResizeRequest:
            debug (x11)
                Log.d("X11: ResizeRequest event");
            X11Window w = getWindow(event.xresizerequest.window);
            if (!w)
                Log.e("ResizeRequest: Window not found");
            break;
        case FocusIn:
            debug (x11)
                Log.d("X11: FocusIn event");
            if (auto w = getWindow(event.xfocus.window))
                w.handleWindowActivityChange(true);
            else
                Log.e("FocusIn: Window not found");
            break;
        case FocusOut:
            debug (x11)
                Log.d("X11: FocusOut event");
            if (auto w = getWindow(event.xfocus.window))
                w.handleWindowActivityChange(false);
            else
                Log.e("FocusOut: Window not found");
            break;
        case KeymapNotify:
            debug (x11)
                Log.d("X11: KeymapNotify event");
            X11Window w = getWindow(event.xkeymap.window);
            break;
        case SelectionClear:
            debug (x11)
                Log.d("X11: SelectionClear event");
            break;
        case SelectionRequest:
            debug (x11)
                Log.d("X11: SelectionRequest event");
            if (event.xselectionrequest.owner in _windowMap)
            {
                XSelectionRequestEvent* selectionRequest = &event.xselectionrequest;

                XEvent selectionEvent;
                selectionEvent.xselection = XSelectionEvent.init;
                selectionEvent.xselection.type = SelectionNotify;
                selectionEvent.xselection.selection = selectionRequest.selection;
                selectionEvent.xselection.target = selectionRequest.target;
                selectionEvent.xselection.property = None;
                selectionEvent.xselection.requestor = selectionRequest.requestor;
                selectionEvent.xselection.time = selectionRequest.time;

                if (selectionRequest.target == XA_STRING || selectionRequest.target == atom_UTF8_STRING)
                {
                    int currentSelectionFormat;
                    Atom currentSelectionType;
                    c_ulong selectionDataLength, overflow;
                    ubyte* selectionDataPtr;
                    if (XGetWindowProperty(x11display, DefaultRootWindow(x11display),
                            atom_beamui_CLIPBOARD_BUFFER, 0, int.max / 4,
                            False, selectionRequest.target, &currentSelectionType, &currentSelectionFormat,
                            &selectionDataLength, &overflow, &selectionDataPtr) == 0)
                    {
                        scope (exit)
                            XFree(selectionDataPtr);
                        XChangeProperty(x11display, selectionRequest.requestor, selectionRequest.property,
                                selectionRequest.target, 8, PropModeReplace, selectionDataPtr,
                                cast(int)selectionDataLength);
                    }
                    selectionEvent.xselection.property = selectionRequest.property;
                }
                else if (selectionRequest.target == atom_TARGETS)
                {
                    Atom[3] supportedFormats = [atom_UTF8_STRING, XA_STRING, atom_TARGETS];
                    XChangeProperty(x11display, selectionRequest.requestor, selectionRequest.property, XA_ATOM, 32,
                            PropModeReplace, cast(ubyte*)supportedFormats.ptr, cast(int)supportedFormats.length);
                    selectionEvent.xselection.property = selectionRequest.property;
                }
                XSendEvent(x11display, selectionRequest.requestor, False, 0, &selectionEvent);
            }
            break;
        case SelectionNotify:
            debug (x11)
                Log.d("X11: SelectionNotify event");
            if (auto w = getWindow(event.xselection.requestor))
            {
                waitingForSelection = false;
            }
            break;
        case ClientMessage:
            debug (x11)
                Log.d("X11: ClientMessage event");
            if (auto w = getWindow(event.xclient.window))
            {
                if (event.xclient.message_type == atom_beamui_TASK_EVENT)
                {
                    w.handlePostedEvent(cast(uint)event.xclient.data.l[0]);
                }
                else if (event.xclient.message_type == atom_beamui_TIMER_EVENT)
                {
                    w.onTimer();
                }
                else if (event.xclient.message_type == atom_beamui_REDRAW_EVENT)
                {
                    if (event.xclient.data.l[0] == w._lastRedrawEventCode)
                        w.redraw();
                }
                else if (event.xclient.message_type == atom_WM_PROTOCOLS)
                {
                    Log.d("Handling WM_PROTOCOLS");
                    if ((event.xclient.format == 32) && (event.xclient.data.l[0]) == atom_WM_DELETE_WINDOW)
                    {
                        Log.d("Handling WM_DELETE_WINDOW");
                        _windowMap.remove(w._win);
                        destroy(w);
                    }
                }
                else if (event.xclient.message_type == atom_beamui_CLOSE_WINDOW_EVENT)
                {
                    _windowMap.remove(w._win);
                    destroy(w);
                }
            }
            else
                Log.e("ClientMessage: Window not found");
            break;
        default:
            break;
        }
    }

    override bool hasClipboardText(bool mouseBuffer = false)
    {
        const selectionType = mouseBuffer ? XA_PRIMARY : atom_CLIPBOARD;
        return XGetSelectionOwner(x11display, selectionType) != None;
    }

    private bool waitingForSelection;
    override dstring getClipboardText(bool mouseBuffer = false)
    {
        const selectionType = mouseBuffer ? XA_PRIMARY : atom_CLIPBOARD;
        auto owner = XGetSelectionOwner(x11display, selectionType);
        if (owner == None)
        {
            Log.d("Selection owner is none");
            return ""d;
        }
        else
        {
            // Find any top-level window
            XWindow xwindow;
            foreach (w; _windowMap)
            {
                if (w.parentWindow is null && w._win != None)
                {
                    xwindow = w._win;
                    break;
                }
            }
            if (xwindow != None)
            {
                import std.datetime;

                waitingForSelection = true;
                XConvertSelection(x11display, selectionType, atom_UTF8_STRING,
                        atom_beamui_CLIPBOARD_BUFFER, xwindow, CurrentTime);
                auto stopWaiting = Clock.currTime() + dur!"msecs"(500);
                while (waitingForSelection)
                {
                    if (stopWaiting <= Clock.currTime())
                    {
                        waitingForSelection = false;
                        setClipboardText(""d);
                        Log.e("Waiting for clipboard contents timeout");
                        return ""d;
                    }
                    pumpEvents();
                }
                Atom selectionTarget;
                int selectionFormat;
                c_ulong selectionDataLength, overflow;
                ubyte* selectionDataPtr;
                if (XGetWindowProperty(x11display, xwindow, atom_beamui_CLIPBOARD_BUFFER, 0, int.max / 4,
                        False, 0, &selectionTarget, &selectionFormat, &selectionDataLength,
                        &overflow, &selectionDataPtr) == 0)
                {
                    scope (exit)
                        XFree(selectionDataPtr);
                    if (selectionTarget == XA_STRING || selectionTarget == atom_UTF8_STRING)
                    {
                        char[] selectionText = cast(char[])selectionDataPtr[0 .. selectionDataLength];
                        return toUTF32(selectionText);
                    }
                    else
                    {
                        Log.d("Selection type is not a string!");
                    }
                }
            }
            else
            {
                Log.d("Could not find any window to get selection");
            }
        }
        return ""d;
    }

    override void setClipboardText(dstring text, bool mouseBuffer = false)
    {
        if (!mouseBuffer && atom_CLIPBOARD == None)
        {
            Log.e("No CLIPBOARD atom available");
            return;
        }
        auto selection = mouseBuffer ? XA_PRIMARY : atom_CLIPBOARD;
        XWindow xwindow = None;
        // Find any top-level window
        foreach (w; _windowMap)
        {
            if (w.parentWindow is null && w._win != None)
            {
                xwindow = w._win;
            }
        }
        if (xwindow == None)
        {
            Log.e("Could not find window to save clipboard text");
            return;
        }

        auto textc = text.toUTF8;
        XChangeProperty(x11display, DefaultRootWindow(x11display), atom_beamui_CLIPBOARD_BUFFER,
                atom_UTF8_STRING, 8, PropModeReplace, cast(ubyte*)textc.ptr, cast(int)textc.length);

        if (XGetSelectionOwner(x11display, selection) != xwindow)
        {
            XSetSelectionOwner(x11display, selection, xwindow, CurrentTime);
        }
    }

    override void requestLayout()
    {
        foreach (w; _windowMap)
        {
            w.requestLayout();
        }
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        foreach (w; _windowMap)
            w.dispatchThemeChanged();
    }
}

extern (C) int beamuimain(string[] args)
{
    import beamui.platforms.common.startup;

    initLogs();

    if (!initFontManager())
    {
        Log.e("******************************************************************");
        Log.e("No font files found!!!");
        Log.e("Currently, only hardcoded font paths implemented.");
        Log.e("Probably you can modify startup.d to add some fonts for your system.");
        Log.e("******************************************************************");
        assert(false);
    }
    initResourceManagers();

    XInitThreads();

    /* use the information from the environment variable DISPLAY
       to create the X connection:
    */
    x11display = XOpenDisplay(null);
    if (!x11display)
    {
        Log.e("Cannot open X11 display");
        return 1;
    }
    x11display2 = XOpenDisplay(null);
    if (!x11display2)
    {
        Log.e("Cannot open secondary connection for X11 display");
        return 1;
    }

    x11screen = DefaultScreen(x11display);

    static if (USE_OPENGL)
    {
        if (initBasicOpenGL())
        {
            GLint[] att = [GLX_RGBA, GLX_DEPTH_SIZE, 24, GLX_DOUBLEBUFFER, None];
            XWindow root = DefaultRootWindow(x11display);
            x11visual = glXChooseVisual(x11display, 0, cast(int*)att.ptr);
            if (x11visual)
            {
                x11cmap = XCreateColormap(x11display, root, cast(Visual*)x11visual.visual, AllocNone);
            }
            else
            {
                Log.e("Cannot find suitable Visual for using of OpenGL");
                disableOpenGL();
            }
        }
        else
            disableOpenGL();
    }

    setupX11Atoms();

    x11cursors[CursorType.none] = XCreateFontCursor(x11display, XC_arrow);
    x11cursors[CursorType.notSet] = XCreateFontCursor(x11display, XC_arrow);
    x11cursors[CursorType.arrow] = XCreateFontCursor(x11display, XC_left_ptr);
    x11cursors[CursorType.ibeam] = XCreateFontCursor(x11display, XC_xterm);
    x11cursors[CursorType.wait] = XCreateFontCursor(x11display, XC_watch);
    x11cursors[CursorType.crosshair] = XCreateFontCursor(x11display, XC_tcross);
    x11cursors[CursorType.waitArrow] = XCreateFontCursor(x11display, XC_watch);
    x11cursors[CursorType.sizeNWSE] = XCreateFontCursor(x11display, XC_fleur);
    x11cursors[CursorType.sizeNESW] = XCreateFontCursor(x11display, XC_fleur);
    x11cursors[CursorType.sizeWE] = XCreateFontCursor(x11display, XC_sb_h_double_arrow);
    x11cursors[CursorType.sizeNS] = XCreateFontCursor(x11display, XC_sb_v_double_arrow);
    x11cursors[CursorType.sizeAll] = XCreateFontCursor(x11display, XC_fleur);
    x11cursors[CursorType.no] = XCreateFontCursor(x11display, XC_pirate);
    x11cursors[CursorType.hand] = XCreateFontCursor(x11display, XC_hand2);

    xim = XOpenIM(x11display, null, null, null);
    if (!xim)
    {
        Log.e("Cannot open input method");
    }

    Log.d("X11 display: ", x11display, ", screen: ", x11screen);

    Platform.instance = new X11Platform;
    Platform.instance.uiTheme = "default";

    version (unittest)
    {
        int result = 0;
    }
    else
    {
        int result = -1;
        try
        {
            result = UIAppMain(args);
        }
        catch (Exception e)
        {
            Log.e("Abnormal UIAppMain termination");
            Log.e("UIAppMain exception: ", e);
        }
    }

    Platform.instance = null;

    static if (USE_OPENGL)
    {
        glNoContext = true;
        if (x11cmap)
            XFreeColormap(x11display, x11cmap);
    }

    releaseResourcesOnAppExit();

    XCloseDisplay(x11display);
    XCloseDisplay(x11display2);

    Log.d("Exiting main");
    return result;
}
