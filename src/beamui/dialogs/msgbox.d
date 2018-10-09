/**
This module contains message box implementation.


Synopsis:
---
import beamui.dialogs.msgbox;

// show message box with single Ok button
window.showMessageBox("Dialog title"d, "Some message"d);

// show message box with OK and CANCEL buttons, cancel by default, and handle its result
window.showMessageBox(tr("Dialog title"), tr("Some message"), [ACTION_OK, ACTION_CANCEL], 1,
    delegate(const Action a) {
        if (a is ACTION_OK)
            Log.d("OK pressed");
        else if (a is ACTION_CANCEL)
            Log.d("CANCEL pressed");
});
---

Copyright: Vadim Lopatin 2014-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.msgbox;

import beamui.core.i18n;
import beamui.core.signals;
import beamui.core.stdaction;
import beamui.dialogs.dialog;
import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.platforms.common.platform;

/// Message box
class MessageBox : Dialog
{
    private dstring _message;
    private Action[] _actions;

    this(dstring caption, dstring message, Window parentWindow = null,
            Action[] buttons = [ACTION_OK], int defaultButtonIndex = 0,
            void delegate(const Action result) handler = null)
    {
        super(caption, parentWindow, DialogFlag.modal |
            (platform.uiDialogDisplayMode & DialogDisplayMode.messageBoxInPopup ? DialogFlag.popup : 0));
        _message = message;
        _actions = buttons;
        _defaultButtonIndex = defaultButtonIndex;
        if (handler)
        {
            dialogClosed = delegate(Dialog dlg, const Action action) { handler(action); };
        }
    }

    override void initialize()
    {
        padding(Insets(10)); // FIXME: move to styles?
        auto msg = new MultilineLabel(_message);
        msg.id = "msg";
        msg.padding(Insets(10));
        addChild(msg);
        addChild(createButtonsPanel(_actions, _defaultButtonIndex, 0));
    }
}
