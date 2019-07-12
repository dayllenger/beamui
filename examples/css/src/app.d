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

    auto splitView = new Panel("split-view");
        auto editorPane = new Panel("editor-pane");
            auto editor = new SourceEdit;
            auto btnUpdate = new Button("Update styles");
        auto controls = new GroupBox("Controls");

    splitView.add(editorPane, new Resizer, controls);
        editorPane.add(editor, btnUpdate);
        controls.add(createControlsPanel());

    btnUpdate.id = "update";
    controls.id = "controls";

    with (editor) {
        smartIndents = true;
        content.syntaxSupport = new CssSyntaxSupport;
        text = stylesheet.toUTF32;
    }

    btnUpdate.onClick ~= {
        platform.reloadTheme();
        currentTheme.setStyleSheet(editor.text.toUTF8);
    };

    window.mainWidget = splitView;
    window.show();

    return platform.enterMessageLoop();
}

Widget createControlsPanel()
{
    auto tabs = new TabWidget;

    auto tab1 = new Panel;
    with (tab1) {
        auto gb = new GroupBox("Group Box");
        with (gb) {
            add(new CheckBox("Check Box").setChecked(true),
                new RadioButton("Radio button").setChecked(true),
                new RadioButton("Radio button"));
        }
        auto r1 = new Panel("p1");
        with (r1) {
            auto ed = new EditLine("Edit line");
            auto comb = new ComboBox(["Item 1", "Item 2", "Item 3"]);
            comb.selectedItemIndex = 0;
            add(ed, comb);
            ed.style.stretch = Stretch.both;
        }
        auto r2 = new Panel("p2");
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

#split-view {
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

#tab1 {
    display: column;
    gap: 15px;
}

#p1, #p2 {
    display: row;
}

Button.folder::label {
    color: orange;
}
`;
