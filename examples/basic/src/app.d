/**
This app is a demo of very basic beamui application.

Synopsis:
---
dub run :basic
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module app;

import beamui;

// mandatory, it does some initialization and then runs UIAppMain
mixin APP_ENTRY_POINT;

/// Entry point for application
extern (C) int UIAppMain(string[] args)
{
    // load better theme
    platform.uiTheme = "light";

    // create a window with 1x1 size and expand it to the size of content
    Window window = platform.createWindow("Basic example", null, WindowFlag.expanded, 1, 1);

    // create some widgets to show
    // Column arranges items vertically
    auto pane = new Column;
        auto header = new Label("Header");
        auto ed1 = new EditLine("Hello");
        auto ed2 = new EditLine("world");
        auto check = new CheckBox("Check me");
        // Row organizes items horizontally
        auto line = new Row;
            auto ok = new Button("OK");
            auto exit = new Button("Exit");

    // using "with" statement for readability
    with (pane) {
        minWidth = 200;
        padding = Insets(15);
        add(header, ed1, ed2, check, line);
        with (header) {
            fontSize = 18;
        }
        with (line) {
            // let the buttons fill horizontal space
            add(ok).setFillWidth(true);
            add(exit).setFillWidth(true);
        }
    }

    // disable OK button
    ok.enabled = false;
    // and enable it when the check box has been pressed
    check.toggled = delegate(Widget src, bool checked) {
        ok.enabled = checked;
    };
    // show message box on OK button click
    ok.clicked = delegate(Widget src) {
        window.showMessageBox("Message box"d, format("%s, %s!"d, ed1.text, ed2.text));
    };
    // close the window by clicking Exit
    exit.clicked = delegate(Widget src) {
        window.close();
    };

    // set main widget for the window and show it
    window.mainWidget = pane;
    window.show();
    // run event loop
    return platform.enterMessageLoop();
}
