/**
Wrappers for basic OpenGL objects - buffers, vertex array objects, textures, and so on.

Every class that represents OpenGL object uses RAII idiom:
it creates a resource in constructor and deletes it in destructor,
so don't forget about proper object destruction.

Note: On construction each object binds itself to the target, and unbinds on destruction.

Copyright: dayllenger 2017-2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.objects;

import derelict.opengl3.gl3;
import derelict.opengl3.types;
import beamui.graphics.gl.errors;

package(beamui) __gshared bool glNoContext;

final class Buffer(GLuint target)
{
    private immutable GLuint id;

    this()
    {
        GLuint handle;
        checkgl!glGenBuffers(1, &handle);
        id = handle;
        bind();
    }

    ~this()
    {
        if (!glNoContext)
        {
            unbind();
            checkgl!glDeleteBuffers(1, &id);
        }
    }

    void bind()
    {
        glBindBuffer(target, id);
    }

    static void unbind()
    {
        checkgl!glBindBuffer(target, 0);
    }

    void fill(float[][] buffs)
    {
        int length;
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

    static if (target == GL_ELEMENT_ARRAY_BUFFER)
    {
        void fill(int[] indexes)
        {
            checkgl!glBufferData(target, cast(int)(indexes.length * int.sizeof), indexes.ptr, GL_STATIC_DRAW);
        }
    }
}

alias VBO = Buffer!GL_ARRAY_BUFFER;
alias EBO = Buffer!GL_ELEMENT_ARRAY_BUFFER;

/// Vertex array object
final class VAO
{
    private immutable GLuint id;

    this()
    {
        GLuint handle;
        checkgl!glGenVertexArrays(1, &handle);
        id = handle;
        bind();
    }

    ~this()
    {
        if (!glNoContext)
        {
            unbind();
            checkgl!glDeleteVertexArrays(1, &id);
        }
    }

    void bind()
    {
        glBindVertexArray(id);
    }

    static void unbind()
    {
        checkgl!glBindVertexArray(0);
    }
}

class Tex2D
{
    immutable GLuint id;

    this()
    {
        GLuint handle;
        checkgl!glGenTextures(1, &handle);
        id = handle;
        bind();
    }

    ~this()
    {
        if (!glNoContext)
        {
            unbind();
            checkgl!glDeleteTextures(1, &id);
        }
    }

    void bind()
    {
        glBindTexture(GL_TEXTURE_2D, id);
    }

    static void unbind()
    {
        checkgl!glBindTexture(GL_TEXTURE_2D, 0);
    }

    void setSamplerParams(bool linear, bool clamp = false, bool mipmap = false)
    {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, linear ? GL_LINEAR : GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, linear ? (!mipmap ? GL_LINEAR
                : GL_LINEAR_MIPMAP_LINEAR) : (!mipmap ? GL_NEAREST : GL_NEAREST_MIPMAP_NEAREST));
        checkError("filtering - glTexParameteri");
        if (clamp)
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            checkError("clamp - glTexParameteri");
        }
    }

    void setup(GLuint binding = 0)
    {
        glActiveTexture(GL_TEXTURE0 + binding);
        glBindTexture(GL_TEXTURE_2D, id);
        checkError("setup texture");
    }
}

/// Framebuffer object
final class FBO
{
    private immutable GLuint id;

    this()
    {
        GLuint handle;
        checkgl!glGenFramebuffers(1, &handle);
        id = handle;
        bind();
    }

    ~this()
    {
        if (!glNoContext)
        {
            unbind();
            checkgl!glDeleteFramebuffers(1, &id);
        }
    }

    void bind()
    {
        glBindFramebuffer(GL_FRAMEBUFFER, id);
    }

    static void unbind()
    {
        checkgl!glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
}
