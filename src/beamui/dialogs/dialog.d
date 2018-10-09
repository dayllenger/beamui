/**
This module contains common Dialog implementation.


Use to create custom dialogs.

Synopsis:
---
import beamui.dialogs.dialog;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.dialog;

import std.conv;
import beamui.core.i18n;
import beamui.core.signals;
import beamui.core.stdaction;
import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.popup;
import beamui.widgets.winframe;
import beamui.platforms.common.platform;

/// Dialog flag bits
enum DialogFlag : uint
{
    /// Dialog is modal
    modal = 1,
    /// Dialog can be resized
    resizable = 2,
    /// Dialog is show in popup widget inside current window instead of separate window
    popup = 4,
}

/// Base for all dialogs
class Dialog : Column
{
    /// Dialog icon resource id
    @property string windowIcon()
    {
        return _icon;
    }
    /// ditto
    @property Dialog windowIcon(string iconResourceID)
    {
        _icon = iconResourceID;
        static if (BACKEND_GUI)
        {
            if (_window)
            {
                if (_icon.length == 0)
                    _window.icon = imageCache.get(platform.defaultWindowIcon);
                else
                    _window.icon = imageCache.get(_icon);
            }
        }
        return this;
    }

    /// Dialog title (caption)
    @property dstring windowTitle()
    {
        return _title;
    }
    /// ditto
    @property Dialog windowTitle(dstring caption)
    {
        _title = caption;
        if (_window)
            _window.title = caption;
        return this;
    }

    /// Signal to pass dialog result
    Signal!(void delegate(Dialog, const Action result)) dialogClosed;

    protected
    {
        Window _window;
        Window _parentWindow;
        Popup _popup;
        dstring _title;
        uint _flags;
        string _icon;
        int _initialWidth;
        int _initialHeight;
        int _defaultButtonIndex = -1;

        const(Action)[] _buttonActions;

        Button _defaultButton;
        Button _cancelButton;
    }

    this(dstring caption, Window parentWindow = null, uint flags = DialogFlag.modal,
            int initialWidth = 0, int initialHeight = 0)
    {
        id = "dialog-main-widget";
        _initialWidth = initialWidth;
        _initialHeight = initialHeight;
        _title = caption;
        _parentWindow = parentWindow;
        _flags = flags;
        _icon = "";
    }

    /// Create panel with buttons based on list of actions
    Widget createButtonsPanel(Action[] actions, int defaultActionIndex, int splitBeforeIndex)
    {
        _defaultButtonIndex = defaultActionIndex;
        _buttonActions = actions;
        auto res = new Row;
        res.id = "buttons";
        res.fillW();
        res.layoutWeight = 0;
        foreach (i, a; actions)
        {
            if (splitBeforeIndex == i)
                res.addSpacer();
            auto btn = new Button(a);
            btn.clicked = delegate(Widget w) { handleAction((cast(Button)w).action); return true; };
            if (defaultActionIndex == i)
            {
                btn.setState(State.default_);
                _defaultButton = btn;
            }
            if (a is ACTION_NO || a is ACTION_CANCEL)
                _cancelButton = btn;
            res.addChild(btn);
        }
        return res;
    }

    /// Override to implement creation of dialog controls
    void initialize()
    {
    }

    /// Shows dialog
    void show()
    {
        initialize();
        WindowFlag wflags;
        if (_flags & DialogFlag.modal)
            wflags |= WindowFlag.modal;
        if (_flags & DialogFlag.resizable)
        {
            wflags |= WindowFlag.resizable;
            fillWH();
        }
        if (_flags & DialogFlag.popup)
        {
            auto _frame = new DialogFrame(this, _cancelButton !is null);
            if (_cancelButton)
            {
                _frame.closeButtonClick = delegate(Widget w) {
                    handleAction(_cancelButton.action);
                    return true;
                };
            }
            _popup = _parentWindow.showPopup(_frame);
            _popup.modal = true;
        }
        else
        {
            if (_initialWidth == 0 && _initialHeight == 0)
                wflags |= WindowFlag.expanded;
            _window = platform.createWindow(_title, _parentWindow, wflags, _initialWidth, _initialHeight);
            windowIcon = _icon;
            _window.backgroundColor = currentTheme.getColor("dialog_background");
            _window.mainWidget = this;
            _window.show();
        }
        onShow();
    }

    /// Called after window with dialog is shown
    protected void onShow()
    {
        // override to do something useful
        _defaultButton.maybe.setFocus();
    }

    /// Notify about dialog result (if action is not null), and then close dialog
    void close(const Action action)
    {
        if (action && dialogClosed.assigned)
        {
            dialogClosed(this, action);
        }
        if (_popup)
            _parentWindow.removePopup(_popup);
        else
            window.close();
    }

    /// Handle dialog button action. Default is to simply call `close`
    protected void handleAction(const Action action)
    {
        close(action);
    }

    /// Call close with default action; returns true if default action is found and invoked
    protected bool closeWithDefaultAction()
    {
        if (_defaultButton)
        {
            handleAction(_defaultButton.action);
            return true;
        }
        return false;
    }

    /// Call close with cancel action (if found); returns true if cancel action is found and invoked
    protected bool closeWithCancelAction()
    {
        if (_cancelButton)
        {
            handleAction(_cancelButton.action);
            return true;
        }
        return false;
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (event.action == KeyAction.keyDown)
        {
            if (event.keyCode == KeyCode.enter && event.modifiers == KeyFlag.control)
            {
                // Ctrl+Enter: default action
                return closeWithDefaultAction();
            }
            if (event.keyCode == KeyCode.escape && event.noModifiers)
            {
                // ESC: cancel/no action
                return closeWithCancelAction();
            }
        }
        return super.onKeyEvent(event);
    }
/+
    override Size measureContent(in Size bounds, bool exactW, bool exactH)
    {
        Size sz = super.measureContent(bounds, exactW, exactH);
        if ((_flags & DialogFlag.resizable) && (_flags & DialogFlag.popup))
        {
            return Size(_parentWindow.width * 4 / 5, _parentWindow.height * 4 / 5); // FIXME: wat?
        }
        else
            return sz;
    }+/
}

/// Frame with caption for dialog
class DialogFrame : WindowFrame
{
    private Dialog _dialog;

    this(Dialog dialog, bool enableCloseButton)
    {
        super(enableCloseButton);
        id = dialog.id ~ "_frame";
        _dialog = dialog;
        title.text = _dialog.windowTitle;
        bodyWidget = _dialog;
    }
}
