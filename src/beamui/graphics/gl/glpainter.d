/**
OpenGL (ES) 3 painter implementation.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.glpainter;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
import std.algorithm.mutation : reverse;
import std.typecons : scoped;

import beamui.core.collections : Buf;
import beamui.core.geometry : BoxI, Rect, RectI, SizeI;
import beamui.core.linalg : Mat2x3, Vec2;
import beamui.core.logger : Log;
import beamui.core.math;
import beamui.core.types : tup;
import beamui.graphics.bitmap : Bitmap, onBitmapDestruction;
import beamui.graphics.brush;
import beamui.graphics.colors : Color, ColorF;
import beamui.graphics.compositing : getBlendFactors;
import beamui.graphics.flattener;
import beamui.graphics.gl.objects : TexId;
import beamui.graphics.gl.renderer;
import beamui.graphics.gl.shaders;
import beamui.graphics.gl.stroke_tiling;
import beamui.graphics.gl.textures;
import beamui.graphics.painter : GlyphInstance, MIN_RECT_F, PaintEngine;
import beamui.graphics.path : SubPath;
import beamui.graphics.pen;
import beamui.graphics.polygons;
import beamui.text.glyph : onGlyphDestruction;

private nothrow:

/*
Notes:
- this module doesn't call GL at all
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
        onBitmapDestruction ~= &textureCache.remove;
        onGlyphDestruction ~= &glyphCache.remove;
    }

    ~this()
    {
        onBitmapDestruction -= &textureCache.remove;
        onGlyphDestruction -= &glyphCache.remove;
        debug ensureNotInGC(this);
    }
}

struct Geometry
{
    Buf!Batch batches;
    Buf!Tri triangles;

    Buf!Vec2 positions;
    Buf!ushort dataIndices;
    Buf!Vec2 positions_textured;
    Buf!ushort dataIndices_textured;
    Buf!Vec2 uvs_textured; // actually in 0..texSize range

    void clear() nothrow
    {
        batches.clear();
        triangles.clear();
        positions.clear();
        dataIndices.clear();
        positions_textured.clear();
        dataIndices_textured.clear();
        uvs_textured.clear();
    }
}

/// Layers form a tree
struct Layer
{
    RenderLayer base;
    alias base this;

    Span sets; /// Sets of this layer and its sub-layers

    float depth = 1;
    float opacity = 1;
    GpaaAppender gpaa;
}

struct Cover
{
    Rect rect; /// Local to batch
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
        Layer* layer; // points into array, so need to handle carefully
        Buf!Layer layers;
        Buf!Set sets;

        Buf!DataChunk dataStore;

        Geometry g_opaque;
        Geometry g_transp;

        Buf!Cover covers;
        Buf!DepthTask depthTasks;

        Buf!Vec2 bufVerts;
        Buf!uint bufContours;
        TileGrid tileGrid;
        Buf!PackedTile tilePoints;
        Buf!ushort tileDataIndices;

        ColorStopAtlas* colorStopAtlas;
        TextureCache* textureCache;
        GlyphCache* glyphCache;

        FlatteningContourIter strokeIter;
        GpaaAppenderPool gpaaPool;

        Renderer renderer;
    }

    this(GLSharedData data)
    in (data)
    {
        renderer.initialize(&data.sh);
        colorStopAtlas = &data.colorStopAtlas;
        textureCache = &data.textureCache;
        glyphCache = &data.glyphCache;
        strokeIter = new FlatteningContourIter;
    }

    ~this()
    {
        debug ensureNotInGC(this);
    }

protected:

    override void begin(FrameConfig conf)
    {
        layers.clear();
        sets.clear();

        dataStore.clear();

        g_opaque.clear();
        g_transp.clear();

        covers.clear();
        depthTasks.clear();

        tileGrid.prepare(conf.ddpSize.w, conf.ddpSize.h);
        tilePoints.clear();
        tileDataIndices.clear();

        colorStopAtlas.reset();
        gpaaPool.reset();

        Layer lr;
        lr.bounds = RectI(0, 0, conf.ddpSize.w, conf.ddpSize.h);
        lr.fill = ColorF(conf.background);
        lr.gpaa = gpaaPool.getFree();
        layers ~= lr;
        layer = &layers.unsafe_ref(0);
        sets ~= Set.init;
    }

    private Buf!GpaaDataToUpload gpaaDataToUpload;
    private Buf!(const(RenderLayer)*) layersToRender;

    override void end()
    {
        layersToRender.clear();
        gpaaDataToUpload.clear();

        textureCache.updateMipmaps();
        prepareSets();
        prepareLayers();
        constructCoverGeometry();

        if (!g_opaque.batches.length && !g_transp.batches.length)
        {
            paint();
            return;
        }

        debug (painter)
        {
            // dfmt off
            Log.fd("GL: %s bt, %s dat, %s tri, %s v",
                g_opaque.batches.length + g_transp.batches.length,
                dataStore.length,
                g_opaque.triangles.length + g_transp.triangles.length,
                g_opaque.positions.length + g_opaque.positions_textured.length +
                g_transp.positions.length + g_transp.positions_textured.length,
            );
            // dfmt on
        }

        // dfmt off
        foreach (ref lr; layers[])
        {
            gpaaDataToUpload ~= GpaaDataToUpload(
                lr.gpaa.indices[],
                lr.gpaa.positions[],
                lr.gpaa.dataIndices[],
                lr.bounds.size,
            );
        }
        renderer.upload(DataToUpload(
            GeometryToUpload(
                g_opaque.triangles[],
                g_opaque.positions[],
                g_opaque.dataIndices[],
                g_opaque.positions_textured[],
                g_opaque.dataIndices_textured[],
                g_opaque.uvs_textured[],
            ),
            GeometryToUpload(
                g_transp.triangles[],
                g_transp.positions[],
                g_transp.dataIndices[],
                g_transp.positions_textured[],
                g_transp.dataIndices_textured[],
                g_transp.uvs_textured[],
            ),
            dataStore[],
            tilePoints[],
            tileDataIndices[],
        ), gpaaDataToUpload[], tileGrid);
        // dfmt on

        paint();
    }

    private void paint()
    {
        foreach (ref lr; layers[])
            layersToRender ~= &lr.base;

        renderer.render(DrawLists(layersToRender[], sets[], g_opaque.batches[], g_transp.batches[]));
    }

    private void prepareSets()
    {
        Set[] list = sets.unsafe_slice;
        foreach (i; 1 .. list.length)
        {
            list[i - 1].b_opaque.end = list[i].b_opaque.start;
            list[i - 1].b_transp.end = list[i].b_transp.start;
            list[i - 1].dataChunks.end = list[i].dataChunks.start;
        }
        list[$ - 1].b_opaque.end = g_opaque.batches.length;
        list[$ - 1].b_transp.end = g_transp.batches.length;
        list[$ - 1].dataChunks.end = dataStore.length;
        list[$ - 1].finishing = true;
    }

    private void prepareLayers()
    in (layers.length)
    {
        if (layers.length == 1)
            return;

        foreach (ref Layer lr; layers.unsafe_slice[1 .. $])
        {
            if (lr.empty)
                continue;

            // indicate the set where to antialias
            sets.unsafe_ref(lr.sets.end - 1).finishing = true;

            // shift batches to the layer origin
            const shift = Vec2(-lr.bounds.left, -lr.bounds.top);
            foreach (i, ref set; sets[][lr.sets.start .. lr.sets.end])
            {
                if (set.layer == lr.index)
                {
                    const Span data = set.dataChunks;
                    foreach (ref DataChunk ch; dataStore.unsafe_slice[data.start .. data.end])
                    {
                        ch.transform.store[0][2] += shift.x;
                        ch.transform.store[1][2] += shift.y;
                        ch.clipRect.translate(shift.x, shift.y);
                    }
                }
            }
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
        foreach (Geometry* g; tup(&g_opaque, &g_transp))
        {
            foreach (ref bt; g.batches.unsafe_slice)
            {
                if (bt.type == BatchType.twopass)
                {
                    const t = g.triangles.length;
                    const Span covs = bt.twopass.covers;
                    foreach (ref cov; covers[][covs.start .. covs.end])
                    {
                        // dfmt off
                        const Vec2[4] vs = [
                            Vec2(cov.rect.left, cov.rect.top),
                            Vec2(cov.rect.left, cov.rect.bottom),
                            Vec2(cov.rect.right, cov.rect.top),
                            Vec2(cov.rect.right, cov.rect.bottom),
                        ];
                        // dfmt on
                        const v = g.positions.length;
                        g.positions ~= vs[];
                        addStrip(g.triangles, v, 4);
                        g.dataIndices.resize(g.dataIndices.length + 4, cast(ushort)cov.dataIndex);
                    }
                    bt.twopass.coverTriangles = Span(t, g.triangles.length);
                }
            }
        }
        foreach (ref set; sets[])
        {
            if (set.layerToCompose > 0)
            {
                auto g = pickGeometry(false);
                Layer* lr = &layers.unsafe_ref(set.layerToCompose);

                const SizeI sz = lr.bounds.size;
                const Vec2[4] vs = [Vec2(0, 0), Vec2(0, sz.h), Vec2(sz.w, 0), Vec2(sz.w, sz.h)];
                const v = g.positions.length;
                const t = g.triangles.length;
                g.positions ~= vs[];
                addStrip(g.triangles, v, 4);
                g.dataIndices.resize(g.dataIndices.length + 4, lr.cmd.dataIndex);
                lr.cmd.triangles = Span(t, g.triangles.length);
            }
        }
    }

    override void beginLayer(LayerOp op)
    {
        Layer lr;
        lr.index = layers.length;
        lr.parent = layer.index;
        lr.sets.start = sets.length;
        lr.depth = layer.depth;
        lr.opacity = op.opacity;
        lr.cmd.composition = getBlendFactors(op.composition);
        lr.cmd.blending = op.blending;
        lr.gpaa = gpaaPool.getFree();
        layers ~= lr;
        layer = &layers.unsafe_ref(lr.index);
        sets ~= makeSet(lr.index);
    }

    override void composeLayer(RectI bounds)
    {
        const opacity = layer.opacity;
        layer.bounds = bounds;
        layer.sets.end = sets.length;
        layer.cmd.dataIndex = cast(ushort)dataStore.length;

        // setup the parent layer back
        sets ~= makeSet(layer.parent, layer.index);
        layer = &layers.unsafe_ref(layer.parent);

        // create a data chunk with the parent layer current depth
        const mat = Mat2x3.translation(Vec2(bounds.left, bounds.top));
        dataStore ~= prepareDataChunk(&mat, opacity);
        advanceDepth();
    }

    override void clipOut(uint index, const SubPath[] contours, FillRule rule, bool complement)
    {
        alias S = Stenciling;
        const set = makeSet(layer.index);
        const task = DepthTask(index, dataStore.length);
        const nonzero = rule == FillRule.nonzero;
        const stenciling = nonzero ? (complement ? S.zero : S.nonzero) : (complement ? S.even : S.odd);
        if (fillPathImpl(contours, null, stenciling))
        {
            sets ~= set;
            sets ~= makeSet(layer.index);
            depthTasks ~= task;
        }
    }

    private Set makeSet(uint layer, uint layerToCompose = 0) const
    {
        return Set(Span(g_opaque.batches.length), Span(g_transp.batches.length), Span(dataStore.length), layer, layerToCompose);
    }

    override void restore(uint index)
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

    override void paintOut(ref const Brush br)
    {
        const r = st.clipRect;
        // dfmt off
        const Vec2[4] vs = [
            Vec2(r.left, r.top),
            Vec2(r.left, r.bottom),
            Vec2(r.right, r.top),
            Vec2(r.right, r.bottom),
        ];
        // dfmt on
        auto g = pickGeometry(br.isOpaque);
        const v = g.positions.length;
        const t = g.triangles.length;
        g.positions ~= vs[];
        addStrip(g.triangles, v, 4);

        if (simple(t, &br))
        {
            dataStore.unsafe_ref(-1).transform = Mat2x3.identity;
        }
    }

    override void fillPath(const SubPath[] list, ref const Brush br, FillRule rule)
    {
        fillPathImpl(list, &br, rule == FillRule.nonzero ? Stenciling.nonzero : Stenciling.odd);
    }

    override void strokePath(const SubPath[] list, ref const Brush br, ref const Pen pen, bool)
    {
        bool evenlyScaled = true;
        float width = pen.width;
        if (pen.shouldScale)
        {
            const o = st.mat * Vec2(0);
            const v = st.mat * Vec2(1, 0) - o;
            const w = st.mat * Vec2(0, 1) - o;
            evenlyScaled = fequal2(v.magnitudeSquared, w.magnitudeSquared);
            width = v.length * pen.width;
        }
        if (br.type == BrushType.solid && evenlyScaled && width < 3)
            strokePathTiled(list, br, pen, width);
        else
            strokePathAsFill(list, br, pen);
    }

    private void strokePathTiled(const SubPath[] list, ref const Brush br, ref const Pen pen, float realWidth)
    {
        bufVerts.clear();
        bufContours.clear();

        const pixelSize = 1.0f / TILE_SIZE;
        Mat2x3 mat = Mat2x3.scaling(Vec2(pixelSize)) * st.mat;
        foreach (ref cr; list)
        {
            const len = cr.flatten!true(bufVerts, mat, pixelSize);
            if (len != 1)
            {
                bufContours ~= len;
                continue;
            }
            // fix degeneracies
            if (pen.cap == LineCap.butt)
            {
                bufVerts.shrink(1);
                continue;
            }
            const p = bufVerts[$ - 1];
            bufVerts.shrink(1);
            bufVerts ~= p - Vec2(pixelSize * 0.25f, 0);
            bufVerts ~= p + Vec2(pixelSize * 0.25f, 0);
            bufContours ~= 2;
        }

        const start = tilePoints.length;
        tileGrid.clipStrokeToLattice(bufVerts[], bufContours[], tilePoints, geometryBBox.screen, realWidth);
        const count = tilePoints.length - start;

        bool reuseBatch;
        if (g_transp.batches.length > sets[$ - 1].b_transp.start)
        {
            Batch* last = &g_transp.batches.unsafe_ref(-1);
            if (last.type == BatchType.tiled)
            {
                reuseBatch = true;
                last.common.triangles.end += count;
            }
        }
        if (!reuseBatch)
        {
            Batch bt;
            bt.type = BatchType.tiled;
            bt.common.triangles = Span(start, start + count);
            g_transp.batches ~= bt;
        }

        tileDataIndices.resize(tilePoints.length, cast(ushort)dataStore.length);

        Mat2x3 quasiMat;
        quasiMat.store[0][0] = realWidth;
        quasiMat.store[1][1] = st.aa ? 0.8f : 100; // contrast
        DataChunk data = prepareDataChunk(&quasiMat, br.opacity);
        ShParams params;
        convertSolid(br.solid, params, data);

        dataStore ~= data;
        advanceDepth();
    }

    private void strokePathAsFill(const SubPath[] list, ref const Brush br, ref const Pen pen)
    {
        auto g = pickGeometry(br.isOpaque);

        auto builder_obj = scoped!TriBuilder(g.positions, g.triangles);
        TriBuilder builder = builder_obj;

        const t = g.triangles.length;
        if (st.aa)
            builder.contour = layer.gpaa;

        // if we are in non-scaling mode, transform contours on CPU, then expand
        const minDist = pen.shouldScale ? getMinDistFromMatrix(st.mat) : 0.7f;
        strokeIter.recharge(list, st.mat, !pen.shouldScale);
        expandStrokes(strokeIter, pen, builder, minDist);

        if (st.aa)
            layer.gpaa.finish(dataStore.length);

        if (g.triangles.length > t)
        {
            const trivial = list.length == 1 && list[0].points.length < 3;
            const mat = pen.shouldScale ? st.mat : Mat2x3.identity;
            if (br.isOpaque || trivial)
            {
                simple(t, &br, &mat);
            }
            else
            {
                // we must do two-pass rendering to avoid overlaps
                // on bends and self-intersections
                const bounds = pen.shouldScale ? geometryBBox.local : Rect.from(geometryBBox.screen);
                twoPass(t, Stenciling.justCover, bounds, geometryBBox.screen, &br, &mat);
            }
        }
    }

    override void drawImage(ref const Bitmap bmp, Vec2 p, float opacity)
    {
        const int w = bmp.width;
        const int h = bmp.height;
        const rp = Rect(p.x, p.y, p.x + w, p.y + h);

        const TextureView view = textureCache.getTexture(bmp);
        if (view.empty)
            return;
        assert(view.box.w == w && view.box.h == h);

        auto g = pickGeometry(false); // fequal6(opacity, 1) // TODO: image opacity
        // dfmt off
        const Vec2[4] vs = [
            Vec2(rp.left, rp.top),
            Vec2(rp.left, rp.bottom),
            Vec2(rp.right, rp.top),
            Vec2(rp.right, rp.bottom),
        ];
        // dfmt on
        Vec2[4] uvs = [Vec2(0, 0), Vec2(0, h), Vec2(w, 0), Vec2(w, h)];
        foreach (ref uv; uvs)
        {
            uv.x += view.box.x;
            uv.y += view.box.y;
        }
        const v = g.positions_textured.length;
        const t = g.triangles.length;
        g.positions_textured ~= vs[];
        g.uvs_textured ~= uvs[];
        addStrip(g.triangles, v, 4);

        if (st.aa)
        {
            // dfmt off
            const Vec2[4] silhouette = [
                Vec2(rp.left, rp.top),
                Vec2(rp.left, rp.bottom),
                Vec2(rp.right, rp.bottom),
                Vec2(rp.right, rp.top),
            ];
            // dfmt on
            layer.gpaa.add(silhouette[]);
            layer.gpaa.finish(dataStore.length);
        }

        if (Batch* similar = hasSimilarImageBatch(view.tex, false))
        {
            similar.common.triangles.end = g.triangles.length;
        }
        else
        {
            ShParams params;
            params.kind = PaintKind.image;
            params.image = ParamsImage(view.tex, view.texSize);

            Batch bt;
            bt.type = BatchType.simple;
            bt.common.params = params;
            bt.common.triangles = Span(t, g.triangles.length);
            bt.simple.hasUV = true;
            g.batches ~= bt;
        }
        const data = prepareDataChunk(null, opacity);
        doneTexturedBatch(*g, data);
    }

    override void drawNinePatch(ref const Bitmap bmp, ref const NinePatchInfo info, float opacity)
    {
        const TextureView view = textureCache.getTexture(bmp);
        if (view.empty)
            return;
        assert(view.box.w == bmp.width && view.box.h == bmp.height);

        auto g = pickGeometry(false);
        // dfmt off
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
        // dfmt on
        foreach (ref uv; uvs)
        {
            uv.x += view.box.x;
            uv.y += view.box.y;
        }
        const v = g.positions_textured.length;
        g.positions_textured ~= vs[];
        g.uvs_textured ~= uvs[];

        // dfmt off
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
        // dfmt on
        foreach (ref tri; tris)
        {
            tri.v0 += v;
            tri.v1 += v;
            tri.v2 += v;
        }
        const t = g.triangles.length;
        g.triangles ~= tris[];

        if (st.aa)
        {
            const rp = Rect(info.dst_x0, info.dst_y0, info.dst_x3, info.dst_y3);
            // dfmt off
            const Vec2[4] silhouette = [
                Vec2(rp.left, rp.top),
                Vec2(rp.left, rp.bottom),
                Vec2(rp.right, rp.bottom),
                Vec2(rp.right, rp.top),
            ];
            // dfmt on
            layer.gpaa.add(silhouette[]);
            layer.gpaa.finish(dataStore.length);
        }

        if (Batch* similar = hasSimilarImageBatch(view.tex, false))
        {
            similar.common.triangles.end = g.triangles.length;
        }
        else
        {
            ShParams params;
            params.kind = PaintKind.image;
            params.image = ParamsImage(view.tex, view.texSize);

            Batch bt;
            bt.type = BatchType.simple;
            bt.common.params = params;
            bt.common.triangles = Span(t, g.triangles.length);
            bt.simple.hasUV = true;
            g.batches ~= bt;
        }
        const data = prepareDataChunk(null, opacity);
        doneTexturedBatch(*g, data);
    }

    override void drawText(const GlyphInstance[] run, Color c)
    {
        auto g = pickGeometry(false);

        Batch bt;
        bt.type = BatchType.simple;
        bt.common.params.kind = PaintKind.text;
        bt.common.triangles = Span(g.triangles.length, g.triangles.length);
        bt.simple.hasUV = true;

        Batch* similar;
        ParamsText params;
        bool firstGlyph = true;
        foreach (gi; run)
        {
            const TextureView view = glyphCache.getTexture(gi.glyph);
            if (view.empty)
                continue;

            if (firstGlyph)
            {
                firstGlyph = false;
                params = ParamsText(view.tex, view.texSize);
                similar = hasSimilarTextBatch(view.tex);
            }
            else if (params.tex !is view.tex)
            {
                if (similar)
                {
                    similar.common.triangles.end = g.triangles.length;
                    similar = null;
                }
                else
                {
                    bt.common.params.text = params;
                    bt.common.triangles.end = g.triangles.length;
                    g.batches ~= bt;
                }
                bt.common.triangles.start = g.triangles.length;
                params = ParamsText(view.tex, view.texSize);
            }
            addGlyph(*g, gi, view);
        }
        if (!params.tex)
            return;

        assert(bt.common.triangles.start < g.triangles.length);
        if (similar)
        {
            similar.common.triangles.end = g.triangles.length;
        }
        else
        {
            bt.common.params.text = params;
            bt.common.triangles.end = g.triangles.length;
            g.batches ~= bt;
        }
        auto data = prepareDataChunk(null, 0);
        data.color = ColorF(c).premultiplied;
        doneTexturedBatch(*g, data);
    }

private:

    void addGlyph(ref Geometry g, GlyphInstance gi, ref const TextureView view)
    {
        const float x = gi.position.x;
        const float y = gi.position.y;
        const float w = view.box.w;
        const float h = view.box.h;
        const Vec2[4] vs = [Vec2(x, y), Vec2(x, y + h), Vec2(x + w, y), Vec2(x + w, y + h)];
        Vec2[4] uvs = [Vec2(0, 0), Vec2(0, h), Vec2(w, 0), Vec2(w, h)];
        foreach (ref uv; uvs)
        {
            uv.x += view.box.x;
            uv.y += view.box.y;
        }
        const v = g.positions_textured.length;
        g.positions_textured ~= vs[];
        g.uvs_textured ~= uvs[];
        addStrip(g.triangles, v, 4);
    }

    bool fillPathImpl(const SubPath[] list, const Brush* br, Stenciling stenciling)
    {
        auto g = pickGeometry(br ? br.isOpaque : true);

        if (list.length == 1)
        {
            if (list[0].points.length < 3)
                return false;

            const v = g.positions.length;
            const t = g.triangles.length;
            uint pcount = list[0].flatten!false(g.positions, st.mat);
            // remove the extra point
            if (list[0].closed)
            {
                g.positions.shrink(1);
                pcount--;
            }
            addFan(g.triangles, v, pcount);

            if (st.aa)
            {
                layer.gpaa.add(g.positions[][v .. $]);
                layer.gpaa.finish(dataStore.length);
            }
            // spline is convex iff hull of its control points is convex
            if (isConvex(list[0].points) && stenciling != Stenciling.zero && stenciling != Stenciling.even)
            {
                return simple(t, br);
            }
            else
            {
                return twoPass(t, stenciling, list[0].bounds, geometryBBox.screen, br);
            }
        }
        else
        {
            // C(S(p)) = C(S(p_0 + p_1 + ... + p_n)),
            // where S - stencil, C - cover

            const t = g.triangles.length;
            foreach (ref sp; list)
            {
                if (sp.points.length < 3)
                    continue;

                const v = g.positions.length;
                uint pcount = sp.flatten!false(g.positions, st.mat);
                if (sp.closed)
                {
                    g.positions.shrink(1);
                    pcount--;
                }
                addFan(g.triangles, v, pcount);
                if (st.aa)
                    layer.gpaa.add(g.positions[][v .. $]);
            }
            if (st.aa)
                layer.gpaa.finish(dataStore.length);

            if (g.triangles.length > t)
                return twoPass(t, stenciling, geometryBBox.local, geometryBBox.screen, br);
            else
                return false;
        }
    }

    // TODO: find more opportunities for merging

    Geometry* pickGeometry(bool opaque)
    {
        return opaque ? &g_opaque : &g_transp;
    }

    bool simple(uint tstart, const Brush* br, const Mat2x3* m = null)
    {
        DataChunk data = prepareDataChunk(m, br ? br.opacity : 1);
        ShParams params;
        if (!convertBrush(br, params, data))
            return false;

        const opaque = br ? br.isOpaque : true;
        auto g = pickGeometry(opaque);
        // try to merge
        if (auto last = hasSimilarSimpleBatch(params.kind, opaque))
        {
            assert(last.common.triangles.end == tstart);
            last.common.triangles.end = g.triangles.length;
        }
        else
        {
            Batch bt;
            bt.type = BatchType.simple;
            bt.common.params = params;
            bt.common.triangles = Span(tstart, g.triangles.length);
            g.batches ~= bt;
        }
        doneBatch(*g, data);
        return true;
    }

    /// Stencil, than cover
    bool twoPass(uint tstart, Stenciling stenciling, Rect bbox, RectI clip, const Brush* br, const Mat2x3* m = null)
    {
        import std.math : SQRT1_2;

        DataChunk data = prepareDataChunk(m, br ? br.opacity : 1);
        ShParams params;
        if (!convertBrush(br, params, data))
            return false;

        if (stenciling == Stenciling.zero || stenciling == Stenciling.even)
        {
            // When clipping out, we have to enlarge the rectangle to cover
            // the whole `clipRect`. Both passes share the same matrix, so the
            // rectangle may be rotated. Fortunately, it is clipped very early
            // by `clipRect` itself.
            bbox.expand(bbox.width * SQRT1_2 + 1, bbox.height * SQRT1_2 + 1);
        }

        const opaque = br ? br.isOpaque : true;
        auto g = pickGeometry(opaque);
        const coverIdx = covers.length;
        covers ~= Cover(bbox, clip, dataStore.length);
        // try to merge
        if (auto last = hasSimilarTwoPassBatch(params.kind, opaque, stenciling, clip))
        {
            assert(last.common.triangles.end == tstart);
            last.common.triangles.end = g.triangles.length;
            last.twopass.covers.end++;
        }
        else
        {
            Batch bt;
            bt.type = BatchType.twopass;
            bt.common.params = params;
            bt.common.triangles = Span(tstart, g.triangles.length);
            bt.twopass.covers = Span(coverIdx, coverIdx + 1);
            bt.twopass.stenciling = stenciling;
            g.batches ~= bt;
        }
        doneBatch(*g, data);
        return true;
    }

    Batch* hasSimilarSimpleBatch(PaintKind kind, bool opaque)
    in (sets.length)
    {
        Batch* last;
        if (kind == PaintKind.empty || kind == PaintKind.solid)
        {
            if (opaque)
            {
                if (g_opaque.batches.length > sets[$ - 1].b_opaque.start)
                    last = &g_opaque.batches.unsafe_ref(-1);
            }
            else
            {
                if (g_transp.batches.length > sets[$ - 1].b_transp.start)
                    last = &g_transp.batches.unsafe_ref(-1);
            }
        }
        if (last && last.type == BatchType.simple && last.common.params.kind == kind)
            return last;
        return null;
    }

    Batch* hasSimilarImageBatch(const TexId* tex, bool opaque)
    in (sets.length)
    {
        Batch* last;
        if (tex && g_transp.batches.length > sets[$ - 1].b_transp.start)
        {
            if (opaque)
            {
                if (g_opaque.batches.length > sets[$ - 1].b_opaque.start)
                    last = &g_opaque.batches.unsafe_ref(-1);
            }
            else
            {
                if (g_transp.batches.length > sets[$ - 1].b_transp.start)
                    last = &g_transp.batches.unsafe_ref(-1);
            }
        }
        if (last && last.common.params.kind == PaintKind.image && last.common.params.image.tex is tex)
            return last;
        return null;
    }

    Batch* hasSimilarTextBatch(const TexId* tex)
    in (sets.length)
    {
        if (tex && g_transp.batches.length > sets[$ - 1].b_transp.start)
        {
            Batch* last = &g_transp.batches.unsafe_ref(-1);
            if (last.type == BatchType.simple)
            {
                const params = &last.common.params;
                if (params.kind == PaintKind.text && params.text.tex is tex)
                    return last;
            }
        }
        return null;
    }

    Batch* hasSimilarTwoPassBatch(PaintKind kind, bool opaque, Stenciling stenciling, RectI clip)
    in (sets.length)
    {
        Batch* last;
        if (kind == PaintKind.empty || kind == PaintKind.solid)
        {
            if (opaque)
            {
                if (g_opaque.batches.length > sets[$ - 1].b_opaque.start)
                    last = &g_opaque.batches.unsafe_ref(-1);
            }
            else
            {
                if (g_transp.batches.length > sets[$ - 1].b_transp.start)
                    last = &g_transp.batches.unsafe_ref(-1);
            }
        }
        if (last && last.type == BatchType.twopass && last.common.params.kind == kind)
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
        return null;
    }

    void doneBatch(ref Geometry g, ref const DataChunk data)
    {
        g.dataIndices.resize(g.positions.length, cast(ushort)dataStore.length);
        dataStore ~= data;
        advanceDepth();
    }

    void doneTexturedBatch(ref Geometry g, ref const DataChunk data)
    {
        g.dataIndices_textured.resize(g.positions_textured.length, cast(ushort)dataStore.length);
        dataStore ~= data;
        advanceDepth();
    }

    void advanceDepth()
    {
        layer.depth *= 0.999f;
    }

    DataChunk prepareDataChunk(const Mat2x3* m, float opacity)
    {
        // dfmt off
        return DataChunk(
            m ? *m : st.mat,
            layer.depth,
            0,
            Rect.from(st.clipRect),
            ColorF(0, 0, 0, opacity),
        );
        // dfmt on
    }

    bool convertBrush(const Brush* br, ref ShParams params, ref DataChunk data)
    {
        if (dataStore.length >= MAX_DATA_CHUNKS)
            return false;
        if (!br)
            return true; // PaintKind.empty

        final switch (br.type) with (BrushType)
        {
        case solid:
            return convertSolid(br.solid, params, data);
        case linear:
            return convertLinear(br.linear, params, data);
        case radial:
            return convertRadial(br.radial, params, data);
        case pattern:
            return convertPattern(br.pattern, params, data);
        }
    }

    bool convertSolid(Color cu, ref ShParams params, ref DataChunk data)
    {
        ColorF c = cu;
        c.a *= data.color.a; // opacity was stored here
        data.color = c.premultiplied;
        params.kind = PaintKind.solid;
        return true;
    }

    bool convertLinear(ref const LinearGradient grad, ref ShParams params, ref DataChunk data)
    in (grad.colors.length >= 2)
    {
        const start = data.transform * grad.start;
        const end = data.transform * grad.end;
        if (fequal2(start.x, end.x) && fequal2(start.y, end.y))
            return convertSolid(grad.colors[$ - 1], params, data);

        const count = grad.colors.length;
        const row = ColorStopAtlasRow(grad.colors);
        const atlasIndex = colorStopAtlas.add(row);
        // dfmt off
        params.kind = PaintKind.linear;
        params.linear = ParamsLG(
            start,
            end,
            grad.stops[0 .. count],
            colorStopAtlas.tex,
            atlasIndex,
        );
        // dfmt on
        return true;
    }

    bool convertRadial(ref const RadialGradient grad, ref ShParams params, ref DataChunk data)
    in (grad.colors.length >= 2)
    {
        const radius = (data.transform * Vec2(grad.radius, 0) - data.transform * Vec2(0)).length;
        if (fzero2(radius))
            return convertSolid(grad.colors[$ - 1], params, data);

        const center = data.transform * grad.center;

        const count = grad.colors.length;
        const row = ColorStopAtlasRow(grad.colors);
        const atlasIndex = colorStopAtlas.add(row);
        // dfmt off
        params.kind = PaintKind.radial;
        params.radial = ParamsRG(
            center,
            radius,
            grad.stops[0 .. count],
            colorStopAtlas.tex,
            atlasIndex,
        );
        // dfmt on
        return true;
    }

    bool convertPattern(ref const ImagePattern pat, ref ShParams params, ref DataChunk data)
    in (pat.image)
    {
        const TextureView view = textureCache.getTexture(*pat.image);
        if (view.empty)
            return false; // skip rendering

        // dfmt off
        params.kind = PaintKind.pattern;
        params.pattern = ParamsPattern(
            view.tex,
            view.texSize,
            view.box,
            (data.transform * pat.transform).inverted,
        );
        // dfmt on
        return true;
    }
}

void addFan(ref Buf!Tri output, uint vstart, size_t vcount)
in (vcount >= 2)
{
    const v0 = vstart;
    const tris = cast(uint)vcount - 2;
    output.reserve(output.length + tris);
    foreach (v; v0 .. v0 + tris)
        output ~= Tri(v0, v + 1, v + 2);
}

void addStrip(ref Buf!Tri output, uint vstart, size_t vcount)
in (vcount >= 2)
{
    const v0 = vstart;
    const tris = cast(uint)vcount - 2;
    output.reserve(output.length + tris);
    foreach (v; v0 .. v0 + tris)
        output ~= Tri(v, v + 1, v + 2);
}

final class TriBuilder : StrokeBuilder
{
nothrow:
    private
    {
        Buf!Vec2* positions;
        Buf!Tri* triangles;
        GpaaAppender contour;

        enum Mode
        {
            strip,
            fan
        }

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
        if (contour)
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

final class GpaaAppender
{
nothrow:
    private
    {
        Buf!uint indices;
        Buf!Vec2 positions;
        Buf!ushort dataIndices;

        uint istart;
    }

    void prepare()
    {
        indices.clear();
        dataIndices.clear();
        positions.clear();
        positions ~= Vec2(0, 0);
    }

    void add(const Vec2[] points)
    {
        begin();
        vs(points);
        const fst = points[0];
        const lst = points[$ - 1];
        if (!fequal2(fst.x, lst.x) || !fequal2(fst.y, lst.y))
            v(fst);
        end();
    }

    void begin()
    {
        istart = positions.length;
    }

    void end()
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
    {
        positions.put(v0);
    }

    void vs(const Vec2[] points)
    {
        positions.put(points);
    }

    void finish(uint dataIndex)
    {
        dataIndices.resize(positions.length, cast(ushort)dataIndex);
    }
}

struct GpaaAppenderPool
{
    private GpaaAppender[] pool;
    private uint engaged;

    GpaaAppender getFree()
    {
        GpaaAppender app;
        if (engaged < pool.length)
        {
            app = pool[engaged];
        }
        else
        {
            app = new GpaaAppender;
            pool ~= app;
        }
        engaged++;
        app.prepare();
        return app;
    }

    void reset()
    {
        engaged = 0;
    }
}

void ensureNotInGC(const Object object)
{
    import core.memory : GC;
    import core.stdc.stdio : fprintf, stderr;
    import beamui.core.functions : getShortClassName;

    // the old way of checking this obliterates assert messages
    static if (__VERSION__ >= 2090)
    {
        if (GC.inFinalizer())
        {
            const name = getShortClassName(object);
            fprintf(stderr, "Error: %.*s must be destroyed manually.\n", cast(int)name.length, name.ptr);
        }
    }
}
