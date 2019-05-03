module app;

import beamui;

/// Entry point for application
int main()
{
    // you can embed resources into the executable
    resourceList.embed!"resources.list";
    // and you can setup resource paths; not required if only embedded resources are used
    // beware the order: it must be before any resource loading, like theme
    /+
    string[] resourceDirs = [ // will use only existing directories
        appendPath(exePath, "resources/"), // at the same directory as executable
        appendPath(exePath, "../resources/"), // at the dub project directory
    ];
    resourceList.resourceDirs = resourceDirs;
    +/
    // initialize the library
    GuiApp app;
    app.conf.theme = "light";
    if (!app.initialize())
        return -1;

    // you can change default log level, e.g. always use trace, even for release builds
    //Log.setLogLevel(LogLevel.trace);
    // direct logs to a file
    //Log.setFileLogger(new std.stdio.File("ui.log", "w"));

    // you can override default hinting mode (normal, autohint, disabled)
    FontManager.hintingMode = HintingMode.normal;
    // you can override antialiasing setting
    // fonts with size less than specified value will not be antialiased
    FontManager.minAntialiasedFontSize = 0;
    // you can turn on subpixel font rendering (ClearType)
    FontManager.subpixelRenderingMode = SubpixelRenderingMode.none; // bgr, rgb


    // create a window
    // expand window size if content is bigger than defaults
    auto window = platform.createWindow("Controls overview - beamui");

    // create main content layout (0 is for no spacing between parts)
    auto frame = new Column(0);

    TabWidget tabs;

    //=========================================================================
    // create main menu

    auto fileOpenAction = new Action("&Open", "document-open", KeyCode.O, KeyMods.control);
    fileOpenAction.bind(frame, {
        auto dlg = new FileDialog("Open Text File"d, window);
        dlg.allowMultipleFiles = true;
        dlg.addFilter(FileFilterEntry("All files", "*"));
        dlg.addFilter(FileFilterEntry("Text files", "*.txt;*.log"));
        dlg.addFilter(FileFilterEntry("Source files", "*.d;*.dd;*.c;*.cpp;*.h;*.hpp"));
        dlg.addFilter(FileFilterEntry("Executable files", "*", true));
        dlg.dialogClosed ~= (const Action result) {
            import std.path : baseName;

            if (result is ACTION_OPEN)
            {
                string[] filenames = dlg.filenames;
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
    auto fileSaveAction = new Action("&Save", "document-save", KeyCode.S, KeyMods.control);
    auto fileExitAction = new Action("E&xit", "document-close", KeyCode.X, KeyMods.alt);
    fileExitAction.bind(frame, &window.close);


    auto mainMenu = new MenuBar;
    auto fileMenu = mainMenu.addSubmenu("&File");
    fileMenu.add(fileOpenAction, fileSaveAction);
    auto openRecentMenu = fileMenu.addSubmenu("Open recent", "document-open-recent");
    openRecentMenu.addAction("&1: File 1"d);
    openRecentMenu.addAction("&2: File 2"d);
    openRecentMenu.addAction("&3: File 3"d);
    openRecentMenu.addAction("&4: File 4"d);
    openRecentMenu.addAction("&5: File 5"d);
    fileMenu.add(fileExitAction);

    auto editMenu = mainMenu.addSubmenu("&Edit");
    editMenu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);
    editMenu.addSeparator();
    editMenu.addAction("&Preferences");

    auto viewMenu = mainMenu.addSubmenu("&View");
    auto themeMenu = viewMenu.addSubmenu("&Theme");
    {
        Action def = new Action("Default").setCheckable(true);
        Action light = new Action("Light").setCheckable(true).setChecked(true);
        Action dark = new Action("Dark").setCheckable(true);
        def.bind(frame, { platform.uiTheme = "default"; });
        light.bind(frame, { platform.uiTheme = "light"; });
        dark.bind(frame, { platform.uiTheme = "dark"; });
        themeMenu.addActionGroup(def, light, dark);
    }

    auto windowMenu = mainMenu.addSubmenu("&Window");
    windowMenu.addAction("&Preferences");
    windowMenu.addSeparator();
    windowMenu.addAction("Minimize").bind(frame, { window.minimize(); });
    windowMenu.addAction("Maximize").bind(frame, { window.maximize(); });
    windowMenu.addAction("Restore").bind(frame, { window.restore(); });

    auto helpMenu = mainMenu.addSubmenu("&Help");
    helpMenu.addAction("&View help")
        .bind(frame, {
            platform.openURL("https://github.com/dayllenger/beamui");
        });
    helpMenu.addAction("&About")
        .bind(frame, {
            window.showMessageBox("About"d,
                "beamui demo app\n(c) dayllenger, 2018\nhttp://github.com/dayllenger/beamui"d);
        });

    frame.add(mainMenu);

    // create popup menu for edit widgets
    auto editorPopupMenu = new Menu;
    editorPopupMenu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);

    //=========================================================================
    // create tabs

    tabs = new TabWidget;
    tabs.tabClosed ~= (string tabID) { tabs.removeTab(tabID); };
    tabs.tabChanged ~= (string newTabID, string oldTabID) {
        window.title = tabs.tab(newTabID).text ~ " - controls overview - beamui"d;
    };

    // most of controls example
    {
        auto controls = new Column;
            auto line1 = new Row;
                auto gb = new GroupBox("CheckBox"d);
                auto gb2 = new GroupBox("RadioButton"d);
                auto col1 = new Column;
                    auto gb3 = new GroupBox("Button"d, Orientation.horizontal);
                    auto gb4 = new GroupBox("Button with icon and text"d, Orientation.horizontal);
                    auto gbtext = new GroupBox("Label"d, Orientation.horizontal);
                auto col2 = new Column;
                    auto gb21 = new GroupBox("Button with Action"d);
                        auto btnToggle = new Button("Toggle action above"d, null, true);
                    auto gb22 = new GroupBox("ImageWidget"d);
                auto col3 = new Column;
                    auto gb31 = new GroupBox("SwitchButton"d);
            auto line2 = new Row;
                auto gb5 = new GroupBox("Slider and Scrollbar"d, Orientation.horizontal);
                    auto sl = new Slider(Orientation.horizontal);
                    auto sb = new ScrollBar(Orientation.horizontal);
                auto gb6 = new GroupBox("EditLine"d, Orientation.horizontal);
            auto line3 = new Row;
                auto gbeditbox = new GroupBox("EditBox"d);
                    auto edbox = new EditBox("Some text in EditBox\nOne more line\nYet another text line");
                auto gbtabs = new GroupBox("TabWidget"d);
                    auto tabs1 = new TabWidget;
            auto line4 = new Row;
                auto gbgrid = new GroupBox("StringGridWidget"d);
                    auto grid = new StringGridWidget;
                auto gbtree = new GroupBox("TreeWidget"d, Orientation.vertical);
                    auto tree = new TreeWidget;
                    auto newTreeItemForm = new Column;
                        auto newTreeItemEd = new EditLine("new item"d);
                        auto newTreeItemFormRow = new Row;
                            auto btnAddItem = new Button("Add"d);
                            auto btnRemoveItem = new Button("Remove"d);

        with (controls) {
            style.padding = 12;
            add(line1, line2, line3, line4);
            with (line1) {
                add(gb, gb2, col1, col2, col3);
                with (gb) {
                    add(new CheckBox("CheckBox 1"d),
                        new CheckBox("CheckBox 2"d).setChecked(true),
                        new CheckBox("CheckBox disabled"d).setEnabled(false),
                        new CheckBox("CheckBox disabled"d).setEnabled(false).setChecked(true));
                }
                with (gb2) {
                    add(new RadioButton("RadioButton 1"d).setChecked(true),
                        new RadioButton("RadioButton 2"d),
                        new RadioButton("RadioButton disabled"d).setEnabled(false));
                }
                with (col1) {
                    add(gb3, gb4, gbtext);
                    with (gb3) {
                        add(new Button("Button"d),
                            new Button("Button disabled"d).setEnabled(false));
                    }
                    with (gb4) {
                        add(new Button("Enabled"d, "document-open"),
                            new Button("Disabled"d, "document-save").setEnabled(false));
                    }
                    with (gbtext) {
                        auto l1 = new Label("Red text"d);
                        auto l2 = new Label("Italic text"d);
                        l1.style.fontSize = 18;
                        l1.style.textColor = 0xFF0000;
                        l2.style.fontSize = 18;
                        l2.style.fontItalic = true;
                        add(l1, l2);
                    }
                }
                with (col2) {
                    add(gb21, gb22);
                    with (gb21) {
                        auto btn = new Button(fileOpenAction);
                        btn.orientation = Orientation.vertical;
                        add(btn, btnToggle);
                    }
                    with (gb22) {
                        add(new ImageWidget("cr3_logo"));
                    }
                }
                with (col3) {
                    add(gb31);
                    with (gb31) {
                        add(new SwitchButton(),
                            new SwitchButton().setChecked(true),
                            new SwitchButton().setEnabled(false),
                            new SwitchButton().setEnabled(false).setChecked(true));
                    }
                }
            }
            with (line2) {
                add(gb5).setFillWidth(true);
                add(gb6);
                with (gb5) {
                    add(sb).setFillWidth(true);
                    add(sl).setFillWidth(true);
                }
                with (gb6) {
                    auto ed1 = new EditLine("Some text"d);
                    auto ed2 = new EditLine("Some text"d);
                    ed1.style.minWidth = 150;
                    ed2.style.minWidth = 150;
                    ed2.enabled = false;
                    add(ed1, ed2);
                }
            }
            with (line3) {
                add(gbeditbox).setFillWidth(true);
                add(gbtabs);
                with (gbeditbox) {
                    add(edbox).setFillHeight(true);
                }
                with (gbtabs) {
                    add(tabs1);
                    with (tabs1) {
                        tabHost.style.padding = 10;
                        tabHost.style.backgroundColor = 0xE0E0E0;
                        auto tab1 = new MultilineLabel("Label on tab page\nLabels can be\nMultiline"d);
                        auto tab2 = new ImageWidget("beamui-logo");
                        addTab(tab1.setID("tab1"), "Tab 1"d);
                        addTab(tab2.setID("tab2"), "Tab 2"d);
                    }
                }
            }
            with (line4) {
                add(gbgrid).setFillWidth(true);
                add(gbtree);
                with (gbgrid) {
                    add(grid).setFillHeight(true);
                }
                with (gbtree) {
                    add(tree, newTreeItemForm);
                    with (newTreeItemForm) {
                        add(newTreeItemEd);
                        add(newTreeItemFormRow).setFillWidth(false).setAlignment(Align.right);
                        with (newTreeItemFormRow) {
                            add(btnAddItem, btnRemoveItem);
                        }
                    }
                }
            }
        }

        btnToggle.checked = fileOpenAction.enabled;
        btnToggle.clicked ~= {
            fileOpenAction.enabled = !fileOpenAction.enabled;
        };

        sb.scrolled ~= (ScrollEvent event) { Log.d("scrollbar: ", event.action); };
        sl.scrolled ~= (ScrollEvent event) { Log.d("slider: ", event.action); };

        import std.random : uniform;

        grid.resize(12, 10);
        foreach (index, month; ["January"d, "February"d, "March"d, "April"d, "May"d, "June"d,
                "July"d, "August"d, "September"d, "October"d, "November"d, "December"d])
        {
            grid.setColTitle(cast(int)index, month);
        }
        foreach (y; 0 .. grid.rows)
        {
            grid.setRowTitle(y, to!dstring(y + 1));
        }
        foreach (x; 0 .. grid.cols)
        {
            foreach (y; 0 .. grid.rows)
            {
                int n = uniform(0, 10000);
                grid.setCellText(x, y, "%.2f"d.format(n / 100.0));
            }
        }
        //grid.alignment = Align.right;
        grid.setColWidth(0, 30);
        grid.autoFit();

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
        tree.items.selectItem(tree1);
        // test adding new tree items
        btnAddItem.clicked ~= {
            dstring label = newTreeItemEd.text;
            string id = format("item%d", uniform(1000000, 9999999));
            TreeItem item = tree.items.selectedItem;
            if (item)
            {
                Log.d("Creating new tree item `", label, "` with id: ", id);
                TreeItem newItem = new TreeItem(id, label);
                item.addChild(newItem);
            }
        };
        btnRemoveItem.clicked ~= {
            TreeItem item = tree.items.selectedItem;
            if (item)
            {
                Log.d("Removing tree item `", item.text, "` with id: ", item.id);
                item.parent.removeChild(item);
            }
        };

        tabs.addTab(controls.setID("CONTROLS"), "Controls");
    }

    // indicators
    {
        auto indicators = new Column;

        auto pb = new ProgressBar;
        pb.data.progress = 250;
        pb.animationInterval = 50;
        indicators.add(pb);

        tabs.addTab(indicators.setID("INDICATORS"), "Indicators");
    }

    // two long lists
    // left one is list with widgets as items
    // right one is list with string list adapter
    {
        auto longLists = new Row;
            auto list = new ListWidget(Orientation.vertical);
            auto list2 = new StringListWidget;
            auto itemedit = new Column;
                auto itemtext = new EditLine("Text for new item"d);
                auto addbtn = new Button("Add item"d);

        with (longLists) {
            add(list).setFillWidth(true);
            add(list2).setFillWidth(true);
            add(itemedit);
            with (itemedit) {
                style.padding = Insets(0, 6);
                add(new Label("New item text:"d), itemtext, addbtn);
            }
        }

        auto listAdapter = new WidgetListAdapter;
        listAdapter.add(new Label("This is a list of widgets"d));
        list.ownAdapter = listAdapter;
        list.selectItem(0);

        auto stringList = new StringListAdapter;
        stringList.add("This is a list of strings from StringListAdapter"d);
        stringList.add("If you type with your keyboard,"d);
        stringList.add("then you can find the"d);
        stringList.add("item in the list"d);
        stringList.add("neat!"d);
        list2.ownAdapter = stringList;
        list2.selectItem(0);

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

        addbtn.clicked ~= {
            stringList.add(itemtext.text);
            listAdapter.add(new Label(itemtext.text));
        };

        tabs.addTab(longLists.setID("LISTS"), "Long list");
    }

    // form as a table layout
    {
        auto table = new TableLayout;
        table.colCount = 2;
        // headers
        table.addChild(new Label("Parameter"d));
        table.addChild(new Label("Field"d));
        // row 1
        table.addChild(new Label("First Name"d));
        table.addChild(new EditLine("John"d));
        // row 2, disabled
        table.addChild(new Label("Last Name"d).setEnabled(false));
        table.addChild(new EditLine("Doe"d).setEnabled(false));
        // row 3, normal readonly combo box
        table.addChild(new Label("Country"d));
        auto combo1 = new ComboBox(["Australia"d, "Canada"d, "France"d, "Germany"d,
                "Italy"d, "Poland"d, "Russia"d, "Spain"d, "UK"d, "USA"d]);
        combo1.selectedItemIndex = 3;
        table.addChild(combo1);
        // row 4, disabled readonly combo box
        table.addChild(new Label("City"d));
        auto combo2 = new ComboBox(["none"d]);
        combo2.enabled = false;
        combo2.selectedItemIndex = 0;
        table.addChild(combo2);

        tabs.addTab(table.setID("TABLE"), "Table layout");
    }

    // editors
    {
        dstring sourceCode = q{#!/usr/bin/env rdmd
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
        auto editors = new Column;
            auto editLineLabel = new Label("EditLine: Single line editor"d);
            auto editLine = new EditLine("Single line editor sample text");
            auto editorLabel1 = new Label("SourceEdit: multiline editor, for source code editing"d);
            auto sourceEditor1 = new SourceEdit;
            auto editorLabel2 = new Label("SourceEdit: additional view for the same content"d);
            auto sourceEditor2 = new SourceEdit;

            auto editLineControl = createBaseEditorSettingsControl(editLine); // see after UIAppMain
            auto editorControl = createBaseEditorSettingsControl(sourceEditor1)
                .addSourceEditorControls(sourceEditor1);

        with (editors) {
            add(editLineLabel, editLineControl, editLine);
            add(editorLabel1, editorControl);
            add(sourceEditor1).setFillHeight(true);
            add(editorLabel2);
            add(sourceEditor2).setFillHeight(true);
            with (editLine) {
                popupMenu = editorPopupMenu;
            }
            with (sourceEditor1) {
                text = sourceCode;
                popupMenu = editorPopupMenu;
                showIcons = true;
            }
            with (sourceEditor2) {
                content = sourceEditor1.content; // view the same content as first editbox
            }
        }

        tabs.addTab(editors.setID("EDITORS"), "Editors");
    }

    // string grid
    {
        auto gridTab = new Column;
            auto gridSettings = new Row;
                auto cb1 = new CheckBox("Full column on left"d);
                auto cb2 = new CheckBox("Full row on top"d);
            auto grid = new StringGridWidget;

        with (gridTab) {
            add(gridSettings);
            add(grid).setFillHeight(true);
            with (gridSettings) {
                add(cb1, cb2);
                cb1.tooltipText = "Extends scroll area to show full column at left when scrolled to rightmost column"d;
                cb2.tooltipText = "Extends scroll area to show full row at top when scrolled to end row"d;
            }
            with (grid) {
                showColHeaders = true;
                showRowHeaders = true;
            }
        }

        cb1.checked = grid.fullColumnOnLeft;
        cb2.checked = grid.fullRowOnTop;
        cb1.toggled ~= (checked) { grid.fullColumnOnLeft = checked; };
        cb2.toggled ~= (checked) { grid.fullRowOnTop = checked; };

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

        tabs.addTab(gridTab.setID("GRID"), "Grid");
    }

    // charts
    {
        auto barChart1 = new SimpleBarChart("SimpleBarChart Example"d);
        barChart1.addBar(12.0, Color(255, 0, 0), "Red bar"d);
        barChart1.addBar(24.0, Color(0, 255, 0), "Green bar"d);
        barChart1.addBar(5.0, Color(0, 0, 255), "Blue bar"d);
        barChart1.addBar(12.0, Color(230, 126, 34), "Orange bar"d);

        auto barChart2 = new SimpleBarChart("SimpleBarChart Example - long descriptions"d);
        barChart2.addBar(12.0, Color(255, 0, 0), "Red bar\n(12.0)"d);
        barChart2.addBar(24.0, Color(0, 255, 0), "Green bar\n(24.0)"d);
        barChart2.addBar(5.0, Color(0, 0, 255), "Blue bar\n(5.0)"d);
        barChart2.addBar(12.0, Color(230, 126, 34), "Orange bar\n(12.0)\nlong long long description added here"d);

        auto barChart3 = new SimpleBarChart("SimpleBarChart Example with axis ratio 0.3"d);
        barChart3.addBar(12.0, Color(255, 0, 0), "Red bar"d);
        barChart3.addBar(24.0, Color(0, 255, 0), "Green bar"d);
        barChart3.addBar(5.0, Color(0, 0, 255), "Blue bar"d);
        barChart3.addBar(12.0, Color(230, 126, 34), "Orange bar"d);
        barChart3.axisRatio = 0.3;

        auto barChart4 = new SimpleBarChart("SimpleBarChart Example with axis ratio 1.3"d);
        barChart4.addBar(12.0, Color(255, 0, 0), "Red bar"d);
        barChart4.addBar(24.0, Color(0, 255, 0), "Green bar"d);
        barChart4.addBar(5.0, Color(0, 0, 255), "Blue bar"d);
        barChart4.addBar(12.0, Color(230, 126, 34), "Orange bar"d);
        barChart4.axisRatio = 1.3;

        auto chartsLayout = new Row;
        with (chartsLayout) {
            auto col1 = new Column;
            auto col2 = new Column;
            with (col1) {
                add(barChart1, barChart2);
            }
            with (col2) {
                add(barChart3, barChart4);
            }
            add(col1, col2);
        }

        tabs.addTab(chartsLayout.setID("CHARTS"), "Charts");
    }

    // animation
    static if (BACKEND_GUI)
    {
    }

    //==========================================================================

    tabs.selectTab("CONTROLS");
    frame.add(tabs).setFillHeight(true);

    window.mainWidget = frame;
    static if (BACKEND_GUI)
        window.icon = imageCache.get("beamui-logo");
    window.show();

    return platform.enterMessageLoop();
}

Widget createBaseEditorSettingsControl(EditWidgetBase editor)
{
    auto row = new Row;
    auto cb1 = new CheckBox("Catch tabs");
    auto cb2 = new CheckBox("Use spaces for indentation");
    auto cb3 = new CheckBox("Read only");
    auto cb4 = new CheckBox("Fixed font");
    auto cb5 = new CheckBox("Tab size 8");
    row.add(cb1, cb2, cb3, cb4, cb5);

    cb1.checked = editor.wantTabs;
    cb2.checked = editor.useSpacesForTabs;
    cb3.checked = editor.readOnly;
    cb4.checked = editor.style.fontFamily == FontFamily.monospace;
    cb5.checked = editor.tabSize == 8;
    cb1.toggled ~= (checked) { editor.wantTabs = checked; };
    cb2.toggled ~= (checked) { editor.useSpacesForTabs = checked; };
    cb3.toggled ~= (checked) { editor.readOnly = checked; };
    cb4.toggled ~= (checked) {
        if (checked)
        {
            editor.style.fontFace = "Courier New";
            editor.style.fontFamily = FontFamily.monospace;
        }
        else
        {
            editor.style.fontFace = "Arial";
            editor.style.fontFamily = FontFamily.sans_serif;
        }
    };
    cb5.toggled ~= (checked) { editor.tabSize(checked ? 8 : 4); };

    return row;
}

Widget addSourceEditorControls(Widget base, SourceEdit editor)
{
    auto cb1 = new CheckBox("Show line numbers");
    base.addChild(cb1);
    cb1.checked = editor.showLineNumbers;
    cb1.toggled ~= (checked) { editor.showLineNumbers = checked; };
    return base;
}
