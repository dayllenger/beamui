/**


Copyright: Vadim Lopatin 2015-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.common.startup;

import std.utf : toUTF32;
import beamui.core.config;
import beamui.graphics.fonts;
import beamui.graphics.resources;
import beamui.widgets.styles;
import beamui.widgets.widget;

static if (BACKEND_GUI)
{
    version (Windows)
    {
        /// Initialize font manager - default implementation
        /// On win32 - first it tries to init freetype, and falls back to win32 fonts.
        /// On linux/mac - tries to init freetype with some hardcoded font paths
        extern (C) bool initFontManager()
        {
            import core.sys.windows.windows;
            import std.utf;
            import beamui.platforms.windows.win32fonts;

            /// Testing freetype font manager
            static if (USE_FREETYPE)
            try
            {
                Log.v("Trying to init FreeType font manager");

                import beamui.graphics.ftfonts;

                // trying to create font manager
                Log.v("Creating FreeTypeFontManager");
                auto ftfontMan = new FreeTypeFontManager;

                import core.sys.windows.shlobj;

                string fontsPath = "c:\\Windows\\Fonts\\";
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
                            fontsPath = toUTF8(fromWStringz(szPath)); // FIXME: compile error
                        }
                    }
                    else
                    {
                        if (GetWindowsDirectory(szPath.ptr, MAX_PATH - 1))
                        {
                            fontsPath = toUTF8(fromWStringz(szPath));
                            Log.i("Windows directory: ", fontsPath);
                            fontsPath ~= "\\Fonts\\";
                            Log.i("Fonts directory: ", fontsPath);
                        }
                    }
                }
                Log.v("Registering fonts");
                // arial
                ftfontMan.registerFont(fontsPath ~ "arial.ttf", FontFamily.sans_serif, "Arial",
                        false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "arialbd.ttf", FontFamily.sans_serif, "Arial",
                        false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "arialbi.ttf", FontFamily.sans_serif, "Arial",
                        true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "ariali.ttf", FontFamily.sans_serif, "Arial",
                        true, FontWeight.normal);
                // arial unicode ms
                ftfontMan.registerFont(fontsPath ~ "arialni.ttf", FontFamily.sans_serif,
                        "Arial Unicode MS", false, FontWeight.normal);
                // arial narrow
                ftfontMan.registerFont(fontsPath ~ "arialn.ttf", FontFamily.sans_serif,
                        "Arial Narrow", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "arialnb.ttf", FontFamily.sans_serif,
                        "Arial Narrow", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "arialnbi.ttf", FontFamily.sans_serif,
                        "Arial Narrow", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "arialni.ttf", FontFamily.sans_serif,
                        "Arial Narrow", true, FontWeight.normal);
                // calibri
                ftfontMan.registerFont(fontsPath ~ "calibri.ttf", FontFamily.sans_serif,
                        "Calibri", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "calibrib.ttf", FontFamily.sans_serif,
                        "Calibri", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "calibriz.ttf", FontFamily.sans_serif,
                        "Calibri", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "calibrii.ttf", FontFamily.sans_serif,
                        "Calibri", true, FontWeight.normal);
                // cambria
                ftfontMan.registerFont(fontsPath ~ "cambria.ttc", FontFamily.sans_serif,
                        "Cambria", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "cambriab.ttf", FontFamily.sans_serif,
                        "Cambria", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "cambriaz.ttf", FontFamily.sans_serif,
                        "Cambria", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "cambriai.ttf", FontFamily.sans_serif,
                        "Cambria", true, FontWeight.normal);
                // candara
                ftfontMan.registerFont(fontsPath ~ "Candara.ttf", FontFamily.sans_serif,
                        "Candara", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "Candarab.ttf", FontFamily.sans_serif,
                        "Candara", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "Candaraz.ttf", FontFamily.sans_serif,
                        "Candara", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "Candarai.ttf", FontFamily.sans_serif,
                        "Candara", true, FontWeight.normal);
                // century
                ftfontMan.registerFont(fontsPath ~ "CENTURY.TTF", FontFamily.serif, "Century",
                        false, FontWeight.normal);
                // comic sans ms
                ftfontMan.registerFont(fontsPath ~ "comic.ttf", FontFamily.serif,
                        "Comic Sans MS", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "comicbd.ttf", FontFamily.serif,
                        "Comic Sans MS", false, FontWeight.bold);
                // constantia
                ftfontMan.registerFont(fontsPath ~ "constan.ttf", FontFamily.serif,
                        "Constantia", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "constanb.ttf", FontFamily.serif,
                        "Constantia", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "constanz.ttf", FontFamily.serif,
                        "Constantia", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "constani.ttf", FontFamily.serif,
                        "Constantia", true, FontWeight.normal);
                // corbel
                ftfontMan.registerFont(fontsPath ~ "corbel.ttf", FontFamily.sans_serif, "Corbel",
                        false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "corbelb.ttf", FontFamily.sans_serif,
                        "Corbel", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "corbelz.ttf", FontFamily.sans_serif,
                        "Corbel", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "corbeli.ttf", FontFamily.sans_serif,
                        "Corbel", true, FontWeight.normal);
                // courier new
                ftfontMan.registerFont(fontsPath ~ "cour.ttf", FontFamily.monospace,
                        "Courier New", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "courbd.ttf", FontFamily.monospace,
                        "Courier New", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "courbi.ttf", FontFamily.monospace,
                        "Courier New", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "couri.ttf", FontFamily.monospace,
                        "Courier New", true, FontWeight.normal);
                // franklin gothic book
                ftfontMan.registerFont(fontsPath ~ "frank.ttf", FontFamily.sans_serif,
                        "Franklin Gothic Book", false, FontWeight.normal);
                // times new roman
                ftfontMan.registerFont(fontsPath ~ "times.ttf", FontFamily.serif,
                        "Times New Roman", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "timesbd.ttf", FontFamily.serif,
                        "Times New Roman", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "timesbi.ttf", FontFamily.serif,
                        "Times New Roman", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "timesi.ttf", FontFamily.serif,
                        "Times New Roman", true, FontWeight.normal);
                // consolas
                ftfontMan.registerFont(fontsPath ~ "consola.ttf", FontFamily.monospace,
                        "Consolas", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "consolab.ttf", FontFamily.monospace,
                        "Consolas", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "consolai.ttf", FontFamily.monospace,
                        "Consolas", true, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "consolaz.ttf", FontFamily.monospace,
                        "Consolas", true, FontWeight.bold);
                // garamond
                ftfontMan.registerFont(fontsPath ~ "GARA.TTF", FontFamily.serif, "Garamond",
                        false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "GARABD.TTF", FontFamily.serif, "Garamond",
                        false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "GARAIT.TTF", FontFamily.serif, "Garamond",
                        true, FontWeight.normal);
                // georgia
                ftfontMan.registerFont(fontsPath ~ "georgia.ttf", FontFamily.sans_serif,
                        "Georgia", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "georgiab.ttf", FontFamily.sans_serif,
                        "Georgia", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "georgiaz.ttf", FontFamily.sans_serif,
                        "Georgia", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "georgiai.ttf", FontFamily.sans_serif,
                        "Georgia", true, FontWeight.normal);
                // KaiTi
                ftfontMan.registerFont(fontsPath ~ "kaiu.ttf", FontFamily.sans_serif, "KaiTi",
                        false, FontWeight.normal);
                // Lucida Console
                ftfontMan.registerFont(fontsPath ~ "lucon.ttf", FontFamily.monospace,
                        "Lucida Console", false, FontWeight.normal);
                // malgun gothic
                ftfontMan.registerFont(fontsPath ~ "malgun.ttf", FontFamily.serif,
                        "Malgun Gothic", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "malgunbd.ttf", FontFamily.serif,
                        "Malgun Gothic", false, FontWeight.bold);
                // meiryo
                ftfontMan.registerFont(fontsPath ~ "meiryo.ttc", FontFamily.serif, "Meiryo",
                        false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "meiryob.ttc", FontFamily.serif, "Meiryo",
                        false, FontWeight.bold);
                // ms mhei
                ftfontMan.registerFont(fontsPath ~ "MSMHei.ttf", FontFamily.serif,
                        "Microsoft MHei", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "MSMHei-Bold.ttf", FontFamily.serif,
                        "Microsoft MHei", false, FontWeight.bold);
                // ms neo gothic
                ftfontMan.registerFont(fontsPath ~ "MSNeoGothic.ttf", FontFamily.serif,
                        "Microsoft NeoGothic", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "MSNeoGothic-Bold.ttf", FontFamily.serif,
                        "Microsoft NeoGothic", false, FontWeight.bold);
                // palatino linotype
                ftfontMan.registerFont(fontsPath ~ "pala.ttf", FontFamily.serif,
                        "Palatino Linotype", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "palab.ttf", FontFamily.serif,
                        "Palatino Linotype", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "palabi.ttf", FontFamily.serif,
                        "Palatino Linotype", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "palai.ttf", FontFamily.serif,
                        "Palatino Linotype", true, FontWeight.normal);
                // segoeui
                ftfontMan.registerFont(fontsPath ~ "segoeui.ttf", FontFamily.sans_serif,
                        "Segoe UI", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "segoeuib.ttf", FontFamily.sans_serif,
                        "Segoe UI", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "segoeuiz.ttf", FontFamily.sans_serif,
                        "Segoe UI", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "segoeuii.ttf", FontFamily.sans_serif,
                        "Segoe UI", true, FontWeight.normal);
                // SimSun
                ftfontMan.registerFont(fontsPath ~ "simsun.ttc", FontFamily.sans_serif, "SimSun",
                        false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "simsunb.ttf", FontFamily.sans_serif,
                        "SimSun", false, FontWeight.bold);
                // tahoma
                ftfontMan.registerFont(fontsPath ~ "tahoma.ttf", FontFamily.sans_serif, "Tahoma",
                        false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "tahomabd.ttf", FontFamily.sans_serif,
                        "Tahoma", false, FontWeight.bold);
                // trebuchet ms
                ftfontMan.registerFont(fontsPath ~ "trebuc.ttf", FontFamily.sans_serif,
                        "Trebuchet MS", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "trebucbd.ttf", FontFamily.sans_serif,
                        "Trebuchet MS", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "trebucbi.ttf", FontFamily.sans_serif,
                        "Trebuchet MS", true, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "trebucit.ttf", FontFamily.sans_serif,
                        "Trebuchet MS", true, FontWeight.normal);
                // verdana
                ftfontMan.registerFont(fontsPath ~ "verdana.ttf", FontFamily.sans_serif,
                        "Verdana", false, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "verdanab.ttf", FontFamily.sans_serif,
                        "Verdana", false, FontWeight.bold);
                ftfontMan.registerFont(fontsPath ~ "verdanai.ttf", FontFamily.sans_serif,
                        "Verdana", true, FontWeight.normal);
                ftfontMan.registerFont(fontsPath ~ "verdanaz.ttf", FontFamily.sans_serif,
                        "Verdana", true, FontWeight.bold);
                if (ftfontMan.registeredFontCount())
                {
                    FontManager.instance = ftfontMan;
                }
                else
                {
                    Log.w("No fonts registered in FreeType font manager. Disabling FreeType.");
                    destroy(ftfontMan);
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
    }
    else
    {
        import beamui.graphics.ftfonts;

        bool registerFonts(FreeTypeFontManager ft, string path)
        {
            import std.file;

            if (!exists(path) || !isDir(path))
                return false;
            ft.registerFont(path ~ "DejaVuSans.ttf", FontFamily.sans_serif, "DejaVuSans", false, FontWeight.normal);
            ft.registerFont(path ~ "DejaVuSans-Bold.ttf", FontFamily.sans_serif, "DejaVuSans", false, FontWeight.bold);
            ft.registerFont(path ~ "DejaVuSans-Oblique.ttf", FontFamily.sans_serif, "DejaVuSans",
                    true, FontWeight.normal);
            ft.registerFont(path ~ "DejaVuSans-BoldOblique.ttf", FontFamily.sans_serif, "DejaVuSans",
                    true, FontWeight.bold);
            ft.registerFont(path ~ "DejaVuSansMono.ttf", FontFamily.monospace, "DejaVuSansMono",
                    false, FontWeight.normal);
            ft.registerFont(path ~ "DejaVuSansMono-Bold.ttf", FontFamily.monospace,
                    "DejaVuSansMono", false, FontWeight.bold);
            ft.registerFont(path ~ "DejaVuSansMono-Oblique.ttf", FontFamily.monospace,
                    "DejaVuSansMono", true, FontWeight.normal);
            ft.registerFont(path ~ "DejaVuSansMono-BoldOblique.ttf", FontFamily.monospace,
                    "DejaVuSansMono", true, FontWeight.bold);
            return true;
        }

        string[] findFontsInDirectory(string dir)
        {
            import std.file : DirEntry;
            import beamui.core.files;

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

        void registerFontsFromDirectory(FreeTypeFontManager ft, string dir)
        {
            string[] fontFiles = findFontsInDirectory(dir);
            Log.d("Fonts in ", dir, " : ", fontFiles);
            foreach (file; fontFiles)
                ft.registerFont(file);
        }

        /// Initialize font manager - default implementation
        /// On win32 - first it tries to init freetype, and falls back to win32 fonts.
        /// On linux/mac - tries to init freetype with some hardcoded font paths
        extern (C) bool initFontManager()
        {
            auto ft = new FreeTypeFontManager;

            if (!registerFontConfigFonts(ft))
            {
                // TODO: use FontConfig
                Log.w("No fonts found using FontConfig. Trying hardcoded paths.");
                version (Android)
                {
                    ft.registerFontsFromDirectory("/system/fonts");
                }
                else
                {
                    ft.registerFonts("/usr/share/fonts/truetype/dejavu/");
                    ft.registerFonts("/usr/share/fonts/TTF/");
                    ft.registerFonts("/usr/share/fonts/dejavu/");
                    ft.registerFonts("/usr/share/fonts/truetype/ttf-dejavu/"); // let it compile on Debian Wheezy
                }
                version (OSX)
                {
                    ft.registerFont("/Library/Fonts/Arial.ttf", FontFamily.sans_serif, "Arial",
                            false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Arial Bold.ttf", FontFamily.sans_serif, "Arial",
                            false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Arial Italic.ttf", FontFamily.sans_serif,
                            "Arial", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Arial Bold Italic.ttf", FontFamily.sans_serif,
                            "Arial", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Arial.ttf", FontFamily.sans_serif, "Arial",
                            false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Arial Bold.ttf", FontFamily.sans_serif, "Arial",
                            false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Arial Italic.ttf", FontFamily.sans_serif,
                            "Arial", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Arial Bold Italic.ttf", FontFamily.sans_serif,
                            "Arial", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Arial Narrow.ttf", FontFamily.sans_serif,
                            "Arial Narrow", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Arial Narrow Bold.ttf", FontFamily.sans_serif,
                            "Arial Narrow", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Arial Narrow Italic.ttf", FontFamily.sans_serif,
                            "Arial Narrow", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Arial Narrow Bold Italic.ttf",
                            FontFamily.sans_serif, "Arial Narrow", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Courier New.ttf", FontFamily.monospace,
                            "Courier New", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Courier New Bold.ttf", FontFamily.monospace,
                            "Courier New", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Courier New Italic.ttf", FontFamily.monospace,
                            "Courier New", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Courier New Bold Italic.ttf",
                            FontFamily.monospace, "Courier New", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Georgia.ttf", FontFamily.serif, "Georgia",
                            false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Georgia Bold.ttf", FontFamily.serif, "Georgia",
                            false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Georgia Italic.ttf", FontFamily.serif,
                            "Georgia", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Georgia Bold Italic.ttf", FontFamily.serif,
                            "Georgia", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Comic Sans MS.ttf", FontFamily.sans_serif,
                            "Comic Sans", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Comic Sans MS Bold.ttf", FontFamily.sans_serif,
                            "Comic Sans", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Tahoma.ttf", FontFamily.sans_serif, "Tahoma",
                            false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Tahoma Bold.ttf", FontFamily.sans_serif,
                            "Tahoma", false, FontWeight.bold, true);

                    ft.registerFont("/Library/Fonts/Microsoft/Arial.ttf", FontFamily.sans_serif,
                            "Arial", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Arial Bold.ttf",
                            FontFamily.sans_serif, "Arial", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Arial Italic.ttf",
                            FontFamily.sans_serif, "Arial", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Arial Bold Italic.ttf",
                            FontFamily.sans_serif, "Arial", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Calibri.ttf", FontFamily.sans_serif,
                            "Calibri", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Calibri Bold.ttf",
                            FontFamily.sans_serif, "Calibri", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Calibri Italic.ttf",
                            FontFamily.sans_serif, "Calibri", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Calibri Bold Italic.ttf",
                            FontFamily.sans_serif, "Calibri", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Times New Roman.ttf",
                            FontFamily.serif, "Times New Roman", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Times New Roman Bold.ttf",
                            FontFamily.serif, "Times New Roman", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Times New Roman Italic.ttf",
                            FontFamily.serif, "Times New Roman", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Times New Roman Bold Italic.ttf",
                            FontFamily.serif, "Times New Roman", true, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Verdana.ttf", FontFamily.sans_serif,
                            "Verdana", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Verdana Bold.ttf",
                            FontFamily.sans_serif, "Verdana", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Verdana Italic.ttf",
                            FontFamily.sans_serif, "Verdana", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Verdana Bold Italic.ttf",
                            FontFamily.sans_serif, "Verdana", true, FontWeight.bold, true);

                    ft.registerFont("/Library/Fonts/Microsoft/Consolas.ttf", FontFamily.monospace,
                            "Consolas", false, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Consolas Bold.ttf",
                            FontFamily.monospace, "Consolas", false, FontWeight.bold, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Consolas Italic.ttf",
                            FontFamily.monospace, "Consolas", true, FontWeight.normal, true);
                    ft.registerFont("/Library/Fonts/Microsoft/Consolas Bold Italic.ttf",
                            FontFamily.monospace, "Consolas", true, FontWeight.bold, true);

                    ft.registerFont("/System/Library/Fonts/Menlo.ttc", FontFamily.monospace,
                            "Menlo", false, FontWeight.normal, true);
                }
            }

            if (!ft.registeredFontCount)
                return false;

            FontManager.instance = ft;
            return true;
        }
    }
}

/**
    Initialize logging (for win32 and console - to file ui.log, for other platforms - stderr;
    log level is TRACE for debug builds, and WARN for release builds)
*/
extern (C) void initLogs()
{
    static import std.stdio;

    static if (BACKEND_CONSOLE)
    {
        debug
        {
            Log.setFileLogger(new std.stdio.File("ui.log", "w"));
            Log.setLogLevel(LogLevel.trace);
        }
        else
        {
            // no logging unless version ForceLogs is set
            version (ForceLogs)
            {
                Log.setFileLogger(new std.stdio.File("ui.log", "w"));
            }
        }
    }
    else
    {
        version (Windows)
        {
            debug
            {
                Log.setFileLogger(new std.stdio.File("ui.log", "w"));
            }
            else
            {
                // no logging unless version ForceLogs is set
                version (ForceLogs)
                {
                    Log.setFileLogger(new std.stdio.File("ui.log", "w"));
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
extern (C) void initResourceManagers()
{
    Log.d("initResourceManagers()");

    import beamui.core.stdaction;
    import beamui.graphics.fonts;
    import beamui.graphics.resources;
    import beamui.widgets.editors;

    _gamma65 = new glyph_gamma_table!65(1.0);
    _gamma256 = new glyph_gamma_table!256(1.0);
    static if (USE_FREETYPE)
    {
        import beamui.graphics.ftfonts;

        STD_FONT_FACES = ["Arial" : 12, "Times New Roman" : 12, "Courier New" : 10, "DejaVu Serif" : 10,
            "DejaVu Sans" : 10, "DejaVu Sans Mono" : 10, "Liberation Serif" : 11, "Liberation Sans" : 11,
            "Liberation Mono" : 11, "Verdana" : 10, "Menlo" : 13, "Consolas" : 12, "DejaVuSansMono"
            : 10, "Lucida Sans Typewriter" : 10, "Lucida Console" : 12, "FreeMono" : 8,
            "FreeSans" : 8, "FreeSerif" : 8,];
    }

    version (EmbedStandardResources)
        resourceList.embed!"standard_resources.list";

    static if (BACKEND_GUI)
    {
        version (Windows)
        {
            import beamui.platforms.windows.win32fonts;

            initWin32FontsTables();
        }
        imageCache = new ImageCache;
    }
    _drawableCache = new DrawableCache;

    static if (USE_OPENGL)
    {
        import beamui.graphics.gldrawbuf;

        initGLCaches();
    }

    initStandardActions();
    initStandardEditorActions();
    registerStandardWidgets();

    Log.d("initResourceManagers() -- finished");
}

/// Register standard widgets to use in DML
extern (C) void registerStandardWidgets();

/// Call this when all resources are supposed to be freed to report counts of non-freed resources by type
extern (C) void releaseResourcesOnAppExit()
{
    import core.exception;
    import core.memory;
    import core.thread;

    debug
    {
        if (Widget.instanceCount > 0)
        {
            Log.e("Non-zero Widget instance count when exiting: ", Widget.instanceCount);
        }
    }

    try
    {
        GC.collect();
    }
    catch(InvalidMemoryOperationError e)
    {
        Log.d(e);
    }

    currentTheme = null;
    drawableCache = null;
    static if (BACKEND_GUI)
    {
        try
        {
            GC.collect();
        }
        catch(InvalidMemoryOperationError e)
        {
            Log.d(e);
        }

        imageCache = null;
    }
    try
    {
        GC.collect();
    }
    catch(InvalidMemoryOperationError e)
    {
        Log.d(e);
    }

    FontManager.instance = null;
    static if (USE_OPENGL)
    {
        import beamui.graphics.gldrawbuf;

        destroyGLCaches();
    }

    try
    {
        GC.collect();
    }
    catch(InvalidMemoryOperationError e)
    {
        Log.d(e);
    }


    debug
    {
        if (DrawBuf.instanceCount > 0)
        {
            Log.e("Non-zero DrawBuf instance count when exiting: ", DrawBuf.instanceCount);
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
            import beamui.graphics.ftfonts;

            if (FreeTypeFontFile.instanceCount > 0)
            {
                Log.e("Non-zero FreeTypeFontFile instance count when exiting: ", FreeTypeFontFile.instanceCount);
            }
            if (FreeTypeFont.instanceCount > 0)
            {
                Log.e("Non-zero FreeTypeFont instance count when exiting: ", FreeTypeFont.instanceCount);
            }
        }
    }
}

version (unittest)
{
    version (Windows)
    {
        mixin APP_ENTRY_POINT;

        /// Entry point for application
        extern (C) int UIAppMain(string[] args)
        {
            // just to enable running unit tests
            import core.runtime;
            import std.stdio;

            if (!runModuleUnitTests())
            {
                writeln("Error occured in unit tests. Press enter.");
                readln();
                return 1;
            }
            return 0;
        }
    }
}
