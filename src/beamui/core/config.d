/**
Convenient configuration constants.

Synopsis:
---
static if (USE_OPENGL)
{
    // application built with OpenGL support, we may use gl functions
}
---

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.config;

immutable string BEAMUI_VERSION = import("BEAMUI_VERSION");

// OpenGL is enabled by default
version (NO_OPENGL)
    enum USE_OPENGL = false;
else
    enum USE_OPENGL = true;

version (FREETYPE)
    enum USE_FREETYPE = true;
else
    enum USE_FREETYPE = false;
