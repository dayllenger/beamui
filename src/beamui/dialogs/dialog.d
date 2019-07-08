/**
Common Dialog implementation, used to create custom dialogs.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.dialog;

import std.conv;
import beamui.core.i18n;
import beamui.core.signals;
import beamui.core.stdaction;
import beamui.layout.linear : Spacer;
import beamui.widgets.controls;
import beamui.widgets.popup;
import beamui.widgets.widget;
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
class Dialog : Panel
{
    /// Dialog icon resource id
    @property string windowIcon() const { return _icon; }
    /// ditto
    @property void windowIcon(string iconResourceID)
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
    }

    /// Dialog title (caption)
    @property dstring windowTitle() const { return _title; }
    /// ditto
    @property void windowTitle(dstring caption)
    {
        _title = caption;
        if (_window)
            _window.title = caption;
    }

    /// Signal to pass dialog result
    Signal!(void delegate(const Action result)) dialogClosed;

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
        auto res = new Panel("buttons");
        foreach (i, a; actions)
        {
            if (splitBeforeIndex == i)
                res.addChild(new Spacer);
            auto btn = new Button(a);
            (Action a) {
                btn.clicked ~= { handleAction(a); };
            }(a);
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
        WindowOptions wopts;
        if (_flags & DialogFlag.modal)
            wopts |= WindowOptions.modal;
        if (_flags & DialogFlag.resizable)
        {
            wopts |= WindowOptions.resizable;
        }
        if (_flags & DialogFlag.popup)
        {
            auto _frame = new DialogFrame(this, _cancelButton !is null);
            if (_cancelButton)
            {
                _frame.closeButtonClicked ~= {
                    handleAction(_cancelButton.action);
                };
            }
            _popup = _parentWindow.showPopup(_frame);
            _popup.modal = true;
        }
        else
        {
            if (_initialWidth == 0 && _initialHeight == 0)
                wopts |= WindowOptions.expanded;
            _window = platform.createWindow(_title, _parentWindow, wopts, _initialWidth, _initialHeight);
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
            dialogClosed(action);
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
            if (event.key == Key.enter && event.modifiers == KeyMods.control)
            {
                // Ctrl+Enter: default action
                return closeWithDefaultAction();
            }
            if (event.key == Key.escape && event.noModifiers)
            {
                // ESC: cancel/no action
                return closeWithCancelAction();
            }
        }
        return super.onKeyEvent(event);
    }
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
