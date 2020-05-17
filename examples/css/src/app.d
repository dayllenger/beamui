module app;

import beamui;
import beamui.css.syntax;

mixin RegisterPlatforms;

enum DEFAULT_STYLE = "style";

int main()
{
    resourceList.setResourceDirs(
        appendPath(exePath, "resources/"),
        appendPath(exePath, "../resources/"),
    );

    GuiApp app;
    app.conf.theme = "light";
    if (!app.initialize())
        return -1;

    const filename = resourceList.getPathByID(DEFAULT_STYLE);
    const styles = cast(string)loadResourceBytes(filename);
    setStyleSheet(currentTheme, styles);

    Window window1 = platform.createWindow("CSS sandbox - beamui");
    Window window2 = platform.createWindow("CSS hot-reloader", window1, WindowOptions.expanded, 1, 1);

    window1.onClose = {
        window1 = null;
        if (window2)
            window2.close();
    };
    window2.onClose = {
        window2 = null;
        if (window1)
            window1.close();
    };

    window1.show(() => render!Controls);
    window2.show(() => render!CssHotReloadWidget);
    return platform.enterMessageLoop();
}

class CssHotReloadWidget : Panel
{
    protected static class State : IState
    {
        bool watching;
        bool error;

        dstring resourceID = DEFAULT_STYLE;
        FileMonitor fmon;

        void watch(Window win)
        {
            const filename = resourceList.getPathByID(toUTF8(resourceID));
            fmon = FileMonitor(filename);
            if (fmon.check() == FileMonitor.Status.missing)
            {
                setState(error, true);
                return;
            }
            updateStyles();
            win.setTimer(1000, {
                if (!watching)
                    return false;

                const status = fmon.check();
                if (status == FileMonitor.Status.modified)
                {
                    updateStyles();
                }
                else if (status == FileMonitor.Status.missing)
                {
                    setState(watching, false);
                    setState(error, true);
                }
                return true;
            });
            setState(watching, true);
            setState(error, false);
        }

        void updateStyles()
        {
            const filename = resourceList.getPathByID(toUTF8(resourceID));
            const styles = cast(string)loadResourceBytes(filename);
            platform.reloadTheme();
            setStyleSheet(currentTheme, styles);
        }
    }

    override protected void build()
    {
        State st = useState!State;
        wrap(
            render((Label tip) {
                tip.text = "Style resource ID:";
            }),
            render((EditLine ed) {
                ed.text = st.resourceID;
                if (!st.watching)
                    ed.onChange = (s) { st.resourceID = s; };
                else
                    ed.readOnly = true;
            }),
            render((CheckButton b) {
                b.text = "Watch";
                b.checked = st.watching;
                b.onToggle = (v) {
                    if (v)
                        st.watch(window);
                    else
                        setState(st.watching, false);
                };
            }),
            render((Button b) {
                b.text = "Reload manually";
                b.onClick = &st.updateStyles;
            }),
            render((Label tip) {
                if (st.watching)
                {
                    tip.text = "Status: watching";
                    tip.attributes["state"] = "watching";
                }
                else if (st.error)
                {
                    tip.text = "Status: no such file";
                    tip.attributes["state"] = "error";
                }
                else
                    tip.text = "Status: not watching";
            }),
        );
    }
}

class Controls : Panel
{
    protected static class State : IState
    {
        bool dummyBool;
        double dummyDouble = 50;
        EditableContent someText;

        this()
        {
            someText = new EditableContent;
            someText.text = "Lorem ipsum dolor sit amet consectetur adipisicing elit.";
        }
    }

    override void build()
    {
        State st = useState!State;
        wrap(
            render((TabWidget tw) {
                tw.buildHiddenTabs = true;
            }).wrap(
                TabPair(
                    (TabItem i) { i.text = "Tab 1"; },
                    (Panel p) {
                        p.id = "tab1";
                        p.wrap(
                            render((GroupBox gb) {
                                gb.caption = "Group Box";
                            }).wrap(
                                render((CheckBox cb) {
                                    cb.text = "Check Box";
                                    cb.checked = st.dummyBool;
                                    cb.onToggle = (ch) { setState(st.dummyBool, ch); };
                                }),
                                render((RadioButton rb) {
                                    rb.text = "Radio button";
                                    rb.checked = true;
                                    rb.onToggle = (ch) { Log.d(); };
                                }),
                                render((RadioButton rb) {
                                    rb.text = "Radio button";
                                }),
                            ),
                            render((ScrollBar sb) {}),
                            render((Slider sl) {
                                sl.value = st.dummyDouble;
                                sl.onChange = (v) { setState(st.dummyDouble, v); };
                            }),
                            render((Panel p) { p.id = "p1"; }).wrap(
                                render((EditLine ed) {
                                    ed.attributes["expand"];
                                    ed.placeholder = "Edit line";
                                }),
                                render((ComboBox cb) {
                                    static items = ["Item 1"d, "Item 2"d, "Item 3"d];
                                    cb.items = items;
                                }),
                            ),
                            render((Panel p) { p.id = "p2"; }).wrap(
                                render((Button b) {
                                    b.attributes["expand"];
                                    b.text = "Button";
                                }),
                                render((Button b) {
                                    b.attributes["folder"];
                                    b.text = "Button";
                                    b.iconID = "folder";
                                    b.onClick = { Log.d("click"); };
                                }),
                                render((Button b) {
                                    b.iconID = "dialog-cancel";
                                    b.onClick = { Log.d("click"); };
                                }),
                            ),
                        );
                    }
                ),
                TabPair(
                    (TabItem i) { i.text = "Tab 2"; },
                    (Panel p) {
                        p.id = "tab2";
                        p.wrap(
                            render((SourceEdit ed) {
                                ed.content = st.someText;
                            }),
                            render((Resizer r) {}),
                            render((EditBox ed) {
                                ed.content = st.someText;
                                ed.readOnly = true;
                            }),
                        );
                    }
                ),
            )
        );
    }
}
