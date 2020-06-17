/**
Implementation of Win32 platform support

Provides Win32Window and Win32Platform classes.

Usually you don't need to use this module directly.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.windows.winapp;

version (Windows):
import beamui.core.config;

static if (BACKEND_GUI):
import core.runtime;
import core.sys.windows.shellapi;
import core.sys.windows.winbase;
import core.sys.windows.windef;
import core.sys.windows.wingdi;
import core.sys.windows.winuser;
import std.string : toStringz;
import std.utf : toUTF16, toUTF16z;

import beamui.core.functions;
import beamui.core.geometry;
import beamui.core.logger;
import beamui.core.signals;
import beamui.events.event;
import beamui.events.keyboard;
import beamui.events.pointer;
import beamui.events.wheel;
import beamui.graphics.bitmap;
import beamui.graphics.images;
import beamui.graphics.painter : PaintEngine;
import beamui.graphics.swpainter;
import beamui.platforms.common.platform;
import beamui.platforms.common.startup;
import beamui.platforms.windows.win32bitmap;
import beamui.platforms.windows.win32fonts;

pragma(lib, "gdi32.lib");
pragma(lib, "user32.lib");

immutable WIN_CLASS_NAME = "BEAMUI_APP";

static if (USE_OPENGL)
{
    bool setupPixelFormat(HDC device)
    {
        PIXELFORMATDESCRIPTOR pfd = {
            PIXELFORMATDESCRIPTOR.sizeof, // size
            1,  // version
            PFD_SUPPORT_OPENGL | PFD_DRAW_TO_WINDOW | PFD_DOUBLEBUFFER, // support double-buffering
            PFD_TYPE_RGBA, // color type
            16, // prefered color depth
            0, 0, 0, 0, 0, 0, // color bits (ignored)
            0,  // no alpha buffer
            0,  // alpha bits (ignored)
            0,  // no accumulation buffer
            0, 0, 0, 0, // accum bits (ignored)
            24, // depth buffer
            8,  // stencil buffer
            0,  // no auxiliary buffers
            0,  // main layer PFD_MAIN_PLANE
            0,  // reserved
            0, 0, 0, // no layer, visible, damage masks
        };
        return SetPixelFormat(device, ChoosePixelFormat(device, &pfd), &pfd) == TRUE;
    }

    HPALETTE setupPalette(HDC device)
    {
        import core.stdc.stdlib : malloc, free;

        PIXELFORMATDESCRIPTOR pfd;
        DescribePixelFormat(device, GetPixelFormat(device), pfd.sizeof, &pfd);

        int paletteSize;
        if (pfd.dwFlags & PFD_NEED_PALETTE)
        {
            paletteSize = 1 << pfd.cColorBits;
        }
        else
            return null;

        LOGPALETTE* pPal = cast(LOGPALETTE*)malloc(LOGPALETTE.sizeof + paletteSize * PALETTEENTRY.sizeof);
        pPal.palVersion = 0x300;
        pPal.palNumEntries = cast(ushort)paletteSize;

        // build a simple RGB color palette
        {
            const redMask = (1 << pfd.cRedBits) - 1;
            const greenMask = (1 << pfd.cGreenBits) - 1;
            const blueMask = (1 << pfd.cBlueBits) - 1;
            foreach (i; 0 .. paletteSize)
            {
                pPal.palPalEntry[i].peRed = cast(ubyte)((((i >> pfd.cRedShift) & redMask) * 255) / redMask);
                pPal.palPalEntry[i].peGreen = cast(ubyte)((((i >> pfd.cGreenShift) & greenMask) * 255) / greenMask);
                pPal.palPalEntry[i].peBlue = cast(ubyte)((((i >> pfd.cBlueShift) & blueMask) * 255) / blueMask);
                pPal.palPalEntry[i].peFlags = 0;
            }
        }

        HPALETTE palette = CreatePalette(pPal);
        free(pPal);

        if (palette)
        {
            SelectPalette(device, palette, FALSE);
            RealizePalette(device);
        }

        return palette;
    }

    /// Shared opengl context helper
    struct SharedGLContext
    {
        import wgl;

        private HGLRC _context;
        private HPALETTE _palette;

        /// Init OpenGL context, if not yet initialized
        bool initialize(HDC device, int major, int minor)
        {
            if (!setupPixelFormat(device))
            {
                Log.e("WGL: failed to setup pixel format");
                return false;
            }
            if (_context)
                return true;

            // first initialization
            _palette = setupPalette(device);
            HGLRC dummy = wglCreateContext(device);
            if (dummy)
            {
                if (wglMakeCurrent(device, dummy))
                {
                    loadWGLExtensions();
                    if (WGL_ARB_create_context)
                    {
                        const int[] attribs = [
                            WGL_CONTEXT_MAJOR_VERSION_ARB, major,
                            WGL_CONTEXT_MINOR_VERSION_ARB, minor,
                            WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
                            0 // end
                        ];
                        _context = wglCreateContextAttribsARB(device, null, attribs.ptr);
                    }
                    wglMakeCurrent(device, null);
                }
                wglDeleteContext(dummy);
            }
            return _context !is null;
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
                Log.fe("WGL: failed to make context current, err: %x", GetLastError());
            }
        }
        /// Make null context current for DC
        void unbind(HDC device)
        {
            wglMakeCurrent(device, null);
        }
    }

    /// OpenGL context to share between windows
    __gshared SharedGLContext sharedGLContext;
}

const uint CUSTOM_MESSAGE = WM_USER + 1;
const uint TIMER_MESSAGE = WM_USER + 2;

/// Returns true if message is handled, put return value into result
alias UnknownWindowMessageHandler =
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

        PaintEngine _paintEngine;
        Bitmap _backbuffer;
        Win32BitmapData _backbufferData;

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

        width = max(w, 1);
        height = max(h, 1);

        uint ws = WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
        if (options & WindowOptions.resizable)
            ws |= WS_OVERLAPPEDWINDOW;
        else
            ws |= WS_OVERLAPPED | WS_CAPTION | WS_CAPTION | WS_BORDER | WS_SYSMENU;

        const BoxI screenRc = getScreenDimensions();
        Log.d("Screen dimensions: ", screenRc);

        int x = CW_USEDEFAULT;
        int y = CW_USEDEFAULT;

        if (options & WindowOptions.fullscreen)
        {
            // fullscreen
            x = screenRc.x;
            y = screenRc.y;
            width = screenRc.w;
            height = screenRc.h;
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
            _platform.createGLContext(this);
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
        if (_hwnd)
        {
            DestroyWindow(_hwnd);
            _hwnd = null;
        }
    }

    override protected void cleanup()
    {
        _destroying = true;

        static if (USE_OPENGL)
            bindContext(); // required to correctly destroy GL objects
        eliminate(_paintEngine);
        _backbufferData = null;
        _backbuffer = Bitmap.init;
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

    override @property void onFileDrop(void delegate(string[]) handler)
    {
        DragAcceptFiles(_hwnd, handler ? TRUE : FALSE);
        super.onFileDrop(handler);
    }

    /// Custom window message handler
    Signal!UnknownWindowMessageHandler onUnknownWindowMessage;

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
                    const bsz = getBorderSize();
                    const w = newWindowRect.w + bsz.w;
                    const h = newWindowRect.h + bsz.h;
                    SetWindowPos(_hwnd, NULL, 0, 0, w, h, flags | SWP_NOMOVE);
                    rectChanged = true;
                    res = true;
                }
            }
            else
            {
                if (newWindowRect.w != int.min && newWindowRect.h != int.min)
                {
                    // change size and position
                    const bsz = getBorderSize();
                    const w = newWindowRect.w + bsz.w;
                    const h = newWindowRect.h + bsz.h;
                    SetWindowPos(_hwnd, NULL, newWindowRect.x, newWindowRect.y, w, h, flags);
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

    private SizeI getBorderSize()
    {
        RECT wr, cr;
        GetWindowRect(_hwnd, &wr);
        GetClientRect(_hwnd, &cr);
        const w = (wr.right - wr.left) - (cr.right - cr.left);
        const h = (wr.bottom - wr.top) - (cr.bottom - cr.top);
        return SizeI(w, h);
    }

    override protected void handleSizeHintsChange()
    {
        const r = windowRect;
        const flags = SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOZORDER;
        SetWindowPos(_hwnd, NULL, 0, 0, r.w, r.h, flags);
    }

    override @property bool isActive() const
    {
        return _hwnd == GetForegroundWindow();
    }

    // make them visible for WndProc
    override protected void handleResize(int width, int height)
    {
        super.handleResize(width, height);
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

    override @property void icon(Bitmap ic)
    {
        if (_icon)
            DestroyIcon(_icon);
        _icon = null;
        if (!ic)
        {
            Log.e("Trying to set null icon for window");
            return;
        }
        auto resizedicon = new Win32BitmapData(32, 32);
        auto bm = Bitmap(resizedicon);
        bm.blit(ic, RectI(0, 0, ic.width, ic.height), RectI(0, 0, 32, 32));
        ICONINFO ii;
        HBITMAP mask = resizedicon.createTransparencyBitmap();
        HBITMAP color = resizedicon.extractBitmap();
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

    override protected void show()
    {
        ReleaseCapture();

        adjustSize();
        adjustPosition();

        if (options & WindowOptions.fullscreen)
        {
            const BoxI rc = getScreenDimensions();
            SetWindowPos(_hwnd, HWND_TOPMOST, 0, 0, rc.w, rc.h, SWP_SHOWWINDOW);
            _windowState = WindowState.fullscreen;
        }
        else
        {
            ShowWindow(_hwnd, SW_SHOWNORMAL);
            _windowState = WindowState.normal;
        }

        SetFocus(_hwnd);
        //UpdateWindow(_hwnd);

        update();
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

    private CursorType _cursorType;
    private HANDLE[CursorType] _cursorCache;

    override protected void setCursorType(CursorType type)
    {
        _cursorType = type;

        HANDLE h;
        if (auto p = type in _cursorCache)
        {
            h = *p;
        }
        else
        {
            const id = convertCursorType(type);
            if (id)
                h = LoadCursor(null, MAKEINTRESOURCE(id));
            _cursorCache[type] = h;
        }
        SetCursor(h);
    }

    static private ushort convertCursorType(CursorType type)
    {
        switch (type) with (CursorType)
        {
        case none:
            return 0;
        case pointer:
        case grab:
            return IDC_HAND;
        case help:
            return IDC_HELP;
        case progress:
            return IDC_APPSTARTING;
        case wait:
            return IDC_WAIT;
        case crosshair:
            return IDC_CROSS;
        case text:
        case textVertical:
            return IDC_IBEAM;
        case move:
        case scrollAll:
            return IDC_SIZEALL;
        case noDrop:
        case notAllowed:
            return IDC_NO;
        case resizeE:
        case resizeW:
        case resizeEW:
        case resizeCol:
            return IDC_SIZEWE;
        case resizeN:
        case resizeS:
        case resizeNS:
        case resizeRow:
            return IDC_SIZENS;
        case resizeNE:
        case resizeSW:
        case resizeNESW:
            return IDC_SIZENESW;
        case resizeNW:
        case resizeSE:
        case resizeNWSE:
            return IDC_SIZENWSE;
        default:
            return IDC_ARROW;
        }
    }

    private void updateDPI()
    {
        HDC device = GetDC(_hwnd);
        const dpi = GetDeviceCaps(device, LOGPIXELSY);
        setDPI(dpi, 1); // TODO
    }

    private void paint()
    {
        debug (redraw)
            const paintStart = currentTimeMillis;

        if (openglEnabled)
        {
            static if (USE_OPENGL)
                paintUsingOpenGL();
        }
        else
            paintUsingGDI();

        debug (redraw)
        {
            const paintEnd = currentTimeMillis;
            Log.d("WM_PAINT handling took ", paintEnd - paintStart, " ms");
        }
    }

    private void paintUsingGDI()
    {
        PAINTSTRUCT ps;
        HDC device = BeginPaint(_hwnd, &ps);
        scope (exit)
            EndPaint(_hwnd, &ps);

        if (!_paintEngine)
        {
            // create stuff on the first run
            _backbufferData = new Win32BitmapData(1, 1);
            _backbuffer = Bitmap(_backbufferData);
            _paintEngine = new SWPaintEngine(_backbuffer);
        }
        draw(_paintEngine);

        _backbufferData.drawTo(device);
    }

    static if (USE_OPENGL)
    {
        import wgl;

        override protected bool createContext(int major, int minor)
        {
            HDC device = GetDC(_hwnd);
            return sharedGLContext.initialize(device, major, minor);
        }

        override protected void destroyContext()
        {
            // no action needed
        }

        override protected void handleGLReadiness()
        {
            disableVSync();
        }

        private void disableVSync()
        {
            if (WGL_EXT_swap_control)
                wglSwapIntervalEXT(0);
        }

        override protected void bindContext()
        {
            HDC device = GetDC(_hwnd);
            sharedGLContext.bind(device);
        }

        override protected void swapBuffers()
        {
            HDC device = GetDC(_hwnd);
            SwapBuffers(device);
        }

        private void paintUsingOpenGL()
        {
            // hack to stop infinite WM_PAINT loop
            PAINTSTRUCT ps;
            HDC hdc2 = BeginPaint(_hwnd, &ps);
            EndPaint(_hwnd, &ps); // FIXME: scope(exit)?

            drawUsingOpenGL(_paintEngine);
        }
    }

    //===============================================================

    private ButtonDetails _lbutton;
    private ButtonDetails _mbutton;
    private ButtonDetails _rbutton;

    private void updateButtonsState(uint winFlags)
    {
        if (!(winFlags & MK_LBUTTON) && _lbutton.isDown)
            _lbutton.reset();
        if (!(winFlags & MK_MBUTTON) && _mbutton.isDown)
            _mbutton.reset();
        if (!(winFlags & MK_RBUTTON) && _rbutton.isDown)
            _rbutton.reset();
    }

    private MouseMods convertMouseMods(uint winFlags)
    {
        MouseMods mods;
        if (winFlags & MK_LBUTTON)
            mods |= MouseMods.left;
        if (winFlags & MK_RBUTTON)
            mods |= MouseMods.right;
        if (winFlags & MK_MBUTTON)
            mods |= MouseMods.middle;
        if (winFlags & MK_XBUTTON1)
            mods |= MouseMods.xbutton1;
        if (winFlags & MK_XBUTTON2)
            mods |= MouseMods.xbutton2;
        return mods;
    }

    private KeyMods _keyMods;

    private void processMouseEvent(uint winMessage, uint winFlags, short x, short y)
    {
        debug (mouse)
            Log.d("Win32 Mouse Message ", winMessage, ", flags: ", winFlags, ", x: ", x, ", y: ", y);

        MouseAction action = MouseAction.buttonDown;
        MouseButton button;
        ButtonDetails* pbuttonDetails;
        switch (winMessage)
        {
        case WM_MOUSEMOVE:
            action = MouseAction.move;
            updateButtonsState(winFlags);
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
        default: // unsupported event
            return;
        }

        const mmods = convertMouseMods(winFlags);

        if (action == MouseAction.buttonDown)
        {
            pbuttonDetails.down(x, y, mmods, _keyMods);
        }
        else if (action == MouseAction.buttonUp)
        {
            pbuttonDetails.up(x, y, mmods, _keyMods);
        }

        auto event = new MouseEvent(action, button, mmods, _keyMods, x, y);
        event.lbutton = _lbutton;
        event.rbutton = _rbutton;
        event.mbutton = _mbutton;

        dispatchMouseEvent(event);
        update();
    }

    private void processWheelEvent(uint winFlags, POINT pt, int deltaX, int deltaY)
    {
        if (deltaX != 0 || deltaY != 0)
        {
            ScreenToClient(_hwnd, &pt);
            const x = cast(short)pt.x;
            const y = cast(short)pt.y;
            const mmods = convertMouseMods(winFlags);
            const dx = cast(short)deltaX;
            const dy = cast(short)deltaY;
            auto event = new WheelEvent(x, y, mmods, _keyMods, dx, dy);
            dispatchWheelEvent(event);
            update();
        }
    }

    private void updateKeyMods(KeyAction action, KeyMods mod, KeyMods preserve)
    {
        if (action == KeyAction.keyDown)
            _keyMods |= mod;
        else
        {
            if (preserve && (_keyMods & preserve) == preserve)
                // e.g. when both lctrl and rctrl are pressed, and lctrl is up, preserve rctrl mod
                _keyMods = (_keyMods & ~mod) | preserve;
            else
                _keyMods &= ~mod;
        }
    }

    private void processKeyEvent(KeyAction action, uint winKeyCode, int repeatCount, bool syskey = false)
    {
        debug (keys)
            Log.fd("processKeyEvent %s, keyCode: %s, syskey: %s, mods: %s",
                action, winKeyCode, syskey, _keyMods);

        Key key = cast(Key)winKeyCode;
        if (winKeyCode == 0xBF)
            key = Key.divide;

        if (syskey)
            _keyMods |= KeyMods.alt;

        switch (key)
        {
        case Key.lshift:
            updateKeyMods(action, KeyMods.lshift, KeyMods.rshift);
            break;
        case Key.rshift:
            updateKeyMods(action, KeyMods.rshift, KeyMods.lshift);
            break;
        case Key.lcontrol:
            updateKeyMods(action, KeyMods.lcontrol, KeyMods.rcontrol);
            break;
        case Key.rcontrol:
            updateKeyMods(action, KeyMods.rcontrol, KeyMods.lcontrol);
            break;
        case Key.lalt:
            updateKeyMods(action, KeyMods.lalt, KeyMods.ralt);
            break;
        case Key.ralt:
            updateKeyMods(action, KeyMods.ralt, KeyMods.lalt);
            break;
        case Key.lwin:
            updateKeyMods(action, KeyMods.lmeta, KeyMods.rmeta);
            break;
        case Key.rwin:
            updateKeyMods(action, KeyMods.rmeta, KeyMods.lmeta);
            break;
        case Key.control:
        case Key.shift:
        case Key.alt:
            break;
        default:
            updateKeyMods((GetKeyState(VK_LCONTROL) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.lcontrol, KeyMods.rcontrol);
            updateKeyMods((GetKeyState(VK_RCONTROL) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.rcontrol, KeyMods.lcontrol);
            updateKeyMods((GetKeyState(VK_LSHIFT) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.lshift, KeyMods.rshift);
            updateKeyMods((GetKeyState(VK_RSHIFT) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.rshift, KeyMods.lshift);
            updateKeyMods((GetKeyState(VK_LWIN) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.lmeta, KeyMods.rmeta);
            updateKeyMods((GetKeyState(VK_RWIN) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.rmeta, KeyMods.lmeta);
            updateKeyMods((GetKeyState(VK_LMENU) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.lalt, KeyMods.ralt);
            updateKeyMods((GetKeyState(VK_RMENU) & 0x8000) != 0 ? KeyAction.keyDown
                    : KeyAction.keyUp, KeyMods.ralt, KeyMods.lalt);
            //updateKeyMods((GetKeyState(VK_LALT) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyMods.lalt, KeyMods.ralt);
            //updateKeyMods((GetKeyState(VK_RALT) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyMods.ralt, KeyMods.lalt);
            break;
        }
        //updateKeyMods((GetKeyState(VK_CONTROL) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyMods.control);
        //updateKeyMods((GetKeyState(VK_SHIFT) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyMods.shift);
        //updateKeyMods((GetKeyState(VK_MENU) & 0x8000) != 0 ? KeyAction.keyDown : KeyAction.keyUp, KeyMods.alt);

        debug (keys)
            Log.fd("converted, action: %s, key: %s, syskey: %s, mods: %s",
                action, key, syskey, _keyMods);

        dispatchKeyEvent(new KeyEvent(action, key, _keyMods));
        update();
    }

    private void processTextInput(dchar ch, int repeatCount)
    {
        assert(ch != 0);

        debug (keys)
            Log.fd("processTextInput char: %s (%s)", ch, cast(int)ch);

        KeyEvent event;
        const bool ctrlAZKeyCode = 1 <= ch && ch <= 26;
        if (ctrlAZKeyCode && (_keyMods & (KeyMods.control | KeyMods.alt)) != 0)
        {
            event = new KeyEvent(KeyAction.text, cast(Key)(Key.A + ch - 1), _keyMods);
        }
        else
        {
            dchar[] text;
            text ~= ch;
            KeyMods mods = _keyMods;
            if ((mods & KeyMods.alt) && (mods & KeyMods.control))
            {
                mods &= (~(KeyMods.lralt)) & (~(KeyMods.lrcontrol));
                debug (keys)
                    Log.fd("processKeyEvent, removed Ctrl+Alt mods, char: %s (%s), mods: %s",
                        ch, cast(int)ch, mods);
            }
            if (mods & KeyMods.control || (mods & KeyMods.lalt) == KeyMods.lalt || mods & KeyMods.meta)
                return;

            event = new KeyEvent(KeyAction.text, Key.none, mods, cast(dstring)text);
        }

        dispatchKeyEvent(event);
        update();
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

    override protected void handleTimer()
    {
        super.handleTimer();
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
        deinitializeWin32Backend();
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

    override protected int opApply(scope int delegate(size_t i, Window w) callback)
    {
        foreach (i, w; windows)
            if (const result = callback(i, w))
                break;
        return 0;
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
        static import wgl;

        if (!wgl.loadWGL())
            disableOpenGL();
    }

    return new Win32Platform(conf);
}

private void deinitializeWin32Backend()
{
    static if (USE_OPENGL)
    {
        sharedGLContext.uninit();
    }

    if (windowClassRegistered)
    {
        UnregisterClassW(toUTF16z(WIN_CLASS_NAME), GetModuleHandle(null));
        windowClassRegistered = false;
    }
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

    // related documentation:
    // https://msdn.microsoft.com/en-us/library/windows/desktop/ms633573(v=vs.85).aspx
    // https://docs.microsoft.com/en-us/windows/desktop/winmsg/about-messages-and-message-queues

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
                    window.handleResize(w, h);
                    InvalidateRect(hwnd, null, FALSE);
                }
            }
        }
        return 0;
    case WM_GETMINMAXINFO:
        if (window)
        {
            const bsz = window.getBorderSize();
            MINMAXINFO* info = cast(MINMAXINFO*)lParam;
            info.ptMinTrackSize.x = window.minSize.w + bsz.w;
            info.ptMinTrackSize.y = window.minSize.h + bsz.h;
            info.ptMaxTrackSize.x = window.maxSize.w + bsz.w;
            info.ptMaxTrackSize.y = window.maxSize.h + bsz.h;
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
        return 1; // processed
    case WM_PAINT:
        if (window)
            window.paint();
        return 0; // processed
    case WM_SETCURSOR:
        if (window)
        {
            if (LOWORD(lParam) == HTCLIENT)
            {
                window.setCursorType(window._cursorType);
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
        if (window)
        {
            window.processMouseEvent(message, cast(uint)wParam, cast(short)(lParam & 0xFFFF),
                cast(short)((lParam >> 16) & 0xFFFF));
            return 0; // processed
        }
        break;
    case WM_MOUSEWHEEL:
        if (window)
        {
            const pt = POINT(lParam & 0xFFFF, (lParam >> 16) & 0xFFFF);
            const delta = (cast(short)(wParam >> 16)) / 120;
            window.processWheelEvent(cast(uint)wParam, pt, 0, -delta);
            return 0;
        }
        break;
    case 0x020E: // WM_MOUSEHWHEEL
        if (window)
        {
            const pt = POINT(lParam & 0xFFFF, (lParam >> 16) & 0xFFFF);
            const delta = (cast(short)(wParam >> 16)) / 120;
            window.processWheelEvent(cast(uint)wParam, pt, delta, 0);
            return 0;
        }
        break;
    case WM_KEYDOWN:
    case WM_SYSKEYDOWN:
    case WM_KEYUP:
    case WM_SYSKEYUP:
        if (window)
        {
            const int repeatCount = lParam & 0xFFFF;
            const WPARAM vk = wParam;
            WPARAM new_vk = vk;
            const UINT scancode = (lParam & 0x00ff0000) >> 16;
            const int extended = (lParam & 0x01000000) != 0;
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

            KeyAction action;
            if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN)
                action = KeyAction.keyDown;
            else
                action = KeyAction.keyUp;
            window.processKeyEvent(action, cast(uint)new_vk, repeatCount,
                message == WM_SYSKEYUP || message == WM_SYSKEYDOWN);
            return 0; // processed
        }
        break;
    case WM_UNICHAR:
        if (window)
        {
            int repeatCount = lParam & 0xFFFF;
            dchar ch = wParam == UNICODE_NOCHAR ? 0 : cast(dchar)wParam;
            debug (keys)
                Log.d("WM_UNICHAR ", ch, " (", cast(int)ch, ")");
            if (ch)
            {
                window.processTextInput(ch, repeatCount);
                return 0; // processed
            }
        }
        break;
    case WM_CHAR:
        if (window)
        {
            int repeatCount = lParam & 0xFFFF;
            dchar ch = wParam == UNICODE_NOCHAR ? 0 : cast(dchar)wParam;
            debug (keys)
                Log.d("WM_CHAR ", ch, " (", cast(int)ch, ")");
            if (ch)
            {
                window.processTextInput(ch, repeatCount);
                return 0; // processed
            }
        }
        break;
    case CUSTOM_MESSAGE:
        if (window)
            window.handlePostedEvent(cast(uint)lParam);
        return 1;
    case TIMER_MESSAGE:
        if (window)
            window.handleTimer();
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
            return 0;
        }
        break;
    case WM_CLOSE:
        if (window)
        {
            if (!window.canClose)
                return 0; // prevent closing
        }
        // default handler inside DefWindowProc will close the window
        break;
    case WM_NCCREATE:
    case WM_NCCALCSIZE:
    default:
        //Log.d("Unhandled message ", message);
        break;
    }

    if (window)
        return window.handleUnknownWindowMessage(message, wParam, lParam);
    else
        return DefWindowProc(hwnd, message, wParam, lParam);
}
