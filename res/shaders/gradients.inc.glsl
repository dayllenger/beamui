
// included into linear and radial
float calc_offset(in float fraction)
{
    for (int i = 0; i < MAX_STOPS; i++)
    {
        if (i + 1 == stopsCount)
            return float(i);
        float b = stops[i + 1];
        if (fraction < b)
        {
            float a = stops[i];
            float l = b - a;
            return i + (l > 0 ? (fraction - a) / l : 0);
        }
    }
}
