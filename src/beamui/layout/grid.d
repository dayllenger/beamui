/**
A small subset of CSS Grid Layout.

Implemented features:
$(UL
    $(LI template rows/columns)
    $(LI named template areas)
    $(LI track sizes: length, percentage, fr, min-content, max-content, auto)
    $(LI line indices (positive only) and spans)
    $(LI automatic flow)
    $(LI ordering)
    $(LI alignment and stretching)
    $(LI gaps)
)

Features unlikely to be implemented because of their extreme complexity:
$(UL
    $(LI minmax(), repeat(), fit-content() functions)
    $(LI named lines)
    $(LI dense packing)
    $(LI baseline alignment)
    $(LI several CSS shorthands)
)

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.grid;

import std.algorithm.iteration : sum;
import std.algorithm.mutation : SwapStrategy, swap;
import std.algorithm.sorting : sort;
import std.math : isFinite;
import beamui.core.collections : Buf;
import beamui.core.geometry;
import beamui.core.math;
import beamui.core.units : LayoutLength, Length;
import beamui.layout.alignment;
import beamui.style.computed_style : ComputedStyle, StyleProperty;
import beamui.widgets.widget : DependentSize, ILayout, Widget;

enum GridFlow : ubyte
{
    row,
    column,
}

struct GridNamedAreas
{
    SizeI size;
    RectI[string] map; /// Counts from zero (unlike grid lines)
}

struct GridLineName
{
    private bool span;
    private int num;
    private string name;

    nothrow:

    this(bool span, int num)
        in(num > 0)
        in(num < 10_000)
    {
        this.span = span;
        this.num = num;
    }

    this(string name)
    {
        this.name = name;
    }
}

struct TrackSize
{
    private enum Type : ubyte
    {
        common,
        fr,
        minContent,
        maxContent,
    }
    private union
    {
        Length common;
        float fr;
    }
    private Type type;

    nothrow:
    private this(int);

    static TrackSize automatic()
    {
        return TrackSize.init;
    }
    static TrackSize fromLength(Length len)
    {
        TrackSize ts;
        ts.common = len;
        return ts;
    }
    static TrackSize fromFraction(float fr)
        in(fr >= 0)
    {
        TrackSize ts;
        ts.fr = fr;
        ts.type = Type.fr;
        return ts;
    }
    static TrackSize minContent()
    {
        TrackSize ts;
        ts.type = Type.minContent;
        return ts;
    }
    static TrackSize maxContent()
    {
        TrackSize ts;
        ts.type = Type.maxContent;
        return ts;
    }
}

private struct GridItem
{
    Widget wt;
    Insets margins;
    Insets marginsNoAuto;
    BoxI area;
    Boundaries bs;
    AlignItem[2] alignment;

    Segment hseg;
}

private struct TrackBoundaries
{
    float min = 0;
    float nat = 0;
}

private struct Track
{
    enum Sizing : ubyte
    {
        automatic,
        fixed,
        flexible,
        minContent,
        maxContent,
    }
    Sizing sizing;
    LayoutLength size;
    TrackBoundaries bs;
    float factor = 0;

    nothrow:

    this(TrackSize ts)
    {
        if (ts.type == TrackSize.Type.fr)
        {
            if (ts.fr > 0)
            {
                factor = ts.fr;
                sizing = Sizing.flexible;
            }
            else
                sizing = Sizing.minContent;
        }
        else if (ts.type == TrackSize.Type.minContent)
            sizing = Sizing.minContent;
        else if (ts.type == TrackSize.Type.maxContent)
            sizing = Sizing.maxContent;
        else
        {
            size = ts.common.toLayout();
            if (size.isDefined)
            {
                bs.min = bs.nat = size.applyPercent(0);
                sizing = Sizing.fixed;
            }
        }
    }

    void adjustSizes(float min, float nat)
    {
        // this logic is much simpler in the absence of minmax() and other functions
        if (sizing == Sizing.automatic || sizing == Sizing.flexible)
        {
            bs.min = .max(bs.min, min);
            bs.nat = .max(bs.nat, nat);
        }
        else if (sizing == Sizing.minContent)
        {
            bs.min = bs.nat = .max(bs.min, min);
        }
        else if (sizing == Sizing.maxContent)
        {
            bs.min = bs.nat = .max(bs.nat, nat);
        }
    }

    void refreshSizes(float frame)
    {
        if (size.isDefined)
        {
            assert(sizing == Sizing.fixed);
            bs.min = bs.nat = size.applyPercent(frame);
        }
        else
            bs = TrackBoundaries.init;
    }
}

class GridLayout : ILayout
{
    private
    {
        Widget host;

        Buf!GridItem items;
        Buf!Track cols;
        Buf!Track rows;

        SizeI gridSize;

        LayoutLength columnGap, rowGap;
        Distribution[2] contentAlignment;
        AlignItem[2] defaultAlignment = AlignItem.stretch;
    }

    void onSetup(Widget host)
    {
        this.host = host;
    }

    void onDetach()
    {
        host = null;
        items.clear();
        cols.clear();
        rows.clear();
        gridSize = SizeI.init;
    }

    void onStyleChange(StyleProperty p)
    {
        switch (p) with (StyleProperty)
        {
        case justifyContent:
        case justifyItems:
        case alignContent:
        case alignItems:
        case rowGap:
        case columnGap:
        case gridAutoFlow:
        case gridAutoRows:
        case gridAutoColumns:
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
        case justifySelf:
        case alignSelf:
        case order:
        case gridRowStart:
        case gridRowEnd:
        case gridColumnStart:
        case gridColumnEnd:
            host.requestLayout();
            break;
        default:
            break;
        }
    }

    void prepare(ref Buf!Widget list)
    {
        // apply order
        sort!((a, b) => a.style.order < b.style.order, SwapStrategy.stable)(list.unsafe_slice);
        // get grid parameters
        const ComputedStyle* st = host.style;
        const colSizes = st.gridTemplateColumns;
        const rowSizes = st.gridTemplateRows;
        const namedAreas = st.gridTemplateAreas;
        const flow = st.gridAutoFlow;
        const autoColSize = st.gridAutoColumns;
        const autoRowSize = st.gridAutoRows;
        columnGap = host.style.columnGap;
        rowGap = host.style.rowGap;
        contentAlignment = st.placeContent;
        defaultAlignment = st.placeItems;
        // get the explicit grid size
        gridSize.w = max(namedAreas.size.w, cast(int)colSizes.length);
        gridSize.h = max(namedAreas.size.h, cast(int)rowSizes.length);
        // allocate empty grid items
        items.clear();
        items.resize(list.length);
        // find definite areas for all items in the grid
        resolveItemPositions(list.unsafe_slice, namedAreas, flow);
        // sort items by their spans
        sort!((ref a, ref b) => a.area.w + a.area.h < b.area.w + b.area.h)(items.unsafe_slice);
        // allocate tracks
        cols.clear();
        rows.clear();
        cols.reserve(gridSize.w);
        rows.reserve(gridSize.h);
        foreach (ts; colSizes)
            cols ~= Track(ts);
        foreach (ts; rowSizes)
            rows ~= Track(ts);
        foreach (_; colSizes.length .. gridSize.w)
            cols ~= Track(autoColSize);
        foreach (_; rowSizes.length .. gridSize.h)
            rows ~= Track(autoRowSize);
    }

    private void resolveItemPositions(Widget[] widgets, const GridNamedAreas namedAreas, GridFlow flow)
    {
        bool hasIndefinite;
        foreach (i, ref GridItem item; items.unsafe_slice)
        {
            const ComputedStyle* wst = widgets[i].style;
            // unpack item's grid area properties and also get margins
            item.wt = widgets[i];
            item.margins = wst.margins;
            item.marginsNoAuto = ignoreAutoMargin(item.margins);
            const a = processSpecifiedLineNames(namedAreas.map, wst.gridArea);
            item.area = a;
            // contribute to the implicit grid size
            gridSize.w = max(gridSize.w, a.x + a.w, a.w);
            gridSize.h = max(gridSize.h, a.y + a.h, a.h);
            hasIndefinite = hasIndefinite || a.x == INDEF || a.y == INDEF;
        }
        // at this point, some positions may still be indefinite
        if (hasIndefinite)
            gridSize = resolveImplicitPositions(items.unsafe_slice, gridSize, flow);
    }

    Boundaries measure()
    {
        if (items.length == 0)
            return Boundaries.init;

        foreach (i, ref GridItem item; items.unsafe_slice)
        {
            // measure items
            item.wt.measure();
            Boundaries wbs = item.wt.boundaries;
            // add margins
            const msz = item.marginsNoAuto.size;
            wbs.min += msz;
            wbs.nat += msz;
            wbs.max += msz;
            // items are sorted, so small spans will go first
            distributeSizesAcrossColumns(wbs, item.area);
            distributeSizesAcrossRows(wbs, item.area);
        }
        // compute preferred size of the container
        Boundaries bs;
        foreach (ref c; cols.unsafe_slice)
        {
            bs.min.w += c.bs.min;
            bs.nat.w += c.bs.nat;
        }
        foreach (ref r; rows.unsafe_slice)
        {
            bs.min.h += r.bs.min;
            bs.nat.h += r.bs.nat;
        }
        // add gaps
        const cgapMin = columnGap.applyPercent(0);
        const rgapMin = rowGap.applyPercent(0);
        // the correct formula for percentage gaps is `base / (1 - % * (n - 1))`,
        // but it grows to infinity and goes negative on large spacing
        const cgapNat = columnGap.applyPercent(bs.nat.w);
        const rgapNat = rowGap.applyPercent(bs.nat.h);
        bs.min.w += cgapMin * (gridSize.w - 1);
        bs.min.h += rgapMin * (gridSize.h - 1);
        bs.nat.w += cgapNat * (gridSize.w - 1);
        bs.nat.h += rgapNat * (gridSize.h - 1);
        return bs;
    }

    private void distributeSizesAcrossColumns(ref const Boundaries bs, BoxI area)
    {
        if (area.w == 1)
        {
            Track* tr = &cols.unsafe_ref(area.x);
            tr.adjustSizes(bs.min.w, bs.nat.w);
        }
        else
        {
            assert(area.w > 0);
            const min = bs.min.w / area.w;
            const nat = bs.nat.w / area.w;
            foreach (j; area.x .. area.x + area.w)
            {
                Track* tr = &cols.unsafe_ref(j);
                tr.adjustSizes(min, nat);
            }
        }
    }
    private void distributeSizesAcrossRows(ref const Boundaries bs, BoxI area)
    {
        if (area.h == 1)
        {
            Track* tr = &rows.unsafe_ref(area.y);
            tr.adjustSizes(bs.min.h, bs.nat.h);
        }
        else
        {
            assert(area.h > 0);
            const min = bs.min.h / area.h;
            const nat = bs.nat.h / area.h;
            foreach (j; area.y .. area.y + area.h)
            {
                Track* tr = &rows.unsafe_ref(j);
                tr.adjustSizes(min, nat);
            }
        }
    }

    void arrange(Box box)
    {
        if (items.length == 0)
            return;

        // get sizes for fixed tracks, erase sizes from the previous phase
        foreach (ref tr; cols.unsafe_slice)
            tr.refreshSizes(box.w);
        foreach (ref tr; rows.unsafe_slice)
            tr.refreshSizes(box.h);

        const cgap = columnGap.applyPercent(box.w);
        const rgap = rowGap.applyPercent(box.h);
        Box boxNoGaps = box;
        // may become negative, but it's fine
        boxNoGaps.w -= cgap * (gridSize.w - 1);
        boxNoGaps.h -= rgap * (gridSize.h - 1);

        // gather items' style properties and boundaries, resolve percent sizes
        foreach (i, ref GridItem item; items.unsafe_slice)
        {
            const ComputedStyle* st = item.wt.style;
            const alignment = st.placeSelf;
            item.alignment[0] = alignment[0] ? alignment[0] : defaultAlignment[0];
            item.alignment[1] = alignment[1] ? alignment[1] : defaultAlignment[1];

            const minw = st.minWidth;
            const maxw = st.maxWidth;
            const minh = st.minHeight;
            const maxh = st.maxHeight;
            const w = st.width;
            const h = st.height;

            Boundaries bs = item.wt.boundaries;
            if (minw.isPercent)
                bs.min.w = minw.applyPercent(box.w);
            if (maxw.isPercent)
                bs.max.w = min(bs.max.w, maxw.applyPercent(box.w));
            if (minh.isPercent)
                bs.min.h = minw.applyPercent(box.h);
            if (maxh.isPercent)
                bs.max.h = min(bs.max.h, maxh.applyPercent(box.h));
            if (h.isPercent)
                bs.nat.h = h.applyPercent(box.h);

            if (item.wt.dependentSize == DependentSize.width)
            {
                // width depends on height, but we don't know the height yet.
                // estimate it with some heuristics
                float approxHeight;
                if (h.isDefined || bs.nat.h < boxNoGaps.h)
                    approxHeight = bs.nat.h;
                else
                    approxHeight = boxNoGaps.h;
                bs.nat.w = item.wt.widthForHeight(approxHeight);
            }
            else if (w.isPercent)
                bs.nat.w = w.applyPercent(box.w);

            bs.max.w = max(bs.max.w, bs.min.w);
            bs.max.h = max(bs.max.h, bs.min.h);
            bs.nat.w = clamp(bs.nat.w, bs.min.w, bs.max.w);

            const mw = item.marginsNoAuto.width;
            bs.min.w += mw;
            bs.nat.w += mw;
            bs.max.w += mw;
            assert(isFinite(bs.min.w) && isFinite(bs.nat.w));

            item.bs = bs;
            distributeSizesAcrossColumns(bs, item.area);
        }
        // lay out columns first to find exact widths for all items
        arrangeColumns(Segment(boxNoGaps.x, boxNoGaps.w), cgap);

        foreach (i, ref GridItem item; items.unsafe_slice)
        {
            Boundaries* bs = &item.bs;

            if (item.wt.dependentSize == DependentSize.height)
                bs.nat.h = item.wt.heightForWidth(item.hseg.size);

            bs.nat.h = clamp(bs.nat.h, bs.min.h, bs.max.h);

            const mh = item.marginsNoAuto.height;
            bs.min.h += mh;
            bs.nat.h += mh;
            bs.max.h += mh;
            assert(isFinite(bs.min.h) && isFinite(bs.nat.h));

            distributeSizesAcrossRows(*bs, item.area);
        }
        // lay out rows and items themselves
        arrangeRowsAndItems(Segment(boxNoGaps.y, boxNoGaps.h), rgap);
    }

    private void arrangeColumns(Segment space, float gap)
    {
        Buf!float bufPos;
        Buf!float bufSizes;
        bufPos.resize(cols.length);
        bufSizes.resize(cols.length);

        sizeTracks(cols[], bufSizes.unsafe_slice, space.size);
        placeTracks(cols[], bufSizes.unsafe_slice, bufPos.unsafe_slice, gap, space, contentAlignment[0]);

        // arrange items
        foreach (i, ref GridItem item; items.unsafe_slice)
        {
            // use natural size as initial
            const sz = item.bs.nat.w;
            // get the area dimensions
            const BoxI area = item.area;
            Segment areaSeg;
            areaSeg.pos = bufPos[area.x];
            areaSeg.size = bufPos[area.x + area.w - 1] - bufPos[area.x] + bufSizes[area.x + area.w - 1];
            // align or stretch the item, considering auto margins
            alias Auto = SIZE_UNSPECIFIED!float;
            const Insets m = item.margins;
            AlignItem a = item.alignment[0];
            if (sz < areaSeg.size)
            {
                if (m.left is Auto)
                {
                    if (m.right is Auto)
                        a = AlignItem.center;
                    else
                        a = AlignItem.end;
                }
                else if (m.right is Auto)
                    a = AlignItem.start;
            }
            else
                a = AlignItem.stretch;
            assert(a != AlignItem.unspecified);
            const seg = alignItem(Segment(0, sz), areaSeg, a);
            item.hseg = Segment(seg.pos, clamp(seg.size, item.bs.min.w, item.bs.max.w));
        }
    }

    private void arrangeRowsAndItems(Segment space, float gap)
    {
        Buf!float bufPos;
        Buf!float bufSizes;
        bufPos.resize(rows.length);
        bufSizes.resize(rows.length);

        sizeTracks(rows[], bufSizes.unsafe_slice, space.size);
        placeTracks(rows[], bufSizes.unsafe_slice, bufPos.unsafe_slice, gap, space, contentAlignment[1]);

        foreach (i, ref GridItem item; items.unsafe_slice)
        {
            const sz = item.bs.nat.h;

            const BoxI area = item.area;
            Segment areaSeg;
            areaSeg.pos = bufPos[area.y];
            areaSeg.size = bufPos[area.y + area.h - 1] - bufPos[area.y] + bufSizes[area.y + area.h - 1];

            alias Auto = SIZE_UNSPECIFIED!float;
            const Insets m = item.margins;
            AlignItem a = item.alignment[1];
            if (sz < areaSeg.size)
            {
                if (m.top is Auto)
                {
                    if (m.bottom is Auto)
                        a = AlignItem.center;
                    else
                        a = AlignItem.end;
                }
                else if (m.bottom is Auto)
                    a = AlignItem.start;
            }
            else
                a = AlignItem.stretch;
            assert(a != AlignItem.unspecified);
            const vseg = alignItem(Segment(0, sz), areaSeg, a);

            Box b = Box(item.hseg.pos, vseg.pos, item.hseg.size, clamp(vseg.size, item.bs.min.h, item.bs.max.h));
            // subtract margins
            b.shrink(item.marginsNoAuto);
            // lay out the widget
            assert(isFinite(b.x) && isFinite(b.y));
            assert(isFinite(b.w) && isFinite(b.h));
            item.wt.layout(b);
        }
    }
}

private nothrow:

enum INDEF = int.min;

BoxI processSpecifiedLineNames(const RectI[string] namedAreas, const GridLineName[4] area)
{
    GridLineName l = area[1], r = area[3], t = area[0], b = area[2];
    BoxI box = BoxI(INDEF, INDEF, 1, 1);

    // first of all, convert area names to line indices
    const(RectI)* lastRect;
    if (l.name.length)
    {
        lastRect = l.name in namedAreas;
        if (lastRect)
            l.num = lastRect.left + 1;
    }
    if (r.name.length)
    {
        if (r.name !is l.name)
            lastRect = r.name in namedAreas;
        if (lastRect)
            r.num = lastRect.right + 1;
    }
    if (t.name.length)
    {
        if (t.name !is r.name)
            lastRect = t.name in namedAreas;
        if (lastRect)
            t.num = lastRect.top + 1;
    }
    if (b.name.length)
    {
        if (b.name !is t.name)
            lastRect = b.name in namedAreas;
        if (lastRect)
            b.num = lastRect.bottom + 1;
    }
    // set spans, fix double spans
    if (l.span)
        box.w = l.num;
    else if (r.span)
        box.w = r.num;
    if (t.span)
        box.h = t.num;
    else if (b.span)
        box.h = b.num;
    // erase span info
    if (l.span)
        l = GridLineName.init;
    if (r.span)
        r = GridLineName.init;
    if (t.span)
        t = GridLineName.init;
    if (b.span)
        b = GridLineName.init;
    // compute spans from known positions, fix swapped ones
    if (l.num && r.num)
    {
        if (l.num > r.num)
            swap(l.num, r.num);
        box.w = max(r.num - l.num, 1);
    }
    if (t.num && b.num)
    {
        if (t.num > b.num)
            swap(t.num, b.num);
        box.h = max(b.num - t.num, 1);
    }
    // now all the spans are done, calculate some final positions
    if (l.num)
        box.x = l.num - 1;
    else if (r.num)
    {
        box.x = r.num - 1 - box.w;
        // clamp items trying to escape, as there is no support for negative lines yet
        if (box.x < 0)
        {
            box.w += box.x;
            box.x = 0;
        }
    }
    if (t.num)
        box.y = t.num - 1;
    else if (b.num)
    {
        box.y = b.num - 1 - box.h;
        if (box.y < 0)
        {
            box.h += box.y;
            box.y = 0;
        }
    }
    return box;
}

SizeI resolveImplicitPositions(GridItem[] items, SizeI size, GridFlow flow)
{
    // transpose when in column flow to use the common algorithm
    if (flow == GridFlow.column)
    {
        foreach (ref item; items)
        {
            swap(item.area.x, item.area.y);
            swap(item.area.w, item.area.h);
        }
        swap(size.w, size.h);
    }

    // using an additional array for chunks of 2^k cells,
    // the algorithm might be ~3 times faster on grids with thousands of tracks,
    // but on usual grids it's not measurable and can be worse
    bool[][] occupied = new bool[][size.h];
    foreach (ref row; occupied)
        row = new bool[size.w];

    static void fill(bool[][] occupied, const BoxI* a)
    {
        const r = RectI(*a);
        foreach (row; occupied[r.top .. r.bottom])
            row[r.left .. r.right] = true;
    }
    static bool fits(bool[] row, ref int left, int right)
    {
        foreach_reverse (x; left .. right)
        {
            if (row[x])
            {
                left = x + 1;
                return false;
            }
        }
        return true;
    }
    // 1. consider items with definite positions
    foreach (ref item; items)
    {
        BoxI* a = &item.area;
        if (a.x != INDEF && a.y != INDEF)
            fill(occupied, a);
    }
    // 2. compute in-flow positions for items with the other position definite
    foreach (ref item; items)
    {
        BoxI* a = &item.area;
        if (a.x == INDEF && a.y != INDEF)
        {
            int left;
            Loop: while (true)
            {
                const right = min(left + a.w, size.w);
                foreach (row; occupied[a.y .. a.y + a.h])
                {
                    if (!fits(row, left, right))
                        continue Loop;
                }
                break;
            }
            a.x = left;
            if (size.w < a.x + a.w)
            {
                size.w = a.x + a.w;
                foreach (ref row; occupied)
                    row.length = size.w;
            }
            fill(occupied, a);
        }
    }
    // 3. compute the leftover positions
    PointI cursor;
    foreach (ref item; items)
    {
        BoxI* a = &item.area;
        if (a.x != INDEF && a.y == INDEF)
        {
            if (a.x < cursor.x)
                cursor.y++;
            cursor.x = a.x;

            const right = a.x + a.w;
            int bottom = min(cursor.y + a.h, size.h);
            for (; cursor.y < bottom; cursor.y++)
            {
                auto left = a.x;
                if (!fits(occupied[cursor.y], left, right))
                    bottom = min(cursor.y + a.h, size.h);
            }

            a.y = cursor.y;
            if (size.h < a.y + a.h)
            {
                size.h = a.y + a.h;
                foreach (_; occupied.length .. size.h)
                    occupied ~= new bool[size.w];
            }
            fill(occupied, a);
        }
        else if (a.x == INDEF && a.y == INDEF)
        {
            ByY: for (;; cursor.y++)
            {
                const bottom = min(cursor.y + a.h, size.h);
                ByX: for (; cursor.x <= size.w - a.w;)
                {
                    const right = cursor.x + a.w;
                    foreach (row; occupied[cursor.y .. bottom])
                    {
                        if (!fits(row, cursor.x, right))
                            continue ByX;
                    }
                    break ByY;
                }
                cursor.x = 0;
            }

            a.x = cursor.x;
            a.y = cursor.y;
            if (size.h < a.y + a.h)
            {
                size.h = a.y + a.h;
                foreach (_; occupied.length .. size.h)
                    occupied ~= new bool[size.w];
            }
            fill(occupied, a);
        }
    }
    // transpose back, if did
    if (flow == GridFlow.column)
    {
        foreach (ref item; items)
        {
            swap(item.area.x, item.area.y);
            swap(item.area.w, item.area.h);
        }
        swap(size.w, size.h);
    }
    return size;
}

void sizeTracks(const Track[] tracks, float[] sizes, const float available)
    in(tracks.length)
    in(tracks.length == sizes.length)
    in(isFinite(available))
{
    // set the base size from minimum
    float required = 0;
    foreach (i, ref tr; tracks)
        required += (sizes[i] = tr.bs.min);

    enum eps = 0.01;
    if (available < required + eps)
        return;

    // handle the simplest case
    if (tracks.length == 1)
    {
        const tr = &tracks[0];
        if (tr.factor > 0)
        {
            if (tr.factor < 1)
                sizes[0] += tr.factor * (available - required);
            else
                sizes[0] = available;
        }
        else if (tr.sizing == Track.Sizing.automatic)
            sizes[0] = min(available, tr.bs.nat);
        return;
    }

    static struct Item
    {
        uint index;
        float factorOrBase = 0;
        float limit = 0;
        float diff = 0;
    }
    // gather all tracks with `auto` and `fr` sizes in two arrays
    Buf!Item automatic;
    Buf!Item flexible;
    float allFactors = 0;
    foreach (i, ref tr; tracks)
    {
        const min = tr.bs.min;
        const nat = tr.bs.nat;
        if (tr.factor > 0)
        {
            flexible ~= Item(cast(uint)i, tr.factor);
            allFactors += tr.factor;
        }
        else if (tr.sizing == Track.Sizing.automatic && min < nat)
        {
            automatic ~= Item(cast(uint)i, min, nat, nat - min);
            allFactors += 1;
        }
        else
            assert(min == nat);
    }
    if (!automatic.length && !flexible.length)
        return;

    float freeSpace = available - required;
    // if the sum of factors is less than 1, tracks won't fill the whole space.
    // doesn't work with `auto` tracks currently
    allFactors = max(allFactors, 1);
    // sort items so that ones with small capacity will fill up first
    sort!((a, b) => a.diff < b.diff)(automatic.unsafe_slice);
    // expand `auto` tracks from minimal to normal size
    foreach (Item item; automatic[])
    {
        const ratio = 1 / allFactors;
        const size = item.factorOrBase + freeSpace * ratio;
        if (size > item.limit)
        {
            sizes[item.index] = item.limit;
            freeSpace -= item.diff;
            allFactors -= 1;
        }
        else
            sizes[item.index] = size;
    }
    // expand flexible tracks from minimum to infinity
    foreach (Item item; flexible[])
    {
        const ratio = item.factorOrBase / allFactors;
        sizes[item.index] += freeSpace * ratio;
    }
}

void placeTracks(const Track[] tracks, float[] sizes, float[] positions, float gap, Segment space, Distribution mode)
{
    const freeSpace = space.size - sum(sizes);
    // stretch tracks with `auto` sizes only
    if (mode == Distribution.stretch)
    {
        mode = Distribution.start;
        if (freeSpace > 0)
        {
            uint count;
            foreach (ref tr; tracks)
            {
                if (tr.sizing == Track.Sizing.automatic)
                    count++;
            }
            if (count > 0)
            {
                const fraction = freeSpace / count;
                foreach (i, ref tr; tracks)
                {
                    if (tr.sizing == Track.Sizing.automatic)
                        sizes[i] += fraction;
                }
            }
        }
    }
    placeSegments(sizes, positions, space.pos, freeSpace, mode);
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
