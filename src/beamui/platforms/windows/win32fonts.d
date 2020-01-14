/**
Win32 fonts support.

Part of the Win32 platform.

Usually you don't need to use this module directly.

Copyright: Vadim Lopatin 2014-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.windows.win32fonts;

version (Windows):
import beamui.core.config;

static if (BACKEND_GUI):
import core.sys.windows.windows;
import std.math;
import std.string;
import std.utf;
import beamui.core.logger;
import beamui.text.fonts;
import beamui.text.glyph;

private struct FontDef
{
    immutable FontFamily family;
    immutable string face;
    immutable ubyte pitchAndFamily;

    this(FontFamily family, string face, ubyte pitchAndFamily)
    {
        this.family = family;
        this.face = face;
        this.pitchAndFamily = pitchAndFamily;
    }
}

// support of subpixel rendering
// from AntigrainGeometry https://rsdn.ru/forum/src/830679.1

// Sub-pixel energy distribution lookup table.
// See description by Steve Gibson: http://grc.com/cttech.htm
// The class automatically normalizes the coefficients
// in such a way that primary + 2*secondary + 3*tertiary = 1.0
// Also, the input values are in range of 0...NumLevels, output ones
// are 0...255
//---------------------------------
struct lcd_distribution_lut(int maxv = 65)
{
    this(double prim, double second, double tert)
    {
        double norm = (255.0 / (maxv - 1)) / (prim + second * 2 + tert * 2);
        prim *= norm;
        second *= norm;
        tert *= norm;
        for (int i = 0; i < maxv; i++)
        {
            m_primary[i] = cast(ubyte)floor(prim * i);
            m_secondary[i] = cast(ubyte)floor(second * i);
            m_tertiary[i] = cast(ubyte)floor(tert * i);
        }
    }

    uint primary(int v) const
    {
        if (v >= maxv)
        {
            Log.e("pixel value returned from font engine > 64: ", v);
            v = maxv - 1;
        }
        return m_primary[v];
    }

    uint secondary(int v) const
    {
        if (v >= maxv)
        {
            Log.e("pixel value returned from font engine > 64: ", v);
            v = maxv - 1;
        }
        return m_secondary[v];
    }

    uint tertiary(int v) const
    {
        if (v >= maxv)
        {
            Log.e("pixel value returned from font engine > 64: ", v);
            v = maxv - 1;
        }
        return m_tertiary[v];
    }

private:
    ubyte[maxv] m_primary;
    ubyte[maxv] m_secondary;
    ubyte[maxv] m_tertiary;
}

private immutable lut = lcd_distribution_lut!65(0.5, 0.25, 0.125);

private int colorStat(ubyte* p)
{
    int avg = (cast(int)p[0] + cast(int)p[1] + cast(int)p[2]) / 3;
    return abs(avg - cast(int)p[0]) + abs(avg - cast(int)p[1]) + abs(avg - cast(int)p[2]);
}

private int minIndex(int n0, int n1, int n2)
{
    if (n0 <= n1 && n0 <= n2)
        return 0;
    if (n1 <= n0 && n1 <= n2)
        return 1;
    return n2;
}

// This function prepares the alpha-channel information
// for the glyph averaging the values in accordance with
// the method suggested by Steve Gibson. The function
// extends the width by 4 extra pixels, 2 at the beginning
// and 2 at the end. Also, it doesn't align the new width
// to 4 bytes, that is, the output gm.gmBlackBoxX is the
// actual width of the array.
// returns dst glyph width
//---------------------------------
ushort prepare_lcd_glyph(ubyte* gbuf1, ref GLYPHMETRICS gm, ref ubyte[] gbuf2, ref int shiftedBy)
{
    shiftedBy = 0;
    uint src_stride = (gm.gmBlackBoxX + 3) / 4 * 4;
    uint dst_width = src_stride + 4;
    gbuf2 = new ubyte[dst_width * gm.gmBlackBoxY];

    for (uint y = 0; y < gm.gmBlackBoxY; ++y)
    {
        ubyte* src_ptr = gbuf1 + src_stride * y;
        ubyte* dst_ptr = gbuf2.ptr + dst_width * y;
        for (uint x = 0; x < gm.gmBlackBoxX; ++x)
        {
            uint v = *src_ptr++;
            dst_ptr[0] += lut.tertiary(v);
            dst_ptr[1] += lut.secondary(v);
            dst_ptr[2] += lut.primary(v);
            dst_ptr[3] += lut.secondary(v);
            dst_ptr[4] += lut.tertiary(v);
            ++dst_ptr;
        }
    }
    /*
    int dx = (dst_width - 2) / 3;
    int stats[3] = [0, 0, 0];
    for (uint y = 0; y < gm.gmBlackBoxY; y++) {
        for(uint x = 0; x < dx; ++x)
        {
            for (uint x0 = 0; x0 < 3; x0++) {
                stats[x0] += colorStat(gbuf2.ptr + dst_width * y + x0);
            }
        }
    }
    shiftedBy = 0; //minIndex(stats[0], stats[1], stats[2]);
    if (shiftedBy) {
        for (uint y = 0; y < gm.gmBlackBoxY; y++) {
            ubyte * dst_ptr = gbuf2.ptr + dst_width * y;
            for(uint x = 0; x < gm.gmBlackBoxX; ++x)
            {
                if (x + shiftedBy < gm.gmBlackBoxX)
                    dst_ptr[x] = dst_ptr[x + shiftedBy];
                else
                    dst_ptr[x] = 0;
            }
        }
    }
    */
    return cast(ushort)dst_width;
}

/// Font implementation based on Win32 API system fonts
final class Win32Font : Font
{
    override @property bool isNull() const { return _hfont is null; }

    private
    {
        HFONT _hfont;
        int _dpi;

        LOGFONTA _logfont;
        HDC _dc;
        GlyphCache _glyphCache;
    }

    override void clear()
    {
        if (_hfont)
        {
            DeleteObject(_hfont);
            _hfont = NULL;
            _desc.height = 0;
            _desc.baseline = 0;
            _desc.size = 0;
        }
        if (_dc)
        {
            DeleteObject(_dc);
            _dc = NULL;
        }
    }

    uint getGlyphIndex(dchar code)
    {
        if (!_dc)
            return 0;
        wchar[2] s;
        wchar[2] g;
        s[0] = cast(wchar)code;
        s[1] = 0;
        g[0] = 0;
        GCP_RESULTSW gcp;
        gcp.lStructSize = GCP_RESULTSW.sizeof;
        gcp.lpOutString = null;
        gcp.lpOrder = null;
        gcp.lpDx = null;
        gcp.lpCaretPos = null;
        gcp.lpClass = null;
        gcp.lpGlyphs = g.ptr;
        gcp.nGlyphs = 2;
        gcp.nMaxFit = 2;

        DWORD res = GetCharacterPlacementW(_dc, s.ptr, 1, 1000, &gcp, 0);
        if (!res)
            return 0;
        return g[0];
    }

    override GlyphRef getCharGlyph(dchar ch, bool withImage = true)
    {
        GlyphRef found = _glyphCache.find(ch);
        if (found !is null)
            return found;
        uint glyphIndex = getGlyphIndex(ch);
        if (!glyphIndex)
        {
            ch = getReplacementChar(ch);
            if (!ch)
                return null;
            glyphIndex = getGlyphIndex(ch);
            if (!glyphIndex)
            {
                ch = getReplacementChar(ch);
                if (!ch)
                    return null;
                glyphIndex = getGlyphIndex(ch);
            }
        }
        if (!glyphIndex)
            return null;
        if (glyphIndex >= 0xFFFF)
            return null;
        GLYPHMETRICS metrics;

        bool needSubpixelRendering = FontManager.subpixelRenderingMode && antialiased;
        MAT2 scaleMatrix = {{0, 1}, {0, 0}, {0, 0}, {0, 1}};

        uint res;
        res = GetGlyphOutlineW(_dc, cast(wchar)ch, GGO_METRICS, &metrics, 0, null, &scaleMatrix);
        if (res == GDI_ERROR)
            return null;

        auto g = new Glyph;
        static if (USE_OPENGL)
        {
            g.id = nextGlyphID();
        }
        //g.blackBoxX = cast(ushort)metrics.gmBlackBoxX;
        //g.blackBoxY = cast(ubyte)metrics.gmBlackBoxY;
        //g.originX = cast(byte)metrics.gmptGlyphOrigin.x;
        //g.originY = cast(byte)metrics.gmptGlyphOrigin.y;
        //g.width = cast(ubyte)metrics.gmCellIncX;
        g.subpixelMode = SubpixelRenderingMode.none;

        if (needSubpixelRendering)
        {
            scaleMatrix.eM11.value = 3; // request glyph 3 times wider for subpixel antialiasing
        }

        const bmp = antialiased ? GGO_GRAY8_BITMAP : GGO_BITMAP;
        // calculate bitmap size
        int gs = GetGlyphOutlineW(_dc, cast(wchar)ch, bmp, &metrics, 0, NULL, &scaleMatrix);
        if (gs >= 0x10000 || gs < 0)
            return null;

        if (needSubpixelRendering)
        {
            //Log.d("ch=", ch);
            //Log.d("NORMAL:  blackBoxX=", g.blackBoxX, " \tblackBoxY=", g.blackBoxY, " \torigin.x=", g.originX, " \torigin.y=", g.originY, "\tgmCellIncX=", g.width);
            g.blackBoxX = cast(ushort)metrics.gmBlackBoxX;
            g.blackBoxY = cast(ubyte)metrics.gmBlackBoxY;
            g.originX = cast(byte)((metrics.gmptGlyphOrigin.x + 0) / 3);
            g.originY = cast(byte)metrics.gmptGlyphOrigin.y;
            g.widthPixels = (metrics.gmCellIncX + 2) / 3;
            g.subpixelMode = FontManager.subpixelRenderingMode;
            //Log.d(" *3   :  blackBoxX=", metrics.gmBlackBoxX, " \tblackBoxY=", metrics.gmBlackBoxY, " \torigin.x=", metrics.gmptGlyphOrigin.x, " \torigin.y=", metrics.gmptGlyphOrigin.y, " \tgmCellIncX=", metrics.gmCellIncX);
            //Log.d("  /3  :  blackBoxX=", g.blackBoxX, " \tblackBoxY=", g.blackBoxY, " \torigin.x=", g.originX, " \torigin.y=", g.originY, "\tgmCellIncX=", g.width);
        }
        else
        {
            g.blackBoxX = cast(ushort)metrics.gmBlackBoxX;
            g.blackBoxY = cast(ubyte)metrics.gmBlackBoxY;
            g.originX = cast(byte)metrics.gmptGlyphOrigin.x;
            g.originY = cast(byte)metrics.gmptGlyphOrigin.y;
            g.widthPixels = metrics.gmCellIncX;
        }

        if (g.blackBoxX > 0 && g.blackBoxY > 0)
        {
            g.glyph = new ubyte[g.blackBoxX * g.blackBoxY];
            if (gs > 0)
            {
                if (antialiased)
                {
                    // antialiased glyph
                    ubyte[] glyph = new ubyte[gs];
                    res = GetGlyphOutlineW(_dc, cast(wchar)ch, GGO_GRAY8_BITMAP, //GGO_METRICS
                            &metrics,
                            gs, glyph.ptr, &scaleMatrix);
                    if (res == GDI_ERROR)
                    {
                        return null;
                    }
                    if (needSubpixelRendering)
                    {
                        ubyte[] newglyph;
                        int shiftedBy = 0;
                        g.blackBoxX = prepare_lcd_glyph(glyph.ptr, metrics, newglyph, shiftedBy);
                        g.glyph = newglyph;
                        //g.originX = cast(ubyte)((metrics.gmptGlyphOrigin.x + 2 - shiftedBy) / 3);
                        //g.width = cast(ubyte)((metrics.gmCellIncX  + 2 - shiftedBy) / 3);
                    }
                    else
                    {
                        int glyph_row_size = (g.blackBoxX + 3) / 4 * 4;
                        ubyte* src = glyph.ptr;
                        ubyte* dst = g.glyph.ptr;
                        for (int y = 0; y < g.blackBoxY; y++)
                        {
                            for (int x = 0; x < g.blackBoxX; x++)
                            {
                                dst[x] = _gamma65.correct(src[x]);
                            }
                            src += glyph_row_size;
                            dst += g.blackBoxX;
                        }
                    }
                }
                else
                {
                    // bitmap glyph
                    ubyte[] glyph = new ubyte[gs];
                    res = GetGlyphOutlineW(_dc, cast(wchar)ch, GGO_BITMAP, //GGO_METRICS
                            &metrics, gs,
                            glyph.ptr, &scaleMatrix);
                    if (res == GDI_ERROR)
                    {
                        return null;
                    }
                    int glyph_row_bytes = ((g.blackBoxX + 7) / 8);
                    int glyph_row_size = (glyph_row_bytes + 3) / 4 * 4;
                    ubyte* src = glyph.ptr;
                    ubyte* dst = g.glyph.ptr;
                    for (int y = 0; y < g.blackBoxY; y++)
                    {
                        for (int x = 0; x < g.blackBoxX; x++)
                        {
                            int offset = x >> 3;
                            int shift = 7 - (x & 7);
                            ubyte b = ((src[offset] >> shift) & 1) ? 255 : 0;
                            dst[x] = b;
                        }
                        src += glyph_row_size;
                        dst += g.blackBoxX;
                    }
                }
            }
            else
            {
                // empty glyph
                for (int i = g.blackBoxX * g.blackBoxY - 1; i >= 0; i--)
                    g.glyph[i] = 0;
            }
        }
        // found!
        return _glyphCache.put(ch, cast(GlyphRef)g);
    }

    /// Init from font definition
    bool create(FontDef* def, int size, ushort weight, bool italic)
    {
        if (!isNull())
            clear();

        LOGFONTA lf;
        lf.lfCharSet = ANSI_CHARSET; //DEFAULT_CHARSET;
        lf.lfFaceName[0 .. def.face.length] = def.face;
        lf.lfFaceName[def.face.length] = 0;
        lf.lfHeight = -size; //pixelsToPoints(size);
        lf.lfItalic = italic;
        lf.lfWeight = weight;
        lf.lfOutPrecision = OUT_TT_ONLY_PRECIS; //OUT_OUTLINE_PRECIS; //OUT_TT_ONLY_PRECIS;
        lf.lfClipPrecision = CLIP_DEFAULT_PRECIS;
        //lf.lfQuality = NONANTIALIASED_QUALITY; //ANTIALIASED_QUALITY;
        //lf.lfQuality = PROOF_QUALITY; //ANTIALIASED_QUALITY;
        lf.lfQuality = antialiased ? NONANTIALIASED_QUALITY : ANTIALIASED_QUALITY; //PROOF_QUALITY; //ANTIALIASED_QUALITY; //size < 18 ? NONANTIALIASED_QUALITY : PROOF_QUALITY; //ANTIALIASED_QUALITY;
        lf.lfPitchAndFamily = def.pitchAndFamily;
        _hfont = CreateFontIndirectA(&lf);
        _dc = CreateCompatibleDC(NULL);
        SelectObject(_dc, _hfont);

        TEXTMETRICW tm;
        GetTextMetricsW(_dc, &tm);

        _desc.size = size;
        _desc.height = tm.tmHeight;
        _desc.baseline = _desc.height - tm.tmDescent;
        _desc.weight = weight;
        _desc.style = italic ? FontStyle.italic : FontStyle.normal;
        _desc.face = def.face;
        _desc.family = def.family;

        debug (FontResources)
        {
            Log.fd("Created Win32Font %s, size: %d, height: %d, points: %d, dpi: %d",
                _desc.face, _desc.size, _desc.height, lf.lfHeight, _dpi);
        }
        return true;
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

/// Font manager implementation based on Win32 API system fonts
final class Win32FontManager : FontManager
{
    private FontList _activeFonts;
    private FontDef[] _fontFaces;
    private size_t[string] _faceByName;

    /// Override to return list of font faces available
    override FontFaceProps[] getFaces()
    {
        FontFaceProps[] res;
        for (int i = 0; i < _fontFaces.length; i++)
        {
            FontFaceProps item = FontFaceProps(_fontFaces[i].face, _fontFaces[i].family);
            bool found;
            for (int j = 0; j < res.length; j++)
            {
                if (res[j].face == item.face)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                res ~= item;
        }
        return res;
    }

    this()
    {
        debug Log.i("Creating Win32FontManager");
        // initialize font manager by enumerating of system fonts
        LOGFONTA lf;
        lf.lfCharSet = ANSI_CHARSET; //DEFAULT_CHARSET;
        HDC dc = CreateCompatibleDC(NULL);
        const int res = EnumFontFamiliesExA(
            dc, // handle to DC
            &lf, // font information
            &fontEnumFontFamProc, // callback function (FONTENUMPROC)
            cast(LPARAM)cast(void*)this, // additional data
            0U, // not used; must be 0
        );
        DeleteObject(dc);
        Log.i("Found ", _fontFaces.length, " font faces");
    }

    ~this()
    {
        debug Log.i("Destroying Win32FontManager");
    }

    override protected FontRef getFontImpl(int size, ushort weight, bool italic, FontFamily family, string face)
    {
        FontDef* def = findFace(family, face);
        if (def !is null)
        {
            ptrdiff_t index = _activeFonts.find(size, weight, italic, def.family, def.face);
            if (index >= 0)
                return _activeFonts.get(index);
            debug (FontResources)
                Log.d("Creating new font");
            auto item = new Win32Font;
            if (!item.create(def, size, weight, italic))
                return FontRef.init;
            debug (FontResources)
                Log.d("Adding to list of active fonts");
            return _activeFonts.add(item);
        }
        else
            return FontRef.init;
    }

    /// Find font face definition by family only (try to get one of defaults for family if possible)
    private FontDef* findFace(FontFamily family)
    {
        switch (family)
        {
        case FontFamily.sans_serif:
            return findFace([
                "Arial",
                "Tahoma",
                "Calibri",
                "Verdana",
                "Lucida Sans",
            ]);
        case FontFamily.serif:
            return findFace([
                "Times New Roman",
                "Georgia",
                "Century Schoolbook",
                "Bookman Old Style",
            ]);
        case FontFamily.monospace:
            return findFace([
                "Courier New",
                "Lucida Console",
                "Century Schoolbook",
                "Bookman Old Style",
            ]);
        case FontFamily.cursive:
            return findFace([
                "Comic Sans MS",
                "Lucida Handwriting",
                "Monotype Corsiva",
            ]);
        default:
            return null;
        }
    }

    /// Find font face definition by list of faces
    private FontDef* findFace(string[] faces)
    {
        foreach (f; faces)
        {
            if (auto ptr = findFace(f))
                return ptr;
        }
        return null;
    }

    /// Find font face definition by face only
    private FontDef* findFace(string face)
    {
        if (face.length == 0)
            return null;
        string[] faces = split(face, ",");
        foreach (f; faces)
        {
            if (auto p = f in _faceByName)
                return &_fontFaces[*p];
        }
        return null;
    }

    /// Find font face definition by family and face
    private FontDef* findFace(FontFamily family, string face)
    {
        // by face only
        if (auto ptr = findFace(face))
            return ptr;
        // best for family
        if (auto ptr = findFace(family))
            return ptr;
        foreach (ref def; _fontFaces)
        {
            if (def.family == family)
                return &def;
        }
        if (auto ptr = findFace(FontFamily.sans_serif))
            return ptr;
        return &_fontFaces[0];
    }

    /// Register enumerated font
    bool registerFont(FontFamily family, string face, ubyte pitchAndFamily)
    {
        debug (FontResources)
            Log.fv("registerFont(%s, %s)", family, face);
        _faceByName[face] = _fontFaces.length;
        _fontFaces ~= FontDef(family, face, pitchAndFamily);
        return true;
    }

    /// Clear usage flags for all entries
    override void checkpoint()
    {
        _activeFonts.checkpoint();
    }

    /// Removes entries not used after last call of checkpoint() or cleanup()
    override void cleanup()
    {
        _activeFonts.cleanup();
        //_list.cleanup();
    }

    /// Clears glyph cache
    override void clearGlyphCaches()
    {
        _activeFonts.clearGlyphCache();
    }
}

FontFamily pitchAndFamilyToFontFamily(ubyte flags)
{
    if ((flags & FF_DECORATIVE) == FF_DECORATIVE)
        return FontFamily.fantasy;
    else if ((flags & (FIXED_PITCH)) != 0) // | | MONO_FONT
        return FontFamily.monospace;
    else if ((flags & (FF_ROMAN)) != 0)
        return FontFamily.serif;
    else if ((flags & (FF_SCRIPT)) != 0)
        return FontFamily.cursive;
    return FontFamily.sans_serif;
}

extern (Windows) int fontEnumFontFamProc(
    const LOGFONTA* logicalFontData,
    const TEXTMETRICA* physicalFontData,
    DWORD fontType,
    LPARAM appDefinedData)
{
    if (fontType == TRUETYPE_FONTTYPE)
    {
        Win32FontManager fontman = cast(Win32FontManager)cast(void*)appDefinedData;
        string face = fromStringz(logicalFontData.lfFaceName.ptr).dup;
        FontFamily family = pitchAndFamilyToFontFamily(logicalFontData.lfPitchAndFamily);
        if (face.length < 2 || face[0] == '@')
            return 1;
        fontman.registerFont(family, face, logicalFontData.lfPitchAndFamily);
    }
    return 1;
}
