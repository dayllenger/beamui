/**
Formatting and drawing of simple label-like text.

Simple means without inner markup, with no selection and cursor capabilities.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.text.simple;

import std.array : Appender;
import std.uni : isAlphaNum, toLower, toUpper;
import beamui.core.collections : Buf;
import beamui.core.functions : clamp, max, move;
import beamui.core.geometry : Point, Size;
import beamui.graphics.drawbuf;
import beamui.text.fonts;
import beamui.text.glyph : GlyphRef;
import beamui.text.shaping;
import beamui.text.style;

/// Text string line
private struct Line
{
    dstring str;
    ComputedGlyph[] glyphs;
    int width;

    /** Measure text string to calculate char sizes and total text size.

        Supports tab stop processing.
    */
    void measure(ref const TextLayoutStyle style)
    {
        Font font = cast()style.font;
        assert(font !is null, "Font is mandatory");

        const size_t len = str.length;
        if (len == 0)
        {
            // trivial case; do not resize buffers
            width = 0;
            return;
        }

        static Buf!ComputedGlyph shapingBuf;
        shape(str, font, style.transform, shapingBuf);

        const int spaceWidth = font.spaceWidth;

        auto pglyphs = shapingBuf.unsafe_ptr;
        int x;
        foreach (i, ch; str)
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
        width = x;

        // copy the temporary buffer. this will be removed eventually
        if (glyphs.length < len)
            glyphs.length = len;
        glyphs[0 .. len] = pglyphs[0 .. len];
    }

    /// Split line by width
    void wrap(int boxWidth, ref Buf!Line output)
    {
        if (boxWidth <= 0)
            return;
        if (width <= boxWidth)
        {
            output ~= this;
            return;
        }

        import std.ascii : isWhite;

        const size_t len = str.length;
        const pstr = str.ptr;
        const pglyphs = glyphs.ptr;
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
            if (i > lineStart && lineWidth > boxWidth)
            {
                // need splitting
                size_t lineEnd = i;
                if (lastWordEnd > lineStart && lastWordEndX >= boxWidth / 3)
                {
                    // split on word bound
                    lineEnd = lastWordEnd;
                    lineWidth = lastWordEndX;
                }
                // add line
                output ~= Line(str[lineStart .. lineEnd], glyphs[lineStart .. lineEnd], lineWidth);

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
        if (lineStart < len)
        {
            // append the last line
            output ~= Line(str[lineStart .. $], glyphs[lineStart .. $], lineWidth);
        }
    }

    /// Draw measured line at the position, applying alignment
    void draw(DrawBuf buf, int x, int y, int boxWidth, ref const TextStyle style)
    {
        if (str.length == 0)
            return; // nothing to draw - empty text

        Font font = (cast(TextStyle)style).font;
        assert(font);

        const int height = font.height;
        const int lineWidth = width;
        if (lineWidth < boxWidth)
        {
            // align
            if (style.alignment == TextAlign.center)
            {
                x += (boxWidth - lineWidth) / 2;
            }
            else if (style.alignment == TextAlign.end)
            {
                x += boxWidth - lineWidth;
            }
        }
        // check visibility
        Rect clip = buf.clipRect;
        if (clip.empty)
            return; // clipped out
        clip.offset(-x, -y);
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

        auto pglyphs = glyphs.ptr;
        int pen;
        for (uint i; i < cast(uint)str.length; i++) // `i` can mutate
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
                        foreach_reverse (j; i .. cast(uint)str.length)
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
            const int underlineY = y + baseline + decorThickness;
            Rect r = Rect(x, underlineY, x, underlineY + decorThickness);
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
            const int overlineY = y;
            const r = Rect(x, overlineY, x + lineWidth, overlineY + decorThickness);
            buf.fillRect(r, decorColor);
        }
        // text goes after overline and underline
        buf.drawText(x, y, buffer[], style.color);
        // line-through goes over the text
        if (lineThrough)
        {
            const xheight = font.getCharGlyph('x').blackBoxY;
            const lineThroughY = y + baseline - xheight / 2 - decorThickness;
            const r = Rect(x, lineThroughY, x + lineWidth, lineThroughY + decorThickness);
            buf.fillRect(r, decorColor);
        }
    }
}

/** Presents single- or multiline text as is, without inner formatting.

    Properties like bold or underline affect the whole text object.
    Can be aligned horizontally, can have an underlined hotkey character.
*/
struct SimpleText
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
            if (s.length > 0)
            {
                // split by EOL char
                size_t lineStart;
                foreach (i, ch; s)
                {
                    if (ch == '\n')
                    {
                        _lines.put(Line(s[lineStart .. i]));
                        lineStart = i + 1;
                    }
                }
                _lines.put(Line(s[lineStart .. $]));
            }
            measured = false;
        }

        /// True whether there is no text
        bool empty() const
        {
            return original.length == 0;
        }

        /// Size of the text after the last measure
        Size size() const { return _size; }
        /// Size of the text after the last measure and wrapping
        Size sizeAfterWrap() const { return _sizeAfterWrap; }
    }

    /// Text style to adjust properties
    TextStyle style;

    private
    {
        dstring original;
        Appender!(Line[]) _lines;
        Buf!Line _wrappedLines;
        TextLayoutStyle oldLayoutStyle;
        Size _size;
        Size _sizeAfterWrap;

        bool measured;
    }

    this(dstring txt)
    {
        str = txt;
    }

    /// Measure the text during layout
    void measure()
    {
        auto ls = TextLayoutStyle(style);
        if (measured && oldLayoutStyle is ls)
            return;

        oldLayoutStyle = ls;

        int w;
        foreach (ref line; _lines.data)
        {
            line.measure(ls);
            w = max(w, line.width);
        }
        _size.w = w;
        _size.h = ls.font.height * cast(int)_lines.data.length;
        _wrappedLines.clear();
        measured = true;
    }

    /// Wrap lines within a width, setting `sizeAfterWrap`. Measures, if needed
    void wrap(int boxWidth)
    {
        if (boxWidth == _sizeAfterWrap.w && _wrappedLines.length > 0)
            return;

        measure();
        _wrappedLines.clear();

        bool fits = true;
        foreach (ref line; _lines.data)
        {
            if (line.width > boxWidth)
            {
                fits = false;
                break;
            }
        }
        if (fits)
        {
            _sizeAfterWrap.w = boxWidth;
            _sizeAfterWrap.h = _size.h;
        }
        else
        {
            foreach (ref line; _lines.data)
                line.wrap(boxWidth, _wrappedLines);
            _sizeAfterWrap.w = boxWidth;
            _sizeAfterWrap.h = style.font.height * _wrappedLines.length;
        }
    }

    /// Draw text into buffer. Measures, if needed
    void draw(DrawBuf buf, int x, int y, int boxWidth)
    {
        measure();

        const int lineHeight = style.font.height;
        auto lns = _wrappedLines.length > _lines.data.length ? _wrappedLines.unsafe_slice : _lines.data;
        foreach (ref line; lns)
        {
            line.draw(buf, x, y, boxWidth, style);
            y += lineHeight;
        }
    }
}
