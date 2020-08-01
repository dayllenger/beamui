flat in float opacity;
out vec4 f_color;

#define MAX_STOPS 16
#define ROW_SIZE (1.0 / 1024.0)

uniform int viewportHeight;
uniform vec2 center;
uniform float radius;    // > 0
uniform int stopsCount;  // 2 .. MAX_STOPS
uniform float[MAX_STOPS] stops;
uniform sampler2D colors;
uniform uint atlasIndex;

float calc_offset(in float fraction); // uses all unused uniforms

void main()
{
    const vec2 pos = vec2(gl_FragCoord.x, viewportHeight - gl_FragCoord.y);
    const vec2 vec = pos - center;
    const float fraction = clamp(length(vec) / radius, 0, 1);
    const float offset = calc_offset(fraction);

    float u = offset / MAX_STOPS + 0.5 / MAX_STOPS;
    float v = (float(atlasIndex) + 0.5) * ROW_SIZE;
    f_color = texture(colors, vec2(u, v)) * opacity;
}
