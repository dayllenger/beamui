/**
Grid views on data.

Synopsis:
---
auto grid = new StringGridWidget("GRID1");
grid.showColHeaders = true;
grid.showRowHeaders = true;
grid.resize(30, 50);
grid.fixedCols = 3;
grid.fixedRows = 2;
//grid.rowSelect = true; // testing full row selection
grid.selectCell(4, 6, false);
// create sample grid content
foreach (y; 0 .. grid.rows)
{
    foreach (x; 0 .. grid.cols)
    {
        grid.setCellText(x, y, format("cell(%s, %s)"d, x + 1, y + 1));
    }
    grid.setRowTitle(y, to!dstring(y + 1));
}
foreach (x; 0 .. grid.cols)
{
    int col = x + 1;
    dstring res;
    int n1 = col / 26;
    int n2 = col % 26;
    if (n1)
        res ~= n1 + 'A';
    res ~= n2 + 'A';
    grid.setColTitle(x, res);
}
grid.autoFit();
---

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017-2018, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.grid;

import std.container.rbtree;
import beamui.core.config;
import beamui.core.stdaction;
import beamui.text.simple : drawSimpleText;
import beamui.text.sizetest;
import beamui.widgets.controls;
import beamui.widgets.menu;
import beamui.widgets.scroll;
import beamui.widgets.scrollbar;
import beamui.widgets.widget;

/// Data provider for GridWidget.
interface GridAdapter
{
    /// Number of columns
    @property int cols() const;
    /// Number of rows
    @property int rows() const;
    /// Returns widget to draw cell at (col, row)
    Widget cellWidget(int col, int row);
    /// Returns row header widget, `null` if no header
    Widget rowHeader(int row);
    /// Returns column header widget, `null` if no header
    Widget colHeader(int col);
}

///
class StringGridAdapter : GridAdapter
{
    private
    {
        int _cols;
        int _rows;
        dstring[][] _data;
        dstring[] _rowTitles;
        dstring[] _colTitles;
    }

    @property
    {
        /// Number of columns
        int cols() const { return _cols; }
        /// ditto
        void cols(int v)
        {
            resize(v, _rows);
        }
        /// Number of rows
        int rows() const { return _rows; }
        /// ditto
        void rows(int v)
        {
            resize(_cols, v);
        }
    }

    /// Returns row header title
    dstring rowTitle(int row)
    {
        return _rowTitles[row];
    }
    /// Set row header title
    StringGridAdapter setRowTitle(int row, dstring title)
    {
        _rowTitles[row] = title;
        return this;
    }
    /// Returns row header title
    dstring colTitle(int col)
    {
        return _colTitles[col];
    }
    /// Set col header title
    StringGridAdapter setColTitle(int col, dstring title)
    {
        _colTitles[col] = title;
        return this;
    }
    /// Get cell text
    dstring cellText(int col, int row)
    {
        return _data[row][col];
    }
    /// Set cell text
    StringGridAdapter setCellText(int col, int row, dstring text)
    {
        _data[row][col] = text;
        return this;
    }
    /// Set new size
    void resize(int cols, int rows)
    {
        if (cols == _cols && rows == _rows)
            return;
        _cols = cols;
        _rows = rows;
        _data.length = _rows;
        for (int y = 0; y < _rows; y++)
            _data[y].length = _cols;
        _colTitles.length = _cols;
        _rowTitles.length = _rows;
    }
    /// Returns widget to draw cell at (col, row)
    Widget cellWidget(int col, int row)
    {
        return null;
    }
    /// Returns row header widget, `null` if no header
    Widget rowHeader(int row)
    {
        return null;
    }
    /// Returns column header widget, `null` if no header
    Widget colHeader(int col)
    {
        return null;
    }
}

/// Adapter for custom drawing of some cells in grid widgets
interface CustomGridCellAdapter
{
    /// Returns true for custom drawn cell
    bool isCustomCell(int col, int row) const;
    /// Returns cell size
    Size measureCell(int col, int row) const;
    /// Draw data cell content
    void drawCell(DrawBuf buf, Box b, int col, int row);
}

interface GridModelAdapter
{
    @property int fixedCols() const;
    @property int fixedRows() const;
    @property void fixedCols(int value);
    @property void fixedRows(int value);
}

/// Abstract grid widget
class GridWidgetBase : ScrollAreaBase, GridModelAdapter, ActionOperator
{
    @property
    {
        /// Selected cells when multiselect is enabled
        RedBlackTree!PointI selection() { return _selection; }
        /// Selected column
        int col() const
        {
            return _col - _headerCols;
        }
        /// Selected row
        int row() const
        {
            return _row - _headerRows;
        }
        /// Column count
        int cols() const
        {
            return _cols - _headerCols;
        }
        /// ditto
        void cols(int c)
        {
            resize(c, rows);
        }
        /// Row count
        int rows() const
        {
            return _rows - _headerRows;
        }
        /// ditto
        void rows(int r)
        {
            resize(cols, r);
        }

        /// Column resizing flag; when true, allow resizing of column with mouse
        bool allowColResizing() const { return _allowColResizing; }
        /// ditto
        void allowColResizing(bool flagAllowColResizing)
        {
            _allowColResizing = flagAllowColResizing;
        }

        /// Row header column count
        int headerCols() const { return _headerCols; }
        /// ditto
        void headerCols(int c)
        {
            _headerCols = c;
            invalidate();
        }
        /// Col header row count
        int headerRows() const { return _headerRows; }
        /// ditto
        void headerRows(int r)
        {
            _headerRows = r;
            invalidate();
        }

        /// Fixed (non-scrollable) data column count
        int fixedCols() const
        {
            return _gridModelAdapter is null ? _fixedCols : _gridModelAdapter.fixedCols;
        }
        /// ditto
        void fixedCols(int c)
        {
            if (_gridModelAdapter is null)
                _fixedCols = c;
            else
                _gridModelAdapter.fixedCols = c;
            invalidate();
        }
        /// Fixed (non-scrollable) data row count
        int fixedRows() const
        {
            return _gridModelAdapter is null ? _fixedRows : _gridModelAdapter.fixedCols;
        }
        /// ditto
        void fixedRows(int r)
        {
            if (_gridModelAdapter is null)
                _fixedRows = r;
            else
                _gridModelAdapter.fixedCols = r;
            invalidate();
        }

        /// Count of non-scrollable columns (header + fixed)
        int nonScrollCols() const
        {
            return _headerCols + fixedCols;
        }
        /// Count of non-scrollable rows (header + fixed)
        int nonScrollRows() const
        {
            return _headerRows + fixedRows;
        }

        /// Default column width - for newly added columns
        int defColumnWidth() const { return _defColumnWidth; }
        /// ditto
        void defColumnWidth(int v)
        {
            _defColumnWidth = v;
            _changedSize = true;
        }
        /// Default row height - for newly added rows
        int defRowHeight() const { return _defRowHeight; }
        /// ditto
        void defRowHeight(int v)
        {
            _defRowHeight = v;
            _changedSize = true;
        }

        /// When true, allows multi cell selection
        bool multiSelect() const { return _multiSelect; }
        /// ditto
        void multiSelect(bool flag)
        {
            _multiSelect = flag;
            if (!_multiSelect)
            {
                _selection.clear();
                _selection.insert(PointI(_col - _headerCols, _row - _headerRows));
            }
        }

        /// When true, allows only select the whole row
        bool rowSelect() const { return _rowSelect; }
        /// ditto
        void rowSelect(bool flag)
        {
            _rowSelect = flag;
            if (_rowSelect)
            {
                _selection.clear();
                _selection.insert(PointI(_col - _headerCols, _row - _headerRows));
            }
            invalidate();
        }

        /// Flag to enable column headers
        bool showColHeaders() const { return _showColHeaders; }
        /// ditto
        void showColHeaders(bool show)
        {
            if (_showColHeaders != show)
            {
                _showColHeaders = show;
                foreach (i; 0 .. _headerRows)
                    autoFitRowHeight(i);
                _changedSize = true;
                invalidate();
            }
        }

        /// Flag to enable row headers
        bool showRowHeaders() const { return _showRowHeaders; }
        /// ditto
        void showRowHeaders(bool show)
        {
            if (_showRowHeaders != show)
            {
                _showRowHeaders = show;
                foreach (i; 0 .. _headerCols)
                    autoFitColumnWidth(i);
                _changedSize = true;
                invalidate();
            }
        }

        /// Returns all (fixed + scrollable) cells size in pixels
        Size fullAreaPixels() const
        {
            if (_changedSize)
                caching(this).updateCumulativeSizes();
            int w = _cols ? _colCumulativeWidths[_cols - 1] : 0;
            int h = _rows ? _rowCumulativeHeights[_rows - 1] : 0;
            return Size(w, h);
        }
        /// Non-scrollable area size in pixels
        Size nonScrollAreaPixels() const
        {
            if (_changedSize)
                caching(this).updateCumulativeSizes();
            int nscols = nonScrollCols;
            int nsrows = nonScrollRows;
            int w = nscols ? _colCumulativeWidths[nscols - 1] : 0;
            int h = nsrows ? _rowCumulativeHeights[nsrows - 1] : 0;
            return Size(w, h);
        }
        /// Scrollable area size in pixels
        Size scrollAreaPixels() const
        {
            return fullAreaPixels - nonScrollAreaPixels;
        }

        /// Adapter to override drawing of some particular cells
        CustomGridCellAdapter customCellAdapter() { return _customCellAdapter; }
        /// ditto
        void customCellAdapter(CustomGridCellAdapter adapter)
        {
            _customCellAdapter = adapter;
        }

        /// Adapter to hold grid model data
        GridModelAdapter gridModelAdapter() { return _gridModelAdapter; }
        /// ditto
        void gridModelAdapter(GridModelAdapter adapter)
        {
            _gridModelAdapter = adapter;
        }

        /// Smooth horizontal scroll flag - when true - scrolling by pixels, when false - by cells
        bool smoothHScroll() const { return _smoothHScroll; }
        /// ditto
        void smoothHScroll(bool flagSmoothScroll)
        {
            if (_smoothHScroll != flagSmoothScroll)
            {
                _smoothHScroll = flagSmoothScroll;
                // TODO: snap to grid if necessary
                updateScrollBars();
            }
        }
        /// Smooth vertical scroll flag - when true - scrolling by pixels, when false - by cells
        bool smoothVScroll() const { return _smoothVScroll; }
        /// ditto
        void smoothVScroll(bool flagSmoothScroll)
        {
            if (_smoothVScroll != flagSmoothScroll)
            {
                _smoothVScroll = flagSmoothScroll;
                // TODO: snap to grid if necessary
                updateScrollBars();
            }
        }

        /// Extends scroll area to show full column at left when scrolled to rightmost column
        bool fullColumnOnLeft() const { return _fullColumnOnLeft; }
        /// ditto
        void fullColumnOnLeft(bool newFullColumnOnLeft)
        {
            if (_fullColumnOnLeft != newFullColumnOnLeft)
            {
                _fullColumnOnLeft = newFullColumnOnLeft;
                updateScrollBars();
            }
        }
        /// Extends scroll area to show full row at top when scrolled to end row
        bool fullRowOnTop() const { return _fullColumnOnLeft; }
        /// ditto
        void fullRowOnTop(bool newFullRowOnTop)
        {
            if (_fullRowOnTop != newFullRowOnTop)
            {
                _fullRowOnTop = newFullRowOnTop;
                updateScrollBars();
            }
        }
    }

    /// Callback to handle selection change
    Listener!(void delegate(int col, int row)) onSelectCell;
    /// Callback to handle cell double click or Enter key press
    Listener!(void delegate(int col, int row)) onActivateCell;
    /// Callback for handling of view scroll (top left visible cell change)
    Listener!(void delegate(int col, int row)) onViewScroll;
    /// Callback for handling header cell click
    Listener!(void delegate(int col, int row)) onHeaderCellClick;

    private
    {
        /// Column count (including header columns and fixed columns)
        int _cols;
        /// Row count (including header rows and fixed rows)
        int _rows;

        /// Column widths before expanding and resizing
        Buf!int _colUntouchedWidths;
        /// Column widths
        Buf!int _colWidths;
        /// Total width from the left of the first column to the right of specified column
        Buf!int _colCumulativeWidths;
        /// Row heights before expanding and resizing
        Buf!int _rowUntouchedHeights;
        /// Row heights
        Buf!int _rowHeights;
        /// Total height from the top of the first row to the bottom of specified row
        Buf!int _rowCumulativeHeights;

        /// When true, shows col headers row
        bool _showColHeaders;
        /// When true, shows row headers column
        bool _showRowHeaders;
        /// Number of header rows (e.g. like col name A, B, C... in excel; 0 for no header row)
        int _headerRows;
        /// Number of header columns (e.g. like row number in excel; 0 for no header column)
        int _headerCols;
        /// Number of fixed (non-scrollable) columns
        int _fixedCols;
        /// Number of fixed (non-scrollable) rows
        int _fixedRows;

        /// Selected cells when multiselect is enabled
        RedBlackTree!PointI _selection;
        /// Selected cell column
        int _col;
        /// Selected cell row
        int _row;
        /// When true, allows multi cell selection
        bool _multiSelect;
        /// When true, allows to select only whole row
        bool _rowSelect;
        /// Default column width - for newly added columns
        int _defColumnWidth;
        /// Default row height - for newly added rows
        int _defRowHeight;

        CustomGridCellAdapter _customCellAdapter;
        GridModelAdapter _gridModelAdapter;

        bool _smoothHScroll = true;
        bool _smoothVScroll = true;

        bool _allowColResizing = true;

        Color _selectionColor = Color(0x4040FF, 0x80);
        Color _selectionColorRowSelect = Color(0xA0B0FF, 0x40);
        Color _fixedCellBackgroundColor = Color(0xE0E0E0, 0x40);
        Color _fixedCellBorderColor = Color(0xC0C0C0, 0x40);
        Color _cellBorderColor = Color(0xC0C0C0, 0x40);
        Color _cellHeaderBorderColor = Color(0x202020, 0x40);
        Color _cellHeaderBackgroundColor = Color(0x909090, 0x40);
        Color _cellHeaderSelectedBackgroundColor = Color(0xFFC040, 0x80);
        DrawableRef _cellHeaderBackgroundDrawable;
        DrawableRef _cellHeaderSelectedBackgroundDrawable;
        DrawableRef _cellRowHeaderBackgroundDrawable;
        DrawableRef _cellRowHeaderSelectedBackgroundDrawable;

        bool _fullColumnOnLeft = true;
        bool _fullRowOnTop = true;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        _headerCols = 1;
        _headerRows = 1;
        _selection = new RedBlackTree!PointI;
        _defRowHeight = BACKEND_CONSOLE ? 1 : 20;
        _defColumnWidth = BACKEND_CONSOLE ? 7 : 100;

        _showColHeaders = true;
        _showRowHeaders = true;
        allowsFocus = true;
        resize(1, 1);

        bindActions();
    }

    ~this()
    {
        unbindActions();
        _cellHeaderBackgroundDrawable.clear();
        _cellHeaderSelectedBackgroundDrawable.clear();
        _cellRowHeaderBackgroundDrawable.clear();
        _cellRowHeaderSelectedBackgroundDrawable.clear();
    }

    private bool _changedSize = true;
    /// Recalculate `_colCumulativeWidths`, `_rowCumulativeHeights` after resizes
    protected void updateCumulativeSizes()
    {
        if (!_changedSize)
            return;
        _changedSize = false;
        _colCumulativeWidths.resize(_colWidths.length);
        _rowCumulativeHeights.resize(_rowHeights.length);
        int accum;
        foreach (i; 0 .. _colWidths.length)
        {
            accum += _colWidths[i];
            _colCumulativeWidths[i] = accum;
        }
        accum = 0;
        foreach (i; 0 .. _rowHeights.length)
        {
            accum += _rowHeights[i];
            _rowCumulativeHeights[i] = accum;
        }
    }

    /// Set number of columns and rows in the grid
    void resize(int c, int r)
    {
        if (c == cols && r == rows)
            return;
        _changedSize = true;
        _colWidths.resize(c + _headerCols);
        _colUntouchedWidths.resize(c + _headerCols);
        for (int i = _cols; i < c + _headerCols; i++)
        {
            _colWidths[i] = _defColumnWidth;
            _colUntouchedWidths[i] = _defColumnWidth;
        }

        _rowHeights.resize(r + _headerRows);
        _rowUntouchedHeights.resize(r + _headerRows);
        for (int i = _rows; i < r + _headerRows; i++)
        {
            _rowHeights[i] = _defRowHeight;
            _rowUntouchedHeights[i] = _defRowHeight;
        }
        _cols = c + _headerCols;
        _rows = r + _headerRows;
        updateCumulativeSizes();
    }

    /// Returns true if column is inside client area and not overlapped outside scroll area
    bool colVisible(int i) const
    {
        if (i < 0 || _cols <= i)
            return false;
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        if (i == 0)
            return true;
        int nscols = nonScrollCols;
        if (i < nscols)
        {
            // non-scrollable
            return _colCumulativeWidths[i - 1] < clientBox.width;
        }
        else
        {
            // scrollable
            int start = _colCumulativeWidths[i - 1] - scrollPos.x;
            int end = _colCumulativeWidths[i] - scrollPos.x;
            if (start >= clientBox.width)
                return false; // at right
            if (end <= (nscols ? _colCumulativeWidths[nscols - 1] : 0))
                return false; // at left
            return true; // visible
        }
    }
    /// Returns true if row is inside client area and not overlapped outside scroll area
    bool rowVisible(int j) const
    {
        if (j < 0 || _rows <= j)
            return false;
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        if (j == 0)
            return true; // first row always visible
        int nsrows = nonScrollRows;
        if (j < nsrows)
        {
            // non-scrollable
            return _rowCumulativeHeights[j - 1] < clientBox.height;
        }
        else
        {
            // scrollable
            int start = _rowCumulativeHeights[j - 1] - scrollPos.y;
            int end = _rowCumulativeHeights[j] - scrollPos.y;
            if (start >= clientBox.height)
                return false; // at right
            if (end <= (nsrows ? _rowCumulativeHeights[nsrows - 1] : 0))
                return false; // at left
            return true; // visible
        }
    }

    /// Get cell rectangle (relative to client area) not counting scroll position
    Box cellBoxNoScroll(int i, int j) const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        if (i < 0 || _cols <= i || j < 0 || _rows <= j)
            return Box(0, 0, 0, 0);
        return Box(i ? _colCumulativeWidths[i - 1] : 0, j ? _rowCumulativeHeights[j - 1] : 0,
                _colWidths[i], _rowHeights[j]);
    }
    /// Get cell rectangle relative to client area; row 0 is col headers row; col 0 is row headers column
    Box cellBox(int i, int j) const
    {
        Box b = cellBoxNoScroll(i, j);
        int nscols = nonScrollCols;
        int nsrows = nonScrollRows;
        if (i >= nscols)
            b.x -= scrollPos.x;
        if (j >= nsrows)
            b.y -= scrollPos.y;
        return b;
    }

    void setColWidth(int i, int w)
    {
        _colWidths[i] = w;
        _changedSize = true;
    }

    void setRowHeight(int j, int h)
    {
        _rowHeights[j] = h;
        _changedSize = true;
    }

    /// Get column width, 0 is header column
    int colWidth(int i) const
    {
        if (i < 0 || _colWidths.length <= i)
            return 0;
        return _colWidths[i];
    }

    /// Get row height, 0 is header row
    int rowHeight(int j) const
    {
        if (j < 0 || _rowHeights.length <= j)
            return 0;
        return _rowHeights[j];
    }

    /// Converts client rect relative coordinates to cell coordinates
    bool pointToCell(int x, int y, ref int col, ref int row, ref Box cellb) const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        int nscols = nonScrollCols;
        int nsrows = nonScrollRows;
        Size ns = nonScrollAreaPixels;
        col = colByAbsoluteX(x < ns.w ? x : x + scrollPos.x);
        row = rowByAbsoluteY(y < ns.h ? y : y + scrollPos.y);
        cellb = cellBox(col, row);
        return cellb.contains(x, y);
    }

    override protected void updateScrollBars()
    {
        if (_changedSize)
            updateCumulativeSizes();
        super.updateScrollBars();
    }

    /// Search for index of position inside cumulative sizes array
    protected static int findPosIndex(const(int[]) cumulativeSizes, int pos)
    {
        // binary search
        if (pos < 0 || !cumulativeSizes.length)
            return 0;
        int a = 0; // inclusive lower bound
        int b = cast(int)cumulativeSizes.length; // exclusive upper bound
        if (pos >= cumulativeSizes[$ - 1])
            return b - 1;
        const w = cumulativeSizes.ptr;
        while (true)
        {
            if (a + 1 >= b)
                return a; // single point
            // middle point
            // always inside range
            int c = (a + b) >> 1;
            int start = c ? w[c - 1] : 0;
            int end = w[c];
            if (pos < start)
            {
                // left
                b = c;
            }
            else if (pos >= end)
            {
                // right
                a = c + 1;
            }
            else
            {
                // found
                return c;
            }
        }
    }

    /// Column by X, ignoring scroll position
    protected int colByAbsoluteX(int x) const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        return findPosIndex(_colCumulativeWidths[], x);
    }

    /// Row by Y, ignoring scroll position
    protected int rowByAbsoluteY(int y) const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        return findPosIndex(_rowCumulativeHeights[], y);
    }

    /// Returns first fully visible column in scroll area
    protected int scrollCol() const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        int x = nonScrollAreaPixels.w + scrollPos.x;
        int col = colByAbsoluteX(x);
        int start = col ? _colCumulativeWidths[col - 1] : 0;
        int end = _colCumulativeWidths[col];
        if (x <= start)
            return col;
        // align to next col
        return colByAbsoluteX(end);
    }

    /// Returns last fully visible column in scroll area
    protected int lastScrollCol() const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        int x = scrollPos.x + clientBox.w - 1;
        int col = colByAbsoluteX(x);
        int start = col ? _colCumulativeWidths[col - 1] : 0;
        int end = _colCumulativeWidths[col];
        // not fully visible
        if (x < end - 1 && col > nonScrollCols && col > scrollCol)
            col--;
        return col;
    }

    /// Returns first fully visible row in scroll area
    protected int scrollRow() const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        int y = nonScrollAreaPixels.h + scrollPos.y;
        int row = rowByAbsoluteY(y);
        int start = row ? _rowCumulativeHeights[row - 1] : 0;
        int end = _rowCumulativeHeights[row];
        if (y <= start)
            return row;
        // align to next col
        return rowByAbsoluteY(end);
    }

    /// Returns last fully visible row in scroll area
    protected int lastScrollRow() const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        int y = scrollPos.y + clientBox.h - 1;
        int row = rowByAbsoluteY(y);
        int start = row ? _rowCumulativeHeights[row - 1] : 0;
        int end = _rowCumulativeHeights[row];
        // not fully visible
        if (y < end - 1 && row > nonScrollRows && row > scrollRow)
            row--;
        return row;
    }

    /// Move scroll position horizontally by `dx`, and vertically by `dy`; returns true if scrolled
    bool scrollBy(int dx, int dy)
    {
        if (_changedSize)
            updateCumulativeSizes();
        int col = clamp(scrollCol + dx, nonScrollCols, _cols - 1);
        int row = clamp(scrollRow + dy, nonScrollRows, _rows - 1);
        Box b = cellBoxNoScroll(col, row);
        Size ns = nonScrollAreaPixels;
        return scrollTo(b.x - ns.w, b.y - ns.h);
    }

    override protected void correctScrollPos()
    {
        Size csz = fullContentSize;
        Size extra;
        // extending scroll area if necessary
        if (_fullRowOnTop || _fullColumnOnLeft)
        {
            Size nonscrollPixels = nonScrollAreaPixels;
            int maxscrollx = clientBox.x + csz.w - clientBox.w;
            int maxscrolly = clientBox.y + csz.h - clientBox.h;
            int col = colByAbsoluteX(maxscrollx);
            int row = rowByAbsoluteY(maxscrolly);
            Box b = cellBoxNoScroll(col, row);

            // extend scroll area to show full column at left when scrolled to rightmost column
            if (_fullColumnOnLeft && maxscrollx >= nonscrollPixels.w && b.x < maxscrollx)
                extra.w = b.x + b.w - maxscrollx;

            // extend scroll area to show full row at top when scrolled to end row
            if (_fullRowOnTop && maxscrolly >= nonscrollPixels.h && b.y < maxscrolly)
                extra.h = b.y + b.h - maxscrolly;
        }

        scrollPos.x = min(scrollPos.x, max(0, csz.w + extra.w - clientBox.w));
        scrollPos.y = min(scrollPos.y, max(0, csz.h + extra.h - clientBox.h));
    }

    /// Set scroll position to show specified cell as top left in scrollable area. Returns true if scrolled
    bool scrollTo(int x, int y)
    {
        if (_changedSize)
            updateCumulativeSizes();
        const oldpos = scrollPos;
        const newpos = Point(x, y);
        const bool changed = oldpos != newpos;
        if (changed)
        {
            scrollPos = newpos;
            updateScrollBars();
            invalidate();
            if (onViewScroll.assigned)
                onViewScroll(x, y);
        }
        return changed;
    }

    override protected void handleHScroll(ScrollEvent event)
    {
        event.discard();
        // scroll w/o changing selection
        if (event.action == ScrollAction.moved || event.action == ScrollAction.released)
        {
            scrollTo(event.position, scrollPos.y);
        }
        else if (event.action == ScrollAction.pageUp)
        {
            scrollBy(scrollCol - lastScrollCol, 0);
        }
        else if (event.action == ScrollAction.pageDown)
        {
            scrollBy(lastScrollCol - scrollCol, 0);
        }
        else if (event.action == ScrollAction.lineUp)
        {
            scrollBy(-1, 0);
        }
        else if (event.action == ScrollAction.lineDown)
        {
            scrollBy(1, 0);
        }
    }

    override protected void handleVScroll(ScrollEvent event)
    {
        event.discard();
        // scroll w/o changing selection
        if (event.action == ScrollAction.moved || event.action == ScrollAction.released)
        {
            scrollTo(scrollPos.x, event.position);
        }
        else if (event.action == ScrollAction.pageUp)
        {
            scrollBy(0, scrollRow - lastScrollRow);
        }
        else if (event.action == ScrollAction.pageDown)
        {
            scrollBy(0, lastScrollRow - scrollRow);
        }
        else if (event.action == ScrollAction.lineUp)
        {
            scrollBy(0, -1);
        }
        else if (event.action == ScrollAction.lineDown)
        {
            if (lastScrollRow < _rows - 1)
                scrollBy(0, 1);
        }
    }

    /// Ensure that cell is visible (scroll if necessary)
    void makeCellVisible(int i, int j)
    {
        if (_changedSize)
            updateCumulativeSizes();
        bool scrolled;
        Point newpos = scrollPos;
        Rect rc = Rect(cellBoxNoScroll(i, j));
        Size skip = nonScrollAreaPixels;
        Rect visibleRc = Rect(scrollPos.x + skip.w, scrollPos.y + skip.h,
                              scrollPos.x + clientBox.w, scrollPos.y + clientBox.h);

        if (i >= nonScrollCols) // can scroll X
        {
            int ldiff = visibleRc.left - rc.left; // TODO: consider text direction?
            if (ldiff > 0)
            {
                // scroll left
                newpos.x -= ldiff;
            }
            else if (rc.right > visibleRc.right)
            {
                // scroll right
                // if cell bigger than viewport, scroll to cell left border
                newpos.x += min(-ldiff, rc.right - visibleRc.right);
            }
        }
        if (j >= nonScrollRows) // can scroll Y
        {
            int tdiff = visibleRc.top - rc.top;
            if (tdiff > 0)
            {
                // scroll up
                newpos.y -= tdiff;
            }
            else if (rc.bottom > visibleRc.bottom)
            {
                // scroll down
                newpos.y += min(-tdiff, rc.bottom - visibleRc.bottom);
            }
        }
        newpos.x = max(newpos.x, 0);
        newpos.y = max(newpos.y, 0);
        if (newpos != scrollPos)
        {
            scrollTo(newpos.x, newpos.y);
        }
    }

    private PointI _lastSelectedCell;

    bool multiSelectCell(int i, int j, bool expandExisting = false)
    {
        if (_col == i && _row == j && !expandExisting)
            return false; // same position
        if (i < _headerCols || _cols <= i || j < _headerRows || _rows <= j)
            return false; // out of range
        if (_changedSize)
            updateCumulativeSizes();
        _lastSelectedCell.x = i;
        _lastSelectedCell.y = j;
        if (_rowSelect)
            i = _headerCols;
        if (expandExisting)
        {
            _selection.clear();
            int startX = _col - _headerCols;
            int startY = _row - headerRows;
            int endX = i - _headerCols;
            int endY = j - headerRows;
            if (_rowSelect)
                startX = 0;
            if (startX > endX)
            {
                startX = endX;
                endX = _col - _headerCols;
            }
            if (startY > endY)
            {
                startY = endY;
                endY = _row - _headerRows;
            }
            for (int x = startX; x <= endX; ++x)
            {
                for (int y = startY; y <= endY; ++y)
                {
                    _selection.insert(PointI(x, y));
                }
            }
        }
        else
        {
            _selection.insert(PointI(col - _headerCols, row - _headerRows));
            _col = col;
            _row = row;
        }
        invalidate();
        makeCellVisible(_lastSelectedCell.x, _lastSelectedCell.y);
        return true;
    }

    /// Move selection to specified cell
    bool selectCell(int i, int j, bool makeVisible = true)
    {
        _selection.clear();
        if (_col == i && _row == j)
            return false; // same position
        if (i < _headerCols || _cols <= i || j < _headerRows || _rows <= j)
            return false; // out of range
        if (_changedSize)
            updateCumulativeSizes();
        _col = i;
        _row = j;
        _lastSelectedCell = PointI(i, j);
        if (_rowSelect)
        {
            _selection.insert(PointI(0, j - _headerRows));
        }
        else
        {
            _selection.insert(PointI(i - _headerCols, j - _headerRows));
        }
        invalidate();
        if (makeVisible)
            makeCellVisible(_col, _row);
        if (onSelectCell.assigned)
            onSelectCell(_col - _headerCols, _row - _headerRows);
        return true;
    }

    /// Select cell and call `onCellActivated` handler
    bool activateCell(int i, int j)
    {
        if (_changedSize)
            updateCumulativeSizes();
        if (_col != i || _row != j)
        {
            selectCell(i, j, true);
        }
        onActivateCell(this.col, this.row);
        return true;
    }

    /// Cell popup menu
    Signal!(Menu delegate(int col, int row)) cellPopupMenuBuilder;

    protected Menu getCellPopupMenu(int col, int row)
    {
        return cellPopupMenuBuilder.assigned ? cellPopupMenuBuilder(col, row) : null;
    }

    /// Returns true if widget can show popup menu (e.g. by mouse right click at point x,y)
    override bool canShowPopupMenu(int x, int y)
    {
        int col, row;
        Box b;
        x -= clientBox.x;
        y -= clientBox.y;
        pointToCell(x, y, col, row, b);
        Menu menu = getCellPopupMenu(col - _headerCols, row - _headerRows);
        bool result = menu !is null; // FIXME
        destroy(menu);
        return result;
    }

    override void showPopupMenu(int x, int y)
    {
        int col, row;
        Box b;
        int xx = x - clientBox.x;
        int yy = y - clientBox.y;
        pointToCell(xx, yy, col, row, b);
        if (auto menu = getCellPopupMenu(col - _headerCols, row - _headerRows))
        {
            import beamui.widgets.popup;

            auto popup = window.showPopup(menu, WeakRef!Widget(this), PopupAlign.point | PopupAlign.right, x, y);
            popup.ownContent = false;
        }
    }

    override CursorType getCursorType(int x, int y) const
    {
        if (_allowColResizing)
        {
            if (_colResizingIndex >= 0) // resizing in progress
                return CursorType.sizeWE;
            int col = isColumnResizingPoint(x, y);
            if (col >= 0)
                return CursorType.sizeWE;
        }
        return CursorType.arrow;
    }

    private int _colResizingIndex = -1;
    private int _colResizingStartX = -1;
    private int _colResizingStartWidth = -1;

    protected void startColResize(int i, int x)
    {
        _colResizingIndex = i;
        _colResizingStartX = x;
        _colResizingStartWidth = _colWidths[i];
    }

    protected void processColResize(int x)
    {
        if (_colResizingIndex < 0 || _cols <= _colResizingIndex)
            return;
        int newWidth = max(_colResizingStartWidth + x - _colResizingStartX, 0);
        _colWidths[_colResizingIndex] = newWidth;
        _changedSize = true;
        updateScrollBars();
        invalidate();
    }

    protected void endColResize()
    {
        _colResizingIndex = -1;
    }

    /// Returns column index to resize if point is in column resize area in header row, -1 if outside resize area
    int isColumnResizingPoint(int x, int y) const
    {
        if (_changedSize)
            caching(this).updateCumulativeSizes();
        x -= clientBox.x;
        y -= clientBox.y;
        if (!_headerRows)
            return -1; // no header rows
        if (y >= _rowCumulativeHeights[_headerRows - 1])
            return -1; // not in header row
        // point is somewhere in header row
        int resizeRange = BACKEND_GUI ? 5 : 1;
        if (x >= nonScrollAreaPixels.w)
            x += scrollPos.x;
        int col = colByAbsoluteX(x);
        int start = col > 0 ? _colCumulativeWidths[col - 1] : 0;
        int end = (col < _cols ? _colCumulativeWidths[col] : _colCumulativeWidths[$ - 1]) - 1;
        if (x >= end - resizeRange / 2)
            return col; // resize this column
        if (x <= start + resizeRange / 2)
            return col - 1; // resize previous column
        return -1;
    }

    //===============================================================
    // Actions

    protected void bindActions()
    {
        debug (editors)
            Log.d("Grid `", id, "`: bind actions");

        ACTION_LINE_BEGIN.bind(this, &lineBegin);
        ACTION_LINE_END.bind(this, &lineEnd);
        ACTION_PAGE_UP.bind(this, &pageUp);
        ACTION_PAGE_DOWN.bind(this, &pageDown);
        ACTION_PAGE_BEGIN.bind(this, &pageBegin);
        ACTION_PAGE_END.bind(this, &pageEnd);
        ACTION_DOCUMENT_BEGIN.bind(this, &documentBegin);
        ACTION_DOCUMENT_END.bind(this, &documentEnd);

        ACTION_SELECT_LINE_BEGIN.bind(this, &selectLineBegin);
        ACTION_SELECT_LINE_END.bind(this, &selectLineEnd);
        ACTION_SELECT_PAGE_UP.bind(this, &selectPageUp);
        ACTION_SELECT_PAGE_DOWN.bind(this, &selectPageDown);
        ACTION_SELECT_PAGE_BEGIN.bind(this, &selectPageBegin);
        ACTION_SELECT_PAGE_END.bind(this, &selectPageEnd);
        ACTION_SELECT_DOCUMENT_BEGIN.bind(this, &selectDocumentBegin);
        ACTION_SELECT_DOCUMENT_END.bind(this, &selectDocumentEnd);

        ACTION_ENTER.bind(this, { onActivateCell(col, row); });
        ACTION_SELECT_ALL.bind(this, &selectAll);
    }

    protected void unbindActions()
    {
        bunch(
            ACTION_LINE_BEGIN,
            ACTION_LINE_END,
            ACTION_PAGE_UP,
            ACTION_PAGE_DOWN,
            ACTION_PAGE_BEGIN,
            ACTION_PAGE_END,
            ACTION_DOCUMENT_BEGIN,
            ACTION_DOCUMENT_END,
            ACTION_SELECT_LINE_BEGIN,
            ACTION_SELECT_LINE_END,
            ACTION_SELECT_PAGE_UP,
            ACTION_SELECT_PAGE_DOWN,
            ACTION_SELECT_PAGE_BEGIN,
            ACTION_SELECT_PAGE_END,
            ACTION_SELECT_DOCUMENT_BEGIN,
            ACTION_SELECT_DOCUMENT_END,
            ACTION_ENTER,
            ACTION_SELECT_ALL
        ).unbind(this);
    }

    /// Move cursor to the beginning of line
    private void lineBegin()
    {
        if (_rowSelect)
        {
            documentBegin();
            return;
        }
        int sc = scrollCol; // first fully visible column in scroll area
        if (sc > nonScrollCols && _col > sc)
        {
            // move selection and don's scroll
            selectCell(sc, _row);
        }
        else
        {
            // scroll
            if (sc > nonScrollCols)
            {
                scrollPos.x = 0;
                updateScrollBars();
                invalidate();
            }
            selectCell(_headerCols, _row);
        }
    }
    /// Move cursor to the end of line
    private void lineEnd()
    {
        if (_rowSelect)
        {
            documentEnd();
            return;
        }
        if (_col < lastScrollCol)
        {
            // move selection and don's scroll
            selectCell(lastScrollCol, _row);
        }
        else
        {
            selectCell(_cols - 1, _row);
        }
    }
    /// Move cursor one page up
    private void pageUp()
    {
        int sr = scrollRow; // first fully visible row in scroll area
        if (_row > sr)
        {
            // not at top scrollable cell
            selectCell(_col, sr);
        }
        else
        {
            // at top of scrollable area
            if (scrollRow > nonScrollRows)
            {
                // scroll up line by line
                int prevRow = _row;
                for (int i = prevRow - 1; i >= _headerRows; i--)
                {
                    selectCell(_col, i);
                    if (lastScrollRow <= prevRow)
                        break;
                }
            }
            else
            {
                // scrolled to top - move upper cell
                selectCell(_col, _headerRows);
            }
        }
    }
    /// Move cursor one page down
    private void pageDown()
    {
        if (_row < _rows - 1)
        {
            int lr = lastScrollRow;
            if (_row < lr)
            {
                // not at bottom scrollable cell
                selectCell(_col, lr);
            }
            else
            {
                // scroll down
                int prevRow = _row;
                for (int i = prevRow + 1; i < _rows; i++)
                {
                    selectCell(_col, i);
                    if (scrollRow >= prevRow)
                        break;
                }
            }
        }
    }
    /// Move cursor to the beginning of page
    private void pageBegin()
    {
        if (scrollRow > nonScrollRows)
            selectCell(_col, scrollRow);
        else
            selectCell(_col, _headerRows);
    }
    /// Move cursor to the end of page
    private void pageEnd()
    {
        selectCell(_col, lastScrollRow);
    }
    /// Move cursor to the beginning of document
    private void documentBegin()
    {
        if (scrollPos.y > 0)
        {
            scrollPos.y = 0;
            updateScrollBars();
            invalidate();
        }
        selectCell(_col, _headerRows);
    }
    /// Move cursor to the end of document
    private void documentEnd()
    {
        selectCell(_col, _rows - 1);
    }

    /// Move cursor to the beginning of line with selection
    private void selectLineBegin()
    {
        if (!_multiSelect)
        {
            lineBegin();
            return;
        }
        if (_rowSelect)
        {
            selectDocumentBegin();
            return;
        }
        int sc = scrollCol; // first fully visible column in scroll area
        if (sc > nonScrollCols && _col > sc)
        {
            multiSelectCell(sc, _lastSelectedCell.y, true);
        }
        else
        {
            if (sc > nonScrollCols)
            {
                scrollPos.x = 0;
                updateScrollBars();
                invalidate();
            }
            multiSelectCell(_headerCols, _lastSelectedCell.y, true);
        }
    }
    /// Move cursor to the end of line with selection
    private void selectLineEnd()
    {
        if (!_multiSelect)
        {
            lineEnd();
            return;
        }
        if (_rowSelect)
        {
            selectDocumentEnd();
            return;
        }
        if (_col < lastScrollCol)
        {
            // move selection and don's scroll
            multiSelectCell(lastScrollCol, _lastSelectedCell.y, true);
        }
        else
        {
            multiSelectCell(_cols - 1, _lastSelectedCell.y, true);
        }
    }
    /// Move cursor one page up with selection
    private void selectPageUp()
    {
        int sr = scrollRow; // first fully visible row in scroll area
        if (_row > sr)
        {
            // not at top scrollable cell
            multiSelectCell(_lastSelectedCell.x, sr, true);
        }
        else
        {
            // at top of scrollable area
            if (scrollRow > nonScrollRows)
            {
                // scroll up line by line
                int prevRow = _row;
                for (int i = prevRow - 1; i >= _headerRows; i--)
                {
                    multiSelectCell(_lastSelectedCell.x, i, true);
                    if (lastScrollRow <= prevRow)
                        break;
                }
            }
            else
            {
                // scrolled to top - move upper cell
                multiSelectCell(_lastSelectedCell.x, _headerRows, true);
            }
        }
    }
    /// Move cursor one page down with selection
    private void selectPageDown()
    {
        if (_row < _rows - 1)
        {
            int lr = lastScrollRow;
            if (_row < lr)
            {
                // not at bottom scrollable cell
                multiSelectCell(_lastSelectedCell.x, lr, true);
            }
            else
            {
                // scroll down
                int prevRow = _row;
                for (int i = prevRow + 1; i < _rows; i++)
                {
                    multiSelectCell(_lastSelectedCell.x, i, true);
                    if (scrollRow >= prevRow)
                        break;
                }
            }
        }
    }
    /// Move cursor to the beginning of page with selection
    private void selectPageBegin()
    {
        if (!_multiSelect)
        {
            pageBegin();
            return;
        }
        if (scrollRow > nonScrollRows)
            multiSelectCell(_lastSelectedCell.x, scrollRow, true);
        else
            multiSelectCell(_lastSelectedCell.x, _headerRows, true);
    }
    /// Move cursor to the end of page with selection
    private void selectPageEnd()
    {
        if (!_multiSelect)
        {
            pageEnd();
            return;
        }
        multiSelectCell(_lastSelectedCell.x, lastScrollRow, true);
    }
    /// Move cursor to the beginning of document with selection
    private void selectDocumentBegin()
    {
        if (!_multiSelect)
        {
            documentBegin();
            return;
        }
        if (scrollPos.y > 0)
        {
            scrollPos.y = 0;
            updateScrollBars();
            invalidate();
        }
        multiSelectCell(_lastSelectedCell.x, _headerRows, true);
    }
    /// Move cursor to the end of document with selection
    private void selectDocumentEnd()
    {
        if (!_multiSelect)
        {
            documentEnd();
            return;
        }
        multiSelectCell(_lastSelectedCell.x, _rows - 1, true);
    }

    /// Select all entries without moving the cursor
    private void selectAll()
    {
        if (!_multiSelect)
            return;
        int endX = row;
        if (_rowSelect)
            endX = 0;
        for (int x = 0; x <= endX; ++x)
        {
            for (int y = 0; y < rows; ++y)
            {
                _selection.insert(PointI(x, y));
            }
        }
        invalidate();
    }

    //===============================================================
    // Events

    /// Grid navigation using keys
    override bool handleKeyEvent(KeyEvent event)
    {
        /+
        if (_rowSelect)
        {
            switch (actionID) with (GridActions)
            {
            case left:
                actionID = GridActions.scrollLeft;
                break;
            case right:
                actionID = GridActions.scrollRight;
                break;
                //case lineBegin:
                //    actionID = GridActions.scrollPageLeft;
                //    break;
                //case lineEnd:
                //    actionID = GridActions.scrollPageRight;
                //    break;
            default:
                break;
            }
        }
        +/
        if (event.action == KeyAction.keyDown)
        {
            const bool shiftPressed = event.alteredBy(KeyMods.shift);
            // move or expand selection left
            if (event.key == Key.left)
            {
                if (_multiSelect && shiftPressed)
                {
                    multiSelectCell(_lastSelectedCell.x - 1, _lastSelectedCell.y, true);
                }
                else
                {
                    selectCell(_col - 1, _row);
                }
                return true;
            }
            // move or expand selection right
            if (event.key == Key.right)
            {
                if (_multiSelect && shiftPressed)
                {
                    multiSelectCell(_lastSelectedCell.x + 1, _lastSelectedCell.y, true);
                }
                else
                {
                    selectCell(_col + 1, _row);
                }
                return true;
            }
            // move or expand selection up
            if (event.key == Key.up)
            {
                if (_multiSelect && shiftPressed)
                {
                    multiSelectCell(_lastSelectedCell.x, _lastSelectedCell.y - 1, true);
                }
                else
                {
                    selectCell(_col, _row - 1);
                }
                return true;
            }
            // move or expand selection down
            if (event.key == Key.down)
            {
                if (_multiSelect && shiftPressed)
                {
                    multiSelectCell(_lastSelectedCell.x, _lastSelectedCell.y + 1, true);
                }
                else
                {
                    selectCell(_col, _row + 1);
                }
                return true;
            }
        }
        return super.handleKeyEvent(event);
    }

    override bool handleMouseEvent(MouseEvent event)
    {
        if (visibility != Visibility.visible)
            return false;
        int c, r; // col, row
        Box b;
        bool cellFound = false;
        bool normalCell = false;
        bool insideHeaderRow = false;
        bool insideHeaderCol = false;
        if (_colResizingIndex >= 0)
        {
            if (event.action == MouseAction.move)
            {
                // column resize is active
                processColResize(event.x);
                return true;
            }
            if (event.action == MouseAction.buttonUp || event.action == MouseAction.cancel)
            {
                // stop column resizing
                if (event.action == MouseAction.buttonUp)
                    processColResize(event.x);
                endColResize();
                return true;
            }
        }
        // convert coordinates
        if (event.action == MouseAction.buttonUp || event.action == MouseAction.buttonDown ||
                event.action == MouseAction.move)
        {
            int x = event.x - clientBox.x;
            int y = event.y - clientBox.y;
            if (_headerRows)
                insideHeaderRow = y < _rowCumulativeHeights[_headerRows - 1];
            if (_headerCols)
                insideHeaderCol = y < _colCumulativeWidths[_headerCols - 1];
            cellFound = pointToCell(x, y, c, r, b);
            normalCell = c >= _headerCols && r >= _headerRows;
        }
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            if (canFocus && !focused)
                setFocus();
            int resizeCol = isColumnResizingPoint(event.x, event.y);
            if (resizeCol >= 0)
            {
                // start column resizing
                startColResize(resizeCol, event.x);
                event.track(WeakRef!Widget(this));
                return true;
            }
            if (cellFound && normalCell)
            {
                if (c == _col && r == _row && event.doubleClick)
                {
                    activateCell(c, r);
                }
                else if (_multiSelect && event.alteredBy(KeyMods.control))
                {
                    multiSelectCell(c, r, event.alteredBy(KeyMods.shift));
                }
                else
                {
                    selectCell(c, r);
                }
            }
            return true;
        }
        if (event.action == MouseAction.buttonUp && event.button == MouseButton.left)
        {
            if (cellFound && !normalCell)
            {
                onHeaderCellClick(c, r);
            }
        }
        if (event.action == MouseAction.move && event.alteredByButton(MouseButton.left))
        {
            // TODO: selection
            if (cellFound && normalCell)
            {
                if (_multiSelect)
                {
                    multiSelectCell(c, r, true);
                }
                else
                {
                    selectCell(c, r);
                }
            }
            return true;
        }
        return super.handleMouseEvent(event);
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        if (event.alteredBy(KeyMods.shift))
            scrollBy(event.deltaY, event.deltaX);
        else
            scrollBy(event.deltaX, event.deltaY);
        return true;
    }

    //===============================================================

    override Size fullContentSize() const
    {
        return fullAreaPixels;
    }

    private int _minVisibleCols = 2;
    private int _minVisibleRows = 2;

    /// Number of columns from 0 that are taken to measure minimum visible width
    @property int minVisibleCols() const { return _minVisibleCols; }
    /// ditto
    @property void minVisibleCols(int newMinVisibleCols)
    {
        _minVisibleCols = newMinVisibleCols;
        requestLayout();
    }

    /// Number of rows from 0 that are taken to measure minimum visible height; if there are too little rows last row height is multiplied
    @property int minVisibleRows() const { return _minVisibleRows; }
    /// ditto
    @property void minVisibleRows(int newMinVisibleRows)
    {
        _minVisibleRows = newMinVisibleRows;
        requestLayout();
    }

    override protected void adjustBoundaries(ref Boundaries bs)
    {
        if (_cols == 0 || _rows == 0)
        {
            bs.min += Size(100, 100);
            bs.nat += Size(100, 100);
            return;
        }

        Size sz;
        // width
        const firstVisibleCol = _showRowHeaders ? 0 : _headerCols;
        foreach (i; firstVisibleCol .. min(_cols, _minVisibleCols + firstVisibleCol))
            sz.w += min(_colUntouchedWidths[i], 100);
        // height
        const firstVisibleRow = _showColHeaders ? 0 : _headerRows;
        foreach (j; firstVisibleRow .. min(_rows, _minVisibleRows + firstVisibleRow))
            sz.h += _rowUntouchedHeights[j];
        if (_rows < _minVisibleRows)
            sz.h += (_minVisibleRows - _rows) * _rowUntouchedHeights[_rows - 1];

        bs.min += sz;
        bs.nat += sz;
    }

    protected Size measureCell(int x, int y) const
    {
        // override it!
        return Size(BACKEND_CONSOLE ? 5 : 80, BACKEND_CONSOLE ? 1 : 20);
    }

    protected int measureColWidth(int x) const
    {
        if (!_showRowHeaders && x < _headerCols)
            return 0;
        int w;
        foreach (i; 0 .. _rows)
        {
            Size sz = measureCell(x - _headerCols, i - _headerRows);
            w = max(w, sz.w);
        }
        static if (BACKEND_GUI)
            w = max(w, 10); // TODO: use min size
        else
            w = max(w, 1); // TODO: use min size
        return w;
    }

    protected int measureRowHeight(int y) const
    {
        int h;
        foreach (i; 0 .. _cols)
        {
            Size sz = measureCell(i - _headerCols, y - _headerRows);
            h = max(h, sz.h);
        }
        static if (BACKEND_GUI)
            h = max(h, 12); // TODO: use min size
        return h;
    }

    /// Resize columns and rows to their content
    void autoFit()
    {
        autoFitColumnWidths();
        autoFitRowHeights();
        updateCumulativeSizes();
    }

    /// Resize columns to their content
    void autoFitColumnWidths()
    {
        foreach (i; 0 .. _cols)
            autoFitColumnWidth(i);
        _changedSize = true;
        invalidate();
    }

    /// Resize specified column to its content
    void autoFitColumnWidth(int i)
    {
        if (!_showRowHeaders && i < _headerCols)
        {
            _colUntouchedWidths[i] = 0;
            _colWidths[i] = 0;
        }
        else
        {
            _colUntouchedWidths[i] = measureColWidth(i) + (BACKEND_CONSOLE ? 1 : 3);
            _colWidths[i] = _colUntouchedWidths[i];
        }
        _changedSize = true;
    }

    /// Resize rows to their content
    void autoFitRowHeights()
    {
        foreach (i; 0 .. _rows)
            autoFitRowHeight(i);
    }

    /// Resize specified row to its content
    void autoFitRowHeight(int j)
    {
        if (!_showColHeaders && j < _headerRows)
        {
            _rowUntouchedHeights[j] = 0;
            _rowHeights[j] = 0;
        }
        else
        {
            _rowUntouchedHeights[j] = measureRowHeight(j) + (BACKEND_CONSOLE ? 0 : 2);
            _rowHeights[j] = _rowUntouchedHeights[j];
        }
        _changedSize = true;
    }

    /// Extend specified column width to fit client area. Should be used after autofit and layout
    void fillColumnWidth(int i)
    {
        int w = clientBox.width;
        int totalw;
        foreach (k; 0 .. _cols)
            totalw += _colWidths[k];
        if (w > totalw)
            _colWidths.unsafe_ref(i + _headerCols) += w - totalw;
        _changedSize = true;
        invalidate();
    }

    override protected void drawClient(DrawBuf buf)
    {
        if (!_cols || !_rows)
            return; // no cells

        int nscols = nonScrollCols;
        int nsrows = nonScrollRows;
        Size nspixels = nonScrollAreaPixels;
        int maxVisibleCol = colByAbsoluteX(clientBox.width + scrollPos.x);
        int maxVisibleRow = rowByAbsoluteY(clientBox.height + scrollPos.y);
        for (int phase = 0; phase < 2; phase++)
        { // phase0 == background, phase1 == foreground
            for (int y = 0; y <= maxVisibleRow; y++)
            {
                if (!rowVisible(y))
                    continue;
                for (int x = 0; x <= maxVisibleCol; x++)
                {
                    if (!colVisible(x))
                        continue;
                    Box cellBox = cellBox(x, y);
                    if (BACKEND_CONSOLE && phase == 1)
                    {
                        cellBox.width--;
                    }
                    Box clippedCellBox = cellBox;
                    if (x >= nscols && cellBox.x < nspixels.w)
                        clippedCellBox.x = nspixels.w; // clip scrolled left
                    if (y >= nsrows && cellBox.y < nspixels.h)
                        clippedCellBox.y = nspixels.h; // clip scrolled left
                    if (clippedCellBox.empty)
                        continue; // completely clipped out

                    cellBox.x += clientBox.x;
                    cellBox.y += clientBox.y;
                    clippedCellBox.x += clientBox.x;
                    clippedCellBox.y += clientBox.y;

                    auto cellSaver = ClipRectSaver(buf, clippedCellBox, 0);
                    bool isHeader = x < _headerCols || y < _headerRows;
                    if (phase == 0)
                    {
                        if (isHeader)
                            drawHeaderCellBackground(buf, cellBox, x - _headerCols, y - _headerRows);
                        else
                            drawCellBackground(buf, cellBox, x - _headerCols, y - _headerRows);
                    }
                    else
                    {
                        if (isHeader)
                            drawHeaderCell(buf, cellBox, x - _headerCols, y - _headerRows);
                        else
                            drawCell(buf, cellBox, x - _headerCols, y - _headerRows);
                    }
                }
            }
        }
    }

    /// Draw data cell content
    protected void drawCell(DrawBuf buf, Box b, int col, int row)
    {
        // override it
    }

    /// Draw header cell content
    protected void drawHeaderCell(DrawBuf buf, Box b, int col, int row)
    {
        // override it
    }

    /// Draw data cell background
    protected void drawCellBackground(DrawBuf buf, Box b, int col, int row)
    {
        // override it
    }

    /// Draw header cell background
    protected void drawHeaderCellBackground(DrawBuf buf, Box b, int col, int row)
    {
        // override it
    }
}

class StringGridWidgetBase : GridWidgetBase
{
    /// Get cell text
    abstract dstring cellText(int col, int row) const;
    /// Set cell text
    abstract StringGridWidgetBase setCellText(int col, int row, dstring text);
    /// Returns row header title
    abstract dstring rowTitle(int row) const;
    /// Set row header title
    abstract StringGridWidgetBase setRowTitle(int row, dstring title);
    /// Returns row header title
    abstract dstring colTitle(int col) const;
    /// Set col header title
    abstract StringGridWidgetBase setColTitle(int col, dstring title);
}

/**
    Grid view with string data shown. All rows are of the same height
*/
class StringGridWidget : StringGridWidgetBase
{
    private
    {
        dstring[][] _data;
        dstring[] _rowTitles;
        dstring[] _colTitles;
    }

    this()
    {
        handleThemeChange();
    }

    /// Get cell text
    override dstring cellText(int col, int row) const
    {
        if (col >= 0 && col < cols && row >= 0 && row < rows)
            return _data[row][col];
        return ""d;
    }

    override StringGridWidgetBase setCellText(int col, int row, dstring text)
    {
        if (col >= 0 && col < cols && row >= 0 && row < rows)
            _data[row][col] = text;
        return this;
    }

    override void resize(int c, int r)
    {
        if (c == cols && r == rows)
            return;
        int oldcols = cols;
        int oldrows = rows;
        super.resize(c, r);
        _data.length = r;
        for (int y = 0; y < r; y++)
            _data[y].length = c;
        _colTitles.length = c;
        _rowTitles.length = r;
    }

    override dstring rowTitle(int row) const
    {
        return _rowTitles[row];
    }
    override StringGridWidgetBase setRowTitle(int row, dstring title)
    {
        _rowTitles[row] = title;
        return this;
    }

    override dstring colTitle(int col) const
    {
        return _colTitles[col];
    }
    override StringGridWidgetBase setColTitle(int col, dstring title)
    {
        _colTitles[col] = title;
        return this;
    }

    override protected Size measureCell(int x, int y) const
    {
        if (_customCellAdapter && _customCellAdapter.isCustomCell(x, y))
        {
            return _customCellAdapter.measureCell(x, y);
        }
        dstring txt;
        if (x >= 0 && y >= 0)
            txt = cellText(x, y);
        else if (y < 0 && x >= 0)
            txt = colTitle(x);
        else if (y >= 0 && x < 0)
            txt = rowTitle(y);
        Font fnt = font.get;
        auto st = TextLayoutStyle(fnt);
        Size sz = computeTextSize(txt, st);
        sz.h = max(sz.h, fnt.height);
        return sz;
    }

    override protected void drawCell(DrawBuf buf, Box b, int col, int row)
    {
        if (_customCellAdapter && _customCellAdapter.isCustomCell(col, row))
            return _customCellAdapter.drawCell(buf, b, col, row);

        static if (BACKEND_GUI)
            b.shrink(Insets(1, 2));
        else
            b.width--;

        dstring txt = cellText(col, row);
        const offset = BACKEND_CONSOLE ? 0 : 1;
        drawSimpleText(buf, txt, b.x + offset, b.y + offset, font.get, style.textColor);
    }

    override protected void drawHeaderCell(DrawBuf buf, Box b, int col, int row)
    {
        static if (BACKEND_GUI)
            b.shrink(Insets(1, 2));
        else
            b.width--;
        dstring txt;
        if (row < 0 && col >= 0)
            txt = colTitle(col);
        else if (row >= 0 && col < 0)
            txt = rowTitle(row);
        if (!txt.length)
            return;
        Font fnt = font.get;
        auto st = TextLayoutStyle(fnt);
        const sz = computeTextSize(txt, st);
        Align ha = Align.left;
        if (col < 0)
            ha = Align.right;
        //if (row < 0)
        //    ha = Align.hcenter;
        const cb = alignBox(b, sz, ha | Align.vcenter);
        const offset = BACKEND_CONSOLE ? 0 : 1;
        const cl = currentTheme.getColor("grid_cell_text_header", style.textColor);
        drawSimpleText(buf, txt, cb.x + offset, cb.y + offset, fnt, cl);
    }

    override protected void drawHeaderCellBackground(DrawBuf buf, Box b, int c, int r)
    {
        bool selectedCol = (c == col) && !_rowSelect;
        bool selectedRow = r == row;
        bool selectedCell = selectedCol && selectedRow;
        if (_rowSelect && selectedRow)
            selectedCell = true;
        if (!selectedCell && _multiSelect)
        {
            selectedCell = PointI(c, r) in _selection || (_rowSelect && PointI(0, r) in _selection);
        }
        // draw header cell background
        DrawableRef dw = c < 0 ? _cellRowHeaderBackgroundDrawable : _cellHeaderBackgroundDrawable;
        Color cl = _cellHeaderBackgroundColor;
        if (c >= 0 || r >= 0)
        {
            if (c < 0 && selectedRow)
            {
                cl = _cellHeaderSelectedBackgroundColor;
                dw = _cellRowHeaderSelectedBackgroundDrawable;
            }
            else if (r < 0 && selectedCol)
            {
                cl = _cellHeaderSelectedBackgroundColor;
                dw = _cellHeaderSelectedBackgroundDrawable;
            }
        }
        Rect rc = b;
        if (!dw.isNull)
            dw.drawTo(buf, b);
        else
            buf.fillRect(rc, cl);
        static if (BACKEND_GUI)
        {
            Color borderColor = _cellHeaderBorderColor;
            // vertical
            buf.drawLine(Point(rc.right, rc.bottom), Point(rc.right, rc.top), borderColor);
            // horizontal
            buf.drawLine(Point(rc.left, rc.bottom), Point(rc.right, rc.bottom), borderColor);
        }
    }

    override protected void drawCellBackground(DrawBuf buf, Box b, int c, int r)
    {
        bool selectedCol = c == col;
        bool selectedRow = r == row;
        bool selectedCell = selectedCol && selectedRow;
        if (_rowSelect && selectedRow)
            selectedCell = true;
        if (!selectedCell && _multiSelect)
        {
            selectedCell = PointI(c, r) in _selection || (_rowSelect && PointI(0, r) in _selection);
        }

        Rect rc = b;
        Color borderColor = _cellBorderColor;
        if (c < fixedCols || r < fixedRows)
        {
            // fixed cell background
            buf.fillRect(rc, _fixedCellBackgroundColor);
            borderColor = _fixedCellBorderColor;
        }
        static if (BACKEND_GUI)
        {
            // vertical
            buf.drawLine(Point(rc.right, rc.bottom), Point(rc.right, rc.top), borderColor);
            // horizontal
            buf.drawLine(Point(rc.left, rc.bottom), Point(rc.right, rc.bottom), borderColor);
        }
        if (selectedCell)
        {
            static if (BACKEND_GUI)
            {
                if (_rowSelect)
                    buf.drawFrame(rc, _selectionColorRowSelect, Insets(1, 0), _cellBorderColor);
                else
                    buf.drawFrame(rc, _selectionColor, Insets(1), _cellBorderColor);
            }
            else
            {
                if (_rowSelect)
                    buf.fillRect(rc, _selectionColorRowSelect);
                else
                    buf.fillRect(rc, _selectionColor);
            }
        }
    }

    override void handleThemeChange()
    {
        super.handleThemeChange();
        _selectionColor = currentTheme.getColor("grid_selection", Color(0x4040FF, 0x80));
        _selectionColorRowSelect = currentTheme.getColor("grid_selection_row", Color(0xA0B0FF, 0x40));
        _fixedCellBackgroundColor = currentTheme.getColor("grid_cell_background_fixed", Color(0xE0E0E0, 0x40));
        _cellBorderColor = currentTheme.getColor("grid_cell_border", Color(0xC0C0C0, 0x40));
        _fixedCellBorderColor = currentTheme.getColor("grid_cell_border_fixed", _cellBorderColor);
        _cellHeaderBorderColor = currentTheme.getColor("grid_cell_border_header", Color(0x202020, 0x40));
        _cellHeaderBackgroundColor = currentTheme.getColor("grid_cell_background_header", Color(0x909090, 0x40));
        _cellHeaderSelectedBackgroundColor = currentTheme.getColor("grid_cell_background_header_selected", Color(0xFFC040, 0x80));
        _cellHeaderBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_header");
        _cellHeaderSelectedBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_header_selected");
        _cellRowHeaderBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_row_header");
        _cellRowHeaderSelectedBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_row_header_selected");
    }
}
