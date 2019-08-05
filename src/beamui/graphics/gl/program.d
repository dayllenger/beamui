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
import beamui.core.functions : getShortClassName;
import beamui.core.logger;
import beamui.graphics.gl.api;
import beamui.graphics.gl.compiler;
import beamui.graphics.gl.errors;

/// Base class for GUI shader programs
class GLProgram
{
    abstract @property string vertexSource() const;
    abstract @property string fragmentSource() const;

    /// Returns true if program is ready for use
    final @property bool valid() const
    {
        return programID != 0;
    }

    private GLuint programID;

    this()
    {
        assert(glslVersionInt != 0 && glslVersionString.length > 0);

        Log.v("GL: compiling ", getShortClassName(this));

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
            Log.e("GL: some of program locations were not found");
            programID = 0;
            return;
        }

        relinkProgram(programID);
        if (programID == 0)
            Log.e("GL: cannot relink program");
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
        buf.reserve(code.length);
        buf ~= "#version ";
        buf ~= glslVersionString;
        buf ~= '\n';

        bool detab;
        foreach (ch; code)
        {
            if (ch != ' ' && ch != '\t')
                detab = false;
            if (!detab)
            {
                buf ~= ch;
                if (ch == '\n')
                    detab = true;
            }
        }

        // compatibility fixes
        if (glslVersionInt < 150)
            buf = replace(buf, " texture(", " texture2D(");
        if (glslVersionInt < 140)
        {
            buf = replace(buf, "\nconst ", "\n");
            if (stage == ShaderStage.vertex)
            {
                buf = replace(buf, "\nin ", "\nattribute ");
                buf = replace(buf, "\nout ", "\nvarying ");
            }
            else
            {
                buf = replace(buf, "\nin ", "\nvarying ");
                buf = replace(buf, "\nout vec4 outColor;", "\n");
                buf = replace(buf, "outColor", "gl_FragColor");
            }
        }
        return cast(string)buf;
    }

    /// Binds program in the current context
    final void bind()
    {
        assert(valid, "Attempt to bind invalid shader program");
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

    /// Associate a number with an attribute. Must be used inside of `initLocations`
    final void bindAttribLocation(string name, GLuint location) const
    {
        checkgl!glBindAttribLocation(programID, location, toStringz(name));
    }
    /// Get uniform location from program, returns -1 if location is not found
    final int getUniformLocation(string name) const
    {
        return checkgl!glGetUniformLocation(programID, toStringz(name));
    }

    package(beamui) static int glslVersionInt;
    private static char[] glslVersionString;

    package(beamui) static bool determineGLSLVersion()
    {
        if (const raw = checkgl!glGetString(GL_SHADING_LANGUAGE_VERSION))
        {
            for (int i;; i++)
            {
                const ch = raw[i];
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

        return glslVersionInt != 0 && glslVersionString.length > 0;
    }
}
