/**


Copyright: Vadim Lopatin 2015-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.inputbox;

import beamui.core.actions;
import beamui.core.i18n;
import beamui.core.signals;
import beamui.core.stdaction;
import beamui.dialogs.dialog;
import beamui.widgets.editors;
import beamui.widgets.text;
import beamui.platforms.common.platform;

/// Input box
class InputBox : Dialog
{
    override @property dstring text() const { return _editor.text; }

    override @property void text(dstring txt)
    {
        _editor.text = txt;
    }

    private
    {
        dstring _message;
        Action[] _actions;
        dstring _initialText;
        EditLine _editor;
    }

    this(dstring caption, dstring message, Window parentWindow, dstring initialText,
            void delegate(dstring result) handler)
    {
        super(caption, parentWindow, DialogFlag.modal |
            (platform.uiDialogDisplayMode & DialogDisplayMode.inputBoxInPopup ? DialogFlag.popup : 0));
        _message = message;
        _actions = [ACTION_OK, ACTION_CANCEL];
        _defaultButtonIndex = 0;
        _initialText = initialText;
        if (handler)
        {
            onClose ~= (const Action action) {
                if (action is ACTION_OK)
                {
                    handler(text);
                }
            };
        }
    }

    override void initialize()
    {
        auto msg = new Label(_message);
        _editor = new EditLine(_initialText);
        _editor.onEnterKeyPress ~= {
            closeWithDefaultAction();
            return true;
        };
        _editor.popupMenu = EditLine.createDefaultPopupMenu();
        add(msg, _editor, createButtonsPanel(_actions, _defaultButtonIndex, 0));
    }

    override protected void handleShow()
    {
        super.handleShow();
        _editor.selectAll();
        _editor.setFocus();
    }
}
