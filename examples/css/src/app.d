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
            WindowFlag.expanded | WindowFlag.resizable, 800, 600);

    Row splitView = new Row;
        auto editorPane = new Column;
            auto editor = new SourceEdit;
            auto btnUpdate = new Button("Update styles");
        auto controls = new GroupBox("Controls");

    with (splitView) {
        id = "split-view";
        add(editorPane).setFillWidth(true);
        addResizer();
        add(controls);
        with (editorPane) {
            id = "editor-pane";
            add(editor).setFillHeight(true);
            add(btnUpdate).setFillWidth(false);
            btnUpdate.id = "update";
        }
        with (controls) {
            id = "controls";
            add(createControlsPanel());
        }
    }

    editor.text = stylesheet.toUTF32;
    btnUpdate.clicked = delegate(Widget wt) {
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

    auto tab1 = new Column;
    with (tab1) {
        spacing = 15;
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
            add(ed).setFillWidth(true);
            add(comb);
        }
        Row r2 = new Row;
        with (r2) {
            add(new Button("Button")).setFillWidth(true);
            add(new Button("Button", "folder").addStyleClasses("folder"),
                new Button(null, "dialog-cancel"));
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
