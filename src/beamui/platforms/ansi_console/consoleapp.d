/**


Copyright: Vadim Lopatin 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.ansi_console.consoleapp;

import beamui.core.config;

static if (BACKEND_ANSI_CONSOLE):
import beamui.core.events;
import beamui.core.logger;
import beamui.graphics.colors : Color;
import beamui.graphics.drawables : ConsoleDrawBuf;
import beamui.graphics.drawbuf;
import beamui.platforms.ansi_console.consolefont;
import beamui.platforms.ansi_console.dconsole;
import beamui.platforms.common.platform;
import beamui.platforms.common.startup;
import beamui.text.glyph : GlyphRef;

class ConsoleWindow : Window
{
    private
    {
        ConsolePlatform _platform;

        dstring _title;
    }

    this(ConsolePlatform platform, dstring caption, Window parent, WindowOptions options)
    {
        super(parent, options);
        _platform = platform;
        width = _platform.console.width;
        height = _platform.console.height;
        _windowRect = BoxI(0, 0, width, height);
        setDPI(10, 1);
    }

    override @property dstring title() const { return _title; }

    override @property void title(dstring caption)
    {
        _title = caption;
    }

    override @property void icon(DrawBufRef icon)
    {
        // ignore
    }

    override void show()
    {
        if (!mainWidget)
        {
            Log.e("Window is shown without main widget");
            mainWidget = new Widget;
        }
        _visible = true;
        handleWindowStateChange(WindowState.normal, BoxI(0, 0, _platform.console.width, _platform.console.height));
        invalidate();
    }

    override void invalidate()
    {
        _platform.update();
    }

    override void close()
    {
        Log.d("ConsoleWindow.close()");
        _platform.closeWindow(this);
    }

    //===============================================================

    override @property bool isActive() const
    {
        // todo
        return true;
    }

    private bool _visible;
    /// Returns true if window is shown
    @property bool visible() { return _visible; }

    override protected void scheduleSystemTimer(long timestamp)
    {
        // we poll timers manually
    }
}

class ConsolePlatform : Platform
{
    @property Console console() { return _console; }

    @property DrawBuf drawBuf() { return _drawBuf; }

    private
    {
        Console _console;
        WindowMap!(ConsoleWindow, size_t) windows;
        ANSIConsoleDrawBuf _drawBuf;
    }

    this(ref AppConf conf)
    {
        super(conf);

        _console = new Console;
        _console.batchMode = true;
        _console.onKeyEvent = &handleKey;
        _console.onMouseEvent = &handleMouse;
        _console.onWheelEvent = &handleWheel;
        _console.onResize = &handleResize;
        _console.onInputIdle = &handleInputIdle;
        _console.init();
        _console.setCursorType(ConsoleCursorType.hidden);
        _drawBuf = new ANSIConsoleDrawBuf(_console);
    }

    ~this()
    {
        destroy(windows);
        //Log.d("Destroying console");
        //destroy(_console);
        Log.d("Destroying drawbuf");
        destroy(_drawBuf);
    }

    override Window createWindow(dstring title, Window parent,
            WindowOptions options = WindowOptions.resizable | WindowOptions.expanded,
            uint width = 0, uint height = 0)
    {
        auto res = new ConsoleWindow(this, title, parent, options);
        windows.add(res, windows.count);
        return res;
    }

    override void closeWindow(Window w)
    {
        windows.remove(cast(ConsoleWindow)w);
    }

    @property ConsoleWindow activeWindow()
    {
        return windows.last;
    }

    protected bool handleKey(KeyEvent event)
    {
        auto w = activeWindow;
        if (!w)
            return false;
        if (w.dispatchKeyEvent(event))
        {
            _needRedraw = true;
            return true;
        }
        return false;
    }

    protected bool handleMouse(MouseEvent event)
    {
        auto w = activeWindow;
        if (!w)
            return false;
        if (w.dispatchMouseEvent(event))
        {
            _needRedraw = true;
            return true;
        }
        return false;
    }

    protected bool handleWheel(WheelEvent event)
    {
        auto w = activeWindow;
        if (!w)
            return false;
        w.dispatchWheelEvent(event);
        _needRedraw = true;
        return true;
    }

    protected bool handleResize(int width, int height)
    {
        drawBuf.resize(width, height);
        foreach (w; windows)
        {
            w.handleResize(width, height);
        }
        _needRedraw = true;
        return false;
    }

    private bool _needRedraw = true;
    void update()
    {
        _needRedraw = true;
    }

    protected void redraw()
    {
        if (!_needRedraw)
            return;
        foreach (w; windows)
        {
            if (w.visible)
            {
                _drawBuf.fillRect(Rect(0, 0, w.width, w.height), w.backgroundColor);
                w.draw(_drawBuf);
                auto caretRect = w.caretRect;
                if (w is activeWindow)
                {
                    if (!caretRect.empty)
                    {
                        _drawBuf.console.setCursor(caretRect.left, caretRect.top);
                        _drawBuf.console.setCursorType(w.caretReplace ? ConsoleCursorType.replace
                                : ConsoleCursorType.insert);
                    }
                    else
                    {
                        _drawBuf.console.setCursorType(ConsoleCursorType.hidden);
                    }
                    _drawBuf.console.setWindowCaption(w.title);
                }
            }
        }
        _needRedraw = false;
    }

    protected bool handleInputIdle()
    {
        foreach (w; windows)
        {
            w.pollTimers();
            w.handlePostedEvents();
        }
        redraw();
        _console.flush();
        windows.purge();
        return false;
    }

    override int enterMessageLoop()
    {
        Log.i("Entered message loop");
        while (_console.pollInput())
        {
            if (windows.count == 0)
            {
                Log.d("No windows - exiting message loop");
                break;
            }
        }
        windows.purge();
        Log.i("Exiting from message loop");
        return 0;
    }

    private dstring _clipboardText;

    override bool hasClipboardText(bool mouseBuffer = false)
    {
        return _clipboardText.length > 0;
    }

    override dstring getClipboardText(bool mouseBuffer = false)
    {
        return _clipboardText;
    }

    override void setClipboardText(dstring text, bool mouseBuffer = false)
    {
        _clipboardText = text;
    }

    override void requestLayout()
    {
        // TODO
    }

    private void handleCtrlC()
    {
        Log.w("Ctrl+C pressed - stopping application");
        if (_console)
        {
            _console.stop();
        }
    }
}

/// Drawing buffer - image container which allows to perform some drawing operations
class ANSIConsoleDrawBuf : ConsoleDrawBuf
{
    @property Console console() { return _console; }

    private Console _console;

    this(Console console)
    {
        _console = console;
        resetClipping();
    }

    ~this()
    {
        Log.d("Calling console.uninit");
        _console.uninit();
    }

    override @property int width() const
    {
        return _console.width;
    }
    override @property int height() const
    {
        return _console.height;
    }

    override void beforeDrawing()
    {
        // TODO?
    }
    override void afterDrawing()
    {
        // TODO?
    }
    override @property int bpp() const
    {
        return 4;
    }
    // returns pointer to ARGB scanline, null if y is out of range or buffer doesn't provide access to its memory
    //uint * scanLine(int y) { return null; }

    override void resize(int width, int height)
    {
        // IGNORE
        resetClipping();
    }

    //===============================================================
    // Drawing methods

    override void fill(Color color)
    {
        // TODO
        fillRect(Rect(0, 0, width, height), color);
    }

    private struct RGB
    {
        int r;
        int g;
        int b;
        int match(int rr, int gg, int bb) immutable
        {
            int dr = rr - r;
            int dg = gg - g;
            int db = bb - b;
            if (dr < 0)
                dr = -dr;
            if (dg < 0)
                dg = -dg;
            if (db < 0)
                db = -db;
            return dr + dg + db;
        }
    }

    version (Windows)
    {
        // windows color table
        static immutable RGB[16] CONSOLE_COLORS_RGB = [
            RGB(0,0,0),
            RGB(0,0,128),
            RGB(0,128,0),
            RGB(0,128,128),
            RGB(128,0,0),
            RGB(128,0,128),
            RGB(128,128,0),
            RGB(192,192,192),
            RGB(0x7c,0x7c,0x7c), // ligth gray
            RGB(0,0,255),
            RGB(0,255,0),
            RGB(0,255,255),
            RGB(255,0,0),
            RGB(255,0,255),
            RGB(255,255,0),
            RGB(255,255,255),
        ];
    }
    else
    {
        // linux color table
        static immutable RGB[16] CONSOLE_COLORS_RGB = [
            RGB(0,0,0),
            RGB(128,0,0),
            RGB(0,128,0),
            RGB(128,128,0),
            RGB(0,0,128),
            RGB(128,0,128),
            RGB(0,128,128),
            RGB(192,192,192),
            RGB(0x7c,0x7c,0x7c), // ligth gray
            RGB(255,0,0),
            RGB(0,255,0),
            RGB(255,255,0),
            RGB(0,0,255),
            RGB(255,0,255),
            RGB(0,255,255),
            RGB(255,255,255),
        ];
    }

    static ubyte toConsoleColor(Color color, bool forBackground = false)
    {
        if (forBackground && color.a >= 0x80)
            return CONSOLE_TRANSPARENT_BACKGROUND;
        int r = color.r;
        int g = color.g;
        int b = color.b;
        int bestMatch = CONSOLE_COLORS_RGB[0].match(r, g, b);
        int bestMatchIndex = 0;
        for (int i = 1; i < 16; i++)
        {
            int m = CONSOLE_COLORS_RGB[i].match(r, g, b);
            if (m < bestMatch)
            {
                bestMatch = m;
                bestMatchIndex = i;
            }
        }
        return cast(ubyte)bestMatchIndex;
    }

    static immutable dchar[512] SPACE_STRING = ' ';

    override void fillRect(Rect rc, Color color)
    {
        if (color.a >= 128)
            return; // transparent
        _console.backgroundColor = toConsoleColor(color);
        if (applyClipping(rc))
        {
            int w = rc.width;
            foreach (y; rc.top .. rc.bottom)
            {
                _console.setCursor(rc.left, y);
                _console.writeText(SPACE_STRING[0 .. w]);
            }
        }
    }

    override void fillGradientRect(Rect rc, Color color1, Color color2, Color color3, Color color4)
    {
        // TODO
        fillRect(rc, color1);
    }

    override void fillRectPattern(Rect rc, Color color, PatternType pattern)
    {
        // default implementation: does not support patterns
        fillRect(rc, color);
    }

    override void drawPixel(int x, int y, Color color)
    {
        // TODO
    }

    override void drawChar(int x, int y, dchar ch, Color color, Color bgcolor)
    {
        if (!clipRect.contains(x, y))
            return;
        ubyte tc = toConsoleColor(color, false);
        ubyte bc = toConsoleColor(bgcolor, true);
        dchar[1] text;
        text[0] = ch;
        _console.textColor = tc;
        _console.backgroundColor = bc;
        _console.setCursor(x, y);
        _console.writeText(cast(dstring)text);
    }

    override void drawGlyph(int x, int y, GlyphRef glyph, Color color)
    {
        // TODO
    }

    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect)
    {
        // not supported
    }

    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        // not supported
    }

    override void clear()
    {
        resetClipping();
    }
}

extern (C) void mySignalHandler(int value)
{
    Log.i("Signal handler - signal = ", value);
    if (auto platform = cast(ConsolePlatform)platform)
        platform.handleCtrlC();
}

extern (C) Platform initPlatform(AppConf conf)
{
    version (Windows)
    {
        import core.sys.windows.winuser;

        DOUBLE_CLICK_THRESHOLD_MS = GetDoubleClickTime();
    }
    else
    {
        // set Ctrl+C handler
        import core.sys.posix.signal;

        sigset(SIGINT, &mySignalHandler);
    }

    conf.dialogDisplayModes = DialogDisplayMode.allTypesOfDialogsInPopup;
    return new ConsolePlatform(conf);
}
