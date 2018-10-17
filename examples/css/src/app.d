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

mixin APP_ENTRY_POINT;

/// Entry point for application
extern (C) int UIAppMain(string[] args)
{
    platform.uiTheme = "light";
    currentTheme.setStyleSheet(stylesheet);

    Window window = platform.createWindow("CSS sandbox", null,
                                          WindowFlag.expanded | WindowFlag.resizable,
                                          800, 600);

    Row splitView = new Row;
    splitView.id = "split-view";

        auto editorPane = new Column;
        editorPane.id = "editor-pane";

            auto editor = new SourceEdit;
            editor.text = stylesheet.toUTF32;

            auto btnUpdate = new Button("Update styles");
            btnUpdate.id = "update";
            btnUpdate.clicked = delegate(Widget wt) {
                platform.reloadTheme();
                currentTheme.setStyleSheet(editor.text.toUTF8);
            };

        editorPane.add(editor).fillHeight(true);
        editorPane.add(btnUpdate).fillWidth(false);

        auto controls = new GroupBox("Controls");
        controls.id = "controls";
        controls.add(createControlsPanel());

    splitView.add(editorPane).fillWidth(true);
    splitView.addResizer();
    splitView.add(controls);

    window.mainWidget = splitView;
    window.show();

    return platform.enterMessageLoop();
}

Widget createControlsPanel()
{
    auto tabs = new TabWidget;

    Column col = new Column;
    col.spacing = 15;

        auto gb = new GroupBox("Group Box");
        gb.add(new CheckBox("Check Box").checked(true));
        gb.add(new RadioButton("Radio button").checked(true));
        gb.add(new RadioButton("Radio button"));

        Row r1 = new Row;
            auto ed = new EditLine("Edit line");
            auto comb = new ComboBox(["Item 1", "Item 2", "Item 3"]);
            comb.selectedItemIndex = 0;
        r1.add(ed).fillWidth(true);
        r1.add(comb);

        Row r2 = new Row;
        r2.add(new Button("Button")).fillWidth(true);
        r2.add(new Button("Button", "folder"));
        r2.add(new Button(null, "dialog-cancel"));

    col.add(gb);
    col.add(new ScrollBar(Orientation.horizontal));
    col.add(new Slider(Orientation.horizontal));
    col.add(r1);
    col.add(r2);

    tabs.addTab(col.id("tab1"), "Tab 1");
    tabs.addTab(new Widget().id("tab2"), "Tab 2");
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
`;
