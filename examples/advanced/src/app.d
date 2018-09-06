/**

Synopsis:
---
dub run :advanced
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module app;

import beamui;

mixin APP_ENTRY_POINT;

/// Entry point for application
extern (C) int UIAppMain(string[] args)
{
    // you may set different log level, e.g. always use trace, even for release builds
    //Log.setLogLevel(LogLevel.trace);
    // direct logs to a file
    //Log.setFileLogger(new std.stdio.File("ui.log", "w"));

    // you may embed resources into the executable
    resourceList.embed!"resources.list";
    // and you may setup resource paths
    // not required if only embedded resources are used
    string[] resourceDirs = [
        //appendPath(exePath, "res/"), // at the same directory as executable
        appendPath(exePath, "../res/"), // at project directory
        appendPath(exePath, "../../../res/"),   // for Visual D builds
        //appendPath(exePath, "../../../../res/"),// for Mono-D builds
    ];
    // will use only existing directories
    platform.resourceDirs = resourceDirs;

    // select application language, English is default
    //platform.uiLanguage = "ru";
    // add domain-specific translation file
    //loadTranslator("advanced-ru");
    // load theme from file "light.css"
    platform.uiTheme = "light";

    // you can override default hinting mode (normal, autohint, disabled)
    FontManager.hintingMode = HintingMode.normal;
    // you can override antialiasing setting
    // fonts with size less than specified value will not be antialiased
    FontManager.minAntialiasedFontSize = 0;
    // you can turn on subpixel font rendering (ClearType)
    FontManager.subpixelRenderingMode = SubpixelRenderingMode.none; // bgr, rgb


    // create a window
    // expand window size if content is bigger than 800, 700
    auto window = platform.createWindow("Advanced example", null,
            WindowFlag.resizable | WindowFlag.expanded, 800, 700);

    // create main content layout
    auto frame = new Column;
    frame.spacing = 0;

    TabWidget tabs;

    //=========================================================================
    // create main menu

    auto fileOpenAction = new Action(tr("&Open"), "document-open", KeyCode.O, KeyFlag.control);
    fileOpenAction.bind(frame, {
        auto dlg = new FileDialog("Open Text File"d, window);
        dlg.allowMultipleFiles = true;
        dlg.addFilter(FileFilterEntry(tr("All files"d), "*"));
        dlg.addFilter(FileFilterEntry(tr("Text files"d), "*.txt;*.log"));
        dlg.addFilter(FileFilterEntry(tr("Source files"d), "*.d;*.dd;*.c;*.cpp;*.h;*.hpp"));
        dlg.addFilter(FileFilterEntry(tr("Executable files"d), "*", true));
        dlg.dialogClosed = delegate(Dialog dlg, const Action result) {
            import std.path : baseName;

            if (result is ACTION_OPEN)
            {
                string[] filenames = (cast(FileDialog)dlg).filenames;
                foreach (fn; filenames)
                {
                    if (fn.endsWith(".c") || fn.endsWith(".cpp") || fn.endsWith(".h") || fn.endsWith(".hpp") ||
                        fn.endsWith(".d") || fn.endsWith(".dd") || fn.endsWith(".ddoc") || fn.endsWith(".json") ||
                        fn.endsWith(".xml") || fn.endsWith(".html") || fn.endsWith(".css") ||
                        fn.endsWith(".txt") || fn.endsWith(".log"))
                    {
                        // open source file in tab
                        int index = tabs.tabIndex(fn);
                        if (index >= 0)
                        {
                            // file is already opened in tab
                            tabs.selectTab(index, true);
                        }
                        else
                        {
                            auto editor = new SourceEdit;
                            editor.id = fn;
                            if (editor.load(fn))
                            {
                                tabs.addTab(editor, toUTF32(baseName(fn)), null, true);
                                tabs.selectTab(fn);
                            }
                            else
                            {
                                destroy(editor);
                                window.showMessageBox("File open error"d, "Cannot open file "d ~ toUTF32(fn));
                            }
                        }
                    }
                    else
                    {
                        window.showMessageBox("FileOpen result"d, "File with bad extension: "d ~ toUTF32(fn));
                    }
                }
            }
        };
        dlg.show();
    });
    auto fileSaveAction = new Action(tr("&Save"), "document-save", KeyCode.S, KeyFlag.control);
    auto fileExitAction = new Action(tr("E&xit"), "document-close", KeyCode.X, KeyFlag.alt);
    fileExitAction.bind(frame, &window.close);


    auto mainMenu = new MenuBar;
    auto fileMenu = mainMenu.addSubmenu(tr("&File"));
    fileMenu.add(fileOpenAction, fileSaveAction);
    auto openRecentMenu = fileMenu.addSubmenu(tr("Open recent"), "document-open-recent");
    openRecentMenu.addAction("&1: File 1"d);
    openRecentMenu.addAction("&2: File 2"d);
    openRecentMenu.addAction("&3: File 3"d);
    openRecentMenu.addAction("&4: File 4"d);
    openRecentMenu.addAction("&5: File 5"d);
    fileMenu.add(fileExitAction);

    auto editMenu = mainMenu.addSubmenu(tr("&Edit"));
    editMenu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);
    editMenu.addSeparator();
    editMenu.addAction(tr("&Preferences"));

    auto viewMenu = mainMenu.addSubmenu(tr("&View"));
    auto themeMenu = viewMenu.addSubmenu(tr("&Theme"));
    themeMenu.addAction(tr("Reload theme"), null, { platform.reloadTheme(); });
    themeMenu.addAction(tr("Default"), null, {
        platform.uiTheme = "default";
    }).checkable(true);
    themeMenu.addAction(tr("Light"), null, {
        platform.uiTheme = "light";
    }).checkable(true).checked(true);
    themeMenu.addAction(tr("Dark"), null, {
        platform.uiTheme = "dark";
    }).checkable(true);

    auto windowMenu = mainMenu.addSubmenu(tr("&Window"));
    windowMenu.addAction(tr("&Preferences"));
    windowMenu.addSeparator();
    windowMenu.addAction(tr("Minimize"), null, { window.minimize(); });
    windowMenu.addAction(tr("Maximize"), null, { window.maximize(); });
    windowMenu.addAction(tr("Restore"), null, { window.restore(); });

    auto helpMenu = mainMenu.addSubmenu(tr("&Help"));
    helpMenu.addAction(tr("&View help"), null, {
        platform.openURL("https://github.com/dayllenger/beamui");
    });
    helpMenu.addAction(tr("&About"), null, {
        window.showMessageBox("About"d,
            "beamui demo app\n(c) dayllenger, 2018\nhttp://github.com/dayllenger/beamui"d);
    });

    frame.addChild(mainMenu);

    // create popup menu for edit widgets
    auto editorPopupMenu = new Menu;
    editorPopupMenu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);

    //=========================================================================
    // create tabs

    tabs = new TabWidget;
    tabs.tabClosed = delegate(string tabID) { tabs.removeTab(tabID); };
    tabs.tabChanged = delegate(string newTabID, string oldTabID) {
        window.title = tabs.tab(newTabID).text ~ " - advanced example"d;
    };

    // most of controls example
    {
        auto controls = new Column;
        controls.padding = RectOffset(12.pt);

        auto line1 = new Row;
        controls.addChild(line1);

        auto gb = new GroupBox("CheckBox"d);
        gb.addChild(new CheckBox("CheckBox 1"d));
        gb.addChild(new CheckBox("CheckBox 2"d).checked(true));
        gb.addChild(new CheckBox("CheckBox disabled"d).enabled(false));
        gb.addChild(new CheckBox("CheckBox disabled"d).checked(true).enabled(false));
        line1.addChild(gb);

        auto gb2 = new GroupBox("RadioButton"d);
        gb2.addChild(new RadioButton("RadioButton 1"d).checked(true));
        gb2.addChild(new RadioButton("RadioButton 2"d));
        gb2.addChild(new RadioButton("RadioButton disabled"d).enabled(false));
        line1.addChild(gb2);

        auto col1 = new Column;
        auto gb3 = new GroupBox("Button"d, Orientation.horizontal);
        gb3.addChild(new Button("Button"d));
        gb3.addChild(new Button("Button disabled"d).enabled(false));
        col1.addChild(gb3);
        auto gb4 = new GroupBox("Button with icon and text"d, Orientation.horizontal);
        gb4.addChild(new Button("Enabled"d, "document-open"));
        gb4.addChild(new Button("Disabled"d, "document-save").enabled(false));
        col1.addChild(gb4);
        auto gbtext = new GroupBox("Label"d, Orientation.horizontal);
        gbtext.addChild(new Label("Red text"d).fontSize(12.pt).textColor(0xFF0000));
        gbtext.addChild(new Label("Italic text"d).fontSize(12.pt).fontItalic(true));
        col1.addChild(gbtext);
        line1.addChild(col1);

        auto col2 = new Column;
        auto gb32 = new GroupBox("Button with Action"d);
        gb32.addChild(new Button(fileOpenAction).orientation(Orientation.vertical));
        auto btnToggle = new Button("Toggle action above"d, null, true);
        btnToggle.checked(fileOpenAction.enabled);
        btnToggle.clicked = (Widget w) {
            fileOpenAction.enabled = !fileOpenAction.enabled;
            return true;
        };
        gb32.addChild(btnToggle);
        col2.addChild(gb32);
        auto gb33 = new GroupBox("ImageWidget"d);
        gb33.addChild(new ImageWidget("cr3_logo"));
        col2.addChild(gb33);
        line1.addChild(col2);

        auto col3 = new Column;
        auto gb31 = new GroupBox("SwitchButton"d);
        gb31.addChild(new SwitchButton);
        gb31.addChild(new SwitchButton().checked(true));
        gb31.addChild(new SwitchButton().enabled(false));
        gb31.addChild(new SwitchButton().enabled(false).checked(true));
        col3.addChild(gb31);
        line1.addChild(col3);

        auto line2 = new Row;
        controls.addChild(line2);

        auto gb5 = new GroupBox("horizontal ScrollBar"d);
        gb5.addChild(new ScrollBar(Orientation.horizontal));
        line2.addChild(gb5);
        auto gb6 = new GroupBox("horizontal Slider"d);
        gb6.addChild(new Slider(Orientation.horizontal));
        line2.addChild(gb6);
        auto gb7 = new GroupBox("EditLine"d);
        gb7.addChild(new EditLine("Some text"d).minWidth(120.pt));
        line2.addChild(gb7);
        auto gb8 = new GroupBox("EditLine disabled"d);
        gb8.addChild(new EditLine("Some text"d).enabled(false).minWidth(120.pt));
        line2.addChild(gb8);

        auto line3 = new Row;
        auto gbeditbox = new GroupBox("EditBox"d);
        auto ed1 = new EditBox("Some text in EditBox\nOne more line\nYet another text line");
        gbeditbox.addChild(ed1.fillH());
        line3.addChild(gbeditbox.fillW());
        GroupBox gbtabs = new GroupBox("TabWidget"d);
        auto tabs1 = new TabWidget;
        tabs1.addTab(new Label("Label on tab page\nLabels can be\nMultiline"d).
                maxLines(3).id("tab1"), "Tab 1"d);
        tabs1.addTab(new ImageWidget("beamui-logo").id("tab2"), "Tab 2"d);
        tabs1.tabHost.padding = RectOffset(10.pt);
        tabs1.tabHost.backgroundColor = 0xE0E0E0;
        gbtabs.addChild(tabs1);
        line3.addChild(gbtabs);
        controls.addChild(line3);

        auto line4 = new Row;
        auto gbgrid = new GroupBox("StringGridWidget"d);
        auto grid = new StringGridWidget;
        grid.resize(12, 10);
        foreach (index, month; ["January"d, "February"d, "March"d, "April"d, "May"d, "June"d,
                "July"d, "August"d, "September"d, "October"d, "November"d, "December"d])
            grid.setColTitle(cast(int)index, month);
        foreach (y; 0 .. grid.rows)
            grid.setRowTitle(y, to!dstring(y + 1));
        //grid.alignment = Align.right;
        grid.setColWidth(0, 30.pt);
        grid.autoFit();

        import std.random;

        foreach (x; 0 .. grid.cols)
        {
            foreach (y; 0 .. grid.rows)
            {
                int n = uniform(0, 10000);
                grid.setCellText(x, y, "%.2f"d.format(n / 100.0));
            }
        }
        gbgrid.addChild(grid.fillH());
        line4.addChild(gbgrid.fillW());

        auto gbtree = new GroupBox("TreeWidget"d, Orientation.vertical);
        auto tree = new TreeWidget;
        //tree.layoutWidth(WRAP_CONTENT).fillH();
//         tree.maxHeight(200.pt);
        TreeItem tree1 = tree.items.newChild("group1", "Group 1"d, "document-open");
        tree1.newChild("g1_1", "Group 1 item 1"d);
        tree1.newChild("g1_2", "Group 1 item 2"d);
        tree1.newChild("g1_3", "Group 1 item 3"d);
        TreeItem tree2 = tree.items.newChild("group2", "Group 2"d, "document-save");
        tree2.newChild("g2_1", "Group 2 item 1"d, "edit-copy");
        tree2.newChild("g2_2", "Group 2 item 2"d, "edit-cut");
        tree2.newChild("g2_3", "Group 2 item 3"d, "edit-paste");
        tree2.newChild("g2_4", "Group 2 item 4"d);
        TreeItem tree3 = tree.items.newChild("group3", "Group 3"d);
        tree3.newChild("g3_1", "Group 3 item 1"d);
        tree3.newChild("g3_2", "Group 3 item 2"d);
        TreeItem tree32 = tree3.newChild("g3_3", "Group 3 item 3"d);
        tree3.newChild("g3_4", "Group 3 item 4"d);
        tree32.newChild("group3_2_1", "Group 3 item 2 subitem 1"d);
        tree32.newChild("group3_2_2", "Group 3 item 2 subitem 2"d);
        tree32.newChild("group3_2_3", "Group 3 item 2 subitem 3"d);
        tree32.newChild("group3_2_4", "Group 3 item 2 subitem 4"d);
        tree32.newChild("group3_2_5", "Group 3 item 2 subitem 5"d);
        tree3.newChild("g3_5", "Group 3 item 5"d);
        tree3.newChild("g3_6", "Group 3 item 6"d);
        gbtree.addChild(tree);
        tree.items.selectItem(tree1);
        // test adding new tree items
        auto newTreeItemForm = new Column;
        auto newTreeItemEd = new EditLine("new item"d);
        auto newTreeItemFormRow = new Row;
        auto btnAddItem = new Button("Add"d);
        auto btnRemoveItem = new Button("Remove"d);
        newTreeItemFormRow.addSpacer();
        newTreeItemFormRow.addChild(btnAddItem);
        newTreeItemFormRow.addChild(btnRemoveItem);
        newTreeItemForm.addChild(newTreeItemEd);
        newTreeItemForm.addChild(newTreeItemFormRow);
        btnAddItem.clicked = delegate(Widget source) {
            import std.random;

            dstring label = newTreeItemEd.text;
            string id = "item%d".format(uniform(1000000, 9999999, rndGen));
            TreeItem item = tree.items.selectedItem;
            if (item)
            {
                Log.d("Creating new tree item ", id, " ", label);
                TreeItem newItem = new TreeItem(id, label);
                item.addChild(newItem);
            }
            return true;
        };
        btnRemoveItem.clicked = delegate(Widget source) {
            TreeItem item = tree.items.selectedItem;
            if (item)
            {
                Log.d("Removing tree item ", item.id, " ", item.text);
                item.parent.removeChild(item);
            }
            return true;
        };
        gbtree.addChild(newTreeItemForm);
        line4.addChild(gbtree);
        controls.addChild(line4);

        tabs.addTab(controls.id("CONTROLS"), tr("Controls"));
    }

    // two long lists
    // left one is list with widgets as items
    // right one is list with string list adapter
    {
        auto longLists = new Row;

        auto list = new ListWidget(Orientation.vertical);
        auto listAdapter = new WidgetListAdapter;
        listAdapter.add(new Label("This is a list of widgets"d));
        list.ownAdapter = listAdapter;
        list.selectItem(0);
        longLists.addChild(list.fillW());

        auto list2 = new StringListWidget;
        auto stringList = new StringListAdapter;
        stringList.add("This is a list of strings from StringListAdapter"d);
        stringList.add("If you type with your keyboard,"d);
        stringList.add("then you can find the"d);
        stringList.add("item in the list"d);
        stringList.add("neat!"d);
        list2.ownAdapter = stringList;
        list2.selectItem(0);
        longLists.addChild(list2.fillW());

        for (int i = 1; i < 1000; i++)
        {
            dstring label = "List item "d ~ to!dstring(i);
            listAdapter.add(new Label("Widget list - "d ~ label));
            stringList.add("Simple string - "d ~ label);
        }
        listAdapter.resetItemState(0, State.enabled);
        listAdapter.resetItemState(5, State.enabled);
        listAdapter.resetItemState(7, State.enabled);
        listAdapter.resetItemState(12, State.enabled);
        assert(list.itemEnabled(5) == false);
        assert(list.itemEnabled(6) == true);

        auto itemedit = new Column;
        itemedit.addChild(new Label("New item text:"d));
        auto itemtext = new EditLine("Text for new item"d);
        itemedit.addChild(itemtext);
        auto btn = new Button("Add item"d);
        btn.clicked = delegate(Widget src) {
            stringList.add(itemtext.text);
            listAdapter.add(new Label(itemtext.text));
            return true;
        };
        itemedit.addChild(btn);
        longLists.addChild(itemedit);

        tabs.addTab(longLists.id("LISTS"), tr("Long list"));
    }

    // form as a table layout
    {
        auto table = new TableLayout;
        table.colCount = 2;
        // headers
        table.addChild(new Label("Parameter"d).alignment(Align.right | Align.vcenter));
        table.addChild(new Label("Field"d).alignment(Align.left | Align.vcenter));
        // row 1
        table.addChild(new Label("First Name"d).alignment(Align.right | Align.vcenter));
        table.addChild(new EditLine("John"d));
        // row 2, disabled
        table.addChild(new Label("Last Name"d).alignment(Align.right | Align.vcenter).enabled(false));
        table.addChild(new EditLine("Doe"d).enabled(false));
        // row 3, normal readonly combo box
        table.addChild(new Label("Country"d).alignment(Align.right | Align.vcenter));
        auto combo1 = new ComboBox(["Australia"d, "Canada"d, "France"d, "Germany"d,
                "Italy"d, "Poland"d, "Russia"d, "Spain"d, "UK"d, "USA"d]);
        combo1.selectedItemIndex = 3;
        table.addChild(combo1);
        // row 4, disabled readonly combo box
        table.addChild(new Label("City"d).alignment(Align.right | Align.vcenter));
        auto combo2 = new ComboBox(["none"d]);
        combo2.enabled = false;
        combo2.selectedItemIndex = 0;
        table.addChild(combo2).fillW();

        tabs.addTab(table.id("TABLE"), tr("Table layout"));
    }

    // editors
    {
        auto editors = new Column;

        editors.addChild(new Label("EditLine: Single line editor"d));
        auto editLine = new EditLine("Single line editor sample text");
        editLine.popupMenu = editorPopupMenu;
        editors.addChild(createBaseEditorSettingsControl(editLine)); // see after UIAppMain
        editors.addChild(editLine);

        editors.addChild(new Label("SourceEdit: multiline editor, for source code editing"d));
        auto srcEditBox = new SourceEdit;
        srcEditBox.text = q{#!/usr/bin/env rdmd
void main()
{
    import std.stdio : writefln;
    import std.algorithm.sorting : sort;
    import std.range : chain;

    int[] arr1 = [4, 9, 7];
    int[] arr2 = [5, 2, 1, 10];
    int[] arr3 = [6, 8, 3];
    // @nogc functions are guaranteed by the compiler
    // to be without any GC allocation
    () @nogc {
        sort(chain(arr1, arr2, arr3));
    }();
    writefln("%s\n%s\n%s\n", arr1, arr2, arr3);
}
}d;
        srcEditBox.popupMenu = editorPopupMenu;
        srcEditBox.showIcons = true;
        auto editorControl = createBaseEditorSettingsControl(srcEditBox);
        editors.addChild(addSourceEditorControls(editorControl, srcEditBox));
        editors.addChild(srcEditBox.fillH());

        editors.addChild(new Label("EditBox: additional view for the same content (split view testing)"d));
        auto srcEditBox2 = new SourceEdit;
        srcEditBox2.content = srcEditBox.content; // view the same content as first editbox
        editors.addChild(srcEditBox2.fillH());

        tabs.addTab(editors.id("EDITORS"), tr("Editors"));
    }

    // string grid
    {
        auto gridTab = new Column;
        auto gridSettings = new Row;
        auto grid = new StringGridWidget;

        auto cb1 = new CheckBox("Full column on left"d).checked(grid.fullColumnOnLeft)
            .tooltipText("Extends scroll area to show full column at left when scrolled to rightmost column"d);
        auto cb2 = new CheckBox("Full row on top"d).checked(grid.fullRowOnTop)
            .tooltipText("Extends scroll area to show full row at top when scrolled to end row"d);
        cb1.checkChanged ~= (w, checked) { grid.fullColumnOnLeft = checked; };
        cb2.checkChanged ~= (w, checked) { grid.fullRowOnTop = checked; };
        gridSettings.addChild(cb1);
        gridSettings.addChild(cb2);
        gridTab.addChild(gridSettings);

        grid.showColHeaders = true;
        grid.showRowHeaders = true;
        grid.resize(30, 50);
        grid.fixedCols = 3;
        grid.fixedRows = 2;
        //grid.rowSelect = true; // testing full row selection
        grid.multiSelect = true;
        grid.selectCell(4, 6, false);

        // create sample grid content
        for (int y = 0; y < grid.rows; y++)
        {
            for (int x = 0; x < grid.cols; x++)
            {
                grid.setCellText(x, y, "cell("d ~ to!dstring(x + 1) ~ ","d ~ to!dstring(y + 1) ~ ")"d);
            }
            grid.setRowTitle(y, to!dstring(y + 1));
        }
        for (int x = 0; x < grid.cols; x++)
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

        gridTab.addChild(grid.fillH());

        tabs.addTab(gridTab.id("GRID"), tr("Grid"d));
    }

    // charts
    {
        auto barChart1 = new SimpleBarChart("SimpleBarChart Example"d);
        barChart1.addBar(12.0, makeRGBA(255, 0, 0, 0), "Red bar"d);
        barChart1.addBar(24.0, makeRGBA(0, 255, 0, 0), "Green bar"d);
        barChart1.addBar(5.0, makeRGBA(0, 0, 255, 0), "Blue bar"d);
        barChart1.addBar(12.0, makeRGBA(230, 126, 34, 0), "Orange bar"d);
        //barChart1.fillWH();

        auto barChart2 = new SimpleBarChart("SimpleBarChart Example - long descriptions"d);
        barChart2.addBar(12.0, makeRGBA(255, 0, 0, 0), "Red bar\n(12.0)"d);
        barChart2.addBar(24.0, makeRGBA(0, 255, 0, 0), "Green bar\n(24.0)"d);
        barChart2.addBar(5.0, makeRGBA(0, 0, 255, 0), "Blue bar\n(5.0)"d);
        barChart2.addBar(12.0, makeRGBA(230, 126, 34, 0), "Orange bar\n(12.0)\nlong long long description added here"d);

        auto barChart3 = new SimpleBarChart("SimpleBarChart Example with axis ratio 0.3"d);
        barChart3.addBar(12.0, makeRGBA(255, 0, 0, 0), "Red bar"d);
        barChart3.addBar(24.0, makeRGBA(0, 255, 0, 0), "Green bar"d);
        barChart3.addBar(5.0, makeRGBA(0, 0, 255, 0), "Blue bar"d);
        barChart3.addBar(12.0, makeRGBA(230, 126, 34, 0), "Orange bar"d);
        barChart3.axisRatio = 0.3;

        auto barChart4 = new SimpleBarChart("SimpleBarChart Example with axis ratio 1.3"d);
        barChart4.addBar(12.0, makeRGBA(255, 0, 0, 0), "Red bar"d);
        barChart4.addBar(24.0, makeRGBA(0, 255, 0, 0), "Green bar"d);
        barChart4.addBar(5.0, makeRGBA(0, 0, 255, 0), "Blue bar"d);
        barChart4.addBar(12.0, makeRGBA(230, 126, 34, 0), "Orange bar"d);
        barChart4.axisRatio = 1.3;

        auto chartsLayout = new Row;

        auto chartColumn1 = new Column;
        auto chartColumn2 = new Column;

        chartColumn1.addChild(barChart1);
        chartColumn1.addChild(barChart2);
        chartsLayout.addChild(chartColumn1);
        chartColumn2.addChild(barChart3);
        chartColumn2.addChild(barChart4);
        chartsLayout.addChild(chartColumn2);

        tabs.addTab(chartsLayout.id("CHARTS"), tr("Charts"d));
    }

    // canvas
    static if (BACKEND_GUI)
    {
        auto canvas = new CanvasWidget;
        canvas.drawCalled = delegate(DrawBuf buf, Box area) {
            buf.fill(0xFFFFFF);

            int lh = canvas.font.height;
            int x = area.x + 5;
            int y = area.y + 5;
            canvas.font.drawText(buf, x + 20, y, "solid rectangles"d, 0xC080C0);
            buf.fillRect(Rect(x + 20, y + lh + 1, x + 150, y + 200), 0x80FF80);
            buf.fillRect(Rect(x + 90, y + 80, x + 250, y + 250), 0x80FF80FF);

            canvas.font.drawText(buf, x + 400, y, "frame"d, 0x208020);
            buf.drawFrame(Rect(x + 400, y + lh + 1, x + 550, y + 150),
                          0x2090A0, RectOffset(6, 6, 6, 18), 0);

            canvas.font.drawText(buf, x + 20, y + 300, "points"d, 0x000080);
            for (int i = 0; i < 100; i += 2)
                buf.drawPixel(x + 20 + i, y + lh + 305, 0xFF0000 + i * 2);

            canvas.font.drawText(buf, x + 450, y + 300, "lines"d, 0x800020);
            for (int i = 0; i < 40; i += 3)
                buf.drawLine(Point(x + 400 + i * 4, y + 250), Point(x + 350 + i * 7, y + 320 + i * 2), 0x008000 + i * 5);

            canvas.font.drawText(buf, x + 20, y + 500, "ellipse"d, 0x208050);
            buf.drawEllipseF(x + 100, y + 600, 100, 80, 3, 0x80008000, 0x804040FF);

            canvas.font.drawText(buf, x + 320, y + 500, "ellipse arc"d, 0x208050);
            buf.drawEllipseArcF(x + 350, y + lh + 505, 150, 180, 45, 130, 3, 0x40008000, 0x804040FF);
        };

        tabs.addTab(canvas.id("CANVAS"), tr("Canvas"));
    }

    // animation
    static if (BACKEND_GUI)
    {
    }

    //==========================================================================

    tabs.selectTab("CONTROLS");
    frame.addChild(tabs.fillH());

    window.mainWidget = frame;
    static if (BACKEND_GUI)
        window.icon = getImage("beamui-logo");
    window.show();

    return platform.enterMessageLoop();
}

Widget createBaseEditorSettingsControl(EditWidgetBase editor)
{
    auto res = new Row;
    auto cb1 = new CheckBox(tr("Catch tabs")).checked(editor.wantTabs);
    auto cb2 = new CheckBox(tr("Use spaces for indentation")).checked(editor.useSpacesForTabs);
    auto cb3 = new CheckBox(tr("Read only")).checked(editor.readOnly);
    auto cb4 = new CheckBox(tr("Fixed font")).checked(editor.fontFamily == FontFamily.monospace);
    auto cb5 = new CheckBox(tr("Tab size 8")).checked(editor.tabSize == 8);
    cb1.checkChanged ~= (w, checked) { editor.wantTabs = checked; };
    cb2.checkChanged ~= (w, checked) { editor.useSpacesForTabs = checked; };
    cb3.checkChanged ~= (w, checked) { editor.readOnly = checked; };
    cb4.checkChanged ~= (w, checked) {
        if (checked)
            editor.fontFace("Courier New").fontFamily(FontFamily.monospace);
        else
            editor.fontFace("Arial").fontFamily(FontFamily.sans_serif);
    };
    cb5.checkChanged ~= (w, checked) { editor.tabSize(checked ? 8 : 4); };
    res.addChild(cb1);
    res.addChild(cb2);
    res.addChild(cb3);
    res.addChild(cb4);
    res.addChild(cb5);
    return res;
}

Widget addSourceEditorControls(Widget base, SourceEdit editor)
{
    auto cb1 = new CheckBox(tr("Show line numbers")).checked(editor.showLineNumbers);
    cb1.checkChanged ~= (w, checked) { editor.showLineNumbers = checked; };
    base.addChild(cb1);
    return base;
}
