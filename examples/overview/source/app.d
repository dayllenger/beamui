/// Widget overview. No functionality, just appearance and basic behaviour.
module app;

import beamui;
import std.conv : dtext;

mixin RegisterPlatforms;

int main()
{
    // you can embed resources into the executable
    resourceList.embed!"resources.list";
    // and you can setup resource paths; not required if only embedded resources are used.
    // it will use existing directories only.
    // beware the order: it must be before any resource loading, like theme.
    /+
    resourceList.resourceDirs = [
        appendPath(exePath, "resources/"), // at the same directory as executable
        appendPath(exePath, "../resources/"), // at the dub project directory
    ];
    +/

    // initialize the library
    GuiApp app;
    if (!app.initialize())
        return -1;

    platform.stylesheets = [StyleResource("light"), StyleResource("style")];

    // you can change default log level, e.g. always use trace, even for release builds
    //Log.setLogLevel(LogLevel.trace);
    // direct logs to a file
    //Log.setFileLogger(new std.stdio.File("ui.log", "w"));

    // you can set font hinting mode and antialiasing settings
    FontManager.hintingMode = HintingMode.normal;
    // fonts with size less than specified value will not be antialiased
    FontManager.minAntialiasedFontSize = 0;
    // you can turn on subpixel font rendering (ClearType-like)
    FontManager.subpixelRenderingMode = SubpixelRenderingMode.none; // bgr, rgb

    // by default, window will expand if it's smaller than its content
    Window window = platform.createWindow("Controls overview - beamui");

    window.show(() => render!App);
    return platform.runEventLoop();
}

class App : Panel
{
    override void build()
    {
        wrap(
            render((Tabs tabs) {
                tabs.onSelect = (item) {
                    const ti = cast(TabItem)item;
                    window.title = ti.text ~ " overview - beamui"d;
                };
            }).wrap(
                TabPair(
                    (TabItem ti) { ti.text = "Controls"; },
                    (TabForControls tab) {}
                ),
                TabPair(
                    (TabItem ti) { ti.text = "Editors"; },
                    (TabForEditors tab) {}
                ),
                TabPair(
                    (TabItem ti) { ti.text = "Lists"; },
                    (TabForLists tab) {}
                ),
                TabPair(
                    (TabItem ti) { ti.text = "Charts"; },
                    (TabForCharts tab) {}
                ),
            )
        );
    }
}

/// Most of basic controls and indicators
class TabForControls : Panel
{
    enum Options { one, two, three, }

    static class State : WidgetState
    {
        Action fileOpenAction;
        EditableContent content;

        bool dummyBool;
        Options dummyOption;
        double dummyValue = 0.5;
        double[2] dummyRange = [2, 6];

        this()
        {
            fileOpenAction = new Action("&Open", "document-open", Key.O, KeyMods.control);
            content = new EditableContent;
            content.text = "Some text in TextArea\nOne more line\nYet another text line";
        }
    }

    override State createState()
    {
        return new State;
    }

    override void build()
    {
        State st = use!State;
        wrap(
            render((Panel p) {}).wrap(
                render((Panel p) {}).wrap(
                    render((GroupBox gb) {
                        gb.caption = "Label";
                        gb.attributes["labels"];
                    }).wrap(
                        render((Label l1) {
                            l1.text = "Red text";
                            l1.attributes["l-1"];
                        }),
                        render((Label l2) {
                            l2.text = "Italic text";
                            l2.attributes["l-2"];
                        }),
                        render((Label l) {
                            l.text = "Lorem ipsum\ndolor sit amet\nconsectetur\nadipisicing elit.\nIllo, tenetur.";
                            l.attributes["lorem"];
                        }),
                        render((Link link) {
                            link.url = "https://github.com/dayllenger/beamui";
                        }).wrap(
                            render((Label t) { t.text = "Go to GitHub page"; })
                        ),
                    ),
                ),
                render((Panel p) {}).wrap(
                    render((GroupBox gb) {
                        gb.caption = "ImageWidget";
                    }).wrap(
                        render((ImageWidget iw) {
                            iw.imageID = "cr3_logo";
                        })
                    ),
                    render((GroupBox gb) {
                        gb.caption = "SwitchButton";
                    }).wrap(
                        render((SwitchButton sb) {
                            sb.checked = st.dummyBool;
                            sb.onToggle = (v) { setState(st.dummyBool, v); };
                        }),
                        render((SwitchButton sb) {
                            sb.checked = !st.dummyBool;
                            sb.onToggle = (v) { setState(st.dummyBool, !v); };
                        }),
                        render((SwitchButton sb) {}),
                        render((SwitchButton sb) { sb.checked = true; }),
                    ),
                ),
                render((Panel p) {}).wrap(
                    render((GroupBox gb) {
                        gb.caption = "CheckBox";
                    }).wrap(
                        render((CheckBox cb) {
                            cb.text = "Option 1";
                            cb.checked = st.dummyBool;
                            cb.onToggle = (v) { setState(st.dummyBool, v); };
                        }),
                        render((CheckBox cb) {
                            cb.text = "Option 2";
                            cb.checked = !st.dummyBool;
                            cb.onToggle = (v) { setState(st.dummyBool, !v); };
                        }),
                        render((CheckBox cb) {
                            cb.text = "Option 3";
                        }),
                        render((CheckBox cb) {
                            cb.text = "Option 4";
                            cb.checked = true;
                        }),
                    ),
                    render((GroupBox gb) {
                        gb.caption = "RadioButton";
                    }).wrap(
                        render((RadioButton rb) {
                            rb.text = "Option 1";
                            rb.checked = st.dummyOption == Options.one;
                            rb.onToggle = (v) { setState(st.dummyOption, Options.one); };
                        }),
                        render((RadioButton rb) {
                            rb.text = "Option 2";
                            rb.checked = st.dummyOption == Options.two;
                            rb.onToggle = (v) { setState(st.dummyOption, Options.two); };
                        }),
                        render((RadioButton rb) {
                            rb.text = "Option 3";
                            rb.checked = st.dummyOption == Options.three;
                        }),
                    ),
                ),
                render((Panel p) {}).wrap(
                    render((GroupBox gb) {
                        gb.caption = "Button";
                    }).wrap(
                        render((Button b) {
                            b.text = "Enabled";
                            b.onClick = { Log.d("click"); };
                        }),
                        render((Button b) {
                            b.text = "Disabled";
                        }),
                        render((Button b) {
                            b.text = "Enabled";
                            b.iconID = "document-open";
                            b.onClick = { Log.d("click"); };
                        }),
                        render((Button b) {
                            b.text = "Disabled";
                            b.iconID = "document-save";
                        }),
                    ),
                    render((GroupBox gb) {
                        gb.caption = "More buttons";
                    }).wrap(
                        render((ActionButton ab) {
                            ab.action = st.fileOpenAction;
                        }),
                        render((CheckButton b) {
                            b.text = "Toggle the action above";
                            b.checked = st.fileOpenAction.enabled;
                            b.onToggle = (v) {
                                setState(v, !v); // temporary hack
                                st.fileOpenAction.enabled = !v;
                            };
                        }),
                    ),
                ),
            ),
            render((Panel p) {}).wrap(
                render((GroupBox gb) {
                    gb.caption = "Scrollbar, Slider, RangeSlider, ProgressBar";
                    gb.attributes["stretch"];
                }).wrap(
                    render((ScrollBar sb) {
                        sb.onScroll = (action, pos) {
                            Log.d("scrollbar: ", action);
                            return true;
                        };
                    }),
                    render((Slider sl) {
                        sl.value = st.dummyValue;
                        sl.minValue = -0.75;
                        sl.maxValue = 0.75;
                        sl.step = 0.1;
                        sl.onChange = (v) {
                            Log.d("slider: ", v);
                            setState(st.dummyValue, v);
                        };
                    }),
                    render((RangeSlider sl) {
                        sl.first = st.dummyRange[0];
                        sl.second = st.dummyRange[1];
                        sl.minValue = 0;
                        sl.maxValue = 10;
                        sl.step = 0.1;
                        sl.pageStep = 100;
                        sl.onChange = (a, b) {
                            Log.fd("range-slider: (%s, %s)", a, b);
                            setState(st.dummyRange[0], a);
                            setState(st.dummyRange[1], b);
                        };
                    }),
                    render((ProgressBar pb) {
                        pb.progress = PROGRESS_HIDDEN;
                    }),
                ),
            ),
            render((Panel p) {}).wrap(
                render((GroupBox gb) {
                    gb.caption = "TextField";
                }).wrap(
                    render((TextField ed) {
                        ed.placeholder = "Name";
                    }),
                    render((TextField ed) {
                        ed.placeholder = "Password";
                        ed.passwordChar = '•';
                    }),
                    render((TextField ed) {
                        ed.text = "Read-only";
                        ed.readOnly = true;
                    }),
                ),
                render((GroupBox gb) {
                    gb.caption = "TextArea";
                    gb.attributes["stretch"];
                }).wrap(
                    render((TextArea ed) {
                        ed.content = st.content;
                        ed.attributes["stretch"];
                    })
                ),
            ),
        );
    }
}

class TabForEditors : Panel
{
    static class State : WidgetState
    {
        dstring text = "Single line editor sample text";
        EditableContent content;

        this()
        {
            content = new EditableContent;
            content.text = q{#!/usr/bin/env rdmd
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
        }
    }

    override State createState()
    {
        return new State;
    }

    override void build()
    {
        State st = use!State;
        wrap(
            render((Label t) {
                t.text = "TextField: single-line editor";
            }),
            render((TextFieldWithSettings ed) {
                ed.text = st.text;
                ed.onChange = (str) { setState(st.text, str); };
            }),
            render((Label t) {
                t.text = "SourceEdit: multiline editor, for source code editing";
            }),
            render((SourceEditorWithSettings ed) {
                ed.content = st.content;
            }),
            render((Label t) {
                t.text = "TextArea: additional view on the same content";
            }),
            render((TextArea ed) {
                ed.content = st.content; // view the same content as the first editor
            }),
        );
    }
}

class TextFieldWithSettings : Panel
{
    dstring text;
    void delegate(dstring) onChange;

    static class State : WidgetState
    {
        bool readOnly;
        bool catchTabs;
        int tabSize = 4;
        FontFamily fontFamily = FontFamily.sans_serif;
    }

    override State createState()
    {
        return new State;
    }

    override void build()
    {
        State st = use!State;
        wrap(
            render((Panel p) {
                p.attributes["settings"];
            }).wrap(
                render((CheckBox cb) {
                    cb.text = "Read only";
                    cb.checked = st.readOnly;
                    cb.onToggle = (v) { setState(st.readOnly, v); };
                }),
                render((CheckBox cb) {
                    cb.text = "Catch tabs";
                    cb.checked = st.catchTabs;
                    cb.onToggle = (v) { setState(st.catchTabs, v); };
                }),
                render((CheckBox cb) {
                    cb.text = "Tab size 8";
                    cb.checked = st.tabSize == 8;
                    cb.onToggle = (v) { setState(st.tabSize, v ? 8 : 4); };
                }),
                render((CheckBox cb) {
                    cb.text = "Fixed font";
                    cb.checked = st.fontFamily == FontFamily.monospace;
                    cb.onToggle = (v) { setState(st.fontFamily, v ? FontFamily.monospace : FontFamily.sans_serif); };
                }),
            ),
            render((TextField ed) {
                ed.text = text;
                ed.onChange = onChange;
                ed.readOnly = st.readOnly;
                ed.wantTabs = st.catchTabs;
            }),
        );
    }
}

class SourceEditorWithSettings : Panel
{
    EditableContent content;

    static class State : WidgetState
    {
        bool readOnly;
        bool catchTabs = true;
        int tabSize = 4;
        FontFamily fontFamily = FontFamily.monospace;

        bool useSpaces = true;
        bool lineNumbers = true;
    }

    override State createState()
    {
        return new State;
    }

    override void build()
    {
        State st = use!State;
        wrap(
            render((Panel p) {
                p.attributes["settings"];
            }).wrap(
                render((CheckBox cb) {
                    cb.text = "Read only";
                    cb.checked = st.readOnly;
                    cb.onToggle = (v) { setState(st.readOnly, v); };
                }),
                render((CheckBox cb) {
                    cb.text = "Catch tabs";
                    cb.checked = st.catchTabs;
                    cb.onToggle = (v) { setState(st.catchTabs, v); };
                }),
                render((CheckBox cb) {
                    cb.text = "Tab size 8";
                    cb.checked = st.tabSize == 8;
                    cb.onToggle = (v) { setState(st.tabSize, v ? 8 : 4); };
                }),
                render((CheckBox cb) {
                    cb.text = "Use spaces for indentation";
                    cb.checked = st.useSpaces;
                    cb.onToggle = (v) { setState(st.useSpaces, v); };
                }),
                render((CheckBox cb) {
                    cb.text = "Show line numbers";
                    cb.checked = st.lineNumbers;
                    cb.onToggle = (v) { setState(st.lineNumbers, v); };
                }),
                render((CheckBox cb) {
                    cb.text = "Fixed font";
                    cb.checked = st.fontFamily == FontFamily.monospace;
                    cb.onToggle = (v) { setState(st.fontFamily, v ? FontFamily.monospace : FontFamily.sans_serif); };
                }),
            ),
            render((SourceEdit ed) {
                ed.content = content;
                ed.showIcons = true;
                ed.readOnly = st.readOnly;
                ed.wantTabs = st.catchTabs;
                ed.useSpacesForTabs = st.useSpaces;
                ed.showLineNumbers = st.lineNumbers;
            }),
        );
    }
}

/// List controls & combo boxes
class TabForLists : Panel
{
    static class State : WidgetState
    {
        TypeInfo_Class[] classes;
        dstring[] classNames;

        TypeInfo_Class selectedClass;
        TypeInfo_Class selectedDetail;

        this()
        {
            foreach (m; ModuleInfo)
            {
                if (m)
                    foreach (c; m.localClasses)
                        if (c)
                        {
                            classes ~= c;
                            classNames ~= c.name.to!dstring;
                        }
            }
        }
    }

    override State createState()
    {
        return new State;
    }

    override void build()
    {
        import std.array : array;
        import std.algorithm : map, splitter;
        import std.string : join;
        import beamui.graphics.colors : decodeHexColor, decodeTextColor;

        State st = use!State;

        // make color names so decodeTextColor can parse them
        static immutable dstring[] colorNames = [__traits(allMembers, NamedColor)]
            .map!(a => a.splitter('_').join).array;

        wrap(
            render((Panel p) {}).wrap(
                render((GroupBox gb) {
                    gb.caption = "Symbol List";
                    gb.attributes["labels"];
                }).wrap(
                    render((Label lb) {
                        lb.text = "Symbol name:";
                    }),
                    render((ComboBox cb) {
                        cb.items = st.classNames;
                        cb.onSelect = (i) {
                            setState(st.selectedClass, st.classes[i]);
                            setState(st.selectedDetail, null);
                        };
                    }),
                    render((Label lb) {
                        lb.text = "Color:";
                    }),
                    render((ComboEdit cb) {
                        // TODO: make ComboEdit emit string events, not indexes
                        cb.items = colorNames;
                        cb.onSelect = (i) {
                            auto input = colorNames[i].to!string;

                            auto color = decodeHexColor(input)
                                .or(decodeTextColor(input)
                                .or(Color.transparent));

                            window.backgroundColor = color;
                        };
                    }),
                ),
            ),
            render((Panel p) {}).wrap(
                render((GroupBox gb) {
                    gb.caption = "Runtime Introspection";
                    gb.attributes["labels"];
                }).wrap(
                    render((Label lb) {
                        lb.text = "Selected: " ~ (st.selectedClass ? st.selectedClass.name : "none").to!dstring;
                    }),
                    render((Label lb) {
                        lb.text = "Inheritance:";
                    }),
                    render((ListView lv) {
                        if (!st.selectedClass) {
                            lv.visible = false;
                            return;
                        }

                        dstring[] items;
                        TypeInfo_Class[] context;
                        void dumpRuntimeInfo(TypeInfo_Class type, string indent)
                        {
                            context ~= type;
                            items ~= (indent ~ type.name).to!dstring;

                            if (type.base)
                                dumpRuntimeInfo(type.base, indent ~ "\t");

                            foreach (iface; type.interfaces)
                                if (iface.classinfo) {
                                    items ~= (indent ~ "implements " ~ iface.classinfo.name).to!dstring;
                                    context ~= iface.classinfo;
                                }
                        }

                        assert(items.length == context.length);

                        dumpRuntimeInfo(st.selectedClass, "");

                        lv.visible = true;
                        lv.itemCount = cast(uint)items.length;
                        lv.itemBuilder = i => lv.item(items[i]);
                        lv.onSelect = i => setState(st.selectedDetail, context[i]);
                    }),
                    render((Label lb) {
                        lb.text = "Details:";
                    }),
                    render((ListView lv) {
                        if (!st.selectedDetail) {
                            lv.visible = false;
                            return;
                        }

                        auto t = st.selectedDetail;

                        dstring[] items;
                        items ~= dtext("Name: ", t.name);
                        items ~= dtext("Data size: ", t.initializer.length);
                        static foreach (flag; __traits(allMembers, TypeInfo_Class.ClassFlags))
                        {
                            items ~= dtext(flag, ": ",
                                (t.m_flags & __traits(getMember, TypeInfo_Class.ClassFlags, flag)) != 0
                                    ? "yes" : "no");
                        }

                        lv.visible = true;
                        lv.itemCount = cast(uint)items.length;
                        lv.itemBuilder = i => lv.item(items[i]);
                    }),
                ),
            ),
        );
    }
}

/// Simple charts
class TabForCharts : Panel
{
    const c1 = NamedColor.tomato;
    const c2 = NamedColor.lime_green;
    const c3 = NamedColor.royal_blue;
    const c4 = Color(230, 126, 34);

    const values = [12.0, 24.0, 5.0, 10.0];

    const bars = [
        SimpleBar(c1, "Red bar"),
        SimpleBar(c2, "Green bar"),
        SimpleBar(c3, "Blue bar"),
        SimpleBar(c4, "Orange bar"),
    ];
    const barsLong = [
        SimpleBar(c1, "Red bar\nwith a long long long description"),
        SimpleBar(c2, "Green bar\nwith a long long long description"),
        SimpleBar(c3, "Blue bar\nwith a long long long description"),
        SimpleBar(c4, "Orange bar\nwith a long long long description"),
    ];

    override void build()
    {
        wrap(
            render((SimpleBarChart ch) {
                ch.title = "SimpleBarChart with axis ratio 0.3";
                ch.data = values;
                ch.bars = bars;
                ch.axisRatio = 0.3;
            }),
            render((SimpleBarChart ch) {
                ch.title = "SimpleBarChart with long descriptions";
                ch.data = values;
                ch.bars = barsLong;
            }),
        );
    }
}
/+
    //=========================================================================
    // create main menu

    fileOpenAction.bind(frame, {
        auto dlg = new FileDialog("Open Text File"d, window);
        dlg.allowMultipleFiles = true;
        dlg.addFilter(FileFilterEntry("All files", "*"));
        dlg.addFilter(FileFilterEntry("Text files", "*.txt;*.log"));
        dlg.addFilter(FileFilterEntry("Source files", "*.d;*.dd;*.c;*.cpp;*.h;*.hpp"));
        dlg.addFilter(FileFilterEntry("Executable files", "*", true));
        dlg.onClose ~= (const Action result) {
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
                                new MessageBox(window, "File open error"d, "Cannot open file "d ~ toUTF32(fn)).show();
                            }
                        }
                    }
                    else
                    {
                        new MessageBox(window, "FileOpen result"d, "File with bad extension: "d ~ toUTF32(fn)).show();
                    }
                }
            }
        };
        dlg.show();
    });
    auto fileSaveAction = new Action("&Save", "document-save", Key.S, KeyMods.control);
    auto fileExitAction = new Action("E&xit", "document-close", Key.X, KeyMods.alt);
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
        Action def = Action.makeCheckable("Default");
        Action light = Action.makeCheckable("Light").setChecked(true);
        Action dark = Action.makeCheckable("Dark");
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
            new MessageBox(
                window,
                "About"d,
                "beamui demo app\n(c) dayllenger, 2018\nhttp://github.com/dayllenger/beamui"d,
            ).show();
        });

    frame.add(mainMenu);

    //=========================================================================
    // create tabs

    tabs = new Tabs;
    tabs.onTabClose ~= (string tabID) { tabs.removeTab(tabID); };

    {
            auto line4 = new Panel;
                auto gbgrid = new GroupBox("StringGridWidget"d);
                    auto grid = new StringGridWidget;
                auto gbtree = new GroupBox("TreeWidget"d, Orientation.vertical);
                    auto tree = new TreeWidget;
                    auto newTreeItemForm = new Panel;
                        auto newTreeItemEd = new TextField("new item"d);
                        auto newTreeItemFormRow = new Panel;
                            auto btnAddItem = new Button("Add"d);
                            auto btnRemoveItem = new Button("Remove"d);

            with (line4) {
                add(gbgrid, gbtree);
                with (gbgrid) {
                    add(grid);
                    gbgrid.style.stretch = Stretch.both;
                    grid.style.stretch = Stretch.both;
                }
                with (gbtree) {
                    add(tree, newTreeItemForm);
                    with (newTreeItemForm) {
                        style.display = "column";
                        add(newTreeItemEd, newTreeItemFormRow);
                        with (newTreeItemFormRow) {
                            style.display = "row";
                            style.alignment = Align.right;
                            style.stretch = Stretch.none;
                            add(btnAddItem, btnRemoveItem);
                        }
                    }
                }
            }

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
        btnAddItem.onClick ~= {
            dstring label = newTreeItemEd.text;
            string id = format("item%d", uniform(1000000, 9999999));
            TreeItem item = tree.items.selectedItem;
            if (!item)
                item = tree.items;
            Log.d("Creating new tree item `", label, "` with id: ", id);
            TreeItem newItem = new TreeItem(id, label);
            item.addChild(newItem);
        };
        btnRemoveItem.onClick ~= {
            TreeItem item = tree.items.selectedItem;
            if (item)
            {
                Log.d("Removing tree item `", item.text, "` with id: ", item.id);
                item.parent.removeChild(item);
            }
        };
        tree.onSelect ~= (TreeItem item, bool) {
            btnRemoveItem.enabled = item !is null;
        };
    }

    // two long lists
    // left one is list with widgets as items
    // right one is list with string list adapter
    {
        auto longLists = new Panel;
            auto list = new ListWidget(Orientation.vertical);
            auto list2 = new StringListWidget;
            auto itemedit = new Panel;
                auto itemtext = new TextField("Text for new item"d);
                auto addbtn = new Button("Add item"d);

        with (longLists) {
            style.display = "row";
            add(list, list2, itemedit);
            list.style.stretch = Stretch.both;
            list2.style.stretch = Stretch.both;
            with (itemedit) {
                style.display = "column";
                style.padding = Insets(0, 6);
                add(new Label("New item text:"d), itemtext, addbtn);
            }
        }

        list.addChild(new Label("This is a list of widgets"d));
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
            list.addChild(new Label("Widget list - "d ~ label));
            stringList.add("Simple string - "d ~ label);
        }
        list.child(0).resetState(State.enabled);
        list.child(5).resetState(State.enabled);
        list.child(7).resetState(State.enabled);
        list.child(12).resetState(State.enabled);
        assert(!list.itemEnabled(5));
        assert( list.itemEnabled(6));

        addbtn.onClick ~= {
            stringList.add(itemtext.text);
            list.addChild(new Label(itemtext.text));
        };

        tabs.addTab(longLists.setID("LISTS"), "Long list");
    }

    tabs.addTab(createFormTab(), "Form");

    // string grid
    {
        auto gridTab = new Panel;
            auto gridSettings = new Panel;
                auto cb1 = new CheckBox("Full column on left"d);
                auto cb2 = new CheckBox("Full row on top"d);
            auto grid = new StringGridWidget;

        with (gridTab) {
            style.display = "column";
            add(gridSettings, grid);
            with (gridSettings) {
                style.display = "row";
                add(cb1, cb2);
                cb1.tooltipText = "Extends scroll area to show full column at left when scrolled to rightmost column"d;
                cb2.tooltipText = "Extends scroll area to show full row at top when scrolled to end row"d;
            }
            with (grid) {
                grid.style.stretch = Stretch.both;
                showColHeaders = true;
                showRowHeaders = true;
            }
        }

        cb1.checked = grid.fullColumnOnLeft;
        cb2.checked = grid.fullRowOnTop;
        cb1.onToggle ~= (checked) { grid.fullColumnOnLeft = checked; };
        cb2.onToggle ~= (checked) { grid.fullRowOnTop = checked; };

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

    //==========================================================================

    tabs.selectTab("CONTROLS");
    tabs.style.stretch = Stretch.both;
    frame.add(tabs);
}

Widget createFormTab()
{
    // form as a grid layout
    auto form = new Panel("FORM");
    // headers
    form.addChild(new Label("Parameter"d));
    form.addChild(new Label("Field"d));
    // row 1
    form.addChild(new Label("First Name"d));
    form.addChild(new TextField("John"d));
    // row 2, disabled
    form.addChild(new Label("Last Name"d).setEnabled(false));
    form.addChild(new TextField("Doe"d).setEnabled(false));
    // row 3, normal readonly combo box
    form.addChild(new Label("Country"d));
    auto combo1 = new ComboBox(["Australia"d, "Canada"d, "France"d, "Germany"d,
            "Italy"d, "Poland"d, "Russia"d, "Spain"d, "UK"d, "USA"d]);
    combo1.selectedItemIndex = 3;
    form.addChild(combo1);
    // row 4, disabled readonly combo box
    form.addChild(new Label("City"d));
    auto combo2 = new ComboBox(["none"d]);
    combo2.enabled = false;
    combo2.selectedItemIndex = 0;
    form.addChild(combo2);

    setStyleSheet(currentTheme, `
    TabHost > #FORM {
        display: grid;
        grid-template-columns: auto 120px;
        justify-content: start;
        align-content: start;
    }
    `);

    return form;
}

Widget createTabForEditors()
{
    // create popup menu for edit widgets
    auto editorPopupMenu = new Menu;
    editorPopupMenu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);

    with (editLine) {
        popupMenu = editorPopupMenu;
    }
    with (sourceEditor1) {
        popupMenu = editorPopupMenu;
    }
}

Widget createTextFieldSettingsControl(TextField editor)
{
    cb4.checked = editor.style.fontFamily == FontFamily.monospace;
    cb4.onToggle ~= (checked) {
        editor.style.fontFace = checked ? "Courier New" : "Arial";
        editor.style.fontFamily = checked ? FontFamily.monospace : FontFamily.sans_serif;
    };
}

Widget createSourceEditorSettingsControl(SourceEdit editor)
{
    cb6.checked = editor.style.fontFamily == FontFamily.monospace;
    cb6.onToggle ~= (checked) {
        editor.style.fontFace = checked ? "Courier New" : "Arial";
        editor.style.fontFamily = checked ? FontFamily.monospace : FontFamily.sans_serif;
    };
}
+/
