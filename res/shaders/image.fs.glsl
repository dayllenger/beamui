in vec2 uv;
out vec4 f_color;

uniform sampler2D tex;
uniform float opacity;

void main()
{
    f_color = texture(tex, uv) * opacity;
}
