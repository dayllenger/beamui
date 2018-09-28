/**
This module contains implementation of source code editor widget.

SourceEdit - base class for source code editors, with line numbering, syntax highlight, etc.

Synopsis:
---
import beamui.widgets.srcedit;
---

Copyright: Vadim Lopatin 2014-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.srcedit;

import beamui.core.units;
import beamui.graphics.colors;
import beamui.graphics.fonts;
import beamui.widgets.editors;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.widget;

class SourceEdit : EditBox
{
    @property
    {
        /// When true, line numbers are shown
        bool showLineNumbers() const
        {
            return _showLineNumbers;
        }
        /// ditto
        SourceEdit showLineNumbers(bool flag)
        {
            if (_showLineNumbers != flag)
            {
                _showLineNumbers = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
            return this;
        }

        /// When true, show modification marks for lines (whether line is unchanged/modified/modified_saved)
        bool showModificationMarks() const
        {
            return _showModificationMarks;
        }
        /// ditto
        SourceEdit showModificationMarks(bool flag)
        {
            if (_showModificationMarks != flag)
            {
                _showModificationMarks = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
            return this;
        }

        /// When true, show icons like bookmarks or breakpoints at the left
        bool showIcons() const
        {
            return _showIcons;
        }
        /// ditto
        SourceEdit showIcons(bool flag)
        {
            if (_showIcons != flag)
            {
                _showIcons = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
            return this;
        }

        /// When true, show folding controls at the left
        bool showFolding() const
        {
            return _showFolding;
        }
        /// ditto
        SourceEdit showFolding(bool flag)
        {
            if (_showFolding != flag)
            {
                _showFolding = flag;
                updateLeftPaneWidth();
                requestLayout();
            }
            return this;
        }

        string filename()
        {
            return _filename;
        }
    }

    /// Set bool property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setBoolProperty", "bool",
            "showIcons", "showFolding", "showModificationMarks", "showLineNumbers"));

    protected
    {
        bool _showLineNumbers = true; /// show line numbers in left pane
        bool _showModificationMarks = true; /// show modification marks in left pane
        bool _showIcons = false; /// show icons in left pane
        bool _showFolding = false; /// show folding controls in left pane

        int _lineNumbersWidth = 0;
        int _modificationMarksWidth = 0;
        int _iconsWidth = 0;
        int _foldingWidth = 0;

        uint _iconsPaneWidth = BACKEND_CONSOLE ? 1 : 16;
        uint _foldingPaneWidth = BACKEND_CONSOLE ? 1 : 12;
        uint _modificationMarksPaneWidth = BACKEND_CONSOLE ? 1 : 4;

        uint _leftPaneBackgroundColor = 0xF4F4F4;
        uint _leftPaneBackgroundColor2 = 0xFFFFFF;
        uint _leftPaneBackgroundColor3 = 0xF8F8F8;
        uint _leftPaneLineNumberColor = 0x4060D0;
        uint _leftPaneLineNumberColorEdited = 0xC0C000;
        uint _leftPaneLineNumberColorSaved = 0x00C000;
        uint _leftPaneLineNumberColorCurrentLine = 0xFFFFFFFF;
        uint _leftPaneLineNumberBackgroundColorCurrentLine = 0xC08080FF;
        uint _leftPaneLineNumberBackgroundColor = 0xF4F4F4;
        uint _colorIconBreakpoint = 0xFF0000;
        uint _colorIconBookmark = 0x0000FF;
        uint _colorIconError = 0x80FF0000;

        string _filename;
    }

    this()
    {
        _extendRightScrollBound = true;
        minFontSize(9).maxFontSize(75); // allow font zoom with Ctrl + MouseWheel
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

    override void onThemeChanged()
    {
        super.onThemeChanged();
        _leftPaneBackgroundColor = currentTheme.getColor("editor_left_pane_background");
        _leftPaneBackgroundColor2 = currentTheme.getColor("editor_left_pane_background2");
        _leftPaneBackgroundColor3 = currentTheme.getColor("editor_left_pane_background3");
        _leftPaneLineNumberColor = currentTheme.getColor("editor_left_pane_line_number_text");
        _leftPaneLineNumberColorEdited = currentTheme.getColor("editor_left_pane_line_number_text_edited", 0xC0C000);
        _leftPaneLineNumberColorSaved = currentTheme.getColor("editor_left_pane_line_number_text_saved", 0x00C000);
        _leftPaneLineNumberColorCurrentLine = currentTheme.getColor("editor_left_pane_line_number_text_current_line",
                0xFFFFFFFF);
        _leftPaneLineNumberBackgroundColorCurrentLine = currentTheme.getColor(
                "editor_left_pane_line_number_background_current_line", 0xC08080FF);
        _leftPaneLineNumberBackgroundColor = currentTheme.getColor("editor_left_pane_line_number_background");
        _colorIconBreakpoint = currentTheme.getColor("editor_left_pane_line_icon_breakpoint", 0xFF0000);
        _colorIconBookmark = currentTheme.getColor("editor_left_pane_line_icon_bookmark", 0x0000FF);
        _colorIconError = currentTheme.getColor("editor_left_pane_line_icon_error", 0x80FF0000);
    }

    override protected bool onLeftPaneMouseClick(MouseEvent event)
    {
        if (_leftPaneWidth <= 0)
            return false;

        Box cb = clientBox;
        Box lineBox = Box(cb.x - _leftPaneWidth, cb.y, _leftPaneWidth, _lineHeight);
        int i = _firstVisibleLine;
        while (true)
        {
            if (lineBox.y > cb.y + cb.h)
                break;
            if (lineBox.y <= event.y && event.y < lineBox.y + lineBox.h)
                return handleLeftPaneMouseClick(event, lineBox, i);

            i++;
            lineBox.y += _lineHeight;
        }
        return false;
    }

    protected bool handleLeftPaneMouseClick(MouseEvent event, Box b, int line)
    {
        b.width -= 3;
        if (_foldingWidth)
        {
            b.w -= _foldingWidth;
            Box b2 = Box(b.x + b.w, b.y, _foldingWidth, b.h);
            if (b2.x <= event.x && event.x < b2.x + b2.w)
                return handleLeftPaneFoldingMouseClick(event, b2, line);
        }
        if (_modificationMarksWidth)
        {
            b.w -= _modificationMarksWidth;
            Box b2 = Box(b.x + b.w, b.y, _modificationMarksWidth, b.h);
            if (b2.x <= event.x && event.x < b2.x + b2.w)
                return handleLeftPaneModificationMarksMouseClick(event, b2, line);
        }
        if (_lineNumbersWidth)
        {
            b.w -= _lineNumbersWidth;
            Box b2 = Box(b.x + b.w, b.y, _lineNumbersWidth, b.h);
            if (b2.x <= event.x && event.x < b2.x + b2.w)
                return handleLeftPaneLineNumbersMouseClick(event, b2, line);
        }
        if (_iconsWidth)
        {
            b.w -= _iconsWidth;
            Box b2 = Box(b.x + b.w, b.y, _iconsWidth, b.h);
            if (b2.x <= event.x && event.x < b2.x + b2.w)
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
                    if (!menu.openingSubmenu(_popupMenu))
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
            _content.lineIcons.toggleBookmark(line);
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
            dchar[] s = to!(dchar[])(lineCount + 1);
            foreach (ref ch; s)
                ch = '9';
            FontRef fnt = font;
            Size sz = fnt.textSize(cast(immutable)s);
            _lineNumbersWidth = sz.w;
        }
        _leftPaneWidth = _lineNumbersWidth + _modificationMarksWidth + _foldingWidth + _iconsWidth;
        if (_leftPaneWidth)
            _leftPaneWidth += BACKEND_CONSOLE ? 1 : 3;
    }

    override protected void drawLeftPane(DrawBuf buf, Rect rc, int line)
    {
        buf.fillRect(rc, _leftPaneBackgroundColor);
        //buf.fillRect(Rect(rc.right - 2, rc.top, rc.right - 1, rc.bottom), _leftPaneBackgroundColor2);
        //buf.fillRect(Rect(rc.right - 1, rc.top, rc.right - 0, rc.bottom), _leftPaneBackgroundColor3);
        rc.right -= BACKEND_CONSOLE ? 1 : 3;
        if (_foldingWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _foldingWidth;
            drawLeftPaneFolding(buf, rc2, line);
        }
        if (_modificationMarksWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _modificationMarksWidth;
            drawLeftPaneModificationMarks(buf, rc2, line);
        }
        if (_lineNumbersWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _lineNumbersWidth;
            drawLeftPaneLineNumbers(buf, rc2, line);
        }
        if (_iconsWidth)
        {
            Rect rc2 = rc;
            rc.right = rc2.left = rc2.right - _iconsWidth;
            drawLeftPaneIcons(buf, rc2, line);
        }
    }

    protected void drawLeftPaneFolding(DrawBuf buf, Rect rc, int line)
    {
        buf.fillRect(rc, _leftPaneBackgroundColor2);
    }

    protected void drawLeftPaneModificationMarks(DrawBuf buf, Rect rc, int line)
    {
        if (line >= 0 && line < content.length)
        {
            EditStateMark m = content.editMark(line);
            if (m == EditStateMark.changed)
            {
                // modified, not saved
                buf.fillRect(rc, 0xFFD040);
            }
            else if (m == EditStateMark.saved)
            {
                // modified, saved
                buf.fillRect(rc, 0x20C020);
            }
        }
    }

    protected void drawLeftPaneLineNumbers(DrawBuf buf, Rect rc, int line)
    {
        uint bgcolor = _leftPaneLineNumberBackgroundColor;
        if (line == _caretPos.line && !isFullyTransparentColor(_leftPaneLineNumberBackgroundColorCurrentLine))
            bgcolor = _leftPaneLineNumberBackgroundColorCurrentLine;
        buf.fillRect(rc, bgcolor);
        if (line < 0)
            return;
        dstring s = to!dstring(line + 1);
        FontRef fnt = font;
        Size sz = fnt.textSize(s);
        int x = rc.right - sz.w;
        int y = rc.top + (rc.height - sz.h) / 2;
        uint color = _leftPaneLineNumberColor;
        if (line == _caretPos.line && !isFullyTransparentColor(_leftPaneLineNumberColorCurrentLine))
            color = _leftPaneLineNumberColorCurrentLine;
        if (line >= 0 && line < content.length)
        {
            EditStateMark m = content.editMark(line);
            if (m == EditStateMark.changed)
            {
                // modified, not saved
                color = _leftPaneLineNumberColorEdited;
            }
            else if (m == EditStateMark.saved)
            {
                // modified, saved
                color = _leftPaneLineNumberColorSaved;
            }
        }
        fnt.drawText(buf, x, y, s, color);
    }

    protected void drawLeftPaneIcons(DrawBuf buf, Rect rc, int line)
    {
        buf.fillRect(rc, _leftPaneBackgroundColor3);
        drawLeftPaneIcon(buf, rc, content.lineIcons.findByLineAndType(line, LineIconType.error));
        drawLeftPaneIcon(buf, rc, content.lineIcons.findByLineAndType(line, LineIconType.bookmark));
        drawLeftPaneIcon(buf, rc, content.lineIcons.findByLineAndType(line, LineIconType.breakpoint));
    }

    protected void drawLeftPaneIcon(DrawBuf buf, Rect rc, LineIcon icon)
    {
        if (!icon)
            return;
        if (icon.type == LineIconType.error)
        {
            buf.fillRect(rc, _colorIconError);
        }
        else if (icon.type == LineIconType.bookmark)
        {
            int dh = rc.height / 4;
            rc.top += dh;
            rc.bottom -= dh;
            buf.fillRect(rc, _colorIconBookmark);
        }
        else if (icon.type == LineIconType.breakpoint)
        {
            if (rc.height > rc.width)
            {
                int delta = rc.height - rc.width;
                rc.top += delta / 2;
                rc.bottom -= (delta + 1) / 2;
            }
            else
            {
                int delta = rc.width - rc.height;
                rc.left += delta / 2;
                rc.right -= (delta + 1) / 2;
            }
            int dh = rc.height / 5;
            rc.top += dh;
            rc.bottom -= dh;
            int dw = rc.width / 5;
            rc.left += dw;
            rc.right -= dw;
            buf.fillRect(rc, _colorIconBreakpoint);
        }
    }
}
