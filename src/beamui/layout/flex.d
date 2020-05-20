/**
CSS Flexible Box Layout.

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.flex;

import std.algorithm.iteration : sum;
import std.algorithm.mutation : swap, SwapStrategy;
import std.algorithm.sorting : sort;
import std.math : abs, isFinite;

import beamui.core.collections : Buf;
import beamui.core.geometry;
import beamui.core.math;
import beamui.core.units : LayoutLength;
import beamui.layout.alignment;
import beamui.style.computed_style : ComputedStyle, StyleProperty;
import beamui.widgets.widget : DependentSize, Element, ILayout;

enum FlexDirection : ubyte
{
    row,
    rowReverse,
    column,
    columnReverse,
}

enum FlexWrap : ubyte
{
    off,
    on,
    reverse,
}

// I use X axis for the main axis, so I transpose X and Y in column layouts

private struct FlexItem
{
    float grow = 0;
    float shrink = 1;
    float baseSize = 0;
    Boundaries bs;
    AlignItem alignment = AlignItem.unspecified;
}

class FlexLayout : ILayout
{
    private
    {
        Element host;

        Element[] elements;
        Buf!FlexItem items;
        Buf!Insets margins;

        FlexDirection dir;
        FlexWrap wrap;
        LayoutLength columnGap, rowGap;
        Distribution[2] contentAlignment;
        AlignItem defaultAlignment = AlignItem.stretch;
        bool vertical;
        bool multiline;
        bool revX;
        bool revY;
    }

    void onSetup(Element host)
    {
        this.host = host;
    }

    void onDetach()
    {
        host = null;
        elements = null;
        items.clear();
        margins.clear();
    }

    void onStyleChange(StyleProperty p)
    {
        switch (p) with (StyleProperty)
        {
        case justifyContent:
        case alignItems:
        case rowGap:
        case columnGap:
        case flexDirection:
        case flexWrap:
            host.requestLayout();
            break;
        case alignContent:
            if (multiline)
                host.requestLayout();
            break;
        default:
            break;
        }
    }

    void onChildStyleChange(StyleProperty p)
    {
        switch (p) with (StyleProperty)
        {
        case alignSelf:
        case order:
        case flexGrow:
        case flexShrink:
        case flexBasis:
            host.requestLayout();
            break;
        default:
            break;
        }
    }

    void prepare(ref Buf!Element list)
    {
        // apply order
        sort!((a, b) => a.style.order < b.style.order, SwapStrategy.stable)(list.unsafe_slice);
        // allocate empty flex items
        elements = list.unsafe_slice;
        items.resize(list.length);
        margins.resize(list.length);

        // fetch parameters
        const ComputedStyle* st = host.style;
        dir = st.flexDirection;
        wrap = st.flexWrap;
        columnGap = st.columnGap;
        rowGap = st.rowGap;
        contentAlignment = st.placeContent;
        defaultAlignment = st.placeItems[1];
        // content stretching by main axis is not applicable to flexbox
        if (contentAlignment[0] == Distribution.stretch)
            contentAlignment[0] = Distribution.start;
        // prepare some useful statements
        vertical = dir == FlexDirection.column || dir == FlexDirection.columnReverse;
        multiline = wrap != FlexWrap.off;
        revX = dir == FlexDirection.rowReverse || dir == FlexDirection.columnReverse;
        revY = wrap == FlexWrap.reverse;
    }

    Boundaries measure()
    {
        const itemCount = cast(int)items.length;
        if (itemCount == 0)
            return Boundaries.init;

        Boundaries bs;
        foreach (i; 0 .. itemCount)
        {
            // measure items
            Element el = elements[i];
            el.measure();
            Boundaries wbs = el.boundaries;
            // apply margins, store them
            const m = el.style.margins;
            const msz = ignoreAutoMargin(m).size;
            wbs.min += msz;
            wbs.nat += msz;
            wbs.max += msz;
            margins[i] = m;
            // compute container min-nat-max sizes
            if (!vertical)
            {
                bs.addWidth(wbs);
                bs.maximizeHeight(wbs);
            }
            else
            {
                bs.maximizeWidth(wbs);
                bs.addHeight(wbs);
            }
        }
        // add gaps (for main axis only)
        if (!vertical)
        {
            const gapMin = !multiline ? columnGap.applyPercent(0) : 0;
            const gapNat = columnGap.applyPercent(bs.nat.w);
            bs.min.w += gapMin * (itemCount - 1);
            bs.nat.w += gapNat * (itemCount - 1);
        }
        else
        {
            const gapMin = !multiline ? rowGap.applyPercent(0) : 0;
            const gapNat = rowGap.applyPercent(bs.nat.h);
            bs.min.h += gapMin * (itemCount - 1);
            bs.nat.h += gapNat * (itemCount - 1);
        }
        // transpose or swap margins in case of a vertical or reversed layout
        swapMargins(margins.unsafe_slice, vertical, revX, revY);
        return bs;
    }

    void arrange(Box box)
    {
        if (items.length == 0)
            return;

        foreach (i; 0 .. items.length)
        {
            FlexItem item;

            // gather style properties for each item
            Element el = elements[i];
            const ComputedStyle* st = el.style;
            item.grow = st.flexGrow;
            item.shrink = st.flexShrink;
            const alignment = st.placeSelf[1];
            item.alignment = alignment ? alignment : defaultAlignment;
            const minw = st.minWidth;
            const minh = st.minHeight;
            const maxw = st.maxWidth;
            const maxh = st.maxHeight;
            const w = st.width;
            const h = st.height;

            // resolve percent sizes, combine them with boundaries
            Boundaries bs = el.boundaries;
            if (minw.isPercent)
                bs.min.w = minw.applyPercent(box.w);
            if (minh.isPercent)
                bs.min.h = minw.applyPercent(box.h);
            if (maxw.isPercent)
                bs.max.w = min(bs.max.w, maxw.applyPercent(box.w));
            if (maxh.isPercent)
                bs.max.h = min(bs.max.h, maxh.applyPercent(box.h));
            if (w.isPercent)
                bs.nat.w = w.applyPercent(box.w);
            if (h.isPercent)
                bs.nat.h = h.applyPercent(box.h);

            if (vertical)
                transpose(bs);

            // clamp cross sizes right away
            bs.max.h = max(bs.max.h, bs.min.h);
            bs.nat.h = clamp(bs.nat.h, bs.min.h, bs.max.h);

            // consider margins
            const Size msz = ignoreAutoMargin(margins[i]).size;
            // determine outer flex base size
            const basis = st.flexBasis;
            if (!basis.isDefined)
            {
                // use intrinsic aspect ratio; cross size is definite
                if (vertical)
                {
                    if (el.dependentSize == DependentSize.height)
                        bs.nat.w = el.heightForWidth(bs.nat.h);
                }
                else
                {
                    if (el.dependentSize == DependentSize.width)
                        bs.nat.w = el.widthForHeight(bs.nat.h);
                }
            }
            else
                bs.nat.w = st.flexBasis.applyPercent(vertical ? box.h : box.w);
            item.baseSize = bs.nat.w + msz.w;

            bs.max.w = max(bs.max.w, bs.min.w);
            bs.nat.w = clamp(bs.nat.w, bs.min.w, bs.max.w);
            bs.min += msz;
            bs.nat += msz;
            bs.max += msz;
            assert(isFinite(bs.min.w) && isFinite(bs.min.h));
            assert(isFinite(bs.nat.w) && isFinite(bs.nat.h));
            item.bs = bs;
            // from now, `nat.w` is what is called "outer hypothetical main size"

            items[i] = item;
        }

        if (vertical)
            transpose(box);

        const cgap = columnGap.applyPercent(box.w);
        const rgap = rowGap.applyPercent(box.h);
        if (!vertical)
            doLayout(box, cgap, rgap);
        else
            doLayout(box, rgap, cgap);
    }

    private void doLayout(Box box, float mainGap, float crossGap)
    {
        // allocate a buffer for the resulting boxes
        Buf!Box bufBoxes;
        bufBoxes.resize(items.length);
        Box[] boxes = bufBoxes.unsafe_slice;

        // set item cross sizes to their natural sizes
        foreach (i, ref item; items[])
            boxes[i].h = item.bs.nat.h;

        // use simple arrays for main axis positions and sizes
        Buf!float bufPos;
        Buf!float bufSizes;
        bufPos.resize(items.length);
        bufSizes.resize(items.length);

        // wrap lines (if needed to) and compute main axis sizes
        Buf!Line bufLines;
        Buf!float bufLinePos;
        Buf!float bufLineSizes;
        if (multiline)
        {
            wrapLines(items[], bufLines, box.w, mainGap);

            bufLinePos.resize(bufLines.length);
            bufLineSizes.resize(bufLines.length);

            // compute line cross sizes
            foreach (j, line; bufLines[])
            {
                float lsz = 0;
                foreach (ref item; items[][line.start .. line.end])
                {
                    // TODO: consider baseline alignment (9.4.8.1)
                    lsz = max(lsz, item.bs.nat.h);
                }
                bufLineSizes[j] = lsz;
            }

            // arrange lines (may stretch them)
            const freeSpace = box.h - sum(bufLineSizes[]) - crossGap * (cast(int)bufLines.length - 1);
            placeSegments(bufLineSizes.unsafe_slice, bufLinePos.unsafe_slice, box.y, freeSpace, contentAlignment[1]);
            // add gaps between lines
            if (!fzero6(crossGap))
            {
                float offset = 0;
                foreach (ref pos; bufLinePos.unsafe_slice)
                {
                    pos += offset;
                    offset += crossGap;
                }
            }

            // run main sizing algorithm for each line
            foreach (line; bufLines[])
            {
                const lineItems = items[][line.start .. line.end];
                auto lineSizes = bufSizes.unsafe_slice[line.start .. line.end];
                const spacing = mainGap * (cast(int)lineItems.length - 1);
                resolveFlexibleLengths(lineItems, lineSizes, box.w - spacing);
            }
        }
        else // size all items at once
        {
            const spacing = mainGap * (cast(int)items.length - 1);
            resolveFlexibleLengths(items[], bufSizes.unsafe_slice, box.w - spacing);
        }

        // compute item positions by main axis
        if (multiline)
        {
            foreach (line; bufLines[])
            {
                const subSizes = bufSizes[][line.start .. line.end];
                auto subPos = bufPos.unsafe_slice[line.start .. line.end];
                const subMargins = margins[][line.start .. line.end];
                placeMain(subSizes, subPos, subMargins, Segment(box.x, box.w), mainGap, contentAlignment[0]);
            }
        }
        else
            placeMain(bufSizes[], bufPos.unsafe_slice, margins[], Segment(box.x, box.w), mainGap, contentAlignment[0]);

        // pack main axis positions and sizes back
        foreach (i, ref b; boxes)
        {
            b.x = bufPos[i];
            b.w = bufSizes[i];
        }

        // align items by cross axis (may stretch them)
        if (multiline)
        {
            foreach (j; 0 .. bufLines.length)
            {
                const Line line = bufLines[j];
                auto subBoxes = boxes[line.start .. line.end];
                const subItems = items[][line.start .. line.end];
                const subMargins = margins[][line.start .. line.end];
                const seg = Segment(bufLinePos[j], bufLineSizes[j]);
                alignItems(subBoxes, subItems, subMargins, seg);
            }
        }
        else
            alignItems(boxes, items[], margins[], Segment(box.y, box.h));

        // subtract margins
        foreach (i, ref b; boxes)
        {
            b.shrink(ignoreAutoMargin(margins[i]));
        }

        // if vertical, transpose boxes back; if reversed, translate items into backward order
        swapBoxes(boxes, vertical, revX, revY, box);

        // lay out the elements
        foreach (i, b; boxes)
        {
            elements[i].layout(b);
        }
    }
}

private nothrow:

enum eps = 1e-3;

void transpose(ref Boundaries bs)
{
    swap(bs.min.w, bs.min.h);
    swap(bs.nat.w, bs.nat.h);
    swap(bs.max.w, bs.max.h);
}

void transpose(ref Box b)
{
    swap(b.x, b.y);
    swap(b.w, b.h);
}

struct TmpItem
{
    bool frozen;
    float minSize = 0;
    float maxSize = 0;
    float baseSize = 0;
    float hypSize = 0;
    float factor = 0;
    float scaledFactor = 0;
    bool minViolation;
    bool maxViolation;
}

void resolveFlexibleLengths(const FlexItem[] origItems, float[] sizes, const float mainSize)
    in(isFinite(mainSize))
{
    // allocate temporary items
    Buf!TmpItem bufItems;
    bufItems.resize(cast(uint)origItems.length);
    TmpItem[] items = bufItems.unsafe_slice;

    // compute base and hypothetical sizes
    float sum = 0;
    foreach (i, ref flexItem; origItems)
    {
        TmpItem* item = &items[i];
        item.baseSize = flexItem.baseSize;
        item.minSize = flexItem.bs.min.w;
        item.maxSize = flexItem.bs.max.w;
        item.hypSize = flexItem.bs.nat.w;
        sum += item.hypSize;
    }

    // determine the used flex factor
    const bool growing = sum < mainSize;
    foreach (i, ref item; origItems)
        items[i].factor = growing ? item.grow : item.shrink;

    // size inflexible items and set default sizes for others
    foreach (i, ref item; items)
    {
        sizes[i] = item.hypSize;
        if (fzero6(item.factor))
            item.frozen = true;
        else if (growing && item.baseSize > item.hypSize)
            item.frozen = true;
        else if (!growing && item.baseSize < item.hypSize)
            item.frozen = true;
    }

    // main loop
    const initialFreeSpace = calculateFreeSpace(items, sizes, mainSize);
    while (!allFrozen(items))
    {
        float sumOfFactorsUnfrozen = 0;
        foreach (ref item; items)
        {
            if (!item.frozen)
                sumOfFactorsUnfrozen += item.factor;
        }
        float remainingFreeSpace = calculateFreeSpace(items, sizes, mainSize);
        if (sumOfFactorsUnfrozen < 1)
        {
            const space = initialFreeSpace * sumOfFactorsUnfrozen;
            if (space < remainingFreeSpace)
                remainingFreeSpace = space;
        }
        if (!fzero2(remainingFreeSpace))
        {
            if (growing)
                expand(items, sizes, sumOfFactorsUnfrozen, remainingFreeSpace);
            else
                shrink(items, sizes, remainingFreeSpace);
        }
        fixMinMaxViolations(items, sizes);
    }
}

float calculateFreeSpace(const TmpItem[] items, const float[] sizes, const float mainSize)
    out(r; isFinite(r))
{
    float sum = 0;
    foreach (i, ref item; items)
        sum += item.frozen ? sizes[i] : item.baseSize;
    return mainSize - sum;
}

bool allFrozen(const TmpItem[] items)
{
    foreach (ref item; items)
        if (!item.frozen)
            return false;
    return true;
}

void expand(const TmpItem[] items, float[] sizes, const float factors, const float freeSpace)
    in(factors > 0)
{
    foreach (i, ref item; items)
    {
        if (!item.frozen)
        {
            const ratio = item.factor / factors;
            sizes[i] = item.baseSize + ratio * freeSpace;
        }
    }
}

void shrink(TmpItem[] items, float[] sizes, const float freeSpace)
{
    float factors = 0;
    foreach (ref item; items)
    {
        if (!item.frozen)
        {
            item.scaledFactor = item.factor * item.baseSize;
            factors += item.scaledFactor;
        }
    }
    assert(factors > 0);
    foreach (i, ref item; items)
    {
        if (!item.frozen)
        {
            const ratio = item.scaledFactor / factors;
            sizes[i] = item.baseSize - ratio * abs(freeSpace);
        }
    }
}

void fixMinMaxViolations(TmpItem[] items, float[] sizes)
{
    float totalViolation = 0;
    foreach (i, ref item; items)
    {
        if (item.frozen)
            continue;

        float sz = sizes[i];
        if (sz > item.maxSize)
        {
            sz = item.maxSize;
            item.maxViolation = true;
        }
        if (sz < item.minSize)
        {
            sz = item.minSize;
            item.minViolation = true;
        }
        totalViolation += sz - sizes[i];
        sizes[i] = sz;
    }
    if (fzero2(totalViolation))
    {
        foreach (ref item; items)
            item.frozen = true;
    }
    else if (totalViolation > 0)
    {
        foreach (ref item; items)
            if (item.minViolation)
                item.frozen = true;
    }
    else if (totalViolation < 0)
    {
        foreach (ref item; items)
            if (item.maxViolation)
                item.frozen = true;
    }
}

struct Line
{
    uint start;
    uint end;
}

void wrapLines(const FlexItem[] items, ref Buf!Line buf, float mainSize, float mainGap)
    in(items.length > 0)
{
    buf.clear();
    mainSize += eps; // tight boxes may not fit

    const count = cast(uint)items.length;
    uint start, end;
    float sz = 0;
    foreach (i; 0 .. count)
    {
        sz += items[i].bs.nat.w;
        if (sz > mainSize)
        {
            end = start == i ? i + 1 : i;
            buf ~= Line(start, end);
            start = end;
            sz = items[i].bs.nat.w;
        }
        sz += mainGap;
    }
    if (end != count)
        buf ~= Line(end, count);
}

void placeMain(const float[] sizes, float[] positions, const Insets[] margins, Segment room, float gap, Distribution mode)
    in(sizes.length > 0)
    in(sizes.length == positions.length)
    in(sizes.length == margins.length)
{
    const freeSpace = room.size - sum(sizes) - gap * (cast(int)sizes.length - 1);
    const uint autoMargins = countAutoMargins(margins);
    // auto margins will override any distribution strategy
    if (freeSpace > 0 && autoMargins > 0)
    {
        const perMarginSpace = freeSpace / autoMargins;
        float pen = room.pos;
        foreach (i, sz; sizes)
        {
            const Insets m = margins[i];
            if (m.left == SIZE_UNSPECIFIED!float)
                pen += perMarginSpace;

            positions[i] = pen;
            pen += sz;

            if (m.right == SIZE_UNSPECIFIED!float)
                pen += perMarginSpace;
        }
    }
    else
    {
        final switch (mode) with (Distribution)
        {
        case start:
            placeFromStart(sizes, positions, room.pos);
            break;
        case end:
            placeFromStart(sizes, positions, room.pos + freeSpace);
            break;
        case center:
            placeToCenter(sizes, positions, room.pos, freeSpace);
            break;
        case spaceBetween:
            placeWithSpaceBetween(sizes, positions, room.pos, freeSpace);
            break;
        case spaceAround:
            placeWithSpaceAround(sizes, positions, room.pos, freeSpace);
            break;
        case spaceEvenly:
            placeWithSpaceAroundEvenly(sizes, positions, room.pos, freeSpace);
            break;
        case stretch:
            assert(0);
        }
    }
    // add gaps
    if (!fzero6(gap))
    {
        float offset = 0;
        foreach (ref pos; positions)
        {
            pos += offset;
            offset += gap;
        }
    }
}

uint countAutoMargins(const Insets[] margins)
{
    uint count;
    foreach (ref m; margins)
    {
        if (m.left == SIZE_UNSPECIFIED!float)
            count++;
        if (m.right == SIZE_UNSPECIFIED!float)
            count++;
    }
    return count;
}

void alignItems(Box[] boxes, const FlexItem[] items, const Insets[] margins, const Segment room)
{
    foreach (i, ref b; boxes)
    {
        const item = &items[i];
        // consider auto margins by cross axis
        const Insets m = margins[i];
        AlignItem a = item.alignment;
        if (b.h < room.size)
        {
            if (m.top == SIZE_UNSPECIFIED!float)
            {
                if (m.bottom == SIZE_UNSPECIFIED!float)
                    a = AlignItem.center;
                else
                    a = AlignItem.end;
            }
            else if (m.bottom == SIZE_UNSPECIFIED!float)
                a = AlignItem.start;
        }
        assert(a != AlignItem.unspecified);
        const seg = alignItem(Segment(b.y, b.h), room, a);
        b.y = seg.pos;
        b.h = min(seg.size, item.bs.max.h);
    }
}

void swapMargins(Insets[] margins, bool transpose, bool byX, bool byY)
{
    if (transpose)
    {
        foreach (ref m; margins)
        {
            swap(m.left, m.top);
            swap(m.right, m.bottom);
        }
    }
    if (byX && byY)
    {
        foreach (ref m; margins)
        {
            swap(m.left, m.right);
            swap(m.top, m.bottom);
        }
    }
    else if (byX)
    {
        foreach (ref m; margins)
            swap(m.left, m.right);
    }
    else if (byY)
    {
        foreach (ref m; margins)
            swap(m.top, m.bottom);
    }
}

void swapBoxes(Box[] boxes, bool transpose, bool byX, bool byY, Box room)
{
    const r = Rect(room);
    if (byX && byY)
    {
        foreach (ref b; boxes)
        {
            b.x = r.right - (b.x + b.w - r.left);
            b.y = r.bottom - (b.y + b.h - r.top);
        }
    }
    else if (byX)
    {
        foreach (ref b; boxes)
            b.x = r.right - (b.x + b.w - r.left);
    }
    else if (byY)
    {
        foreach (ref b; boxes)
            b.y = r.bottom - (b.y + b.h - r.top);
    }
    if (transpose)
    {
        foreach (ref b; boxes)
        {
            swap(b.x, b.y);
            swap(b.w, b.h);
        }
    }
}
