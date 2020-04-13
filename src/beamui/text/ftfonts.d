/**
FontManager implementation based on FreeType library.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.text.ftfonts;

import beamui.core.config;

static if (USE_FREETYPE):
import std.file;
import std.math : abs;
import std.string;
import bindbc.freetype;
import beamui.core.collections;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types : Result, Ok, Err;
import beamui.text.fonts;
import beamui.text.glyph;

package(beamui) __gshared int[string] STD_FONT_FACES;

private int stdFontFacePriority(string face)
{
    return STD_FONT_FACES.get(face, 0);
}

private struct FontDef
{
    FontFamily family;
    string face;
    bool italic;
    ushort weight;
}

private final class FontFileItem
{
    @property ref inout(FontDef) def() inout { return _def; }
    @property string[] filenames() { return _filenames; }
    @property FT_Library* library() { return _library; }

    private FontList _activeFonts;
    private FT_Library* _library;
    private FontDef _def;
    private string[] _filenames;

    this(ref FT_Library library, ref FontDef def)
    {
        _library = &library;
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

    FontRef get(int size)
    {
        ptrdiff_t index = _activeFonts.find(size);
        if (index >= 0)
            return _activeFonts.get(index);
        auto font = new FreeTypeFont(this, size);
        if (!font.create())
        {
            destroy(font);
            return FontRef.init;
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

final class FreeTypeFontFile
{
    private
    {
        string _filename;
        FT_Library* _library;
        FT_Face _face;
        FT_GlyphSlot _slot;
        FT_Matrix _matrix; // transformation matrix
    }

    this(ref FT_Library library, string filename)
    {
        _library = &library;
        _filename = filename;
        _matrix.xx = 0x10000;
        _matrix.yy = 0x10000;
        _matrix.xy = 0;
        _matrix.yx = 0;
        debug const count = debugPlusInstance();
        debug (FontResources)
            Log.d("Created FreeTypeFontFile, count: ", count);
    }

    ~this()
    {
        clear();
        debug const count = debugMinusInstance();
        debug (FontResources)
            Log.d("Destroyed FreeTypeFontFile, count: ", count);
    }

    mixin DebugInstanceCount!();

    private static string familyName(FT_Face face)
    {
        string faceName = fromStringz(face.family_name).dup;
        char[] styleName = fromStringz(face.style_name);
        if (faceName == "Arial" && styleName == "Narrow")
            faceName ~= " Narrow";
        else if (styleName == "Condensed")
            faceName ~= " Condensed";
        return faceName;
    }

    /// Open face with specified size
    bool open(int size, int index, ref FontDescription desc)
    {
        // create face object
        int error = FT_New_Face(*_library, toStringz(_filename), index, &_face);
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
                kernFile = null;
            }
            if (kernFile.length > 0)
            {
                error = FT_Attach_File(_face, toStringz(kernFile));
                if (error)
                {
                    clear();
                    return false;
                }
            }
        }
        _slot = _face.glyph;

        error = FT_Set_Pixel_Sizes(_face, 0, size);
        if (error)
        {
            clear();
            return false;
        }

        // overwrite existing description
        // TODO: test multiple files
        desc.face = familyName(_face);
        desc.style = _face.style_flags & FT_STYLE_FLAG_ITALIC ? FontStyle.italic : FontStyle.normal;
        desc.weight = _face.style_flags & FT_STYLE_FLAG_BOLD ? FontWeight.bold : FontWeight.normal;

        desc.size = size;
        desc.height = cast(int)((_face.size.metrics.height + 63) >> 6);
        desc.baseline = desc.height + cast(int)(_face.size.metrics.descender >> 6);
        desc.hasKerning = FT_HAS_KERNING(_face);

        debug (FontResources)
        {
            Log.fd("Opened font, face: %s, size: %d, height: %d, weight: %d, style: %s",
                desc.face, size, desc.height, desc.weight, desc.style);
        }
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

    /// Retrieve glyph information, filling glyph struct; returns `Err` if glyph is not found
    Result!GlyphRef getGlyphInfo(dchar code, dchar def_char, bool antialiased, bool withImage = true)
    {
        alias FM = FontManager;

        const int glyph_index = getCharIndex(code, def_char);
        int flags = FT_LOAD_DEFAULT;
        if (antialiased)
        {
            if (FM.subpixelRenderingMode)
                flags |= FT_LOAD_TARGET_LCD;
            else if (FM.hintingMode == HintingMode.light)
                flags |= FT_LOAD_TARGET_LIGHT;
            else
                flags |= FT_LOAD_TARGET_NORMAL;
        }
        else
        {
            flags |= FT_LOAD_TARGET_MONO;
        }
        if (withImage)
            flags |= FT_LOAD_RENDER;
        if (FM.hintingMode == HintingMode.autohint || FM.hintingMode == HintingMode.light)
            flags |= FT_LOAD_FORCE_AUTOHINT;
        else if (FM.hintingMode == HintingMode.disabled)
            flags |= FT_LOAD_NO_AUTOHINT | FT_LOAD_NO_HINTING;

        const int error = FT_Load_Glyph(_face, glyph_index, flags);
        if (error)
            return Err!GlyphRef;

        auto glyph = new Glyph;
        glyph.blackBoxX = cast(ushort)((_slot.metrics.width + 32) >> 6);
        glyph.blackBoxY = cast(ubyte)((_slot.metrics.height + 32) >> 6);
        glyph.originX = cast(byte)((_slot.metrics.horiBearingX + 32) >> 6);
        glyph.originY = cast(byte)((_slot.metrics.horiBearingY + 32) >> 6);
        glyph.widthPixels = abs(_slot.metrics.horiAdvance) / 64.0f;
        glyph.subpixelMode = antialiased ? FM.subpixelRenderingMode : SubpixelRenderingMode.none;
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
                if (!antialiased)
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
        if (_face)
        {
            if (*_library) // check if library is still open
                FT_Done_Face(_face);
            _face = null;
        }
    }

    float getKerningOffset(FT_UInt prevCharIndex, FT_UInt nextCharIndex)
    {
        const FT_KERNING_DEFAULT = 0;
        FT_Vector delta;
        const int error = FT_Get_Kerning(
            _face,              // handle to face object
            prevCharIndex,      // left glyph index
            nextCharIndex,      // right glyph index
            FT_KERNING_DEFAULT, // kerning mode
            &delta);            // target vector
        return !error ? delta.x / 64.0f : 0;
    }
}

/// Font implementation based on FreeType
final class FreeTypeFont : Font
{
    override @property bool isNull() const { return _files.empty; }

    private
    {
        FontFileItem _fontItem;
        Collection!(FreeTypeFontFile, true) _files;

        GlyphCache _glyphCache;
    }

    this(FontFileItem item, int size)
    {
        _fontItem = item;
        _desc.face = item.def.face;
        _desc.family = item.def.family;
        _desc.style = item.def.italic ? FontStyle.italic : FontStyle.normal;
        _desc.weight = item.def.weight;
        _desc.size = size;
        _desc.height = size;
    }

    ~this()
    {
        clear();
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
    override float getKerningOffset(dchar prevChar, dchar currentChar)
    {
        if (!_desc.hasKerning || !prevChar || !currentChar)
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
        if (auto glyph = file.getGlyphInfo(ch, 0, antialiased, withImage))
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
            auto file = new FreeTypeFontFile(*_fontItem.library, filename);
            if (file.open(_desc.size, 0, _desc))
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

/// FreeType-based font manager
final class FreeTypeFontManager : FontManager
{
    private FT_Library _library;
    private FontFileItem[] _fontFiles;
    private FontFileItem[FontDef] _fontFileMap;

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

    private FontFileItem findBestMatch(FontDef def)
    {
        FontFileItem best;
        int bestScore;
        string[] faces = def.face.length ? split(def.face, ",") : null;
        foreach (FontFileItem item; _fontFiles)
        {
            int score;
            int bestFaceMatch;
            if (faces.length && def.face.length)
            {
                foreach (i; 0 .. faces.length)
                {
                    string f = faces[i].strip;
                    if (f.icmp(item.def.face) == 0)
                    {
                        score += 3000 - i;
                        break;
                    }
                    bestFaceMatch = max(bestFaceMatch, faceMatch(f, item.def.face));
                }
            }
            score += bestFaceMatch;
            if (def.family == item.def.family)
                score += 1000; // family match
            if (def.italic == item.def.italic)
                score += 50; // italic match
            const int weightDiff = abs(def.weight - item.def.weight);
            score += 30 - weightDiff / 30; // weight match
            if (score > bestScore)
            {
                bestScore = score;
                best = item;
            }
        }
        return best;
    }

    this()
    {
        import std.string : strip;
        import loader = bindbc.loader.sharedlib;

        Log.v("Loading FreeType library");
        loader.resetErrors();
        const support = loadFreeType();
        if (support != ftSupport)
        {
            Log.e("Errors when loading FreeType:");
            foreach (e; loader.errors())
            {
                Log.e(strip(fromStringz(e.error)), " - ", strip(fromStringz(e.message)));
            }
            throw new Exception("Cannot load FreeType library");
        }

        Log.v("Initializing FreeType library");
        const int error = FT_Init_FreeType(&_library);
        if (error)
        {
            Log.e("FreeType error code: ", error);
            throw new Exception("Cannot init FreeType library");
        }
        //FT_Library_SetLcdFilter(_library, FT_LCD_FILTER_DEFAULT);
    }

    ~this()
    {
        debug (FontResources)
            Log.d("FreeTypeFontManager ~this()");
        eliminate(_fontFiles);
        eliminate(_fontFileMap);
        debug (FontResources)
            Log.d("Destroyed all fonts. Freeing library.");
        // uninit library
        if (_library)
        {
            FT_Done_FreeType(_library);
            _library = null;
        }
    }

    override protected FontRef getFontImpl(int size, ushort weight, bool italic, FontFamily family, string face)
    {
        FontFileItem f = findBestMatch(FontDef(family, face, italic, weight));
        return f ? f.get(size) : FontRef.init;
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
        switch (baseName(filename))
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
            break;
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
            Log.fv("registerFont(%s, %s, %s, italic: %s, weight: %s)",
                filename, family, face, italic, weight);
        if (!exists(filename) || !isFile(filename))
        {
            Log.d("Font file ", filename, " not found");
            return false;
        }

        if (!dontLoadFile)
        {
            auto font = new FreeTypeFontFile(_library, filename);
            FontDescription desc;
            if (!font.open(24, 0, desc))
            {
                Log.e("Failed to open font ", filename);
                destroy(font);
                return false;
            }

            if (face is null || weight == 0)
            {
                // properties are not set by caller
                // get properties from loaded font
                face = desc.face;
                italic = desc.style == FontStyle.italic;
                weight = desc.weight;
                debug (FontResources)
                {
                    Log.fd("Using properties from font file; face: %s, weight: %s, italic: %s",
                        face, weight, italic);
                }
            }
            destroy(font);
        }

        FontDef def = FontDef(family, face, italic, weight);
        FontFileItem item = _fontFileMap.get(def, null);
        if (item is null)
        {
            item = new FontFileItem(_library, def);
            _fontFiles ~= item;
            _fontFileMap[def] = item;
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

version (Posix)
{
    bool registerFontConfigFonts(FreeTypeFontManager fontMan)
    {
        import fontconfig;

        const loaded = loadFontConfig();
        if (!loaded)
        {
            Log.w("Cannot load FontConfig shared library");
            return false;
        }

        Log.i("Getting list of fonts using FontConfig");
        const long startts = currentTimeMillis();

        FcObjectSet* os = FcObjectSetBuild(
            FC_FILE, FC_WEIGHT, FC_FAMILY,
            FC_SLANT, FC_SPACING, FC_INDEX, FC_STYLE,
            null);
        FcPattern* pat = FcPatternCreate();

        FcPatternAddBool(pat, FC_SCALABLE, 1);

        FcFontSet* fontset = FcFontList(null, pat, os);

        FcPatternDestroy(pat);
        FcObjectSetDestroy(os);

        int facesFound;

        // load fonts from file
        foreach (i; 0 .. fontset.nfont)
        {
            FcChar8* fcfile;
            if (FcPatternGetString(fontset.fonts[i], FC_FILE, 0, &fcfile) != FcResultMatch)
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
            if (FcPatternGetString(fontset.fonts[i], FC_FAMILY, 0, &fcfamily) != FcResultMatch)
                continue;
            FcPatternGetString(fontset.fonts[i], FC_STYLE, 0, &fcstyle);
            FcPatternGetInteger(fontset.fonts[i], FC_SLANT, 0, &fcslant);
            FcPatternGetInteger(fontset.fonts[i], FC_SPACING, 0, &fcspacing);
            FcPatternGetInteger(fontset.fonts[i], FC_WEIGHT, 0, &fcweight);

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

            const bool italic = fcslant != FC_SLANT_ROMAN;

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

        const long elapsed = currentTimeMillis - startts;
        Log.i("FontConfig: ", facesFound, " font files registered in ", elapsed, "ms");

        unloadFontConfig();

        return facesFound > 0;
    }
}
