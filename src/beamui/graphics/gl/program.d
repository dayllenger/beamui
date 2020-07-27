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
public import beamui.graphics.gl.compiler : ShaderStage;
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
    abstract @property string[ShaderStage] sources() const;

    /// Returns true if program is ready for use
    final @property bool isValid() const
    {
        return programID != 0;
    }

    const GLuint programID;

    this()
    {
        assert(GLSLInfo.versionInt != 0 && GLSLInfo.versionString.length > 0);

        Log.v("GL: compiling ", getShortClassName(this));

        // compile shaders
        GLuint[] shaderIDs;
        foreach (pair; byKeyValue(sources))
        {
            const src = preprocess(pair.value, pair.key);
            const shader = compileShader(src, pair.key);
            if (!shader)
            {
                foreach (sh; shaderIDs)
                    glDeleteShader(sh);
                return;
            }
            shaderIDs ~= shader;
        }

        // create and assemble program
        const id = glCreateProgram();
        foreach (sh; shaderIDs)
            glAttachShader(id, sh);

        // flag the shaders for deletion
        foreach (sh; shaderIDs)
            glDeleteShader(sh);

        if (!beforeLinking(GLProgramInterface(id)))
        {
            Log.e("GL: error setting program parameters");
            glDeleteProgram(id);
            return;
        }
        if (!linkProgram(id))
        {
            glDeleteProgram(id);
            return;
        }
        if (!afterLinking(GLProgramInterface(id)))
        {
            Log.e("GL: some of program locations were not found");
            glDeleteProgram(id);
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
                buf = replace(buf, "\nout vec4 f_color;", "\n");
                buf = replace(buf, "f_color", "gl_FragColor");
            }
        }
        return cast(string)buf;
    }

    /// Bind locations, set transform feedback varyings, etc. Return false on error
    abstract bool beforeLinking(const GLProgramInterface pi);
    /// Get code locations and other info. Return false on error
    abstract bool afterLinking(const GLProgramInterface pi);
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
