// Humus' geometric post-process anti-aliasing
// http://www.humus.name/index.php?page=3D&ID=86

in float dummy;  // always 0
flat in vec4 pack;
out vec4 f_color;

uniform vec2 texPixelSize;
uniform sampler2D tex;

void main()
{
    // compute the difference between sample position and geometric line
    const float diff = dot(gl_FragCoord.xy, pack.xy) + pack.z;

    // compute the coverage of the neighboring surface
    const float coverage = 0.5 - abs(diff) + dummy;
    vec2 offset = vec2(0);

    if (coverage > 0)
    {
        // select direction to sample a neighbor pixel
        float dir = diff >= 0 ? 1 : -1;
        if (pack.w == 0)
            offset.x = dir * coverage;
        else
            offset.y = dir * coverage;
    }

    // blend pixel with neighbor pixel using texture filtering
    // and shifting the coordinate appropriately
    f_color = texture(tex, texPixelSize * (gl_FragCoord.xy + offset));
}
