// Humus' geometric post-process anti-aliasing
// http://www.humus.name/index.php?page=3D&ID=86

in vec2 v_point0;
in vec2 v_point1;
in uint v_dataIndex;
out float dummy;    // workaround for a bug on Intel driver
flat out vec4 pack; // this value is provided by the 2nd segment point

uniform vec2 pixelSize;
uniform int viewportHeight;

void fetchData(in int index, out mat3 transform, out float depth, out vec4 clip, out vec4 color);
void clipByRect(in vec2 pos, in vec4 clip);

void main()
{
    mat3 transform;
    float depth;
    vec4 clip;
    vec4 color;
    fetchData(int(v_dataIndex), transform, depth, clip, color);

    const vec2 pos0 = (transform * vec3(v_point0, 1)).xy;
    const vec2 pos1 = (transform * vec3(v_point1, 1)).xy;
    const vec2 npos = pos1 * pixelSize * 2.0 - 1.0;
    gl_Position.x =  npos.x;
    gl_Position.y = -npos.y; // user Y is reversed
    gl_Position.z = depth;
    gl_Position.w = 1.0;

    clipByRect(pos1, clip);

    // compute screen-space position and direction of the line
    const vec2 pos = vec2(pos1.x, viewportHeight - pos1.y);
    vec2 dir = pos - vec2(pos0.x, viewportHeight - pos0.y);

    // select between mostly horizontal or vertical
    const bool x_gt_y = abs(dir.x) > abs(dir.y);
    // pass down the screen-space line equation
    if (x_gt_y)
    {
        float k = dir.y / dir.x;
        pack.xy = vec2(k, -1);
        // less smoothing for semitransparent shapes -> less interference on overlaps
        pack.w = (color.a + 1.0) * 0.5;
    }
    else
    {
        float k = dir.x / dir.y;
        pack.xy = vec2(-1, k);
        pack.w = 0;
    }
    pack.z = -dot(pos, pack.xy);

    dummy = 0;
}
