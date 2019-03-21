/**
Sugar for basic OpenGL objects - buffers, vertex array objects, textures, and so on.

Copyright: dayllenger 2017-2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.objects;

import beamui.core.config;

static if (USE_OPENGL):
public import beamui.graphics.gl.api : GLuint;
import beamui.graphics.gl.api;
import beamui.graphics.gl.errors;

package(beamui) __gshared bool glNoContext;

/// Buffer objects facility
struct Buffer(GLuint target_)
{
    alias target = target_;

static:
    void bind(ref GLuint id)
    {
        if (id == 0)
            glGenBuffers(1, &id);
        checkgl!glBindBuffer(target, id);
    }

    void unbind()
    {
        glBindBuffer(target, 0);
    }

    void del(ref GLuint id)
    {
        if (!glNoContext)
        {
            glBindBuffer(target, 0);
            glDeleteBuffers(1, &id);
        }
        id = 0;
    }

    static if (target != GL_ELEMENT_ARRAY_BUFFER)
    {
        void fill(float[][] buffs...)
        {
            size_t length;
            foreach (b; buffs)
                length += b.length;
            checkgl!glBufferData(target, length * float.sizeof, null, GL_STATIC_DRAW);
            int offset;
            foreach (b; buffs)
            {
                checkgl!glBufferSubData(target, offset, b.length * float.sizeof, b.ptr);
                offset += b.length * float.sizeof;
            }
        }
    }
    else
    {
        void fill(int[] indexes)
        {
            checkgl!glBufferData(target, indexes.length * int.sizeof, indexes.ptr, GL_STATIC_DRAW);
        }
    }
}

alias VBO = Buffer!GL_ARRAY_BUFFER;
alias EBO = Buffer!GL_ELEMENT_ARRAY_BUFFER;

/// Vertex array object facility
struct VAO
{
static:
    void bind(ref GLuint id)
    {
        if (id == 0)
            glGenVertexArrays(1, &id);
        checkgl!glBindVertexArray(id);
    }

    void unbind()
    {
        glBindVertexArray(0);
    }

    void del(ref GLuint id)
    {
        if (!glNoContext)
        {
            glBindVertexArray(0);
            glDeleteVertexArrays(1, &id);
        }
        id = 0;
    }
}

/// 2D texture facility
struct Tex2D
{
static:
    void bind(ref GLuint id)
    {
        if (id == 0)
            glGenTextures(1, &id);
        checkgl!glBindTexture(GL_TEXTURE_2D, id);
    }

    void setup(GLuint id, GLuint binding)
    {
        assert(id > 0);
        glActiveTexture(GL_TEXTURE0 + binding);
        glBindTexture(GL_TEXTURE_2D, id);
        checkError("setup texture");
    }

    void unbind()
    {
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    void del(ref GLuint id)
    {
        if (!glNoContext)
        {
            glBindTexture(GL_TEXTURE_2D, 0);
            glDeleteTextures(1, &id);
        }
        id = 0;
    }

    void setFiltering(bool linear, bool mipmap)
    {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, linear ? GL_LINEAR : GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, linear ?
            (!mipmap ? GL_LINEAR : GL_LINEAR_MIPMAP_LINEAR) :
            (!mipmap ? GL_NEAREST : GL_NEAREST_MIPMAP_NEAREST));
        checkError("filtering - glTexParameteri");
    }

    void setRepeating(bool repeat)
    {
        if (!repeat)
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            checkError("clamp - glTexParameteri");
        }
    }
}

/// Framebuffer object facility
struct FBO
{
static:
    void bind(ref GLuint id)
    {
        if (id == 0)
            glGenFramebuffers(1, &id);
        checkgl!glBindFramebuffer(GL_FRAMEBUFFER, id);
    }

    void unbind()
    {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }

    void del(ref GLuint id)
    {
        if (!glNoContext)
        {
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glDeleteFramebuffers(1, &id);
        }
        id = 0;
    }
}
