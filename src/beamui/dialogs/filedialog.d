/**
File dialog implementation.

Can show dialog for open / save.


Synopsis:
---
auto dlg = new FileDialog(tr("Open File"), window, FileDialogFlag.open);
dlg.show();
---

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.filedialog;

import std.array : empty;
import std.file;
import std.path;
import beamui.core.files;
import beamui.core.functions;
import beamui.core.i18n;
import beamui.core.stdaction;
import beamui.dialogs.dialog;
import beamui.layout.linear;
import beamui.platforms.common.platform;
import beamui.text.simple : drawSimpleText;
import beamui.text.sizetest;
import beamui.widgets.combobox;
import beamui.widgets.controls;
import beamui.widgets.editors;
import beamui.widgets.grid;
import beamui.widgets.lists;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.text;
import beamui.widgets.widget;

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

/// Filetype filter entry for `FileDialog`
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

    /// Sort entries according to `_sortOrder`
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

        try
        {
            const SysTime t = f.timeLastModified;
            return format("%04d.%02d.%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.minute);
        }
        catch (Exception e)
        {
            Log.w(e.msg);
            return "----.--.-- --:--";
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
        if (_fileList.box.h > 0)
            _fileList.scrollTo(0, 0);

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
            //import beamui.dialogs.messagebox;
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

    override bool handleKeyEvent(KeyEvent event)
    {
        if (event.action == KeyAction.keyDown)
        {
            if (event.key == Key.backspace && event.noModifiers)
            {
                upLevel();
                return true;
            }
        }
        return super.handleKeyEvent(event);
    }

    override bool isCustomCell(int col, int row) const
    {
        return (col == 0 || col == 1) && row >= 0;
    }

    protected inout(DrawableRef) rowIcon(int row) inout
    {
        string iconID = toUTF8(_fileList.cellText(0, row));
        DrawableRef res;
        if (iconID.length)
        {
            if (Bitmap bm = imageCache.get(iconID))
                res = new ImageDrawable(bm); // TODO: reduce allocations
        }
        return cast(inout)res;
    }

    override Size measureCell(int col, int row) const
    {
        if (col == 1)
        {
            dstring txt = _fileList.cellText(col, row);
            auto st = TextLayoutStyle(_fileList.font.get);
            return computeTextSize(txt, st);
        }
        static if (BACKEND_CONSOLE)
            return Size(0, 0);
        else
        {
            const icon = rowIcon(row);
            return !icon.isNull ? Size(icon.width + 2, icon.height + 2) : Size(0, 0);
        }
    }

    override void drawCell(Painter pr, Box b, int col, int row)
    {
        if (col == 1)
        {
            if (BACKEND_GUI)
                b.shrink(Insets(1, 2));
            else
                b.w--;
            dstring txt = _fileList.cellText(col, row);
            const offset = BACKEND_CONSOLE ? 0 : 1;
            Color cl = _fileList.style.textColor;
            if (_entries[row].isDir)
                cl = currentTheme.getColor("file_dialog_dir_name", cl);
            drawSimpleText(pr, txt, b.x + offset, b.y + offset, _fileList.font.get, cl);
            return;
        }
        DrawableRef img = rowIcon(row);
        if (!img.isNull)
        {
            const sz = Size(img.width, img.height);
            const ib = alignBox(b, sz, Align.center);
            img.drawTo(pr, ib);
        }
    }

    protected ListWidget createRootsList()
    {
        auto res = new ListWidget;
        foreach (ref RootEntry root; _roots)
        {
            auto btn = new Button(root.label, root.icon);
            btn.style.display = "column";
            btn.setAttribute("flat");
            btn.allowsClick = false;
            btn.allowsFocus = false;
            btn.allowsHover = false;
            btn.tooltipText = toUTF32(root.path);
            res.addChild(btn);
        }
        res.onItemClick ~= (int itemIndex) {
            openDirectory(_roots[itemIndex].path, null);
            res.selectItem(-1);
        };
        return res;
    }

    /// File list item activated (double clicked or Enter key pressed)
    protected void handleItemActivation(int index)
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
    protected void handleItemSelection(int index)
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

    bool handlePathSelection(string path)
    {
        return openDirectory(path, null);
    }

    protected Menu getCellPopupMenu(int col, int row)
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

        style.minWidth = BACKEND_CONSOLE ? 50 : 600;

        auto content = new Panel;
            Widget leftPanel = createRootsList();
            auto rightPanel = new Panel;
                _edPath = new FilePathPanel;
                _fileList = new StringGridWidget;
                _edFilename = new EditLine;

        with (content) {
            setAttribute("content");
            add(leftPanel, new Resizer, rightPanel);
            with (leftPanel) {
                setAttribute("left-panel");
                style.minWidth = BACKEND_CONSOLE ? 7 : 40;
            }
            with (rightPanel) {
                setAttribute("right-panel");
                add(new Label(tr("Path") ~ ":"), _edPath, _fileList, _edFilename);
                if (_filters.length)
                {
                    _cbFilters = new ComboBox;
                    _cbFilters.setAttribute("filter");
                    add(_cbFilters);
                }
                with (_edPath) {
                    setAttribute("path");
                }
                with (_fileList) {
                    bindSubItem(this, "grid");
                    fullColumnOnLeft = false;
                    fullRowOnTop = false;
                    showRowHeaders = false;
                    minVisibleRows = 10;
                    minVisibleCols = 4;
                }
                with (_edFilename) {
                    setAttribute("filename");
                    popupMenu = EditLine.createDefaultPopupMenu();
                }
            }
        }
        add(content);

        if (_flags & FileDialogFlag.enableCreateDirectory)
        {
            add(createButtonsPanel([ACTION_CREATE_DIRECTORY, _action, ACTION_CANCEL], 1, 1));
        }
        else
        {
            add(createButtonsPanel([_action, ACTION_CANCEL], 0, 0));
        }

        _edPath.onPathSelection = &handlePathSelection;
        if (_flags & FileDialogFlag.selectDirectory)
        {
            _edFilename.visibility = Visibility.gone;
        }

        _fileList.resize(4, 3);
        _fileList.setColTitle(0, " "d);
        updateColumnHeaders();
        _fileList.rowSelect = true;
        _fileList.multiSelect = _allowMultipleFiles;
        _fileList.cellPopupMenuBuilder ~= &getCellPopupMenu;
        _fileList.onHeaderCellClick = &handleHeaderCellClick;

        _fileList.onKeyEvent ~= (KeyEvent event) {
            if (_shortcutHelper.handleKeyEvent(event))
                locateFileInList(_shortcutHelper.text);
            return false;
        };

        _fileList.customCellAdapter = this;
        _fileList.onActivateCell = delegate(int col, int row) {
            handleItemActivation(row);
        };
        _fileList.onSelectCell = delegate(int col, int row) {
            handleItemSelection(row);
        };

        if (_filters.length)
        {
            dstring[] filterLabels;
            foreach (f; _filters)
                filterLabels ~= f.label;
            _cbFilters.items = filterLabels;
            _cbFilters.selectedItemIndex = _filterIndex;
            _cbFilters.onSelect ~= (int itemIndex) {
                _filterIndex = itemIndex;
                reopenDirectory();
            };
        }

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

    protected void handleHeaderCellClick(int col, int row)
    {
        debug Log.d("header cell clicked: col=", col, " row=", row);
        if (row == 0 && col >= 2 && col <= 4)
        {
            // 2=NAME, 3=SIZE, 4=MODIFIED
            changeSortOrder(col);
        }
    }

    override protected void handleShow()
    {
        _fileList.setFocus();
    }

    override void layout(Box geom)
    {
        _fileList.autoFitColumnWidths();
        super.layout(geom);
        _fileList.fillColumnWidth(1);
    }
}

alias PathSelectionHandler = bool delegate(string path);

class FilePathPanelItem : Panel
{
    Listener!PathSelectionHandler onPathSelection;

    private
    {
        string _path;
        Label _text;
        Button _button;
    }

    this(string path)
    {
        _path = path;
        string fname = isRoot(path) ? path : baseName(path);
        _text = new Label(toUTF32(fname));
        _text.bindSubItem(this, "label");
        _text.allowsHover = true;
        _text.allowsClick = true;
        _text.onClick ~= &handleTextClick;
        _button = new Button(null, "scrollbar_btn_right");
        _button.bindSubItem(this, "button");
        _button.allowsFocus = false;
        _button.onClick ~= &handleButtonClick;
        allowsHover = true;
        add(_text, _button);
    }

    private void handleTextClick()
    {
        if (onPathSelection.assigned)
            onPathSelection(_path);
    }

    private void handleButtonClick()
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
                    if (onPathSelection.assigned)
                        onPathSelection(fullPath);
                });
            }();
        }
        auto popup = window.showPopup(menu, WeakRef!Widget(_button), PopupAlign.below);
    }
}

/// Panel with buttons - path segments - for fast navigation to subdirs.
class FilePathPanelButtons : WidgetGroup
{
    Listener!PathSelectionHandler onPathSelection;

    private string _path;

    this()
    {
        allowsClick = true;
    }

    protected void initialize(string path)
    {
        _path = path;
        removeAllChildren();
        string itemPath = path;
        while (true)
        {
            auto item = new FilePathPanelItem(itemPath);
            item.onPathSelection = &handlePathSelection;
            addChild(item);
            if (isRoot(itemPath))
                break;

            itemPath = parentDir(itemPath);
        }
        itemSizes.length = childCount;
    }

    protected bool handlePathSelection(string path)
    {
        return onPathSelection.assigned ? onPathSelection(path) : false;
    }

    private float[] itemSizes;
    override void measure()
    {
        Boundaries bs;
        Size min;
        foreach (i; 0 .. childCount)
        {
            Widget item = child(i);
            item.visibility = Visibility.visible;

            item.measure();
            const wbs = item.boundaries;
            itemSizes[i] = wbs.nat.w;
            if (i == 0)
                min = wbs.min;
            bs.addWidth(wbs);
            bs.maximizeHeight(wbs);
        }
        bs.min = min;
        setBoundaries(bs);
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        setBox(geom);

        const inner = innerBox;
        const maxw = inner.w;
        float totalw = 0;
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
        // changing child visibility to `gone` forces parent layout
        cancelLayout();
        // lay out visible items
        // backward order
        Box ibox = inner;
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

    override protected void drawContent(Painter pr)
    {
        drawAllChildren(pr);
    }
}

/// Panel - either path segment buttons or text editor line
class FilePathPanel : Panel
{
    @property string path() const { return _path; }

    @property void path(string value)
    {
        _segments.initialize(value);
        _edPath.text = toUTF32(value);
        _path = value;
        showChild(ID_SEGMENTS);
    }

    Listener!PathSelectionHandler onPathSelection;

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
        _edPath.onEnterKeyPress ~= &handleEnterKey;
        _edPath.onFocusChange ~= &handleEditorFocusChanged;
        _segments.onClick ~= &handleSegmentClickOutside;
        _segments.onPathSelection = &handlePathSelection;
        addChild(_segments);
        addChild(_edPath);
    }

    void setDefaultPopupMenu()
    {
        _edPath.popupMenu = EditLine.createDefaultPopupMenu();
    }

    protected void handleEditorFocusChanged(bool focused)
    {
        if (!focused)
        {
            _edPath.text = toUTF32(_path);
            showChild(ID_SEGMENTS);
        }
    }

    protected bool handlePathSelection(string path)
    {
        if (onPathSelection.assigned)
        {
            if (exists(path))
                return onPathSelection(path);
        }
        return false;
    }

    protected void handleSegmentClickOutside()
    {
        // switch to editor
        _edPath.text = toUTF32(_path);
        showChild(ID_EDITOR);
        _edPath.setFocus();
    }

    protected bool handleEnterKey()
    {
        string fn = buildNormalizedPath(toUTF8(_edPath.text));
        if (exists(fn) && isDir(fn))
            handlePathSelection(fn);
        return true;
    }
}

class FileNameEditLine : Panel
{
    @property
    {
        /// Handle Enter key press inside line editor
        ref Signal!(bool delegate()) onEnterKeyPress()
        {
            return _edFileName.onEnterKeyPress;
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

        override void text(dstring s)
        {
            _edFileName.text = s;
        }

        /// Mapping of file extension to icon resource name, e.g. ".txt": "text-plain"
        ref string[string] filetypeIcons() { return _filetypeIcons; }

        /// Filter list for file type filter combo box
        const(FileFilterEntry[]) filters() const { return _filters; }
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

    /// Editor content is changed
    Signal!(void delegate(dstring)) onChange;

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
        _edFileName.style.minWidth = BACKEND_CONSOLE ? 16 : 200;
        _btn = new Button("..."d);
        _btn.bindSubItem(this, "button");
        _btn.onClick ~= {
            auto dlg = new FileDialog(_caption, window, null, _fileDialogFlags);
            foreach (key, value; _filetypeIcons)
                dlg.filetypeIcons[key] = value;
            dlg.filters = _filters;
            dlg.onClose ~= (const Action result) {
                if (result is ACTION_OPEN || result is ACTION_OPEN_DIRECTORY)
                {
                    _edFileName.text = toUTF32((cast(FileDialog)dlg).filename);
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
        _edFileName.onChange ~= &onChange.emit;
        add(_edFileName, _btn);
    }

    void setDefaultPopupMenu()
    {
        _edFileName.popupMenu = EditLine.createDefaultPopupMenu();
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
