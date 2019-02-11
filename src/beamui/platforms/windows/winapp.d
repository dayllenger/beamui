/**
Implementation of Win32 platform support

Provides Win32Window and Win32Platform classes.

Usually you don't need to use this module directly.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.windows.winapp;

import beamui.core.config;

static if (BACKEND_WIN32):
import core.runtime;
import core.sys.windows.windows;
import std.algorithm;
import std.file;
import std.stdio;
import std.string;
import std.utf;
import beamui.core.logger;
import beamui.graphics.drawbuf;
import beamui.graphics.fonts;
import beamui.graphics.images;
import beamui.platforms.common.platform;
import beamui.platforms.common.startup;
import beamui.platforms.windows.win32drawbuf;
import beamui.platforms.windows.win32fonts;
import beamui.widgets.widget;
static if (USE_OPENGL)
{
    import beamui.graphics.glsupport;
}

pragma(lib, "gdi32.lib");
pragma(lib, "user32.lib");

immutable WIN_CLASS_NAME = "BEAMUI_APP";

static if (USE_OPENGL)
{
    bool setupPixelFormat(HDC device)
    {
        PIXELFORMATDESCRIPTOR pfd = {
            PIXELFORMATDESCRIPTOR.sizeof, /* size */
                1, /* version */
                PFD_SUPPORT_OPENGL | PFD_DRAW_TO_WINDOW | PFD_DOUBLEBUFFER, /* support double-buffering */
                PFD_TYPE_RGBA, /* color type */
                16, /* prefered color depth */
                0, 0, 0, 0, 0, 0, /* color bits (ignored) */
                0, /* no alpha buffer */
                0, /* alpha bits (ignored) */
                0, /* no accumulation buffer */
                0, 0, 0, 0, /* accum bits (ignored) */
                16, /* depth buffer */
                0, /* no stencil buffer */
                0, /* no auxiliary buffers */
                0, /* main layer PFD_MAIN_PLANE */
                0, /* reserved */
                0, 0, 0, /* no layer, visible, damage masks */
        };
        int pixelFormat;

        pixelFormat = ChoosePixelFormat(device, &pfd);
        if (pixelFormat == 0)
        {
            Log.e("ChoosePixelFormat failed.");
            return false;
        }

        if (SetPixelFormat(device, pixelFormat, &pfd) != TRUE)
        {
            Log.e("SetPixelFormat failed.");
            return false;
        }
        return true;
    }

    HPALETTE setupPalette(HDC device)
    {
        import core.stdc.stdlib;

        HPALETTE palette = NULL;
        int pixelFormat = GetPixelFormat(device);
        PIXELFORMATDESCRIPTOR pfd;
        LOGPALETTE* pPal;
        int paletteSize;

        DescribePixelFormat(device, pixelFormat, PIXELFORMATDESCRIPTOR.sizeof, &pfd);

        if (pfd.dwFlags & PFD_NEED_PALETTE)
        {
            paletteSize = 1 << pfd.cColorBits;
        }
        else
        {
            return null;
        }

        pPal = cast(LOGPALETTE*)malloc(LOGPALETTE.sizeof + paletteSize * PALETTEENTRY.sizeof);
        pPal.palVersion = 0x300;
        pPal.palNumEntries = cast(ushort)paletteSize;

        /* build a simple RGB color palette */
        {
            int redMask = (1 << pfd.cRedBits) - 1;
            int greenMask = (1 << pfd.cGreenBits) - 1;
            int blueMask = (1 << pfd.cBlueBits) - 1;
            int i;

            for (i = 0; i < paletteSize; ++i)
            {
                pPal.palPalEntry[i].peRed = cast(ubyte)((((i >> pfd.cRedShift) & redMask) * 255) / redMask);
                pPal.palPalEntry[i].peGreen = cast(ubyte)((((i >> pfd.cGreenShift) & greenMask) * 255) / greenMask);
                pPal.palPalEntry[i].peBlue = cast(ubyte)((((i >> pfd.cBlueShift) & blueMask) * 255) / blueMask);
                pPal.palPalEntry[i].peFlags = 0;
            }
        }

        palette = CreatePalette(pPal);
        free(pPal);

        if (palette)
        {
            SelectPalette(device, palette, FALSE);
            RealizePalette(device);
        }

        return palette;
    }

    private __gshared bool DERELICT_GL3_RELOADED = false;
}

const uint CUSTOM_MESSAGE = WM_USER + 1;
const uint TIMER_MESSAGE = WM_USER + 2;

static if (USE_OPENGL)
{
    /// Shared opengl context helper
    struct SharedGLContext
    {
        import derelict.opengl3.wgl;

        HGLRC _context; // opengl context
        HPALETTE _palette;
        bool _error;
        /// Init OpenGL context, if not yet initialized
        bool init(HDC device)
        {
            if (_context)
            {
                // just setup pixel format
                if (setupPixelFormat(device))
                {
                    Log.i("OpenGL context already exists. Setting pixel format.");
                }
                else
                {
                    Log.e("Cannot setup pixel format");
                }
                return true;
            }
            if (_error)
                return false;
            if (setupPixelFormat(device))
            {
                _palette = setupPalette(device);
                _context = wglCreateContext(device);
                if (_context)
                {
                    bind(device);
                    bool initialized = initGLSupport(platform.GLVersionMajor < 3);
                    unbind(device);
                    if (!initialized)
                    {
                        uninit();
                        Log.e("Failed to init OpenGL shaders");
                        _error = true;
                        return false;
                    }
                    return true;
                }
                else
                {
                    _error = true;
                    return false;
                }
            }
            else
            {
                Log.e("Cannot setup pixel format");
                _error = true;
                return false;
            }
        }

        void uninit()
        {
            if (_context)
            {
                wglDeleteContext(_context);
                _context = null;
            }
        }
        /// Make this context current for DC
        void bind(HDC device)
        {
            if (!wglMakeCurrent(device, _context))
            {
                import std.string : format;

                Log.e("wglMakeCurrent is failed. GetLastError=%x".format(GetLastError()));
            }
        }
        /// Make null context current for DC
        void unbind(HDC device)
        {
            //wglMakeCurrent(device, null);
            wglMakeCurrent(null, null);
        }

        void swapBuffers(HDC device)
        {
            SwapBuffers(device);
        }
    }

    /// OpenGL context to share between windows
    __gshared SharedGLContext sharedGLContext;
}

/// Returns true if message is handled, put return value into result
alias unknownWindowMessageHandler =
    bool delegate(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam, ref LRESULT result);

final class Win32Window : Window
{
    /// Win32 only - return window handle
    @property HWND windowHandle() { return _hwnd; }

    private
    {
        Win32Platform _platform;

        HWND _hwnd;

        dstring _title;
        DrawBuf _drawbuf;

        bool useOpengl;
        bool _destroying;
    }

    this(Win32Platform platform, dstring title, Window parent, WindowOptions options, uint w = 0, uint h = 0)
    {
        super(parent, options);
        _platform = platform;
        _title = title;
        _windowState = WindowState.hidden;

        if (parent)
            parent.addModalChild(this);

        auto w32parent = cast(Win32Window)parent;
        HWND parenthwnd = w32parent ? w32parent._hwnd : null;

        width = w > 0 ? w : 500;
        height = h > 0 ? h : 300;

        uint ws = WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
        if (options & WindowOptions.resizable)
            ws |= WS_OVERLAPPEDWINDOW;
        else
            ws |= WS_OVERLAPPED | WS_CAPTION | WS_CAPTION | WS_BORDER | WS_SYSMENU;

        BoxI screenRc = getScreenDimensions();
        Log.d("Screen dimensions: ", screenRc);

        int x = CW_USEDEFAULT;
        int y = CW_USEDEFAULT;

        if (options & WindowOptions.fullscreen)
        {
            // fullscreen
            x = screenRc.x;
            y = screenRc.y;
            width = screenRc.width;
            height = screenRc.height;
            ws = WS_POPUP;
        }
        if (options & WindowOptions.borderless)
        {
            ws = WS_POPUP | WS_SYSMENU;
        }

        _hwnd = CreateWindowW(toUTF16z(WIN_CLASS_NAME), // window class name
                toUTF16z(title), // window caption
                ws, // window style
                x, // initial x position
                y, // initial y position
                width, // initial x size
                height, // initial y size
                parenthwnd, // parent window handle
                null, // window menu handle
                GetModuleHandle(null), // program instance handle
                cast(void*)this); // creation parameters

        static if (USE_OPENGL)
        {
            // initialize OpenGL rendering
            HDC device = GetDC(_hwnd);

            if (openglEnabled)
            {
                useOpengl = sharedGLContext.init(device);
            }
        }

        updateDPI();

        RECT rect;
        GetWindowRect(_hwnd, &rect);
        handleWindowStateChange(WindowState.unspecified, BoxI(rect.left, rect.top, width, height));

        if (platform.defaultWindowIcon.length != 0)
            this.icon = imageCache.get(platform.defaultWindowIcon);
    }

    ~this()
    {
        _destroying = true;
        eliminate(_drawbuf);

        if (_hwnd)
            DestroyWindow(_hwnd);
        _hwnd = null;
    }

    private BoxI getScreenDimensions()
    {
        MONITORINFO monitor_info;
        monitor_info.cbSize = monitor_info.sizeof;
        HMONITOR hMonitor;
        if (_hwnd)
        {
            hMonitor = MonitorFromWindow(_hwnd, MONITOR_DEFAULTTONEAREST);
        }
        else
        {
            hMonitor = MonitorFromPoint(POINT(0, 0), MONITOR_DEFAULTTOPRIMARY);
        }
        GetMonitorInfo(hMonitor, &monitor_info);
        RECT rc = monitor_info.rcMonitor;
        return BoxI(rc.left, rc.top, rc.right - rc.left, rc.bottom - rc.top);
    }

    override @property void onFilesDropped(void delegate(string[]) handler)
    {
        DragAcceptFiles(_hwnd, handler ? TRUE : FALSE);
        super.onFilesDropped(handler);
    }

    /// Custom window message handler
    Signal!unknownWindowMessageHandler onUnknownWindowMessage;
    private LRESULT handleUnknownWindowMessage(UINT message, WPARAM wParam, LPARAM lParam)
    {
        if (onUnknownWindowMessage.assigned)
        {
            LRESULT res;
            if (onUnknownWindowMessage(_hwnd, message, wParam, lParam, res))
                return res;
        }
        return DefWindowProc(_hwnd, message, wParam, lParam);
    }

    override protected void handleWindowStateChange(WindowState newState, BoxI newWindowRect = BoxI.none)
    {
        if (_destroying)
            return;
        super.handleWindowStateChange(newState, newWindowRect);
    }

    override bool setWindowState(WindowState newState, bool activate = false, BoxI newWindowRect = BoxI.none)
    {
        if (!_hwnd)
            return false;
        bool res = false;
        // change state and activate support
        switch (newState)
        {
        case WindowState.unspecified:
            if (activate)
            {
                switch (_windowState)
                {
                case WindowState.hidden: // show hidden window
                    ShowWindow(_hwnd, SW_SHOW);
                    res = true;
                    break;
                case WindowState.normal:
                    ShowWindow(_hwnd, SW_SHOWNORMAL);
                    res = true;
                    break;
                case WindowState.fullscreen:
                    ShowWindow(_hwnd, SW_SHOWNORMAL);
                    res = true;
                    break;
                case WindowState.minimized:
                    ShowWindow(_hwnd, SW_SHOWMINIMIZED);
                    res = true;
                    break;
                case WindowState.maximized:
                    ShowWindow(_hwnd, SW_SHOWMAXIMIZED);
                    res = true;
                    break;
                default:
                    break;
                }
                res = true;
            }
            break;
        case WindowState.maximized:
            if (_windowState != WindowState.maximized || activate)
            {
                ShowWindow(_hwnd, activate ? SW_SHOWMAXIMIZED : SW_MAXIMIZE);
                res = true;
            }
            break;
        case WindowState.minimized:
            if (_windowState != WindowState.minimized || activate)
            {
                ShowWindow(_hwnd, activate ? SW_SHOWMINIMIZED : SW_MINIMIZE);
                res = true;
            }
            break;
        case WindowState.hidden:
            if (_windowState != WindowState.hidden)
            {
                ShowWindow(_hwnd, SW_HIDE);
                res = true;
            }
            break;
        case WindowState.normal:
            if (_windowState != WindowState.normal || activate)
            {
                ShowWindow(_hwnd, activate ? SW_SHOWNORMAL : SW_SHOWNA); // SW_RESTORE
                res = true;
            }
            break;

        default:
            break;
        }
        // change size and/or position
        bool rectChanged = false;
        if (newWindowRect != BoxI.none && (newState == WindowState.normal ||
                newState == WindowState.unspecified))
        {
            UINT flags = SWP_NOOWNERZORDER | SWP_NOZORDER;
            if (!activate)
                flags |= SWP_NOACTIVATE;
            if (newWindowRect.x == int.min || newWindowRect.y == int.min)
            {
                // no position specified
                if (newWindowRect.w != int.min && newWindowRect.h != int.min)
                {
                    // change size only
                    SetWindowPos(_hwnd, NULL, 0, 0, newWindowRect.w + 2 * GetSystemMetrics(SM_CXDLGFRAME),
                            newWindowRect.h + GetSystemMetrics(SM_CYCAPTION) + 2 * GetSystemMetrics(SM_CYDLGFRAME),
                            flags | SWP_NOMOVE);
                    rectChanged = true;
                    res = true;
                }
            }
            else
            {
                if (newWindowRect.w != int.min && newWindowRect.h != int.min)
                {
                    // change size and position
                    SetWindowPos(_hwnd, NULL, newWindowRect.x, newWindowRect.y,
                            newWindowRect.w + 2 * GetSystemMetrics(SM_CXDLGFRAME),
                            newWindowRect.h + GetSystemMetrics(SM_CYCAPTION) + 2 * GetSystemMetrics(SM_CYDLGFRAME),
                            flags);
                    rectChanged = true;
                    res = true;
                }
                else
                {
                    // change position only
                    SetWindowPos(_hwnd, NULL, newWindowRect.x, newWindowRect.y, 0, 0, flags | SWP_NOSIZE);
                    rectChanged = true;
                    res = true;
                }
            }
        }

        if (rectChanged)
        {
            handleWindowStateChange(newState, BoxI(
                newWindowRect.x == int.min ? _windowRect.x : newWindowRect.x,
                newWindowRect.y == int.min ? _windowRect.y : newWindowRect.y,
                newWindowRect.w == int.min ? _windowRect.w : newWindowRect.w,
                newWindowRect.h == int.min ? _windowRect.h : newWindowRect.h));
        }
        else
            handleWindowStateChange(newState, BoxI.none);

        return res;
    }

    override @property bool isActive() const
    {
        return _hwnd == GetForegroundWindow();
    }

    override protected void handleWindowActivityChange(bool isWindowActive)
    {
        super.handleWindowActivityChange(isWindowActive);
    }

    //===============================================================

    override @property dstring title() const
    {
        return _title;
    }

    override @property void title(dstring caption)
    {
        _title = caption;
        if (_hwnd)
            SetWindowTextW(_hwnd, toUTF16z(_title));
    }

    private HICON _icon;

    override @property void icon(DrawBufRef buf)
    {
        if (_icon)
            DestroyIcon(_icon);
        _icon = null;
        auto ic = cast(ColorDrawBuf)buf.get;
        if (!ic)
        {
            Log.e("Trying to set null icon for window");
            return;
        }
        auto resizedicon = new Win32ColorDrawBuf(ic, 32, 32);
        resizedicon.invertAlpha();
        ICONINFO ii;
        HBITMAP mask = resizedicon.createTransparencyBitmap();
        HBITMAP color = resizedicon.destroyLeavingBitmap();
        ii.fIcon = TRUE;
        ii.xHotspot = 0;
        ii.yHotspot = 0;
        ii.hbmMask = mask;
        ii.hbmColor = color;
        _icon = CreateIconIndirect(&ii);
        if (_icon)
        {
            SendMessageW(_hwnd, WM_SETICON, ICON_SMALL, cast(LPARAM)_icon);
            SendMessageW(_hwnd, WM_SETICON, ICON_BIG, cast(LPARAM)_icon);
        }
        else
        {
            Log.e("failed to create icon");
        }
        if (mask)
            DeleteObject(mask);
        DeleteObject(color);
    }

    override void show()
    {
        if (!mainWidget)
        {
            Log.e("Window is shown without main widget");
            mainWidget = new Widget;
        }
        ReleaseCapture();

        adjustSize();
        adjustPosition();

        mainWidget.setFocus();

        if (options & WindowOptions.fullscreen)
        {
            BoxI rc = getScreenDimensions();
            SetWindowPos(_hwnd, HWND_TOPMOST, 0, 0, rc.width, rc.height, SWP_SHOWWINDOW);
            _windowState = WindowState.fullscreen;
        }
        else
        {
            ShowWindow(_hwnd, SW_SHOWNORMAL);
            _windowState = WindowState.normal;
        }

        SetFocus(_hwnd);
        //UpdateWindow(_hwnd);
    }

    override void invalidate()
    {
        InvalidateRect(_hwnd, null, FALSE);
        //UpdateWindow(_hwnd);
    }

    private bool _closeCalled;

    override void close()
    {
        if (_closeCalled)
            return;
        _closeCalled = true;
        _platform.closeWindow(this);
    }

    //===============================================================

    private uint _cursorType;
    private HANDLE[ushort] _cursorCache;

    private HANDLE loadCursor(ushort id)
    {
        if (auto p = id in _cursorCache)
            return *p;
        HANDLE h = LoadCursor(null, MAKEINTRESOURCE(id));
        _cursorCache[id] = h;
        return h;
    }

    private void onSetCursorType()
    {
        HANDLE winCursor = null;
        switch (_cursorType) with (CursorType)
        {
        case none:
            winCursor = null;
            break;
        case notSet:
            break;
        case arrow:
            winCursor = loadCursor(IDC_ARROW);
            break;
        case ibeam:
            winCursor = loadCursor(IDC_IBEAM);
            break;
        case wait:
            winCursor = loadCursor(IDC_WAIT);
            break;
        case crosshair:
            winCursor = loadCursor(IDC_CROSS);
            break;
        case waitArrow:
            winCursor = loadCursor(IDC_APPSTARTING);
            break;
        case sizeNWSE:
            winCursor = loadCursor(IDC_SIZENWSE);
            break;
        case sizeNESW:
            winCursor = loadCursor(IDC_SIZENESW);
            break;
        case sizeWE:
            winCursor = loadCursor(IDC_SIZEWE);
            break;
        case sizeNS:
            winCursor = loadCursor(IDC_SIZENS);
            break;
        case sizeAll:
            winCursor = loadCursor(IDC_SIZEALL);
            break;
        case no:
            winCursor = loadCursor(IDC_NO);
            break;
        case hand:
            winCursor = loadCursor(IDC_HAND);
            break;
        default:
            break;
        }
        SetCursor(winCursor);
    }

    override protected void setCursorType(CursorType cursorType)
    {
        _cursorType = cursorType;
        onSetCursorType();
    }

    private void updateDPI()
    {
        HDC hdc = GetDC(_hwnd);
        const dpi = GetDeviceCaps(hdc, LOGPIXELSY);
        setDPI(dpi, 1); // TODO
    }

    private void onPaint()
    {
        debug (redraw)
            Log.d("onPaint()");
        long paintStart = currentTimeMillis;
        static if (USE_OPENGL)
        {
            if (useOpengl && sharedGLContext._context)
            {
                paintUsingOpenGL();
            }
            else
            {
                paintUsingGDI();
            }
        }
        else
        {
            paintUsingGDI();
        }
        long paintEnd = currentTimeMillis;
        debug (redraw)
            Log.d("WM_PAINT handling took ", paintEnd - paintStart, " ms");
    }

    private void paintUsingGDI()
    {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(_hwnd, &ps);
        scope (exit)
            EndPaint(_hwnd, &ps);

        const pw = physicalWidth;
        const ph = physicalHeight;
        if (!_drawbuf)
            _drawbuf = new Win32ColorDrawBuf(pw, ph);
        else
            _drawbuf.resize(pw, ph);
        _drawbuf.resetClipping();

        _drawbuf.fill(backgroundColor);
        onDraw(_drawbuf);
        (cast(Win32ColorDrawBuf)_drawbuf).drawTo(hdc, 0, 0);
    }

    static if (USE_OPENGL)
    {
        override protected void bindContext()
        {
            HDC hdc = GetDC(_hwnd);
            sharedGLContext.bind(hdc);
        }

        override protected void swapBuffers()
        {
            HDC hdc = GetDC(_hwnd);
            sharedGLContext.swapBuffers(hdc);
        }

        private void paintUsingOpenGL()
        {
            // hack to stop infinite WM_PAINT loop
            PAINTSTRUCT ps;
            HDC hdc2 = BeginPaint(_hwnd, &ps);
            EndPaint(_hwnd, &ps); // FIXME: scope(exit)?

            drawUsingOpenGL(_drawbuf);
        }
    }

    //===============================================================

    private ButtonDetails _lbutton;
    private ButtonDetails _mbutton;
    private ButtonDetails _rbutton;

    private void updateButtonsState(uint flags)
    {
        if (!(flags & MK_LBUTTON) && _lbutton.isDown)
            _lbutton.reset();
        if (!(flags & MK_MBUTTON) && _mbutton.isDown)
            _mbutton.reset();
        if (!(flags & MK_RBUTTON) && _rbutton.isDown)
            _rbutton.reset();
    }

    private bool processMouseEvent(uint message, uint flags, short x, short y)
    {
        debug (mouse)
            Log.d("Win32 Mouse Message ", message, " flags=", flags, " x=", x, " y=", y);
        MouseButton button = MouseButton.none;
        MouseAction action = MouseAction.buttonDown;
        ButtonDetails* pbuttonDetails = null;
        short wheelDelta = 0;
        switch (message)
        {
        case WM_MOUSEMOVE:
            action = MouseAction.move;
            updateButtonsState(flags);
            break;
        case WM_LBUTTONDOWN:
            action = MouseAction.buttonDown;
            button = MouseButton.left;
            pbuttonDetails = &_lbutton;
            SetFocus(_hwnd);
            break;
        case WM_RBUTTONDOWN:
            action = MouseAction.buttonDown;
            button = MouseButton.right;
            pbuttonDetails = &_rbutton;
            SetFocus(_hwnd);
            break;
        case WM_MBUTTONDOWN:
            action = MouseAction.buttonDown;
            button = MouseButton.middle;
            pbuttonDetails = &_mbutton;
            SetFocus(_hwnd);
            break;
        case WM_LBUTTONUP:
            action = MouseAction.buttonUp;
            button = MouseButton.left;
            pbuttonDetails = &_lbutton;
            break;
        case WM_RBUTTONUP:
            action = MouseAction.buttonUp;
            button = MouseButton.right;
            pbuttonDetails = &_rbutton;
            break;
        case WM_MBUTTONUP:
            action = MouseAction.buttonUp;
            button = MouseButton.middle;
            pbuttonDetails = &_mbutton;
            break;
        case WM_MOUSELEAVE:
            debug (mouse)
                Log.d("WM_MOUSELEAVE");
            action = MouseAction.leave;
            break;
        case WM_MOUSEWHEEL:
            {
                action = MouseAction.wheel;
                wheelDelta = (cast(short)(flags >> 16)) / 120;
                POINT pt;
                pt.x = x;
                pt.y = y;
                ScreenToClient(_hwnd, &pt);
                x = cast(short)pt.x;
                y = cast(short)pt.y;
            }
            break;
        default: // unsupported event
            return false;
        }
        if (action == MouseAction.buttonDown)
        {
            pbuttonDetails.down(x, y, cast(ushort)flags);
        }
        else if (action == MouseAction.buttonUp)
        {
            pbuttonDetails.up(x, y, cast(ushort)flags);
        }
        auto event = new MouseEvent(action, button, cast(ushort)flags, x, y, wheelDelta);
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
        return res;
    }

    private uint _keyFlags;

    private void updateKeyFlags(KeyAction action, KeyFlag flag, uint preserveFlag)
    {
        if (action == KeyAction.keyDown)
            _keyFlags |= flag;
        else
        {
            if (preserveFlag && (_keyFlags & preserveFlag) == preserveFlag)
            {
                // e.g. when both lctrl and rctrl are pressed, and lctrl is up, preserve rctrl flag
                _keyFlags = (_keyFlags & ~flag) | preserveFlag;
            }
            else
            {
                _keyFlags &= ~flag;
            }
        }
    }

    private bool processKeyEvent(KeyAction action, uint keyCode, int repeatCount, dchar character = 0, bool syskey = false)
    {
        debug (keys)
            Log.fd("processKeyEvent %s, keyCode: %s, char: %s (%s), syskey: %s, _keyFlags: %04x",
                action, keyCode, character, cast(int)character, syskey, _keyFlags);
        KeyEvent event;
        if (syskey)
            _keyFlags |= KeyFlag.alt;
        //else
        //    _keyFlags &= ~KeyFlag.alt;
        uint oldFlags = _keyFlags;
        if (action == KeyAction.keyDown || action == KeyAction.keyUp)
        {
            switch (keyCode)
            {
            case KeyCode.lshift:
                updateKeyFlags(action, KeyFlag.lshift, KeyFlag.rshift);
                break;
            case KeyCode.rshift:
                updateKeyFlags(action, KeyFlag.rshift, KeyFlag.lshift);
                break;
            case KeyCode.lcontrol:
                updateKeyFlags(action, KeyFlag.lcontrol, KeyFlag.rcontrol);
                break;
            case KeyCode.rcontrol:
                updateKeyFlags(action, KeyFlag.rcontrol, KeyFlag.lcontrol);
                break;
            case KeyCode.lalt:
                updateKeyFlags(action, KeyFlag.lalt, KeyFlag.ralt);
                break;
            case KeyCode.ralt:
                updateKeyFlags(action, KeyFlag.ralt, KeyFlag.lalt);
                break;
            case KeyCode.lwin:
                updateKeyFlags(action, KeyFlag.lmenu, KeyFlag.rmenu);
                break;
            case KeyCode.rwin:
                updateKeyFlags(action, KeyFlag.rmenu, KeyFlag.lmenu);
                break;
                //case KeyCode.WIN:
            case KeyCode.control:
            case KeyCode.shift:
            case KeyCode.alt: //case KeyCode.WIN:
                break;
            default:
                updateKeyFlags((GetKeyState(VK_LCONTROL) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.lcontrol, KeyFlag.rcontrol);
                updateKeyFlags((GetKeyState(VK_RCONTROL) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.rcontrol, KeyFlag.lcontrol);
                updateKeyFlags((GetKeyState(VK_LSHIFT) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.lshift, KeyFlag.rshift);
                updateKeyFlags((GetKeyState(VK_RSHIFT) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.rshift, KeyFlag.lshift);
                updateKeyFlags((GetKeyState(VK_LWIN) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.lmenu, KeyFlag.rmenu);
                updateKeyFlags((GetKeyState(VK_RWIN) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.rmenu, KeyFlag.lmenu);
                updateKeyFlags((GetKeyState(VK_LMENU) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.lalt, KeyFlag.ralt);
                updateKeyFlags((GetKeyState(VK_RMENU) & 0x8000) != 0 ? KeyAction.keyDown
                        : KeyAction.keyUp, KeyFlag.ralt, KeyFlag.lalt);
                //updateKeyFlags((GetKeyState(VK_LALT) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyFlag.lalt, KeyFlag.ralt);
                //updateKeyFlags((GetKeyState(VK_RALT) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyFlag.ralt, KeyFlag.lalt);
                break;
            }
            //updateKeyFlags((GetKeyState(VK_CONTROL) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyFlag.control);
            //updateKeyFlags((GetKeyState(VK_SHIFT) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyFlag.shift);
            //updateKeyFlags((GetKeyState(VK_MENU) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyFlag.alt);
            if (keyCode == 0xBF)
                keyCode = KeyCode.divide;

            debug (keys)
            {
                if (oldFlags != _keyFlags)
                {
                    Log.fd("processKeyEvent %s, flags updated: keyCode: %s, char: %s (%s), syskey: %s, _keyFlags: %04x",
                        action, keyCode, character, cast(int)character, syskey, _keyFlags);
                }
            }

            event = new KeyEvent(action, keyCode, _keyFlags);
        }
        else if (action == KeyAction.text && character != 0)
        {
            bool ctrlAZKeyCode = (character >= 1 && character <= 26);
            if ((_keyFlags & (KeyFlag.control | KeyFlag.alt)) && ctrlAZKeyCode)
            {
                event = new KeyEvent(action, KeyCode.A + character - 1, _keyFlags);
            }
            else
            {
                dchar[] text;
                text ~= character;
                uint newFlags = _keyFlags;
                if ((newFlags & KeyFlag.alt) && (newFlags & KeyFlag.control))
                {
                    newFlags &= (~(KeyFlag.lralt)) & (~(KeyFlag.lrcontrol));
                    debug (keys)
                        Log.fd("processKeyEvent, flags updated for text: keyCode: %s, char: %s (%s), syskey: %s, _keyFlags: %04x",
                            keyCode, character, cast(int)character, syskey, _keyFlags);
                }
                event = new KeyEvent(action, 0, newFlags, cast(dstring)text);
            }
        }
        bool res;
        if (event !is null)
        {
            res = dispatchKeyEvent(event);
        }
        if (res)
        {
            debug (redraw)
                Log.d("Calling update() after key event");
            update();
        }
        return res;
    }

    //===============================================================

    override protected void captureMouse(bool enabled)
    {
        debug (mouse)
            Log.d(enabled ? "Setting capture" : "Releasing capture");
        if (enabled)
            SetCapture(_hwnd);
        else
            ReleaseCapture();
    }

    override void postEvent(CustomEvent event)
    {
        super.postEvent(event);
        PostMessageW(_hwnd, CUSTOM_MESSAGE, 0, event.uniqueID);
    }

    override protected void postTimerEvent()
    {
        PostMessageW(_hwnd, TIMER_MESSAGE, 0, 0);
    }

    override protected void onTimer()
    {
        super.onTimer();
    }
}

final class Win32Platform : Platform
{
    private WindowMap!(Win32Window, HWND) windows;

    this(ref AppConf conf)
    {
        super(conf);
    }

    ~this()
    {
        destroy(windows);
        unregisterWndClass();
    }

    override int enterMessageLoop()
    {
        MSG msg;
        while (GetMessage(&msg, null, 0, 0))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            windows.purge();
        }
        return cast(int)msg.wParam;
    }

    override Window createWindow(dstring windowCaption, Window parent,
            WindowOptions options = WindowOptions.resizable | WindowOptions.expanded,
            uint width = 0, uint height = 0)
    {
        return new Win32Window(this, windowCaption, parent, options, width, height);
    }

    override void closeWindow(Window w)
    {
        Win32Window window = cast(Win32Window)w;
        SendMessage(window._hwnd, WM_CLOSE, 0, 0);
    }

    override void requestLayout()
    {
        foreach (w; windows)
        {
            w.requestLayout();
            w.invalidate();
        }
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        foreach (w; windows)
            w.dispatchThemeChanged();
    }

    override bool hasClipboardText(bool mouseBuffer = false)
    {
        if (mouseBuffer)
            return false;
        return (IsClipboardFormatAvailable(CF_UNICODETEXT) != 0);
    }

    override dstring getClipboardText(bool mouseBuffer = false)
    {
        if (mouseBuffer)
            return null; // not supported under win32
        if (!IsClipboardFormatAvailable(CF_UNICODETEXT))
            return null;
        if (!OpenClipboard(NULL))
            return null;

        dstring result;
        HGLOBAL hglb = GetClipboardData(CF_UNICODETEXT);
        if (hglb != NULL)
        {
            LPWSTR lptstr = cast(LPWSTR)GlobalLock(hglb);
            if (lptstr != NULL)
            {
                wstring w = fromWStringz(lptstr);
                result = normalizeEOLs(toUTF32(w));

                GlobalUnlock(hglb);
            }
        }

        CloseClipboard();
        return result;
    }

    override void setClipboardText(dstring text, bool mouseBuffer = false)
    {
        if (text.length < 1 || mouseBuffer)
            return;
        if (!OpenClipboard(NULL))
            return;

        EmptyClipboard();
        wstring w = toUTF16(text);
        HGLOBAL hglbCopy = GlobalAlloc(GMEM_MOVEABLE, cast(uint)((w.length + 1) * TCHAR.sizeof));
        if (hglbCopy == NULL)
        {
            CloseClipboard();
            return;
        }
        LPWSTR lptstrCopy = cast(LPWSTR)GlobalLock(hglbCopy);
        for (int i = 0; i < w.length; i++)
        {
            lptstrCopy[i] = w[i];
        }
        lptstrCopy[w.length] = 0;
        GlobalUnlock(hglbCopy);
        SetClipboardData(CF_UNICODETEXT, hglbCopy);

        CloseClipboard();
    }
}

private bool registerWndClass()
{
    WNDCLASSW wndclass;
    wndclass.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wndclass.lpfnWndProc = cast(WNDPROC)&WndProc;
    wndclass.cbClsExtra = 0;
    wndclass.cbWndExtra = 0;
    wndclass.hInstance = GetModuleHandle(null);
    wndclass.hIcon = LoadIcon(null, IDI_APPLICATION);
    wndclass.hCursor = LoadCursor(null, IDC_ARROW);
    wndclass.hbrBackground = cast(HBRUSH)GetStockObject(WHITE_BRUSH);
    wndclass.lpszMenuName = null;
    wndclass.lpszClassName = toUTF16z(WIN_CLASS_NAME);

    if (!RegisterClassW(&wndclass))
        return false;

    windowClassRegistered = true;
    return true;
}

private __gshared bool windowClassRegistered;

private void unregisterWndClass()
{
    if (windowClassRegistered)
    {
        UnregisterClassW(toUTF16z(WIN_CLASS_NAME), GetModuleHandle(null));
        windowClassRegistered = false;
    }
}

extern (C) Platform initPlatform(AppConf conf)
{
    DOUBLE_CLICK_THRESHOLD_MS = GetDoubleClickTime();

    setAppDPIAwareOnWindows();

    Log.v("Registering window class");
    if (!registerWndClass())
    {
        MessageBoxA(null, "This program requires Windows NT!", "beamui app".toStringz, MB_ICONERROR);
        return null;
    }

    static if (USE_OPENGL)
    {
        if (!initBasicOpenGL())
            disableOpenGL();
    }

    return new Win32Platform(conf);
}

extern (Windows) LRESULT WndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    auto w32platform = cast(Win32Platform)Platform.instance;

    void* p = cast(void*)GetWindowLongPtr(hwnd, GWLP_USERDATA);
    Win32Window windowParam = p ? cast(Win32Window)(p) : null;
    Win32Window window = w32platform.windows[hwnd];
    if (windowParam && window)
        assert(window is windowParam);
    if (!window && windowParam)
    {
        Log.e("Cannot find window in map by HWND");
    }

    switch (message)
    {
    case WM_CREATE:
        {
            CREATESTRUCT* pcreateStruct = cast(CREATESTRUCT*)lParam;
            window = cast(Win32Window)pcreateStruct.lpCreateParams;
            void* ptr = cast(void*)window;
            SetWindowLongPtr(hwnd, GWLP_USERDATA, cast(LONG_PTR)ptr);
            window._hwnd = hwnd;
            Log.v("created window, adding to map");
            w32platform.windows.add(window, hwnd);
        }
        return 0;
    case WM_DESTROY:
        if (window)
        {
            Log.v("destroyed window, removing from map");
            w32platform.windows.remove(window);
        }
        if (w32platform.windows.count == 0)
            PostQuitMessage(0);
        return 0;
    case WM_WINDOWPOSCHANGED:
        if (window)
        {
            if (IsIconic(hwnd))
            {
                window.handleWindowStateChange(WindowState.minimized);
            }
            else
            {
                WINDOWPOS* pos = cast(WINDOWPOS*)lParam;
                //Log.d("WM_WINDOWPOSCHANGED: ", *pos);

                RECT rect;
                GetClientRect(hwnd, &rect);
                const int w = rect.right - rect.left;
                const int h = rect.bottom - rect.top;
                WindowState state = WindowState.unspecified;
                if (IsZoomed(hwnd))
                    state = WindowState.maximized;
                else if (IsIconic(hwnd))
                    state = WindowState.minimized;
                else if (IsWindowVisible(hwnd))
                    state = WindowState.normal;
                else
                    state = WindowState.hidden;
                window.handleWindowStateChange(state, BoxI(pos.x, pos.y, w, h));
                if (window.width != w || window.height != h)
                {
                    window.updateDPI(); // TODO: WM_DPICHANGED
                    window.onResize(w, h);
                    InvalidateRect(hwnd, null, FALSE);
                }
            }
        }
        return 0;
    case WM_ACTIVATE:
        if (window)
        {
            if (wParam == WA_INACTIVE)
                window.handleWindowActivityChange(false);
            else if (wParam == WA_ACTIVE || wParam == WA_CLICKACTIVE)
                window.handleWindowActivityChange(true);
        }
        return 0;
    case WM_ERASEBKGND:
        // processed
        return 1;
    case WM_PAINT:
        if (window)
            window.onPaint();
        return 0; // processed
    case WM_SETCURSOR:
        if (window)
        {
            if (LOWORD(lParam) == HTCLIENT)
            {
                window.onSetCursorType();
                return 1;
            }
        }
        break;
    case WM_MOUSELEAVE:
    case WM_MOUSEMOVE:
    case WM_LBUTTONDOWN:
    case WM_MBUTTONDOWN:
    case WM_RBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_MBUTTONUP:
    case WM_RBUTTONUP:
    case WM_MOUSEWHEEL:
        if (window)
        {
            if (window.processMouseEvent(message, cast(uint)wParam, cast(short)(lParam & 0xFFFF),
                    cast(short)((lParam >> 16) & 0xFFFF)))
                return 0; // processed
        }
        // not processed - default handling
        return DefWindowProc(hwnd, message, wParam, lParam);
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYUP:
        if (window)
        {
            int repeatCount = lParam & 0xFFFF;
            WPARAM vk = wParam;
            WPARAM new_vk = vk;
            UINT scancode = (lParam & 0x00ff0000) >> 16;
            int extended = (lParam & 0x01000000) != 0;
            switch (vk)
            {
            case VK_SHIFT:
                new_vk = MapVirtualKey(scancode, 3); //MAPVK_VSC_TO_VK_EX
                break;
            case VK_CONTROL:
                new_vk = extended ? VK_RCONTROL : VK_LCONTROL;
                break;
            case VK_MENU:
                new_vk = extended ? VK_RMENU : VK_LMENU;
                break;
            default:
                // not a key we map from generic to left/right specialized
                //  just return it.
                new_vk = vk;
                break;
            }

            if (window.processKeyEvent(message == WM_KEYDOWN || message == WM_SYSKEYDOWN ? KeyAction.keyDown
                    : KeyAction.keyUp, cast(uint)new_vk, repeatCount, 0, message == WM_SYSKEYUP ||
                    message == WM_SYSKEYDOWN))
                return 0; // processed
        }
        break;
    case WM_UNICHAR:
        if (window)
        {
            int repeatCount = lParam & 0xFFFF;
            dchar ch = wParam == UNICODE_NOCHAR ? 0 : cast(uint)wParam;
            debug (keys)
                Log.d("WM_UNICHAR ", ch, " (", cast(int)ch, ")");
            if (window.processKeyEvent(KeyAction.text, cast(uint)wParam, repeatCount, ch))
                return 1; // processed
            return 1;
        }
        break;
    case WM_CHAR:
        if (window)
        {
            int repeatCount = lParam & 0xFFFF;
            dchar ch = wParam == UNICODE_NOCHAR ? 0 : cast(uint)wParam;
            debug (keys)
                Log.d("WM_CHAR ", ch, " (", cast(int)ch, ")");
            if (window.processKeyEvent(KeyAction.text, cast(uint)wParam, repeatCount, ch))
                return 1; // processed
            return 1;
        }
        break;
    case CUSTOM_MESSAGE:
        if (window)
            window.handlePostedEvent(cast(uint)lParam);
        return 1;
    case TIMER_MESSAGE:
        if (window)
            window.onTimer();
        return 1;
    case WM_DROPFILES:
        if (window)
        {
            HDROP hdrop = cast(HDROP)wParam;
            string[] files;
            wchar[] buf;
            auto count = DragQueryFileW(hdrop, 0xFFFFFFFF, cast(wchar*)NULL, 0);
            for (int i = 0; i < count; i++)
            {
                auto sz = DragQueryFileW(hdrop, i, cast(wchar*)NULL, 0);
                buf.length = sz + 2;
                sz = DragQueryFileW(hdrop, i, buf.ptr, sz + 1);
                files ~= toUTF8(buf[0 .. sz]);
            }
            if (files.length)
                window.handleDroppedFiles(files);
            DragFinish(hdrop);
        }
        return 0;
    case WM_CLOSE:
        if (window)
        {
            if (!window.canClose)
                return 0; // prevent closing
            //destroy(window);
        }
        // default handler inside DefWindowProc will close window
        break;
    case WM_GETMINMAXINFO:
    case WM_NCCREATE:
    case WM_NCCALCSIZE:
    default:
        //Log.d("Unhandled message ", message);
        break;
    }
    if (window)
        return window.handleUnknownWindowMessage(message, wParam, lParam);
    return DefWindowProc(hwnd, message, wParam, lParam);
}
