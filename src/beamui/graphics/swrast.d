/**
Utilities for software rasterization.

Polygon rasterizer is a rework of stb_truetype.h rasterizers by Sean Barrett.

Clipping and line rasterization is partly from $(LINK rosettacode.org).

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.swrast;

private nothrow:

import core.stdc.math : fabs;
import core.stdc.stdlib : malloc, free;
import std.algorithm.mutation : swap;
import std.math : abs, ceil, floor, lrint, quantize, round;
import beamui.core.collections : Buf;
import beamui.core.geometry : BoxI, RectI;
import beamui.core.linalg : Vec2, crossProduct;
import beamui.core.math : fequal2, fzero2, clamp, max, min;
import beamui.graphics.polygons : computeBoundingBox;

public interface Plotter
{
    nothrow:

    void setPixel(int, int);
    void mixPixel(int, int, float);
    void setScanLine(int, int, int);
    void mixScanLine(int, int, int, float);
}

public enum RastFillRule
{
    nonzero,
    odd,
    zero,
    even,
}

public struct RastParams
{
    bool antialias;
    BoxI clip;
    RastFillRule rule;
}

//===============================================================
// Polygon rasterizer

public void rasterizePolygons(const Vec2[] points, const uint[] contours, RastParams params, Plotter plotter)
    in(points.length)
    in(contours.length)
    in(!params.clip.empty)
    in(plotter)
{
    // perform clipping first; contours may change their geometry

    static struct Contour
    {
        uint start;
        uint len;
        bool updated;
        RectI bounds;
    }
    Contour* ctrs = cast(Contour*)malloc(Contour.sizeof * contours.length);
    if (!ctrs) return;
    scope(exit) free(ctrs);

    // we will adjust rasterizer clipping box to the polygon bounding box,
    // because clip is also the working area (on usual fill rules),
    // and we need to minimize it
    const RectI clip = params.clip;
    RectI bbox = RectI(int.max, int.max, int.min, int.min);
    Buf!Vec2 pts;

    // initialize the array, collect contour bounding boxes into it
    int n;
    foreach (i, len; contours)
    {
        Contour* ctr = &ctrs[i];
        ctr.start = n;
        ctr.len = len;
        ctr.updated = false;
        const ps = points[n .. n + len];
        const cb = computeBoundingBox(ps);
        const cbi = ctr.bounds = RectI(
            ifloor(cb.left),
            ifloor(cb.top),
            iceil(cb.right),
            iceil(cb.bottom),
        );
        bbox.left = min(bbox.left, cbi.left);
        bbox.top = min(bbox.top, cbi.top);
        bbox.right = max(bbox.right, cbi.right);
        bbox.bottom = max(bbox.bottom, cbi.bottom);
        n += len;
    }
    // clip contours
    foreach (i, ref ctr; ctrs[0 .. contours.length])
    {
        const RectI cb = ctr.bounds;
        if (cb.top >= clip.bottom || cb.left > clip.right ||
            cb.bottom <= clip.top || cb.right <= clip.left)
        {
            ctr.start = 0;
            ctr.len = 0;
            ctr.updated = true;
            continue;
        }
        Vec2[2][4] clipEdges;
        uint ceCount;
        if (cb.top < clip.top)
        {
            clipEdges[ceCount++] = [Vec2(clip.left, clip.top), Vec2(clip.right, clip.top)];
        }
        if (cb.right > clip.right)
        {
            clipEdges[ceCount++] = [Vec2(clip.right, clip.top), Vec2(clip.right, clip.bottom)];
        }
        if (cb.bottom > clip.bottom)
        {
            clipEdges[ceCount++] = [Vec2(clip.right, clip.bottom), Vec2(clip.left, clip.bottom)];
        }
        if (cb.left < clip.left)
        {
            clipEdges[ceCount++] = [Vec2(clip.left, clip.bottom), Vec2(clip.left, clip.top)];
        }
        if (ceCount > 0)
        {
            const before = pts.length;
            clip_poly(points[ctr.start .. ctr.start + ctr.len], clipEdges[0 .. ceCount], pts);
            ctr.start = before;
            ctr.len = pts.length - before;
            ctr.updated = true;
        }
    }
    if (!isComplementary(params.rule))
    {
        bbox.intersect(clip);
        params.clip = BoxI(bbox);
    }

    // now we have to blow out the windings into explicit edge lists
    n = 0;
    foreach (ref ctr; ctrs[0 .. contours.length])
        n += ctr.len;
    if (n == 0)
        return;

    Edge* e = cast(Edge*)malloc(Edge.sizeof * (n + 1)); // add an extra one as a sentinel
    if (!e) return;
    scope(exit) free(e);
    n = 0;

    int j, k;
    foreach (ref ctr; ctrs[0 .. contours.length])
    {
        if (ctr.len == 0)
            continue;

        const Vec2* p = ctr.updated ? &pts[ctr.start] : &points[ctr.start];
        j = ctr.len - 1;
        for (k = 0; k < ctr.len; j = k++)
        {
            if (p[j].y == p[k].y)
                continue;

            int a = k, b = j;
            e[n].invert = false;
            if (p[j].y < p[k].y)
            {
                e[n].invert = true;
                a = j, b = k;
            }
            e[n].x0 = p[a].x - params.clip.x;
            e[n].y0 = p[a].y - params.clip.y;
            e[n].x1 = p[b].x - params.clip.x;
            e[n].y1 = p[b].y - params.clip.y;
            ++n;
        }
    }

    // now sort the edges by their highest point (should snap to integer, and then by x)
    sort_edges(e, n);

    // now, traverse the scanlines and find the intersections on each scanline
    if (params.antialias)
        rasterize_sorted_edges_aa(e, n, params, plotter);
    else
        rasterize_sorted_edges(e, n, params, plotter);
}

/// Sutherland-Hodgman clipping
void clip_poly(const(Vec2)[] input, const Vec2[2][] clipEdges, ref Buf!Vec2 output)
{
    // check if a point is on the LEFT side of an edge
    static bool inside(Vec2 p, ref const Vec2[2] edge)
    {
        return (edge[1].y - edge[0].y) * p.x +
               (edge[0].x - edge[1].x) * p.y +
               (edge[1].x * edge[0].y - edge[0].x * edge[1].y) < 0;
    }
    // calculate intersection point
    static Vec2 intersection(ref const Vec2[2] edge, Vec2 s, Vec2 e)
    {
        const Vec2 dc = edge[0] - edge[1];
        const Vec2 dp = s - e;

        const float n1 = crossProduct(edge[0], edge[1]);
        const float n2 = crossProduct(s, e);
        const float n3 = 1 / (dc.x * dp.y - dc.y * dp.x);

        return Vec2((n1 * dp.x - n2 * dc.x) * n3, (n1 * dp.y - n2 * dc.y) * n3);
    }

    // double bufferization to avoid extra copying
    static Buf!Vec2 tmp;

    const olen = output.length;
    Buf!Vec2* writer = (clipEdges.length % 2 == 1) ? &output : &tmp;

    foreach (ref edge; clipEdges)
    {
        if (writer is &output)
            writer.shrink(output.length - olen);
        else
            writer.clear();

        foreach (i; 0 .. input.length)
        {
            // get subject polygon edge
            const Vec2 s = input[i];
            const Vec2 e = input[(i + 1) % $];

            // Case 1: Both vertices are inside:
            // Only the second vertex is added to the output list
            if(inside(s, edge) && inside(e, edge))
            {
                writer.put(e);
            }
            // Case 2: First vertex is outside while second one is inside:
            // Both the point of intersection of the edge with the clip boundary
            // and the second vertex are added to the output list
            else if(!inside(s, edge) && inside(e, edge))
            {
                writer.put(intersection(edge, s, e));
                writer.put(e);
            }
            // Case 3: First vertex is inside while second one is outside:
            // Only the point of intersection of the edge with the clip boundary
            // is added to the output list
            else if(inside(s, edge) && !inside(e, edge))
            {
                writer.put(intersection(edge, s, e));
            }
            // Case 4: Both vertices are outside
            else
            {
                // No vertices are added to the output list
            }
        }
        if (writer is &output)
        {
            input = output[][olen .. $];
            writer = &tmp;
        }
        else
        {
            input = tmp[];
            writer = &output;
        }
    }
}

bool isComplementary(RastFillRule rule)
{
    return rule == RastFillRule.zero || rule == RastFillRule.even;
}

struct Edge
{
    float x0, y0, x1, y1;
    bool invert;
}

void sort_edges(Edge* p, int n)
{
    sort_edges_quicksort(p, n);
    sort_edges_ins_sort(p, n);
}

int cmp_edges(Edge* a, Edge* b)
{
    return a.y0 < b.y0;
}

void sort_edges_ins_sort(Edge* p, int n)
{
    for (int i = 1; i < n; ++i)
    {
        Edge t = p[i];
        Edge* a = &t;
        int j = i;
        while (j > 0)
        {
            Edge* b = &p[j - 1];
            const int c = cmp_edges(a, b);
            if (c == 0)
                break;
            p[j] = p[j - 1];
            --j;
        }
        if (i != j)
            p[j] = t;
    }
}

void sort_edges_quicksort(Edge* p, int n)
{
    // threshold for transitioning to insertion sort
    while (n > 12)
    {
        Edge t;
        int c01, c12, c, m, i, j;

        // compute median of three
        m = n >> 1;
        c01 = cmp_edges(&p[0], &p[m]);
        c12 = cmp_edges(&p[m], &p[n - 1]);
        // if 0 >= mid >= end, or 0 < mid < end, then use mid
        if (c01 != c12)
        {
            // otherwise, we'll need to swap something else to middle
            c = cmp_edges(&p[0], &p[n - 1]);
            // 0>mid && mid<n:  0>n => n; 0<n => 0
            // 0<mid && mid>n:  0>n => 0; 0<n => n
            int z = (c == c12) ? 0 : n - 1;
            t = p[z];
            p[z] = p[m];
            p[m] = t;
        }
        // now p[m] is the median-of-three
        // swap it to the beginning so it won't move around
        t = p[0];
        p[0] = p[m];
        p[m] = t;

        // partition loop
        i = 1;
        j = n - 1;
        for (;;)
        {
            // handling of equality is crucial here
            // for sentinels & efficiency with duplicates
            for (;; ++i)
            {
                if (!cmp_edges(&p[i], &p[0]))
                    break;
            }
            for (;; --j)
            {
                if (!cmp_edges(&p[0], &p[j]))
                    break;
            }
            // make sure we haven't crossed
            if (i >= j)
                break;
            t = p[i];
            p[i] = p[j];
            p[j] = t;

            ++i;
            --j;
        }
        // recurse on smaller side, iterate on larger
        if (j < (n - i))
        {
            sort_edges_quicksort(p, j);
            p = p + i;
            n = n - i;
        }
        else
        {
            sort_edges_quicksort(p + i, n - i);
            n = j;
        }
    }
}

struct Hheap_chunk
{
    Hheap_chunk* next;
}

struct Hheap
{
    Hheap_chunk* head;
    void* first_free;
    int num_remaining_in_head_chunk;
}

void* hheap_alloc(Hheap* hh, size_t size)
{
    if (hh.first_free)
    {
        void* p = hh.first_free;
        hh.first_free = *cast(void**)p;
        return p;
    }
    else
    {
        if (hh.num_remaining_in_head_chunk == 0)
        {
            const int count = size < 32 ? 2000 : size < 128 ? 800 : 100;
            Hheap_chunk* c = cast(Hheap_chunk*)malloc(Hheap_chunk.sizeof + size * count);
            if (!c)
                return null;
            c.next = hh.head;
            hh.head = c;
            hh.num_remaining_in_head_chunk = count;
        }
        --hh.num_remaining_in_head_chunk;
        return cast(char*)(hh.head) + Hheap_chunk.sizeof + size * hh.num_remaining_in_head_chunk;
    }
}

void hheap_free(Hheap* hh, void* p)
{
    *cast(void**)p = hh.first_free;
    hh.first_free = p;
}

void hheap_cleanup(Hheap* hh)
{
    Hheap_chunk* c = hh.head;
    while (c)
    {
        Hheap_chunk* n = c.next;
        free(c);
        c = n;
    }
}

// antialiased part

struct ActiveEdgeAA
{
    ActiveEdgeAA* next;
    float fx, fdx, fdy;
    float direction;
    float sy;
    float ey;
}

ActiveEdgeAA* new_active_aa(Hheap* hh, const Edge* e, float start_point)
{
    ActiveEdgeAA* z = cast(ActiveEdgeAA*)hheap_alloc(hh, ActiveEdgeAA.sizeof);
    const float dxdy = (e.x1 - e.x0) / (e.y1 - e.y0);
    assert(z);
    if (!z)
        return null;

    z.fdx = dxdy;
    z.fdy = dxdy != 0.0f ? (1.0f / dxdy) : 0.0f;
    z.fx = e.x0 + dxdy * (start_point - e.y0);
    z.direction = e.invert ? 1.0f : -1.0f;
    z.sy = e.y0;
    z.ey = max(e.y1, start_point); // avoid a floating-point precision problem
    z.next = null;
    return z;
}

// directly AA rasterize edges w/o supersampling
void rasterize_sorted_edges_aa(Edge* e, int n, RastParams params, Plotter plotter)
{
    const int width = params.clip.w;
    Hheap hh;
    ActiveEdgeAA* active;
    float[512 + 1] scanline_data = void;
    float* scanline, scanline2;

    if (width > 256)
        scanline = cast(float*)malloc((width * 2 + 1) * float.sizeof);
    else
        scanline = scanline_data.ptr;

    scanline2 = scanline + width;

    e[n].y0 = params.clip.h + 1;

    foreach (y; 0 .. params.clip.h)
    {
        // find scanline Y bounds
        const float scan_y_top = y;
        const float scan_y_bottom = y + 1;
        ActiveEdgeAA** step = &active;

        // update all active edges;
        // remove all active edges that terminate before the top of this scanline
        while (*step)
        {
            ActiveEdgeAA* z = *step;
            if (z.ey <= scan_y_top)
            {
                *step = z.next; // delete from list
                assert(z.direction);
                z.direction = 0;
                hheap_free(&hh, z);
            }
            else
            {
                step = &((*step).next); // advance through list
            }
        }

        // insert all edges that start before the bottom of this scanline
        while (e.y0 <= scan_y_bottom)
        {
            if (e.y0 != e.y1)
            {
                ActiveEdgeAA* z = new_active_aa(&hh, e, scan_y_top);
                if (z)
                {
                    // insert at front
                    z.next = active;
                    active = z;
                }
            }
            ++e;
        }

        // now process all active edges
        if (active)
        {
            scanline[0 .. width * 2 + 1] = 0;

            const span = fill_active_edges_aa(scanline, scanline2 + 1, width, active, scan_y_top);

            const int xx = params.clip.x;
            const int yy = params.clip.y + y;
            final switch (params.rule) with (RastFillRule)
            {
            case nonzero:
                alias cov = w => fabs(w);
                draw_scanline_aa!cov(scanline, width, span, xx, yy, plotter);
                break;
            case odd:
                alias cov = w => w == 0 ? 0 : fabs(w - quantize(w, 2.0f));
                draw_scanline_aa!cov(scanline, width, span, xx, yy, plotter);
                break;
            case zero:
                alias cov = w => w == 0 ? 1 : (1 - min(fabs(w), 1));
                draw_scanline_aa!cov(scanline, width, [0, width], xx, yy, plotter);
                break;
            case even:
                alias cov = w => w == 0 ? 1 : (1 - fabs(w - quantize(w, 2.0f)));
                draw_scanline_aa!cov(scanline, width, [0, width], xx, yy, plotter);
                break;
            }
        }
        else if (isComplementary(params.rule))
        {
            // fill outer areas
            plotter.setScanLine(params.clip.x, params.clip.x + width, params.clip.y + y);
        }

        // advance all the edges
        step = &active;
        while (*step)
        {
            ActiveEdgeAA* z = *step;
            z.fx += z.fdx; // advance to position for current scanline
            step = &((*step).next); // advance through list
        }
    }

    hheap_cleanup(&hh);

    if (scanline !is scanline_data.ptr)
        free(scanline);
}

// returns filled scanline boundaries
int[2] fill_active_edges_aa(float* scanline, float* scanline_fill, int len, const(ActiveEdgeAA)* e, float y_top)
{
    const float y_bottom = y_top + 1;
    float fx0 = len, fx1 = 0;

    while (e)
    {
        // brute force every pixel

        // compute intersection points with top & bottom
        assert(e.ey >= y_top);

        if (e.fdx != 0)
        {
            float x0 = e.fx;
            const dx = e.fdx;
            float xb = x0 + dx;
            float x_top, x_bottom;
            float sy0, sy1;
            float dy = e.fdy;
            assert(e.sy <= y_bottom && e.ey >= y_top);

            // compute endpoints of line segment clipped to this scanline (if the
            // line segment starts on this scanline). x0 is the intersection of the
            // line with y_top, but that may be off the line segment.
            if (e.sy > y_top)
            {
                x_top = x0 + dx * (e.sy - y_top);
                sy0 = e.sy;
            }
            else
            {
                x_top = x0;
                sy0 = y_top;
            }
            if (e.ey < y_bottom)
            {
                x_bottom = x0 + dx * (e.ey - y_top);
                sy1 = e.ey;
            }
            else
            {
                x_bottom = xb;
                sy1 = y_bottom;
            }
            // after clipping, the endpoint can appear out of bounds a bit
            if (x_top < 0)
                x_top = 0;
            if (x_top >= len)
                x_top = len - eps;
            if (x_bottom < 0)
                x_bottom = 0;
            if (x_bottom >= len)
                x_bottom = len - eps;

            // from here on, we don't have to range check x values

            if (cast(int)x_top == cast(int)x_bottom)
            {
                // simple case, only spans one pixel
                const int x = cast(int)x_top;
                const float height = sy1 - sy0;
                scanline[x] += e.direction * (1 - ((x_top - x) + (x_bottom - x)) / 2) * height;
                scanline_fill[x] += e.direction * height; // everything right of this pixel is filled
            }
            else
            {
                // covers 2+ pixels
                if (x_top > x_bottom)
                {
                    // flip scanline vertically; signed area is the same
                    float t;
                    sy0 = y_bottom - (sy0 - y_top);
                    sy1 = y_bottom - (sy1 - y_top);
                    t = sy0, sy0 = sy1, sy1 = t;
                    t = x_bottom, x_bottom = x_top, x_top = t;
                    dy = -dy;
                    t = x0, x0 = xb, xb = t;
                }

                const int x1 = cast(int)x_top;
                const int x2 = cast(int)x_bottom;
                // compute intersection with y axis at x1+1
                float y_crossing = (x1 + 1 - x0) * dy + y_top;

                const float sign = e.direction;
                // area of the rectangle covered from y0..y_crossing
                float area = sign * (y_crossing - sy0);
                // area of the triangle (x_top,y0), (x+1,y0), (x+1,y_crossing)
                scanline[x1] += area * (1 - ((x_top - x1) + (x1 + 1 - x1)) / 2);

                const float step = sign * dy;
                foreach (x; x1 + 1 .. x2)
                {
                    scanline[x] += area + step / 2;
                    area += step;
                }
                y_crossing += dy * (x2 - (x1 + 1));

                area = min(area, 1);

                scanline[x2] += area +
                    sign * (1 - ((x2 - x2) + (x_bottom - x2)) / 2) * (sy1 - y_crossing);
                scanline_fill[x2] += sign * (sy1 - sy0);
            }
        }
        else // fully vertical
        {
            // simplified version of the code above
            float x0 = e.fx;
            if (x0 < 0)
                x0 = 0;
            if (x0 >= len)
                x0 = len - eps;

            const int x = cast(int)x0;
            const float height = min(e.ey, y_bottom) - max(e.sy, y_top);
            scanline[x] += e.direction * (1 - (x0 - x)) * height;
            scanline_fill[x] += e.direction * height;
        }

        // find line boundaries for optimization
        fx0 = min(fx0, e.fx, e.fx + e.fdx);
        fx1 = max(fx1, e.fx, e.fx + e.fdx);

        e = e.next;
    }
    return [max(ifloor(fx0), 0), min(iceil(fx1), len)];
}

void draw_scanline_aa(alias calcCoverage)(const float* scanline, const int width,
    const int[2] span, const int x, const int y, Plotter plotter)
{
    const float* scanline2 = scanline + width;
    int prev = x;
    bool run;
    float sum = 0;
    foreach (i; span[0] .. span[1])
    {
        sum += scanline2[i];
        const cov = calcCoverage(scanline[i] + sum);
        if (cov > 1 - eps)
        {
            if (!run)
            {
                prev = x + i;
                run = true;
            }
        }
        else
        {
            const xx = x + i;
            if (run)
            {
                plotter.setScanLine(prev, xx, y);
                run = false;
            }
            if (cov > eps)
                plotter.mixPixel(xx, y, cov);
        }
    }
    if (run)
        plotter.setScanLine(prev, x + span[1], y);
}

// non-antialiased part

enum FIXSHIFT = 10;
enum FIX = 1 << FIXSHIFT;
enum FIXHALF = 1 << (FIXSHIFT - 1);
enum FIXMASK = FIX - 1;

struct ActiveEdge
{
   ActiveEdge *next;
   int x, dx;
   float ey;
   int direction;
}

ActiveEdge* new_active(Hheap* hh, const Edge* e, float start_point)
{
    ActiveEdge* z = cast(ActiveEdge*)hheap_alloc(hh, ActiveEdge.sizeof);
    const float dxdy = (e.x1 - e.x0) / (e.y1 - e.y0);
    assert(z);
    if (!z)
        return null;

    // round dx down to avoid overshooting
    if (dxdy < 0)
        z.dx = -ifloor(FIX * -dxdy);
    else
        z.dx = ifloor(FIX * dxdy);

    // use z.dx so when we offset later it's by the same amount
    z.x = ifloor(FIX * e.x0 + z.dx * (start_point - e.y0));

    z.ey = e.y1;
    z.next = null;
    z.direction = e.invert ? 1 : -1;
    return z;
}

void sort_active_edges_bubble(ref ActiveEdge* active)
{
    ActiveEdge** step;
    while (true)
    {
        bool changed;
        step = &active;
        while (*step && (*step).next)
        {
            if ((*step).x > (*step).next.x)
            {
                ActiveEdge* t = *step;
                ActiveEdge* q = t.next;

                t.next = q.next;
                q.next = t;
                *step = q;
                changed = true;
            }
            step = &(*step).next;
        }
        if (!changed)
            break;
    }
}

void sort_active_edges_merge(ref ActiveEdge* head)
{
    if (!head || !head.next)
        return;

    static void front_back_split(ActiveEdge* source, ref ActiveEdge* front, ref ActiveEdge* back)
    {
        ActiveEdge* slow = source;
        ActiveEdge* fast = source.next;

        while (fast)
        {
            fast = fast.next;
            if (fast)
            {
                slow = slow.next;
                fast = fast.next;
            }
        }

        front = source;
        back = slow.next;
        slow.next = null;
    }

    static ActiveEdge* sorted_merge(ActiveEdge* a, ActiveEdge* b)
    {
        if (!a) return b;
        if (!b) return a;

        ActiveEdge* result;
        if (a.x < b.x)
        {
            result = a;
            result.next = sorted_merge(a.next, b);
        }
        else
        {
            result = b;
            result.next = sorted_merge(a, b.next);
        }
        return result;
    }

    ActiveEdge* a;
    ActiveEdge* b;
    front_back_split(head, a, b);

    sort_active_edges_merge(a);
    sort_active_edges_merge(b);

    head = sorted_merge(a, b);
}

void rasterize_sorted_edges(Edge* e, int n, RastParams params, Plotter plotter)
{
    Hheap hh;
    ActiveEdge* active;

    e[n].y0 = params.clip.h + 1;

    foreach (y; 0 .. params.clip.h)
    {
        // find center of pixel for this scanline
        const float scan_y = y + 0.5f;
        ActiveEdge** step = &active;

        // update all active edges;
        // remove all active edges that terminate before the center of this scanline
        int count;
        while (*step)
        {
            ActiveEdge* z = *step;
            if (z.ey <= scan_y)
            {
                *step = z.next; // delete from list
                assert(z.direction);
                z.direction = 0;
                hheap_free(&hh, z);
            }
            else
            {
                z.x += z.dx; // advance to position for current scanline
                step = &((*step).next); // advance through list
            }
            count++;
        }

        // resort the list if needed
        if (count < 20)
            sort_active_edges_bubble(active);
        else
            sort_active_edges_merge(active);

        // insert all edges that start before the center of this scanline -- omit ones that also end on this scanline
        while (e.y0 <= scan_y)
        {
            if (e.y1 > scan_y)
            {
                ActiveEdge* z = new_active(&hh, e, scan_y);
                if (z)
                {
                    // find insertion point
                    if (!active)
                        active = z;
                    else if (z.x < active.x)
                    {
                        // insert at front
                        z.next = active;
                        active = z;
                    }
                    else
                    {
                        // find thing to insert AFTER
                        ActiveEdge* p = active;
                        while (p.next && p.next.x < z.x)
                            p = p.next;
                        // at this point, p.next.x is NOT < z.x
                        z.next = p.next;
                        p.next = z;
                    }
                }
            }
            ++e;
        }

        // now process all active edges
        if (active)
        {
            const int len = params.clip.w;
            const int xx = params.clip.x;
            const int yy = params.clip.y + y;
            final switch (params.rule) with (RastFillRule)
            {
            case nonzero:
                fill_active_edges!(w => w != 0)(len, active, xx, yy, plotter);
                break;
            case odd:
                fill_active_edges!(w => w % 2 != 0)(len, active, xx, yy, plotter);
                break;
            case zero:
                fill_active_edges!(w => w == 0)(len, active, xx, yy, plotter);
                break;
            case even:
                fill_active_edges!(w => w % 2 == 0)(len, active, xx, yy, plotter);
                break;
            }
        }
        else if (isComplementary(params.rule))
        {
            // fill outer areas
            plotter.setScanLine(params.clip.x, params.clip.x + params.clip.w, params.clip.y + y);
        }
    }

    hheap_cleanup(&hh);
}

void fill_active_edges(alias filled)(int len, const(ActiveEdge)* e, int x, int y, Plotter plotter)
{
    int x0, w;

    while (e)
    {
        if (!filled(w))
        {
            // if we're currently in the unfilled area, we need to record the edge start point
            x0 = e.x;
            w += e.direction;
        }
        else
        {
            const int x1 = e.x;
            w += e.direction;
            // if we went to the unfilled area, we need to draw
            if (!filled(w))
                draw_scanline(len, x0, x1, x, y, plotter);
        }

        e = e.next;
    }
    // fill the rest (only in complementary fill rules)
    if (filled(w))
        draw_scanline(len, x0, len << FIXSHIFT, x, y, plotter);
}

void draw_scanline(const int len, const int x0, const int x1, const int x, const int y, Plotter plotter)
{
    int i = x0 >> FIXSHIFT;
    int j = x1 >> FIXSHIFT;

    if (i < len && j >= 0)
    {
        if (i != j)
        {
            if (i >= 0) // check x0 coverage
            {
                if (FIX - (x0 & FIXMASK) < FIXHALF)
                    i++;
            }
            else
                i = 0; // clip

            if (j < len) // check x1 coverage
            {
                if ((x1 & FIXMASK) >= FIXHALF)
                    j++;
            }
            else
                j = len; // clip

            // fill pixels between x0 and x1
            plotter.setScanLine(x + i, x + j, y);
        }
        else
        {
            // x0,x1 are the same pixel, so compute combined coverage
            if (x1 - x0 >= FIXHALF)
            {
                const xx = x + i;
                plotter.setScanLine(xx, xx + 1, y);
            }
        }
    }
}

//===============================================================
// Trapezoid rasterizer

public struct HorizEdge
{
    float l = 0, r = 0, y = 0;

    static bool isValidTrapezoid(HorizEdge top, HorizEdge bot) nothrow
    {
        return top.y <= bot.y && // a trapezoid with zero height is a chain break
            ((top.l + eps < top.r && bot.l <= bot.r) ||
             (bot.l + eps < bot.r && top.l <= top.r));
    }
}

public void rasterizeTrapezoidChain(const HorizEdge[] chain, RastParams params, Plotter plotter)
    in(chain.length > 1)
    in(!params.clip.empty)
    in(plotter)
{
    float xmin = float.max, xmax = -float.max;
    foreach (ref e; chain)
    {
        xmin = min(xmin, e.l);
        xmax = max(xmax, e.r);
    }

    const h_bounds = SpanI(max(params.clip.x, ifloor(xmin)), min(params.clip.x + params.clip.w, iceil(xmax)));
    if (h_bounds.start >= h_bounds.end)
        return;
    const v_bounds = SpanI(params.clip.y, params.clip.y + params.clip.h);
    auto accum = Accumulator(h_bounds);

    int y;
    foreach (i; 1 .. chain.length)
    {
        HorizEdge top = chain[i - 1];
        HorizEdge bot = chain[i];
        assert(HorizEdge.isValidTrapezoid(top, bot));

        if (fequal2(top.y, bot.y))
            continue;
        if (top.y >= v_bounds.end)
            break;
        if (bot.y <= v_bounds.start)
            continue;

        TrapezoidI itrap = {top.l, top.r, bot.l, bot.r};

        const height = bot.y - top.y;
        const step_l = (bot.l - top.l) / height;
        const step_r = (bot.r - top.r) / height;
        const top_bound = max(top.y, v_bounds.start);
        const bot_bound = min(bot.y, v_bounds.end);
        int y0 = iround(top_bound);
        int y1 = iround(bot_bound);
        float diff0, diff1;
        bool top_cap, bot_cap;

        if (!fequal2(top.y, y0))
        {
            if (y0 < top.y)
                y0++;

            diff0 = y0 - top.y;
            top_cap = diff0 < 1 && top_bound < y0;
            itrap.tl += step_l * diff0;
            itrap.tr += step_r * diff0;
        }
        if (!fequal2(bot.y, y1))
        {
            if (bot.y < y1)
                y1--;

            diff1 = bot.y - y1;
            bot_cap = diff1 < 1 && y1 < bot_bound;
            itrap.bl -= step_l * diff1;
            itrap.br -= step_r * diff1;
        }

        // a thin trapezoid inside one scan-line
        if (y0 > y1)
        {
            y = y1;
            accum.add(ScanLine(top.l, top.r, bot.l, bot.r), height, step_l, step_r);
            continue;
        }
        // top line
        if (top_cap)
        {
            accum.add(ScanLine(top.l, top.r, itrap.tl, itrap.tr), diff0, step_l, step_r);
            if (params.antialias)
                accum.plot_aa(y0 - 1, plotter);
            else
                accum.plot(y0 - 1, plotter);
        }
        // the body within integer bounds
        if (y0 < y1)
        {
            itrap.ty = y0;
            itrap.by = y1;
            if (params.antialias)
                rasterize_trapezoid_i_aa(h_bounds, itrap, step_l, step_r, plotter);
            else
                rasterize_trapezoid_i(h_bounds, itrap, step_l, step_r, plotter);
        }
        // bottom line
        if (bot_cap)
        {
            y = y1;
            accum.add(ScanLine(itrap.bl, itrap.br, bot.l, bot.r), diff1, step_l, step_r);
        }
    }
    if (params.antialias)
        accum.plot_aa(y, plotter);
    else
        accum.plot(y, plotter);
}

struct SpanI
{
    int start, end;
}

struct TrapezoidI
{
    float tl = 0, tr = 0;
    float bl = 0, br = 0;
    int ty, by;
}

struct ScanLine
{
    float tl = 0, tr = 0;
    float bl = 0, br = 0;
}

struct Accumulator
{
    nothrow:

    // TODO: rewrite to store the difference in coverage
    private float* scanline;
    private SpanI frame;
    private int width;
    private bool ready;

    @disable this();
    @disable this(this);

    this(SpanI frame)
    {
        this.frame = frame;
        this.width = frame.end - frame.start;
    }

    ~this()
    {
        free(scanline);
    }

    private void initialize()
    {
        if (!scanline)
            scanline = cast(float*)malloc(width * float.sizeof);
        if (!scanline)
            assert(0);
        scanline[0 .. width] = 0;
        ready = true;
    }

    void add(const ScanLine ln, const float height, const float step_l, const float step_r)
    {
        if (!ready)
            initialize();

        const slope_l = step_l != 0 ? fabs(1 / step_l) : 10;
        const slope_r = step_r != 0 ? fabs(1 / step_r) : 10;

        const xf_ll = (step_l < 0 ? ln.bl : ln.tl) - frame.start;
        const xf_lr = (step_l < 0 ? ln.tl : ln.bl) - frame.start;
        const xf_rl = (step_r < 0 ? ln.br : ln.tr) - frame.start;
        const xf_rr = (step_r < 0 ? ln.tr : ln.br) - frame.start;
        const int x_ll = ifloor(xf_ll);
        const int x_lr = iceil(xf_lr);
        const int x_rl = ifloor(xf_rl);
        const int x_rr = iceil(xf_rr);

        // the algorithm assumes that added lines never overlap,
        // which is true for trapezoid chain
        if (x_ll < x_lr)
        {
            const int len = x_lr - x_ll;
            if (slope_l / height <= 1 || len == 2)
            {
                const int next = x_ll + 1;
                const int last = x_lr - 1;
                float b;
                {
                    const a0 = next - xf_ll;
                    const b0 = a0 * slope_l;
                    b = b0;
                    this[x_ll] += a0 * b0 / 2;
                }
                if (len > 2)
                {
                    float area = (b + b + slope_l) / 2;
                    b += slope_l * (len - 2);
                    foreach (x; next .. last)
                    {
                        this[x] += area;
                        area += slope_l;
                    }
                }
                {
                    const a = xf_lr - last;
                    b = height - b;
                    this[last] += a * (height - b / 2);
                }
            }
            else
            {
                assert(len == 1);
                this[x_ll] += (xf_lr - xf_ll) * height / 2;
            }
            // there may be a small rectangle between
            this[x_lr - 1] += (min(xf_rl, x_lr) - xf_lr) * height;
        }

        float[] middle = this[x_lr .. x_rl];
        if (middle.length)
            middle[] += height;

        if (x_rl < x_rr)
        {
            this[x_rl] += (xf_rl - max(xf_lr, x_rl)) * height;

            const int len = x_rr - x_rl;
            if (slope_r / height <= 1 || len == 2)
            {
                const int next = x_rl + 1;
                const int last = x_rr - 1;
                float b;
                {
                    const a0 = next - xf_rl;
                    const b0 = a0 * slope_r;
                    b = height - b0;
                    this[x_rl] += a0 * (height - b0 / 2);
                }
                if (len > 2)
                {
                    float area = (b + b - slope_r) / 2;
                    b -= slope_r * (len - 2);
                    foreach (x; next .. last)
                    {
                        this[x] += area;
                        area -= slope_r;
                    }
                }
                {
                    const a = xf_rr - last;
                    this[last] += a * b / 2;
                }
            }
            else
            {
                assert(len == 1);
                this[x_rl] += (xf_rr - xf_rl) * height / 2;
            }
        }
    }

    private void opIndexOpAssign(string op)(float v, int i)
    {
        // super simple clipping
        if (0 <= i && i < width)
            mixin("scanline[i]" ~ op ~ "= v;");
    }

    private float[] opSlice(int from, int to)
    {
        from = max(from, 0);
        to = min(to, width);
        return from < to ? scanline[from .. to] : null;
    }

    void plot_aa(int y, Plotter plotter)
    {
        if (!ready)
            return;

        int prev = frame.start;
        bool run;
        foreach (i; 0 .. width)
        {
            const cov = scanline[i];
            if (cov > 1 - eps)
            {
                if (!run)
                {
                    prev = frame.start + i;
                    run = true;
                }
            }
            else
            {
                if (run)
                {
                    plotter.setScanLine(prev, frame.start + i, y);
                    run = false;
                }
                if (cov > eps)
                    plotter.mixPixel(frame.start + i, y, cov);
            }
        }
        if (run)
            plotter.setScanLine(prev, frame.end, y);

        ready = false;
    }

    void plot(int y, Plotter plotter)
    {
        if (!ready)
            return;

        int prev = frame.start;
        bool run;
        foreach (i; 0 .. width)
        {
            const cov = scanline[i];
            if (cov > 0.5f)
            {
                if (!run)
                {
                    prev = frame.start + i;
                    run = true;
                }
            }
            else if (run)
            {
                plotter.setScanLine(prev, frame.start + i, y);
                run = false;
                break;
            }
        }
        if (run)
            plotter.setScanLine(prev, frame.end, y);

        ready = false;
    }
}

void rasterize_trapezoid_i_aa(SpanI clip, ref const TrapezoidI trap, float step_l, float step_r, Plotter plotter)
{
    const slope_l = step_l != 0 ? fabs(1 / step_l) : 10;
    const slope_r = step_r != 0 ? fabs(1 / step_r) : 10;

    void draw_scan_line(ref const ScanLine ln, int y)
    {
        const xf_ll = step_l < 0 ? ln.bl : ln.tl;
        const xf_lr = step_l < 0 ? ln.tl : ln.bl;
        const xf_rl = step_r < 0 ? ln.br : ln.tr;
        const xf_rr = step_r < 0 ? ln.tr : ln.br;
        const int x_ll = ifloor(xf_ll);
        const int x_lr = iceil(xf_lr);
        const int x_rl = ifloor(xf_rl);
        const int x_rr = iceil(xf_rr);
        const int x_ll_ch = clamp(x_ll, clip.start, clip.end);
        const int x_lr_ch = clamp(x_lr, clip.start, clip.end);
        const int x_rl_ch = clamp(x_rl, clip.start, clip.end);
        const int x_rr_ch = clamp(x_rr, clip.start, clip.end);

        if (x_ll_ch < x_lr_ch)
        {
            const int len = x_lr - x_ll;
            if (slope_l <= 1 || len == 2)
            {
                const int next = x_ll + 1;
                const int last = x_lr - 1;
                float b;
                {
                    const a0 = next - xf_ll;
                    const b0 = a0 * slope_l;
                    b = b0;
                    if (x_ll == x_ll_ch)
                    {
                        const area = a0 * b0 / 2;
                        plotter.mixPixel(x_ll, y, area);
                    }
                }
                foreach (x; next .. last)
                {
                    const b0 = b;
                    b += slope_l;
                    if (x_ll_ch <= x && x < x_lr_ch)
                    {
                        const area = (b0 + b) / 2;
                        plotter.mixPixel(x, y, area);
                    }
                }
                if (x_lr == x_lr_ch)
                {
                    const a = xf_lr - last;
                    b = 1 - b;
                    const area = 1 - a * b / 2;
                    plotter.mixPixel(last, y, area);
                }
            }
            else
            {
                assert(len == 1);
                const area = x_lr - (xf_ll + xf_lr) / 2;
                plotter.mixPixel(x_ll, y, area);
            }
        }
        if (x_lr_ch < x_rl_ch)
        {
            plotter.setScanLine(x_lr_ch, x_rl_ch, y);
        }
        if (x_rl_ch < x_rr_ch)
        {
            const int len = x_rr - x_rl;
            if (slope_r <= 1 || len == 2)
            {
                const int next = x_rl + 1;
                const int last = x_rr - 1;
                float b;
                {
                    const a0 = next - xf_rl;
                    const b0 = a0 * slope_r;
                    b = 1 - b0;
                    if (x_rl == x_rl_ch)
                    {
                        const area = 1 - a0 * b0 / 2;
                        plotter.mixPixel(x_rl, y, area);
                    }
                }
                foreach (x; next .. last)
                {
                    const b0 = b;
                    b -= slope_r;
                    if (x_rl_ch <= x && x < x_rr_ch)
                    {
                        const area = (b0 + b) / 2;
                        plotter.mixPixel(x, y, area);
                    }
                }
                if (x_rr == x_rr_ch)
                {
                    const a = xf_rr - last;
                    const area = a * b / 2;
                    plotter.mixPixel(last, y, area);
                }
            }
            else
            {
                assert(len == 1);
                const area = (xf_rl + xf_rr) / 2 - x_rl;
                plotter.mixPixel(x_rl, y, area);
            }
        }
    }

    ScanLine ln = {trap.tl, trap.tr, trap.tl, trap.tr};

    foreach (y; trap.ty .. trap.by)
    {
        ln.bl += step_l;
        ln.br += step_r;
        draw_scan_line(ln, y);
        ln.tl = ln.bl;
        ln.tr = ln.br;
    }
}

void rasterize_trapezoid_i(SpanI clip, TrapezoidI trap, float step_l, float step_r, Plotter plotter)
{
    foreach (y; trap.ty .. trap.by)
    {
        const int x0 = max(iroundFast(trap.tl), clip.start);
        const int x1 = min(iroundFast(trap.tr), clip.end);
        if (x0 < x1)
            plotter.setScanLine(x0, x1, y);
        trap.tl += step_l;
        trap.tr += step_r;
    }
}

//===============================================================
// Line rasterizer

public void rasterizeLine(Vec2 p0, Vec2 p1, ref const RastParams params, Plotter plotter)
    in(!params.clip.empty)
    in(plotter)
{
    const visible = clip_line(RectI(params.clip), p0.x, p0.y, p1.x, p1.y);
    if (!visible)
        return;

    assert(p0.x >= 0 && p0.y >= 0 && p1.x >= 0 && p1.y >= 0);

    if (params.antialias)
    {
        const dx = p1.x - p0.x;
        const dy = p1.y - p0.y;
        const ax = abs(dx);
        const ay = abs(dy);
        if (ax > ay)
            rasterize_line_hori_aa(p0.x, p0.y, p1.x, p1.y, ay < eps && fzero2(p0.x - round(p0.x)), plotter);
        else
            rasterize_line_vert_aa(p0.x, p0.y, p1.x, p1.y, ax < eps && fzero2(p0.y - round(p0.y)), plotter);
    }
    else
    {
        const x0i = iround(p0.x);
        const y0i = iround(p0.y);
        const x1i = iround(p1.x);
        const y1i = iround(p1.y);
        rasterize_line(x0i, y0i, x1i, y1i, plotter);
    }
}

bool clip_line(RectI clip, ref float x0, ref float y0, ref float x1, ref float y1)
{
    // Cohen–Sutherland clipping algorithm clips a line from
    // P0 = (x0, y0) to P1 = (x1, y1) against a rectangle with
    // diagonal from (xmin, ymin) to (xmax, ymax).
    // https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm

    enum OutCode : ubyte
    {
        inside = 0,
        left   = 1 << 0,
        right  = 1 << 1,
        bottom = 1 << 2,
        top    = 1 << 3,
    }

    // Compute the bit code for a point (x, y) using the clip rectangle
    // bounded diagonally by (xmin, ymin), and (xmax, ymax)
    static OutCode computeOutCode(ref const RectI clip, float x, float y)
    {
        OutCode code; // initialised as being inside of clip window

        if (x < clip.left) // to the left of clip window
            code |= OutCode.left;
        else if (x > clip.right) // to the right of clip window
            code |= OutCode.right;
        if (y < clip.top) // below the clip window
            code |= OutCode.bottom;
        else if (y > clip.bottom) // above the clip window
            code |= OutCode.top;

        return code;
    }

    // compute outcodes for P0, P1, and whatever point lies outside the clip rectangle
    OutCode outcode0 = computeOutCode(clip, x0, y0);
    OutCode outcode1 = computeOutCode(clip, x1, y1);
    bool accept;

    while (true)
    {
        if (!(outcode0 | outcode1))
        { // Bitwise OR is 0. Trivially accept and get out of loop
            accept = true;
            break;
        }
        else if (outcode0 & outcode1)
        { // Bitwise AND is not 0. Trivially reject and get out of loop
            break;
        }
        else
        {
            // failed both tests, so calculate the line segment to clip
            // from an outside point to an intersection with clip edge
            float x, y;

            // At least one endpoint is outside the clip rectangle; pick it.
            const outcodeOut = outcode0 ? outcode0 : outcode1;

            // Now find the intersection point;
            // use formulas y = y0 + slope * (x - x0), x = x0 + (1 / slope) * (y - y0)
            if (outcodeOut & OutCode.top)
            { // point is above the clip rectangle
                x = x0 + (x1 - x0) * (clip.bottom - y0) / (y1 - y0);
                y = clip.bottom;
            }
            else if (outcodeOut & OutCode.bottom)
            { // point is below the clip rectangle
                x = x0 + (x1 - x0) * (clip.top - y0) / (y1 - y0);
                y = clip.top;
            }
            else if (outcodeOut & OutCode.right)
            { // point is to the right of clip rectangle
                y = y0 + (y1 - y0) * (clip.right - x0) / (x1 - x0);
                x = clip.right;
            }
            else if (outcodeOut & OutCode.left)
            { // point is to the left of clip rectangle
                y = y0 + (y1 - y0) * (clip.left - x0) / (x1 - x0);
                x = clip.left;
            }

            // Now we move outside point to intersection point to clip
            // and get ready for next pass.
            if (outcodeOut == outcode0)
            {
                x0 = x;
                y0 = y;
                outcode0 = computeOutCode(clip, x0, y0);
            }
            else
            {
                x1 = x;
                y1 = y;
                outcode1 = computeOutCode(clip, x1, y1);
            }
        }
    }
    return accept;
}

void rasterize_line_hori_aa(float x0, float y0, float x1, float y1, bool fast, Plotter plotter)
{
    const dx = x1 - x0;
    const dy = y1 - y0;
    if (x0 > x1)
    {
        swap(x0, x1);
        swap(y0, y1);
    }
    const gradient = dx != 0 ? dy / dx : 1;

    // handle the first endpoint
    float xEnd = round(x0);
    float yEnd = y0 + gradient * (xEnd - x0);
    float xGap = rfpart(x0 + 0.5f);
    const x0i = cast(int)xEnd;
    const y0i = ipart(yEnd);
    plotter.mixPixel(x0i, y0i, rfpart(yEnd) * xGap);
    plotter.mixPixel(x0i, y0i + 1, fpart(yEnd) * xGap);
    // first y-intersection for the main loop
    float yInter = yEnd + gradient;

    // handle the second endpoint
    xEnd = round(x1);
    yEnd = y1 + gradient * (xEnd - x1);
    xGap = fpart(x1 + 0.5f);
    const x1i = cast(int)xEnd;
    const y1i = ipart(yEnd);
    plotter.mixPixel(x1i, y1i, rfpart(yEnd) * xGap);
    plotter.mixPixel(x1i, y1i + 1, fpart(yEnd) * xGap);

    // main loop
    if (fast)
    {
        const y = iround(y0);
        plotter.setScanLine(x0i + 1, x1i, y);
    }
    else
    {
        foreach (x; x0i + 1 .. x1i)
        {
            const y = ipart(yInter);
            plotter.mixPixel(x, y, y + 1 - yInter); // rfpart
            plotter.mixPixel(x, y + 1, yInter - y); // fpart
            yInter += gradient;
        }
    }
}

void rasterize_line_vert_aa(float x0, float y0, float x1, float y1, bool fast, Plotter plotter)
{
    const dx = x1 - x0;
    const dy = y1 - y0;
    if (y0 > y1)
    {
        swap(x0, x1);
        swap(y0, y1);
    }
    const float gradient = dy != 0 ? dx / dy : 1;

    // handle the first endpoint
    float yEnd = round(y0);
    float xEnd = x0 + gradient * (yEnd - y0);
    float yGap = rfpart(y0 + 0.5f);
    const y0i = cast(int)yEnd;
    const x0i = ipart(xEnd);
    plotter.mixPixel(x0i, y0i, rfpart(xEnd) * yGap);
    plotter.mixPixel(x0i + 1, y0i, fpart(xEnd) * yGap);
    // first x-intersection for the main loop
    float xInter = xEnd + gradient;

    // handle the second endpoint
    yEnd = round(y1);
    xEnd = x1 + gradient * (yEnd - y1);
    yGap = fpart(y1 + 0.5f);
    const y1i = cast(int)yEnd;
    const x1i = ipart(xEnd);
    plotter.mixPixel(x1i, y1i, rfpart(xEnd) * yGap);
    plotter.mixPixel(x1i + 1, y1i, fpart(xEnd) * yGap);

    // main loop
    if (fast)
    {
        const x = iround(x0);
        foreach (y; y0i + 1 .. y1i)
        {
            plotter.mixPixel(x, y, 1);
        }
    }
    else
    {
        foreach (y; y0i + 1 .. y1i)
        {
            const x = ipart(xInter);
            plotter.mixPixel(x, y, x + 1 - xInter); // rfpart
            plotter.mixPixel(x + 1, y, xInter - x); // fpart
            xInter += gradient;
        }
    }
}

void rasterize_line(int x0, int y0, int x1, int y1, Plotter plotter)
{
    // fast path - horizontal
    if (y0 == y1)
    {
        if (x0 > x1)
            swap(x0, x1);
        plotter.setScanLine(x0, x1 + 1, y0);
        return;
    }
    // fast path - vertical
    if (x0 == x1)
    {
        if (y0 > y1)
            swap(y0, y1);
        foreach (y; y0 .. y1 + 1)
            plotter.setPixel(x0, y);
        return;
    }

    const int dx = x1 - x0;
    const int ix = (dx > 0) - (dx < 0);
    const int dx2 = abs(dx) * 2;
    const int dy = y1 - y0;
    const int iy = (dy > 0) - (dy < 0);
    const int dy2 = abs(dy) * 2;
    plotter.setPixel(x0, y0);
    if (dx2 >= dy2)
    {
        int error = dy2 - dx2 / 2;
        while (x0 != x1)
        {
            if (error >= 0 && (error || ix > 0))
            {
                error -= dx2;
                y0 += iy;
            }
            error += dy2;
            x0 += ix;
            plotter.setPixel(x0, y0);
        }
    }
    else
    {
        int error = dx2 - dy2 / 2;
        while (y0 != y1)
        {
            if (error >= 0 && (error || iy > 0))
            {
                error -= dy2;
                x0 += ix;
            }
            error += dx2;
            y0 += iy;
            plotter.setPixel(x0, y0);
        }
    }
}

enum eps = 0.01f;

int ipart(float x)
{
    return cast(int)x;
}

int ifloor(float x)
{
    return cast(int)floor(x);
}

int iceil(float x)
{
    return cast(int)ceil(x);
}

int iround(float x)
{
    return cast(int)round(x);
}

int iroundFast(float x)
{
    return cast(int)lrint(x);
}

float fpart(float x)
{
    return x - floor(x);
}

float rfpart(float x)
{
    return floor(x) + 1 - x;
}
