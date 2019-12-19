in vec2 uv;
out vec4 f_color;

uniform sampler2D tex;
uniform vec4 textRunColor;

void main()
{
    float val = texture(tex, uv).r;
    f_color = textRunColor * val;
}
