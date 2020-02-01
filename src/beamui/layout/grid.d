/**
A small subset of CSS Grid Layout.

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.grid;

import beamui.core.geometry;
import beamui.core.units : Length, LengthUnit;

enum GridFlow : ubyte
{
    row,
    column,
}

struct TrackSize
{
    private enum Type : ubyte
    {
        common,
        fr,
        minContent,
        maxContent,
    }
    private union
    {
        Length common;
        float fr;
    }
    private Type type;

    private this(int);

    static TrackSize automatic()
    {
        return TrackSize.init;
    }
    static TrackSize fromLength(Length len)
    {
        TrackSize ts;
        ts.common = len;
        return ts;
    }
    static TrackSize fromFraction(float fr)
        in(fr >= 0)
    {
        TrackSize ts;
        ts.fr = fr;
        ts.type = Type.fr;
        return ts;
    }
    static TrackSize minContent()
    {
        TrackSize ts;
        ts.type = Type.minContent;
        return ts;
    }
    static TrackSize maxContent()
    {
        TrackSize ts;
        ts.type = Type.maxContent;
        return ts;
    }
}
