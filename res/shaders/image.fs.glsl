in vec2 uv;
flat in float opacity;
out vec4 f_color;

uniform sampler2D tex;

void main()
{
    f_color = texture(tex, uv) * opacity;
}
