in vec2 v_position;
in uint v_dataIndex;

#ifdef UV
in vec2 v_texCoord;
out vec2 uv;
uniform vec2 texPixelSize;
#endif

#ifdef DATA_COLOR
flat out vec4 brushColor;
#else
#ifndef NO_COLOR
flat out float opacity;
#endif
#endif

#ifdef COMPOSITION
out vec2 texCoord;
uniform int texHeight;
uniform ivec2 texPos;
#endif

uniform vec2 pixelSize;

#ifdef NO_COLOR
uniform float customDepth;
#endif

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
#ifndef NO_COLOR
    opacity = color.a;
#endif
#endif

    const vec3 pos = transform * vec3(v_position, 1);
    const vec2 npos = pos.xy * pixelSize * 2.0 - 1.0;
    gl_Position.x =  npos.x;
    gl_Position.y = -npos.y; // user Y is reversed
#ifdef NO_COLOR
    gl_Position.z = max(depth, customDepth);
#else
    gl_Position.z = depth;
#endif
    gl_Position.w = 1.0;

    clipByRect(pos.xy, clip);

#ifdef UV
    uv = v_texCoord * texPixelSize;
#endif
#ifdef COMPOSITION
    texCoord = vec2(texPos.x + v_position.x, texHeight - texPos.y - v_position.y);
#endif
}
