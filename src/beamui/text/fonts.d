/**
Base fonts access interface and common implementation.

Font - base class for fonts.

FontManager - base class for font managers - provides access to available fonts.


Actual implementations are:

beamui.text.ftfonts - FreeType based font manager.

beamui.platforms.ansi_console.consolefont - console font manager (with single font).

beamui.platforms.windows.win32fonts - Win32 API based font manager.


See_Also: $(LINK2 $(DDOX_ROOT_DIR)beamui/graphics/drawbuf.html, DrawBuf)

Synopsis:
---
// find suitable font of size 25, normal, preferrable Arial, or, if not available, any SansSerif font
FontRef font = FontManager.instance.getFont(25, FontWeight.normal, false, FontFamily.sans_serif, "Arial");

dstring sampleText = "Sample text to draw"d;
// measure text string width and height (one line)
Size sz = font.textSize(sampleText);
// draw red text at center of DrawBuf buf
font.drawText(buf, buf.width / 2 - sz.w/2, buf.height / 2 - sz.h / 2, sampleText, 0xFF0000);
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.text.fonts;

public import beamui.core.geometry : Size;
public import beamui.text.glyph : GlyphRef, SubpixelRenderingMode;
import beamui.core.config;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types;
import beamui.graphics.colors : Color;
import beamui.graphics.drawbuf;
import beamui.style.types;
import beamui.text.glyph;

/// Font families enum
enum FontFamily : ubyte
{
    /// Unknown / not set / does not matter
    unspecified,
    /// Sans Serif font, e.g. Arial
    sans_serif,
    /// Serif font, e.g. Times New Roman
    serif,
    /// Fantasy font
    fantasy,
    /// Cursive font
    cursive,
    /// Monospace font (fixed pitch font), e.g. Courier New
    monospace
}

/// Font weight constants (0..1000)
enum FontWeight : uint
{
    /// Normal font weight
    normal = 400,
    /// Bold font
    bold = 800
}

/// Font style
enum FontStyle : ubyte
{
    normal,
    italic
}

/// Custom character properties - for char-by-char drawing of text string with different character color and style
struct CustomCharProps
{
    Color color;
    TextFlag textFlags = TextFlag.unspecified;

    this(Color color, bool underline = false, bool strikeThrough = false)
    {
        this.color = color;
        if (underline)
            this.textFlags |= TextFlag.underline;
        if (strikeThrough)
            this.textFlags |= TextFlag.strikeThrough;
    }
}

/// Constant for measureText maxWidth paramenter - to tell that all characters of text string should be measured.
enum int MAX_WIDTH_UNSPECIFIED = int.max;

/**
    Instance of font with specific size, weight, face, etc.

    Allows to measure text string and draw it on `DrawBuf`.

    Use `FontManager.instance.getFont()` to retrieve font instance.
*/
class Font : RefCountedObject
{
    @property
    {
        /// Returns font size (as requested from font engine)
        abstract int size() const;
        /// Returns actual font height including interline space
        abstract int height() const;
        /// Returns font weight
        abstract ushort weight() const;
        /// Returns baseline offset
        abstract int baseline() const;
        /// Returns true if font is italic
        abstract bool italic() const;
        /// Returns font face name
        abstract string face() const;
        /// Returns font family
        abstract FontFamily family() const;
        /// Returns true if font object is not yet initialized / loaded
        abstract bool isNull() const;

        /// Returns true if antialiasing is enabled, false if not enabled
        bool antialiased() const
        {
            return size >= FontManager.instance.minAntialiasedFontSize;
        }

        /// Returns true if font has fixed pitch (all characters have equal width)
        bool isFixed() const
        {
            if (_fixedFontDetection < 0)
            {
                with (caching(this))
                {
                    if (charWidth('i') == charWidth(' ') && charWidth('M') == charWidth('i'))
                        _fixedFontDetection = 1;
                    else
                        _fixedFontDetection = 0;
                }
            }
            return _fixedFontDetection == 1;
        }

        /// Returns width of the space character
        int spaceWidth() const
        {
            if (_spaceWidth < 0)
            {
                with (caching(this))
                {
                    _spaceWidth = charWidth(' ');
                    if (_spaceWidth <= 0)
                        _spaceWidth = charWidth('0');
                    if (_spaceWidth <= 0)
                        _spaceWidth = size;
                }
            }
            return _spaceWidth;
        }

        /// Does this font allow kerning?
        bool allowKerning() const { return _allowKerning; }
        /// ditto
        protected void allowKerning(bool allow)
        {
            _allowKerning = allow;
        }
    }

    private int _fixedFontDetection = -1;
    private int _spaceWidth = -1;
    private bool _allowKerning;

    this()
    {
        _textSizeBuffer.reserve(100);
        _textSizeBuffer.assumeSafeAppend();
    }

    ~this()
    {
        clear();
    }

    /// Returns character width
    int charWidth(dchar ch)
    {
        GlyphRef g = getCharGlyph(ch);
        return !g ? 0 : g.widthPixels;
    }

    /// Override to implement kerning offset calculation
    int getKerningOffset(dchar prevChar, dchar currentChar)
    {
        return 0;
    }

    /*******************************************************************************************
     * Measure text string, return accumulated widths[] (distance to end of n-th character), returns number of measured chars.
     *
     * Supports Tab character processing and processing of menu item labels like '&File'.
     *
     * Params:
     *          text = text string to measure
     *          widths = output buffer to put measured widths (widths[i] will be set to cumulative widths text[0..i], see also _textSizeBuffer description)
     *          maxWidth = maximum width to measure - measure is stopping if max width is reached (pass MAX_WIDTH_UNSPECIFIED to measure all characters)
     *          tabSize = tabulation size, in number of spaces
     *          tabOffset = when string is drawn not from left position, use to move tab stops left/right
     *          textFlags = TextFlag bit set - to control underline, hotkey label processing, etc...
     * Returns:
     *          number of characters measured (may be less than text.length if maxWidth is reached)
     ******************************************************************************************/
    int measureText(const dchar[] text, ref int[] widths, int maxWidth = MAX_WIDTH_UNSPECIFIED,
            int tabSize = 4, int tabOffset = 0, TextFlag textFlags = TextFlag.unspecified)
    {
        if (text.length == 0)
            return 0;
        const dchar* pstr = text.ptr;
        uint len = cast(uint)text.length;
        if (widths.length < len)
            widths.length = len;
        bool hotkeys = (textFlags & TextFlag.hotkeys) != 0;
        bool fixed = isFixed;
        bool useKerning = allowKerning && !fixed;
        int fixedCharWidth = charWidth('M');
        int x = 0;
        int charsMeasured = 0;
        int* pwidths = widths.ptr;
        int spWidth = fixed ? fixedCharWidth : spaceWidth;
        int tabWidth = spWidth * tabSize; // width of full tab in pixels
        tabOffset = tabOffset % tabWidth;
        if (tabOffset < 0)
            tabOffset += tabWidth;
        dchar prevChar = 0;
        foreach (int i; 0 .. len)
        {
            dchar ch = pstr[i];
            if (ch == '\t')
            {
                // measure tab
                int tabPosition = (x + tabWidth - tabOffset) / tabWidth * tabWidth + tabOffset;
                while (tabPosition < x + spWidth)
                    tabPosition += tabWidth;
                pwidths[i] = tabPosition;
                charsMeasured = i + 1;
                x = tabPosition;
                prevChar = 0;
                continue;
            }
            else if (hotkeys && ch == '&')
            {
                pwidths[i] = x;
                prevChar = 0;
                continue; // skip '&' in hot key when measuring
            }
            if (fixed)
            {
                // fast calculation for fixed pitch
                x += fixedCharWidth;
                pwidths[i] = x;
                charsMeasured = i + 1;
            }
            else
            {
                GlyphRef glyph = getCharGlyph(pstr[i], true); // TODO: what is better
                if (glyph is null)
                {
                    // if no glyph, use previous width - treat as zero width
                    pwidths[i] = x;
                    prevChar = 0;
                    continue;
                }
                int kerningDelta = useKerning && prevChar ? getKerningOffset(ch, prevChar) : 0;
                int width = ((glyph.widthScaled + kerningDelta + 63) >> 6);
                if (width < glyph.originX + glyph.correctedBlackBoxX)
                    width = glyph.originX + glyph.correctedBlackBoxX;
                int w = x + width; // using advance
                //int w2 = x + glyph.originX + glyph.correctedBlackBoxX; // using black box
                //if (w < w2) // choose bigger value
                //    w = w2;
                pwidths[i] = w;
                x += width;
                charsMeasured = i + 1;
            }
            if (x > maxWidth)
                break;
            prevChar = ch;
        }
        return charsMeasured;
    }

    /*************************************************************************
     * Buffer to reuse while measuring strings to avoid GC
     *
     * This array store character widths cumulatively.
     * For example, after measure of monospaced 10-pixel-width font line
     * "abc def" _textSizeBuffer should contain something like:
     * [10, 20, 30, 40, 50, 60, 70]
     ************************************************************************/
    protected int[] _textSizeBuffer;

    /*************************************************************************
     * Measure text string as single line, returns width and height
     *
     * Params:
     *          text = text string to measure
     *          maxWidth = maximum width - measure is stopping if max width is reached
     *          tabSize = tabulation size, in number of spaces
     *          tabOffset = when string is drawn not from left position, use to move tab stops left/right
     *          textFlags = TextFlag bit set - to control underline, hotkey label processing, etc...
     ************************************************************************/
    Size textSize(dstring text, int maxWidth = MAX_WIDTH_UNSPECIFIED, int tabSize = 4,
            int tabOffset = 0, TextFlag textFlags = TextFlag.unspecified)
    {
        return textSizeMemoized(this, text, maxWidth, tabSize, tabOffset, textFlags);
    }

    import std.functional : memoize;

    alias textSizeMemoized = memoize!(Font.textSizeImpl);

    static Size textSizeImpl(Font font, const dchar[] text, int maxWidth = MAX_WIDTH_UNSPECIFIED,
            int tabSize = 4, int tabOffset = 0, TextFlag textFlags = TextFlag.unspecified)
    {
        if (font._textSizeBuffer.length < text.length + 1)
            font._textSizeBuffer.length = text.length + 1;
        int charsMeasured = font.measureText(text, font._textSizeBuffer, maxWidth, tabSize, tabOffset, textFlags);
        if (charsMeasured < 1)
            return Size(0, 0);
        return Size(font._textSizeBuffer[charsMeasured - 1], font.height);
    }

    /*****************************************************************************************
     * Draw text string to buffer.
     *
     * Params:
     *      buf =   graphics buffer to draw text to
     *      x =     x coordinate to draw first character at
     *      y =     y coordinate to draw first character at
     *      text =  text string to draw
     *      color =  color for drawing of glyphs
     *      tabSize = tabulation size, in number of spaces
     *      tabOffset = when string is drawn not from left position, use to move tab stops left/right
     *      textFlags = set of TextFlag bit fields
     ****************************************************************************************/
    void drawText(DrawBuf buf, int x, int y, const dchar[] text, Color color, int tabSize = 4,
            int tabOffset = 0, TextFlag textFlags = TextFlag.unspecified)
    {
        if (text.length == 0)
            return; // nothing to draw - empty text
        if (_textSizeBuffer.length < text.length)
            _textSizeBuffer.length = text.length;
        int charsMeasured = measureText(text, _textSizeBuffer, MAX_WIDTH_UNSPECIFIED, tabSize, tabOffset, textFlags);
        Rect clip = buf.clipRect; //clipOrFullRect;
        if (clip.empty)
            return; // not visible - clipped out
        if (y + height < clip.top || y >= clip.bottom)
            return; // not visible - fully above or below clipping rectangle
        bool hotkeys = (textFlags & TextFlag.hotkeys) != 0;
        int _baseline = baseline;
        bool underline = (textFlags & TextFlag.underline) != 0;
        int underlineHeight = 1;
        int underlineY = y + _baseline + underlineHeight * 2;
        foreach (int i; 0 .. charsMeasured)
        {
            dchar ch = text[i];
            if (hotkeys && ch == '&')
            {
                if ((textFlags & TextFlag.underlineHotkeys) == TextFlag.underlineHotkeys)
                    underline = true; // turn ON underline for hot key
                continue; // skip '&' in hot key when measuring
            }
            int xx = (i > 0) ? _textSizeBuffer[i - 1] : 0;
            if (x + xx > clip.right)
                break;
            if (x + xx + 255 < clip.left)
                continue; // far at left of clipping region

            if (underline)
            {
                int xx2 = _textSizeBuffer[i];
                // draw underline
                if (xx2 > xx)
                    buf.fillRect(Rect(x + xx, underlineY, x + xx2, underlineY + underlineHeight), color);
                // turn off underline after hot key
                if (!(textFlags & TextFlag.underline))
                    underline = false;
            }

            if (ch == ' ' || ch == '\t')
                continue;
            GlyphRef glyph = getCharGlyph(ch);
            if (glyph is null)
                continue;
            if (glyph.blackBoxX && glyph.blackBoxY)
            {
                int gx = x + xx + glyph.originX;
                if (gx + glyph.correctedBlackBoxX < clip.left)
                    continue;
                buf.drawGlyph(gx, y + _baseline - glyph.originY, glyph, color);
            }
        }
    }

    /*****************************************************************************************
    * Draw text string to buffer.
    *
    * Params:
    *      buf =   graphics buffer to draw text to
    *      x =     x coordinate to draw first character at
    *      y =     y coordinate to draw first character at
    *      text =  text string to draw
    *      charProps =  array of character properties, charProps[i] are properties for character text[i]
    *      tabSize = tabulation size, in number of spaces
    *      tabOffset = when string is drawn not from left position, use to move tab stops left/right
    *      textFlags = set of TextFlag bit fields
    ****************************************************************************************/
    void drawColoredText(DrawBuf buf, int x, int y, const dchar[] text, const CustomCharProps[] charProps,
            int tabSize = 4, int tabOffset = 0, TextFlag textFlags = TextFlag.unspecified)
    {
        if (text.length == 0)
            return; // nothing to draw - empty text
        if (_textSizeBuffer.length < text.length)
            _textSizeBuffer.length = text.length;
        int charsMeasured = measureText(text, _textSizeBuffer, MAX_WIDTH_UNSPECIFIED, tabSize, tabOffset, textFlags);
        Rect clip = buf.clipRect; //clipOrFullRect;
        if (clip.empty)
            return; // not visible - clipped out
        if (y + height < clip.top || y >= clip.bottom)
            return; // not visible - fully above or below clipping rectangle
        int _baseline = baseline;
        uint customizedTextFlags = (charProps.length ? charProps[0].textFlags : 0) | textFlags;
        bool underline = (customizedTextFlags & TextFlag.underline) != 0;
        int underlineHeight = 1;
        int underlineY = y + _baseline + underlineHeight * 2;
        foreach (int i; 0 .. charsMeasured)
        {
            dchar ch = text[i];
            Color color = i < charProps.length ? charProps[i].color : charProps[$ - 1].color;
            customizedTextFlags = (i < charProps.length ? charProps[i].textFlags : charProps[$ - 1].textFlags) |
                textFlags;
            underline = (customizedTextFlags & TextFlag.underline) != 0;
            // turn off underline after hot key
            if (ch == '&' &&
                (textFlags & (TextFlag.underlineHotkeys | TextFlag.hotkeys | TextFlag.underlineHotkeysOnAlt)))
            {
                if (textFlags & (TextFlag.underlineHotkeys | TextFlag.underlineHotkeysOnAlt))
                    underline = true; // turn ON underline for hot key
                continue; // skip '&' in hot key when measuring
            }
            int xx = (i > 0) ? _textSizeBuffer[i - 1] : 0;
            if (x + xx > clip.right)
                break;
            if (x + xx + 255 < clip.left)
                continue; // far at left of clipping region

            if (underline)
            {
                int xx2 = _textSizeBuffer[i];
                // draw underline
                if (xx2 > xx)
                    buf.fillRect(Rect(x + xx, underlineY, x + xx2, underlineY + underlineHeight), color);
                // turn off underline after hot key
                if (!(customizedTextFlags & TextFlag.underline))
                    underline = false;
            }

            if (ch == ' ' || ch == '\t')
                continue;
            GlyphRef glyph = getCharGlyph(ch);
            if (glyph is null)
                continue;
            if (glyph.blackBoxX && glyph.blackBoxY)
            {
                int gx = x + xx + glyph.originX;
                if (gx + glyph.correctedBlackBoxX < clip.left)
                    continue;
                buf.drawGlyph(gx, y + _baseline - glyph.originY, glyph, color);
            }
        }
    }

    /// Get character glyph information
    abstract GlyphRef getCharGlyph(dchar ch, bool withImage = true);

    /// Clear usage flags for all entries
    abstract void checkpoint();
    /// Removes entries not used after last call of `checkpoint()` or `cleanup()`
    abstract void cleanup();
    /// Clears glyph cache
    abstract void clearGlyphCache();

    /// Cleanup resources
    void clear()
    {
    }
}

alias FontRef = Ref!Font;

/// Font instance collection - utility class, for font manager implementations
struct FontList
{
    private FontRef[] _list;

    ~this()
    {
        clear();
    }

    @property size_t length() const
    {
        return _list.length;
    }

    void clear()
    {
        foreach (ref item; _list)
        {
            item.clear();
            item = null;
        }
        _list = null;
    }

    /// Returns item by index
    ref FontRef get(size_t index)
    {
        return _list[index];
    }

    /// Find by a set of parameters - returns index of found item, -1 if not found
    ptrdiff_t find(int size, ushort weight, bool italic, FontFamily family, string face)
    {
        foreach (i, ref item; _list)
        {
            Font f = item.get;
            if (f.family != family)
                continue;
            if (f.size != size)
                continue;
            if (f.italic != italic || f.weight != weight)
                continue;
            if (f.face != face)
                continue;
            return i;
        }
        return -1;
    }
    /// Find by size only - returns index of found item, -1 if not found
    ptrdiff_t find(int size)
    {
        foreach (i, ref item; _list)
        {
            Font f = item.get;
            if (f.size == size)
                return i;
        }
        return -1;
    }

    ref FontRef add(Font item)
    {
        _list ~= FontRef(item);
        return _list[$ - 1];
    }

    /// Remove unused items - with reference count == 1
    void cleanup()
    {
        foreach (ref item; _list)
            if (item.refCount <= 1)
                item.clear();
        _list = efilter!(a => !a.isNull)(_list);
        foreach (ref item; _list)
            item.cleanup();
    }

    void checkpoint()
    {
        foreach (ref item; _list)
            item.checkpoint();
    }

    /// Clears glyph cache
    void clearGlyphCache()
    {
        foreach (ref item; _list)
            item.clearGlyphCache();
    }
}

/// Default min font size for antialiased fonts (e.g. if 16 is set, for 16+ sizes antialiasing will be used, for sizes <=15 - antialiasing will be off)
const int DEF_MIN_ANTIALIASED_FONT_SIZE = 0; // 0 means always use antialiasing

/// Hinting mode (currently supported for FreeType only)
enum HintingMode
{
    /// Based on information from font (using bytecode interpreter)
    normal,
    /// Force autohinting algorithm even if font contains hint data
    autohint,
    /// Disable hinting completely
    disabled,
    /// Light autohint (similar to Mac)
    light
}

/// Font face properties item
struct FontFaceProps
{
    /// Font face name
    string face;
    /// Font family
    FontFamily family;
}

enum int MAX_ALLOWED_FONT_SIZE = 512;

/// Access points to fonts.
class FontManager
{
    static @property
    {
        /// Font manager singleton instance
        FontManager instance() { return _instance; }
        /// ditto
        void instance(FontManager manager)
        {
            foreach (ref f; fontCache)
                f.clear();
            fontCache.clear();

            eliminate(_instance);
            _instance = manager;
        }

        /** Default font size for application, in device-independent pixels.

            Used as fallback, and also represents `1rem` CSS length. 12 pixels initially.
        */
        int defaultFontSize() { return _defaultFontSize; }
        /// ditto
        void defaultFontSize(int size)
        {
            size = clamp(size, 1, MAX_ALLOWED_FONT_SIZE);
            if (_defaultFontSize != size)
            {
                _defaultFontSize = size;
                // TODO: update!
            }
        }

        /// Min font size for antialiased fonts (0 means antialiasing always on, some big value = always off)
        int minAntialiasedFontSize() { return _minAntialiasedFontSize; }
        /// ditto
        void minAntialiasedFontSize(int size)
        {
            size = clamp(size, 1, MAX_ALLOWED_FONT_SIZE);
            if (_minAntialiasedFontSize != size)
            {
                _minAntialiasedFontSize = size;
                if (_instance)
                    _instance.clearGlyphCaches();
            }
        }

        /// Current hinting mode (normal, autoHint, disabled)
        HintingMode hintingMode() { return _hintingMode; }
        /// ditto
        void hintingMode(HintingMode mode)
        {
            if (_hintingMode != mode)
            {
                _hintingMode = mode;
                if (_instance)
                    _instance.clearGlyphCaches();
            }
        }

        /// Current subpixel rendering mode for fonts (aka ClearType)
        SubpixelRenderingMode subpixelRenderingMode() { return _subpixelRenderingMode; }
        /// ditto
        void subpixelRenderingMode(SubpixelRenderingMode mode)
        {
            _subpixelRenderingMode = mode;
        }

        /// Font gamma (1.0 is neutral, < 1.0 makes glyphs lighter, >1.0 makes glyphs bolder)
        double fontGamma() { return _fontGamma; }
        /// ditto
        void fontGamma(double v)
        {
            double gamma = clamp(v, 0.1, 4);
            if (_fontGamma != gamma)
            {
                _fontGamma = gamma;
                _gamma65.gamma = gamma;
                _gamma256.gamma = gamma;
                if (_instance)
                    _instance.clearGlyphCaches();
            }
        }
    }

    private static __gshared
    {
        FontManager _instance;
        int _defaultFontSize = 12;
        int _minAntialiasedFontSize = DEF_MIN_ANTIALIASED_FONT_SIZE;
        HintingMode _hintingMode = HintingMode.normal;
        SubpixelRenderingMode _subpixelRenderingMode = SubpixelRenderingMode.none;
        double _fontGamma = 1.0;
    }

    // Font cache for fast getFont()
    private
    {
        alias FontArgsTuple = Tup!(int, ushort, bool, FontFamily, string);
        static FontRef[FontArgsTuple] fontCache;
    }

    /// Get font instance best matched specified parameters
    final FontRef getFont(int size, ushort weight, bool italic, FontFamily family, string face)
    {
        auto t = FontArgsTuple(size, weight, italic, family, face);
        if (auto p = t in fontCache)
            return *p;
        FontRef res = getFontImpl(size, weight, italic, family, face);
        fontCache[t] = res;
        return res;
    }
    /// Non-caching implementation of `getFont()`
    abstract protected ref FontRef getFontImpl(int size, ushort weight, bool italic, FontFamily family, string face);

    /// Override to return list of font faces available
    FontFaceProps[] getFaces()
    {
        return null;
    }

    /// Clear usage flags for all entries - to clean up unused fonts
    abstract void checkpoint();

    /// Removes entries not used after last call of `checkpoint()` or `cleanup()`
    abstract void cleanup();

    /// Clear glyph cache
    void clearGlyphCaches()
    {
        // override to clear glyph caches
    }

    ~this()
    {
        Log.d("Destroying font manager");
    }
}

package(beamui) __gshared GlyphGammaTable!65 _gamma65;
package(beamui) __gshared GlyphGammaTable!256 _gamma256;

/**
    Support for font glyph gamma correction.

    Table to correct gamma and translate to output range 0..255.
    `maxv` is 65 for Win32 fonts and 256 for FreeType.
*/
final class GlyphGammaTable(int maxv)
{
    private ubyte[maxv] _map;
    private double _gamma = 1.0;

    this(double gammaValue = 1.0)
    {
        gamma(gammaValue);
    }

    @property double gamma() const { return _gamma; }

    @property void gamma(double g)
    {
        import std.math : pow, round;

        _gamma = g;
        foreach (int i; 0 .. maxv)
        {
            double v = (maxv - 1.0 - i) / maxv;
            v = pow(v, g);
            int n = 255 - cast(int)round(v * 255);
            ubyte n_clamp = cast(ubyte)clamp(n, 0, 255);
            _map[i] = n_clamp;
        }
    }

    /// Correct byte value from source range to 0..255 applying gamma
    ubyte correct(ubyte src) const
    {
        if (src >= maxv)
            src = maxv - 1;
        return _map[src];
    }
}

enum dchar UNICODE_SOFT_HYPHEN_CODE = 0x00ad;
enum dchar UNICODE_ZERO_WIDTH_SPACE = 0x200b;
enum dchar UNICODE_NO_BREAK_SPACE = 0x00a0;
enum dchar UNICODE_HYPHEN = 0x2010;
enum dchar UNICODE_NB_HYPHEN = 0x2011;

/// Find some suitable replacement for important characters missing in font
dchar getReplacementChar(dchar code)
{
    switch (code)
    {
    case UNICODE_SOFT_HYPHEN_CODE:
        return '-';
    case 0x0401: // CYRILLIC CAPITAL LETTER IO
        return 0x0415; //CYRILLIC CAPITAL LETTER IE
    case 0x0451: // CYRILLIC SMALL LETTER IO
        return 0x0435; // CYRILLIC SMALL LETTER IE
    case UNICODE_NO_BREAK_SPACE:
        return ' ';
    case 0x2010:
    case 0x2011:
    case 0x2012:
    case 0x2013:
    case 0x2014:
    case 0x2015:
        return '-';
    case 0x2018:
    case 0x2019:
    case 0x201a:
    case 0x201b:
        return '\'';
    case 0x201c:
    case 0x201d:
    case 0x201e:
    case 0x201f:
    case 0x00ab:
    case 0x00bb:
        return '\"';
    case 0x2039:
        return '<';
    case 0x203A:
    case '‣':
    case '►':
        return '>';
    case 0x2044:
        return '/';
    case 0x2022: // css_lst_disc:
        return '*';
    case 0x26AA: // css_lst_disc:
    case 0x25E6: // css_lst_disc:
    case 0x25CF: // css_lst_disc:
        return 'o';
    case 0x25CB: // css_lst_circle:
        return '*';
    case 0x25A0: // css_lst_square:
        return '-';
    case '↑': //
        return '▲';
    case '↓': //
        return '▼';
    case '▲': //
        return '^';
    case '▼': //
        return 'v';
    default:
        return 0;
    }
}
