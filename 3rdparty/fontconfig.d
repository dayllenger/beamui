module fontconfig;

import bindbc.loader;

private SharedLib lib;

bool isFontConfigLoaded()
{
    return lib != invalidHandle;
}

void unloadFontConfig()
{
    if (lib != invalidHandle)
        lib.unload();
}

bool loadFontConfig()
{
    version (Windows)
    {
        const(char)[][1] libNames = ["libfontconfig-1.dll"];
    }
    else version (OSX)
    {
        const(char)[][1] libNames = ["/usr/local/lib/libfontconfig.dylib"];
    }
    else version (Posix)
    {
        const(char)[][2] libNames = ["libfontconfig.so.1", "libfontconfig.so"];
    }
    else
        static assert(0, "Need to implement FontConfig libNames for this operating system");

    foreach (name; libNames)
    {
        lib = load(name.ptr);
        if (lib != invalidHandle)
            break;
    }
    if (lib == invalidHandle)
        return false;

    const errCount = errorCount();

    bindSymbol(lib, cast(void**)&FcObjectSetBuild, "FcObjectSetBuild");
    bindSymbol(lib, cast(void**)&FcPatternCreate, "FcPatternCreate");
    bindSymbol(lib, cast(void**)&FcPatternAddBool, "FcPatternAddBool");
    bindSymbol(lib, cast(void**)&FcFontList, "FcFontList");
    bindSymbol(lib, cast(void**)&FcPatternDestroy, "FcPatternDestroy");
    bindSymbol(lib, cast(void**)&FcObjectSetDestroy, "FcObjectSetDestroy");
    bindSymbol(lib, cast(void**)&FcPatternGetString, "FcPatternGetString");
    bindSymbol(lib, cast(void**)&FcPatternGetInteger, "FcPatternGetInteger");
    bindSymbol(lib, cast(void**)&FcPatternGetBool, "FcPatternGetBool");
    bindSymbol(lib, cast(void**)&FcFontSetDestroy, "FcFontSetDestroy");

    return errorCount() == errCount;
}

//===============================================================

alias FcChar8 = char;
alias FcChar16 = wchar;
alias FcChar32 = dchar;
alias FcBool = int;

enum : int
{
    FcFalse = 0,
    FcTrue = 1
}

struct FcMatrix
{
    double xx, xy, yx, yy;
}

struct FcCharSet;
struct FcLangSet;
struct FcConfig;

enum : int
{
    FcTypeUnknown = -1,
    FcTypeVoid,
    FcTypeInteger,
    FcTypeDouble,
    FcTypeString,
    FcTypeBool,
    FcTypeMatrix,
    FcTypeCharSet,
    FcTypeFTFace,
    FcTypeLangSet,
    FcTypeRange
}

alias FcType = int;

enum : int
{
    FcResultMatch,
    FcResultNoMatch,
    FcResultTypeMismatch,
    FcResultNoId,
    FcResultOutOfMemory
}

alias FcResult = int;

struct FcValue
{
    FcType type;
    union
    {
        const FcChar8* s;
        int i;
        FcBool b;
        double d;
        const FcMatrix* m;
        const FcCharSet* c;
        void* f;
        const FcLangSet* l;
        const FcRange* r;
    }
}

enum FcMatchKind
{
    FcMatchPattern,
    FcMatchFont,
    FcMatchScan
}

enum FcLangResult
{
    FcLangEqual = 0,
    FcLangDifferentCountry = 1,
    FcLangDifferentTerritory = 1,
    FcLangDifferentLang = 2
}

enum FcSetName
{
    FcSetSystem = 0,
    FcSetApplication = 1
}

enum FcEndian
{
    FcEndianBig,
    FcEndianLittle
}

struct FcFontSet
{
    int nfont;
    int sfont;
    FcPattern** fonts;
}

struct FcObjectSet
{
    int nobject;
    int sobject;
    const char** objects;
}

struct FcPattern;
struct FcRange;

enum
{
    FC_WEIGHT_THIN = 0,
    FC_WEIGHT_EXTRALIGHT = 40,
    FC_WEIGHT_ULTRALIGHT = FC_WEIGHT_EXTRALIGHT,
    FC_WEIGHT_LIGHT = 50,
    FC_WEIGHT_DEMILIGHT = 55,
    FC_WEIGHT_SEMILIGHT = FC_WEIGHT_DEMILIGHT,
    FC_WEIGHT_BOOK = 75,
    FC_WEIGHT_REGULAR = 80,
    FC_WEIGHT_NORMAL = FC_WEIGHT_REGULAR,
    FC_WEIGHT_MEDIUM = 100,
    FC_WEIGHT_DEMIBOLD = 180,
    FC_WEIGHT_SEMIBOLD = FC_WEIGHT_DEMIBOLD,
    FC_WEIGHT_BOLD = 200,
    FC_WEIGHT_EXTRABOLD = 205,
    FC_WEIGHT_ULTRABOLD = FC_WEIGHT_EXTRABOLD,
    FC_WEIGHT_BLACK = 210,
    FC_WEIGHT_HEAVY = FC_WEIGHT_BLACK,
    FC_WEIGHT_EXTRABLACK = 215,
    FC_WEIGHT_ULTRABLACK = FC_WEIGHT_EXTRABLACK
}

enum
{
    FC_SLANT_ROMAN = 0,
    FC_SLANT_ITALIC = 100,
    FC_SLANT_OBLIQUE = 110
}

enum
{
    FC_WIDTH_ULTRACONDENSED = 50,
    FC_WIDTH_EXTRACONDENSED = 63,
    FC_WIDTH_CONDENSED = 75,
    FC_WIDTH_SEMICONDENSED = 87,
    FC_WIDTH_NORMAL = 100,
    FC_WIDTH_SEMIEXPANDED = 113,
    FC_WIDTH_EXPANDED = 125,
    FC_WIDTH_EXTRAEXPANDED = 150,
    FC_WIDTH_ULTRAEXPANDED = 200
}

enum
{
    FC_PROPORTIONAL = 0,
    FC_DUAL = 90,
    FC_MONO = 100,
    FC_CHARCELL = 110
}

immutable
{
    char* FC_FAMILY = "family"; /// String
    char* FC_STYLE = "style"; /// String
    char* FC_SLANT = "slant"; /// Int
    char* FC_WEIGHT = "weight"; /// Int
    char* FC_SIZE = "size"; /// Range (double)
    char* FC_ASPECT = "aspect"; /// Double
    char* FC_PIXEL_SIZE = "pixelsize"; /// Double
    char* FC_SPACING = "spacing"; /// Int
    char* FC_FOUNDRY = "foundry"; /// String
    char* FC_ANTIALIAS = "antialias"; /// Bool (depends)
    char* FC_HINTING = "hinting"; /// Bool (true)
    char* FC_HINT_STYLE = "hintstyle"; /// Int
    char* FC_VERTICAL_LAYOUT = "verticallayout"; /// Bool (false)
    char* FC_AUTOHINT = "autohint"; /// Bool (false)
    char* FC_GLOBAL_ADVANCE = "globaladvance"; /// Bool (true)
    char* FC_WIDTH = "width"; /// Int
    char* FC_FILE = "file"; /// String
    char* FC_INDEX = "index"; /// Int
    char* FC_FT_FACE = "ftface"; /// FT_Face
    char* FC_RASTERIZER = "rasterizer"; /// String (deprecated)
    char* FC_OUTLINE = "outline"; /// Bool
    char* FC_SCALABLE = "scalable"; /// Bool
    char* FC_COLOR = "color"; /// Bool
    char* FC_SCALE = "scale"; /// double
    char* FC_DPI = "dpi"; /// double
    char* FC_RGBA = "rgba"; /// Int
    char* FC_MINSPACE = "minspace"; /// Bool use minimum line spacing
    char* FC_SOURCE = "source"; /// String (deprecated)
    char* FC_CHARSET = "charset"; /// CharSet
    char* FC_LANG = "lang"; /// String RFC 3066 langs
    char* FC_FONTVERSION = "fontversion"; /// Int from 'head' table
    char* FC_FULLNAME = "fullname"; /// String
    char* FC_FAMILYLANG = "familylang"; /// String RFC 3066 langs
    char* FC_STYLELANG = "stylelang"; /// String RFC 3066 langs
    char* FC_FULLNAMELANG = "fullnamelang"; /// String RFC 3066 langs
    char* FC_CAPABILITY = "capability"; /// String
    char* FC_FONTFORMAT = "fontformat"; /// String
    char* FC_EMBOLDEN = "embolden"; /// Bool - true if emboldening needed
    char* FC_EMBEDDED_BITMAP = "embeddedbitmap"; /// Bool - true to enable embedded bitmaps
    char* FC_DECORATIVE = "decorative"; /// Bool - true if style is a decorative variant
    char* FC_LCD_FILTER = "lcdfilter"; /// Int
    char* FC_FONT_FEATURES = "fontfeatures"; /// String
    char* FC_NAMELANG = "namelang"; /// String RFC 3866 langs
    char* FC_PRGNAME = "prgname"; /// String
    char* FC_HASH = "hash"; /// String (deprecated)
    char* FC_POSTSCRIPT_NAME = "postscriptname"; /// String
}

extern (C) @nogc nothrow
{
    alias p_FC_FcObjectSetBuild = FcObjectSet* function(const char* first, ...);
    alias p_FC_FcPatternCreate = FcPattern* function();
    alias p_FC_FcPatternAddBool = FcBool function(FcPattern* p, const char* object, FcBool b);
    alias p_FC_FcFontList = FcFontSet* function(FcConfig* config, FcPattern* p, FcObjectSet* os);
    alias p_FC_FcPatternDestroy = void function(FcPattern* p);
    alias p_FC_FcObjectSetDestroy = void function(FcObjectSet* os);
    alias p_FC_FcPatternGetString = FcResult function(const FcPattern* p,
            const char* object, int n, FcChar8** s);
    alias p_FC_FcPatternGetInteger = FcResult function(const FcPattern* p,
            const char* object, int n, int* i);
    alias p_FC_FcPatternGetBool = FcResult function(const FcPattern* p,
            const char* object, int n, FcBool* b);
    alias p_FC_FcFontSetDestroy = void function(FcFontSet* s);
}

__gshared
{
    p_FC_FcObjectSetBuild FcObjectSetBuild;
    p_FC_FcPatternCreate FcPatternCreate;
    p_FC_FcPatternAddBool FcPatternAddBool;
    p_FC_FcFontList FcFontList;
    p_FC_FcPatternDestroy FcPatternDestroy;
    p_FC_FcObjectSetDestroy FcObjectSetDestroy;
    p_FC_FcPatternGetString FcPatternGetString;
    p_FC_FcPatternGetInteger FcPatternGetInteger;
    p_FC_FcPatternGetBool FcPatternGetBool;
    p_FC_FcFontSetDestroy FcFontSetDestroy;
}
