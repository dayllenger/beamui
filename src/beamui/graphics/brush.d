/**
Brush contains color information, applied in a drawing.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.brush;

import std.algorithm : sort;
import beamui.core.linalg : Vec2, Mat2x3;
import beamui.core.math : clamp, fequal6, fzero6;
import beamui.graphics.colors : Color;
import beamui.graphics.drawbuf : ColorDrawBuf;

enum BrushType
{
    solid,
    linear,
    radial,
    pattern,
}

private enum PaintOpacity
{
    opaque,
    hidden,
    translucent,
}

struct Brush
{
    @property
    {
        BrushType type() const { return _type; }

        Color solid() const { assert(type == BrushType.solid); return _solid; }
        ref const(LinearGradient) linear() const { assert(type == BrushType.linear); return _linear; }
        ref const(RadialGradient) radial() const { assert(type == BrushType.radial); return _radial; }
        ref const(Pattern) pattern() const { assert(type == BrushType.pattern); return _pattern; }

        float opacity() const { return _opacity; }
        /// ditto
        void opacity(float value)
        {
            _opacity = clamp(value, 0, 1);
        }

        bool isOpaque() const
        {
            return _paintOpacity == PaintOpacity.opaque && fequal6(_opacity, 1);
        }
        bool isFullyTransparent() const
        {
            return _paintOpacity == PaintOpacity.hidden || fzero6(_opacity);
        }
    }

    private BrushType _type;
    private union
    {
        Color _solid;
        LinearGradient _linear;
        RadialGradient _radial;
        Pattern _pattern;
    }
    private float _opacity = 1;
    private PaintOpacity _paintOpacity;

    static Brush fromSolid(Color color)
    {
        Brush br;
        br._type = BrushType.solid;
        br._solid = color;
        br._paintOpacity = color.isOpaque ? PaintOpacity.opaque :
            color.isFullyTransparent ? PaintOpacity.hidden : PaintOpacity.translucent;
        return br;
    }

    static Brush fromPattern(ColorDrawBuf image, Mat2x3 transform = Mat2x3.identity)
    {
        Brush br;
        br._type = BrushType.pattern;
        br._pattern = Pattern(image, transform);
        br._paintOpacity = image ? PaintOpacity.opaque : PaintOpacity.hidden;
        return br;
    }
}

struct GradientBuilder
{
    private struct ColorStop
    {
        float offset = 0;
        Color color;
    }
    private ColorStop[] _stops;

    ref GradientBuilder addStop(float offset, Color color)
    {
        offset = clamp(offset, 0, 1);
        // replace if such offset already exists
        foreach (ref s; _stops)
        {
            if (fequal6(offset, s.offset))
            {
                s.color = color;
                return this;
            }
        }
        _stops ~= ColorStop(offset, color);
        return this;
    }

    Brush makeLinear(float startX, float startY, float endX, float endY)
    {
        bool success;
        Brush br = make(success);
        if (success)
        {
            br._type = BrushType.linear;
            br._linear.start = Vec2(startX, startY);
            br._linear.end = Vec2(endX, endY);
        }
        return br;
    }

    Brush makeRadial(float centerX, float centerY, float radius)
    {
        bool success;
        Brush br = make(success);
        if (success)
        {
            br._type = BrushType.radial;
            br._radial.center = Vec2(centerX, centerY);
            br._radial.radius = clamp(radius, 0, float.max);
        }
        return br;
    }

    private Brush make(out bool success)
    {
        if (_stops.length == 0)
            return Brush.fromSolid(Color.transparent);
        if (_stops.length == 1)
            return Brush.fromSolid(_stops[0].color);

        PaintOpacity op = _stops[0].color.isOpaque ? PaintOpacity.opaque :
            _stops[0].color.isFullyTransparent ? PaintOpacity.hidden : PaintOpacity.translucent;
        bool singleColor = true;

        foreach (i; 1 .. _stops.length)
        {
            if (singleColor && _stops[i].color != _stops[i - 1].color)
                singleColor = false;
            if (op == PaintOpacity.opaque)
            {
                if (!_stops[i].color.isOpaque)
                    op = PaintOpacity.translucent;
            }
            else if (op == PaintOpacity.hidden)
            {
                if (!_stops[i].color.isFullyTransparent)
                    op = PaintOpacity.translucent;
            }
        }
        if (op == PaintOpacity.hidden)
            return Brush.fromSolid(Color.transparent);
        if (singleColor)
            return Brush.fromSolid(_stops[0].color);

        sort!`a.offset < b.offset`(_stops);

        auto stops = new float[_stops.length];
        auto colors = new Color[_stops.length];
        foreach (i, s; _stops)
        {
            stops[i] = s.offset;
            colors[i] = s.color;
        }

        Brush br;
        // hack: all gradients have the same first fields
        br._linear.stops = stops;
        br._linear.colors = colors;
        br._paintOpacity = op;
        success = true;
        return br;
    }
}

struct LinearGradient
{
    float[] stops;
    Color[] colors;
    Vec2 start;
    Vec2 end;
}

struct RadialGradient
{
    float[] stops;
    Color[] colors;
    Vec2 center;
    float radius = 0;
}

struct Pattern
{
    ColorDrawBuf image;
    Mat2x3 transform;
}
