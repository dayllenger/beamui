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

version (CONSOLE) {
    enum BACKEND_GUI = false;
    enum BACKEND_CONSOLE = true;
} else {
    enum BACKEND_GUI = true;
    enum BACKEND_CONSOLE = false;
}

// OpenGL is enabled by default
version (NO_OPENGL)
    enum USE_OPENGL = false;
else
    enum USE_OPENGL = BACKEND_GUI;

version (FREETYPE)
    enum USE_FREETYPE = BACKEND_GUI;
else
    enum USE_FREETYPE = false;
