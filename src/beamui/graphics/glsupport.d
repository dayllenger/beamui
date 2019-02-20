/**
This module contains OpenGL access layer.

To enable OpenGL support, build with version(USE_OPENGL);

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.glsupport;

import beamui.core.config;

static if (USE_OPENGL):
import beamui.core.functions : eliminate;
import beamui.core.geometry : Point, Rect;
import beamui.core.logger;
import beamui.core.math3d;
import beamui.graphics.colors : Color;
import beamui.graphics.gl.errors;
import beamui.graphics.gl.objects;
import beamui.graphics.gl.program;
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

class SolidFillProgram : GLProgram
{
    override @property string vertexSource() const
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

    override @property string fragmentSource() const
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
    override @property string vertexSource() const
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

    override @property string fragmentSource() const
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

private __gshared GLBackend _glBackend;
/// Returns GL backend instance. Null if GL is not loaded.
@property GLBackend glSupport() { return _glBackend; }

/// Load OpenGL 1.0 and 1.1 functions
bool initBasicOpenGL()
{
    if (_glBackend)
        return true;
    glNoContext = false;
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

/// Initialize OpenGL backend (call only when current OpenGL context is initialized)
bool initGLSupport(bool legacy)
{
    if (_glBackend)
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
        legacy = legacy || glReloaded && !gl3Reloaded;
    }
    const char major = glGetString(GL_VERSION)[0];
    legacy = legacy || major < '3';
    if (!legacy)
    {
        auto normal = new NormalGLBackend;
        if (normal.valid)
        {
            _glBackend = normal;
            Log.v("OpenGL initialized successfully");
            return true;
        }
        else
            destroy(normal);
    }
    // trying legacy
    static if (SUPPORT_LEGACY_OPENGL)
    {
        // situation when GL version is 3+ with no old functions
        if (!glLightfv)
        {
            Log.w("Legacy GL API is not supported");
            if (major >= '3')
                Log.w("Try to create OpenGL context with <= 3.1 version");
            return false;
        }
        _glBackend = new LegacyGLBackend;
        Log.v("OpenGL initialized successfully");
        return true;
    }
    else
    {
        // do not recreate legacy mode
        return false;
    }
}

/// Deinitialize GLBackend, destroy all internal shaders, buffers, etc.
void uninitGLSupport()
{
    eliminate(_glBackend);
    glNoContext = true;
}

/// Open GL drawing backend
abstract class GLBackend
{
    @property OpenGLQueue queue() { return _queue; }
    /// Projection matrix
    @property ref mat4 projectionMatrix() { return _projectionMatrix; }

    private
    {
        OpenGLQueue _queue;
        /// Current gl buffer width
        int bufferDx;
        /// Current gl buffer height
        int bufferDy;
        mat4 _projectionMatrix;
    }

    this()
    {
        Log.d("Creating GL backend");
        _queue = new OpenGLQueue;
    }

    ~this()
    {
        eliminate(_queue);
    }

    void beforeRenderGUI()
    {
        glEnable(GL_BLEND);
        checkgl!glDisable(GL_CULL_FACE);
        checkgl!glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    }

    protected void fillBuffers(float[] vertices, float[] colors, float[] texcoords, int[] indices) {}

    protected void destroyBuffers() {}

    protected void drawLines(int length, int start);

    protected void drawSolidFillTriangles(int length, int start);

    protected void drawColorAndTextureTriangles(Tex2D texture, bool linear, int length, int start);

    /// Call glFlush
    final void flushGL()
    {
        checkgl!glFlush();
    }

    final bool generateMipmap(int dx, int dy, ubyte* pixels, int level, ref ubyte[] dst)
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
        foreach (y; 0 .. newdy)
        {
            foreach (x; 0 .. newdx)
            {
                dstptr[0] = cast(ubyte)((srcptr[0 + 0] + srcptr[0 + 4] +srcptr[0 + srcstride] +
                    srcptr[0 + srcstride + 4]) >> 2);
                dstptr[1] = cast(ubyte)((srcptr[1 + 0] + srcptr[1 + 4] +srcptr[1 + srcstride] +
                    srcptr[1 + srcstride + 4]) >> 2);
                dstptr[2] = cast(ubyte)((srcptr[2 + 0] + srcptr[2 + 4] +srcptr[2 + srcstride] +
                    srcptr[2 + srcstride + 4]) >> 2);
                dstptr[3] = cast(ubyte)((srcptr[3 + 0] + srcptr[3 + 4] +srcptr[3 + srcstride] +
                    srcptr[3 + srcstride + 4]) >> 2);
                dstptr += 4;
                srcptr += 8;
            }
            srcptr += srcstride; // skip srcline
        }
        checkgl!glTexImage2D(GL_TEXTURE_2D, level, GL_RGBA, newdx, newdy, 0, GL_RGBA, GL_UNSIGNED_BYTE, dst.ptr);
        return true;
    }

    final bool setTextureImage(Tex2D texture, int dx, int dy, ubyte* pixels, int mipmapLevels = 0)
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

    final bool setTextureImageAlpha(Tex2D texture, int dx, int dy, ubyte* pixels)
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

    final void clearDepthBuffer()
    {
        glClear(GL_DEPTH_BUFFER_BIT);
        //glClear(GL_DEPTH_BUFFER_BIT | GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    }

    void setOrthoProjection(Rect windowRect, Rect view);
}

/// Backend for OpenGL 3.0+
private final class NormalGLBackend : GLBackend
{
    @property bool valid()
    {
        return _shadersAreInitialized;
    }

    private
    {
        SolidFillProgram _solidFillProgram;
        TextureProgram _textureProgram;
        bool _shadersAreInitialized;

        VBO vbo;
        EBO ebo;
    }

    this()
    {
        _shadersAreInitialized = initShaders();
        if (_shadersAreInitialized)
            Log.d("Shaders compiled successfully");
        else
            Log.e("Failed to compile shaders");
    }

    ~this()
    {
        Log.d("Uniniting shaders");
        eliminate(_solidFillProgram);
        eliminate(_textureProgram);
    }

    private bool initShaders()
    {
        Log.v("Compiling solid fill program");
        _solidFillProgram = new SolidFillProgram;
        if (!_solidFillProgram.check())
            return false;
        Log.v("Compiling texture program");
        _textureProgram = new TextureProgram;
        if (!_textureProgram.check())
            return false;
        return true;
    }

    override protected void fillBuffers(float[] vertices, float[] colors, float[] texcoords, int[] indices)
    {
        assert(_solidFillProgram && _textureProgram);

        resetBindings();

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

    override protected void destroyBuffers()
    {
        assert(_solidFillProgram && _textureProgram);

        resetBindings();

        _solidFillProgram.destroyBuffers();
        _textureProgram.destroyBuffers();

        eliminate(vbo);
        eliminate(ebo);
    }

    /// This function is needed to draw custom OpenGL scene correctly (especially on legacy API)
    private static void resetBindings()
    {
        if (defined!glUseProgram)
            GLProgram.unbind();
        if (defined!glBindVertexArray)
            VAO.unbind();
        if (defined!glBindBuffer)
            VBO.unbind();
    }

    private static bool defined(alias func)()
    {
        import std.traits : isFunction;

        static if (isFunction!func)
            return true;
        else
            return func !is null;
    }

    override protected void drawLines(int length, int start)
    {
        _solidFillProgram.drawBatch(length, start, true);
    }

    override protected void drawSolidFillTriangles(int length, int start)
    {
        _solidFillProgram.drawBatch(length, start);
    }

    override protected void drawColorAndTextureTriangles(Tex2D texture, bool linear, int length, int start)
    {
        _textureProgram.drawBatch(texture, linear, length, start);
    }

    override void setOrthoProjection(Rect windowRect, Rect view)
    {
        bufferDx = windowRect.width;
        bufferDy = windowRect.height;
        _projectionMatrix.setOrtho(view.left, view.right, view.top, view.bottom, 0.5f, 50.0f);

        checkgl!glViewport(view.left, windowRect.height - view.bottom, view.width, view.height);
    }
}

static if (SUPPORT_LEGACY_OPENGL)
/// Backend for old fixed pipeline OpenGL
private final class LegacyGLBackend : GLBackend
{
    override protected void drawLines(int length, int start)
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

    override protected void drawSolidFillTriangles(int length, int start)
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

    override protected void drawColorAndTextureTriangles(Tex2D texture, bool linear, int length, int start)
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

    override void setOrthoProjection(Rect windowRect, Rect view)
    {
        bufferDx = windowRect.width;
        bufferDy = windowRect.height;
        _projectionMatrix.setOrtho(view.left, view.right, view.top, view.bottom, 0.5f, 50.0f);

        glMatrixMode(GL_PROJECTION);
        //checkgl!glPushMatrix();
        //glLoadIdentity();
        glLoadMatrixf(_projectionMatrix.m.ptr);
        //glOrthof(0, _dx, 0, _dy, -1.0f, 1.0f);
        glMatrixMode(GL_MODELVIEW);
        //checkgl!glPushMatrix();
        glLoadIdentity();
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
