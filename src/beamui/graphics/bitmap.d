/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.bitmap;

import beamui.core.collections : Buf;
import beamui.core.config;
import beamui.core.functions : getShortClassName;
import beamui.core.geometry : InsetsI, RectI, SizeI;
import beamui.core.logger;
import beamui.core.types : Ref, RefCountedObject;
import beamui.graphics.colors;

/// Describes supported formats of bitmap pixel data
enum PixelFormat
{
    invalid,
    argb8,
    a8,
}

/// 9-patch image scaling information (unscaled frame and scaled middle parts)
struct NinePatch
{
    /// Frame (non-scalable) part size for left, top, right, bottom edges.
    InsetsI frame;
    /// Padding (distance to content area) for left, top, right, bottom edges.
    InsetsI padding;
}

/// Non thread safe
private __gshared uint drawBufIDGenerator;

class Bitmap : RefCountedObject
{
    @property
    {
        /// Bitmap width, in pixels
        int width() const { return _w; }
        /// Bitmap height, in pixels
        int height() const { return _h; }
        /// Bitmap size, in pixels
        SizeI size() const
        {
            return SizeI(_w, _h);
        }
        /// Bitmap pixel format
        PixelFormat format() const
        {
            return impl ? impl.format : PixelFormat.invalid;
        }

        /// Nine-patch info pointer, `null` if this is not a nine patch image buffer
        const(NinePatch)* ninePatch() const { return _ninePatch; }
        /// ditto
        void ninePatch(NinePatch* ninePatch)
        {
            _ninePatch = ninePatch;
        }
        /// Check whether there is nine-patch information available
        bool hasNinePatch() const
        {
            return _ninePatch !is null;
        }

        /// Unique ID of bitmap instance, for using with hardware accelerated rendering for caching
        uint id() const { return _id; }
    }

    private IBitmap impl;

    protected int _w, _h;

    private
    {
        NinePatch* _ninePatch;
        uint _id;

        void* _data;
    }

    debug
    {
        private __gshared int _instanceCount;
        static int instanceCount() { return _instanceCount; }
    }

    this(PixelFormat format)
    {
        impl = getBitmapImpl(format);
        _id = drawBufIDGenerator++;
        debug _instanceCount++;
    }

    ~this()
    {
        debug
        {
            if (APP_IS_SHUTTING_DOWN)
                onResourceDestroyWhileShutdown("bitmap", getShortClassName(this));
            _instanceCount--;
        }
    }

    void function(uint) onDestroyCallback;

    /// Call to remove this image from OpenGL cache when image is updated.
    void invalidate()
    {
        if (onDestroyCallback)
        {
            // remove from cache
            onDestroyCallback(_id);
            // assign new ID
            _id = drawBufIDGenerator++;
        }
    }

    /// Resize the bitmap, invalidating its content
    void resize(int width, int height)
    {
        if (_w != width || _h != height)
        {
            _w = width;
            _h = height;
            _data = resizeImpl(width, height);
        }
    }

    abstract protected void* resizeImpl(int width, int height);

    /// Get a constant pointer to the beginning of the pixel data. `null` if bitmap has zero size
    const(T)* pixels(T)() const
        if (T.sizeof == 1 || T.sizeof == 2 || T.sizeof == 4 ||
            T.sizeof == 8 || T.sizeof == 12 || T.sizeof == 16)
    {
        return cast(const(T)*)_data;
    }
    /// Provides a constant view on the pixel data. The bitmap must have non-zero size
    const(PixelRef!T) look(T)() const
        if (T.sizeof == 1 || T.sizeof == 2 || T.sizeof == 4 ||
            T.sizeof == 8 || T.sizeof == 12 || T.sizeof == 16)
        in(_data)
    {
        return const(PixelRef!T)(cast(const(T*))_data, _w, _h);
    }
    /// Provides a mutable access to the pixel data. The bitmap must have non-zero size
    PixelRef!T mutate(T)()
        if (T.sizeof == 1 || T.sizeof == 2 || T.sizeof == 4 ||
            T.sizeof == 8 || T.sizeof == 12 || T.sizeof == 16)
        in(_data)
    {
        return PixelRef!T(cast(T*)_data, _w, _h);
    }

    /// Detect nine patch using image 1-pixel border. Returns true if 9-patch markup is found in the image
    bool detectNinePatch()
        in(format != PixelFormat.invalid)
    {
        if (_w < 3 || _h < 3)
            return false; // image is too small

        int x00, x01, x10, x11, y00, y01, y10, y11;
        bool found = true;
        found = found && detectHLine(0, x00, x01);
        found = found && detectHLine(_h - 1, x10, x11);
        found = found && detectVLine(0, y00, y01);
        found = found && detectVLine(_w - 1, y10, y11);
        if (!found)
            return false; // no black pixels on 1-pixel frame

        NinePatch* p = new NinePatch;
        p.frame.left = x00 - 1;
        p.frame.top = y00 - 1;
        p.frame.right = _w - x01 - 1;
        p.frame.bottom = _h - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.top = y10 - 1;
        p.padding.right = _w - x11 - 1;
        p.padding.bottom = _h - y11 - 1;
        _ninePatch = p;
        return true;
    }

    /// Detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1)
    {
        const rowBytes = _w * impl.stride;
        const void* line = _data + y * rowBytes;
        bool foundUsed;
        x0 = 0;
        x1 = 0;
        foreach (x; 1 .. _w - 1)
        {
            if (impl.isBlackPixel(line + x * impl.stride))
            {
                if (!foundUsed)
                {
                    x0 = x;
                    foundUsed = true;
                }
                x1 = x + 1;
            }
        }
        return x1 > x0;
    }
    /// Detect position of black pixels in column for 9-patch markup
    private bool detectVLine(int x, ref int y0, ref int y1)
    {
        const rowBytes = _w * impl.stride;
        bool foundUsed;
        y0 = 0;
        y1 = 0;
        foreach (y; 1 .. _h - 1)
        {
            const void* line = _data + y * rowBytes;
            if (impl.isBlackPixel(line + x * impl.stride))
            {
                if (!foundUsed)
                {
                    y0 = y;
                    foundUsed = true;
                }
                y1 = y + 1;
            }
        }
        return y1 > y0;
    }

    /// Apply buffer bounds clipping to rectangle
    bool applyClipping(ref RectI rc) const
    {
        return rc.intersect(RectI(0, 0, width, height));
    }
    /// Apply buffer bounds clipping to rectangle.
    /// If clipping applied to first rectangle, reduce second rectangle bounds proportionally
    bool applyClipping(ref RectI rc, ref RectI rc2) const
    {
        if (rc.empty || rc2.empty)
            return false;
        if (rc.width == rc2.width && rc.height == rc2.height)
        {
            // unscaled
            if (rc.left < 0)
            {
                rc2.left -= rc.left;
                rc.left = 0;
            }
            if (rc.top < 0)
            {
                rc2.top -= rc.top;
                rc.top = 0;
            }
            if (rc.right > width)
            {
                rc2.right -= rc.right - width;
                rc.right = width;
            }
            if (rc.bottom > height)
            {
                rc2.bottom -= rc.bottom - height;
                rc.bottom = height;
            }
        }
        else
        {
            // scaled
            int dstdx = rc.width;
            int dstdy = rc.height;
            int srcdx = rc2.width;
            int srcdy = rc2.height;
            if (rc.left < 0)
            {
                rc2.left -= (rc.left) * srcdx / dstdx;
                rc.left = 0;
            }
            if (rc.top < 0)
            {
                rc2.top -= (rc.top) * srcdy / dstdy;
                rc.top = 0;
            }
            if (rc.right > width)
            {
                rc2.right -= (rc.right - width) * srcdx / dstdx;
                rc.right = width;
            }
            if (rc.bottom > height)
            {
                rc2.bottom -= (rc.bottom - height) * srcdx / dstdx;
                rc.bottom = height;
            }
        }
        return !rc.empty && !rc2.empty;
    }

    //===============================================================
    // Mutation methods

    /// Fill the whole bitmap with a solid color
    void fill(Color color)
        in(format != PixelFormat.invalid)
    {
        if (_w <= 0 || _h <= 0)
            return;

        impl.fill(IBitmap.BitmapView(size, _w * impl.stride, _data), color);
    }

    /// Fill a rectangle with a solid color. The rectangle is clipped against image boundaries
    void fillRect(RectI rect, Color color)
        in(format != PixelFormat.invalid)
    {
        if (!applyClipping(rect))
            return;

        const rowBytes = _w * impl.stride;
        const byteOffset = rect.top * rowBytes + rect.left * impl.stride;
        impl.fill(IBitmap.BitmapView(rect.size, rowBytes, _data + byteOffset), color);
    }

    /** Copy pixel data from `srcRect` region of `source` bitmap to `dstRect` of this bitmap.

        Source and destination regions are clipped against image boundaries.
        Rescales if rectangles have different sizes using "nearest" method.

        Limitations: Bitmaps should have the same pixel format.

        Returns: True if copied something.
    */
    bool blit(const Bitmap source, RectI srcRect, RectI dstRect)
        in(format != PixelFormat.invalid)
        in(source)
        in(source.format != PixelFormat.invalid)
    {
        if (!source.applyClipping(srcRect, dstRect))
            return false;
        if (!applyClipping(dstRect, srcRect))
            return false;

        const rowBytes1 = _w * impl.stride;
        const rowBytes2 = source._w * source.impl.stride;
        const byteOffset1 = dstRect.top * rowBytes1 + dstRect.left * impl.stride;
        const byteOffset2 = srcRect.top * rowBytes2 + srcRect.left * source.impl.stride;
        return impl.blit(
            IBitmap.BitmapView(dstRect.size, rowBytes1, _data + byteOffset1),
            const(IBitmap.BitmapView)(srcRect.size, rowBytes2, source._data + byteOffset2),
            source.format,
        );
    }

    void preMultiplyAlpha()
    {
        if (format != PixelFormat.argb8)
            return;

        auto pxRef = mutate!uint;
        foreach (y; 0 .. _h)
        {
            uint* row = pxRef.scanline(y);
            foreach (ref pixel; row[0 .. _w])
            {
                Color c = Color.fromPacked(pixel);
                c.r = ((c.r * c.a) >> 8) & 0xFF;
                c.g = ((c.g * c.a) >> 8) & 0xFF;
                c.b = ((c.b * c.a) >> 8) & 0xFF;
                pixel = c.rgba;
            }
        }
    }
}

struct PixelRef(T)
{
    private T* ptr;
    private uint rowPitch;
    private uint h;

    /// Returns a pointer to a scanline. `y` must be in bounds
    inout(T)* scanline(int y) inout
        in(0 <= y && y < h)
    {
        return ptr + y * rowPitch;
    }
}

alias DrawBufRef = Ref!Bitmap;

class ColorDrawBuf : Bitmap
{
    private Buf!uint _buf;

    /// Create ARGB8888 draw buf of specified width and height
    this(int width, int height)
    {
        super(PixelFormat.argb8);
        resize(width, height);
    }
    /// Create copy of `ColorDrawBuf`
    this(ColorDrawBuf src)
    {
        super(PixelFormat.argb8);
        resize(src.width, src.height);
        if (auto len = _buf.length)
            _buf.unsafe_ptr[0 .. len] = src._buf.unsafe_ptr[0 .. len];
    }
    /// Create resized copy of `ColorDrawBuf`
    this(ColorDrawBuf src, int width, int height)
    {
        super(PixelFormat.argb8);
        resize(width, height); // fills with transparent
        blit(src, RectI(0, 0, src.width, src.height), RectI(0, 0, width, height));
    }

    override protected void* resizeImpl(int width, int height)
    {
        _buf.resize(_w * _h);
        return _buf.unsafe_ptr;
    }
}

private IBitmap[PixelFormat] implementations;

static this()
{
    implementations[PixelFormat.argb8] = new BitmapARGB8;
    implementations[PixelFormat.a8] = new BitmapA8;
}

private IBitmap getBitmapImpl(PixelFormat fmt)
{
    IBitmap* p = fmt in implementations;
    assert(p, "Unsupported pixel format");
    return *p;
}

interface IBitmap
{
    struct BitmapView
    {
        const SizeI sz;
        const uint rowBytes;
        private void* ptr;

        inout(T*) scanline(T)(int y) inout
            in(0 <= y && y < sz.h)
        {
            return cast(inout(T*))(ptr + y * rowBytes);
        }
    }

nothrow:
    PixelFormat format() const;
    ubyte stride() const;

    /// Is an opaque black pixel?
    bool isBlackPixel(const void* pixel) const;

    void fill(BitmapView dst, Color color);
    bool blit(BitmapView dst, const BitmapView src, PixelFormat srcFmt);

static:
    void fillGeneric(T)(ref BitmapView dst, T value)
    {
        const uint w = dst.sz.w;
        const uint h = dst.sz.h;
        foreach (y; 0 .. h)
        {
            T* row = dst.scanline!T(y);
            row[0 .. w] = value;
        }
    }

    void blitGeneric(T)(ref const BitmapView src, ref BitmapView dst)
    {
        if (src.sz == dst.sz)
        {
            const uint w = src.sz.w;
            const uint h = src.sz.h;
            foreach (y; 0 .. h)
            {
                const srcrow = src.scanline!T(y);
                auto dstrow = dst.scanline!T(y);
                dstrow[0 .. w] = srcrow[0 .. w];
            }
        }
        else // need to rescale
        {
            auto xmapArray = createMap(src.sz.w, dst.sz.w);
            auto ymapArray = createMap(src.sz.h, dst.sz.h);
            uint* xmap = xmapArray.unsafe_ptr;
            uint* ymap = ymapArray.unsafe_ptr;

            const uint w = dst.sz.w;
            const uint h = dst.sz.h;
            foreach (y; 0 .. h)
            {
                const srcrow = src.scanline!T(ymap[y]);
                auto dstrow = dst.scanline!T(y);
                foreach (x; 0 .. w)
                {
                    dstrow[x] = srcrow[xmap[x]];
                }
            }
        }
    }

    /// Create mapping of source coordinates to destination coordinates, for resize
    private Buf!uint createMap(uint srcLen, uint dstLen)
    {
        Buf!uint ret;
        ret.reserve(dstLen);
        const k = cast(double)srcLen / dstLen;
        foreach (i; 0 .. dstLen)
            ret ~= cast(uint)(i * k);
        return ret;
    }
}

final class BitmapARGB8 : IBitmap
{
    PixelFormat format() const { return PixelFormat.argb8; }
    ubyte stride() const { return 4; }

    bool isBlackPixel(const void* pixel) const
    {
        const ptr = cast(const uint*)pixel;
        const c = Color.fromPacked(*ptr);
        return c.r < 10 && c.g < 10 && c.b < 10 && c.a > 245;
    }

    void fill(BitmapView dst, Color color)
    {
        fillGeneric!uint(dst, color.rgba);
    }

    bool blit(BitmapView dst, const BitmapView src, PixelFormat srcFmt)
    {
        switch (srcFmt) with (PixelFormat)
        {
        case argb8:
            blitGeneric!uint(src, dst);
            return true;
        default:
            return false;
        }
    }
}

final class BitmapA8 : IBitmap
{
    PixelFormat format() const { return PixelFormat.a8; }
    ubyte stride() const { return 1; }

    bool isBlackPixel(const void* pixel) const
    {
        const ptr = cast(const ubyte*)pixel;
        return *ptr < 5;
    }

    void fill(BitmapView dst, Color color)
    {
        fillGeneric!ubyte(dst, color.toGray);
    }

    bool blit(BitmapView dst, const BitmapView src, PixelFormat srcFmt)
    {
        switch (srcFmt) with (PixelFormat)
        {
        case a8:
            blitGeneric!ubyte(src, dst);
            return true;
        default:
            return false;
        }
    }
}
