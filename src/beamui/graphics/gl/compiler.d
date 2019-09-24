/**
GLSL shader compiling and linking routines.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.compiler;

import beamui.core.config;

static if (USE_OPENGL):
nothrow:

import std.string : stripRight;
import beamui.core.functions : collectException, min;
import beamui.core.logger;
import beamui.graphics.gl.api;

enum ShaderStage : ubyte
{
    vertex = 1,
    fragment = 2,
}

private GLenum shaderStageToGLenum(ShaderStage stage)
{
    final switch (stage) with(ShaderStage)
    {
        case vertex:      return GL_VERTEX_SHADER;
        case fragment:    return GL_FRAGMENT_SHADER;
    }
}

/// Compile single shader from source. Returns 0 in case of error
GLuint compileShader(string source, const ShaderStage stage)
{
    // create a shader
    GLuint shaderID = glCreateShader(shaderStageToGLenum(stage));

    // compile the shader
    const char* csource = source.ptr;
    GLint length = cast(GLint)source.length;
    glShaderSource(shaderID, 1, &csource, &length);
    glCompileShader(shaderID);

    // check the shader
    if (!checkCompilation(shaderID, stage))
    {
        shaderID = 0;
        glDeleteShader(shaderID);
    }

    return shaderID;
}

/// Link compiled shaders. Deletes passed shader objects. Returns 0 in case of error
GLuint linkShaders(const GLuint[] shaderIDs...)
{
    // create and link program
    GLuint programID = glCreateProgram();
    foreach(sh; shaderIDs)
        glAttachShader(programID, sh);
    glLinkProgram(programID);

    // check the program
    if (!checkLinking(programID))
    {
        programID = 0;
        glDeleteProgram(programID);
    }
    // flag the shaders for deletion
    foreach(sh; shaderIDs)
    {
        glDeleteShader(sh);
    }
    return programID;
}

/// Relink after some location bindings. Nullifies `programID` in case of error
void relinkProgram(ref GLuint programID)
{
    glLinkProgram(programID);

    // check the program
    if (!checkLinking(programID))
    {
        programID = 0;
        glDeleteProgram(programID);
    }
}

private enum logMaxLen = 1023;

private bool checkCompilation(const GLuint shaderID, const ShaderStage stage)
{
    // get status
    GLint status = GL_FALSE;
    glGetShaderiv(shaderID, GL_COMPILE_STATUS, &status);
    const bool ok = status != GL_FALSE;
    // get log
    GLint infolen;
    glGetShaderiv(shaderID, GL_INFO_LOG_LENGTH, &infolen); // includes \0
    if (infolen > 1)
    {
        char[logMaxLen + 1] infobuffer = 0;
        glGetShaderInfoLog(shaderID, logMaxLen, null, infobuffer.ptr);
        infolen = min(infolen - 1, logMaxLen);
        char[] s;
        collectException(stripRight(infobuffer[0 .. infolen]), s);
        // it can be some warning
        if (!ok)
        {
            Log.fe("Failed to compile %s shader:\n%s", stage, s);
        }
        else
            Log.w('\n', s);
    }
    return ok;
}

private bool checkLinking(const GLuint programID)
{
    // get status
    GLint status = GL_FALSE;
    glGetProgramiv(programID, GL_LINK_STATUS, &status);
    const bool ok = status != GL_FALSE;
    // get log
    GLint infolen;
    glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &infolen); // includes \0
    if (infolen > 1)
    {
        char[logMaxLen + 1] infobuffer = 0;
        glGetProgramInfoLog(programID, logMaxLen, null, infobuffer.ptr);
        infolen = min(infolen - 1, logMaxLen);
        char[] s;
        collectException(stripRight(infobuffer[0 .. infolen]), s);
        // it can be some warning
        if (!ok)
        {
            Log.e("Failed to link shaders:\n", s);
        }
        else
            Log.w('\n', s);
    }
    return ok;
}
