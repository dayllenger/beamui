/**
Sugar for basic shareable OpenGL objects - buffers, textures, renderbuffers.

Copyright: dayllenger 2017-2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.objects;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
import beamui.core.geometry : BoxI, SizeI;
import beamui.graphics.gl.api;
import beamui.graphics.gl.errors;

package(beamui.graphics):

struct BufferId
{
    GLuint handle;
}

struct TexId
{
    GLuint handle;
}

struct RbId
{
    GLuint handle;
}

/// Buffer objects facility
struct Buffer(GLenum target_)
{
static nothrow:

    alias target = target_;

    void bind(ref BufferId id)
    {
        if (id.handle == 0)
            glGenBuffers(1, &id.handle);
        checkgl!glBindBuffer(target, id.handle);
    }

    void unbind()
    {
        glBindBuffer(target, 0);
    }

    void del(ref BufferId id)
    {
        glDeleteBuffers(1, &id.handle);
        id.handle = 0;
    }

    void upload(T)(const T[] data, GLenum usage)
    {
        checkgl!glBufferData(target, data.length * T.sizeof, data.ptr, usage);
    }
}

alias VBO = Buffer!GL_ARRAY_BUFFER;
alias EBO = Buffer!GL_ELEMENT_ARRAY_BUFFER;
// dfmt off
enum TexFiltering : ubyte { sharp, smooth }
enum TexMipmaps : bool { no, yes }
enum TexWrap : ubyte { clamp, repeat }
// dfmt on

/// 2D texture facility
struct Tex2D
{
static nothrow:

    void bind(ref TexId id)
    {
        if (id.handle == 0)
            glGenTextures(1, &id.handle);
        checkgl!glBindTexture(GL_TEXTURE_2D, id.handle);
    }

    void setup(TexId id, GLuint binding)
    {
        assert(id.handle > 0);
        glActiveTexture(GL_TEXTURE0 + binding);
        checkgl!glBindTexture(GL_TEXTURE_2D, id.handle);
    }

    void unbind()
    {
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    void del(ref TexId id)
    {
        glDeleteTextures(1, &id.handle);
        id.handle = 0;
    }

    void setBasicParams(TexFiltering filter, TexMipmaps mipmap, TexWrap wrap)
    {
        GLenum mag, min;
        if (filter == TexFiltering.smooth)
        {
            mag = GL_LINEAR;
            min = mipmap ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR;
        }
        else
        {
            mag = GL_NEAREST;
            min = mipmap ? GL_NEAREST_MIPMAP_NEAREST : GL_NEAREST;
        }
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, mag);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, min);

        if (wrap == TexWrap.clamp)
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        }
        checkError("filtering");
    }

    void resize(SizeI size, GLint level, GLint internalFormat, GLenum format, GLenum type)
    in (size.w > 0 && size.h > 0)
    {
        checkgl!glTexImage2D(GL_TEXTURE_2D, level, internalFormat, size.w, size.h, 0, format, type, null);
    }

    void copy(TexId oldTex, SizeI oldSize)
    in (oldTex.handle)
    in (oldSize.w > 0 && oldSize.h > 0)
    {
        // create a framebuffer
        GLuint fbo;
        glGenFramebuffers(1, &fbo);
        GLint prevDrawFbo, prevReadFbo;
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prevDrawFbo);
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prevReadFbo);
        // attach the old texture to it, set it for reading
        glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
        checkgl!glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, oldTex.handle, 0);
        checkgl!glReadBuffer(GL_COLOR_ATTACHMENT0);
        checkFramebuffer();
        // copy pixels
        checkgl!glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, oldSize.w, oldSize.h);
        // delete the framebuffer and the texture
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, prevDrawFbo);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, prevReadFbo);
        checkgl!glDeleteFramebuffers(1, &fbo);
    }

    void uploadSubImage(BoxI box, GLint level, GLenum format, GLenum type, const void* data)
    {
        checkgl!glTexSubImage2D(GL_TEXTURE_2D, level, box.x, box.y, box.w, box.h, format, type, data);
    }
}

/// Depth-stencil renderbuffer facility
struct DepthStencilRB
{
static nothrow:

    void bind(ref RbId id)
    {
        if (id.handle == 0)
            glGenRenderbuffers(1, &id.handle);
        checkgl!glBindRenderbuffer(GL_RENDERBUFFER, id.handle);
    }

    void unbind()
    {
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
    }

    void del(ref RbId id)
    {
        glDeleteRenderbuffers(1, &id.handle);
        id.handle = 0;
    }

    void resize(SizeI size)
    in (size.w > 0 && size.h > 0)
    {
        checkgl!glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, size.w, size.h);
    }
}
