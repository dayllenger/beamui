// Humus' geometric post-process anti-aliasing
// http://www.humus.name/index.php?page=3D&ID=86

in float dummy;  // always 0
flat in vec4 pack;
out vec4 f_color;

uniform vec2 texPixelSize;
uniform sampler2D tex;

void main()
{
    const vec2 uv = texPixelSize * gl_FragCoord.xy;
    vec2 offset = texPixelSize * vec2(1 - pack.w, pack.w);

    // compute the difference between sample position and geometric line
    const float diff = dot(gl_FragCoord.xy, pack.xy) + pack.z;
    if (diff < -0.001 || 0.001 < diff)
    {
        // compute the coverage of the neighboring surface
        const float coverage = 0.5 - abs(diff) + dummy;
        // select direction to sample a neighbor pixel
        offset *= sign(diff) * coverage;

        // blend pixel with neighbor pixel using texture filtering
        // and shifting the coordinate appropriately
        f_color = texture(tex, uv + offset);
    }
    else
    {
        // this path handles a nasty case: when the line goes close to pixel center,
        // the code above may choose the wrong pixel because of differences between
        // shader and rasterizer calculations

        // just mix two neighbor pixels
        f_color = (texture(tex, uv + offset) + texture(tex, uv - offset)) * 0.5;
    }
}
