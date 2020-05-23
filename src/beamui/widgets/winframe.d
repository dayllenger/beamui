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

/** Window frame with caption widget.

    CSS_nodes:
    ---
    WindowFrame
    ├── Panel.caption
    │   ├── Label
    │   ╰── Button?.flat
    ╰── Panel.body
        ╰── *items*
    ---
*/
class WindowFrame : Panel
{
    dstring title;
    /// If assigned, the close button will be visible
    void delegate() onClose;

    override protected void build()
    {
        // swap children - pass them down the tree
        auto content = _children;
        wrap(
            render((Panel p) {
                p.attributes["caption"];
                p.namespace = null;
            }).wrap(
                render((Label lb) {
                    lb.text = title;
                    lb.namespace = null;
                }),
                onClose ? render((Button b) {
                    b.attributes["flat"];
                    b.namespace = null;
                    b.iconID = "close";
                    b.onClick = onClose;
                }) : null,
            ),
            render((Panel p) {
                p.attributes["body"];
                p.namespace = null;
            }).wrap(content),
        );
    }
}
