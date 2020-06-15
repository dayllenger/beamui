/**
Abstract popup and window opener.

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.trigger;

import beamui.platforms.common.platform : platform, Window, WindowOptions;
import beamui.widgets.popup : Popup;
import beamui.widgets.widget;

interface ITrigger
{
    void show();
    void hide();
}

class WindowTrigger : Widget, ITrigger
{
    dstring title;
    WindowOptions options;
    Widget delegate() builder;

    static protected class State : WidgetState
    {
        Window window;
    }

    override protected State createState()
    {
        return new State;
    }

    void show()
    {
        auto st = use!State;
        if (!st.window && builder)
        {
            Window win = platform.createWindow(title, window, options);
            win.onClose = { setState(st.window, null); };
            win.show(builder);
            setState(st.window, win);
        }
    }

    void hide()
    {
        auto st = use!State;
        if (st.window)
        {
            platform.closeWindow(st.window);
            setState(st.window, null);
        }
    }

    override protected void build()
    {
        Window win = use!State.window;
        if (win && win.title != title)
            win.title = title;
    }

    override protected Element createElement()
    {
        return null;
    }
}

class PopupTrigger : Widget, ITrigger
{
    string animIn;
    string animOut;

    Popup delegate() builder;

    protected enum Mode
    {
        closed,
        preparing,
        opening,
        opened,
        closing,
    }

    static protected class State : WidgetState
    {
        Mode mode;

        void show(Window win)
        {
            if (mode == Mode.closed || mode == Mode.closing)
            {
                setState(mode, Mode.preparing);
                assert(win);
                win.setTimer(16, { // FIXME: should be zero
                    setState(mode, Mode.opening);
                    return false;
                });
            }
        }

        void hide()
        {
            setState(mode, Mode.closing);
        }

        void finish()
        {
            if (mode == Mode.opening)
                setState(mode, Mode.opened);
            else
                setState(mode, Mode.closed);
        }
    }

    override protected State createState()
    {
        return new State;
    }

    void show()
    {
        use!State.show(window);
    }

    void hide()
    {
        use!State.hide();
    }

    override protected void build()
    {
        window.showPopup(builder ? buildPopup() : null);
    }

    private Popup buildPopup()
    {
        auto st = use!State;

        if (st.mode == Mode.preparing)
        {
            if (animIn.length)
            {
                auto p = builder();
                assert(p);
                p.attributes[animIn];
                p.attributes["out"];
                p.visible = false;
                return p;
            }
            return null;
        }

        if (!animIn.length && st.mode == Mode.opening)
            st.mode = Mode.opened;
        if (!animOut.length && st.mode == Mode.closing)
            st.mode = Mode.closed;

        if (st.mode != Mode.closed)
        {
            auto p = builder();
            assert(p);
            if (animIn.length)
            {
                if (st.mode == Mode.closed || st.mode == Mode.opening)
                    p.attributes[animIn];
            }
            if (animOut.length)
            {
                if (st.mode == Mode.opened || st.mode == Mode.closing)
                    p.attributes[animOut];
            }
            if (animIn.length || animOut.length)
            {
                if (st.mode == Mode.opening || st.mode == Mode.opened)
                    p.attributes["in"];
                else
                    p.attributes["out"];

                if (st.mode == Mode.opening || st.mode == Mode.closing)
                    p.onAnimationEnd = (name) { st.finish(); };
            }
            return p;
        }
        return null;
    }

    override protected Element createElement()
    {
        return null;
    }
}
