/**
Text formatting and drawing.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.text;

import beamui.core.functions : max;
import beamui.core.logger;
import beamui.core.types : Point, Size;
import beamui.graphics.colors : Color;
import beamui.graphics.drawbuf;
import beamui.graphics.fonts;
import beamui.style.types : TextFlag;

/// Holds text properties - font style, colors, and so on
struct TextStyle
{
    /// Contains size, style, weight properties
    Font font;
    /// Text color
    Color color;
    /// Text background color
    Color backgroundColor;
    /// Flags like underline
    TextFlag flags;
    /// Size of the tab character in number of spaces
    int tabSize = 4;
}

/// Text style applied to a part of text line
struct MarkupUnit
{
    /// Style pointer
    TextStyle* style;
    /// Starting char index
    int start;
}

/// Text string line
struct TextLine
{
    dstring data;
    // measure data
    Glyph*[] glyphs;
    ushort[] charWidths;
    Size size;

    /**
    Measure text string to calculate char sizes and total text size.

    Supports Tab character processing and processing of menu item labels like `&File`.
    */
    void measure(const ref TextStyle style)
    {
        Font font = cast(Font)style.font;
        const bool fixed = font.isFixed;
        const ushort fixedCharWidth = cast(ushort)font.charWidth('M');
        const int spaceWidth = fixed ? fixedCharWidth : font.spaceWidth;
        const bool useKerning = !fixed && font.allowKerning;
        const bool hotkeys = (style.flags & TextFlag.hotkeys) != 0;

        const size_t len = data.length;
        charWidths.length = len;
        glyphs.length = len;
        auto pstr = data.ptr;
        auto pwidths = charWidths.ptr;
        auto pglyphs = glyphs.ptr;
        int x;
        dchar prevChar = 0;
        foreach (i; 0 .. len)
        {
            const dchar ch = pstr[i];
            if (ch == '\t')
            {
                // calculate tab stop
                int n = x / (spaceWidth * style.tabSize) + 1;
                int tabPosition = spaceWidth * style.tabSize * n;
                pwidths[i] = cast(ushort)(tabPosition - x);
                x = tabPosition;
                prevChar = 0;
                continue;
            }
            else if (hotkeys && ch == '&')
            {
                pwidths[i] = 0;
                prevChar = 0;
                continue; // skip '&' in hotkey when measuring
            }
            Glyph* glyph = font.getCharGlyph(ch);
            pglyphs[i] = glyph;
            if (fixed)
            {
                // fast calculation for fixed pitch
                pwidths[i] = fixedCharWidth;
                x += fixedCharWidth;
            }
            else
            {
                if (glyph is null)
                {
                    // if no glyph, treat as zero width
                    pwidths[i] = 0;
                    prevChar = 0;
                    continue;
                }
                // apply kerning
                int kerningDelta = useKerning && prevChar ? font.getKerningOffset(prevChar, ch) : 0;
                int w = max((glyph.widthScaled + kerningDelta + 63) >> 6,
                            glyph.originX + glyph.correctedBlackBoxX);
                pwidths[i] = cast(ushort)w;
                x += w;
            }
            prevChar = ch;
        }
        size.w = x;
        size.h = font.height;
    }

    /// Draw measured line at the position
    void draw(DrawBuf buf, Point pos, const ref TextStyle style)
    {
        Font font = cast(Font)style.font;
        // check visibility
        const Rect clip = buf.clipRect;
        if (clip.empty)
            return; // clipped out
        if (pos.y + font.height < clip.top || clip.bottom <= pos.y)
            return; // fully above or below clipping rectangle

        const bool hotkeys = (style.flags & TextFlag.hotkeys) != 0;
        const int baseline = font.baseline;
        bool underline = (style.flags & TextFlag.underline) != 0;
        const int underlineHeight = 1;
        const int underlineY = pos.y + baseline + underlineHeight * 2;

        const size_t len = data.length;
        auto pstr = data.ptr;
        auto pwidths = charWidths.ptr;
        auto pglyphs = glyphs.ptr;
        int pen = pos.x;
        foreach (i; 0 .. len)
        {
            const dchar ch = pstr[i];
            if (hotkeys && ch == '&')
            {
                if ((style.flags & TextFlag.underlineHotkeys) == TextFlag.underlineHotkeys)
                    underline = true; // turn ON underline for hotkey
                continue; // skip '&' in hotkey
            }
            // check glyph visibility
            if (clip.right < pen)
                break;
            if (pen + 255 < clip.left)
                continue; // far at left of clipping region

            ushort w = pwidths[i];
            if (w == 0)
                continue;
            if (underline)
            {
                // draw underline
                buf.fillRect(Rect(pen, underlineY, pen + w, underlineY + underlineHeight), style.color);
                // turn off underline after hotkey
                if (!(style.flags & TextFlag.underline))
                    underline = false;
            }

            if (ch == ' ' || ch == '\t')
            {
                pen += w;
                continue;
            }

            Glyph* glyph = pglyphs[i];
            assert(glyph !is null);
            if (glyph.blackBoxX && glyph.blackBoxY)
            {
                int gx = pen + glyph.originX;
                if (gx + glyph.correctedBlackBoxX < clip.left)
                    continue;
                buf.drawGlyph(gx, pos.y + baseline - glyph.originY, glyph, style.color);
            }
            pen += w;
        }
    }
}

/// Represents single-line text, which can have underlined hotkeys.
/// Properties like bold or underline affects the whole text.
struct SingleLineText
{
    @property
    {
        /// Text line data
        dstring text() const { return line.data; }
        /// ditto
        void text(dstring s)
        {
            line.data = s;
            measured = false;
        }

        /// Text line font
        Font font() { return style.font; }
        /// ditto
        void font(Font f)
        {
            style.font = f;
            measured = false;
        }

        /// Size of the tab character in spaces
        int tabSize() const { return style.tabSize; }
        /// ditto
        void tabSize(int v)
        {
            assert(1 <= v && v <= 16);
            style.tabSize = v;
            measured = false;
        }

        /// True whether there is no text
        bool empty() const
        {
            return line.data.length == 0;
        }

        /// Size of the text. Available only after `measure()` call
        Size size() const { return line.size; }
    }

    private
    {
        TextLine line;
        TextStyle style;
        bool measured;
    }

    /// Measure single-line text on layout
    void measure(TextFlag textFlags = TextFlag.unspecified)
    {
        if (empty)
            return;
        style.flags = textFlags;
        line.measure(style);
        measured = true;
    }

    /// Draw text into buffer, applying alignment
    void draw(DrawBuf buf, Point pos, int boxWidth, Color color, TextAlign alignment = TextAlign.start,
            TextFlag textFlags = TextFlag.unspecified)
    {
        if (!measured)
        {
            Log.e("not measured: ", text);
            return;
        }
        style.color = color;
        style.flags = textFlags;
        // align
        const int lineWidth = line.size.w;
        if (alignment == TextAlign.center)
        {
            pos.x += (boxWidth - lineWidth) / 2;
        }
        else if (alignment == TextAlign.end)
        {
            pos.x += boxWidth - lineWidth;
        }
        // draw
        line.draw(buf, pos, style);
    }
}

/// Represents multi-line text as is, without inner formatting.
/// Can be aligned horizontally.
struct PlainText
{
    @property
    {
        /// Text data
        dstring text() const { return lines[0].data; }
        /// ditto
        void text(dstring s)
        {
            lines.length = 1;
            lines[0].data = s;
            measured = false;
        }

        /// Text font
        Font font() { return style.font; }
        /// ditto
        void font(Font f)
        {
            style.font = f;
            measured = false;
        }

        /// Size of the tab character in spaces
        int tabSize() const { return style.tabSize; }
        /// ditto
        void tabSize(int v)
        {
            assert(1 <= v && v <= 16);
            style.tabSize = v;
            measured = false;
        }

        /// True whether there is no text
        bool empty() const
        {
            return lines.length == 0;
        }

        /// Size of the text. Available only after `measure()` call
        Size size() const { return lines[0].size; }
    }

    private
    {
        TextLine[] lines;
        TextLine[] wrappedLines;
        TextStyle style;
        bool measured;
    }

    /// Measure multiline text on layout
    void measure(TextFlag textFlags = TextFlag.unspecified)
    {
        if (empty)
            return;
        style.flags = textFlags;
        foreach (ref line; lines)
        {
            line.measure(style);
        }
        measured = true;
    }

    void wrapLines(int width)
    {
        wrappedLines = lines;
    }

    /// Draw text into buffer, applying alignment
    void draw(DrawBuf buf, Point pos, int boxWidth, Color color, TextAlign alignment = TextAlign.start,
            TextFlag textFlags = TextFlag.unspecified)
    {
        if (!measured)
        {
            Log.e("not measured: ", text);
            return;
        }
        style.color = color;
        style.flags = textFlags;
        const int lineHeight = style.font.height;
        int y = pos.y;
        auto lns = wrappedLines.length >= lines.length ? wrappedLines : lines;
        foreach (ref line; lns)
        {
            int x = pos.x;
            // align
            const int lineWidth = line.size.w;
            if (alignment == TextAlign.center)
            {
                x += (boxWidth - lineWidth) / 2;
            }
            else if (alignment == TextAlign.end)
            {
                x += boxWidth - lineWidth;
            }
            // draw
            line.draw(buf, Point(x, y), style);
            y += lineHeight;
        }
    }
}
