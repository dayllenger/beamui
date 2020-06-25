/**
Source code editor widget.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.srcedit;

import beamui.core.units;
import beamui.text.simple : drawSimpleText;
import beamui.text.sizetest;
import beamui.text.style : TextAlign, TextStyle;
import beamui.widgets.editors;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.scroll : ScrollBarMode;
import beamui.widgets.widget;

/// Base class for source code editors, with line numbering, syntax highlight, etc.
class SourceEdit : TextArea
{
    /// When true, line numbers are shown
    bool showLineNumbers = true;
    /// When true, show modification marks for lines (whether line is unchanged/modified/modified_saved)
    bool showModificationMarks = true;
    /// When true, show icons (e.g. bookmarks or breakpoints) on the left pane
    bool showIcons;
    /// When true, show folding controls on the left pane
    bool showFolding;

    this()
    {
        // allow font zoom with Ctrl + MouseWheel
        minFontSize = 9;
        maxFontSize = 75;
    }

    override protected Element createElement()
    {
        return new ElemSourceEdit(content);
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemSourceEdit el = fastCast!ElemSourceEdit(element);
        el.showLineNumbers = showLineNumbers;
        el.showModificationMarks = showModificationMarks;
        el.showIcons = showIcons;
        el.showFolding = showFolding;
    }
}

class ElemSourceEdit : ElemTextArea
{
    @property
    {
        bool showLineNumbers() const { return _showLineNumbers; }
        /// ditto
        void showLineNumbers(bool flag)
        {
            if (_showLineNumbers == flag)
                return;
            _showLineNumbers = flag;
            updateLeftPaneWidth();
            requestLayout();
        }

        bool showModificationMarks() const { return _showModificationMarks; }
        /// ditto
        void showModificationMarks(bool flag)
        {
            if (_showModificationMarks == flag)
                return;
            _showModificationMarks = flag;
            updateLeftPaneWidth();
            requestLayout();
        }

        bool showIcons() const { return _showIcons; }
        /// ditto
        void showIcons(bool flag)
        {
            if (_showIcons == flag)
                return;
            _showIcons = flag;
            updateLeftPaneWidth();
            requestLayout();
        }

        bool showFolding() const { return _showFolding; }
        /// ditto
        void showFolding(bool flag)
        {
            if (_showFolding == flag)
                return;
            _showFolding = flag;
            updateLeftPaneWidth();
            requestLayout();
        }
    }

    private
    {
        bool _showLineNumbers = true;
        bool _showModificationMarks = true;
        bool _showIcons;
        bool _showFolding;

        float _lineNumbersWidth = 0;
        float _modificationMarksWidth = 0;
        float _iconsWidth = 0;
        float _foldingWidth = 0;

        uint _iconsPaneWidth = BACKEND_CONSOLE ? 1 : 16;
        uint _foldingPaneWidth = BACKEND_CONSOLE ? 1 : 12;
        uint _modificationMarksPaneWidth = BACKEND_CONSOLE ? 1 : 4;

        Color _leftPaneBgColor1;
        Color _leftPaneBgColor2;
        Color _leftPaneBgColor3;
        Color _leftPaneLineNumColor;
        Color _leftPaneLineNumColorEdited;
        Color _leftPaneLineNumColorSaved;
        Color _leftPaneLineNumColorCurrentLine;
        Color _leftPaneLineNumBgColor;
        Color _leftPaneLineNumBgColorCurrLine;
        Color _colorIconBreakpoint;
        Color _colorIconBookmark;
        Color _colorIconError;
    }

    this(EditableContent content)
    {
        super(content);
        _extendRightScrollBound = true;
    }

    override void handleCustomPropertiesChange()
    {
        super.handleCustomPropertiesChange();

        auto style = this.style;
        auto pick = (string name) => style.getPropertyValue!Color(name, Color(255, 0, 255));
        _leftPaneBgColor1 = pick("--left-pane-bg-1");
        _leftPaneBgColor2 = pick("--left-pane-bg-2");
        _leftPaneBgColor3 = pick("--left-pane-bg-3");
        _leftPaneLineNumColor = pick("--left-pane-number-text");
        _leftPaneLineNumColorEdited = pick("--left-pane-number-text-edited");
        _leftPaneLineNumColorSaved = pick("--left-pane-number-text-saved");
        _leftPaneLineNumColorCurrentLine = pick("--left-pane-number-text-current-line");
        _leftPaneLineNumBgColor = pick("--left-pane-number-bg");
        _leftPaneLineNumBgColorCurrLine = pick("--left-pane-number-bg-current-line");
        _colorIconBreakpoint = pick("--left-pane-icon-breakpoint");
        _colorIconBookmark = pick("--left-pane-icon-bookmark");
        _colorIconError = pick("--left-pane-icon-error");
    }

    override protected bool handleLeftPaneMouseClick(MouseEvent event)
    {
        if (_leftPaneWidth <= 0)
            return false;

        Box cb = clientBox;
        Box lineBox = Box(cb.x - _leftPaneWidth, cb.y, _leftPaneWidth, lineHeight);
        int i = firstVisibleLine;
        while (true)
        {
            if (lineBox.y > cb.y + cb.h)
                break;
            if (lineBox.containsY(event.y))
                return handleLeftPaneMouseClick(event, lineBox, i);

            i++;
            lineBox.y += lineHeight;
        }
        return false;
    }

    protected bool handleLeftPaneMouseClick(MouseEvent event, Box b, int line)
    {
        b.w -= 3;
        if (_foldingWidth)
        {
            b.w -= _foldingWidth;
            Box b2 = Box(b.x + b.w, b.y, _foldingWidth, b.h);
            if (b2.containsX(event.x))
                return handleLeftPaneFoldingMouseClick(event, b2, line);
        }
        if (_modificationMarksWidth)
        {
            b.w -= _modificationMarksWidth;
            Box b2 = Box(b.x + b.w, b.y, _modificationMarksWidth, b.h);
            if (b2.containsX(event.x))
                return handleLeftPaneModificationMarksMouseClick(event, b2, line);
        }
        if (_lineNumbersWidth)
        {
            b.w -= _lineNumbersWidth;
            Box b2 = Box(b.x + b.w, b.y, _lineNumbersWidth, b.h);
            if (b2.containsX(event.x))
                return handleLeftPaneLineNumbersMouseClick(event, b2, line);
        }
        if (_iconsWidth)
        {
            b.w -= _iconsWidth;
            Box b2 = Box(b.x + b.w, b.y, _iconsWidth, b.h);
            if (b2.containsX(event.x))
                return handleLeftPaneIconsMouseClick(event, b2, line);
        }
        return true;
    }

    protected bool handleLeftPaneFoldingMouseClick(MouseEvent event, Box b, int line)
    {
        return true;
    }

    protected bool handleLeftPaneModificationMarksMouseClick(MouseEvent event, Box b, int line)
    {
        return true;
    }

    protected bool handleLeftPaneLineNumbersMouseClick(MouseEvent event, Box b, int line)
    {
        return true;
    }

    protected bool handleLeftPaneIconsMouseClick(MouseEvent event, Box b, int line)
    {
/+
        if (event.button == MouseButton.right)
        {
            if (auto menu = getLeftPaneIconsPopupMenu(line))
            {
                if (menu.openingSubmenu.assigned)
                    if (!menu.openingSubmenu(popupMenu))
                        return true;
                auto popup = window.showPopup(menu);
                popup.anchor = WeakRef!Widget(this);
                popup.alignment = PopupAlign.point | PopupAlign.right;
                popup.point = Point(event.x, event.y);
            }
            return true;
        }
+/
        return true;
    }

    protected Menu getLeftPaneIconsPopupMenu(int line)
    {
        ACTION_ED_TOGGLE_BOOKMARK.bind(this, {
            content.lineIcons.toggleBookmark(line);
        });
        Menu m = render!Menu;
        m.wrap(m.item(ACTION_ED_TOGGLE_BOOKMARK));
        return m;
    }

    override protected void updateLeftPaneWidth()
    {
        _iconsWidth = _showIcons ? _iconsPaneWidth : 0;
        _foldingWidth = _showFolding ? _foldingPaneWidth : 0;
        _modificationMarksWidth = _showModificationMarks && (BACKEND_GUI || !_showLineNumbers) ?
            _modificationMarksPaneWidth : 0;
        _lineNumbersWidth = 0;
        if (_showLineNumbers)
        {
            dchar[] s = to!(dchar[])(content.lineCount);
            foreach (ref ch; s)
                ch = '9';
            auto st = TextLayoutStyle(font.get);
            const sz = computeTextSize(cast(immutable)s, st);
            _lineNumbersWidth = sz.w;
        }
        _leftPaneWidth = _lineNumbersWidth + _modificationMarksWidth + _foldingWidth + _iconsWidth;
        if (_leftPaneWidth)
            _leftPaneWidth += BACKEND_CONSOLE ? 1 : 3;
    }

    override protected void drawLeftPane(Painter pr, Rect rc, int line)
    {
        pr.fillRect(rc.left, rc.top, rc.width, rc.height, _leftPaneBgColor1);
        rc.right -= BACKEND_CONSOLE ? 1 : 3;
        if (_foldingWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _foldingWidth;
            drawLeftPaneFolding(pr, rc2, line);
        }
        if (_modificationMarksWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _modificationMarksWidth;
            drawLeftPaneModificationMarks(pr, rc2, line);
        }
        if (_lineNumbersWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _lineNumbersWidth;
            drawLeftPaneLineNumbers(pr, rc2, line);
        }
        if (_iconsWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _iconsWidth;
            drawLeftPaneIcons(pr, rc2, line);
        }
    }

    protected void drawLeftPaneFolding(Painter pr, Rect rc, int line)
    {
        pr.fillRect(rc.left, rc.top, rc.width, rc.height, _leftPaneBgColor2);
    }

    protected void drawLeftPaneModificationMarks(Painter pr, Rect rc, int line)
    {
        if (0 <= line && line < content.lineCount)
        {
            EditStateMark m = content.editMark(line);
            if (m == EditStateMark.changed)
            {
                // modified, not saved
                pr.fillRect(rc.left, rc.top, rc.width, rc.height, Color(0xFFD040));
            }
            else if (m == EditStateMark.saved)
            {
                // modified, saved
                pr.fillRect(rc.left, rc.top, rc.width, rc.height, Color(0x20C020));
            }
        }
    }

    protected void drawLeftPaneLineNumbers(Painter pr, Rect rc, int line)
    {
        Color bgcolor = _leftPaneLineNumBgColor;
        if (line == caretPos.line && !_leftPaneLineNumBgColorCurrLine.isFullyTransparent)
            bgcolor = _leftPaneLineNumBgColorCurrLine;
        pr.fillRect(rc.left, rc.top, rc.width, rc.height, bgcolor);
        if (line < 0)
            return;

        dstring s = to!dstring(line + 1);
        TextStyle st;
        st.font = font.get;
        st.alignment = TextAlign.end;
        st.color = _leftPaneLineNumColor;
        if (line == caretPos.line && !_leftPaneLineNumColorCurrentLine.isFullyTransparent)
            st.color = _leftPaneLineNumColorCurrentLine;
        if (0 <= line && line < content.lineCount)
        {
            EditStateMark m = content.editMark(line);
            if (m == EditStateMark.changed)
            {
                // modified, not saved
                st.color = _leftPaneLineNumColorEdited;
            }
            else if (m == EditStateMark.saved)
            {
                // modified, saved
                st.color = _leftPaneLineNumColorSaved;
            }
        }
        drawSimpleText(pr, s, rc.left, rc.top, rc.width, st);
    }

    protected void drawLeftPaneIcons(Painter pr, Rect rc, int line)
    {
        pr.fillRect(rc.left, rc.top, rc.width, rc.height, _leftPaneBgColor3);
        drawLeftPaneIcon(pr, rc, content.lineIcons.findByLineAndType(line, LineIconType.error));
        drawLeftPaneIcon(pr, rc, content.lineIcons.findByLineAndType(line, LineIconType.bookmark));
        drawLeftPaneIcon(pr, rc, content.lineIcons.findByLineAndType(line, LineIconType.breakpoint));
    }

    protected void drawLeftPaneIcon(Painter pr, Rect rc, LineIcon icon)
    {
        if (!icon)
            return;
        if (icon.type == LineIconType.error)
        {
            pr.fillRect(rc.left, rc.top, rc.width, rc.height, _colorIconError);
        }
        else if (icon.type == LineIconType.bookmark)
        {
            const dh = rc.height / 4;
            rc.top += dh;
            rc.bottom -= dh;
            pr.fillRect(rc.left, rc.top, rc.width, rc.height, _colorIconBookmark);
        }
        else if (icon.type == LineIconType.breakpoint)
        {
            if (rc.height > rc.width)
            {
                const delta = rc.height - rc.width;
                rc.top += delta / 2;
                rc.bottom -= (delta + 1) / 2;
            }
            else
            {
                const delta = rc.width - rc.height;
                rc.left += delta / 2;
                rc.right -= (delta + 1) / 2;
            }
            const dh = rc.height / 5;
            rc.top += dh;
            rc.bottom -= dh;
            const dw = rc.width / 5;
            rc.left += dw;
            rc.right -= dw;
            pr.fillRect(rc.left, rc.top, rc.width, rc.height, _colorIconBreakpoint);
        }
    }
}
