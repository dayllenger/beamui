/**
Path that outlines a complex figure.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.path;

import std.math;
import beamui.core.collections : Buf;
import beamui.core.geometry : Rect;
import beamui.core.linalg : Mat2x3, Vec2, Vec2d;
import beamui.core.math;
import beamui.graphics.flattener;

struct SubPath
{
nothrow:
    const(Path.Command)[] commands;
    const(Vec2)[] points;
    bool closed;
    Rect bounds;

    uint flatten(bool transform)(ref Buf!Vec2 output, Mat2x3 mat, float pixelSize = 1) const
    {
        const len = output.length;
        Vec2 p = points[0];
        static if (transform)
            p = mat * p;
        output ~= p;
        const(Vec2)[] r = points[1 .. $];

        // compute distance tolerance
        const minDistFromMat = getMinDistFromMatrix(mat);
        const skip = minDistFromMat > 1000; // TODO: develop robust ways to handle degeneracies

        float minDist = pixelSize;
        static if (transform)
            minDist *= 0.7f;
        else
            minDist *= minDistFromMat;

        foreach (cmd; !skip ? commands : null)
        {
            final switch (cmd) with (Path.Command)
            {
            case lineTo:
                p = r[0];
                static if (transform)
                    p = mat * p;
                r = r[1 .. $];
                break;
            case quadTo:
                Vec2 p1 = r[0];
                Vec2 p2 = r[1];
                static if (transform)
                {
                    p1 = mat * p1;
                    p2 = mat * p2;
                }
                flattenQuadraticBezier(output, p, p1, p2, false, minDist);
                p = p2;
                r = r[2 .. $];
                break;
            case cubicTo:
                Vec2 p1 = r[0];
                Vec2 p2 = r[1];
                Vec2 p3 = r[2];
                static if (transform)
                {
                    p1 = mat * p1;
                    p2 = mat * p2;
                    p3 = mat * p3;
                }
                flattenCubicBezier(output, p, p1, p2, p3, false, minDist);
                p = p3;
                r = r[3 .. $];
                break;
            }
            output ~= p;
        }
        debug sanitize(output[][len .. $]);
        return output.length - len;
    }

    debug private void sanitize(const Vec2[] points) const
    {
        // the contour must not contain coincident adjacent points
        foreach (j; 1 .. points.length)
        {
            const vs = points[j - 1 .. j + 1];
            if (fequal6(vs[0].x, vs[1].x) && fequal6(vs[0].y, vs[1].y))
                assert(0, "Path has coincident adjacent points");
        }
    }
}

/// Represents vector shape as one or more subpaths, which contain series of segments
struct Path
{
nothrow:
    @property
    {
        /// True if no points and contours
        bool empty() const
        {
            return subpaths.length == 0;
        }
        /// True if path includes only one contour
        bool integral() const
        {
            return subpaths.length == 1;
        }
        /// Get the first subpath. Will be empty if the path is empty
        const(SubPath) firstSubpath() const
        {
            if (subpaths.length == 0)
                return SubPath.init;

            SubPath sub;
            sub.closed = subpaths[0].closed;
            sub.bounds = subpaths.length > 1 ? subpaths[0].bounds : currentContourBounds;

            const end = subpaths.length > 1 ? subpaths[1].start : commands.length;
            sub.commands = commands[][0 .. end];
            sub.points = points[][0 .. countPoints(sub.commands)];
            return sub;
        }
    }

    enum Command : ubyte
    {
        lineTo,
        quadTo,
        cubicTo,
    }

    private
    {
        struct SubPathInternal
        {
            uint start;
            Vec2 startPos;

            bool closed;
            Rect bounds;
        }

        Buf!Command commands;
        Buf!Vec2 points;
        Buf!SubPathInternal subpaths;

        bool closed = true;
        Vec2 pos;
        Rect currentContourBounds;
    }

    private void ensureContourStarted()
    {
        if (closed)
        {
            if (subpaths.length > 0)
                subpaths.unsafe_ref(-1).bounds = currentContourBounds;
            currentContourBounds = Rect(pos, pos);

            points ~= pos;
            subpaths ~= SubPathInternal(commands.length, pos);
            closed = false;
        }
    }

    private void expandBounds(Vec2 p)
    {
        alias r = currentContourBounds;
        r.left = min(r.left, p.x);
        r.top = min(r.top, p.y);
        r.right = max(r.right, p.x);
        r.bottom = max(r.bottom, p.y);
    }

    /// Set the current pen position. Closes current subpath, if one exists
    ref Path moveTo(float x, float y) return
    {
        pos.x = x;
        pos.y = y;
        closed = true;
        return this;
    }
    /// Move the current position by a vector. Closes current subpath, if one exists
    ref Path moveBy(float dx, float dy) return
    {
        pos.x += dx;
        pos.y += dy;
        closed = true;
        return this;
    }

    /// Add a line segment to a point
    ref Path lineTo(float x, float y) return
    {
        ensureContourStarted();
        if (fequal2(x, pos.x) && fequal2(y, pos.y))
            return this;

        pos.x = x;
        pos.y = y;
        commands ~= Command.lineTo;
        points ~= pos;
        expandBounds(pos);
        return this;
    }
    /// Add a line segment to a point, relative to the current position
    ref Path lineBy(float dx, float dy) return
    {
        return lineTo(pos.x + dx, pos.y + dy);
    }

    /// Add a quadratic Bézier curve with one control point and endpoint
    ref Path quadraticTo(float p1x, float p1y, float p2x, float p2y) return
    {
        ensureContourStarted();
        bool eq = fequal2(p1x, pos.x) && fequal2(p1y, pos.y);
        eq = eq && fequal2(p2x, pos.x) && fequal2(p2y, pos.y);
        if (eq)
            return this;

        const p1 = Vec2(p1x, p1y);
        const p2 = Vec2(p2x, p2y);
        commands ~= Command.quadTo;
        points ~= p1;
        points ~= p2;
        pos = p2;
        expandBounds(p1);
        expandBounds(p2);
        return this;
    }
    /// Add a quadratic Bézier curve with one control point and endpoint, relative to the current position
    ref Path quadraticBy(float p1dx, float p1dy, float p2dx, float p2dy) return
    {
        return quadraticTo(pos.x + p1dx, pos.y + p1dy, pos.x + p2dx, pos.y + p2dy);
    }

    /// Add a cubic Bézier curve with two control points and endpoint
    ref Path cubicTo(float p1x, float p1y, float p2x, float p2y, float p3x, float p3y) return
    {
        ensureContourStarted();
        bool eq = fequal2(p1x, pos.x) && fequal2(p1y, pos.y);
        eq = eq && fequal2(p2x, pos.x) && fequal2(p2y, pos.y);
        eq = eq && fequal2(p3x, pos.x) && fequal2(p3y, pos.y);
        if (eq)
            return this;

        const p1 = Vec2(p1x, p1y);
        const p2 = Vec2(p2x, p2y);
        const p3 = Vec2(p3x, p3y);
        commands ~= Command.cubicTo;
        points ~= p1;
        points ~= p2;
        points ~= p3;
        pos = p3;
        expandBounds(p1);
        expandBounds(p2);
        expandBounds(p3);
        return this;
    }
    /// Add a cubic Bézier curve with two control points and endpoint, relative to the current position
    ref Path cubicBy(float p1dx, float p1dy, float p2dx, float p2dy, float p3dx, float p3dy) return
    {
        return cubicTo(pos.x + p1dx, pos.y + p1dy, pos.x + p2dx, pos.y + p2dy, pos.x + p3dx, pos.y + p3dy);
    }

    /** Add an circular arc extending to a specified point.

        Positive angle draws clockwise.
    */
    ref Path arcTo(float x, float y, float angle) return
    {
        ensureContourStarted();
        if (fequal2(x, pos.x) && fequal2(y, pos.y))
            return this;

        const bool clockwise = angle > 0;
        angle = min(fabs(angle), 359) * PI / 180;
        if (angle < 1e-3f)
        {
            pos.x = x;
            pos.y = y;
            commands ~= Command.lineTo;
            points ~= pos;
            expandBounds(pos);
            return this;
        }

        // find radius using cosine formula
        const double cosine_2 = cos(cast(double)angle / 2);
        const double cosine = 2 * cosine_2 * cosine_2 - 1;
        const double squareDist = (pos.x - x) * (pos.x - x) + (pos.y - y) * (pos.y - y);
        const double squareRadius = squareDist / (2 - 2 * cosine);
        const double r = sqrt(squareRadius);
        if (r < 1e-6)
            return this;

        // find center
        const v = Vec2d(x - pos.x, y - pos.y);
        const ncenter = (clockwise ? v.rotated90fromXtoY : v.rotated90fromYtoX).normalized;
        const mid = Vec2d((x + pos.x) / 2, (y + pos.y) / 2);
        const center = mid + ncenter * r * cosine_2;
        // find angle to the first arc point
        const dir = clockwise ? -1 : 1;
        const double dy = (center.y - y) / r;
        const double beta = asin(dy);
        const double deltaAngle = angle * dir;
        const double startAngle = (center.x < x ? beta : PI - beta) - deltaAngle;

        // convert arc into a cubic spline, max 90 degrees for each segment
        const parts = cast(uint)(angle / PI_2 + 1);
        const double halfPartDA = (deltaAngle / parts) / 2;
        const double kappa = dir * fabs(4.0 / 3.0 * (1 - cos(halfPartDA)) / sin(halfPartDA));

        Vec2 p0 = pos;
        Vec2 a = Vec2(p0.x - center.x, center.y - p0.y);
        foreach (i; 1 .. parts + 1)
        {
            const double gamma = startAngle + deltaAngle * i / parts;
            const b = Vec2(r * cos(gamma), r * sin(gamma));

            const p3 = Vec2(center.x + b.x, center.y - b.y);
            const p1 = Vec2(p0.x - kappa * a.y, p0.y - kappa * a.x);
            const p2 = Vec2(p3.x + kappa * b.y, p3.y + kappa * b.x);

            commands ~= Command.cubicTo;
            points ~= p1;
            points ~= p2;
            points ~= p3;
            expandBounds(p1);
            expandBounds(p2);
            expandBounds(p3);

            a = b;
            p0 = p3;
        }
        pos.x = x;
        pos.y = y;
        return this;
    }
    /** Add an circular arc extending to a point, relative to the current position.

        Positive angle draws clockwise.
    */
    ref Path arcBy(float dx, float dy, float angle) return
    {
        return arcTo(pos.x + dx, pos.y + dy, angle);
    }

    /// Add a polyline to the path; equivalent to multiple `lineTo` calls with optional `moveTo` beforehand
    ref Path addPolyline(const Vec2[] array, bool detached) return
    {
        if (array.length != 0)
        {
            const p0 = array[0];
            if (detached)
                moveTo(p0.x, p0.y);
            ensureContourStarted();

            foreach (i; 1 .. array.length)
            {
                const a = array[i - 1];
                const b = array[i];
                if (!fequal6(a.x, b.x) || !fequal6(a.y, b.y))
                {
                    commands ~= Command.lineTo;
                    points ~= b;
                    expandBounds(b);
                }
            }
        }
        return this;
    }

    /** Return pen to initial contour (subpath) position and start new contour.

        Visually affects only stroking: filled shapes are closed by definition.
    */
    ref Path close() return
    {
        if (!closed)
        {
            assert(subpaths.length > 0);
            subpaths.unsafe_ref(-1).closed = true;
            const start = subpaths[$ - 1].startPos;
            const end = points[$ - 1];
            if (!fequal6(end.x, start.x) || !fequal6(end.y, start.y))
            {
                commands ~= Command.lineTo;
                points ~= start;
            }
            pos = start;
            closed = true;
        }
        return this;
    }

    /// Translate path by a vector. Can be expensive for very long path
    ref Path translate(float dx, float dy) return
    {
        foreach (ref p; points.unsafe_slice)
        {
            p.x += dx;
            p.y += dy;
        }
        foreach (ref subpath; subpaths.unsafe_slice)
        {
            subpath.bounds.translate(dx, dy);
        }
        currentContourBounds.translate(dx, dy);
        return this;
    }

    /// Clear path and reset it to initial state. Retains allocated memory for future use
    void reset()
    {
        commands.clear();
        points.clear();
        subpaths.clear();
        closed = true;
        pos = Vec2(0);
    }

    int opApply(scope int delegate(ref const SubPath) nothrow callback) const
    {
        if (points.length == 0)
            return 0;
        assert(subpaths.length > 0);

        uint pstart;
        foreach (i; 0 .. subpaths.length)
        {
            SubPath sub;
            sub.closed = subpaths[i].closed;
            sub.bounds = (i + 1 < subpaths.length) ? subpaths[i].bounds : currentContourBounds;

            const start = subpaths[i].start;
            const end = (i + 1 < subpaths.length) ? subpaths[i + 1].start : commands.length;
            sub.commands = commands[][start .. end];

            const pend = pstart + countPoints(sub.commands);
            sub.points = points[][pstart .. pend];
            pstart = pend;

            const int result = callback(sub);
            if (result != 0)
                return result;
        }
        return 0;
    }
}

private nothrow:

uint countPoints(const Path.Command[] cmds)
{
    uint count = 1;
    foreach (cmd; cmds)
    {
        final switch (cmd) with (Path.Command)
        {
        case lineTo:
            count += 1;
            break;
        case quadTo:
            count += 2;
            break;
        case cubicTo:
            count += 3;
            break;
        }
    }
    return count;
}
