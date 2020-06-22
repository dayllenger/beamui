/**
Atlas to pack rectangles, add or remove them over time.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.atlas;

import std.array : insertInPlace;
import beamui.core.functions : eliminate;
import beamui.core.geometry : BoxI, PointI, RectI, SizeI;
import beamui.core.math : min;

alias ID = uint;

/** Atlas places rectangles in a frame to use space optimally.

    Atlas can grow. It will never move rectangles.

    It works much faster when the rectangles have similar sizes and are sorted
    from small to big.
*/
struct Atlas
{
nothrow:

    private
    {
        const SizeI _maxSize;
        const SizeI _initialSize;
        const int gap;
        const int minTileSize;
        SizeI _size;

        BoxI[ID] added;
        int[] cols; // widths
        int[] rows; // heights
        bool[][] occupied; // by rows
        SizeI[] minFailed; // by rows
    }

    @disable this();
    @disable this(this);

    this(SizeI maxSize, SizeI initialSize, bool onePixelGap)
    in (0 < maxSize.w && maxSize.w <= 2 ^^ 16)
    in (0 < maxSize.h && maxSize.h <= 2 ^^ 16)
    in (0 < initialSize.w && initialSize.w <= maxSize.w)
    in (0 < initialSize.h && initialSize.h <= maxSize.h)
    {
        _maxSize = maxSize;
        _size = _initialSize = initialSize;
        gap = onePixelGap ? 1 : 0;
        minTileSize = 8;

        cols = [initialSize.w];
        rows = [initialSize.h];
        occupied = [[false]];
        minFailed = [initialSize];
    }

    /// Add a rectangle of `id` (if `size` isn't `null`) or find already added
    AtlasResult findOrAdd(ID id, const SizeI* size)
    {
        if (auto p = id in added)
            return AtlasResult(*p, _size, false);

        return size ? add(id, *size) : AtlasResult.init;
    }

    private AtlasResult add(ID id, SizeI size)
    in (size.w > 0 && size.h > 0)
    {
        const sizePlusGap = SizeI(size.w + gap, size.h + gap);
        // find free cells
        foreach (j; 0 .. rows.length) // from top to bottom
        {
            SizeI* pMinFailed = minFailed.ptr + j;
            if (pMinFailed.w < size.w || pMinFailed.h < size.h)
                continue;

            const bool* occup = occupied.ptr[j].ptr;
            foreach (i; 0 .. cols.length) // from left to right
            {
                if (occup[i])
                    continue;

                PointI pos = void;
                if (tryToAdd(sizePlusGap, i, j, pos))
                {
                    const b = BoxI(pos, size);
                    added[id] = b;
                    return AtlasResult(b, _size, true);
                }
            }
            if (size.w <= pMinFailed.w && size.h <= pMinFailed.h)
            {
                // sacrifice quality a bit for optimization
                if (size.w <= size.h)
                {
                    pMinFailed.w = size.w;
                    pMinFailed.h = size.h - 1;
                }
                else
                {
                    pMinFailed.w = size.w - 1;
                    pMinFailed.h = size.h;
                }
            }
        }
        // does not fit, try to resize
        const canGrowH = _size.w + gap < _maxSize.w;
        const canGrowV = _size.h + gap < _maxSize.h;
        if (canGrowH || canGrowV)
        {
            if (canGrowH && ((canGrowV && _size.w <= _size.h) || !canGrowV))
            {
                const oldWidth = _size.w;
                _size.w = min(oldWidth * 2, _maxSize.w);
                const addedColumn = _size.w - oldWidth - gap;
                cols ~= addedColumn;
                foreach (j; 0 .. rows.length)
                {
                    occupied[j] ~= false;
                    minFailed[j].w += addedColumn;
                    minFailed[j].h = _size.h;
                }
            }
            else
            {
                const oldHeight = _size.h;
                _size.h = min(oldHeight * 2, _maxSize.h);
                rows ~= _size.h - oldHeight - gap;
                occupied ~= new bool[cols.length];
                minFailed[$ - 1] = _size;
                minFailed ~= _size;
            }
            return add(id, size);
        }
        // no place
        return AtlasResult.init;
    }

    private bool tryToAdd(const SizeI size, const size_t i, const size_t j, out PointI result)
    {
        SizeI block = SizeI(cols.ptr[i], rows.ptr[j]);
        size_t iend = i + 1;
        size_t jend = j + 1;

        if (block.w < size.w)
        {
            const bool* occup = occupied.ptr[j].ptr;
            bool wfit;
            for (; iend < cols.length; iend++)
            {
                if (occup[iend])
                    return false;

                block.w += cols.ptr[iend];
                if (block.w >= size.w)
                {
                    wfit = true;
                    break;
                }
            }
            if (!wfit)
                return false;
            iend++;
        }
        if (block.h < size.h)
        {
            bool hfit;
            for (; jend < rows.length; jend++)
            {
                if (occupied.ptr[jend].ptr[i])
                    return false;

                block.h += rows.ptr[jend];
                if (block.h >= size.h)
                {
                    hfit = true;
                    break;
                }
            }
            if (!hfit)
                return false;

            jend++;
            foreach (jj; j + 1 .. jend)
            {
                const bool* occup = occupied.ptr[jj].ptr;
                foreach (ii; i + 1 .. iend)
                {
                    if (occup[ii])
                        return false;
                }
            }
        }
        // fits
        const diffW = block.w - size.w;
        const diffH = block.h - size.h;
        try
        {
            if (diffW >= minTileSize)
            {
                // split the last column
                cols[iend - 1] -= diffW;
                insertInPlace(cols, iend, diffW);
                foreach (ref r; occupied)
                    insertInPlace(r, iend, r[iend - 1]);
            }
            if (diffH >= minTileSize)
            {
                // split the last row
                rows[jend - 1] -= diffH;
                insertInPlace(rows, jend, diffH);
                insertInPlace(minFailed, jend, minFailed[jend - 1]);
                insertInPlace(occupied, jend, occupied[jend - 1].dup);
            }
        }
        catch (Exception)
            assert(0);
        // mark cells
        foreach (jj; j .. jend)
            occupied[jj][i .. iend] = true;
        // calculate position
        foreach (w; cols[0 .. i])
            result.x += w;
        foreach (h; rows[0 .. j])
            result.y += h;

        return true;
    }

    /// Remove a rectangle by `id`, returns true if there was such item
    AtlasResult remove(ID id)
    {
        BoxI box;
        if (auto p = id in added)
            box = *p;
        else
            return AtlasResult.init;

        added.remove(id);
        if (added.length > 0)
        {
            // find affected cells
            const RectI r = box;
            size_t i, iend, j, jend;
            bool started;
            int pos;
            foreach (ii, w; cols)
            {
                if (!started && r.left <= pos)
                {
                    i = ii;
                    started = true;
                }
                if (r.right < pos)
                    break;
                if (started)
                    iend = ii + 1;
                pos += w;
            }
            started = false;
            pos = 0;
            foreach (jj, h; rows)
            {
                if (!started && r.top <= pos)
                {
                    j = jj;
                    started = true;
                }
                if (r.bottom < pos)
                    break;
                if (started)
                    jend = jj + 1;
                pos += h;
            }
            // clear those cells
            foreach (jj; j .. jend)
            {
                occupied[jj][i .. iend] = false;
                minFailed[jj] = _size;
            }
        }
        else
        {
            cols = [_size.w];
            rows = [_size.h];
            occupied = [[false]];
            minFailed = [_size];
        }
        return AtlasResult(box, _size, true);
    }

    /// Remove all rectangles from the atlas and set its size to initial
    void clear()
    {
        _size = _initialSize;
        added.clear();
        cols = [_initialSize.w];
        rows = [_initialSize.h];
        occupied = [[false]];
        minFailed = [_initialSize];
    }
}

struct AtlasList(ubyte MAX_PAGES, SizeI MAX_SIZE, SizeI INITIAL_SIZE, bool onePixelGap)
{
nothrow:
    private Atlas*[MAX_PAGES] pages;
    private ubyte pageCount;

    @disable this(this);

    ~this()
    {
        foreach (ref atlas; pages[0 .. pageCount])
            eliminate(atlas);
    }

    AtlasListResult findOrAdd(ID id, const SizeI* size)
    {
        if (size)
        {
            if (size.w <= 0 || size.h <= 0)
                return AtlasListResult.init;
            if (size.w > MAX_SIZE.w || size.h > MAX_SIZE.h)
                return AtlasListResult.init;
        }
        foreach (i, atlas; pages[0 .. pageCount])
        {
            const res = atlas.findOrAdd(id, size);
            if (!res.error)
                return AtlasListResult(res.box, res.atlasSize, cast(ubyte)i, res.changed);
        }
        if (!size)
            return AtlasListResult.init;

        // no place in existing pages, make new
        if (pageCount < MAX_PAGES)
        {
            const i = pageCount++;
            auto atlas = pages[i] = new Atlas(MAX_SIZE, INITIAL_SIZE, true);
            const res = atlas.add(id, *size);
            if (!res.error)
                return AtlasListResult(res.box, res.atlasSize, i, res.changed);
        }
        // no pages anymore, or something else went wrong
        return AtlasListResult.init;
    }

    void remove(ID id)
    {
        foreach (atlas; pages[0 .. pageCount])
        {
            if (!atlas.remove(id).error)
                break;
        }
    }

    void clear()
    {
        foreach (atlas; pages[0 .. pageCount])
            atlas.clear();
    }
}

struct AtlasResult
{
    BoxI box;
    SizeI atlasSize;
    bool changed;

    bool error() const nothrow
    {
        return box.w == 0 || box.h == 0;
    }
}

struct AtlasListResult
{
    BoxI box;
    SizeI pageSize;
    ubyte index;
    bool changed;

    bool error() const nothrow
    {
        return box.w == 0 || box.h == 0;
    }
}
