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
class TableLayout : WidgetGroup
{
    @property
    {
        /// Number of columns
        int colCount() const { return _colCount; }
        /// ditto
        void colCount(int count)
        {
            if (_colCount != count)
            {
                _colCount = count;
                requestLayout();
            }
        }
        /// Number of rows
        int rowCount() const
        {
            return (childCount + (_colCount - 1)) / _colCount * _colCount;
        }
    }

    private
    {
        Array!LayoutItem _cells;
        Array!LayoutItem _rows;
        Array!LayoutItem _cols;

        int _colCount = 1;
    }

    protected int rowSpace(int gap) const
    {
        int c = rowCount;
        return c > 1 ? gap * (c - 1) : 0;
    }

    protected int colSpace(int gap) const
    {
        int c = colCount;
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

    protected void initialize(int rc, int cc)
    {
        _cells.length = rc * cc;
        _rows.length = rc;
        _cols.length = cc;
        _cells[] = LayoutItem();
        _rows[] = LayoutItem();
        _cols[] = LayoutItem();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        if (ptype == StyleProperty.rowGap || ptype == StyleProperty.columnGap)
            requestLayout();
    }

    override void measure()
    {
        int rc = rowCount;
        int cc = colCount;
        initialize(rc, cc);

        // measure cells
        foreach (int i; 0 .. rc * cc)
        {
            if (i < childCount)
            {
                Widget item = child(i);
                item.measure();
                Boundaries wbs = item.boundaries;
                _cells[i].wt = item;
                _cells[i].bs = wbs;
            }
        }

        static void applyCellToRow(ref LayoutItem row, ref LayoutItem cell)
        {
            row.bs.addWidth(cell.bs);
            row.bs.maximizeHeight(cell.bs);
            row.result.h = row.bs.nat.h;
//             if (cell.wt)
//                 row.fill |= cell.wt.fillsHeight;
        }

        static void applyCellToCol(ref LayoutItem column, ref LayoutItem cell)
        {
            column.bs.maximizeWidth(cell.bs);
            column.bs.addHeight(cell.bs);
            column.result.w = column.bs.nat.w;
//             if (cell.wt)
//                 column.fill |= cell.wt.fillsWidth;
        }

        Boundaries bs;
        // calc total row sizes
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

        const colgap = style.columnGap.applyPercent(bs.nat.w);
        const rowgap = style.columnGap.applyPercent(bs.nat.h);
        const space = Size(colSpace(colgap), rowSpace(rowgap));
        bs.min += space;
        bs.nat += space;
        bs.max += space;
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        const inner = innerBox;

        const colgap = style.columnGap.applyPercent(inner.w);
        const rowgap = style.columnGap.applyPercent(inner.h);
        allocateSpace!`w`(_cols, inner.w - colSpace(colgap));
        allocateSpace!`h`(_rows, inner.h - rowSpace(rowgap));

        int ypen = 0;
        foreach (y; 0 .. rowCount)
        {
            int h = row(y).result.h;
            int xpen = 0;
            foreach (x; 0 .. colCount)
            {
                int w = col(x).result.w;
                Box wb = Box(inner.x + xpen, inner.y + ypen, w, h);

                cell(x, y).wt.maybe.layout(wb);
                xpen += w + colgap;
            }
            ypen += h + rowgap;
        }
    }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        drawAllChildren(buf);
    }
}
