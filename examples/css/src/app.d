module app;

import beamui;
import beamui.tools.css_hot_reload;

mixin RegisterPlatforms;

int main()
{
    resourceList.setResourceDirs(
        appendPath(exePath, "resources/"),
        appendPath(exePath, "../resources/"),
    );

    GuiApp app;
    if (!app.initialize())
        return -1;

    platform.stylesheets = [StyleResource("light"), StyleResource("style")];

    Window window1 = platform.createWindow("CSS sandbox - beamui");
    Window window2 = platform.createWindow("CSS hot reloader", window1, WindowOptions.expanded, 1, 1);

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

class Controls : Panel
{
    static protected class State : WidgetState
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

    override protected State createState()
    {
        return new State;
    }

    override void build()
    {
        State st = use!State;
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
