/**
Publicly imports OpenGL 4 or OpenGL ES 3 API.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.api;

import beamui.core.config;

static if (USE_OPENGL):

version (Android)
{
    public import GLES3.gl3;
}
else
{
    public import bindbc.opengl.bind;
}
