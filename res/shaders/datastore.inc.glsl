uniform sampler2D dataStore;

#define DATA_ROW_LENGTH 256
#define DATA_TEXELS_IN_CHUNK 4

void fetchData(in int index, out mat3 transform, out float depth, out vec4 clip, out vec4 color)
{
    const int u = index % DATA_ROW_LENGTH;
    const int v = index / DATA_ROW_LENGTH;
    const vec4 data1 = texelFetch(dataStore, ivec2(u * DATA_TEXELS_IN_CHUNK    , v), 0);
    const vec4 data2 = texelFetch(dataStore, ivec2(u * DATA_TEXELS_IN_CHUNK + 1, v), 0);
    clip = texelFetch(dataStore, ivec2(u * DATA_TEXELS_IN_CHUNK + 2, v), 0);
#ifndef NO_COLOR
    color = texelFetch(dataStore, ivec2(u * DATA_TEXELS_IN_CHUNK + 3, v), 0);
#endif

    // (a b c) (d e f) =>
    // (a) (d)    (a) (b) (c)
    // (b) (e) => (d) (e) (f)
    // (c) (f)    (0) (0) (1)
    transform = mat3(
        data1.x, data1.w, 0.0,
        data1.y, data2.x, 0.0,
        data1.z, data2.y, 1.0
    );
    depth = data2.z;
}
