/**
Path that outlines a complex figure.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.path;

import beamui.core.collections : Buf;
import beamui.core.geometry : RectF;
import beamui.core.linalg : Vec2;
import beamui.core.math : fequal2, fequal6, fzero2, max, min;
import beamui.graphics.flattener;

struct SubPath
{
    Vec2[] points;
    bool closed;
    RectF bounds;
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

            const end = subpaths.length > 1 ? subpaths[1].start : points.length;
            const pts = points[][0 .. end];
            const bounds = subpaths.length > 1 ? subpaths[0].bounds : currentContourBounds;
            return const(SubPath)(pts, subpaths[0].closed, bounds);
        }
    }

    private
    {
        struct SubPathInternal
        {
            uint start;
            bool closed;
            RectF bounds;
        }

        Buf!Vec2 points;
        Buf!SubPathInternal subpaths;
        bool closed = true;
        float posx = 0;
        float posy = 0;
        RectF currentContourBounds;
    }

    private void ensureContourStarted()
    {
        if (closed)
        {
            if (subpaths.length > 0)
                subpaths.unsafe_ref(-1).bounds = currentContourBounds;
            currentContourBounds = RectF(posx, posy, posx, posy);

            const i = points.length;
            points ~= Vec2(posx, posy);
            subpaths ~= SubPathInternal(i);
            closed = false;
        }
    }

    private void insertLastPoint()
    {
        points ~= Vec2(posx, posy);
        expandBounds(posx, posy);
    }

    private void expandBounds(float px, float py)
    {
        alias r = currentContourBounds;
        r.left = min(r.left, px);
        r.top = min(r.top, py);
        r.right = max(r.right, px);
        r.bottom = max(r.bottom, py);
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
    ref Path moveBy(float dx, float dy)
    {
        posx += dx;
        posy += dy;
        closed = true;
        return this;
    }

    /// Add a line segment to a point
    ref Path lineTo(float x, float y)
    {
        ensureContourStarted();
        if (fequal2(x, posx) && fequal2(y, posy)) return this;
        posx = x;
        posy = y;
        insertLastPoint();
        return this;
    }
    /// Add a line segment to a point, relative to the current position
    ref Path lineBy(float dx, float dy)
    {
        ensureContourStarted();
        if (fzero2(dx) && fzero2(dy)) return this;
        posx += dx;
        posy += dy;
        insertLastPoint();
        return this;
    }

    /// Add a quadratic Bézier curve with one control point and endpoint
    ref Path quadraticTo(float p1x, float p1y, float p2x, float p2y)
    {
        ensureContourStarted();
        flattenQuadraticBezier(
            points,
            Vec2(posx, posy),
            Vec2(p1x, p1y),
            Vec2(p2x, p2y),
            false,
        );
        posx = p2x;
        posy = p2y;
        insertLastPoint();
        expandBounds(p1x, p1y);
        return this;
    }
    /// Add a quadratic Bézier curve with one control point and endpoint, relative to the current position
    ref Path quadraticBy(float p1dx, float p1dy, float p2dx, float p2dy)
    {
        return quadraticTo(posx + p1dx, posy + p1dy, posx + p2dx, posy + p2dy);
    }

    /// Add a cubic Bézier curve with two control points and endpoint
    ref Path cubicTo(float p1x, float p1y, float p2x, float p2y, float p3x, float p3y)
    {
        ensureContourStarted();
        flattenCubicBezier(
            points,
            Vec2(posx, posy), Vec2(p1x, p1y),
            Vec2(p2x,  p2y),  Vec2(p3x, p3y),
            false,
        );
        posx = p3x;
        posy = p3y;
        insertLastPoint();
        expandBounds(p1x, p1y);
        expandBounds(p2x, p2y);
        return this;
    }
    /// Add a cubic Bézier curve with two control points and endpoint, relative to the current position
    ref Path cubicBy(float p1dx, float p1dy, float p2dx, float p2dy, float p3dx, float p3dy)
    {
        return cubicTo(posx + p1dx, posy + p1dy, posx + p2dx, posy + p2dy, posx + p3dx, posy + p3dy);
    }

    /** Add an circular arc extending to a specified point.

        Positive angle draws clockwise.
    */
    ref Path arcTo(float x, float y, float angle)
    {
        import std.math : abs, asin, cos, sqrt, PI;

        ensureContourStarted();
        if (fzero2(angle) || (fequal2(x, posx) && fequal2(y, posy))) return this;

        const bool clockwise = angle > 0;
        angle = min(abs(angle), 360) * PI / 180;
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

        flattenArc(points, center, r, startAngle, angle * dir, false);
        posx = x;
        posy = y;
        insertLastPoint();
        expandBounds(center.x - r, center.y - r);
        expandBounds(center.x + r, center.y + r);
        return this;
    }
    /** Add an circular arc extending to a point, relative to the current position.

        Positive angle draws clockwise.
    */
    ref Path arcBy(float dx, float dy, float angle)
    {
        return arcTo(posx + dx, posy + dy, angle);
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
                ensureContourStarted();

            foreach (i; 1 .. array.length)
            {
                const a = array[i - 1];
                const b = array[i];
                if (!fequal6(a.x, b.x) || !fequal6(a.y, b.y))
                {
                    points ~= b;
                    expandBounds(b.x, b.y);
                }
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
        points.clear();
        subpaths.clear();
        closed = true;
        posx = posy = 0;
    }

    int opApply(scope int delegate(ref const SubPath) nothrow callback) const
    {
        if (points.length == 0)
            return 0;
        assert(subpaths.length > 0);

        const Vec2[] pts = points[];
        foreach (i; 0 .. subpaths.length)
        {
            const start = subpaths[i].start;
            const end = (i + 1 < subpaths.length) ? subpaths[i + 1].start : pts.length;
            const bounds = (i + 1 < subpaths.length) ? subpaths[i].bounds : currentContourBounds;
            const subpath = const(SubPath)(pts[start .. end], subpaths[i].closed, bounds);

            // the contour must not contain coincident adjacent points
            debug foreach (j; 1 .. subpath.points.length)
            {
                if (fequal6(subpath.points[j - 1].x, subpath.points[j].x) &&
                    fequal6(subpath.points[j - 1].y, subpath.points[j].y))
                    assert(0, "Path has coincident adjacent points");
            }
            const int result = callback(subpath);
            if (result != 0)
                return result;
        }
        return 0;
    }
}
