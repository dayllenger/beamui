/**
GLSL shader compiling and linking routines.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.compiler;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
nothrow:
// dfmt on
import std.string : stripRight;
import beamui.core.functions : collectException, min;
import beamui.core.logger;
import beamui.graphics.gl.api;

enum ShaderStage : GLenum
{
    vertex = GL_VERTEX_SHADER,
    fragment = GL_FRAGMENT_SHADER,
}

/// Compile single shader from source. Returns 0 in case of error
GLuint compileShader(string source, const ShaderStage stage)
{
    // create a shader
    GLuint shaderID = glCreateShader(stage);

    // compile the shader
    const char* csource = source.ptr;
    GLint length = cast(GLint)source.length;
    glShaderSource(shaderID, 1, &csource, &length);
    glCompileShader(shaderID);

    // check the shader
    if (!checkCompilation(shaderID, stage))
    {
        glDeleteShader(shaderID);
        shaderID = 0;
    }
    return shaderID;
}

/// Link prepared shader program. Returns false in case of error
bool linkProgram(GLuint programID)
{
    glLinkProgram(programID);

    // check the program
    return checkLinking(programID);
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
