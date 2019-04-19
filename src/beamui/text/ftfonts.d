/**
FontManager implementation based on FreeType library.

Copyright: Vadim Lopatin 2014-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.text.ftfonts;

import beamui.core.config;

static if (USE_FREETYPE):
import std.file;
import std.string;
import derelict.freetype.ft;
import beamui.core.collections;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types : Result, Ok, Err;
import beamui.text.fonts;
import beamui.text.glyph;

package(beamui) __gshared int[string] STD_FONT_FACES;

private int stdFontFacePriority(string face)
{
    if (auto p = face in STD_FONT_FACES)
        return *p;
    else
        return 0;
}

private struct FontDef
{
    immutable FontFamily family;
    immutable string face;
    immutable bool italic;
    immutable ushort weight;

    this(FontFamily family, string face, bool italic, ushort weight)
    {
        this.family = family;
        this.face = face;
        this.italic = italic;
        this.weight = weight;
    }

    bool opEquals(ref const FontDef v) const
    {
        return family == v.family && italic == v.italic && weight == v.weight && face == v.face;
    }

    hash_t toHash() const nothrow @safe
    {
        hash_t res = 123;
        res = res * 31 + cast(hash_t)italic;
        res = res * 31 + cast(hash_t)weight;
        res = res * 31 + cast(hash_t)family;
        res = res * 31 + typeid(face).getHash(&face);
        return res;
    }
}

private class FontFileItem
{
    @property ref inout(FontDef) def() inout { return _def; }
    @property string[] filenames() { return _filenames; }
    @property FT_Library library() { return _library; }

    private FontList _activeFonts;
    private FT_Library _library;
    private FontDef _def;
    private string[] _filenames;

    this(FT_Library library, ref FontDef def)
    {
        _library = library;
        _def = def;
    }

    void addFile(string fn)
    {
        // check for duplicate entry
        foreach (ref string existing; _filenames)
            if (fn == existing)
                return;
        _filenames ~= fn;
    }

    private FontRef _nullFontRef;
    ref FontRef get(int size)
    {
        ptrdiff_t index = _activeFonts.find(size);
        if (index >= 0)
            return _activeFonts.get(index);
        auto font = new FreeTypeFont(this, size);
        if (!font.create())
        {
            destroy(font);
            return _nullFontRef;
        }
        return _activeFonts.add(font);
    }

    void clearGlyphCaches()
    {
        _activeFonts.clearGlyphCache();
    }

    void checkpoint()
    {
        _activeFonts.checkpoint();
    }

    void cleanup()
    {
        _activeFonts.cleanup();
    }
}

class FreeTypeFontFile
{
    private
    {
        string _filename;
        string _faceName;
        FT_Library _library;
        FT_Face _face;
        FT_GlyphSlot _slot;
        FT_Matrix _matrix; // transformation matrix

        int _height;
        int _size;
        int _baseline;
        ushort _weight;
        bool _italic;

        bool _allowKerning = true;
    }

    this(FT_Library library, string filename)
    {
        _library = library;
        _filename = filename;
        _matrix.xx = 0x10000;
        _matrix.yy = 0x10000;
        _matrix.xy = 0;
        _matrix.yx = 0;
        debug++_instanceCount;
        debug (FontResources)
            Log.d("Created FreeTypeFontFile, count: ", _instanceCount);
    }

    debug private static __gshared int _instanceCount;
    debug @property static int instanceCount() { return _instanceCount; }

    ~this()
    {
        clear();
        debug _instanceCount--;
        debug (FontResources)
            Log.d("Destroyed FreeTypeFontFile, count: ", _instanceCount);
    }

    @property
    {
        FT_Library library() { return _library; }

        string filename() const { return _filename; }

        // properties as detected after opening of file
        string face() const { return _faceName; }
        int height() const { return _height; }
        int size() const { return _size; }
        int baseline() const { return _baseline; }
        ushort weight() const { return _weight; }
        bool italic() const { return _italic; }
    }

    private static string familyName(FT_Face face)
    {
        string faceName = fromStringz(face.family_name).dup;
        string styleName = fromStringz(face.style_name).dup;
        if (faceName == "Arial" && styleName == "Narrow")
            faceName ~= " Narrow";
        else if (styleName == "Condensed")
            faceName ~= " Condensed";
        return faceName;
    }

    /// Open face with specified size
    bool open(int size, int index = 0)
    {
        int error = FT_New_Face(_library, _filename.toStringz, index, &_face); /* create face object */
        if (error)
            return false;
        if (_filename.endsWith(".pfb") || _filename.endsWith(".pfa"))
        {
            string kernFile = _filename[0 .. $ - 4];
            if (exists(kernFile ~ ".afm"))
            {
                kernFile ~= ".afm";
            }
            else if (exists(kernFile ~ ".pfm"))
            {
                kernFile ~= ".pfm";
            }
            else
            {
                destroy(kernFile);
            }
            if (kernFile.length > 0)
                error = FT_Attach_File(_face, kernFile.toStringz);
        }
        debug (FontResources)
            Log.d("Font file opened successfully");
        _slot = _face.glyph;
        _faceName = familyName(_face);
        error = FT_Set_Pixel_Sizes(_face, /* handle to face object */
                0, /* pixel_width           */
                size); /* pixel_height          */
        if (error)
        {
            clear();
            return false;
        }
        _height = cast(int)((_face.size.metrics.height + 63) >> 6);
        _size = size;
        _baseline = _height + cast(int)(_face.size.metrics.descender >> 6);
        _weight = _face.style_flags & FT_STYLE_FLAG_BOLD ? FontWeight.bold : FontWeight.normal;
        _italic = _face.style_flags & FT_STYLE_FLAG_ITALIC ? true : false;
        debug (FontResources)
            Log.d("Opened font face=", _faceName, " height=", _height, " size=", size, " weight=",
                    weight, " italic=", italic);
        return true; // successfully opened
    }

    /// Find glyph index for character
    FT_UInt getCharIndex(dchar code, dchar def_char = 0)
    {
        if (code == '\t')
            code = ' ';
        FT_UInt index = FT_Get_Char_Index(_face, code);
        if (index == 0)
        {
            dchar replacement = getReplacementChar(code);
            if (replacement)
            {
                index = FT_Get_Char_Index(_face, replacement);
                if (index == 0)
                {
                    replacement = getReplacementChar(replacement);
                    if (replacement)
                    {
                        index = FT_Get_Char_Index(_face, replacement);
                    }
                }
            }
            if (index == 0 && def_char)
                index = FT_Get_Char_Index(_face, def_char);
        }
        return index;
    }

    /// Allow kerning
    @property bool allowKerning()
    {
        return FT_HAS_KERNING(_face);
    }

    /// Retrieve glyph information, filling glyph struct; returns `Err` if glyph is not found
    Result!GlyphRef getGlyphInfo(dchar code, dchar def_char, bool withImage = true)
    {
        const int glyph_index = getCharIndex(code, def_char);
        int flags = FT_LOAD_DEFAULT;
        const bool _drawMonochrome = _size < FontManager.minAntialiasedFontSize;
        const subpixel = _drawMonochrome ? SubpixelRenderingMode.none : FontManager.subpixelRenderingMode;
        flags |= (!_drawMonochrome ? (subpixel ? FT_LOAD_TARGET_LCD
                : (FontManager.instance.hintingMode == HintingMode.light ?
                FT_LOAD_TARGET_LIGHT : FT_LOAD_TARGET_NORMAL)) : FT_LOAD_TARGET_MONO);
        if (withImage)
            flags |= FT_LOAD_RENDER;
        if (FontManager.instance.hintingMode == HintingMode.autohint ||
                FontManager.instance.hintingMode == HintingMode.light)
            flags |= FT_LOAD_FORCE_AUTOHINT;
        else if (FontManager.instance.hintingMode == HintingMode.disabled)
            flags |= FT_LOAD_NO_AUTOHINT | FT_LOAD_NO_HINTING;
        int error = FT_Load_Glyph(_face, /* handle to face object */
                glyph_index, /* glyph index           */
                flags); /* load flags, see below */
        if (error)
            return Err!GlyphRef;
        auto glyph = new Glyph;
        glyph.blackBoxX = cast(ushort)((_slot.metrics.width + 32) >> 6);
        glyph.blackBoxY = cast(ubyte)((_slot.metrics.height + 32) >> 6);
        glyph.originX = cast(byte)((_slot.metrics.horiBearingX + 32) >> 6);
        glyph.originY = cast(byte)((_slot.metrics.horiBearingY + 32) >> 6);
        glyph.widthScaled = cast(ushort)(myabs(cast(int)(_slot.metrics.horiAdvance)));
        glyph.widthPixels = cast(ubyte)(myabs(cast(int)(_slot.metrics.horiAdvance + 32)) >> 6);
        glyph.subpixelMode = subpixel;
        //glyph.glyphIndex = cast(ushort)code;
        if (withImage)
        {
            FT_Bitmap* bitmap = &_slot.bitmap;
            ushort w = cast(ushort)(bitmap.width);
            ubyte h = cast(ubyte)(bitmap.rows);
            glyph.blackBoxX = w;
            glyph.blackBoxY = h;
            glyph.originX = cast(byte)(_slot.bitmap_left);
            glyph.originY = cast(byte)(_slot.bitmap_top);
            int sz = w * cast(int)h;
            if (sz > 0)
            {
                glyph.glyph = new ubyte[sz];
                if (_drawMonochrome)
                {
                    // monochrome bitmap
                    ubyte mask = 0x80;
                    ubyte* ptr = bitmap.buffer;
                    ubyte* dst = glyph.glyph.ptr;
                    foreach (y; 0 .. h)
                    {
                        ubyte* row = ptr;
                        mask = 0x80;
                        foreach (x; 0 .. w)
                        {
                            *dst++ = (*row & mask) ? 0xFF : 00;
                            mask >>= 1;
                            if (!mask && x != w - 1)
                            {
                                mask = 0x80;
                                row++;
                            }
                        }
                        ptr += bitmap.pitch;
                    }

                }
                else
                {
                    // antialiased
                    foreach (y; 0 .. h)
                    {
                        foreach (x; 0 .. w)
                        {
                            glyph.glyph[y * w + x] = _gamma256.correct(bitmap.buffer[y * bitmap.pitch + x]);
                        }
                    }
                }
            }
            static if (USE_OPENGL)
            {
                glyph.id = nextGlyphID();
            }
        }
        return Ok(cast(GlyphRef)glyph);
    }

    @property bool isNull() const
    {
        return (_face is null);
    }

    void clear()
    {
        if (_face !is null)
            FT_Done_Face(_face);
        _face = null;
    }

    int getKerningOffset(FT_UInt prevCharIndex, FT_UInt nextCharIndex)
    {
        const FT_KERNING_DEFAULT = 0;
        FT_Vector delta;
        int error = FT_Get_Kerning(_face, /* handle to face object */
                prevCharIndex, /* left glyph index      */
                nextCharIndex, /* right glyph index     */
                FT_KERNING_DEFAULT, /* kerning mode          */
                &delta); /* target vector         */
        const RSHIFT = 0;
        if (!error)
            return cast(int)((delta.x) >> RSHIFT);
        return 0;
    }
}

/**
    Font implementation based on FreeType.
*/
class FreeTypeFont : Font
{
    override @property const
    {
        int size() { return _size; }

        int height()
        {
            return _files.count > 0 ? _files[0].height : _size;
        }
        ushort weight()
        {
            return _fontItem.def.weight;
        }
        int baseline()
        {
            return _files.count > 0 ? _files[0].baseline : 0;
        }
        bool italic()
        {
            return _fontItem.def.italic;
        }
        string face()
        {
            return _fontItem.def.face;
        }
        FontFamily family()
        {
            return _fontItem.def.family;
        }
        bool isNull()
        {
            return _files.empty;
        }
    }

    private
    {
        FontFileItem _fontItem;
        Collection!(FreeTypeFontFile, true) _files;

        int _size;
        int _height;

        GlyphCache _glyphCache;
    }

    debug private static __gshared int _instanceCount;
    debug @property static int instanceCount() { return _instanceCount; }

    this(FontFileItem item, int size)
    {
        _fontItem = item;
        _size = size;
        _height = size;
        allowKerning = true;
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created font, count: ", _instanceCount);
    }

    ~this()
    {
        clear();
        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed font, count: ", _instanceCount);
    }

    override void clear()
    {
        _files.clear();
    }

    /// Find glyph index for character
    bool findGlyph(dchar code, dchar def_char, ref FT_UInt index, ref FreeTypeFontFile file)
    {
        foreach (FreeTypeFontFile f; _files)
        {
            index = f.getCharIndex(code, def_char);
            if (index != 0)
            {
                file = f;
                return true;
            }
        }
        return false;
    }

    /// Get kerning between two chars
    override int getKerningOffset(dchar prevChar, dchar currentChar)
    {
        if (!allowKerning || !prevChar || !currentChar)
            return 0;
        FT_UInt index1;
        FreeTypeFontFile file1;
        if (!findGlyph(prevChar, 0, index1, file1))
            return 0;
        FT_UInt index2;
        FreeTypeFontFile file2;
        if (!findGlyph(currentChar, 0, index2, file2))
            return 0;
        if (file1 !is file2)
            return 0;
        return file1.getKerningOffset(index1, index2);
    }

    override GlyphRef getCharGlyph(dchar ch, bool withImage = true)
    {
        if (ch > 0xFFFF) // do not support unicode chars above 0xFFFF - due to cache limitations
            return null;
        GlyphRef found = _glyphCache.find(cast(ushort)ch);
        if (found !is null)
            return found;
        FT_UInt index;
        FreeTypeFontFile file;
        if (!findGlyph(ch, 0, index, file))
        {
            if (!findGlyph(ch, '?', index, file))
                return null;
        }
        if (auto glyph = file.getGlyphInfo(ch, 0, withImage))
        {
            if (withImage)
                return _glyphCache.put(ch, glyph.val);
            else
                return glyph.val;
        }
        else
            return null;
    }

    /// Load font files
    bool create()
    {
        if (!isNull())
            clear();
        foreach (string filename; _fontItem.filenames)
        {
            auto file = new FreeTypeFontFile(_fontItem.library, filename);
            if (file.open(_size, 0))
            {
                _files.append(file);
            }
            else
            {
                destroy(file);
            }
        }
        return _files.count > 0;
    }

    override void checkpoint()
    {
        _glyphCache.checkpoint();
    }

    override void cleanup()
    {
        _glyphCache.cleanup();
    }

    override void clearGlyphCache()
    {
        _glyphCache.clear();
    }
}

private derelict.util.exception.ShouldThrow missingSymFunc(string symName)
{
    import std.algorithm : equal;
    static import derelict.util.exception;

    foreach (s; ["FT_New_Face", "FT_Attach_File", "FT_Set_Pixel_Sizes", "FT_Get_Char_Index",
            "FT_Load_Glyph", "FT_Done_Face", "FT_Init_FreeType", "FT_Done_FreeType", "FT_Get_Kerning"])
    {
        if (symName.equal(s)) // Symbol is used
            return derelict.util.exception.ShouldThrow.Yes;
    }
    // Don't throw for unused symbol
    return derelict.util.exception.ShouldThrow.No;
}

/// FreeType based font manager.
class FreeTypeFontManager : FontManager
{
    private FT_Library _library;
    private FontFileItem[] _fontFiles;

    private FontFileItem findFileItem(ref FontDef def)
    {
        foreach (FontFileItem item; _fontFiles)
            if (item.def == def)
                return item;
        return null;
    }

    /// Return list of available font faces
    override FontFaceProps[] getFaces()
    {
        FontFaceProps[] list;
        foreach (f; _fontFiles)
        {
            auto item = FontFaceProps(f.def.face, f.def.family);
            bool there;
            foreach (ref p; list)
            {
                if (p.face == item.face)
                {
                    there = true;
                    break;
                }
            }
            if (!there)
                list ~= item;
        }
        return list;
    }

    private static int faceMatch(string requested, string existing)
    {
        if (!requested.icmp("Arial"))
        {
            if (!existing.icmp("DejaVu Sans"))
            {
                return 200;
            }
        }
        if (!requested.icmp("Times New Roman"))
        {
            if (!existing.icmp("DejaVu Serif"))
            {
                return 200;
            }
        }
        if (!requested.icmp("Courier New"))
        {
            if (!existing.icmp("DejaVu Sans Mono"))
            {
                return 200;
            }
        }
        return stdFontFacePriority(existing) * 10;
    }

    private FontFileItem findBestMatch(ushort weight, bool italic, FontFamily family, string face)
    {
        FontFileItem best = null;
        int bestScore = 0;
        string[] faces = face ? split(face, ",") : null;
        foreach (FontFileItem item; _fontFiles)
        {
            int score = 0;
            int bestFaceMatch = 0;
            if (faces && face.length)
            {
                foreach (i; 0 .. faces.length)
                {
                    string f = faces[i].strip;
                    if (f.icmp(item.def.face) == 0)
                    {
                        score += 3000 - i;
                        break;
                    }
                    int match = faceMatch(f, item.def.face);
                    if (match > bestFaceMatch)
                        bestFaceMatch = match;
                }
            }
            score += bestFaceMatch;
            if (family == item.def.family)
                score += 1000; // family match
            if (italic == item.def.italic)
                score += 50; // italic match
            int weightDiff = myabs(weight - item.def.weight);
            score += 30 - weightDiff / 30; // weight match
            if (score > bestScore)
            {
                bestScore = score;
                best = item;
            }
        }
        return best;
    }

    //private FontList _activeFonts;

    private static __gshared FontRef _nullFontRef;

    this()
    {
        // load dynamic library
        try
        {
            Log.v("DerelictFT: Loading FreeType library");
            if (!DerelictFT)
            {
                Log.w("DerelictFT is null. Compiler bug? Applying workaround to fix it.");
                version (Android)
                {
                    //DerelictFT = new DerelictFTLoader("libft2.so");
                    DerelictFT = new DerelictFTLoader;
                }
                else
                {
                    DerelictFT = new DerelictFTLoader;
                }
            }
            DerelictFT.missingSymbolCallback = &missingSymFunc;
            Log.v("DerelictFT: Missing symbols callback is registered");
            DerelictFT.load();
            Log.v("DerelictFT: Loaded");
        }
        catch (Exception e)
        {
            Log.e("Derelict: cannot load freetype shared library: ", e.msg);
            throw new Exception("Cannot load freetype library");
        }
        Log.v("Initializing FreeType library");
        // init library
        int error = FT_Init_FreeType(&_library);
        if (error)
        {
            Log.e("Cannot init freetype library, error=", error);
            throw new Exception("Cannot init freetype library");
        }
        //FT_Library_SetLcdFilter(_library, FT_LCD_FILTER_DEFAULT);
    }

    ~this()
    {
        debug (FontResources)
            Log.d("FreeTypeFontManager ~this()");
        //_activeFonts.clear();
        eliminate(_fontFiles);
        debug (FontResources)
            Log.d("Destroyed all fonts. Freeing library.");
        // uninit library
        if (_library)
            FT_Done_FreeType(_library);
    }

    override protected ref FontRef getFontImpl(int size, ushort weight, bool italic, FontFamily family, string face)
    {
        FontFileItem f = findBestMatch(weight, italic, family, face);
        if (f is null)
            return _nullFontRef;
        return f.get(size);
    }

    override void checkpoint()
    {
        foreach (ref ff; _fontFiles)
        {
            ff.checkpoint();
        }
    }

    override void cleanup()
    {
        foreach (ref ff; _fontFiles)
        {
            ff.cleanup();
        }
    }

    override void clearGlyphCaches()
    {
        foreach (ref ff; _fontFiles)
        {
            ff.clearGlyphCaches();
        }
    }

    bool registerFont(string filename, bool skipUnknown = false)
    {
        import std.path : baseName;

        FontFamily family = FontFamily.sans_serif;
        string face;
        bool italic;
        ushort weight;
        string name = filename.baseName;
        switch (name)
        {
        case "DroidSans.ttf":
            face = "Droid Sans";
            weight = FontWeight.normal;
            break;
        case "DroidSans-Bold.ttf":
            face = "Droid Sans";
            weight = FontWeight.bold;
            break;
        case "DroidSansMono.ttf":
            face = "Droid Sans Mono";
            weight = FontWeight.normal;
            family = FontFamily.monospace;
            break;
        case "Roboto-Light.ttf":
            face = "Roboto";
            weight = FontWeight.normal;
            break;
        case "Roboto-LightItalic.ttf":
            face = "Roboto";
            weight = FontWeight.normal;
            italic = true;
            break;
        case "Roboto-Bold.ttf":
            face = "Roboto";
            weight = FontWeight.bold;
            break;
        case "Roboto-BoldItalic.ttf":
            face = "Roboto";
            weight = FontWeight.bold;
            italic = true;
            break;
        default:
            if (skipUnknown)
                return false;
        }
        return registerFont(filename, FontFamily.sans_serif, face, italic, weight);
    }

    /// Register freetype font by filename - optinally font properties can be passed if known (e.g. from libfontconfig).
    bool registerFont(string filename, FontFamily family, string face = null, bool italic = false,
            ushort weight = 0, bool dontLoadFile = false)
    {
        if (_library is null)
            return false;
        debug (FontResources)
            Log.v("FreeTypeFontManager.registerFont ", filename, " ", family, " ", face,
                  " italic=", italic, " weight=", weight);
        if (!exists(filename) || !isFile(filename))
        {
            Log.d("Font file ", filename, " not found");
            return false;
        }

        if (!dontLoadFile)
        {
            auto font = new FreeTypeFontFile(_library, filename);
            if (!font.open(24))
            {
                Log.e("Failed to open font ", filename);
                destroy(font);
                return false;
            }

            if (face == null || weight == 0)
            {
                // properties are not set by caller
                // get properties from loaded font
                face = font.face;
                italic = font.italic;
                weight = font.weight;
                debug (FontResources)
                    Log.d("Using properties from font file: face=", face, " weight=", weight, " italic=", italic);
            }
            destroy(font);
        }

        FontDef def = FontDef(family, face, italic, weight);
        FontFileItem item = findFileItem(def);
        if (item is null)
        {
            item = new FontFileItem(_library, def);
            _fontFiles ~= item;
        }
        item.addFile(filename);

        // registered
        return true;
    }

    /// Returns number of registered fonts
    @property int registeredFontCount() const
    {
        return cast(int)_fontFiles.length;
    }
}

private int myabs(int n)
{
    return n >= 0 ? n : -n;
}

version (Posix)
{
    bool registerFontConfigFonts(FreeTypeFontManager fontMan)
    {
        import fontconfig;

        try
        {
            DerelictFC.load();
        }
        catch (Exception e)
        {
            Log.w("Cannot load FontConfig shared library");
            return false;
        }

        Log.i("Getting list of fonts using FontConfig");
        long startts = currentTimeMillis();

        FcFontSet* fontset;

        FcObjectSet* os = FcObjectSetBuild(FC_FILE.toStringz, FC_WEIGHT.toStringz, FC_FAMILY.toStringz,
                FC_SLANT.toStringz, FC_SPACING.toStringz, FC_INDEX.toStringz, FC_STYLE.toStringz, null);
        FcPattern* pat = FcPatternCreate();

        FcPatternAddBool(pat, FC_SCALABLE.toStringz, 1);

        fontset = FcFontList(null, pat, os);

        FcPatternDestroy(pat);
        FcObjectSetDestroy(os);

        int facesFound;

        // load fonts from file
        foreach (i; 0 .. fontset.nfont)
        {
            FcChar8* fcfile;
            if (FcPatternGetString(fontset.fonts[i], FC_FILE.toStringz, 0, &fcfile) != FcResultMatch)
                continue;
            string filename = fcfile.fromStringz.idup;
            char[] fn = fromStringz(fcfile).dup;
            toLowerInPlace(fn);
            if (!fn.endsWith(".ttf") && !fn.endsWith(".odf") && !fn.endsWith(".otf") &&
                !fn.endsWith(".pfb") && !fn.endsWith(".pfa"))
            {
                continue;
            }

            FcChar8* fcfamily;
            FcChar8* fcstyle;
            int fcslant = FC_SLANT_ROMAN;
            int fcspacing;
            int fcweight = FC_WEIGHT_MEDIUM;
            if (FcPatternGetString(fontset.fonts[i], FC_FAMILY.toStringz, 0, &fcfamily) != FcResultMatch)
                continue;
            FcPatternGetString(fontset.fonts[i], FC_STYLE.toStringz, 0, &fcstyle);
            FcPatternGetInteger(fontset.fonts[i], FC_SLANT.toStringz, 0, &fcslant);
            FcPatternGetInteger(fontset.fonts[i], FC_SPACING.toStringz, 0, &fcspacing);
            FcPatternGetInteger(fontset.fonts[i], FC_WEIGHT.toStringz, 0, &fcweight);

            FontFamily family;
            if (fcspacing == FC_MONO)
                family = FontFamily.monospace;
            else
            {
                char[] fm = fcfamily.fromStringz.dup;
                toLowerInPlace(fm);
                if (fm.indexOf("sans") >= 0)
                    family = FontFamily.sans_serif;
                else if (fm.indexOf("serif") >= 0)
                    family = FontFamily.serif;
                else
                    family = FontFamily.sans_serif;
            }

            string face = fcfamily.fromStringz.idup;
            char[] st = fcstyle.fromStringz.dup;
            toLowerInPlace(st);
            if (st.indexOf("condensed") >= 0)
                face ~= " Condensed";
            else if (st.indexOf("extralight") >= 0)
                face ~= " Extra Light";

            bool italic = fcslant != FC_SLANT_ROMAN;

            ushort weight = 400;
            switch (fcweight)
            {
            case FC_WEIGHT_THIN:
                weight = 100;
                break;
            case FC_WEIGHT_EXTRALIGHT:
                weight = 200;
                break;
            case FC_WEIGHT_LIGHT:
            case FC_WEIGHT_DEMILIGHT:
                weight = 300;
                break;
            case FC_WEIGHT_BOOK:
            case FC_WEIGHT_REGULAR:
                weight = 400;
                break;
            case FC_WEIGHT_MEDIUM:
                weight = 500;
                break;
            case FC_WEIGHT_DEMIBOLD:
                weight = 600;
                break;
            case FC_WEIGHT_BOLD:
            case FC_WEIGHT_EXTRABOLD:
                weight = 700;
                break;
            case FC_WEIGHT_BLACK:
                weight = 800;
                break;
            case FC_WEIGHT_EXTRABLACK:
                weight = 900;
                break;
            default:
                break;
            }

            if (fontMan.registerFont(filename, family, face, italic, weight, true))
                facesFound++;
        }

        FcFontSetDestroy(fontset);

        long elapsed = currentTimeMillis - startts;
        Log.i("FontConfig: ", facesFound, " font files registered in ", elapsed, "ms");

        return facesFound > 0;
    }
}
