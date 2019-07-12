/**
Status line control.

Status line is usually shown in the bottom of window, and shows status of app.

Contains one or more text and/or icon items

Copyright: Vadim Lopatin 2015-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.statusline;

import beamui.text.sizetest;
import beamui.widgets.controls;
import beamui.widgets.editors;
import beamui.widgets.text;
import beamui.widgets.widget;

class StatusLineTextPanel : Panel
{
    private Label _text;

    this()
    {
        _text = new Label(""d);
        addChild(_text);
    }

    override @property dstring text() const
    {
        return _text.text;
    }

    override @property void text(dstring s)
    {
        _text.text = s;
    }
}

class StatusLineIconPanel : Panel
{
    private ImageWidget _icon;

    this()
    {
        _icon = new ImageWidget;
        addChild(_icon);
    }

    @property string iconID() const
    {
        return _icon.imageID;
    }

    @property void iconID(string icon)
    {
        _icon.imageID = icon;
    }
}

class StatusLineTextAndIconPanel : StatusLineTextPanel
{
    private ImageWidget _icon;

    this()
    {
        _icon = new ImageWidget;
        _icon.style.minWidth = BACKEND_CONSOLE ? 1 : 20;
        _icon.style.minHeight = BACKEND_CONSOLE ? 1 : 20;
        _icon.style.alignment = Align.center;
        add(_icon);
    }

    @property string iconID() const
    {
        return _icon.imageID;
    }

    @property void iconID(string icon)
    {
        _icon.imageID = icon;
    }
}

class StatusLineBackgroundOperationPanel : StatusLineTextAndIconPanel
{
    this()
    {
        visibility = Visibility.gone;
    }

    private uint animationProgress;
    /// Show / update / animate background operation status; when both parameters are nulls, hide background op status panel
    void setBackgroundOperationStatus(string icon, dstring statusText)
    {
        if (icon || statusText)
        {
            visibility = Visibility.visible;
            text = statusText;
            iconID = icon;
            animationProgress = (animationProgress + 30) % 512;
            uint a = animationProgress;
            if (a >= 256)
                a = 512 - a;
            _icon.style.backgroundColor = (a << 24) | 0x00FF00;
        }
        else
        {
            visibility = Visibility.gone;
        }
    }
}

class StatusLineEditorStatePanel : StatusLineTextPanel
{
    EditorStateInfo _editorState;

    this()
    {
        //_text.alignment = Align.vcenter | Align.right;
        //_text.backgroundColor = 0x80FF0000;
        //backgroundColor = 0x8000FF00;
        updateSize();
        visibility = Visibility.gone;
    }

    dstring makeStateString() const
    {
        if (!_editorState.active)
            return null;
        import std.string : format;

        return "%d : %d    ch=0x%05x    %s  "d.format(_editorState.line, _editorState.col,
                _editorState.character, _editorState.replaceMode ? "OVR"d : "INS"d);
    }

    private void updateSize()
    {
        auto st = TextLayoutStyle(font.get);
        const sz = computeTextSize("  ch=0x00000    000000 : 000    INS  "d, st);
        _text.style.minWidth = sz.w;
    }

    override void handleThemeChange()
    {
        super.handleThemeChange();
        updateSize();
    }

    void setState(Widget source, ref EditorStateInfo editorState)
    {
        if (editorState != _editorState)
        {
            _editorState = editorState;
            text = makeStateString();
            auto v = _editorState.active ? Visibility.visible : Visibility.gone;
            if (v != visibility)
                visibility = v;
        }
    }
}

/// Status line control
class StatusLine : Panel
{
    private
    {
        Label _defStatus;
        StatusLineBackgroundOperationPanel _backgroundOperationPanel;
        StatusLineEditorStatePanel _editorStatePanel;
    }

    this()
    {
        _defStatus = new Label(" "d);
        _backgroundOperationPanel = new StatusLineBackgroundOperationPanel;
        _editorStatePanel = new StatusLineEditorStatePanel;
        add(_defStatus, _backgroundOperationPanel, _editorStatePanel);
    }

    /// Set text to show in status line in specific panel
    void setStatusText(string itemID, dstring value)
    {
        _defStatus.text = value;
    }
    /// Set text to show in status line
    void setStatusText(dstring value)
    {
        setStatusText(null, value);
    }
    /// Show / update / animate background operation status; when both parameters are nulls, hide background op status panel
    void setBackgroundOperationStatus(string icon, dstring statusText = null)
    {
        _backgroundOperationPanel.setBackgroundOperationStatus(icon, statusText);
    }

    /// Editor `onStateChange` slot
    protected void handleEditorStateChange(Widget source, ref EditorStateInfo editorState)
    {
        _editorStatePanel.setState(source, editorState);
    }

    void hideEditorState()
    {
        EditorStateInfo editorState;
        _editorStatePanel.setState(null, editorState);
    }
}
