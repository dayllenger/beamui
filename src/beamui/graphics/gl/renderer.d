/**
OpenGL (ES) 3 painter implementation, part 2.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.renderer;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
import bindbc.opengl.util : loadExtendedGLSymbol;

import beamui.core.collections : Buf;
import beamui.core.geometry;
import beamui.core.linalg;
import beamui.core.math;
import beamui.core.types : Tup, tup;
import beamui.graphics.colors : ColorF;
import beamui.graphics.compositing : BlendMode, CompositeOperation;
import beamui.graphics.gl.api;
import beamui.graphics.gl.errors;
import beamui.graphics.gl.gl;
import beamui.graphics.gl.objects;
import beamui.graphics.gl.program;
import beamui.graphics.gl.shaders;
import beamui.graphics.gl.stroke_tiling;
import beamui.graphics.painter : CustomSceneDelegate, MIN_RECT_I;

package nothrow:

enum MAX_DATA_CHUNKS = 2 ^^ 16;
enum MAX_LAYERS = 2 ^^ 12;

enum BatchType
{
    simple,
    twopass,
    tiled,
    custom,
}

enum Stenciling
{
    justCover,
    nonzero,
    zero,
    // complementary fill rules are currently an internal feature used by `clipIn`
    odd,
    even,
}

struct Span
{
    int start, end;
}

struct Batch
{
    BatchType type;
    BatchCommon common;
    union
    {
        BatchSimple simple;
        BatchTwoPass twopass;
        BatchCustom custom;
    }
}

struct BatchCommon
{
    ShParams params;
    Span triangles;
}

struct BatchSimple
{
    bool hasUV;
}

struct BatchTwoPass
{
    Span covers;
    Span coverTriangles;
    Stenciling stenciling;
}

struct BatchCustom
{
    uint scene;
    ComposeCmd cmd;
}

enum PaintKind
{
    empty,
    solid,
    linear,
    radial,
    pattern,
    image,
    text,
}

struct ShParams
{
    PaintKind kind;
    union
    {
        ParamsLG linear;
        ParamsRG radial;
        ParamsPattern pattern;
        ParamsImage image;
        ParamsText text;

        ParamsTiled tiled;
    }
}

/// Data chunks are copied directly into GPU buffer
struct DataChunk
{
    Mat2x3 transform;
    float depth = 0;
    float reserved = 0;
    Rect clipRect;
    ColorF color;
}

struct ComposeCmd
{
    Span triangles;
    CompositeOperation composition;
    BlendMode blending;
}

struct RenderLayer
{
    uint index;
    uint parent;

    RectI bounds = MIN_RECT_I;
    ColorF fill;

    ComposeCmd cmd;

    bool empty() const nothrow
    {
        return bounds.empty;
    }
}

/// In a set, batches can be rearranged
struct Set
{
    Span b_opaque;
    Span b_transp;
    Span dataChunks;
    uint layer;
    uint layerToCompose;
    bool finishing;
}

struct CustomScene
{
    CustomSceneDelegate deleg;
    SizeI size;
}

struct Tri
{
    uint v0, v1, v2;
}

struct DrawLists
{
    const(RenderLayer*)[] layers;
    const(Set)[] sets;
    const(Batch)[] b_opaque;
    const(Batch)[] b_transp;
}

struct GeometryToUpload
{
    const(Tri)[] tris;
    const(Vec2)[] pos1;
    const(ushort)[] dat1;
    const(Vec2)[] pos2;
    const(ushort)[] dat2;
    const(Vec2)[] uvs2;
}

struct DataToUpload
{
    GeometryToUpload opaque;
    GeometryToUpload transp;
    const(DataChunk)[] dataStore;

    const(PackedTile)[] strokeTiles;
    const(ushort)[] strokeTileDat;
}

private struct GPUGeometry
{
    VaoId vao;
    BufferId vboPos;
    BufferId vboDat;
    VaoId vaoTextured;
    BufferId vboTexturedPos;
    BufferId vboTexturedDat;
    BufferId vboTexturedUVs;
    BufferId ebo;
}

struct Renderer
{
nothrow:

    private
    {
        Device device;
        StdShaders* sh;
        FboId defaultFBO;

        RenderTargetPool rtpool;
        DataBuffer databuf;
        TileBuffer tilebuf;

        GPUGeometry g_opaque;
        GPUGeometry g_transp;

        VaoId vaoTiles;
        BufferId vboTiles;
        BufferId vboTileDat;

        Tup!(TexId, BoxI)[] renderedScenes;

        GpaaRenderer gpaa;

        bool advancedHardwareBlending;
        extern (C) void function() glBlendBarrierKHR;
        extern (C) void function(uint, uint) @nogc glVertexAttribDivisorARB;

        bool fail;
    }

    @disable this(this);

    void initialize(StdShaders* sh, GLuint defaultFBO)
    {
        this.sh = sh;
        this.defaultFBO = FboId(defaultFBO);

        // check the custom framebuffer
        if (defaultFBO != 0)
        {
            enum TARGET = GL_READ_FRAMEBUFFER;
            enum TYPE = GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE;

            assert(glIsFramebuffer(defaultFBO), "Not a framebuffer object");
            glBindFramebuffer(TARGET, defaultFBO);

            GLint[4] params;
            glGetFramebufferAttachmentParameteriv(TARGET, GL_COLOR_ATTACHMENT0, TYPE, &params[0]);
            glGetFramebufferAttachmentParameteriv(TARGET, GL_DEPTH_ATTACHMENT, TYPE, &params[1]);
            glGetFramebufferAttachmentParameteriv(TARGET, GL_STENCIL_ATTACHMENT, TYPE, &params[2]);
            glGetFramebufferAttachmentParameteriv(TARGET, GL_DEPTH_STENCIL_ATTACHMENT, TYPE, &params[3]);
            const hasColor = params[0] != GL_NONE;
            const hasDepth = params[1] != GL_NONE || params[3] != GL_NONE;
            const hasStencil = params[2] != GL_NONE || params[3] != GL_NONE;
            assert(hasColor && hasDepth && hasStencil, "Framebuffer must have color, depth, and stencil attachments");
            assert(checkFramebuffer(TARGET));

            glBindFramebuffer(TARGET, 0);
        }

        if (device.hasExtension("GL_ARB_instanced_arrays"))
        {
            try
                loadExtendedGLSymbol(cast(void**)&glVertexAttribDivisorARB, "glVertexAttribDivisorARB");
            catch (Exception e)
                assert(0);
        }
        if (!glVertexAttribDivisorARB)
            return failGracefully();

        foreach (g; tup(&g_opaque, &g_transp))
        {
            VBO.bind(g.vboPos);
            VBO.bind(g.vboDat);
            VBO.bind(g.vboTexturedPos);
            VBO.bind(g.vboTexturedDat);
            VBO.bind(g.vboTexturedUVs);
        }
        VBO.bind(vboTiles);
        VBO.bind(vboTileDat);
        VBO.unbind();

        foreach (g; tup(&g_opaque, &g_transp))
            EBO.bind(g.ebo);
        EBO.unbind();

        foreach (g; tup(&g_opaque, &g_transp))
        {
            device.vaoman.bind(g.vao);
            VBO.bind(g.vboPos);
            device.vaoman.addAttribF(0, 2);
            VBO.bind(g.vboDat);
            device.vaoman.addAttribU16(1, 1);
            EBO.bind(g.ebo);

            device.vaoman.bind(g.vaoTextured);
            VBO.bind(g.vboTexturedPos);
            device.vaoman.addAttribF(0, 2);
            VBO.bind(g.vboTexturedDat);
            device.vaoman.addAttribU16(1, 1);
            VBO.bind(g.vboTexturedUVs);
            device.vaoman.addAttribF(2, 2);
            EBO.bind(g.ebo);
        }
        device.vaoman.bind(vaoTiles);
        glVertexAttribDivisorARB(0, 1);
        glVertexAttribDivisorARB(1, 1);
        glVertexAttribDivisorARB(2, 1);

        device.vaoman.unbind();

        databuf.initialize();
        tilebuf.initialize();
        gpaa.initialize(device);

        if (device.hasExtension("GL_KHR_blend_equation_advanced"))
        {
            advancedHardwareBlending = true;
            try
                loadExtendedGLSymbol(cast(void**)&glBlendBarrierKHR, "glBlendBarrierKHR");
            catch (Exception e)
                assert(0);
        }
    }

    ~this()
    {
        rtpool.purge(device.fboman);
        gpaa.deinitialize(device);

        foreach (g; tup(&g_opaque, &g_transp))
        {
            device.vaoman.del(g.vao);
            device.vaoman.del(g.vaoTextured);
            VBO.del(g.vboPos);
            VBO.del(g.vboDat);
            VBO.del(g.vboTexturedPos);
            VBO.del(g.vboTexturedDat);
            VBO.del(g.vboTexturedUVs);
            EBO.del(g.ebo);
        }
        device.vaoman.del(vaoTiles);
        VBO.del(vboTiles);
        VBO.del(vboTileDat);
    }

    void upload(const DataToUpload data, const GpaaDataToUpload[] gpaaData, ref const TileGrid tileGrid)
    {
        if (fail)
            return;

        foreach (pair; tup(tup(&data.opaque, &g_opaque), tup(&data.transp, &g_transp)))
        {
            if (pair[0].tris.length)
            {
                assert(pair[0].pos1.length || pair[0].pos2.length);
                assert(pair[0].pos1.length == pair[0].dat1.length);
                assert(pair[0].pos2.length == pair[0].dat2.length);
                assert(pair[0].pos2.length == pair[0].uvs2.length);

                EBO.bind(pair[1].ebo);
                EBO.upload(pair[0].tris, GL_DYNAMIC_DRAW);
                VBO.bind(pair[1].vboPos);
                VBO.upload(pair[0].pos1, GL_DYNAMIC_DRAW);
                VBO.bind(pair[1].vboDat);
                VBO.upload(pair[0].dat1, GL_DYNAMIC_DRAW);
                VBO.bind(pair[1].vboTexturedPos);
                VBO.upload(pair[0].pos2, GL_DYNAMIC_DRAW);
                VBO.bind(pair[1].vboTexturedDat);
                VBO.upload(pair[0].dat2, GL_DYNAMIC_DRAW);
                VBO.bind(pair[1].vboTexturedUVs);
                VBO.upload(pair[0].uvs2, GL_DYNAMIC_DRAW);
            }
        }
        if (data.strokeTiles.length)
        {
            VBO.bind(vboTiles);
            VBO.upload(data.strokeTiles, GL_DYNAMIC_DRAW);
            VBO.bind(vboTileDat);
            VBO.upload(data.strokeTileDat, GL_DYNAMIC_DRAW);
        }
        databuf.upload(data.dataStore);
        tilebuf.upload(tileGrid);
        gpaa.upload(gpaaData);
    }

    bool render(const DrawLists lists, CustomScene[] scenes)
    {
        if (fail)
            return false;

        // render custom scenes before touching GL state
        if (scenes.length)
        {
            renderedScenes = new Tup!(TexId, BoxI)[scenes.length];
            foreach (i, scene; scenes)
            {
                const tex = scene.deleg.render(scene.size);
                const valid = tex.id && glIsTexture(cast(GLuint)tex.id);
                assert(valid, "Invalid texture returned from the scene delegate");
                renderedScenes[i] = tup(TexId(cast(GLuint)tex.id), BoxI(tex.origin, scene.size));
            }
        }

        prepare();

        static struct LayerInfo
        {
            RenderTarget rt;
            bool dirty = true;
            Buf!(const(Batch)*) clips;
        }

        LayerInfo[] infos = new LayerInfo[lists.layers.length];
        infos[0].rt.fbo = defaultFBO;
        infos[0].rt.box = BoxI(lists.layers[0].bounds);

        foreach (i, ref set; lists.sets)
        {
            const RenderLayer* lr = lists.layers[set.layer];
            if (lr.empty)
                continue;
            if (infos[lr.parent].rt.empty)
                continue;

            // get a render target
            LayerInfo* info = &infos[lr.index];
            RenderTarget* rt = &info.rt;
            if (rt.empty)
            {
                *rt = rtpool.take(device.fboman, lr.bounds.size);
                if (rt.empty)
                    continue;
            }
            // setup the framebuffer
            if (device.fboman.bind(rt.fbo))
                glViewport(rt.box.x, rt.box.y, rt.box.w, rt.box.h);
            // clear it
            if (info.dirty)
            {
                device.clear(rt.box, lr.fill);
                info.dirty = false;
            }

            // now it's time to draw actual batches
            const Batch[] b_opaque = lists.b_opaque[set.b_opaque.start .. set.b_opaque.end];
            const Batch[] b_transp = lists.b_transp[set.b_transp.start .. set.b_transp.end];
            const pbase = ParamsBase(Vec2(1.0f / rt.box.w, 1.0f / rt.box.h), rt.box.h, databuf.tex);
            // draw opaque first front-to-back
            const flagsOpq = DrawFlags.clippingPlanes | DrawFlags.depthTest;
            foreach_reverse (ref bt; b_opaque)
            {
                drawBatch(g_opaque, bt, pbase, flagsOpq);
                if (bt.common.params.kind == PaintKind.empty)
                    info.clips ~= &bt;
            }
            // compose layer if some
            if (set.layerToCompose > 0)
            {
                const RenderLayer* lrCompose = lists.layers[set.layerToCompose];
                RenderTarget* rtCompose = &infos[set.layerToCompose].rt;
                if (!rtCompose.empty)
                {
                    const params = ParamsComposition(rtCompose.tex, rtCompose.box);
                    compose(lrCompose.cmd, pbase, params);
                    rtpool.remove(rtCompose.id);
                    *rtCompose = RenderTarget.init;
                }
            }
            // draw transparent back-to-front without writing to depth
            const flagsTrt = flagsOpq | DrawFlags.blending | DrawFlags.noDepthWrite;
            foreach (ref bt; b_transp)
            {
                drawBatch(g_transp, bt, pbase, flagsTrt);
            }
            if (fail)
                break;

            // antialias the layer
            if (set.finishing && gpaa.hasSomething)
            {
                // remove clipping
                if (info.clips.length)
                {
                    auto prog = sh.empty;
                    device.progman.bind(prog);
                    prog.prepare(pbase, true);

                    glDepthFunc(GL_ALWAYS);

                    foreach (bt; info.clips[])
                        drawDepthResetBatch(g_opaque, *bt);

                    glDepthFunc(GL_LEQUAL);
                }
                if (auto prog = sh.gpaa)
                {
                    gpaa.perform(device, set.layer, rt.box, prog, pbase);
                }
                else
                {
                    failGracefully();
                    break;
                }
            }
        }

        infos[] = LayerInfo.init;

        reset();

        return !fail;
    }

private:

    void prepare()
    {
        device.initialize(DrawFlags.clippingPlanes | DrawFlags.depthTest);

        glDepthFunc(GL_LEQUAL);
        glClearDepth(1.0);
        glClearStencil(0);
        glStencilMask(0xFF);
    }

    void reset()
    {
        rtpool.reset();

        // reset touched state to correctly draw custom OpenGL scene and the like
        device.reset();

        VBO.unbind();
        EBO.unbind();
        Tex2D.unbind();

        glClearColor(0, 0, 0, 0);
        glDepthFunc(GL_LESS);
        glStencilFunc(GL_ALWAYS, 0, 0xFF);
        glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
    }

    void drawBatch(ref GPUGeometry g, ref const Batch bt, ref const ParamsBase pbase, DrawFlags flags)
    {
        final switch (bt.type) with (BatchType)
        {
        case simple:
            if (!setupSurfaceShader(pbase, bt.common.params))
                return failGracefully();

            performSimple(g, bt.simple.hasUV, bt.common.triangles, flags);
            break;
        case twopass:
            if (auto prog = sh.empty)
            {
                device.progman.bind(prog);
                prog.prepare(pbase, false);
            }
            else
                return failGracefully();

            const flagsSt = flags | DrawFlags.stencilTest;
            // no depth test -> no depth write
            const flags1stPass = (flagsSt | DrawFlags.noColorWrite) & ~DrawFlags.depthTest;
            const BatchTwoPass m = bt.twopass;
            performStencil(g, m.stenciling, bt.common.triangles, flags1stPass);

            if (!setupSurfaceShader(pbase, bt.common.params))
                return failGracefully();

            performCover(g, m.stenciling, m.coverTriangles, flagsSt);
            break;
        case tiled:
            performTiled(pbase, bt.common.params, bt.common.triangles, flags);
            break;
        case custom:
            const view = renderedScenes[bt.custom.scene];
            const params = ParamsComposition(view[0], view[1]);
            compose(bt.custom.cmd, pbase, params);
            break;
        }
    }

    void drawDepthResetBatch(ref GPUGeometry g, ref const Batch bt)
    {
        enum flags = DrawFlags.clippingPlanes | DrawFlags.depthTest | DrawFlags.noColorWrite;
        enum flagsSt = flags | DrawFlags.stencilTest;

        switch (bt.type) with (BatchType)
        {
        case simple:
            performSimple(g, bt.simple.hasUV, bt.common.triangles, flags);
            break;
        case twopass:
            const BatchTwoPass m = bt.twopass;
            performStencil(g, m.stenciling, bt.common.triangles, flagsSt & ~DrawFlags.depthTest);
            performCover(g, m.stenciling, m.coverTriangles, flagsSt);
            break;
        default:
            assert(0);
        }
    }

    void performSimple(ref GPUGeometry g, bool hasUV, Span tris, DrawFlags flags)
    {
        const vao = hasUV ? g.vaoTextured : g.vao;
        device.drawTriangles(vao, flags, tris.start * 3, (tris.end - tris.start) * 3);
    }

    void performStencil(ref GPUGeometry g, Stenciling type, Span tris, DrawFlags flags)
    {
        final switch (type) with (Stenciling)
        {
        case justCover:
            glStencilFunc(GL_ALWAYS, 1, 0);
            glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
            break;
        case nonzero:
        case zero:
            glStencilFunc(GL_ALWAYS, 0, 0);
            glStencilOpSeparate(GL_FRONT, GL_KEEP, GL_KEEP, GL_INCR_WRAP);
            glStencilOpSeparate(GL_BACK, GL_KEEP, GL_KEEP, GL_DECR_WRAP);
            break;
        case odd:
        case even:
            glStencilFunc(GL_ALWAYS, 0, 0);
            glStencilOp(GL_KEEP, GL_KEEP, GL_INCR_WRAP);
            break;
        }

        device.drawTriangles(g.vao, flags, tris.start * 3, (tris.end - tris.start) * 3);
    }

    void performCover(ref GPUGeometry g, Stenciling type, Span tris, DrawFlags flags)
    {
        final switch (type) with (Stenciling)
        {
        case justCover:
            glStencilFunc(GL_EQUAL, 1, 0xFF);
            glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
            break;
        case nonzero:
            glStencilFunc(GL_NOTEQUAL, 0, 0xFF);
            glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
            break;
        case zero:
            glStencilFunc(GL_EQUAL, 0, 0xFF);
            glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
            break;
        case odd:
            glStencilFunc(GL_NOTEQUAL, 0, 0x1);
            glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
            break;
        case even:
            glStencilFunc(GL_EQUAL, 0, 0x1);
            glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);
            break;
        }

        device.drawTriangles(g.vao, flags, tris.start * 3, (tris.end - tris.start) * 3);
    }

    bool setupSurfaceShader(ref const ParamsBase base, ref const ShParams params)
    {
        final switch (params.kind) with (PaintKind)
        {
        case empty:
            if (auto prog = sh.empty)
            {
                device.progman.bind(prog);
                prog.prepare(base, false);
                return true;
            }
            return false;
        case solid:
            if (auto prog = sh.solid)
            {
                device.progman.bind(prog);
                prog.prepare(base);
                return true;
            }
            return false;
        case linear:
            if (auto prog = sh.linear)
            {
                device.progman.bind(prog);
                prog.prepare(base, params.linear);
                return true;
            }
            return false;
        case radial:
            if (auto prog = sh.radial)
            {
                device.progman.bind(prog);
                prog.prepare(base, params.radial);
                return true;
            }
            return false;
        case pattern:
            if (auto prog = sh.pattern)
            {
                device.progman.bind(prog);
                prog.prepare(base, params.pattern);
                return true;
            }
            return false;
        case image:
            if (auto prog = sh.image)
            {
                device.progman.bind(prog);
                prog.prepare(base, params.image);
                return true;
            }
            return false;
        case text:
            if (auto prog = sh.text)
            {
                device.progman.bind(prog);
                prog.prepare(base, params.text);
                return true;
            }
            return false;
        }
    }

    void performTiled(ref const ParamsBase pbase, ref const ShParams params, Span points, DrawFlags flags)
    {
        if (points.start >= points.end)
            return;

        if (auto prog = sh.solidStroke)
        {
            ParamsTiled ptiled = params.tiled;
            ptiled.buf_segments = tilebuf.buf_segments;
            device.progman.bind(prog);
            prog.prepare(pbase, ptiled);
        }
        else
            return failGracefully();

        device.vaoman.bind(vaoTiles);
        VBO.bind(vboTiles);
        device.vaoman.addAttribU16(0, 2, 8, points.start * 8 + 0);
        device.vaoman.addAttribU32(1, 1, 8, points.start * 8 + 4);
        VBO.bind(vboTileDat);
        device.vaoman.addAttribU16(2, 1, 2, points.start * 2);
        device.drawInstancedQuads(vaoTiles, flags, points.end - points.start);
    }

    void compose(ref const ComposeCmd cmd, ref const ParamsBase pbase, ref const ParamsComposition params)
    {
        if (cmd.blending != BlendMode.normal && advancedHardwareBlending && sh.blend)
        {
            device.progman.bind(sh.blend);
            sh.blend.prepare(pbase, params);
            device.setAdvancedBlending(cmd.blending);
            glBlendBarrierKHR();
        }
        else
        {
            auto prog = sh.compose;
            if (!prog)
                return failGracefully();

            device.progman.bind(prog);
            prog.prepare(pbase, params);
            device.setBlending(cmd.composition);
        }

        const g = &g_transp;
        const flags = DrawFlags.blending | DrawFlags.clippingPlanes | DrawFlags.depthTest | DrawFlags.noDepthWrite;
        device.drawTriangles(g.vao, flags, cmd.triangles.start * 3, (cmd.triangles.end - cmd.triangles.start) * 3);
        device.resetBlending();
    }

    void failGracefully()
    {
        fail = true;
    }
}

private struct DataBuffer
{
nothrow:
    enum ROW_LENGTH = 256;
    enum TEXELS_IN_CHUNK = 4;
    enum WIDTH = ROW_LENGTH * TEXELS_IN_CHUNK;
    static assert(DataChunk.sizeof == TEXELS_IN_CHUNK * 16);

    // for now, I store the data simply in a texture
    TexId tex;

    @disable this(this);

    void initialize()
    {
        Tex2D.bind(tex);
        Tex2D.setBasicParams(TexFiltering.sharp, TexMipmaps.no, TexWrap.clamp);
        Tex2D.unbind();
    }

    ~this()
    {
        Tex2D.del(tex);
    }

    private int rows;

    void upload(const DataChunk[] dataStore)
    {
        if (dataStore.length == 0)
            return;

        const fmt = TexFormat(GL_RGBA, GL_RGBA32F, GL_FLOAT);
        Tex2D.bind(tex);
        Tex2D.upload1D(fmt, rows, ROW_LENGTH, TEXELS_IN_CHUNK, dataStore[]);
        Tex2D.unbind();
    }
}

private struct RenderTarget
{
    uint id;
    FboId fbo;
    TexId tex;
    BoxI box;

    bool empty() const nothrow
    {
        return box.empty;
    }
}

private struct RenderTargetPool
{
nothrow:

    enum INITIAL_SIZE = SizeI(16, 16);
    enum MAX_SIZE = SizeI(4096, 4096);
    enum MAX_PAGES = 16;

    private struct Page
    {
        uint id; /// Non-zero means it's in use
        FboId fbo;
        TexId colorTex;
        RbId depthRB;
        SizeI size;
    }

    private Page[MAX_PAGES] pages;

    @disable this(this);

    // use `purge` to clear it
    ~this()
    {
        assert(pages[0].fbo.handle == 0);
    }

    RenderTarget take(ref FboManager man, SizeI size)
    in (size.w > 0 && size.h > 0)
    {
        import std.random : uniform;

        if (size.w > MAX_SIZE.w || size.h > MAX_SIZE.h)
            return RenderTarget.init;

        // search in free pages
        foreach (ref page; pages)
        {
            if (page.id > 0)
                continue;

            // get a random id
            uint id;
            try
                id = uniform(1, uint.max);
            catch (Exception e)
                assert(0);

            // create or resize the page framebuffer
            if (!preparePage(man, page, size))
                break;

            page.id = id;
            return RenderTarget(id, page.fbo, page.colorTex, BoxI(0, 0, size.w, size.h));
        }
        // no pages anymore
        return RenderTarget.init;
    }

    void remove(uint id)
    {
        if (!id)
            return;

        foreach (ref page; pages)
        {
            if (page.id == id)
            {
                page.id = 0;
                return;
            }
        }
    }

    void reset()
    {
        foreach (ref page; pages)
        {
            page.id = 0;
        }
    }

    void purge(ref FboManager man)
    {
        foreach (ref page; pages)
        {
            if (page.fbo.handle)
                man.del(page.fbo);
            if (page.colorTex.handle)
                Tex2D.del(page.colorTex);
            if (page.depthRB.handle)
                DepthStencilRB.del(page.depthRB);
        }
    }

    static private bool preparePage(ref FboManager man, ref Page page, SizeI requiredSize)
    {
        const size = choosePageSize(page.size, requiredSize);
        const fmt = TexFormat(GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE);
        if (page.fbo.handle)
        {
            if (page.size == size)
                return true;

            Tex2D.bind(page.colorTex);
            Tex2D.resize(size, 0, fmt);
            Tex2D.unbind();
            DepthStencilRB.bind(page.depthRB);
            DepthStencilRB.resize(size);
            DepthStencilRB.unbind();
            page.size = size;
            return true;
        }
        else
        {
            TexId ct;
            RbId drb;
            Tex2D.bind(ct);
            Tex2D.setBasicParams(TexFiltering.sharp, TexMipmaps.no, TexWrap.clamp);
            Tex2D.resize(size, 0, fmt);
            Tex2D.unbind();
            DepthStencilRB.bind(drb);
            DepthStencilRB.resize(size);
            DepthStencilRB.unbind();

            FboId fbo = man.create();
            man.bind(fbo);
            man.attachColorTex2D(ct, 0);
            man.attachDepthStencilRB(drb);
            const ready = checkFramebuffer();
            if (ready)
            {
                man.bind(FboId.init);
                page.fbo = fbo;
                page.colorTex = ct;
                page.depthRB = drb;
                page.size = size;
            }
            else
            {
                man.bind(FboId.init);
                man.del(fbo);
                Tex2D.del(ct);
                DepthStencilRB.del(drb);
            }
            return ready;
        }
    }

    static private SizeI choosePageSize(SizeI curr, SizeI req)
    {
        curr.w = max(curr.w, INITIAL_SIZE.w);
        curr.h = max(curr.h, INITIAL_SIZE.h);

        while (curr.w < req.w)
            curr.w *= 2;
        while (curr.h < req.h)
            curr.h *= 2;

        return curr;
    }
}

struct GpaaDataToUpload
{
    const(uint)[] ids;
    const(Vec2)[] pos;
    const(ushort)[] dat;
    SizeI viewSize;
}

/** Client code for geometric post-process anti-aliasing.

    The idea belongs to Humus: $(LINK http://www.humus.name/index.php?page=3D&ID=86)
*/
private struct GpaaRenderer
{
nothrow:
    private
    {
        VaoId vao;
        BufferId vboPos;
        BufferId vboDat;
        BufferId ebo;
        TexId tex;
        SizeI texSize;

        Buf!Span layers;
        Buf!uint indices;
        Buf!Vec2 positions;
        Buf!ushort dataIndices;
    }

    @disable this(this);

    ~this()
    {
        assert(!vao.handle);
    }

    void initialize(ref Device device)
    {
        VBO.bind(vboPos);
        VBO.bind(vboDat);
        VBO.unbind();

        EBO.bind(ebo);
        EBO.unbind();

        device.vaoman.bind(vao);
        VBO.bind(vboPos);
        device.vaoman.addAttribF(0, 2);
        device.vaoman.addAttribF(1, 2, 0, Vec2.sizeof);
        VBO.bind(vboDat);
        device.vaoman.addAttribU16(2, 1, 0, ushort.sizeof);
        EBO.bind(ebo);
        device.vaoman.unbind();

        Tex2D.bind(tex);
        Tex2D.setBasicParams(TexFiltering.smooth, TexMipmaps.no, TexWrap.clamp); // must be linear
        Tex2D.resize(SizeI(1, 1), 0, TexFormat(GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE));
        Tex2D.unbind();
    }

    void deinitialize(ref Device device)
    {
        device.vaoman.del(vao);
        VBO.del(vboPos);
        VBO.del(vboDat);
        EBO.del(ebo);
        Tex2D.del(tex);
    }

    void upload(const GpaaDataToUpload[] byLayer)
    {
        layers.clear();
        indices.clear();
        positions.clear();
        dataIndices.clear();

        bool empty = true;
        foreach (ref data; byLayer)
        {
            if (data.ids.length && data.viewSize.w > 0 && data.viewSize.h > 0)
            {
                empty = false;
                break;
            }
        }
        if (empty)
            return;

        SizeI maxSize;
        foreach (ref data; byLayer)
        {
            const span = Span(cast(int)indices.length, cast(int)(indices.length + data.ids.length));
            layers ~= span;
            if (span.start == span.end)
                continue;

            indices ~= data.ids;
            indices.unsafe_slice[span.start .. span.end] += positions.length;
            positions ~= data.pos;
            dataIndices ~= data.dat;
            maxSize.w = max(maxSize.w, data.viewSize.w);
            maxSize.h = max(maxSize.h, data.viewSize.h);
        }

        assert(positions.length);
        assert(positions.length == dataIndices.length);

        EBO.bind(ebo);
        EBO.upload(indices[], GL_DYNAMIC_DRAW);
        VBO.bind(vboPos);
        VBO.upload(positions[], GL_DYNAMIC_DRAW);
        VBO.bind(vboDat);
        VBO.upload(dataIndices[], GL_DYNAMIC_DRAW);

        // resize the temporary texture if needed to
        const sz = chooseTargetSize(texSize, maxSize);
        if (texSize != sz)
        {
            texSize = sz;
            Tex2D.bind(tex);
            Tex2D.resize(sz, 0, TexFormat(GL_RGBA, GL_RGBA8, GL_UNSIGNED_BYTE));
            Tex2D.unbind();
        }
    }

    bool hasSomething() const
    {
        return indices.length > 0;
    }

    void perform(ref Device device, uint layerIndex, BoxI viewBox, ShaderGPAA shader, ParamsBase pbase)
    {
        const span = layers[layerIndex];
        if (span.start == span.end)
            return;

        // copy the current framebuffer contents into the texture
        Tex2D.bind(tex);
        checkgl!glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, viewBox.x, viewBox.y, viewBox.w, viewBox.h);

        const params = ParamsGPAA(tex, Vec2(1.0f / texSize.w, 1.0f / texSize.h));
        device.progman.bind(shader);
        shader.prepare(pbase, params);

        const flags = DrawFlags.clippingPlanes | DrawFlags.depthTest | DrawFlags.noDepthWrite;
        device.drawLines(vao, flags, span.start, span.end - span.start);
    }
}

/// Choose appropriate framebuffer texture size after possible window resize
private SizeI chooseTargetSize(SizeI current, SizeI resized)
in (resized.w > 0 && resized.h > 0)
{
    // bad case
    if (current.w <= 0)
        current.w = 16;
    if (current.h <= 0)
        current.h = 16;
    // became significantly shorter
    if (resized.w * 8 < current.w)
        current.w /= 8;
    if (resized.h * 8 < current.h)
        current.h /= 8;
    // became larger
    while (current.w < resized.w)
        current.w *= 2;
    while (current.h < resized.h)
        current.h *= 2;

    return current;
}
