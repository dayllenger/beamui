/**
Bezier curve and circle arc flattening routines.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.flattener;

nothrow @safe:

import std.math : fabs, cos, sin, sqrt, isFinite, PI, PI_2;
import beamui.core.collections : Buf;
import beamui.core.linalg : Vec2;

// Bezier flattening is based on Maxim Shemanarev article
// https://web.archive.org/web/20190309181735/http://antigrain.com/research/adaptive_bezier/index.html
// It works, but requires further development

/// Convert cubic bezier curve into a list of points
void flattenCubicBezier(ref Buf!Vec2 output, Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3, bool endpointsToo)
in (isFinite(p0.x) && isFinite(p0.y))
in (isFinite(p1.x) && isFinite(p1.y))
in (isFinite(p2.x) && isFinite(p2.y))
in (isFinite(p3.x) && isFinite(p3.y))
{
    if (endpointsToo)
        output ~= p0;
    recursiveCubicBezier(output, p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y, 0);
    if (endpointsToo)
        output ~= p3;
}

private void recursiveCubicBezier(ref Buf!Vec2 output, float x1, float y1, float x2, float y2, float x3, float y3,
        float x4, float y4, int level)
{
    if (level > 10)
        return;

    enum distanceTolerance = 0.5f * 0.5f;

    // calculate all midpoints
    const x12 = (x1 + x2) / 2;
    const y12 = (y1 + y2) / 2;
    const x23 = (x2 + x3) / 2;
    const y23 = (y2 + y3) / 2;
    const x34 = (x3 + x4) / 2;
    const y34 = (y3 + y4) / 2;
    const x123 = (x12 + x23) / 2;
    const y123 = (y12 + y23) / 2;
    const x234 = (x23 + x34) / 2;
    const y234 = (y23 + y34) / 2;
    const x1234 = (x123 + x234) / 2;
    const y1234 = (y123 + y234) / 2;

    // try to approximate
    const dx = x4 - x1;
    const dy = y4 - y1;
    const d2 = fabs((x2 - x4) * dy - (y2 - y4) * dx);
    const d3 = fabs((x3 - x4) * dy - (y3 - y4) * dx);

    // check flatness
    if ((d2 + d3) * (d2 + d3) <= distanceTolerance * (dx * dx + dy * dy))
    {
        output ~= Vec2(x1234, y1234);
    }
    else
    {
        recursiveCubicBezier(output, x1, y1, x12, y12, x123, y123, x1234, y1234, level + 1);
        recursiveCubicBezier(output, x1234, y1234, x234, y234, x34, y34, x4, y4, level + 1);
    }
}

/// Convert quadratic bezier curve into a list of points
void flattenQuadraticBezier(ref Buf!Vec2 output, Vec2 p0, Vec2 p1, Vec2 p2, bool endpointsToo)
in (isFinite(p0.x) && isFinite(p0.y))
in (isFinite(p1.x) && isFinite(p1.y))
in (isFinite(p2.x) && isFinite(p2.y))
{
    if (endpointsToo)
        output ~= p0;
    recursiveQuadraticBezier(output, p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, 0);
    if (endpointsToo)
        output ~= p2;
}

private void recursiveQuadraticBezier(ref Buf!Vec2 output, float x1, float y1, float x2, float y2, float x3, float y3, int level)
{
    if (level > 10)
        return;

    enum distanceTolerance = 0.5f * 0.5f;

    // calculate all midpoints
    const x12 = (x1 + x2) / 2;
    const y12 = (y1 + y2) / 2;
    const x23 = (x2 + x3) / 2;
    const y23 = (y2 + y3) / 2;
    const x123 = (x12 + x23) / 2;
    const y123 = (y12 + y23) / 2;

    // try to approximate
    const dx = x3 - x1;
    const dy = y3 - y1;
    const d = fabs((x2 - x3) * dy - (y2 - y3) * dx);

    // check flatness
    if (d <= distanceTolerance)
    {
        output ~= Vec2(x123, y123);
    }
    else
    {
        recursiveQuadraticBezier(output, x1, y1, x12, y12, x123, y123, level + 1);
        recursiveQuadraticBezier(output, x123, y123, x23, y23, x3, y3, level + 1);
    }
}

/// Convert circular arc into a list of points
void flattenArc(ref Buf!Vec2 output, Vec2 center, float radius, float startAngle, float deltaAngle, bool endpointsToo)
in (isFinite(center.x) && isFinite(center.y))
in (isFinite(radius))
in (isFinite(startAngle))
in (isFinite(deltaAngle))
{
    const rx0 = radius * cos(startAngle);
    const ry0 = radius * sin(startAngle);
    if (endpointsToo)
        output ~= Vec2(center.x + rx0, center.y - ry0);

    deltaAngle = deltaAngle % (PI * 2);
    const angleOffset = fabs(deltaAngle);
    if (angleOffset < 1e-6f || radius < 1e-6f)
        return;

    // convert arc into a cubic spline, max 90 degrees for each segment
    const parts = cast(uint)(angleOffset / PI_2 + 1);
    const halfPartDA = (deltaAngle / parts) / 2;
    float kappa = fabs(4.0f / 3.0f * (1 - cos(halfPartDA)) / sin(halfPartDA));
    if (deltaAngle < 0)
        kappa = -kappa;

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

        recursiveCubicBezier(output, x0, y0, x1, y1, x2, y2, x3, y3, 0);
        if (i < parts || endpointsToo)
            output ~= Vec2(x3, y3);

        ax = bx;
        ay = by;
        x0 = x3;
        y0 = y3;
    }
}
