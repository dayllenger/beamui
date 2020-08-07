flat in ivec2 segments;
flat in vec2 shift;
flat in float width;
flat in float contrast;

uniform int viewportHeight;
uniform sampler2D buf_segments;

float get_line_dist(in vec2 p, in vec2 a, in vec2 b)
{
    vec2 pa = p - a;
    vec2 ba = b - a;
    vec2 d = pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return dot(d, d);
}

float get_real_dist(in float d)
{
    return sqrt(d) * TILE_SIZE;
}

float get_stroke_alpha(in float d)
{
    float e = -clamp((d - 0.5 * width) * contrast, -0.5, 0.5);
    return smoothstep(-0.5, 0.5, e);
}

float compute_stroke_sdf()
{
    vec2 uv = vec2(gl_FragCoord.x, float(viewportHeight) - gl_FragCoord.y) / TILE_SIZE;

    float d = 100.0;
    for (int i = segments.x; i < segments.x + segments.y; i++)
    {
        ivec2 seg_index = ivec2(i % ROW_LENGTH, i / ROW_LENGTH);
        vec4 seg = texelFetch(buf_segments, seg_index, 0);
        d = min(d, get_line_dist(uv, seg.xy + shift, seg.zw + shift));
    }
    return get_stroke_alpha(get_real_dist(d));
}
