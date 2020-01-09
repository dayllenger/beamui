/**
Formatting and drawing of simple label-like text.

Simple means without inner markup, with no selection and cursor capabilities.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.text.simple;

import std.array : Appender;
import beamui.core.collections : Buf;
import beamui.core.geometry : PointF, Size, RectF;
import beamui.core.math : max;
import beamui.core.units : snapToDevicePixels;
import beamui.graphics.colors : Color;
import beamui.graphics.drawbuf : GlyphInstance;
import beamui.graphics.painter : Painter;
import beamui.text.fonts : Font;
import beamui.text.glyph : GlyphRef;
import beamui.text.shaping;
import beamui.text.style;

/// Text string line
private struct Line
{
    dstring str;
    ComputedGlyph[] glyphs;
    float width = 0;

    /** Measure text string to calculate char sizes and total text size.

        Supports tab stop processing.
    */
    void measure(ref const TextLayoutStyle style)
    {
        Font font = cast()style.font;
        assert(font, "Font is mandatory");

        const size_t len = str.length;
        if (len == 0)
        {
            // trivial case; do not resize buffers
            width = 0;
            return;
        }

        static Buf!ComputedGlyph shapingBuf;
        shape(str, shapingBuf, font, style.transform);

        const spaceWidth = font.spaceWidth;

        auto pglyphs = shapingBuf.unsafe_ptr;
        float x = 0;
        foreach (i, ch; str)
        {
            if (ch == '\t')
            {
                // calculate tab stop
                const n = x / (spaceWidth * style.tabSize) + 1;
                const tabPosition = spaceWidth * style.tabSize * n;
                pglyphs[i].width = tabPosition - x;
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
    void wrap(float boxWidth, ref Appender!(Line[]) output)
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
        float lastWordEndX = 0;
        float lineWidth = 0;
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
    void draw(Painter pr, float x, float y, const float boxWidth, ref const TextStyle style)
    {
        if (str.length == 0)
            return; // nothing to draw - empty text

        Font font = (cast(TextStyle)style).font;
        assert(font);

        const int height = font.height;
        // check visibility
        RectF clip = pr.getLocalClipBounds();
        clip.translate(-x, -y);
        if (height < clip.top || clip.bottom <= 0)
            return; // fully above or below of the clipping rectangle

        // align, if needed
        const lineWidth = width;
        if (lineWidth < boxWidth)
        {
            if (style.alignment == TextAlign.center)
            {
                x += (boxWidth - lineWidth) / 2;
            }
            else if (style.alignment == TextAlign.end)
            {
                x += boxWidth - lineWidth;
            }
        }
        // snap to the nearest pixel
        x = snapToDevicePixels(x);
        y = snapToDevicePixels(y);

        const int baseline = font.baseline;
        const bool underline = (style.decoration.line & TextDecorLine.under) != 0;
        float charUnderlinePos = 0;
        float charUnderlineW = 0;

        const bool drawEllipsis = boxWidth < lineWidth && style.overflow != TextOverflow.clip;
        GlyphRef ellipsis = drawEllipsis ? font.getCharGlyph('…') : null;
        const ellipsisW = drawEllipsis ? ellipsis.widthPixels : 0;
        const bool ellipsisMiddle = style.overflow == TextOverflow.ellipsisMiddle;
        const float ellipsisMiddleCorner = (boxWidth + ellipsisW) / 2;
        bool tail;
        float ellipsisPos = 0;

        static Buf!GlyphInstance buffer;
        buffer.clear();

        auto pglyphs = glyphs.ptr;
        float pen = 0;
        for (uint i; i < cast(uint)str.length; i++) // `i` can mutate
        {
            const w = pglyphs[i].width;
            if (w == 0)
                continue;

            // check glyph visibility
            if (pen > clip.right)
                break;
            const current = pen;
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
                        float tailStart = boxWidth;
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
                const p = PointF(x + current + glyph.originX, y + baseline - glyph.originY);
                buffer ~= GlyphInstance(glyph, p);
            }
        }
        if (drawEllipsis)
        {
            const p = PointF(x + ellipsisPos, y + baseline - ellipsis.originY);
            buffer ~= GlyphInstance(ellipsis, p);
        }

        // preform actual drawing
        const int decorThickness = 1 + height / 24;
        const decorColor = style.decoration.color;
        const bool overline = (style.decoration.line & TextDecorLine.over) != 0;
        const bool lineThrough = (style.decoration.line & TextDecorLine.through) != 0;
        if (underline || charUnderlineW > 0)
        {
            const underlineY = y + baseline + decorThickness;
            const w = underline ? lineWidth : charUnderlineW;
            pr.fillRect(x, underlineY, w, decorThickness, decorColor);
        }
        if (overline)
        {
            const overlineY = y;
            pr.fillRect(x, overlineY, lineWidth, decorThickness, decorColor);
        }
        // text goes after overline and underline
        pr.drawText(buffer[], style.color);
        // line-through goes over the text
        if (lineThrough)
        {
            const xheight = font.getCharGlyph('x').blackBoxY;
            const lineThroughY = y + baseline - xheight / 2 - decorThickness;
            pr.fillRect(x, lineThroughY, lineWidth, decorThickness, decorColor);
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
            if (original is s)
                return;
            original = s;
            lines.clear();
            wrappedLines.clear();
            if (s.length > 0)
            {
                // split by EOL char
                size_t lineStart;
                foreach (i, ch; s)
                {
                    if (ch == '\n')
                    {
                        lines ~= Line(s[lineStart .. i]);
                        lineStart = i + 1;
                    }
                }
                lines ~= Line(s[lineStart .. $]);
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
        Appender!(Line[]) lines;
        Appender!(Line[]) wrappedLines;
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
        wrappedLines.clear();

        float w = 0;
        foreach (ref line; lines.data)
        {
            line.measure(ls);
            w = max(w, line.width);
        }
        _size.w = cast(int)w;
        _size.h = ls.font.height * cast(int)lines.data.length;
        measured = true;
    }

    /// Wrap lines within a width, setting `sizeAfterWrap`. Measures, if needed
    void wrap(float boxWidth)
    {
        if (boxWidth == _sizeAfterWrap.w && wrappedLines.data.length > 0)
            return;

        measure();
        wrappedLines.clear();

        bool fits = true;
        foreach (ref line; lines.data)
        {
            if (line.width > boxWidth)
            {
                fits = false;
                break;
            }
        }
        if (fits)
        {
            _sizeAfterWrap.w = cast(int)boxWidth;
            _sizeAfterWrap.h = _size.h;
        }
        else
        {
            foreach (ref line; lines.data)
                line.wrap(boxWidth, wrappedLines);
            _sizeAfterWrap.w = cast(int)boxWidth;
            _sizeAfterWrap.h = style.font.height * cast(int)wrappedLines.data.length;
        }
    }

    /// Draw text into buffer. Measures, if needed
    void draw(Painter pr, float x, float y, float boxWidth)
    {
        // skip early if not visible
        const clip = pr.getLocalClipBounds();
        if (clip.empty || clip.bottom <= y || clip.right <= x)
            return;

        auto lns = wrappedLines.data.length > lines.data.length ? wrappedLines.data : lines.data;
        const float lineHeight = style.font.height;
        const float height = lineHeight * lns.length;
        if (y + height < clip.top)
            return;

        measure();

        foreach (ref line; lns)
        {
            line.draw(pr, x, y, boxWidth, style);
            y += lineHeight;
        }
    }

    private void drawInternal(Painter pr, float x, float y, float boxWidth, float lineHeight)
    {
        auto lns = wrappedLines.data.length > lines.data.length ? wrappedLines.data : lines.data;
        foreach (ref line; lns)
        {
            line.draw(pr, x, y, boxWidth, style);
            y += lineHeight;
        }
    }
}

private struct SimpleTextPool
{
    int[dstring] strToIndex;
    SimpleText[] list;
    int engaged;

    SimpleText* get(dstring str)
    {
        int i = strToIndex.get(str, -1);
        if (i == -1)
        {
            if (strToIndex.length > 1024)
            {
                strToIndex.clear();
                engaged = 0;
            }
            strToIndex[str] = i = engaged;
            engaged++;
            if (list.length < engaged)
                list.length = engaged * 3 / 2 + 1;
        }
        SimpleText* txt = &list[i];
        txt.str = str;
        return txt;
    }
}
private SimpleTextPool immediate;

package(beamui) void clearSimpleTextPool()
{
    immediate = SimpleTextPool.init;
}

/// Draw simple text immediately. Useful in very dynamic and massive data lists
void drawSimpleText(Painter pr, dstring str, float x, float y, Font font, Color color)
{
    assert(font, "Font is mandatory");

    if (str.length == 0 || color.isFullyTransparent)
        return;
    // skip early if not visible
    const clip = pr.getLocalClipBounds();
    if (clip.empty || clip.bottom <= y || clip.right <= x)
        return;

    const int lineHeight = font.height;
    if (y < clip.top)
    {
        const int maxHeight = lineHeight * cast(int)(str.length + 1);
        if (y + maxHeight < clip.top)
            return;
        const int height = lineHeight * countLines(str);
        if (y + height < clip.top)
            return;
    }

    SimpleText* txt = immediate.get(str);
    TextStyle st;
    st.font = font;
    st.color = color;
    txt.style = st;
    txt.measure();
    txt.drawInternal(pr, x, y, float.max, lineHeight);
}
/// ditto
void drawSimpleText(Painter pr, dstring str, float x, float y, float boxWidth, ref TextStyle style)
{
    assert(style.font, "Font is mandatory");

    if (str.length == 0)
        return;
    // skip early if not visible
    const clip = pr.getLocalClipBounds();
    if (clip.empty || clip.bottom <= y || clip.right <= x)
        return;

    const int lineHeight = style.font.height;
    if (y < clip.top)
    {
        const int maxHeight = lineHeight * cast(int)(str.length + 1);
        if (y + maxHeight < clip.top)
            return;
        if (!style.wrap)
        {
            const int height = lineHeight * countLines(str);
            if (y + height < clip.top)
                return;
        }
    }

    SimpleText* txt = immediate.get(str);
    txt.style = style;
    txt.measure();
    if (style.wrap)
    {
        txt.wrap(boxWidth);
        if (y + txt.sizeAfterWrap.h < clip.top)
            return;
    }
    txt.drawInternal(pr, x, y, boxWidth, lineHeight);
}

private int countLines(dstring str)
{
    int count = 1;
    foreach (ch; str)
        if (ch == '\n')
            count++;
    return count;
}
