/**
Some algorithms on polygons, mostly with convex shapes.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.polygons;

nothrow:

import std.algorithm : sort, swap;
import beamui.core.collections : Buf;
import beamui.core.geometry : RectF;
import beamui.core.linalg : Vec2, crossProduct;
import beamui.core.math : fequal2, fzero6;
import beamui.graphics.swrast : HorizEdge;

/** Determines the interior part of a filled path shape.

    More info here: $(LINK https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/fill-rule)
*/
enum FillRule
{
    nonzero,
    evenodd,
}

/// Compute the smallest enclosing rectangle of a point cloud
RectF computeBoundingBox(const Vec2[] points, RectF initial = RectF(float.max, float.max, -float.max, -float.max))
{
    RectF r = initial;
    foreach (p; points)
    {
        if (r.left > p.x)
            r.left = p.x;
        if (r.top > p.y)
            r.top = p.y;
        if (r.right < p.x)
            r.right = p.x;
        if (r.bottom < p.y)
            r.bottom = p.y;
    }
    return r;
}

/// Check that a polygon, defined as a point list, is convex
bool isConvex(const Vec2[] polygon)
{
    // https://math.stackexchange.com/a/1745427

    if (polygon.length <= 3)
        return true;

    enum eps = 1e-6;

    float wSign = 0;  // first nonzero orientation (positive or negative)

    byte xSign;
    byte xFirstSign;  // sign of first nonzero edge vector x
    int  xFlips;      // number of sign changes in x

    byte ySign;
    byte yFirstSign;  // sign of first nonzero edge vector y
    int  yFlips;      // number of sign changes in y

    Vec2 curr = polygon[$ - 2];
    Vec2 next = polygon[$ - 1];

    foreach (p; polygon)
    {
        const prev = curr;
        curr = next;
        next = p;

        const b = curr - prev; // previous edge vector ("before")
        const a = next - curr; // next edge vector ("after")

        // calculate sign flips using the next edge vector ("after"),
        // recording the first sign
        if (a.x > eps)
        {
            if (xSign == 0)
                xFirstSign = 1;
            else if (xSign < 0)
                xFlips++;
            xSign = 1;
        }
        else if (a.x < -eps)
        {
            if (xSign == 0)
                xFirstSign = -1;
            else if (xSign > 0)
                xFlips++;
            xSign = -1;
        }

        if (xFlips > 2)
            return false;

        if (a.y > eps)
        {
            if (ySign == 0)
                yFirstSign = 1;
            else if (ySign < 0)
                yFlips++;
            ySign = 1;
        }
        else if (a.y < -eps)
        {
            if (ySign == 0)
                yFirstSign = -1;
            else if (ySign > 0)
                yFlips++;
            ySign = -1;
        }

        if (yFlips > 2)
            return false;

        // find out the orientation of this pair of edges,
        // and ensure it does not differ from previous ones
        const w = crossProduct(b, a);
        if (wSign == 0 && !fzero6(w))
            wSign = w;
        else if (wSign > eps && w < -eps)
            return false;
        else if (wSign < -eps && w > eps)
            return false;
    }

    // final/wraparound sign flips
    if (xSign != 0 && xFirstSign != 0 && xSign != xFirstSign)
        xFlips++;
    if (ySign != 0 && yFirstSign != 0 && ySign != yFirstSign)
        yFlips++;

    // convex polygons have two sign flips along each axis
    return xFlips == 2 && yFlips == 2;
}

/// Compute the convex hull of a polygon and append it to the `output` point list in clockwise order
void computeConvexHull(const Vec2[] polygon, ref Buf!Vec2 output)
{
    // https://en.wikibooks.org/wiki/Algorithm_Implementation/Geometry/Convex_hull/Monotone_chain

    if (polygon.length <= 3)
    {
        output ~= polygon;
        return;
    }

    static Buf!Vec2 sorted;
    sorted ~= polygon;
    sortPointsYX(sorted.unsafe_slice);

    // build right hull
    const ol1 = output.length;
    foreach (o; sorted)
    {
        while (output.length >= ol1 + 2)
        {
            const a = output[$ - 2];
            const b = output[$ - 1];
            // check if makes counter-clockwise turn
            if (crossProduct(a - o, b - o) <= 0)
                output.shrink(1);
            else
                break;
        }
        output ~= o;
    }
    output.shrink(1);

    // build left hull; exactly the same, but from bottom to top
    const ol2 = output.length;
    foreach_reverse (o; sorted)
    {
        while (output.length >= ol2 + 2)
        {
            const a = output[$ - 2];
            const b = output[$ - 1];
            // check if makes counter-clockwise turn
            if (crossProduct(a - o, b - o) <= 0)
                output.shrink(1);
            else
                break;
        }
        output ~= o;
    }
    output.shrink(1);

    // clear (but not deallocate) our temporary buffer
    sorted.clear();
}

/// Sort points lexicographically by increasing Y first
private void sortPointsYX(Vec2[] points)
{
    sort!(`a.y < b.y || a.y == b.y && a.x < b.x`)(points);
}

/** Convert simple y-monotone polygon into a chain of valid horizontal trapezoids.

    The trapezoid count is always less than the vertex count.

    Returns: true if converted something.
*/
bool splitIntoTrapezoids(const Vec2[] poly, ref Buf!HorizEdge output)
{
    const ptrdiff_t len = poly.length;
    if (len < 3)
        return false;

    // check if monotone
    // and find indices of the highest and the lowest point
    ptrdiff_t topIndex, bottomIndex;
    {
        // the idea is that a y-monotone polygon has only one local minimum

        static bool less(const Vec2* poly, ptrdiff_t i, ptrdiff_t j)
        {
            return poly[i].y < poly[j].y || (poly[i].y == poly[j].y && i < j);
        }

        float topY = float.max, bottomY = -float.max;
        int localMins;
        foreach (i; 0 .. len)
        {
            // compare with the previous and the next
            if (less(poly.ptr, i, (i + 1) % len) && less(poly.ptr, i, (i - 1 + len) % len))
            {
                localMins++;
                if (localMins > 1)
                    return false;
            }

            const y = poly[i].y;
            if (y < topY)
            {
                topIndex = i;
                topY = y;
            }
            if (y > bottomY)
            {
                bottomIndex = i;
                bottomY = y;
            }
        }
        assert(localMins == 1);
    }

    static bool intersect(ref const Vec2[2] a, ref const Vec2[2] b)
    {
        const Vec2 r = a[1] - a[0];
        const Vec2 s = b[1] - b[0];
        const Vec2 qp = b[0] - a[0];
        const float rxs = crossProduct(r, s);
        if (fzero6(rxs)) // parallel
            return false;

        const float t = crossProduct(qp, s) / rxs;
        const float u = crossProduct(qp, r) / rxs;
        enum eps = 1e-6f;
        return eps < t && t < 1 - eps && eps < u && u < 1 - eps;
    }

    // iterate from top to bottom, construct trapezoids,
    // abort if the polygon has self-intersections
    uint added;
    HorizEdge bot = { poly[topIndex].x, poly[topIndex].x, poly[topIndex].y };
    ptrdiff_t b = topIndex; // backward
    ptrdiff_t f = topIndex; // forward
    foreach (_; 0 .. len)
    {
        const bnext = (b - 1 + len) % len;
        const fnext = (f + 1) % len;
        const Vec2[2] bseg = [poly[b], poly[bnext]];
        const Vec2[2] fseg = [poly[f], poly[fnext]];
        // check intersections
        if (intersect(bseg, fseg))
        {
            output.shrink(added);
            return false;
        }
        // skip horizontal edges
        if (bseg[0].y == bseg[1].y)
        {
            if (bot.l == bseg[0].x)
                bot.l = bseg[1].x;
            else if (bot.r == bseg[0].x)
                bot.r = bseg[1].x;
            if (bot.l > bot.r)
                swap(bot.l, bot.r);
            b = bnext;
            continue;
        }
        if (fseg[0].y == fseg[1].y)
        {
            if (bot.l == fseg[0].x)
                bot.l = fseg[1].x;
            else if (bot.r == fseg[0].x)
                bot.r = fseg[1].x;
            if (bot.l > bot.r)
                swap(bot.l, bot.r);
            f = fnext;
            continue;
        }
        // locate trapezoid bottom edge
        const HorizEdge top = bot;
        if (fequal2(fseg[1].y, bseg[1].y)) // at the same height
        {
            bot.l = fseg[1].x;
            bot.r = bseg[1].x;
            bot.y = fseg[1].y;
            f = fnext;
            b = bnext;
        }
        else if (fseg[1].y < bseg[1].y)
        {
            bot.r = fseg[1].x;
            bot.y = fseg[1].y;
            const c = (bot.y - bseg[0].y) / (bseg[1].y - bseg[0].y);
            bot.l = bseg[0].x + c * (bseg[1].x - bseg[0].x);
            f = fnext;
        }
        else
        {
            bot.l = bseg[1].x;
            bot.y = bseg[1].y;
            const c = (bot.y - fseg[0].y) / (fseg[1].y - fseg[0].y);
            bot.r = fseg[0].x + c * (fseg[1].x - fseg[0].x);
            b = bnext;
        }
        if (bot.l > bot.r)
            swap(bot.l, bot.r);

        if (HorizEdge.isValidTrapezoid(top, bot))
        {
            if (added == 0 || output[$ - 1] != top)
            {
                output ~= top;
                added++;
            }
            output ~= bot;
            added++;
        }
    }
    return added > 0;
}

//===============================================================
// Tests

version (unittest)
{
    immutable rectPoly = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)];
    immutable starPoly = [Vec2(20, 0), Vec2(0, 40), Vec2(40, 20), Vec2(0, 20), Vec2(40, 40)];
}

unittest
{
    assert( isConvex(rectPoly));
    assert(!isConvex(starPoly));

    Buf!Vec2 points;
    computeConvexHull(starPoly, points);
    assert(points[] == [Vec2(20, 0), Vec2(40, 20), Vec2(40, 40), Vec2(0, 40), Vec2(0, 20)]);
}

unittest
{
    Buf!HorizEdge traps;
    assert(splitIntoTrapezoids(rectPoly, traps));
    assert(traps[] == [HorizEdge(0, 10, 0), HorizEdge(0, 10, 10)]);
    assert(!splitIntoTrapezoids(starPoly, traps));
}
