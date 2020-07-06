/**
Media queries.

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.media;

import beamui.core.config;

struct MediaQueryInput
{
    int width;
    int height;
    float dpi = 96;
    float dpr = 1;
    enum bool grid = BACKEND_CONSOLE;
}
