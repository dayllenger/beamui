/**

Synopsis:
---
dub run :opengl
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module app;

import beamui;

mixin APP_ENTRY_POINT;

/// Entry point for application
extern (C) int UIAppMain(string[] args)
{
    // you can explicitly set OpenGL context version
    platform.GLVersionMajor = 2;
    platform.GLVersionMinor = 1;

    Window window = platform.createWindow("OpenGL example", null);

    //==========================================================================

    static if (USE_OPENGL)
        window.mainWidget = new MyOpenGLWidget;
    else
        window.mainWidget = new Label("Library is built without OpenGL support");

    //==========================================================================

    window.show();

    return platform.enterMessageLoop();
}

static if (USE_OPENGL):

class MyOpenGLWidget : Widget
{
}
