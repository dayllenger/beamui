/**
Path that outlines a complex figure.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.path;

import beamui.core.collections : Buf;
import beamui.core.linalg : Vec2;
import beamui.core.math : fequal1, fequal6, fzero1;
import beamui.graphics.flattener;

struct SubPath
{
    Vec2[] points;
    bool closed;
}

/// Represents vector shape as one or more subpaths, which contain series of segments
struct Path
{
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

            const end = subpaths.length > 1 ? subpaths[1].start : points.length;
            const pts = points[][0 .. end];
            return const(SubPath)(pts, subpaths[0].closed);
        }
    }

    private
    {
        struct SubPathInternal
        {
            uint start;
            bool closed;
        }

        Buf!Vec2 points;
        Buf!SubPathInternal subpaths;
        bool closed = true;
        float posx = 0;
        float posy = 0;
    }

    private void startSubpath()
    {
        if (closed)
        {
            const i = points.length;
            points ~= Vec2(posx, posy);
            subpaths ~= SubPathInternal(i);
            closed = false;
        }
    }
    private void insertLastPoint()
    {
        points ~= Vec2(posx, posy);
    }

    /// Set the current pen position. Closes current subpath, if one exists
    ref Path moveTo(float x, float y)
    {
        posx = x;
        posy = y;
        closed = true;
        return this;
    }
    /// Move the current position by a vector. Closes current subpath, if one exists
    ref Path relMoveTo(float dx, float dy)
    {
        posx += dx;
        posy += dy;
        closed = true;
        return this;
    }

    /// Add a line segment to a point
    ref Path lineTo(float x, float y)
    {
        startSubpath();
        if (fequal1(x, posx) && fequal1(y, posy)) return this;
        posx = x;
        posy = y;
        insertLastPoint();
        return this;
    }
    /// Add a horizontal line segment to specified `x` coordinate
    ref Path lineToHor(float x)
    {
        startSubpath();
        if (fequal1(x, posx)) return this;
        posx = x;
        insertLastPoint();
        return this;
    }
    /// Add a vertical line segment to specified `y` coordinate
    ref Path lineToVert(float y)
    {
        startSubpath();
        if (fequal1(y, posy)) return this;
        posy = y;
        insertLastPoint();
        return this;
    }
    /// Relative version of `lineTo`
    ref Path relLineTo(float dx, float dy)
    {
        startSubpath();
        if (fzero1(dx) && fzero1(dy)) return this;
        posx += dx;
        posy += dy;
        insertLastPoint();
        return this;
    }
    /// Relative version of `lineToHor`
    ref Path relLineToHor(float dx)
    {
        startSubpath();
        if (fzero1(dx)) return this;
        posx += dx;
        insertLastPoint();
        return this;
    }
    /// Relative version of `lineToVert`
    ref Path relLineToVert(float dy)
    {
        startSubpath();
        if (fzero1(dy)) return this;
        posy += dy;
        insertLastPoint();
        return this;
    }

    /// Add a quadratic Bézier curve with one control point and endpoint
    ref Path quadraticTo(float p1x, float p1y, float p2x, float p2y)
    {
        startSubpath();
        flattenQuadraticBezier(
            Vec2(posx, posy),
            Vec2(p1x, p1y),
            Vec2(p2x, p2y),
            false, points);
        posx = p2x;
        posy = p2y;
        insertLastPoint();
        return this;
    }
    /// Relative version of `quadraticTo`
    ref Path relQuadraticTo(float p1dx, float p1dy, float p2dx, float p2dy)
    {
        return quadraticTo(posx + p1dx, posy + p1dy, posx + p2dx, posy + p2dy);
    }

    /// Add a cubic Bézier curve with two control points and endpoint
    ref Path cubicTo(float p1x, float p1y, float p2x, float p2y, float p3x, float p3y)
    {
        startSubpath();
        flattenCubicBezier(
            Vec2(posx, posy), Vec2(p1x, p1y),
            Vec2(p2x,  p2y),  Vec2(p3x, p3y),
            false, points);
        posx = p3x;
        posy = p3y;
        insertLastPoint();
        return this;
    }
    /// Relative version of `cubicTo`
    ref Path relCubicTo(float p1dx, float p1dy, float p2dx, float p2dy, float p3dx, float p3dy)
    {
        return cubicTo(posx + p1dx, posy + p1dy, posx + p2dx, posy + p2dy, posx + p3dx, posy + p3dy);
    }

    /// Add an circular arc extending to a specified point
    ref Path arcTo(float x, float y, float angle, bool clockwise)
    {
        import std.math : asin, cos, sqrt, PI;

        startSubpath();
        if (angle < 0 || 360 < angle || fzero1(angle) || fequal1(angle, 360) ||
            fequal1(x, posx) && fequal1(y, posy)) return this;

        angle = angle * PI / 180;
        const cosine_2 = cos(angle / 2);
        const cosine = 2 * cosine_2 * cosine_2 - 1;
        // find radius using cosine formula
        const squareDist = (posx - x) * (posx - x) + (posy - y) * (posy - y);
        const squareRadius = squareDist / (2 - 2 * cosine);
        const r = sqrt(squareRadius);
        // find center
        const v = Vec2(posx - x, posy - y);
        const ncenter = (clockwise ? v.rotated90cw : v.rotated90ccw).normalized;
        const mid = Vec2((x + posx) / 2, (y + posy) / 2);
        const center = mid + ncenter * r * cosine_2;
        // find angle to the first arc point
        const dir = clockwise ? -1 : 1;
        const dy = (center.y - y) / r;
        const beta = asin(dy);
        const startAngle = (center.x < x ? beta : PI - beta) - angle * dir;

        flattenArc(center, r, startAngle, angle * dir, false, points);
        posx = x;
        posy = y;
        insertLastPoint();
        return this;
    }
    /// Relative version of `arcTo`
    ref Path relArcTo(float dx, float dy, float angle, bool clockwise)
    {
        return arcTo(posx + dx, posy + dy, angle, clockwise);
    }

    /// Add a polyline to the path; equivalent to multiple `lineTo` calls with optional `moveTo` beforehand
    ref Path addPolyline(const Vec2[] array, bool detached)
    {
        if (array.length != 0)
        {
            const p0 = array[0];
            if (detached)
                moveTo(p0.x, p0.y);
            if (!closed)
                points ~= p0;
            else
                startSubpath();

            foreach (i; 1 .. array.length)
            {
                const a = array[i - 1];
                const b = array[i];
                if (!fequal6(a.x, b.x) || !fequal6(a.y, b.y))
                    points ~= b;
            }
        }
        return this;
    }

    /// Return pen to initial contour (subpath) position and start new contour.
    /// Visually affects only stroking: filled shapes are closed by definition
    ref Path close()
    {
        if (!closed)
        {
            assert(subpaths.length > 0);
            subpaths.unsafe_ref(-1).closed = true;
            const start = points[subpaths[$ - 1].start];
            const end = points[$ - 1];
            if (!fequal6(end.x, start.x) || !fequal6(end.y, start.y))
                points ~= start;
            posx = start.x;
            posy = start.y;
            closed = true;
        }
        return this;
    }

    /// Translate path by a vector. Can be expensive for very long path
    ref Path translate(float dx, float dy)
    {
        foreach (ref p; points.unsafe_slice)
        {
            p.x += dx;
            p.y += dy;
        }
        return this;
    }

    /// Clear path and reset it to initial state. Retains allocated memory for future use
    void reset()
    {
        points.clear();
        subpaths.clear();
        closed = true;
        posx = posy = 0;
    }

    int opApply(scope int delegate(ref const SubPath) callback) const
    {
        if (points.length == 0)
            return 0;
        assert(subpaths.length > 0);

        const Vec2[] pts = points[];
        foreach (i; 0 .. subpaths.length)
        {
            const start = subpaths[i].start;
            const end = (i + 1 < subpaths.length) ? subpaths[i + 1].start : pts.length;
            const subpath = const(SubPath)(pts[start .. end], subpaths[i].closed);

            // the contour must not contain coincident adjacent points
            debug foreach (j; 1 .. subpath.points.length)
                if (fequal6(subpath.points[j - 1].x, subpath.points[j].x) &&
                    fequal6(subpath.points[j - 1].y, subpath.points[j].y))
                    assert(0, "Path has coincident adjacent points");

            const int result = callback(subpath);
            if (result != 0)
                return result;
        }
        return 0;
    }
}
