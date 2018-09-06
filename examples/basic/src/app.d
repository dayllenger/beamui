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

mixin APP_ENTRY_POINT;

/// Entry point for application
extern (C) int UIAppMain(string[] args)
{
    string[] resourceDirs = [
        appendPath(exePath, "../../../res/"),
    ];
    // will use only existing directories
    platform.resourceDirs = resourceDirs;

    platform.uiTheme = "light";

    auto window = platform.createWindow("Basic example", null);

    window.mainWidget = parseML(q{
        Column {
            padding: 10pt
            Label { text: "Text" }
            Spacer {}
            Row {
                Spacer {}
                Button { id: btnOk; text: "OK" }
                Button { id: btnCancel; text: "Cancel" }
            }
        }
    });

    window.mainWidget.childByID!Button("btnCancel").clicked = delegate(Widget w) {
        window.close();
        return true;
    };

    window.show();

    return platform.enterMessageLoop();
}
