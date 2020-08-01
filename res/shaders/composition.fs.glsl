in vec2 texCoord;
flat in float opacity;
out vec4 f_color;

uniform sampler2D tex;

void main()
{
    vec4 c = texelFetch(tex, ivec2(texCoord), 0);
    f_color = vec4(c.rgb, c.a) * opacity;
}
