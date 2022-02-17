/**

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.tools.css_hot_reload;

import beamui;

class CssHotReloadWidget : Panel {
    static protected class State : WidgetState {
        bool watching;
        bool error;

        FileMonitor[] monitors;

        void watch(Window win) {
            foreach (res; platform.stylesheets) {
                const fn = resourceList.getPathByID(res.resourceID);
                if (!fn.startsWith(EMBEDDED_RESOURCE_PREFIX))
                    monitors ~= FileMonitor(fn);
            }
            foreach (ref fmon; monitors) {
                if (fmon.check() == FileMonitor.Status.missing) {
                    setState(error, true);
                    return;
                }
            }
            updateStyles();
            win.setTimer(1000, {
                if (!watching)
                    return false;

                foreach (ref fmon; monitors) {
                    const status = fmon.check();
                    if (status == FileMonitor.Status.modified) {
                        updateStyles();
                        break;
                    } else if (status == FileMonitor.Status.missing) {
                        setState(watching, false);
                        setState(error, true);
                        break;
                    }
                }
                return true;
            });
            setState(watching, true);
            setState(error, false);
        }

        void updateStyles() {
            platform.stylesheets = platform.stylesheets;
        }
    }

    override protected State createState() {
        return new State;
    }

    override protected void build() {
        State st = use!State;
        wrap(
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
            render((Button b) { b.text = "Reload manually"; b.onClick = &st.updateStyles; }),
            render((Label tip) {
                if (st.watching) {
                    tip.text = "Status: watching";
                    tip.attributes["state"] = "watching";
                } else if (st.error) {
                    tip.text = "Status: no such file";
                    tip.attributes["state"] = "error";
                } else
                    tip.text = "Status: not watching";
            }),
        );
    }
}
