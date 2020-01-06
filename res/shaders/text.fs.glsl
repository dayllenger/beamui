in vec2 uv;
flat in vec4 brushColor;
out vec4 f_color;

uniform sampler2D tex;

void main()
{
    float val = texture(tex, uv).r;
    f_color = brushColor * val;
}
