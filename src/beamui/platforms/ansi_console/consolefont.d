/**


Copyright: Vadim Lopatin 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.ansi_console.consolefont;

import beamui.core.config;

static if (BACKEND_ANSI_CONSOLE):
import beamui.graphics.colors : Color;
import beamui.style.types : TextFlag;
import beamui.text.glyph;
import beamui.text.fonts;

class ConsoleFont : Font
{
    override @property const
    {
        bool isNull() { return false; }
        bool antialiased() { return false; }
        bool isFixed() { return true; }
        float spaceWidth() { return 1; }
    }

    private immutable(Glyph) _glyph;

    this()
    {
        _desc.face = "console";
        _desc.family = FontFamily.monospace;
        _desc.style = FontStyle.normal;
        _desc.weight = 400;
        _desc.size = 1;
        _desc.height = 1;

        immutable(Glyph) g = {
            blackBoxX: 1,
            blackBoxY: 1,
            widthPixels: 1,
            originX: 0,
            originY: 0,
            subpixelMode: SubpixelRenderingMode.none,
            glyph: [0],
        };
        _glyph = g;
    }

    override float getCharWidth(dchar ch) const { return 1; }

    override int measureText(const dchar[] text, ref int[] widths, int maxWidth = MAX_WIDTH_UNSPECIFIED,
            int tabSize = 4, int tabOffset = 0, TextFlag textFlags = TextFlag.unspecified)
    {
        if (text.length == 0)
            return 0;
        const dchar* pstr = text.ptr;
        uint len = cast(uint)text.length;
        if (widths.length < len)
            widths.length = len + 1;
        int x = 0;
        int charsMeasured = 0;
        int* pwidths = widths.ptr;
        int tabWidth = spaceWidth * tabSize; // width of full tab in pixels
        tabOffset = tabOffset % tabWidth;
        if (tabOffset < 0)
            tabOffset += tabWidth;
        foreach (int i; 0 .. len)
        {
            //auto measureStart = std.datetime.Clock.currAppTick;
            dchar ch = pstr[i];
            if (ch == '\t')
            {
                // measure tab
                int tabPosition = (x + tabWidth - tabOffset) / tabWidth * tabWidth + tabOffset;
                while (tabPosition < x + spaceWidth)
                    tabPosition += tabWidth;
                pwidths[i] = tabPosition;
                charsMeasured = i + 1;
                x = tabPosition;
                continue;
            }
            else if (ch == '&' &&
                (textFlags & (TextFlag.underlineHotkeys | TextFlag.hotkeys | TextFlag.underlineHotkeysOnAlt)))
            {
                pwidths[i] = x;
                continue; // skip '&' in hot key when measuring
            }
            int w = x + 1; // using advance
            pwidths[i] = w;
            x += 1;
            charsMeasured = i + 1;
            if (x > maxWidth)
                break;
        }
        return charsMeasured;
    }

    override void drawText(DrawBuf drawBuf, int x, int y, const dchar[] text, Color color, int tabSize = 4,
            int tabOffset = 0, TextFlag textFlags = TextFlag.unspecified)
    {
        if (text.length == 0)
            return; // nothing to draw - empty text
        import beamui.platforms.ansi_console.consoleapp;
        import beamui.platforms.ansi_console.dconsole;

        ANSIConsoleDrawBuf buf = cast(ANSIConsoleDrawBuf)drawBuf;
        if (!buf)
            return;
        if (_textSizeBuffer.length < text.length)
            _textSizeBuffer.length = text.length;
        int charsMeasured = measureText(text, _textSizeBuffer, MAX_WIDTH_UNSPECIFIED, tabSize, tabOffset, textFlags);
        Rect clip = buf.clipRect; //clipOrFullRect;
        if (clip.empty)
            return; // not visible - clipped out
        if (y + height < clip.top || y >= clip.bottom)
            return; // not visible - fully above or below clipping rectangle
        int _baseline = baseline;
        bool underline = (textFlags & TextFlag.underline) != 0;
        int underlineHeight = 1;
        int underlineY = y + _baseline + underlineHeight * 2;
        buf.console.textColor = ANSIConsoleDrawBuf.toConsoleColor(color);
        buf.console.backgroundColor = CONSOLE_TRANSPARENT_BACKGROUND;
        //Log.d("drawText: (", x, ',', y, ") '", text, "', color=", buf.console.textColor);
        foreach (int i; 0 .. charsMeasured)
        {
            dchar ch = text[i];
            if (ch == '&' &&
                (textFlags & (TextFlag.underlineHotkeys | TextFlag.hotkeys | TextFlag.underlineHotkeysOnAlt)))
            {
                if (textFlags & (TextFlag.underlineHotkeys | TextFlag.underlineHotkeysOnAlt))
                    underline = true; // turn ON underline for hot key
                continue; // skip '&' in hot key when measuring
            }
            int xx = (i > 0) ? _textSizeBuffer[i - 1] : 0;
            if (x + xx >= clip.right)
                break;
            if (x + xx < clip.left)
                continue; // far at left of clipping region

            if (underline)
            {
                // draw underline
                buf.console.underline = true;
                // turn off underline after hot key
                if (!(textFlags & TextFlag.underline))
                {
                    underline = false;
                    buf.console.underline = false;
                }
            }

            if (ch == ' ' || ch == '\t')
                continue;
            int gx = x + xx;
            if (gx < clip.left)
                continue;
            buf.console.setCursor(gx, y);
            buf.console.writeText(cast(dstring)(text[i .. i + 1]));
        }
        buf.console.underline = false;
    }

    override void drawColoredText(DrawBuf drawBuf, int x, int y, const dchar[] text,
            const CustomCharProps[] charProps, int tabSize = 4, int tabOffset = 0,
            TextFlag textFlags = TextFlag.unspecified)
    {
        if (text.length == 0)
            return; // nothing to draw - empty text

        import beamui.platforms.ansi_console.consoleapp;
        import beamui.platforms.ansi_console.dconsole;

        ANSIConsoleDrawBuf buf = cast(ANSIConsoleDrawBuf)drawBuf;

        if (_textSizeBuffer.length < text.length)
            _textSizeBuffer.length = text.length;
        int charsMeasured = measureText(text, _textSizeBuffer, MAX_WIDTH_UNSPECIFIED, tabSize, tabOffset, textFlags);
        Rect clip = buf.clipRect; //clipOrFullRect;
        if (clip.empty)
            return; // not visible - clipped out
        if (y + height < clip.top || y >= clip.bottom)
            return; // not visible - fully above or below clipping rectangle
        int _baseline = baseline;
        uint customizedTextFlags = (charProps.length ? charProps[0].textFlags : 0) | textFlags;
        bool underline = (customizedTextFlags & TextFlag.underline) != 0;
        int underlineHeight = 1;
        int underlineY = y + _baseline + underlineHeight * 2;
        buf.console.backgroundColor = CONSOLE_TRANSPARENT_BACKGROUND;
        foreach (int i; 0 .. charsMeasured)
        {
            dchar ch = text[i];
            Color color = i < charProps.length ? charProps[i].color : charProps[$ - 1].color;
            buf.console.textColor = ANSIConsoleDrawBuf.toConsoleColor(color);
            customizedTextFlags = (i < charProps.length ? charProps[i].textFlags : charProps[$ - 1].textFlags) |
                textFlags;
            underline = (customizedTextFlags & TextFlag.underline) != 0;
            // turn off underline after hot key
            if (ch == '&' &&
                    (textFlags & (TextFlag.underlineHotkeys | TextFlag.hotkeys | TextFlag
                        .underlineHotkeysOnAlt)))
            {
                // draw underline
                buf.console.underline = true;
                // turn off underline after hot key
                if (!(textFlags & TextFlag.underline))
                {
                    underline = false;
                    buf.console.underline = false;
                }
                continue; // skip '&' in hot key when measuring
            }
            int xx = (i > 0) ? _textSizeBuffer[i - 1] : 0;
            if (x + xx >= clip.right)
                break;
            if (x + xx < clip.left)
                continue; // far at left of clipping region

            if (underline)
            {
                // draw underline
                buf.console.underline = true;
                // turn off underline after hot key
                if (!(customizedTextFlags & TextFlag.underline))
                {
                    underline = false;
                    buf.console.underline = false;
                }
            }

            if (ch == ' ' || ch == '\t')
                continue;

            int gx = x + xx;
            if (gx < clip.left)
                continue;
            buf.console.setCursor(gx, y);
            buf.console.writeText(cast(dstring)(text[i .. i + 1]));
        }
    }

    override GlyphRef getCharGlyph(dchar ch, bool withImage = true)
    {
        return &_glyph;
    }

    override void checkpoint()
    {
        // ignore
    }
    override void cleanup()
    {
        // ignore
    }
    override void clearGlyphCache()
    {
        // ignore
    }

    override void clear()
    {
    }
}

class ConsoleFontManager : FontManager
{
    this()
    {
        _font = new ConsoleFont;
    }

    private FontRef _font;

    override protected FontRef getFontImpl(int size, ushort weight, bool italic, FontFamily family, string face)
    {
        return _font;
    }

    override void checkpoint()
    {
        // ignore
    }

    override void cleanup()
    {
        // ignore
    }
}
