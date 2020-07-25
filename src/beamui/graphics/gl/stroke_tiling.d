/**
Split thin strokes into tiles.

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.gl.stroke_tiling;

import beamui.core.config;

// dfmt off
static if (USE_OPENGL):
// dfmt on
import beamui.core.collections : Buf;
import beamui.core.geometry;
import beamui.core.linalg : Vec2, Vec2i;
import beamui.core.logger;
import beamui.core.math;
import beamui.graphics.gl.api;
import beamui.graphics.gl.objects;
import beamui.graphics.pen : PathIter;
import Math = std.math;

package nothrow:

enum TILE_SIZE = 16;

private struct Segment
{
    Vec2 a, b;
}

private struct Tile
{
    Buf!ushort segments;
}

struct PackedTile
{
    ushort x, y;
    uint segments;
}

struct TileGrid
{
nothrow:
    private
    {
        Tile[] tileSegments;
        Buf!Segment packedSegments;

        SizeI size;
    }

    void prepare(int viewportW, int viewportH)
    {
        size = SizeI(viewportW / TILE_SIZE + 1, viewportH / TILE_SIZE + 1);

        const maxCount = size.w * size.h * 2;
        if (tileSegments.length < maxCount)
        {
            // BUG in compiler: Bufs are not destroyed/moved on array resize
            foreach (ref tile; tileSegments)
                tile = Tile.init;
            tileSegments = new Tile[maxCount];
        }
        packedSegments.clear();
    }

    /// `points` are already transformed and scaled down. `trBounds` is only transformed
    void clipStrokeToLattice(const Vec2[] points, const uint[] contours, ref Buf!PackedTile pack, RectI trBounds, float width)
    {
        enum pixel = 1.0f / TILE_SIZE;
        const halfWidth = (width * 0.5f + 1) * pixel;
        // dfmt off
        RectI bounds = RectI(
            cast(int)Math.floor(trBounds.left * pixel - halfWidth),
            cast(int)Math.floor(trBounds.top * pixel - halfWidth),
            cast(int)Math.ceil(trBounds.right * pixel + halfWidth),
            cast(int)Math.ceil(trBounds.bottom * pixel + halfWidth),
        );
        bounds.intersect(RectI(0, 0, size.w, size.h));
        // dfmt on

        foreach (tileY; bounds.top .. bounds.bottom)
        {
            const offset = tileY * size.w;
            foreach (ref tile; tileSegments[offset + bounds.left .. offset + bounds.right])
            {
                tile.segments.clear();
            }
        }

        uint first;
        foreach (len; contours)
        {
            if (first + len >= ushort.max)
                break;

            foreach (i; first + 1 .. first + len)
            {
                const Vec2 a = points[i - 1], b = points[i];
                const Vec2 n0 = (b - a).normalized * halfWidth;
                const Vec2 n1 = n0.rotated90fromXtoY;
                const Vec2 c1 = n0 + n1;
                const Vec2 c2 = n0 - n1;
                const index = cast(ushort)(i - 1);
                traverseTiles(this, bounds, index, a - c1, b + c2);
                traverseTiles(this, bounds, index, a - c2, b + c1);
            }
            first += len;
        }

        foreach (tileY; bounds.top .. bounds.bottom)
        {
            const Tile* row = &tileSegments[tileY * size.w];
            foreach (tileX; bounds.left .. bounds.right)
            {
                const Tile* tile = &row[tileX];
                if (!tile.segments.length)
                    continue;

                PackedTile ptile = void;
                ptile.x = cast(ushort)tileX;
                ptile.y = cast(ushort)tileY;
                ptile.segments = packedSegments.length << 8 | tile.segments.length;
                pack ~= ptile;

                foreach (index; tile.segments[])
                {
                    packedSegments ~= Segment(points[index], points[index + 1]);
                }
            }
        }
    }

    private void add(ref const RectI bounds, Vec2i tileCoords, ushort index)
    {
        if (!bounds.contains(tileCoords))
            return;

        const i = tileCoords.y * size.w + tileCoords.x;
        Tile* tile = &tileSegments[i];
        if (!tile.segments.length || tile.segments[$ - 1] != index)
            tile.segments ~= index;
    }
}

/// Implements a fast voxel traversal algorithm (http://www.cse.yorku.ca/~amana/research/grid.pdf)
private void traverseTiles(ref TileGrid grid, RectI bounds, ushort index, Vec2 from, Vec2 to)
{
    Vec2i tileCoords = Vec2i(cast(int)from.x, cast(int)from.y);
    const tileCoordsTo = Vec2i(cast(int)to.x, cast(int)to.y);

    // just one tile
    if (tileCoords == tileCoordsTo)
    {
        grid.add(bounds, tileCoords, index);
        return;
    }

    static int sgn(float x)
    {
        return x < 0 ? -1 : 1;
    }

    static float frac(float x)
    {
        return x - cast(int)x;
    }

    const vec = to - from;
    const step = Vec2i(sgn(vec.x), sgn(vec.y));

    Vec2 tDelta = Vec2(1_000_000);
    if (!fzero6(vec.x))
        tDelta.x = step.x / vec.x;
    if (!fzero6(vec.y))
        tDelta.y = step.y / vec.y;

    Vec2 tMax = tDelta;
    tMax.x *= step.x > 0 ? 1 - frac(from.x) : frac(from.x);
    tMax.y *= step.y > 0 ? 1 - frac(from.y) : frac(from.y);

    if (min(tMax.x, tMax.y) != 0)
        grid.add(bounds, tileCoords, index);

    const maxSteps = Math.abs(tileCoords.x - tileCoordsTo.x) + Math.abs(tileCoords.y - tileCoordsTo.y);
    for (int i; i < maxSteps && tileCoords != tileCoordsTo; i++)
    {
        if (tMax.x < tMax.y)
        {
            tMax.x += tDelta.x;
            tileCoords.x += step.x;
        }
        else
        {
            tMax.y += tDelta.y;
            tileCoords.y += step.y;
        }
        grid.add(bounds, tileCoords, index);
    }
}

struct TileBuffer
{
nothrow:
    enum ROW_LENGTH = 256;

    TexId buf_segments;

    private
    {
        int segmentRows;
    }

    @disable this(this);

    void initialize()
    {
        Tex2D.bind(buf_segments);
        Tex2D.setBasicParams(TexFiltering.sharp, TexMipmaps.no, TexWrap.clamp);
        Tex2D.unbind();
    }

    ~this()
    {
        Tex2D.del(buf_segments);
    }

    void upload(ref const TileGrid grid)
    {
        if (grid.packedSegments.length == 0)
            return;

        {
            const fmt = TexFormat(GL_RGBA, GL_RGBA32F, GL_FLOAT);
            Tex2D.bind(buf_segments);
            Tex2D.upload1D(fmt, segmentRows, ROW_LENGTH, 1, grid.packedSegments[]);
        }
        Tex2D.unbind();
    }
}
