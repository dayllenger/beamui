/**
This module is just to simplify import of most useful beamui modules.

Synopsis:
---
// helloworld
import beamui;

int main()
{
    // initialize library
    GuiApp app;
    if (!app.initialize())
        return -1;

    // create a window
    Window window = platform.createWindow("My Window");
    // create some widget to show in the window
    window.mainWidget = new Button("Hello, world!"d);
    // show window
    window.show();
    // run event loop
    return platform.enterMessageLoop();
}
---

Copyright: Vadim Lopatin 2014-2018, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui;

// the imports should be selective, but DCD doesn't care about them
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
    import beamui.dialogs.filedialog;
    import beamui.dialogs.messagebox;
    import beamui.dialogs.settingsdialog;
    import beamui.graphics.bitmap;
    import beamui.graphics.brush; // : Brush, GradientBuilder;
    import beamui.graphics.colors; // : Color, NamedColor;
    import beamui.graphics.compositing; // : BlendMode, CompositeMode;
    import beamui.graphics.images;
    import beamui.graphics.painter; // : Painter, PaintSaver;
    import beamui.graphics.path; // : Path;
    import beamui.graphics.pen; // : LineCap, LineJoin, Pen;
    import beamui.graphics.polygons; // : FillRule;
    import beamui.graphics.resources;
    import beamui.layout.alignment;
    import beamui.layout.flex;
    import beamui.layout.free;
    import beamui.layout.linear;
    import beamui.layout.table;
    import beamui.style.theme;
    import beamui.text.fonts;
    import beamui.text.style;
    import beamui.widgets.appframe;
    import beamui.widgets.charts;
    import beamui.widgets.combobox;
    import beamui.widgets.controls;
    import beamui.widgets.docks;
    import beamui.widgets.editors;
    import beamui.widgets.grid;
    import beamui.widgets.groupbox;
    import beamui.widgets.lists;
    import beamui.widgets.menu;
    import beamui.widgets.popup;
    import beamui.widgets.progressbar;
    import beamui.widgets.scroll;
    import beamui.widgets.scrollbar;
    import beamui.widgets.slider;
    import beamui.widgets.srcedit;
    import beamui.widgets.statusline;
    import beamui.widgets.tabs;
    import beamui.widgets.text;
    import beamui.widgets.toolbars;
    import beamui.widgets.tree;
    import beamui.widgets.widget;
    import beamui.platforms.common.platform;
}
