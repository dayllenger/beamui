/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.layout.table;

import std.container.array;
import beamui.layout.linear;
import beamui.widgets.widget;

/// Layout children as table with rows and columns
class TableLayout : ILayout
{
    @property
    {
        /// Number of columns
        int colCount() const { return _colCount; }
        /// ditto
        void colCount(int count)
        {
            assert(count > 0);
            if (_colCount != count)
            {
                _colCount = count;
                host.maybe.requestLayout();
            }
        }
        /// Number of rows (computed after layout phase)
        int rowCount() const
        {
            return cast(int)_rows.length;
        }
    }

    private
    {
        int _colCount = 1;

        Widget host;

        Array!LayoutItem _cells;
        Array!LayoutItem _rows;
        Array!LayoutItem _cols;
    }

    protected float rowSpace(float gap) const
    {
        const c = rowCount;
        return c > 1 ? gap * (c - 1) : 0;
    }

    protected float colSpace(float gap) const
    {
        const c = colCount;
        return c > 1 ? gap * (c - 1) : 0;
    }

    protected ref LayoutItem cell(int col, int row)
    {
        return _cells[row * colCount + col];
    }

    protected ref LayoutItem row(int r)
    {
        return _rows[r];
    }

    protected ref LayoutItem col(int c)
    {
        return _cols[c];
    }

    void onSetup(Widget host)
    {
        this.host = host;
    }

    void onDetach()
    {
        host = null;
        _cells.length = 0;
        _rows.length = 0;
        _cols.length = 0;
    }

    void onStyleChange(StyleProperty p)
    {
        if (p == StyleProperty.rowGap || p == StyleProperty.columnGap)
            host.requestLayout();
    }

    void onChildStyleChange(StyleProperty p)
    {
        if (p == StyleProperty.alignment || p == StyleProperty.stretch)
            host.requestLayout();
    }

    void prepare(ref Buf!Widget list)
    {
        const int cc = _colCount;
        const int rc = (list.length + cc - 1) / cc;
        _cells.length = rc * cc;
        _rows.length = rc;
        _cols.length = cc;
        _rows[] = LayoutItem();
        _cols[] = LayoutItem();
        foreach (int i; 0 .. rc * cc)
        {
            if (i < list.length)
                _cells[i] = LayoutItem(list.unsafe_ptr[i]);
            else
                _cells[i] = LayoutItem();
        }
    }

    Boundaries measure()
    {
        // measure cells
        foreach (ref LayoutItem c; _cells)
        {
            if (c.wt)
            {
                c.wt.measure();
                c.bs = c.wt.boundaries;
            }
        }

        static void applyCellToRow(ref LayoutItem row, ref LayoutItem cell)
        {
            row.bs.addWidth(cell.bs);
            row.bs.maximizeHeight(cell.bs);
            row.result.h = row.bs.nat.h;
            if (cell.wt)
            {
                const stretch = cell.wt.style.stretch;
                row.fill |= stretch == Stretch.cross || stretch == Stretch.both;
            }
        }

        static void applyCellToCol(ref LayoutItem column, ref LayoutItem cell)
        {
            column.bs.maximizeWidth(cell.bs);
            column.bs.addHeight(cell.bs);
            column.result.w = column.bs.nat.w;
            if (cell.wt)
            {
                const stretch = cell.wt.style.stretch;
                column.fill |= stretch == Stretch.main || stretch == Stretch.both;
            }
        }

        Boundaries bs;
        // calc total row sizes
        const rc = cast(int)_rows.length;
        const cc = cast(int)_cols.length;
        foreach (y; 0 .. rc)
        {
            foreach (x; 0 .. cc)
            {
                applyCellToRow(row(y), cell(x, y));
            }
            bs.addHeight(row(y).bs);
        }
        // calc total column sizes
        foreach (x; 0 .. cc)
        {
            foreach (y; 0 .. rc)
            {
                applyCellToCol(col(x), cell(x, y));
            }
            bs.addWidth(col(x).bs);
        }

        const colgap = host.style.columnGap.applyPercent(bs.nat.w);
        const rowgap = host.style.rowGap.applyPercent(bs.nat.h);
        const space = Size(colSpace(colgap), rowSpace(rowgap));
        bs.min += space;
        bs.nat += space;
        bs.max += space;
        return bs;
    }

    void arrange(Box box)
    {
        const colgap = host.style.columnGap.applyPercent(box.w);
        const rowgap = host.style.rowGap.applyPercent(box.h);
        allocateSpace!`w`(_cols, box.w - colSpace(colgap));
        allocateSpace!`h`(_rows, box.h - rowSpace(rowgap));

        float ypen = 0;
        foreach (y; 0 .. rowCount)
        {
            const h = row(y).result.h;
            float xpen = 0;
            foreach (x; 0 .. colCount)
            {
                const w = col(x).result.w;
                const wb = Box(box.x + xpen, box.y + ypen, w, h);
                cell(x, y).wt.maybe.layout(wb);
                xpen += w + colgap;
            }
            ypen += h + rowgap;
        }
    }
}
