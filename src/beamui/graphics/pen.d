/**
Types and helpers for path stroking.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.pen;

nothrow:

import std.math : acos, atan2, sqrt, PI;
import beamui.core.collections : Buf;
import beamui.core.linalg : Vec2, crossProduct, dotProduct;
import beamui.core.math;
import beamui.graphics.flattener;
import beamui.graphics.path;

import beamui.core.logger;

/** Style of the line end points.

    See illustrations on $(LINK2 https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/lineCap, MDN).
*/
enum LineCap
{
    butt,
    round,
    square,
}

/** Style of corner created, when two lines meet.

    See illustrations on $(LINK2 https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/lineJoin, MDN).
*/
enum LineJoin
{
    miter,
    bevel,
    round,
}

/// A simple struct to hold stroke parameters
struct Pen
{
    float width = 1;
    LineCap cap;
    LineJoin join;
    float miterLimit = 10;
}

interface PathIter
{
    bool next(out const(Vec2)[] points, out bool closed) nothrow;
}

interface StrokeBuilder
{
nothrow:
    void beginContour();
    void add(Vec2 left, Vec2 right);
    Buf!Vec2* beginFanLeft(Vec2 center);
    Buf!Vec2* beginFanRight(Vec2 center);
    void endFan();
    void breakStrip();
    void endContour();
}

/// Build strokes from given path and stroke parameters
void expandStrokes(PathIter iter, Pen pen, StrokeBuilder builder)
in (iter)
in (builder)
{
    if (pen.width < 0.01f)
        return;

    pen.width = clamp(pen.width, 0.01f, 1000.0f);
    pen.miterLimit = clamp(pen.miterLimit, 0.01f, 100.0f);

    const(Vec2)[] points;
    bool closed;
    while (iter.next(points, closed))
    {
        builder.beginContour();
        expandSubpath(points, closed, pen, builder);
        builder.endContour();
    }
}

private void expandSubpath(const Vec2[] points, bool loop, ref const Pen pen, StrokeBuilder builder)
{
    // generated points run in such order:
    //  0            2 4
    //  x----->------x 5
    //  1   ^     3/6 \
    //      path       \
    //                8 x 7

    const r = pen.width / 2;

    if (points.length >= 3) // common case first
    {
        // start
        Vec2 norm1;
        Vec2 first = points[0];
        const firstN = (first - points[1]).normalized;
        norm1 = firstN.rotated90fromXtoY;
        if (!loop)
        {
            if (pen.cap == LineCap.round)
                makeRoundCap(first, firstN * r, builder);
            else if (pen.cap == LineCap.square)
                first += firstN * r;
        }
        const firstV = norm1 * r;
        builder.add(first + firstV, first - firstV);

        // the body
        Vec2 norm0;
        foreach (i; 2 .. points.length)
        {
            const p = points[i - 1];
            const p1 = points[i];
            // calculate segment normals
            norm0 = norm1;
            norm1 = (p1 - p).rotated90fromYtoX.normalized;
            const ncos = dotProduct(norm0, norm1);
            // skip collinear
            if (!fequal6(ncos, 1))
                makeJoin(p, norm0, norm1, ncos, r, pen.join, pen.miterLimit, builder);
        }
        // end
        Vec2 last = points[$ - 1];
        const lastN = (last - points[$ - 2]).normalized;
        if (loop)
        {
            // the last point is equal to the first point here
            norm0 = lastN.rotated90fromYtoX;
            norm1 = firstN.rotated90fromXtoY;
            makeJoin(last, norm0, norm1, dotProduct(norm0, norm1), r, pen.join, pen.miterLimit, builder);
            // close the loop
            builder.add(first + firstV, first - firstV);
        }
        else
        {
            if (pen.cap == LineCap.square)
                last += lastN * r;
            const v = lastN.rotated90fromYtoX * r;
            builder.add(last + v, last - v);
            if (pen.cap == LineCap.round)
                makeRoundCap(last, lastN * r, builder);
        }
    }
    // the simplest cases next
    else if (points.length == 2)
    {
        const outsideN = (points[0] - points[1]).normalized;
        const outside = outsideN * r;
        const v = outside.rotated90fromXtoY;

        if (pen.cap == LineCap.square)
        {
            // generate just one rectangle
            builder.add(points[0] + outside + v, points[0] + outside - v);
            builder.add(points[1] - outside + v, points[1] - outside - v);
        }
        else
        {
            // starting cap
            if (pen.cap == LineCap.round)
                makeRoundCap(points[0], outside, builder);
            // the body
            builder.add(points[0] + v, points[0] - v);
            builder.add(points[1] + v, points[1] - v);
            // ending cap
            if (pen.cap == LineCap.round)
                makeRoundCap(points[1], -outside, builder);
        }
    }
    else if (points.length == 1)
    {
        if (pen.cap == LineCap.round)
        {
            // make a circle
            makeRoundCap(points[0], Vec2(-r, 0), builder);
            makeRoundCap(points[0], Vec2(r, 0), builder);
        }
        else if (pen.cap == LineCap.square)
        {
            // make a square
            const p = points[0];
            builder.add(Vec2(p.x - r, p.y - r), Vec2(p.x - r, p.y + r));
            builder.add(Vec2(p.x + r, p.y - r), Vec2(p.x + r, p.y + r));
        }
    }
}

private void makeJoin(Vec2 p, Vec2 n0, Vec2 n1, float ncos, float r, LineJoin type, float miterLimit, StrokeBuilder builder)
{
    // if flat enough, join simply by the first points
    const mul1 = r / 2;
    const mul2 = r / 32;
    const cusp = type != LineJoin.round && fequal2(ncos * mul1, -mul1);
    if (cusp || fequal2(ncos * mul2, mul2))
    {
        const v = n1 * r;
        if (ncos < 0) // acute angle, need to flip
        {
            builder.add(p - v, p + v);
            builder.breakStrip();
        }
        builder.add(p + v, p - v);
    }
    else
    {
        const v0 = n0 * r;
        const v1 = n1 * r;

        if (type == LineJoin.round)
        {
            const upper = crossProduct(n0, n1) > 0;
            float startAngle = atan2(-n0.y, n0.x);
            float angleOffset = acos(ncos);
            if (upper)
                angleOffset *= -1;
            else
                startAngle -= PI;

            builder.add(p + v0, p - v0);

            Buf!Vec2* positions = upper ? builder.beginFanLeft(p - v0) : builder.beginFanRight(p + v0);
            flattenArc(*positions, p, r, startAngle, angleOffset, true);
            builder.endFan();

            builder.add(p + v1, p - v1);
        }
        else
        {
            const sum = n0 + n1;
            // v = r * n / cos alpha/2
            // |sum| = sqrt(n0^2 + n1^2 + 2 n0 n1 cos alpha) = sqrt(2 + 2 cos alpha) =
            // = 2sqrt((1 + cos alpha)/2) = 2|cos alpha/2|
            // => v = 2r sum / |sum|^2
            Vec2 v = sum * (2 / sum.magnitudeSquared);
            const l2 = v.magnitudeSquared;

            if (type == LineJoin.bevel || l2 > miterLimit * miterLimit)
            {
                builder.add(p + v0, p - v0);
                builder.add(p + v1, p - v1);
            }
            else // miter
            {
                v *= r;
                const upper = crossProduct(n0, n1) > 0;
                if (upper)
                {
                    builder.add(p + v, p - v0);
                    builder.breakStrip();
                    builder.add(p + v, p - v1);
                }
                else
                {
                    builder.add(p + v0, p - v);
                    builder.breakStrip();
                    builder.add(p + v1, p - v);
                }
            }
        }
    }
}

private void makeRoundCap(Vec2 p, Vec2 outside, StrokeBuilder builder)
{
    Buf!Vec2* positions = builder.beginFanLeft(p);

    const n = outside.rotated90fromYtoX;
    outside *= 4.0f / 3.0f;
    flattenCubicBezier(*positions, p + n, p + n + outside, p - n + outside, p - n, true);

    builder.endFan();
}
