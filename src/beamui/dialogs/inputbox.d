/**


Copyright: Vadim Lopatin 2015-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dialogs.inputbox;

import beamui.core.i18n;
import beamui.core.signals;
import beamui.core.stdaction;
import beamui.dialogs.dialog;
import beamui.widgets.editors;
import beamui.widgets.layouts;
import beamui.widgets.text;
import beamui.platforms.common.platform;

/// Input box
class InputBox : Dialog
{
    override @property dstring text() const { return _text; }

    override @property void text(dstring txt)
    {
        _text = txt;
    }

    private
    {
        dstring _message;
        Action[] _actions;
        EditLine _editor;
        dstring _text;
    }

    this(dstring caption, dstring message, Window parentWindow, dstring initialText,
            void delegate(dstring result) handler)
    {
        super(caption, parentWindow, DialogFlag.modal |
            (platform.uiDialogDisplayMode & DialogDisplayMode.inputBoxInPopup ? DialogFlag.popup : 0));
        _message = message;
        _actions = [ACTION_OK, ACTION_CANCEL];
        _defaultButtonIndex = 0;
        _text = initialText;
        if (handler)
        {
            dialogClosed = delegate(Dialog dlg, const Action action) {
                if (action is ACTION_OK)
                {
                    handler(_text);
                }
            };
        }
    }

    override void initialize()
    {
        padding(Insets(10)); // TODO: move to styles?
        auto msg = new MultilineLabel(_message);
        msg.id = "msg";
        msg.padding(Insets(10));
        _editor = new EditLine(_text);
        _editor.id = "inputbox_editor";
        _editor.enterKeyPressed = delegate(EditWidgetBase editor) {
            closeWithDefaultAction();
            return true;
        };
        _editor.contentChanged = delegate(EditableContent content) { _text = content.text; };
        _editor.setDefaultPopupMenu();
        add(msg, _editor, createButtonsPanel(_actions, _defaultButtonIndex, 0));
    }

    override protected void onShow()
    {
        super.onShow();
        _editor.selectAll();
        _editor.setFocus();
    }
}
