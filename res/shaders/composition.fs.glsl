in vec2 texCoord;
out vec4 f_color;

uniform sampler2D tex;
uniform float opacity;

void main()
{
    vec4 c = texelFetch(tex, ivec2(texCoord), 0);
    f_color = vec4(c.rgb, c.a) * opacity;
}
