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

Copyright: Vadim Lopatin 2014-2018, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui;

public
{
    import beamui.core.files;
    import beamui.core.resources;
    import beamui.core.settings;
    import beamui.dialogs.dialog;
    import beamui.dialogs.filedialog;
    import beamui.dialogs.messagebox;
    import beamui.dialogs.settingsdialog;
    import beamui.events.action;
    import beamui.events.shortcut;
    import beamui.events.stdactions;
    import beamui.graphics.brush : Brush, GradientBuilder;
    import beamui.graphics.compositing : BlendMode, CompositeMode;
    import beamui.graphics.images;
    import beamui.graphics.path : Path;
    import beamui.graphics.pen : LineCap, LineJoin, Pen;
    import beamui.graphics.polygons : FillRule;
    import beamui.layout.factory : registerLayoutType;
    import beamui.layout.flex : FlexDirection, FlexWrap;
    import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
    import beamui.layout.linear : ElemResizer, Resizer, ResizerEventType, Spacer;
    import beamui.platforms.common.platform;
    import beamui.style.theme;
    import beamui.text.fonts : Font, FontFamily, FontManager, FontRef, FontStyle, FontWeight, HintingMode;
    import beamui.text.glyph : GlyphRef, SubpixelRenderingMode;
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
    import beamui.widgets.trigger;
    import beamui.widgets.widget; // exports a lot of stuff too
}
