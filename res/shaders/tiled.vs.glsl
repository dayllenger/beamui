in uvec2 v_tile;
in uint v_segments;
in uint v_dataIndex;
flat out ivec2 segments;
flat out vec2 shift;
flat out float width;
flat out float contrast;

#ifdef DATA_COLOR
flat out vec4 brushColor;
#else
flat out float opacity;
#endif

uniform vec2 pixelSize;

void fetchData(in int index, out mat3 transform, out float depth, out vec4 clip, out vec4 color);
void clipByRect(in vec2 pos, in vec4 clip);

void main()
{
    mat3 transform;
    float depth;
    vec4 clip;
    vec4 color;
    fetchData(int(v_dataIndex), transform, depth, clip, color);
#ifdef DATA_COLOR
    brushColor = color;
#else
    opacity = color.a;
#endif

    segments = ivec2(int(v_segments >> 8), int(v_segments) & 0xFF);
    shift = transform[2].xy / TILE_SIZE;
    width = transform[0][0];
    contrast = transform[1][1];

    const vec2 offset = vec2(gl_VertexID & 1, (gl_VertexID & 2) == 2);
    const vec2 pos = (vec2(v_tile) + offset) * TILE_SIZE + transform[2].xy;
    const vec2 npos = pos * pixelSize * 2.0 - 1.0;
    gl_Position.x =  npos.x;
    gl_Position.y = -npos.y; // user Y is reversed
    gl_Position.z = depth;
    gl_Position.w = 1.0;

    clipByRect(pos, clip);
}
