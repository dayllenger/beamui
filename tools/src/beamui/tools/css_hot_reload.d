/**

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.tools.css_hot_reload;

import beamui;

class CssHotReloadWidget : Panel
{
    dstring defaultStyleSheet;

    static protected class State : WidgetState
    {
        bool watching;
        bool error;

        dstring resourceID;
        FileMonitor fmon;

        this(dstring resourceID)
        {
            this.resourceID = resourceID;
        }

        void watch(Window win)
        {
            const filename = resourceList.getPathByID(toUTF8(resourceID));
            fmon = FileMonitor(filename);
            if (fmon.check() == FileMonitor.Status.missing)
            {
                setState(error, true);
                return;
            }
            updateStyles();
            win.setTimer(1000, {
                if (!watching)
                    return false;

                const status = fmon.check();
                if (status == FileMonitor.Status.modified)
                {
                    updateStyles();
                }
                else if (status == FileMonitor.Status.missing)
                {
                    setState(watching, false);
                    setState(error, true);
                }
                return true;
            });
            setState(watching, true);
            setState(error, false);
        }

        void updateStyles()
        {
            const filename = resourceList.getPathByID(toUTF8(resourceID));
            const styles = cast(string)loadResourceBytes(filename);
            platform.reloadTheme();
            setStyleSheet(currentTheme, styles);
        }
    }

    override protected State createState()
    {
        return new State(defaultStyleSheet);
    }

    override protected void build()
    {
        State st = use!State;
        wrap(
            render((Label tip) {
                tip.text = "Style resource ID:";
            }),
            render((EditLine ed) {
                ed.text = st.resourceID;
                if (!st.watching)
                    ed.onChange = (s) { st.resourceID = s; };
                else
                    ed.readOnly = true;
            }),
            render((CheckButton b) {
                b.text = "Watch";
                b.checked = st.watching;
                b.onToggle = (v) {
                    if (v)
                        st.watch(window);
                    else
                        setState(st.watching, false);
                };
            }),
            render((Button b) {
                b.text = "Reload manually";
                b.onClick = &st.updateStyles;
            }),
            render((Label tip) {
                if (st.watching)
                {
                    tip.text = "Status: watching";
                    tip.attributes["state"] = "watching";
                }
                else if (st.error)
                {
                    tip.text = "Status: no such file";
                    tip.attributes["state"] = "error";
                }
                else
                    tip.text = "Status: not watching";
            }),
        );
    }
}
