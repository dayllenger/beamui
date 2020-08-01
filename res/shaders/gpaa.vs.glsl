// Humus' geometric post-process anti-aliasing
// http://www.humus.name/index.php?page=3D&ID=86

in vec2 v_point0;
in vec2 v_point1;
in uint v_dataIndex;
out float dummy;    // workaround for a bug on Intel driver
flat out vec4 pack; // this value is provided by the 2nd segment point

out float gl_ClipDistance[4];

uniform vec2 pixelSize;
uniform int viewportHeight;

void fetchData(in int index, out mat3 transform, out float depth, out vec4 clip, out vec4 color);

void main()
{
    mat3 transform;
    float depth;
    vec4 clip;
    vec4 color;
    fetchData(int(v_dataIndex), transform, depth, clip, color);

    const vec2 pos0 = (transform * vec3(v_point0, 1)).xy;
    const vec2 pos1 = (transform * vec3(v_point1, 1)).xy;
    gl_Position.x = pos1.x * pixelSize.x * 2 - 1;
    gl_Position.y = 1 - pos1.y * pixelSize.y * 2; // user Y is reversed
    gl_Position.z = depth;
    gl_Position.w = 1;

    gl_ClipDistance[0] = -pos1.y + clip.w;
    gl_ClipDistance[1] = -pos1.x + clip.z;
    gl_ClipDistance[2] =  pos1.y - clip.y;
    gl_ClipDistance[3] =  pos1.x - clip.x;

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
        pack.w = 1;
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
