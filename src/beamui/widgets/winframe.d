/**
This module implements window frame widget.

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

/// Window frame with caption widget
class WindowFrame : Column
{
    @property Widget bodyWidget()
    {
        return _bodyWidget;
    }

    @property void bodyWidget(Widget widget)
    {
        _bodyLayout.replaceChild(widget, _bodyWidget);
        _bodyWidget = widget;
        _bodyWidget.fillWH();
        _bodyWidget.parent = this;
        requestLayout();
    }

    @property Label title()
    {
        return _title;
    }

    Signal!(bool delegate(Widget)) closeButtonClick;

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
        _title.fillW();

        _closeButton = new Button(null, "close");
        _closeButton.styleID = "Button.transparent"; // TODO
        _closeButton.clicked = &closeButtonClick.emit;
        if (!_showCloseButton)
            _closeButton.visibility = Visibility.gone;

        _titleLayout.addChild(_title);
        _titleLayout.addChild(_closeButton);

        _bodyLayout = new Row;
        _bodyLayout.bindSubItem(this, "body");

        _bodyWidget = createBodyWidget();
        _bodyLayout.addChild(_bodyWidget);
        _bodyWidget.fillWH();
        //_bodyWidget.bindSubItem(this, "body");

        addChild(_titleLayout);
        addChild(_bodyLayout);
    }

    protected Widget createBodyWidget()
    {
        return new Widget("DOCK_WINDOW_BODY");
    }
}
