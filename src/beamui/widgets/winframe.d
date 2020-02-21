/**
Window frame widget.

Copyright: Vadim Lopatin 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.winframe;

import beamui.widgets.controls;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Window frame with caption widget
class WindowFrame : Panel
{
    @property Widget bodyWidget() { return _bodyWidget; }
    /// ditto
    @property void bodyWidget(Widget widget)
    {
        _bodyLayout.replaceChild(_bodyWidget, widget);
        destroy(_bodyWidget);
        _bodyWidget = widget;
    }

    @property Label title() { return _title; }

    Signal!(void delegate()) onCloseButtonClick;

    private
    {
        Widget _bodyWidget;
        Panel _titleLayout;
        Label _title;
        Button _closeButton;
        bool _showCloseButton;
        Panel _bodyLayout;
    }

    this(bool showCloseButton = true)
    {
        _showCloseButton = showCloseButton;
        initialize();
    }

    protected void initialize()
    {
        _titleLayout = new Panel(null, "caption");
            _title = new Label;
            _closeButton = new Button(null, "close");
        _bodyLayout = new Panel(null, "body");
            _bodyWidget = createBodyWidget();

        with (_titleLayout) {
            isolateThisStyle();
            add(_title, _closeButton);
        }
        with (_title) {
            isolateThisStyle();
            setAttribute("label");
        }
        with (_closeButton) {
            setAttribute("flat");
        }
        with (_bodyLayout) {
            isolateThisStyle();
            add(_bodyWidget);
        }
        add(_titleLayout, _bodyLayout);

        _closeButton.onClick ~= &onCloseButtonClick.emit;
        if (!_showCloseButton)
            _closeButton.visibility = Visibility.gone;
    }

    protected Widget createBodyWidget()
    {
        return new Widget;
    }
}
