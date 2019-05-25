/**
Text size tester.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.text.sizetest;

import beamui.core.collections : Buf;
import beamui.core.geometry : Size;
import beamui.text.shaping;
import beamui.text.style : TextLayoutStyle;

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

        if (style.font && _str.length > 0)
        {
            static Buf!ComputedGlyph shapingBuf;
            shape(_str, style.font, style.transform, shapingBuf);

            const int spaceWidth = style.font.spaceWidth;
            const int height = style.font.height;

            auto pglyphs = shapingBuf.unsafe_ptr;
            Size sz = Size(0, height);
            foreach (i, ch; _str)
            {
                if (ch == '\t')
                {
                    // calculate tab stop
                    const n = sz.w / (spaceWidth * style.tabSize) + 1;
                    sz.w = spaceWidth * style.tabSize * n;
                    continue;
                }
                sz.w += pglyphs[i].width;
                if (ch == '\n')
                    sz.h += height;
            }
            computedSize = sz;
        }
        else
            computedSize = Size();
        return computedSize;
    }
}
