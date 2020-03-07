/+ Under major rewrite
module app;

import beamui;

/// Entry point for application
int main()
{
    // initialize library
    GuiApp app;
    app.conf.theme = "light"; // load better theme
    if (!app.initialize())
        return -1;

    // create a window with 1x1 size and expand it to the size of content
    Window window = platform.createWindow("Basic example - beamui", null, WindowOptions.expanded, 1, 1);

    // create some widgets to show
    auto pane = new Panel;
        auto header = new Label("Header");
        auto ed1 = new EditLine("Hello");
        auto ed2 = new EditLine("world");
        auto check = new CheckBox("Check me");
        auto line = new Panel;
            auto ok = new Button("OK");
            auto exit = new Button("Exit");

    // using "with" statement for readability
    with (pane) {
        // column arranges items vertically
        style.display = "column";
        style.minWidth = 200;
        style.padding = Insets(30);
        add(header, ed1, ed2, check, line);
        with (header) {
            style.fontSize = 18;
        }
        with (line) {
            // row organizes items horizontally
            style.display = "row";
            add(ok, exit);
            // let the buttons fill horizontal space
            ok.style.stretch = Stretch.main;
            exit.style.stretch = Stretch.main;
        }
    }

    // disable OK button
    ok.enabled = false;
    // and enable it when the check box has been pressed
    check.onToggle ~= (bool checked) {
        ok.enabled = checked;
    };
    // show message box on OK button click
    ok.onClick ~= {
        window.showMessageBox("Message box"d, format("%s, %s!"d, ed1.text, ed2.text));
    };
    // close the window by clicking Exit
    exit.onClick ~= &window.close;

    // set main widget for the window and show it
    window.mainWidget = pane;
    window.show();
    // run event loop
    return platform.enterMessageLoop();
}
+/
