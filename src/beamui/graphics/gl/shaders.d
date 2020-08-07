/**
Client code for standard shaders.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.shaders;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
import std.conv : to;
import beamui.core.functions : eliminate;
import beamui.core.geometry : BoxI, SizeI;
import beamui.core.linalg : Mat2x3, Vec2;
import beamui.graphics.colors : ColorF;
import beamui.graphics.gl.api;
import beamui.graphics.gl.objects : Tex2D, TexId;
import beamui.graphics.gl.program;
import beamui.graphics.gl.stroke_tiling : TILE_SIZE, TileBuffer;

package:

/// Contains all standard shaders. They are compiled on demand, so every getter may return `null`
struct StdShaders
{
nothrow:
    private
    {
        ShaderEmpty _empty;
        ShaderSolid _solid;
        ShaderLinear _linear;
        ShaderRadial _radial;
        ShaderPattern _pattern;
        ShaderImage _image;
        ShaderText _text;
        ShaderCompose _compose;
        ShaderBlend _blend;
        ShaderGPAA _gpaa;

        ShaderSolidStroke _solidStroke;
    }

    @disable this(this);
    // dfmt off
    ShaderEmpty     empty() { return take(_empty); }
    ShaderSolid     solid() { return take(_solid); }
    ShaderLinear   linear() { return take(_linear); }
    ShaderRadial   radial() { return take(_radial); }
    ShaderPattern pattern() { return take(_pattern); }
    ShaderImage     image() { return take(_image); }
    ShaderText       text() { return take(_text); }
    ShaderCompose compose() { return take(_compose); }
    ShaderBlend     blend() { return take(_blend); }
    ShaderGPAA       gpaa() { return take(_gpaa); }

    ShaderSolidStroke solidStroke() { return take(_solidStroke); }
    // dfmt on

    // non-cached compilation of all the shaders may take 200 ms or more,
    // so we won't compile until it's really needed
    private T take(T : GLProgram)(ref T prog)
    {
        if (!prog)
            prog = new T;
        return prog.isValid ? prog : null;
    }

    ~this()
    {
        static foreach (sh; typeof(this).tupleof)
            eliminate(sh);
    }
}

struct ParamsBase
{
    Vec2 pixelSize;
    int viewportHeight;
    TexId dataStore;
}

struct ParamsLG
{
    Vec2 start;
    Vec2 end;
    const(float)[] stops;
    TexId colors;
    uint atlasIndex;
}

struct ParamsRG
{
    Vec2 center;
    float radius = 0;
    const(float)[] stops;
    TexId colors;
    uint atlasIndex;
}

struct ParamsPattern
{
    const(TexId)* tex;
    const(SizeI)* texSize;
    BoxI patRect;
    Mat2x3 matrix;
}

struct ParamsTiled
{
    TexId buf_segments;
}

struct ParamsImage
{
    const(TexId)* tex;
    const(SizeI)* texSize;
}

struct ParamsText
{
    const(TexId)* tex;
    const(SizeI)* texSize;
}

struct ParamsComposition
{
    TexId tex;
    BoxI box;
}

struct ParamsGPAA
{
    TexId tex;
    Vec2 texPixelSize;
}

private enum SamplerIndex
{
    data,
    colors,
    texture,
    segments,
}

private struct Locations(string[] names)
{
nothrow:
    static foreach (name; names)
        mixin("GLint " ~ name ~ ";");

    bool initialize(const GLProgramInterface pi)
    {
        // retrieve all uniform locations, fail if not found
        static foreach (m; typeof(this).tupleof)
        {
            m = pi.getUniformLocation(__traits(identifier, m));
            if (m < 0)
                return false;
        }
        return true;
    }
}

abstract class ShaderBase : GLProgram
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        const vs = import("base.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        return [ShaderStage.vertex : vs];
    }

    override protected bool beforeLinking(const GLProgramInterface pi)
    {
        pi.bindAttribLocation("v_position", 0);
        pi.bindAttribLocation("v_dataIndex", 1);
        return true;
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return loc.initialize(pi);
    }

    private void prepare(ref const ParamsBase p)
    {
        glUniform2f(loc.pixelSize, p.pixelSize.x, p.pixelSize.y);

        glUniform1i(loc.dataStore, SamplerIndex.data);
        Tex2D.setup(p.dataStore, SamplerIndex.data);
    }

    private Locations!(["pixelSize", "dataStore"]) loc;
}

final class ShaderEmpty : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        enum def1 = "#define NO_COLOR\n";
        const vs = def1 ~ import("base.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = "void main() {}";
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase p, bool resetDepth)
    {
        super.prepare(p);
        glUniform1f(loc.customDepth, resetDepth ? 1.0f : 0.0f);
    }

    private Locations!(["customDepth"]) loc;
}

final class ShaderSolid : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        enum def1 = "#define DATA_COLOR\n";
        const vs = def1 ~ import("base.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = import("solid.fs.glsl");
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    void prepare(ref const ParamsBase pbase)
    {
        super.prepare(pbase);
    }
}

final class ShaderLinear : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        auto map = super.sources;
        map[ShaderStage.fragment] = import("linear.fs.glsl") ~ import("gradients.inc.glsl");
        return map;
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsLG p)
    {
        super.prepare(pbase);
        const len = cast(int)p.stops.length;
        glUniform1i(loc.viewportHeight, pbase.viewportHeight);
        glUniform2f(loc.start, p.start.x, p.start.y);
        glUniform2f(loc.end, p.end.x, p.end.y);
        glUniform1i(loc.stopsCount, len);
        glUniform1fv(loc.stops, len, p.stops.ptr);
        glUniform1ui(loc.atlasIndex, p.atlasIndex);

        glUniform1i(loc.colors, SamplerIndex.colors);
        Tex2D.setup(p.colors, SamplerIndex.colors);
    }

    // dfmt off
    private Locations!([
        "viewportHeight", "start", "end", "stopsCount", "stops", "colors", "atlasIndex"
    ]) loc;
    // dfmt on
}

final class ShaderRadial : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        auto map = super.sources;
        map[ShaderStage.fragment] = import("radial.fs.glsl") ~ import("gradients.inc.glsl");
        return map;
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsRG p)
    {
        super.prepare(pbase);
        const len = cast(int)p.stops.length;
        glUniform1i(loc.viewportHeight, pbase.viewportHeight);
        glUniform2f(loc.center, p.center.x, p.center.y);
        glUniform1f(loc.radius, p.radius);
        glUniform1i(loc.stopsCount, len);
        glUniform1fv(loc.stops, len, p.stops.ptr);
        glUniform1ui(loc.atlasIndex, p.atlasIndex);

        glUniform1i(loc.colors, SamplerIndex.colors);
        Tex2D.setup(p.colors, SamplerIndex.colors);
    }

    // dfmt off
    private Locations!([
        "viewportHeight", "center", "radius", "stopsCount", "stops", "colors", "atlasIndex"
    ]) loc;
    // dfmt on
}

final class ShaderPattern : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        auto map = super.sources;
        map[ShaderStage.fragment] = import("pattern.fs.glsl");
        return map;
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsPattern p)
    in (p.tex && p.texSize)
    {
        super.prepare(pbase);
        glUniform1i(loc.viewportHeight, pbase.viewportHeight);
        const sz = *p.texSize;
        const b = p.patRect;
        const x = b.x / cast(float)sz.w;
        const y = b.y / cast(float)sz.h;
        const w = b.w / cast(float)sz.w;
        const h = b.h / cast(float)sz.h;
        glUniform2f(loc.position, x, y);
        glUniform2f(loc.size, w, h);
        glUniform2i(loc.imgSize, b.w, b.h);
        glUniformMatrix3x2fv(loc.matrix, 1, GL_TRUE, p.matrix.ptr);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(*p.tex, SamplerIndex.texture);
    }

    // dfmt off
    private Locations!([
        "viewportHeight", "tex", "position", "size", "imgSize", "matrix"
    ]) loc;
    // dfmt on
}

final class ShaderSolidStroke : GLProgram
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        enum def1 = "#define DATA_COLOR\n";
        enum def2 = "#define TILED_STROKE\n";
        enum def3 = "#define TILE_SIZE " ~ to!string(TILE_SIZE) ~ ".0\n";
        enum def4 = "#define ROW_LENGTH " ~ to!string(TileBuffer.ROW_LENGTH) ~ "\n";
        const vs = def1 ~ def3 ~ import("tiled.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = def2 ~ def3 ~ def4 ~ import("stroke-sdf.inc.glsl") ~ import("solid.fs.glsl");
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    override protected bool beforeLinking(const GLProgramInterface pi)
    {
        pi.bindAttribLocation("v_tile", 0);
        pi.bindAttribLocation("v_segments", 1);
        pi.bindAttribLocation("v_dataIndex", 2);
        return true;
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsTiled p)
    {
        glUniform2f(loc.pixelSize, pbase.pixelSize.x, pbase.pixelSize.y);
        glUniform1i(loc.viewportHeight, pbase.viewportHeight);

        glUniform1i(loc.dataStore, SamplerIndex.data);
        Tex2D.setup(pbase.dataStore, SamplerIndex.data);
        glUniform1i(loc.buf_segments, SamplerIndex.segments);
        Tex2D.setup(p.buf_segments, SamplerIndex.segments);
    }

    private Locations!(["pixelSize", "viewportHeight", "buf_segments", "dataStore"]) loc;
}

final class ShaderImage : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        enum defs = "#define UV\n";
        const vs = defs ~ import("base.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = import("image.fs.glsl");
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    override protected bool beforeLinking(const GLProgramInterface pi)
    {
        pi.bindAttribLocation("v_texCoord", 2);
        return super.beforeLinking(pi);
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsImage p)
    in (p.tex && p.texSize)
    {
        super.prepare(pbase);
        glUniform2f(loc.texPixelSize, 1.0f / p.texSize.w, 1.0f / p.texSize.h);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(*p.tex, SamplerIndex.texture);
    }

    private Locations!(["texPixelSize", "tex"]) loc;
}

final class ShaderText : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        enum defs = "#define DATA_COLOR\n" ~ "#define UV\n";
        const vs = defs ~ import("base.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = import("text.fs.glsl");
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    override protected bool beforeLinking(const GLProgramInterface pi)
    {
        pi.bindAttribLocation("v_texCoord", 2);
        return super.beforeLinking(pi);
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsText p)
    in (p.tex && p.texSize)
    {
        super.prepare(pbase);
        glUniform2f(loc.texPixelSize, 1.0f / p.texSize.w, 1.0f / p.texSize.h);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(*p.tex, SamplerIndex.texture);
    }

    private Locations!(["texPixelSize", "tex"]) loc;
}

final class ShaderCompose : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        enum defs = "#define COMPOSITION\n";
        const vs = defs ~ import("base.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = import("composition.fs.glsl");
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsComposition p)
    {
        super.prepare(pbase);
        glUniform1i(loc.texHeight, p.box.h);
        glUniform2i(loc.texPos, p.box.x, p.box.y);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(p.tex, SamplerIndex.texture);
    }

    private Locations!(["tex", "texHeight", "texPos"]) loc;
}

final class ShaderBlend : ShaderBase
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        enum defs = "#define COMPOSITION\n";
        const vs = defs ~ import("base.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = import("blending.fs.glsl");
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return super.afterLinking(pi) && loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsComposition p)
    {
        super.prepare(pbase);
        glUniform1i(loc.texHeight, p.box.h);
        glUniform2i(loc.texPos, p.box.x, p.box.y);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(p.tex, SamplerIndex.texture);
    }

    private Locations!(["tex", "texHeight", "texPos"]) loc;
}

final class ShaderGPAA : GLProgram
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        const vs = import("gpaa.vs.glsl") ~ import("datastore.inc.glsl") ~ import("clip-rect.inc.glsl");
        const fs = import("gpaa.fs.glsl");
        return [ShaderStage.vertex : vs, ShaderStage.fragment : fs];
    }

    override protected bool beforeLinking(const GLProgramInterface pi)
    {
        pi.bindAttribLocation("v_point0", 0);
        pi.bindAttribLocation("v_point1", 1);
        pi.bindAttribLocation("v_dataIndex", 2);
        pi.bindAttribLocation("v_layerIndex", 3);
        return true;
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        return loc.initialize(pi);
    }

    void prepare(ref const ParamsBase pbase, ref const ParamsGPAA p)
    {
        glUniform2f(loc.pixelSize, pbase.pixelSize.x, pbase.pixelSize.y);
        glUniform1i(loc.viewportHeight, pbase.viewportHeight);
        glUniform2f(loc.texPixelSize, p.texPixelSize.x, p.texPixelSize.y);

        glUniform1i(loc.dataStore, SamplerIndex.data);
        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(pbase.dataStore, SamplerIndex.data);
        Tex2D.setup(p.tex, SamplerIndex.texture);
    }

    // dfmt off
    private Locations!([
        "pixelSize", "viewportHeight", "dataStore", "tex", "texPixelSize"
    ]) loc;
    // dfmt on
}
