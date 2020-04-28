module app;

import beamui;
import beamui.css.syntax;

int main()
{
    GuiApp app;
    app.conf.theme = "light";
    if (!app.initialize())
        return -1;

    setStyleSheet(currentTheme, styles);

    Window window = platform.createWindow("CSS sandbox");

    cssContent = new EditableContent;
    cssContent.text = toUTF32(styles);
    cssContent.syntaxSupport = new CssSyntaxSupport;

    window.show(() => render!App);
    return platform.enterMessageLoop();
}

EditableContent cssContent;

class App : Panel
{
    override void build()
    {
        wrap(
            render((Panel p) {
                p.id = "editor-pane";
            }).wrap(
                render((SourceEdit ed) {
                    ed.content = cssContent;
                    // ed.smartIndents = true;
                }),
                render((Button b) {
                    b.id = "update";
                    b.text = "Update styles";
                    b.onClick = {
                        platform.reloadTheme();
                        setStyleSheet(currentTheme, toUTF8(cssContent.text));
                    };
                }),
            ),
            render((Resizer r) {}),
            render((Controls c) {}),
        );
    }
}

class Controls : GroupBox
{
    this()
    {
        caption = "Controls";
    }

    override void build()
    {
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
                                    cb.checked = true;
                                    cb.onToggle = (ch) { Log.d(); };
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
                            render((Slider sl) {}),
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
                    }
                ),
            )
        );
    }
}

const styles =
`/* some styles for this window */

App {
    display: row;
    padding: 10px;
    gap: 3px;
}

#editor-pane {
    display: column;
    width: 500px;
    height: 500px;
    stretch: both;
}

#editor-pane SourceEdit {
    stretch: both;
}

Button#update {
    align: hcenter;
    stretch: none;
    padding: 6px;
    focus-rect-color: none;
}

/* write your own and press the button below */

.expand { stretch: both; }

#tab1 {
    display: column;
    gap: 15px;
}

#p1, #p2 {
    display: row;
}

Button.folder > .label {
    color: orange;
}
`;
