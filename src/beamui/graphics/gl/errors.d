/**
Utilities for OpenGL error checking.

Copyright: dayllenger 2017-2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.errors;

import beamui.core.config;

static if (USE_OPENGL):
import std.conv : to;
import beamui.core.logger;
import beamui.graphics.gl.api : GLenum, glGetError, GL_NO_ERROR;

/// Convenient wrapper around glGetError(). Usage: checkgl!glFunction(funcParams);
template checkgl(alias func)
{
    debug auto checkgl(string functionName = __FUNCTION__, int line = __LINE__, Args...)(Args args)
    {
        scope (success)
            checkError(__traits(identifier, func), functionName, line);
        return func(args);
    }
    else
        alias checkgl = func;
}

/// Check for GL error. If an error occured, reports about it in the logger and returns true
bool checkError(string context = "", string functionName = __FUNCTION__, int line = __LINE__)
{
    GLenum err = glGetError();
    if (err != GL_NO_ERROR)
    {
        Log.e("OpenGL error ", glErrorToString(err), " at ", functionName, ":", line, " -- ", context);
        return true;
    }
    return false;
}

/// Convert numeric GL error code to a human-readable symbolic name
string glErrorToString(GLenum err)
{
    /*  For reporting OpenGL errors, it's nicer to get a human-readable symbolic name for the
        error instead of the numeric form. Derelict's GLenum is just an alias for uint, so we
        can't depend on D's nice toString() for enums. */
    switch (err)
    {
    case 0x0500:
        return "GL_INVALID_ENUM";
    case 0x0501:
        return "GL_INVALID_VALUE";
    case 0x0502:
        return "GL_INVALID_OPERATION";
    case 0x0505:
        return "GL_OUT_OF_MEMORY";
    case 0x0506:
        return "GL_INVALID_FRAMEBUFFER_OPERATION";
    case 0x0507:
        return "GL_CONTEXT_LOST";
    case GL_NO_ERROR:
        return "No GL error";
    default:
        return "Unknown GL error: " ~ to!string(err);
    }
}
