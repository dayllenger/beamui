in vec2 v_position;
in uint v_dataIndex;

#ifdef UV
in vec2 v_texCoord;
out vec2 uv;
uniform vec2 texPixelSize;
#endif

#ifdef DATA_COLOR
flat out vec4 brushColor;
#endif

#ifdef COMPOSITION
out vec2 texCoord;
uniform int texHeight;
uniform ivec2 texPos;
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
#endif

    const vec3 pos = transform * vec3(v_position, 1);
    gl_Position.x = pos.x * pixelSize.x * 2 - 1;
    gl_Position.y = 1 - pos.y * pixelSize.y * 2; // user Y is reversed
    gl_Position.z = depth;
    gl_Position.w = 1;

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
