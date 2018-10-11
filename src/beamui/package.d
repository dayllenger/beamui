/**
This module is just to simplify import of most useful beamui modules.

Synopsis:
---
// helloworld
import beamui;
// required in one of modules
mixin APP_ENTRY_POINT;

/// Entry point for application
extern (C) int UIAppMain(string[] args)
{
    // create a window
    Window window = platform.createWindow("My Window", null);
    // create some widget to show in the window
    window.mainWidget = new Button("Hello, world!"d);
    // show window
    window.show();
    // run message loop
    return platform.enterMessageLoop();
}
---

Copyright: Vadim Lopatin 2014-2018, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui;

public
{
    import beamui.core.actions;
    import beamui.core.config;
    import beamui.core.files;
    import beamui.core.functions;
    import beamui.core.i18n;
    import beamui.core.logger;
    import beamui.core.settings;
    import beamui.core.stdaction;
    import beamui.core.types;
    import beamui.dialogs.dialog;
    import beamui.dialogs.filedlg;
    import beamui.dialogs.msgbox;
    import beamui.dialogs.settingsdialog;
    import beamui.dml.parser;
    import beamui.graphics.colors;
    import beamui.graphics.drawbuf;
    import beamui.graphics.fonts;
    import beamui.graphics.images;
    import beamui.graphics.resources;
    import beamui.style.theme;
    import beamui.widgets.appframe;
    import beamui.widgets.charts;
    import beamui.widgets.combobox;
    import beamui.widgets.controls;
    import beamui.widgets.docks;
    import beamui.widgets.editors;
    import beamui.widgets.grid;
    import beamui.widgets.groupbox;
    import beamui.widgets.layouts;
    import beamui.widgets.lists;
    import beamui.widgets.menu;
    import beamui.widgets.popup;
    import beamui.widgets.progressbar;
    import beamui.widgets.scroll;
    import beamui.widgets.scrollbar;
    import beamui.widgets.srcedit;
    import beamui.widgets.statusline;
    import beamui.widgets.tabs;
    import beamui.widgets.toolbars;
    import beamui.widgets.tree;
    import beamui.widgets.widget;
    import beamui.platforms.common.platform;
}
