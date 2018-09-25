/**


Copyright: Vadim Lopatin 2016-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.dmlwidgets;

/// Register standard widgets to use in DML
extern (C) void registerStandardWidgets()
{
    import beamui.core.config;
    import beamui.core.logger;

    Log.d("Registering standard widgets for DML");

    import beamui.widgets.metadata;
    import beamui.widgets.widget;

    mixin(registerWidgetMetadataClass!Widget);

    import beamui.widgets.layouts;

    mixin(registerWidgetMetadataClass!Row);
    mixin(registerWidgetMetadataClass!Column);
    mixin(registerWidgetMetadataClass!FrameLayout);
    mixin(registerWidgetMetadataClass!TableLayout);
    mixin(registerWidgetMetadataClass!Spacer);
    mixin(registerWidgetMetadataClass!HSpacer);
    mixin(registerWidgetMetadataClass!VSpacer);
    mixin(registerWidgetMetadataClass!Resizer);

    import beamui.widgets.controls;

    mixin(registerWidgetMetadataClass!Label);
    mixin(registerWidgetMetadataClass!MultilineLabel);
    mixin(registerWidgetMetadataClass!Button);
    mixin(registerWidgetMetadataClass!SwitchButton);
    mixin(registerWidgetMetadataClass!RadioButton);
    mixin(registerWidgetMetadataClass!CheckBox);
    mixin(registerWidgetMetadataClass!CanvasWidget);

    import beamui.widgets.scrollbar;

    mixin(registerWidgetMetadataClass!ScrollBar);
    mixin(registerWidgetMetadataClass!Slider);

    import beamui.widgets.lists;

    mixin(registerWidgetMetadataClass!ListWidget);
    mixin(registerWidgetMetadataClass!StringListWidget);

    import beamui.widgets.editors;

    mixin(registerWidgetMetadataClass!EditLine);
    mixin(registerWidgetMetadataClass!EditBox);
    mixin(registerWidgetMetadataClass!LogWidget);

    import beamui.widgets.combobox;

    mixin(registerWidgetMetadataClass!ComboBox);
    mixin(registerWidgetMetadataClass!ComboEdit);

    import beamui.widgets.grid;

    mixin(registerWidgetMetadataClass!StringGridWidget);

    import beamui.widgets.groupbox;

    mixin(registerWidgetMetadataClass!GroupBox);

    import beamui.widgets.progressbar;

    mixin(registerWidgetMetadataClass!ProgressBar);

    import beamui.widgets.menu;

    mixin(registerWidgetMetadataClass!Menu);
    mixin(registerWidgetMetadataClass!MenuBar);

    import beamui.widgets.tree;

    mixin(registerWidgetMetadataClass!TreeWidget);

    import beamui.widgets.tabs;

    mixin(registerWidgetMetadataClass!TabWidget);

    import beamui.dialogs.filedlg;

    mixin(registerWidgetMetadataClass!FileNameEditLine);
    mixin(registerWidgetMetadataClass!DirEditLine);
}
