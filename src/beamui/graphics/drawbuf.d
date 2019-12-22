/**
This module contains drawing buffer implementation.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.drawbuf;

public import beamui.core.geometry;
public import beamui.core.types;
import std.math;
import beamui.core.collections : Buf;
import beamui.core.config;
import beamui.core.functions;
import beamui.core.linalg;
import beamui.core.logger;
import beamui.core.math;
import beamui.graphics.colors;
import beamui.text.glyph : GlyphRef, SubpixelRenderingMode;

/// 9-patch image scaling information (unscaled frame and scaled middle parts)
struct NinePatch
{
    /// Frame (non-scalable) part size for left, top, right, bottom edges.
    InsetsI frame;
    /// Padding (distance to content area) for left, top, right, bottom edges.
    InsetsI padding;
}

enum PatternType : uint
{
    solid,
    dotted,
}

/// Positioned glyph
struct GlyphInstance
{
    GlyphRef glyph;
    Point position;
}

static if (USE_OPENGL)
{
    /// Non thread safe
    private __gshared uint drawBufIDGenerator = 0;
}

/// Custom draw delegate for OpenGL direct drawing
alias DrawHandler = void delegate(Rect windowRect, Rect rc);

/// Drawing buffer - image container which allows to perform some drawing operations
class DrawBuf : RefCountedObject
{
    @property
    {
        /// Image buffer bits per pixel value
        abstract int bpp() const;
        /// Image width
        abstract int width() const;
        /// Image height
        abstract int height() const;

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
    }

    private Rect _clipRect;
    private NinePatch* _ninePatch;
    private uint _alpha = 255;

    static if (USE_OPENGL)
    {
        private uint _id;
        /// Unique ID of drawbuf instance, for using with hardware accelerated rendering for caching
        @property uint id() const { return _id; }
    }

    debug static
    {
        private __gshared int _instanceCount;
        int instanceCount() { return _instanceCount; }
    }

    this()
    {
        static if (USE_OPENGL)
        {
            _id = drawBufIDGenerator++;
        }
        debug _instanceCount++;
    }

    ~this()
    {
        debug
        {
            if (APP_IS_SHUTTING_DOWN)
                onResourceDestroyWhileShutdown("drawbuf", getShortClassName(this));
            _instanceCount--;
        }
        clear();
    }

    void function(uint) onDestroyCallback;

    /// Call to remove this image from OpenGL cache when image is updated.
    void invalidate()
    {
        static if (USE_OPENGL)
        {
            if (onDestroyCallback)
            {
                // remove from cache
                onDestroyCallback(_id);
                // assign new ID
                _id = drawBufIDGenerator++;
            }
        }
    }

    /// Resize the image buffer, invalidating its content
    abstract void resize(int width, int height);

    void clear()
    {
        resetClipping();
    }

    /// Current alpha setting (applied to all drawing operations)
    @property uint alpha() const { return _alpha; }
    /// ditto
    @property void alpha(uint alpha)
    {
        _alpha = min(alpha, 0xFF);
    }

    /// Apply additional transparency to current drawbuf alpha value
    void addAlpha(uint alpha)
    {
        _alpha = blendAlpha(_alpha, alpha);
    }

    /// Applies current drawbuf alpha to color
    void applyAlpha(ref Color c)
    {
        c.addAlpha(_alpha);
    }

    /// Detect nine patch using image 1-pixel border. Returns true if 9-patch markup is found in the image
    bool detectNinePatch()
    {
        // override
        return false;
    }

    //===============================================================
    // Clipping rectangle functions

    /// Init clip rectangle to full buffer size
    void resetClipping()
    {
        _clipRect = Rect(0, 0, width, height);
    }

    @property bool hasClipping() const
    {
        return _clipRect.left != 0 || _clipRect.top != 0 || _clipRect.right != width || _clipRect.bottom != height;
    }
    /// Clipping rectangle
    @property ref const(Rect) clipRect() const { return _clipRect; }
    /// ditto
    @property void clipRect(const ref Rect rc)
    {
        _clipRect = rc;
        _clipRect.intersect(Rect(0, 0, width, height));
    }
    /// Set new clipping rectangle, intersect with previous one
    void intersectClipRect(const ref Rect rc)
    {
        _clipRect.intersect(rc);
    }
    /// Returns true if rectangle is completely clipped out and cannot be drawn.
    @property bool isClippedOut(const ref Rect rc) const
    {
        return !_clipRect.intersects(rc);
    }
    /// Apply `clipRect` and buffer bounds clipping to rectangle
    bool applyClipping(ref Rect rc) const
    {
        rc.intersect(_clipRect);
        if (rc.left < 0)
            rc.left = 0;
        if (rc.top < 0)
            rc.top = 0;
        if (rc.right > width)
            rc.right = width;
        if (rc.bottom > height)
            rc.bottom = height;
        return !rc.empty;
    }
    /// Apply `clipRect` and buffer bounds clipping to rectangle
    /// If clipping applied to first rectangle, reduce second rectangle bounds proportionally
    bool applyClipping(ref Rect rc, ref Rect rc2) const
    {
        if (rc.empty || rc2.empty)
            return false;
        if (!rc.intersects(_clipRect))
            return false;
        if (rc.width == rc2.width && rc.height == rc2.height)
        {
            // unscaled
            if (rc.left < _clipRect.left)
            {
                rc2.left += _clipRect.left - rc.left;
                rc.left = _clipRect.left;
            }
            if (rc.top < _clipRect.top)
            {
                rc2.top += _clipRect.top - rc.top;
                rc.top = _clipRect.top;
            }
            if (rc.right > _clipRect.right)
            {
                rc2.right -= rc.right - _clipRect.right;
                rc.right = _clipRect.right;
            }
            if (rc.bottom > _clipRect.bottom)
            {
                rc2.bottom -= rc.bottom - _clipRect.bottom;
                rc.bottom = _clipRect.bottom;
            }
            if (rc.left < 0)
            {
                rc2.left += -rc.left;
                rc.left = 0;
            }
            if (rc.top < 0)
            {
                rc2.top += -rc.top;
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
            if (rc.left < _clipRect.left)
            {
                rc2.left += (_clipRect.left - rc.left) * srcdx / dstdx;
                rc.left = _clipRect.left;
            }
            if (rc.top < _clipRect.top)
            {
                rc2.top += (_clipRect.top - rc.top) * srcdy / dstdy;
                rc.top = _clipRect.top;
            }
            if (rc.right > _clipRect.right)
            {
                rc2.right -= (rc.right - _clipRect.right) * srcdx / dstdx;
                rc.right = _clipRect.right;
            }
            if (rc.bottom > _clipRect.bottom)
            {
                rc2.bottom -= (rc.bottom - _clipRect.bottom) * srcdy / dstdy;
                rc.bottom = _clipRect.bottom;
            }
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
    /// Reserved for hardware-accelerated drawing - begins drawing batch
    void beforeDrawing()
    {
        _alpha = 255;
    }
    /// Reserved for hardware-accelerated drawing - ends drawing batch
    void afterDrawing()
    {
    }

    //========================================================
    // Drawing methods

    /// Fill the whole buffer with solid color (no clipping applied)
    abstract void fill(Color color);
    /// Fill rectangle with solid color (clipping is applied)
    abstract void fillRect(Rect rc, Color color);
    /// Fill rectangle with a gradient (clipping is applied)
    abstract void fillGradientRect(Rect rc, Color color1, Color color2, Color color3, Color color4);

    /// Fill rectangle with solid color and pattern (clipping is applied)
    void fillRectPattern(Rect rc, Color color, PatternType pattern)
    {
        if (color.isFullyTransparent)
            return;
        if (applyClipping(rc))
        {
            final switch (pattern) with (PatternType)
            {
            case solid:
                fillRect(rc, color);
                break;
            case dotted:
                auto img = makeTemporaryImage(2, 2);
                img.fill(Color.transparent);
                foreach (x; 0 .. 2)
                {
                    foreach (y; 0 .. 2)
                    {
                        if ((x ^ y) & 1)
                            img.drawPixel(x, y, color);
                    }
                }
                drawTiledImage(rc, img);
                destroy(img);
                break;
            }
        }
    }
    /// Draw pixel at (x, y) with specified color (clipping is applied)
    abstract void drawPixel(int x, int y, Color color);
    /// Draw 8bit alpha image - usually font glyph using specified color (clipping is applied)
    abstract void drawGlyph(int x, int y, GlyphRef glyph, Color color);
    /// Draw source buffer rectangle contents to destination buffer (clipping is applied)
    abstract void drawFragment(int x, int y, DrawBuf src, Rect srcrect);
    /// Draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    abstract void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect);

    final void drawText(int x, int y, const GlyphInstance[] run, Color color)
    {
        if (run.length == 0 || color.isFullyTransparent)
            return;

        const clipLeft = _clipRect.left;
        foreach (gi; run)
        {
            GlyphRef g = gi.glyph;
            const xx = x + gi.position.x;
            if (xx + g.correctedBlackBoxX >= clipLeft)
            {
                const yy = y + gi.position.y;
                drawGlyph(xx, yy, g, color);
            }
        }
    }

    /// Draw unscaled image at specified coordinates
    void drawImage(int x, int y, DrawBuf src)
    {
        drawFragment(x, y, src, Rect(0, 0, src.width, src.height));
    }
    /// Draw tiles of unscaled image to a buffer rectangle
    /// Experimental API
    void drawTiledImage(Rect dstrect, DrawBuf src, int tilex0 = 0, int tiley0 = 0)
    {
        Rect rc = dstrect;
        int imgdx = src.width;
        int imgdy = src.height;
        int offsetx = ((tilex0 % imgdx) + imgdx) % imgdx;
        int offsety = ((tiley0 % imgdy) + imgdy) % imgdy;
        int xx0 = rc.left;
        int yy0 = rc.top;
        if (offsetx)
            xx0 -= imgdx - offsetx;
        if (offsety)
            yy0 -= imgdy - offsety;
        for (int yy = yy0; yy < rc.bottom; yy += imgdy)
        {
            for (int xx = xx0; xx < rc.right; xx += imgdx)
            {
                Rect dst = Rect(xx, yy, xx + imgdx, yy + imgdy);
                if (dst.intersects(rc))
                {
                    Rect sr = Rect(0, 0, imgdx, imgdy);
                    if (dst.right > rc.right)
                        sr.right -= dst.right - rc.right;
                    if (dst.bottom > rc.bottom)
                        sr.bottom -= dst.bottom - rc.bottom;
                    if (!sr.empty)
                        drawFragment(dst.left, dst.top, src, sr);
                }
            }
        }
    }
    /// Draw an image rescaling with 9-patch
    void drawNinePatch(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        assert(src.hasNinePatch);

        static void correctFrameBounds(ref int n1, ref int n2, ref int n3, ref int n4)
        {
            if (n1 > n2)
            {
                //assert(n2 - n1 == n4 - n3);
                int middledist = (n1 + n2) / 2 - n1;
                n1 = n2 = n1 + middledist;
                n3 = n4 = n3 + middledist;
            }
        }

        auto p = src.ninePatch;
        Rect rc = dstrect;
        uint w = srcrect.width;
        uint h = srcrect.height;
        int x0 = srcrect.left;
        int x1 = srcrect.left + p.frame.left;
        int x2 = srcrect.right - p.frame.right;
        int x3 = srcrect.right;
        int y0 = srcrect.top;
        int y1 = srcrect.top + p.frame.top;
        int y2 = srcrect.bottom - p.frame.bottom;
        int y3 = srcrect.bottom;
        int dstx0 = rc.left;
        int dstx1 = rc.left + p.frame.left;
        int dstx2 = rc.right - p.frame.right;
        int dstx3 = rc.right;
        int dsty0 = rc.top;
        int dsty1 = rc.top + p.frame.top;
        int dsty2 = rc.bottom - p.frame.bottom;
        int dsty3 = rc.bottom;

        correctFrameBounds(x1, x2, dstx1, dstx2);
        correctFrameBounds(y1, y2, dsty1, dsty2);

        //correctFrameBounds(x1, x2);
        //correctFrameBounds(y1, y2);
        //correctFrameBounds(dstx1, dstx2);
        //correctFrameBounds(dsty1, dsty2);
        if (y0 < y1 && dsty0 < dsty1)
        {
            // top row
            if (x0 < x1 && dstx0 < dstx1)
                drawFragment(dstx0, dsty0, src, Rect(x0, y0, x1, y1)); // top left
            if (x1 < x2 && dstx1 < dstx2)
                drawRescaled(Rect(dstx1, dsty0, dstx2, dsty1), src, Rect(x1, y0, x2, y1)); // top center
            if (x2 < x3 && dstx2 < dstx3)
                drawFragment(dstx2, dsty0, src, Rect(x2, y0, x3, y1)); // top right
        }
        if (y1 < y2 && dsty1 < dsty2)
        {
            // middle row
            if (x0 < x1 && dstx0 < dstx1)
                drawRescaled(Rect(dstx0, dsty1, dstx1, dsty2), src, Rect(x0, y1, x1, y2)); // middle center
            if (x1 < x2 && dstx1 < dstx2)
                drawRescaled(Rect(dstx1, dsty1, dstx2, dsty2), src, Rect(x1, y1, x2, y2)); // center
            if (x2 < x3 && dstx2 < dstx3)
                drawRescaled(Rect(dstx2, dsty1, dstx3, dsty2), src, Rect(x2, y1, x3, y2)); // middle center
        }
        if (y2 < y3 && dsty2 < dsty3)
        {
            // bottom row
            if (x0 < x1 && dstx0 < dstx1)
                drawFragment(dstx0, dsty2, src, Rect(x0, y2, x1, y3)); // bottom left
            if (x1 < x2 && dstx1 < dstx2)
                drawRescaled(Rect(dstx1, dsty2, dstx2, dsty3), src, Rect(x1, y2, x2, y3)); // bottom center
            if (x2 < x3 && dstx2 < dstx3)
                drawFragment(dstx2, dsty2, src, Rect(x2, y2, x3, y3)); // bottom right
        }
    }
    /// Draws rectangle frame of specified color, widths (per side), pattern and optinally fills inner area
    void drawFrame(Rect rc, Color frameColor, Insets frameSideWidths, Color innerAreaColor = Color.transparent,
            PatternType pattern = PatternType.solid)
    {
        // draw frame
        if (!frameColor.isFullyTransparent)
        {
            Rect r;
            // left side
            r = rc;
            r.right = r.left + frameSideWidths.left;
            if (!r.empty)
                fillRectPattern(r, frameColor, pattern);
            // right side
            r = rc;
            r.left = r.right - frameSideWidths.right;
            if (!r.empty)
                fillRectPattern(r, frameColor, pattern);
            // top side
            r = rc;
            r.left += frameSideWidths.left;
            r.right -= frameSideWidths.right;
            Rect rc2 = r;
            rc2.bottom = r.top + frameSideWidths.top;
            if (!rc2.empty)
                fillRectPattern(rc2, frameColor, pattern);
            // bottom side
            rc2 = r;
            rc2.top = r.bottom - frameSideWidths.bottom;
            if (!rc2.empty)
                fillRectPattern(rc2, frameColor, pattern);
        }
        // draw internal area
        if (!innerAreaColor.isFullyTransparent)
        {
            rc.left += frameSideWidths.left;
            rc.top += frameSideWidths.top;
            rc.right -= frameSideWidths.right;
            rc.bottom -= frameSideWidths.bottom;
            if (!rc.empty)
                fillRect(rc, innerAreaColor);
        }
    }

    /// Draw focus rectangle; vertical gradient is supported - `color1` is top color, `color2` is bottom color
    void drawFocusRect(Rect rc, Color color1, Color color2 = Color.none)
    {
        // override for faster performance when using OpenGL
        if (rc.empty)
            return;
        if (color2 == Color.none)
            color2 = color1;
        if (color1.isFullyTransparent && color2.isFullyTransparent)
            return;
        // draw horizontal lines
        foreach (int x; rc.left .. rc.right)
        {
            if ((x ^ rc.top) & 1)
                drawPixel(x, rc.top, color1);
            if ((x ^ (rc.bottom - 1)) & 1)
                drawPixel(x, rc.bottom - 1, color2);
        }
        // draw vertical lines
        foreach (int y; rc.top + 1 .. rc.bottom - 1)
        {
            Color c = color1;
            if (color1 != color2)
                c = Color.mix(color1, color2, (y - rc.top) / cast(double)rc.height);
            if ((y ^ rc.left) & 1)
                drawPixel(rc.left, y, c);
            if ((y ^ (rc.right - 1)) & 1)
                drawPixel(rc.right - 1, y, c);
        }
    }

    /// Draw filled triangle in float coordinates; clipping is already applied
    protected void fillTriangleFClipped(Vec2 p1, Vec2 p2, Vec2 p3, Color color)
    {
        // override and implement it
    }

    /// Find intersection of line p1..p2 with clip rectangle
    protected bool intersectClipF(ref Vec2 p1, ref Vec2 p2, ref bool p1moved, ref bool p2moved)
    {
        const cr = RectF.from(_clipRect);
        if (p1.x < cr.left && p2.x < cr.left)
            return true;
        if (p1.x >= cr.right && p2.x >= cr.right)
            return true;
        if (p1.y < cr.top && p2.y < cr.top)
            return true;
        if (p1.y >= cr.bottom && p2.y >= cr.bottom)
            return true;
        // horizontal clip
        if (p1.x < cr.left && p2.x >= cr.left)
        {
            // move p1 to clip left
            p1 += (p2 - p1) * ((cr.left - p1.x) / (p2.x - p1.x));
            p1moved = true;
        }
        if (p2.x < cr.left && p1.x >= cr.left)
        {
            // move p2 to clip left
            p2 += (p1 - p2) * ((cr.left - p2.x) / (p1.x - p2.x));
            p2moved = true;
        }
        if (p1.x > cr.right && p2.x < cr.right)
        {
            // move p1 to clip right
            p1 += (p2 - p1) * ((cr.right - p1.x) / (p2.x - p1.x));
            p1moved = true;
        }
        if (p2.x > cr.right && p1.x < cr.right)
        {
            // move p1 to clip right
            p2 += (p1 - p2) * ((cr.right - p2.x) / (p1.x - p2.x));
            p2moved = true;
        }
        // vertical clip
        if (p1.y < cr.top && p2.y >= cr.top)
        {
            // move p1 to clip left
            p1 += (p2 - p1) * ((cr.top - p1.y) / (p2.y - p1.y));
            p1moved = true;
        }
        if (p2.y < cr.top && p1.y >= cr.top)
        {
            // move p2 to clip left
            p2 += (p1 - p2) * ((cr.top - p2.y) / (p1.y - p2.y));
            p2moved = true;
        }
        if (p1.y > cr.bottom && p2.y < cr.bottom)
        {
            // move p1 to clip right             <0              <0
            p1 += (p2 - p1) * ((cr.bottom - p1.y) / (p2.y - p1.y));
            p1moved = true;
        }
        if (p2.y > cr.bottom && p1.y < cr.bottom)
        {
            // move p1 to clip right
            p2 += (p1 - p2) * ((cr.bottom - p2.y) / (p1.y - p2.y));
            p2moved = true;
        }
        return false;
    }

    /// Draw filled triangle in float coordinates
    void fillTriangleF(Vec2 p1, Vec2 p2, Vec2 p3, Color color)
    {
        if (_clipRect.empty) // clip rectangle is empty - all drawables are clipped out
            return;
        // apply clipping
        const cr = RectF.from(_clipRect);
        if (cr.contains(p1) && cr.contains(p2) && cr.contains(p3))
        {
            // all points inside clipping area - no clipping required
            fillTriangleFClipped(p1, p2, p3, color);
            return;
        }
        // check if all points outside the same bound
        if (p1.x < cr.left && p2.x < cr.left && p3.x < cr.left)
            return;
        if (p1.x >= cr.right && p2.x >= cr.right && p3.x >= cr.bottom)
            return;
        if (p1.y < cr.top && p2.y < cr.top && p3.y < cr.top)
            return;
        if (p1.y >= cr.bottom && p2.y >= cr.bottom && p3.y >= cr.bottom)
            return;

        // do triangle clipping
        /++
         +                   side 1
         +  p1-------p11------------p21--------------p2
         +   \                                       /
         +    \                                     /
         +     \                                   /
         +      \                                 /
         +    p13\                               /p22
         +        \                             /
         +         \                           /
         +          \                         /
         +           \                       /  side 2
         +    side 3  \                     /
         +             \                   /
         +              \                 /
         +               \               /p32
         +             p33\             /
         +                 \           /
         +                  \         /
         +                   \       /
         +                    \     /
         +                     \   /
         +                      \ /
         +                      p3
         +/
        Vec2 p11 = p1;
        Vec2 p13 = p1;
        Vec2 p21 = p2;
        Vec2 p22 = p2;
        Vec2 p32 = p3;
        Vec2 p33 = p3;
        bool p1moved = false;
        bool p2moved = false;
        bool p3moved = false;
        bool side1clipped = intersectClipF(p11, p21, p1moved, p2moved);
        bool side2clipped = intersectClipF(p22, p32, p2moved, p3moved);
        bool side3clipped = intersectClipF(p33, p13, p3moved, p1moved);
        if (!p1moved && !p2moved && !p3moved)
        {
            // no moved - no clipping
            fillTriangleFClipped(p1, p2, p3, color);
        }
        else if (p1moved && !p2moved && !p3moved)
        {
            fillTriangleFClipped(p11, p2, p3, color);
            fillTriangleFClipped(p3, p13, p11, color);
        }
        else if (!p1moved && p2moved && !p3moved)
        {
            fillTriangleFClipped(p22, p3, p1, color);
            fillTriangleFClipped(p1, p21, p22, color);
        }
        else if (!p1moved && !p2moved && p3moved)
        {
            fillTriangleFClipped(p33, p1, p2, color);
            fillTriangleFClipped(p2, p32, p33, color);
        }
        else if (p1moved && p2moved && !p3moved)
        {
            if (!side1clipped)
            {
                fillTriangleFClipped(p13, p11, p21, color);
                fillTriangleFClipped(p21, p22, p13, color);
            }
            fillTriangleFClipped(p22, p3, p13, color);
        }
        else if (!p1moved && p2moved && p3moved)
        {
            if (!side2clipped)
            {
                fillTriangleFClipped(p21, p22, p32, color);
                fillTriangleFClipped(p32, p33, p21, color);
            }
            fillTriangleFClipped(p21, p33, p1, color);
        }
        else if (p1moved && !p2moved && p3moved)
        {
            if (!side3clipped)
            {
                fillTriangleFClipped(p13, p11, p32, color);
                fillTriangleFClipped(p32, p33, p13, color);
            }
            fillTriangleFClipped(p11, p2, p32, color);
        }
        else if (p1moved && p2moved && p3moved)
        {
            if (side1clipped)
            {
                fillTriangleFClipped(p13, p22, p32, color);
                fillTriangleFClipped(p32, p33, p13, color);
            }
            else if (side2clipped)
            {
                fillTriangleFClipped(p11, p21, p33, color);
                fillTriangleFClipped(p33, p13, p11, color);
            }
            else if (side3clipped)
            {
                fillTriangleFClipped(p11, p21, p22, color);
                fillTriangleFClipped(p22, p32, p11, color);
            }
            else
            {
                fillTriangleFClipped(p13, p11, p21, color);
                fillTriangleFClipped(p21, p22, p13, color);
                fillTriangleFClipped(p22, p32, p33, color);
                fillTriangleFClipped(p33, p13, p22, color);
            }
        }
    }

    /// Draw filled quad in float coordinates
    void fillQuadF(Vec2 p1, Vec2 p2, Vec2 p3, Vec2 p4, Color color)
    {
        fillTriangleF(p1, p2, p3, color);
        fillTriangleF(p3, p4, p1, color);
    }

    /// Draw line of arbitrary width in float coordinates
    void drawLineF(Vec2 p1, Vec2 p2, float width, Color color)
    {
        // direction vector
        Vec2 v = (p2 - p1).normalized;
        // calculate normal vector
        // calculate normal vector : rotate CCW 90 degrees
        Vec2 n = v.rotated90ccw();
        // rotate CCW 90 degrees
        n.y = v.x;
        n.x = -v.y;
        // offset by normal * half_width
        n *= width / 2;
        // draw line using quad
        fillQuadF(p1 - n, p2 - n, p2 + n, p1 + n, color);
    }

    protected void calcLineSegmentQuad(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, float width, ref Vec2[4] quad)
    {
        // direction vector
        Vec2 v = (p2 - p1).normalized;
        // calculate normal vector : rotate CCW 90 degrees
        Vec2 n = v.rotated90ccw();
        // offset by normal * half_width
        n *= width / 2;
        // draw line using quad
        Vec2 pp10 = p1 - n;
        Vec2 pp20 = p2 - n;
        Vec2 pp11 = p1 + n;
        Vec2 pp21 = p2 + n;
        if ((p1 - p0).magnitudeSquared > 0.1f)
        {
            // has prev segment
            Vec2 prevv = (p1 - p0).normalized;
            Vec2 prevn = prevv.rotated90ccw();
            Vec2 prev10 = p1 - prevn * width / 2;
            Vec2 prev11 = p1 + prevn * width / 2;
            pp10 = intersectVectors(pp10, -v, prev10, prevv);
            pp11 = intersectVectors(pp11, -v, prev11, prevv);
        }
        if ((p3 - p2).magnitudeSquared > 0.1f)
        {
            // has next segment
            Vec2 nextv = (p3 - p2).normalized;
            Vec2 nextn = nextv.rotated90ccw();
            Vec2 next20 = p2 - nextn * width / 2;
            Vec2 next21 = p2 + nextn * width / 2;
            pp20 = intersectVectors(pp20, v, next20, -nextv);
            pp21 = intersectVectors(pp21, v, next21, -nextv);
        }
        quad[0] = pp10;
        quad[1] = pp20;
        quad[2] = pp21;
        quad[3] = pp11;
    }
    /// Draw line of arbitrary width in float coordinates p1..p2 with angle based on
    /// Previous (p0..p1) and next (p2..p3) segments
    void drawLineSegmentF(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, float width, Color color)
    {
        Vec2[4] quad;
        calcLineSegmentQuad(p0, p1, p2, p3, width, quad);
        fillQuadF(quad[0], quad[1], quad[2], quad[3], color);
    }

    /// Draw poly line of arbitrary width in float coordinates;
    /// When cycled is true, connect first and last point (optionally fill inner area)
    void polyLineF(const Vec2[] points, float width, Color color, bool cycled = false,
            Color innerAreaColor = Color.transparent)
    {
        if (points.length < 2)
            return;
        bool hasInnerArea = !innerAreaColor.isFullyTransparent;
        if (color.isFullyTransparent)
        {
            if (hasInnerArea)
                fillPolyF(points, innerAreaColor);
            return;
        }
        int len = cast(int)points.length;
        if (hasInnerArea)
        {
            Buf!Vec2 innerArea;
            for (int i = 0; i < len; i++)
            {
                Vec2[4] quad;
                int index0 = i - 1;
                int index1 = i;
                int index2 = i + 1;
                int index3 = i + 2;
                if (index0 < 0)
                    index0 = cycled ? len - 1 : 0;
                index2 %= len; // only can be if cycled
                index3 %= len; // only can be if cycled
                if (!cycled)
                {
                    if (index1 == len - 1)
                    {
                        index0 = index1;
                        index2 = 0;
                        index3 = 0;
                    }
                    else if (index1 == len - 2)
                    {
                        index2 = len - 1;
                        index3 = len - 1;
                    }
                }
                calcLineSegmentQuad(points[index0], points[index1], points[index2], points[index3], width, quad);
                innerArea ~= quad[3];
            }
            fillPolyF(innerArea[], innerAreaColor);
        }
        if (!color.isFullyTransparent)
        {
            for (int i = 0; i < len; i++)
            {
                int index0 = i - 1;
                int index1 = i;
                int index2 = i + 1;
                int index3 = i + 2;
                if (index0 < 0)
                    index0 = cycled ? len - 1 : 0;
                index2 %= len; // only can be if cycled
                index3 %= len; // only can be if cycled
                if (!cycled)
                {
                    if (index1 == len - 1)
                    {
                        index0 = index1;
                        index2 = 0;
                        index3 = 0;
                    }
                    else if (index1 == len - 2)
                    {
                        index2 = len - 1;
                        index3 = len - 1;
                    }
                }
                if (cycled || i + 1 < len)
                    drawLineSegmentF(points[index0], points[index1], points[index2], points[index3], width, color);
            }
        }
    }

    /// Draw filled polyline (vertexes must be in clockwise order)
    void fillPolyF(const Vec2[] points, Color color)
    {
        if (points.length < 3)
            return;
        if (points.length == 3)
        {
            fillTriangleF(points[0], points[1], points[2], color);
            return;
        }

        Vec2[] list = points.dup;
        bool moved;
        while (list.length > 3)
        {
            moved = false;
            for (int i = 0; i < list.length; i++)
            {
                Vec2 p1 = list[i + 0];
                Vec2 p2 = list[(i + 1) % list.length];
                Vec2 p3 = list[(i + 2) % list.length];
                float cross = crossProduct(p2 - p1, p3 - p2);
                if (cross > 0)
                {
                    // draw triangle
                    fillTriangleF(p1, p2, p3, color);
                    int indexToRemove = (i + 1) % (cast(int)list.length);
                    // remove triangle from poly
                    for (int j = indexToRemove; j + 1 < list.length; j++)
                        list[j] = list[j + 1];
                    list.length = list.length - 1;
                    i += 2;
                    moved = true;
                }
            }
            if (list.length == 3)
            {
                fillTriangleF(list[0], list[1], list[2], color);
                break;
            }
            if (!moved)
                break;
        }
    }

    /// Draw ellipse or filled ellipse
    void drawEllipseF(float centerX, float centerY, float xRadius, float yRadius, float lineWidth,
            Color lineColor, Color fillColor = Color.transparent)
    {
        if (xRadius < 0)
            xRadius = -xRadius;
        if (yRadius < 0)
            yRadius = -yRadius;
        int numLines = cast(int)((xRadius + yRadius) / 5);
        if (numLines < 4)
            numLines = 4;
        float step = PI * 2 / numLines;
        float angle = 0;
        Buf!Vec2 points;
        foreach (i; 0 .. numLines)
        {
            float x = centerX + cos(angle) * xRadius;
            float y = centerY + sin(angle) * yRadius;
            angle += step;
            points ~= Vec2(x, y);
        }
        polyLineF(points[], lineWidth, lineColor, true, fillColor);
    }

    /// Draw ellipse arc or filled ellipse arc
    void drawEllipseArcF(float centerX, float centerY, float xRadius, float yRadius, float startAngle,
            float endAngle, float lineWidth, Color lineColor, Color fillColor = Color.transparent)
    {
        if (xRadius < 0)
            xRadius = -xRadius;
        if (yRadius < 0)
            yRadius = -yRadius;
        startAngle = startAngle * 2 * PI / 360;
        endAngle = endAngle * 2 * PI / 360;
        if (endAngle < startAngle)
            endAngle += 2 * PI;
        float angleDiff = endAngle - startAngle;
        if (angleDiff > 2 * PI)
            angleDiff %= 2 * PI;
        int numLines = cast(int)((xRadius + yRadius) / angleDiff);
        if (numLines < 3)
            numLines = 4;
        float step = angleDiff / numLines;
        float angle = startAngle;
        Buf!Vec2 points;
        points ~= Vec2(centerX, centerY);
        for (int i = 0; i < numLines; i++)
        {
            float x = centerX + cos(angle) * xRadius;
            float y = centerY + sin(angle) * yRadius;
            angle += step;
            points ~= Vec2(x, y);
        }
        polyLineF(points[], lineWidth, lineColor, true, fillColor);
    }

    /// Draw poly line of width == 1px; when cycled is true, connect first and last point
    void polyLine(const Point[] points, Color color, bool cycled)
    {
        if (points.length < 2)
            return;
        for (int i = 0; i + 1 < points.length; i++)
        {
            drawLine(points[i], points[i + 1], color);
        }
        if (cycled && points.length > 2)
            drawLine(points[$ - 1], points[0], color);
    }

    /// Draw line from point p1 to p2 with specified color
    void drawLine(Point p1, Point p2, Color color)
    {
        if (!clipLine(_clipRect, p1, p2))
            return;

        // from rosettacode.org
        const int dx = p2.x - p1.x;
        const int ix = (dx > 0) - (dx < 0);
        const int dx2 = abs(dx) * 2;
        const int dy = p2.y - p1.y;
        const int iy = (dy > 0) - (dy < 0);
        const int dy2 = abs(dy) * 2;
        drawPixel(p1.x, p1.y, color);
        if (dx2 >= dy2)
        {
            int error = dy2 - dx2 / 2;
            while (p1.x != p2.x)
            {
                if (error >= 0 && (error || ix > 0))
                {
                    error -= dx2;
                    p1.y += iy;
                }
                error += dy2;
                p1.x += ix;
                drawPixel(p1.x, p1.y, color);
            }
        }
        else
        {
            int error = dx2 - dy2 / 2;
            while (p1.y != p2.y)
            {
                if (error >= 0 && (error || iy > 0))
                {
                    error -= dy2;
                    p1.x += ix;
                }
                error += dx2;
                p1.y += iy;
                drawPixel(p1.x, p1.y, color);
            }
        }
    }

    // basically a modified drawEllipseArcF that doesn't draw but gives you the lines instead!
    static Vec2[] makeArcPath(Vec2 center, float radiusX, float radiusY, float startAngle, float endAngle)
    {
        radiusX = fabs(radiusX);
        radiusY = fabs(radiusY);
        startAngle = startAngle * 2 * PI / 360;
        endAngle = endAngle * 2 * PI / 360;
        if (endAngle < startAngle)
            endAngle += 2 * PI;
        float angleDiff = endAngle - startAngle;
        if (angleDiff > 2 * PI)
            angleDiff %= 2 * PI;
        int numLines = cast(int)(sqrt(radiusX * radiusX + radiusY * radiusY) / angleDiff);
        if (numLines < 3)
            numLines = 4;
        float step = angleDiff / numLines;
        float angle = startAngle;
        Vec2[] points;
        points.assumeSafeAppend;
        if (!fzero6(radiusX))
        {
            foreach (i; 0 .. numLines + 1)
            {
                float x = center.x + cos(angle) * radiusX;
                float y = center.y + sin(angle) * radiusY;
                angle += step;
                points ~= Vec2(x, y);
            }
        }
        else
            points ~= Vec2(center.x, center.y);
        return points;
    }

    // calculates inwards XY offsets from rect corners
    static Vec2[4] calcRectRoundedCornerRadius(Vec4 corners, float w, float h, bool keepSquareXY)
    {
        // clamps radius to corner
        static float clampRadius(float r, float len)
        {
            if (len - 2 * r < 0)
                return len / 2;
            return r;
        }

        if (keepSquareXY)
            w = h = min(w, h);

        Vec2[4] cornerRad;
        cornerRad[0] = Vec2(clampRadius(corners.x, w), clampRadius(corners.x, h));
        cornerRad[1] = Vec2(-clampRadius(corners.y, w), clampRadius(corners.y, h));
        cornerRad[2] = Vec2(clampRadius(corners.z, w), -clampRadius(corners.z, h));
        cornerRad[3] = Vec2(-clampRadius(corners.w, w), -clampRadius(corners.w, h));
        return cornerRad;
    }

    /// Builds outer rounded rect path
    /// The last parameter optionally writes out indices of first segment of corners excluding top-left
    static Vec2[] makeRoundedRectPath(Rect rect, Vec4 corners, bool keepSquareXY,
            size_t[] outCornerSegmentsStart = null)
    {
        import std.range : chain;
        import std.array : array;

        Vec2[4] cornerRad = calcRectRoundedCornerRadius(corners, rect.width, rect.height, keepSquareXY);
        Vec2 topLeftC = Vec2(rect.left, rect.top) + cornerRad[0];
        Vec2 topRightC = Vec2(rect.left, rect.top) + cornerRad[1] + Vec2(rect.width, 0);
        Vec2 botLeftC = Vec2(rect.left, rect.top) + cornerRad[2] + Vec2(0, rect.height);
        Vec2 botRightC = Vec2(rect.left, rect.top) + cornerRad[3] + Vec2(rect.width, rect.height);
        auto lt = makeArcPath(topLeftC, cornerRad[0].x, cornerRad[0].y, 180, 270);
        auto rt = makeArcPath(topRightC, cornerRad[1].x, cornerRad[1].y, 270, 0);
        auto lb = makeArcPath(botLeftC, cornerRad[2].x, cornerRad[2].y, 90, 180);
        auto rb = makeArcPath(botRightC, cornerRad[3].x, cornerRad[3].y, 0, 90);
        if (outCornerSegmentsStart.length)
        {
            outCornerSegmentsStart[0] = lt.length;
            outCornerSegmentsStart[1] = lt.length + rt.length;
            outCornerSegmentsStart[2] = lt.length + rt.length + lb.length;
        }
        auto outerPath = chain(lt, rt, rb, lb, lt[0 .. 1]);
        return outerPath.array();
    }

    /// Draws rect with rounded corners
    void drawRoundedRectF(Rect rect, Vec4 corners, bool keepSquareXY, float frameWidth,
                          Color frameColor, Color fillColor = Color.transparent)
    {
        auto fullPath = makeRoundedRectPath(rect, corners, keepSquareXY);
        // fill inner area, doing this manually by sectors to reduce flickering artifacts
        if (!fillColor.isFullyTransparent)
        {
            const center = Vec2(rect.middleX, rect.middleY);
            foreach (i; 1 .. fullPath.length)
            {
                fillTriangleF(center, fullPath[i - 1], fullPath[i], fillColor);
            }
        }
        if (!frameColor.isFullyTransparent && frameWidth > 0)
        {
            foreach (i; 1 .. fullPath.length)
            {
                drawLineF(fullPath[i - 1], fullPath[i], frameWidth, frameColor);
            }
        }
    }

    /// Draw custom OpenGL scene
    void drawCustomOpenGLScene(Rect rc, DrawHandler handler)
    {
        // override it for OpenGL draw buffer
        Log.w("drawCustomOpenGLScene is called for non-OpenGL DrawBuf");
    }
}

alias DrawBufRef = Ref!DrawBuf;

/// RAII setting/restoring of a DrawBuf clip rectangle
struct ClipRectSaver
{
    private DrawBuf _buf;
    private Rect _oldClipRect;
    private uint _oldAlpha;

    /// Intersect new clip rectangle and apply alpha to draw buf
    this(DrawBuf buf, Rect newClipRect, uint newAlpha = 255)
    {
        _buf = buf;
        _oldClipRect = buf.clipRect;
        _oldAlpha = buf.alpha;

        buf.intersectClipRect(newClipRect);
        if (newAlpha < 255)
            buf.addAlpha(newAlpha);
    }
    /// ditto
    this(DrawBuf buf, Box newClipBox, uint newAlpha = 255)
    {
        this(buf, Rect(newClipBox), newAlpha);
    }
    /// Restore previous clip rectangle
    ~this()
    {
        _buf.clipRect = _oldClipRect;
        _buf.alpha = _oldAlpha;
    }
}

class ColorDrawBufBase : DrawBuf
{
    override @property
    {
        int bpp() const { return 32; }
        int width() const { return _w; }
        int height() const { return _h; }
    }

    protected int _w;
    protected int _h;

    /// Returns pointer to ARGB scanline, `null` if `y` is out of range or buffer doesn't provide access to its memory
    inout(uint*) scanLine(int y) inout
    {
        return null;
    }

    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect)
    {
        auto img = cast(ColorDrawBufBase)src;
        if (!img)
            return;
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        if (applyClipping(dstrect, srcrect))
        {
            if (src.applyClipping(srcrect, dstrect))
            {
                const int dx = srcrect.width;
                const int dy = srcrect.height;
                foreach (yy; 0 .. dy)
                {
                    uint* srcrow = img.scanLine(srcrect.top + yy) + srcrect.left;
                    uint* dstrow = scanLine(dstrect.top + yy) + dstrect.left;
                    if (_alpha == 255)
                    {
                        // simplified version - no alpha blending
                        foreach (i; 0 .. dx)
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
                    else
                    {
                        // combine two alphas
                        foreach (i; 0 .. dx)
                        {
                            const uint pixel = srcrow[i];
                            const uint alpha = blendAlpha(_alpha, pixel >> 24);
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

    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        if (_alpha == 0)
            return; // fully transparent - don't draw
        auto img = cast(ColorDrawBufBase)src;
        if (!img)
            return;
        double kx = cast(double)srcrect.width / dstrect.width;
        double ky = cast(double)srcrect.height / dstrect.height;
        if (applyClipping(dstrect, srcrect))
        {
            auto xmapArray = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right, kx);
            auto ymapArray = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom, ky);
            int* xmap = xmapArray.unsafe_ptr;
            int* ymap = ymapArray.unsafe_ptr;

            const int dx = dstrect.width;
            const int dy = dstrect.height;
            foreach (y; 0 .. dy)
            {
                uint* srcrow = img.scanLine(ymap[y]);
                uint* dstrow = scanLine(dstrect.top + y) + dstrect.left;
                if (_alpha == 255)
                {
                    // simplified alpha calculation
                    foreach (x; 0 .. dx)
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
                else
                {
                    // blending two alphas
                    foreach (x; 0 .. dx)
                    {
                        const uint srcpixel = srcrow[xmap[x]];
                        const uint alpha = blendAlpha(_alpha, srcpixel >> 24);
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

    override void drawGlyph(int x, int y, GlyphRef glyph, Color color)
    {
        applyAlpha(color);
        const uint rgb = color.rgb;
        immutable(ubyte[]) src = glyph.glyph;
        const int srcdx = glyph.blackBoxX;
        const int srcdy = glyph.blackBoxY;
        const bool clipping = true; //!_clipRect.empty();
        const bool subpixel = glyph.subpixelMode != SubpixelRenderingMode.none;
        foreach (int yy; 0 .. srcdy)
        {
            const int liney = y + yy;
            if (clipping && (liney < _clipRect.top || liney >= _clipRect.bottom))
                continue;
            if (liney < 0 || liney >= _h)
                continue;

            uint* row = scanLine(liney);
            immutable(ubyte*) srcrow = src.ptr + yy * srcdx;
            foreach (int xx; 0 .. srcdx)
            {
                int colx = x + (subpixel ? xx / 3 : xx);
                if (clipping && (colx < _clipRect.left || colx >= _clipRect.right))
                    continue;
                if (colx < 0 || colx >= _w)
                    continue;

                const uint alpha = blendAlpha(color.a, srcrow[xx]);
                if (subpixel)
                {
                    blendSubpixel(row[colx], rgb, alpha, xx % 3, glyph.subpixelMode);
                }
                else
                {
                    if (alpha == 255)
                    {
                        row[colx] = rgb;
                    }
                    else if (alpha > 0)
                    {
                        // apply blending
                        blendARGB(row[colx], rgb, alpha);
                    }
                }
            }
        }
    }

    void drawGlyphToTexture(int x, int y, GlyphRef glyph)
    {
        immutable(ubyte[]) src = glyph.glyph;
        int srcdx = glyph.blackBoxX;
        int srcdy = glyph.blackBoxY;
        bool subpixel = glyph.subpixelMode != SubpixelRenderingMode.none;
        foreach (int yy; 0 .. srcdy)
        {
            int liney = y + yy;
            uint* row = scanLine(liney);
            immutable(ubyte*) srcrow = src.ptr + yy * srcdx;
            int increment = subpixel ? 3 : 1;
            for (int xx = 0; xx <= srcdx - increment; xx += increment)
            {
                int colx = x + (subpixel ? xx / 3 : xx);
                if (subpixel)
                {
                    uint t1 = srcrow[xx];
                    uint t2 = srcrow[xx + 1];
                    uint t3 = srcrow[xx + 2];
                    //uint pixel = ((t2 ^ 0x00) << 24) | ((t1  ^ 0xFF)<< 16) | ((t2 ^ 0xFF) << 8) | (t3 ^ 0xFF);
                    uint pixel = ((t2 ^ 0x00) << 24) | 0xFFFFFF;
                    row[colx] = pixel;
                }
                else
                {
                    uint alpha1 = srcrow[xx] ^ 0xFF;
                    //uint pixel = (alpha1 << 24) | 0xFFFFFF; //(alpha1 << 16) || (alpha1 << 8) || alpha1;
                    //uint pixel = ((alpha1 ^ 0xFF) << 24) | (alpha1 << 16) | (alpha1 << 8) | alpha1;
                    uint pixel = ((alpha1 ^ 0xFF) << 24) | 0xFFFFFF;
                    row[colx] = pixel;
                }
            }
        }
    }

    override void fillRect(Rect rc, Color color)
    {
        applyAlpha(color);
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

    override void fillGradientRect(Rect rc, Color color1, Color color2, Color color3, Color color4)
    {
        if (applyClipping(rc))
        {
            foreach (y; rc.top .. rc.bottom)
            {
                // interpolate vertically at the side edges
                const double ay = (y - rc.top) / cast(double)(rc.bottom - rc.top);
                const cl = Color.mix(color1, color2, ay);
                const cr = Color.mix(color3, color4, ay);

                uint* row = scanLine(y);
                foreach (x; rc.left .. rc.right)
                {
                    // interpolate horizontally
                    const double ax = (x - rc.left) / cast(double)(rc.right - rc.left);
                    row[x] = Color.mix(cl, cr, ax).rgba;
                }
            }
        }
    }

    override void drawPixel(int x, int y, Color color)
    {
        if (!_clipRect.contains(x, y))
            return;

        applyAlpha(color);
        uint* row = scanLine(y);
        if (color.isOpaque)
        {
            row[x] = color.rgba;
        }
        else if (!color.isFullyTransparent)
        {
            // apply blending
            blendARGB(row[x], color.rgb, color.a);
        }
    }
}

class GrayDrawBuf : DrawBuf
{
    override @property
    {
        int bpp() const { return 8; }
        int width() const { return _w; }
        int height() const { return _h; }
    }

    private int _w;
    private int _h;
    private Buf!ubyte _buf;

    this(int width, int height)
    {
        resize(width, height);
    }

    ubyte* scanLine(int y)
    {
        if (y >= 0 && y < _h)
            return _buf.unsafe_ptr + _w * y;
        return null;
    }

    override void resize(int width, int height)
    {
        if (_w == width && _h == height)
            return;
        _w = width;
        _h = height;
        _buf.resize(_w * _h);
        resetClipping();
    }

    override void fill(Color color)
    {
        if (hasClipping)
            fillRect(Rect(0, 0, _w, _h), color);
        else
            _buf.unsafe_slice[] = color.toGray;
    }

    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect)
    {
        auto img = cast(GrayDrawBuf)src;
        if (!img)
            return;
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        if (applyClipping(dstrect, srcrect))
        {
            if (src.applyClipping(srcrect, dstrect))
            {
                const int dx = srcrect.width;
                const int dy = srcrect.height;
                foreach (yy; 0 .. dy)
                {
                    ubyte* srcrow = img.scanLine(srcrect.top + yy) + srcrect.left;
                    ubyte* dstrow = scanLine(dstrect.top + yy) + dstrect.left;
                    dstrow[0 .. dx] = srcrow[0 .. dx];
                }
            }
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

    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        auto img = cast(GrayDrawBuf)src;
        if (!img)
            return;
        if (applyClipping(dstrect, srcrect))
        {
            auto xmapArray = createMap(dstrect.left, dstrect.right, srcrect.left, srcrect.right);
            auto ymapArray = createMap(dstrect.top, dstrect.bottom, srcrect.top, srcrect.bottom);
            int* xmap = xmapArray.unsafe_ptr;
            int* ymap = ymapArray.unsafe_ptr;

            const int dx = dstrect.width;
            const int dy = dstrect.height;
            foreach (y; 0 .. dy)
            {
                ubyte* srcrow = img.scanLine(ymap[y]);
                ubyte* dstrow = scanLine(dstrect.top + y) + dstrect.left;
                foreach (x; 0 .. dx)
                {
                    ubyte srcpixel = srcrow[xmap[x]];
                    ubyte dstpixel = dstrow[x];
                    dstrow[x] = srcpixel;
                }
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

    override void drawGlyph(int x, int y, GlyphRef glyph, Color color)
    {
        const ubyte c = color.toGray;
        immutable(ubyte[]) src = glyph.glyph;
        const int srcdx = glyph.blackBoxX;
        const int srcdy = glyph.blackBoxY;
        const bool clipping = true; //!_clipRect.empty();
        foreach (int yy; 0 .. srcdy)
        {
            int liney = y + yy;
            if (clipping && (liney < _clipRect.top || liney >= _clipRect.bottom))
                continue;
            if (liney < 0 || liney >= _h)
                continue;
            ubyte* row = scanLine(liney);
            immutable(ubyte*) srcrow = src.ptr + yy * srcdx;
            foreach (int xx; 0 .. srcdx)
            {
                int colx = xx + x;
                if (clipping && (colx < _clipRect.left || colx >= _clipRect.right))
                    continue;
                if (colx < 0 || colx >= _w)
                    continue;

                const uint alpha = blendAlpha(color.a, srcrow[xx]);
                if (alpha == 255)
                {
                    row[colx] = c;
                }
                else if (alpha > 0)
                {
                    // apply blending
                    row[colx] = blendGray(row[colx], c, alpha);
                }
            }
        }
    }

    override void fillRect(Rect rc, Color color)
    {
        applyAlpha(color);
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

    override void fillGradientRect(Rect rc, Color color1, Color color2, Color color3, Color color4)
    {
        if (applyClipping(rc))
        {
            ubyte c1 = color1.toGray;
            ubyte c2 = color2.toGray;
            ubyte c3 = color3.toGray;
            ubyte c4 = color4.toGray;
            foreach (y; rc.top .. rc.bottom)
            {
                // interpolate vertically at the side edges
                uint ay = (255 * (y - rc.top)) / (rc.bottom - rc.top);
                ubyte cl = blendGray(c2, c1, ay);
                ubyte cr = blendGray(c4, c3, ay);

                ubyte* row = scanLine(y);
                foreach (x; rc.left .. rc.right)
                {
                    // interpolate horizontally
                    uint ax = (255 * (x - rc.left)) / (rc.right - rc.left);
                    row[x] = blendGray(cr, cl, ax);
                }
            }
        }
    }

    override void drawPixel(int x, int y, Color color)
    {
        if (!_clipRect.contains(x, y))
            return;

        applyAlpha(color);
        ubyte* row = scanLine(y);
        if (color.isOpaque)
        {
            row[x] = color.toGray;
        }
        else if (!color.isFullyTransparent)
        {
            // apply blending
            row[x] = blendGray(row[x], color.toGray, color.a);
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
        drawRescaled(Rect(0, 0, width, height), src, Rect(0, 0, src.width, src.height));
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

    override void resize(int width, int height)
    {
        if (_w == width && _h == height)
            return;
        _w = width;
        _h = height;
        _buf.resize(_w * _h);
        resetClipping();
    }

    override void fill(Color color)
    {
        if (hasClipping)
            fillRect(Rect(0, 0, _w, _h), color);
        else
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

/// Experimental
DrawBuf makeTemporaryImage(uint width, uint height)
{
    return new ColorDrawBuf(width, height);
}

package bool clipLine(Rect clipRect, ref Point p1, ref Point p2)
{
    float x0 = p1.x;
    float y0 = p1.y;
    float x1 = p2.x;
    float y1 = p2.y;
    bool res = CohenSutherlandLineClipAndDraw(clipRect, x0, y0, x1, y1);
    if (res)
    {
        p1.x = cast(int)x0;
        p1.y = cast(int)y0;
        p2.x = cast(int)x1;
        p2.y = cast(int)y1;
    }
    return res;
}

// Cohen–Sutherland clipping algorithm clips a line from
// P0 = (x0, y0) to P1 = (x1, y1) against a rectangle with
// diagonal from (xmin, ymin) to (xmax, ymax).
// https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm
private bool CohenSutherlandLineClipAndDraw(ref const Rect clipRect, ref float x0, ref float y0, ref float x1, ref float y1)
{
    enum OutCode : ubyte
    {
        inside = 0, // 0000
        left = 1, // 0001
        right = 2, // 0010
        bottom = 4, // 0100
        top = 8, // 1000
    }

    // Compute the bit code for a point (x, y) using the clip rectangle
    // bounded diagonally by (xmin, ymin), and (xmax, ymax)
    static OutCode computeOutCode(ref const Rect clipRect, float x, float y)
    {
        OutCode code; // initialised as being inside of clip window

        if (x < clipRect.left) // to the left of clip window
            code |= OutCode.left;
        else if (x > clipRect.right) // to the right of clip window
            code |= OutCode.right;
        if (y < clipRect.top) // below the clip window
            code |= OutCode.bottom;
        else if (y > clipRect.bottom) // above the clip window
            code |= OutCode.top;

        return code;
    }

    // compute outcodes for P0, P1, and whatever point lies outside the clip rectangle
    OutCode outcode0 = computeOutCode(clipRect, x0, y0);
    OutCode outcode1 = computeOutCode(clipRect, x1, y1);
    bool accept;

    while (true)
    {
        if (!(outcode0 | outcode1))
        { // Bitwise OR is 0. Trivially accept and get out of loop
            accept = true;
            break;
        }
        else if (outcode0 & outcode1)
        { // Bitwise AND is not 0. Trivially reject and get out of loop
            break;
        }
        else
        {
            // failed both tests, so calculate the line segment to clip
            // from an outside point to an intersection with clip edge
            float x, y;

            // At least one endpoint is outside the clip rectangle; pick it.
            const outcodeOut = outcode0 ? outcode0 : outcode1;

            // Now find the intersection point;
            // use formulas y = y0 + slope * (x - x0), x = x0 + (1 / slope) * (y - y0)
            if (outcodeOut & OutCode.top)
            { // point is above the clip rectangle
                x = x0 + (x1 - x0) * (clipRect.bottom - y0) / (y1 - y0);
                y = clipRect.bottom;
            }
            else if (outcodeOut & OutCode.bottom)
            { // point is below the clip rectangle
                x = x0 + (x1 - x0) * (clipRect.top - y0) / (y1 - y0);
                y = clipRect.top;
            }
            else if (outcodeOut & OutCode.right)
            { // point is to the right of clip rectangle
                y = y0 + (y1 - y0) * (clipRect.right - x0) / (x1 - x0);
                x = clipRect.right;
            }
            else if (outcodeOut & OutCode.left)
            { // point is to the left of clip rectangle
                y = y0 + (y1 - y0) * (clipRect.left - x0) / (x1 - x0);
                x = clipRect.left;
            }

            // Now we move outside point to intersection point to clip
            // and get ready for next pass.
            if (outcodeOut == outcode0)
            {
                x0 = x;
                y0 = y;
                outcode0 = computeOutCode(clipRect, x0, y0);
            }
            else
            {
                x1 = x;
                y1 = y;
                outcode1 = computeOutCode(clipRect, x1, y1);
            }
        }
    }
    return accept;
}
