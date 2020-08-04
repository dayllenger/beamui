#ifdef TILED_STROKE
in uvec2 v_tile;
in uint v_segments;
flat out ivec2 segments;
flat out float width;
flat out float contrast;
#else
in vec2 v_position;
#endif

in uint v_dataIndex;

#ifdef UV
in vec2 v_texCoord;
out vec2 uv;
uniform vec2 texPixelSize;
#endif

#ifdef DATA_COLOR
flat out vec4 brushColor;
#else
flat out float opacity;
#endif

#ifdef COMPOSITION
out vec2 texCoord;
uniform int texHeight;
uniform ivec2 texPos;
#endif

#ifdef CUSTOM_DEPTH
uniform float customDepth;
#endif

out float gl_ClipDistance[4];

uniform vec2 pixelSize;

void fetchData(in int index, out mat3 transform, out float depth, out vec4 clip, out vec4 color);

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

#ifdef TILED_STROKE
    segments = ivec2(int(v_segments >> 8), int(v_segments) & 0xFF);
    width = transform[0][0];
    contrast = transform[1][1];

    const vec2 offset = vec2(gl_VertexID & 1, (gl_VertexID & 2) == 2);
    const vec2 pos = (vec2(v_tile) + offset) * TILE_SIZE;
#else
    const vec3 pos = transform * vec3(v_position, 1);
#endif

    gl_Position.x = pos.x * pixelSize.x * 2.0 - 1.0;
    gl_Position.y = 1.0 - pos.y * pixelSize.y * 2.0; // user Y is reversed
#ifdef CUSTOM_DEPTH
    gl_Position.z = max(depth, customDepth);
#else
    gl_Position.z = depth;
#endif
    gl_Position.w = 1.0;

    gl_ClipDistance[0] = -pos.y + clip.w;
    gl_ClipDistance[1] = -pos.x + clip.z;
    gl_ClipDistance[2] =  pos.y - clip.y;
    gl_ClipDistance[3] =  pos.x - clip.x;

#ifdef UV
    uv = v_texCoord * texPixelSize;
#endif
#ifdef COMPOSITION
    texCoord = vec2(texPos.x + v_position.x, texHeight - texPos.y - v_position.y);
#endif
}
