out float gl_ClipDistance[4];

void clipByRect(in vec2 pos, in vec4 clip)
{
    gl_ClipDistance[0] = -pos.y + clip.w;
    gl_ClipDistance[1] = -pos.x + clip.z;
    gl_ClipDistance[2] =  pos.y - clip.y;
    gl_ClipDistance[3] =  pos.x - clip.x;
}
