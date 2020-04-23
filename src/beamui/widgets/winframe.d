/**
Window frame widget.

Copyright: Vadim Lopatin 2015, dayllenger 2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.winframe;

import beamui.widgets.controls : Button;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Window frame with caption widget
class WindowFrame : Panel
{
    dstring title;
    /// If assigned, the close button will be visible
    void delegate() onClose;

    protected Widget _content;

    final WindowFrame wrap(Widget content)
    {
        _content = content;
        return this;
    }

    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        wrap(
            render((Panel p) {
                p.attributes["caption"];
                p.isolateThisStyle = true;
            }).wrap(
                render((Label lb) {
                    lb.text = title;
                    lb.isolateThisStyle = true;
                }),
                onClose ? render((Button b) {
                    b.attributes["flat"];
                    b.iconID = "close";
                    b.onClick = onClose;
                }) : null,
            ),
            render((Panel p) {
                p.attributes["body"];
                p.isolateThisStyle = true;
            }).wrap(_content),
        );
    }
}
