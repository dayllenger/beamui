/**
Single-line and multiline simple text editors.

Copyright: Vadim Lopatin 2014-2017, James Johnson 2017, dayllenger 2019-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.editors;

public import beamui.core.editable;
import beamui.core.collections;
import beamui.core.linestream;
import beamui.core.parseutils : isWordChar;
import beamui.core.signals;
import beamui.core.stdaction;
import beamui.core.streams;
import beamui.core.undo;
import beamui.graphics.brush : Brush;
import beamui.graphics.colors;
import beamui.graphics.path;
import beamui.graphics.pen : Pen;
import beamui.style.computed_style : ComputedStyle;
import beamui.text.line;
import beamui.text.simple;
import beamui.text.sizetest;
import beamui.text.style;
import beamui.widgets.controls;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.scroll;
import beamui.widgets.scrollbar;
import beamui.widgets.widget;
import beamui.platforms.common.platform;

/// Editor state to display in status line
struct EditorStateInfo
{
    /// Editor mode: true if replace mode, false if insert mode
    bool replaceMode;
    /// Cursor position column (1-based)
    int col;
    /// Cursor position line (1-based)
    int line;
    /// Character under cursor
    dchar character;
    /// Returns true if editor is in active state
    @property bool active() const
    {
        return col > 0 && line > 0;
    }
}

/// Flags used for search / replace / text highlight
enum TextSearchOptions
{
    none = 0,
    caseSensitive = 1,
    wholeWords = 2,
    selectionOnly = 4,
}

/// Delete word before cursor (ctrl + backspace)
Action ACTION_ED_DEL_PREV_WORD;
/// Delete char after cursor (ctrl + del key)
Action ACTION_ED_DEL_NEXT_WORD;

/// Indent text block or single line (e.g., Tab key to insert tab character)
Action ACTION_ED_INDENT;
/// Unindent text or remove whitespace before cursor (usually Shift+Tab)
Action ACTION_ED_UNINDENT;

/// Insert new line before current position (Ctrl+Shift+Enter)
Action ACTION_ED_PREPEND_NEW_LINE;
/// Insert new line after current position (Ctrl+Enter)
Action ACTION_ED_APPEND_NEW_LINE;
/// Delete current line
Action ACTION_ED_DELETE_LINE;
/// Turn On/Off replace mode
Action ACTION_ED_TOGGLE_REPLACE_MODE;

/// Toggle line comment
Action ACTION_ED_TOGGLE_LINE_COMMENT;
/// Toggle block comment
Action ACTION_ED_TOGGLE_BLOCK_COMMENT;
/// Toggle bookmark in current line
Action ACTION_ED_TOGGLE_BOOKMARK;
/// Move cursor to next bookmark
Action ACTION_ED_GOTO_NEXT_BOOKMARK;
/// Move cursor to previous bookmark
Action ACTION_ED_GOTO_PREVIOUS_BOOKMARK;

/// Find text
Action ACTION_ED_FIND;
/// Find next occurence - continue search forward
Action ACTION_ED_FIND_NEXT;
/// Find previous occurence - continue search backward
Action ACTION_ED_FIND_PREV;
/// Replace text
Action ACTION_ED_REPLACE;

void initStandardEditorActions()
{
    ACTION_ED_DEL_PREV_WORD = new Action(null, Key.backspace, KeyMods.control);
    ACTION_ED_DEL_NEXT_WORD = new Action(null, Key.del, KeyMods.control);

    ACTION_ED_INDENT = new Action(null, Key.tab);
    ACTION_ED_UNINDENT = new Action(null, Key.tab, KeyMods.shift);

    ACTION_ED_PREPEND_NEW_LINE = new Action(tr("Prepend new line"), Key.enter, KeyMods.control | KeyMods.shift);
    ACTION_ED_APPEND_NEW_LINE = new Action(tr("Append new line"), Key.enter, KeyMods.control);
    ACTION_ED_DELETE_LINE = new Action(tr("Delete line"), Key.D, KeyMods.control);
    ACTION_ED_TOGGLE_REPLACE_MODE = new Action(tr("Replace mode"), Key.ins);
    ACTION_ED_TOGGLE_LINE_COMMENT = new Action(tr("Toggle line comment"), Key.divide, KeyMods.control);
    ACTION_ED_TOGGLE_BLOCK_COMMENT = new Action(tr("Toggle block comment"), Key.divide, KeyMods.control | KeyMods.shift);

    ACTION_ED_TOGGLE_BOOKMARK = new Action(tr("Toggle bookmark"), Key.B, KeyMods.control | KeyMods.shift);
    ACTION_ED_GOTO_NEXT_BOOKMARK = new Action(tr("Go to next bookmark"), Key.down, KeyMods.control | KeyMods.shift | KeyMods.alt);
    ACTION_ED_GOTO_PREVIOUS_BOOKMARK = new Action(tr("Go to previous bookmark"), Key.up, KeyMods.control | KeyMods.shift | KeyMods.alt);

    ACTION_ED_FIND = new Action(tr("Find..."), Key.F, KeyMods.control);
    ACTION_ED_FIND_NEXT = new Action(tr("Find next"), Key.F3);
    ACTION_ED_FIND_PREV = new Action(tr("Find previous"), Key.F3, KeyMods.shift);
    ACTION_ED_REPLACE = new Action(tr("Replace..."), Key.H, KeyMods.control);

    bunch(
        ACTION_ED_DEL_PREV_WORD,
        ACTION_ED_DEL_NEXT_WORD,
        ACTION_ED_INDENT,
        ACTION_ED_UNINDENT,
    ).context(ActionContext.widget);
    bunch(
        ACTION_ED_PREPEND_NEW_LINE,
        ACTION_ED_APPEND_NEW_LINE,
        ACTION_ED_DELETE_LINE,
        ACTION_ED_TOGGLE_REPLACE_MODE,
        ACTION_ED_TOGGLE_LINE_COMMENT,
        ACTION_ED_TOGGLE_BLOCK_COMMENT,
        ACTION_ED_TOGGLE_BOOKMARK,
        ACTION_ED_GOTO_NEXT_BOOKMARK,
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK,
        ACTION_ED_FIND,
        ACTION_ED_FIND_NEXT,
        ACTION_ED_FIND_PREV,
        ACTION_ED_REPLACE
    ).context(ActionContext.widgetTree);
}

class NgEditLine : NgWidget
{
    dstring placeholder;
    dchar passwordChar = 0;

    bool readOnly;
    bool enableCaretBlinking = true;
    bool copyWholeLineWhenNoSelection = true;
    bool wantTabs;

    void delegate(dstring) onChange;

    @property void text(dstring str)
    {
        _text = str;
        _replace = true;
    }

    private
    {
        dstring _text;
        bool _replace;
    }

    static NgEditLine make(void delegate(dstring) onChange)
    {
        NgEditLine w = arena.make!NgEditLine;
        w.onChange = onChange;
        return w;
    }

    static NgEditLine make(dstring text, void delegate(dstring) onChange)
    {
        NgEditLine w = arena.make!NgEditLine;
        w._text = text;
        w._replace = true;
        w.onChange = onChange;
        return w;
    }

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemEditLine;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemEditLine el = fastCast!ElemEditLine(element);
        if (_replace)
            el.text = _text;
        el.placeholder = placeholder;
        el.passwordChar = passwordChar;

        el.readOnly = readOnly;
        el.enableCaretBlinking = enableCaretBlinking;
        el.copyWholeLineWhenNoSelection = copyWholeLineWhenNoSelection;
        el.wantTabs = wantTabs;

        el.onChange.clear();
        if (onChange)
            el.onChange ~= onChange;
    }
}
/+
class NgEditBox : NgWidget
{
    dstring placeholder;

    bool readOnly;
    bool enableCaretBlinking = true;
    bool copyWholeLineWhenNoSelection = true;

    bool wantTabs = true;
    bool useSpacesForTabs = true;
    int tabSize = 4;

    bool smartIndentsAfterPaste;

    bool showTabPositionMarks;
    bool showWhiteSpaceMarks;

    int minFontSize = -1;
    int maxFontSize = -1;

    void delegate(EditableContent) onChange;

    protected EditableContent content;
    protected ScrollBarMode hscrollbarMode;
    protected ScrollBarMode vscrollbarMode;

    static NgEditBox make(
        EditableContent content,
        ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
        ScrollBarMode vscrollbarMode = ScrollBarMode.automatic,
    )
        in(content)
    {
        NgEditBox w = arena.make!NgEditBox;
        w.content = content;
        w.hscrollbarMode = hscrollbarMode;
        w.vscrollbarMode = vscrollbarMode;
        return w;
    }

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

    override protected Element fetchElement()
    {
        auto el = fetchEl!ElemEditBox;
        el.setAttribute("ignore");
        return el;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemEditBox el = fastCast!ElemEditBox(element);
        el.content = content;
        el.hscrollbarMode = hscrollbarMode;
        el.vscrollbarMode = vscrollbarMode;

        el.placeholder = placeholder;

        el.readOnly = readOnly;
        el.enableCaretBlinking = enableCaretBlinking;
        el.copyWholeLineWhenNoSelection = copyWholeLineWhenNoSelection;

        el.wantTabs = wantTabs;
        el.useSpacesForTabs = useSpacesForTabs;
        el.tabSize = tabSize;

        el.smartIndentsAfterPaste = smartIndentsAfterPaste;

        el.showTabPositionMarks = showTabPositionMarks;
        el.showWhiteSpaceMarks = showWhiteSpaceMarks;

        el.minFontSize = minFontSize;
        el.maxFontSize = maxFontSize;

        el.onContentChange.clear();
        if (onChange)
            el.onContentChange ~= onChange;
    }
}
+/
/// Common interface for single- and multiline editors
interface IEditor
{
    @property
    {
        /// Text as a string
        dstring text() const;
        /// ditto
        void text(dstring txt);

        /// Placeholder is a short peace of text that describe expected value in an input field
        dstring placeholder() const;
        /// ditto
        void placeholder(dstring txt);

        dstring minSizeTester() const;
        /// ditto
        void minSizeTester(dstring txt);

        /// When true, user cannot change content of the editor
        bool readOnly() const;
        /// ditto
        void readOnly(bool flag);

        /// When true, entered character replaces the character under cursor
        bool replaceMode() const;
        /// ditto
        void replaceMode(bool flag);

        /// When true, enables caret blinking, otherwise it's always visible
        bool enableCaretBlinking() const;
        /// ditto
        void enableCaretBlinking(bool flag);
    }

    /// Copy currently selected text into clipboard
    void copy();
    /// Cut currently selected text into clipboard
    void cut();
    /// Replace currently selected text with clipboard content
    void paste();

    /// Clear selection (doesn't change the text, just deselects)
    void deselect();
    /// Select the whole text
    void selectAll();
/+
    /// Create the default popup menu with undo/redo/cut/copy/paste actions
    static Menu createDefaultPopupMenu()
    {
        auto menu = new Menu;
        menu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);
        return menu;
    }
+/
}

/// Single-line text field
class ElemEditLine : Element, IEditor, ActionOperator
{
    @property
    {
        /// Text line string
        override dstring text() const { return _str; }
        /// ditto
        override void text(dstring txt)
        {
            if (_str != txt)
            {
                txt = replaceEOLsWithSpaces(txt);
                const r = LineRange(0, lineLength);
                performOperation(new SingleLineEditOperation(r, txt));
            }
        }

        dstring placeholder() const
        {
            return _placeholder ? _placeholder.str : null;
        }
        void placeholder(dstring txt)
        {
            if (!_placeholder)
            {
                if (txt.length > 0)
                {
                    _placeholder = new SimpleText(txt);
                    _placeholder.style.font = font;
                    _placeholder.style.color = NamedColor.gray;
                }
            }
            else
                _placeholder.str = txt;
        }

        dstring minSizeTester() const
        {
            return _minSizeTester.str;
        }
        void minSizeTester(dstring txt)
        {
            _minSizeTester.str = txt;
            requestLayout();
        }

        bool readOnly() const
        {
            return (state & State.readOnly) != 0;
        }
        void readOnly(bool flag)
        {
            if (flag)
                setState(State.readOnly);
            else
                resetState(State.readOnly);
        }

        bool replaceMode() const { return _replaceMode; }
        void replaceMode(bool flag)
        {
            _replaceMode = flag;
            invalidate();
        }

        bool enableCaretBlinking() const { return _enableCaretBlinking; }
        void enableCaretBlinking(bool flag)
        {
            stopCaretBlinking();
            _enableCaretBlinking = flag;
        }

        /// Password character - 0 for normal editor, some character
        /// e.g. `*` to hide text by replacing all characters with this char
        dchar passwordChar() const { return _passwordChar; }
        /// ditto
        void passwordChar(dchar ch)
        {
            if (_passwordChar != ch)
            {
                _passwordChar = ch;
                requestLayout();
            }
        }

        /// Length of the line string
        int lineLength() const
        {
            return cast(int)_str.length;
        }

        /// True when there is no text
        bool empty() const
        {
            return _str.length == 0;
        }

        /// Returns true if the line is empty or consists only of spaces and tabs
        bool isBlank() const
        {
            foreach (ch; _str)
                if (ch != ' ' && ch != '\t')
                    return false;
            return true;
        }

        /// Returns caret position
        int caretPos() const { return _caretPos; }

        /// Current selection range
        LineRange selectionRange() const { return _selectionRange; }
        /// ditto
        void selectionRange(LineRange range)
        {
            correctRange(range);
            _selectionRange = range;
            _caretPos = range.end;
            onCaretPosChange(_caretPos);
        }

        /// Get full content size in pixels
        Size fullContentSize() const
        {
            Size sz = _txtline.size;
            // add a little margin for the caret
            sz.w += _spaceWidth;
            return sz;
        }
    }

    /// When true, Tab / Shift+Tab presses are processed internally in widget (e.g. insert tab character) instead of focus change navigation.
    bool wantTabs;
    /// When true, allows copy / cut whole current line if there is no selection
    bool copyWholeLineWhenNoSelection = true;

    /// Emits when the editor content changes
    Signal!(void delegate(dstring)) onChange;
    /// Emits when the editor caret position changes
    Signal!(void delegate(int)) onCaretPosChange;
    /// Emits on Enter key press inside the text field
    Signal!(bool delegate()) onEnterKeyPress; // FIXME: better name

    private
    {
        dstring _str;
        UndoBuffer _undoBuffer;

        bool _selectAllWhenFocusedWithTab = true;
        bool _deselectAllWhenUnfocused = true;
        bool _camelCasePartsAsWords = true;
        bool _replaceMode;
        dchar _passwordChar = 0;

        int _caretPos;
        LineRange _selectionRange;

        float _spaceWidth = 0;
        /// Horizontal offset in pixels
        float _scrollPos = 0;

        Color _selectionColorFocused = Color(0x60A0FF, 0x50);
        Color _selectionColorNormal = Color(0x60A0FF, 0x30);
        Color _caretColor = Color(0x0);
        Color _caretColorReplace = Color(0x8080FF, 0x80);

        TextStyle _txtStyle;
        SimpleText* _placeholder;
        TextSizeTester _minSizeTester;
        TextLine _txtline;

        float _firstGlyphPosX = 0;
    }

    this(dstring initialContent = null)
    {
        allowsFocus = true;
        bindActions();
        handleFontChange();
        handleThemeChange();

        _undoBuffer = new UndoBuffer;
        _minSizeTester.str = "aaaaa"d;
        text = initialContent;
    }

    ~this()
    {
        unbindActions();
        eliminate(_undoBuffer);
    }

    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
        if (focused)
        {
            updateActions();
            startCaretBlinking();
        }
        else
        {
            stopCaretBlinking();
            if (_deselectAllWhenUnfocused)
                _selectionRange = LineRange(_caretPos, _caretPos);
        }
        if (focused && _selectAllWhenFocusedWithTab && receivedFocusFromKeyboard)
            selectAll();
        super.handleFocusChange(focused);
    }

    override void handleThemeChange()
    {
        super.handleThemeChange();
        _caretColor = currentTheme.getColor("edit_caret", Color(0x0));
        _caretColorReplace = currentTheme.getColor("edit_caret_replace", Color(0x8080FF, 0x80));
        _selectionColorFocused = currentTheme.getColor("editor_selection_focused", Color(0x60A0FF, 0x50));
        _selectionColorNormal = currentTheme.getColor("editor_selection_normal", Color(0x60A0FF, 0x30));
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            const tsz = style.tabSize;
            _txtStyle.tabSize = tsz;
            _minSizeTester.style.tabSize = tsz;
            measureVisibleText();
            break;
        case textTransform:
            _txtStyle.transform = style.textTransform;
            _minSizeTester.style.transform = style.textTransform;
            measureVisibleText();
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font font = font();
        _spaceWidth = font.spaceWidth;
        _txtStyle.font = font;
        _minSizeTester.style.font = font;
        if (auto ph = _placeholder)
            ph.style.font = font;
        measureVisibleText();
    }

    override CursorType getCursorType(float x, float y) const
    {
        return CursorType.text;
    }

    //===============================================================

    /// Edit the content
    protected void performOperation(SingleLineEditOperation op)
    {
        LineRange rangeBefore = op.rangeBefore;
        assert(rangeBefore.start <= rangeBefore.end);

        dstring oldcontent = getRangeText(rangeBefore);
        dstring newcontent = op.content;

        LineRange rangeAfter = op.rangeBefore;
        rangeAfter.end = rangeAfter.start + cast(int)newcontent.length;
        assert(rangeAfter.start <= rangeAfter.end);
        op.setNewRange(rangeAfter, oldcontent);
        replaceRange(rangeBefore, newcontent);
        _undoBuffer.push(op);
        handleContentChange(rangeAfter.end);
    }

    final protected void replaceRange(LineRange before, dstring newContent)
    {
        const dstring head = 0 < before.start && before.start <= _str.length ? _str[0 .. before.start] : null;
        const dstring tail = 0 <= before.end && before.end < _str.length ? _str[before.end .. $] : null;

        _str = head ~ newContent ~ tail;
    }

    protected void handleContentChange(int posAfter)
    {
        _caretPos = min(posAfter, lineLength);
        _selectionRange = LineRange(_caretPos, _caretPos);
        measureVisibleText();
        ensureCaretVisible();
        updateActions();
        invalidate();
        onChange(_str);
        onCaretPosChange(_caretPos);
        return;
    }

    final protected dstring applyPasswordChar(dstring s)
    {
        if (!s.length || !_passwordChar)
            return s;
        dchar[] ss = new dchar[s.length];
        ss[] = _passwordChar;
        return cast(dstring)ss;
    }

    //===============================================================
    // Coordinate mapping, caret, and selection

    protected Box textPosToClient(int p) const
    {
        Box b;
        if (p >= _txtline.glyphCount)
        {
            b.x = _txtline.size.w;
        }
        else if (p > 0)
        {
            foreach (ref fg; _txtline.glyphs[0 .. p])
                b.x += fg.width;
        }
        b.x += _firstGlyphPosX - _scrollPos;
        b.w = 1;
        b.h = innerBox.h;
        return b;
    }

    protected int clientToTextPos(Point pt) const
    {
        pt.x += _scrollPos;
        const col = findClosestGlyphInRow(_txtline.glyphs, _firstGlyphPosX, pt.x);
        return col != -1 ? col : _txtline.glyphCount;
    }

    protected void ensureCaretVisible()
    {
        const Box b = textPosToClient(_caretPos);
        const oldpos = _scrollPos;
        if (b.x < _spaceWidth * 4)
        {
            // scroll left
            _scrollPos = max(_scrollPos + b.x - _spaceWidth * 4, 0);
        }
        else if (b.x > innerBox.w - _spaceWidth * 4)
        {
            // scroll right
            _scrollPos += b.x - innerBox.w + _spaceWidth * 4;
        }
        _scrollPos = clamp(fullContentSize.w - innerBox.w, 0, _scrollPos);
        if (oldpos != _scrollPos)
            invalidate();
    }

    private
    {
        bool _enableCaretBlinking = true;
        int _caretBlinkingInterval = 800;
        ulong _caretTimerID;
        bool _caretHidden;
        long _lastBlinkStartTs;
    }

    protected void startCaretBlinking()
    {
        if (!_enableCaretBlinking)
            return;

        if (auto win = window)
        {
            static if (BACKEND_CONSOLE)
            {
                win.caretRect = caretRect;
                win.caretReplace = _replaceMode;
            }
            else
            {
                const long ts = currentTimeMillis;
                if (_caretTimerID)
                {
                    if (_lastBlinkStartTs + _caretBlinkingInterval / 4 > ts)
                        return; // don't update timer too frequently
                    win.cancelTimer(_caretTimerID);
                }
                _caretTimerID = setTimer(_caretBlinkingInterval / 2, {
                    _caretHidden = !_caretHidden;
                    if (!_caretHidden)
                        _lastBlinkStartTs = currentTimeMillis;
                    invalidate();
                    const bool repeat = focused;
                    if (!repeat)
                        _caretTimerID = 0;
                    return repeat;
                });
                _lastBlinkStartTs = ts;
                _caretHidden = false;
                invalidate();
            }
        }
    }
    protected void stopCaretBlinking()
    {
        if (!_enableCaretBlinking)
            return;

        if (auto win = window)
        {
            static if (BACKEND_CONSOLE)
            {
                win.caretRect = Rect.init;
            }
            else
            {
                if (_caretTimerID)
                {
                    win.cancelTimer(_caretTimerID);
                    _caretTimerID = 0;
                    _caretHidden = false;
                }
            }
        }
    }

    /// Returns cursor rectangle
    protected Rect caretRect() const
    {
        assert(0 <= _caretPos && _caretPos <= lineLength);
        Box caret = textPosToClient(_caretPos);
        caret.x = snapToDevicePixels(caret.x);
        if (_replaceMode)
        {
            if (_caretPos < lineLength)
                caret.w = textPosToClient(_caretPos + 1).x - caret.x;
            else
                caret.w = _spaceWidth;
        }
        caret.x += innerBox.x;
        caret.y += innerBox.y;
        return Rect(caret);
    }
    /// Draw caret
    protected void drawCaret(Painter pr)
    {
        if (focused && !_caretHidden)
        {
            const Rect r = caretRect();
            if (r.intersects(Rect(innerBox)))
            {
                if (_replaceMode && BACKEND_GUI)
                    pr.fillRect(r.left, r.top, r.width, r.height, _caretColorReplace);
                else
                    pr.fillRect(r.left, r.top, 1, r.height, _caretColor);
            }
        }
    }

    /// When position is out of content bounds, fix it to nearest valid position
    final void correctPosition(ref int position) const
    {
        position = clamp(position, 0, lineLength);
    }
    /// When range positions is out of content bounds or swapped, fix them to nearest valid position
    final void correctRange(ref LineRange range) const
    {
        range.start = clamp(range.start, 0, lineLength);
        range.end = clamp(range.end, range.start, lineLength);
    }

    /// Change caret position, fixing it to valid bounds, and ensure it is visible
    void jumpTo(int pos, bool select = false)
    {
        correctPosition(pos);
        if (_caretPos != pos)
        {
            const old = _caretPos;
            _caretPos = pos;
            updateSelectionAfterCursorMovement(old, select);
            ensureCaretVisible();
        }
    }

    protected void updateSelectionAfterCursorMovement(int oldCaretPos, bool selecting)
    {
        if (selecting)
        {
            if (oldCaretPos == _selectionRange.start)
            {
                if (_caretPos >= _selectionRange.end)
                {
                    _selectionRange.start = _selectionRange.end;
                    _selectionRange.end = _caretPos;
                }
                else
                {
                    _selectionRange.start = _caretPos;
                }
            }
            else if (oldCaretPos == _selectionRange.end)
            {
                if (_caretPos < _selectionRange.start)
                {
                    _selectionRange.end = _selectionRange.start;
                    _selectionRange.start = _caretPos;
                }
                else
                {
                    _selectionRange.end = _caretPos;
                }
            }
            else
            {
                if (oldCaretPos < _caretPos)
                {
                    // start selection forward
                    _selectionRange.start = oldCaretPos;
                    _selectionRange.end = _caretPos;
                }
                else
                {
                    // start selection backward
                    _selectionRange.start = _caretPos;
                    _selectionRange.end = oldCaretPos;
                }
            }
        }
        else
            _selectionRange = LineRange(_caretPos, _caretPos);

        invalidate();
        updateActions();
        onCaretPosChange(_caretPos);
    }

    protected void selectWordByMouse(float x, float y)
    {
        const int oldCaretPos = _caretPos;
        const int newPos = clientToTextPos(Point(x, y));
        const LineRange r = EditableContent.findWordBoundsInLine(_str, newPos);
        if (!r.empty)
        {
            _selectionRange = r;
            _caretPos = r.end;
            invalidate();
            updateActions();
            onCaretPosChange(_caretPos);
        }
        else
        {
            _caretPos = newPos;
            updateSelectionAfterCursorMovement(oldCaretPos, false);
        }
    }

    protected void selectLineByMouse(float x, float y)
    {
        const int oldCaretPos = _caretPos;
        const int newPos = clientToTextPos(Point(x, y));
        const LineRange r = LineRange(0, lineLength);
        if (!r.empty)
        {
            _selectionRange = r;
            _caretPos = r.end;
            invalidate();
            updateActions();
            onCaretPosChange(_caretPos);
        }
        else
        {
            _caretPos = newPos;
            updateSelectionAfterCursorMovement(oldCaretPos, false);
        }
    }

    protected void updateCaretPositionByMouse(float x, float y, bool selecting)
    {
        const int pos = clientToTextPos(Point(x, y));
        jumpTo(pos, selecting);
    }

    /// Returns current selection text
    dstring getSelectedText() const
    {
        return _selectionRange.start < _selectionRange.end ? _str[_selectionRange.start .. _selectionRange.end] : null;
    }

    /// Returns text from the specified range
    dstring getRangeText(LineRange range) const
    {
        correctRange(range);
        return range.start < range.end ? _str[range.start .. range.end] : null;
    }

    void replaceSelectionText(dstring newText)
    {
        performOperation(new SingleLineEditOperation(_selectionRange, newText));
    }

    protected bool removeSelectionText()
    {
        if (_selectionRange.empty)
            return false;
        // clear selection
        performOperation(new SingleLineEditOperation(_selectionRange, null));
        return true;
    }

    protected bool removeRangeText(LineRange range)
    {
        if (range.empty)
            return false;
        _selectionRange = range;
        _caretPos = _selectionRange.start;
        performOperation(new SingleLineEditOperation(range, null));
        return true;
    }

    /// Change text position `p` to nearest word bound (direction < 0 - back, > 0 - forward)
    protected int moveByWord(int p, int direction, bool camelCasePartsAsWords) const
    {
        import beamui.core.parseutils : isLowerWordChar, isUpperWordChar;

        correctPosition(p);
        const s = _str;
        const len = cast(int)s.length;
        if (direction < 0) // back
        {
            int found;
            for (int i = p - 1; i > 0; i--)
            {
                // check if position i + 1 is after word end
                dchar thischar = i >= 0 && i < len ? s[i] : ' ';
                dchar nextchar = i - 1 >= 0 && i - 1 < len ? s[i - 1] : ' ';
                if (thischar == '\t')
                    thischar = ' ';
                if (nextchar == '\t')
                    nextchar = ' ';
                if (EditableContent.isWordBound(thischar, nextchar) || (camelCasePartsAsWords &&
                        isUpperWordChar(thischar) && isLowerWordChar(nextchar)))
                {
                    found = i;
                    break;
                }
            }
            p = found;
        }
        else if (direction > 0) // forward
        {
            int found = len;
            for (int i = p; i < len; i++)
            {
                // check if position i + 1 is after word end
                dchar thischar = s[i];
                dchar nextchar = i < len - 1 ? s[i + 1] : ' ';
                if (thischar == '\t')
                    thischar = ' ';
                if (nextchar == '\t')
                    nextchar = ' ';
                if (EditableContent.isWordBound(thischar, nextchar) || (camelCasePartsAsWords &&
                        isLowerWordChar(thischar) && isUpperWordChar(nextchar)))
                {
                    found = i + 1;
                    break;
                }
            }
            p = found;
        }
        return p;
    }

    //===============================================================
    // Actions

    protected void bindActions()
    {
        debug (editors)
            Log.d("Editor `", id, "`: bind actions");

        ACTION_LINE_BEGIN.bind(this, { jumpTo(0, false); });
        ACTION_LINE_END.bind(this, { jumpTo(lineLength, false); });
        ACTION_DOCUMENT_BEGIN.bind(this, { jumpTo(0, false); });
        ACTION_DOCUMENT_END.bind(this, { jumpTo(lineLength, false); });
        ACTION_SELECT_LINE_BEGIN.bind(this, { jumpTo(0, true); });
        ACTION_SELECT_LINE_END.bind(this, { jumpTo(lineLength, true); });
        ACTION_SELECT_DOCUMENT_BEGIN.bind(this, { jumpTo(0, true); });
        ACTION_SELECT_DOCUMENT_END.bind(this, { jumpTo(lineLength, true); });

        ACTION_BACKSPACE.bind(this, &delPrevChar);
        ACTION_DELETE.bind(this, &delNextChar);
        ACTION_ED_DEL_PREV_WORD.bind(this, &delPrevWord);
        ACTION_ED_DEL_NEXT_WORD.bind(this, &delNextWord);

        ACTION_SELECT_ALL.bind(this, &selectAll);

        ACTION_UNDO.bind(this, { undo(); });
        ACTION_REDO.bind(this, { redo(); });

        ACTION_CUT.bind(this, &cut);
        ACTION_COPY.bind(this, &copy);
        ACTION_PASTE.bind(this, &paste);

        ACTION_ED_TOGGLE_REPLACE_MODE.bind(this, { replaceMode = !replaceMode; });
    }

    protected void unbindActions()
    {
        bunch(
            ACTION_LINE_BEGIN,
            ACTION_LINE_END,
            ACTION_DOCUMENT_BEGIN,
            ACTION_DOCUMENT_END,
            ACTION_SELECT_LINE_BEGIN,
            ACTION_SELECT_LINE_END,
            ACTION_SELECT_DOCUMENT_BEGIN,
            ACTION_SELECT_DOCUMENT_END,
            ACTION_BACKSPACE,
            ACTION_DELETE,
            ACTION_ED_DEL_PREV_WORD,
            ACTION_ED_DEL_NEXT_WORD,
            ACTION_SELECT_ALL,
            ACTION_UNDO,
            ACTION_REDO,
            ACTION_CUT,
            ACTION_COPY,
            ACTION_PASTE,
            ACTION_ED_TOGGLE_REPLACE_MODE
        ).unbind(this);
    }

    protected void updateActions()
    {
        debug (editors)
            Log.d("Editor `", id, "`: update actions");

        if (!(state & State.focused))
            return;

        ACTION_UNDO.enabled = enabled && hasUndo;
        ACTION_REDO.enabled = enabled && hasRedo;

        ACTION_CUT.enabled = enabled && (copyWholeLineWhenNoSelection || !_selectionRange.empty);
        ACTION_COPY.enabled = copyWholeLineWhenNoSelection || !_selectionRange.empty;
        ACTION_PASTE.enabled = enabled && platform.hasClipboardText();
    }

    protected void delPrevChar()
    {
        if (readOnly)
            return;
        if (removeSelectionText())
            return;
        if (_caretPos > 0)
            removeRangeText(LineRange(_caretPos - 1, _caretPos));
    }
    protected void delNextChar()
    {
        if (readOnly)
            return;
        if (removeSelectionText())
            return;
        if (_caretPos < lineLength)
            removeRangeText(LineRange(_caretPos, _caretPos + 1));
    }
    protected void delPrevWord()
    {
        if (readOnly)
            return;
        if (removeSelectionText())
            return;
        const int newpos = moveByWord(_caretPos, -1, _camelCasePartsAsWords);
        if (newpos < _caretPos)
            removeRangeText(LineRange(newpos, _caretPos));
    }
    protected void delNextWord()
    {
        if (readOnly)
            return;
        if (removeSelectionText())
            return;
        const int newpos = moveByWord(_caretPos, 1, _camelCasePartsAsWords);
        if (newpos > _caretPos)
            removeRangeText(LineRange(_caretPos, newpos));
    }

    void cut()
    {
        if (readOnly)
            return;
        LineRange range = _selectionRange;
        if (range.empty && copyWholeLineWhenNoSelection)
        {
            range = LineRange(0, lineLength);
        }
        if (!range.empty)
        {
            dstring selectionText = getRangeText(range);
            platform.setClipboardText(selectionText);
            performOperation(new SingleLineEditOperation(range, null));
        }
    }

    void copy()
    {
        LineRange range = _selectionRange;
        if (range.empty && copyWholeLineWhenNoSelection)
        {
            range = LineRange(0, lineLength);
        }
        if (!range.empty)
        {
            dstring selectionText = getRangeText(range);
            platform.setClipboardText(selectionText);
        }
    }

    void paste()
    {
        if (readOnly)
            return;
        dstring selectionText = platform.getClipboardText();
        dstring line = replaceEOLsWithSpaces(selectionText);
        performOperation(new SingleLineEditOperation(_selectionRange, line));
    }

    void deselect()
    {
        _selectionRange = LineRange(_caretPos, _caretPos);
        invalidate();
    }

    void selectAll()
    {
        const r = LineRange(0, lineLength);
        if (_selectionRange != r)
        {
            _selectionRange = r;
            invalidate();
            updateActions();
        }
        _caretPos = r.end;
        ensureCaretVisible();
    }

    //===============================================================
    // Undo/redo

    /// Returns true if there is at least one operation in undo buffer
    final @property bool hasUndo() const
    {
        return _undoBuffer.hasUndo;
    }
    /// Returns true if there is at least one operation in redo buffer
    final @property bool hasRedo() const
    {
        return _undoBuffer.hasRedo;
    }

    /// Undoes last change
    final bool undo()
    {
        if (!hasUndo || readOnly)
            return false;

        auto op = cast(SingleLineEditOperation)_undoBuffer.undo();
        replaceRange(op.range, op.contentBefore);
        handleContentChange(op.rangeBefore.end);
        return true;
    }
    /// Redoes last undone change
    final bool redo()
    {
        if (!hasRedo || readOnly)
            return false;

        auto op = cast(SingleLineEditOperation)_undoBuffer.redo();
        replaceRange(op.rangeBefore, op.content);
        handleContentChange(op.range.end);
        return true;
    }

    /// Clear undo/redo history
    final void clearUndo()
    {
        _undoBuffer.clear();
    }

    //===============================================================
    // Events

    override bool handleKeyEvent(KeyEvent event)
    {
        import std.ascii : isAlpha;

        debug (keys)
            Log.d("handleKeyEvent ", event.action, " ", event.key, ", mods ", event.allModifiers);

        if (focused)
            startCaretBlinking();

        const bool noOtherModifiers = !event.alteredBy(KeyMods.alt | KeyMods.meta);
        if (event.action == KeyAction.keyDown && noOtherModifiers)
        {
            const bool shiftPressed = event.alteredBy(KeyMods.shift);
            const bool controlPressed = event.alteredBy(KeyMods.control);
            if (event.key == Key.left)
            {
                int pos = _caretPos;
                if (!controlPressed)
                {
                    // move cursor one char left
                    if (pos > 0)
                        pos--;
                }
                else
                {
                    // move cursor one word left
                    pos = moveByWord(pos, -1, _camelCasePartsAsWords);
                }
                // with selection when Shift is pressed
                jumpTo(pos, shiftPressed);
                return true;
            }
            if (event.key == Key.right)
            {
                int pos = _caretPos;
                if (!controlPressed)
                {
                    // move cursor one char right
                    if (pos < lineLength)
                        pos++;
                }
                else
                {
                    // move cursor one word right
                    pos = moveByWord(pos, 1, _camelCasePartsAsWords);
                }
                // with selection when Shift is pressed
                jumpTo(pos, shiftPressed);
                return true;
            }
            if (onEnterKeyPress.assigned)
            {
                if (event.key == Key.enter && event.noModifiers)
                {
                    if (onEnterKeyPress())
                        return true;
                }
            }
            if (event.key == Key.tab && event.noModifiers)
            {
                if (wantTabs && !readOnly)
                {
                    // insert a tab character
                    performOperation(new SingleLineEditOperation(_selectionRange, "\t"d));
                    return true;
                }
            }
        }

        const bool noCtrlPressed = !event.alteredBy(KeyMods.control);
        if (event.action == KeyAction.text && event.text.length && noCtrlPressed)
        {
            debug (editors)
                Log.d("text entered: ", event.text);
            if (readOnly)
                return true;
            if (!(event.alteredBy(KeyMods.alt) && event.text.length == 1 && isAlpha(event.text[0])))
            { // filter out Alt+A..Z
                if (replaceMode && _selectionRange.empty && lineLength >= _caretPos + event.text.length)
                {
                    // replace next char(s)
                    LineRange range = _selectionRange;
                    range.end += cast(int)event.text.length;
                    performOperation(new SingleLineEditOperation(range, event.text));
                }
                else
                {
                    performOperation(new SingleLineEditOperation(_selectionRange, event.text));
                }
                return true;
            }
        }
        return super.handleKeyEvent(event);
    }

    override bool handleMouseEvent(MouseEvent event)
    {
        debug (mouse)
            Log.d("mouse event: ", id, " ", event.action, "  (", event.x, ",", event.y, ")");

        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            setFocus();
            const x = event.x - innerBox.x;
            const y = event.y - innerBox.y;
            if (event.tripleClick)
            {
                selectLineByMouse(x, y);
            }
            else if (event.doubleClick)
            {
                selectWordByMouse(x, y);
            }
            else
            {
                const bool doSelect = event.alteredBy(KeyMods.shift);
                updateCaretPositionByMouse(x, y, doSelect);
            }
            startCaretBlinking();
            return true;
        }
        if (event.action == MouseAction.move && event.alteredByButton(MouseButton.left))
        {
            const x = event.x - innerBox.x;
            const y = event.y - innerBox.y;
            updateCaretPositionByMouse(x, y, true);
            return true;
        }
        return super.handleMouseEvent(event);
    }

    //===============================================================
    // Measure, layout, drawing

    protected Size measureVisibleText()
    {
        _txtline.str = applyPasswordChar(_str);
        _txtline.measured = false;
        auto tlstyle = TextLayoutStyle(_txtStyle);
        assert(!tlstyle.wrap);
        _txtline.measure(tlstyle);
        return _txtline.size;
    }

    override protected Boundaries computeBoundaries()
    {
        auto bs = super.computeBoundaries();
        const sz = _minSizeTester.getSize();
        bs.min += sz;
        bs.nat += sz;
        return bs;
    }

    override protected void arrangeContent()
    {
        // ensure that scroll position is inside min/max area,
        // move back after window or widget resize
        _scrollPos = clamp(fullContentSize.w - innerBox.w, 0, _scrollPos);
    }

    final override protected void drawContent(Painter pr)
    {
        // apply clipping
        pr.clipIn(BoxI.from(innerBox));

        const b = innerBox;
        drawLineBackground(pr, b, b);

        if (_txtline.glyphCount == 0)
        {
            // draw the placeholder when no text
            if (auto ph = _placeholder)
            {
                const ComputedStyle* st = style;
                ph.style.alignment = st.textAlign;
                ph.style.decoration = TextDecor(st.textDecorLine, ph.style.color, st.textDecorStyle);
                ph.style.overflow = st.textOverflow;
                ph.style.tabSize = st.tabSize;
                ph.style.transform = st.textTransform;
                ph.draw(pr, b.x - _scrollPos, b.y, b.w);
            }
            _firstGlyphPosX = 0;
        }
        else
        {
            const ComputedStyle* st = style;
            _txtStyle.alignment = st.textAlign;
            _txtStyle.color = st.textColor;
            _txtStyle.decoration = st.textDecor;
            _txtStyle.overflow = st.textOverflow;
            _firstGlyphPosX = _txtline.draw(pr, b.x - _scrollPos, b.y, b.w - _spaceWidth, _txtStyle);
        }

        drawCaret(pr);
    }

    /// Override for custom highlighting of the line background
    protected void drawLineBackground(Painter pr, Box lineBox, Box visibleBox)
    {
        if (_selectionRange.empty)
            return;

        // draw selection
        const start = textPosToClient(_selectionRange.start).x;
        const end = textPosToClient(_selectionRange.end).x;
        Box b = lineBox;
        b.x = start + innerBox.x;
        b.w = end - start;
        if (!b.empty)
        {
            const color = focused ? _selectionColorFocused : _selectionColorNormal;
            pr.fillRect(b.x, b.y, b.w, b.h, color);
        }
    }
}
/+
/// Multiline editor and base for complex source editors
class EditBox : ScrollAreaBase, IEditor, ActionOperator
{
    @property
    {
        /// Editor content object
        inout(EditableContent) content() inout { return _content; }
        /// ditto
        void content(EditableContent content)
        {
            if (_content is content)
                return; // not changed
            if (_content)
            {
                // disconnect from the old content
                _content.onContentChange -= &handleContentChange;
                if (_ownContent)
                    destroy(_content);
            }
            _content = content;
            _ownContent = false;
            _content.onContentChange ~= &handleContentChange;
            if (_content.readOnly)
                readOnly = true;
        }

        /// Text in the editor
        override dstring text() const
        {
            return _content.text;
        }
        /// ditto
        override void text(dstring s)
        {
            _content.text = s;
            requestLayout();
        }

        dstring placeholder() const
        {
            return _placeholder ? _placeholder.str : null;
        }
        void placeholder(dstring txt)
        {
            if (!_placeholder)
            {
                if (txt.length > 0)
                {
                    _placeholder = new SimpleText(txt);
                    _placeholder.style.font = font;
                    _placeholder.style.color = NamedColor.gray;
                }
            }
            else
                _placeholder.str = txt;
        }

        dstring minSizeTester() const
        {
            return _minSizeTester.str;
        }
        void minSizeTester(dstring txt)
        {
            _minSizeTester.str = txt;
            requestLayout();
        }

        bool readOnly() const
        {
            return (state & State.readOnly) != 0 || _content.readOnly;
        }
        void readOnly(bool flag)
        {
            if (flag)
                setState(State.readOnly);
            else
                resetState(State.readOnly);
        }

        bool replaceMode() const { return _replaceMode; }
        void replaceMode(bool on)
        {
            _replaceMode = on;
            handleEditorStateChange();
            invalidate();
        }

        /// Tab size (in number of spaces)
        int tabSize() const
        {
            return _content.tabSize;
        }
        /// ditto
        void tabSize(int value)
        {
            const ts = TabSize(value);
            if (ts != _content.tabSize)
            {
                _content.tabSize = ts;
                _txtStyle.tabSize = ts;
                requestLayout();
            }
        }

        /// When true, spaces will be inserted instead of tabs on Tab key
        bool useSpacesForTabs() const
        {
            return _content.useSpacesForTabs;
        }
        /// ditto
        void useSpacesForTabs(bool on)
        {
            _content.useSpacesForTabs = on;
        }

        /// True if smart indents are supported
        bool supportsSmartIndents() const
        {
            return _content.supportsSmartIndents;
        }
        /// True if smart indents are enabled
        bool smartIndents() const
        {
            return _content.smartIndents;
        }
        /// ditto
        void smartIndents(bool enabled)
        {
            _content.smartIndents = enabled;
        }

        /// True if smart indents after paste are enabled
        bool smartIndentsAfterPaste() const
        {
            return _content.smartIndentsAfterPaste;
        }
        /// ditto
        void smartIndentsAfterPaste(bool enabled)
        {
            _content.smartIndentsAfterPaste = enabled;
        }

        int minFontSize() const { return _minFontSize; }
        /// ditto
        void minFontSize(int size)
        {
            _minFontSize = size;
        }

        int maxFontSize() const { return _maxFontSize; }
        /// ditto
        void maxFontSize(int size)
        {
            _maxFontSize = size;
        }

        /// When true shows mark on tab positions in beginning of line
        bool showTabPositionMarks() const { return _showTabPositionMarks; }
        /// ditto
        void showTabPositionMarks(bool show)
        {
            if (show != _showTabPositionMarks)
            {
                _showTabPositionMarks = show;
                invalidate();
            }
        }
        /// When true, show marks for tabs and spaces at beginning and end of line, and tabs inside line
        bool showWhiteSpaceMarks() const { return _showWhiteSpaceMarks; }
        /// ditto
        void showWhiteSpaceMarks(bool show)
        {
            if (_showWhiteSpaceMarks != show)
            {
                _showWhiteSpaceMarks = show;
                invalidate();
            }
        }

        /// Font line height, always > 0
        protected int lineHeight() const { return _lineHeight; }

        protected int firstVisibleLine() const { return _firstVisibleLine; }

        final protected int linesOnScreen() const
        {
            import std.math : ceil;

            return cast(int)ceil(clientBox.h / _lineHeight);
        }

        override Size fullContentSize() const
        {
            return Size(_maxLineWidth + (_extendRightScrollBound ? clientBox.w / 16 : 0),
                        _lineHeight * _content.lineCount);
        }
    }

    /// When true, Tab / Shift+Tab presses are processed internally in widget (e.g. insert tab character) instead of focus change navigation.
    bool wantTabs = true;
    /// When true, allows copy / cut whole current line if there is no selection
    bool copyWholeLineWhenNoSelection = true;

    /// Modified state change listener (e.g. content has been saved, or first time modified after save)
    Signal!(void delegate(bool modified)) onModifiedStateChange;

    /// Signal to emit when editor content is changed
    Signal!(void delegate(EditableContent)) onContentChange;

    /// Signal to emit when editor cursor position or Insert/Replace mode is changed.
    Signal!(void delegate(ref EditorStateInfo editorState)) onStateChange;

    // left pane - can be used to show line numbers, collapse controls, bookmarks, breakpoints, custom icons
    protected float _leftPaneWidth = 0;
    protected bool _extendRightScrollBound = true;

    private
    {
        EditableContent _content;
        /// When `_ownContent` is false, `_content` should not be destroyed in editor destructor
        bool _ownContent = true;

        bool _replaceMode;
        bool _selectAllWhenFocusedWithTab;
        bool _deselectAllWhenUnfocused;
        bool _camelCasePartsAsWords = true;

        int _minFontSize = -1; // disable zooming
        int _maxFontSize = -1; // disable zooming
        bool _showTabPositionMarks;
        bool _showWhiteSpaceMarks;

        Color _selectionColorFocused = Color(0x60A0FF, 0x50);
        Color _selectionColorNormal = Color(0x60A0FF, 0x30);
        Color _caretColor = Color(0x0);
        Color _caretColorReplace = Color(0x8080FF, 0x80);

        Color _searchHighlightColorCurrent = Color(0x8080FF, 0x80);
        Color _searchHighlightColorOther = Color(0x8080FF, 0x40);
        Color _matchingBracketHighlightColor = Color(0xFFE0B0, 0xA0);

        /// When true, call `measureVisibleText` on next layout
        bool _contentChanged = true;

        int _lineHeight = 1;
        float _spaceWidth;

        int _firstVisibleLine;
        float _maxLineWidth = 0; // computed in `measureVisibleText`
        int _lastMeasureLineCount;

        TextStyle _txtStyle;
        SimpleText* _placeholder;
        TextSizeTester _minSizeTester;
        /// Lines, visible in the client area
        TextLine[] _visibleLines;
        /// Local positions of the lines
        Point[] _visibleLinePositions;
        // a stupid pool for markup
        LineMarkup[] _markup;
        uint _markupEngaged;
    }

    this(dstring initialContent = null,
         ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        allowsFocus = true;

        _content = new EditableContent;
        _content.onContentChange ~= &handleContentChange;

        bindActions();
        handleFontChange();
        handleThemeChange();

        text = initialContent;
        _minSizeTester.str = "aaaaa\naaaaa"d;
        setScrollSteps(0, 3);
    }

    ~this()
    {
        unbindActions();
        if (_ownContent)
        {
            destroy(_content);
            _content = null;
        }
    }

    //===============================================================
    // Focus

    override Widget setFocus(FocusReason reason = FocusReason.unspecified)
    {
        Widget res = super.setFocus(reason);
        if (focused)
            handleEditorStateChange();
        return res;
    }

    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
        if (focused)
        {
            updateActions();
            startCaretBlinking();
        }
        else
        {
            stopCaretBlinking();
            cancelHoverTimer();

            if (_deselectAllWhenUnfocused)
                deselectInternal();
        }
        if (focused && _selectAllWhenFocusedWithTab && receivedFocusFromKeyboard)
            selectAll();
        super.handleFocusChange(focused);
    }

    //===============================================================

    override void handleThemeChange()
    {
        super.handleThemeChange();
        _caretColor = currentTheme.getColor("edit_caret", Color(0x0));
        _caretColorReplace = currentTheme.getColor("edit_caret_replace", Color(0x8080FF, 0x80));
        _selectionColorFocused = currentTheme.getColor("editor_selection_focused", Color(0x60A0FF, 0x50));
        _selectionColorNormal = currentTheme.getColor("editor_selection_normal", Color(0x60A0FF, 0x30));

        _searchHighlightColorCurrent = currentTheme.getColor("editor_search_highlight_current", Color(0x8080FF, 0x80));
        _searchHighlightColorOther = currentTheme.getColor("editor_search_highlight_other", Color(0x8080FF, 0x40));
        _matchingBracketHighlightColor = currentTheme.getColor("editor_matching_bracket_highlight", Color(0xFFE0B0, 0xA0));
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case textTransform:
            _txtStyle.transform = style.textTransform;
            _minSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }

        if (ptype == StyleProperty.whiteSpace)
        {
            _txtStyle.wrap = style.wordWrap;
            // horizontal scrollbar should not be visible in word wrap mode
            if (_txtStyle.wrap)
            {
                previousHScrollbarMode = hscrollbarMode;
                previousXScrollPos = scrollPos.x;
                hscrollbarMode = ScrollBarMode.hidden;
                scrollPos.x = 0;
            }
            else
            {
                hscrollbarMode = previousHScrollbarMode;
                scrollPos.x = previousXScrollPos;
            }
        }
    }
    // to hold horizontal scroll position toggling between normal and word wrap mode
    private float previousXScrollPos = 0;
    private ScrollBarMode previousHScrollbarMode;

    override protected void handleFontChange()
    {
        Font font = font();
        _spaceWidth = font.spaceWidth;
        _lineHeight = max(font.height, 1);
        _txtStyle.font = font;
        _minSizeTester.style.font = font;
        if (auto ph = _placeholder)
            ph.style.font = font;
    }

    override protected void updateVScrollBar(ScrollData data)
    {
        data.setRange(_content.lineCount, max(linesOnScreen - 1, 1));
        data.position = _firstVisibleLine;
    }

    override protected void handleHScroll(ScrollEvent event)
    {
        if (scrollPos.x != event.position)
        {
            scrollPos.x = event.position;
            invalidate();
        }
    }

    override protected void handleVScroll(ScrollEvent event)
    {
        const pos = cast(int)event.position;
        if (_firstVisibleLine != pos)
        {
            _firstVisibleLine = pos;
            event.discard();
            measureVisibleText();
            updateScrollBars();
            invalidate();
        }
    }

    /// Updates `onStateChange` with recent position
    protected void handleEditorStateChange()
    {
        if (!onStateChange.assigned)
            return;
        EditorStateInfo info;
        if (visible)
        {
            info.replaceMode = _replaceMode;
            info.line = _caretPos.line + 1;
            info.col = _caretPos.pos + 1;
            if (0 <= _caretPos.line && _caretPos.line < _content.lineCount)
            {
                dstring line = _content.line(_caretPos.line);
                if (_caretPos.pos >= 0 && _caretPos.pos < line.length)
                    info.character = line[_caretPos.pos];
                else
                    info.character = '\n';
            }
        }
        onStateChange(info);
    }

    override bool canShowPopupMenu(float x, float y)
    {
        if (popupMenu is null)
            return false;
        if (popupMenu.openingSubmenu.assigned)
            if (!popupMenu.openingSubmenu(popupMenu))
                return false;
        return true;
    }

    override CursorType getCursorType(float x, float y) const
    {
        return x < box.x + _leftPaneWidth ? CursorType.arrow : CursorType.text;
    }

    //===============================================================
    // Editing

    protected void handleContentChange(EditOperation operation,
            ref TextRange rangeBefore, ref TextRange rangeAfter, Object source)
    {
        debug (editors)
            Log.d("handleContentChange rangeBefore: ", rangeBefore, ", rangeAfter: ", rangeAfter,
                    ", text: ", operation.content);
        _contentChanged = true;
        if (source is this)
        {
            if (operation.action == EditAction.replaceContent)
            {
                // fully replaced, e.g., loaded from file or text property is assigned
                _caretPos = rangeAfter.end;
                deselectInternal();
                measureVisibleText();
                ensureCaretVisible();
                correctCaretPos();
                requestLayout();
                updateActions();
            }
            else if (operation.action == EditAction.saveContent)
            {
                // saved
            }
            else
            {
                // modified
                _caretPos = rangeAfter.end;
                deselectInternal();
                measureVisibleText();
                ensureCaretVisible();
                updateActions();
                processSmartIndent(operation);
            }
        }
        else
        {
            measureVisibleText();
            correctCaretPos();
            requestLayout();
            updateActions();
        }
        invalidate();
        if (onModifiedStateChange.assigned)
        {
            if (_lastReportedModifiedState != _content.modified)
            {
                _lastReportedModifiedState = _content.modified;
                onModifiedStateChange(_content.modified);
                updateActions();
            }
        }
        onContentChange(_content);
        handleEditorStateChange();
        return;
    }
    private bool _lastReportedModifiedState;

    void cut()
    {
        if (readOnly)
            return;
        TextRange range = _selectionRange;
        if (range.empty && copyWholeLineWhenNoSelection)
        {
            range = currentLineRange;
        }
        if (!range.empty)
        {
            dstring selectionText = getRangeText(range);
            platform.setClipboardText(selectionText);
            auto op = new EditOperation(EditAction.replace, range, [""d]);
            _content.performOperation(op, this);
        }
    }

    void copy()
    {
        TextRange range = _selectionRange;
        if (range.empty && copyWholeLineWhenNoSelection)
        {
            range = currentLineRange;
        }
        if (!range.empty)
        {
            dstring selectionText = getRangeText(range);
            platform.setClipboardText(selectionText);
        }
    }

    void paste()
    {
        if (readOnly)
            return;
        dstring selectionText = platform.getClipboardText();
        dstring[] lines = splitDString(selectionText);
        auto op = new EditOperation(EditAction.replace, _selectionRange, lines);
        _content.performOperation(op, this);
    }

    protected void delPrevChar()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionText())
            return;
        if (_caretPos.pos > 0)
        {
            // delete prev char in current line
            auto range = TextRange(_caretPos, _caretPos);
            range.start.pos--;
            removeRangeText(range);
        }
        else if (_caretPos.line > 0)
        {
            // merge with previous line
            auto range = TextRange(_caretPos, _caretPos);
            range.start = _content.lineEnd(range.start.line - 1);
            removeRangeText(range);
        }
    }
    protected void delNextChar()
    {
        const currentLineLength = _content[_caretPos.line].length;
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionText())
            return;
        if (_caretPos.pos < currentLineLength)
        {
            // delete char in current line
            auto range = TextRange(_caretPos, _caretPos);
            range.end.pos++;
            removeRangeText(range);
        }
        else if (_caretPos.line < _content.lineCount - 1)
        {
            // merge with next line
            auto range = TextRange(_caretPos, _caretPos);
            range.end.line++;
            range.end.pos = 0;
            removeRangeText(range);
        }
    }
    protected void delPrevWord()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionText())
            return;
        const TextPosition newpos = _content.moveByWord(_caretPos, -1, _camelCasePartsAsWords);
        if (newpos < _caretPos)
            removeRangeText(TextRange(newpos, _caretPos));
    }
    protected void delNextWord()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionText())
            return;
        const TextPosition newpos = _content.moveByWord(_caretPos, 1, _camelCasePartsAsWords);
        if (newpos > _caretPos)
            removeRangeText(TextRange(_caretPos, newpos));
    }

    protected void insertNewLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            auto op = new EditOperation(EditAction.replace, _selectionRange, [""d, ""d]);
            _content.performOperation(op, this);
        }
    }
    protected void prependNewLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            _caretPos.pos = 0;
            auto op = new EditOperation(EditAction.replace, _selectionRange, [""d, ""d]);
            _content.performOperation(op, this);
        }
    }
    protected void appendNewLine()
    {
        if (!readOnly)
        {
            const TextPosition oldCaretPos = _caretPos;
            correctCaretPos();
            const TextPosition p = _content.lineEnd(_caretPos.line);
            const TextRange r = TextRange(p, p);
            auto op = new EditOperation(EditAction.replace, r, [""d, ""d]);
            _content.performOperation(op, this);
            _caretPos = oldCaretPos;
            handleEditorStateChange();
        }
    }
    protected void deleteLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            auto op = new EditOperation(EditAction.replace, _content.lineRange(_caretPos.line), [""d]);
            _content.performOperation(op, this);
        }
    }

    protected void indent()
    {
        if (readOnly)
            return;
        if (_selectionRange.empty)
        {
            const emptyRange = TextRange(_caretPos, _caretPos);
            if (useSpacesForTabs)
            {
                // insert one or more spaces to
                dstring spaces = spacesForTab(_caretPos.pos);
                auto op = new EditOperation(EditAction.replace, emptyRange, [spaces]);
                _content.performOperation(op, this);
            }
            else
            {
                // just insert tab character
                auto op = new EditOperation(EditAction.replace, emptyRange, ["\t"d]);
                _content.performOperation(op, this);
            }
        }
        else
        {
            if (multipleLinesSelected)
            {
                indentRange(false);
                return;
            }
            // insert a tab
            if (useSpacesForTabs)
            {
                // insert one or more spaces to
                dstring spaces = spacesForTab(_selectionRange.start.pos);
                auto op = new EditOperation(EditAction.replace, _selectionRange, [spaces]);
                _content.performOperation(op, this);
            }
            else
            {
                // just insert tab character
                auto op = new EditOperation(EditAction.replace, _selectionRange, ["\t"d]);
                _content.performOperation(op, this);
            }
        }
    }
    protected void unindent()
    {
        if (readOnly)
            return;
        if (_selectionRange.empty)
        {
            // remove spaces before caret
            const TextRange r = spaceBefore(_caretPos);
            if (!r.empty)
            {
                auto op = new EditOperation(EditAction.replace, r, [""d]);
                _content.performOperation(op, this);
            }
        }
        else
        {
            if (multipleLinesSelected())
            {
                indentRange(true);
                return;
            }
            // remove space before selection
            const TextRange r = spaceBefore(_selectionRange.start);
            if (r.empty)
                return;

            const int nchars = r.end.pos - r.start.pos;
            TextRange saveRange = _selectionRange;
            TextPosition saveCursor = _caretPos;
            auto op = new EditOperation(EditAction.replace, r, [""d]);
            _content.performOperation(op, this);
            if (saveCursor.line == saveRange.start.line)
                saveCursor.pos -= nchars;
            if (saveRange.end.line == saveRange.start.line)
                saveRange.end.pos -= nchars;
            saveRange.start.pos -= nchars;
            _selectionRange = saveRange;
            _caretPos = saveCursor;
            ensureCaretVisible();
        }
    }

    /// Generate string of spaces, to reach next tab position
    final protected dstring spacesForTab(int currentPos)
    {
        const int newPos = (currentPos + tabSize + 1) / tabSize * tabSize;
        return "                "d[0 .. (newPos - currentPos)];
    }

    /// Indent / unindent selected lines
    protected void indentRange(bool back)
    {
        TextRange r = _selectionRange;
        r.start.pos = 0;
        if (r.end.pos > 0)
            r.end = _content.lineBegin(r.end.line + 1);
        if (r.end.line <= r.start.line)
            r = TextRange(_content.lineBegin(_caretPos.line), _content.lineBegin(_caretPos.line + 1));
        int lineCount = r.end.line - r.start.line;
        if (r.end.pos > 0)
            lineCount++;
        dstring[] newContent = new dstring[lineCount + 1];
        bool changed;
        for (int i = 0; i < lineCount; i++)
        {
            dstring srcline = _content.line(r.start.line + i);
            dstring dstline = indentLine(srcline, back, r.start.line + i == _caretPos.line ? &_caretPos : null);
            newContent[i] = dstline;
            if (dstline.length != srcline.length)
                changed = true;
        }
        if (changed)
        {
            const TextRange saveRange = r;
            const TextPosition saveCursor = _caretPos;
            auto op = new EditOperation(EditAction.replace, r, newContent);
            _content.performOperation(op, this);
            _selectionRange = saveRange;
            _caretPos = saveCursor;
            ensureCaretVisible();
        }
    }

    /// Change line indentation
    final protected dstring indentLine(dstring src, bool back, TextPosition* cursorPos)
    {
        int firstNonSpace = -1;
        int x = 0;
        int unindentPos = -1;
        int cursor = cursorPos ? cursorPos.pos : 0;
        for (int i = 0; i < src.length; i++)
        {
            const ch = src[i];
            if (ch == ' ')
            {
                x++;
            }
            else if (ch == '\t')
            {
                x = (x + tabSize + 1) / tabSize * tabSize;
            }
            else
            {
                firstNonSpace = i;
                break;
            }
            if (x <= tabSize)
                unindentPos = i + 1;
        }
        if (firstNonSpace == -1) // only spaces or empty line -- do not change it
            return src;
        if (back)
        {
            // unindent
            if (unindentPos == -1)
                return src; // no change
            if (unindentPos == src.length)
            {
                if (cursorPos)
                    cursorPos.pos = 0;
                return ""d;
            }
            if (cursor >= unindentPos)
                cursorPos.pos -= unindentPos;
            return src[unindentPos .. $].dup;
        }
        else
        {
            // indent
            if (useSpacesForTabs)
            {
                if (cursor > 0)
                    cursorPos.pos += tabSize;
                return spacesForTab(0) ~ src;
            }
            else
            {
                if (cursor > 0)
                    cursorPos.pos++;
                return "\t"d ~ src;
            }
        }
    }

    final protected TextRange spaceBefore(TextPosition pos) const
    {
        auto result = TextRange(pos, pos);
        dstring s = _content[pos.line];
        int x = 0;
        int start = -1;
        for (int i = 0; i < pos.pos; i++)
        {
            const ch = s[i];
            if (ch == ' ')
            {
                if (start == -1 || (x % tabSize) == 0)
                    start = i;
                x++;
            }
            else if (ch == '\t')
            {
                if (start == -1 || (x % tabSize) == 0)
                    start = i;
                x = (x + tabSize + 1) / tabSize * tabSize;
            }
            else
            {
                x++;
                start = -1;
            }
        }
        if (start != -1)
        {
            result.start.pos = start;
        }
        return result;
    }

    protected void processSmartIndent(EditOperation operation)
    {
        if (!supportsSmartIndents)
            return;
        if (!smartIndents && !smartIndentsAfterPaste)
            return;
        _content.syntaxSupport.applySmartIndent(operation, this);
    }

    void toggleLineComment()
    {
        SyntaxSupport syn = _content.syntaxSupport;
        if (!readOnly && syn && syn.supportsToggleLineComment)
            if (syn.canToggleLineComment(_selectionRange))
                syn.toggleLineComment(_selectionRange, this);
    }
    void toggleBlockComment()
    {
        SyntaxSupport syn = _content.syntaxSupport;
        if (!readOnly && syn && syn.supportsToggleBlockComment)
            if (syn.canToggleBlockComment(_selectionRange))
                syn.toggleBlockComment(_selectionRange, this);
    }

    //===============================================================
    // Coordinate mapping, caret, and selection

    private bool _enableScrollAfterText = true;
    protected void ensureCaretVisible(bool center = false)
    {
        _caretPos.line = clamp(_caretPos.line, 0, _content.lineCount - 1);

        // fully visible lines
        const int visibleLines = max(linesOnScreen - 1, 1);
        int maxFirstVisibleLine = _content.lineCount - 1;
        if (!_enableScrollAfterText)
            maxFirstVisibleLine = max(_content.lineCount - visibleLines, 0);

        int line = _firstVisibleLine;

        if (_caretPos.line < _firstVisibleLine)
        {
            line = _caretPos.line;
            if (center)
                line -= visibleLines / 2;
        }
        else if (_txtStyle.wrap && _firstVisibleLine <= maxFirstVisibleLine)
        {
            // for wordwrap mode, move down sooner
            const int offsetLines = -caretHeightOffset / _lineHeight;
            debug (editors)
                Log.d("offsetLines: ", offsetLines);
            if (_caretPos.line >= _firstVisibleLine + visibleLines - offsetLines)
            {
                line = _caretPos.line - visibleLines + 1 + offsetLines;
                if (center)
                    line += visibleLines / 2;
            }
        }
        else if (_caretPos.line >= _firstVisibleLine + visibleLines)
        {
            line = _caretPos.line - visibleLines + 1;
            if (center)
                line += visibleLines / 2;
        }

        line = clamp(line, 0, maxFirstVisibleLine);
        if (_firstVisibleLine != line)
        {
            _firstVisibleLine = line;
            measureVisibleText();
            invalidate();
        }

        const Box b = textPosToClient(_caretPos);
        const oldpos = scrollPos.x;
        if (b.x < 0)
        {
            // scroll left
            scrollPos.x = max(scrollPos.x + b.x - clientBox.w / 4, 0);
        }
        else if (b.x >= clientBox.w - 10)
        {
            // scroll right
            if (!_txtStyle.wrap)
                scrollPos.x += (b.x - clientBox.w) + clientBox.w / 4;
            else
                scrollPos.x = 0;
        }
        if (oldpos != scrollPos.x)
            invalidate();
        updateScrollBars();
        handleEditorStateChange();
    }

    protected Box textPosToClient(TextPosition pos) const
    {   // similar to the method in Paragraph
        const first = _firstVisibleLine;
        const lines = _visibleLines;
        const positions = _visibleLinePositions;

        if (lines.length == 0 || pos.line < first || first + cast(int)lines.length <= pos.line)
            return Box.init;

        Box b;
        b.w = 1;
        b.h = _lineHeight;
        b.pos = positions[pos.line - first];

        const TextLine* line = &lines[pos.line - first];
        const glyphs = line.glyphs;
        if (line.wrapped)
        {
            foreach (ref span; line.wrapSpans)
            {
                if (pos.pos <= span.end)
                {
                    b.x = span.offset;
                    foreach (i; span.start .. pos.pos)
                        b.x += glyphs[i].width;
                    break;
                }
                b.y += span.height;
            }
        }
        else
        {
            if (pos.pos < line.glyphCount)
            {
                foreach (i; 0 .. pos.pos)
                    b.x += glyphs[i].width;
            }
            else
                b.x += line.size.w;
        }
        b.x -= scrollPos.x;
        return b;
    }

    protected TextPosition clientToTextPos(Point pt) const
    {   // similar to the method in Paragraph
        const first = _firstVisibleLine;
        const lines = _visibleLines;
        const positions = _visibleLinePositions;

        if (lines.length == 0)
            return TextPosition(0, 0);

        // find the line first
        const(TextLine)* line = &lines[$ - 1]; // default as if it is lower
        int index = first + cast(int)lines.length - 1;
        if (pt.y < positions[0].y) // upper
        {
            line = &lines[0];
            index = first;
        }
        else if (pt.y < positions[$ - 1].y + line.height) // inside
        {
            foreach (i, ref ln; lines)
            {
                const p = positions[i];
                if (p.y <= pt.y && pt.y < p.y + ln.height)
                {
                    line = &ln;
                    index = first + cast(int)i;
                    break;
                }
            }
        }
        // then find the column
        pt.x += scrollPos.x;
        const p = positions[index - first];
        const glyphs = line.glyphs;
        if (line.wrapped)
        {
            float y = p.y;
            foreach (ref span; line.wrapSpans)
            {
                if (y <= pt.y && pt.y < y + span.height)
                {
                    int col = findClosestGlyphInRow(glyphs[span.start .. span.end], span.offset, pt.x);
                    if (col != -1)
                        col += span.start;
                    else
                        col = span.end;
                    return TextPosition(index, col);
                }
                y += span.height;
            }
        }
        else
        {
            const col = findClosestGlyphInRow(glyphs, p.x, pt.x);
            if (col != -1)
                return TextPosition(index, col);
        }
        return TextPosition(index, line.glyphCount);
    }

    private
    {
        TextPosition _caretPos;
        TextRange _selectionRange;

        bool _enableCaretBlinking = true;
        int _caretBlinkingInterval = 800;
        ulong _caretTimerID;
        bool _caretHidden;
        long _lastBlinkStartTs;
    }

    @property
    {
        /// Returns caret position
        TextPosition caretPos() const { return _caretPos; }

        /// Current selection range
        TextRange selectionRange() const { return _selectionRange; }
        /// ditto
        void selectionRange(TextRange range)
        {
            if (range.empty)
                return;
            _selectionRange = range;
            _caretPos = range.end;
            handleEditorStateChange();
        }

        /// Returns range for the line with caret
        TextRange currentLineRange() const
        {
            return _content.lineRange(_caretPos.line);
        }

        bool enableCaretBlinking() const { return _enableCaretBlinking; }
        void enableCaretBlinking(bool flag)
        {
            stopCaretBlinking();
            _enableCaretBlinking = flag;
        }

        /// Returns true if one or more lines selected fully
        final protected bool multipleLinesSelected() const
        {
            return _selectionRange.end.line > _selectionRange.start.line;
        }
    }

    /// Change caret position, fixing it to valid bounds
    void setCaretPos(int line, int column, bool select = false)
    {
        auto pos = TextPosition(line, column);
        _content.correctPosition(pos);
        if (_caretPos != pos)
        {
            const old = _caretPos;
            _caretPos = pos;
            updateSelectionAfterCursorMovement(old, select);
        }
    }
    /// Change caret position, fixing it to valid bounds, and ensure it is visible
    void jumpTo(int line, int column, bool select = false, bool center = false)
    {
        auto pos = TextPosition(line, column);
        _content.correctPosition(pos);
        if (_caretPos != pos)
        {
            const old = _caretPos;
            _caretPos = pos;
            updateSelectionAfterCursorMovement(old, select);
            ensureCaretVisible(center);
        }
    }

    protected void startCaretBlinking()
    {
        if (!_enableCaretBlinking)
            return;

        if (auto win = window)
        {
            static if (BACKEND_CONSOLE)
            {
                win.caretRect = caretRect;
                win.caretReplace = _replaceMode;
            }
            else
            {
                const long ts = currentTimeMillis;
                if (_caretTimerID)
                {
                    if (_lastBlinkStartTs + _caretBlinkingInterval / 4 > ts)
                        return; // don't update timer too frequently
                    win.cancelTimer(_caretTimerID);
                }
                _caretTimerID = setTimer(_caretBlinkingInterval / 2, {
                    _caretHidden = !_caretHidden;
                    if (!_caretHidden)
                        _lastBlinkStartTs = currentTimeMillis;
                    invalidate();
                    const bool repeat = focused;
                    if (!repeat)
                        _caretTimerID = 0;
                    return repeat;
                });
                _lastBlinkStartTs = ts;
                _caretHidden = false;
                invalidate();
            }
        }
    }

    protected void stopCaretBlinking()
    {
        if (!_enableCaretBlinking)
            return;

        if (auto win = window)
        {
            static if (BACKEND_CONSOLE)
            {
                win.caretRect = Rect.init;
            }
            else
            {
                if (_caretTimerID)
                {
                    win.cancelTimer(_caretTimerID);
                    _caretTimerID = 0;
                    _caretHidden = false;
                }
            }
        }
    }

    /// In word wrap mode, set by caretRect so ensureCaretVisible will know when to scroll
    private int caretHeightOffset;

    /// Returns cursor rectangle
    protected Rect caretRect() const
    {
        Box caret = textPosToClient(_caretPos);
        caret.x = snapToDevicePixels(caret.x);
        if (_replaceMode)
        {
            caret.w = _spaceWidth;
            if (_caretPos.pos < _content.lineLength(_caretPos.line))
            {
                const nextPos = TextPosition(_caretPos.line, _caretPos.pos + 1);
                const nextBox = textPosToClient(nextPos);
                // if it is not a line break
                if (caret.x < nextBox.x)
                    caret.w = nextBox.x - caret.x;
            }
        }
        caret.x += clientBox.x;
        caret.y += clientBox.y;
        return Rect(caret);
    }

    /// Draw caret
    protected void drawCaret(Painter pr)
    {
        if (focused && !_caretHidden)
        {
            const Rect r = caretRect();
            if (r.intersects(Rect(clientBox)))
            {
                if (_replaceMode && BACKEND_GUI)
                    pr.fillRect(r.left, r.top, r.width, r.height, _caretColorReplace);
                else
                    pr.fillRect(r.left, r.top, 1, r.height, _caretColor);
            }
        }
    }

    /// When cursor position or selection is out of content bounds, fix it to nearest valid position
    protected void correctCaretPos()
    {
        const oldCaretPos = _caretPos;
        _content.correctPosition(_caretPos);
        _content.correctPosition(_selectionRange.start);
        _content.correctPosition(_selectionRange.end);
        if (_selectionRange.empty)
            deselectInternal();
        if (oldCaretPos != _caretPos)
            handleEditorStateChange();
    }

    protected void updateSelectionAfterCursorMovement(TextPosition oldCaretPos, bool selecting)
    {
        if (selecting)
        {
            if (oldCaretPos == _selectionRange.start)
            {
                if (_caretPos >= _selectionRange.end)
                {
                    _selectionRange.start = _selectionRange.end;
                    _selectionRange.end = _caretPos;
                }
                else
                {
                    _selectionRange.start = _caretPos;
                }
            }
            else if (oldCaretPos == _selectionRange.end)
            {
                if (_caretPos < _selectionRange.start)
                {
                    _selectionRange.end = _selectionRange.start;
                    _selectionRange.start = _caretPos;
                }
                else
                {
                    _selectionRange.end = _caretPos;
                }
            }
            else
            {
                if (oldCaretPos < _caretPos)
                {
                    // start selection forward
                    _selectionRange.start = oldCaretPos;
                    _selectionRange.end = _caretPos;
                }
                else
                {
                    // start selection backward
                    _selectionRange.start = _caretPos;
                    _selectionRange.end = oldCaretPos;
                }
            }
        }
        else
            deselectInternal();
        invalidate();
        updateActions();
        handleEditorStateChange();
    }

    protected void moveCursorByLine(bool up, bool select)
    {
        int line = _caretPos.line;
        if (up)
            line--;
        else
            line++;
        jumpTo(line, _caretPos.pos, select);
    }

    protected void selectWordByMouse(float x, float y)
    {
        const TextPosition oldCaretPos = _caretPos;
        const TextPosition newPos = clientToTextPos(Point(x, y));
        const TextRange r = _content.wordBounds(newPos);
        if (r.start < r.end)
        {
            _selectionRange = r;
            _caretPos = r.end;
            invalidate();
            updateActions();
        }
        else
        {
            _caretPos = newPos;
            updateSelectionAfterCursorMovement(oldCaretPos, false);
        }
        handleEditorStateChange();
    }

    protected void selectLineByMouse(float x, float y)
    {
        const TextPosition oldCaretPos = _caretPos;
        const TextPosition newPos = clientToTextPos(Point(x, y));
        const TextRange r = _content.lineRange(newPos.line);
        if (r.start < r.end)
        {
            _selectionRange = r;
            _caretPos = r.end;
            invalidate();
            updateActions();
        }
        else
        {
            _caretPos = newPos;
            updateSelectionAfterCursorMovement(oldCaretPos, false);
        }
        handleEditorStateChange();
    }

    protected void updateCaretPositionByMouse(float x, float y, bool selecting)
    {
        const TextPosition pos = clientToTextPos(Point(x, y));
        setCaretPos(pos.line, pos.pos, selecting);
    }

    /// Returns current selection text (joined with LF when span over multiple lines)
    dstring getSelectedText() const
    {
        return getRangeText(_selectionRange);
    }

    /// Returns text for specified range (joined with LF when span over multiple lines)
    dstring getRangeText(TextRange range) const
    {
        return concatDStrings(_content.rangeText(range));
    }

    void replaceSelectionText(dstring newText)
    {
        auto op = new EditOperation(EditAction.replace, _selectionRange, [newText]);
        _content.performOperation(op, this);
    }

    protected bool removeSelectionText()
    {
        if (_selectionRange.empty)
            return false;
        // clear selection
        auto op = new EditOperation(EditAction.replace, _selectionRange, [""d]);
        _content.performOperation(op, this);
        return true;
    }

    protected bool removeRangeText(TextRange range)
    {
        if (range.empty)
            return false;
        _selectionRange = range;
        _caretPos = _selectionRange.start;
        auto op = new EditOperation(EditAction.replace, range, [""d]);
        _content.performOperation(op, this);
        return true;
    }

    void deselect()
    {
        _selectionRange = TextRange(_caretPos, _caretPos);
        invalidate();
    }

    private void deselectInternal()
    {
        _selectionRange = TextRange(_caretPos, _caretPos);
    }

    //===============================================================
    // Actions

    protected void bindActions()
    {
        debug (editors)
            Log.d("Editor `", id, "`: bind actions");

        ACTION_LINE_BEGIN.bind(this, { jumpToLineBegin(false); });
        ACTION_LINE_END.bind(this, { jumpToLineEnd(false); });
        ACTION_DOCUMENT_BEGIN.bind(this, { jumpToDocumentBegin(false); });
        ACTION_DOCUMENT_END.bind(this, { jumpToDocumentEnd(false); });
        ACTION_SELECT_LINE_BEGIN.bind(this, { jumpToLineBegin(true); });
        ACTION_SELECT_LINE_END.bind(this, { jumpToLineEnd(true); });
        ACTION_SELECT_DOCUMENT_BEGIN.bind(this, { jumpToDocumentBegin(true); });
        ACTION_SELECT_DOCUMENT_END.bind(this, { jumpToDocumentEnd(true); });

        ACTION_BACKSPACE.bind(this, &delPrevChar);
        ACTION_DELETE.bind(this, &delNextChar);
        ACTION_ED_DEL_PREV_WORD.bind(this, &delPrevWord);
        ACTION_ED_DEL_NEXT_WORD.bind(this, &delNextWord);

        ACTION_SELECT_ALL.bind(this, &selectAll);

        ACTION_UNDO.bind(this, { _content.undo(this); });
        ACTION_REDO.bind(this, { _content.redo(this); });

        ACTION_CUT.bind(this, &cut);
        ACTION_COPY.bind(this, &copy);
        ACTION_PASTE.bind(this, &paste);

        ACTION_ED_TOGGLE_REPLACE_MODE.bind(this, { replaceMode = !replaceMode; });

        ACTION_PAGE_UP.bind(this, { jumpByPageUp(false); });
        ACTION_PAGE_DOWN.bind(this, { jumpByPageDown(false); });
        ACTION_PAGE_BEGIN.bind(this, { jumpToPageBegin(false); });
        ACTION_PAGE_END.bind(this, { jumpToPageEnd(false); });
        ACTION_SELECT_PAGE_UP.bind(this, { jumpByPageUp(true); });
        ACTION_SELECT_PAGE_DOWN.bind(this, { jumpByPageDown(true); });
        ACTION_SELECT_PAGE_BEGIN.bind(this, { jumpToPageBegin(true); });
        ACTION_SELECT_PAGE_END.bind(this, { jumpToPageEnd(true); });

        ACTION_ZOOM_IN.bind(this, { zoom(true); });
        ACTION_ZOOM_OUT.bind(this, { zoom(false); });

        ACTION_ED_INDENT.bind(this, &indent);
        ACTION_ED_UNINDENT.bind(this, &unindent);

        ACTION_ENTER.bind(this, &insertNewLine);
        ACTION_ED_PREPEND_NEW_LINE.bind(this, &prependNewLine);
        ACTION_ED_APPEND_NEW_LINE.bind(this, &appendNewLine);
        ACTION_ED_DELETE_LINE.bind(this, &deleteLine);

        ACTION_ED_TOGGLE_BOOKMARK.bind(this, {
            _content.lineIcons.toggleBookmark(_caretPos.line);
        });
        ACTION_ED_GOTO_NEXT_BOOKMARK.bind(this, {
            LineIcon mark = _content.lineIcons.findNext(LineIconType.bookmark,
                    _selectionRange.end.line, 1);
            if (mark)
                jumpTo(mark.line, 0);
        });
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK.bind(this, {
            LineIcon mark = _content.lineIcons.findNext(LineIconType.bookmark,
                    _selectionRange.end.line, -1);
            if (mark)
                jumpTo(mark.line, 0);
        });

        ACTION_ED_TOGGLE_LINE_COMMENT.bind(this, &toggleLineComment);
        ACTION_ED_TOGGLE_BLOCK_COMMENT.bind(this, &toggleBlockComment);

        ACTION_ED_FIND.bind(this, &openFindPanel);
        ACTION_ED_FIND_NEXT.bind(this, { findNext(false); });
        ACTION_ED_FIND_PREV.bind(this, { findNext(true); });
        ACTION_ED_REPLACE.bind(this, &openReplacePanel);
    }

    protected void unbindActions()
    {
        bunch(
            ACTION_LINE_BEGIN,
            ACTION_LINE_END,
            ACTION_DOCUMENT_BEGIN,
            ACTION_DOCUMENT_END,
            ACTION_SELECT_LINE_BEGIN,
            ACTION_SELECT_LINE_END,
            ACTION_SELECT_DOCUMENT_BEGIN,
            ACTION_SELECT_DOCUMENT_END,
            ACTION_BACKSPACE,
            ACTION_DELETE,
            ACTION_ED_DEL_PREV_WORD,
            ACTION_ED_DEL_NEXT_WORD,
            ACTION_SELECT_ALL,
            ACTION_UNDO,
            ACTION_REDO,
            ACTION_CUT,
            ACTION_COPY,
            ACTION_PASTE,
            ACTION_ED_TOGGLE_REPLACE_MODE
        ).unbind(this);
        bunch(
            ACTION_PAGE_UP,
            ACTION_PAGE_DOWN,
            ACTION_PAGE_BEGIN,
            ACTION_PAGE_END,
            ACTION_SELECT_PAGE_UP,
            ACTION_SELECT_PAGE_DOWN,
            ACTION_SELECT_PAGE_BEGIN,
            ACTION_SELECT_PAGE_END,
            ACTION_ZOOM_IN,
            ACTION_ZOOM_OUT,
            ACTION_ED_INDENT,
            ACTION_ED_UNINDENT,
            ACTION_ENTER,
            ACTION_ED_TOGGLE_BOOKMARK,
            ACTION_ED_GOTO_NEXT_BOOKMARK,
            ACTION_ED_GOTO_PREVIOUS_BOOKMARK,
            ACTION_ED_TOGGLE_LINE_COMMENT,
            ACTION_ED_TOGGLE_BLOCK_COMMENT,
            ACTION_ED_PREPEND_NEW_LINE,
            ACTION_ED_APPEND_NEW_LINE,
            ACTION_ED_DELETE_LINE,
            ACTION_ED_FIND,
            ACTION_ED_FIND_NEXT,
            ACTION_ED_FIND_PREV,
            ACTION_ED_REPLACE
        ).unbind(this);
    }

    protected void updateActions()
    {
        debug (editors)
            Log.d("Editor `", id, "`: update actions");

        if (!(state & State.focused))
            return;

        ACTION_UNDO.enabled = enabled && _content.hasUndo;
        ACTION_REDO.enabled = enabled && _content.hasRedo;

        ACTION_CUT.enabled = enabled && (copyWholeLineWhenNoSelection || !_selectionRange.empty);
        ACTION_COPY.enabled = copyWholeLineWhenNoSelection || !_selectionRange.empty;
        ACTION_PASTE.enabled = enabled && platform.hasClipboardText();

        ACTION_ED_INDENT.enabled = enabled && wantTabs;
        ACTION_ED_UNINDENT.enabled = enabled && wantTabs;

        ACTION_ED_GOTO_NEXT_BOOKMARK.enabled = _content.lineIcons.hasBookmarks;
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK.enabled = _content.lineIcons.hasBookmarks;

        SyntaxSupport syn = _content.syntaxSupport;
        {
            Action a = ACTION_ED_TOGGLE_LINE_COMMENT;
            a.visible = syn && syn.supportsToggleLineComment;
            if (a.visible)
                a.enabled = enabled && syn.canToggleLineComment(_selectionRange);
        }
        {
            Action a = ACTION_ED_TOGGLE_BLOCK_COMMENT;
            a.visible = syn && syn.supportsToggleBlockComment;
            if (a.visible)
                a.enabled = enabled && syn.canToggleBlockComment(_selectionRange);
        }

        ACTION_ED_REPLACE.enabled = !readOnly;
    }

    void jumpToLineBegin(bool select)
    {
        const space = _content.getLineWhiteSpace(_caretPos.line);
        int pos = _caretPos.pos;
        if (pos > 0)
        {
            if (pos > space.firstNonSpaceIndex && space.firstNonSpaceIndex > 0)
                pos = space.firstNonSpaceIndex;
            else
                pos = 0;
        }
        else // caret is on the left border
        {
            if (space.firstNonSpaceIndex > 0)
                pos = space.firstNonSpaceIndex;
        }
        jumpTo(_caretPos.line, pos, select);
    }

    void jumpToLineEnd(bool select)
    {
        const currentLineLen = _content.lineLength(_caretPos.line);
        const pos = max(_caretPos.pos, currentLineLen);
        jumpTo(_caretPos.line, pos, select);
    }

    void jumpToDocumentBegin(bool select)
    {
        jumpTo(0, 0, select);
    }

    void jumpToDocumentEnd(bool select)
    {
        const end = _content.end;
        jumpTo(end.line, end.pos, select);
    }

    void jumpToPageBegin(bool select)
    {
        jumpTo(_firstVisibleLine, _caretPos.pos, select);
    }

    void jumpToPageEnd(bool select)
    {
        const line = min(_firstVisibleLine + linesOnScreen - 2, _content.lineCount - 1);
        jumpTo(line, _caretPos.pos, select);
    }

    void jumpByPageUp(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        ensureCaretVisible();
        const int newpos = _firstVisibleLine - linesOnScreen;
        if (newpos < 0)
        {
            _firstVisibleLine = 0;
            _caretPos.line = 0;
        }
        else
        {
            const int delta = _firstVisibleLine - newpos;
            _firstVisibleLine = newpos;
            _caretPos.line -= delta;
        }
        correctCaretPos();
        measureVisibleText();
        updateScrollBars();
        updateSelectionAfterCursorMovement(oldCaretPos, select);
    }

    void jumpByPageDown(bool select)
    {
        TextPosition oldCaretPos = _caretPos;
        ensureCaretVisible();
        const int newpos = _firstVisibleLine + linesOnScreen;
        if (newpos >= _content.lineCount)
        {
            _caretPos.line = _content.lineCount - 1;
        }
        else
        {
            const int delta = newpos - _firstVisibleLine;
            _firstVisibleLine = newpos;
            _caretPos.line += delta;
        }
        correctCaretPos();
        measureVisibleText();
        updateScrollBars();
        updateSelectionAfterCursorMovement(oldCaretPos, select);
    }

    void selectAll()
    {
        _selectionRange.start.line = 0;
        _selectionRange.start.pos = 0;
        _selectionRange.end = _content.lineEnd(_content.lineCount - 1);
        _caretPos = _selectionRange.end;
        ensureCaretVisible();
        invalidate();
        updateActions();
    }

    /// Zoom in when `zoomIn` is true and out vice versa
    void zoom(bool zoomIn)
    {
        const int dir = zoomIn ? 1 : -1;
        if (_minFontSize < _maxFontSize && _minFontSize > 0 && _maxFontSize > 0)
        {
            const int currentFontSize = style.fontSize;
            const int increment = currentFontSize >= 30 ? 2 : 1;
            int fs = currentFontSize + increment * dir;
            if (fs > 30)
                fs &= 0xFFFE;
            if (currentFontSize != fs && _minFontSize <= fs && fs <= _maxFontSize)
            {
                debug (editors)
                    Log.i("Font size in editor ", id, " zoomed to ", fs);
                style.fontSize = cast(ushort)fs;
                measureVisibleText();
                updateScrollBars();
            }
        }
    }

    //===============================================================
    // Events

    override bool handleKeyEvent(KeyEvent event)
    {
        import std.ascii : isAlpha;

        debug (keys)
            Log.d("handleKeyEvent ", event.action, " ", event.key, ", mods ", event.allModifiers);
        if (focused)
            startCaretBlinking();
        cancelHoverTimer();

        const bool noOtherModifiers = !event.alteredBy(KeyMods.alt | KeyMods.meta);
        if (event.action == KeyAction.keyDown && noOtherModifiers)
        {
            const bool shiftPressed = event.alteredBy(KeyMods.shift);
            const bool controlPressed = event.alteredBy(KeyMods.control);
            if (event.key == Key.left)
            {
                correctCaretPos();
                TextPosition pos = _caretPos;
                if (!controlPressed)
                {
                    // move cursor one char left
                    if (pos.pos > 0)
                    {
                        pos.pos--;
                    }
                    else if (pos.line > 0)
                    {
                        pos.line--;
                        pos.pos = int.max;
                    }
                }
                else
                {
                    // move cursor one word left
                    pos = _content.moveByWord(pos, -1, _camelCasePartsAsWords);
                }
                // with selection when Shift is pressed
                jumpTo(pos.line, pos.pos, shiftPressed);
                return true;
            }
            if (event.key == Key.right)
            {
                correctCaretPos();
                TextPosition pos = _caretPos;
                if (!controlPressed)
                {
                    // move cursor one char right
                    const currentLineLength = _content[pos.line].length;
                    if (pos.pos < currentLineLength)
                    {
                        pos.pos++;
                    }
                    else if (pos.line < _content.lineCount - 1)
                    {
                        pos.pos = 0;
                        pos.line++;
                    }
                }
                else
                {
                    // move cursor one word right
                    pos = _content.moveByWord(pos, 1, _camelCasePartsAsWords);
                }
                // with selection when Shift is pressed
                jumpTo(pos.line, pos.pos, shiftPressed);
                return true;
            }
            if (event.key == Key.up)
            {
                if (!controlPressed)
                    // move cursor one line up (with selection when Shift pressed)
                    moveCursorByLine(true, shiftPressed);
                else
                    scrollUp();
                return true;
            }
            if (event.key == Key.down)
            {
                if (!controlPressed)
                    // move cursor one line down (with selection when Shift pressed)
                    moveCursorByLine(false, shiftPressed);
                else
                    scrollDown();
                return true;
            }
        }

        const bool noCtrlPressed = !event.alteredBy(KeyMods.control);
        if (event.action == KeyAction.text && event.text.length && noCtrlPressed)
        {
            debug (editors)
                Log.d("text entered: ", event.text);
            if (readOnly)
                return true;
            if (!(event.alteredBy(KeyMods.alt) && event.text.length == 1 && isAlpha(event.text[0])))
            { // filter out Alt+A..Z
                if (replaceMode && _selectionRange.empty &&
                        _content[_caretPos.line].length >= _caretPos.pos + event.text.length)
                {
                    // replace next char(s)
                    TextRange range = _selectionRange;
                    range.end.pos += cast(int)event.text.length;
                    auto op = new EditOperation(EditAction.replace, range, [event.text]);
                    _content.performOperation(op, this);
                }
                else
                {
                    auto op = new EditOperation(EditAction.replace, _selectionRange, [event.text]);
                    _content.performOperation(op, this);
                }
                return true;
            }
        }
        return super.handleKeyEvent(event);
    }

    private TextPosition _hoverTextPosition;
    private Point _hoverMousePosition;
    private ulong _hoverTimer;
    private long _hoverTimeoutMillis = 800;

    /// Override to handle mouse hover timeout in text
    protected void handleHoverTimeout(Point pt, TextPosition pos)
    {
        // override to do something useful on hover timeout
    }

    protected void handleHover(Point pos)
    {
        if (_hoverMousePosition == pos)
            return;
        debug (mouse)
            Log.d("handleHover ", pos);
        cancelHoverTimer();
        const p = pos - clientBox.pos;
        _hoverMousePosition = pos;
        _hoverTextPosition = clientToTextPos(p);
        const Box reversePos = textPosToClient(_hoverTextPosition);
        if (p.x < reversePos.x + 10)
        {
            _hoverTimer = setTimer(_hoverTimeoutMillis, delegate() {
                handleHoverTimeout(_hoverMousePosition, _hoverTextPosition);
                _hoverTimer = 0;
                return false;
            });
        }
    }

    protected void cancelHoverTimer()
    {
        if (_hoverTimer)
        {
            cancelTimer(_hoverTimer);
            _hoverTimer = 0;
        }
    }

    override bool handleMouseEvent(MouseEvent event)
    {
        debug (mouse)
            Log.d("mouse event: ", id, " ", event.action, "  (", event.x, ",", event.y, ")");
        // support onClick
        const bool insideLeftPane = event.x < clientBox.x && event.x >= clientBox.x - _leftPaneWidth;
        if (event.action == MouseAction.buttonDown && insideLeftPane)
        {
            setFocus();
            cancelHoverTimer();
            if (handleLeftPaneMouseClick(event))
                return true;
        }
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            setFocus();
            cancelHoverTimer();
            if (event.tripleClick)
            {
                selectLineByMouse(event.x - clientBox.x, event.y - clientBox.y);
            }
            else if (event.doubleClick)
            {
                selectWordByMouse(event.x - clientBox.x, event.y - clientBox.y);
            }
            else
            {
                const bool doSelect = event.alteredBy(KeyMods.shift);
                updateCaretPositionByMouse(event.x - clientBox.x, event.y - clientBox.y, doSelect);

                if (event.keyMods == KeyMods.control)
                    handleControlClick();
            }
            startCaretBlinking();
            invalidate();
            return true;
        }
        if (event.action == MouseAction.move && event.alteredByButton(MouseButton.left))
        {
            updateCaretPositionByMouse(event.x - clientBox.x, event.y - clientBox.y, true);
            return true;
        }
        if (event.action == MouseAction.move && event.noMouseMods)
        {
            // hover
            if (focused && !insideLeftPane)
            {
                handleHover(event.pos);
            }
            else
            {
                cancelHoverTimer();
            }
            return true;
        }
        if (event.action == MouseAction.buttonUp && event.button == MouseButton.left)
        {
            cancelHoverTimer();
            return true;
        }
        if (event.action == MouseAction.focusOut || event.action == MouseAction.cancel)
        {
            cancelHoverTimer();
            return true;
        }
        if (event.action == MouseAction.focusIn)
        {
            cancelHoverTimer();
            return true;
        }
        cancelHoverTimer();
        return super.handleMouseEvent(event);
    }

    protected bool handleLeftPaneMouseClick(MouseEvent event)
    {
        return false;
    }

    /// Handle Ctrl + Left mouse click on text
    protected void handleControlClick()
    {
        // override to do something useful on Ctrl + Left mouse click in text
    }

    override bool handleWheelEvent(WheelEvent event)
    {
        cancelHoverTimer();

        const mods = event.keyMods;
        if (event.deltaY > 0)
        {
            if (mods == KeyMods.shift)
                scrollRight();
            else if (mods == KeyMods.control)
                zoom(false);
            else
                scrollDown();
            return true;
        }
        if (event.deltaY < 0)
        {
            if (mods == KeyMods.shift)
                scrollLeft();
            else if (mods == KeyMods.control)
                zoom(true);
            else
                scrollUp();
            return true;
        }

        if (event.deltaX < 0)
        {
            scrollLeft();
            return true;
        }
        if (event.deltaX > 0)
        {
            scrollRight();
            return true;
        }
        if (event.deltaZ < 0)
        {
            zoom(false);
            return true;
        }
        if (event.deltaZ > 0)
        {
            zoom(true);
            return true;
        }

        return super.handleWheelEvent(event);
    }

    //===============================================================
    // Search

    private dstring _textToHighlight;
    private TextSearchOptions _textToHighlightOptions;

    /// Text pattern to highlight - e.g. for search
    @property dstring textToHighlight() const { return _textToHighlight; }
    /// Set text to highlight -- e.g. for search
    void setTextToHighlight(dstring pattern, TextSearchOptions textToHighlightOptions)
    {
        _textToHighlight = pattern;
        _textToHighlightOptions = textToHighlightOptions;
        invalidate();
    }

    /// Find next occurence of text pattern in content, returns true if found
    bool findNextPattern(ref TextPosition pos, dstring pattern, TextSearchOptions searchOptions, int direction)
    {
        const TextRange[] all = findAll(pattern, searchOptions);
        if (!all.length)
            return false;
        int currentIndex = -1;
        int nearestIndex = cast(int)all.length;
        for (int i = 0; i < all.length; i++)
        {
            if (all[i].isInsideOrNext(pos))
            {
                currentIndex = i;
                break;
            }
        }
        for (int i = 0; i < all.length; i++)
        {
            if (pos < all[i].start)
            {
                nearestIndex = i;
                break;
            }
            if (pos > all[i].end)
            {
                nearestIndex = i + 1;
            }
        }
        if (currentIndex >= 0)
        {
            if (all.length < 2 && direction != 0)
                return false;
            currentIndex += direction;
            if (currentIndex < 0)
                currentIndex = cast(int)all.length - 1;
            else if (currentIndex >= all.length)
                currentIndex = 0;
            pos = all[currentIndex].start;
            return true;
        }
        if (direction < 0)
            nearestIndex--;
        if (nearestIndex < 0)
            nearestIndex = cast(int)all.length - 1;
        else if (nearestIndex >= all.length)
            nearestIndex = 0;
        pos = all[nearestIndex].start;
        return true;
    }

    /// Find all occurences of text pattern in content; options is a bitset of `TextSearchOptions`
    TextRange[] findAll(dstring pattern, TextSearchOptions options) const
    {
        if (!pattern.length)
            return null;

        import std.string : indexOf, CaseSensitive;
        import std.typecons : Yes, No;

        const bool caseSensitive = (options & TextSearchOptions.caseSensitive) != 0;
        const bool wholeWords = (options & TextSearchOptions.wholeWords) != 0;
        const bool selectionOnly = (options & TextSearchOptions.selectionOnly) != 0;
        TextRange[] res;
        foreach (i; 0 .. _content.lineCount)
        {
            const dstring lineText = _content.line(i);
            if (lineText.length < pattern.length)
                continue;
            ptrdiff_t start;
            while (true)
            {
                const pos = lineText[start .. $].indexOf(pattern, caseSensitive ?
                        Yes.caseSensitive : No.caseSensitive);
                if (pos < 0)
                    break;
                // found text to highlight
                start += pos;
                if (!wholeWords || isWholeWord(lineText, start, start + pattern.length))
                {
                    const p = TextPosition(i, cast(int)start);
                    res ~= TextRange(p, p.offset(cast(int)pattern.length));
                }
                start += _textToHighlight.length;
            }
        }
        return res;
    }

    private FindPanel _findPanel;

    protected void openFindPanel()
    {
        createFindPanel(false, false);
        _findPanel.replaceMode = false;
        _findPanel.activate();
    }

    protected void openReplacePanel()
    {
        createFindPanel(false, true);
        _findPanel.replaceMode = true;
        _findPanel.activate();
    }

    protected void findNext(bool backward)
    {
        createFindPanel(false, false);
        _findPanel.findNext(backward);
        // don't change replace mode
    }

    /// Create find panel; returns true if panel was not yet visible
    protected bool createFindPanel(bool selectionOnly, bool replaceMode)
    {
        bool res;
        const dstring txt = selectionText(true);
        if (!_findPanel)
        {
            _findPanel = new FindPanel(this, selectionOnly, replaceMode, txt);
            addChild(_findPanel);
            res = true;
        }
        else
        {
            if (_findPanel.visibility != Visibility.visible)
            {
                _findPanel.visibility = Visibility.visible;
                if (txt.length)
                    _findPanel.searchText = txt;
                res = true;
            }
        }
        return res;
    }

    protected void closeFindPanel(bool hideOnly = true)
    {
        if (_findPanel)
        {
            setFocus();
            if (hideOnly)
            {
                _findPanel.visibility = Visibility.gone;
            }
            else
            {
                removeChild(_findPanel);
                destroy(_findPanel);
                _findPanel = null;
            }
        }
    }

    private dstring selectionText(bool singleLineOnly = false) const
    {
        const TextRange range = _selectionRange;
        if (range.empty)
            return null;

        dstring res = getRangeText(range);
        if (singleLineOnly)
        {
            foreach (i, ch; res)
            {
                if (ch == '\n')
                {
                    res = res[0 .. i];
                    break;
                }
            }
        }
        return res;
    }

    //===============================================================
    // Markup

    private TextAttr[][ubyte] _tokenHighlight;

    /// Set highlight options for particular token category
    void setTokenHighlight(TokenCategory category, TextAttr attribute)
    {
        if (auto p = category in _tokenHighlight)
            *p ~= attribute;
        else
            _tokenHighlight[category] = [attribute];
    }
    /// Clear highlight options for all tokens
    void clearTokenHighlight()
    {
        _tokenHighlight.clear();
    }

    /// Construct a custom text markup to highlight the line
    protected LineMarkup* handleCustomLineMarkup(int line, dstring txt)
    {
        import std.algorithm : group;

        if (_tokenHighlight.length == 0)
            return null; // no highlight attributes set

        TokenPropString tokenProps = _content.lineTokenProps(line);
        if (tokenProps.length == 0)
            return null;

        bool hasNonzeroTokens;
        foreach (t; tokenProps)
        {
            if (t)
            {
                hasNonzeroTokens = true;
                break;
            }
        }
        if (!hasNonzeroTokens)
            return null; // all characters are of unknown token type (uncategorized)

        const index = _markupEngaged;
        _markupEngaged++;
        if (_markup.length < _markupEngaged)
            _markup.length = _markupEngaged;

        LineMarkup* result = &_markup[index];
        result.clear();

        uint i;
        foreach (item; group(tokenProps))
        {
            const tok = item[0];
            TextAttr[] attrs;
            if (auto p = tok in _tokenHighlight)
                attrs = *p;
            else if (auto p = (tok & TOKEN_CATEGORY_MASK) in _tokenHighlight)
                attrs = *p;

            const len = cast(uint)item[1];
            if (attrs.length > 0)
            {
                MarkupSpan span = result.span(i, len);
                foreach (ref a; attrs)
                    span.set(a);
            }
            i += len;
        }
        assert(i == tokenProps.length);
        result.prepare(); // FIXME: should be automatic
        return result;
    }

    //===============================================================
    // Measure, layout, drawing

    protected void highlightTextPattern(Painter pr, int lineIndex, Box lineBox, Box visibleBox)
    {
        dstring pattern = _textToHighlight;
        TextSearchOptions options = _textToHighlightOptions;
        if (!pattern.length)
        {
            // support highlighting selection text - if whole word is selected
            if (_selectionRange.empty || !_selectionRange.singleLine)
                return;
            if (_selectionRange.start.line >= _content.lineCount)
                return;
            const dstring selLine = _content.line(_selectionRange.start.line);
            const int start = _selectionRange.start.pos;
            const int end = _selectionRange.end.pos;
            if (start >= selLine.length)
                return;
            pattern = selLine[start .. end];
            if (!isWordChar(pattern[0]) || !isWordChar(pattern[$ - 1]))
                return;
            if (!isWholeWord(selLine, start, end))
                return;
            // whole word is selected - enable highlight for it
            options = TextSearchOptions.caseSensitive | TextSearchOptions.wholeWords;
        }
        if (!pattern.length)
            return;
        dstring lineText = _content.line(lineIndex);
        if (lineText.length < pattern.length)
            return;

        import std.string : indexOf, CaseSensitive;
        import std.typecons : Yes, No;

        const bool caseSensitive = (options & TextSearchOptions.caseSensitive) != 0;
        const bool wholeWords = (options & TextSearchOptions.wholeWords) != 0;
        const bool selectionOnly = (options & TextSearchOptions.selectionOnly) != 0;
        ptrdiff_t start;
        while (true)
        {
            const pos = lineText[start .. $].indexOf(pattern, caseSensitive ? Yes.caseSensitive : No.caseSensitive);
            if (pos < 0)
                break;
            // found text to highlight
            start += pos;
            if (!wholeWords || isWholeWord(lineText, start, start + pattern.length))
            {
                const a = cast(int)start;
                const b = a + cast(int)pattern.length;
                const caretInside = _caretPos.line == lineIndex && a <= _caretPos.pos && _caretPos.pos <= b;
                const color = caretInside ? _searchHighlightColorCurrent : _searchHighlightColorOther;
                highlightLineRange(pr, lineBox, color, lineIndex, a, b);
            }
            start += pattern.length;
        }
    }

    static bool isValidWordBound(dchar innerChar, dchar outerChar)
    {
        return !isWordChar(innerChar) || !isWordChar(outerChar);
    }
    /// Returns true if selected range of string is whole word
    static bool isWholeWord(dstring lineText, size_t start, size_t end)
    {
        if (start >= lineText.length || start >= end)
            return false;
        if (start > 0 && !isValidWordBound(lineText[start], lineText[start - 1]))
            return false;
        if (end > 0 && end < lineText.length && !isValidWordBound(lineText[end - 1], lineText[end]))
            return false;
        return true;
    }

    /// Override to add custom items on left panel
    protected void updateLeftPaneWidth()
    {
    }

    override protected Boundaries computeBoundaries()
    {
        auto bs = super.computeBoundaries();
        measureVisibleText();
        _minSizeTester.style.tabSize = _content.tabSize;
        const sz = _minSizeTester.getSize() + Size(_leftPaneWidth, 0);
        bs.min += sz;
        bs.nat += sz;
        return bs;
    }

    override protected void adjustClientBox(ref Box clb)
    {
        updateLeftPaneWidth();
        clb.x += _leftPaneWidth;
        clb.w -= _leftPaneWidth;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        if (geom != box)
            _contentChanged = true;

        super.layout(geom);
    }

    override protected void arrangeContent()
    {
        super.arrangeContent();

        if (_findPanel && _findPanel.visibility != Visibility.gone)
        {
            _findPanel.measure();
            const sz = _findPanel.natSize;
            const cb = clientBox;
            _findPanel.layout(Box(cb.x, cb.y + cb.h - sz.h, cb.w, sz.h));
        }

        if (_contentChanged)
        {
            measureVisibleText();
            _contentChanged = false;
        }

        if (auto ph = _placeholder)
            ph.wrap(clientBox.w);
    }

    protected Size measureVisibleText()
    {
        int numVisibleLines = linesOnScreen;
        if (_firstVisibleLine >= _content.lineCount)
        {
            _firstVisibleLine = max(_content.lineCount - numVisibleLines + 1, 0);
            _caretPos.line = _content.lineCount - 1;
            _caretPos.pos = 0;
        }
        numVisibleLines = max(numVisibleLines, 1);
        if (_firstVisibleLine + numVisibleLines > _content.lineCount)
            numVisibleLines = max(_content.lineCount - _firstVisibleLine, 1);

        _visibleLines.length = numVisibleLines;
        _visibleLinePositions.length = numVisibleLines;
        _markupEngaged = 0;

        Size sz;
        foreach (i, ref line; _visibleLines)
        {
            line.str = _content[_firstVisibleLine + cast(int)i];
            line.markup = handleCustomLineMarkup(_firstVisibleLine + cast(int)i, line.str);
            line.measured = false;
            auto tlstyle = TextLayoutStyle(_txtStyle);
            line.measure(tlstyle);
            // width - max from visible lines
            sz.w = max(sz.w, line.size.w);
            // wrap now, because we may need this information without drawing
            if (_txtStyle.wrap)
                line.wrap(clientBox.w);
        }
        sz.h = _lineHeight * _content.lineCount; // height - for all lines
        // we use max width of the viewed lines as content width
        // in some situations, we reset it to shrink the horizontal scrolling range
        if (_content.lineCount < _lastMeasureLineCount / 3)
            _maxLineWidth = sz.w;
        else if (sz.w * 10 < _maxLineWidth && clientBox.w < sz.w)
            _maxLineWidth = sz.w;
        else
            _maxLineWidth = max(_maxLineWidth, sz.w);
        _lastMeasureLineCount = _content.lineCount;
        return sz;
    }

    protected void highlightLineRange(Painter pr, Box lineBox, Color color,
        int line, int start, int end, bool extend = false)
    {
        const TextLine* ln = &_visibleLines[line - _firstVisibleLine];
        if (ln.wrapped)
        {
            float y = lineBox.y;
            foreach (ref span; ln.wrapSpans)
            {
                if (span.end <= start)
                {
                    y += span.height;
                    continue;
                }
                if (end <= span.start)
                    break;

                const i1 = max(span.start, start);
                const i2 = min(span.end, end);
                const ext = extend && i2 == ln.glyphCount;
                highlightLineRangeImpl(pr, y, span.height, color, line, i1, i2, ext);
                y += span.height;
            }
        }
        else
            highlightLineRangeImpl(pr, lineBox.y, lineBox.h, color, line, start, end, extend);
    }

    private void highlightLineRangeImpl(Painter pr, float y, float h, Color color,
        int line, int start, int end, bool extend)
    {
        const Box a = textPosToClient(TextPosition(line, start));
        const Box b = textPosToClient(TextPosition(line, end));
        const w = b.x - a.x + (extend ? _spaceWidth : 0);
        pr.fillRect(clientBox.x + a.x, y, w, h, color);
    }

    /// Override to custom highlight of line background
    protected void drawLineBackground(Painter pr, int lineIndex, Box lineBox, Box visibleBox)
    {
        // highlight odd lines
        //if ((lineIndex & 1))
        //    buf.fillRect(visibleRect, 0xF4808080);

        const sel = _selectionRange;
        if (!sel.empty && sel.start.line <= lineIndex && lineIndex <= sel.end.line)
        {
            // line is inside selection
            int start;
            int end = int.max;
            bool extend;
            if (lineIndex == sel.start.line)
            {
                start = sel.start.pos;
            }
            if (lineIndex == sel.end.line)
            {
                end = sel.end.pos;
            }
            else
                extend = true;
            // draw selection rect for the line
            const c = focused ? _selectionColorFocused : _selectionColorNormal;
            highlightLineRange(pr, lineBox, c, lineIndex, start, end, extend);
        }

        highlightTextPattern(pr, lineIndex, lineBox, visibleBox);

        const br = _matchingBraces;
        const brcolor = _matchingBracketHighlightColor;
        if (br.start.line == lineIndex)
        {
            highlightLineRange(pr, lineBox, brcolor, lineIndex, br.start.pos, br.start.pos + 1);
        }
        if (br.end.line == lineIndex)
        {
            highlightLineRange(pr, lineBox, brcolor, lineIndex, br.end.pos, br.end.pos + 1);
        }

        // frame around current line
        if (focused && lineIndex == _caretPos.line && sel.singleLine && sel.start.line == _caretPos.line)
        {
            const c = Color(0x808080, 0x60);
            pr.fillRect(visibleBox.x, visibleBox.y, visibleBox.w, 1, c);
            pr.fillRect(visibleBox.x, visibleBox.y + visibleBox.h - 1, visibleBox.w, 1, c);
        }
    }

    override protected void drawExtendedArea(Painter pr)
    {
        if (_leftPaneWidth <= 0)
            return;

        const int lineCount = _content.lineCount;
        const cb = clientBox;
        Box b = Box(cb.x - _leftPaneWidth, cb.y, _leftPaneWidth, 0);
        int i = _firstVisibleLine;
        while (b.y < cb.y + cb.h)
        {
            if (i < lineCount)
            {
                b.h = _visibleLines[i - _firstVisibleLine].height;
                drawLeftPane(pr, Rect(b), i);
            }
            else
            {
                b.h = _lineHeight;
                drawLeftPane(pr, Rect(b), -1);
            }
            b.y += b.h;
            i++;
        }
    }

    protected void drawLeftPane(Painter pr, Rect rc, int line)
    {
        // override to draw a custom left pane
    }

    private TextRange _matchingBraces;

    /// Find max tab mark column position for line
    protected int findMaxTabMarkColumn(int lineIndex) const
    {
        if (lineIndex < 0 || lineIndex >= _content.lineCount)
            return -1;
        int maxSpace = -1;
        auto space = _content.getLineWhiteSpace(lineIndex);
        maxSpace = space.firstNonSpaceColumn;
        if (maxSpace >= 0)
            return maxSpace;
        foreach_reverse (i; 0 .. lineIndex)
        {
            space = _content.getLineWhiteSpace(i);
            if (!space.empty)
            {
                maxSpace = space.firstNonSpaceColumn;
                break;
            }
        }
        foreach (i; lineIndex + 1 .. _content.lineCount)
        {
            space = _content.getLineWhiteSpace(i);
            if (!space.empty)
            {
                if (maxSpace < 0 || maxSpace < space.firstNonSpaceColumn)
                    maxSpace = space.firstNonSpaceColumn;
                break;
            }
        }
        return maxSpace;
    }

    protected void drawTabPositionMarks(Painter pr, int lineIndex, Box lineBox)
    {
        const int maxCol = findMaxTabMarkColumn(lineIndex);
        if (maxCol > 0)
        {
            const spaceWidth = _spaceWidth;
            lineBox.h = _visibleLines[lineIndex - _firstVisibleLine].wrapSpans[0].height;
            Rect rc = lineBox;
            Color color = style.textColor;
            color.addAlpha(0x40);
            for (int i = 0; i < maxCol; i += tabSize)
            {
                drawDottedLineV(pr, cast(int)(rc.left + i * spaceWidth), cast(int)rc.top, cast(int)rc.bottom, color);
            }
        }
    }

    protected void drawWhiteSpaceMarks(Painter pr, int lineIndex, Box lineBox, Box visibleBox)
    {
        const TextLine* line = &_visibleLines[lineIndex - _firstVisibleLine];
        const txt = line.str;
        int firstNonSpace = -1;
        int lastNonSpace = -1;
        bool hasTabs;
        for (int i = 0; i < txt.length; i++)
        {
            if (txt[i] == '\t')
            {
                hasTabs = true;
            }
            else if (txt[i] != ' ')
            {
                if (firstNonSpace == -1)
                    firstNonSpace = i;
                lastNonSpace = i + 1;
            }
        }
        if (txt.length > 0 && firstNonSpace == -1)
            firstNonSpace = cast(int)txt.length;
        if (firstNonSpace <= 0 && txt.length <= lastNonSpace && !hasTabs)
            return;

        Color color = style.textColor;
        color.addAlpha(0x40);

        const oldAA = pr.antialias;
        pr.antialias = false;

        const FragmentGlyph[] glyphs = line.glyphs;
        const visibleRect = Rect(visibleBox);
        Box b = lineBox;
        foreach (ref span; line.wrapSpans)
        {
            const i1 = span.start;
            const i2 = span.end;
            b.x = lineBox.x + span.offset;
            foreach (i; i1 .. i2)
            {
                const fg = &glyphs[i];
                const ch = txt[i];
                const bool outsideText = i < firstNonSpace || lastNonSpace <= i;
                if ((ch == ' ' && outsideText) || ch == '\t')
                {
                    b.w = fg.width;
                    b.h = fg.height;
                    if (Rect(b).intersects(visibleRect))
                    {
                        if (ch == ' ')
                            drawSpaceMark(pr, b, color);
                        else if (ch == '\t')
                            drawTabMark(pr, b, color);
                    }
                }
                b.x += fg.width;
            }
            b.y += span.height;
        }
        pr.antialias = oldAA;
    }

    private void drawSpaceMark(Painter pr, Box g, Color color)
    {
        import std.math : round;
        // round because anti-aliasing is turned off
        const float sz = max(g.h / 7, 1);
        const b = Box(round(g.x + g.w / 2 - sz / 2), round(g.y + g.h / 2 - sz / 2), sz, sz);
        pr.fillRect(b.x, b.y, b.w, b.h, color);
    }

    private void drawTabMark(Painter pr, Box g, Color color)
    {
        import std.math : round;

        static Path path;
        path.reset();

        const float sz = round(g.h / 5);
        path.moveTo(round(g.x + g.w - sz * 2 - 1), round(g.y + g.h / 2 - sz))
            .lineBy( sz, sz)
            .lineBy(-sz, sz)
            .moveBy(sz, 0)
            .lineBy( sz, -sz)
            .lineBy(-sz, -sz)
        ;
        const brush = Brush.fromSolid(color);
        pr.stroke(path, brush, Pen(g.h / 16));
    }

    override protected void drawClient(Painter pr)
    {
        // update matched braces
        if (!_content.findMatchedBraces(_caretPos, _matchingBraces))
        {
            _matchingBraces.start.line = -1;
            _matchingBraces.end.line = -1;
        }

        const b = clientBox;

        if (auto ph = _placeholder)
        {
            // draw the placeholder when no text
            const ls = _content.lines;
            if (ls.length == 0 || (ls.length == 1 && ls[0].length == 0))
            {
                const ComputedStyle* st = style;
                ph.style.alignment = st.textAlign;
                ph.style.decoration = TextDecor(st.textDecorLine, ph.style.color, st.textDecorStyle);
                ph.style.overflow = st.textOverflow;
                ph.style.tabSize = _content.tabSize;
                ph.style.transform = st.textTransform;
                ph.draw(pr, b.x - scrollPos.x, b.y, b.w);
            }
        }

        const ComputedStyle* st = style;
        _txtStyle.alignment = st.textAlign;
        _txtStyle.color = st.textColor;
        _txtStyle.decoration = st.textDecor;
        _txtStyle.overflow = st.textOverflow;

        const px = b.x - scrollPos.x;
        float y = 0;
        foreach (i, ref line; _visibleLines)
        {
            const py = b.y + y;
            const h = line.height;
            const lineIndex = _firstVisibleLine + cast(int)i;
            const lineBox = Box(px, py, line.size.w, h);
            const visibleBox = Box(b.x, lineBox.y, b.w, lineBox.h);
            drawLineBackground(pr, lineIndex, lineBox, visibleBox);
            if (_showTabPositionMarks)
                drawTabPositionMarks(pr, lineIndex, lineBox);
            if (_showWhiteSpaceMarks)
                drawWhiteSpaceMarks(pr, lineIndex, lineBox, visibleBox);

            const x = line.draw(pr, px, py, b.w, _txtStyle);
            _visibleLinePositions[i] = Point(x, y);
            y += h;
        }

        drawCaret(pr);

        _findPanel.maybe.draw(pr);
    }
}

/// Read only edit box for displaying logs with lines append operation
class LogWidget : EditBox
{
    @property
    {
        /// Max lines to show (when appended more than max lines, older lines will be truncated), 0 means no limit
        int maxLines() const { return _maxLines; }
        /// ditto
        void maxLines(int n)
        {
            _maxLines = n;
        }

        /// When true, automatically scrolls down when new lines are appended (usually being reset by scrollbar interaction)
        bool scrollLock() const { return _scrollLock; }
        /// ditto
        void scrollLock(bool flag)
        {
            _scrollLock = flag;
        }
    }

    private int _maxLines;
    private bool _scrollLock;

    this()
    {
        _scrollLock = true;
        _enableScrollAfterText = false;
        readOnly = true;
        // allow font zoom with Ctrl + MouseWheel
        minFontSize = 8;
        maxFontSize = 36;
        handleThemeChange();
    }

    /// Append lines to the end of text
    void appendText(dstring text)
    {
        if (text.length == 0)
            return;
        {
            dstring[] lines = splitDString(text);
            TextRange range;
            range.start = range.end = _content.end;
            auto op = new EditOperation(EditAction.replace, range, lines);
            _content.performOperation(op, this);
        }
        if (_maxLines > 0 && _content.lineCount > _maxLines)
        {
            TextRange range;
            range.end.line = _content.lineCount - _maxLines;
            auto op = new EditOperation(EditAction.replace, range, [""d]);
            _content.performOperation(op, this);
        }
        updateScrollBars();
        if (_scrollLock)
        {
            _caretPos = lastLineBegin();
            ensureCaretVisible();
        }
    }

    TextPosition lastLineBegin() const
    {
        TextPosition res;
        if (_content.lineCount == 0)
            return res;
        if (_content.lineLength(_content.lineCount - 1) == 0 && _content.lineCount > 1)
            res.line = _content.lineCount - 2;
        else
            res.line = _content.lineCount - 1;
        return res;
    }

    override protected void arrangeContent()
    {
        super.arrangeContent();
        if (_scrollLock)
        {
            measureVisibleText();
            _caretPos = lastLineBegin();
            ensureCaretVisible();
        }
    }
}

class FindPanel : Panel
{
    @property
    {
        /// Returns true if panel is working in replace mode
        bool replaceMode() const { return _replaceMode; }
        /// ditto
        void replaceMode(bool newMode)
        {
            if (newMode != _replaceMode)
            {
                _replaceMode = newMode;
                _edReplace.visibility = newMode ? Visibility.visible : Visibility.gone;
                _replaceBtns.visibility = newMode ? Visibility.visible : Visibility.gone;
                toggleAttribute("find-only");
            }
        }

        dstring searchText() const
        {
            return _edFind.text;
        }
        /// ditto
        void searchText(dstring newText)
        {
            _edFind.text = newText;
        }
    }

    private
    {
        EditBox _editor;
        bool _replaceMode;

        EditLine _edFind;
        EditLine _edReplace;
        Panel _replaceBtns;
        Button _cbCaseSensitive;
        Button _cbWholeWords;
        CheckBox _cbSelection;
        Button _btnFindNext;
        Button _btnFindPrev;
    }

    this(EditBox editor, bool selectionOnly, bool replace, dstring initialText = ""d)
    {
        _editor = editor;
        _replaceMode = replace;

        _edFind = new EditLine(initialText);
        _edReplace = new EditLine(initialText);
        auto findBtns = new Panel(null, "find-buttons");
            _btnFindNext = new Button("Find next");
            _btnFindPrev = new Button("Find previous");
            _cbCaseSensitive = new Button(null, "find_case_sensitive");
            _cbWholeWords = new Button(null, "find_whole_words");
            _cbSelection = new CheckBox("Sel");
        _replaceBtns = new Panel(null, "replace-buttons");
            auto btnReplace = new Button("Replace");
            auto btnReplaceAndFind = new Button("Replace and find");
            auto btnReplaceAll = new Button("Replace all");
        auto closeBtn = new Button(null, "close");

        add(_edFind, _edReplace, findBtns, _replaceBtns, closeBtn);
        findBtns.add(_btnFindNext, _btnFindPrev, _cbCaseSensitive, _cbWholeWords, _cbSelection);
        _replaceBtns.add(btnReplace, btnReplaceAndFind, btnReplaceAll);

        with (_cbCaseSensitive) {
            allowsToggle = true;
            tooltipText = "Case sensitive";
        }
        with (_cbWholeWords) {
            allowsToggle = true;
            tooltipText = "Whole words";
        }
        _edFind.setAttribute("find");
        _edReplace.setAttribute("replace");
        closeBtn.setAttribute("close");

        if (!replace)
        {
            setAttribute("find-only");
            _edReplace.visibility = Visibility.gone;
            _replaceBtns.visibility = Visibility.gone;
        }

        _edFind.onEnterKeyPress ~= { findNext(_backDirection); return true; };
        _edFind.onChange ~= &handleFindTextChange;

        _btnFindNext.onClick ~= { findNext(false); };
        _btnFindPrev.onClick ~= { findNext(true); };

        _cbCaseSensitive.onToggle ~= &handleCaseSensitiveToggle;
        _cbWholeWords.onToggle ~= &handleCaseSensitiveToggle;
        _cbSelection.onToggle ~= &handleCaseSensitiveToggle;

        btnReplace.onClick ~= { replaceOne(); };
        btnReplaceAndFind.onClick ~= {
            replaceOne();
            findNext(_backDirection);
        };
        btnReplaceAll.onClick ~= { replaceAll(); };

        closeBtn.onClick ~= &close;

        focusGroup = true;

        setDirection(false);
        updateHighlight();
    }

    void activate()
    {
        _edFind.setFocus();
        _edFind.jumpTo(_edFind.lineLength);
    }

    void close()
    {
        _editor.setTextToHighlight(null, TextSearchOptions.none);
        _editor.closeFindPanel();
    }

    override bool handleKeyEvent(KeyEvent event)
    {
        if (event.key == Key.tab)
            return super.handleKeyEvent(event);
        if (event.action == KeyAction.keyDown && event.key == Key.escape)
        {
            close();
            return true;
        }
        return false;
    }

    private bool _backDirection;
    void setDirection(bool back)
    {
        _backDirection = back;
        if (back)
        {
            _btnFindNext.resetState(State.default_);
            _btnFindPrev.setState(State.default_);
        }
        else
        {
            _btnFindNext.setState(State.default_);
            _btnFindPrev.resetState(State.default_);
        }
    }

    TextSearchOptions makeSearchOptions() const
    {
        TextSearchOptions res;
        if (_cbCaseSensitive.checked)
            res |= TextSearchOptions.caseSensitive;
        if (_cbWholeWords.checked)
            res |= TextSearchOptions.wholeWords;
        if (_cbSelection.checked)
            res |= TextSearchOptions.selectionOnly;
        return res;
    }

    bool findNext(bool back)
    {
        setDirection(back);
        const currentText = _edFind.text;
        debug (editors)
            Log.d("findNext text=", currentText, " back=", back);
        if (!currentText.length)
            return false;
        _editor.setTextToHighlight(currentText, makeSearchOptions());
        TextPosition pos = _editor.caretPos;
        const bool res = _editor.findNextPattern(pos, currentText, makeSearchOptions(), back ? -1 : 1);
        if (res)
        {
            _editor.selectionRange = TextRange(pos, pos.offset(cast(int)currentText.length));
            _editor.ensureCaretVisible();
        }
        return res;
    }

    bool replaceOne()
    {
        const currentText = _edFind.text;
        const newText = _edReplace.text;
        debug (editors)
            Log.d("replaceOne text=", currentText, " back=", _backDirection, " newText=", newText);
        if (!currentText.length)
            return false;
        _editor.setTextToHighlight(currentText, makeSearchOptions());
        TextPosition pos = _editor.caretPos;
        const bool res = _editor.findNextPattern(pos, currentText, makeSearchOptions(), 0);
        if (res)
        {
            _editor.selectionRange = TextRange(pos, pos.offset(cast(int)currentText.length));
            _editor.replaceSelectionText(newText);
            _editor.selectionRange = TextRange(pos, pos.offset(cast(int)newText.length));
            _editor.ensureCaretVisible();
        }
        return res;
    }

    int replaceAll()
    {
        int count;
        for (int i;; i++)
        {
            debug (editors)
                Log.d("replaceAll - calling replaceOne, iteration ", i);
            if (!replaceOne())
                break;
            count++;
            TextPosition initialPosition = _editor.caretPos;
            debug (editors)
                Log.d("replaceAll - position is ", initialPosition);
            if (!findNext(_backDirection))
                break;
            TextPosition newPosition = _editor.caretPos;
            debug (editors)
                Log.d("replaceAll - next position is ", newPosition);
            if (_backDirection && newPosition >= initialPosition)
                break;
            if (!_backDirection && newPosition <= initialPosition)
                break;
        }
        debug (editors)
            Log.d("replaceAll - done, replace count = ", count);
        _editor.ensureCaretVisible();
        return count;
    }

    void updateHighlight()
    {
        const currentText = _edFind.text;
        debug (editors)
            Log.d("updateHighlight currentText: ", currentText);
        _editor.setTextToHighlight(currentText, makeSearchOptions());
    }

    void handleFindTextChange(dstring str)
    {
        debug (editors)
            Log.d("handleFindTextChange");
        updateHighlight();
    }

    void handleCaseSensitiveToggle(bool checkValue)
    {
        updateHighlight();
    }
}
+/
