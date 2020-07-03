/**
Software painter implementation.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.swpainter;

private nothrow:

import std.algorithm.mutation : swap;
import std.math : ceil, floor, round;
import std.typecons : scoped;
import pixman;
import beamui.core.collections : Buf;
import beamui.core.functions : eliminate;
import beamui.core.geometry : BoxI, PointI, Rect, RectI, SizeI;
import beamui.core.linalg : Mat2x3, Vec2, dotProduct;
import beamui.core.math;
import beamui.core.types : Tup, tup;
import beamui.graphics.bitmap : Bitmap;
import beamui.graphics.brush;
import beamui.graphics.colors : Color;
import beamui.graphics.compositing;
import beamui.graphics.flattener;
import beamui.graphics.painter;
import beamui.graphics.polygons;
import beamui.graphics.pen;
import beamui.graphics.swrast;
import beamui.text.glyph : GlyphRef, SubpixelRenderingMode;

public final class SWPaintEngine : PaintEngine
{
    private
    {
        struct Layer
        {
            PM_ImageView img;
            BoxI box; /// Layer-relative
            LayerOp op;
        }

        const(State)* _st;

        LayerPool layerPool;
        MaskPool maskPool;

        Bitmap* backbuf;
        PM_Image base_layer;
        PM_ImageView layer; // points either to base_layer or to some layer img in the stack
        Buf!Layer layerStack;

        Buf!Vec2 bufVerts;
        Buf!uint bufContours;
        Buf!HorizEdge bufTraps;

        typeof(scoped!(PlotterSolid!false)()) plotter_solid_op;
        typeof(scoped!(PlotterSolid!true)()) plotter_solid_tr;
        typeof(scoped!(PlotterLinear!false)()) plotter_linear_op;
        typeof(scoped!(PlotterLinear!true)()) plotter_linear_tr;
        typeof(scoped!(PlotterRadial!false)()) plotter_radial_op;
        typeof(scoped!(PlotterRadial!true)()) plotter_radial_tr;
        typeof(scoped!PlotterMask()) plotter_mask;
    }

    this(ref Bitmap backbuffer)
    in (backbuffer)
    {
        backbuf = &backbuffer;
        plotter_solid_op = scoped!(PlotterSolid!false)();
        plotter_solid_tr = scoped!(PlotterSolid!true)();
        plotter_linear_op = scoped!(PlotterLinear!false)();
        plotter_linear_tr = scoped!(PlotterLinear!true)();
        plotter_radial_op = scoped!(PlotterRadial!false)();
        plotter_radial_tr = scoped!(PlotterRadial!true)();
        plotter_mask = scoped!PlotterMask();
    }

    ~this()
    {
        foreach (layer; layerStack.unsafe_slice)
            pixman_image_unref(layer.img);
    }

protected:

    const(State)* st() nothrow
    {
        return _st;
    }

    void begin(const(State)* st, int w, int h, Color bg)
    {
        _st = st;

        backbuf.resize(w, h);
        backbuf.fill(bg);
        base_layer = PM_Image.fromBitmap(*backbuf, Repeat.no, Filtering.no);
        layer = base_layer.view;
    }

    void end()
    {
        foreach (layer; layerStack.unsafe_slice)
            pixman_image_unref(layer.img);
        layerStack.clear();
    }

    void paint()
    {
    }

    void beginLayer(BoxI clip, bool expand, LayerOp op)
    {
        layer = layerPool.take(clip.size);
        layerStack ~= Layer(layer, clip, op);
    }

    void composeLayer()
    {
        Layer src = layerStack.unsafe_ref(-1);
        layerStack.shrink(1);
        PM_ImageView dst_img = layerStack.length > 0 ? layerStack.unsafe_ref(-1).img : base_layer.view;
        scope (exit)
        {
            pixman_image_unref(src.img);
            layer = dst_img;
        }

        PM_Image mask_img = PM_Image.fromOpacity(src.op.opacity);
        if (!mask_img)
            return;

        const bool w3c = src.op.blending != BlendMode.normal;
        const operator = w3c ? pm_op(src.op.blending) : pm_op(src.op.composition);
        // dfmt off
        pixman_image_composite32(
            operator,
            src.img, mask_img, dst_img,
            0, 0,
            0, 0,
            src.box.x, src.box.y,
            src.box.w, src.box.h,
        );
        // dfmt on
    }

    void clipOut(uint index, Rect r)
    {
    }

    void clipOut(uint index, ref Contours contours, FillRule rule, bool complement)
    {
    }

    void restore(uint index)
    {
    }

    void paintOut(ref const Brush br)
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

    void fillPath(ref Contours contours, ref const Brush br, FillRule rule)
    {
        const lst = contours.list;
        BoxI clip = contours.trBounds;
        Mat2x3 mat = st.mat;

        paintUsingBrush(br, clip, mat, (Plotter plotter) {
            const fillRule = rule == FillRule.nonzero ? RastFillRule.nonzero : RastFillRule.odd;
            auto rparams = RastParams(st.aa, clip, fillRule);
            bufVerts.clear();
            if (lst.length == 1)
            {
                if (lst[0].points.length >= 3)
                {
                    transform(lst[0].points, bufVerts, mat);
                    bufTraps.clear();
                    if (splitIntoTrapezoids(bufVerts[], bufTraps))
                    {
                        rasterizeTrapezoidChain(bufTraps[], rparams, plotter);
                    }
                    else
                    {
                        const uint[1] lengths = bufVerts.length;
                        rasterizePolygons(bufVerts[], lengths[], rparams, plotter);
                    }
                }
            }
            else
            {
                bufContours.clear();
                foreach (ref cr; lst)
                {
                    if (cr.points.length >= 3)
                    {
                        transform(cr.points, bufVerts, mat);
                        bufContours ~= cast(uint)cr.points.length;
                    }
                }
                if (bufContours.length)
                    rasterizePolygons(bufVerts[], bufContours[], rparams, plotter);
            }
        });
    }

    void strokePath(ref Contours contours, ref const Brush br, ref const Pen pen, bool hairline)
    {
        if (hairline)
            strokeHairlinePath(contours.list, br);
        else
            strokeThickPath(contours, br, pen);
    }

    private void strokeThickPath(ref Contours contours, ref const Brush br, ref const Pen pen)
    {
        BoxI clip = contours.trBounds;
        Mat2x3 mat = st.mat;

        paintUsingBrush(br, clip, mat, (Plotter plotter) {
            bufVerts.clear();
            bufContours.clear();
            {
                auto iter = scoped!ContourIter(contours);
                auto builder = scoped!PolyBuilder(bufVerts, bufContours);
                expandStrokes(iter, pen, builder);
            }
            if (bufVerts.length)
            {
                transformInPlace(bufVerts.unsafe_slice, mat);
                auto rparams = RastParams(st.aa, clip);
                rasterizePolygons(bufVerts[], bufContours[], rparams, plotter);
            }
        });
    }

    private void strokeHairlinePath(const Contour[] lst, ref const Brush br)
    {
        BoxI clip = st.clipRect;
        Mat2x3 mat = st.mat;
        mat.translate(Vec2(-0.5f, -0.5f));

        paintUsingBrush(br, clip, mat, (Plotter plotter) {
            auto rparams = RastParams(st.aa, clip);
            foreach (ref cr; lst)
            {
                const Vec2[] points = cr.points;
                bufVerts.clear();
                transform(points, bufVerts, mat);

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
            if (br.isOpaque)
            {
                PlotterSolid!false p = plotter_solid_op;
                p.initialize(layer, c);
                callback(p);
            }
            else
            {
                PlotterSolid!true p = plotter_solid_tr;
                p.initialize(layer, c.withAlpha(cast(ubyte)(c.a * br.opacity)));
                callback(p);
            }
        }
        else if (br.type == BrushType.linear)
        {
            if (br.isOpaque)
            {
                PlotterLinear!false p = plotter_linear_op;
                p.initialize(layer, br.linear, mat);
                callback(p);
            }
            else
            {
                PlotterLinear!true p = plotter_linear_tr;
                p.initialize(layer, br.linear, mat);
                callback(p);
            }
        }
        else if (br.type == BrushType.radial)
        {
            if (br.isOpaque)
            {
                PlotterRadial!false p = plotter_radial_op;
                p.initialize(layer, br.radial, mat);
                callback(p);
            }
            else
            {
                PlotterRadial!true p = plotter_radial_tr;
                p.initialize(layer, br.radial, mat);
                callback(p);
            }
        }
        else if (br.type == BrushType.pattern)
        {
            PM_Image src_img = PM_Image.fromBitmap(*br.pattern.image, Repeat.yes, Filtering.yes);
            if (!src_img)
                return;

            PM_Image mask_img = maskPool.take(clip.size, Filtering.no);
            if (!mask_img)
                return;

            const r = clip;
            clip.x = 0;
            clip.y = 0;
            mat.translate(Vec2(-r.x, -r.y));
            const Mat2x3 pmat = (mat * br.pattern.transform).inverted;
            src_img.setTransform(pmat);

            PlotterMask p = plotter_mask;
            p.initialize(mask_img, br.opacity);
            callback(p);
            // dfmt off
            pixman_image_composite32(
                pixman_op_t.over,
                src_img, mask_img, layer,
                0, 0,
                0, 0,
                r.x, r.y,
                r.w, r.h,
            );
            // dfmt on
        }
    }

    void drawLine(Vec2 p, Vec2 q, Color c)
    {
        p = st.mat * p;
        q = st.mat * q;

        auto rparams = RastParams(st.aa, BoxI(st.clipRect));
        auto plotter = choosePlotterForSolidColor(c);
        rasterizeLine(p, q, rparams, plotter);
    }

    void fillRect(Rect r, Color c)
    {
        fillRectImpl(r, choosePlotterForSolidColor(c));
    }

    private void fillRectImpl(Rect r, lazy Plotter plotter)
    {
        // dfmt off
        Vec2[4] vs = [
            Vec2(r.left, r.top),
            Vec2(r.right, r.top),
            Vec2(r.right, r.bottom),
            Vec2(r.left, r.bottom),
        ];
        // dfmt on
        transformInPlace(vs[], st.mat);
        const BoxI clip = clipByRect(computeBoundingBox(vs[]));
        if (clip.empty)
            return;

        // axis-aligned -> one trapezoid
        if (fequal2(vs[0].x, vs[3].x) && fequal2(vs[0].y, vs[1].y))
        {
            if (vs[0].x > vs[1].x)
                swap(vs[0].x, vs[1].x);
            if (vs[0].y > vs[2].y)
                swap(vs[0].y, vs[2].y);

            const HorizEdge[2] t = [HorizEdge(vs[0].x, vs[1].x, vs[0].y), HorizEdge(vs[0].x, vs[1].x, vs[2].y)];
            auto rparams = RastParams(st.aa, clip);
            rasterizeTrapezoidChain(t[], rparams, plotter);
        }
        else
        {
            const uint[1] lengths = 4;
            auto rparams = RastParams(st.aa, clip);
            rasterizePolygons(vs[], lengths[], rparams, plotter);
        }
    }

    void fillTriangle(Vec2[3] ps, Color c)
    {
        transformInPlace(ps[], st.mat);
        const BoxI clip = clipByRect(computeBoundingBox(ps[]));
        if (clip.empty)
            return;

        const uint[1] lengths = 3;
        auto rparams = RastParams(st.aa, clip);
        auto plotter = choosePlotterForSolidColor(c);
        rasterizePolygons(ps[], lengths[], rparams, plotter);
    }

    void fillCircle(float cx, float cy, float r, Color c)
    {
        const BoxI clip = clipByRect(transformBounds(Rect(cx - r, cy - r, cx + r, cy + r)));
        if (clip.empty)
            return;

        const rx = r * 4.0f / 3.0f;
        const top = Vec2(cx, cy - r);
        const bot = Vec2(cx, cy + r);

        bufVerts.clear();
        flattenCubicBezier(bufVerts, top, Vec2(cx + rx, top.y), Vec2(cx + rx, bot.y), bot, true);
        flattenCubicBezier(bufVerts, bot, Vec2(cx - rx, bot.y), Vec2(cx - rx, top.y), top, false);
        transformInPlace(bufVerts.unsafe_slice, st.mat);

        bufTraps.clear();
        const added = splitIntoTrapezoids(bufVerts[], bufTraps);
        if (!added)
            return;

        auto rparams = RastParams(st.aa, clip);
        auto plotter = choosePlotterForSolidColor(c);
        rasterizeTrapezoidChain(bufTraps[], rparams, plotter);
    }

    void drawImage(ref const Bitmap bmp, Vec2 pos, float opacity)
    {
        const rect = Rect(pos.x, pos.y, pos.x + bmp.width, pos.y + bmp.height);
        const BoxI clip = clipByRect(transformBounds(rect));
        if (clip.empty)
            return;

        PM_Image mask_img = PM_Image.fromOpacity(opacity);
        if (!mask_img)
            return;

        PM_Image src_img = PM_Image.fromBitmap(bmp, Repeat.no, Filtering.yes);
        if (!src_img)
            return;

        Mat2x3 mat = st.mat;
        mat.translate(pos).invert().translate(Vec2(clip.x, clip.y));
        src_img.setTransform(mat);
        // dfmt off
        pixman_image_composite32(
            pixman_op_t.over,
            src_img, mask_img, layer,
            0, 0,
            0, 0,
            clip.x, clip.y,
            clip.w, clip.h,
        );
        // dfmt on
    }

    void drawNinePatch(ref const Bitmap bmp, ref const NinePatchInfo info, float opacity)
    {
        const rect = Rect(info.dst_x0, info.dst_y0, info.dst_x3, info.dst_y3);
        const BoxI clip = clipByRect(transformBounds(rect));
        if (clip.empty)
            return;

        PM_Image mask_img = PM_Image.fromOpacity(opacity);
        if (!mask_img)
            return;

        // for proper filtering, we blit the image to a temporary layer first,
        // then compose it using the matrix
        const tmpsz = SizeI(cast(int)ceil(rect.width), cast(int)ceil(rect.height));
        PM_Image tmp_img = PM_Image(layerPool.take(tmpsz));
        if (!tmp_img)
            return;
        pixman_image_set_filter(tmp_img, pixman_filter_t.good, null, 0);

        PM_Image src_img = PM_Image.fromBitmap(bmp, Repeat.no, Filtering.no);
        if (!src_img)
            return;

        drawNinePatchImpl(src_img, tmp_img, info);

        Mat2x3 mat = st.mat;
        mat.translate(rect.topLeft).invert().translate(Vec2(clip.x, clip.y));
        tmp_img.setTransform(mat);
        // dfmt off
        pixman_image_composite32(
            pixman_op_t.over,
            tmp_img, mask_img, layer,
            0, 0,
            0, 0,
            clip.x, clip.y,
            clip.w, clip.h,
        );
        // dfmt on
    }

    private void drawNinePatchImpl(PM_ImageView src, PM_ImageView dest, ref const NinePatchInfo info)
    {
        with (info)
        {
            // shift to the origin and round
            const int dst_x1i = cast(int)round(dst_x1 - dst_x0);
            const int dst_x2i = cast(int)round(dst_x2 - dst_x0);
            const int dst_x3i = cast(int)round(dst_x3 - dst_x0);
            const int dst_y1i = cast(int)round(dst_y1 - dst_y0);
            const int dst_y2i = cast(int)round(dst_y2 - dst_y0);
            const int dst_y3i = cast(int)round(dst_y3 - dst_y0);
            // top row
            if (y0 < y1 && 0 < dst_y1i)
            {
                // top left
                if (x0 < x1 && 0 < dst_x1i)
                    drawPatch(src, dest, RectI(x0, y0, x1, y1), RectI(0, 0, 0, 0));
                // top center
                if (x1 < x2 && dst_x1i < dst_x2i)
                    drawPatch(src, dest, RectI(x1, y0, x2, y1), RectI(dst_x1i, 0, dst_x2i, dst_y1i));
                // top right
                if (x2 < x3 && dst_x2i < dst_x3i)
                    drawPatch(src, dest, RectI(x2, y0, x3, y1), RectI(dst_x2i, 0, 0, 0));
            }
            // middle row
            if (y1 < y2 && dst_y1i < dst_y2i)
            {
                // middle left
                if (x0 < x1 && 0 < dst_x1i)
                    drawPatch(src, dest, RectI(x0, y1, x1, y2), RectI(0, dst_y1i, dst_x1i, dst_y2i));
                // center
                if (x1 < x2 && dst_x1i < dst_x2i)
                    drawPatch(src, dest, RectI(x1, y1, x2, y2), RectI(dst_x1i, dst_y1i, dst_x2i, dst_y2i));
                // middle right
                if (x2 < x3 && dst_x2i < dst_x3i)
                    drawPatch(src, dest, RectI(x2, y1, x3, y2), RectI(dst_x2i, dst_y1i, dst_x3i, dst_y2i));
            }
            // bottom row
            if (y2 < y3 && dst_y2i < dst_y3i)
            {
                // bottom left
                if (x0 < x1 && 0 < dst_x1i)
                    drawPatch(src, dest, RectI(x0, y2, x1, y3), RectI(0, dst_y2i, 0, 0));
                // bottom center
                if (x1 < x2 && dst_x1i < dst_x2i)
                    drawPatch(src, dest, RectI(x1, y2, x2, y3), RectI(dst_x1i, dst_y2i, dst_x2i, dst_y3i));
                // bottom right
                if (x2 < x3 && dst_x2i < dst_x3i)
                    drawPatch(src, dest, RectI(x2, y2, x3, y3), RectI(dst_x2i, dst_y2i, 0, 0));
            }
        }
    }

    private void drawPatch(PM_ImageView src_img, PM_ImageView dest_img, RectI srcRect, RectI dstRect)
    {
        const from = BoxI(srcRect);
        BoxI to = BoxI(dstRect);

        Mat2x3 mat = Mat2x3.translation(Vec2(from.x, from.y));
        if (to.empty)
            to.size = from.size;
        else
            mat.scale(Vec2(from.w / cast(float)to.w, from.h / cast(float)to.h));
        src_img.setTransform(mat);
        // dfmt off
        pixman_image_composite32(
            pixman_op_t.src,
            src_img, null, dest_img,
            0, 0,
            0, 0,
            to.x, to.y,
            to.w, to.h,
        );
        // dfmt on
    }

    void drawText(const GlyphInstance[] run, Color c)
    {
        if (run[0].glyph.subpixelMode != SubpixelRenderingMode.none)
            return;

        PM_Image src_img = PM_Image.fromSolidColor(c);
        if (!src_img)
            return;

        BoxI untrBounds;
        BoxI clip;
        {
            const Rect r = computeTextRunBounds(run);
            const x = floor(r.left);
            const y = floor(r.top);
            untrBounds.x = cast(int)x;
            untrBounds.y = cast(int)y;
            untrBounds.w = cast(int)ceil(r.right - x);
            untrBounds.h = cast(int)ceil(r.bottom - y);
            clip = clipByRect(transformBounds(r));
        }
        if (clip.empty)
            return;

        PM_Image mask_img = maskPool.take(untrBounds.size, Filtering.yes);
        if (!mask_img)
            return;

        blitGlyphs(run, mask_img.getData!ubyte(), mask_img.getStride(), untrBounds.x, untrBounds.y);

        Mat2x3 mat = st.mat;
        mat.translate(Vec2(untrBounds.x, untrBounds.y)).invert();
        mask_img.setTransform(mat);
        // dfmt off
        pixman_image_composite32(
            pixman_op_t.over,
            src_img, mask_img, layer,
            0, 0,
            clip.x, clip.y,
            clip.x, clip.y,
            clip.w, clip.h,
        );
        // dfmt on
    }

    private Plotter choosePlotterForSolidColor(Color c)
    {
        if (c.isOpaque)
        {
            PlotterSolid!false p = plotter_solid_op;
            p.initialize(layer, c);
            return p;
        }
        else
        {
            PlotterSolid!true p = plotter_solid_tr;
            p.initialize(layer, c);
            return p;
        }
    }
}

Rect computeTextRunBounds(const GlyphInstance[] run)
{
    Rect r = MIN_RECT_F;
    foreach (ref gi; run)
    {
        r.left = min(r.left, gi.position.x);
        r.top = min(r.top, gi.position.y);
        r.right = max(r.right, gi.position.x + gi.glyph.correctedBlackBoxX);
        r.bottom = max(r.bottom, gi.position.y + gi.glyph.blackBoxY);
    }
    return r;
}

void blitGlyphs(const GlyphInstance[] run, ubyte* mask, uint stride, int x_left, int y_top)
{
    foreach (gi; run)
    {
        const int xx = cast(int)gi.position.x - x_left;
        const int yy = cast(int)gi.position.y - y_top;
        const ubyte[] data = gi.glyph.glyph;
        const uint width = gi.glyph.correctedBlackBoxX;
        ubyte* maskBlock = mask + yy * stride + xx;
        foreach (row; 0 .. gi.glyph.blackBoxY)
        {
            maskBlock[row * stride .. row * stride + width] = data[row * width .. row * width + width];
        }
    }
}

void transform(const Vec2[] vs, ref Buf!Vec2 output, ref const Mat2x3 m)
{
    output.reserve(output.length + cast(uint)vs.length);
    foreach (ref v; vs)
        output ~= m * v;
}

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

final class PlotterMask : Plotter
{
    ubyte* image;
    uint stride;
    ubyte fill;

    void initialize(ref PM_ImageView mask, float opacity)
    {
        image = mask.getData!ubyte();
        stride = mask.getStride();
        fill = cast(ubyte)(opacity * 255);
    }

    void setPixel(int x, int y)
    {
        ubyte* pixel = image + y * stride + x;
        *pixel = fill;
    }

    void mixPixel(int x, int y, float cov)
    {
        ubyte* pixel = image + y * stride + x;
        const uint val = *pixel + cast(uint)(fill * cov);
        *pixel = val < fill ? cast(ubyte)val : fill;
    }

    void setScanLine(int x0, int x1, int y)
    {
        ubyte* pixel = image + y * stride;
        pixel[x0 .. x1] = fill;
    }

    void mixScanLine(int x0, int x1, int y, float cov)
    {
        const a = cast(uint)(fill * cov);
        ubyte* pixel = image + y * stride + x0;
        foreach (_; x0 .. x1)
        {
            const uint val = *pixel + a;
            *pixel = val < fill ? cast(ubyte)val : fill;
            pixel++;
        }
    }
}

final class PlotterSolid(bool translucent) : Plotter
{
    uint* image;
    uint stride;
    Color color;
    uint rgb;

    void initialize(ref PM_ImageView surface, Color c)
    {
        image = surface.getData!uint();
        stride = surface.getStride();
        color = c;
        rgb = c.rgb;
    }

    void setPixel(int x, int y)
    {
        uint* pixel = image + y * stride + x;
        static if (translucent)
            *pixel = blendARGB(*pixel, color);
        else
            *pixel = rgb;
    }

    void mixPixel(int x, int y, float cov)
    {
        Color c = color;
        static if (translucent)
            c.a = cast(ubyte)(c.a * cov);
        else
            c.a = cast(ubyte)(0xFF * cov);
        uint* pixel = image + y * stride + x;
        *pixel = blendARGB(*pixel, c);
    }

    void setScanLine(int x0, int x1, int y)
    {
        static if (translucent)
        {
            uint* pixel = image + y * stride + x0;
            foreach (_; x0 .. x1)
            {
                *pixel = blendARGB(*pixel, color);
                pixel++;
            }
        }
        else
        {
            uint* pixel = image + y * stride;
            pixel[x0 .. x1] = rgb;
        }
    }

    void mixScanLine(int x0, int x1, int y, float cov)
    {
        Color c = color;
        static if (translucent)
            c.a = cast(ubyte)(c.a * cov);
        else
            c.a = cast(ubyte)(0xFF * cov);
        uint* pixel = image + y * stride + x0;
        foreach (_; x0 .. x1)
        {
            *pixel = blendARGB(*pixel, c);
            pixel++;
        }
    }
}

enum eps = 0.01f;
enum eps2 = 0.001f;

final class PlotterLinear(bool translucent) : Plotter
{
    uint* image;
    uint stride;
    Vec2 start;
    Vec2 axis;
    float revAxisLen2 = 0;
    Color first;
    Color last;
    Buf!float stops;
    Buf!Color colors;

    void initialize(ref PM_ImageView surface, ref const LinearGradient grad, ref const Mat2x3 mat)
    in (grad.stops.length >= 2)
    in (grad.colors.length >= 2)
    {
        image = surface.getData!uint();
        stride = surface.getStride();
        start = mat * grad.start;
        axis = mat * grad.end - start;
        revAxisLen2 = 1 / axis.magnitudeSquared;
        first = grad.colors[0];
        last = grad.colors[$ - 1];
        stops.clear();
        colors.clear();
        stops ~= grad.stops;
        colors ~= grad.colors;
    }

nothrow:

    float calcFraction(int x, int y)
    {
        return dotProduct(Vec2(x, y) - start, axis) * revAxisLen2;
    }

    Color getColor(float fraction)
    {
        if (fraction < eps2)
            return first;
        if (fraction > 1 - eps2)
            return last;

        foreach (i; 1 .. stops.length)
        {
            const b = stops[i];
            if (fraction < b)
            {
                const a = stops[i - 1];
                const f = b > a ? (fraction - a) / (b - a) : 0;
                return gradMix(colors[i - 1], colors[i], f);
            }
        }
        assert(0);
    }

    void setPixel(int x, int y)
    {
        const c = getColor(calcFraction(x, y));
        uint* pixel = image + y * stride + x;
        static if (translucent)
            *pixel = blendARGB(*pixel, c);
        else
            *pixel = c.rgba;
    }

    void mixPixel(int x, int y, float cov)
    {
        Color c = getColor(calcFraction(x, y));
        static if (translucent)
            c.a = cast(ubyte)(c.a * cov);
        else
            c.a = cast(ubyte)(0xFF * cov);
        uint* pixel = image + y * stride + x;
        *pixel = blendARGB(*pixel, c);
    }

    void setScanLine(int x0, int x1, int y)
    {
        uint* pixel = image + y * stride + x0;
        // use the difference between consecutive positions
        const fdiff = axis.x * revAxisLen2;
        float fraction = calcFraction(x0, y);
        foreach (x; x0 .. x1)
        {
            const c = getColor(fraction);
            static if (translucent)
                *pixel = blendARGB(*pixel, c);
            else
                *pixel = c.rgba;
            fraction += fdiff;
            pixel++;
        }
    }

    void mixScanLine(int x0, int x1, int y, float cov)
    {
        uint* pixel = image + y * stride + x0;
        const fdiff = axis.x * revAxisLen2;
        float fraction = calcFraction(x0, y);
        foreach (x; x0 .. x1)
        {
            Color c = getColor(fraction);
            static if (translucent)
                c.a = cast(ubyte)(c.a * cov);
            else
                c.a = cast(ubyte)(0xFF * cov);
            *pixel = blendARGB(*pixel, c);
            fraction += fdiff;
            pixel++;
        }
    }
}

final class PlotterRadial(bool translucent) : Plotter
{
    uint* image;
    uint stride;
    Vec2 center;
    float invRadius2 = 0;
    Color first;
    Color last;
    Buf!float stops2;
    Buf!Color colors;

    void initialize(ref PM_ImageView surface, ref const RadialGradient grad, ref const Mat2x3 mat)
    in (grad.stops.length >= 2)
    in (grad.colors.length >= 2)
    in (grad.radius > 0)
    {
        image = surface.getData!uint();
        stride = surface.getStride();
        center = mat * grad.center;
        invRadius2 = 1 / (grad.radius * grad.radius);
        first = grad.colors[0];
        last = grad.colors[$ - 1];
        stops2.clear();
        colors.clear();
        foreach (s; grad.stops)
            stops2 ~= s * s;
        colors ~= grad.colors;
    }

nothrow:

    float calcFraction(int x, int y)
    {
        return (Vec2(x, y) - center).magnitudeSquared * invRadius2;
    }

    Color getColor(float fraction)
    {
        if (fraction < eps2)
            return first;
        if (fraction > 1 - eps2)
            return last;

        foreach (i; 1 .. stops2.length)
        {
            const b = stops2[i];
            if (fraction < b)
            {
                const a = stops2[i - 1];
                const f = b > a ? (fraction - a) / (b - a) : 0;
                return gradMix(colors[i - 1], colors[i], f);
            }
        }
        assert(0);
    }

    void setPixel(int x, int y)
    {
        const c = getColor(calcFraction(x, y));
        uint* pixel = image + y * stride + x;
        static if (translucent)
            *pixel = blendARGB(*pixel, c);
        else
            *pixel = c.rgba;
    }

    void mixPixel(int x, int y, float cov)
    {
        Color c = getColor(calcFraction(x, y));
        static if (translucent)
            c.a = cast(ubyte)(c.a * cov);
        else
            c.a = cast(ubyte)(0xFF * cov);
        uint* pixel = image + y * stride + x;
        *pixel = blendARGB(*pixel, c);
    }

    void setScanLine(int x0, int x1, int y)
    {
        uint* pixel = image + y * stride + x0;
        // use the difference between consecutive positions
        float fdiff = (2 * (x0 - center.x) + 1) * invRadius2;
        const fdiff2 = 2 * invRadius2;
        float fraction = calcFraction(x0, y);
        foreach (x; x0 .. x1)
        {
            const c = getColor(fraction);
            static if (translucent)
                *pixel = blendARGB(*pixel, c);
            else
                *pixel = c.rgba;
            fraction += fdiff;
            fdiff += fdiff2;
            pixel++;
        }
    }

    void mixScanLine(int x0, int x1, int y, float cov)
    {
        uint* pixel = image + y * stride + x0;
        float fdiff = (2 * (x0 - center.x) + 1) * invRadius2;
        const fdiff2 = 2 * invRadius2;
        float fraction = calcFraction(x0, y);
        foreach (x; x0 .. x1)
        {
            Color c = getColor(fraction);
            static if (translucent)
                c.a = cast(ubyte)(c.a * cov);
            else
                c.a = cast(ubyte)(0xFF * cov);
            *pixel = blendARGB(*pixel, c);
            fraction += fdiff;
            fdiff += fdiff2;
            pixel++;
        }
    }
}

uint blendARGB(uint dst, Color src)
{
    const uint dstr = (dst >> 16) & 0xFF;
    const uint dstg = (dst >> 8) & 0xFF;
    const uint dstb = (dst >> 0) & 0xFF;
    const uint dsta = (dst >> 24) & 0xFF;
    const uint alpha = src.a;
    const uint invAlpha = 0xFF - alpha;
    const uint r = ((src.r * alpha + dstr * invAlpha) >> 8) & 0xFF;
    const uint g = ((src.g * alpha + dstg * invAlpha) >> 8) & 0xFF;
    const uint b = ((src.b * alpha + dstb * invAlpha) >> 8) & 0xFF;
    const uint a = ((alpha * 0xFF + dsta * invAlpha) >> 8) & 0xFF;
    return (a << 24) | (r << 16) | (g << 8) | b;
}

Color gradMix(Color c1, Color c2, float t)
{
    const uint alpha = cast(uint)(t * 0xFF);
    const uint invAlpha = 0xFF - alpha;
    const uint r = (c1.r * invAlpha + c2.r * alpha) >> 8;
    const uint g = (c1.g * invAlpha + c2.g * alpha) >> 8;
    const uint b = (c1.b * invAlpha + c2.b * alpha) >> 8;
    const uint a = (c1.a * invAlpha + c2.a * alpha) >> 8;
    return Color(r, g, b, a);
}

pixman_fixed_t pm_f(float f)
{
    return cast(pixman_fixed_t)(f * 65_536);
}

pixman_point_fixed_t pm_pt(Vec2 v)
{
    return pixman_point_fixed_t(pm_f(v.x), pm_f(v.y));
}

pixman_color_t pm_c(Color c)
{
    // premultiply here
    const ushort a = c.a * 256;
    const ushort r = cast(ushort)(c.r * c.a);
    const ushort g = cast(ushort)(c.g * c.a);
    const ushort b = cast(ushort)(c.b * c.a);
    return pixman_color_t(r, g, b, a);
}

pixman_color_t pm_gray(float opacity)
in (0 <= opacity && opacity <= 1)
{
    const v = cast(ushort)(opacity * ushort.max);
    return pixman_color_t(v, v, v, v);
}

pixman_transform_t pm_mat(ref const Mat2x3 mat)
{
    pixman_transform_t tr = void;
    tr.matrix[0] = [pm_f(mat.store[0][0]), pm_f(mat.store[0][1]), pm_f(mat.store[0][2])];
    tr.matrix[1] = [pm_f(mat.store[1][0]), pm_f(mat.store[1][1]), pm_f(mat.store[1][2])];
    tr.matrix[2] = [pm_f(0), pm_f(0), pm_f(1)];
    return tr;
}

pixman_op_t pm_op(CompositeMode mode)
{
    // dfmt off
    final switch (mode) with (CompositeMode)
    {
        case copy:       return pixman_op_t.src;
        case sourceOver: return pixman_op_t.over;
        case sourceIn:   return pixman_op_t.in_;
        case sourceOut:  return pixman_op_t.out_;
        case sourceAtop: return pixman_op_t.atop;
        case destOver:   return pixman_op_t.over_reverse;
        case destIn:     return pixman_op_t.in_reverse;
        case destOut:    return pixman_op_t.out_reverse;
        case destAtop:   return pixman_op_t.atop_reverse;
        case xor:        return pixman_op_t.xor;
        case lighter:    return pixman_op_t.add;
    }
    // dfmt on
}

pixman_op_t pm_op(BlendMode mode)
{
    // dfmt off
    final switch (mode) with (BlendMode)
    {
        case normal:     return pixman_op_t.over;
        case multiply:   return pixman_op_t.multiply;
        case screen:     return pixman_op_t.screen;
        case overlay:    return pixman_op_t.overlay;
        case darken:     return pixman_op_t.darken;
        case lighten:    return pixman_op_t.lighten;
        case colorDodge: return pixman_op_t.color_dodge;
        case colorBurn:  return pixman_op_t.color_burn;
        case hardLight:  return pixman_op_t.hard_light;
        case softLight:  return pixman_op_t.soft_light;
        case difference: return pixman_op_t.difference;
        case exclusion:  return pixman_op_t.exclusion;
        case hue:        return pixman_op_t.hsl_hue;
        case saturation: return pixman_op_t.hsl_saturation;
        case color:      return pixman_op_t.hsl_color;
        case luminosity: return pixman_op_t.hsl_luminosity;
    }
    // dfmt on
}

// dfmt off
enum Repeat : bool { no, yes }
enum Filtering : bool { no, yes }
// dfmt on

struct PM_Image
{
    PM_ImageView view;
    alias view this;

    @disable this(this);

    ~this()
    {
        if (view.handle)
        {
            pixman_image_unref(view.handle);
            view.handle = null;
        }
    }

    static PM_Image fromOpacity(float opacity)
    {
        const pxc = pm_gray(opacity);
        return PM_Image(PM_ImageView(pixman_image_create_solid_fill(&pxc)));
    }

    static PM_Image fromSolidColor(Color c)
    {
        const pxc = pm_c(c);
        return PM_Image(PM_ImageView(pixman_image_create_solid_fill(&pxc)));
    }

    static PM_Image fromBitmap(ref const Bitmap bmp, Repeat repeat, Filtering filter)
    in (bmp)
    {
        // dfmt off
        auto ret = pixman_image_create_bits(
            pixman_format_code_t.a8r8g8b8,
            bmp.width,
            bmp.height,
            cast(uint*)bmp.pixels!uint,
            cast(int)bmp.rowBytes,
        );
        // dfmt on
        if (repeat)
            pixman_image_set_repeat(ret, pixman_repeat_t.normal);
        if (filter)
            pixman_image_set_filter(ret, pixman_filter_t.good, null, 0);
        return PM_Image(PM_ImageView(ret));
    }
}

struct PM_ImageView
{
    pixman_image_t* handle;
    alias handle this;

    T* getData(T)()
    in (handle)
    out (ptr; ptr)
    {
        return cast(T*)pixman_image_get_data(handle);
    }

    uint getStride()
    in (handle)
    {
        const bytes = pixman_image_get_depth(handle) / 8;
        assert(bytes > 0);
        return pixman_image_get_stride(handle) / bytes;
    }

    void setTransform(ref const Mat2x3 mat)
    in (handle)
    {
        const tr = pm_mat(mat);
        pixman_image_set_transform(handle, &tr);
    }
}

struct LayerPool
{
    PM_ImageView take(SizeI size)
    in (size.w > 0)
    in (size.h > 0)
    {
        auto img = pixman_image_create_bits(pixman_format_code_t.a8r8g8b8, size.w, size.h, null, 0);
        return PM_ImageView(img);
    }
}

struct MaskPool
{
    PM_Image take(SizeI size, Filtering filter)
    in (size.w > 0)
    in (size.h > 0)
    {
        auto img = pixman_image_create_bits(pixman_format_code_t.a8, size.w, size.h, null, 0);
        if (filter)
            pixman_image_set_filter(img, pixman_filter_t.good, null, 0);
        return PM_Image(PM_ImageView(img));
    }
}
