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
import beamui.core.geometry : Point, Rect, RectF;
import beamui.core.linalg;
import beamui.core.logger;
import beamui.graphics.colors : Color, ColorF;
import beamui.graphics.gl.api;
import beamui.graphics.gl.errors;
import beamui.graphics.gl.objects;
import beamui.graphics.gl.program;

private __gshared GLBackend _glBackend;
/// Returns GL backend instance. Null if GL is not loaded.
@property GLBackend glSupport() { return _glBackend; }

/// Initialize OpenGL backend (call only when current OpenGL context is initialized)
bool initGLBackend()
{
    if (_glBackend)
        return true;

    _glBackend = GLBackend.create();
    return _glBackend !is null;
}

/// Deinitialize GLBackend, destroy all internal shaders, buffers, etc.
void uninitGLSupport()
{
    eliminate(_glBackend);
}

/// Drawing backend on OpenGL 3.0+
final class GLBackend
{
    @property OpenGLQueue queue() { return _queue; }

    private
    {
        OpenGLQueue _queue;
        /// Current gl buffer width
        int bufferDx;
        /// Current gl buffer height
        int bufferDy;
    }

    static GLBackend create()
    {
        Log.d("GL: creating backend");
        return new GLBackend;
    }

    private this()
    {
        _queue = new OpenGLQueue;
    }

    ~this()
    {
        eliminate(_queue);
    }

    private bool generateMipmap(int dx, int dy, ubyte* pixels, int level, ref ubyte[] dst)
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

    bool setTextureImage(TexId texture, int dx, int dy, ubyte* pixels, bool smooth, int mipmapLevels = 0)
    {
        checkError("before setTextureImage");
        Tex2D.bind(texture);
        Tex2D.setBasicParams(
            smooth ? TexFiltering.smooth : TexFiltering.sharp,
            mipmapLevels > 1 ? TexMipmaps.yes : TexMipmaps.no,
            TexWrap.clamp,
        );

        checkgl!glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, mipmapLevels > 0 ? mipmapLevels - 1 : 0);
        checkgl!glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, dx, dy, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
        if (checkError("updateTexture - glTexImage2D"))
        {
            Log.e("GL: cannot set image for texture");
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
        Tex2D.unbind();
        return true;
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

        TexId texture;
        int textureDx;
        int textureDy;

        // length of batch in indices
        int length;
        // offset in index buffer
        int start;
    }

    import beamui.core.collections : Buf;

    Buf!OpenGLBatch batches;
    // a big buffer
    Buf!float _vertices;
    Buf!float _colors;
    Buf!float _texCoords;
    Buf!int _indices;

    static immutable float Z_2D = -2.0f;

    /// Add textured rectangle to queue
    void addTexturedRect(TexId texture, int textureDx, int textureDy, Color color1, Color color2,
            Color color3, Color color4, Rect srcrc, Rect dstrc)
        in(texture.handle)
    {
        if (batches.length == 0 || batches[$ - 1].type != OpenGLBatch.BatchType.texturedRect ||
                batches[$ - 1].texture != texture)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.texturedRect, texture, textureDx, textureDy);
            if (batches.length > 1)
                batches.unsafe_ref(-1).start = batches[$ - 2].start + batches[$ - 2].length;
        }

        ColorF[4] colors = [ ColorF(color1), ColorF(color2), ColorF(color3), ColorF(color4) ];

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
    void addSolidRect(RectF dstRect, Color color)
    {
        addGradientRect(dstRect, color, color, color, color);
    }

    /// Add gradient rectangle to queue
    void addGradientRect(RectF rc, Color color1, Color color2, Color color3, Color color4)
    {
        if (batches.length == 0 || batches[$ - 1].type != OpenGLBatch.BatchType.rect)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.rect);
            if (batches.length > 1)
                batches.unsafe_ref(-1).start = batches[$ - 2].start + batches[$ - 2].length;
        }

        ColorF[4] colors = [ ColorF(color1), ColorF(color2), ColorF(color3), ColorF(color4) ];

        float x0 = rc.left;
        float y0 = glSupport.bufferDy - rc.top;
        float x1 = rc.right;
        float y1 = glSupport.bufferDy - rc.bottom;

        float[3 * 4] vertices = [x0, y0, Z_2D, x0, y1, Z_2D, x1, y0, Z_2D, x1, y1, Z_2D];
        // fill texture coords buffer with zeros
        float[2 * 4] texCoords = 0;

        enum verts = 4;
        mixin(add);
    }

    /// Add triangle to queue
    void addTriangle(Vec2 p1, Vec2 p2, Vec2 p3, Color color1, Color color2, Color color3)
    {
        if (batches.length == 0 || batches[$ - 1].type != OpenGLBatch.BatchType.triangle)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.triangle);
            if (batches.length > 1)
                batches.unsafe_ref(-1).start = batches[$ - 2].start + batches[$ - 2].length;
        }

        ColorF[3] colors = [ ColorF(color1), ColorF(color2), ColorF(color3) ];

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
    void addLine(Vec2 p1, Vec2 p2, Color color1, Color color2)
    {
        if (batches.length == 0 || batches[$ - 1].type != OpenGLBatch.BatchType.line)
        {
            batches ~= OpenGLBatch(OpenGLBatch.BatchType.line);
            if (batches.length > 1)
                batches.unsafe_ref(-1).start = batches[$ - 2].start + batches[$ - 2].length;
        }

        ColorF[2] colors = [ ColorF(color1), ColorF(color2) ];

        // half-pixel offset is essential for correct result
        float x0 = p1.x + 0.5;
        float y0 = glSupport.bufferDy - p1.y - 0.5;
        float x1 = p2.x + 0.5;
        float y1 = glSupport.bufferDy - p2.y - 0.5;

        float[3 * 2] vertices = [x0, y0, Z_2D, x1, y1, Z_2D];
        // fill texture coords buffer with zeros
        float[2 * 2] texCoords = 0;

        enum verts = 2;
        mixin(add);
    }

    enum add = q{
        int offset = _vertices.length / 3;
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

        batches.unsafe_ref(-1).length += indices.length;

        _vertices ~= cast(float[])vertices;
        _colors ~= cast(float[])colors;
        _texCoords ~= cast(float[])texCoords;
        _indices ~= cast(int[])indices;
    };
}
