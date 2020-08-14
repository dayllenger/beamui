/**
Painter implementation for console interfaces.

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.txtpainter;

import beamui.core.config;

// dfmt off
static if (BACKEND_CONSOLE):
// dfmt on
import std.typecons : scoped;

import beamui.core.collections : Buf;
import beamui.core.geometry;
import beamui.core.linalg;
import beamui.core.logger;
import beamui.core.math;
import beamui.graphics.bitmap;
import beamui.graphics.brush;
import beamui.graphics.colors : Color;
import beamui.graphics.flattener;
import beamui.graphics.painter;
import beamui.graphics.path : SubPath;
import beamui.graphics.pen;
import beamui.graphics.polygons;
import beamui.graphics.swrast;

final class ConsolePaintEngine : PaintEngine
{
    private
    {
        Bitmap* backbuf;

        FlatteningContourIter strokeIter;

        Buf!Vec2 bufVerts;
        Buf!uint bufContours;

        typeof(scoped!PlotterSolid()) plotter_solid;
    }

    this(ref Bitmap backbuffer)
    in (backbuffer)
    in (backbuffer.format == PixelFormat.cbf32)
    {
        backbuf = &backbuffer;
        strokeIter = new FlatteningContourIter;
        plotter_solid = scoped!PlotterSolid();
    }

protected:

    override void begin(FrameConfig conf)
    {
        backbuf.resize(conf.ddpSize.w, conf.ddpSize.h);
        backbuf.fill(conf.background);
    }

    override void end()
    {
    }

    override void beginLayer(LayerInfo)
    {
    }

    override void composeLayer(RectI)
    {
    }

    override void clipOut(uint, const SubPath[], FillRule, bool complement)
    {
    }

    override void restore(uint)
    {
    }

    override void paintOut(ref const Brush br)
    {
        Mat2x3 mat = st.mat;
        BoxI clip = st.clipRect;
        assert(!clip.empty);

        paintUsingBrush(br, clip, mat, (Plotter plotter) {
            const HorizEdge[2] t = [
                HorizEdge(clip.x, clip.x + clip.w, clip.y), HorizEdge(clip.x, clip.x + clip.w, clip.y + clip.h)
            ];
            auto rparams = RastParams(false, clip);
            rasterizeTrapezoidChain(t[], rparams, plotter);
        });
    }

    override void fillPath(const SubPath[] list, ref const Brush br, FillRule rule)
    {
        BoxI clip = geometryBBox.screen;
        Mat2x3 mat = st.mat;

        paintUsingBrush(br, clip, mat, (Plotter plotter) {
            bufVerts.clear();
            bufContours.clear();
            foreach (ref sp; list)
            {
                if (sp.points.length >= 3)
                    bufContours ~= sp.flatten!true(bufVerts, mat);
            }
            if (bufContours.length)
            {
                const fillRule = rule == FillRule.nonzero ? RastFillRule.nonzero : RastFillRule.odd;
                auto rparams = RastParams(false, clip, fillRule);
                rasterizePolygons(bufVerts[], bufContours[], rparams, plotter);
            }
        });
    }

    override void strokePath(const SubPath[] list, ref const Brush br, ref const Pen pen, bool hairline)
    {
        if (hairline)
            strokeHairlinePath(list, br);
        else
            strokeThickPath(list, br, pen);
    }

    private void strokeThickPath(const SubPath[] list, ref const Brush br, ref const Pen pen)
    {
        BoxI clip = geometryBBox.screen;
        Mat2x3 mat = st.mat;

        paintUsingBrush(br, clip, mat, (Plotter plotter) {
            bufVerts.clear();
            bufContours.clear();
            {
                // in non-scaling mode, transform contours before expanding
                strokeIter.recharge(list, mat, !pen.shouldScale);
                auto builder = scoped!PolyBuilder(bufVerts, bufContours);
                const minDist = pen.shouldScale ? getMinDistFromMatrix(mat) : 0.7f;
                expandStrokes(strokeIter, pen, builder, minDist);
            }
            if (bufVerts.length)
            {
                if (pen.shouldScale)
                    transformInPlace(bufVerts.unsafe_slice, mat);
                auto rparams = RastParams(false, clip);
                rasterizePolygons(bufVerts[], bufContours[], rparams, plotter);
            }
        });
    }

    private void strokeHairlinePath(const SubPath[] list, ref const Brush br)
    {
        BoxI clip = st.clipRect;
        Mat2x3 mat = st.mat;
        mat.translate(Vec2(-0.5f, -0.5f));

        paintUsingBrush(br, clip, mat, (Plotter plotter) {
            auto rparams = RastParams(false, clip);
            foreach (ref sp; list)
            {
                bufVerts.clear();
                sp.flatten!true(bufVerts, mat);

                foreach (i; 1 .. bufVerts.length)
                {
                    Vec2 p = bufVerts[i - 1];
                    Vec2 q = bufVerts[i];
                    rasterizeLine(p, q, rparams, plotter);
                }
            }
        });
    }

    private void paintUsingBrush(ref const Brush br, ref BoxI clip, ref Mat2x3 mat, scope void delegate(Plotter) callback)
    {
        if (br.type == BrushType.solid)
        {
            const Color c = br.solid;
            PlotterSolid p = plotter_solid;
            p.initialize(*backbuf, c.withAlpha(cast(ubyte)(c.a * br.opacity)));
            callback(p);
        }
    }

    override void drawImage(ref const Bitmap bmp, Vec2 pos, float)
    {
        if (bmp.format != PixelFormat.cbf32)
            return;

        const offset = st.mat * Vec2(0);
        const x = cast(int)(offset.x + pos.x);
        const y = cast(int)(offset.y + pos.y);
        const w = bmp.width;
        const h = bmp.height;
        backbuf.blit(bmp, RectI(0, 0, w, h), RectI(x, y, x + w, y + h));
    }

    override void drawNinePatch(ref const Bitmap bmp, ref const NinePatchInfo info, float)
    {
    }

    override void drawText(const GlyphInstance[] run, Color c)
    {
        const offset = st.mat * Vec2(0);
        const xrgb8 = c.rgba;
        auto view = backbuf.mutate!Pixel;
        foreach (g; run)
        {
            const x = cast(int)(offset.x + g.position.x);
            const y = cast(int)(offset.y + g.position.y);
            if (x < 0 || backbuf.width <= x)
                continue;
            if (y < 0 || backbuf.height <= y)
                continue;

            Pixel* px = &view.scanline(y)[x];
            px.c = g.glyph.id;
            px.f = xrgb8;
        }
    }
}

private nothrow:

void transformInPlace(Vec2[] vs, ref const Mat2x3 m)
{
    foreach (ref v; vs)
        v = m * v;
}

final class PolyBuilder : StrokeBuilder
{
nothrow:
    private
    {
        Buf!Vec2* points;
        Buf!Vec2 otherSide;
        Buf!uint* contours;

        uint pstart;
    }

    this(ref Buf!Vec2 points, ref Buf!uint contours)
    {
        this.points = &points;
        this.contours = &contours;
    }

    void beginContour()
    {
        pstart = points.length;
    }

    void add(Vec2 left, Vec2 right)
    {
        if (pstart == points.length || (*points)[$ - 1] != left)
            points.put(left);
        otherSide.put(right);
    }

    Buf!Vec2* beginFanLeft(Vec2)
    {
        return points;
    }

    Buf!Vec2* beginFanRight(Vec2)
    {
        return &otherSide;
    }

    void endFan()
    {
    }

    void breakStrip()
    {
    }

    void endContour()
    {
        points.reserve(points.length + otherSide.length);
        foreach_reverse (p; otherSide[])
            points.put(p);
        contours.put(points.length - pstart);
        otherSide.clear();
        pstart = 0;
    }
}

struct Pixel
{
    dchar c;
    uint b, f;
}

final class PlotterSolid : Plotter
{
    PixelRef!Pixel image;
    Color color;

    void initialize(ref Bitmap surface, Color c)
    {
        image = surface.mutate!Pixel();
        color = c;
    }

    void setPixel(int x, int y)
    {
        Pixel* pixel = image.scanline(y) + x;
        pixel.b = blendRGB(pixel.b, color);
    }

    void mixPixel(int x, int y, float cov)
    {
        Color c = color;
        c.a = cast(ubyte)(c.a * cov);
        Pixel* pixel = image.scanline(y) + x;
        pixel.b = blendRGB(pixel.b, c);
    }

    void setScanLine(int x0, int x1, int y)
    {
        Pixel* pixel = image.scanline(y) + x0;
        foreach (_; x0 .. x1)
        {
            pixel.b = blendRGB(pixel.b, color);
            pixel++;
        }
    }

    void mixScanLine(int x0, int x1, int y, float cov)
    {
        Color c = color;
        c.a = cast(ubyte)(c.a * cov);
        Pixel* pixel = image.scanline(y) + x0;
        foreach (_; x0 .. x1)
        {
            pixel.b = blendRGB(pixel.b, c);
            pixel++;
        }
    }
}

uint blendRGB(uint dst, Color src)
{
    const uint dstr = (dst >> 16) & 0xFF;
    const uint dstg = (dst >> 8) & 0xFF;
    const uint dstb = (dst >> 0) & 0xFF;
    const uint alpha = src.a;
    const uint invAlpha = 0xFF - src.a;
    const uint r = ((src.r * alpha + dstr * invAlpha) >> 8) & 0xFF;
    const uint g = ((src.g * alpha + dstg * invAlpha) >> 8) & 0xFF;
    const uint b = ((src.b * alpha + dstb * invAlpha) >> 8) & 0xFF;
    return (r << 16) | (g << 8) | b;
}
