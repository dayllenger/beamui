/**
This module contains OpenGL access layer.

To enable OpenGL support, build with version(USE_OPENGL);

Synopsis:
---
import beamui.graphics.glsupport;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.glsupport;

import beamui.core.config;

static if (USE_OPENGL):
import std.array;
import std.conv;
import std.string;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.math3d;
import beamui.core.types;
import beamui.graphics.colors : Color;
import beamui.graphics.gl.errors;
import beamui.graphics.gl.objects;
package(beamui) import beamui.graphics.gl.objects : glNoContext;

version (Android)
{
    enum SUPPORT_LEGACY_OPENGL = false;
    import EGL.eglplatform : EGLint;
    import EGL.egl;

    //import GLES2.gl2;
    import GLES3.gl3;

    static if (SUPPORT_LEGACY_OPENGL)
    {
        import GLES.gl : glEnableClientState, glLightfv, glColor4f, GL_ALPHA_TEST,
            GL_VERTEX_ARRAY, GL_COLOR_ARRAY, glVertexPointer, glColorPointer, glDisableClientState,
            GL_TEXTURE_COORD_ARRAY, glTexCoordPointer, glColorPointer, glMatrixMode, glLoadMatrixf,
            glLoadIdentity, GL_PROJECTION, GL_MODELVIEW;
    }
}
else
{
    enum SUPPORT_LEGACY_OPENGL = true;
    import derelict.opengl3.types;
    import derelict.opengl3.gl3;
    import derelict.opengl3.gl;

    derelict.util.exception.ShouldThrow gl3MissingSymFunc(string symName)
    {
        import std.algorithm : equal;
        static import derelict.util.exception;

        foreach (s; ["glGetError", "glShaderSource", "glCompileShader", "glGetShaderiv",
                "glGetShaderInfoLog", "glGetString", "glCreateProgram", "glUseProgram",
                "glDeleteProgram", "glDeleteShader", "glEnable", "glDisable",
                "glBlendFunc", "glUniformMatrix4fv", "glGetAttribLocation", "glGetUniformLocation",
                "glGenVertexArrays", "glBindVertexArray", "glBufferData", "glBindBuffer", "glBufferSubData"])
        {
            if (symName.equal(s)) // Symbol is used
                return derelict.util.exception.ShouldThrow.Yes;
        }
        // Don't throw for unused symbol
        return derelict.util.exception.ShouldThrow.No;
    }
}

/// Base class for GUI shader programs
class GLProgram
{
    abstract @property string vertexSource();
    abstract @property string fragmentSource();
    protected GLuint program;
    protected bool initialized;
    protected bool error;

    private GLuint vertexShader;
    private GLuint fragmentShader;
    private string glslversion;
    private int glslversionInt;
    private char[] glslversionString;

    private void compatibilityFixes(ref char[] code, GLuint type)
    {
        if (glslversionInt < 150)
            code = replace(code, " texture(", " texture2D(");
        if (glslversionInt < 140)
        {
            if (type == GL_VERTEX_SHADER)
            {
                code = replace(code, "in ", "attribute ");
                code = replace(code, "out ", "varying ");
            }
            else
            {
                code = replace(code, "in ", "varying ");
                code = replace(code, "out vec4 outColor;", "");
                code = replace(code, "outColor", "gl_FragColor");
            }
        }
    }

    private GLuint compileShader(string src, GLuint type)
    {
        import std.string : toStringz, fromStringz;

        char[] sourceCode;
        if (glslversionString.length)
        {
            sourceCode ~= "#version ";
            sourceCode ~= glslversionString;
            sourceCode ~= "\n";
        }
        sourceCode ~= src;
        compatibilityFixes(sourceCode, type);

        Log.d("compileShader: glslVersion = ", glslversion, ", type: ", (type == GL_VERTEX_SHADER ?
                "GL_VERTEX_SHADER" : (type == GL_FRAGMENT_SHADER ? "GL_FRAGMENT_SHADER" : "UNKNOWN")));
        //Log.v("Shader code:\n", sourceCode);
        GLuint shader = checkgl!glCreateShader(type);
        const char* psrc = sourceCode.toStringz;
        checkgl!glShaderSource(shader, 1, &psrc, null);
        checkgl!glCompileShader(shader);
        GLint compiled;
        checkgl!glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
        if (compiled)
        {
            // compiled successfully
            return shader;
        }
        else
        {
            Log.e("Failed to compile shader source:\n", sourceCode);
            GLint blen = 0;
            GLsizei slen = 0;
            checkgl!glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &blen);
            if (blen > 1)
            {
                GLchar[] msg = new GLchar[blen + 1];
                checkgl!glGetShaderInfoLog(shader, blen, &slen, msg.ptr);
                Log.e("Shader compilation error: ", fromStringz(msg.ptr));
            }
            return 0;
        }
    }

    bool compile()
    {
        glslversion = checkgl!fromStringz(cast(const char*)glGetString(GL_SHADING_LANGUAGE_VERSION)).dup;
        glslversionString.length = 0;
        glslversionInt = 0;
        foreach (ch; glslversion)
        {
            if (ch >= '0' && ch <= '9')
            {
                glslversionString ~= ch;
                glslversionInt = glslversionInt * 10 + (ch - '0');
            }
            else if (ch != '.')
                break;
        }
        version (Android)
        {
            glslversionInt = 130;
        }

        vertexShader = compileShader(vertexSource, GL_VERTEX_SHADER);
        fragmentShader = compileShader(fragmentSource, GL_FRAGMENT_SHADER);
        if (!vertexShader || !fragmentShader)
        {
            error = true;
            return false;
        }
        program = checkgl!glCreateProgram();
        checkgl!glAttachShader(program, vertexShader);
        checkgl!glAttachShader(program, fragmentShader);
        checkgl!glLinkProgram(program);
        GLint isLinked = 0;
        checkgl!glGetProgramiv(program, GL_LINK_STATUS, &isLinked);
        if (!isLinked)
        {
            GLint maxLength = 0;
            checkgl!glGetProgramiv(program, GL_INFO_LOG_LENGTH, &maxLength);
            GLchar[] msg = new GLchar[maxLength + 1];
            checkgl!glGetProgramInfoLog(program, maxLength, &maxLength, msg.ptr);
            Log.e("Error while linking program: ", fromStringz(msg.ptr));
            error = true;
            return false;
        }
        Log.d("Program linked successfully");

        if (!initLocations())
        {
            Log.e("some of locations were not found");
            error = true;
        }
        initialized = true;
        Log.v("Program is initialized successfully");
        return !error;
    }

    /// Override to init shader code locations
    abstract bool initLocations();

    ~this()
    {
        if (program)
            glDeleteProgram(program);
        if (vertexShader)
            glDeleteShader(vertexShader);
        if (fragmentShader)
            glDeleteShader(fragmentShader);
        program = vertexShader = fragmentShader = 0;
        initialized = false;
    }

    /// Returns true if program is ready for use
    bool check()
    {
        return !error && initialized;
    }

    static GLuint currentProgram;
    /// Binds program to current context
    void bind()
    {
        if (program != currentProgram)
        {
            checkgl!glUseProgram(program);
            currentProgram = program;
        }
    }

    /// Unbinds program from current context
    static void unbind()
    {
        checkgl!glUseProgram(0);
        currentProgram = 0;
    }

    /// Get uniform location from program, returns -1 if location is not found
    int getUniformLocation(string variableName)
    {
        return checkgl!glGetUniformLocation(program, variableName.toStringz);
    }

    /// Get attribute location from program, returns -1 if location is not found
    int getAttribLocation(string variableName)
    {
        return checkgl!glGetAttribLocation(program, variableName.toStringz);
    }
}

class SolidFillProgram : GLProgram
{
    override @property string vertexSource()
    {
        return q{
            in vec3 vertexPosition;
            in vec4 vertexColor;
            out vec4 color;
            uniform mat4 MVP;

            void main()
            {
                gl_Position = MVP * vec4(vertexPosition, 1);
                color = vertexColor;
            }
        };
    }

    override @property string fragmentSource()
    {
        return q{
            in vec4 color;
            out vec4 outColor;

            void main()
            {
                outColor = color;
            }
        };
    }

    protected GLint matrixLocation;
    protected GLint vertexLocation;
    protected GLint colAttrLocation;
    override bool initLocations()
    {
        matrixLocation = getUniformLocation("MVP");
        vertexLocation = getAttribLocation("vertexPosition");
        colAttrLocation = getAttribLocation("vertexColor");
        return matrixLocation >= 0 && vertexLocation >= 0 && colAttrLocation >= 0;
    }

    VAO vao;

    protected void beforeExecute()
    {
        bind();
        checkgl!glUniformMatrix4fv(matrixLocation, 1, false, glSupport.projectionMatrix.m.ptr);
    }

    protected void createVAO(size_t verticesBufferLength)
    {
        vao = new VAO;

        glVertexAttribPointer(vertexLocation, 3, GL_FLOAT, GL_FALSE, 0, cast(void*)0);
        glVertexAttribPointer(colAttrLocation, 4, GL_FLOAT, GL_FALSE, 0,
                cast(void*)(verticesBufferLength * float.sizeof));

        glEnableVertexAttribArray(vertexLocation);
        glEnableVertexAttribArray(colAttrLocation);
    }

    bool drawBatch(int length, int start, bool areLines = false)
    {
        if (!check())
            return false;
        beforeExecute();

        vao.bind();

        checkgl!glDrawElements(areLines ? GL_LINES : GL_TRIANGLES, cast(int)length, GL_UNSIGNED_INT,
                cast(void*)(start * 4));

        return true;
    }

    void destroyBuffers()
    {
        eliminate(vao);
    }
}

class TextureProgram : SolidFillProgram
{
    override @property string vertexSource()
    {
        return q{
            in vec3 vertexPosition;
            in vec4 vertexColor;
            in vec2 vertexUV;
            out vec4 color;
            out vec2 UV;
            uniform mat4 MVP;

            void main()
            {
                gl_Position = MVP * vec4(vertexPosition, 1);
                color = vertexColor;
                UV = vertexUV;
            }
        };
    }

    override @property string fragmentSource()
    {
        return q{
            in vec4 color;
            in vec2 UV;
            out vec4 outColor;
            uniform sampler2D tex;

            void main()
            {
                outColor = texture(tex, UV) * color;
            }
        };
    }

    GLint texCoordLocation;
    override bool initLocations()
    {
        bool res = super.initLocations();
        texCoordLocation = getAttribLocation("vertexUV");
        return res && texCoordLocation >= 0;
    }

    protected void createVAO(size_t verticesBufferLength, size_t colorsBufferLength)
    {
        vao = new VAO;

        glVertexAttribPointer(vertexLocation, 3, GL_FLOAT, GL_FALSE, 0, cast(void*)0);
        glVertexAttribPointer(colAttrLocation, 4, GL_FLOAT, GL_FALSE, 0,
                cast(void*)(verticesBufferLength * float.sizeof));
        glVertexAttribPointer(texCoordLocation, 2, GL_FLOAT, GL_FALSE, 0,
                cast(void*)((verticesBufferLength + colorsBufferLength) * float.sizeof));

        glEnableVertexAttribArray(vertexLocation);
        glEnableVertexAttribArray(colAttrLocation);
        glEnableVertexAttribArray(texCoordLocation);
    }

    bool drawBatch(Tex2D texture, bool linear, int length, int start)
    {
        if (!check())
            return false;
        beforeExecute();

        texture.setup();
        texture.setSamplerParams(linear);

        vao.bind();

        checkgl!glDrawElements(GL_TRIANGLES, cast(int)length, GL_UNSIGNED_INT, cast(void*)(start * 4));

        texture.unbind();
        return true;
    }
}

private __gshared GLSupport _glSupport;
@property GLSupport glSupport()
{
    if (!_glSupport)
    {
        Log.f("GLSupport is not initialized");
        assert(false, "GLSupport is not initialized");
    }
    if (!_glSupport.valid)
    {
        Log.e("GLSupport programs are not initialized");
    }
    return _glSupport;
}

/// Load OpenGL 1.0 and 1.1 functions
bool initBasicOpenGL()
{
    try
    {
        DerelictGL3.missingSymbolCallback = &gl3MissingSymFunc;
        DerelictGL3.load();
        DerelictGL.missingSymbolCallback = &gl3MissingSymFunc;
        DerelictGL.load();
        return true;
    }
    catch (Exception e)
    {
        Log.e("Cannot load GL library: ", e);
        return false;
    }
}

/// Initialize OpenGL support helper (call only when current OpenGL context is initialized)
bool initGLSupport(bool legacy)
{
    if (_glSupport && _glSupport.valid)
        return true;
    version (Android)
    {
        Log.d("initGLSupport");
    }
    else
    {
        // at first reload DerelictGL
        static bool triedToReloadDerelict;
        static bool gl3Reloaded;
        static bool glReloaded;
        if (!triedToReloadDerelict)
        {
            triedToReloadDerelict = true;
            try
            {
                Log.v("Reloading DerelictGL3");
                DerelictGL3.missingSymbolCallback = &gl3MissingSymFunc;
                DerelictGL3.reload();
                gl3Reloaded = true;
            }
            catch (Exception e)
            {
                Log.e("Exception while reloading DerelictGL3: ", e);
            }
            try
            {
                Log.v("Reloading DerelictGL");
                DerelictGL.missingSymbolCallback = &gl3MissingSymFunc;
                DerelictGL.reload();
                glReloaded = true;
            }
            catch (Exception e)
            {
                Log.e("Exception while reloading DerelictGL: ", e);
            }
        }
        if (!gl3Reloaded && !glReloaded)
        {
            Log.e("Neither DerelictGL3 nor DerelictGL were reloaded successfully");
            return false;
        }
        legacy = glReloaded && !gl3Reloaded;
    }
    if (!_glSupport)
    {
        int major = *cast(int*)(glGetString(GL_VERSION)[0 .. 1].ptr);
        legacy = legacy || major < 3;
        _glSupport = new GLSupport(legacy);
        if (!_glSupport.valid)
        {
            Log.e("Failed to compile shaders");
            version (Android)
            {
                // do not recreate legacy mode
                return false;
            }
            else
            {
                // try opposite legacy flag
                if (_glSupport.legacyMode == legacy)
                {
                    Log.i("Trying to reinit GLSupport with legacy flag ", !legacy);
                    _glSupport = new GLSupport(!legacy);
                }
                // situation when opposite legacy flag is true and GL version is 3+ with no old functions
                if (_glSupport.legacyMode)
                {
                    if (major >= 3)
                    {
                        Log.e("Try to create OpenGL context with <= 3.1 version");
                        return false;
                    }
                }
            }
        }
    }
    if (_glSupport.valid)
    {
        Log.v("OpenGL is initialized ok");
        return true;
    }
    else
    {
        Log.e("Failed to compile shaders");
        return false;
    }
}

/// OpenGL support helper
final class GLSupport
{
    private bool _legacyMode;
    @property bool legacyMode()
    {
        return _legacyMode;
    }

    @property queue()
    {
        return _queue;
    }

    @property bool valid()
    {
        return _legacyMode || _shadersAreInitialized;
    }

    this(bool legacy)
    {
        Log.d("Creating GLSupport");
        _queue = new OpenGLQueue;
        version (Android)
        {
        }
        else
        {
            if (legacy && !glLightfv)
            {
                Log.w("GLSupport legacy API is not supported");
                legacy = false;
            }
        }
        _legacyMode = legacy;
        if (!_legacyMode)
            _shadersAreInitialized = initShaders();
    }

    ~this()
    {
        Log.d("Uniniting shaders");
        eliminate(_solidFillProgram);
        eliminate(_textureProgram);

        eliminate(_queue);
    }

    private OpenGLQueue _queue;

    private SolidFillProgram _solidFillProgram;
    private TextureProgram _textureProgram;

    private bool _shadersAreInitialized;
    private bool initShaders()
    {
        if (_solidFillProgram is null)
        {
            Log.v("Compiling solid fill program");
            _solidFillProgram = new SolidFillProgram;
            _solidFillProgram.compile();
            if (!_solidFillProgram.check())
                return false;
        }
        if (_textureProgram is null)
        {
            Log.v("Compiling texture program");
            _textureProgram = new TextureProgram;
            _textureProgram.compile();
            if (!_textureProgram.check())
                return false;
        }
        Log.d("Shaders compiled successfully");
        return true;
    }

    void beforeRenderGUI()
    {
        glEnable(GL_BLEND);
        checkgl!glDisable(GL_CULL_FACE);
        checkgl!glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    }

    private VBO vbo;
    private EBO ebo;

    private void fillBuffers(float[] vertices, float[] colors, float[] texcoords, int[] indices)
    {
        resetBindings();

        if (_legacyMode)
            return;

        vbo = new VBO;
        ebo = new EBO;

        vbo.bind();
        vbo.fill([vertices, colors, texcoords]);

        ebo.bind();
        ebo.fill(indices);

        // create vertex array objects and bind vertex buffers to them
        _solidFillProgram.createVAO(vertices.length);
        vbo.bind();
        ebo.bind();
        _textureProgram.createVAO(vertices.length, colors.length);
        vbo.bind();
        ebo.bind();
    }

    /// This function is needed to draw custom OpenGL scene correctly (especially on legacy API)
    private void resetBindings()
    {
        import std.traits : isFunction;

        if (isFunction!glUseProgram)
            GLProgram.unbind();
        if (isFunction!glBindVertexArray)
            VAO.unbind();
        if (isFunction!glBindBuffer)
            VBO.unbind();
    }

    private void destroyBuffers()
    {
        resetBindings();

        if (_legacyMode)
            return;

        if (_solidFillProgram)
            _solidFillProgram.destroyBuffers();
        if (_textureProgram)
            _textureProgram.destroyBuffers();

        eliminate(vbo);
        eliminate(ebo);
    }

    private void drawLines(int length, int start)
    {
        if (_legacyMode)
        {
            static if (SUPPORT_LEGACY_OPENGL)
            {
                glEnableClientState(GL_VERTEX_ARRAY);
                glEnableClientState(GL_COLOR_ARRAY);
                glVertexPointer(3, GL_FLOAT, 0, cast(void*)_queue._vertices.data.ptr);
                glColorPointer(4, GL_FLOAT, 0, cast(void*)_queue._colors.data.ptr);

                checkgl!glDrawElements(GL_LINES, cast(int)length, GL_UNSIGNED_INT,
                        cast(void*)(_queue._indices.data[start .. start + length].ptr));

                glDisableClientState(GL_COLOR_ARRAY);
                glDisableClientState(GL_VERTEX_ARRAY);
            }
        }
        else
        {
            assert(_solidFillProgram !is null);
            _solidFillProgram.drawBatch(length, start, true);
        }
    }

    private void drawSolidFillTriangles(int length, int start)
    {
        if (_legacyMode)
        {
            static if (SUPPORT_LEGACY_OPENGL)
            {
                glEnableClientState(GL_VERTEX_ARRAY);
                glEnableClientState(GL_COLOR_ARRAY);
                glVertexPointer(3, GL_FLOAT, 0, cast(void*)_queue._vertices.data.ptr);
                glColorPointer(4, GL_FLOAT, 0, cast(void*)_queue._colors.data.ptr);

                checkgl!glDrawElements(GL_TRIANGLES, cast(int)length, GL_UNSIGNED_INT,
                        cast(void*)(_queue._indices.data[start .. start + length].ptr));

                glDisableClientState(GL_COLOR_ARRAY);
                glDisableClientState(GL_VERTEX_ARRAY);
            }
        }
        else
        {
            assert(_solidFillProgram !is null);
            _solidFillProgram.drawBatch(length, start);
        }
    }

    private void drawColorAndTextureTriangles(Tex2D texture, bool linear, int length, int start)
    {
        if (_legacyMode)
        {
            static if (SUPPORT_LEGACY_OPENGL)
            {
                glEnable(GL_TEXTURE_2D);
                texture.setup();
                texture.setSamplerParams(linear);

                glEnableClientState(GL_COLOR_ARRAY);
                glEnableClientState(GL_VERTEX_ARRAY);
                glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                glVertexPointer(3, GL_FLOAT, 0, cast(void*)_queue._vertices.data.ptr);
                glTexCoordPointer(2, GL_FLOAT, 0, cast(void*)_queue._texCoords.data.ptr);
                glColorPointer(4, GL_FLOAT, 0, cast(void*)_queue._colors.data.ptr);

                checkgl!glDrawElements(GL_TRIANGLES, cast(int)length, GL_UNSIGNED_INT,
                        cast(void*)(_queue._indices.data[start .. start + length].ptr));

                glDisableClientState(GL_TEXTURE_COORD_ARRAY);
                glDisableClientState(GL_VERTEX_ARRAY);
                glDisableClientState(GL_COLOR_ARRAY);
                glDisable(GL_TEXTURE_2D);
            }
        }
        else
        {
            assert(_textureProgram !is null);
            _textureProgram.drawBatch(texture, linear, length, start);
        }
    }

    /// Call glFlush
    void flushGL()
    {
        checkgl!glFlush();
    }

    bool generateMipmap(int dx, int dy, ubyte* pixels, int level, ref ubyte[] dst)
    {
        if ((dx & 1) || (dy & 1) || dx < 2 || dy < 2)
            return false; // size is not even
        int newdx = dx / 2;
        int newdy = dy / 2;
        int newlen = newdx * newdy * 4;
        if (newlen > dst.length)
            dst.length = newlen;
        ubyte* dstptr = dst.ptr;
        ubyte* srcptr = pixels;
        int srcstride = dx * 4;
        for (int y = 0; y < newdy; y++)
        {
            for (int x = 0; x < newdx; x++)
            {
                dstptr[0] = cast(ubyte)((srcptr[0 + 0] + srcptr[0 + 4] + srcptr[0 + srcstride] + srcptr[0 + srcstride +
                        4]) >> 2);
                dstptr[1] = cast(ubyte)((srcptr[1 + 0] + srcptr[1 + 4] + srcptr[1 + srcstride] + srcptr[1 + srcstride +
                        4]) >> 2);
                dstptr[2] = cast(ubyte)((srcptr[2 + 0] + srcptr[2 + 4] + srcptr[2 + srcstride] + srcptr[2 + srcstride +
                        4]) >> 2);
                dstptr[3] = cast(ubyte)((srcptr[3 + 0] + srcptr[3 + 4] + srcptr[3 + srcstride] + srcptr[3 + srcstride +
                        4]) >> 2);
                dstptr += 4;
                srcptr += 8;
            }
            srcptr += srcstride; // skip srcline
        }
        checkgl!glTexImage2D(GL_TEXTURE_2D, level, GL_RGBA, newdx, newdy, 0, GL_RGBA, GL_UNSIGNED_BYTE, dst.ptr);
        return true;
    }

    bool setTextureImage(Tex2D texture, int dx, int dy, ubyte* pixels, int mipmapLevels = 0)
    {
        checkError("before setTextureImage");
        texture.bind();
        checkgl!glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        texture.setSamplerParams(true, true);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, mipmapLevels > 0 ? mipmapLevels - 1 : 0);
        // ORIGINAL: glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, dx, dy, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
        checkgl!glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, dx, dy, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
        if (checkError("updateTexture - glTexImage2D"))
        {
            Log.e("Cannot set image for texture");
            return false;
        }
        if (mipmapLevels > 1)
        {
            ubyte[] buffer;
            ubyte* src = pixels;
            int ndx = dx;
            int ndy = dy;
            for (int i = 1; i < mipmapLevels; i++)
            {
                if (!generateMipmap(ndx, ndy, src, i, buffer))
                    break;
                ndx /= 2;
                ndy /= 2;
                src = buffer.ptr;
            }
        }
        texture.unbind();
        return true;
    }

    bool setTextureImageAlpha(Tex2D texture, int dx, int dy, ubyte* pixels)
    {
        checkError("before setTextureImageAlpha");
        texture.bind();
        checkgl!glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        texture.setSamplerParams(true, true);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, dx, dy, 0, GL_ALPHA, GL_UNSIGNED_BYTE, pixels);
        if (checkError("setTextureImageAlpha - glTexImage2D"))
        {
            Log.e("Cannot set image for texture");
            return false;
        }
        texture.unbind();
        return true;
    }

    void clearDepthBuffer()
    {
        glClear(GL_DEPTH_BUFFER_BIT);
        //glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    }

    /// Projection matrix
    /// Current gl buffer width
    private int bufferDx;
    /// Current gl buffer height
    private int bufferDy;
    private mat4 _projectionMatrix;

    @property ref mat4 projectionMatrix()
    {
        return _projectionMatrix;
    }

    void setOrthoProjection(Rect windowRect, Rect view)
    {
        flushGL(); // FIXME: needed?
        bufferDx = windowRect.width;
        bufferDy = windowRect.height;
        _projectionMatrix.setOrtho(view.left, view.right, view.top, view.bottom, 0.5f, 50.0f);

        if (_legacyMode)
        {
            static if (SUPPORT_LEGACY_OPENGL)
            {
                glMatrixMode(GL_PROJECTION);
                //checkgl!glPushMatrix();
                //glLoadIdentity();
                glLoadMatrixf(_projectionMatrix.m.ptr);
                //glOrthof(0, _dx, 0, _dy, -1.0f, 1.0f);
                glMatrixMode(GL_MODELVIEW);
                //checkgl!glPushMatrix();
                glLoadIdentity();
            }
        }
        checkgl!glViewport(view.left, windowRect.height - view.bottom, view.width, view.height);
    }
}

/// OpenGL GUI rendering queue. It collects gui draw calls, fills a big buffer for vertex data and draws everything
private final class OpenGLQueue
{
    /// OpenGL batch structure - to draw several triangles in single OpenGL call
    private struct OpenGLBatch
    {
        enum BatchType
        {
            line = 0,
            rect,
            triangle,
            texturedRect
        }
        BatchType type;

        Tex2D texture;
        int textureDx;
        int textureDy;
        bool textureLinear;

        // length of batch in indices
        int length;
        // offset in index buffer
        int start;
    }

    import std.array : Appender;

    Appender!(OpenGLBatch[]) batches;
    // a big buffer
    Appender!(float[]) _vertices;
    Appender!(float[]) _colors;
    Appender!(float[]) _texCoords;
    Appender!(int[]) _indices;

    /// Draw all
    void flush()
    {
        glSupport.fillBuffers(_vertices.data, _colors.data, _texCoords.data, _indices.data);
        foreach (b; batches.data)
        {
            final switch (b.type) with (OpenGLBatch.BatchType)
            {
            case line:
                glSupport.drawLines(b.length, b.start);
                break;
            case rect:
                glSupport.drawSolidFillTriangles(b.length, b.start);
                break;
            case triangle:
                glSupport.drawSolidFillTriangles(b.length, b.start);
                break;
            case texturedRect:
                glSupport.drawColorAndTextureTriangles(b.texture, b.textureLinear, b.length, b.start);
                break;
            }
        }
        //Log.d(batches.length, " ", _vertices.data.length, " ", _colors.data.length, " ", _texCoords.data.length, " ", _indices.data.length);
        glSupport.destroyBuffers();
        batches.clear();
        _vertices.clear();
        _colors.clear();
        _texCoords.clear();
        _indices.clear();
    }

    static immutable float Z_2D = -2.0f;

    /// Add textured rectangle to queue
    void addTexturedRect(Tex2D texture, int textureDx, int textureDy, Color color1, Color color2,
            Color color3, Color color4, Rect srcrc, Rect dstrc, bool linear)
    {
        if (batches.data.length == 0 || batches.data[$ - 1].type != OpenGLBatch.BatchType.texturedRect ||
                batches.data[$ - 1].texture.id != texture.id || batches.data[$ - 1].textureLinear != linear)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.texturedRect, texture, textureDx, textureDy, linear);
            if (batches.data.length > 1)
                batches.data[$ - 1].start = batches.data[$ - 2].start + batches.data[$ - 2].length;
        }

        float[4 * 4] colors;
        color1.rgbaf(colors[0], colors[1], colors[2], colors[3]);
        color2.rgbaf(colors[4], colors[5], colors[6], colors[7]);
        color3.rgbaf(colors[8], colors[9], colors[10], colors[11]);
        color4.rgbaf(colors[12], colors[13], colors[14], colors[15]);

        float dstx0 = cast(float)dstrc.left;
        float dsty0 = cast(float)(glSupport.bufferDy - dstrc.top);
        float dstx1 = cast(float)dstrc.right;
        float dsty1 = cast(float)(glSupport.bufferDy - dstrc.bottom);

        float srcx0 = srcrc.left / cast(float)textureDx;
        float srcy0 = srcrc.top / cast(float)textureDy;
        float srcx1 = srcrc.right / cast(float)textureDx;
        float srcy1 = srcrc.bottom / cast(float)textureDy;

        float[3 * 4] vertices = [dstx0, dsty0, Z_2D, dstx0, dsty1, Z_2D, dstx1, dsty0, Z_2D, dstx1, dsty1, Z_2D];

        float[2 * 4] texCoords = [srcx0, srcy0, srcx0, srcy1, srcx1, srcy0, srcx1, srcy1];

        enum verts = 4;
        mixin(add);
    }

    /// Add solid rectangle to queue
    void addSolidRect(Rect dstRect, Color color)
    {
        addGradientRect(dstRect, color, color, color, color);
    }

    /// Add gradient rectangle to queue
    void addGradientRect(Rect rc, Color color1, Color color2, Color color3, Color color4)
    {
        if (batches.data.length == 0 || batches.data[$ - 1].type != OpenGLBatch.BatchType.rect)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.rect);
            if (batches.data.length > 1)
                batches.data[$ - 1].start = batches.data[$ - 2].start + batches.data[$ - 2].length;
        }

        float[4 * 4] colors;
        color1.rgbaf(colors[0], colors[1], colors[2], colors[3]);
        color2.rgbaf(colors[4], colors[5], colors[6], colors[7]);
        color3.rgbaf(colors[8], colors[9], colors[10], colors[11]);
        color4.rgbaf(colors[12], colors[13], colors[14], colors[15]);

        float x0 = cast(float)(rc.left);
        float y0 = cast(float)(glSupport.bufferDy - rc.top);
        float x1 = cast(float)(rc.right);
        float y1 = cast(float)(glSupport.bufferDy - rc.bottom);

        float[3 * 4] vertices = [x0, y0, Z_2D, x0, y1, Z_2D, x1, y0, Z_2D, x1, y1, Z_2D];
        // fill texture coords buffer with zeros
        float[2 * 4] texCoords = 0;

        enum verts = 4;
        mixin(add);
    }

    /// Add triangle to queue
    void addTriangle(PointF p1, PointF p2, PointF p3, Color color1, Color color2, Color color3)
    {
        if (batches.data.length == 0 || batches.data[$ - 1].type != OpenGLBatch.BatchType.triangle)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.triangle);
            if (batches.data.length > 1)
                batches.data[$ - 1].start = batches.data[$ - 2].start + batches.data[$ - 2].length;
        }

        float[4 * 3] colors;
        color1.rgbaf(colors[0], colors[1], colors[2], colors[3]);
        color2.rgbaf(colors[4], colors[5], colors[6], colors[7]);
        color3.rgbaf(colors[8], colors[9], colors[10], colors[11]);

        float x0 = p1.x;
        float y0 = glSupport.bufferDy - p1.y;
        float x1 = p2.x;
        float y1 = glSupport.bufferDy - p2.y;
        float x2 = p3.x;
        float y2 = glSupport.bufferDy - p3.y;

        float[3 * 3] vertices = [x0, y0, Z_2D, x1, y1, Z_2D, x2, y2, Z_2D];
        // fill texture coords buffer with zeros
        float[2 * 3] texCoords = 0;

        enum verts = 3;
        mixin(add);
    }

    /// Add line to queue
    void addLine(Point p1, Point p2, Color color1, Color color2)
    {
        if (batches.data.length == 0 || batches.data[$ - 1].type != OpenGLBatch.BatchType.line)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.line);
            if (batches.data.length > 1)
                batches.data[$ - 1].start = batches.data[$ - 2].start + batches.data[$ - 2].length;
        }

        float[4 * 2] colors;
        color1.rgbaf(colors[0], colors[1], colors[2], colors[3]);
        color2.rgbaf(colors[4], colors[5], colors[6], colors[7]);

        // half-pixel offset is essential for correct result
        float x0 = cast(float)(p1.x) + 0.5;
        float y0 = cast(float)(glSupport.bufferDy - p1.y) - 0.5;
        float x1 = cast(float)(p2.x) + 0.5;
        float y1 = cast(float)(glSupport.bufferDy - p2.y) - 0.5;

        float[3 * 2] vertices = [x0, y0, Z_2D, x1, y1, Z_2D];
        // fill texture coords buffer with zeros
        float[2 * 2] texCoords = 0;

        enum verts = 2;
        mixin(add);
    }

    enum add = q{
        int offset = cast(int)_vertices.data.length / 3;
        static if (verts == 4)
        {
            // make indices for rectangle (2 triangles == 6 vertexes per rect)
            int[6] indices = [
                offset + 0,
                offset + 1,
                offset + 2,
                offset + 1,
                offset + 2,
                offset + 3 ];
        } else
        static if (verts == 3)
        {
            // make indices for triangles
            int[3] indices = [
                offset + 0,
                offset + 1,
                offset + 2 ];
        } else
        static if (verts == 2)
        {
            // make indices for lines
            int[2] indices = [
                offset + 0,
                offset + 1 ];
        } else
            static assert(0);

        batches.data[$ - 1].length += cast(int)indices.length;

        _vertices ~= cast(float[])vertices;
        _colors ~= cast(float[])colors;
        _texCoords ~= cast(float[])texCoords;
        _indices ~= cast(int[])indices;
    };
}
