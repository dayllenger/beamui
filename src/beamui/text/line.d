/**

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.text.line;

import std.container.array;
import beamui.core.collections : Buf;
import beamui.core.geometry : Point, Rect, Size;
import beamui.core.math;
import beamui.core.units : snapToDevicePixels;
import beamui.graphics.painter : GlyphInstance, Painter;
import beamui.text.fonts : Font, FontManager, FontStyle;
import beamui.text.glyph : GlyphRef;
import beamui.text.shaping;
import beamui.text.style;

struct FragmentGlyph
{
    GlyphRef glyph;
    float width = 0;
    int height;
    int baseline;
}

int findClosestGlyphInRow(const FragmentGlyph[] row, float x0, float x)
{
    float x1 = x0;
    foreach (i; 0 .. row.length)
    {
        x1 += row[i].width;
        const mx = (x0 + x1) / 2;
        if (x <= mx)
            return cast(int)i;
        x0 = x1;
    }
    return -1;
}

struct LineSpan
{
    uint start;
    uint end;
    float width = 0;
    float height = 0;
    float offset = 0;
}

struct TextLine
{
    @property
    {
        int glyphCount() const
        {
            return cast(int)_glyphs.length;
        }

        Size size() const
        {
            return Size(_defaultSpan.width, _defaultSpan.height);
        }

        float height() const
        {
            return _wrapSpans.length > 0 ? _sizeAfterWrap.h : _defaultSpan.height;
        }

        bool wrapped() const
        {
            return _wrapSpans.length > 0;
        }

        const(FragmentGlyph[]) glyphs() const
        {
            if (_glyphs.length > 0)
                return (&_glyphs.front())[0 .. _glyphs.length];
            else
                return null;
        }

        const(LineSpan[]) wrapSpans() const return
        {
            if (_wrapSpans.length > 0)
                return (&_wrapSpans.front())[0 .. _wrapSpans.length];
            else
                return (&_defaultSpan)[0 .. 1];
        }
    }

    dstring str;
    LineMarkup* markup;
    bool measured;

    private
    {
        LineSpan _defaultSpan;
        Size _sizeAfterWrap;

        Array!FragmentGlyph _glyphs;
        Array!LineSpan _wrapSpans;
    }

    this(dstring str)
    {
        this.str = str;
    }

    this(this) // FIXME: doesn't link without it
    {}

    void measure(ref TextLayoutStyle style)
    {
        assert(style.font, "Font is mandatory");

        if (measured)
            return;

        const len = cast(uint)str.length;
        const height = style.font.height;
        _defaultSpan = LineSpan(0, len, 0, height, 0);
        _sizeAfterWrap = Size(0, 0);
        _glyphs.length = 0;
        _wrapSpans.length = 0;

        if (len == 0)
        {
            measured = true;
            return;
        }
        if (!markup || markup.empty)
        {
            measureSimpleFragment(0, len, style);
        }
        else
        {
            uint i, start;
            measureFragment(i, start, len, style);
        }
        measured = true;
    }

    private void measureFragment(ref uint i, ref uint start, uint end, TextLayoutStyle prevStyle)
    {
        TextLayoutStyle nextStyle = void;

        while (i < markup.list.length)
        {
            MarkupUnit* mu = &markup.list[i];
            if (mu.start >= end)
                break;
            i++;
            // filter relevant attributes and make a fragment style
            const Font f = prevStyle.font;
            switch (mu.attribute.type) with (TextAttr.Type)
            {
            case fontFace:
                nextStyle = prevStyle;
                nextStyle.font = FontManager.instance.getFont(
                    f.size, f.weight, f.italic, f.family, mu.attribute.data.fontFace);
                break;
            case fontFamily:
                nextStyle = prevStyle;
                nextStyle.font = FontManager.instance.getFont(
                    f.size, f.weight, f.italic, mu.attribute.data.fontFamily, f.face);
                break;
            case fontSize:
                nextStyle = prevStyle;
                nextStyle.font = FontManager.instance.getFont(
                    mu.attribute.data.fontSize, f.weight, f.italic, f.family, f.face);
                break;
            case fontStyle:
                nextStyle = prevStyle;
                nextStyle.font = FontManager.instance.getFont(
                    f.size, f.weight, mu.attribute.data.fontStyle == FontStyle.italic, f.family, f.face);
                break;
            case fontWeight:
                nextStyle = prevStyle;
                nextStyle.font = FontManager.instance.getFont(
                    f.size, mu.attribute.data.fontWeight, f.italic, f.family, f.face);
                break;
            case transform:
                nextStyle = prevStyle;
                nextStyle.transform = mu.attribute.data.transform;
                break;
            default:
                continue;
            }
            // before
            if (start < mu.start)
                measureSimpleFragment(start, mu.start, prevStyle);
            // inside
            start = mu.start;
            measureFragment(i, start, min(mu.start + mu.count, end), nextStyle);
        }
        // after
        if (start < end)
        {
            measureSimpleFragment(start, end, prevStyle);
            start = end;
        }
    }

    private void measureSimpleFragment(uint start, uint end, ref TextLayoutStyle style)
    {
        assert(start < end);

        Font font = style.font;

        static Buf!ComputedGlyph shapingBuf;
        shape(str[start .. end], shapingBuf, font, style.transform);

        const int height = font.height;
        const baseline = font.baseline;
        const spaceWidth = font.spaceWidth;
        const int tabSize = style.tabSize;
        float x = _defaultSpan.width;
        foreach (i, ch; str[start .. end])
        {
            if (ch == '\t')
            {
                // calculate tab stops
                // TODO: turn off when text is aligned?
                const n = cast(int)x / cast(int)(spaceWidth * tabSize) + 1;
                const w = spaceWidth * tabSize * n - x;
                _glyphs ~= FragmentGlyph(null, w, height, baseline);
                x += w;
            }
            else
            {
                ComputedGlyph* g = shapingBuf.unsafe_ptr + i;
                _glyphs ~= FragmentGlyph(g.glyph, g.width, height, baseline);
                x += g.width;
            }
        }
        _defaultSpan.width = x;
        _defaultSpan.height = max(_defaultSpan.height, height);
    }

    float wrap(float boxWidth)
    {
        assert(measured);

        if (boxWidth == _sizeAfterWrap.w)
            return _sizeAfterWrap.h;

        _wrapSpans.length = 0;
        _sizeAfterWrap = Size(0, 0);

        const len = cast(uint)str.length;
        if (len == 0)
            return _defaultSpan.height;
        if (boxWidth <= 0)
            return _defaultSpan.height;
        if (_defaultSpan.width <= boxWidth)
            return _defaultSpan.height;

        import std.ascii : isWhite;

        const pstr = str.ptr;
        int totalHeight;
        float lineWidth = 0;
        int lineHeight;
        uint lineStart, lastWordEnd;
        float lastWordEndX = 0;
        bool whitespace;
        for (uint i; i < len; i++)
        {
            const dchar ch = pstr[i];
            lineHeight = max(lineHeight, _glyphs[i].height);
            // split by whitespace characters
            if (isWhite(ch))
            {
                // track the last word end
                if (!whitespace)
                {
                    lastWordEnd = i;
                    lastWordEndX = lineWidth;
                    whitespace = true;
                }
                lineWidth += _glyphs[i].width;
                continue;
            }
            whitespace = false;
            lineWidth += _glyphs[i].width;
            // split if doesn't fit
            if (i > lineStart && lineWidth > boxWidth)
            {
                uint lineEnd = i;
                if (lastWordEnd > lineStart && lastWordEndX >= boxWidth / 3)
                {
                    // split on word bound
                    lineEnd = lastWordEnd;
                    lineWidth = lastWordEndX;
                }
                // add a line
                _wrapSpans ~= LineSpan(lineStart, lineEnd, lineWidth, lineHeight);

                totalHeight += lineHeight;
                lineHeight = 0;

                // find next line start
                lineStart = lineEnd;
                while (lineStart < len && isWhite(str[lineStart]))
                    lineStart++;
                if (lineStart == len)
                    break;

                i = lineStart - 1;
                lastWordEnd = 0;
                lastWordEndX = 0;
                lineWidth = 0;
            }
        }
        _wrapSpans ~= LineSpan(lineStart, len, lineWidth, lineHeight);
        _sizeAfterWrap = Size(boxWidth, totalHeight + lineHeight);
        return _sizeAfterWrap.h;
    }

    float draw(Painter pr, float x, float y, float boxWidth, ref TextStyle style)
    {
        assert(measured);

        const len = cast(uint)_glyphs.length;
        if (len == 0)
            return 0; // nothing to draw

        const pos = Point(x, y);
        const al = markup && markup.alignmentSet ? markup.alignment : style.alignment;
        float startingOffset = 0;

        if (_wrapSpans.length > 0)
        {
            // align each line
            foreach (ref span; _wrapSpans)
                span.offset = alignHor(span.width, boxWidth, al);
            startingOffset = _wrapSpans[0].offset;

            const(LineSpan)[] wraps = (&_wrapSpans.front())[0 .. _wrapSpans.length];
            Point offset = Point(startingOffset, 0);
            if (!markup || markup.empty)
            {
                drawSimpleFragmentWrapped(pr, pos, offset, wraps, 0, len, style);
            }
            else
            {
                uint i, start;
                drawFragmentWrapped(pr, pos, offset, wraps, i, start, len, style);
            }
        }
        else // single line
        {
            startingOffset = alignHor(_defaultSpan.width, boxWidth, al);
            float offset = _defaultSpan.offset = startingOffset;
            if (!markup || markup.empty)
            {
                drawSimpleFragmentNonWrapped(pr, pos, boxWidth, offset, 0, len, style);
            }
            else
            {
                uint i, start;
                drawFragmentNonWrapped(pr, pos, boxWidth, offset, i, start, len, style);
            }
        }
        return startingOffset;
    }

    private static float alignHor(float lineWidth, float boxWidth, TextAlign a)
    {
        if (lineWidth < boxWidth)
        {
            if (a == TextAlign.center)
                return (boxWidth - lineWidth) / 2;
            else if (a == TextAlign.end)
                return boxWidth - lineWidth;
        }
        return 0;
    }

    private static bool mutateStyle(ref TextStyle prev, ref TextStyle next, MarkupUnit* mu)
    {
        // filter relevant attributes and make a fragment style
        const t = mu.attribute.type;
        if (t == TextAttr.Type.foreground)
        {
            next = prev;
            next.color = mu.attribute.data.foreground;
            return true;
        }
        if (t == TextAttr.Type.background)
        {
            next = prev;
            next.background = mu.attribute.data.background;
            return true;
        }
        if (t == TextAttr.Type.decoration)
        {
            next = prev;
            next.decoration = mu.attribute.data.decoration;
            return true;
        }
        return false;
    }

    private bool drawFragmentNonWrapped(Painter pr, Point linePos, float boxWidth,
        ref float offset, ref uint i, ref uint start, uint end, TextStyle prevStyle)
    {
        TextStyle nextStyle = void;

        while (i < markup.list.length)
        {
            MarkupUnit* mu = &markup.list[i];
            if (mu.start >= end)
                break;
            i++;
            if (!mutateStyle(prevStyle, nextStyle, mu))
                continue;
            // before
            if (start < mu.start)
                if (drawSimpleFragmentNonWrapped(pr, linePos, boxWidth, offset, start, mu.start, prevStyle))
                    return true;
            // inside
            start = mu.start;
            const end2 = min(mu.start + mu.count, end);
            if (drawFragmentNonWrapped(pr, linePos, boxWidth, offset, i, start, end2, nextStyle))
                return true;
        }
        // after
        if (start < end)
        {
            if (drawSimpleFragmentNonWrapped(pr, linePos, boxWidth, offset, start, end, prevStyle))
                return true;
            start = end;
        }
        return false;
    }

    private bool drawSimpleFragmentNonWrapped(Painter pr, Point linePos, float boxWidth,
        ref float offset, uint start, uint end, ref TextStyle style)
    {
        assert(start < end);

        static Buf!GlyphInstance buffer;
        buffer.clear();

        // snap to the nearest pixel
        linePos = snapToDevicePixels(linePos);

        auto ellipsis = Ellipsis(boxWidth, _defaultSpan.width, style.overflow, style.font);

        SimpleLine line;
        line.dx = offset;
        float pen = snapToDevicePixels(offset);
        foreach (ref fg; _glyphs[start .. end])
        {
            line.height = max(line.height, fg.height);
            line.baseline = max(line.baseline, fg.baseline);
            if (!ellipsis.shouldDraw)
            {
                // check overflow
                if (ellipsis.needed)
                {
                    // next glyph doesn't fit, so we need the current to give a space for ellipsis
                    if (pen + fg.width + ellipsis.width > boxWidth)
                    {
                        ellipsis.shouldDraw = true;
                        ellipsis.pos = pen;
                        continue;
                    }
                }
                if (auto g = fg.glyph)
                {
                    const p = Point(pen + g.originX, fg.baseline - g.originY);
                    buffer ~= GlyphInstance(g, linePos + p);
                }
                pen += fg.width;
            }
        }
        if (ellipsis.shouldDraw)
        {
            const g = ellipsis.glyph;
            const p = Point(ellipsis.pos + g.originX, line.baseline - g.originY);
            buffer ~= GlyphInstance(g, linePos + p);
        }
        line.width = pen - offset;
        line.draw(pr, linePos, buffer[], style);
        offset = pen;

        return ellipsis.shouldDraw;
    }

    private void drawFragmentWrapped(Painter pr, Point linePos, ref Point offset,
        ref const(LineSpan)[] wraps, ref uint i, ref uint start, uint end, TextStyle prevStyle)
    {
        TextStyle nextStyle = void;

        while (i < markup.list.length)
        {
            MarkupUnit* mu = &markup.list[i];
            if (mu.start >= end)
                break;
            i++;
            if (!mutateStyle(prevStyle, nextStyle, mu))
                continue;
            // before
            if (start < mu.start)
                drawSimpleFragmentWrapped(pr, linePos, offset, wraps, start, mu.start, prevStyle);
            // inside
            start = mu.start;
            drawFragmentWrapped(pr, linePos, offset, wraps, i, start, min(mu.start + mu.count, end), nextStyle);
        }
        // after
        if (start < end)
        {
            drawSimpleFragmentWrapped(pr, linePos, offset, wraps, start, end, prevStyle);
            start = end;
        }
    }

    private void drawSimpleFragmentWrapped(Painter pr, Point linePos, ref Point offset,
        ref const(LineSpan)[] wraps, uint start, uint end, ref TextStyle style)
    {
        assert(start < end);

        static Buf!GlyphInstance buffer;
        buffer.clear();

        // snap to the nearest pixel
        linePos = snapToDevicePixels(linePos);

        float xpen = snapToDevicePixels(offset.x);
        float ypen = offset.y;
        size_t passed;
        foreach (j, ref span; wraps)
        {
            if (span.end <= start)
                continue;
            if (end <= span.start)
                break;

            if (start <= span.start)
                passed = j;

            const i1 = max(span.start, start);
            const i2 = min(span.end, end);

            if (j > 0)
            {
                xpen = snapToDevicePixels(span.offset);
                ypen += span.height;
            }
            SimpleLine line;
            line.dx = xpen;
            line.dy = ypen;
            const rypen = snapToDevicePixels(ypen);
            foreach (ref fg; _glyphs[i1 .. i2])
            {
                line.height = max(line.height, fg.height);
                line.baseline = max(line.baseline, fg.baseline);
                if (auto g = fg.glyph)
                {
                    const p = Point(xpen + g.originX, rypen + fg.baseline - g.originY);
                    buffer ~= GlyphInstance(g, linePos + p);
                }
                xpen += fg.width;
            }
            line.width = xpen - line.dx;
            line.draw(pr, linePos, buffer[], style);
            buffer.clear();
        }
        if (passed > 0)
            wraps = wraps[passed .. $];
        offset.x = xpen;
        offset.y = ypen;
    }
}

private struct Ellipsis
{
    const bool needed;
    const float width = 0;
    GlyphRef glyph;
    bool shouldDraw;
    float pos = 0;

    this(float boxWidth, float lineWidth, TextOverflow p, Font f)
    {
        needed = boxWidth < lineWidth && p == TextOverflow.ellipsis;
        if (needed)
        {
            glyph = f.getCharGlyph('…');
            width = glyph.widthPixels;
        }
    }
}

private struct SimpleLine
{
    float dx = 0;
    float dy = 0;
    float width = 0;
    int height;
    int baseline;

    /// Perform actual drawing
    void draw(Painter pr, const Point pos, const GlyphInstance[] glyphs, ref TextStyle style)
    {
        const x = pos.x + dx;
        const y = pos.y + dy;
        // background
        if (!style.background.isFullyTransparent)
        {
            pr.fillRect(x, y, width, height, style.background);
        }
        // decorations
        const int decorThickness = 1 + height / 24;
        const decorColor = style.decoration.color;
        if (style.decoration.line & TextDecorLine.under)
        {
            const underlineY = y + baseline + decorThickness;
            pr.fillRect(x, underlineY, width, decorThickness, decorColor);
        }
        if (style.decoration.line & TextDecorLine.over)
        {
            const overlineY = y;
            pr.fillRect(x, overlineY, width, decorThickness, decorColor);
        }
        // text goes after overline and underline
        pr.drawText(glyphs, style.color);
        // line-through goes over the text
        if (style.decoration.line & TextDecorLine.through)
        {
            const xheight = style.font.getCharGlyph('x').blackBoxY;
            const lineThroughY = y + baseline - xheight / 2 - decorThickness;
            pr.fillRect(x, lineThroughY, width, decorThickness, decorColor);
        }
    }
}
