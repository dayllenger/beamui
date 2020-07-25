flat in vec4 brushColor;
out vec4 f_color;

void main()
{
#ifdef TILED_STROKE
    float a = compute_stroke_sdf();
    f_color = brushColor * a;
#else
    f_color = brushColor;
#endif
}
