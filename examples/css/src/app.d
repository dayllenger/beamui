/**

Synopsis:
---
dub run :css
---

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module app;

import beamui;
import beamui.css.syntax;

int main()
{
    GuiApp app;
    app.conf.theme = "light";
    if (!app.initialize())
        return -1;

    currentTheme.setStyleSheet(stylesheet);

    Window window = platform.createWindow("CSS sandbox");

    Row splitView = new Row;
        auto editorPane = new Column;
            auto editor = new SourceEdit;
            auto btnUpdate = new Button("Update styles");
        auto controls = new GroupBox("Controls");

    with (splitView) {
        id = "split-view";
        add(editorPane, new Resizer, controls);
        with (editorPane) {
            id = "editor-pane";
            style.width = 500;
            style.height = 500;
            style.stretch = Stretch.both;
            add(editor, btnUpdate);
            with (editor) {
                style.stretch = Stretch.both;
                smartIndents = true;
                content.syntaxSupport = new CssSyntaxSupport;
            }
            btnUpdate.id = "update";
            btnUpdate.style.stretch = Stretch.none;
        }
        with (controls) {
            id = "controls";
            add(createControlsPanel());
        }
    }
    window.mainWidget = splitView;

    editor.text = stylesheet.toUTF32;
    btnUpdate.clicked ~= {
        platform.reloadTheme();
        currentTheme.setStyleSheet(editor.text.toUTF8);
    };

    window.show();

    return platform.enterMessageLoop();
}

Widget createControlsPanel()
{
    auto tabs = new TabWidget;

    auto tab1 = new Column;
    with (tab1) {
        style.spacing = 15;
        auto gb = new GroupBox("Group Box");
        with (gb) {
            add(new CheckBox("Check Box").setChecked(true),
                new RadioButton("Radio button").setChecked(true),
                new RadioButton("Radio button"));
        }
        Row r1 = new Row;
        with (r1) {
            auto ed = new EditLine("Edit line");
            auto comb = new ComboBox(["Item 1", "Item 2", "Item 3"]);
            comb.selectedItemIndex = 0;
            add(ed, comb);
            ed.style.stretch = Stretch.both;
        }
        Row r2 = new Row;
        with (r2) {
            auto btn1 = new Button("Button");
            auto btn2 = new Button("Button", "folder");
            auto btn3 = new Button(null, "dialog-cancel");
            btn2.setAttribute("folder");
            add(btn1, btn2, btn3);
            btn1.style.stretch = Stretch.both;
        }
        add(gb);
        add(new ScrollBar(Orientation.horizontal), new Slider(Orientation.horizontal));
        add(r1, r2);
    }
    auto tab2 = new Widget;

    tabs.addTab(tab1.setID("tab1"), "Tab 1");
    tabs.addTab(tab2.setID("tab2"), "Tab 2");
    return tabs;
}

string stylesheet =
`/* some styles for this window */

Button#update {
    align: hcenter;
    padding: 6px;
    focus-rect-color: none;
}

Row#split-view {
    padding: 10px;
    spacing: 3;
}

/* write your own and press the button below */

Button.folder::label {
    color: orange;
}
`;
