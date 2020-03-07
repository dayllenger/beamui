/**
Source code editor widget.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.srcedit;
/+
import beamui.core.units;
import beamui.text.simple : drawSimpleText;
import beamui.text.sizetest;
import beamui.text.style : TextAlign, TextStyle;
import beamui.widgets.editors;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.scroll : ScrollBarMode;
import beamui.widgets.widget;

alias ElemSourceEdit = SourceEdit;

class NgSourceEdit : NgEditBox
{
    bool showLineNumbers = true;
    bool showModificationMarks = true;
    bool showIcons;
    bool showFolding;

    static NgSourceEdit make(EditableContent content)
        in(content)
    {
        NgSourceEdit w = arena.make!NgSourceEdit;
        w.content = content;
        w.hscrollbarMode = ScrollBarMode.automatic;
        w.vscrollbarMode = ScrollBarMode.automatic;
        w.minFontSize = 9;
        w.maxFontSize = 75;
        return w;
    }

    override protected Element fetchElement()
    {
        auto el = fetchEl!ElemSourceEdit;
        el.setAttribute("ignore");
        return el;
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

/// Base class for source code editors, with line numbering, syntax highlight, etc.
class SourceEdit : EditBox
{
    @property
    {
        /// When true, line numbers are shown
        bool showLineNumbers() const { return _showLineNumbers; }
        /// ditto
        void showLineNumbers(bool flag)
        {
            if (_showLineNumbers != flag)
            {
                _showLineNumbers = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
        }

        /// When true, show modification marks for lines (whether line is unchanged/modified/modified_saved)
        bool showModificationMarks() const { return _showModificationMarks; }
        /// ditto
        void showModificationMarks(bool flag)
        {
            if (_showModificationMarks != flag)
            {
                _showModificationMarks = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
        }

        /// When true, show icons like bookmarks or breakpoints at the left
        bool showIcons() const { return _showIcons; }
        /// ditto
        void showIcons(bool flag)
        {
            if (_showIcons != flag)
            {
                _showIcons = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
        }

        /// When true, show folding controls at the left
        bool showFolding() const { return _showFolding; }
        /// ditto
        void showFolding(bool flag)
        {
            if (_showFolding != flag)
            {
                _showFolding = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
        }

        string filename() const { return _filename; }
    }

    private
    {
        bool _showLineNumbers = true; /// show line numbers in left pane
        bool _showModificationMarks = true; /// show modification marks in left pane
        bool _showIcons = false; /// show icons in left pane
        bool _showFolding = false; /// show folding controls in left pane

        float _lineNumbersWidth = 0;
        float _modificationMarksWidth = 0;
        float _iconsWidth = 0;
        float _foldingWidth = 0;

        uint _iconsPaneWidth = BACKEND_CONSOLE ? 1 : 16;
        uint _foldingPaneWidth = BACKEND_CONSOLE ? 1 : 12;
        uint _modificationMarksPaneWidth = BACKEND_CONSOLE ? 1 : 4;

        Color _leftPaneBgColor = Color(0xF4F4F4);
        Color _leftPaneBgColor2 = Color(0xFFFFFF);
        Color _leftPaneBgColor3 = Color(0xF8F8F8);
        Color _leftPaneLineNumColor = Color(0x4060D0);
        Color _leftPaneLineNumColorEdited = Color(0xC0C000);
        Color _leftPaneLineNumColorSaved = Color(0x00C000);
        Color _leftPaneLineNumColorCurrentLine = Color.transparent;
        Color _leftPaneLineNumBgColorCurrLine = Color(0x8080FF, 0x40);
        Color _leftPaneLineNumBgColor = Color(0xF4F4F4);
        Color _colorIconBreakpoint = Color(0xFF0000);
        Color _colorIconBookmark = Color(0x0000FF);
        Color _colorIconError = Color(0xFF0000, 0x80);

        string _filename;
    }

    this()
    {
        _extendRightScrollBound = true;
        // allow font zoom with Ctrl + MouseWheel
        minFontSize = 9;
        maxFontSize = 75;
    }

    /// Load from file
    bool load(string fn)
    {
        if (content.load(fn))
        {
            _filename = fn;
            requestLayout();
            return true;
        }
        // failed
        _filename = null;
        return false;
    }

    bool save(string fn)
    {
        if (content.save(fn))
        {
            _filename = fn;
            requestLayout();
            window.update();
            return true;
        }
        // failed
        requestLayout();
        window.update();
        _filename = null;
        return false;
    }

    override void handleThemeChange()
    {
        super.handleThemeChange();
        _leftPaneBgColor = currentTheme.getColor("editor_left_pane_background", Color(0xF4F4F4));
        _leftPaneBgColor2 = currentTheme.getColor("editor_left_pane_background2", Color(0xFFFFFF));
        _leftPaneBgColor3 = currentTheme.getColor("editor_left_pane_background3", Color(0xF8F8F8));
        _leftPaneLineNumColor = currentTheme.getColor("editor_left_pane_line_number_text", Color(0x4060D0));
        _leftPaneLineNumColorEdited = currentTheme.getColor("editor_left_pane_line_number_text_edited", Color(0xC0C000));
        _leftPaneLineNumColorSaved = currentTheme.getColor("editor_left_pane_line_number_text_saved", Color(0x00C000));
        _leftPaneLineNumColorCurrentLine = currentTheme.getColor("editor_left_pane_line_number_text_current_line");
        _leftPaneLineNumBgColorCurrLine = currentTheme.getColor(
                "editor_left_pane_line_number_background_current_line", Color(0x8080FF, 0x40));
        _leftPaneLineNumBgColor = currentTheme.getColor("editor_left_pane_line_number_background", Color(0xF4F4F4));
        _colorIconBreakpoint = currentTheme.getColor("editor_left_pane_line_icon_breakpoint", Color(0xFF0000));
        _colorIconBookmark = currentTheme.getColor("editor_left_pane_line_icon_bookmark", Color(0x0000FF));
        _colorIconError = currentTheme.getColor("editor_left_pane_line_icon_error", Color(0xFF0000, 0x80));
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
        if (event.button == MouseButton.right)
        {
            if (auto menu = getLeftPaneIconsPopupMenu(line))
            {
                if (menu.openingSubmenu.assigned)
                    if (!menu.openingSubmenu(popupMenu))
                        return true;
                auto popup = window.showPopup(menu, WeakRef!Widget(this),
                        PopupAlign.point | PopupAlign.right, event.x, event.y);
            }
            return true;
        }
        return true;
    }

    protected Menu getLeftPaneIconsPopupMenu(int line)
    {
        Menu menu = new Menu;
        ACTION_ED_TOGGLE_BOOKMARK.bind(this, {
            content.lineIcons.toggleBookmark(line);
        });
        menu.add(ACTION_ED_TOGGLE_BOOKMARK);
        return menu;
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
        pr.fillRect(rc.left, rc.top, rc.width, rc.height, _leftPaneBgColor);
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
+/
