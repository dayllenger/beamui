/**
GLSL shader compiling and linking routines.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.compiler;

import beamui.core.config;

static if (USE_OPENGL):
import std.string : stripRight;
import derelict.opengl3.gl3;
import derelict.opengl3.types;
import beamui.core.functions : min;
import beamui.core.logger;

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

    // delete the program parts
    foreach(sh; shaderIDs)
    {
        glDetachShader(programID, sh);
        glDeleteShader(sh);
    }

    return programID;
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
        char[] s = stripRight(infobuffer[0 .. infolen]);
        // it can be some warning
        if (!ok)
        {
            Log.fe("Failed to compile %s shader:", stage);
            Log.e(s);
        }
        else
            Log.w(s);
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
        char[] s = stripRight(infobuffer[0 .. infolen]);
        // it can be some warning
        if (!ok)
        {
            Log.e("Failed to link shaders:");
            Log.e(s);
        }
        else
            Log.w(s);
    }
    return ok;
}
