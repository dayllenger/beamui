/**
Base fonts access interface and common implementation.

Synopsis:
---
// find suitable font of size 25, normal, preferrable Arial, or, if not available, any SansSerif font
FontRef font = FontManager.instance.getFont(25, FontWeight.normal, false, FontFamily.sans_serif, "Arial");
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.text.fonts;

public import beamui.core.geometry : Size;
public import beamui.text.glyph : GlyphRef, SubpixelRenderingMode;
import beamui.core.functions : caching, clamp, DebugInstanceCount, eliminate, remove;
import beamui.core.logger;
import beamui.core.types;

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

/// Font weight constants (100..900)
enum FontWeight : ushort
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

/// Contains all needed font properties
struct FontDescription
{
    string face;
    FontFamily family;
    FontStyle style;
    ushort weight;

    int size;
    int height;
    int baseline;
    bool hasKerning;
}

/** Font instance with specific size, weight, face, etc.

    Use `FontManager.instance.getFont()` to retrieve it.
*/
class Font : RefCountedObject
{
    @property
    {
        // dfmt off
        /// Font size (as requested from font engine)
        final int size() const { return _desc.size; }
        /// Actual font height including interline space
        final int height() const { return _desc.height; }
        /// Font weight (100..900)
        final ushort weight() const { return _desc.weight; }
        /// Baseline offset
        final int baseline() const { return _desc.baseline; }
        /// True if the font style is italic
        final bool italic() const { return _desc.style == FontStyle.italic; }
        /// Font face name
        final string face() const { return _desc.face; }
        /// Font family
        final FontFamily family() const { return _desc.family; }
        /// Does this font have kerning?
        final bool hasKerning() const { return _desc.hasKerning; }
        // dfmt on

        /// Returns true if font object is not yet initialized / loaded
        abstract bool isNull() const;

        /// Returns true if antialiasing is enabled, false if not enabled
        bool antialiased() const
        {
            return size >= FontManager.minAntialiasedFontSize;
        }

        /// Returns true if font has fixed pitch (all characters have equal width)
        bool isFixed() const
        {
            if (_fixedFontDetection < 0)
            {
                with (caching(this))
                {
                    if (getCharWidth('i') == getCharWidth(' ') && getCharWidth('M') == getCharWidth('i'))
                        _fixedFontDetection = 1;
                    else
                        _fixedFontDetection = 0;
                }
            }
            return _fixedFontDetection == 1;
        }

        /// Returns width of the space character
        float spaceWidth() const
        {
            if (_spaceWidth < 0)
            {
                with (caching(this))
                {
                    _spaceWidth = getCharWidth(' ');
                    if (_spaceWidth <= 0)
                        _spaceWidth = getCharWidth('0');
                    if (_spaceWidth <= 0)
                        _spaceWidth = size;
                }
            }
            return _spaceWidth;
        }
    }

    /// Properties as detected after opening of file
    protected FontDescription _desc;
    private int _fixedFontDetection = -1;
    private float _spaceWidth = -1;

    this()
    {
        debug const count = debugPlusInstance();
        debug (resalloc)
            Log.d("Created font, count: ", count);
    }

    ~this()
    {
        debug const count = debugMinusInstance();
        debug (resalloc)
            Log.d("Destroyed font, count: ", count);
        clear();
    }

    mixin DebugInstanceCount;

    /// Returns character width
    float getCharWidth(dchar ch)
    {
        GlyphRef g = getCharGlyph(ch);
        return g ? g.widthPixels : 0;
    }

    /// Override to implement kerning offset calculation
    float getKerningOffset(dchar prevChar, dchar currentChar)
    {
        return 0;
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
        _list = remove!(a => a.isNull)(_list);
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

/// Base class for font managers. Provides access to available fonts
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
                _gamma65 = GlyphGammaTable!65(gamma);
                _gamma256 = GlyphGammaTable!256(gamma);
                if (_instance)
                    _instance.clearGlyphCaches();
            }
        }
    }

    __gshared private
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
    abstract protected FontRef getFontImpl(int size, ushort weight, bool italic, FontFamily family, string face);

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

/** Support for font glyph gamma correction.

    Table to correct gamma and translate to output range 0..255.
    `maxv` is 65 for Win32 fonts and 256 for FreeType.
*/
struct GlyphGammaTable(int maxv) if (maxv <= 256)
{
    import std.math : pow, round;

    private ubyte[maxv] _map;
    private double _gamma = 1.0;

    @disable this();

    this(double gammaValue)
    {
        _gamma = gammaValue;
        foreach (int i; 0 .. maxv)
        {
            const double v1 = (maxv - 1.0 - i) / maxv;
            const double v2 = pow(v1, gammaValue);
            const int n = 255 - cast(int)round(v2 * 255);
            _map[i] = cast(ubyte)clamp(n, 0, 255);
        }
    }

    @property double gamma() const { return _gamma; }

    /// Correct byte value from source range to 0..255 applying gamma
    ubyte correct(ubyte src) const
    {
        if (src >= maxv)
            src = maxv - 1;
        return _map[src];
    }
}

package(beamui) __gshared GlyphGammaTable!65  _gamma65  = GlyphGammaTable!65(1.0);
package(beamui) __gshared GlyphGammaTable!256 _gamma256 = GlyphGammaTable!256(1.0);

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
