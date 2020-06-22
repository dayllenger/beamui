/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.gl.program;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
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
nothrow:

    abstract @property string vertexSource() const;
    abstract @property string fragmentSource() const;

    /// Returns true if program is ready for use
    final @property bool valid() const
    {
        return programID != 0;
    }

    const GLuint programID;

    this()
    {
        assert(GLSLInfo.versionInt != 0 && GLSLInfo.versionString.length > 0);

        Log.v("GL: compiling ", getShortClassName(this));

        string vsrc = preprocess(vertexSource, ShaderStage.vertex);
        string fsrc = preprocess(fragmentSource, ShaderStage.fragment);
        const vs = compileShader(vsrc, ShaderStage.vertex);
        const fs = compileShader(fsrc, ShaderStage.fragment);
        if (vs == 0 || fs == 0)
            return;

        const id = linkShaders(vs, fs);
        if (!id)
            return;

        if (!initLocations(GLProgramInterface(id)))
        {
            Log.e("GL: some of program locations were not found");
            return;
        }
        if (!relinkProgram(id))
        {
            Log.e("GL: cannot relink program");
            return;
        }
        programID = id;
    }

    ~this()
    {
        if (programID != 0)
            glDeleteProgram(programID);
    }

    private string preprocess(string code, ShaderStage stage)
    {
        char[] buf;
        buf.reserve(code.length);
        buf ~= "#version ";
        buf ~= GLSLInfo.versionString;
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
        if (GLSLInfo.versionInt < 420)
            buf = replace(buf, "\nconst ", "\n");
        if (GLSLInfo.versionInt < 150)
            buf = replace(buf, " texture(", " texture2D(");
        if (GLSLInfo.versionInt < 140)
        {
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

    /// Override to init shader code locations. Return `false` on error
    abstract bool initLocations(const GLProgramInterface pi);
}

struct GLProgramInterface
{
nothrow:

    const GLuint programID;

    /// Associate a number with an attribute
    void bindAttribLocation(string name, GLuint location) const
    {
        checkgl!glBindAttribLocation(programID, location, toStringz(name));
    }
    /// Get uniform location from program, returns -1 if location is not found
    int getUniformLocation(string name) const
    {
        return checkgl!glGetUniformLocation(programID, toStringz(name));
    }
}

package struct GLSLInfo
{
    static int versionInt;
    static char[] versionString;

    static bool determineVersion() nothrow
    {
        if (const raw = checkgl!glGetString(GL_SHADING_LANGUAGE_VERSION))
        {
            for (int i;; i++)
            {
                const ch = raw[i];
                if (ch >= '0' && ch <= '9')
                {
                    versionInt = versionInt * 10 + (ch - '0');
                    versionString ~= ch;
                }
                else if (ch != '.')
                    break;
            }
        }
        version (Android)
        {
            versionInt = 130;
        }

        return versionInt != 0 && versionString.length > 0;
    }
}
