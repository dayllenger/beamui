/**
Console font manager (with a single font).

Copyright: Vadim Lopatin 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.text.consolefont;

import beamui.core.config;

// dfmt off
static if (BACKEND_CONSOLE):
// dfmt on
import beamui.graphics.colors : Color;
import beamui.text.glyph;
import beamui.text.fonts;

class ConsoleFont : Font
{
    // dfmt off
    override @property const
    {
        bool isNull() { return false; }
        bool antialiased() { return false; }
        bool isFixed() { return true; }
        float spaceWidth() { return 1; }
    }
    // dfmt on

    private GlyphCache _glyphCache;

    this()
    {
        _desc.family = FontFamily.both(GenericFontFamily.monospace, "console");
        _desc.style = FontStyle.normal;
        _desc.weight = 400;
        _desc.size = 1;
        _desc.height = 1;
    }

    override float getCharWidth(dchar ch) const
    {
        return 1;
    }

    override GlyphRef getCharGlyph(dchar ch, bool withImage = true)
    {
        static immutable ubyte[1] data;

        GlyphRef g = _glyphCache.find(ch);
        if (!g)
        {
            g = new immutable(Glyph)(ch, 1, 1, 1, 0, 0, SubpixelRenderingMode.none, data[]);
            _glyphCache.put(ch, g);
        }
        return g;
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

    override protected FontRef getFontImpl(ref const FontSelector selector)
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
