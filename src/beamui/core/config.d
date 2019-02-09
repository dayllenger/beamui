/**
Convenient configuration constants.

Synopsis:
---
static if (USE_OPENGL)
{
    // application built with OpenGL support, we may use gl functions
}

static if (BACKEND_CONSOLE)
{
    // application built against console
}
---

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.config;

immutable string BEAMUI_VERSION = import("BEAMUI_VERSION");

version (EXTERNAL)
{
    // Use this file to define any enums that is need for the external backend
    mixin(import("external_cfg.d"));
}
else
{
    enum BACKEND_ANSI_CONSOLE = __traits(compiles, _CONSOLE);
    enum BACKEND_CONSOLE = BACKEND_ANSI_CONSOLE;
    enum BACKEND_GUI = !BACKEND_CONSOLE;

    enum USE_OPENGL      = BACKEND_GUI &&!__traits(compiles, _NO_OPENGL);
    enum USE_FREETYPE    = BACKEND_GUI && __traits(compiles, _FREETYPE);
    enum BACKEND_ANDROID = BACKEND_GUI && __traits(compiles, _ANDROID);
    enum BACKEND_X11     = BACKEND_GUI && __traits(compiles, _X11)   && !BACKEND_ANDROID;
    enum BACKEND_SDL     = BACKEND_GUI && __traits(compiles, _SDL)   && !BACKEND_ANDROID && !BACKEND_X11;
    enum BACKEND_WIN32   = BACKEND_GUI && __traits(compiles, _WIN32) && !BACKEND_ANDROID && !BACKEND_X11 && !BACKEND_SDL;

    private
    {
        // OpenGL is enabled by default
        version (NO_OPENGL)
            enum _NO_OPENGL;

        version (CONSOLE)
        {
            enum _CONSOLE;
        }
        else
        {
            version (Posix)
            {
                // FreeType and SDL is default on Linux and macOS
                enum _FREETYPE;
                enum _SDL;
            }
            version (Windows)
            {
                // and optional on Windows
                version (FREETYPE)
                    enum _FREETYPE;
                version (SDL)
                    enum _SDL;
                enum _WIN32;
            }
            version (Android)
            {
                // Android uses its own EGL backend
                enum _ANDROID;
            }
            // X11 or other backend will replace SDL or Win32
            version (X11)
                enum _X11;
        }
    }
}
