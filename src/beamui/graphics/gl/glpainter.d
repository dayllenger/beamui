/**
OpenGL (ES) 3.0 painter implementation.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.glpainter;

import beamui.core.config;

static if (USE_OPENGL):
import std.algorithm.mutation : reverse;
import std.typecons : scoped;
import beamui.core.collections : Buf;
import beamui.core.geometry : BoxI, RectF, RectI, SizeI;
import beamui.core.linalg : Vec2, Mat2x3;
import beamui.core.logger : Log;
import beamui.core.math;
import beamui.graphics.brush;
import beamui.graphics.colors : Color, ColorF;
import beamui.graphics.compositing : getBlendFactors;
import beamui.graphics.drawbuf : ColorDrawBufBase, GlyphInstance;
import beamui.graphics.flattener : flattenCubicBezier;
import beamui.graphics.painter : PaintEngine;
import beamui.graphics.pen;
import beamui.graphics.polygons;
import beamui.graphics.gl.renderer;
import beamui.graphics.gl.shaders;
import beamui.graphics.gl.textures;

private nothrow:

/*
Notes:
- this module doesn't call GL at all
- all matrices and boxes are local to the containing layer, if not stated otherwise
- all source and destination pixels are premultiplied, if not stated otherwise
*/

/// Contains objects shared between GL painters and their drawing layers
public final class GLSharedData
{
    private
    {
        StdShaders sh;

        ColorStopAtlas colorStopAtlas;
        TextureCache textureCache;
        GlyphCache glyphCache;
    }

    this()
    {
        colorStopAtlas.initialize();
    }

    ~this()
    {
        debug ensureNotInGC(this);
    }
}

struct Cover
{
    RectF rect; /// Local to batch
    RectI clip;
    uint dataIndex;
}

struct DepthTask
{
    int index;
    uint dataIndex;
}

public final class GLPaintEngine : PaintEngine
{
    private
    {
        const(State)* _st;

        Layer* layer; // points into array, so need to handle carefully
        Buf!Layer layers;
        Buf!Set sets;
        Buf!Batch batches;

        Buf!DataChunk dataStore;
        Buf!Tri triangles;

        Buf!Vec2 positions;
        Buf!ushort dataIndices;
        Buf!Vec2 positions_textured;
        Buf!ushort dataIndices_textured;
        Buf!Vec2 uvs_textured;

        Buf!Cover covers;
        Buf!DepthTask depthTasks;
        Buf!Vec2 layerOffsets;

        ColorStopAtlas* colorStopAtlas;
        TextureCache* textureCache;
        GlyphCache* glyphCache;

        GpaaAppender gpaa;

        Renderer renderer;
    }

    this(GLSharedData data)
        in(data)
    {
        renderer.initialize(&data.sh);
        colorStopAtlas = &data.colorStopAtlas;
        textureCache = &data.textureCache;
        glyphCache = &data.glyphCache;
    }

    ~this()
    {
        debug ensureNotInGC(this);
    }

protected:

    const(State)* st() const { return _st; }

    void begin(const(State)* st, int w, int h, Color bg)
    {
        _st = st;

        layers.clear();
        sets.clear();
        batches.clear();

        dataStore.clear();
        triangles.clear();

        positions.clear();
        dataIndices.clear();
        positions_textured.clear();
        dataIndices_textured.clear();
        uvs_textured.clear();

        covers.clear();
        depthTasks.clear();

        Layer lr;
        lr.clip = lr.bounds = RectI(0, 0, w, h);
        lr.fill = ColorF(bg);
        layers ~= lr;
        layer = &layers.unsafe_ref(0);
        sets ~= Set.init;

        colorStopAtlas.reset();
        gpaa.prepare();
    }

    void end()
    {
        prepareSets();
        prepareLayers();
        constructCoverGeometry();
        sortBatches();

        if (batches.length)
        {
            debug (painter)
            {
                Log.fd("GL: %s bt, %s dat, %s tri, %s v",
                    batches.length,
                    dataStore.length,
                    triangles.length,
                    positions.length + positions_textured.length,
                );
            }
            renderer.upload(const(DataToUpload)(
                triangles[],
                positions[],
                dataIndices[],
                positions_textured[],
                dataIndices_textured[],
                uvs_textured[],
                dataStore[],
            ), const(GpaaDataToUpload)(
                gpaa.indices[],
                gpaa.positions[],
                gpaa.dataIndices[],
                gpaa.layerIndices[],
                getGlobalLayerPositions(),
            ));
        }
    }

    void paint()
    {
        renderer.render(const(DrawLists)(layers[], sets[], batches[]));
    }

    private void prepareSets()
    {
        Set[] list = sets.unsafe_slice;
        foreach (i; 1 .. list.length)
        {
            list[i - 1].batches.end = list[i].batches.start;
            list[i - 1].dataChunks.end = list[i].dataChunks.start;
        }
        list[$ - 1].batches.end = batches.length;
        list[$ - 1].dataChunks.end = dataStore.length;
    }

    private void prepareLayers()
        in(layers.length)
    {
        if (layers.length == 1)
            return;

        // compute optimal layer boundaries on screen, starting from leafs
        foreach_reverse (ref Layer lr; layers.unsafe_slice[1 .. $])
        {
            foreach (i, ref set; sets[][lr.sets.start .. lr.sets.end])
            {
                if (set.layer == lr.index)
                {
                    foreach (ref bt; batches[][set.batches.start .. set.batches.end])
                        lr.bounds.include(bt.common.clip);
                }
            }
            RectI clip = lr.clip;
            clip.translate(-clip.left, -clip.top);
            if (lr.bounds.intersect(clip))
            {
                // parent layer should have at least that size
                Layer* parent = &layers.unsafe_ref(lr.parent);
                RectI r = lr.bounds;
                r.translate(lr.clip.left, lr.clip.top);
                parent.bounds.include(r);
            }
        }
        // reset for the main layer
        {
            Layer* main = &layers.unsafe_ref(0);
            main.bounds = RectI(0, 0, main.clip.width, main.clip.height);
        }
        // do other job, iterating in straight order
        foreach (ref Layer lr; layers.unsafe_slice[1 .. $])
        {
            if (lr.empty)
                continue;

            // shift batches to the layer origin
            const shift = Vec2(-lr.bounds.left, -lr.bounds.top);
            foreach (i, ref set; sets[][lr.sets.start .. lr.sets.end])
            {
                if (set.layer == lr.index)
                {
                    const Span data = set.dataChunks;
                    foreach (ref DataChunk ch; dataStore.unsafe_slice[data.start .. data.end])
                    {
                        ch.transform = Mat2x3.translation(shift) * ch.transform;
                        ch.clipRect.translate(shift.x, shift.y);
                    }
                }
            }
            // adjust final layer coordinates
            const RectI parentBounds = layers[lr.parent].bounds;
            const layerShift = Vec2(
                lr.clip.left + lr.bounds.left - parentBounds.left,
                lr.clip.top + lr.bounds.top - parentBounds.top,
            );
            dataStore.unsafe_ref(lr.cmd.dataIndex).transform = Mat2x3.translation(layerShift);
        }
        // at this point, all sub-layers of empty layers are empty too
        foreach (ref Set set; sets.unsafe_slice)
        {
            if (layers[set.layerToCompose].empty)
                set.layerToCompose = 0;
        }
    }

    private void constructCoverGeometry()
    {
        foreach (ref bt; batches.unsafe_slice)
        {
            if (bt.type == BatchType.twopass)
            {
                const t = triangles.length;
                const Span covs = bt.twopass.covers;
                foreach (ref cov; covers[][covs.start .. covs.end])
                {
                    const Vec2[4] vs = [
                        Vec2(cov.rect.left, cov.rect.top),
                        Vec2(cov.rect.left, cov.rect.bottom),
                        Vec2(cov.rect.right, cov.rect.top),
                        Vec2(cov.rect.right, cov.rect.bottom),
                    ];
                    const v = positions.length;
                    positions ~= vs[];
                    addStrip(triangles, v, 4);
                    dataIndices.resize(dataIndices.length + 4, cast(ushort)cov.dataIndex);
                }
                bt.twopass.coverTriangles = Span(t, triangles.length);
            }
        }
        foreach (ref set; sets[])
        {
            if (set.layerToCompose > 0)
            {
                Layer* lr = &layers.unsafe_ref(set.layerToCompose);

                const SizeI sz = lr.bounds.size;
                const Vec2[4] vs = [
                    Vec2(0, 0),
                    Vec2(0, sz.h),
                    Vec2(sz.w, 0),
                    Vec2(sz.w, sz.h),
                ];
                const v = positions.length;
                const t = triangles.length;
                positions ~= vs[];
                addStrip(triangles, v, 4);
                dataIndices.resize(dataIndices.length + 4, lr.cmd.dataIndex);
                lr.cmd.triangles = Span(t, triangles.length);
            }
        }
    }

    private void sortBatches()
    {
        // sort geometry front-to-back inside an opaque batch
        foreach (ref bt; batches[])
        {
            if (bt.common.opaque)
            {
                const Span tris = bt.common.triangles;
                reverse(triangles.unsafe_slice[tris.start .. tris.end]);
            }
        }
    }

    private const(Vec2[]) getGlobalLayerPositions()
    {
        if (layers.length == 1)
            return null;

        layerOffsets.resize(layers.length);
        Vec2[] list = layerOffsets.unsafe_slice;

        foreach (i; 1 .. layers.length)
        {
            const Layer* lr = &layers[i];
            list[i] = list[lr.parent] + Vec2(lr.clip.left, lr.clip.top);
        }
        foreach (i; 1 .. layers.length)
        {
            const Layer* lr = &layers[i];
            list[i].x += lr.bounds.left;
            list[i].y += lr.bounds.top;
        }
        return list;
    }

    void beginLayer(BoxI clip, bool expand, LayerOp op)
    {
        Layer lr;
        lr.index = layers.length;
        lr.parent = layer.index;
        lr.sets.start = sets.length;
        lr.clip = RectI(clip);
        if (expand)
            lr.bounds = RectI(0, 0, clip.w, clip.h);
        lr.depth = layer.depth;
        lr.cmd.opacity = op.opacity;
        lr.cmd.composition = getBlendFactors(op.composition);
        lr.cmd.blending = op.blending;
        layers ~= lr;
        layer = &layers.unsafe_ref(lr.index);
        sets ~= Set(Span(batches.length), Span(dataStore.length), lr.index);

        gpaa.setLayerIndex(lr.index);
    }

    void composeLayer()
    {
        layer.sets.end = sets.length;
        layer.cmd.dataIndex = cast(ushort)dataStore.length;
        // setup the parent layer back
        sets ~= Set(Span(batches.length), Span(dataStore.length), layer.parent, layer.index);
        layer = &layers.unsafe_ref(layer.parent);
        // create an empty data chunk with the parent layer current depth
        const Mat2x3 mat;
        dataStore ~= prepareDataChunk(&mat);
        advanceDepth();

        gpaa.setLayerIndex(layer.index);
    }

    void clipOut(uint index, RectF r)
    {
        const set = Set(Span(batches.length), Span(dataStore.length), layer.index);
        const task = DepthTask(index, dataStore.length);
        if (fillRectImpl(r, null))
        {
            sets ~= set;
            sets ~= Set(Span(batches.length), Span(dataStore.length), layer.index);
            depthTasks ~= task;
        }
    }

    void clipOut(uint index, ref Contours contours, FillRule rule, bool complement)
    {
        const set = Set(Span(batches.length), Span(dataStore.length), layer.index);
        const task = DepthTask(index, dataStore.length);
        const stenciling = rule == FillRule.nonzero ?
            (complement ? Stenciling.zero : Stenciling.nonzero) :
            (complement ? Stenciling.even : Stenciling.odd);
        if (fillPathImpl(contours, null, stenciling))
        {
            sets ~= set;
            sets ~= Set(Span(batches.length), Span(dataStore.length), layer.index);
            depthTasks ~= task;
        }
    }

    void restore(uint index)
    {
        const int i = index;
        foreach (ref DepthTask task; depthTasks.unsafe_slice)
        {
            if (task.index >= i)
            {
                task.index = -1; // done
                setDepth(task.dataIndex);
            }
        }
    }

    private void setDepth(uint dataIndex)
    {
        dataStore.unsafe_ref(dataIndex).depth = layer.depth;
    }

    void paintOut(ref const Brush br)
    {
        const r = layer.clip;
        const Vec2[4] vs = [
            Vec2(r.left, r.top),
            Vec2(r.left, r.bottom),
            Vec2(r.right, r.top),
            Vec2(r.right, r.bottom),
        ];
        const v = positions.length;
        const t = triangles.length;
        positions ~= vs[];
        addStrip(triangles, v, 4);

        if (simple(t, r, &br))
        {
            dataStore.unsafe_ref(-1).transform = Mat2x3.identity;
        }
    }

    void fillPath(ref Contours contours, ref const Brush br, FillRule rule)
    {
        fillPathImpl(contours, &br, rule == FillRule.nonzero ? Stenciling.nonzero : Stenciling.odd);
    }

    void strokePath(ref Contours contours, ref const Brush br, ref const Pen pen, bool)
    {
        auto iter = scoped!ContourIter(contours);
        auto builder_obj = scoped!TriBuilder(positions, triangles);
        TriBuilder builder = builder_obj;

        const t = triangles.length;
        if (st.aa)
            builder.contour = gpaa.contour;

        expandStrokes(iter, pen, builder);
        if (st.aa)
            gpaa.finish(dataStore.length);
        if (triangles.length > t)
        {
            const trivial = contours.list.length == 1 && contours.list[0].points.length < 3;
            if (br.isOpaque || trivial)
            {
                simple(t, contours.trBounds, &br);
            }
            else
            {
                // we must do two-pass rendering to avoid overlaps
                // on bends and self-intersections
                twoPass(t, Stenciling.justCover, contours.bounds, contours.trBounds, &br);
            }
        }
    }

    void drawLine(Vec2 p, Vec2 q, Color c)
    {
        BoxI clip;
        {
            const tp = st.mat * p;
            const tq = st.mat * q;
            const bbox = RectF(
                min(tp.x, tq.x) - 0.5f,
                min(tp.y, tq.y) - 0.5f,
                max(tp.x, tq.x) + 0.5f,
                max(tp.y, tq.y) + 0.5f,
            );
            clip = clipByRect(bbox);
        }
        if (clip.empty)
            return;

        const origin = st.mat * Vec2(0);
        const coeffX = (st.mat * Vec2(1, 0) - origin).length;
        const coeffY = (st.mat * Vec2(0, 1) - origin).length;
        if (coeffX <= 0 && coeffY <= 0)
            return;

        // draw line using quad
        p.x += 0.5f;
        p.y += 0.5f;
        q.x += 0.5f;
        q.y += 0.5f;
        const n = (q - p).normalized;
        const dir2 = Vec2(n.x * 0.5f / coeffX, n.y * 0.5f / coeffY);
        const offset = dir2.rotated90ccw();
        p -= dir2;
        q += dir2;
        Vec2[4] ps = [p - offset, q - offset, q + offset, p + offset];

        const v = positions.length;
        const t = triangles.length;
        positions ~= ps[];
        triangles ~= Tri(v, v + 1, v + 2);
        triangles ~= Tri(v + 2, v + 3, v);

        if (st.aa)
        {
            gpaa.add(ps[]);
            gpaa.finish(dataStore.length);
        }

        simpleColorOnly(t, RectI(clip), c);
    }

    void fillRect(RectF r, Color c)
    {
        fillRectImpl(r, &c);
    }

    void fillTriangle(Vec2[3] ps, Color c)
    {
        const BoxI clip = clipByRect(transformBounds(computeBoundingBox(ps[])));
        if (clip.empty)
            return;

        const v = positions.length;
        const t = triangles.length;
        positions ~= ps[];
        triangles ~= Tri(v, v + 1, v + 2);

        if (st.aa)
        {
            gpaa.add(ps[]);
            gpaa.finish(dataStore.length);
        }

        simpleColorOnly(t, RectI(clip), c);
    }

    void fillCircle(float cx, float cy, float r, Color c)
    {
        const BoxI clip = clipByRect(transformBounds(RectF(cx - r, cy - r, cx + r, cy + r)));
        if (clip.empty)
            return;

        const ry = r * 4.0f / 3.0f;
        const pl = Vec2(cx - r, cy);
        const pr = Vec2(cx + r, cy);

        const v = positions.length;
        positions ~= Vec2(cx, cy);
        positions ~= pl;
        flattenCubicBezier(positions, pl, Vec2(pl.x, cy - ry), Vec2(pr.x, cy - ry), pr, false);
        positions ~= pr;
        flattenCubicBezier(positions, pr, Vec2(pr.x, cy + ry), Vec2(pl.x, cy + ry), pl, false);
        positions ~= pl;
        const vend = positions.length;

        const t = triangles.length;
        addFan(triangles, v, vend - v);

        if (st.aa)
        {
            gpaa.add(positions[][v + 1 .. vend]);
            gpaa.finish(dataStore.length);
        }

        simpleColorOnly(t, RectI(clip), c);
    }

    void drawImage(const ColorDrawBufBase img, Vec2 p, float opacity)
    {
        const int w = img.width;
        const int h = img.height;
        const rp = RectF(p.x, p.y, p.x + w, p.y + h);
        const BoxI clip = clipByRect(transformBounds(rp));
        if (clip.empty)
            return;

        const TextureView view = textureCache.getTexture(img);
        if (view.empty)
            return;
        assert(view.box.w == w && view.box.h == h);

        const Vec2[4] vs = [
            Vec2(rp.left, rp.top),
            Vec2(rp.left, rp.bottom),
            Vec2(rp.right, rp.top),
            Vec2(rp.right, rp.bottom),
        ];
        Vec2[4] uvs = [Vec2(0, 0), Vec2(0, h), Vec2(w, 0), Vec2(w, h)];
        foreach (ref uv; uvs)
        {
            uv.x = (uv.x + view.box.x) / view.texSize.w;
            uv.y = (uv.y + view.box.y) / view.texSize.h;
        }
        const v = positions_textured.length;
        const t = triangles.length;
        positions_textured ~= vs[];
        uvs_textured ~= uvs[];
        addStrip(triangles, v, 4);

        if (st.aa)
        {
            const Vec2[4] silhouette = [
                Vec2(rp.left, rp.top),
                Vec2(rp.left, rp.bottom),
                Vec2(rp.right, rp.bottom),
                Vec2(rp.right, rp.top),
            ];
            gpaa.add(silhouette[]);
            gpaa.finish(dataStore.length);
        }

        ShParams params;
        params.kind = PaintKind.image;
        params.image = ParamsImage(view.tex, opacity);

        Batch bt;
        bt.type = BatchType.simple;
        // bt.common.opaque = fequal6(opacity, 1);
        bt.common.clip = RectI(clip);
        bt.common.params = params;
        bt.common.triangles = Span(t, triangles.length);
        bt.simple.hasUV = true;
        batches ~= bt;

        dataIndices_textured.resize(positions_textured.length, cast(ushort)dataStore.length);
        dataStore ~= prepareDataChunk();

        advanceDepth();
    }

    void drawNinePatch(const ColorDrawBufBase img, ref const NinePatchInfo info, float opacity)
    {
        const rp = RectF(info.dst_x0, info.dst_y0, info.dst_x3, info.dst_y3);
        const BoxI clip = clipByRect(transformBounds(rp));
        if (clip.empty)
            return;

        const TextureView view = textureCache.getTexture(img);
        if (view.empty)
            return;
        assert(view.box.w == img.width && view.box.h == img.height);

        const Vec2[16] vs = [
            Vec2(info.dst_x0, info.dst_y0),
            Vec2(info.dst_x0, info.dst_y1),
            Vec2(info.dst_x1, info.dst_y0),
            Vec2(info.dst_x1, info.dst_y1),
            Vec2(info.dst_x2, info.dst_y0),
            Vec2(info.dst_x2, info.dst_y1),
            Vec2(info.dst_x3, info.dst_y0),
            Vec2(info.dst_x3, info.dst_y1),
            Vec2(info.dst_x0, info.dst_y2),
            Vec2(info.dst_x0, info.dst_y3),
            Vec2(info.dst_x1, info.dst_y2),
            Vec2(info.dst_x1, info.dst_y3),
            Vec2(info.dst_x2, info.dst_y2),
            Vec2(info.dst_x2, info.dst_y3),
            Vec2(info.dst_x3, info.dst_y2),
            Vec2(info.dst_x3, info.dst_y3),
        ];
        Vec2[16] uvs = [
            Vec2(info.x0, info.y0),
            Vec2(info.x0, info.y1),
            Vec2(info.x1, info.y0),
            Vec2(info.x1, info.y1),
            Vec2(info.x2, info.y0),
            Vec2(info.x2, info.y1),
            Vec2(info.x3, info.y0),
            Vec2(info.x3, info.y1),
            Vec2(info.x0, info.y2),
            Vec2(info.x0, info.y3),
            Vec2(info.x1, info.y2),
            Vec2(info.x1, info.y3),
            Vec2(info.x2, info.y2),
            Vec2(info.x2, info.y3),
            Vec2(info.x3, info.y2),
            Vec2(info.x3, info.y3),
        ];
        foreach (ref uv; uvs)
        {
            uv.x = (uv.x + view.box.x) / view.texSize.w;
            uv.y = (uv.y + view.box.y) / view.texSize.h;
        }
        const v = positions_textured.length;
        positions_textured ~= vs[];
        uvs_textured ~= uvs[];

        Tri[18] tris = [
            Tri(0, 1, 2), Tri(1, 2, 3),
            Tri(2, 3, 4), Tri(3, 4, 5),
            Tri(4, 5, 6), Tri(5, 6, 7),
            Tri(1, 8, 3), Tri(8, 3, 10),
            Tri(3, 10, 5), Tri(10, 5, 12),
            Tri(5, 12, 7), Tri(12, 7, 14),
            Tri(8, 9, 10), Tri(9, 10, 11),
            Tri(10, 11, 12), Tri(11, 12, 13),
            Tri(12, 13, 14), Tri(13, 14, 15),
        ];
        foreach (ref tri; tris)
        {
            tri.v0 += v;
            tri.v1 += v;
            tri.v2 += v;
        }
        const t = triangles.length;
        triangles ~= tris[];

        if (st.aa)
        {
            const Vec2[4] silhouette = [
                Vec2(rp.left, rp.top),
                Vec2(rp.left, rp.bottom),
                Vec2(rp.right, rp.bottom),
                Vec2(rp.right, rp.top),
            ];
            gpaa.add(silhouette[]);
            gpaa.finish(dataStore.length);
        }

        ShParams params;
        params.kind = PaintKind.image;
        params.image = ParamsImage(view.tex, opacity);

        Batch bt;
        bt.type = BatchType.simple;
        // bt.common.opaque = fequal6(opacity, 1);
        bt.common.clip = RectI(clip);
        bt.common.params = params;
        bt.common.triangles = Span(t, triangles.length);
        bt.simple.hasUV = true;
        batches ~= bt;

        dataIndices_textured.resize(positions_textured.length, cast(ushort)dataStore.length);
        dataStore ~= prepareDataChunk();

        advanceDepth();
    }

    void drawText(const GlyphInstance[] run, Color c)
    {
        Batch bt;
        bt.type = BatchType.simple;
        bt.common.triangles = Span(triangles.length, triangles.length);
        bt.simple.hasUV = true;

        ShParams params;
        params.kind = PaintKind.text;
        params.text = ParamsText(null, ColorF(c));

        bool firstGlyph = true;
        foreach (gi; run)
        {
            const TextureView view = glyphCache.getTexture(gi.glyph);
            if (view.empty)
                continue;

            if (firstGlyph)
            {
                params.text.tex = view.tex;
                firstGlyph = false;
            }
            if (params.text.tex != view.tex)
            {
                bt.common.params = params;
                bt.common.triangles.end = triangles.length;
                batches ~= bt;

                bt.common.triangles.start = triangles.length;
                params.text.tex = view.tex;
            }

            const x = gi.position.x;
            const y = gi.position.y;
            const Vec2[4] vs = [
                Vec2(x, y),
                Vec2(x, y + view.box.h),
                Vec2(x + view.box.w, y),
                Vec2(x + view.box.w, y + view.box.h),
            ];
            const r = RectF(view.box.x, view.box.y, view.box.x + view.box.w, view.box.y + view.box.h);
            const Vec2[4] uvs = [
                Vec2(r.left / view.texSize.w, r.top / view.texSize.h),
                Vec2(r.left / view.texSize.w, r.bottom / view.texSize.h),
                Vec2(r.right / view.texSize.w, r.top / view.texSize.h),
                Vec2(r.right / view.texSize.w, r.bottom / view.texSize.h),
            ];
            const v = positions_textured.length;
            positions_textured ~= vs[];
            uvs_textured ~= uvs[];
            addStrip(triangles, v, 4);
        }
        if (params.text.tex)
        {
            bt.common.params = params;
            bt.common.triangles.end = triangles.length;
            batches ~= bt;
        }

        dataIndices_textured.resize(positions_textured.length, cast(ushort)dataStore.length);
        dataStore ~= prepareDataChunk();

        advanceDepth();
    }

private:

    bool fillRectImpl(RectF r, Color* c)
    {
        const RectF tr = transformBounds(r);
        const BoxI clip = clipByRect(tr);
        if (clip.empty)
            return false;

        const Vec2[4] vs = [
            Vec2(r.left, r.top),
            Vec2(r.left, r.bottom),
            Vec2(r.right, r.top),
            Vec2(r.right, r.bottom),
        ];
        const v = positions.length;
        const t = triangles.length;
        positions ~= vs[];
        addStrip(triangles, v, 4);

        // TODO: does not antialias if it's pixel-aligned
        if (st.aa)
        {
            const Vec2[4] silhouette = [
                Vec2(r.left, r.top),
                Vec2(r.left, r.bottom),
                Vec2(r.right, r.bottom),
                Vec2(r.right, r.top),
            ];
            gpaa.add(silhouette[]);
            gpaa.finish(dataStore.length);
        }
        return c ? simpleColorOnly(t, RectI(clip), *c) : simple(t, RectI(clip), null);
    }

    bool fillPathImpl(ref Contours contours, const Brush* br, Stenciling stenciling)
    {
        const lst = contours.list;
        if (lst.length == 1)
        {
            const(Vec2)[] points = lst[0].points[0 .. $ - (lst[0].closed ? 1 : 0)];
            if (points.length < 3)
                return false;

            const RectI clip = lst[0].trBounds;
            const v = positions.length;
            const t = triangles.length;
            positions ~= points;
            addFan(triangles, v, points.length);

            if (st.aa)
            {
                gpaa.add(points);
                gpaa.finish(dataStore.length);
            }

            if (isConvex(points) && stenciling != Stenciling.zero && stenciling != Stenciling.even)
            {
                return simple(t, clip, br);
            }
            else
            {
                return twoPass(t, stenciling, lst[0].bounds, clip, br);
            }
        }
        else
        {
            // C(S(p)) = C(S(p_0 + p_1 + ... + p_n)),
            // where S - stencil, C - cover

            const t = triangles.length;
            foreach (ref cr; lst)
            {
                const Vec2[] points = cr.points[0 .. $ - (cr.closed ? 1 : 0)];
                if (points.length < 3)
                    continue;

                const v = positions.length;
                positions ~= points;
                addFan(triangles, v, points.length);
                if (st.aa)
                    gpaa.add(points);
            }
            if (st.aa)
                gpaa.finish(dataStore.length);

            if (triangles.length > t)
                return twoPass(t, stenciling, contours.bounds, contours.trBounds, br);
            else
                return false;
        }
    }

    // TODO: find more opportunities for merging

    bool simpleColorOnly(uint tstart, RectI clip, Color color)
    {
        const opaque = color.isOpaque;
        DataChunk data = prepareDataChunk(null, color);
        // try to merge with the previous
        if (auto last = hasSimilarSimpleBatch(PaintKind.solid, opaque))
        {
            last.common.clip.include(clip);
            assert(last.common.triangles.end == tstart);
            last.common.triangles.end = triangles.length;
        }
        else
        {
            Batch bt;
            bt.type = BatchType.simple;
            bt.common.opaque = opaque;
            bt.common.clip = clip;
            bt.common.params.kind = PaintKind.solid;
            bt.common.triangles = Span(tstart, triangles.length);
            batches ~= bt;
        }
        doneBatch(data);
        return true;
    }

    bool simple(uint tstart, RectI clip, const Brush* br)
    {
        ShParams params;
        DataChunk data;
        if (!convertBrush(br, params, data))
            return false;

        const opaque = br ? br.isOpaque : true; // TODO: image opacity
        // try to merge
        if (auto last = hasSimilarSimpleBatch(params.kind, opaque))
        {
            last.common.clip.include(clip);
            assert(last.common.triangles.end == tstart);
            last.common.triangles.end = triangles.length;
        }
        else
        {
            Batch bt;
            bt.type = BatchType.simple;
            bt.common.opaque = opaque;
            bt.common.clip = clip;
            bt.common.params = params;
            bt.common.triangles = Span(tstart, triangles.length);
            batches ~= bt;
        }
        doneBatch(data);
        return true;
    }

    /// Stencil, than cover
    bool twoPass(uint tstart, Stenciling stenciling, RectF bbox, RectI clip, const Brush* br)
    {
        ShParams params;
        DataChunk data;
        if (!convertBrush(br, params, data))
            return false;

        if (stenciling == Stenciling.zero || stenciling == Stenciling.even)
        {
            import std.math : SQRT2;

            bbox.expand(bbox.width * SQRT2, bbox.height * SQRT2);
        }

        const opaque = br ? br.isOpaque : true; // TODO: image opacity
        const coverIdx = covers.length;
        covers ~= Cover(bbox, clip, dataStore.length);
        // try to merge
        if (auto last = hasSimilarTwoPassBatch(params.kind, opaque, stenciling, clip))
        {
            last.common.clip.include(clip);
            assert(last.common.triangles.end == tstart);
            last.common.triangles.end = triangles.length;
            last.twopass.covers.end++;
        }
        else
        {
            Batch bt;
            bt.type = BatchType.twopass;
            bt.common.opaque = opaque;
            bt.common.clip = clip;
            bt.common.params = params;
            bt.common.triangles = Span(tstart, triangles.length);
            bt.twopass.covers = Span(coverIdx, coverIdx + 1);
            bt.twopass.stenciling = stenciling;
            batches ~= bt;
        }
        doneBatch(data);
        return true;
    }

    Batch* hasSimilarSimpleBatch(PaintKind kind, bool opaque)
        in(sets.length)
    {
        if ((kind == PaintKind.empty || kind == PaintKind.solid) && batches.length > sets[$ - 1].batches.start)
        {
            Batch* last = &batches.unsafe_ref(-1);
            if (last.type == BatchType.simple && last.common.opaque == opaque && last.common.params.kind == kind)
                return last;
        }
        return null;
    }

    Batch* hasSimilarTwoPassBatch(PaintKind kind, bool opaque, Stenciling stenciling, RectI clip)
        in(sets.length)
    {
        if ((kind == PaintKind.empty || kind == PaintKind.solid) && batches.length > sets[$ - 1].batches.start)
        {
            Batch* last = &batches.unsafe_ref(-1);
            if (last.type == BatchType.twopass && last.common.opaque == opaque && last.common.params.kind == kind)
            {
                const bt = last.twopass;
                if (bt.stenciling == stenciling)
                {
                    // we can merge non-overlapping covers
                    foreach (ref cov; covers[][bt.covers.start .. bt.covers.end])
                    {
                        if (clip.intersects(cov.clip))
                            return null;
                    }
                    return last;
                }
            }
        }
        return null;
    }

    void doneBatch(ref DataChunk data)
    {
        dataIndices.resize(positions.length, cast(ushort)dataStore.length);
        dataStore ~= data;
        advanceDepth();
    }

    void advanceDepth()
    {
        layer.depth *= 0.999f;
    }

    DataChunk prepareDataChunk(const Mat2x3* m = null, Color c = Color.transparent)
    {
        return DataChunk(
            m ? *m : st.mat,
            layer.depth,
            0,
            RectF.from(st.clipRect),
            ColorF(c).premultiplied,
        );
    }

    bool convertBrush(const Brush* br, ref ShParams params, ref DataChunk data)
    {
        if (dataStore.length >= MAX_DATA_CHUNKS)
            return false;

        data = prepareDataChunk();
        if (!br)
            return true; // PaintKind.empty

        final switch (br.type) with (BrushType)
        {
            case solid:   return convertSolid(br.solid, br.opacity, params, data);
            case linear:  return convertLinear(br.linear, br.opacity, params, data);
            case radial:  return convertRadial(br.radial, br.opacity, params, data);
            case pattern: return convertPattern(br.pattern, br.opacity, params, data);
        }
    }

    bool convertSolid(Color cu, float opacity, ref ShParams params, ref DataChunk data)
    {
        ColorF c = cu;
        c.a *= opacity;
        data.color = c.premultiplied;
        params.kind = PaintKind.solid;
        return true;
    }

    bool convertLinear(ref const LinearGradient grad, float opacity, ref ShParams params, ref DataChunk data)
        in(grad.colors.length >= 2)
    {
        const start = data.transform * grad.start;
        const end = data.transform * grad.end;
        if (fequal2(start.x, end.x) && fequal2(start.y, end.y))
            return convertSolid(grad.colors[$ - 1], opacity, params, data);

        const count = grad.colors.length;
        const row = ColorStopAtlasRow(grad.colors, opacity);
        const atlasIndex = colorStopAtlas.add(row);

        params.kind = PaintKind.linear;
        params.linear = ParamsLG(
            start,
            end,
            grad.stops[0 .. count],
            colorStopAtlas.tex,
            atlasIndex,
        );
        return true;
    }

    bool convertRadial(ref const RadialGradient grad, float opacity, ref ShParams params, ref DataChunk data)
        in(grad.colors.length >= 2)
    {
        const radius = (data.transform * Vec2(grad.radius, 0) - data.transform * Vec2(0)).length;
        if (fzero2(radius))
            return convertSolid(grad.colors[$ - 1], opacity, params, data);

        const center = data.transform * grad.center;

        const count = grad.colors.length;
        const row = ColorStopAtlasRow(grad.colors, opacity);
        const atlasIndex = colorStopAtlas.add(row);

        params.kind = PaintKind.radial;
        params.radial = ParamsRG(
            center,
            radius,
            grad.stops[0 .. count],
            colorStopAtlas.tex,
            atlasIndex,
        );
        return true;
    }

    bool convertPattern(ref const ImagePattern pat, float opacity, ref ShParams params, ref DataChunk data)
        in(pat.image)
    {
        const TextureView view = textureCache.getTexture(pat.image);
        if (view.empty)
            return false; // skip rendering

        params.kind = PaintKind.pattern;
        params.pattern = ParamsPattern(
            view.tex,
            view.texSize,
            view.box,
            (data.transform * pat.transform).inverted,
            opacity,
        );
        return true;
    }
}

void addFan(ref Buf!Tri output, uint vstart, size_t vcount)
    in(vcount >= 2)
{
    const v0 = vstart;
    const tris = cast(uint)vcount - 2;
    output.reserve(output.length + tris);
    foreach (v; v0 .. v0 + tris)
        output ~= Tri(v0, v + 1, v + 2);
}

void addStrip(ref Buf!Tri output, uint vstart, size_t vcount)
    in(vcount >= 2)
{
    const v0 = vstart;
    const tris = cast(uint)vcount - 2;
    output.reserve(output.length + tris);
    foreach (v; v0 .. v0 + tris)
        output ~= Tri(v, v + 1, v + 2);
}

struct LineAppender
{
    nothrow:

    @property bool ready() const { return positions !is null; }

    private Buf!Vec2* positions;
    private Buf!uint* indices;
    private uint istart;

    this(ref Buf!Vec2 positions, ref Buf!uint indices)
        in(positions.length > 0)
    {
        this.positions = &positions;
        this.indices = &indices;
    }

    void begin()
        in(positions)
    {
        istart = positions.length;
    }

    void end()
        in(positions)
    {
        const iend = positions.length;
        if (iend == istart)
            return;

        foreach (i; istart .. iend - 1)
        {
            indices.put(i - 1);
            indices.put(i);
        }
        istart = iend;
    }

    void v(Vec2 v0)
        in(positions)
    {
        positions.put(v0);
    }

    void vs(const Vec2[] points)
        in(positions)
    {
        positions.put(points);
    }
}

final class TriBuilder : StrokeBuilder
{
    nothrow:

    private
    {
        Buf!Vec2* positions;
        Buf!Tri* triangles;
        LineAppender contour;

        enum Mode { strip, fan }
        Mode mode;
        uint vstart;
    }

    this(ref Buf!Vec2 positions, ref Buf!Tri triangles)
    {
        this.positions = &positions;
        this.triangles = &triangles;
    }

    void beginContour()
    {
        vstart = positions.length;
    }

    void add(Vec2 left, Vec2 right)
    {
        positions.put(left);
        positions.put(right);
    }

    Buf!Vec2* beginFanLeft(Vec2 center)
    {
        endContour();
        mode = Mode.fan;
        positions.put(center);
        return positions;
    }

    Buf!Vec2* beginFanRight(Vec2 center)
    {
        endContour();
        mode = Mode.fan;
        positions.put(center);
        return positions;
    }

    void endFan()
    {
        endContour();
    }

    void breakStrip()
    {
        endContour();
    }

    void endContour()
    {
        const vend = positions.length;
        if (vend - vstart < 3)
        {
            vstart = vend;
            mode = Mode.strip;
            return;
        }
        // generate indices
        const tris = vend - vstart - 2;
        foreach (v; vstart .. vstart + tris)
        {
            triangles.put(Tri(mode == Mode.strip ? v : vstart, v + 1, v + 2));
        }
        // generate line silhouette for further antialiasing
        if (contour.ready)
        {
            contour.begin();
            if (mode == Mode.strip)
            {
                contour.v((*positions)[vstart]);
                for (uint v = vstart + 1; v < vend; v += 2)
                    contour.v((*positions)[v]);
                contour.v((*positions)[vend - 2]);
                contour.end();
                for (uint v = vstart; v < vend; v += 2)
                    contour.v((*positions)[v]);
            }
            else
            {
                contour.vs((*positions)[][vstart .. vend]);
            }
            contour.end();
        }

        vstart = vend;
        mode = Mode.strip;
    }
}

struct GpaaAppender
{
    nothrow:

    @property LineAppender contour() { return appender; }

    private
    {
        Buf!uint indices;
        Buf!Vec2 positions;
        Buf!ushort dataIndices;
        Buf!ushort layerIndices;
        LineAppender appender;

        uint layerIndex;
    }

    void prepare()
    {
        indices.clear();
        dataIndices.clear();
        positions.clear();
        positions ~= Vec2(0, 0);
        appender = LineAppender(positions, indices);
    }

    void setLayerIndex(uint i)
    {
        layerIndex = i;
    }

    void add(const Vec2[] points)
    {
        appender.begin();
        appender.vs(points);
        const fst = points[0];
        const lst = points[$ - 1];
        if (!fequal2(fst.x, lst.x) || !fequal2(fst.y, lst.y))
            appender.v(fst);
        appender.end();
    }

    void finish(uint dataIndex)
    {
        dataIndices.resize(positions.length, cast(ushort)dataIndex);
        layerIndices.resize(positions.length, cast(ushort)layerIndex);
    }
}

void ensureNotInGC(const Object object)
{
    import core.exception : InvalidMemoryOperationError;
    import core.memory : GC;
    import core.stdc.stdio : fprintf, stderr;
    import beamui.core.functions : getShortClassName;

    try
    {
        cast(void)GC.malloc(1);
    }
    catch(InvalidMemoryOperationError e)
    {
        const name = getShortClassName(object);
        fprintf(stderr, "Error: %.*s must be destroyed manually.\n", name.length, name.ptr);
        assert(0);
    }
}
