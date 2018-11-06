/**
This module contains FileDialog implementation.

Can show dialog for open / save.


Synopsis:
---
import beamui.dialogs.filedlg;

auto dlg = new FileDialog(tr("Open File"), window, FileDialogFlag.open);
dlg.show();
---

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.filedlg;

import std.array : empty;
import std.file;
import std.path;
import beamui.core.files;
import beamui.core.functions;
import beamui.core.i18n;
import beamui.core.stdaction;
import beamui.dialogs.dialog;
import beamui.widgets.combobox;
import beamui.widgets.controls;
import beamui.widgets.editors;
import beamui.widgets.grid;
import beamui.widgets.layouts;
import beamui.widgets.lists;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.platforms.common.platform;

/// Flags for file dialog options
enum FileDialogFlag : uint
{
    /// File must exist (use this for open dialog)
    fileMustExist = 0x100,
    /// Ask before saving to existing
    confirmOverwrite = 0x200,
    /// Select directory, not file
    selectDirectory = 0x400,
    /// Show Create Directory button
    enableCreateDirectory = 0x800,
    /// Flags for Open dialog
    open = fileMustExist | enableCreateDirectory,
    /// Flags for Save dialog
    save = confirmOverwrite | enableCreateDirectory,
}

/// File dialog action codes
enum FileDialogActions
{
    showInFileManager = 4000,
    createDirectory = 4001,
    deleteFile = 4002,
}

/// Filetype filter entry for FileDialog
struct FileFilterEntry
{
    dstring label;
    string[] filter;
    bool executableOnly;

    this(dstring displayLabel, string filterList, bool executableOnly = false)
    {
        import std.string : split;

        label = displayLabel;
        if (filterList.length)
            filter = filterList.split(';');
        this.executableOnly = executableOnly;
    }
}

/// Sorting orders for file dialog items
enum FileListSortOrder
{
    name,
    nameDesc,
    size,
    sizeDesc,
    timestamp,
    timestampDesc,
}

/// File open / save dialog
class FileDialog : Dialog, CustomGridCellAdapter
{
    @property
    {
        /// Mapping of file extension to icon resource name, e.g. ".txt": "text-plain"
        ref string[string] filetypeIcons() { return _filetypeIcons; }

        /// Filter list for file type filter combo box
        FileFilterEntry[] filters() { return _filters; }
        /// ditto
        void filters(FileFilterEntry[] values)
        {
            _filters = values;
        }

        /// Filter index
        int filterIndex() const { return _filterIndex; }
        /// ditto
        void filterIndex(int index)
        {
            _filterIndex = index;
        }

        /// The path to the directory whose files should be displayed
        string path() const { return _path; }
        /// ditto
        void path(string s)
        {
            _path = s;
        }

        /// The name of the file or directory that is currently selected
        string filename() const { return _filename; }
        /// ditto
        void filename(string s)
        {
            _filename = s;
        }

        /// All the selected filenames
        string[] filenames()
        {
            string[] res;
            res.reserve(_fileList.selection.length);
            int i = 0;
            foreach (val; _fileList.selection)
            {
                res ~= _entries[val.y];
                ++i;
            }
            return res;
        }

        bool showHiddenFiles() const { return _showHiddenFiles; }

        void showHiddenFiles(bool b)
        {
            _showHiddenFiles = b;
        }

        bool allowMultipleFiles() const { return _allowMultipleFiles; }

        void allowMultipleFiles(bool b)
        {
            _allowMultipleFiles = b;
        }

        /// Currently selected filter value - array of patterns like ["*.txt", "*.rtf"]
        const(string[]) selectedFilter() const
        {
            if (_filterIndex >= 0 && _filterIndex < _filters.length)
                return _filters[_filterIndex].filter;
            return null;
        }
        /// ditto
        bool executableFilterSelected() const
        {
            if (_filterIndex >= 0 && _filterIndex < _filters.length)
                return _filters[_filterIndex].executableOnly;
            return false;
        }
    }

    private
    {
        FilePathPanel _edPath;
        EditLine _edFilename;
        ComboBox _cbFilters;
        StringGridWidget _fileList;
        FileListSortOrder _sortOrder = FileListSortOrder.name;
        Widget leftPanel;
        Column rightPanel;

        Action _action;

        RootEntry[] _roots;
        FileFilterEntry[] _filters;
        int _filterIndex;
        string _path;
        string _filename;
        DirEntry[] _entries;
        bool _isRoot;

        bool _isOpenDialog;

        bool _showHiddenFiles;
        bool _allowMultipleFiles;

        string[string] _filetypeIcons;

        TextTypingShortcutHelper _shortcutHelper;
    }

    this(dstring caption, Window parent, Action action = null,
            uint fileDialogFlags = DialogFlag.modal | DialogFlag.resizable | FileDialogFlag.fileMustExist)
    {
        super(caption, parent, fileDialogFlags |
            (platform.uiDialogDisplayMode & DialogDisplayMode.fileDialogInPopup ? DialogFlag.popup : 0));
        _isOpenDialog = !(_flags & FileDialogFlag.confirmOverwrite);
        if (action is null)
        {
            if (fileDialogFlags & FileDialogFlag.selectDirectory)
                action = ACTION_OPEN_DIRECTORY;
            else if (_isOpenDialog)
                action = ACTION_OPEN;
            else
                action = ACTION_SAVE;
        }
        _action = action;
    }

    /// Add new filter entry
    void addFilter(FileFilterEntry value)
    {
        _filters ~= value;
    }

    protected bool upLevel()
    {
        return openDirectory(parentDir(_path), _path);
    }

    protected bool reopenDirectory()
    {
        return openDirectory(_path, null);
    }

    protected void locateFileInList(dstring pattern)
    {
        if (!pattern.length)
            return;
        int selection = max(_fileList.row, 0);
        int index = -1; // first matched item
        string mask = pattern.toUTF8;
        // search forward from current row to end of list
        for (int i = selection; i < _entries.length; i++)
        {
            string fname = baseName(_entries[i].name);
            if (fname.startsWith(mask))
            {
                index = i;
                break;
            }
        }
        if (index < 0)
        {
            // search from beginning of list to current position
            for (int i = 0; i < selection && i < _entries.length; i++)
            {
                string fname = baseName(_entries[i].name);
                if (fname.startsWith(mask))
                {
                    index = i;
                    break;
                }
            }
        }
        if (index >= 0)
        {
            // move selection
            _fileList.selectCell(1, index + 1);
            window.update();
        }
    }

    /// Change sort order after clicking on column col
    protected void changeSortOrder(int col)
    {
        assert(col >= 2 && col <= 4);
        // 2=NAME, 3=SIZE, 4=MODIFIED
        col -= 2;
        int n = col * 2;
        if ((n & 0xFE) == ((cast(int)_sortOrder) & 0xFE))
        {
            // invert DESC / ASC if clicked same column as in current sorting order
            _sortOrder = cast(FileListSortOrder)(_sortOrder ^ 1);
        }
        else
        {
            _sortOrder = cast(FileListSortOrder)n;
        }
        string selectedItemPath;
        int currentRow = _fileList.row;
        if (currentRow >= 0 && currentRow < _entries.length)
        {
            selectedItemPath = _entries[currentRow].name;
        }
        updateColumnHeaders();
        sortEntries();
        entriesToCells(selectedItemPath);
        requestLayout();
        if (window)
            window.update();
    }

    /// Predicate for sorting items - NAME
    static bool compareItemsByName(ref DirEntry item1, ref DirEntry item2)
    {
        return item1.isDir && !item2.isDir || item1.isDir == item2.isDir && item1.name < item2.name;
    }
    /// Predicate for sorting items - NAME DESC
    static bool compareItemsByNameDesc(ref DirEntry item1, ref DirEntry item2)
    {
        return item1.isDir && !item2.isDir || item1.isDir == item2.isDir && item1.name > item2.name;
    }
    /// Predicate for sorting items - SIZE
    static bool compareItemsBySize(ref DirEntry item1, ref DirEntry item2)
    {
        return item1.isDir && !item2.isDir || item1.isDir && item2.isDir &&
               item1.name < item2.name || !item1.isDir && !item2.isDir && item1.size < item2.size;
    }
    /// Predicate for sorting items - SIZE DESC
    static bool compareItemsBySizeDesc(ref DirEntry item1, ref DirEntry item2)
    {
        return item1.isDir && !item2.isDir || item1.isDir && item2.isDir &&
               item1.name < item2.name || !item1.isDir && !item2.isDir && item1.size > item2.size;
    }
    /// Predicate for sorting items - TIMESTAMP
    static bool compareItemsByTimestamp(ref DirEntry item1, ref DirEntry item2)
    {
        try
        {
            return item1.timeLastModified < item2.timeLastModified;
        }
        catch (Exception e)
        {
            return false;
        }
    }
    /// Predicate for sorting items - TIMESTAMP DESC
    static bool compareItemsByTimestampDesc(ref DirEntry item1, ref DirEntry item2)
    {
        try
        {
            return item1.timeLastModified > item2.timeLastModified;
        }
        catch (Exception e)
        {
            return false;
        }
    }

    /// Sort entries according to _sortOrder
    protected void sortEntries()
    {
        if (_entries.length < 1)
            return;
        DirEntry[] entriesToSort = _entries[0 .. $];
        if (_entries.length > 0)
        {
            string fname = baseName(_entries[0].name);
            if (fname == "..")
            {
                entriesToSort = _entries[1 .. $];
            }
        }

        switch (_sortOrder) with (FileListSortOrder)
        {
        default:
        case name:
            sort!compareItemsByName(entriesToSort);
            break;
        case nameDesc:
            sort!compareItemsByNameDesc(entriesToSort);
            break;
        case size:
            sort!compareItemsBySize(entriesToSort);
            break;
        case sizeDesc:
            sort!compareItemsBySizeDesc(entriesToSort);
            break;
        case timestamp:
            sort!compareItemsByTimestamp(entriesToSort);
            break;
        case timestampDesc:
            sort!compareItemsByTimestampDesc(entriesToSort);
            break;
        }
    }

    protected string formatTimestamp(ref DirEntry f)
    {
        import std.datetime : SysTime;
        import std.typecons : Nullable;

        Nullable!SysTime ts;
        try
        {
            ts = f.timeLastModified;
        }
        catch (Exception e)
        {
            Log.w(e.msg);
        }
        if (ts.isNull)
        {
            return "----.--.-- --:--";
        }
        else
        {
            //date = "%04d.%02d.%02d %02d:%02d:%02d".format(ts.year, ts.month, ts.day, ts.hour, ts.minute, ts.second);
            return "%04d.%02d.%02d %02d:%02d".format(ts.year, ts.month, ts.day, ts.hour, ts.minute);
        }
    }

    protected int entriesToCells(string selectedItemPath)
    {
        _fileList.rows = cast(int)_entries.length;
        int selectionIndex = -1;
        for (int i = 0; i < _entries.length; i++)
        {
            if (_entries[i].name == selectedItemPath)
                selectionIndex = i;
            string fname = baseName(_entries[i].name);
            string sz;
            string date;
            bool d = _entries[i].isDir;
            _fileList.setCellText(1, i, toUTF32(fname));
            if (d)
            {
                _fileList.setCellText(0, i, "folder");
                if (fname != "..")
                    date = formatTimestamp(_entries[i]);
            }
            else
            {
                string ext = extension(fname);
                string resname;
                if (ext in _filetypeIcons)
                    resname = _filetypeIcons[ext];
                else if (baseName(fname) in _filetypeIcons)
                    resname = _filetypeIcons[baseName(fname)];
                else
                    resname = "text-plain";
                _fileList.setCellText(0, i, toUTF32(resname));
                double size = double.nan;
                try
                {
                    size = _entries[i].size;
                }
                catch (Exception e)
                {
                    Log.w(e.msg);
                }
                import std.math : isNaN;

                if (size.isNaN)
                    sz = "--";
                else
                {
                    sz = size < 1024 ? to!string(size) ~ " B" : (size < 1024 * 1024 ?
                            "%.1f".format(size / 1024) ~ " KB" : (size < 1024 * 1024 * 1024 ?
                            "%.1f".format(size / (1024 * 1024)) ~ " MB" :
                            "%.1f".format(size / (1024 * 1024 * 1024)) ~ " GB"));
                }
                date = formatTimestamp(_entries[i]);
            }
            _fileList.setCellText(2, i, toUTF32(sz));
            _fileList.setCellText(3, i, toUTF32(date));
        }
        if (_fileList.box.height > 0)
            _fileList.scrollTo(0, 0);

        autofitGrid();
        if (selectionIndex >= 0)
            _fileList.selectCell(1, selectionIndex + 1, true);
        else if (_entries.length > 0)
            _fileList.selectCell(1, 1, true);
        return selectionIndex;
    }

    protected bool openDirectory(string dir, string selectedItemPath)
    {
        dir = buildNormalizedPath(dir);
        Log.d("FileDialog.openDirectory(", dir, ")");
        DirEntry[] entries;

        auto attrFilter = (showHiddenFiles ? AttrFilter.all : AttrFilter.allVisible) |
            AttrFilter.special | AttrFilter.parent;
        if (executableFilterSelected())
        {
            attrFilter |= AttrFilter.executable;
        }
        try
        {
            _entries = listDirectory(dir, attrFilter, selectedFilter());
        }
        catch (Exception e)
        {
            Log.e("Cannot list directory " ~ dir, e);
            //import beamui.dialogs.msgbox;
            //auto msgBox = new MessageBox(tr("Error"), e.msg.toUTF32, window());
            //msgBox.show();
            //return false;
            // show empty dir if failed to read
        }
        _fileList.rows = 0;
        _path = dir;
        _isRoot = isRoot(dir);
        _edPath.path = _path; //toUTF32(_path);
        int selectionIndex = entriesToCells(selectedItemPath);
        return true;
    }

    void autofitGrid()
    {
        _fileList.autoFitColumnWidths();
        _fileList.fillColumnWidth(1);
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (event.action == KeyAction.keyDown)
        {
            if (event.keyCode == KeyCode.backspace && event.flags == 0)
            {
                upLevel();
                return true;
            }
        }
        return super.onKeyEvent(event);
    }

    override bool isCustomCell(int col, int row)
    {
        return (col == 0 || col == 1) && row >= 0;
    }

    protected DrawableRef rowIcon(int row)
    {
        string iconID = toUTF8(_fileList.cellText(0, row));
        DrawableRef res;
        if (iconID.length)
        {
            auto img = imageCache.get(iconID);
            if (!img.isNull)
                res = new ImageDrawable(img); // TODO: reduce allocations
        }
        return res;
    }

    override Size measureCell(int col, int row)
    {
        if (col == 1)
        {
            FontRef fnt = _fileList.font;
            dstring txt = _fileList.cellText(col, row);
            Size sz = fnt.textSize(txt);
            sz.h = max(sz.h, fnt.height);
            return sz;
        }
        if (BACKEND_CONSOLE)
            return Size(0, 0);
        else
        {
            DrawableRef icon = rowIcon(row);
            if (icon.isNull)
                return Size(0, 0);
            return Size(icon.width + 2.pt, icon.height + 2.pt);
        }
    }

    override void drawCell(DrawBuf buf, Box b, int col, int row)
    {
        if (col == 1)
        {
            if (BACKEND_GUI)
                b.shrink(Insets(1, 2));
            else
                b.width--;
            FontRef fnt = _fileList.font;
            dstring txt = _fileList.cellText(col, row);
            Size sz = fnt.textSize(txt);
            Align ha = Align.left;
            //if (sz.h < b.h)
            //    applyAlign(b, sz, ha, Align.vcenter);
            int offset = BACKEND_CONSOLE ? 0 : 1;
            Color cl = _fileList.textColor;
            if (_entries[row].isDir)
                cl = currentTheme.getColor("file_dialog_dir_name", cl);
            fnt.drawText(buf, b.x + offset, b.y + offset, txt, cl);
            return;
        }
        DrawableRef img = rowIcon(row);
        if (!img.isNull)
        {
            Size sz = Size(img.width, img.height);
            applyAlign(b, sz, Align.hcenter, Align.vcenter);
            img.drawTo(buf, b);
        }
    }

    protected ListWidget createRootsList()
    {
        auto res = new ListWidget;
        auto adapter = new WidgetListAdapter;
        foreach (ref RootEntry root; _roots)
        {
            auto btn = new Button(root.label, root.icon);
            btn.orientation = Orientation.vertical;
            btn.style = "flat";
            btn.focusable = false;
            btn.tooltipText = root.path.toUTF32;
            adapter.add(btn);
        }
        res.ownAdapter = adapter;
        res.itemClicked = delegate(Widget source, int itemIndex) {
            openDirectory(_roots[itemIndex].path, null);
            res.selectItem(-1);
        };
        res.focusable = true;
        return res;
    }

    /// File list item activated (double clicked or Enter key pressed)
    protected void onItemActivated(int index)
    {
        DirEntry e = _entries[index];
        if (e.isDir)
        {
            openDirectory(e.name, _path);
        }
        else if (e.isFile)
        {
            string fname = e.name;
            _filename = fname;
            if ((_flags & FileDialogFlag.confirmOverwrite) && exists(fname) && isFile(fname))
            {
                showConfirmOverwriteQuestion(fname);
            }
            else
            {
                handleAction(_action);
            }
        }
    }

    /// File list item selected
    protected void onItemSelected(int index)
    {
        DirEntry e = _entries[index];
        string fname = e.name;
        _edFilename.text = toUTF32(baseName(fname));
        _filename = fname;
    }

    protected void createAndEnterDirectory(string name)
    {
        string newdir = buildNormalizedPath(_path, name);
        try
        {
            mkdirRecurse(newdir);
            openDirectory(newdir, null);
        }
        catch (Exception e)
        {
            window.showMessageBox(tr("Cannot create folder"), tr("Folder creation is failed"));
        }
    }

    override void handleAction(const Action action)
    {
        if (action is ACTION_CANCEL)
        {
            close(action);
        }
        if (action is ACTION_CREATE_DIRECTORY)
        {
            // show editor popup
            window.showInputBox(tr("Create new folder"), tr("Input folder name"), ""d, delegate(dstring s) {
                if (!s.empty)
                    createAndEnterDirectory(toUTF8(s));
            });
        }
        if (action is ACTION_OPEN || action is ACTION_OPEN_DIRECTORY || action is ACTION_SAVE)
        {
            auto baseFilename = toUTF8(_edFilename.text);
            if (action is ACTION_OPEN_DIRECTORY)
                _filename = _path ~ dirSeparator;
            else
                _filename = _path ~ dirSeparator ~ baseFilename;

            if (action !is ACTION_OPEN_DIRECTORY && exists(_filename) && isDir(_filename))
            {
                // directory name in _edFileName.text but we need file so open directory
                openDirectory(_filename, null);
            }
            else if (baseFilename.length > 0)
            {
                // success if either selected dir & has to open dir or if selected file
                if (action is ACTION_OPEN_DIRECTORY && exists(_filename) && isDir(_filename))
                {
                    close(_action);
                }
                else if (action is ACTION_SAVE && !(_flags & FileDialogFlag.fileMustExist))
                {
                    // save dialog
                    if ((_flags & FileDialogFlag.confirmOverwrite) && exists(_filename) && isFile(_filename))
                    {
                        showConfirmOverwriteQuestion(_filename);
                    }
                    else
                    {
                        close(_action);
                    }
                }
                else if (!(_flags & FileDialogFlag.fileMustExist) || exists(_filename) && isFile(_filename))
                {
                    // open dialog
                    close(_action);
                }
            }
        }
    }

    /// Shows question "override file?"
    protected void showConfirmOverwriteQuestion(string filename)
    {
        window.showMessageBox(tr("Confirm overwrite"),
            format(tr("A file named \"%s\" already exists. Do you want to replace it?"), baseName(filename)),
            [ACTION_YES, ACTION_NO], 1,
            delegate(const Action a) { if (a is ACTION_YES) handleAction(_action); }
        );
    }

    bool onPathSelected(string path)
    {
        return openDirectory(path, null);
    }

    protected Menu getCellPopupMenu(GridWidgetBase source, int col, int row)
    {
        if (row >= 0 && row < _entries.length)
        {
            Menu menu = new Menu;
            DirEntry e = _entries[row];
            // show in explorer action
            menu.addAction(tr("Show in file manager"))
                .bind(this, { platform.showInFileManager(e.name); });
            // create directory action
//             if (_flags & FileDialogFlag.enableCreateDirectory)
//                 menu.add(ACTION_CREATE_DIRECTORY); // TODO

            if (e.isDir)
            {
                //_edFilename.text = ""d;
                //_filename = "";
            }
            else if (e.isFile)
            {
                //string fname = e.name;
                //_edFilename.text = toUTF32(baseName(fname));
                //_filename = fname;
            }
            return menu;
        }
        return null;
    }

    override void initialize()
    {
        // remember filename specified by user, file grid initialization can change it
        string defaultFilename = _filename;

        _roots = getRootPaths() ~ getBookmarkPaths();

        minWidth(BACKEND_CONSOLE ? 50 : 600).minHeight(400); // TODO: move in styles

        auto content = new Row(1.pt);
        content.id = "dlgcontent";

        leftPanel = createRootsList();
        leftPanel.id = "leftPanel";
        leftPanel.minWidth = BACKEND_CONSOLE ? 7 : 40.pt;

        rightPanel = new Column;
        rightPanel.id = "rightPanel";
        rightPanel.addChild(new Label(tr("Path") ~ ":"));

        content.add(leftPanel);
        content.addResizer();
        content.add(rightPanel).fillWidth(true);

        _edPath = new FilePathPanel;
        _edPath.id = "path";
        _edPath.pathSelected = &onPathSelected;
        _edFilename = new EditLine;
        _edFilename.id = "filename";
        _edFilename.setDefaultPopupMenu();
        if (_flags & FileDialogFlag.selectDirectory)
        {
            _edFilename.visibility = Visibility.gone;
        }

        _fileList = new StringGridWidget;
        _fileList.id = "files";
        _fileList.bindSubItem(this, "grid");
        _fileList.fullColumnOnLeft(false);
        _fileList.fullRowOnTop(false);
        _fileList.resize(4, 3);
        _fileList.setColTitle(0, " "d);
        updateColumnHeaders();
        _fileList.showRowHeaders = false;
        _fileList.rowSelect = true;
        _fileList.multiSelect = _allowMultipleFiles;
        _fileList.cellPopupMenuBuilder = &getCellPopupMenu;
        _fileList.minVisibleRows = 10;
        _fileList.minVisibleCols = 4;
        _fileList.headerCellClicked = &onHeaderCellClicked;

        _fileList.keyEvent = delegate(Widget source, KeyEvent event) {
            if (_shortcutHelper.onKeyEvent(event))
                locateFileInList(_shortcutHelper.text);
            return false;
        };

        rightPanel.add(_edPath);
        rightPanel.add(_fileList).fillHeight(true);
        rightPanel.add(_edFilename);

        if (_filters.length)
        {
            dstring[] filterLabels;
            foreach (f; _filters)
                filterLabels ~= f.label;
            _cbFilters = new ComboBox(filterLabels);
            _cbFilters.id = "filter";
            _cbFilters.selectedItemIndex = _filterIndex;
            _cbFilters.itemSelected = delegate(Widget source, int itemIndex) {
                _filterIndex = itemIndex;
                reopenDirectory();
            };
            rightPanel.add(_cbFilters);
        }

        add(content).fillHeight(true);
        if (_flags & FileDialogFlag.enableCreateDirectory)
        {
            add(createButtonsPanel([ACTION_CREATE_DIRECTORY, _action, ACTION_CANCEL], 1, 1));
        }
        else
        {
            add(createButtonsPanel([_action, ACTION_CANCEL], 0, 0));
        }

        _fileList.customCellAdapter = this;
        _fileList.cellActivated = delegate(GridWidgetBase source, int col, int row) {
            onItemActivated(row);
        };
        _fileList.cellSelected = delegate(GridWidgetBase source, int col, int row) {
            onItemSelected(row);
        };

        if (_path.empty || !_path.exists || !_path.isDir)
        {
            _path = currentDir;
            if (!_path.exists || !_path.isDir)
                _path = homePath;
        }
        openDirectory(_path, _filename);

        // set default file name if specified by user
        if (defaultFilename.length != 0)
            _edFilename.text = toUTF32(baseName(defaultFilename));
    }

    /// Get sort order suffix for column title
    protected dstring appendSortOrderSuffix(dstring columnName, FileListSortOrder arrowUp, FileListSortOrder arrowDown)
    {
        if (_sortOrder == arrowUp)
            return columnName ~ " ▲";
        if (_sortOrder == arrowDown)
            return columnName ~ " ▼";
        return columnName;
    }

    protected void updateColumnHeaders()
    {
        _fileList.setColTitle(1, appendSortOrderSuffix(tr("Name"),
                FileListSortOrder.nameDesc, FileListSortOrder.name));
        _fileList.setColTitle(2, appendSortOrderSuffix(tr("Size"),
                FileListSortOrder.sizeDesc, FileListSortOrder.size));
        _fileList.setColTitle(3, appendSortOrderSuffix(tr("Modified"),
                FileListSortOrder.timestampDesc, FileListSortOrder.timestamp));
    }

    protected void onHeaderCellClicked(GridWidgetBase source, int col, int row)
    {
        debug Log.d("onHeaderCellClicked col=", col, " row=", row);
        if (row == 0 && col >= 2 && col <= 4)
        {
            // 2=NAME, 3=SIZE, 4=MODIFIED
            changeSortOrder(col);
        }
    }

    override protected void onShow()
    {
        _fileList.setFocus();
    }

    override void layout(Box geom)
    {
        super.layout(geom);
        autofitGrid();
    }
}

alias onPathSelectionHandler = bool delegate(string path);

class FilePathPanelItem : Row
{
    Listener!onPathSelectionHandler pathSelected;

    private
    {
        string _path;
        Label _text;
        Button _button;
    }

    this(string path)
    {
        _path = path;
        spacing = 0;
        string fname = isRoot(path) ? path : baseName(path);
        _text = new Label(toUTF32(fname));
        _text.bindSubItem(this, "label");
        _text.trackHover = true;
        _text.clickable = true;
        _text.clicked = &onTextClick;
        _button = new Button(null, "scrollbar_btn_right");
        _button.bindSubItem(this, "button");
        _button.focusable = false;
        _button.clicked = &onButtonClick;
        trackHover = true;
        addChild(_text);
        addChild(_button);
    }

    private void onTextClick(Widget src)
    {
        if (pathSelected.assigned)
            pathSelected(_path);
    }

    private void onButtonClick(Widget src)
    {
        // show popup menu with subdirs
        string[] filters;
        DirEntry[] entries;
        try
        {
            AttrFilter attrFilter = AttrFilter.dirs | AttrFilter.parent;
            entries = listDirectory(_path, attrFilter);
        }
        catch (Exception e)
        {
            return;
        }
        if (entries.length == 0)
            return;

        Menu menu = new Menu;
        foreach (ref DirEntry e; entries)
        {
            () {
                string fullPath = e.name;
                string d = baseName(fullPath);
                menu.addAction(toUTF32(d)).bind(this, {
                    if (pathSelected.assigned)
                        pathSelected(fullPath);
                });
            }();
        }
        auto popup = window.showPopup(menu, WeakRef!Widget(_button), PopupAlign.below);
    }
}

/// Panel with buttons - path segments - for fast navigation to subdirs.
class FilePathPanelButtons : WidgetGroupDefaultDrawing
{
    Listener!onPathSelectionHandler pathSelected;

    private string _path;

    this()
    {
        clickable = true;
    }

    protected void initialize(string path)
    {
        _path = path;
        removeAllChildren();
        string itemPath = path;
        while (true)
        {
            auto item = new FilePathPanelItem(itemPath);
            item.pathSelected = &onPathSelected;
            addChild(item);
            if (isRoot(itemPath))
                break;

            itemPath = parentDir(itemPath);
        }
        itemSizes.length = childCount;
    }

    protected bool onPathSelected(string path)
    {
        return pathSelected.assigned ? pathSelected(path) : false;
    }

    private int[] itemSizes;
    override Boundaries computeBoundaries()
    {
        Boundaries bs;
        Size min;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            item.visibility = Visibility.visible;

            Boundaries wbs = item.computeBoundaries();
            itemSizes[i] = wbs.nat.w;
            if (i == 0)
                min = wbs.min;
            bs.addWidth(wbs);
            bs.maximizeHeight(wbs);
        }
        bs.min = min;
        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
        applyPadding(geom);

        int maxw = geom.w;

        int totalw;
        int visibleItems;
        bool exceeded;
        // update visibility
        foreach (i; 0 .. childCount)
        {
            if (totalw + itemSizes[i] > maxw)
            {
                exceeded = true;
            }
            if (!exceeded || i == 0)
            { // at least one item must be visible
                totalw += itemSizes[i];
                visibleItems++;
            }
            else
            {
                Widget item = child(i);
                item.visibility = Visibility.gone;
            }
        }
        // lay out visible items
        // backward order
        Box ibox = geom;
        for (int i = visibleItems - 1; i >= 0; i--)
        {
            Widget item = child(i);
            if (item.visibility != Visibility.gone)
            {
                ibox.w = itemSizes[i];
                if (i == visibleItems - 1)
                    ibox.w = min(ibox.w, maxw);
                item.layout(ibox);
                ibox.x += ibox.w;
            }
        }
    }
}

/// Panel - either path segment buttons or text editor line
class FilePathPanel : FrameLayout
{
    @property string path() const { return _path; }

    @property void path(string value)
    {
        _segments.initialize(value);
        _edPath.text = toUTF32(value);
        _path = value;
        showChild(ID_SEGMENTS);
    }

    Listener!onPathSelectionHandler pathSelected;

    static const ID_SEGMENTS = "SEGMENTS";
    static const ID_EDITOR = "ED_PATH";

    private
    {
        FilePathPanelButtons _segments;
        EditLine _edPath;
        string _path;
    }

    this()
    {
        _segments = new FilePathPanelButtons;
        _segments.id = ID_SEGMENTS;
        _edPath = new EditLine;
        _edPath.id = ID_EDITOR;
        _edPath.enterKeyPressed = &onEnterKey;
        _edPath.focusChanged = &onEditorFocusChanged;
        _segments.clicked = &onSegmentsClickOutside;
        _segments.pathSelected = &onPathSelected;
        addChild(_segments);
        addChild(_edPath);
    }

    void setDefaultPopupMenu()
    {
        _edPath.setDefaultPopupMenu();
    }

    protected void onEditorFocusChanged(Widget source, bool focused)
    {
        if (!focused)
        {
            _edPath.text = toUTF32(_path);
            showChild(ID_SEGMENTS);
        }
    }

    protected bool onPathSelected(string path)
    {
        if (pathSelected.assigned)
        {
            if (exists(path))
                return pathSelected(path);
        }
        return false;
    }

    protected void onSegmentsClickOutside(Widget w)
    {
        // switch to editor
        _edPath.text = toUTF32(_path);
        showChild(ID_EDITOR);
        _edPath.setFocus();
    }

    protected bool onEnterKey(EditWidgetBase editor)
    {
        string fn = buildNormalizedPath(toUTF8(_edPath.text));
        if (exists(fn) && isDir(fn))
            onPathSelected(fn);
        return true;
    }
}

class FileNameEditLine : Row
{
    @property
    {
        /// Handle Enter key press inside line editor
        ref Signal!(bool delegate(EditWidgetBase)) enterKeyPressed()
        {
            return _edFileName.enterKeyPressed;
        }

        uint fileDialogFlags() const { return _fileDialogFlags; }

        void fileDialogFlags(uint f)
        {
            _fileDialogFlags = f;
        }

        dstring caption() const { return _caption; }

        void caption(dstring s)
        {
            _caption = s;
        }

        override dstring text() const
        {
            return _edFileName.text;
        }

        override Widget text(dstring s)
        {
            _edFileName.text = s;
            return this;
        }

        /// Mapping of file extension to icon resource name, e.g. ".txt": "text-plain"
        ref string[string] filetypeIcons() { return _filetypeIcons; }

        /// Filter list for file type filter combo box
        FileFilterEntry[] filters() { return _filters; }
        /// ditto
        void filters(FileFilterEntry[] values)
        {
            _filters = values;
        }

        /// Filter index
        int filterIndex() const { return _filterIndex; }
        /// ditto
        void filterIndex(int index) { _filterIndex = index; }

        bool readOnly() const
        {
            return _edFileName.readOnly;
        }

        void readOnly(bool f)
        {
            _edFileName.readOnly = f;
        }
    }

    /// Modified state change listener (e.g. content has been saved, or first time modified after save)
    Signal!(void delegate(Widget source, bool modified)) modifiedStateChanged;
    /// Editor content is changed
    Signal!(void delegate(EditableContent)) contentChanged;

    private
    {
        EditLine _edFileName;
        Button _btn;
        string[string] _filetypeIcons;
        dstring _caption;
        uint _fileDialogFlags = DialogFlag.modal | DialogFlag.resizable | FileDialogFlag.fileMustExist |
            FileDialogFlag.enableCreateDirectory;
        FileFilterEntry[] _filters;
        int _filterIndex;
    }

    this()
    {
        _caption = tr("Open File");
        _edFileName = new EditLine;
        _edFileName.id = "FileNameEditLine_edFileName";
        _edFileName.minWidth(BACKEND_CONSOLE ? 16 : 200);
        _btn = new Button("..."d);
        _btn.id = "FileNameEditLine_btnFile";
        _btn.bindSubItem(this, "button");
        _btn.clicked = delegate(Widget src) {
            auto dlg = new FileDialog(_caption, window, null, _fileDialogFlags);
            foreach (key, value; _filetypeIcons)
                dlg.filetypeIcons[key] = value;
            dlg.filters = _filters;
            dlg.dialogClosed = delegate(Dialog dlg, const Action result) {
                if (result is ACTION_OPEN || result is ACTION_OPEN_DIRECTORY)
                {
                    _edFileName.text = toUTF32((cast(FileDialog)dlg).filename);
                    if (contentChanged.assigned)
                        contentChanged(_edFileName.content);
                }
            };
            string path = toUTF8(_edFileName.text);
            if (!path.empty)
            {
                if (exists(path) && isFile(path))
                {
                    dlg.path = dirName(path);
                    dlg.filename = baseName(path);
                }
                else if (exists(path) && isDir(path))
                {
                    dlg.path = path;
                }
            }
            dlg.show();
        };
        _edFileName.contentChanged = delegate(EditableContent content) {
            if (contentChanged.assigned)
                contentChanged(content);
        };
        _edFileName.modifiedStateChanged = delegate(Widget src, bool modified) {
            if (modifiedStateChanged.assigned)
                modifiedStateChanged(src, modified);
        };
        add(_edFileName).fillWidth(true);
        add(_btn);
    }

    void setDefaultPopupMenu()
    {
        _edFileName.setDefaultPopupMenu();
    }

    /// Add new filter entry
    void addFilter(FileFilterEntry value)
    {
        _filters ~= value;
    }
}

class DirEditLine : FileNameEditLine
{
    this()
    {
        _fileDialogFlags = DialogFlag.modal | DialogFlag.resizable | FileDialogFlag.fileMustExist |
            FileDialogFlag.selectDirectory | FileDialogFlag.enableCreateDirectory;
        _caption = tr("Select directory");
    }
}
