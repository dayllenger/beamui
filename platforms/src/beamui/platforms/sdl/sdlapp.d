/**
Implementation of SDL2 based backend for the UI.

Copyright: Vadim Lopatin 2014-2017, Roman Chistokhodov 2016-2017, Andrzej Kilijański 2017-2018, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, Andrzej Kilijański
*/
module beamui.platforms.sdl.sdlapp;

import beamui.core.config;

static if (BACKEND_GUI):
import std.string : fromStringz, toStringz;
import std.utf : toUTF32;
import bindbc.sdl;
import beamui.core.events;
import beamui.core.functions;
import beamui.core.geometry;
import beamui.core.logger;
import beamui.graphics.bitmap;
import beamui.graphics.colors : Color;
import beamui.graphics.painter : PaintEngine;
import beamui.graphics.swpainter;
import beamui.platforms.common.platform;
import beamui.platforms.common.startup;
import beamui.text.fonts;
import beamui.text.ftfonts;
version (Windows)
{
    import core.sys.windows.windows;

    pragma(lib, "gdi32.lib");
    pragma(lib, "user32.lib");
}

private __gshared SDL_EventType USER_EVENT_ID;
private __gshared SDL_EventType TIMER_EVENT_ID;
private __gshared SDL_EventType WINDOW_CLOSE_EVENT_ID;

final class SDLWindow : Window
{
    @property uint windowID()
    {
        return _win ? SDL_GetWindowID(_win) : 0;
    }

    private
    {
        SDLPlatform _platform;

        SDL_Window* _win;
        SDL_Renderer* _renderer;

        dstring _title;

        PaintEngine _paintEngine;
        Bitmap _backbuffer;
    }

    this(SDLPlatform platform, dstring caption, Window parent, WindowOptions options, uint w = 0, uint h = 0)
    {
        super(parent, options);
        _platform = platform;
        _title = caption;
        _windowState = WindowState.hidden;

        if (parent)
            parent.addModalChild(this);

        width = w > 0 ? w : 500;
        height = h > 0 ? h : 300;

        create();

        if (platform.defaultWindowIcon.length != 0)
            this.icon = imageCache.get(platform.defaultWindowIcon);
    }

    ~this()
    {
        if (_renderer)
            SDL_DestroyRenderer(_renderer);
        if (_win)
            SDL_DestroyWindow(_win);
    }

    override protected void cleanup()
    {
        static if (USE_OPENGL)
            bindContext(); // required to correctly destroy GL objects
        eliminate(_paintEngine);
        _backbuffer = Bitmap.init;
    }

    private bool create()
    {
        debug Log.d("Creating SDL window of size ", width, "x", height);

        SDL_WindowFlags sdlWindowFlags = SDL_WINDOW_HIDDEN;
        if (options & WindowOptions.resizable)
            sdlWindowFlags |= SDL_WINDOW_RESIZABLE;
        if (options & WindowOptions.fullscreen)
            sdlWindowFlags |= SDL_WINDOW_FULLSCREEN;
        if (options & WindowOptions.borderless)
            sdlWindowFlags = SDL_WINDOW_BORDERLESS;
        sdlWindowFlags |= SDL_WINDOW_ALLOW_HIGHDPI;
        static if (USE_OPENGL)
        {
            if (openglEnabled)
                sdlWindowFlags |= SDL_WINDOW_OPENGL;
        }
        _win = SDL_CreateWindow(toUTF8(_title).toStringz, SDL_WINDOWPOS_UNDEFINED,
                SDL_WINDOWPOS_UNDEFINED, width, height, sdlWindowFlags);
        static if (USE_OPENGL)
        {
            if (!_win && openglEnabled)
            {
                Log.e("SDL_CreateWindow failed - cannot create OpenGL window: ", fromStringz(SDL_GetError()));
                disableOpenGL();
                // recreate w/o OpenGL
                sdlWindowFlags &= ~SDL_WINDOW_OPENGL;
                _win = SDL_CreateWindow(toUTF8(_title).toStringz, SDL_WINDOWPOS_UNDEFINED,
                        SDL_WINDOWPOS_UNDEFINED, width, height, sdlWindowFlags);
            }
        }
        if (!_win)
        {
            Log.e("SDL2: Failed to create window: ", fromStringz(SDL_GetError()));
            return false;
        }

        static if (USE_OPENGL)
        {
            _platform.createGLContext(this);
        }
        if (!openglEnabled)
        {
            _renderer = SDL_CreateRenderer(_win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
            if (!_renderer)
            {
                _renderer = SDL_CreateRenderer(_win, -1, SDL_RENDERER_SOFTWARE);
                if (!_renderer)
                {
                    Log.e("SDL2: Failed to create renderer");
                    return false;
                }
            }
        }

        updateDPI();
        fixSize();
        title = _title;
        int x = 0;
        int y = 0;
        SDL_GetWindowPosition(_win, &x, &y);
        handleWindowStateChange(WindowState.unspecified, BoxI(x, y, width, height));
        return true;
    }

    private void fixSize()
    {
        int w = 0;
        int h = 0;
        SDL_GetWindowSize(_win, &w, &h);
        handleResize(w, h);
    }

    override protected void handleWindowStateChange(WindowState newState, BoxI newWindowRect = BoxI.none)
    {
        super.handleWindowStateChange(newState, newWindowRect);
    }

    override bool setWindowState(WindowState newState, bool activate = false, BoxI newWindowRect = BoxI.none)
    {
        if (_win is null)
            return false;

        bool res = false;

        // change state
        switch (newState)
        {
        case WindowState.maximized:
            if (_windowState != WindowState.maximized)
                SDL_MaximizeWindow(_win);
            res = true;
            break;
        case WindowState.minimized:
            if (_windowState != WindowState.minimized)
                SDL_MinimizeWindow(_win);
            res = true;
            break;
        case WindowState.hidden:
            if (_windowState != WindowState.hidden)
                SDL_HideWindow(_win);
            res = true;
            break;
        case WindowState.normal:
            if (_windowState != WindowState.normal)
            {
                SDL_RestoreWindow(_win);
                version (linux)
                {
                    // On linux with Cinnamon desktop, changing window state from for example minimized reset windows size
                    // and/or position to values from create window (last tested on Cinamon 3.4.6 with SDL 2.0.4)
                    //
                    // Steps to reproduce:
                    // Need app with two windows - dlangide for example.
                    // 1. Comment this fix
                    // 2. dub run --force
                    // 3. After first window appear move it and/or change window size
                    // 4. Click on button to open file
                    // 5. Click on window icon minimize in open file dialog
                    // 6. Restore window clicking on taskbar
                    // 7. The first main window has old position/size
                    // Xfce works OK without this fix
                    if (newWindowRect.w == int.min && newWindowRect.h == int.min)
                        SDL_SetWindowSize(_win, _windowRect.w, _windowRect.h);

                    if (newWindowRect.x == int.min && newWindowRect.y == int.min)
                        SDL_SetWindowPosition(_win, _windowRect.x, _windowRect.y);
                }
            }
            res = true;
            break;
        default:
            break;
        }

        // change size and/or position
        bool rectChanged = false;
        if (newWindowRect != BoxI.none && (newState == WindowState.normal ||
                newState == WindowState.unspecified))
        {
            // change position
            if (newWindowRect.x != int.min && newWindowRect.y != int.min)
            {
                SDL_SetWindowPosition(_win, newWindowRect.x, newWindowRect.y);
                rectChanged = true;
                res = true;
            }

            // change size
            if (newWindowRect.w != int.min && newWindowRect.h != int.min)
            {
                SDL_SetWindowSize(_win, newWindowRect.w, newWindowRect.h);
                rectChanged = true;
                res = true;
            }
        }

        if (activate)
        {
            SDL_RaiseWindow(_win);
            res = true;
        }

        //needed here to make _windowRect and _windowState valid before SDL_WINDOWEVENT_RESIZED/SDL_WINDOWEVENT_MOVED/SDL_WINDOWEVENT_MINIMIZED/SDL_WINDOWEVENT_MAXIMIZED etc handled
        //example: change size by resizeWindow() and make some calculations using windowRect
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

    override protected void handleSizeHintsChange()
    {
        const mn = minSize;
        SizeI mx = maxSize;
        // FIXME: SDL does not allow equal sizes for some reason
        if (mn.w == mx.w)
            mx.w++;
        if (mn.h == mx.h)
            mx.h++;
        SDL_SetWindowMinimumSize(_win, mn.w, mn.h);
        SDL_SetWindowMaximumSize(_win, mx.w, mx.h);
    }

    override @property bool isActive() const
    {
        uint flags = SDL_GetWindowFlags(cast(SDL_Window*)_win);
        return (flags & SDL_WINDOW_INPUT_FOCUS) == SDL_WINDOW_INPUT_FOCUS;
    }

    override protected void handleWindowActivityChange(bool isWindowActive)
    {
        super.handleWindowActivityChange(isWindowActive);
    }

    //===============================================================

    override @property dstring title() const { return _title; }

    override @property void title(dstring caption)
    {
        _title = caption;
        if (_win)
            SDL_SetWindowTitle(_win, toUTF8(caption).toStringz);
    }

    override @property void icon(Bitmap ic)
    {
        if (!ic)
        {
            Log.e("Trying to set null icon for window");
            return;
        }
        const int iconw = 32;
        const int iconh = 32;
        auto iconDraw = Bitmap(iconw, iconh, PixelFormat.argb8);
        iconDraw.blit(ic, RectI(0, 0, ic.width, ic.height), RectI(0, 0, iconw, iconh));
        iconDraw.preMultiplyAlpha();
        SDL_Surface* surface = SDL_CreateRGBSurfaceFrom(
            cast(void*)iconDraw.pixels!uint,
            iconDraw.width, iconDraw.height,
            32, cast(int)iconDraw.rowBytes,
            0x00ff0000, 0x0000ff00, 0x000000ff, 0xff000000,
        );
        if (surface)
        {
            // The icon is attached to the window pointer
            SDL_SetWindowIcon(_win, surface);
            // ...and the surface containing the icon pixel data is no longer required.
            SDL_FreeSurface(surface);
        }
        else
        {
            Log.e("failed to set window icon");
        }
    }

    override protected void show()
    {
        Log.d("SDLWindow.show - ", title);

        adjustSize();
        adjustPosition();

        SDL_ShowWindow(_win);
        fixSize();
        SDL_RaiseWindow(_win);
        invalidate();
    }

    private uint _lastRedrawEventCode;

    override void invalidate()
    {
        _platform.sendRedrawEvent(windowID, ++_lastRedrawEventCode);
    }

    override void close()
    {
        _platform.closeWindow(this);
    }

    //===============================================================

    private void processRedrawEvent(uint code)
    {
        if (code == _lastRedrawEventCode)
            redraw();
    }

    private CursorType _lastCursorType = CursorType.automatic;
    private SDL_Cursor*[CursorType] _cursorCache;

    override protected void setCursorType(CursorType type)
    {
        if (_lastCursorType == type)
            return;

        debug (sdl)
            Log.d("SDL: changing cursor to ", type);

        if (type == CursorType.none)
        {
            SDL_ShowCursor(SDL_DISABLE);
            _lastCursorType = CursorType.none;
            return;
        }
        if (_lastCursorType == CursorType.none)
            SDL_ShowCursor(SDL_ENABLE);

        SDL_Cursor* cursor;
        // check for existing cursor in map
        if (auto p = type in _cursorCache)
        {
            cursor = *p;
        }
        else
        {
            // create new one
            cursor = SDL_CreateSystemCursor(convertCursorType(type));
            _cursorCache[type] = cursor;
        }
        if (cursor)
            SDL_SetCursor(cursor);

        _lastCursorType = type;
    }

    static private SDL_SystemCursor convertCursorType(CursorType type)
    {
        switch (type) with (CursorType)
        {
        case pointer:
        case grab:
            return SDL_SYSTEM_CURSOR_HAND;
        case progress:
            return SDL_SYSTEM_CURSOR_WAITARROW;
        case wait:
            return SDL_SYSTEM_CURSOR_WAIT;
        case crosshair:
            return SDL_SYSTEM_CURSOR_CROSSHAIR;
        case text:
        case textVertical:
            return SDL_SYSTEM_CURSOR_IBEAM;
        case move:
        case scrollAll:
            return SDL_SYSTEM_CURSOR_SIZEALL;
        case noDrop:
        case notAllowed:
            return SDL_SYSTEM_CURSOR_NO;
        case resizeE:
        case resizeW:
        case resizeEW:
        case resizeCol:
            return SDL_SYSTEM_CURSOR_SIZEWE;
        case resizeN:
        case resizeS:
        case resizeNS:
        case resizeRow:
            return SDL_SYSTEM_CURSOR_SIZENS;
        case resizeNESW:
            return SDL_SYSTEM_CURSOR_SIZENESW;
        case resizeNWSE:
            return SDL_SYSTEM_CURSOR_SIZENWSE;
        default:
            return SDL_SYSTEM_CURSOR_ARROW;
        }
    }

    private void updateDPI()
    {
        const displayIndex = SDL_GetWindowDisplayIndex(_win);
        if (displayIndex < 0)
            return;

        float vertdpi = 0;
        if (SDL_GetDisplayDPI(displayIndex, null, null, &vertdpi) != 0)
            return;
        if (vertdpi < 32 || 2000 < vertdpi)
            return;

        int h;
        SDL_GetWindowSize(_win, null, &h);
        int deviceh;
        SDL_GL_GetDrawableSize(_win, null, &deviceh);
        if (h <= 0)
            return;

        setDPI(vertdpi, cast(float)deviceh / h);
    }

    private SDL_Texture* _texture;
    private int _txw, _txh;

    private void updateTextureSize(int pw, int ph)
    {
        if (_texture && (_txw != pw || _txh != ph))
        {
            SDL_DestroyTexture(_texture);
            _texture = null;
        }
        if (!_texture)
        {
            _texture = SDL_CreateTexture(_renderer,
                SDL_PIXELFORMAT_ARGB8888,
                SDL_TEXTUREACCESS_STATIC,
                pw, ph);
            _txw = pw;
            _txh = ph;
        }
    }

    private void redraw()
    {
        // check if size has been changed
        fixSize();

        if (openglEnabled)
        {
            static if (USE_OPENGL)
                drawUsingOpenGL(_paintEngine);
        }
        else
        {
            if (!_paintEngine)
            {
                // create stuff on the first run
                _backbuffer = Bitmap(1, 1, PixelFormat.argb8);
                _paintEngine = new SWPaintEngine(_backbuffer);
            }
            draw(_paintEngine);

            SDL_Rect rect;
            rect.w = _backbuffer.width;
            rect.h = _backbuffer.height;
            updateTextureSize(rect.w, rect.h);
            SDL_UpdateTexture(_texture, &rect, _backbuffer.pixels!uint, cast(int)_backbuffer.rowBytes);
            SDL_RenderCopy(_renderer, _texture, &rect, &rect);
            SDL_RenderPresent(_renderer);
        }
    }

    static if (USE_OPENGL)
    {
        private SDL_GLContext _context;

        override protected bool createContext(int major, int minor)
        {
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, major);
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, minor);
            SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
            // create the actual context and make it current
            _context = SDL_GL_CreateContext(_win);
            const success = _context !is null;
            if (!success)
                Log.e("GL: ", fromStringz(SDL_GetError()));
            return success;
        }

        override protected void destroyContext()
        {
            if (_context)
            {
                SDL_GL_DeleteContext(_context);
                _context = null;
            }
        }

        override protected void handleGLReadiness()
        {
            disableVSync();
        }

        private void disableVSync()
        {
            // try to activate adaptive vsync
            const int res = SDL_GL_SetSwapInterval(-1);
            // if it's not supported, work without vsync
            if (res == -1)
                SDL_GL_SetSwapInterval(0);
        }

        override protected void bindContext()
        {
            SDL_GL_MakeCurrent(_win, _context);
        }

        override protected void swapBuffers()
        {
            SDL_GL_SwapWindow(_win);
        }
    }

    //===============================================================

    private ButtonDetails _lbutton;
    private ButtonDetails _mbutton;
    private ButtonDetails _rbutton;

    private MouseMods convertMouseMods(uint sdlFlags)
    {
        MouseMods mods;
        if (sdlFlags & SDL_BUTTON_LMASK)
            mods |= MouseMods.left;
        if (sdlFlags & SDL_BUTTON_RMASK)
            mods |= MouseMods.right;
        if (sdlFlags & SDL_BUTTON_MMASK)
            mods |= MouseMods.middle;
        return mods;
    }

    private MouseButton convertMouseButton(uint sdlButton)
    {
        if (sdlButton == SDL_BUTTON_LEFT)
            return MouseButton.left;
        if (sdlButton == SDL_BUTTON_RIGHT)
            return MouseButton.right;
        if (sdlButton == SDL_BUTTON_MIDDLE)
            return MouseButton.middle;
        return MouseButton.none;
    }

    private MouseMods lastPressed;
    private short lastx, lasty;
    private KeyMods _keyMods;

    private void processMouseEvent(MouseAction action, uint sdlButton, uint sdlFlags, int x, int y)
    {
        lastPressed = convertMouseMods(sdlFlags);
        lastx = cast(short)x;
        lasty = cast(short)y;
        MouseButton btn = convertMouseButton(sdlButton);
        auto event = new MouseEvent(action, btn, lastPressed, _keyMods, lastx, lasty);

        ButtonDetails* pbuttonDetails;
        if (btn == MouseButton.left)
            pbuttonDetails = &_lbutton;
        else if (btn == MouseButton.right)
            pbuttonDetails = &_rbutton;
        else if (btn == MouseButton.middle)
            pbuttonDetails = &_mbutton;
        if (pbuttonDetails)
        {
            if (action == MouseAction.buttonDown)
            {
                pbuttonDetails.down(cast(short)x, cast(short)y, lastPressed, _keyMods);
            }
            else if (action == MouseAction.buttonUp)
            {
                pbuttonDetails.up(cast(short)x, cast(short)y, lastPressed, _keyMods);
            }
        }
        event.lbutton = _lbutton;
        event.rbutton = _rbutton;
        event.mbutton = _mbutton;

        dispatchMouseEvent(event);
        update();
    }

    private void processWheelEvent(int deltaX, int deltaY)
    {
        if (deltaX != 0 || deltaY != 0)
        {
            const dx = cast(short)deltaX;
            const dy = cast(short)deltaY;
            auto event = new WheelEvent(lastx, lasty, lastPressed, _keyMods, dx, dy);
            dispatchWheelEvent(event);
            update();
        }
    }

    private Key convertKeyCode(uint sdlKeyCode)
    {
        switch (sdlKeyCode)
        {
        case SDLK_0: return Key.alpha0;
        case SDLK_1: return Key.alpha1;
        case SDLK_2: return Key.alpha2;
        case SDLK_3: return Key.alpha3;
        case SDLK_4: return Key.alpha4;
        case SDLK_5: return Key.alpha5;
        case SDLK_6: return Key.alpha6;
        case SDLK_7: return Key.alpha7;
        case SDLK_8: return Key.alpha8;
        case SDLK_9: return Key.alpha9;
        case SDLK_a: return Key.A;
        case SDLK_b: return Key.B;
        case SDLK_c: return Key.C;
        case SDLK_d: return Key.D;
        case SDLK_e: return Key.E;
        case SDLK_f: return Key.F;
        case SDLK_g: return Key.G;
        case SDLK_h: return Key.H;
        case SDLK_i: return Key.I;
        case SDLK_j: return Key.J;
        case SDLK_k: return Key.K;
        case SDLK_l: return Key.L;
        case SDLK_m: return Key.M;
        case SDLK_n: return Key.N;
        case SDLK_o: return Key.O;
        case SDLK_p: return Key.P;
        case SDLK_q: return Key.Q;
        case SDLK_r: return Key.R;
        case SDLK_s: return Key.S;
        case SDLK_t: return Key.T;
        case SDLK_u: return Key.U;
        case SDLK_v: return Key.V;
        case SDLK_w: return Key.W;
        case SDLK_x: return Key.X;
        case SDLK_y: return Key.Y;
        case SDLK_z: return Key.Z;
        case SDLK_F1: return Key.F1;
        case SDLK_F2: return Key.F2;
        case SDLK_F3: return Key.F3;
        case SDLK_F4: return Key.F4;
        case SDLK_F5: return Key.F5;
        case SDLK_F6: return Key.F6;
        case SDLK_F7: return Key.F7;
        case SDLK_F8: return Key.F8;
        case SDLK_F9: return Key.F9;
        case SDLK_F10: return Key.F10;
        case SDLK_F11: return Key.F11;
        case SDLK_F12: return Key.F12;
        case SDLK_F13: return Key.F13;
        case SDLK_F14: return Key.F14;
        case SDLK_F15: return Key.F15;
        case SDLK_F16: return Key.F16;
        case SDLK_F17: return Key.F17;
        case SDLK_F18: return Key.F18;
        case SDLK_F19: return Key.F19;
        case SDLK_F20: return Key.F20;
        case SDLK_F21: return Key.F21;
        case SDLK_F22: return Key.F22;
        case SDLK_F23: return Key.F23;
        case SDLK_F24: return Key.F24;
        case SDLK_BACKSPACE:
            return Key.backspace;
        case SDLK_SPACE:
            return Key.space;
        case SDLK_TAB:
            return Key.tab;
        case SDLK_RETURN:
            return Key.enter;
        case SDLK_ESCAPE:
            return Key.escape;
        case SDLK_DELETE:
        case 0x40000063: // dirty hack for Linux - key on keypad
            return Key.del;
        case SDLK_INSERT:
        case 0x40000062: // dirty hack for Linux - key on keypad
            return Key.ins;
        case SDLK_HOME:
        case 0x4000005f: // dirty hack for Linux - key on keypad
            return Key.home;
        case SDLK_PAGEUP:
        case 0x40000061: // dirty hack for Linux - key on keypad
            return Key.pageUp;
        case SDLK_END:
        case 0x40000059: // dirty hack for Linux - key on keypad
            return Key.end;
        case SDLK_PAGEDOWN:
        case 0x4000005b: // dirty hack for Linux - key on keypad
            return Key.pageDown;
        case SDLK_LEFT:
        case 0x4000005c: // dirty hack for Linux - key on keypad
            return Key.left;
        case SDLK_RIGHT:
        case 0x4000005e: // dirty hack for Linux - key on keypad
            return Key.right;
        case SDLK_UP:
        case 0x40000060: // dirty hack for Linux - key on keypad
            return Key.up;
        case SDLK_DOWN:
        case 0x4000005a: // dirty hack for Linux - key on keypad
            return Key.down;
        case SDLK_KP_ENTER:
            return Key.enter;
        case SDLK_LCTRL:
            return Key.lcontrol;
        case SDLK_LSHIFT:
            return Key.lshift;
        case SDLK_LALT:
            return Key.lalt;
        case SDLK_RCTRL:
            return Key.rcontrol;
        case SDLK_RSHIFT:
            return Key.rshift;
        case SDLK_RALT:
            return Key.ralt;
        case SDLK_LGUI:
            return Key.lwin;
        case SDLK_RGUI:
            return Key.rwin;
        case '/':
            return Key.divide;
        default:
            return Key.none;
        }
    }

    private KeyMods convertKeyMods(uint sdlKeymod)
    {
        KeyMods mods;
        if (sdlKeymod & KMOD_SHIFT)
            mods |= KeyMods.shift;
        if (sdlKeymod & KMOD_CTRL)
            mods |= KeyMods.control;
        if (sdlKeymod & KMOD_ALT)
            mods |= KeyMods.alt;
        if (sdlKeymod & KMOD_GUI)
            mods |= KeyMods.meta;
        if (sdlKeymod & KMOD_LSHIFT)
            mods |= KeyMods.lshift;
        if (sdlKeymod & KMOD_LCTRL)
            mods |= KeyMods.lcontrol;
        if (sdlKeymod & KMOD_LALT)
            mods |= KeyMods.lalt;
        if (sdlKeymod & KMOD_RSHIFT)
            mods |= KeyMods.rshift;
        if (sdlKeymod & KMOD_RCTRL)
            mods |= KeyMods.rcontrol;
        if (sdlKeymod & KMOD_RALT)
            mods |= KeyMods.ralt;
        return mods;
    }

    private void processTextInput(const char* s)
    {
        string str = fromStringz(s).dup;
        dstring ds = toUTF32(str);
        KeyMods mods = convertKeyMods(SDL_GetModState());
        //do not handle Ctrl+Space as text https://github.com/buggins/dlangui/issues/160
        //but do hanlde RAlt https://github.com/buggins/dlangide/issues/129
        debug (keys)
            Log.fd("processTextInput char: %s (%s), mods: %s", ds, cast(int)ds[0], mods);
        if ((mods & KeyMods.alt) && (mods & KeyMods.control))
        {
            mods &= (~(KeyMods.lralt)) & (~(KeyMods.lrcontrol));
            debug (keys)
                Log.fd("processTextInput removed Ctrl+Alt mods char: %s (%s), mods: %s",
                        ds, cast(int)ds[0], mods);
        }

        if (mods & KeyMods.control || (mods & KeyMods.lalt) == KeyMods.lalt || mods & KeyMods.meta)
            return;

        dispatchKeyEvent(new KeyEvent(KeyAction.text, Key.none, mods, ds));
        update();
    }

    static bool isNumLockEnabled()
    {
        version (Windows)
        {
            return !!(GetKeyState(VK_NUMLOCK) & 1);
        }
        else
        {
            return !!(SDL_GetModState() & KMOD_NUM);
        }
    }

    private void processKeyEvent(KeyAction action, uint sdlKeyCode, uint sdlKeymod)
    {
        debug (keys)
            Log.fd("processKeyEvent %s, SDL key: 0x%08x, SDL mods: 0x%08x", action, sdlKeyCode, sdlKeymod);

        const key = convertKeyCode(sdlKeyCode);
        KeyMods mods = convertKeyMods(sdlKeymod);
        if (action == KeyAction.keyDown)
        {
            switch (key)
            {
            case Key.shift:
                mods |= KeyMods.shift;
                break;
            case Key.control:
                mods |= KeyMods.control;
                break;
            case Key.alt:
                mods |= KeyMods.alt;
                break;
            case Key.lshift:
                mods |= KeyMods.lshift;
                break;
            case Key.lcontrol:
                mods |= KeyMods.lcontrol;
                break;
            case Key.lalt:
                mods |= KeyMods.lalt;
                break;
            case Key.rshift:
                mods |= KeyMods.rshift;
                break;
            case Key.rcontrol:
                mods |= KeyMods.rcontrol;
                break;
            case Key.ralt:
                mods |= KeyMods.ralt;
                break;
            case Key.lwin:
            case Key.rwin:
                mods |= KeyMods.meta;
                break;
            default:
                break;
            }
        }
        _keyMods = mods;

        debug (keys)
            Log.fd("converted, action: %s, key: %s, mods: %s", action, key, mods);

        if (action == KeyAction.keyDown || action == KeyAction.keyUp)
        {
            if ((SDLK_KP_1 <= sdlKeyCode && sdlKeyCode <= SDLK_KP_0 ||
                 sdlKeyCode == SDLK_KP_PERIOD) && isNumLockEnabled)
                    return;
        }
        dispatchKeyEvent(new KeyEvent(action, key, mods));
        update();
    }

    //===============================================================

    override protected void captureMouse(bool enabled)
    {
        debug (mouse)
            Log.d(enabled ? "Setting capture" : "Releasing capture");
        SDL_CaptureMouse(enabled ? SDL_TRUE : SDL_FALSE);
    }

    override void postEvent(CustomEvent event)
    {
        super.postEvent(event);
        SDL_Event sdlevent;
        sdlevent.user.type = USER_EVENT_ID;
        sdlevent.user.code = cast(int)event.uniqueID;
        sdlevent.user.windowID = windowID;
        SDL_PushEvent(&sdlevent);
    }

    override protected void postTimerEvent()
    {
        SDL_Event sdlevent;
        sdlevent.user.type = TIMER_EVENT_ID;
        sdlevent.user.code = 0;
        sdlevent.user.windowID = windowID;
        SDL_PushEvent(&sdlevent);
    }

    override protected void handleTimer()
    {
        super.handleTimer();
    }
}

final class SDLPlatform : Platform
{
    private WindowMap!(SDLWindow, uint) windows;

    this(ref AppConf conf)
    {
        super(conf);
    }

    ~this()
    {
        destroy(windows);
        SDL_Quit();
    }

    override void closeWindow(Window w)
    {
        // send a close event for SDLWindow
        SDLWindow window = cast(SDLWindow)w;
        SDL_Event sdlevent;
        sdlevent.user.type = WINDOW_CLOSE_EVENT_ID;
        sdlevent.user.code = 0;
        sdlevent.user.windowID = window.windowID;
        SDL_PushEvent(&sdlevent);
    }

    override protected int opApply(scope int delegate(size_t i, Window w) callback)
    {
        foreach (i, w; windows)
            if (const result = callback(i, w))
                break;
        return 0;
    }

    private SDL_EventType _redrawEventID;

    void sendRedrawEvent(uint windowID, uint code)
    {
        if (!_redrawEventID)
            _redrawEventID = cast(SDL_EventType)SDL_RegisterEvents(1);
        SDL_Event event;
        event.type = _redrawEventID;
        event.user.windowID = windowID;
        event.user.code = code;
        SDL_PushEvent(&event);
    }

    override Window createWindow(dstring title, Window parent,
            WindowOptions options = WindowOptions.resizable | WindowOptions.expanded,
            uint width = 0, uint height = 0)
    {
        auto w = new SDLWindow(this, title, parent, options, width, height);
        windows.add(w, w.windowID);
        return w;
    }

    private bool _windowsMinimized;

    override int enterMessageLoop()
    {
        Log.i("entering message loop");
        SDL_Event event;
        bool skipNextQuit;
        while (SDL_WaitEvent(&event))
        {
            bool quit = processSDLEvent(event, skipNextQuit);
            windows.purge();
            if (quit)
                break;
        }
        Log.i("exiting message loop");
        return 0;
    }

    private uint timestampResizing;

    protected bool processSDLEvent(ref SDL_Event event, ref bool skipNextQuit)
    {
        if (event.type == SDL_QUIT)
        {
            if (!skipNextQuit)
                return true;
            else
                skipNextQuit = false;
        }
        if (_redrawEventID && event.type == _redrawEventID)
        {
            if (event.window.timestamp - timestampResizing <= 1) // TODO: refactor everything
                return false;
            // user defined redraw event
            if (auto w = windows[event.user.windowID])
            {
                w.processRedrawEvent(event.user.code);
            }
            return false;
        }
        switch (event.type)
        {
        case SDL_WINDOWEVENT:
            // window events
            SDLWindow w = windows[event.window.windowID];
            if (!w)
            {
                Log.w("SDL_WINDOWEVENT ", event.window.event, " received with unknown id ", event.window.windowID);
                break;
            }
            // found window
            switch (event.window.event)
            {
            case SDL_WINDOWEVENT_RESIZED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_RESIZED - ", w.title,
                            ", pos: ", event.window.data1, ",", event.window.data2);
                // redraw is not needed here: SDL_WINDOWEVENT_RESIZED is following SDL_WINDOWEVENT_SIZE_CHANGED
                // if the size was changed by an external event (window manager, user)
                break;
            case SDL_WINDOWEVENT_SIZE_CHANGED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_SIZE_CHANGED - ", w.title,
                            ", size: ", event.window.data1, ",", event.window.data2);
                w.updateDPI();
                w.handleWindowStateChange(WindowState.unspecified, BoxI(w.windowRect.x,
                        w.windowRect.y, event.window.data1, event.window.data2));
                w.redraw();
                timestampResizing = event.window.timestamp;
                break;
            case SDL_WINDOWEVENT_CLOSE:
                if (w.canClose)
                {
                    debug (sdl)
                        Log.d("SDL_WINDOWEVENT_CLOSE win: ", event.window.windowID);
                    windows.remove(w);
                }
                else
                {
                    skipNextQuit = true;
                }
                break;
            case SDL_WINDOWEVENT_SHOWN:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_SHOWN - ", w.title);
                if (w.windowState != WindowState.normal)
                    w.handleWindowStateChange(WindowState.normal);
                if (!_windowsMinimized && w.hasVisibleModalChild)
                    w.restoreModalChilds();
                break;
            case SDL_WINDOWEVENT_HIDDEN:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_HIDDEN - ", w.title);
                if (w.windowState != WindowState.hidden)
                    w.handleWindowStateChange(WindowState.hidden);
                break;
            case SDL_WINDOWEVENT_EXPOSED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_EXPOSED - ", w.title);
                // process only if this event is not following SDL_WINDOWEVENT_SIZE_CHANGED event
                if (event.window.timestamp - timestampResizing > 1)
                    w.invalidate();
                break;
            case SDL_WINDOWEVENT_MOVED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_MOVED - ", w.title);
                w.handleWindowStateChange(WindowState.unspecified, BoxI(event.window.data1,
                        event.window.data2, w.windowRect.w, w.windowRect.h));
                if (!_windowsMinimized && w.hasVisibleModalChild)
                    w.restoreModalChilds();
                break;
            case SDL_WINDOWEVENT_MINIMIZED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_MINIMIZED - ", w.title);
                if (w.windowState != WindowState.minimized)
                    w.handleWindowStateChange(WindowState.minimized);
                if (!_windowsMinimized && w.hasVisibleModalChild)
                    w.minimizeModalChilds();
                if (!_windowsMinimized && w.options & WindowOptions.modal)
                    w.minimizeParentWindows();
                _windowsMinimized = true;
                break;
            case SDL_WINDOWEVENT_MAXIMIZED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_MAXIMIZED - ", w.title);
                if (w.windowState != WindowState.maximized)
                    w.handleWindowStateChange(WindowState.maximized);
                _windowsMinimized = false;
                break;
            case SDL_WINDOWEVENT_RESTORED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_RESTORED - ", w.title);
                _windowsMinimized = false;
                if (w.options & WindowOptions.modal)
                {
                    w.restoreParentWindows();
                    w.restore(true);
                }

                if (w.windowState != WindowState.normal)
                    w.handleWindowStateChange(WindowState.normal);

                if (w.hasVisibleModalChild)
                    w.restoreModalChilds();
                version (linux)
                { //not sure if needed on Windows or OSX. Also need to check on FreeBSD
                    w.invalidate();
                }
                break;
            case SDL_WINDOWEVENT_ENTER:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_ENTER - ", w.title);
                break;
            case SDL_WINDOWEVENT_LEAVE:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_LEAVE - ", w.title);
                break;
            case SDL_WINDOWEVENT_FOCUS_GAINED:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_FOCUS_GAINED - ", w.title);
                if (!_windowsMinimized)
                    w.restoreModalChilds();
                w.handleWindowActivityChange(true);
                break;
            case SDL_WINDOWEVENT_FOCUS_LOST:
                debug (sdl)
                    Log.d("SDL_WINDOWEVENT_FOCUS_LOST - ", w.title);
                w.handleWindowActivityChange(false);
                break;
            default:
                break;
            }
            break;
        case SDL_KEYDOWN:
            SDLWindow w = windows[event.key.windowID];
            if (w && !w.hasVisibleModalChild)
            {
                w.processKeyEvent(KeyAction.keyDown, event.key.keysym.sym, event.key.keysym.mod);
                SDL_StartTextInput();
            }
            break;
        case SDL_KEYUP:
            SDLWindow w = windows[event.key.windowID];
            if (w)
            {
                if (w.hasVisibleModalChild)
                    w.restoreModalChilds();
                else
                    w.processKeyEvent(KeyAction.keyUp, event.key.keysym.sym, event.key.keysym.mod);
            }
            break;
        case SDL_TEXTEDITING:
            debug (sdl)
                Log.d("SDL_TEXTEDITING");
            break;
        case SDL_TEXTINPUT:
            debug (sdl)
                Log.d("SDL_TEXTINPUT");
            SDLWindow w = windows[event.text.windowID];
            if (w && !w.hasVisibleModalChild)
            {
                w.processTextInput(event.text.text.ptr);
            }
            break;
        case SDL_MOUSEMOTION:
            SDLWindow w = windows[event.motion.windowID];
            if (w && !w.hasVisibleModalChild)
            {
                w.processMouseEvent(MouseAction.move, 0, event.motion.state, event.motion.x, event.motion.y);
            }
            break;
        case SDL_MOUSEBUTTONDOWN:
            SDLWindow w = windows[event.button.windowID];
            if (w && !w.hasVisibleModalChild)
            {
                w.processMouseEvent(MouseAction.buttonDown, event.button.button,
                        event.button.state, event.button.x, event.button.y);
            }
            break;
        case SDL_MOUSEBUTTONUP:
            SDLWindow w = windows[event.button.windowID];
            if (w)
            {
                if (w.hasVisibleModalChild)
                    w.restoreModalChilds();
                else
                    w.processMouseEvent(MouseAction.buttonUp, event.button.button,
                            event.button.state, event.button.x, event.button.y);
            }
            break;
        case SDL_MOUSEWHEEL:
            SDLWindow w = windows[event.wheel.windowID];
            if (w && !w.hasVisibleModalChild)
            {
                debug (sdl)
                    Log.d("SDL_MOUSEWHEEL x=", event.wheel.x, " y=", event.wheel.y);
                w.processWheelEvent(-event.wheel.x, -event.wheel.y);
            }
            break;
        default:
            // custom or not supported event
            if (auto w = windows[event.user.windowID])
            {
                if (event.type == USER_EVENT_ID)
                {
                    w.handlePostedEvent(cast(uint)event.user.code);
                }
                else if (event.type == TIMER_EVENT_ID)
                {
                    w.handleTimer();
                }
                else if (event.type == WINDOW_CLOSE_EVENT_ID)
                {
                    if (w.canClose)
                        windows.remove(w);
                }
            }
            break;
        }
        if (windows.count == 0)
        {
            SDL_Quit();
            return true;
        }
        return false;
    }

    override bool hasClipboardText(bool mouseBuffer = false)
    {
        return (SDL_HasClipboardText() == SDL_TRUE);
    }

    override dstring getClipboardText(bool mouseBuffer = false)
    {
        char* txt = SDL_GetClipboardText();
        if (!txt)
            return ""d;
        string s = fromStringz(txt).dup;
        SDL_free(txt);
        return normalizeEOLs(toUTF32(s));
    }

    override void setClipboardText(dstring text, bool mouseBuffer = false)
    {
        string s = toUTF8(text);
        SDL_SetClipboardText(s.toStringz);
    }
}

extern (C) Platform initPlatform(AppConf conf)
{
    version (Windows)
    {
        DOUBLE_CLICK_THRESHOLD_MS = GetDoubleClickTime();

        setAppDPIAwareOnWindows();
    }

    SDLSupport ret = loadSDL();
    if (ret != sdlSupport)
    {
        if(ret == SDLSupport.noLibrary)
            Log.e("This application requires the SDL library");
        else
            Log.e("The version of the SDL library is too low, must be at least 2.0.4");
        return null;
    }

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0)
    {
        Log.e("Cannot init SDL2: ", fromStringz(SDL_GetError()));
        return null;
    }

    USER_EVENT_ID = cast(SDL_EventType)SDL_RegisterEvents(1);
    TIMER_EVENT_ID = cast(SDL_EventType)SDL_RegisterEvents(1);
    WINDOW_CLOSE_EVENT_ID = cast(SDL_EventType)SDL_RegisterEvents(1);

    static if (USE_OPENGL)
    {
        // Set OpenGL attributes
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
        SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
        // Share textures between contexts
        SDL_GL_SetAttribute(SDL_GL_SHARE_WITH_CURRENT_CONTEXT, 1);
    }

    return new SDLPlatform(conf);
}
