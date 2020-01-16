/**


Copyright: Vadim Lopatin 2015-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.common.startup;

import beamui.core.config;
import beamui.core.logger;
import beamui.graphics.bitmap;
import beamui.graphics.drawables;
import beamui.graphics.resources;
import beamui.text.fonts;
import beamui.text.ftfonts;

/** Initialize font manager - default implementation.

    On win32 - first it tries to init freetype (if compiled with), and falls back to win32 fonts.
    On linux/mac - tries to init freetype with fontconfig, and falls back to hardcoded font paths.
    On console - simply uses console font manager.

*/
bool initFontManager()
{
    static if (BACKEND_GUI)
    {
        version (Windows)
        {
            import beamui.platforms.windows.win32fonts;

            /// Testing freetype font manager
            static if (USE_FREETYPE)
            try
            {
                Log.v("Trying to init FreeType font manager");

                auto ft = new FreeTypeFontManager;

                tryHardcodedFontPaths(ft);

                if (ft.registeredFontCount > 0)
                {
                    FontManager.instance = ft;
                }
                else
                {
                    Log.w("No fonts registered in FreeType font manager. Disabling FreeType.");
                    destroy(ft);
                }
            }
            catch (Exception e)
            {
                Log.e("Cannot create FreeTypeFontManager - falling back to win32");
            }

            // use Win32 font manager
            if (FontManager.instance is null)
            {
                FontManager.instance = new Win32FontManager;
            }
            return true;
        }
        else
        {
            auto ft = new FreeTypeFontManager;

            if (!registerFontConfigFonts(ft))
            {
                Log.w("No fonts found using FontConfig. Trying hardcoded paths.");
                tryHardcodedFontPaths(ft);
            }

            if (!ft.registeredFontCount)
                return false;

            FontManager.instance = ft;
            return true;
        }
    }
    else
    {
        import beamui.platforms.ansi_console.consolefont;

        FontManager.instance = new ConsoleFontManager;
        return true;
    }
}

version (Windows)
static if (USE_FREETYPE)
private void tryHardcodedFontPaths(FreeTypeFontManager ft)
{
    import core.sys.windows.shlobj;
    import core.sys.windows.windows;
    import std.utf;

    alias FF = FontFamily;
    alias FW = FontWeight;

    string path = "c:\\Windows\\Fonts\\";
    static if (false)
    { // SHGetFolderPathW not found in shell32.lib
        WCHAR[MAX_PATH] szPath;
        static if (false)
        {
            const CSIDL_FLAG_NO_ALIAS = 0x1000;
            const CSIDL_FLAG_DONT_UNEXPAND = 0x2000;
            if (SUCCEEDED(SHGetFolderPathW(NULL,
                    CSIDL_FONTS | CSIDL_FLAG_NO_ALIAS | CSIDL_FLAG_DONT_UNEXPAND, NULL, 0, szPath.ptr)))
            {
                path = toUTF8(fromWStringz(szPath)); // FIXME: compile error
            }
        }
        else
        {
            if (GetWindowsDirectory(szPath.ptr, MAX_PATH - 1))
            {
                path = toUTF8(fromWStringz(szPath));
                Log.i("Windows directory: ", path);
                path ~= "\\Fonts\\";
                Log.i("Fonts directory: ", path);
            }
        }
    }
    Log.v("Registering fonts");
    // arial
    ft.registerFont(path ~ "arial.ttf", FF.sans_serif, "Arial", false, FW.normal);
    ft.registerFont(path ~ "arialbd.ttf", FF.sans_serif, "Arial", false, FW.bold);
    ft.registerFont(path ~ "arialbi.ttf", FF.sans_serif, "Arial", true, FW.bold);
    ft.registerFont(path ~ "ariali.ttf", FF.sans_serif, "Arial", true, FW.normal);
    // arial unicode ms
    ft.registerFont(path ~ "arialni.ttf", FF.sans_serif, "Arial Unicode MS", false, FW.normal);
    // arial narrow
    ft.registerFont(path ~ "arialn.ttf", FF.sans_serif, "Arial Narrow", false, FW.normal);
    ft.registerFont(path ~ "arialnb.ttf", FF.sans_serif, "Arial Narrow", false, FW.bold);
    ft.registerFont(path ~ "arialnbi.ttf", FF.sans_serif, "Arial Narrow", true, FW.bold);
    ft.registerFont(path ~ "arialni.ttf", FF.sans_serif, "Arial Narrow", true, FW.normal);
    // calibri
    ft.registerFont(path ~ "calibri.ttf", FF.sans_serif, "Calibri", false, FW.normal);
    ft.registerFont(path ~ "calibrib.ttf", FF.sans_serif, "Calibri", false, FW.bold);
    ft.registerFont(path ~ "calibriz.ttf", FF.sans_serif, "Calibri", true, FW.bold);
    ft.registerFont(path ~ "calibrii.ttf", FF.sans_serif, "Calibri", true, FW.normal);
    // cambria
    ft.registerFont(path ~ "cambria.ttc", FF.sans_serif, "Cambria", false, FW.normal);
    ft.registerFont(path ~ "cambriab.ttf", FF.sans_serif, "Cambria", false, FW.bold);
    ft.registerFont(path ~ "cambriaz.ttf", FF.sans_serif, "Cambria", true, FW.bold);
    ft.registerFont(path ~ "cambriai.ttf", FF.sans_serif, "Cambria", true, FW.normal);
    // candara
    ft.registerFont(path ~ "Candara.ttf", FF.sans_serif, "Candara", false, FW.normal);
    ft.registerFont(path ~ "Candarab.ttf", FF.sans_serif, "Candara", false, FW.bold);
    ft.registerFont(path ~ "Candaraz.ttf", FF.sans_serif, "Candara", true, FW.bold);
    ft.registerFont(path ~ "Candarai.ttf", FF.sans_serif, "Candara", true, FW.normal);
    // century
    ft.registerFont(path ~ "CENTURY.TTF", FF.serif, "Century", false, FW.normal);
    // comic sans ms
    ft.registerFont(path ~ "comic.ttf", FF.serif, "Comic Sans MS", false, FW.normal);
    ft.registerFont(path ~ "comicbd.ttf", FF.serif, "Comic Sans MS", false, FW.bold);
    // constantia
    ft.registerFont(path ~ "constan.ttf", FF.serif, "Constantia", false, FW.normal);
    ft.registerFont(path ~ "constanb.ttf", FF.serif, "Constantia", false, FW.bold);
    ft.registerFont(path ~ "constanz.ttf", FF.serif, "Constantia", true, FW.bold);
    ft.registerFont(path ~ "constani.ttf", FF.serif, "Constantia", true, FW.normal);
    // corbel
    ft.registerFont(path ~ "corbel.ttf", FF.sans_serif, "Corbel", false, FW.normal);
    ft.registerFont(path ~ "corbelb.ttf", FF.sans_serif, "Corbel", false, FW.bold);
    ft.registerFont(path ~ "corbelz.ttf", FF.sans_serif, "Corbel", true, FW.bold);
    ft.registerFont(path ~ "corbeli.ttf", FF.sans_serif, "Corbel", true, FW.normal);
    // courier new
    ft.registerFont(path ~ "cour.ttf", FF.monospace, "Courier New", false, FW.normal);
    ft.registerFont(path ~ "courbd.ttf", FF.monospace, "Courier New", false, FW.bold);
    ft.registerFont(path ~ "courbi.ttf", FF.monospace, "Courier New", true, FW.bold);
    ft.registerFont(path ~ "couri.ttf", FF.monospace, "Courier New", true, FW.normal);
    // franklin gothic book
    ft.registerFont(path ~ "frank.ttf", FF.sans_serif, "Franklin Gothic Book", false, FW.normal);
    // times new roman
    ft.registerFont(path ~ "times.ttf", FF.serif, "Times New Roman", false, FW.normal);
    ft.registerFont(path ~ "timesbd.ttf", FF.serif, "Times New Roman", false, FW.bold);
    ft.registerFont(path ~ "timesbi.ttf", FF.serif, "Times New Roman", true, FW.bold);
    ft.registerFont(path ~ "timesi.ttf", FF.serif, "Times New Roman", true, FW.normal);
    // consolas
    ft.registerFont(path ~ "consola.ttf", FF.monospace, "Consolas", false, FW.normal);
    ft.registerFont(path ~ "consolab.ttf", FF.monospace, "Consolas", false, FW.bold);
    ft.registerFont(path ~ "consolai.ttf", FF.monospace, "Consolas", true, FW.normal);
    ft.registerFont(path ~ "consolaz.ttf", FF.monospace, "Consolas", true, FW.bold);
    // garamond
    ft.registerFont(path ~ "GARA.TTF", FF.serif, "Garamond", false, FW.normal);
    ft.registerFont(path ~ "GARABD.TTF", FF.serif, "Garamond", false, FW.bold);
    ft.registerFont(path ~ "GARAIT.TTF", FF.serif, "Garamond", true, FW.normal);
    // georgia
    ft.registerFont(path ~ "georgia.ttf", FF.sans_serif, "Georgia", false, FW.normal);
    ft.registerFont(path ~ "georgiab.ttf", FF.sans_serif, "Georgia", false, FW.bold);
    ft.registerFont(path ~ "georgiaz.ttf", FF.sans_serif, "Georgia", true, FW.bold);
    ft.registerFont(path ~ "georgiai.ttf", FF.sans_serif, "Georgia", true, FW.normal);
    // KaiTi
    ft.registerFont(path ~ "kaiu.ttf", FF.sans_serif, "KaiTi", false, FW.normal);
    // Lucida Console
    ft.registerFont(path ~ "lucon.ttf", FF.monospace, "Lucida Console", false, FW.normal);
    // malgun gothic
    ft.registerFont(path ~ "malgun.ttf", FF.serif, "Malgun Gothic", false, FW.normal);
    ft.registerFont(path ~ "malgunbd.ttf", FF.serif, "Malgun Gothic", false, FW.bold);
    // meiryo
    ft.registerFont(path ~ "meiryo.ttc", FF.serif, "Meiryo", false, FW.normal);
    ft.registerFont(path ~ "meiryob.ttc", FF.serif, "Meiryo", false, FW.bold);
    // ms mhei
    ft.registerFont(path ~ "MSMHei.ttf", FF.serif, "Microsoft MHei", false, FW.normal);
    ft.registerFont(path ~ "MSMHei-Bold.ttf", FF.serif, "Microsoft MHei", false, FW.bold);
    // ms neo gothic
    ft.registerFont(path ~ "MSNeoGothic.ttf", FF.serif, "Microsoft NeoGothic", false, FW.normal);
    ft.registerFont(path ~ "MSNeoGothic-Bold.ttf", FF.serif, "Microsoft NeoGothic", false, FW.bold);
    // palatino linotype
    ft.registerFont(path ~ "pala.ttf", FF.serif, "Palatino Linotype", false, FW.normal);
    ft.registerFont(path ~ "palab.ttf", FF.serif, "Palatino Linotype", false, FW.bold);
    ft.registerFont(path ~ "palabi.ttf", FF.serif, "Palatino Linotype", true, FW.bold);
    ft.registerFont(path ~ "palai.ttf", FF.serif, "Palatino Linotype", true, FW.normal);
    // segoeui
    ft.registerFont(path ~ "segoeui.ttf", FF.sans_serif, "Segoe UI", false, FW.normal);
    ft.registerFont(path ~ "segoeuib.ttf", FF.sans_serif, "Segoe UI", false, FW.bold);
    ft.registerFont(path ~ "segoeuiz.ttf", FF.sans_serif, "Segoe UI", true, FW.bold);
    ft.registerFont(path ~ "segoeuii.ttf", FF.sans_serif, "Segoe UI", true, FW.normal);
    // SimSun
    ft.registerFont(path ~ "simsun.ttc", FF.sans_serif, "SimSun", false, FW.normal);
    ft.registerFont(path ~ "simsunb.ttf", FF.sans_serif, "SimSun", false, FW.bold);
    // tahoma
    ft.registerFont(path ~ "tahoma.ttf", FF.sans_serif, "Tahoma", false, FW.normal);
    ft.registerFont(path ~ "tahomabd.ttf", FF.sans_serif, "Tahoma", false, FW.bold);
    // trebuchet ms
    ft.registerFont(path ~ "trebuc.ttf", FF.sans_serif, "Trebuchet MS", false, FW.normal);
    ft.registerFont(path ~ "trebucbd.ttf", FF.sans_serif, "Trebuchet MS", false, FW.bold);
    ft.registerFont(path ~ "trebucbi.ttf", FF.sans_serif, "Trebuchet MS", true, FW.bold);
    ft.registerFont(path ~ "trebucit.ttf", FF.sans_serif, "Trebuchet MS", true, FW.normal);
    // verdana
    ft.registerFont(path ~ "verdana.ttf", FF.sans_serif, "Verdana", false, FW.normal);
    ft.registerFont(path ~ "verdanab.ttf", FF.sans_serif, "Verdana", false, FW.bold);
    ft.registerFont(path ~ "verdanai.ttf", FF.sans_serif, "Verdana", true, FW.normal);
    ft.registerFont(path ~ "verdanaz.ttf", FF.sans_serif, "Verdana", true, FW.bold);
}

version (Posix)
static if (USE_FREETYPE)
private void tryHardcodedFontPaths(FreeTypeFontManager ft)
{
    import std.file : DirEntry, exists, isDir;
    import beamui.core.files : AttrFilter, listDirectory;

    alias FF = FontFamily;
    alias FW = FontWeight;

    static bool registerFonts(FreeTypeFontManager ft, string path)
    {
        if (!exists(path) || !isDir(path))
            return false;
        ft.registerFont(path ~ "DejaVuSans.ttf", FF.sans_serif, "DejaVuSans", false, FW.normal);
        ft.registerFont(path ~ "DejaVuSans-Bold.ttf", FF.sans_serif, "DejaVuSans", false, FW.bold);
        ft.registerFont(path ~ "DejaVuSans-Oblique.ttf", FF.sans_serif, "DejaVuSans", true, FW.normal);
        ft.registerFont(path ~ "DejaVuSans-BoldOblique.ttf", FF.sans_serif, "DejaVuSans", true, FW.bold);
        ft.registerFont(path ~ "DejaVuSansMono.ttf", FF.monospace, "DejaVuSansMono", false, FW.normal);
        ft.registerFont(path ~ "DejaVuSansMono-Bold.ttf", FF.monospace, "DejaVuSansMono", false, FW.bold);
        ft.registerFont(path ~ "DejaVuSansMono-Oblique.ttf", FF.monospace, "DejaVuSansMono", true, FW.normal);
        ft.registerFont(path ~ "DejaVuSansMono-BoldOblique.ttf", FF.monospace, "DejaVuSansMono", true, FW.bold);
        return true;
    }

    static string[] findFontsInDirectory(string dir)
    {
        DirEntry[] entries;
        try
        {
            entries = listDirectory(dir, AttrFilter.files, ["*.ttf"]);
        }
        catch (Exception e)
        {
            return null;
        }

        string[] res;
        foreach (entry; entries)
        {
            res ~= entry.name;
        }
        return res;
    }

    static void registerFontsFromDirectory(FreeTypeFontManager ft, string dir)
    {
        string[] fontFiles = findFontsInDirectory(dir);
        Log.d("Fonts in ", dir, " : ", fontFiles);
        foreach (file; fontFiles)
            ft.registerFont(file);
    }

    version (Android)
    {
        registerFontsFromDirectory(ft, "/system/fonts/");
    }
    else
    {
        registerFonts(ft, "/usr/share/fonts/truetype/dejavu/");
        registerFonts(ft, "/usr/share/fonts/TTF/");
        registerFonts(ft, "/usr/share/fonts/dejavu/");
        registerFonts(ft, "/usr/share/fonts/truetype/ttf-dejavu/"); // let it compile on Debian Wheezy
    }
    version (OSX)
    {
        enum lib = "/Library/Fonts/";

        ft.registerFont(lib ~ "Arial.ttf", FF.sans_serif, "Arial", false, FW.normal, true);
        ft.registerFont(lib ~ "Arial Bold.ttf", FF.sans_serif, "Arial", false, FW.bold, true);
        ft.registerFont(lib ~ "Arial Italic.ttf", FF.sans_serif, "Arial", true, FW.normal, true);
        ft.registerFont(lib ~ "Arial Bold Italic.ttf", FF.sans_serif, "Arial", true, FW.bold, true);
        ft.registerFont(lib ~ "Arial.ttf", FF.sans_serif, "Arial", false, FW.normal, true);
        ft.registerFont(lib ~ "Arial Bold.ttf", FF.sans_serif, "Arial", false, FW.bold, true);
        ft.registerFont(lib ~ "Arial Italic.ttf", FF.sans_serif, "Arial", true, FW.normal, true);
        ft.registerFont(lib ~ "Arial Bold Italic.ttf", FF.sans_serif, "Arial", true, FW.bold, true);
        ft.registerFont(lib ~ "Arial Narrow.ttf", FF.sans_serif, "Arial Narrow", false, FW.normal, true);
        ft.registerFont(lib ~ "Arial Narrow Bold.ttf", FF.sans_serif, "Arial Narrow", false, FW.bold, true);
        ft.registerFont(lib ~ "Arial Narrow Italic.ttf", FF.sans_serif, "Arial Narrow", true, FW.normal, true);
        ft.registerFont(lib ~ "Arial Narrow Bold Italic.ttf", FF.sans_serif, "Arial Narrow", true, FW.bold, true);
        ft.registerFont(lib ~ "Courier New.ttf", FF.monospace, "Courier New", false, FW.normal, true);
        ft.registerFont(lib ~ "Courier New Bold.ttf", FF.monospace, "Courier New", false, FW.bold, true);
        ft.registerFont(lib ~ "Courier New Italic.ttf", FF.monospace, "Courier New", true, FW.normal, true);
        ft.registerFont(lib ~ "Courier New Bold Italic.ttf", FF.monospace, "Courier New", true, FW.bold, true);
        ft.registerFont(lib ~ "Georgia.ttf", FF.serif, "Georgia", false, FW.normal, true);
        ft.registerFont(lib ~ "Georgia Bold.ttf", FF.serif, "Georgia", false, FW.bold, true);
        ft.registerFont(lib ~ "Georgia Italic.ttf", FF.serif, "Georgia", true, FW.normal, true);
        ft.registerFont(lib ~ "Georgia Bold Italic.ttf", FF.serif, "Georgia", true, FW.bold, true);
        ft.registerFont(lib ~ "Comic Sans MS.ttf", FF.sans_serif, "Comic Sans", false, FW.normal, true);
        ft.registerFont(lib ~ "Comic Sans MS Bold.ttf", FF.sans_serif, "Comic Sans", false, FW.bold, true);
        ft.registerFont(lib ~ "Tahoma.ttf", FF.sans_serif, "Tahoma", false, FW.normal, true);
        ft.registerFont(lib ~ "Tahoma Bold.ttf", FF.sans_serif, "Tahoma", false, FW.bold, true);

        ft.registerFont(lib ~ "Microsoft/Arial.ttf", FF.sans_serif, "Arial", false, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Arial Bold.ttf", FF.sans_serif, "Arial", false, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Arial Italic.ttf", FF.sans_serif, "Arial", true, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Arial Bold Italic.ttf", FF.sans_serif, "Arial", true, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Calibri.ttf", FF.sans_serif, "Calibri", false, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Calibri Bold.ttf", FF.sans_serif, "Calibri", false, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Calibri Italic.ttf", FF.sans_serif, "Calibri", true, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Calibri Bold Italic.ttf", FF.sans_serif, "Calibri", true, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Times New Roman.ttf", FF.serif, "Times New Roman", false, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Times New Roman Bold.ttf", FF.serif, "Times New Roman", false, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Times New Roman Italic.ttf", FF.serif, "Times New Roman", true, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Times New Roman Bold Italic.ttf", FF.serif, "Times New Roman", true, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Verdana.ttf", FF.sans_serif, "Verdana", false, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Verdana Bold.ttf", FF.sans_serif, "Verdana", false, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Verdana Italic.ttf", FF.sans_serif, "Verdana", true, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Verdana Bold Italic.ttf", FF.sans_serif, "Verdana", true, FW.bold, true);

        ft.registerFont(lib ~ "Microsoft/Consolas.ttf", FF.monospace, "Consolas", false, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Consolas Bold.ttf", FF.monospace, "Consolas", false, FW.bold, true);
        ft.registerFont(lib ~ "Microsoft/Consolas Italic.ttf", FF.monospace, "Consolas", true, FW.normal, true);
        ft.registerFont(lib ~ "Microsoft/Consolas Bold Italic.ttf", FF.monospace, "Consolas", true, FW.bold, true);

        ft.registerFont("/System/Library/Fonts/Menlo.ttc", FF.monospace, "Menlo", false, FW.normal, true);
    }
}

/**
    Initialize logging (for win32 and console - to file ui.log, for other platforms - stderr;
    log level is TRACE for debug builds, and WARN for release builds)
*/
void initLogs()
{
    static import std.stdio;

    static std.stdio.File* openLogFile()
    {
        try
        {
            return new std.stdio.File("ui.log", "w");
        }
        catch (Exception e)
        {
            std.stdio.printf("%.*s\n", e.msg.length, e.msg.ptr);
            return null;
        }
    }

    static if (BACKEND_CONSOLE)
    {
        debug
        {
            Log.setFileLogger(openLogFile());
            Log.setLogLevel(LogLevel.trace);
        }
        else
        {
            // no logging unless version ForceLogs is set
            version (ForceLogs)
            {
                Log.setFileLogger(openLogFile());
            }
        }
    }
    else
    {
        version (Windows)
        {
            debug
            {
                Log.setFileLogger(openLogFile());
            }
            else
            {
                // no logging unless version ForceLogs is set
                version (ForceLogs)
                {
                    Log.setFileLogger(openLogFile());
                }
            }
        }
        else version (Android)
        {
            Log.setLogTag("beamui");
            Log.setLogLevel(LogLevel.trace);
        }
        else
        {
            Log.setStderrLogger();
        }
        debug
        {
            Log.setLogLevel(LogLevel.trace);
        }
        else
        {
            version (ForceLogs)
            {
                Log.setLogLevel(LogLevel.trace);
            }
            else
            {
                Log.setLogLevel(LogLevel.warn);
            }
        }
    }
    Log.i("Logger is initialized");
}

/// Call this on application initialization
void initResourceManagers()
{
    Log.d("Initializing resource managers");

    debug APP_IS_SHUTTING_DOWN = false;

    static if (USE_FREETYPE)
    {
        STD_FONT_FACES = [
            "Arial" : 12,
            "Consolas" : 12,
            "Courier New" : 10,
            "DejaVu Sans Mono" : 10,
            "DejaVu Sans" : 10,
            "DejaVu Serif" : 10,
            "DejaVuSansMono" : 10,
            "FreeMono" : 8,
            "FreeSans" : 8,
            "FreeSerif" : 8,
            "Liberation Mono" : 11,
            "Liberation Sans" : 11,
            "Liberation Serif" : 11,
            "Lucida Console" : 12,
            "Lucida Sans Typewriter" : 10,
            "Menlo" : 13,
            "Times New Roman" : 12,
            "Verdana" : 10,
        ];
    }

    resourceList.embedOne!"themes/default.css";
    version (EmbedStandardResources)
        resourceList.embed!"standard_resources.list";

    static if (BACKEND_GUI)
    {
        imageCache = new ImageCache;
    }

    Log.d("initResourceManagers() -- finished");
}

/// Call this when all resources are supposed to be freed to report counts of non-freed resources by type
void releaseResourcesOnAppExit()
{
    import core.memory : GC;
    import beamui.style.style;
    import beamui.style.theme;
    import beamui.text.simple : clearSimpleTextPool;
    import beamui.widgets.widget : Widget;

    GC.collect();

    clearSimpleTextPool();

    debug
    {
        if (Widget.instanceCount > 0)
        {
            Log.e("Non-zero Widget instance count when exiting: ", Widget.instanceCount);
        }
    }

    resourceList = ResourceList.init;

    currentTheme = null;

    debug
    {
        if (Drawable.instanceCount > 0)
        {
            Log.e("Drawable instance count after theme destruction: ", Drawable.instanceCount);
        }
    }

    static if (BACKEND_GUI)
    {
        imageCache = null;
    }

    FontManager.instance = null;

    debug
    {
        if (BitmapData.instanceCount > 0)
        {
            Log.e("Non-zero BitmapData instance count when exiting: ", BitmapData.instanceCount);
        }
        if (Style.instanceCount > 0)
        {
            Log.e("Non-zero Style instance count when exiting: ", Style.instanceCount);
        }
        if (ImageDrawable.instanceCount > 0)
        {
            Log.e("Non-zero ImageDrawable instance count when exiting: ", ImageDrawable.instanceCount);
        }
        if (Drawable.instanceCount > 0)
        {
            Log.e("Non-zero Drawable instance count when exiting: ", Drawable.instanceCount);
        }
        static if (USE_FREETYPE)
        {
            if (FreeTypeFontFile.instanceCount > 0)
            {
                Log.e("Non-zero FreeTypeFontFile instance count when exiting: ", FreeTypeFontFile.instanceCount);
            }
            if (FreeTypeFont.instanceCount > 0)
            {
                Log.e("Non-zero FreeTypeFont instance count when exiting: ", FreeTypeFont.instanceCount);
            }
        }

        APP_IS_SHUTTING_DOWN = true;
    }

    GC.collect();
    GC.minimize();
}

// a workaround for segfaults in travis-ci builds.
// see investigation: https://github.com/dlang/dub/issues/1812
version (unittest)
{
    static if (__VERSION__ >= 2087)
        extern (C) __gshared string[] rt_options = ["gcopt=parallel:0"];
}
