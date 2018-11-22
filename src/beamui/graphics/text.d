/**
Text formatting and drawing.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.text;

import std.array : Appender;
import beamui.core.functions : clamp, max;
import beamui.core.logger;
import beamui.core.types : Point, Size;
import beamui.graphics.colors : Color;
import beamui.graphics.drawbuf;
import beamui.graphics.fonts;
import beamui.style.types : TextFlag;

/// Holds text properties - font style, colors, and so on
struct TextStyle
{
    @property
    {
        /// Font that also contains size, style, weight properties
        Font font() { return _font; }
        /// ditto
        void font(Font value)
        {
            if (_font !is value)
            {
                _font = value;
                _needToMeasure = true;
            }
        }
        /// Text color
        Color color() const { return _color; }
        /// ditto
        void color(Color value)
        {
            _color = value;
        }
        /// Text background color
        Color backgroundColor() const { return _backgroundColor; }
        /// ditto
        void backgroundColor(Color value)
        {
            _backgroundColor = value;
        }
        /// Flags like underline
        TextFlag flags() const { return _flags; }
        /// ditto
        void flags(TextFlag value)
        {
            if (_flags != value)
            {
                _needToMeasure = !!(_flags & TextFlag.hotkeys) != !!(value & TextFlag.hotkeys);
                _flags = value;
            }
        }
        /// Size of the tab character in number of spaces
        int tabSize() const { return _tabSize; }
        /// ditto
        void tabSize(int value)
        {
            value = clamp(value, 1, 16);
            if (_tabSize != value)
            {
                _tabSize = value;
                _needToMeasure = true;
            }
        }

        /// Returns true whether properties which affect measurement were modified
        bool needToMeasure() const { return _needToMeasure; }
    }

    private
    {
        Font _font;
        Color _color;
        Color _backgroundColor;
        TextFlag _flags;
        int _tabSize = 4;

        bool _needToMeasure = true;
    }

    /// Tell style that text measurement is done
    void measured()
    {
        _needToMeasure = false;
    }
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
    @property
    {
        /// Text data
        dstring str() const { return _str; }
        /// ditto
        void str(dstring s)
        {
            _str = s;
            _needToMeasure = true;
        }

        /// Number of characters in the line
        size_t length() const
        {
            return _str.length;
        }

        /// Glyphs array, available after measuring
        const(Glyph*[]) glyphs() const
        {
            return !_needToMeasure ? _glyphs[0 .. _str.length] : null;
        }
        /// Measured character widths
        const(ushort[]) charWidths() const
        {
            return !_needToMeasure ? _charWidths[0 .. _str.length] : null;
        }
        /// Measured text line size
        Size size() const { return _size; }

        /// Returns true whether text is modified and needs to be measured again
        bool needToMeasure() const { return _needToMeasure; }
    }

    private
    {
        dstring _str;
        Glyph*[] _glyphs;
        ushort[] _charWidths;
        Size _size;

        bool _needToMeasure = true;
    }

    this(dstring text)
    {
        _str = text;
    }

    /**
    Measure text string to calculate char sizes and total text size.

    Supports Tab character processing and processing of menu item labels like `&File`.
    */
    void measure(const ref TextStyle style)
    {
        Font font = (cast(TextStyle)style).font;
        assert(font !is null, "Font is mandatory");
        const bool fixed = font.isFixed;
        const ushort fixedCharWidth = cast(ushort)font.charWidth('M');
        const int spaceWidth = fixed ? fixedCharWidth : font.spaceWidth;
        const bool useKerning = !fixed && font.allowKerning;
        const bool hotkeys = (style.flags & TextFlag.hotkeys) != 0;

        const size_t len = _str.length;
        if (_charWidths.length < len || _charWidths.length >= len * 5)
            _charWidths.length = len;
        if (_glyphs.length < len || _glyphs.length >= len * 5)
            _glyphs.length = len;
        auto pwidths = _charWidths.ptr;
        auto pglyphs = _glyphs.ptr;
        int x;
        dchar prevChar = 0;
        foreach (i, ch; _str)
        {
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
        _size.w = x;
        _size.h = font.height;
        _needToMeasure = false;
    }

    /// Split line by width
    TextLine[] wrap(int width)
    {
        if (width <= 0)
            return null;

        import std.ascii : isWhite;

        TextLine[] result;
        const size_t len = _str.length;
        const pstr = _str.ptr;
        const pwidths = _charWidths.ptr;
        size_t lineStart;
        size_t lastWordEnd;
        int lastWordEndX;
        int lineWidth;
        bool whitespace;
        for (size_t i; i < len; i++)
        {
            const dchar ch = pstr[i];
            // split by whitespace characters
            if (isWhite(ch))
            {
                // track last word end
                if (!whitespace)
                {
                    lastWordEnd = i;
                    lastWordEndX = lineWidth;
                }
                whitespace = true;
                // skip this char
                lineWidth += pwidths[i];
                continue;
            }
            whitespace = false;
            lineWidth += pwidths[i];
            if (i > lineStart && lineWidth > width)
            {
                // need splitting
                size_t lineEnd = i;
                if (lastWordEnd > lineStart && lastWordEndX >= width / 3)
                {
                    // split on word bound
                    lineEnd = lastWordEnd;
                    lineWidth = lastWordEndX;
                }
                // add line
                TextLine line;
                line._str = _str[lineStart .. lineEnd];
                line._glyphs = _glyphs[lineStart .. lineEnd];
                line._charWidths = _charWidths[lineStart .. lineEnd];
                line._size = Size(lineWidth, _size.h);
                result ~= line;

                // find next line start
                lineStart = lineEnd;
                while (lineStart < len && isWhite(pstr[lineStart]))
                    lineStart++;
                if (lineStart == len)
                    break;

                i = lineStart - 1;
                lastWordEnd = 0;
                lastWordEndX = 0;
                lineWidth = 0;
            }
        }
        if (lineStart == 0)
        {
            // line is completely within bounds
            result = (&this)[0 .. 1];
        }
        else if (lineStart < len)
        {
            // append the last line
            TextLine line;
            line._str = _str[lineStart .. $];
            line._glyphs = _glyphs[lineStart .. $];
            line._charWidths = _charWidths[lineStart .. $];
            line._size = Size(lineWidth, _size.h);
            result ~= line;
        }
        return result;
    }

    /// Draw measured line at the position
    void draw(DrawBuf buf, Point pos, const ref TextStyle style)
    {
        Font font = (cast(TextStyle)style).font;
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

        const size_t len = _str.length;
        const pwidths = _charWidths.ptr;
        auto pglyphs = _glyphs.ptr;
        int pen = pos.x;
        foreach (i, ch; _str)
        {
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
        /// Original text data
        dstring str() const
        {
            return _line.str;
        }
        /// ditto
        void str(dstring s)
        {
            _line.str = s;
        }

        /// Get text style to adjust properties
        ref TextStyle style() { return _style; }

        /// True whether there is no text
        bool empty() const
        {
            return _line.length == 0;
        }

        /// Size of the text. Measures again, if needed
        Size size()
        {
            if (needToMeasure)
                measure();
            return _line.size;
        }

        private bool needToMeasure() const
        {
            return _line.needToMeasure || _style.needToMeasure;
        }
    }

    private
    {
        TextLine _line;
        TextStyle _style;
    }

    /// Measure single-line text on layout
    void measure()
    {
        _line.measure(_style);
        _style.measured();
    }

    /// Draw text into buffer, applying alignment. Measures, if needed
    void draw(DrawBuf buf, Point pos, int boxWidth, TextAlign alignment = TextAlign.start)
    {
        if (needToMeasure)
            measure();
        // align
        const int lineWidth = _line.size.w;
        if (alignment == TextAlign.center)
        {
            pos.x += (boxWidth - lineWidth) / 2;
        }
        else if (alignment == TextAlign.end)
        {
            pos.x += boxWidth - lineWidth;
        }
        // draw
        _line.draw(buf, pos, _style);
    }
}

/// Represents multi-line text as is, without inner formatting.
/// Can be aligned horizontally.
struct PlainText
{
    @property
    {
        /// Original text data
        dstring str() const { return original; }
        /// ditto
        void str(dstring s)
        {
            original = s;
            _lines.clear();
            _wrappedLines.clear();
            // split by EOL char
            int lineStart;
            foreach (int i, ch; s)
            {
                if (ch == '\n')
                {
                    _lines.put(TextLine(s[lineStart .. i]));
                    lineStart = i + 1;
                }
            }
            _lines.put(TextLine(s[lineStart .. $]));
        }

        const(TextLine[]) lines() const { return _lines.data; }

        /// Get text style to adjust properties
        ref TextStyle style() { return _style; }

        /// True whether there is no text
        bool empty() const
        {
            return _lines.data.length == 0;
        }

        /// Size of the text. Measures again, if needed
        Size size()
        {
            if (needToMeasure)
                measure();
            return _size;
        }

        private bool needToMeasure() const
        {
            if (_style.needToMeasure)
                return true;
            else
            {
                foreach (ref line; _lines.data)
                    if (line.needToMeasure)
                        return true;
                return false;
            }
        }

        private bool needRewrap(int width) const
        {
            return width != previousWrapWidth || _wrappedLines.data.length == 0;
        }
    }

    private
    {
        dstring original;
        Appender!(TextLine[]) _lines;
        Appender!(TextLine[]) _wrappedLines;
        TextStyle _style;
        Size _size;

        int previousWrapWidth = -1;
    }

    /// Measure multiline text on layout
    void measure()
    {
        bool force = _style.needToMeasure;
        Size sz;
        foreach (ref line; _lines.data)
        {
            if (force || line.needToMeasure)
                line.measure(_style);
            sz.w = max(sz.w, line.size.w);
            sz.h += line.size.h;
        }
        _size = sz;
        _style.measured();
        _wrappedLines.clear();
    }

    /// Wrap lines within a width. Measures, if needed
    void wrapLines(int width)
    {
        if (needToMeasure)
            measure();
        if (!needRewrap(width))
            return;

        Size sz;
        _wrappedLines.clear();
        foreach (ref line; _lines.data)
        {
            TextLine[] ls = line.wrap(width);
            foreach (ref l; ls)
            {
                sz.w = max(sz.w, l.size.w);
                sz.h += l.size.h;
            }
            _wrappedLines.put(ls);
        }
        _size = sz;
        previousWrapWidth = width;
    }

    /// Draw text into buffer, applying alignment. Measures, if needed
    void draw(DrawBuf buf, Point pos, int boxWidth, TextAlign alignment = TextAlign.start)
    {
        if (needToMeasure)
            measure();

        const int lineHeight = _style.font.height;
        int y = pos.y;
        auto lns = _wrappedLines.data.length > _lines.data.length ? _wrappedLines.data : _lines.data;
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
            line.draw(buf, Point(x, y), _style);
            y += lineHeight;
        }
    }
}
