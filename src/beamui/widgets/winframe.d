/**
Window frame widget.

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

    Signal!(void delegate()) closeButtonClicked;

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
            _title = new Label;
            _closeButton = new Button(null, "close");
        _bodyLayout = new Row;
            _bodyWidget = createBodyWidget();

        with (_titleLayout) {
            bindSubItem(this, "caption");
            add(_title, _closeButton);
            _title.bindSubItem(this, "label");
            _closeButton.style = "flat";
        }
        with (_bodyLayout) {
            bindSubItem(this, "body");
            add(_bodyWidget).setFillWidth(true);
        }
        add(_titleLayout, _bodyLayout);

        _closeButton.clicked ~= &closeButtonClicked.emit;
        if (!_showCloseButton)
            _closeButton.visibility = Visibility.gone;
    }

    protected Widget createBodyWidget()
    {
        return new Widget("DOCK_WINDOW_BODY");
    }
}
