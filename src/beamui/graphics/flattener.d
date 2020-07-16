/**
Bezier curve and circle arc flattening routines.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.flattener;

nothrow @safe:

import std.math : fabs, cos, sin, isFinite, PI, PI_2;
import beamui.core.linalg : Vec2;

// Bezier flattening is based on Maxim Shemanarev article
// https://web.archive.org/web/20190309181735/http://antigrain.com/research/adaptive_bezier/index.html
// It works, but requires further development

/// Convert quadratic bezier curve into a list of points
void flattenQuadraticBezier(O)(ref O output, Vec2 p0, Vec2 p1, Vec2 p2, bool endpoints, float minDist = 0.7f)
in (isFinite(p0.x) && isFinite(p0.y))
in (isFinite(p1.x) && isFinite(p1.y))
in (isFinite(p2.x) && isFinite(p2.y))
{
    if (endpoints)
        output.put(p0);
    Flattener!O(minDist).quadratic(output, p0, p1, p2, 0);
    if (endpoints)
        output.put(p2);
}

/// Convert cubic bezier curve into a list of points
void flattenCubicBezier(O)(ref O output, Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, bool endpoints, float minDist = 0.7f)
in (isFinite(p0.x) && isFinite(p0.y))
in (isFinite(p1.x) && isFinite(p1.y))
in (isFinite(p2.x) && isFinite(p2.y))
in (isFinite(p3.x) && isFinite(p3.y))
{
    if (endpoints)
        output.put(p0);
    Flattener!O(minDist).cubic(output, p0, p1, p2, p3, 0);
    if (endpoints)
        output.put(p3);
}

/// Convert circular arc into a list of points
void flattenArc(O)(ref O output, Vec2 center, float radius, float startAngle, float deltaAngle, bool endpoints, float minDist = 0.7f)
in (isFinite(center.x) && isFinite(center.y))
in (isFinite(radius))
in (isFinite(startAngle))
in (isFinite(deltaAngle))
{
    const rx0 = radius * cos(startAngle);
    const ry0 = radius * sin(startAngle);
    if (endpoints)
        output.put(Vec2(center.x + rx0, center.y - ry0));

    deltaAngle = deltaAngle % (PI * 2);
    const angleOffset = fabs(deltaAngle);
    if (angleOffset < 1e-6f || radius < 1e-6f)
        return;

    // convert arc into a cubic spline, max 90 degrees for each segment
    const parts = cast(uint)(angleOffset / PI_2 + 1);
    const halfPartDA = (deltaAngle / parts) * 0.5f;
    float kappa = fabs(4.0f / 3.0f * (1 - cos(halfPartDA)) / sin(halfPartDA));
    if (deltaAngle < 0)
        kappa = -kappa;

    const flattener = Flattener!O(minDist);
    float ax = rx0, ay = ry0;
    float x0 = center.x + ax, y0 = center.y - ay;
    foreach (i; 1 .. parts + 1)
    {
        const b = startAngle + deltaAngle * i / parts;
        const bx = radius * cos(b);
        const by = radius * sin(b);

        const x3 = center.x + bx;
        const y3 = center.y - by;
        const x1 = x0 - kappa * ay;
        const y1 = y0 - kappa * ax;
        const x2 = x3 + kappa * by;
        const y2 = y3 + kappa * bx;

        flattener.cubic(output, Vec2(x0, y0), Vec2(x1, y1), Vec2(x2, y2), Vec2(x3, y3), 0);
        if (i < parts || endpoints)
            output.put(Vec2(x3, y3));

        ax = bx;
        ay = by;
        x0 = x3;
        y0 = y3;
    }
}

private struct Flattener(O)
{
    float distanceTolerance = 0.5f;

    this(float minDist)
    in (minDist > 0)
    {
        distanceTolerance = minDist * minDist;
    }

    void quadratic(ref O output, Vec2 p1, Vec2 p2, Vec2 p3, int level) const
    {
        if (level > 10)
            return;

        // calculate all midpoints
        const Vec2 p12 = (p1 + p2) * 0.5f;
        const Vec2 p23 = (p2 + p3) * 0.5f;
        const Vec2 p123 = (p12 + p23) * 0.5f;

        // try to approximate
        const Vec2 dp = p3 - p1;
        const d = fabs((p2.x - p3.x) * dp.y - (p2.y - p3.y) * dp.x);

        // check flatness
        if (d <= distanceTolerance)
        {
            output.put(p123);
        }
        else
        {
            quadratic(output, p1, p12, p123, level + 1);
            quadratic(output, p123, p23, p3, level + 1);
        }
    }

    void cubic(ref O output, Vec2 p1, Vec2 p2, Vec2 p3, Vec2 p4, int level) const
    {
        if (level > 10)
            return;

        // calculate all midpoints
        const Vec2 p12 = (p1 + p2) * 0.5f;
        const Vec2 p23 = (p2 + p3) * 0.5f;
        const Vec2 p34 = (p3 + p4) * 0.5f;
        const Vec2 p123 = (p12 + p23) * 0.5f;
        const Vec2 p234 = (p23 + p34) * 0.5f;
        const Vec2 p1234 = (p123 + p234) * 0.5f;

        // try to approximate
        const Vec2 dp = p4 - p1;
        const d2 = fabs((p2.x - p4.x) * dp.y - (p2.y - p4.y) * dp.x);
        const d3 = fabs((p3.x - p4.x) * dp.y - (p3.y - p4.y) * dp.x);

        // check flatness
        if ((d2 + d3) * (d2 + d3) <= distanceTolerance * dp.magnitudeSquared)
        {
            output.put(p1234);
        }
        else
        {
            cubic(output, p1, p12, p123, p1234, level + 1);
            cubic(output, p1234, p234, p34, p4, level + 1);
        }
    }
}
