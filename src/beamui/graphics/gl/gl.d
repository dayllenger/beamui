/**
Base utilities for the GL rendering.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.gl;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
import beamui.core.geometry : BoxI;
import beamui.graphics.colors : ColorF;
import beamui.graphics.compositing;
import beamui.graphics.gl.api;
import beamui.graphics.gl.errors;
import beamui.graphics.gl.objects : RbId, TexId;

package nothrow:

/// Load and check OpenGL bindings (call only after an OpenGL context is made current)
package(beamui) bool loadGLAPI()
{
    import std.exception : assertNotThrown;
    import std.string : fromStringz, strip;
    import beamui.core.logger : Log;
    import beamui.graphics.gl.program : GLSLInfo;
    static import bindbc.loader.sharedlib;
    static import bindbc.opengl.config;
    static import bindbc.opengl.gl;

    // bindings are __gshared
    static shared bool tried;
    static shared bool loaded;
    if (tried)
        return loaded;
    tried = true;

    version (Android)
    {
        Log.e("GL: unimplemented");
        return false;
    }
    else
    {
        bindbc.loader.sharedlib.resetErrors();
        const support = bindbc.opengl.gl.loadOpenGL();
        if (support != bindbc.opengl.config.glSupport)
        {
            Log.e("GL: errors when loading:");
            foreach (e; bindbc.loader.sharedlib.errors())
            {
                const err = assertNotThrown(strip(fromStringz(e.error)));
                const msg = assertNotThrown(strip(fromStringz(e.message)));
                Log.e(err, " - ", msg);
            }
            Log.e("GL: cannot load the library");
            bindbc.opengl.gl.unloadOpenGL();
            return false;
        }
    }
    const char major = glGetString(GL_VERSION)[0];
    if (major < '3')
    {
        Log.e("GL: the version must be at least 3.0"); // the same on GLES
        return false;
    }
    if (!GLSLInfo.determineVersion())
    {
        Log.e("GL: cannot determine GLSL version");
        return false;
    }
    Log.v("GL: GLSL version is ", GLSLInfo.versionInt);
    loaded = true;
    return true;
}

struct VaoId
{
    GLuint handle;
}

struct FboId
{
    GLuint handle;
}

enum DrawFlags : uint
{
    // dfmt off
    none           = 0,
    blending       = 1 << 0,
    clippingPlanes = 1 << 1,
    depthTest      = 1 << 3,
    noColorWrite   = 1 << 2,
    noDepthWrite   = 1 << 4,
    stencilTest    = 1 << 5,
    all            = 0xFFFFFFFF,
    // dfmt on
}

struct Device
{
nothrow:
    // they save various expensive GL state changes
    FboManager fboman;
    VaoManager vaoman;
    ProgramManager progman;
    private DrawFlags currentFlags;

    @disable this(this);

    bool hasExtension(const(char)* name)
    {
        import core.stdc.string : strcmp;

        int count;
        glGetIntegerv(GL_NUM_EXTENSIONS, &count);

        foreach (i; 0 .. cast(uint)count)
        {
            const(char)* ext = glGetStringi(GL_EXTENSIONS, i);
            if (ext && strcmp(ext, name) == 0)
                return true;
        }
        return false;
    }

    /// Set some GL state to defaults before rendering
    void initialize(DrawFlags initialFlags)
    {
        fboman = FboManager.init;
        vaoman = VaoManager.init;
        progman = ProgramManager.init;
        currentFlags = ~initialFlags;
        setDrawFlags(initialFlags);
        resetBlending();
    }

    void reset()
    {
        setDrawFlags(DrawFlags.none);
        fboman.bind(FboId.init);
        vaoman.unbind();
        progman.unbind();
    }

    void setDrawFlags(DrawFlags f)
    {
        const diff = currentFlags ^ f;
        currentFlags = f;

        if (diff & DrawFlags.blending)
        {
            if (f & DrawFlags.blending)
                glEnable(GL_BLEND);
            else
                glDisable(GL_BLEND);
        }
        if (diff & DrawFlags.clippingPlanes)
        {
            if (f & DrawFlags.clippingPlanes)
            {
                foreach (i; 0 .. 4)
                    glEnable(GL_CLIP_DISTANCE0 + i);
            }
            else
            {
                foreach (i; 0 .. 4)
                    glDisable(GL_CLIP_DISTANCE0 + i);
            }
        }
        if (diff & DrawFlags.noColorWrite)
        {
            if (f & DrawFlags.noColorWrite)
                glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
            else
                glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        }
        if (diff & DrawFlags.depthTest)
        {
            if (f & DrawFlags.depthTest)
                glEnable(GL_DEPTH_TEST);
            else
                glDisable(GL_DEPTH_TEST);
        }
        if (diff & DrawFlags.noDepthWrite)
        {
            if (f & DrawFlags.noDepthWrite)
                glDepthMask(GL_FALSE);
            else
                glDepthMask(GL_TRUE);
        }
        if (diff & DrawFlags.stencilTest)
        {
            if (f & DrawFlags.stencilTest)
                glEnable(GL_STENCIL_TEST);
            else
            {
                glDisable(GL_STENCIL_TEST);
                glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
            }
        }
    }

    void setBlending(CompositeOperation op)
    {
        const src = convertBlendFactor(op.src);
        const dst = convertBlendFactor(op.dst);
        glBlendFunc(src, dst);
    }

    void setAdvancedBlending(BlendMode mode)
    {
        glBlendEquation(convertAdvancedBlendMode(mode));
    }

    void resetBlending()
    {
        glBlendEquation(GL_FUNC_ADD);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    }

    //===============================================================

    void clear(BoxI box, ColorF color)
    {
        // ensure full write
        if (currentFlags & DrawFlags.noColorWrite)
        {
            glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        }
        if (currentFlags & DrawFlags.noDepthWrite)
        {
            glDepthMask(GL_TRUE);
        }
        currentFlags &= ~(DrawFlags.noColorWrite | DrawFlags.noDepthWrite);

        // TODO: optimization: do not clear color if something opaque covers entire layer
        glEnable(GL_SCISSOR_TEST);
        glScissor(box.x, box.y, box.w, box.h);
        glClearColor(color.r, color.g, color.b, color.a);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        glDisable(GL_SCISSOR_TEST);
    }

    void drawTriangles(VaoId vao, DrawFlags flags, int start, int count)
    in (count > 0)
    {
        vaoman.bind(vao);
        setDrawFlags(flags);

        glDrawElements(GL_TRIANGLES, count, GL_UNSIGNED_INT, cast(void*)(start * uint.sizeof));
        checkError("draw triangles");
    }

    void drawLines(VaoId vao, DrawFlags flags, int start, int count)
    in (count > 0)
    {
        vaoman.bind(vao);
        setDrawFlags(flags);

        glDrawElements(GL_LINES, count, GL_UNSIGNED_INT, cast(void*)(start * uint.sizeof));
        checkError("draw lines");
    }

    void drawInstancedQuads(VaoId vao, DrawFlags flags, int count)
    in (count > 0)
    {
        vaoman.bind(vao);
        setDrawFlags(flags);

        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, count);
        checkError("draw triangles");
    }
}

private GLenum convertBlendFactor(AlphaBlendFactor factor)
{
    // dfmt off
    final switch (factor) with (AlphaBlendFactor)
    {
        case zero: return GL_ZERO;
        case one:  return GL_ONE;
        case src:  return GL_SRC_ALPHA;
        case dst:  return GL_DST_ALPHA;
        case oneMinusSrc: return GL_ONE_MINUS_SRC_ALPHA;
        case oneMinusDst: return GL_ONE_MINUS_DST_ALPHA;
    }
    // dfmt on
}

private GLenum convertAdvancedBlendMode(BlendMode mode)
{
    // dfmt off
    enum : GLenum
    {
        MULTIPLY_KHR       = 0x9294,
        SCREEN_KHR         = 0x9295,
        OVERLAY_KHR        = 0x9296,
        DARKEN_KHR         = 0x9297,
        LIGHTEN_KHR        = 0x9298,
        COLORDODGE_KHR     = 0x9299,
        COLORBURN_KHR      = 0x929A,
        HARDLIGHT_KHR      = 0x929B,
        SOFTLIGHT_KHR      = 0x929C,
        DIFFERENCE_KHR     = 0x929E,
        EXCLUSION_KHR      = 0x92A0,

        HSL_HUE_KHR        = 0x92AD,
        HSL_SATURATION_KHR = 0x92AE,
        HSL_COLOR_KHR      = 0x92AF,
        HSL_LUMINOSITY_KHR = 0x92B0,
    }

    final switch (mode) with (BlendMode)
    {
        case normal:     return GL_FUNC_ADD;
        case multiply:   return MULTIPLY_KHR;
        case screen:     return SCREEN_KHR;
        case overlay:    return OVERLAY_KHR;
        case darken:     return DARKEN_KHR;
        case lighten:    return LIGHTEN_KHR;
        case colorDodge: return COLORDODGE_KHR;
        case colorBurn:  return COLORBURN_KHR;
        case hardLight:  return HARDLIGHT_KHR;
        case softLight:  return SOFTLIGHT_KHR;
        case difference: return DIFFERENCE_KHR;
        case exclusion:  return EXCLUSION_KHR;
        case hue:        return HSL_HUE_KHR;
        case saturation: return HSL_SATURATION_KHR;
        case color:      return HSL_COLOR_KHR;
        case luminosity: return HSL_LUMINOSITY_KHR;
    }
    // dfmt on
}

struct FboManager
{
nothrow:
    private FboId current = FboId(GLuint.max);

    FboId create()
    {
        GLuint id;
        glGenFramebuffers(1, &id);
        return FboId(id);
    }

    bool bind(FboId id)
    {
        if (current != id)
        {
            checkgl!glBindFramebuffer(GL_FRAMEBUFFER, id.handle);
            current = id;
            return true;
        }
        return false;
    }

    void del(ref FboId id)
    {
        glDeleteFramebuffers(1, &id.handle);
        id.handle = 0;
    }

    void attachColorTex2D(TexId tex, GLuint num)
    {
        checkgl!glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + num, GL_TEXTURE_2D, tex.handle, 0);
    }

    void attachDepthStencilRB(RbId rb)
    {
        checkgl!glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, rb.handle);
    }
}

struct VaoManager
{
nothrow:
    private VaoId current = VaoId(GLuint.max);

    void bind(ref VaoId id)
    {
        if (id.handle == 0)
            glGenVertexArrays(1, &id.handle);

        if (current != id)
        {
            checkgl!glBindVertexArray(id.handle);
            current = id;
        }
    }

    void unbind()
    {
        if (current.handle != 0)
        {
            glBindVertexArray(0);
            current.handle = 0;
        }
    }

    void del(ref VaoId id)
    {
        glDeleteVertexArrays(1, &id.handle);
        id.handle = 0;
    }

    void addAttribF(GLuint index, GLint components, GLsizei stride = 0, GLsizei offset = 0)
    {
        glVertexAttribPointer(index, components, GL_FLOAT, GL_FALSE, stride, cast(void*)offset);
        glEnableVertexAttribArray(index);
    }

    void addAttribU16(GLuint index, GLint components, GLsizei stride = 0, GLsizei offset = 0)
    {
        glVertexAttribIPointer(index, components, GL_UNSIGNED_SHORT, stride, cast(void*)offset);
        glEnableVertexAttribArray(index);
    }

    void addAttribU32(GLuint index, GLint components, GLsizei stride = 0, GLsizei offset = 0)
    {
        glVertexAttribIPointer(index, components, GL_UNSIGNED_INT, stride, cast(void*)offset);
        glEnableVertexAttribArray(index);
    }
}

struct ProgramManager
{
nothrow:
    import beamui.graphics.gl.program : GLProgram;

    private GLuint current;

    void bind(GLProgram program)
    in (program && program.isValid, "Attempt to bind invalid shader program")
    {
        if (current != program.programID)
        {
            checkgl!glUseProgram(program.programID);
            current = program.programID;
        }
    }

    void unbind()
    {
        if (current != 0)
        {
            checkgl!glUseProgram(0);
            current = 0;
        }
    }
}
