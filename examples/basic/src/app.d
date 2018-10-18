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
    Column pane = new Column;
    pane.minWidth = 200;
    pane.padding = Insets(15);
        Label header = new Label("Header");
        header.fontSize = 18;
        EditLine ed1 = new EditLine("Hello");
        EditLine ed2 = new EditLine("world");
        CheckBox check = new CheckBox("Check me");
    pane.add(header);
    pane.add(ed1);
    pane.add(ed2);
    pane.add(check);
        // Row organizes items horizontally
        Row line = new Row;
            Button ok = new Button("OK");
            Button exit = new Button("Exit");
        // let the buttons fill horizontal space
        line.add(ok).fillWidth(true);
        line.add(exit).fillWidth(true);
    pane.add(line);

    // disable OK button
    ok.enabled = false;
    // and enable it when the check box has been pressed
    check.checkChanged = delegate(Widget src, bool checked) {
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
