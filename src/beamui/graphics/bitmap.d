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

/// Drawing buffer - image container which allows to perform some drawing operations
class DrawBuf : RefCountedObject
{
    @property
    {
        /// Image buffer bits per pixel value
        abstract int bpp() const;
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
        PixelFormat format() const { return _format; }

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

    protected int _w, _h;

    private
    {
        PixelFormat _format;
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
        _format = format;
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

    /// Detect nine patch using image 1-pixel border. Returns true if 9-patch markup is found in the image
    bool detectNinePatch()
    {
        // override
        return false;
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

    //========================================================
    // Drawing methods

    /// Fill the whole bitmap with a solid color
    abstract void fill(Color color);
    /// Fill a rectangle with a solid color. The rectangle is clipped against image boundaries
    abstract void fillRect(RectI rc, Color color);

    /** Copy pixel data from `srcRect` region of `source` bitmap to `dstRect` of this bitmap.

        Source and destination regions are clipped against image boundaries.
        Rescales if rectangles have different sizes using "nearest" method.

        Limitations: Bitmaps should have the same pixel format.

        Returns: True if copied something.
    */
    bool blit(DrawBuf source, RectI srcRect, RectI dstRect)
        in(source)
    {
        if (srcRect.size == dstRect.size)
            drawFragment(dstRect.left, dstRect.top, source, srcRect);
        else
            drawRescaled(dstRect, source, srcRect);
        return true;
    }

    abstract protected void drawFragment(int x, int y, DrawBuf src, RectI srcrect);
    abstract protected void drawRescaled(RectI dstrect, DrawBuf src, RectI srcrect);
}

alias DrawBufRef = Ref!DrawBuf;

class ColorDrawBufBase : DrawBuf
{
    override @property
    {
        int bpp() const { return 32; }
    }

    this()
    {
        super(PixelFormat.argb8);
    }

    /// Returns pointer to ARGB scanline, `null` if `y` is out of range or buffer doesn't provide access to its memory
    inout(uint*) scanLine(int y) inout
    {
        return null;
    }

    override protected void drawFragment(int x, int y, DrawBuf src, RectI srcrect)
    {
        auto img = cast(ColorDrawBufBase)src;
        if (!img)
            return;
        RectI dstrect = RectI(x, y, x + srcrect.width, y + srcrect.height);
        if (!applyClipping(dstrect, srcrect))
            return;
        if (!src.applyClipping(srcrect, dstrect))
            return;

        const int w = srcrect.width;
        const int h = srcrect.height;
        foreach (j; 0 .. h)
        {
            uint* srcrow = img.scanLine(srcrect.top + j) + srcrect.left;
            uint* dstrow = scanLine(dstrect.top + j) + dstrect.left;
            foreach (i; 0 .. w)
            {
                const uint pixel = srcrow[i];
                const uint alpha = pixel >> 24;
                if (alpha == 255)
                {
                    dstrow[i] = pixel;
                }
                else if (alpha > 0)
                {
                    // apply blending
                    blendARGB(dstrow[i], pixel, alpha);
                }
            }
        }
    }

    /// Create mapping of source coordinates to destination coordinates, for resize.
    private Buf!int createMap(int dst0, int dst1, int src0, int src1, double k)
    {
        const dd = dst1 - dst0;
        //int sd = src1 - src0;
        Buf!int ret;
        ret.reserve(dd);
        foreach (int i; 0 .. dd)
            ret ~= src0 + cast(int)(i * k); //sd / dd;
        return ret;
    }

    override protected void drawRescaled(RectI dstrect, DrawBuf src, RectI srcrect)
    {
        auto img = cast(ColorDrawBufBase)src;
        if (!img)
            return;
        double kx = cast(double)srcrect.width / dstrect.width;
        double ky = cast(double)srcrect.height / dstrect.height;
        if (!applyClipping(dstrect, srcrect))
            return;

        auto xmapArray = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right, kx);
        auto ymapArray = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom, ky);
        int* xmap = xmapArray.unsafe_ptr;
        int* ymap = ymapArray.unsafe_ptr;

        const int w = dstrect.width;
        const int h = dstrect.height;
        foreach (y; 0 .. h)
        {
            uint* srcrow = img.scanLine(ymap[y]);
            uint* dstrow = scanLine(dstrect.top + y) + dstrect.left;
            foreach (x; 0 .. w)
            {
                const uint srcpixel = srcrow[xmap[x]];
                const uint alpha = srcpixel >> 24;
                if (alpha == 255)
                {
                    dstrow[x] = srcpixel;
                }
                else if (alpha > 0)
                {
                    // apply blending
                    blendARGB(dstrow[x], srcpixel, alpha);
                }
            }
        }
    }

    /// Detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1)
    {
        uint* line = scanLine(y);
        bool foundUsed = false;
        x0 = 0;
        x1 = 0;
        foreach (int x; 1 .. _w - 1)
        {
            if (isBlackPixel(line[x]))
            { // opaque black pixel
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

    static bool isBlackPixel(uint pixel)
    {
        const c = Color.fromPacked(pixel);
        return c.r < 10 && c.g < 10 && c.b < 10 && c.a > 245;
    }

    /// Detect position of black pixels in column for 9-patch markup
    private bool detectVLine(int x, ref int y0, ref int y1)
    {
        bool foundUsed;
        y0 = 0;
        y1 = 0;
        foreach (int y; 1 .. _h - 1)
        {
            uint* line = scanLine(y);
            if (isBlackPixel(line[x]))
            { // opaque black pixel
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
    /// Detect nine patch using image 1-pixel border (see Android documentation)
    override bool detectNinePatch()
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
        p.frame.right = _w - x01 - 1;
        p.frame.top = y00 - 1;
        p.frame.bottom = _h - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.right = _w - x11 - 1;
        p.padding.top = y10 - 1;
        p.padding.bottom = _h - y11 - 1;
        _ninePatch = p;
        return true;
    }

    override void fillRect(RectI rc, Color color)
    {
        if (!color.isFullyTransparent && applyClipping(rc))
        {
            const bool opaque = color.isOpaque;
            const uint rgb = color.rgb;
            foreach (y; rc.top .. rc.bottom)
            {
                uint* row = scanLine(y);
                if (opaque)
                {
                    row[rc.left .. rc.right] = rgb;
                }
                else
                {
                    foreach (x; rc.left .. rc.right)
                    {
                        // apply blending
                        blendARGB(row[x], rgb, color.a);
                    }
                }
            }
        }
    }
}

class GrayDrawBuf : DrawBuf
{
    override @property
    {
        int bpp() const { return 8; }
    }

    private Buf!ubyte _buf;

    this(int width, int height)
    {
        super(PixelFormat.a8);
        resize(width, height);
    }

    ubyte* scanLine(int y)
    {
        if (y >= 0 && y < _h)
            return _buf.unsafe_ptr + _w * y;
        return null;
    }

    override protected void* resizeImpl(int width, int height)
    {
        _buf.resize(_w * _h);
        return _buf.unsafe_ptr;
    }

    override void fill(Color color)
    {
        _buf.unsafe_slice[] = color.toGray;
    }

    override void drawFragment(int x, int y, DrawBuf src, RectI srcrect)
    {
        auto img = cast(GrayDrawBuf)src;
        if (!img)
            return;
        RectI dstrect = RectI(x, y, x + srcrect.width, y + srcrect.height);
        if (!applyClipping(dstrect, srcrect))
            return;
        if (!src.applyClipping(srcrect, dstrect))
            return;

        const int w = srcrect.width;
        const int h = srcrect.height;
        foreach (j; 0 .. h)
        {
            ubyte* srcrow = img.scanLine(srcrect.top + j) + srcrect.left;
            ubyte* dstrow = scanLine(dstrect.top + j) + dstrect.left;
            dstrow[0 .. w] = srcrow[0 .. w];
        }
    }

    /// Create mapping of source coordinates to destination coordinates, for resize.
    private Buf!int createMap(int dst0, int dst1, int src0, int src1)
    {
        const dd = dst1 - dst0;
        const sd = src1 - src0;
        Buf!int ret;
        ret.reserve(dd);
        foreach (int i; 0 .. dd)
            ret ~= src0 + i * sd / dd;
        return ret;
    }

    override protected void drawRescaled(RectI dstrect, DrawBuf src, RectI srcrect)
    {
        auto img = cast(GrayDrawBuf)src;
        if (!img)
            return;
        if (!applyClipping(dstrect, srcrect))
            return;

        auto xmapArray = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right);
        auto ymapArray = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom);
        int* xmap = xmapArray.unsafe_ptr;
        int* ymap = ymapArray.unsafe_ptr;

        const int w = dstrect.width;
        const int h = dstrect.height;
        foreach (y; 0 .. h)
        {
            ubyte* srcrow = img.scanLine(ymap[y]);
            ubyte* dstrow = scanLine(dstrect.top + y) + dstrect.left;
            foreach (x; 0 .. w)
            {
                dstrow[x] = srcrow[xmap[x]];
            }
        }
    }

    /// Detect position of black pixels in row for 9-patch markup
    private bool detectHLine(int y, ref int x0, ref int x1)
    {
        ubyte* line = scanLine(y);
        bool foundUsed = false;
        x0 = 0;
        x1 = 0;
        foreach (int x; 1 .. _w - 1)
        {
            if (line[x] < 5)
            { // opaque black pixel
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
        bool foundUsed = false;
        y0 = 0;
        y1 = 0;
        foreach (int y; 1 .. _h - 1)
        {
            ubyte* line = scanLine(y);
            if (line[x] < 5)
            { // opaque black pixel
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
    /// Detect nine patch using image 1-pixel border (see Android documentation)
    override bool detectNinePatch()
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
        p.frame.right = _h - y01 - 1;
        p.frame.top = y00 - 1;
        p.frame.bottom = _h - y01 - 1;
        p.padding.left = x10 - 1;
        p.padding.right = _h - y11 - 1;
        p.padding.top = y10 - 1;
        p.padding.bottom = _h - y11 - 1;
        _ninePatch = p;
        return true;
    }

    override void fillRect(RectI rc, Color color)
    {
        if (!color.isFullyTransparent && applyClipping(rc))
        {
            const ubyte c = color.toGray;
            const ubyte a = color.a;
            const bool opaque = color.isOpaque;
            foreach (y; rc.top .. rc.bottom)
            {
                ubyte* row = scanLine(y);
                foreach (x; rc.left .. rc.right)
                {
                    if (opaque)
                    {
                        row[x] = c;
                    }
                    else
                    {
                        // apply blending
                        row[x] = blendGray(row[x], c, a);
                    }
                }
            }
        }
    }
}

class ColorDrawBuf : ColorDrawBufBase
{
    private Buf!uint _buf;

    /// Create ARGB8888 draw buf of specified width and height
    this(int width, int height)
    {
        resize(width, height);
    }
    /// Create copy of `ColorDrawBuf`
    this(ColorDrawBuf src)
    {
        resize(src.width, src.height);
        if (auto len = _buf.length)
            _buf.unsafe_ptr[0 .. len] = src._buf.unsafe_ptr[0 .. len];
    }
    /// Create resized copy of `ColorDrawBuf`
    this(ColorDrawBuf src, int width, int height)
    {
        resize(width, height); // fills with transparent
        blit(src, RectI(0, 0, src.width, src.height), RectI(0, 0, width, height));
    }

    void preMultiplyAlpha()
    {
        foreach (ref pixel; _buf.unsafe_slice)
        {
            Color c = Color.fromPacked(pixel);
            c.r = ((c.r * c.a) >> 8) & 0xFF;
            c.g = ((c.g * c.a) >> 8) & 0xFF;
            c.b = ((c.b * c.a) >> 8) & 0xFF;
            pixel = c.rgba;
        }
    }

    void invertAlpha()
    {
        foreach (ref pixel; _buf.unsafe_slice)
            pixel ^= 0xFF000000;
    }

    void invertByteOrder()
    {
        foreach (ref pixel; _buf.unsafe_slice)
        {
            pixel = (pixel & 0xFF00FF00) | ((pixel & 0xFF0000) >> 16) | ((pixel & 0xFF) << 16);
        }
    }

    // for passing of image to OpenGL texture
    void invertAlphaAndByteOrder()
    {
        foreach (ref pixel; _buf.unsafe_slice)
        {
            pixel = ((pixel & 0xFF00FF00) | ((pixel & 0xFF0000) >> 16) | ((pixel & 0xFF) << 16));
            pixel ^= 0xFF000000;
        }
    }

    override inout(uint*) scanLine(int y) inout
    {
        if (y >= 0 && y < _h)
            return _buf.unsafe_ptr + _w * y;
        return null;
    }

    override protected void* resizeImpl(int width, int height)
    {
        _buf.resize(_w * _h);
        return _buf.unsafe_ptr;
    }

    override void fill(Color color)
    {
        _buf.unsafe_slice[] = color.rgba;
    }

    /// Apply Gaussian blur to the image
    void blur(uint blurSize)
    {
        if (blurSize == 0)
            return; // trivial case

        // utility functions to get and set color
        float[4] get(const uint[] buf, uint x, uint y)
        {
            uint c = buf[x + y * _w];
            float a = 255 - (c >> 24);
            float r = (c >> 16) & 0xFF;
            float g = (c >> 8) & 0xFF;
            float b = (c >> 0) & 0xFF;
            return [r, g, b, a];
        }

        void set(uint[] buf, uint x, uint y, float[4] c)
        {
            buf[x + y * _w] = makeRGBA(c[0], c[1], c[2], 255 - c[3]);
        }

        import std.math : exp, sqrt, PI;
        import beamui.core.math : max, min;

        // Gaussian function
        static float weight(in float x, in float sigma)
        {
            enum inv_sqrt_2pi = 1 / sqrt(2 * PI);
            return exp(-x ^^ 2 / (2 * sigma ^^ 2)) * inv_sqrt_2pi / sigma;
        }

        void blurOneDimension(const uint[] bufIn, uint[] bufOut, uint blurSize, bool horizontally)
        {
            float sigma = blurSize > 2 ? blurSize / 3.0 : blurSize / 2.0;

            foreach (x; 0 .. _w)
            {
                foreach (y; 0 .. _h)
                {
                    float[4] c;
                    c[] = 0;

                    float sum = 0;
                    foreach (int i; 1 .. blurSize + 1)
                    {
                        float[4] c1 = get(bufIn, horizontally ? min(x + i, _w - 1) : x,
                                horizontally ? y : min(y + i, _h - 1));
                        float[4] c2 = get(bufIn, horizontally ? max(x - i, 0) : x, horizontally ? y : max(y - i, 0));
                        float w = weight(i, sigma);
                        c[] += (c1[] + c2[]) * w;
                        sum += 2 * w;
                    }
                    c[] += get(bufIn, x, y)[] * (1 - sum);
                    set(bufOut, x, y, c);
                }
            }
        }
        // intermediate buffer for image
        Buf!uint tmpbuf;
        tmpbuf.resize(_buf.length);
        // do horizontal blur
        blurOneDimension(_buf[], tmpbuf.unsafe_slice, blurSize, true);
        // then do vertical blur
        blurOneDimension(tmpbuf[], _buf.unsafe_slice, blurSize, false);
    }
}
