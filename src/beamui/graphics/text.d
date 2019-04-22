/**
Text formatting and drawing.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.text;

import std.array : Appender;
import std.uni : isAlphaNum, toLower, toUpper;
import beamui.core.collections : Buf;
import beamui.core.functions : clamp, max, move;
import beamui.core.geometry : Point, Size;
import beamui.core.logger;
import beamui.graphics.drawbuf;
import beamui.text.fonts;
import beamui.text.glyph : GlyphRef;
import beamui.text.shaping;
import beamui.text.style;

/// Positioned glyph
struct GlyphInstance
{
    GlyphRef glyph;
    Point position;
}

/// Represents a 2D sequence of glyphs with same attributes
struct TextRun
{
    GlyphInstance[] glyphs;
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

        /// Measured text line size
        Size size() const { return _size; }

        /// Returns true whether text is modified and needs to be measured again
        bool needToMeasure() const { return _needToMeasure; }
    }

    private
    {
        dstring _str;
        ComputedGlyph[] _glyphs;
        Size _size;

        bool _needToMeasure = true;
    }

    this(dstring text)
    {
        _str = text;
    }

    /** Measure text string to calculate char sizes and total text size.

        Supports tab stop processing.
    */
    void measure(Font font, ref const TextLayoutStyle style)
    {
        assert(font !is null, "Font is mandatory");

        const size_t len = _str.length;
        if (len == 0)
        {
            // trivial case; do not resize buffers
            _size = Size(0, font.height);
            _needToMeasure = false;
            return;
        }

        static Buf!ComputedGlyph shapingBuf;
        shape(_str, font, style.transform, shapingBuf);

        const int spaceWidth = font.spaceWidth;

        auto pglyphs = shapingBuf.unsafe_ptr;
        int x;
        foreach (i, ch; _str)
        {
            if (ch == '\t')
            {
                // calculate tab stop
                const n = x / (spaceWidth * style.tabSize) + 1;
                const tabPosition = spaceWidth * style.tabSize * n;
                pglyphs[i].width = cast(ushort)(tabPosition - x);
                pglyphs[i].glyph = null;
                x = tabPosition;
                continue;
            }
            x += pglyphs[i].width;
        }
        _size = Size(x, font.height);
        _needToMeasure = false;

        // copy the temporary buffer. this will be removed eventually
        if (_glyphs.length < len)
            _glyphs.length = len;
        _glyphs[0 .. len] = pglyphs[0 .. len];
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
        const pglyphs = _glyphs.ptr;
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
                lineWidth += pglyphs[i].width;
                continue;
            }
            whitespace = false;
            lineWidth += pglyphs[i].width;
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
            line._size = Size(lineWidth, _size.h);
            result ~= line;
        }
        return result;
    }

    /// Draw measured line at the position, applying alignment
    void draw(DrawBuf buf, Point pos, int boxWidth, ref const TextStyle style)
    {
        if (_str.length == 0)
            return; // nothing to draw - empty text

        Font font = (cast(TextStyle)style).font;
        assert(font);

        const int height = font.height;
        const int lineWidth = _size.w;
        if (lineWidth < boxWidth)
        {
            // align
            if (style.alignment == TextAlign.center)
            {
                pos.x += (boxWidth - lineWidth) / 2;
            }
            else if (style.alignment == TextAlign.end)
            {
                pos.x += boxWidth - lineWidth;
            }
        }
        // check visibility
        Rect clip = buf.clipRect;
        if (clip.empty)
            return; // clipped out
        clip.offset(-pos.x, -pos.y);
        if (height < clip.top || clip.bottom <= 0)
            return; // fully above or below of the clipping rectangle

        const int baseline = font.baseline;
        const underline = style.decoration.line == TextDecoration.Line.underline;
        int charUnderlinePos;
        int charUnderlineW;

        const bool drawEllipsis = boxWidth < lineWidth && style.overflow != TextOverflow.clip;
        GlyphRef ellipsis = drawEllipsis ? font.getCharGlyph('…') : null;
        const ushort ellipsisW = drawEllipsis ? ellipsis.widthScaled >> 6 : 0;
        const bool ellipsisMiddle = style.overflow == TextOverflow.ellipsisMiddle;
        const int ellipsisMiddleCorner = (boxWidth + ellipsisW) / 2;
        bool tail;
        int ellipsisPos;

        static Buf!GlyphInstance buffer;
        buffer.clear();

        auto pglyphs = _glyphs.ptr;
        int pen;
        for (uint i; i < cast(uint)_str.length; i++) // `i` can mutate
        {
            const ushort w = pglyphs[i].width;
            if (w == 0)
                continue;

            // check glyph visibility
            if (pen > clip.right)
                break;
            const int current = pen;
            pen += w;
            if (pen + 255 < clip.left)
                continue; // far at left of clipping region

            if (!underline && i == style.underlinedCharIndex)
            {
                charUnderlinePos = current;
                charUnderlineW = w;
            }

            // check overflow
            if (drawEllipsis && !tail)
            {
                if (ellipsisMiddle)
                {
                    // |text text te...xt text text|
                    //         exceeds ^ here
                    if (pen + ellipsisW > ellipsisMiddleCorner)
                    {
                        // walk to find tail width
                        int tailStart = boxWidth;
                        foreach_reverse (j; i .. cast(uint)_str.length)
                        {
                            if (tailStart - pglyphs[j].width < current + ellipsisW)
                            {
                                // jump to the tail
                                tail = true;
                                i = j;
                                pen = tailStart;
                                break;
                            }
                            else
                                tailStart -= pglyphs[j].width;
                        }
                        ellipsisPos = (current + tailStart - ellipsisW) / 2;
                        continue;
                    }
                }
                else // at the end
                {
                    // next glyph doesn't fit, so we need the current to give a space for ellipsis
                    if (pen + ellipsisW > boxWidth)
                    {
                        ellipsisPos = current;
                        break;
                    }
                }
            }

            GlyphRef glyph = pglyphs[i].glyph;
            if (glyph && glyph.blackBoxX && glyph.blackBoxY) // null if space or tab
            {
                const p = Point(current + glyph.originX, baseline - glyph.originY);
                buffer ~= GlyphInstance(glyph, p);
            }
        }
        if (drawEllipsis)
        {
            const p = Point(ellipsisPos, baseline - ellipsis.originY);
            buffer ~= GlyphInstance(ellipsis, p);
        }

        // preform actual drawing
        const decorThickness = 1 + height / 24;
        const decorColor = style.decoration.color;
        const overline = style.decoration.line == TextDecoration.Line.overline;
        const lineThrough = style.decoration.line == TextDecoration.Line.lineThrough;
        if (underline || charUnderlineW > 0)
        {
            const int underlineY = pos.y + baseline + decorThickness;
            Rect r = Rect(pos.x, underlineY, pos.x, underlineY + decorThickness);
            if (underline)
            {
                r.right += lineWidth;
            }
            else if (charUnderlineW > 0)
            {
                r.left += charUnderlinePos;
                r.right += charUnderlinePos + charUnderlineW;
            }
            buf.fillRect(r, decorColor);
        }
        if (overline)
        {
            const int overlineY = pos.y;
            const r = Rect(pos.x, overlineY, pos.x + lineWidth, overlineY + decorThickness);
            buf.fillRect(r, decorColor);
        }
        // text goes after overline and underline
        buf.drawText(pos.x, pos.y, const(TextRun)(buffer[]), style.color);
        // line-through goes over the text
        if (lineThrough)
        {
            const xheight = font.getCharGlyph('x').blackBoxY;
            const lineThroughY = pos.y + baseline - xheight / 2 - decorThickness;
            const r = Rect(pos.x, lineThroughY, pos.x + lineWidth, lineThroughY + decorThickness);
            buf.fillRect(r, decorColor);
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
            return line.str;
        }
        /// ditto
        void str(dstring s)
        {
            line.str = s;
        }

        /// True whether there is no text
        bool empty() const
        {
            return line.length == 0;
        }

        /// Size of the text after the last measure
        Size size() const
        {
            return line.size;
        }
    }

    /// Text style to adjust properties
    TextStyle style;
    private TextLine line;
    private Font oldFont;
    private TextLayoutStyle oldLayoutStyle;

    private bool needToMeasure(Font font, ref const TextLayoutStyle ls) const
    {
        return line.needToMeasure || oldFont !is font || oldLayoutStyle !is ls;
    }

    /// Measure single-line text during layout
    void measure()
    {
        auto font = style.font;
        auto ls = TextLayoutStyle(style);
        if (!needToMeasure(font, ls))
            return;

        oldFont = font;
        oldLayoutStyle = ls;
        line.measure(font, ls);
    }

    /// Draw text into buffer. Measures, if needed
    void draw(DrawBuf buf, Point pos, int boxWidth)
    {
        measure();
        line.draw(buf, pos, boxWidth, style);
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
            size_t lineStart;
            foreach (i, ch; s)
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

        /// True whether there is no text
        bool empty() const
        {
            return _lines.data.length == 0;
        }

        /// Size of the text after the last measure
        Size size() const { return _size; }
    }

    /// Text style to adjust properties
    TextStyle style;

    private
    {
        dstring original;
        Appender!(TextLine[]) _lines;
        Buf!TextLine _wrappedLines;
        Font oldFont;
        TextLayoutStyle oldLayoutStyle;
        Size _size;

        int previousWrapWidth = -1;
    }

    private bool needToMeasure(Font font, ref const TextLayoutStyle ls) const
    {
        if (oldFont !is font || oldLayoutStyle !is ls)
            return true;
        foreach (ref line; _lines.data)
            if (line.needToMeasure)
                return true;
        return false;
    }

    /// Measure multiline text during layout
    void measure()
    {
        auto font = style.font;
        auto ls = TextLayoutStyle(style);
        if (!needToMeasure(font, ls))
            return;

        oldFont = font;
        oldLayoutStyle = ls;

        Size sz;
        foreach (ref line; _lines.data)
        {
            if (line.needToMeasure)
                line.measure(font, ls);
            sz.w = max(sz.w, line.size.w);
            sz.h += line.size.h;
        }
        _size = sz;
        _wrappedLines.clear();
    }

    private bool needRewrap(int width) const
    {
        return width != previousWrapWidth || _wrappedLines.length == 0;
    }
    /// Wrap lines within a width. Measures, if needed
    void wrapLines(int width)
    {
        if (!needRewrap(width))
            return;

        measure();
        _wrappedLines.clear();
        Size sz;
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

    /// Draw text into buffer. Measures, if needed
    void draw(DrawBuf buf, Point pos, int boxWidth)
    {
        measure();

        const int lineHeight = style.font.height;
        int y = pos.y;
        auto lns = _wrappedLines.length > _lines.data.length ? _wrappedLines.unsafe_slice : _lines.data;
        foreach (ref line; lns)
        {
            line.draw(buf, Point(pos.x, y), boxWidth, style);
            y += lineHeight;
        }
    }
}
