/**
Basic text shaping, for non-complex scripts only.

Read about text shaping here:
$(LINK https://harfbuzz.github.io/what-is-harfbuzz.html#what-is-text-shaping)

This module is not intended to handle complex scripts - Indic, Arabic, etc.
At this point it is decided to keep the library relatively lightweight and
simple, not adding a massive dependency such as HarfBuzz or Pango.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.text.shaping;

import std.uni : isAlphaNum, toLower, toUpper;
import beamui.core.collections : Buf;
import beamui.core.math : max;
import beamui.text.fonts : Font;
import beamui.text.glyph : GlyphRef;
import beamui.text.style : TextTransform;

struct ComputedGlyph
{
    GlyphRef glyph;
    ushort width;
}

/** Transform the string with a uniform set of properties into a list of glyphs.

    This function queries glyphs from the font and calculate their widths.
    It can transform input text to e.g. uppercase.

    It does not perform caching. To perform appending, the function takes a buffer.
    Its resulting length is always same as the length of the passed string.
    Glyphs for non-printable characters are set to `null`.
*/
void shape(dstring str, ref Buf!ComputedGlyph output, Font font, TextTransform transform)
{
    assert(font, "Font is mandatory");

    output.clear();
    const len = cast(uint)str.length;
    if (len == 0)  // trivial case; do not resize the buffer
        return;

    const bool fixed = font.isFixed;
    const fixedCharWidth = cast(ushort)font.getCharWidth('M');
    const spaceWidth = fixed ? fixedCharWidth : cast(ushort)font.spaceWidth;
    const bool useKerning = !fixed && font.hasKerning;

    output.resize(len);

    auto pglyphs = output.unsafe_ptr;
    dchar prevChar = 0;
    foreach (i, ch; str)
    {
        // apply text transformation
        dchar trch = ch;
        if (transform == TextTransform.lowercase)
        {
            trch = toLower(ch);
        }
        else if (transform == TextTransform.uppercase)
        {
            trch = toUpper(ch);
        }
        else if (transform == TextTransform.capitalize)
        {
            if (!isAlphaNum(prevChar))
                trch = toUpper(ch);
        }
        // retrieve glyph
        GlyphRef glyph = font.getCharGlyph(trch);
        pglyphs[i].glyph = glyph;
        if (fixed)
        {
            // fast calculation for fixed pitch
            pglyphs[i].width = fixedCharWidth;
        }
        else
        {
            if (trch == ' ')
            {
                pglyphs[i].width = spaceWidth;
                prevChar = 0;
                continue;
            }
            if (glyph is null)
            {
                // if no glyph, treat as zero width
                pglyphs[i].width = 0;
                prevChar = 0;
                continue;
            }
            const kerningDelta = useKerning && prevChar ? font.getKerningOffset(prevChar, ch) : 0;
            if (kerningDelta != 0)
            {
                // shrink the previous glyph (or expand, maybe)
                pglyphs[i - 1].width += cast(short)(kerningDelta / 64);
            }
            const w = max(glyph.widthScaled >> 6, glyph.originX + glyph.correctedBlackBoxX);
            pglyphs[i].width = cast(ushort)w;
        }
        prevChar = trch;
    }
}
