/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.gl.program;

import beamui.core.config;

static if (USE_OPENGL):
import std.array : replace;
import std.string : toStringz;
import derelict.opengl3.gl3;
import derelict.opengl3.types;
import beamui.core.logger;
import beamui.graphics.gl.compiler;
import beamui.graphics.gl.errors;

/// Base class for GUI shader programs
class GLProgram
{
    abstract @property string vertexSource() const;
    abstract @property string fragmentSource() const;

    private GLuint programID;

    private int glslVersionInt;
    private char[] glslVersionString;

    this()
    {
        const glslVersionRaw = cast(const(char)*)checkgl!glGetString(GL_SHADING_LANGUAGE_VERSION);
        if (glslVersionRaw)
        {
            for (int i;; i++)
            {
                const ch = glslVersionRaw[i];
                if (ch >= '0' && ch <= '9')
                {
                    glslVersionInt = glslVersionInt * 10 + (ch - '0');
                    glslVersionString ~= ch;
                }
                else if (ch != '.')
                    break;
            }
        }
        version (Android)
        {
            glslVersionInt = 130;
        }
        if (glslVersionString.length > 0)
            Log.v("GLSL version: ", glslVersionString);

        string vsrc = preprocess(vertexSource, ShaderStage.vertex);
        string fsrc = preprocess(fragmentSource, ShaderStage.fragment);
        const vs = compileShader(vsrc, ShaderStage.vertex);
        const fs = compileShader(fsrc, ShaderStage.fragment);
        if (vs == 0 || fs == 0)
            return;

        programID = linkShaders(vs, fs);
        if (programID == 0)
            return;

        if (!initLocations())
        {
            Log.e("Some of program locations were not found");
            programID = 0;
            return;
        }
        Log.v("Program initialized successfully");
    }

    ~this()
    {
        if (programID != 0)
            glDeleteProgram(programID);
        programID = 0;
    }

    private string preprocess(string code, ShaderStage stage)
    {
        char[] buf;
        if (glslVersionString.length > 0)
            buf = "#version " ~ glslVersionString ~ "\n";
        buf ~= code;

        // compatibility fixes
        if (glslVersionInt < 150)
            buf = replace(buf, " texture(", " texture2D(");
        if (glslVersionInt < 140)
        {
            if (stage == ShaderStage.vertex)
            {
                buf = replace(buf, "in ", "attribute ");
                buf = replace(buf, "out ", "varying ");
            }
            else
            {
                buf = replace(buf, "in ", "varying ");
                buf = replace(buf, "out vec4 outColor;", "");
                buf = replace(buf, "outColor", "gl_FragColor");
            }
        }
        return cast(string)buf;
    }

    /// Returns true if program is ready for use
    final bool check() const
    {
        return programID != 0;
    }

    /// Binds program in the current context
    void bind()
    {
        assert(check(), "Attempt to bind invalid shader program");
        if (programID != currentProgramID)
        {
            checkgl!glUseProgram(programID);
            currentProgramID = programID;
        }
    }
    private static GLuint currentProgramID; // FIXME: safe on context change?
    /// Unbinds program from current context
    static void unbind()
    {
        checkgl!glUseProgram(0);
        currentProgramID = 0;
    }

    /// Override to init shader code locations. Return `false` on error
    abstract bool initLocations();

    /// Get uniform location from program, returns -1 if location is not found
    final int getUniformLocation(string variableName) const
    {
        return checkgl!glGetUniformLocation(programID, variableName.toStringz);
    }

    /// Get attribute location from program, returns -1 if location is not found
    final int getAttribLocation(string variableName) const
    {
        return checkgl!glGetAttribLocation(programID, variableName.toStringz);
    }
}
