flat in float opacity;
out vec4 f_color;

uniform int viewportHeight;
uniform sampler2D tex;
uniform vec2 position; // 0 .. 1
uniform vec2 size;     // 0 .. 1
uniform ivec2 imgSize;
uniform mat3x2 matrix;

void main()
{
    vec2 pos = (mat3(matrix) * vec3(gl_FragCoord.x, viewportHeight - gl_FragCoord.y, 1)).xy;
    vec2 uv = pos / imgSize;
    // get UV derivatives before wrapping and use textureGrad(),
    // because texture() takes a wrong mipmap level on tile borders
    vec2 dx = dFdx(uv) * size;
    vec2 dy = dFdy(uv) * size;
    uv = position + size * fract(uv);
    f_color = textureGrad(tex, uv, dx, dy) * opacity;
}
