/**

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.alignment;

nothrow:

import beamui.core.geometry : Box, Insets, Point, Size, isDefinedSize;

/// Box alignment options
enum Align : uint
{
    /// Alignment is not specified
    unspecified = 0,
    /// Horizontally align to the left of box
    left = 1,
    /// Horizontally align to the right of box
    right = 2,
    /// Horizontally align to the center of box
    hcenter = left | right,
    /// Vertically align to the top of box
    top = 4,
    /// Vertically align to the bottom of box
    bottom = 8,
    /// Vertically align to the center of box
    vcenter = top | bottom,
    /// Align to the center of box (hcenter | vcenter)
    center = hcenter | vcenter,
    /// Align to the top left corner of box (left | top)
    topleft = left | top,
}

/// Controls whether widget occupies all available width/height in a linear layout
enum Stretch : ubyte
{
    none,
    /// Applies along main axis, i.e. by width in horizontal layouts and by height in vertical ones
    main,
    /// Applies along secondary axis, i.e. by height in horizontal layouts and by width in vertical ones
    cross,
    both,
}

enum AlignItem : ubyte
{
    unspecified,
    stretch,
    start,
    end,
    center,
    // TODO: baseline
}

enum Distribution : ubyte
{
    stretch,
    start,
    end,
    center,
    spaceBetween,
    spaceAround,
    spaceEvenly,
}

struct Segment
{
    float pos = 0;
    float size = 0;
}

/// Applies alignment to a box for content of size `sz`
Box alignBox(Box room, Size sz, Align a)
{
    Point p = room.pos;
    if ((a & Align.hcenter) == Align.hcenter)
        p.x += (room.w - sz.w) / 2;
    else if (a & Align.right)
        p.x += room.w - sz.w;
    if ((a & Align.vcenter) == Align.vcenter)
        p.y += (room.h - sz.h) / 2;
    else if (a & Align.bottom)
        p.y += room.h - sz.h;
    return Box(p, sz);
}

Insets ignoreAutoMargin(Insets m)
{
    if (!isDefinedSize(m.left))
        m.left = 0;
    if (!isDefinedSize(m.right))
        m.right = 0;
    if (!isDefinedSize(m.top))
        m.top = 0;
    if (!isDefinedSize(m.bottom))
        m.bottom = 0;
    return m;
}

Segment alignItem(Segment item, Segment room, AlignItem a)
{
    final switch (a) with (AlignItem)
    {
    case unspecified:
        return item;
    case stretch:
        return room;
    case start:
        return Segment(room.pos, item.size);
    case end:
        return Segment(room.pos + room.size - item.size, item.size);
    case center:
        return Segment(room.pos + (room.size - item.size) / 2, item.size);
    }
}

void placeSegments(float[] sizes, float[] positions, float initialPos, float freeSpace, Distribution mode)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
{
    final switch (mode) with (Distribution)
    {
    case stretch:
        stretchItems(sizes, freeSpace);
        goto case start;
    case start:
        placeFromStart(sizes, positions, initialPos);
        break;
    case end:
        placeFromStart(sizes, positions, initialPos + freeSpace);
        break;
    case center:
        placeToCenter(sizes, positions, initialPos, freeSpace);
        break;
    case spaceBetween:
        placeWithSpaceBetween(sizes, positions, initialPos, freeSpace);
        break;
    case spaceAround:
        placeWithSpaceAround(sizes, positions, initialPos, freeSpace);
        break;
    case spaceEvenly:
        placeWithSpaceAroundEvenly(sizes, positions, initialPos, freeSpace);
        break;
    }
}

void stretchItems(float[] sizes, const float freeSpace)
    in(sizes.length > 0)
{
    if (freeSpace > 0)
    {
        const perItemSize = freeSpace / sizes.length;
        foreach (ref sz; sizes)
            sz += perItemSize;
    }
}

void placeFromStart(const float[] sizes, float[] positions, const float initialPos)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
{
    float pen = initialPos;
    foreach (i, sz; sizes)
    {
        positions[i] = pen;
        pen += sz;
    }
}

void placeFromEnd(const float[] sizes, float[] positions, const float initialPos)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
{
    float pen = initialPos;
    foreach (i, sz; sizes)
    {
        pen -= sz;
        positions[i] = pen;
    }
}

void placeToCenter(const float[] sizes, float[] positions, const float initialPos, const float freeSpace)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
{
    float pen = initialPos + freeSpace / 2;
    foreach (i, sz; sizes)
    {
        positions[i] = pen;
        pen += sz;
    }
}

void placeWithSpaceBetween(const float[] sizes, float[] positions, const float initialPos, const float freeSpace)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
{
    if (freeSpace <= 0 || sizes.length == 1)
    {
        placeFromStart(sizes, positions, initialPos);
        return;
    }
    const perItemSpace = freeSpace / (cast(int)sizes.length - 1);
    float pen = initialPos + sizes[0];
    positions[0] = initialPos;
    foreach (i; 1 .. sizes.length)
    {
        pen += perItemSpace;
        positions[i] = pen;
        pen += sizes[i];
    }
}

void placeWithSpaceAround(const float[] sizes, float[] positions, const float initialPos, const float freeSpace)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
{
    if (freeSpace <= 0 || sizes.length == 1)
    {
        placeToCenter(sizes, positions, initialPos, freeSpace);
        return;
    }
    const perItemSpace_2 = freeSpace / (sizes.length * 2);
    float pen = initialPos;
    foreach (i, sz; sizes)
    {
        pen += perItemSpace_2;
        positions[i] = pen;
        pen += sz + perItemSpace_2;
    }
}

void placeWithSpaceAroundEvenly(const float[] sizes, float[] positions, const float initialPos, const float freeSpace)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
{
    if (freeSpace <= 0 || sizes.length == 1)
    {
        placeToCenter(sizes, positions, initialPos, freeSpace);
        return;
    }
    const perItemSpace = freeSpace / (sizes.length + 1);
    float pen = initialPos;
    foreach (i, sz; sizes)
    {
        pen += perItemSpace;
        positions[i] = pen;
        pen += sz;
    }
}
