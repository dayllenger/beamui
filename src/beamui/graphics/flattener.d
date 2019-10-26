/**
Bezier curve and circle arc flattening routines.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.flattener;

nothrow:

import std.math : fabs, cos, sin, sqrt, PI, PI_2;
import beamui.core.collections : Buf;
import beamui.core.linalg : Vec2;
import beamui.core.math : fequal2, fzero6;

// Bezier flattening is based on Maxim Shemanarev article
// https://web.archive.org/web/20190309181735/http://antigrain.com/research/adaptive_bezier/index.html
// It works, but requires further development

/// Convert cubic bezier curve into a list of points
void flattenCubicBezier(Vec2 p0, Vec2 p1, Vec2 p2, Vec2 p3,
    bool endpointsToo, ref Buf!Vec2 output)
{
    if (endpointsToo)
        output ~= p0;
    recursiveCubicBezier(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y, 0, output);
    if (endpointsToo)
        output ~= p3;
}

private void recursiveCubicBezier(float x1, float y1, float x2, float y2,
    float x3, float y3, float x4, float y4, int level, ref Buf!Vec2 output)
{
    if (level > 10) return;

    enum distanceTolerance = 0.5f * 0.5f;

    // calculate all midpoints
    const x12  = (x1 + x2) / 2;
    const y12  = (y1 + y2) / 2;
    const x23  = (x2 + x3) / 2;
    const y23  = (y2 + y3) / 2;
    const x34  = (x3 + x4) / 2;
    const y34  = (y3 + y4) / 2;
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
       recursiveCubicBezier(x1, y1, x12, y12, x123, y123, x1234, y1234, level + 1, output);
       recursiveCubicBezier(x1234, y1234, x234, y234, x34, y34, x4, y4, level + 1, output);
    }
}

/// Convert quadratic bezier curve into a list of points
void flattenQuadraticBezier(Vec2 p0, Vec2 p1, Vec2 p2,
    bool endpointsToo, ref Buf!Vec2 output)
{
    if (endpointsToo)
        output ~= p0;
    recursiveQuadraticBezier(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, 0, output);
    if (endpointsToo)
        output ~= p2;
}

private void recursiveQuadraticBezier(float x1, float y1, float x2, float y2, float x3, float y3,
    int level, ref Buf!Vec2 output)
{
    if (level > 10) return;

    enum distanceTolerance = 0.5f * 0.5f;

    // calculate all midpoints
    const x12  = (x1 + x2) / 2;
    const y12  = (y1 + y2) / 2;
    const x23  = (x2 + x3) / 2;
    const y23  = (y2 + y3) / 2;
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
        recursiveQuadraticBezier(x1, y1, x12, y12, x123, y123, level + 1, output);
        recursiveQuadraticBezier(x123, y123, x23, y23, x3, y3, level + 1, output);
    }
}

/// Convert circular arc into a list of points
void flattenArc(Vec2 center, float radius, float startAngle, float angleOffset,
    bool endpointsToo, ref Buf!Vec2 output)
{
    if (radius < 0)
        return;

    const rx0 = radius * cos(startAngle);
    const ry0 = radius * sin(startAngle);

    if (endpointsToo)
        output ~= Vec2(center.x + rx0, center.y - ry0);

    if (fzero6(angleOffset) || fzero6(radius))
        return;

    // Based on https://stackoverflow.com/a/44829356, just works.
    // We cut long arcs here by 3 cubic bezier curves, so algorithm becomes very simple.

    enum FULL = PI * 2;

    angleOffset = angleOffset % FULL;
    const endAngle = startAngle + angleOffset;

    const rx = radius * cos(endAngle);
    const ry = radius * sin(endAngle);

    const offset = fabs(angleOffset);
    if (offset > FULL / 3)
    {
        const int dir = angleOffset > 0 ? 1 : -1;
        const rx1 = radius * cos(startAngle + dir * FULL / 3);
        const ry1 = radius * sin(startAngle + dir * FULL / 3);
        if (!fequal2(rx, rx1) || !fequal2(ry, ry1))
        {
            if (offset > FULL * 2 / 3)
            {
                const rx2 = radius * cos(startAngle + dir * FULL * 2 / 3);
                const ry2 = radius * sin(startAngle + dir * FULL * 2 / 3);
                if (!fequal2(rx, rx2) || !fequal2(ry, ry2))
                {
                    flattenArcPart(center.x, center.y, rx0, ry0, rx1, ry1, true, output);
                    flattenArcPart(center.x, center.y, rx1, ry1, rx2, ry2, true, output);
                    flattenArcPart(center.x, center.y, rx2, ry2, rx, ry, endpointsToo, output);
                    return;
                }
            }
            flattenArcPart(center.x, center.y, rx0, ry0, rx1, ry1, true, output);
            flattenArcPart(center.x, center.y, rx1, ry1, rx, ry, endpointsToo, output);
            return;
        }
    }
    flattenArcPart(center.x, center.y, rx0, ry0, rx, ry, endpointsToo, output);
}

private void flattenArcPart(float cx, float cy, float ax, float ay, float bx, float by,
    bool lastToo, ref Buf!Vec2 output)
{
    const q1 = ax * ax + ay * ay;
    const q2 = q1 + ax * bx + ay * by;
    const k2 = 4.0f / 3.0f * (sqrt(2 * q1 * q2) - q2) / (ax * by - ay * bx);

    const x0 = cx + ax;
    const y0 = cy - ay;
    const x1 = cx + ax - k2 * ay;
    const y1 = cy - ay - k2 * ax;
    const x2 = cx + bx + k2 * by;
    const y2 = cy - by + k2 * bx;
    const x3 = cx + bx;
    const y3 = cy - by;

    recursiveCubicBezier(x0, y0, x1, y1, x2, y2, x3, y3, 0, output);
    if (lastToo)
        output ~= Vec2(x3, y3);
}
