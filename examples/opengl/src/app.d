module app;

import beamui;

static assert(USE_OPENGL, "The library must be built with OpenGL support");

mixin RegisterPlatforms;

int main()
{
    GuiApp app;
    // you can explicitly set OpenGL context version
    app.conf.GLVersionMajor = 3;
    app.conf.GLVersionMinor = 3;
    if (!app.initialize())
        return -1;

    platform.stylesheets = [StyleResource("light")];

    Window window = platform.createWindow("OpenGL example - beamui", null);

    auto scene = new Scene;

    window.show(delegate Widget() {
        if (!openglEnabled)
        {
            Label err = render!Label;
            err.text = "OpenGL is disabled";
            return err;
        }

        Panel frame = render!Panel;
        frame.wrap(
            render((Canvas cvs) {
                cvs.onDraw = (Painter pr, Size sz) {
                    pr.drawCustomScene(scene, SizeI(cast(int)sz.w, cast(int)sz.h), LayerInfo.init);
                };
            }),
            render((Label t) { t.text = "Text"; }),
        );
        return frame;
    });
    return platform.runEventLoop();
}

// dfmt off
static if (USE_OPENGL):
// dfmt on
import beamui.core.linalg;
import beamui.graphics.gl.api;
import beamui.graphics.gl.errors;
import beamui.graphics.gl.program;

final class Scene : CustomSceneDelegate
{
nothrow:
    struct Vertex
    {
        Vec3 pos;
        Vec2 uv;
    }

    Vertex[] cube;

    MyProgram program;

    GLuint fbo;
    GLuint colorTex;
    GLuint depthRB;
    SizeI targetSize;

    GLuint vao;
    GLuint vbo;

    this()
    {
        if (!openglEnabled)
            return;

        // construct a framebuffer with color and depth attachments
        glGenTextures(1, &colorTex);
        glGenRenderbuffers(1, &depthRB);
        glGenFramebuffers(1, &fbo);

        fixTargetSize(SizeI.init);

        checkgl!glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        checkgl!glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorTex, 0);
        checkgl!glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthRB);
        assert(checkFramebuffer());
        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        // compile the program
        program = new MyProgram;
        assert(program.isValid);

        // define Cube mesh
        const v000 = Vertex(Vec3(-1, -1, -1), Vec2(0, 0));
        const v100 = Vertex(Vec3(1, -1, -1), Vec2(1, 0));
        const v010 = Vertex(Vec3(-1, 1, -1), Vec2(0, 1));
        const v110 = Vertex(Vec3(1, 1, -1), Vec2(1, 1));
        const v001 = Vertex(Vec3(-1, -1, 1), Vec2(0, 0));
        const v101 = Vertex(Vec3(1, -1, 1), Vec2(1, 0));
        const v011 = Vertex(Vec3(-1, 1, 1), Vec2(0, 1));
        const v111 = Vertex(Vec3(1, 1, 1), Vec2(1, 1));
        cube = [
            v000, v010, v110, v110, v100, v000, // front face
            v101, v111, v011, v011, v001, v101, // back face
            v100, v110, v111, v111, v101, v100, // right face
            v001, v011, v010, v010, v000, v001, // left face
            v010, v011, v111, v111, v110, v010, // top face
            v001, v000, v100, v100, v101, v001, // bottom face
        ];

        // upload the data
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        checkgl!glBufferData(GL_ARRAY_BUFFER, cube.length * Vertex.sizeof, cube.ptr, GL_STATIC_DRAW);

        // create VAO for interleaved attributes
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        checkgl!glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*)0);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, Vertex.sizeof, cast(void*)Vec3.sizeof);
        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        checkgl!glBindVertexArray(0);
    }

    ~this()
    {
        if (!openglEnabled)
            return;

        eliminate(program);

        glDeleteFramebuffers(1, &fbo);
        glDeleteTextures(1, &colorTex);
        glDeleteRenderbuffers(1, &depthRB);

        glDeleteVertexArrays(1, &vao);
        glDeleteBuffers(1, &vbo);
    }

    void fixTargetSize(SizeI size)
    {
        size = getOptimalTargetSize(size);
        if (targetSize == size)
            return;

        targetSize = size;

        alias TEX = GL_TEXTURE_2D;
        alias RB = GL_RENDERBUFFER;

        checkgl!glBindTexture(TEX, colorTex);
        glTexParameteri(TEX, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(TEX, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(TEX, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(TEX, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        checkgl!glTexImage2D(TEX, 0, GL_RGBA8, size.w, size.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, null);
        glBindTexture(TEX, 0);

        checkgl!glBindRenderbuffer(RB, depthRB);
        checkgl!glRenderbufferStorage(RB, GL_DEPTH_COMPONENT24, size.w, size.h);
        glBindRenderbuffer(RB, 0);
    }

    /// Choose an appropriate framebuffer texture size after possible widget resize
    SizeI getOptimalTargetSize(SizeI size) const
    {
        SizeI result = targetSize;
        // became significantly shorter
        if (size.w * 8 < result.w)
            result.w /= 8;
        if (size.h * 8 < result.h)
            result.h /= 8;
        // not initialized
        if (result.w <= 0)
            result.w = 16;
        if (result.h <= 0)
            result.h = 16;
        // became larger
        while (result.w < size.w)
            result.w *= 2;
        while (result.h < size.h)
            result.h *= 2;

        return result;
    }

    Texture render(SizeI size)
    {
        if (!openglEnabled)
            return Texture.init;

        fixTargetSize(size);

        assert(checkFramebuffer());
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbo);

        glEnable(GL_CULL_FACE);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_SCISSOR_TEST);
        glScissor(0, 0, size.w, size.h);
        glViewport(0, 0, size.w, size.h);
        // clear with transparent black and max depth
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        checkgl!glUseProgram(program.programID);

        const matrix = getMatrix(size.w, size.h);
        glUniformMatrix4fv(program.u_matrix, 1, false, matrix.m.ptr);

        glBindVertexArray(vao);
        checkgl!glDrawArrays(GL_TRIANGLES, 0, cast(int)cube.length);

        // clean up: revert touched state to GL context defaults;
        // viewport and scissor box can be leaved as is
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        glBindVertexArray(0);
        glUseProgram(0);
        glDisable(GL_CULL_FACE);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_SCISSOR_TEST);

        return Texture(colorTex);
    }

    Mat4x4 getMatrix(float width, float height) const
    in (width * height > 0)
    {
        Mat4x4 projection;
        const float aspectRatio = width / height;
        projection.setPerspective(45.0f, aspectRatio, 0.1f, 100.0f);

        Mat4x4 view = Mat4x4.identity;
        view.translate(Vec3(0, 0, -6)).rotateX(-15);

        const angle = 2;
        Mat4x4 model = Mat4x4(1.5f);
        model.rotateZ(30.0f + angle * 0.3456778f).rotateY(angle).rotateZ(angle * 1.98765f);

        return projection * view * model;
    }
}

final class MyProgram : GLProgram
{
nothrow:
    override @property string[ShaderStage] sources() const
    {
        string[ShaderStage] stages;
        stages[ShaderStage.vertex] = `
        in vec3 v_position;
        in vec2 v_uv;
        out vec2 uv;

        uniform mat4 u_matrix;

        void main()
        {
            gl_Position = u_matrix * vec4(v_position, 1);
            uv = v_uv;
        }
        `;
        stages[ShaderStage.fragment] = `
        in vec2 uv;
        out vec4 f_color;

        void main()
        {
            f_color = vec4(0.5, 0.25, 1, 1) * vec4(uv, 1, 1);
        }
        `;
        return stages;
    }

    private GLuint u_matrix;

    override protected bool beforeLinking(const GLProgramInterface pi)
    {
        pi.bindAttribLocation("v_position", 0);
        pi.bindAttribLocation("v_uv", 1);
        return true;
    }

    override protected bool afterLinking(const GLProgramInterface pi)
    {
        u_matrix = pi.getUniformLocation("u_matrix");
        return u_matrix >= 0;
    }
}
