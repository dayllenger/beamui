/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.bitmap;

import beamui.core.collections : Buf;
import beamui.core.config;
import beamui.core.functions : DebugInstanceCount, getShortClassName;
import beamui.core.geometry : InsetsI, RectI, SizeI;
import beamui.core.logger;
import beamui.core.signals : Signal;
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
private __gshared uint bitmapIdGenerator;

__gshared Signal!(void delegate(uint id)) onBitmapDestruction;

struct Bitmap
{
    @property
    {
        /// Bitmap width, in pixels
        int width() const
        {
            return data ? data.w : 0;
        }
        /// Bitmap height, in pixels
        int height() const
        {
            return data ? data.h : 0;
        }
        /// Bitmap size, in pixels
        SizeI size() const
        {
            return data ? SizeI(data.w, data.h) : SizeI.init;
        }
        /// Bitmap pixel format. `PixelFormat.invalid` on empty bitmap
        PixelFormat format() const
        {
            return impl ? impl.format : PixelFormat.invalid;
        }
        /// Length of one bitmap row in bytes
        size_t rowBytes() const
        {
            return data ? data.rowBytes : 0;
        }

        /// Nine-patch info pointer, `null` if this is not a nine patch image buffer
        const(NinePatch)* ninePatch() const
        {
            return data ? data.ninePatch : null;
        }
        /// ditto
        void ninePatch(NinePatch* ninePatch)
        {
            if (data)
                data.ninePatch = ninePatch;
        }
        /// Check whether there is nine-patch information available
        bool hasNinePatch() const
        {
            return data && data.ninePatch;
        }

        /// Unique ID of bitmap instance, for using with hardware accelerated rendering for caching
        uint id() const
        {
            return data ? data.id : 0;
        }
    }

    private BitmapData data;
    private IBitmap impl;

    this(int width, int height, PixelFormat format)
        in(width > 0 && height > 0)
    {
        impl = getBitmapImpl(format);
        data = new DefaultBitmapData(width, height, impl.stride, format);
        data.handleResize();
    }

    this(BitmapData data)
        in(data)
    {
        impl = getBitmapImpl(data.format);
        this.data = data;
        data.handleResize();
        assert(data.stride == impl.stride);
    }

    this(ref Bitmap bm)
    {
        if (bm.data)
        {
            data = bm.data;
            impl = bm.impl;
            data.refCount++;
        }
    }

    ~this()
    {
        // decrease counter and destroy the data if no more references left
        if (data)
        {
            if (data.refCount > 1)
                data.refCount--;
            else
                destroy(data);
            data = null;
        }
    }

    /// Copy the shared data right before it is modified
    private void detach()
    {
        if (data.refCount > 1)
        {
            data.refCount--;
            data = data.clone();
        }
    }

    /// Call to remove this image from OpenGL cache when image is updated
    void invalidate()
    {
        if (data)
        {
            // remove from cache
            onBitmapDestruction(data.id);
            // assign new ID
            data.id = bitmapIdGenerator++;
        }
    }

    /// Resize the bitmap, invalidating its content
    void resize(int width, int height)
        in(width > 0 && height > 0)
        in(format != PixelFormat.invalid)
    {
        if (data.w != width || data.h != height)
        {
            detach();
            data.w = width;
            data.h = height;
            data.handleResize();
        }
    }

    /// Get a constant pointer to the beginning of the pixel data. `null` if bitmap has zero size
    const(T)* pixels(T)() const
        if (T.sizeof == 1 || T.sizeof == 2 || T.sizeof == 4 ||
            T.sizeof == 8 || T.sizeof == 12 || T.sizeof == 16)
    {
        return data ? cast(const(T)*)&data.pixels[0] : null;
    }
    /// Provides a constant view on the pixel data. The bitmap must have non-zero size
    const(PixelRef!T) look(T)() const
        if (T.sizeof == 1 || T.sizeof == 2 || T.sizeof == 4 ||
            T.sizeof == 8 || T.sizeof == 12 || T.sizeof == 16)
        in(data)
    {
        return const(PixelRef!T)(data.pixels, data.rowBytes);
    }
    /// Provides a mutable access to the pixel data. The bitmap must have non-zero size
    PixelRef!T mutate(T)()
        if (T.sizeof == 1 || T.sizeof == 2 || T.sizeof == 4 ||
            T.sizeof == 8 || T.sizeof == 12 || T.sizeof == 16)
        in(data)
    {
        detach();
        return PixelRef!T(data.pixels, data.rowBytes);
    }

    bool opCast(To : bool)() const
    {
        return data !is null;
    }

    /// Detect nine patch using image 1-pixel border. Returns true if 9-patch markup is found in the image
    bool detectNinePatch()
        in(format != PixelFormat.invalid)
    {
        if (data.w < 3 || data.h < 3)
            return false; // image is too small

        int x00, x01, x10, x11, y00, y01, y10, y11;
        bool found = true;
        found = found && detectHLine(0, x00, x01);
        found = found && detectHLine(data.h - 1, x10, x11);
        found = found && detectVLine(0, y00, y01);
        found = found && detectVLine(data.w - 1, y10, y11);
        if (!found)
            return false; // no black pixels on 1-pixel frame

        NinePatch* p = new NinePatch;
        p.frame.left = x00 - 1;
        p.frame.top = y00 - 1;
        p.frame.right = data.w - x01 - 1;
        p.frame.bottom = data.h - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.top = y10 - 1;
        p.padding.right = data.w - x11 - 1;
        p.padding.bottom = data.h - y11 - 1;
        data.ninePatch = p;
        return true;
    }

    /// Detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1)
    {
        const void[] line = data.pixels[y * data.rowBytes .. (y + 1) * data.rowBytes];
        bool foundUsed;
        x0 = 0;
        x1 = 0;
        foreach (x; 1 .. data.w - 1)
        {
            if (impl.isBlackPixel(&line[x * impl.stride]))
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
        bool foundUsed;
        y0 = 0;
        y1 = 0;
        foreach (y; 1 .. data.h - 1)
        {
            const void[] line = data.pixels[y * data.rowBytes .. (y + 1) * data.rowBytes];
            if (impl.isBlackPixel(&line[x * impl.stride]))
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
        if (data.w <= 0 || data.h <= 0)
            return;

        detach();
        impl.fill(IBitmap.BitmapView(size, data.rowBytes, &data.pixels[0]), color);
    }

    /// Fill a rectangle with a solid color. The rectangle is clipped against image boundaries
    void fillRect(RectI rect, Color color)
        in(format != PixelFormat.invalid)
    {
        if (!applyClipping(rect))
            return;

        detach();
        const byteOffset = rect.top * data.rowBytes + rect.left * impl.stride;
        impl.fill(IBitmap.BitmapView(rect.size, data.rowBytes, &data.pixels[byteOffset]), color);
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

        detach();
        const byteOffset1 = dstRect.top * data.rowBytes + dstRect.left * impl.stride;
        const byteOffset2 = srcRect.top * source.data.rowBytes + srcRect.left * source.impl.stride;
        return impl.blit(
            IBitmap.BitmapView(dstRect.size, data.rowBytes, &data.pixels[byteOffset1]),
            const(IBitmap.BitmapView)(srcRect.size, source.data.rowBytes, &source.data.pixels[byteOffset2]),
            source.format,
        );
    }

    void preMultiplyAlpha()
    {
        if (format != PixelFormat.argb8)
            return;

        auto pxRef = mutate!uint;
        foreach (y; 0 .. data.h)
        {
            uint* row = pxRef.scanline(y);
            foreach (ref pixel; row[0 .. data.w])
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
    private void[] pixels;
    private size_t rowBytes;

    /// Returns a pointer to a scanline. `y` must be in bounds
    inout(T)* scanline(int y) inout
    {
        return cast(inout(T)*)&pixels[y * rowBytes];
    }
}

abstract class BitmapData
{
    final @property
    {
        int width() const { return w; }
        int height() const { return h; }
    }

    private
    {
        uint refCount = 1;
        uint id;

        int w, h;
        NinePatch* ninePatch;
    }
    protected size_t rowBytes;
    const ubyte stride;
    const PixelFormat format;

    this(uint w, uint h, ubyte stride, PixelFormat format)
        in(w > 0 && h > 0)
        in(stride > 0)
        in(format != PixelFormat.invalid)
    {
        this.w = w;
        this.h = h;
        this.stride = stride;
        this.format = format;

        id = bitmapIdGenerator++;
        debug debugPlusInstance();
    }

    protected this(BitmapData src)
        in(src)
    {
        w = src.w;
        h = src.h;
        rowBytes = src.rowBytes;
        stride = src.stride;
        format = src.format;
        ninePatch = src.ninePatch;

        id = bitmapIdGenerator++;
        debug debugPlusInstance();
    }

    ~this()
    {
        onBitmapDestruction(id);
        debug debugMinusInstance();
    }

    mixin DebugInstanceCount!();

    inout(void[]) pixels() inout;
    void handleResize() out(; rowBytes >= w * stride);
    BitmapData clone() out(bmp; bmp && bmp !is this);
}

final class DefaultBitmapData : BitmapData
{
    private Buf!ubyte buf;

    this(uint w, uint h, ubyte stride, PixelFormat format)
    {
        super(w, h, stride, format);
    }

    this(DefaultBitmapData src)
    {
        super(src);
        buf ~= src.buf[];
    }

    override inout(void[]) pixels() inout
    {
        return buf.unsafe_slice;
    }

    override void handleResize()
    {
        rowBytes = w * stride;
        buf.resize(w * h * stride);
    }

    override BitmapData clone()
    {
        return new DefaultBitmapData(this);
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
        const size_t rowBytes;
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
