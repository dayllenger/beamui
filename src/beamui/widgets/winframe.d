/**
Window frame widget.

Synopsis:
---
import beamui.widgets.docks;
---

Copyright: Vadim Lopatin 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.winframe;

import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.text;

/// Window frame with caption widget
class WindowFrame : Column
{
    @property Widget bodyWidget() { return _bodyWidget; }
    /// ditto
    @property void bodyWidget(Widget widget)
    {
        _bodyLayout.replaceChild(_bodyWidget, widget);
        destroy(_bodyWidget);
        _bodyWidget = widget;
        requestLayout();
    }

    @property Label title() { return _title; }

    Signal!(void delegate(Widget)) closeButtonClick;

    private
    {
        Widget _bodyWidget;
        Row _titleLayout;
        Label _title;
        Button _closeButton;
        bool _showCloseButton;
        Row _bodyLayout;
    }

    this(bool showCloseButton = true)
    {
        _showCloseButton = showCloseButton;
        initialize();
    }

    protected void initialize()
    {
        _titleLayout = new Row;
        _titleLayout.bindSubItem(this, "caption");

        _title = new Label;
        _title.bindSubItem(this, "label");

        _closeButton = new Button(null, "close");
        _closeButton.style = "flat";
        _closeButton.clicked = &closeButtonClick.emit;
        if (!_showCloseButton)
            _closeButton.visibility = Visibility.gone;

        _titleLayout.add(_title);
        _titleLayout.add(_closeButton);

        _bodyLayout = new Row;
        _bodyLayout.bindSubItem(this, "body");

        _bodyWidget = createBodyWidget();
        _bodyLayout.add(_bodyWidget).setFillWidth(true);
        //_bodyWidget.bindSubItem(this, "body");

        add(_titleLayout);
        add(_bodyLayout);
    }

    protected Widget createBodyWidget()
    {
        return new Widget("DOCK_WINDOW_BODY");
    }
}
