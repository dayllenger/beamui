/**
Client code for standard shaders.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.shaders;

import beamui.core.config;

static if (USE_OPENGL):
import beamui.core.functions : eliminate;
import beamui.core.geometry : BoxI, SizeI;
import beamui.core.linalg : Mat2x3, Vec2;
import beamui.graphics.colors : ColorF;
import beamui.graphics.gl.api;
import beamui.graphics.gl.objects : Tex2D, TexId;
import beamui.graphics.gl.program;

package:

/// Contains all standard shaders. They are compiled on demand, so every getter may return `null`
struct StdShaders
{
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
    }

    nothrow:
    @disable this(this);

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

    // non-cached compilation of all the shaders may take 200 ms or more,
    // so we won't compile until it's really needed
    private T take(T : GLProgram)(ref T prog)
    {
        if (!prog)
            prog = new T;
        return prog.valid ? prog : null;
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
    float opacity = 0;
}

struct ParamsImage
{
    const(TexId)* tex;
    const(SizeI)* texSize;
    float opacity = 0;
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
    float opacity = 0;
}

struct ParamsGPAA
{
    TexId layerOffsets;
    TexId tex;
    Vec2 texPixelSize;
}

private enum SamplerIndex
{
    data,
    colors,
    texture,
    offsets,
}

private struct Locations(string[] names)
{
    nothrow:

    static foreach (name; names)
        mixin("GLint " ~ name ~ ";");

    bool initialize(const GLProgram p)
    {
        // retrieve all uniform locations, fail if not found
        static foreach (m; typeof(this).tupleof)
        {
            m = p.getUniformLocation(__traits(identifier, m));
            if (m < 0)
                return false;
        }
        return true;
    }
}

abstract class ShaderBase : GLProgram
{
    nothrow:

    override @property string vertexSource() const
    {
        return import("base.vs.glsl") ~ import("datastore.inc.glsl");
    }

    override protected bool initLocations()
    {
        bindAttribLocation("v_position", 0);
        bindAttribLocation("v_dataIndex", 1);
        return loc.initialize(this);
    }

    private void setup(ref const ParamsBase p)
    {
        bind();
        glUniform2f(loc.pixelSize, p.pixelSize.x, p.pixelSize.y);

        glUniform1i(loc.dataStore, SamplerIndex.data);
        Tex2D.setup(p.dataStore, SamplerIndex.data);
    }

    private Locations!([
        "pixelSize", "dataStore"
    ]) loc;
}

final class ShaderEmpty : ShaderBase
{
    nothrow:

    override @property string fragmentSource() const
    {
        return q{ void main() {} };
    }

    void setup(ref const ParamsBase p)
    {
        super.setup(p);
    }
}

final class ShaderSolid : ShaderBase
{
    nothrow:

    override @property string vertexSource() const
    {
        return "#define DATA_COLOR\n" ~ import("base.vs.glsl") ~ import("datastore.inc.glsl");
    }
    override @property string fragmentSource() const
    {
        return import("solid.fs.glsl");
    }

    override protected bool initLocations()
    {
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase)
    {
        super.setup(pbase);
    }
}

final class ShaderLinear : ShaderBase
{
    nothrow:

    override @property string fragmentSource() const
    {
        return import("linear.fs.glsl") ~ import("gradients.inc.glsl");
    }

    override protected bool initLocations()
    {
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsLG p)
    {
        super.setup(pbase);
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

    private Locations!([
        "viewportHeight", "start", "end", "stopsCount", "stops", "colors", "atlasIndex"
    ]) loc;
}

final class ShaderRadial : ShaderBase
{
    nothrow:

    override @property string fragmentSource() const
    {
        return import("radial.fs.glsl") ~ import("gradients.inc.glsl");
    }

    override protected bool initLocations()
    {
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsRG p)
    {
        super.setup(pbase);
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

    private Locations!([
        "viewportHeight", "center", "radius", "stopsCount", "stops", "colors", "atlasIndex"
    ]) loc;
}

final class ShaderPattern : ShaderBase
{
    nothrow:

    override @property string fragmentSource() const
    {
        return import("pattern.fs.glsl");
    }

    override protected bool initLocations()
    {
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsPattern p)
        in(p.tex && p.texSize)
    {
        super.setup(pbase);
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
        glUniform1f(loc.opacity, p.opacity);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(*p.tex, SamplerIndex.texture);
    }

    private Locations!([
        "viewportHeight", "tex", "position", "size", "imgSize", "matrix", "opacity"
    ]) loc;
}

final class ShaderImage : ShaderBase
{
    nothrow:

    override @property string vertexSource() const
    {
        return "#define UV\n" ~ import("base.vs.glsl") ~ import("datastore.inc.glsl");
    }
    override @property string fragmentSource() const
    {
        return import("image.fs.glsl");
    }

    override protected bool initLocations()
    {
        bindAttribLocation("v_texCoord", 2);
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsImage p)
        in(p.tex && p.texSize)
    {
        super.setup(pbase);
        glUniform2f(loc.texPixelSize, 1.0f / p.texSize.w, 1.0f / p.texSize.h);
        glUniform1f(loc.opacity, p.opacity);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(*p.tex, SamplerIndex.texture);
    }

    private Locations!([
        "texPixelSize", "tex", "opacity"
    ]) loc;
}

final class ShaderText : ShaderBase
{
    nothrow:

    override @property string vertexSource() const
    {
        return "#define DATA_COLOR\n" ~ "#define UV\n" ~ import("base.vs.glsl") ~ import("datastore.inc.glsl");
    }
    override @property string fragmentSource() const
    {
        return import("text.fs.glsl");
    }

    override protected bool initLocations()
    {
        bindAttribLocation("v_texCoord", 2);
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsText p)
        in(p.tex && p.texSize)
    {
        super.setup(pbase);
        glUniform2f(loc.texPixelSize, 1.0f / p.texSize.w, 1.0f / p.texSize.h);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(*p.tex, SamplerIndex.texture);
    }

    private Locations!([
        "texPixelSize", "tex"
    ]) loc;
}

final class ShaderCompose : ShaderBase
{
    nothrow:

    override @property string vertexSource() const
    {
        return "#define COMPOSITION\n" ~ import("base.vs.glsl") ~ import("datastore.inc.glsl");
    }
    override @property string fragmentSource() const
    {
        return import("composition.fs.glsl");
    }

    override protected bool initLocations()
    {
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsComposition p)
    {
        super.setup(pbase);
        glUniform1i(loc.texHeight, p.box.h);
        glUniform2i(loc.texPos, p.box.x, p.box.y);
        glUniform1f(loc.opacity, p.opacity);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(p.tex, SamplerIndex.texture);
    }

    private Locations!([
        "tex", "opacity", "texHeight", "texPos"
    ]) loc;
}

final class ShaderBlend : ShaderBase
{
    nothrow:

    override @property string vertexSource() const
    {
        return "#define COMPOSITION\n" ~ import("base.vs.glsl") ~ import("datastore.inc.glsl");
    }
    override @property string fragmentSource() const
    {
        return import("blending.fs.glsl");
    }

    override protected bool initLocations()
    {
        return super.initLocations() && loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsComposition p)
    {
        super.setup(pbase);
        glUniform1i(loc.texHeight, p.box.h);
        glUniform2i(loc.texPos, p.box.x, p.box.y);
        glUniform1f(loc.opacity, p.opacity);

        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(p.tex, SamplerIndex.texture);
    }

    private Locations!([
        "tex", "opacity", "texHeight", "texPos"
    ]) loc;
}

final class ShaderGPAA : GLProgram
{
    nothrow:

    override @property string vertexSource() const
    {
        return import("gpaa.vs.glsl") ~ import("datastore.inc.glsl");
    }
    override @property string fragmentSource() const
    {
        return import("gpaa.fs.glsl");
    }

    override protected bool initLocations()
    {
        bindAttribLocation("v_point0", 0);
        bindAttribLocation("v_point1", 1);
        bindAttribLocation("v_dataIndex", 2);
        bindAttribLocation("v_layerIndex", 3);
        return loc.initialize(this);
    }

    void setup(ref const ParamsBase pbase, ref const ParamsGPAA p)
    {
        bind();
        glUniform2f(loc.pixelSize, pbase.pixelSize.x, pbase.pixelSize.y);
        glUniform1i(loc.viewportHeight, pbase.viewportHeight);
        glUniform2f(loc.texPixelSize, p.texPixelSize.x, p.texPixelSize.y);

        glUniform1i(loc.dataStore, SamplerIndex.data);
        glUniform1i(loc.layerOffsets, SamplerIndex.offsets);
        glUniform1i(loc.tex, SamplerIndex.texture);
        Tex2D.setup(pbase.dataStore, SamplerIndex.data);
        Tex2D.setup(p.layerOffsets, SamplerIndex.offsets);
        Tex2D.setup(p.tex, SamplerIndex.texture);
    }

    private Locations!([
        "pixelSize", "viewportHeight", "dataStore", "layerOffsets", "tex", "texPixelSize"
    ]) loc;
}
