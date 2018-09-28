/**

This module contains implementation of grid widgets


GridWidgetBase - abstract grid widget

StringGridWidget - grid of strings


Synopsis:
---
import beamui.widgets.grid;

auto grid = new StringGridWidget("GRID1");
grid.fillWH();
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

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.grid;

import std.container.rbtree;
import beamui.core.config;
import beamui.core.stdaction;
import beamui.widgets.controls;
import beamui.widgets.menu;
import beamui.widgets.scroll;
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
    /// Returns row header widget, null if no header
    Widget rowHeader(int row);
    /// Returns column header widget, null if no header
    Widget colHeader(int col);
}

///
class StringGridAdapter : GridAdapter
{
    protected
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
        int cols() const
        {
            return _cols;
        }
        /// Number of columns
        void cols(int v)
        {
            resize(v, _rows);
        }
        /// Number of rows
        int rows() const
        {
            return _rows;
        }
        /// Number of columns
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
    /// Returns row header widget, null if no header
    Widget rowHeader(int row)
    {
        return null;
    }
    /// Returns column header widget, null if no header
    Widget colHeader(int col)
    {
        return null;
    }
}

/// Adapter for custom drawing of some cells in grid widgets
interface CustomGridCellAdapter
{
    /// Returns true for custom drawn cell
    bool isCustomCell(int col, int row);
    /// Returns cell size
    Size measureCell(int col, int row);
    /// Draw data cell content
    void drawCell(DrawBuf buf, Box b, int col, int row);
}

interface GridModelAdapter
{
    @property int fixedCols();
    @property int fixedRows();
    @property void fixedCols(int value);
    @property void fixedRows(int value);
}

/// Abstract grid widget
class GridWidgetBase : ScrollAreaBase, GridModelAdapter, ActionOperator
{
    @property
    {
        /// Selected cells when multiselect is enabled
        RedBlackTree!Point selection()
        {
            return _selection;
        }
        /// Selected column
        int col()
        {
            return _col - _headerCols;
        }
        /// Selected row
        int row()
        {
            return _row - _headerRows;
        }
        /// Column count
        int cols()
        {
            return _cols - _headerCols;
        }
        /// Set column count
        GridWidgetBase cols(int c)
        {
            resize(c, rows);
            return this;
        }
        /// Row count
        int rows()
        {
            return _rows - _headerRows;
        }
        /// Set row count
        GridWidgetBase rows(int r)
        {
            resize(cols, r);
            return this;
        }

        /// Get col resizing flag; when true, allow resizing of column with mouse
        bool allowColResizing()
        {
            return _allowColResizing;
        }
        /// Set col resizing flag; when true, allow resizing of column with mouse
        GridWidgetBase allowColResizing(bool flagAllowColResizing)
        {
            _allowColResizing = flagAllowColResizing;
            return this;
        }

        /// Row header column count
        int headerCols()
        {
            return _headerCols;
        }

        GridWidgetBase headerCols(int c)
        {
            _headerCols = c;
            invalidate();
            return this;
        }
        /// Col header row count
        int headerRows()
        {
            return _headerRows;
        }

        GridWidgetBase headerRows(int r)
        {
            _headerRows = r;
            invalidate();
            return this;
        }

        /// Fixed (non-scrollable) data column count
        int fixedCols()
        {
            return _gridModelAdapter is null ? _fixedCols : _gridModelAdapter.fixedCols;
        }

        void fixedCols(int c)
        {
            if (_gridModelAdapter is null)
                _fixedCols = c;
            else
                _gridModelAdapter.fixedCols = c;
            invalidate();
        }
        /// Fixed (non-scrollable) data row count
        int fixedRows()
        {
            return _gridModelAdapter is null ? _fixedRows : _gridModelAdapter.fixedCols;
        }

        void fixedRows(int r)
        {
            if (_gridModelAdapter is null)
                _fixedRows = r;
            else
                _gridModelAdapter.fixedCols = r;
            invalidate();
        }

        /// Count of non-scrollable columns (header + fixed)
        int nonScrollCols()
        {
            return _headerCols + fixedCols;
        }
        /// Count of non-scrollable rows (header + fixed)
        int nonScrollRows()
        {
            return _headerRows + fixedRows;
        }

        /// Default column width - for newly added columns
        int defColumnWidth()
        {
            return _defColumnWidth;
        }

        GridWidgetBase defColumnWidth(int v)
        {
            _defColumnWidth = v;
            _changedSize = true;
            return this;
        }
        /// Default row height - for newly added rows
        int defRowHeight()
        {
            return _defRowHeight;
        }

        GridWidgetBase defRowHeight(int v)
        {
            _defRowHeight = v;
            _changedSize = true;
            return this;
        }

        /// When true, allows multi cell selection
        bool multiSelect()
        {
            return _multiSelect;
        }

        GridWidgetBase multiSelect(bool flag)
        {
            _multiSelect = flag;
            if (!_multiSelect)
            {
                _selection.clear();
                _selection.insert(Point(_col - _headerCols, _row - _headerRows));
            }
            return this;
        }

        /// When true, allows only select the whole row
        bool rowSelect()
        {
            return _rowSelect;
        }

        GridWidgetBase rowSelect(bool flag)
        {
            _rowSelect = flag;
            if (_rowSelect)
            {
                _selection.clear();
                _selection.insert(Point(_col - _headerCols, _row - _headerRows));
            }
            invalidate();
            return this;
        }

        /// Flag to enable column headers
        bool showColHeaders()
        {
            return _showColHeaders;
        }

        GridWidgetBase showColHeaders(bool show)
        {
            if (_showColHeaders != show)
            {
                _showColHeaders = show;
                for (int i = 0; i < _headerRows; i++)
                    autoFitRowHeight(i);
                _changedSize = true;
                invalidate();
            }
            return this;
        }

        /// Flag to enable row headers
        bool showRowHeaders()
        {
            return _showRowHeaders;
        }

        GridWidgetBase showRowHeaders(bool show)
        {
            if (_showRowHeaders != show)
            {
                _showRowHeaders = show;
                for (int i = 0; i < _headerCols; i++)
                    autoFitColumnWidth(i);
                _changedSize = true;
                invalidate();
            }
            return this;
        }

        /// Returns all (fixed + scrollable) cells size in pixels
        Size fullAreaPixels()
        {
            if (_changedSize)
                updateCumulativeSizes();
            return Size(_cols ? _colCumulativeWidths[_cols - 1] : 0, _rows ? _rowCumulativeHeights[_rows - 1] : 0);
        }
        /// Non-scrollable area size in pixels
        Size nonScrollAreaPixels()
        {
            if (_changedSize)
                updateCumulativeSizes();
            int nscols = nonScrollCols;
            int nsrows = nonScrollRows;
            return Size(nscols ? _colCumulativeWidths[nscols - 1] : 0, nsrows ? _rowCumulativeHeights[nsrows - 1] : 0);
        }
        /// Scrollable area size in pixels
        Size scrollAreaPixels()
        {
            return fullAreaPixels - nonScrollAreaPixels;
        }

        /// Get adapter to override drawing of some particular cells
        CustomGridCellAdapter customCellAdapter()
        {
            return _customCellAdapter;
        }

        /// Set adapter to override drawing of some particular cells
        GridWidgetBase customCellAdapter(CustomGridCellAdapter adapter)
        {
            _customCellAdapter = adapter;
            return this;
        }

        /// Get adapter to hold grid model data
        GridModelAdapter gridModelAdapter()
        {
            return _gridModelAdapter;
        }
        /// Set adapter to hold grid model data
        GridWidgetBase gridModelAdapter(GridModelAdapter adapter)
        {
            _gridModelAdapter = adapter;
            return this;
        }

        /// Smooth horizontal scroll flag - when true - scrolling by pixels, when false - by cells
        bool smoothHScroll() const
        {
            return _smoothHScroll;
        }
        /// ditto
        GridWidgetBase smoothHScroll(bool flagSmoothScroll)
        {
            if (_smoothHScroll != flagSmoothScroll)
            {
                _smoothHScroll = flagSmoothScroll;
                // TODO: snap to grid if necessary
                updateScrollBars();
            }
            return this;
        }

        /// Smooth vertical scroll flag - when true - scrolling by pixels, when false - by cells
        bool smoothVScroll() const
        {
            return _smoothVScroll;
        }
        /// ditto
        GridWidgetBase smoothVScroll(bool flagSmoothScroll)
        {
            if (_smoothVScroll != flagSmoothScroll)
            {
                _smoothVScroll = flagSmoothScroll;
                // TODO: snap to grid if necessary
                updateScrollBars();
            }
            return this;
        }

        /// Extends scroll area to show full column at left when scrolled to rightmost column
        bool fullColumnOnLeft()
        {
            return _fullColumnOnLeft;
        }
        /// ditto
        GridWidgetBase fullColumnOnLeft(bool newFullColumnOnLeft)
        {
            if (_fullColumnOnLeft != newFullColumnOnLeft)
            {
                _fullColumnOnLeft = newFullColumnOnLeft;
                updateScrollBars();
            }
            return this;
        }

        /// Extends scroll area to show full row at top when scrolled to end row
        bool fullRowOnTop()
        {
            return _fullColumnOnLeft;
        }
        /// ditto
        GridWidgetBase fullRowOnTop(bool newFullRowOnTop)
        {
            if (_fullRowOnTop != newFullRowOnTop)
            {
                _fullRowOnTop = newFullRowOnTop;
                updateScrollBars();
            }
            return this;
        }
    }

    /// Set bool property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setBoolProperty", "bool", "showColHeaders",
            "showColHeaders", "rowSelect", "smoothHScroll", "smoothVScroll", "allowColResizing"));

    /// Set int property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setIntProperty", "int", "headerCols",
            "headerRows", "fixedCols", "fixedRows", "cols", "rows", "defColumnWidth", "defRowHeight"));

    /// Callback to handle selection change
    Listener!(void delegate(GridWidgetBase, int col, int row)) cellSelected;
    /// Callback to handle cell double click or Enter key press
    Listener!(void delegate(GridWidgetBase, int col, int row)) cellActivated;
    /// Callback for handling of view scroll (top left visible cell change)
    Listener!(void delegate(GridWidgetBase, int col, int row)) viewScrolled;
    /// Callback for handling header cell click
    Listener!(void delegate(GridWidgetBase, int col, int row)) headerCellClicked;

    protected
    {
        /// Column count (including header columns and fixed columns)
        int _cols;
        /// Row count (including header rows and fixed rows)
        int _rows;
        /// Column widths
        int[] _colWidths;
        /// Total width from first column to right of this
        int[] _colCumulativeWidths;
        /// Row heights
        int[] _rowHeights;
        /// Total height from first row to bottom of this
        int[] _rowCumulativeHeights;
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
        RedBlackTree!Point _selection;
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

        uint _selectionColor = 0x804040FF;
        uint _selectionColorRowSelect = 0xC0A0B0FF;
        uint _fixedCellBackgroundColor = 0xC0E0E0E0;
        uint _fixedCellBorderColor = 0xC0C0C0C0;
        uint _cellBorderColor = 0xC0C0C0C0;
        uint _cellHeaderBorderColor = 0xC0202020;
        uint _cellHeaderBackgroundColor = 0xC0909090;
        uint _cellHeaderSelectedBackgroundColor = 0x80FFC040;
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
        _selection = new RedBlackTree!Point;
        _defRowHeight = BACKEND_CONSOLE ? 1 : 16.pt;
        _defColumnWidth = BACKEND_CONSOLE ? 7 : 100;

        _showColHeaders = true;
        _showRowHeaders = true;
        focusable = true;
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

    protected bool _changedSize = true;
    /// Recalculate _colCumulativeWidths, _rowCumulativeHeights after resizes
    protected void updateCumulativeSizes()
    {
        if (!_changedSize)
            return;
        _changedSize = false;
        _colCumulativeWidths.length = _colWidths.length;
        _rowCumulativeHeights.length = _rowHeights.length;
        for (int i = 0; i < _colCumulativeWidths.length; i++)
        {
            if (i == 0)
                _colCumulativeWidths[i] = _colWidths[i];
            else
                _colCumulativeWidths[i] = _colWidths[i] + _colCumulativeWidths[i - 1];
        }
        for (int i = 0; i < _rowCumulativeHeights.length; i++)
        {
            if (i == 0)
                _rowCumulativeHeights[i] = _rowHeights[i];
            else
                _rowCumulativeHeights[i] = _rowHeights[i] + _rowCumulativeHeights[i - 1];
        }
    }

    /// Set new size
    void resize(int c, int r)
    {
        if (c == cols && r == rows)
            return;
        _changedSize = true;
        _colWidths.length = c + _headerCols;
        for (int i = _cols; i < c + _headerCols; i++)
        {
            _colWidths[i] = _defColumnWidth;
        }
        _rowHeights.length = r + _headerRows;
        for (int i = _rows; i < r + _headerRows; i++)
        {
            _rowHeights[i] = _defRowHeight;
        }
        _cols = c + _headerCols;
        _rows = r + _headerRows;
        updateCumulativeSizes();
    }

    /// Returns true if column is inside client area and not overlapped outside scroll area
    bool colVisible(int x)
    {
        if (_changedSize)
            updateCumulativeSizes();
        if (x < 0 || x >= _cols)
            return false;
        if (x == 0)
            return true;
        int nscols = nonScrollCols;
        if (x < nscols)
        {
            // non-scrollable
            return _colCumulativeWidths[x - 1] < clientBox.width;
        }
        else
        {
            // scrollable
            int start = _colCumulativeWidths[x - 1] - _scrollPos.x;
            int end = _colCumulativeWidths[x] - _scrollPos.x;
            if (start >= clientBox.width)
                return false; // at right
            if (end <= (nscols ? _colCumulativeWidths[nscols - 1] : 0))
                return false; // at left
            return true; // visible
        }
    }
    /// Returns true if row is inside client area and not overlapped outside scroll area
    bool rowVisible(int y)
    {
        if (y < 0 || y >= _rows)
            return false;
        if (_changedSize)
            updateCumulativeSizes();
        if (y == 0)
            return true; // first row always visible
        int nsrows = nonScrollRows;
        if (y < nsrows)
        {
            // non-scrollable
            return _rowCumulativeHeights[y - 1] < clientBox.height;
        }
        else
        {
            // scrollable
            int start = _rowCumulativeHeights[y - 1] - _scrollPos.y;
            int end = _rowCumulativeHeights[y] - _scrollPos.y;
            if (start >= clientBox.height)
                return false; // at right
            if (end <= (nsrows ? _rowCumulativeHeights[nsrows - 1] : 0))
                return false; // at left
            return true; // visible
        }
    }

    /// Get cell rectangle (relative to client area) not counting scroll position
    Box cellBoxNoScroll(int x, int y)
    {
        if (_changedSize)
            updateCumulativeSizes();
        if (x < 0 || y < 0 || x >= _cols || y >= _rows)
            return Box(0, 0, 0, 0);
        return Box(x ? _colCumulativeWidths[x - 1] : 0, y ? _rowCumulativeHeights[y - 1] : 0,
                _colWidths[x], _rowHeights[y]);
    }
    /// Get cell rectangle relative to client area; row 0 is col headers row; col 0 is row headers column
    Box cellBox(int x, int y)
    {
        Box b = cellBoxNoScroll(x, y);
        int nscols = nonScrollCols;
        int nsrows = nonScrollRows;
        if (x >= nscols)
            b.x -= _scrollPos.x;
        if (y >= nsrows)
            b.y -= _scrollPos.y;
        return b;
    }

    void setColWidth(int x, int w)
    {
        _colWidths[x] = w;
        _changedSize = true;
    }

    void setRowHeight(int y, int w)
    {
        _rowHeights[y] = w;
        _changedSize = true;
    }

    /// Get column width, 0 is header column
    int colWidth(int col)
    {
        if (col < 0 || col >= _colWidths.length)
            return 0;
        return _colWidths[col];
    }

    /// Get row height, 0 is header row
    int rowHeight(int row)
    {
        if (row < 0 || row >= _rowHeights.length)
            return 0;
        return _rowHeights[row];
    }

    /// Converts client rect relative coordinates to cell coordinates
    bool pointToCell(int x, int y, ref int col, ref int row, ref Box cellb)
    {
        if (_changedSize)
            updateCumulativeSizes();
        int nscols = nonScrollCols;
        int nsrows = nonScrollRows;
        Size ns = nonScrollAreaPixels;
        col = colByAbsoluteX(x < ns.w ? x : x + _scrollPos.x);
        row = rowByAbsoluteY(y < ns.h ? y : y + _scrollPos.y);
        cellb = cellBox(col, row);
        return cellb.isPointInside(x, y);
    }

    override protected void updateScrollBars()
    {
        if (_changedSize)
            updateCumulativeSizes();
        correctScrollPos();
        super.updateScrollBars();
    }

    /// Search for index of position inside cumulative sizes array
    protected static int findPosIndex(int[] cumulativeSizes, int pos)
    {
        // binary search
        if (pos < 0 || !cumulativeSizes.length)
            return 0;
        int a = 0; // inclusive lower bound
        int b = cast(int)cumulativeSizes.length; // exclusive upper bound
        if (pos >= cumulativeSizes[$ - 1])
            return b - 1;
        int* w = cumulativeSizes.ptr;
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
    protected int colByAbsoluteX(int x)
    {
        if (_changedSize)
            updateCumulativeSizes();
        return findPosIndex(_colCumulativeWidths, x);
    }

    /// Row by Y, ignoring scroll position
    protected int rowByAbsoluteY(int y)
    {
        if (_changedSize)
            updateCumulativeSizes();
        return findPosIndex(_rowCumulativeHeights, y);
    }

    /// Returns first fully visible column in scroll area
    protected int scrollCol()
    {
        if (_changedSize)
            updateCumulativeSizes();
        int x = nonScrollAreaPixels.w + _scrollPos.x;
        int col = colByAbsoluteX(x);
        int start = col ? _colCumulativeWidths[col - 1] : 0;
        int end = _colCumulativeWidths[col];
        if (x <= start)
            return col;
        // align to next col
        return colByAbsoluteX(end);
    }

    /// Returns last fully visible column in scroll area
    protected int lastScrollCol()
    {
        if (_changedSize)
            updateCumulativeSizes();
        int x = _scrollPos.x + _clientBox.w - 1;
        int col = colByAbsoluteX(x);
        int start = col ? _colCumulativeWidths[col - 1] : 0;
        int end = _colCumulativeWidths[col];
        // not fully visible
        if (x < end - 1 && col > nonScrollCols && col > scrollCol)
            col--;
        return col;
    }

    /// Returns first fully visible row in scroll area
    protected int scrollRow()
    {
        if (_changedSize)
            updateCumulativeSizes();
        int y = nonScrollAreaPixels.h + _scrollPos.y;
        int row = rowByAbsoluteY(y);
        int start = row ? _rowCumulativeHeights[row - 1] : 0;
        int end = _rowCumulativeHeights[row];
        if (y <= start)
            return row;
        // align to next col
        return rowByAbsoluteY(end);
    }

    /// Returns last fully visible row in scroll area
    protected int lastScrollRow()
    {
        if (_changedSize)
            updateCumulativeSizes();
        int y = _scrollPos.y + _clientBox.h - 1;
        int row = rowByAbsoluteY(y);
        int start = row ? _rowCumulativeHeights[row - 1] : 0;
        int end = _rowCumulativeHeights[row];
        // not fully visible
        if (y < end - 1 && row > nonScrollRows && row > scrollRow)
            row--;
        return row;
    }

    /// Move scroll position horizontally by dx, and vertically by dy; returns true if scrolled
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
            int maxscrollx = _clientBox.x + csz.w - _clientBox.w;
            int maxscrolly = _clientBox.y + csz.h - _clientBox.h;
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

        _scrollPos.x = clamp(csz.w + extra.w - _clientBox.w, 0, _scrollPos.x);
        _scrollPos.y = clamp(csz.h + extra.h - _clientBox.h, 0, _scrollPos.y);
    }

    /// Set scroll position to show specified cell as top left in scrollable area; col or row -1 value means no change
    bool scrollTo(int x, int y, GridWidgetBase source = null, bool doNotify = true)
    {
        if (_changedSize)
            updateCumulativeSizes();
        Point oldpos = _scrollPos;
        _scrollPos = Point(x, y);
        updateScrollBars();
        invalidate();
        bool changed = oldpos != _scrollPos;
        if (doNotify && changed && viewScrolled.assigned)
        {
            if (source is null)
                source = this;
            viewScrolled(source, x, y);
        }
        return changed;
    }

    /// Process horizontal scrollbar event
    override void onHScroll(ScrollEvent event)
    {
        // scroll w/o changing selection
        if (event.action == ScrollAction.sliderMoved || event.action == ScrollAction.sliderReleased)
        {
            scrollTo(event.position, _scrollPos.y);
        }
        else if (event.action == ScrollAction.pageUp)
        {
            // scroll left cell by cell
            int sc = scrollCol;
            while (scrollCol > nonScrollCols)
            {
                scrollBy(-1, 0);
                if (lastScrollCol <= sc)
                    break;
            }
        }
        else if (event.action == ScrollAction.pageDown)
        {
            int prevCol = lastScrollCol;
            while (scrollCol < prevCol)
            {
                if (!scrollBy(1, 0))
                    break;
            }
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

    /// Process vertical scrollbar event
    override void onVScroll(ScrollEvent event)
    {
        // scroll w/o changing selection
        if (event.action == ScrollAction.sliderMoved || event.action == ScrollAction.sliderReleased)
        {
            scrollTo(_scrollPos.x, event.position);
        }
        else if (event.action == ScrollAction.pageUp)
        {
            // scroll up line by line
            int sr = scrollRow;
            while (scrollRow > nonScrollRows)
            {
                scrollBy(0, -1);
                if (lastScrollRow <= sr)
                    break;
            }
        }
        else if (event.action == ScrollAction.pageDown)
        {
            int prevRow = lastScrollRow;
            while (scrollRow < prevRow)
            {
                if (!scrollBy(0, 1))
                    break;
            }
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
    void makeCellVisible(int col, int row)
    {
        if (_changedSize)
            updateCumulativeSizes();
        bool scrolled = false;
        Point newpos = _scrollPos;
        Rect rc = Rect(cellBoxNoScroll(col, row));
        Size skip = nonScrollAreaPixels;
        Rect visibleRc = Rect(_scrollPos.x + skip.w, _scrollPos.y + skip.h,
                              _scrollPos.x + _clientBox.w, _scrollPos.y + _clientBox.h);
        if (col >= nonScrollCols)
        {
            // can scroll X
            if (rc.left < visibleRc.left)
            {
                // scroll left
                newpos.x += rc.left - visibleRc.left;
            }
            else if (rc.right > visibleRc.right)
            {
                // scroll right
                newpos.x += rc.right - visibleRc.right;
            }
        }
        if (row >= nonScrollRows)
        {
            // can scroll Y
            if (rc.top < visibleRc.top)
            {
                // scroll left
                newpos.y += rc.top - visibleRc.top;
            }
            else if (rc.bottom > visibleRc.bottom)
            {
                // scroll right
                newpos.y += rc.bottom - visibleRc.bottom;
            }
        }
        newpos.x = max(newpos.x, 0);
        newpos.y = max(newpos.y, 0);
        if (newpos != _scrollPos)
        {
            scrollTo(newpos.x, newpos.y);
        }
    }

    private Point _lastSelectedCell;

    bool multiSelectCell(int col, int row, bool expandExisting = false)
    {
        if (_col == col && _row == row && !expandExisting)
            return false; // same position
        if (col < _headerCols || row < _headerRows || col >= _cols || row >= _rows)
            return false; // out of range
        if (_changedSize)
            updateCumulativeSizes();
        _lastSelectedCell.x = col;
        _lastSelectedCell.y = row;
        if (_rowSelect)
            col = _headerCols;
        if (expandExisting)
        {
            _selection.clear();
            int startX = _col - _headerCols;
            int startY = _row - headerRows;
            int endX = col - _headerCols;
            int endY = row - headerRows;
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
                    _selection.insert(Point(x, y));
                }
            }
        }
        else
        {
            _selection.insert(Point(col - _headerCols, row - _headerRows));
            _col = col;
            _row = row;
        }
        invalidate();
        makeCellVisible(_lastSelectedCell.x, _lastSelectedCell.y);
        return true;
    }

    /// Move selection to specified cell
    bool selectCell(int col, int row, bool makeVisible = true, GridWidgetBase source = null, bool needNotification = true)
    {
        if (source is null)
            source = this;
        _selection.clear();
        if (_col == col && _row == row)
            return false; // same position
        if (col < _headerCols || row < _headerRows || col >= _cols || row >= _rows)
            return false; // out of range
        if (_changedSize)
            updateCumulativeSizes();
        _col = col;
        _row = row;
        _lastSelectedCell = Point(col, row);
        if (_rowSelect)
        {
            _selection.insert(Point(0, row - _headerRows));
        }
        else
        {
            _selection.insert(Point(col - _headerCols, row - _headerRows));
        }
        invalidate();
        if (makeVisible)
            makeCellVisible(_col, _row);
        if (needNotification && cellSelected.assigned)
            cellSelected(source, _col - _headerCols, _row - _headerRows);
        return true;
    }

    /// Select cell and call onCellActivated handler
    bool activateCell(int col, int row)
    {
        if (_changedSize)
            updateCumulativeSizes();
        if (_col != col || _row != row)
        {
            selectCell(col, row, true);
        }
        cellActivated(this, this.col, this.row);
        return true;
    }

    /// Cell popup menu
    Signal!(Menu delegate(GridWidgetBase, int col, int row)) cellPopupMenuBuilder;

    protected Menu getCellPopupMenu(int col, int row)
    {
        return cellPopupMenuBuilder.assigned ? cellPopupMenuBuilder(this, col, row) : null;
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
        return menu !is null; // TODO
    }

    /// Shows popup menu at (x,y)
    override void showPopupMenu(int xx, int yy)
    {
        int col, row;
        Box b;
        int x = xx - clientBox.x;
        int y = yy - clientBox.y;
        pointToCell(x, y, col, row, b);
        if (auto menu = getCellPopupMenu(col - _headerCols, row - _headerRows))
        {
            import beamui.widgets.popup;

            auto popup = window.showPopup(menu, WeakRef!Widget(this), PopupAlign.point | PopupAlign.right, xx, yy);
            popup.ownContent = false;
        }
    }

    override CursorType getCursorType(int x, int y)
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

    protected int _colResizingIndex = -1;
    protected int _colResizingStartX = -1;
    protected int _colResizingStartWidth = -1;

    protected void startColResize(int col, int x)
    {
        _colResizingIndex = col;
        _colResizingStartX = x;
        _colResizingStartWidth = _colWidths[col];
    }

    protected void processColResize(int x)
    {
        if (_colResizingIndex < 0 || _colResizingIndex >= _cols)
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
    int isColumnResizingPoint(int x, int y)
    {
        if (_changedSize)
            updateCumulativeSizes();
        x -= clientBox.x;
        y -= clientBox.y;
        if (!_headerRows)
            return -1; // no header rows
        if (y >= _rowCumulativeHeights[_headerRows - 1])
            return -1; // not in header row
        // point is somewhere in header row
        int resizeRange = BACKEND_GUI ? 4.pt : 1;
        if (x >= nonScrollAreaPixels.w)
            x += _scrollPos.x;
        int col = colByAbsoluteX(x);
        int start = col > 0 ? _colCumulativeWidths[col - 1] : 0;
        int end = (col < _cols ? _colCumulativeWidths[col] : _colCumulativeWidths[$ - 1]) - 1;
        //Log.d("column range ", start, "..", end, " x=", x);
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

        ACTION_ENTER.bind(this, { cellActivated(this, col, row); });
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
                _scrollPos.x = 0;
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
        if (_scrollPos.y > 0)
        {
            _scrollPos.y = 0;
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
                _scrollPos.x = 0;
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
        if (_scrollPos.y > 0)
        {
            _scrollPos.y = 0;
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
                _selection.insert(Point(x, y));
            }
        }
        invalidate();
    }

    //===============================================================
    // Events

    /// Grid navigation using keys
    override bool onKeyEvent(KeyEvent event)
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
            bool shiftPressed = !!(event.flags & KeyFlag.shift);
            /// Move or expand selection left
            if (event.keyCode == KeyCode.left)
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
            /// Move or expand selection right
            if (event.keyCode == KeyCode.right)
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
            /// Move or expand selection up
            if (event.keyCode == KeyCode.up)
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
            /// Move or expand selection down
            if (event.keyCode == KeyCode.down)
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
        return super.onKeyEvent(event);
    }

    /// Handle mouse wheel events
    override bool onMouseEvent(MouseEvent event)
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
                event.track(this);
                return true;
            }
            if (cellFound && normalCell)
            {
                if (c == _col && r == _row && event.doubleClick)
                {
                    activateCell(c, r);
                }
                else if (_multiSelect && (event.flags & (MouseFlag.shift | MouseFlag.control)) != 0)
                {
                    multiSelectCell(c, r, (event.flags & MouseFlag.shift) != 0);
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
                headerCellClicked(this, c, r);
            }
        }
        if (event.action == MouseAction.move && (event.flags & MouseFlag.lbutton))
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
        if (event.action == MouseAction.wheel)
        {
            if (event.flags & MouseFlag.shift)
                scrollBy(-cast(int)event.wheelDelta, 0);
            else
                scrollBy(0, -cast(int)event.wheelDelta);
            return true;
        }
        return super.onMouseEvent(event);
    }

    //===============================================================

    override Size fullContentSize()
    {
        Size sz;
        foreach (i; 0 .. _cols)
            sz.w += _colWidths[i];
        foreach (i; 0 .. _rows)
            sz.h += _rowHeights[i];
        return sz;
    }

    protected int _minVisibleCols = 2;
    protected int _minVisibleRows = 2;

    /// Returns number of columns from 0 that are taken to measure minimum visible width
    @property int minVisibleCols()
    {
        return _minVisibleCols;
    }

    /// Set number of columns from 0 that are taken to measure minimum visible width
    @property void minVisibleCols(int newMinVisibleCols)
    {
        _minVisibleCols = newMinVisibleCols;
        requestLayout();
    }

    /// Returns number of rows from 0 that are taken to measure minimum visible height
    @property int minVisibleRows()
    {
        return _minVisibleRows;
    }

    /// Set number of rows from 0 that are taken to measure minimum visible height, if there are too little rows last row height is multiplied
    @property void minVisibleRows(int newMinVisibleRows)
    {
        _minVisibleRows = newMinVisibleRows;
        requestLayout();
    }

    override Size computeMinSize()
    {
        if (_cols == 0 || _rows == 0)
        {
            return Size(100, 100);
        }

        Size sz;
        // width
        int firstVisibleCol = showRowHeaders ? 0 : _headerCols;
        for (int i = firstVisibleCol; i < min(_cols, _minVisibleCols + firstVisibleCol); i++)
            sz.w += _colWidths[i];

        // height
        int firstVisibleRow = showColHeaders ? 0 : _headerRows;
        for (int i = firstVisibleRow; i < min(_rows, _minVisibleRows + firstVisibleRow); i++)
            sz.h += _rowHeights[i];

        if (_rows < _minVisibleRows)
            sz.h += (_minVisibleRows - _rows) * _rowHeights[_rows - 1];

        return sz;
    }

    protected Size measureCell(int x, int y)
    {
        // override it!
        return Size(BACKEND_CONSOLE ? 5 : 80, BACKEND_CONSOLE ? 1 : 20);
    }

    protected int measureColWidth(int x)
    {
        if (!showRowHeaders && x < _headerCols)
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

    protected int measureRowHeight(int y)
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

    /// Extend specified column width to fit client area if grid width
    void fillColumnWidth(int colIndex)
    {
        int w = clientBox.width;
        int totalw = 0;
        foreach (i; 0 .. _cols)
            totalw += _colWidths[i];
        if (w > totalw)
            _colWidths[colIndex + _headerCols] += w - totalw;
        _changedSize = true;
        invalidate();
    }

    void autoFitColumnWidths()
    {
        foreach (i; 0 .. _cols)
            autoFitColumnWidth(i);
        _changedSize = true;
        invalidate();
    }

    void autoFitColumnWidth(int i)
    {
        _colWidths[i] = (i < _headerCols && !_showRowHeaders) ? 0 :
                measureColWidth(i) + (BACKEND_CONSOLE ? 1 : 3.pt);
        _changedSize = true;
    }

    void autoFitRowHeights()
    {
        foreach (i; 0 .. _rows)
            autoFitRowHeight(i);
    }

    void autoFitRowHeight(int i)
    {
        _rowHeights[i] = (i < _headerRows && !_showColHeaders) ? 0 : measureRowHeight(i) + (BACKEND_CONSOLE ? 0 : 2);
        _changedSize = true;
    }

    void autoFit()
    {
        autoFitColumnWidths();
        autoFitRowHeights();
        updateCumulativeSizes();
    }

    override protected void drawClient(DrawBuf buf)
    {
        if (!_cols || !_rows)
            return; // no cells
        auto saver = ClipRectSaver(buf, clientBox, 0);

        int nscols = nonScrollCols;
        int nsrows = nonScrollRows;
        Size nspixels = nonScrollAreaPixels;
        int maxVisibleCol = colByAbsoluteX(clientBox.width + _scrollPos.x);
        int maxVisibleRow = rowByAbsoluteY(clientBox.height + _scrollPos.y);
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
    abstract dstring cellText(int col, int row);
    /// Set cell text
    abstract StringGridWidgetBase setCellText(int col, int row, dstring text);
    /// Returns row header title
    abstract dstring rowTitle(int row);
    /// Set row header title
    abstract StringGridWidgetBase setRowTitle(int row, dstring title);
    /// Returns row header title
    abstract dstring colTitle(int col);
    /// Set col header title
    abstract StringGridWidgetBase setColTitle(int col, dstring title);
}

/**
    Grid view with string data shown. All rows are of the same height
*/
class StringGridWidget : StringGridWidgetBase
{
    protected
    {
        dstring[][] _data;
        dstring[] _rowTitles;
        dstring[] _colTitles;
    }

    this()
    {
        onThemeChanged();
    }

    /// Get cell text
    override dstring cellText(int col, int row)
    {
        if (col >= 0 && col < cols && row >= 0 && row < rows)
            return _data[row][col];
        return ""d;
    }

    /// Set cell text
    override StringGridWidgetBase setCellText(int col, int row, dstring text)
    {
        if (col >= 0 && col < cols && row >= 0 && row < rows)
            _data[row][col] = text;
        return this;
    }

    /// Set new size
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

    /// Returns row header title
    override dstring rowTitle(int row)
    {
        return _rowTitles[row];
    }
    /// Set row header title
    override StringGridWidgetBase setRowTitle(int row, dstring title)
    {
        _rowTitles[row] = title;
        return this;
    }

    /// Returns row header title
    override dstring colTitle(int col)
    {
        return _colTitles[col];
    }

    /// Set col header title
    override StringGridWidgetBase setColTitle(int col, dstring title)
    {
        _colTitles[col] = title;
        return this;
    }

    override protected Size measureCell(int x, int y)
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
        FontRef fnt = font;
        Size sz = fnt.textSize(txt);
        sz.h = max(sz.h, fnt.height);
        return sz;
    }

    /// Draw cell content
    override protected void drawCell(DrawBuf buf, Box b, int col, int row)
    {
        if (_customCellAdapter && _customCellAdapter.isCustomCell(col, row))
        {
            return _customCellAdapter.drawCell(buf, b, col, row);
        }
        if (BACKEND_GUI)
            b.shrink(RectOffset(2, 1));
        else
            b.width--;
        FontRef fnt = font;
        dstring txt = cellText(col, row);
        Size sz = fnt.textSize(txt);
        Align ha = Align.left;
        //if (sz.h < b.h)
        //    applyAlign(b, sz, ha, Align.vcenter);
        int offset = BACKEND_CONSOLE ? 0 : 1;
        fnt.drawText(buf, b.x + offset, b.y + offset, txt, textColor);
    }

    /// Draw cell content
    override protected void drawHeaderCell(DrawBuf buf, Box b, int col, int row)
    {
        if (BACKEND_GUI)
            b.shrink(RectOffset(2, 1));
        else
            b.width--;
        FontRef fnt = font;
        dstring txt;
        if (row < 0 && col >= 0)
            txt = colTitle(col);
        else if (row >= 0 && col < 0)
            txt = rowTitle(row);
        if (!txt.length)
            return;
        Size sz = fnt.textSize(txt);
        Align ha = Align.left;
        if (col < 0)
            ha = Align.right;
        //if (row < 0)
        //    ha = Align.hcenter;
        applyAlign(b, sz, ha, Align.vcenter);
        int offset = BACKEND_CONSOLE ? 0 : 1;
        uint cl = textColor;
        cl = currentTheme.getColor("grid_cell_text_header", cl);
        fnt.drawText(buf, b.x + offset, b.y + offset, txt, cl);
    }

    /// Draw cell background
    override protected void drawHeaderCellBackground(DrawBuf buf, Box b, int c, int r)
    {
        bool selectedCol = (c == col) && !_rowSelect;
        bool selectedRow = r == row;
        bool selectedCell = selectedCol && selectedRow;
        if (_rowSelect && selectedRow)
            selectedCell = true;
        if (!selectedCell && _multiSelect)
        {
            selectedCell = Point(c, r) in _selection || (_rowSelect && Point(0, r) in _selection);
        }
        // draw header cell background
        DrawableRef dw = c < 0 ? _cellRowHeaderBackgroundDrawable : _cellHeaderBackgroundDrawable;
        uint cl = _cellHeaderBackgroundColor;
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
            uint borderColor = _cellHeaderBorderColor;
            // vertical
            buf.drawLine(Point(rc.right, rc.bottom), Point(rc.right, rc.top), _cellHeaderBorderColor);
            // horizontal
            buf.drawLine(Point(rc.left, rc.bottom), Point(rc.right, rc.bottom), _cellHeaderBorderColor);
        }
    }

    /// Draw cell background
    override protected void drawCellBackground(DrawBuf buf, Box b, int c, int r)
    {
        bool selectedCol = c == col;
        bool selectedRow = r == row;
        bool selectedCell = selectedCol && selectedRow;
        if (_rowSelect && selectedRow)
            selectedCell = true;
        if (!selectedCell && _multiSelect)
        {
            selectedCell = Point(c, r) in _selection || (_rowSelect && Point(0, r) in _selection);
        }

        Rect rc = b;
        uint borderColor = _cellBorderColor;
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
                    buf.drawFrame(rc, _selectionColorRowSelect, RectOffset(0, 1), _cellBorderColor);
                else
                    buf.drawFrame(rc, _selectionColor, RectOffset(1), _cellBorderColor);
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

    override void onThemeChanged()
    {
        super.onThemeChanged();
        _selectionColor = currentTheme.getColor("grid_selection", 0x804040FF);
        _selectionColorRowSelect = currentTheme.getColor("grid_selection_row", 0xC0A0B0FF);
        _fixedCellBackgroundColor = currentTheme.getColor("grid_cell_background_fixed", 0xC0E0E0E0);
        _cellBorderColor = currentTheme.getColor("grid_cell_border", 0xC0C0C0C0);
        _fixedCellBorderColor = currentTheme.getColor("grid_cell_border_fixed", _cellBorderColor);
        _cellHeaderBorderColor = currentTheme.getColor("grid_cell_border_header", 0xC0202020);
        _cellHeaderBackgroundColor = currentTheme.getColor("grid_cell_background_header", 0xC0909090);
        _cellHeaderSelectedBackgroundColor = currentTheme.getColor("grid_cell_background_header_selected", 0x80FFC040);
        _cellHeaderBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_header");
        _cellHeaderSelectedBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_header_selected");
        _cellRowHeaderBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_row_header");
        _cellRowHeaderSelectedBackgroundDrawable = currentTheme.getDrawable("grid_cell_background_row_header_selected");
    }
}
