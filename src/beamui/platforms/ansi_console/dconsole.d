/**


Copyright: Vadim Lopatin 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.ansi_console.dconsole;

import beamui.core.config;

static if (BACKEND_ANSI_CONSOLE):
version (Windows)
{
    import core.sys.windows.winbase;
    import core.sys.windows.wincon;
    import core.sys.windows.winuser;
    import core.sys.windows.basetyps, core.sys.windows.w32api, core.sys.windows.winnt;
}
import std.stdio;
import std.utf;
import beamui.core.events;
import beamui.core.logger;
import beamui.core.signals;

/// Console cursor type
enum ConsoleCursorType
{
    hidden, /// Hidden
    insert, /// Insert (usually underscore)
    replace, /// Replace (usually square)
}

enum TextColor : ubyte
{
    BLACK, // 0
    BLUE,
    GREEN,
    CYAN,
    RED,
    MAGENTA,
    YELLOW,
    GREY,
    DARK_GREY, // 8
    LIGHT_BLUE,
    LIGHT_GREEN,
    LIGHT_CYAN,
    LIGHT_RED,
    LIGHT_MAGENTA,
    LIGHT_YELLOW,
    WHITE, // 15
}

immutable ubyte CONSOLE_TRANSPARENT_BACKGROUND = 0xFF;

struct ConsoleChar
{
    dchar ch;
    uint attr = 0xFFFFFFFF;

    @property
    {
        ubyte backgroundColor() const
        {
            return cast(ubyte)((attr >> 8) & 0xFF);
        }

        void backgroundColor(ubyte b)
        {
            attr = (attr & 0xFFFF00FF) | ((cast(uint)b) << 8);
        }

        ubyte textColor() const
        {
            return cast(ubyte)((attr) & 0xFF);
        }

        void textColor(ubyte b)
        {
            attr = (attr & 0xFFFFFF00) | (cast(uint)b);
        }

        bool underline() const
        {
            return (attr & 0x10000) != 0;
        }

        void underline(bool b)
        {
            if (b)
                attr |= 0x10000;
            else
                attr &= ~0x10000;
        }
    }

    /// Set value, supporting transparent background
    void set(ConsoleChar v)
    {
        if (v.backgroundColor == CONSOLE_TRANSPARENT_BACKGROUND)
        {
            ch = v.ch;
            textColor = v.textColor;
            underline = v.underline;
        }
        else
            this = v;
    }
}

immutable ConsoleChar UNKNOWN_CHAR = ConsoleChar.init;

struct ConsoleBuf
{
    @property
    {
        int width() const { return _width; }
        int height() const { return _height; }
        int cursorX() const { return _cursorX; }
        int cursorY() const { return _cursorY; }
    }

    private
    {
        int _width;
        int _height;
        int _cursorX;
        int _cursorY;
        ConsoleChar[] _chars;
    }

    void clear(ConsoleChar ch)
    {
        _chars[0 .. $] = ch;
    }

    void copyFrom(ref ConsoleBuf buf)
    {
        _width = buf._width;
        _height = buf._height;
        _cursorX = buf._cursorX;
        _cursorY = buf._cursorY;
        _chars.length = buf._chars.length;
        for (int i = 0; i < _chars.length; i++)
            _chars[i] = buf._chars[i];
    }

    void set(int x, int y, ConsoleChar ch)
    {
        _chars[y * _width + x].set(ch);
    }

    ConsoleChar get(int x, int y) const
    {
        return _chars[y * _width + x];
    }

    ConsoleChar[] line(int y)
    {
        return _chars[y * _width .. (y + 1) * _width];
    }

    void resize(int w, int h)
    {
        if (_width != w || _height != h)
        {
            _chars.length = w * h;
            _width = w;
            _height = h;
        }
        _cursorX = 0;
        _cursorY = 0;
        _chars[0 .. $] = UNKNOWN_CHAR;
    }

    void scrollUp(uint attr)
    {
        for (int i = 0; i + 1 < _height; i++)
        {
            _chars[i * _width .. (i + 1) * _width] = _chars[(i + 1) * _width .. (i + 2) * _width];
        }
        _chars[(_height - 1) * _width .. _height * _width] = ConsoleChar(' ', attr);
    }

    void setCursor(int x, int y)
    {
        _cursorX = x;
        _cursorY = y;
    }

    void writeChar(dchar ch, uint attr)
    {
        if (_cursorX >= _width)
        {
            _cursorY++;
            _cursorX = 0;
            if (_cursorY >= _height)
            {
                _cursorY = _height - 1;
                scrollUp(attr);
            }
        }
        if (ch == '\n')
        {
            _cursorX = 0;
            _cursorY++;
            if (_cursorY >= _height)
            {
                scrollUp(attr);
                _cursorY = _height - 1;
            }
            return;
        }
        if (ch == '\r')
        {
            _cursorX = 0;
            return;
        }
        set(_cursorX, _cursorY, ConsoleChar(ch, attr));
        _cursorX++;
        if (_cursorX >= _width)
        {
            if (_cursorY < _height - 1)
            {
                _cursorY++;
                _cursorX = 0;
            }
        }
    }

    void write(dstring str, uint attr)
    {
        for (int i = 0; i < str.length; i++)
        {
            writeChar(str[i], attr);
        }
    }
}

version (Windows)
{
}
else
{
    import core.sys.posix.signal;

    __gshared bool SIGHUP_flag = false;
    extern (C) void signalHandler_SIGHUP(int) nothrow @nogc @system
    {
        SIGHUP_flag = true;
        try
        {
            //Log.w("SIGHUP signal fired");
        }
        catch (Exception e)
        {
        }
    }

    void setSignalHandlers()
    {
        signal(SIGHUP, &signalHandler_SIGHUP);
    }
}

/// Console I/O support
class Console
{
    @property
    {
        int width() const
        {
            return _width;
        }

        int height() const
        {
            return _height;
        }

        int cursorX() const
        {
            return _cursorX;
        }

        void cursorX(int x)
        {
            _cursorX = x;
        }

        int cursorY() const
        {
            return _cursorY;
        }

        @property void cursorY(int y)
        {
            _cursorY = y;
        }
    }

    private
    {
        int _cursorX;
        int _cursorY;
        int _width;
        int _height;

        ConsoleBuf _buf;
        ConsoleBuf _batchBuf;
        uint _consoleAttr;
        bool _stopped;
    }

    version (Windows)
    {
        HANDLE _hstdin;
        HANDLE _hstdout;
        WORD _attr;
        immutable ushort COMMON_LVB_UNDERSCORE = 0x8000;
    }
    else
    {
        immutable int READ_BUF_SIZE = 1024;
        char[READ_BUF_SIZE] readBuf;
        int readBufPos = 0;
        bool isSequenceCompleted()
        {
            if (!readBufPos)
                return false;
            if (readBuf[0] == 0x1B)
            {
                if (readBufPos > 1 && readBuf[1] == '[' && readBuf[2] == 'M')
                    return readBufPos >= 6;
                for (int i = 1; i < readBufPos; i++)
                {
                    char ch = readBuf[i];
                    if (ch == 'O' && i == readBufPos - 1)
                        continue;
                    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '@' || ch == '~')
                        return true;
                }
                return false;
            }
            if (readBuf[0] & 0x80)
            {
                if ((readBuf[0] & 0xE0) == 0xC0)
                    return readBufPos >= 2;
                if ((readBuf[0] & 0xF0) == 0xE0)
                    return readBufPos >= 3;
                if ((readBuf[0] & 0xF8) == 0xF0)
                    return readBufPos >= 4;
                if ((readBuf[0] & 0xFC) == 0xF8)
                    return readBufPos >= 5;
                return readBufPos >= 6;
            }
            return true;
        }

        string rawRead(int pollTimeout = 3000)
        {
            if (_stopped)
                return null;
            import core.thread;
            import core.stdc.errno;

            int waitTime = 0;
            int startPos = readBufPos;
            while (readBufPos < READ_BUF_SIZE)
            {
                import core.sys.posix.unistd;

                char ch = 0;
                int res = cast(int)read(STDIN_FILENO, &ch, 1);
                if (res < 0)
                {
                    auto err = errno;
                    switch (err)
                    {
                    case EBADF:
                        Log.e("rawRead stdin EINVAL - stopping terminal");
                        _stopped = true;
                        return null;
                    case EFAULT:
                        Log.e("rawRead stdin EINVAL - stopping terminal");
                        _stopped = true;
                        return null;
                    case EINVAL:
                        Log.e("rawRead stdin EINVAL - stopping terminal");
                        _stopped = true;
                        return null;
                    case EIO:
                        Log.e("rawRead stdin EIO - stopping terminal");
                        _stopped = true;
                        return null;
                    default:
                        break;
                    }
                }
                if (res <= 0)
                {
                    if (readBufPos == startPos && waitTime < pollTimeout)
                    {
                        Thread.sleep(dur!("msecs")(10));
                        waitTime += 10;
                        continue;
                    }
                    break;
                }
                readBuf[readBufPos++] = ch;
                if (isSequenceCompleted())
                    break;
            }
            if (readBufPos > 0 && isSequenceCompleted())
            {
                string s = readBuf[0 .. readBufPos].dup;
                readBufPos = 0;
                return s;
            }
            return null;
        }

        bool rawWrite(string s)
        {
            import core.sys.posix.unistd;
            import core.stdc.errno;

            int res = cast(int)write(STDOUT_FILENO, s.ptr, s.length);
            if (res < 0)
            {
                auto err = errno;
                while (err == EAGAIN)
                {
                    //debug Log.d("rawWrite error EAGAIN - will retry");
                    res = cast(int)write(STDOUT_FILENO, s.ptr, s.length);
                    if (res >= 0)
                        return (res > 0);
                    err = errno;
                }
                Log.e("rawWrite error ", err, " - stopping terminal");
                _stopped = true;
            }
            return (res > 0);
        }
    }

    version (Windows)
    {
        DWORD savedStdinMode;
        DWORD savedStdoutMode;
    }
    else
    {
        import core.sys.posix.termios;
        import core.sys.posix.fcntl;
        import core.sys.posix.sys.ioctl;

        termios savedStdinState;
    }

    void uninit()
    {
        version (Windows)
        {
            SetConsoleMode(_hstdin, savedStdinMode);
            SetConsoleMode(_hstdout, savedStdoutMode);
        }
        else
        {
            import core.sys.posix.unistd;

            tcsetattr(STDIN_FILENO, TCSANOW, &savedStdinState);
            // reset terminal state
            rawWrite("\033c");
            // reset attributes
            rawWrite("\x1b[0m");
            // clear screen
            rawWrite("\033[2J");
            // normal cursor
            rawWrite("\x1b[?25h");
            // set auto wrapping mode
            rawWrite("\x1b[?7h");
        }
    }

    bool init()
    {
        version (Windows)
        {
            _hstdin = GetStdHandle(STD_INPUT_HANDLE);
            if (_hstdin == INVALID_HANDLE_VALUE)
                return false;
            _hstdout = GetStdHandle(STD_OUTPUT_HANDLE);
            if (_hstdout == INVALID_HANDLE_VALUE)
                return false;
            CONSOLE_SCREEN_BUFFER_INFO csbi;
            if (!GetConsoleScreenBufferInfo(_hstdout, &csbi))
            {
                if (!AllocConsole())
                {
                    return false;
                }
                _hstdin = GetStdHandle(STD_INPUT_HANDLE);
                _hstdout = GetStdHandle(STD_OUTPUT_HANDLE);
                if (!GetConsoleScreenBufferInfo(_hstdout, &csbi))
                {
                    return false;
                }
                //printf( "GetConsoleScreenBufferInfo failed: %lu\n", GetLastError());
            }
            // update console modes
            immutable DWORD ENABLE_QUICK_EDIT_MODE = 0x0040;
            immutable DWORD ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
            immutable DWORD ENABLE_LVB_GRID_WORLDWIDE = 0x0010;
            DWORD mode = 0;
            GetConsoleMode(_hstdin, &mode);
            savedStdinMode = mode;
            mode = mode & ~ENABLE_ECHO_INPUT;
            mode = mode & ~ENABLE_LINE_INPUT;
            mode = mode & ~ENABLE_QUICK_EDIT_MODE;
            mode |= ENABLE_PROCESSED_INPUT;
            mode |= ENABLE_MOUSE_INPUT;
            mode |= ENABLE_WINDOW_INPUT;
            SetConsoleMode(_hstdin, mode);
            GetConsoleMode(_hstdout, &mode);
            savedStdoutMode = mode;
            mode = mode & ~ENABLE_PROCESSED_OUTPUT;
            mode = mode & ~ENABLE_WRAP_AT_EOL_OUTPUT;
            mode = mode & ~ENABLE_VIRTUAL_TERMINAL_PROCESSING;
            mode |= ENABLE_LVB_GRID_WORLDWIDE;
            SetConsoleMode(_hstdout, mode);

            _cursorX = csbi.dwCursorPosition.X;
            _cursorY = csbi.dwCursorPosition.Y;
            _width = csbi.srWindow.Right - csbi.srWindow.Left + 1; // csbi.dwSize.X;
            _height = csbi.srWindow.Bottom - csbi.srWindow.Top + 1; // csbi.dwSize.Y;
            _attr = csbi.wAttributes;
            _textColor = _attr & 0x0F;
            _backgroundColor = (_attr & 0xF0) >> 4;
            _underline = (_attr & COMMON_LVB_UNDERSCORE) != 0;
            //writeln("csbi=", csbi);
        }
        else
        {
            import core.sys.posix.unistd;

            if (!isatty(1))
                return false;
            setSignalHandlers();
            fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
            termios ttystate;
            //get the terminal state
            tcgetattr(STDIN_FILENO, &ttystate);
            savedStdinState = ttystate;
            //turn off canonical mode
            ttystate.c_lflag &= ~ICANON;
            ttystate.c_lflag &= ~ECHO;
            //minimum of number input read.
            ttystate.c_cc[VMIN] = 1;
            //set the terminal attributes.
            tcsetattr(STDIN_FILENO, TCSANOW, &ttystate);

            winsize w;
            ioctl(0, TIOCGWINSZ, &w);
            _width = w.ws_col;
            _height = w.ws_row;

            _cursorX = 0;
            _cursorY = 0;

            _textColor = 7;
            _backgroundColor = 0;
            _underline = false;
            // enable mouse tracking - all events
            rawWrite("\033[?1003h");
            //rawWrite("\x1b[c");
            //string termType = rawRead();
            //Log.d("Term type=", termType);
        }
        _buf.resize(_width, _height);
        _batchBuf.resize(_width, _height);
        return true;
    }

    void resize(int width, int height)
    {
        if (_width != width || _height != height)
        {
            _buf.resize(width, height);
            _batchBuf.resize(width, height);
            _width = width;
            _height = height;
            clearScreen(); //??
        }
    }

    /// Clear screen and set cursor position to 0,0
    void clearScreen()
    {
        calcAttributes();
        if (!_batchMode)
        {
            _buf.clear(ConsoleChar(' ', _consoleAttr));
            version (Windows)
            {
                DWORD charsWritten;
                FillConsoleOutputCharacter(_hstdout, ' ', _width * _height, COORD(0, 0), &charsWritten);
                FillConsoleOutputAttribute(_hstdout, _attr, _width * _height, COORD(0, 0), &charsWritten);
            }
            else
            {
                rawWrite("\033[2J");
            }
        }
        else
        {
            _batchBuf.clear(ConsoleChar(' ', _consoleAttr));
        }
        setCursor(0, 0);
    }

    /// Set cursor position
    void setCursor(int x, int y)
    {
        if (!_batchMode)
        {
            _buf.setCursor(x, y);
            rawSetCursor(x, y);
            _cursorX = x;
            _cursorY = y;
        }
        else
        {
            _batchBuf.setCursor(x, y);
        }
    }

    /// Flush batched updates
    void flush()
    {
        if (!_batchMode)
            return;

        bool drawn;
        foreach (y; 0 .. _batchBuf.height)
        {
            ConsoleChar[] batchLine = _batchBuf.line(y);
            ConsoleChar[] bufLine = _buf.line(y);
            foreach (x; 0 .. _batchBuf.width)
            {
                if (batchLine[x] != ConsoleChar.init && batchLine[x] != bufLine[x])
                {
                    // found non-empty sequence
                    int xx = 1;
                    dchar[] str;
                    str ~= batchLine[x].ch;
                    bufLine[x] = batchLine[x];
                    const uint firstAttr = batchLine[x].attr;
                    for (; x + xx < _batchBuf.width; xx++)
                    {
                        if (batchLine[x + xx] == ConsoleChar.init || batchLine[x + xx].attr != firstAttr)
                            break;
                        str ~= batchLine[x + xx].ch;
                        bufLine[x + xx].set(batchLine[x + xx]);
                    }
                    rawWriteTextAt(x, y, firstAttr, cast(dstring)str);
                    x += xx - 1;
                    drawn = true;
                }
            }
        }
        if (drawn || _cursorX != _batchBuf.cursorX || _cursorY != _batchBuf.cursorY)
        {
            _cursorX = _batchBuf.cursorX;
            _cursorY = _batchBuf.cursorY;
            rawSetCursor(_cursorX, _cursorY);
            rawSetCursorType(_cursorType);
        }
        _batchBuf.clear(ConsoleChar.init);
    }

    /// Write text string
    void writeText(dstring str)
    {
        if (!str.length)
            return;
        updateAttributes();
        if (!_batchMode)
        {
            // no batch mode, write directly to screen
            _buf.write(str, _consoleAttr);
            rawWriteText(str);
            _cursorX = _buf.cursorX;
            _cursorY = _buf.cursorY;
        }
        else
        {
            // batch mode
            _batchBuf.write(str, _consoleAttr);
            _cursorX = _batchBuf.cursorX;
            _cursorY = _batchBuf.cursorY;
        }
    }

    protected void rawSetCursor(int x, int y)
    {
        version (Windows)
        {
            SetConsoleCursorPosition(_hstdout, COORD(cast(short)x, cast(short)y));
        }
        else
        {
            import core.stdc.stdio;
            import core.stdc.string;

            char[50] buf;
            sprintf(buf.ptr, "\x1b[%d;%dH", y + 1, x + 1);
            rawWrite(cast(string)(buf[0 .. strlen(buf.ptr)]));
        }
    }

    private dstring _windowCaption;
    void setWindowCaption(dstring str)
    {
        if (_windowCaption == str)
            return;
        _windowCaption = str;
        version (Windows)
        {
            SetConsoleTitle(toUTF16z(str));
        }
        else
        {
            // TODO: ANSI terminal caption
        }
    }

    private ConsoleCursorType _rawCursorType = ConsoleCursorType.insert;
    protected void rawSetCursorType(ConsoleCursorType type)
    {
        if (_rawCursorType == type)
            return;
        version (Windows)
        {
            CONSOLE_CURSOR_INFO ci;
            final switch (type) with (ConsoleCursorType)
            {
            case insert:
                ci.dwSize = 10;
                ci.bVisible = TRUE;
                break;
            case replace:
                ci.dwSize = 100;
                ci.bVisible = TRUE;
                break;
            case hidden:
                ci.dwSize = 10;
                ci.bVisible = FALSE;
                break;
            }
            SetConsoleCursorInfo(_hstdout, &ci);
        }
        else
        {
            final switch (type) with (ConsoleCursorType)
            {
            case insert:
                rawWrite("\x1b[?25h");
                break;
            case replace:
                rawWrite("\x1b[?25h");
                break;
            case hidden:
                rawWrite("\x1b[?25l");
                break;
            }
        }
        _rawCursorType = type;
    }

    private ConsoleCursorType _cursorType = ConsoleCursorType.insert;
    void setCursorType(ConsoleCursorType type)
    {
        _cursorType = type;
        if (!_batchMode)
            rawSetCursorType(_cursorType);
    }

    protected void rawWriteTextAt(int x, int y, uint attr, dstring str)
    {
        if (!str.length)
            return;
        version (Windows)
        {
            CHAR_INFO[1000] lineBuf;
            WORD newattr = cast(WORD)((attr & 0x0F) | (((attr >> 8) & 0x0F) << 4) | (((attr >> 16) & 1) ?
                COMMON_LVB_UNDERSCORE : 0));
            for (int i = 0; i < str.length; i++)
            {
                lineBuf[i].UnicodeChar = cast(WCHAR)str[i];
                lineBuf[i].Attributes = newattr;
            }
            COORD bufSize;
            COORD bufCoord;
            bufSize.X = cast(short)str.length;
            bufSize.Y = 1;
            bufCoord.X = 0;
            bufCoord.Y = 0;
            SMALL_RECT region;
            region.Left = cast(short)x;
            region.Right = cast(short)(x + cast(int)str.length);
            region.Top = cast(short)y;
            region.Bottom = cast(short)y;
            WriteConsoleOutput(_hstdout, lineBuf.ptr, bufSize, bufCoord, &region);
        }
        else
        {
            rawSetCursor(x, y);
            rawSetAttributes(attr);
            rawWriteText(cast(dstring)str);
        }
    }

    protected void rawWriteText(dstring str)
    {
        version (Windows)
        {
            wstring s16 = toUTF16(str);
            DWORD charsWritten;
            WriteConsole(_hstdout, cast(const(void)*)s16.ptr, cast(uint)s16.length, &charsWritten, cast(void*)null);
        }
        else
        {
            string s8 = toUTF8(str);
            rawWrite(s8);
        }
    }

    version (Windows)
    {
    }
    else
    {
        private int lastTextColor = -1;
        private int lastBackgroundColor = -1;
    }
    protected void rawSetAttributes(uint attr)
    {
        version (Windows)
        {
            WORD newattr = cast(WORD)((attr & 0x0F) | (((attr >> 8) & 0x0F) << 4) | (((attr >> 16) & 1) ?
        COMMON_LVB_UNDERSCORE : 0));
            if (newattr != _attr)
            {
                _attr = newattr;
                SetConsoleTextAttribute(_hstdout, _attr);
            }
        }
        else
        {
            int textCol = (attr & 0x0F);
            int bgCol = ((attr >> 8) & 0x0F);
            textCol = (textCol & 7) + (textCol & 8 ? 90 : 30);
            bgCol = (bgCol & 7) + (bgCol & 8 ? 100 : 40);
            if (textCol == lastTextColor && bgCol == lastBackgroundColor)
                return;
            import core.stdc.stdio;
            import core.stdc.string;

            char[50] buf;
            if (textCol != lastTextColor && bgCol != lastBackgroundColor)
                sprintf(buf.ptr, "\x1b[%d;%dm", textCol, bgCol);
            else if (textCol != lastTextColor && bgCol == lastBackgroundColor)
                sprintf(buf.ptr, "\x1b[%dm", textCol);
            else
                sprintf(buf.ptr, "\x1b[%dm", bgCol);
            lastBackgroundColor = bgCol;
            lastTextColor = textCol;
            rawWrite(cast(string)buf[0 .. strlen(buf.ptr)]);
        }
    }

    protected void checkResize()
    {
        version (Windows)
        {
            CONSOLE_SCREEN_BUFFER_INFO csbi;
            if (!GetConsoleScreenBufferInfo(_hstdout, &csbi))
            {
                return;
            }
            _cursorX = csbi.dwCursorPosition.X;
            _cursorY = csbi.dwCursorPosition.Y;
            int w = csbi.srWindow.Right - csbi.srWindow.Left + 1; // csbi.dwSize.X;
            int h = csbi.srWindow.Bottom - csbi.srWindow.Top + 1; // csbi.dwSize.Y;
            if (_width != w || _height != h)
                handleConsoleResize(w, h);
        }
        else
        {
            import core.sys.posix.unistd;

            //import core.sys.posix.fcntl;
            //import core.sys.posix.termios;
            import core.sys.posix.sys.ioctl;

            winsize w;
            ioctl(STDIN_FILENO, TIOCGWINSZ, &w);
            if (_width != w.ws_col || _height != w.ws_row)
            {
                handleConsoleResize(w.ws_col, w.ws_row);
            }
        }
    }

    protected void calcAttributes()
    {
        _consoleAttr = cast(uint)_textColor | (cast(uint)_backgroundColor << 8) | (_underline ? 0x10000 : 0);
        version (Windows)
        {
            _attr = cast(WORD)(_textColor | (_backgroundColor << 4) | (_underline ? COMMON_LVB_UNDERSCORE : 0));
        }
        else
        {
        }
    }

    protected void updateAttributes()
    {
        if (_dirtyAttributes)
        {
            calcAttributes();
            if (!_batchMode)
            {
                version (Windows)
                {
                    SetConsoleTextAttribute(_hstdout, _attr);
                }
                else
                {
                    rawSetAttributes(_consoleAttr);
                }
            }
            _dirtyAttributes = false;
        }
    }

    protected bool _batchMode;
    @property bool batchMode()
    {
        return _batchMode;
    }

    @property void batchMode(bool batch)
    {
        if (_batchMode == batch)
            return;
        if (batch)
        {
            // batch mode turned ON
            _batchBuf.clear(ConsoleChar.init);
            _batchMode = true;
        }
        else
        {
            // batch mode turned OFF
            flush();
            _batchMode = false;
        }
    }

    protected bool _dirtyAttributes;
    protected ubyte _textColor;
    protected ubyte _backgroundColor;
    protected bool _underline;
    /// Get underline text attribute flag
    @property bool underline()
    {
        return _underline;
    }
    /// Set underline text attrubute flag
    @property void underline(bool flag)
    {
        if (flag != _underline)
        {
            _underline = flag;
            _dirtyAttributes = true;
        }
    }
    /// Get text color
    @property ubyte textColor()
    {
        return _textColor;
    }
    /// Set text color
    @property void textColor(ubyte color)
    {
        if (_textColor != color)
        {
            _textColor = color;
            _dirtyAttributes = true;
        }
    }
    /// Get background color
    @property ubyte backgroundColor()
    {
        return _backgroundColor;
    }
    /// Set background color
    @property void backgroundColor(ubyte color)
    {
        if (_backgroundColor != color)
        {
            _backgroundColor = color;
            _dirtyAttributes = true;
        }
    }

    /// Mouse event signal
    Listener!(bool delegate(MouseEvent)) mouseEvent;
    /// Keyboard event signal
    Listener!(bool delegate(KeyEvent)) keyEvent;
    /// Console size changed signal
    Listener!(bool delegate(int width, int height)) resizeEvent;
    /// Console input is idle
    Listener!(bool delegate()) inputIdleEvent;

    protected bool handleKeyEvent(KeyEvent event)
    {
        return keyEvent(event);
    }

    protected bool handleMouseEvent(MouseEvent event)
    {
        ButtonDetails* pbuttonDetails = null;
        if (event.button == MouseButton.left)
            pbuttonDetails = &_lbutton;
        else if (event.button == MouseButton.right)
            pbuttonDetails = &_rbutton;
        else if (event.button == MouseButton.middle)
            pbuttonDetails = &_mbutton;
        if (pbuttonDetails)
        {
            if (event.action == MouseAction.buttonDown)
            {
                pbuttonDetails.down(event.x, event.y, event.mouseMods, event.keyMods);
            }
            else if (event.action == MouseAction.buttonUp)
            {
                pbuttonDetails.up(event.x, event.y, event.mouseMods, event.keyMods);
            }
        }
        event.lbutton = _lbutton;
        event.rbutton = _rbutton;
        event.mbutton = _mbutton;
        return mouseEvent(event);
    }

    protected bool handleConsoleResize(int width, int height)
    {
        resize(width, height);
        if (resizeEvent.assigned)
            return resizeEvent(width, height);
        return false;
    }

    protected bool handleInputIdle()
    {
        checkResize();
        if (inputIdleEvent.assigned)
            return inputIdleEvent();
        return false;
    }

    private MouseMods lastMouseMods;
    private MouseButton lastButtonDown;

    protected ButtonDetails _lbutton;
    protected ButtonDetails _mbutton;
    protected ButtonDetails _rbutton;

    void stop()
    {
        // set stopped flag
        _stopped = true;
    }

    /// Wait for input, handle input
    bool pollInput()
    {
        if (_stopped)
        {
            debug Log.i("Console _stopped flag is set - returning false from pollInput");
            return false;
        }
        version (Windows)
        {
            INPUT_RECORD record;
            DWORD eventsRead;
            BOOL success = PeekConsoleInput(_hstdin, &record, 1, &eventsRead);
            if (!success)
            {
                DWORD err = GetLastError();
                _stopped = true;
                return false;
            }
            if (eventsRead == 0)
            {
                handleInputIdle();
                Sleep(1);
                return true;
            }
            success = ReadConsoleInput(_hstdin, &record, 1, &eventsRead);
            if (!success)
            {
                return false;
            }
            switch (record.EventType)
            {
            case KEY_EVENT:
                const action = record.KeyEvent.bKeyDown ? KeyAction.keyDown : KeyAction.keyUp;
                const key = cast(Key)record.KeyEvent.wVirtualKeyCode;
                const dchar ch = record.KeyEvent.UnicodeChar;
                const uint keyState = record.KeyEvent.dwControlKeyState;
                KeyMods mods;
                if (keyState & LEFT_ALT_PRESSED)
                    mods |= KeyMods.alt | KeyMods.lalt;
                if (keyState & RIGHT_ALT_PRESSED)
                    mods |= KeyMods.alt | KeyMods.ralt;
                if (keyState & LEFT_CTRL_PRESSED)
                    mods |= KeyMods.control | KeyMods.lcontrol;
                if (keyState & RIGHT_CTRL_PRESSED)
                    mods |= KeyMods.control | KeyMods.rcontrol;
                if (keyState & SHIFT_PRESSED)
                    mods |= KeyMods.shift;

                handleKeyEvent(new KeyEvent(action, key, mods));
                if (action == KeyAction.keyDown && ch)
                    handleKeyEvent(new KeyEvent(KeyAction.text, key, mods, [ch]));
                break;
            case MOUSE_EVENT:
                const short x = record.MouseEvent.dwMousePosition.X;
                const short y = record.MouseEvent.dwMousePosition.Y;
                const uint buttonState = record.MouseEvent.dwButtonState;
                const uint keyState = record.MouseEvent.dwControlKeyState;
                const uint eventFlags = record.MouseEvent.dwEventFlags;
                MouseMods mmods;
                KeyMods kmods;
                if ((keyState & LEFT_ALT_PRESSED) || (keyState & RIGHT_ALT_PRESSED))
                    kmods |= KeyMods.alt;
                if ((keyState & LEFT_CTRL_PRESSED) || (keyState & RIGHT_CTRL_PRESSED))
                    kmods |= KeyMods.control;
                if (keyState & SHIFT_PRESSED)
                    kmods |= KeyMods.shift;
                if (buttonState & FROM_LEFT_1ST_BUTTON_PRESSED)
                    mmods |= MouseMods.left;
                if (buttonState & FROM_LEFT_2ND_BUTTON_PRESSED)
                    mmods |= MouseMods.middle;
                if (buttonState & RIGHTMOST_BUTTON_PRESSED)
                    mmods |= MouseMods.right;
                bool actionSent;
                if (mmods != lastMouseMods)
                {
                    MouseButton btn = MouseButton.none;
                    MouseAction action = MouseAction.cancel;
                    if ((mmods & MouseMods.left) != (lastMouseMods & MouseMods.left))
                    {
                        btn = MouseButton.left;
                        action = (mmods & MouseMods.left) ? MouseAction.buttonDown : MouseAction.buttonUp;
                        handleMouseEvent(new MouseEvent(action, btn, mmods, kmods, x, y));
                    }
                    if ((mmods & MouseMods.right) != (lastMouseMods & MouseMods.right))
                    {
                        btn = MouseButton.right;
                        action = (mmods & MouseMods.right) ? MouseAction.buttonDown : MouseAction.buttonUp;
                        handleMouseEvent(new MouseEvent(action, btn, mmods, kmods, x, y));
                    }
                    if ((mmods & MouseMods.middle) != (lastMouseMods & MouseMods.middle))
                    {
                        btn = MouseButton.middle;
                        action = (mmods & MouseMods.middle) ? MouseAction.buttonDown : MouseAction.buttonUp;
                        handleMouseEvent(new MouseEvent(action, btn, mmods, kmods, x, y));
                    }
                    if (action != MouseAction.cancel)
                        actionSent = true;
                }
                if ((eventFlags & MOUSE_MOVED) && !actionSent)
                {
                    auto e = new MouseEvent(MouseAction.move, MouseButton.none, mmods, kmods, x, y);
                    handleMouseEvent(e);
                    actionSent = true;
                }
                if (eventFlags & MOUSE_WHEELED)
                {
                    const delta = cast(short)(buttonState >> 16);
                    auto e = new MouseEvent(MouseAction.wheel, MouseButton.none, mmods, kmods, x, y, delta);
                    handleMouseEvent(e);
                    actionSent = true;
                }
                lastMouseMods = mmods;
                break;
            case WINDOW_BUFFER_SIZE_EVENT:
                const sz = record.WindowBufferSizeEvent.dwSize;
                handleConsoleResize(sz.X, sz.Y);
                break;
            default:
                break;
            }
        }
        else
        {
            import std.algorithm : startsWith;

            if (SIGHUP_flag)
            {
                Log.i("SIGHUP signal fired");
                _stopped = true;
            }

            string s = rawRead(20);
            if (s.length == 0)
            {
                handleInputIdle();
                return !_stopped;
            }
            if (s.length == 6 && s[0] == 27 && s[1] == '[' && s[2] == 'M')
            {
                // mouse event
                MouseAction a = MouseAction.cancel;
                const int mb = s[3] - 32;
                const int mx = s[4] - 32 - 1;
                const int my = s[5] - 32 - 1;

                const int btn = mb & 3;
                if (btn < 3)
                    a = MouseAction.buttonDown;
                else
                    a = MouseAction.buttonUp;
                if (mb & 32)
                    a = MouseAction.move;

                MouseButton button;
                MouseMods mmods;
                KeyMods kmods;
                if (btn == 0)
                {
                    button = MouseButton.left;
                    mmods |= MouseMods.left;
                }
                else if (btn == 1)
                {
                    button = MouseButton.middle;
                    mmods |= MouseMods.middle;
                }
                else if (btn == 2)
                {
                    button = MouseButton.right;
                    mmods |= MouseMods.right;
                }
                else if (btn == 3 && a != MouseAction.move)
                    a = MouseAction.buttonUp;
                if (button != MouseButton.none)
                    lastButtonDown = button;
                else if (a == MouseAction.buttonUp)
                    button = lastButtonDown;
                if (mb & 4)
                    kmods |= KeyMods.shift;
                if (mb & 8)
                    kmods |= KeyMods.alt;
                if (mb & 16)
                    kmods |= KeyMods.control;
                //Log.d("mouse evt:", s, " mb=", mb, " mx=", mx, " my=", my, "  action=", a, " button=", button, " flags=", flags);
                auto evt = new MouseEvent(a, button, mmods, kmods, cast(short)mx, cast(short)my);
                handleMouseEvent(evt);
                return true;
            }

            Key key;
            KeyMods mods;
            dstring text;
            if (s[0] == 27)
            {
                string escSequence = s[1 .. $];
                //Log.d("ESC ", escSequence);
                const char letter = escSequence[$ - 1];
                if (escSequence.startsWith("[") && escSequence.length > 1)
                {
                    import std.string : indexOf;

                    string options = escSequence[1 .. $ - 1];
                    if (letter == '~')
                    {
                        string code = options;
                        const semicolonPos = options.indexOf(";");
                        if (semicolonPos >= 0)
                        {
                            code = options[0 .. semicolonPos];
                            options = options[semicolonPos + 1 .. $];
                        }
                        else
                            options = null;

                        switch (options)
                        {
                            case "5": mods = KeyMods.control; break;
                            case "2": mods = KeyMods.shift; break;
                            case "3": mods = KeyMods.alt; break;
                            case "4": mods = KeyMods.shift | KeyMods.alt; break;
                            case "6": mods = KeyMods.shift | KeyMods.control; break;
                            case "7": mods = KeyMods.alt | KeyMods.control; break;
                            case "8": mods = KeyMods.shift | KeyMods.alt | KeyMods.control; break;
                            default: break;
                        }
                        switch (code)
                        {
                            case "15": key = Key.F5; break;
                            case "17": key = Key.F6; break;
                            case "18": key = Key.F7; break;
                            case "19": key = Key.F8; break;
                            case "20": key = Key.F9; break;
                            case "21": key = Key.F10; break;
                            case "23": key = Key.F11; break;
                            case "24": key = Key.F12; break;
                            case "5":  key = Key.pageUp; break;
                            case "6":  key = Key.pageDown; break;
                            case "2":  key = Key.ins; break;
                            case "3":  key = Key.del; break;
                            default: break;
                        }
                    }
                    else
                    {
                        switch (options)
                        {
                            case "1;5": mods = KeyMods.control; break;
                            case "1;2": mods = KeyMods.shift; break;
                            case "1;3": mods = KeyMods.alt; break;
                            case "1;4": mods = KeyMods.shift | KeyMods.alt; break;
                            case "1;6": mods = KeyMods.shift | KeyMods.control; break;
                            case "1;7": mods = KeyMods.alt | KeyMods.control; break;
                            case "1;8": mods = KeyMods.shift | KeyMods.alt | KeyMods.control; break;
                            default: break;
                        }
                        switch (letter)
                        {
                            case 'A': key = Key.up; break;
                            case 'B': key = Key.down; break;
                            case 'D': key = Key.left; break;
                            case 'C': key = Key.right; break;
                            case 'H': key = Key.home; break;
                            case 'F': key = Key.end; break;
                            default: break;
                        }
                        switch (letter)
                        {
                            case 'P': key = Key.F1; break;
                            case 'Q': key = Key.F2; break;
                            case 'R': key = Key.F3; break;
                            case 'S': key = Key.F4; break;
                            default: break;
                        }
                    }
                }
                else if (escSequence.startsWith("O"))
                {
                    switch (letter)
                    {
                        case 'P': key = Key.F1; break;
                        case 'Q': key = Key.F2; break;
                        case 'R': key = Key.F3; break;
                        case 'S': key = Key.F4; break;
                        default: break;
                    }
                }
            }
            else
            {
                import std.uni : toLower;

                try
                {
                    dstring s32 = toUTF32(s);
                    if (s32.length == 1)
                    {
                        const ch = toLower(s32[0]);
                        if (ch == ' ')
                        {
                            key = Key.space;
                            text = " ";
                        }
                        else if (ch == '\t')
                            key = Key.tab;
                        else if (ch == '\n')
                            key = Key.enter;
                        else if ('a' <= ch && ch <= 'z')
                        {
                            key = cast(Key)(Key.A + ch - 'a');
                            text = s32;
                        }
                        else if ('0' <= ch && ch <= '9')
                        {
                            key = cast(Key)(Key.alpha0 + ch - '0');
                            text = s32;
                        }

                        if (1 <= s32[0] && s32[0] <= 26)
                        {
                            // ctrl + A..Z
                            key = cast(Key)(Key.A + s32[0] - 1);
                            mods = KeyMods.control;
                        }
                        if ('A' <= s32[0] && s32[0] <= 'Z')
                        {
                            // uppercase letter - with shift
                            mods = KeyMods.shift;
                        }
                    }
                    else if (s32[0] >= 32)
                        text = s32;
                }
                catch (Exception e)
                {
                    // skip invalid utf8 encoding
                }
            }
            if (key != Key.none)
            {
                auto keyDown = new KeyEvent(KeyAction.keyDown, key, mods);
                handleKeyEvent(keyDown);
                if (text.length)
                {
                    auto keyText = new KeyEvent(KeyAction.text, key, mods, text);
                    handleKeyEvent(keyText);
                }
                auto keyUp = new KeyEvent(KeyAction.keyUp, key, mods);
                handleKeyEvent(keyUp);
            }
        }
        return !_stopped;
    }
}
