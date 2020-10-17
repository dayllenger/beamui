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
import beamui.graphics.bitmap : Bitmap;
import beamui.graphics.colors : Color;

/// Enumerates supported brush types
enum BrushType
{
    solid,
    linear,
    radial,
    pattern,
}

private enum Opaque
{
    hidden,
    no,
    yes
}

/** Brush is either a color, a gradient, or an image pattern.

    Brush also allows to add some transparency to these fill types.
*/
struct Brush
{
    @property
    {
        /// The brush type. Once brush constructed, it cannot change
        BrushType type() const
        {
            return _type;
        }

        /// Underlying data. The `type` must match in order to get it
        Color solid() const
        {
            assert(type == BrushType.solid);
            return _solid;
        }
        /// ditto
        ref const(LinearGradient) linear() const return
        {
            assert(type == BrushType.linear);
            return _linear;
        }
        /// ditto
        ref const(RadialGradient) radial() const return
        {
            assert(type == BrushType.radial);
            return _radial;
        }
        /// ditto
        ref const(ImagePattern) pattern() const return
        {
            assert(type == BrushType.pattern);
            return _pattern;
        }

        /// Paint opacity, in [0, 1] range
        float opacity() const
        {
            return _opacity;
        }
        /// ditto
        void opacity(float value)
        {
            _opacity = clamp(value, 0, 1);
        }

        /// True if a painter doesn't need to handle alpha values using this brush
        bool isOpaque() const
        {
            return _opq == Opaque.yes && fequal6(_opacity, 1);
        }
        /// True if this brush does not contribute any color
        bool isFullyTransparent() const
        {
            return _opq == Opaque.hidden || fzero6(_opacity);
        }
    }

    private
    {
        BrushType _type;
        union
        {
            Color _solid;
            LinearGradient _linear;
            RadialGradient _radial;
            ImagePattern _pattern;
        }

        float _opacity = 1;
        Opaque _opq = Opaque.hidden; // because the default color is fully transparent black
    }

    /// Create a brush for solid color fill
    static Brush fromSolid(Color color)
    {
        Brush br;
        br._type = BrushType.solid;
        br._solid = color;
        br._opq = color.isOpaque ? Opaque.yes : color.isFullyTransparent ? Opaque.hidden : Opaque.no;
        return br;
    }

    /// Create a brush with an image pattern
    static Brush fromPattern(ref const Bitmap image, Mat2x3 transform = Mat2x3.identity)
    {
        Brush br;
        br._type = BrushType.pattern;
        br._pattern = ImagePattern(&image, transform);
        br._opq = image ? Opaque.yes : Opaque.hidden;
        return br;
    }
}

/// Gradient builder is a utility struct for making different gradient brushes
struct GradientBuilder
{
    private struct ColorStop
    {
        float offset = 0;
        Color color;
    }

    private ColorStop[] _stops;

    /// Add a colorstop. The method clamps `offset` to [0, 1] range
    ref GradientBuilder addStop(float offset, Color color) return
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

    /// Make a brush for a linear gradient between two 2D endpoints
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

    /// Make a brush for a radial gradient with some center and radius
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

        bool singleColor = true;
        Opaque op = Opaque.no;
        if (_stops[0].color.isOpaque)
            op = Opaque.yes;
        else if (_stops[0].color.isFullyTransparent)
            op = Opaque.hidden;

        foreach (i; 1 .. _stops.length)
        {
            if (singleColor && _stops[i].color != _stops[i - 1].color)
                singleColor = false;
            if (op == Opaque.yes)
            {
                if (!_stops[i].color.isOpaque)
                    op = Opaque.no;
            }
            else if (op == Opaque.hidden)
            {
                if (!_stops[i].color.isFullyTransparent)
                    op = Opaque.no;
            }
        }
        if (op == Opaque.hidden)
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
        br._opq = op;
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

struct ImagePattern
{
    const(Bitmap)* image;
    Mat2x3 transform;
}
