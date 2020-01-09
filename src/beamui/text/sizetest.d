/**
Text size tester.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.text.sizetest;

public import beamui.text.style : TextLayoutStyle;
import beamui.core.collections : Buf;
import beamui.core.geometry : Size;
import beamui.core.math : max;
import beamui.core.types : Tup, tup;
import beamui.text.shaping;

/** Used to determine minimal or natural sizes of text widgets.

    Supports all style properties that affect text size.
*/
struct TextSizeTester
{
    @property
    {
        /// Text data
        dstring str() const { return _str; }
        /// ditto
        void str(dstring s)
        {
            _str = s;
            oldStyle.font = null; // invalidate
        }
    }

    /// Text style to adjust properties
    TextLayoutStyle style;

    private
    {
        dstring _str;
        TextLayoutStyle oldStyle;
        Size computedSize;
    }

    /// Compute the tester size (if needed) and return it
    Size getSize()
    {
        if (oldStyle is style)
            return computedSize;

        oldStyle = style;

        return computedSize = computeTextSize(_str, style);
    }
}

/** Measure multiline text to find only its size. Caches results from previous calls.

    Example:
    ---
    Font font;
    dstring txt = "Hello";
    auto st = TextLayoutStyle(font);
    const Size sz = computeTextSize(txt, st);
    ---
*/
Size computeTextSize(dstring str, ref TextLayoutStyle style)
{
    if (!style.font || str.length == 0)
        return Size(0, 0);

    // find memoized value
    static Size[Tup!(dstring, TextLayoutStyle)] cache;
    auto args = tup(str, style);
    if (auto p = args in cache)
        return *p;

    // compute freshly if not found
    static Buf!ComputedGlyph shapingBuf;
    shape(str, shapingBuf, style.font, style.transform);

    const spaceWidth = style.font.spaceWidth;
    const int height = style.font.height;

    auto pglyphs = shapingBuf.unsafe_ptr;
    Size sz = Size(0, height);
    float w = 0;
    foreach (i, ch; str)
    {
        if (ch == '\t')
        {
            // calculate tab stop
            const n = w / (spaceWidth * style.tabSize) + 1;
            w = spaceWidth * style.tabSize * n;
            continue;
        }
        w += pglyphs[i].width;
        if (ch == '\n')
        {
            sz.w = max(sz.w, w);
            sz.h += height;
            w = 0;
        }
    }
    sz.w = max(sz.w, w);
    // memoize
    cache[args] = sz;
    return sz;
}
