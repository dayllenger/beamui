/**
Single-line and multiline simple text editors.

Copyright: Vadim Lopatin 2014-2017, James Johnson 2017, dayllenger 2019
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
import beamui.graphics.colors;
import beamui.text.simple;
import beamui.text.sizetest;
import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.scroll;
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
    ACTION_ED_DELETE_LINE = new Action(tr("Delete line"), Key.D, KeyMods.control).addShortcut(Key.L, KeyMods.control);
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

/// Base for all editor widgets
class EditWidgetBase : ScrollAreaBase, ActionOperator
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
            if (_content !is null)
            {
                // disconnect old content
                _content.contentChanged.disconnect(&onContentChange);
                if (_ownContent)
                {
                    destroy(_content);
                }
            }
            _content = content;
            _ownContent = false;
            _content.contentChanged.connect(&onContentChange);
            if (_content.readOnly)
                enabled = false;
        }

        /// Readonly flag (when true, user cannot change content of editor)
        bool readOnly() const
        {
            return !enabled || _content.readOnly;
        }
        /// ditto
        void readOnly(bool readOnly)
        {
            enabled = !readOnly;
            invalidate();
        }

        /// Replace mode flag (when true, entered character replaces character under cursor)
        bool replaceMode() const { return _replaceMode; }
        /// ditto
        void replaceMode(bool replaceMode)
        {
            _replaceMode = replaceMode;
            handleEditorStateChange();
            invalidate();
        }

        /// When true, spaces will be inserted instead of tabs on Tab key
        bool useSpacesForTabs() const
        {
            return _content.useSpacesForTabs;
        }
        /// ditto
        void useSpacesForTabs(bool useSpacesForTabs)
        {
            _content.useSpacesForTabs = useSpacesForTabs;
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
                requestLayout();
            }
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

        /// True if smart indents are enabled
        bool smartIndentsAfterPaste() const
        {
            return _content.smartIndentsAfterPaste;
        }
        /// ditto
        void smartIndentsAfterPaste(bool enabled)
        {
            _content.smartIndentsAfterPaste = enabled;
        }

        /// When true shows mark on tab positions in beginning of line
        bool showTabPositionMarks() const { return _showTabPositionMarks; }
        /// ditto
        void showTabPositionMarks(bool flag)
        {
            if (flag != _showTabPositionMarks)
            {
                _showTabPositionMarks = flag;
                invalidate();
            }
        }

        /// To hold _scrollpos.x toggling between normal and word wrap mode
        private int previousXScrollPos;
        /// True if word wrap mode is set
        bool wordWrap() const { return _wordWrap; }
        /// Enable or disable word wrap mode
        void wordWrap(bool v)
        {
            _wordWrap = v;
            // horizontal scrollbar should not be visible in word wrap mode
            if (v)
            {
                hscrollbar.visibility = Visibility.hidden;
                previousXScrollPos = _scrollPos.x;
                _scrollPos.x = 0;
                wordWrapRefresh();
            }
            else
            {
                hscrollbar.visibility = Visibility.visible;
                _scrollPos.x = previousXScrollPos;
            }
            invalidate();
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

        dstring minSizeTester() const
        {
            return _minSizeTester.str;
        }
        /// ditto
        void minSizeTester(dstring txt)
        {
            _minSizeTester.str = txt;
            requestLayout();
        }

        /// Placeholder is a short peace of text that describe expected value in an input field
        dstring placeholder() const
        {
            return _placeholder ? _placeholder.str : null;
        }
        /// ditto
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

        /// Font line height, always > 0
        protected int lineHeight() const { return _lineHeight; }
    }

    /// When true, Tab / Shift+Tab presses are processed internally in widget (e.g. insert tab character) instead of focus change navigation.
    bool wantTabs = true;
    /// When true, allows copy / cut whole current line if there is no selection
    bool copyCurrentLineWhenNoSelection = true;

    /// Modified state change listener (e.g. content has been saved, or first time modified after save)
    Signal!(void delegate(bool modified)) modifiedStateChanged;

    /// Signal to emit when editor content is changed
    Signal!(void delegate(EditableContent)) contentChanged;

    /// Signal to emit when editor cursor position or Insert/Replace mode is changed.
    Signal!(void delegate(ref EditorStateInfo editorState)) stateChanged;

    // left pane - can be used to show line numbers, collapse controls, bookmarks, breakpoints, custom icons
    protected int _leftPaneWidth;

    private
    {
        EditableContent _content;
        /// When `_ownContent` is false, `_content` should not be destroyed in editor destructor
        bool _ownContent = true;

        int _lineHeight = 1;
        Point _scrollPos;
        bool _fixedFont;
        int _spaceWidth;

        bool _selectAllWhenFocusedWithTab;
        bool _deselectAllWhenUnfocused;

        bool _replaceMode;

        Color _selectionColorFocused = Color(0xB060A0FF);
        Color _selectionColorNormal = Color(0xD060A0FF);
        Color _searchHighlightColorCurrent = Color(0x808080FF);
        Color _searchHighlightColorOther = Color(0xC08080FF);

        Color _caretColor = Color(0x0);
        Color _caretColorReplace = Color(0x808080FF);
        Color _matchingBracketHighlightColor = Color(0x60FFE0B0);

        /// When true, call `measureVisibleText` on next layout
        bool _contentChanged = true;

        bool _showTabPositionMarks;

        bool _wordWrap;

        SimpleText* _placeholder;
        TextSizeTester _minSizeTester;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        allowsFocus = true;
        bindActions();
        handleFontChange();
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

    override @property bool canFocus() const
    {
        // allow to focus even if not enabled
        return allowsFocus && visible;
    }

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
            {
                _selectionRange.start = _caretPos;
                _selectionRange.end = _caretPos;
            }
        }
        if (focused && _selectAllWhenFocusedWithTab && receivedFocusFromKeyboard)
            selectAll();
        super.handleFocusChange(focused);
    }

    //===============================================================

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        if (auto ph = _placeholder)
        {
            switch (ptype) with (StyleProperty)
            {
            case textAlign:
                ph.style.alignment = style.textAlign;
                break;
            case textDecorationLine:
                ph.style.decoration.line = style.textDecorationLine;
                break;
            case textDecorationStyle:
                ph.style.decoration.style = style.textDecorationStyle;
                break;
            case textOverflow:
                ph.style.overflow = style.textOverflow;
                break;
            case textTransform:
                ph.style.transform = style.textTransform;
                break;
            default:
                break;
            }
        }
    }

    override protected void handleFontChange()
    {
        Font font = font();
        _fixedFont = font.isFixed;
        _spaceWidth = font.spaceWidth;
        _lineHeight = max(font.height, 1);
        _minSizeTester.style.font = font;
        if (auto ph = _placeholder)
            ph.style.font = font;
    }

    /// Updates `stateChanged` with recent position
    protected void handleEditorStateChange()
    {
        if (!stateChanged.assigned)
            return;
        EditorStateInfo info;
        if (visible)
        {
            info.replaceMode = _replaceMode;
            info.line = _caretPos.line + 1;
            info.col = _caretPos.pos + 1;
            if (_caretPos.line >= 0 && _caretPos.line < _content.length)
            {
                dstring line = _content.line(_caretPos.line);
                if (_caretPos.pos >= 0 && _caretPos.pos < line.length)
                    info.character = line[_caretPos.pos];
                else
                    info.character = '\n';
            }
        }
        stateChanged(info);
    }

    override protected void handleClientBoxLayout(ref Box clb)
    {
        updateLeftPaneWidth();
        clb.x += _leftPaneWidth;
        clb.w -= _leftPaneWidth;
    }

    /// Override for multiline editors
    protected int lineCount() const
    {
        return 1;
    }

    //===============================================================
    // Dynamic word wrap implementation

    /// Override for EditBox
    void wordWrapRefresh()
    {
        return;
    }

    /// Characters at which content is split for word wrap mode
    dchar[] splitChars = [' ', '-', '\t'];

    /// Divides up a string for word wrapping, sets info in _span
    dstring[] wrapLine(dstring str, int lineNumber)
    {
        FontRef font = font();
        dstring[] words = explode(str, splitChars);
        int curLineLength = 0;
        dchar[] buildingStr;
        dstring[] buildingStrArr;
        WrapPoint[] wrapPoints;
        int wrappedLineCount = 0;
        int curLineWidth = 0;
        int maxWidth = clientBox.width;
        for (int i = 0; i < words.length; i++)
        {
            dstring word = words[i];
            if (curLineWidth + measureWrappedText(word) > maxWidth)
            {
                if (curLineWidth > 0)
                {
                    buildingStrArr ~= to!dstring(buildingStr);
                    wrappedLineCount++;
                    wrapPoints ~= WrapPoint(curLineLength, curLineWidth);
                    curLineLength = 0;
                    curLineWidth = 0;
                    buildingStr = [];
                }
                while (measureWrappedText(word) > maxWidth)
                {
                    //For when string still too long
                    int wrapPoint = findWrapPoint(word);
                    wrapPoints ~= WrapPoint(wrapPoint, measureWrappedText(word[0 .. wrapPoint]));
                    buildingStr ~= word[0 .. wrapPoint];
                    word = word[wrapPoint .. $];
                    buildingStrArr ~= to!dstring(buildingStr);
                    buildingStr = [];
                    wrappedLineCount++;
                }
            }
            buildingStr ~= word;
            curLineLength += to!int(word.length);
            curLineWidth += measureWrappedText(word);
        }
        wrapPoints ~= WrapPoint(curLineLength, curLineWidth);
        buildingStrArr ~= to!dstring(buildingStr);
        _span ~= LineSpan(lineNumber, wrappedLineCount + 1, wrapPoints, buildingStrArr);
        return buildingStrArr;
    }

    /// Divide (and conquer) text into words
    dstring[] explode(dstring str, dchar[] splitChars)
    {
        dstring[] parts;
        int startIndex = 0;
        import std.string : indexOfAny;

        while (true)
        {
            int index = to!int(str.indexOfAny(splitChars, startIndex));

            if (index == -1)
            {
                parts ~= str[startIndex .. $];
                debug (editors)
                    Log.d("Explode output: ", parts);
                return parts;
            }

            dstring word = str[startIndex .. index];
            dchar nextChar = (str[index .. index + 1])[0];

            import std.ascii : isWhite;

            if (isWhite(nextChar))
            {
                parts ~= word;
                parts ~= to!dstring(nextChar);
            }
            else
            {
                parts ~= word ~ nextChar;
            }
            startIndex = index + 1;
        }
    }

    /// Information about line span into several lines - in word wrap mode
    private LineSpan[] _span;
    private LineSpan[] _spanCache;

    /// Finds good visual wrapping point for string
    int findWrapPoint(dstring text)
    {
        int maxWidth = clientBox.width;
        int wrapPoint = 0;
        while (true)
        {
            if (measureWrappedText(text[0 .. wrapPoint]) < maxWidth)
            {
                wrapPoint++;
            }
            else
            {
                return wrapPoint;
            }
        }
    }

    /// Call measureText for word wrap
    int measureWrappedText(dstring text)
    {
        FontRef font = font();
        int[] measuredWidths;
        measuredWidths.length = text.length;
        //DO NOT REMOVE THIS
        int boggle = font.measureText(text, measuredWidths);
        if (measuredWidths.length > 0)
            return measuredWidths[$ - 1];
        return 0;
    }

    /// Returns number of visible wraps up to a line (not including the first wrapLines themselves)
    int wrapsUpTo(int line)
    {
        int sum;
        lineSpanIterate(delegate(LineSpan curSpan) {
            if (curSpan.start < line)
                sum += curSpan.len - 1;
        });
        return sum;
    }

    /// Returns LineSpan for line based on actual line number
    LineSpan getSpan(int lineNumber)
    {
        LineSpan lineSpan = LineSpan(lineNumber, 0, [WrapPoint(0, 0)], []);
        lineSpanIterate(delegate(LineSpan curSpan) {
            if (curSpan.start == lineNumber)
                lineSpan = curSpan;
        });
        return lineSpan;
    }

    /// Based on a TextPosition, finds which wrapLine it is on for its current line
    int findWrapLine(TextPosition textPos)
    {
        int curWrapLine = 0;
        int curPosition = textPos.pos;
        LineSpan curSpan = getSpan(textPos.line);
        while (true)
        {
            if (curWrapLine == curSpan.wrapPoints.length - 1)
                return curWrapLine;
            curPosition -= curSpan.wrapPoints[curWrapLine].wrapPos;
            if (curPosition < 0)
            {
                return curWrapLine;
            }
            curWrapLine++;
        }
    }

    /// Simple way of iterating through _span
    void lineSpanIterate(void delegate(LineSpan curSpan) iterator)
    {
        //TODO: Rename iterator to iteration?
        foreach (currentSpan; _span)
            iterator(currentSpan);
    }

    //===============================================================

    /// Override to add custom items on left panel
    protected void updateLeftPaneWidth()
    {
    }

    protected bool onLeftPaneMouseClick(MouseEvent event)
    {
        return false;
    }

    protected void drawLeftPane(DrawBuf buf, Rect rc, int line)
    {
        // override for custom drawn left pane
    }

    override bool canShowPopupMenu(int x, int y)
    {
        if (popupMenu is null)
            return false;
        if (popupMenu.openingSubmenu.assigned)
            if (!popupMenu.openingSubmenu(popupMenu))
                return false;
        return true;
    }

    override CursorType getCursorType(int x, int y) const
    {
        return x < box.x + _leftPaneWidth ? CursorType.arrow : CursorType.ibeam;
    }

    protected void updateMaxLineWidth()
    {
    }

    protected void processSmartIndent(EditOperation operation)
    {
        if (!supportsSmartIndents)
            return;
        if (!smartIndents && !smartIndentsAfterPaste)
            return;
        _content.syntaxSupport.applySmartIndent(operation, this);
    }

    protected void onContentChange(EditOperation operation,
            ref TextRange rangeBefore, ref TextRange rangeAfter, Object source)
    {
        debug (editors)
            Log.d("onContentChange rangeBefore: ", rangeBefore, ", rangeAfter: ", rangeAfter,
                    ", text: ", operation.content);
        _contentChanged = true;
        if (source is this)
        {
            if (operation.action == EditAction.replaceContent)
            {
                // fully replaced, e.g., loaded from file or text property is assigned
                _caretPos = rangeAfter.end;
                _selectionRange.start = _caretPos;
                _selectionRange.end = _caretPos;
                updateMaxLineWidth();
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
                _selectionRange.start = _caretPos;
                _selectionRange.end = _caretPos;
                updateMaxLineWidth();
                measureVisibleText();
                ensureCaretVisible();
                updateActions();
                processSmartIndent(operation);
            }
        }
        else
        {
            updateMaxLineWidth();
            measureVisibleText();
            correctCaretPos();
            requestLayout();
            updateActions();
        }
        invalidate();
        if (modifiedStateChanged.assigned)
        {
            if (_lastReportedModifiedState != _content.modified)
            {
                _lastReportedModifiedState = _content.modified;
                modifiedStateChanged(_content.modified);
                updateActions();
            }
        }
        contentChanged(_content);
        handleEditorStateChange();
        return;
    }

    abstract protected Box textPosToClient(TextPosition p) const;

    abstract protected TextPosition clientToTextPos(Point pt) const;

    abstract protected void ensureCaretVisible(bool center = false);

    abstract protected Size measureVisibleText();

    private
    {
        bool _lastReportedModifiedState;

        TextPosition _caretPos;
        TextRange _selectionRange;

        int _caretBlinkingInterval = 800;
        ulong _caretTimerID;
        bool _caretBlinkingPhase;
        long _lastBlinkStartTs;
        bool _caretBlinks = true;
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

        /// When true, enables caret blinking, otherwise it's always visible
        bool showCaretBlinking() const { return _caretBlinks; }
        /// ditto
        void showCaretBlinking(bool blinks)
        {
            _caretBlinks = blinks;
        }
    }

    //===============================================================
    // Caret

    /// Change caret position and ensure it is visible
    void setCaretPos(int line, int column, bool makeVisible = true, bool center = false)
    {
        _caretPos = TextPosition(line, column);
        correctCaretPos();
        invalidate();
        if (makeVisible)
            ensureCaretVisible(center);
        handleEditorStateChange();
    }

    protected void startCaretBlinking()
    {
        if (window)
        {
            static if (BACKEND_CONSOLE)
            {
                window.caretRect = caretRect;
                window.caretReplace = _replaceMode;
            }
            else
            {
                const long ts = currentTimeMillis;
                if (_caretTimerID)
                {
                    if (_lastBlinkStartTs + _caretBlinkingInterval / 4 > ts)
                        return; // don't update timer too frequently
                    cancelTimer(_caretTimerID);
                }
                _caretTimerID = setTimer(_caretBlinkingInterval / 2,
                    delegate() {
                        _caretBlinkingPhase = !_caretBlinkingPhase;
                        if (!_caretBlinkingPhase)
                            _lastBlinkStartTs = currentTimeMillis;
                        invalidate();
                        bool repeat = focused;
                        if (!repeat)
                            _caretTimerID = 0;
                        return repeat;
                    });
                _lastBlinkStartTs = ts;
                _caretBlinkingPhase = false;
                invalidate();
            }
        }
    }

    protected void stopCaretBlinking()
    {
        if (window)
        {
            static if (BACKEND_CONSOLE)
            {
                window.caretRect = Rect.init;
            }
            else
            {
                if (_caretTimerID)
                {
                    cancelTimer(_caretTimerID);
                    _caretTimerID = 0;
                }
            }
        }
    }

    /// In word wrap mode, set by caretRect so ensureCaretVisible will know when to scroll
    private int caretHeightOffset;

    /// Returns cursor rectangle
    protected Rect caretRect()
    {
        Rect caretRc = Rect(textPosToClient(_caretPos));
        if (_replaceMode)
        {
            const dstring s = _content[_caretPos.line];
            if (_caretPos.pos < s.length)
            {
                TextPosition nextPos = _caretPos;
                nextPos.pos++;
                const Rect nextRect = Rect(textPosToClient(nextPos));
                caretRc.right = nextRect.right;
            }
            else
            {
                caretRc.right += _spaceWidth;
            }
        }
        if (_wordWrap)
        {
            _scrollPos.x = 0;
            const int wrapLine = findWrapLine(_caretPos);
            int xOffset;
            if (wrapLine > 0)
            {
                LineSpan curSpan = getSpan(_caretPos.line);
                xOffset = curSpan.accumulation(wrapLine, LineSpan.WrapPointInfo.width);
            }
            const int yOffset = -1 * _lineHeight * (wrapsUpTo(_caretPos.line) + wrapLine);
            caretHeightOffset = yOffset;
            caretRc.offset(clientBox.x - xOffset, clientBox.y - yOffset);
        }
        else
            caretRc.offset(clientBox.x, clientBox.y);
        return caretRc;
    }

    /// Draw caret
    protected void drawCaret(DrawBuf buf)
    {
        if (focused)
        {
            if (_caretBlinkingPhase && _caretBlinks)
                return;
            // draw caret
            const Rect caretRc = caretRect();
            if (caretRc.intersects(Rect(clientBox)))
            {
                //caretRc.left++;
                if (_replaceMode && BACKEND_GUI)
                    buf.fillRect(caretRc, _caretColorReplace);
                //buf.drawLine(Point(caretRc.left, caretRc.bottom), Point(caretRc.left, caretRc.top), _caretColor);
                buf.fillRect(Rect(caretRc.left, caretRc.top, caretRc.left + 1, caretRc.bottom), _caretColor);
            }
        }
    }

    //===============================================================

    override void onThemeChanged()
    {
        super.onThemeChanged();
        _caretColor = currentTheme.getColor("edit_caret", Color(0x0));
        _caretColorReplace = currentTheme.getColor("edit_caret_replace", Color(0x808080FF));
        _selectionColorFocused = currentTheme.getColor("editor_selection_focused", Color(0xB060A0FF));
        _selectionColorNormal = currentTheme.getColor("editor_selection_normal", Color(0xD060A0FF));
        _searchHighlightColorCurrent = currentTheme.getColor("editor_search_highlight_current", Color(0x808080FF));
        _searchHighlightColorOther = currentTheme.getColor("editor_search_highlight_other", Color(0xC08080FF));
        _matchingBracketHighlightColor = currentTheme.getColor("editor_matching_bracket_highlight", Color(0x60FFE0B0));
    }

    /// When cursor position or selection is out of content bounds, fix it to nearest valid position
    protected void correctCaretPos()
    {
        _content.correctPosition(_caretPos);
        _content.correctPosition(_selectionRange.start);
        _content.correctPosition(_selectionRange.end);
        if (_selectionRange.empty)
            _selectionRange = TextRange(_caretPos, _caretPos);
        handleEditorStateChange();
    }

    private int[] _lineWidthBuf;
    protected int calcLineWidth(dstring s)
    {
        int w;
        if (_fixedFont)
        {
            const int tabw = tabSize * _spaceWidth;
            // version optimized for fixed font
            foreach (ch; s)
            {
                if (ch == '\t')
                {
                    w += _spaceWidth;
                    w = (w + tabw - 1) / tabw * tabw;
                }
                else
                {
                    w += _spaceWidth;
                }
            }
        }
        else
        {
            // variable pitch font
            if (_lineWidthBuf.length < s.length)
                _lineWidthBuf.length = s.length;
            const int charsMeasured = font.measureText(s, _lineWidthBuf, int.max);
            if (charsMeasured > 0)
                w = _lineWidthBuf[charsMeasured - 1];
        }
        return w;
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
        {
            _selectionRange.start = _caretPos;
            _selectionRange.end = _caretPos;
        }
        invalidate();
        updateActions();
        handleEditorStateChange();
    }

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

    /// Used instead of using `clientToTextPos` for mouse input when in word wrap mode
    protected TextPosition wordWrapMouseOffset(int x, int y)
    {
        if (_span.length == 0)
            return clientToTextPos(Point(x, y));
        const int selectedVisibleLine = y / _lineHeight;

        LineSpan _curSpan;

        int wrapLine;
        int curLine;
        bool foundWrap;
        int accumulativeWidths;
        int curWrapOfSpan;

        lineSpanIterate(delegate(LineSpan curSpan) {
            while (!foundWrap)
            {
                if (wrapLine == selectedVisibleLine)
                {
                    foundWrap = true;
                    break;
                }
                accumulativeWidths += curSpan.wrapPoints[curWrapOfSpan].wrapWidth;
                wrapLine++;
                curWrapOfSpan++;
                if (curWrapOfSpan >= curSpan.len)
                {
                    break;
                }
            }
            if (!foundWrap)
            {
                accumulativeWidths = 0;
                curLine++;
            }
            curWrapOfSpan = 0;
        });

        const int fakeLineHeight = curLine * _lineHeight;
        return clientToTextPos(Point(x + accumulativeWidths, fakeLineHeight));
    }

    protected void selectWordByMouse(int x, int y)
    {
        const TextPosition oldCaretPos = _caretPos;
        const TextPosition newPos = _wordWrap ? wordWrapMouseOffset(x, y) : clientToTextPos(Point(x, y));
        const TextRange r = content.wordBounds(newPos);
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

    protected void selectLineByMouse(int x, int y, bool onSameLineOnly = true)
    {
        const TextPosition oldCaretPos = _caretPos;
        const TextPosition newPos = _wordWrap ? wordWrapMouseOffset(x, y) : clientToTextPos(Point(x, y));
        if (onSameLineOnly && newPos.line != oldCaretPos.line)
            return; // different lines
        const TextRange r = content.lineRange(newPos.line);
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

    protected void updateCaretPositionByMouse(int x, int y, bool selecting)
    {
        const TextPosition oldCaretPos = _caretPos;
        const TextPosition newPos = _wordWrap ? wordWrapMouseOffset(x, y) : clientToTextPos(Point(x, y));
        if (newPos != _caretPos)
        {
            _caretPos = newPos;
            updateSelectionAfterCursorMovement(oldCaretPos, selecting);
            invalidate();
        }
        handleEditorStateChange();
    }

    /// Generate string of spaces, to reach next tab position
    protected dstring spacesForTab(int currentPos)
    {
        const int newPos = (currentPos + tabSize + 1) / tabSize * tabSize;
        return "                "d[0 .. (newPos - currentPos)];
    }

    /// Returns true if one or more lines selected fully
    protected bool multipleLinesSelected()
    {
        return _selectionRange.end.line > _selectionRange.start.line;
    }

    private bool _camelCasePartsAsWords = true;

    void replaceSelectionText(dstring newText)
    {
        auto op = new EditOperation(EditAction.replace, _selectionRange, [newText]);
        _content.performOperation(op, this);
        ensureCaretVisible();
    }

    protected bool removeSelectionTextIfSelected()
    {
        if (_selectionRange.empty)
            return false;
        // clear selection
        auto op = new EditOperation(EditAction.replace, _selectionRange, [""d]);
        _content.performOperation(op, this);
        ensureCaretVisible();
        return true;
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

    /// Returns range for line with cursor
    @property TextRange currentLineRange() const
    {
        return _content.lineRange(_caretPos.line);
    }

    /// Clear selection (doesn't change text, just deselects)
    void clearSelection()
    {
        _selectionRange = TextRange(_caretPos, _caretPos);
        invalidate();
    }

    protected bool removeRangeText(TextRange range)
    {
        if (range.empty)
            return false;
        _selectionRange = range;
        _caretPos = _selectionRange.start;
        auto op = new EditOperation(EditAction.replace, range, [""d]);
        _content.performOperation(op, this);
        //_selectionRange.start = _caretPos;
        //_selectionRange.end = _caretPos;
        ensureCaretVisible();
        handleEditorStateChange();
        return true;
    }

    //===============================================================
    // Actions

    protected void bindActions()
    {
        debug (editors)
            Log.d("Editor `", id, "`: bind actions");

        ACTION_LINE_BEGIN.bind(this, { LineBegin(false); });
        ACTION_LINE_END.bind(this, { LineEnd(false); });
        ACTION_DOCUMENT_BEGIN.bind(this, { DocumentBegin(false); });
        ACTION_DOCUMENT_END.bind(this, { DocumentEnd(false); });
        ACTION_SELECT_LINE_BEGIN.bind(this, { LineBegin(true); });
        ACTION_SELECT_LINE_END.bind(this, { LineEnd(true); });
        ACTION_SELECT_DOCUMENT_BEGIN.bind(this, { DocumentBegin(true); });
        ACTION_SELECT_DOCUMENT_END.bind(this, { DocumentEnd(true); });

        ACTION_BACKSPACE.bind(this, &DelPrevChar);
        ACTION_DELETE.bind(this, &DelNextChar);
        ACTION_ED_DEL_PREV_WORD.bind(this, &DelPrevWord);
        ACTION_ED_DEL_NEXT_WORD.bind(this, &DelNextWord);

        ACTION_ED_INDENT.bind(this, &Tab);
        ACTION_ED_UNINDENT.bind(this, &BackTab);

        ACTION_SELECT_ALL.bind(this, &selectAll);

        ACTION_UNDO.bind(this, { _content.undo(this); });
        ACTION_REDO.bind(this, { _content.redo(this); });

        ACTION_CUT.bind(this, &cut);
        ACTION_COPY.bind(this, &copy);
        ACTION_PASTE.bind(this, &paste);

        ACTION_ED_TOGGLE_REPLACE_MODE.bind(this, {
            replaceMode = !replaceMode;
            invalidate();
        });
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
            ACTION_ED_INDENT,
            ACTION_ED_UNINDENT,
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

        ACTION_ED_INDENT.enabled = enabled && wantTabs;
        ACTION_ED_UNINDENT.enabled = enabled && wantTabs;

        ACTION_UNDO.enabled = enabled && _content.hasUndo;
        ACTION_REDO.enabled = enabled && _content.hasRedo;

        ACTION_CUT.enabled = enabled && (copyCurrentLineWhenNoSelection || !_selectionRange.empty);
        ACTION_COPY.enabled = copyCurrentLineWhenNoSelection || !_selectionRange.empty;
        ACTION_PASTE.enabled = enabled && platform.hasClipboardText();
    }

    protected void LineBegin(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        const space = _content.getLineWhiteSpace(_caretPos.line);
        if (_caretPos.pos > 0)
        {
            if (_caretPos.pos > space.firstNonSpaceIndex && space.firstNonSpaceIndex > 0)
                _caretPos.pos = space.firstNonSpaceIndex;
            else
                _caretPos.pos = 0;
            ensureCaretVisible();
            updateSelectionAfterCursorMovement(oldCaretPos, select);
        }
        else
        {
            // caret pos is 0
            if (space.firstNonSpaceIndex > 0)
                _caretPos.pos = space.firstNonSpaceIndex;
            ensureCaretVisible();
            updateSelectionAfterCursorMovement(oldCaretPos, select);
            if (!select && _caretPos == oldCaretPos)
            {
                clearSelection();
            }
        }
    }
    protected void LineEnd(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        const dstring currentLine = _content[_caretPos.line];
        if (_caretPos.pos < currentLine.length)
        {
            _caretPos.pos = cast(int)currentLine.length;
            ensureCaretVisible();
            updateSelectionAfterCursorMovement(oldCaretPos, select);
        }
        else if (!select)
        {
            clearSelection();
        }
    }
    protected void DocumentBegin(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        if (_caretPos.pos > 0 || _caretPos.line > 0)
        {
            _caretPos.line = 0;
            _caretPos.pos = 0;
            ensureCaretVisible();
            updateSelectionAfterCursorMovement(oldCaretPos, select);
        }
    }
    protected void DocumentEnd(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        if (_caretPos.line < _content.length - 1 || _caretPos.pos < _content[_content.length - 1].length)
        {
            _caretPos.line = _content.length - 1;
            _caretPos.pos = cast(int)_content[_content.length - 1].length;
            ensureCaretVisible();
            updateSelectionAfterCursorMovement(oldCaretPos, select);
        }
    }

    protected void DelPrevChar()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
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
    protected void DelNextChar()
    {
        const currentLineLength = _content[_caretPos.line].length;
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
            return;
        if (_caretPos.pos < currentLineLength)
        {
            // delete char in current line
            auto range = TextRange(_caretPos, _caretPos);
            range.end.pos++;
            removeRangeText(range);
        }
        else if (_caretPos.line < _content.length - 1)
        {
            // merge with next line
            auto range = TextRange(_caretPos, _caretPos);
            range.end.line++;
            range.end.pos = 0;
            removeRangeText(range);
        }
    }
    protected void DelPrevWord()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
            return;
        const TextPosition newpos = _content.moveByWord(_caretPos, -1, _camelCasePartsAsWords);
        if (newpos < _caretPos)
            removeRangeText(TextRange(newpos, _caretPos));
    }
    protected void DelNextWord()
    {
        if (readOnly)
            return;
        correctCaretPos();
        if (removeSelectionTextIfSelected()) // clear selection
            return;
        const TextPosition newpos = _content.moveByWord(_caretPos, 1, _camelCasePartsAsWords);
        if (newpos > _caretPos)
            removeRangeText(TextRange(_caretPos, newpos));
    }

    protected void Tab()
    {
        if (readOnly)
            return;
        if (_selectionRange.empty)
        {
            if (useSpacesForTabs)
            {
                // insert one or more spaces to
                auto op = new EditOperation(EditAction.replace,
                        TextRange(_caretPos, _caretPos), [spacesForTab(_caretPos.pos)]);
                _content.performOperation(op, this);
            }
            else
            {
                // just insert tab character
                auto op = new EditOperation(EditAction.replace,
                        TextRange(_caretPos, _caretPos), ["\t"d]);
                _content.performOperation(op, this);
            }
        }
        else
        {
            if (multipleLinesSelected())
            {
                indentRange(false);
            }
            else
            {
                // insert tab
                if (useSpacesForTabs)
                {
                    // insert one or more spaces to
                    auto op = new EditOperation(EditAction.replace,
                            _selectionRange, [spacesForTab(_selectionRange.start.pos)]);
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
    }
    protected void BackTab()
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
            }
            else
            {
                // remove space before selection
                const TextRange r = spaceBefore(_selectionRange.start);
                if (!r.empty)
                {
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
        }
    }

    /// Cut currently selected text into clipboard
    void cut()
    {
        if (readOnly)
            return;
        TextRange range = _selectionRange;
        if (range.empty && copyCurrentLineWhenNoSelection)
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

    /// Copy currently selected text into clipboard
    void copy()
    {
        TextRange range = _selectionRange;
        if (range.empty && copyCurrentLineWhenNoSelection)
        {
            range = currentLineRange;
        }
        if (!range.empty)
        {
            dstring selectionText = getRangeText(range);
            platform.setClipboardText(selectionText);
        }
    }

    /// Replace currently selected text with clipboard content
    void paste()
    {
        if (readOnly)
            return;
        dstring selectionText = platform.getClipboardText();
        dstring[] lines;
        if (_content.multiline)
        {
            lines = splitDString(selectionText);
        }
        else
        {
            lines = [replaceEOLsWithSpaces(selectionText)];
        }
        auto op = new EditOperation(EditAction.replace, _selectionRange, lines);
        _content.performOperation(op, this);
    }

    /// Select whole text
    void selectAll()
    {
        _selectionRange.start.line = 0;
        _selectionRange.start.pos = 0;
        _selectionRange.end = _content.lineEnd(_content.length - 1);
        _caretPos = _selectionRange.end;
        ensureCaretVisible();
        invalidate();
        updateActions();
    }

    protected TextRange spaceBefore(TextPosition pos) const
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

    /// Change line indent
    protected dstring indentLine(dstring src, bool back, TextPosition* cursorPos)
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

    /// Indent / unindent range
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

    //===============================================================
    // Events

    override bool onKeyEvent(KeyEvent event)
    {
        import std.ascii : isAlpha;

        debug (keys)
            Log.d("onKeyEvent ", event.action, " ", event.key, ", mods ", event.allModifiers);
        if (focused)
            startCaretBlinking();
        cancelHoverTimer();

        const bool noOtherModifiers = !event.alteredBy(KeyMods.alt | KeyMods.meta);
        if (event.action == KeyAction.keyDown && noOtherModifiers)
        {
            TextPosition oldCaretPos = _caretPos;
            const currentLineLength = _content[_caretPos.line].length;

            const bool shiftPressed = event.alteredBy(KeyMods.shift);
            const bool controlPressed = event.alteredBy(KeyMods.control);
            if (event.key == Key.left)
            {
                if (!controlPressed)
                {
                    // move cursor one char left (with selection when Shift pressed)
                    correctCaretPos();
                    if (_caretPos.pos > 0)
                    {
                        _caretPos.pos--;
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
                    else if (_caretPos.line > 0)
                    {
                        _caretPos = _content.lineEnd(_caretPos.line - 1);
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
                    return true;
                }
                else
                {
                    // move cursor one word left (with selection when Shift pressed)
                    TextPosition newpos = _content.moveByWord(_caretPos, -1, _camelCasePartsAsWords);
                    if (newpos != _caretPos)
                    {
                        _caretPos = newpos;
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
                    return true;
                }
            }
            if (event.key == Key.right)
            {
                if (!controlPressed)
                {
                    // move cursor one char right (with selection when Shift pressed)
                    correctCaretPos();
                    if (_caretPos.pos < currentLineLength)
                    {
                        _caretPos.pos++;
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
                    else if (_caretPos.line < _content.length - 1 && _content.multiline)
                    {
                        _caretPos.pos = 0;
                        _caretPos.line++;
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
                    return true;
                }
                else
                {
                    // move cursor one word right (with selection when Shift pressed)
                    const TextPosition newpos = _content.moveByWord(_caretPos, 1, _camelCasePartsAsWords);
                    if (newpos != _caretPos)
                    {
                        _caretPos = newpos;
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
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
        return super.onKeyEvent(event);
    }

    private TextPosition _hoverTextPosition;
    private Point _hoverMousePosition;
    private ulong _hoverTimer;
    private long _hoverTimeoutMillis = 800;

    /// Override to handle mouse hover timeout in text
    protected void onHoverTimeout(Point pt, TextPosition pos)
    {
        // override to do something useful on hover timeout
    }

    protected void onHover(Point pos)
    {
        if (_hoverMousePosition == pos)
            return;
        debug (mouse)
            Log.d("onHover ", pos);
        const int x = pos.x - box.x - _leftPaneWidth;
        const int y = pos.y - box.y;
        _hoverMousePosition = pos;
        _hoverTextPosition = clientToTextPos(Point(x, y));
        cancelHoverTimer();
        const Box reversePos = textPosToClient(_hoverTextPosition);
        if (x < reversePos.x + 10)
        {
            _hoverTimer = setTimer(_hoverTimeoutMillis, delegate() {
                onHoverTimeout(_hoverMousePosition, _hoverTextPosition);
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

    override bool onMouseEvent(MouseEvent event)
    {
        debug (mouse)
            Log.d("onMouseEvent ", id, " ", event.action, "  (", event.x, ",", event.y, ")");
        // support onClick
        const bool insideLeftPane = event.x < clientBox.x && event.x >= clientBox.x - _leftPaneWidth;
        if (event.action == MouseAction.buttonDown && insideLeftPane)
        {
            setFocus();
            cancelHoverTimer();
            if (onLeftPaneMouseClick(event))
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
                    onControlClick();
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
                onHover(event.pos);
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
        return super.onMouseEvent(event);
    }

    /// Handle Ctrl + Left mouse click on text
    protected void onControlClick()
    {
        // override to do something useful on Ctrl + Left mouse click in text
    }
}

/// Single line editor
class EditLine : EditWidgetBase
{
    @property
    {
        /// Password character - 0 for normal editor, some character
        /// e.g. '*' to hide text by replacing all characters with this char
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
    }

    /// Handle Enter key press inside line editor
    Signal!(bool delegate()) enterKeyPressed; // FIXME: better name

    private
    {
        dstring _measuredText;
        int[] _measuredTextWidths;
        Size _measuredTextSize;

        dchar _passwordChar = 0;
    }

    this(dstring initialContent = null)
    {
        super(ScrollBarMode.hidden, ScrollBarMode.hidden);
        _content = new EditableContent(false);
        _content.contentChanged ~= &onContentChange;
        _selectAllWhenFocusedWithTab = true;
        _deselectAllWhenUnfocused = true;
        wantTabs = false;
        text = initialContent;
        _minSizeTester.str = "aaaaa"d;
        onThemeChanged();
    }

    /// Set default popup menu with copy/paste/cut/undo/redo
    EditLine setDefaultPopupMenu()
    {
        popupMenu = new Menu;
        popupMenu.add(ACTION_UNDO, ACTION_REDO, ACTION_CUT, ACTION_COPY, ACTION_PASTE);
        return this;
    }

    override protected Box textPosToClient(TextPosition p) const
    {
        Box res;
        res.h = clientBox.height;
        if (p.pos == 0)
            res.x = 0;
        else if (p.pos >= _measuredText.length)
            res.x = _measuredTextSize.w;
        else
            res.x = _measuredTextWidths[p.pos - 1];
        res.x -= _scrollPos.x;
        res.w = 1;
        return res;
    }

    override protected TextPosition clientToTextPos(Point pt) const
    {
        pt.x += _scrollPos.x;
        TextPosition res;
        foreach (i; 0 .. _measuredText.length)
        {
            const int x0 = i > 0 ? _measuredTextWidths[i - 1] : 0;
            const int x1 = _measuredTextWidths[i];
            const int mx = (x0 + x1) / 2;
            if (pt.x <= mx)
            {
                res.pos = cast(int)i;
                return res;
            }
        }
        res.pos = cast(int)_measuredText.length;
        return res;
    }

    override protected void ensureCaretVisible(bool center = false)
    {
        //_scrollPos
        const Box b = textPosToClient(_caretPos);
        if (b.x < 0)
        {
            // scroll left
            _scrollPos.x -= -b.x + clientBox.width / 10;
            _scrollPos.x = max(_scrollPos.x, 0);
            invalidate();
        }
        else if (b.x >= clientBox.width - 10)
        {
            // scroll right
            _scrollPos.x += (b.x - clientBox.width) + _spaceWidth * 4;
            invalidate();
        }
        updateScrollBars();
        handleEditorStateChange();
    }

    protected dstring applyPasswordChar(dstring s)
    {
        if (!_passwordChar || s.length == 0)
            return s;
        dchar[] ss = s.dup;
        foreach (ref ch; ss)
            ch = _passwordChar;
        return cast(dstring)ss;
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (enterKeyPressed.assigned)
        {
            if (event.key == Key.enter && event.noModifiers)
            {
                if (event.action == KeyAction.keyDown)
                {
                    if (enterKeyPressed())
                        return true;
                }
            }
        }
        return super.onKeyEvent(event);
    }

    override protected void onMeasure(ref Boundaries bs)
    {
        measureVisibleText();
        _minSizeTester.style.tabSize = _content.tabSize;
        const sz = _minSizeTester.getSize() + Size(_leftPaneWidth, 0);
        bs.min += sz;
        bs.nat += sz;
    }

    override protected Size measureVisibleText()
    {
        FontRef font = font();
        _measuredText = applyPasswordChar(text);
        _measuredTextWidths.length = _measuredText.length;
        int charsMeasured = font.measureText(_measuredText, _measuredTextWidths, MAX_WIDTH_UNSPECIFIED, tabSize);
        _measuredTextSize.w = charsMeasured > 0 ? _measuredTextWidths[charsMeasured - 1] : 0;
        _measuredTextSize.h = font.height;
        return _measuredTextSize;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        clientBox = innerBox;

        if (_contentChanged)
        {
            measureVisibleText();
            _contentChanged = false;
        }
    }

    /// Override to custom highlight of line background
    protected void drawLineBackground(DrawBuf buf, Rect lineRect, Rect visibleRect)
    {
        if (!_selectionRange.empty)
        {
            // line inside selection
            const int start = textPosToClient(_selectionRange.start).x;
            const int end = textPosToClient(_selectionRange.end).x;
            Rect rc = lineRect;
            rc.left = start + clientBox.x;
            rc.right = end + clientBox.x;
            if (!rc.empty)
            {
                // draw selection rect for line
                buf.fillRect(rc, focused ? _selectionColorFocused : _selectionColorNormal);
            }
            if (_leftPaneWidth > 0)
            {
                Rect leftPaneRect = visibleRect;
                leftPaneRect.right = leftPaneRect.left;
                leftPaneRect.left -= _leftPaneWidth;
                drawLeftPane(buf, leftPaneRect, 0);
            }
        }
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        const b = innerBox;
        const saver = ClipRectSaver(buf, b, style.alpha);

        drawLineBackground(buf, Rect(clientBox), Rect(clientBox));

        if (_measuredText.length == 0)
        {
            // draw the placeholder when no text
            if (auto ph = _placeholder)
                ph.draw(buf, b.x - _scrollPos.x, b.y, b.w);
        }
        else
            font.drawText(buf, b.x - _scrollPos.x, b.y, _measuredText, style.textColor, tabSize);

        drawCaret(buf);
    }
}

/// Multiline editor
class EditBox : EditWidgetBase
{
    @property
    {
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

        protected int firstVisibleLine() const { return _firstVisibleLine; }

        final protected int linesOnScreen() const
        {
            return (clientBox.height + _lineHeight - 1) / _lineHeight;
        }
    }

    private
    {
        int _minFontSize = -1; // disable zooming
        int _maxFontSize = -1; // disable zooming
        bool _showWhiteSpaceMarks;

        int _firstVisibleLine;
        int _maxLineWidth;

        static struct VisibleLine
        {
            dstring str;
            int[] positions; /// Char positions
            int width; /// Width (in pixels)
            CustomCharProps[] highlight;
            CustomCharProps[] highlightBuf;

            size_t length() const
            {
                return str.length;
            }
        }
        /// Lines, visible in the client area
        VisibleLine[] _visibleLines;
    }

    this(dstring initialContent = null,
         ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        _content = new EditableContent(true); // multiline
        _content.contentChanged ~= &onContentChange;
        text = initialContent;
        _minSizeTester.str = "aaaaa\naaaaa"d;
        onThemeChanged();
    }

    ~this()
    {
        eliminate(_findPanel);
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        if (ptype == StyleProperty.fontSize)
            _needRewrap = true;
    }

    override void wordWrapRefresh()
    {
        _needRewrap = true;
    }

    override protected int lineCount() const
    {
        return _content.length;
    }

    override protected void updateMaxLineWidth()
    {
        // find max line width. TODO: optimize!!!
        int maxw;
        foreach (i; 0 .. _content.length)
        {
            dstring s = _content[i];
            maxw = max(maxw, calcLineWidth(s));
        }
        _maxLineWidth = maxw;
    }

    protected bool _extendRightScrollBound = true;
    // TODO: `_maxLineWidth + (_extendRightScrollBound ? clientBox.width / 16 : 0)` add to fullContentSize?

    override protected void updateHScrollBar() // TODO: bug as in ScrollArea.updateScrollBars when delete text
    {
        hscrollbar.data.setRange(0, _maxLineWidth + (_extendRightScrollBound ? clientBox.width / 16 : 0));
        hscrollbar.data.pageSize = clientBox.width;
        hscrollbar.data.position = _scrollPos.x;
    }

    override protected void updateVScrollBar()
    {
        vscrollbar.data.setRange(0, _content.length);
        vscrollbar.data.pageSize = linesOnScreen;
        vscrollbar.data.position = _firstVisibleLine;
    }

    override void onHScroll(ScrollEvent event)
    {
        if (event.action == ScrollAction.sliderMoved || event.action == ScrollAction.sliderReleased)
        {
            if (_scrollPos.x != event.position)
            {
                _scrollPos.x = event.position;
                invalidate();
            }
        }
        else if (event.action == ScrollAction.lineUp || event.action == ScrollAction.pageUp)
        {
            scroll(EditorScrollAction.left);
        }
        else if (event.action == ScrollAction.lineDown || event.action == ScrollAction.pageDown)
        {
            scroll(EditorScrollAction.right);
        }
    }

    override void onVScroll(ScrollEvent event)
    {
        if (event.action == ScrollAction.sliderMoved || event.action == ScrollAction.sliderReleased)
        {
            if (_firstVisibleLine != event.position)
            {
                _firstVisibleLine = event.position;
                measureVisibleText();
                invalidate();
            }
        }
        else if (event.action == ScrollAction.pageUp)
        {
            scroll(EditorScrollAction.pageUp);
        }
        else if (event.action == ScrollAction.pageDown)
        {
            scroll(EditorScrollAction.pageDown);
        }
        else if (event.action == ScrollAction.lineUp)
        {
            scroll(EditorScrollAction.lineUp);
        }
        else if (event.action == ScrollAction.lineDown)
        {
            scroll(EditorScrollAction.lineDown);
        }
    }

    override bool onKeyEvent(KeyEvent event)
    {
        const bool noOtherModifiers = !event.alteredBy(KeyMods.alt | KeyMods.meta);
        if (event.action == KeyAction.keyDown && noOtherModifiers)
        {
            const TextPosition oldCaretPos = _caretPos;

            const bool shiftPressed = event.alteredBy(KeyMods.shift);
            const bool controlPressed = event.alteredBy(KeyMods.control);
            if (event.key == Key.up)
            {
                if (!controlPressed)
                {
                    // move cursor one line up (with selection when Shift pressed)
                    if (_caretPos.line > 0 || wordWrap)
                    {
                        if (_wordWrap)
                        {
                            LineSpan curSpan = getSpan(_caretPos.line);
                            int curWrap = findWrapLine(_caretPos);
                            if (curWrap > 0)
                            {
                                _caretPos.pos -= curSpan.wrapPoints[curWrap - 1].wrapPos;
                            }
                            else
                            {
                                const int previousPos = _caretPos.pos;
                                curSpan = getSpan(_caretPos.line - 1);
                                curWrap = curSpan.len - 1;
                                if (curWrap > 0)
                                {
                                    const int accumulativePoint = curSpan.accumulation(curSpan.len - 1,
                                            LineSpan.WrapPointInfo.position);
                                    _caretPos.line--;
                                    _caretPos.pos = accumulativePoint + previousPos;
                                }
                                else
                                {
                                    _caretPos.line--;
                                }
                            }
                        }
                        else if (_caretPos.line > 0)
                            _caretPos.line--;
                        correctCaretPos();
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
                    return true;
                }
                else
                {
                    scroll(EditorScrollAction.lineUp);
                    return true;
                }
            }
            if (event.key == Key.down)
            {
                if (!controlPressed)
                {
                    // move cursor one line down (with selection when Shift pressed)
                    if (_caretPos.line < _content.length - 1)
                    {
                        if (_wordWrap)
                        {
                            const LineSpan curSpan = getSpan(_caretPos.line);
                            const int curWrap = findWrapLine(_caretPos);
                            if (curWrap < curSpan.len - 1)
                            {
                                const int previousPos = _caretPos.pos;
                                _caretPos.pos += curSpan.wrapPoints[curWrap].wrapPos;
                                correctCaretPos();
                                if (_caretPos.pos == previousPos)
                                {
                                    _caretPos.pos = 0;
                                    _caretPos.line++;
                                }
                            }
                            else if (curSpan.len > 1)
                            {
                                const int previousPos = _caretPos.pos;
                                const int previousAccumulatedPosition = curSpan.accumulation(curSpan.len - 1,
                                        LineSpan.WrapPointInfo.position);
                                _caretPos.line++;
                                _caretPos.pos = previousPos - previousAccumulatedPosition;
                            }
                            else
                            {
                                _caretPos.line++;
                            }
                        }
                        else
                        {
                            _caretPos.line++;
                        }
                        correctCaretPos();
                        updateSelectionAfterCursorMovement(oldCaretPos, shiftPressed);
                        ensureCaretVisible();
                    }
                    return true;
                }
                else
                {
                    scroll(EditorScrollAction.lineDown);
                    return true;
                }
            }
        }
        return super.onKeyEvent(event);
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.wheel)
        {
            cancelHoverTimer();
            const mods = event.keyMods;
            if (event.wheelDelta < 0)
            {
                if (mods == KeyMods.shift)
                {
                    scroll(EditorScrollAction.right);
                    return true;
                }
                if (mods == KeyMods.control)
                {
                    zoom(false);
                    return true;
                }
                scroll(EditorScrollAction.lineDown);
                return true;
            }
            else if (event.wheelDelta > 0)
            {
                if (mods == KeyMods.shift)
                {
                    scroll(EditorScrollAction.left);
                    return true;
                }
                if (mods == KeyMods.control)
                {
                    zoom(true);
                    return true;
                }
                scroll(EditorScrollAction.lineUp);
                return true;
            }
        }
        return super.onMouseEvent(event);
    }

    private bool _enableScrollAfterText = true;
    override protected void ensureCaretVisible(bool center = false)
    {
        _caretPos.line = clamp(_caretPos.line, 0, _content.length - 1);
        // fully visible lines
        const int visibleLines = linesOnScreen;
        int maxFirstVisibleLine = _content.length - 1;
        if (!_enableScrollAfterText)
            maxFirstVisibleLine = _content.length - visibleLines;
        maxFirstVisibleLine = max(maxFirstVisibleLine, 0);

        if (_caretPos.line < _firstVisibleLine)
        {
            _firstVisibleLine = _caretPos.line;
            if (center)
            {
                _firstVisibleLine -= visibleLines / 2;
                _firstVisibleLine = max(_firstVisibleLine, 0);
            }
            _firstVisibleLine = min(_firstVisibleLine, maxFirstVisibleLine);
            measureVisibleText();
            invalidate();
        }
        else if (_wordWrap && !(_firstVisibleLine > maxFirstVisibleLine))
        {
            // for wordwrap mode, move down sooner
            const int offsetLines = -1 * caretHeightOffset / _lineHeight;
            debug (editors)
                Log.d("offsetLines: ", offsetLines);
            if (_caretPos.line >= _firstVisibleLine + visibleLines - offsetLines)
            {
                _firstVisibleLine = _caretPos.line - visibleLines + 1 + offsetLines;
                if (center)
                    _firstVisibleLine += visibleLines / 2;
                _firstVisibleLine = min(_firstVisibleLine, maxFirstVisibleLine);
                _firstVisibleLine = max(_firstVisibleLine, 0);
                measureVisibleText();
                invalidate();
            }
        }
        else if (_caretPos.line >= _firstVisibleLine + visibleLines)
        {
            _firstVisibleLine = _caretPos.line - visibleLines + 1;
            if (center)
                _firstVisibleLine += visibleLines / 2;
            _firstVisibleLine = min(_firstVisibleLine, maxFirstVisibleLine);
            _firstVisibleLine = max(_firstVisibleLine, 0);
            measureVisibleText();
            invalidate();
        }
        else if (_firstVisibleLine > maxFirstVisibleLine)
        {
            _firstVisibleLine = maxFirstVisibleLine;
            _firstVisibleLine = max(_firstVisibleLine, 0);
            measureVisibleText();
            invalidate();
        }
        //_scrollPos
        const Box b = textPosToClient(_caretPos);
        if (b.x < 0)
        {
            // scroll left
            _scrollPos.x -= -b.x + clientBox.width / 4;
            _scrollPos.x = max(_scrollPos.x, 0);
            invalidate();
        }
        else if (b.x >= clientBox.width - 10)
        {
            // scroll right
            if (!_wordWrap)
                _scrollPos.x += (b.x - clientBox.width) + clientBox.width / 4;
            invalidate();
        }
        updateScrollBars();
        handleEditorStateChange();
    }

    override protected Box textPosToClient(TextPosition p) const
    {
        Box res;
        const int lineIndex = p.line - _firstVisibleLine;
        res.y = lineIndex * _lineHeight;
        res.h = _lineHeight;
        // if visible
        if (0 <= lineIndex && lineIndex < _visibleLines.length)
        {
            const VisibleLine* line = &_visibleLines[lineIndex];
            if (p.pos == 0)
                res.x = 0;
            else if (p.pos >= line.positions.length)
                res.x = line.width;
            else
                res.x = line.positions[p.pos - 1];
        }
        res.x -= _scrollPos.x;
        res.w = 1;
        return res;
    }

    override protected TextPosition clientToTextPos(Point pt) const
    {
        TextPosition res;
        pt.x += _scrollPos.x;
        const int lineIndex = max(pt.y / _lineHeight, 0);
        if (lineIndex < _visibleLines.length)
        {
            const VisibleLine* line = &_visibleLines[lineIndex];
            res.line = lineIndex + _firstVisibleLine;
            foreach (i; 0 .. line.length)
            {
                const int x0 = i > 0 ? line.positions[i - 1] : 0;
                const int x1 = line.positions[i];
                const int mx = (x0 + x1) / 2;
                if (pt.x <= mx)
                {
                    res.pos = cast(int)i;
                    return res;
                }
            }
            res.pos = cast(int)line.length;
        }
        else if (_visibleLines.length > 0)
        {
            res.line = _firstVisibleLine + cast(int)_visibleLines.length - 1;
            res.pos = cast(int)_visibleLines[$ - 1].length;
        }
        else
        {
            res.line = 0;
            res.pos = 0;
        }
        return res;
    }

    //===============================================================
    // Actions

    override protected void bindActions()
    {
        super.bindActions();

        ACTION_PAGE_UP.bind(this, { PageUp(false); });
        ACTION_PAGE_DOWN.bind(this, { PageDown(false); });
        ACTION_PAGE_BEGIN.bind(this, { PageBegin(false); });
        ACTION_PAGE_END.bind(this, { PageEnd(false); });
        ACTION_SELECT_PAGE_UP.bind(this, { PageUp(true); });
        ACTION_SELECT_PAGE_DOWN.bind(this, { PageDown(true); });
        ACTION_SELECT_PAGE_BEGIN.bind(this, { PageBegin(true); });
        ACTION_SELECT_PAGE_END.bind(this, { PageEnd(true); });

        ACTION_ZOOM_IN.bind(this, { zoom(true); });
        ACTION_ZOOM_OUT.bind(this, { zoom(false); });

        ACTION_ENTER.bind(this, &InsertNewLine);
        ACTION_ED_PREPEND_NEW_LINE.bind(this, &PrependNewLine);
        ACTION_ED_APPEND_NEW_LINE.bind(this, &AppendNewLine);
        ACTION_ED_DELETE_LINE.bind(this, &DeleteLine);

        ACTION_ED_TOGGLE_BOOKMARK.bind(this, {
            _content.lineIcons.toggleBookmark(_caretPos.line);
        });
        ACTION_ED_GOTO_NEXT_BOOKMARK.bind(this, {
            LineIcon mark = _content.lineIcons.findNext(LineIconType.bookmark,
                    _selectionRange.end.line, 1);
            if (mark)
                setCaretPos(mark.line, 0, true);
        });
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK.bind(this, {
            LineIcon mark = _content.lineIcons.findNext(LineIconType.bookmark,
                    _selectionRange.end.line, -1);
            if (mark)
                setCaretPos(mark.line, 0, true);
        });

        ACTION_ED_TOGGLE_LINE_COMMENT.bind(this, &ToggleLineComment);
        ACTION_ED_TOGGLE_BLOCK_COMMENT.bind(this, &ToggleBlockComment);

        ACTION_ED_FIND.bind(this, &openFindPanel);
        ACTION_ED_FIND_NEXT.bind(this, { findNext(false); });
        ACTION_ED_FIND_PREV.bind(this, { findNext(true); });
        ACTION_ED_REPLACE.bind(this, &openReplacePanel);
    }

    override protected void unbindActions()
    {
        super.unbindActions();

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

    override protected void updateActions()
    {
        super.updateActions();

        ACTION_ED_GOTO_NEXT_BOOKMARK.enabled = _content.lineIcons.hasBookmarks;
        ACTION_ED_GOTO_PREVIOUS_BOOKMARK.enabled = _content.lineIcons.hasBookmarks;

        {
            Action a = ACTION_ED_TOGGLE_LINE_COMMENT;
            a.visible = _content.syntaxSupport && _content.syntaxSupport.supportsToggleLineComment;
            if (a.visible)
                a.enabled = enabled && _content.syntaxSupport.canToggleLineComment(_selectionRange);
        }
        {
            Action a = ACTION_ED_TOGGLE_BLOCK_COMMENT;
            a.visible = _content.syntaxSupport && _content.syntaxSupport.supportsToggleBlockComment;
            if (a.visible)
                a.enabled = enabled && _content.syntaxSupport.canToggleBlockComment(_selectionRange);
        }

        ACTION_ED_REPLACE.enabled = !readOnly;
    }

    /// Zoom in when `zoomIn` is true and out vice versa
    void zoom(bool zoomIn)
    {
        const int dir = zoomIn ? 1 : -1;
        if (_minFontSize < _maxFontSize && _minFontSize > 0 && _maxFontSize > 0)
        {
            const int currentFontSize = style.fontSize;
            const int increment = currentFontSize >= 30 ? 2 : 1;
            int newFontSize = currentFontSize + increment * dir; //* 110 / 100;
            if (newFontSize > 30)
                newFontSize &= 0xFFFE;
            if (currentFontSize != newFontSize && newFontSize <= _maxFontSize && newFontSize >= _minFontSize)
            {
                debug (editors)
                    Log.i("Font size in editor ", id, " zoomed to ", newFontSize);
                style.fontSize = cast(ushort)newFontSize;
                measureVisibleText();
                updateScrollBars();
                invalidate();
            }
        }
    }

    protected void PageBegin(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        ensureCaretVisible();
        _caretPos.line = _firstVisibleLine;
        correctCaretPos();
        updateSelectionAfterCursorMovement(oldCaretPos, select);
    }
    protected void PageEnd(bool select)
    {
        const TextPosition oldCaretPos = _caretPos;
        ensureCaretVisible();
        const int fullLines = linesOnScreen;
        int newpos = _firstVisibleLine + fullLines - 1;
        if (newpos >= _content.length)
            newpos = _content.length - 1;
        _caretPos.line = newpos;
        correctCaretPos();
        updateSelectionAfterCursorMovement(oldCaretPos, select);
    }
    protected void PageUp(bool select)
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
    protected void PageDown(bool select)
    {
        TextPosition oldCaretPos = _caretPos;
        ensureCaretVisible();
        const int newpos = _firstVisibleLine + linesOnScreen;
        if (newpos >= _content.length)
        {
            _caretPos.line = _content.length - 1;
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

    protected void ToggleLineComment()
    {
        if (!readOnly && _content.syntaxSupport && _content.syntaxSupport.supportsToggleLineComment &&
                _content.syntaxSupport.canToggleLineComment(_selectionRange))
            _content.syntaxSupport.toggleLineComment(_selectionRange, this);
    }
    protected void ToggleBlockComment()
    {
        if (!readOnly && _content.syntaxSupport && _content.syntaxSupport.supportsToggleBlockComment &&
                _content.syntaxSupport.canToggleBlockComment(_selectionRange))
            _content.syntaxSupport.toggleBlockComment(_selectionRange, this);
    }

    protected void InsertNewLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            auto op = new EditOperation(EditAction.replace, _selectionRange, [""d, ""d]);
            _content.performOperation(op, this);
        }
    }
    protected void PrependNewLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            _caretPos.pos = 0;
            auto op = new EditOperation(EditAction.replace, _selectionRange, [""d, ""d]);
            _content.performOperation(op, this);
        }
    }
    protected void AppendNewLine()
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
    protected void DeleteLine()
    {
        if (!readOnly)
        {
            correctCaretPos();
            auto op = new EditOperation(EditAction.replace, _content.lineRange(_caretPos.line), [""d]);
            _content.performOperation(op, this);
        }
    }

    //===============================================================
    // Scrolling

    protected enum EditorScrollAction
    {
        left,
        right,
        lineUp,
        lineDown,
        pageUp,
        pageDown,
    }

    /// Scroll somewhere (not changing cursor)
    protected void scroll(EditorScrollAction where)
    {
        const int oldScrollPosX = _scrollPos.x;
        const int oldFirstVisibleLine = _firstVisibleLine;
        final switch (where) with (EditorScrollAction)
        {
        case left:
            _scrollPos.x = max(_scrollPos.x - _spaceWidth * 4, 0);
            break;
        case right:
            _scrollPos.x = min(_scrollPos.x + _spaceWidth * 4, _maxLineWidth - clientBox.width);
            break;
        case lineUp:
            _firstVisibleLine = max(_firstVisibleLine - 3, 0);
            break;
        case lineDown:
            _firstVisibleLine = max(min(_firstVisibleLine + 3, _content.length - linesOnScreen), 0);
            break;
        case pageUp:
            _firstVisibleLine = max(_firstVisibleLine - linesOnScreen * 3 / 4, 0);
            break;
        case pageDown:
            const int screen = linesOnScreen;
            _firstVisibleLine = max(min(_firstVisibleLine + screen * 3 / 4, _content.length - screen), 0);
            break;
        }
        if (oldScrollPosX != _scrollPos.x)
        {
            updateScrollBars();
            invalidate();
        }
        if (oldFirstVisibleLine != _firstVisibleLine)
        {
            measureVisibleText();
            updateScrollBars();
            invalidate();
        }
    }

    //===============================================================

    protected void highlightTextPattern(DrawBuf buf, int lineIndex, Rect lineRect, Rect visibleRect)
    {
        dstring pattern = _textToHighlight;
        TextSearchOptions options = _textToHighlightOptions;
        if (!pattern.length)
        {
            // support highlighting selection text - if whole word is selected
            if (_selectionRange.empty || !_selectionRange.singleLine)
                return;
            if (_selectionRange.start.line >= _content.length)
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
                const r = TextRange(TextPosition(lineIndex, cast(int)start),
                        TextPosition(lineIndex, cast(int)(start + pattern.length)));
                const color = r.isInsideOrNext(caretPos) ? _searchHighlightColorCurrent : _searchHighlightColorOther;
                highlightLineRange(buf, lineRect, color, r);
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
        foreach (i; 0 .. _content.length)
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
                    const r = TextRange(TextPosition(i, cast(int)start), TextPosition(i,
                            cast(int)(start + pattern.length)));
                    res ~= r;
                }
                start += _textToHighlight.length;
            }
        }
        return res;
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

    protected void highlightLineRange(DrawBuf buf, Rect lineRect, Color color, TextRange r)
    {
        const Box start = textPosToClient(r.start);
        const Box end = textPosToClient(r.end);
        Rect rc = lineRect;
        rc.left = clientBox.x + start.x;
        rc.right = clientBox.x + end.x + end.w;
        if (_wordWrap && !rc.empty)
        {
            wordWrapFillRect(buf, r.start.line, rc, color);
        }
        else if (!rc.empty)
        {
            // draw selection rect for matching bracket
            buf.fillRect(rc, color);
        }
    }

    /// Used in place of directly calling buf.fillRect in word wrap mode
    void wordWrapFillRect(DrawBuf buf, int line, Rect lineToDivide, Color color)
    {
        Rect rc = lineToDivide;
        auto limitNumber = (int num, int limit) => num > limit ? limit : num;
        const LineSpan curSpan = getSpan(line);
        const yOffset = _lineHeight * (wrapsUpTo(line));
        rc.offset(0, yOffset);
        Rect[] wrappedSelection;
        wrappedSelection.length = curSpan.len;
        foreach (i, wrapLineRect; wrappedSelection)
        {
            const startingDifference = rc.left - clientBox.x;
            wrapLineRect = rc;
            wrapLineRect.offset(-1 * curSpan.accumulation(cast(int)i, LineSpan.WrapPointInfo.width),
                    cast(int)i * _lineHeight);
            wrapLineRect.right = limitNumber(wrapLineRect.right,
                    (rc.left + curSpan.wrapPoints[i].wrapWidth) - startingDifference);
            buf.fillRect(wrapLineRect, color);
        }
    }

    override Size fullContentSize() const
    {
        return Size(_maxLineWidth, _lineHeight * _content.length);
    }

    override protected void onMeasure(ref Boundaries bs)
    {
        updateMaxLineWidth();
        _minSizeTester.style.tabSize = _content.tabSize;
        const sz = _minSizeTester.getSize() + Size(_leftPaneWidth, 0);
        bs.min += sz;
        bs.nat += sz;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        if (geom != box)
            _contentChanged = true;

        Box content = geom;
        if (_findPanel && _findPanel.visibility != Visibility.gone)
        {
            _findPanel.measure();
            Size sz = _findPanel.natSize;
            _findPanel.layout(Box(geom.x, geom.y + geom.h - sz.h, geom.w, sz.h));
            content.h -= sz.h;
        }

        super.layout(content);
        if (_contentChanged)
        {
            measureVisibleText();
            _needRewrap = true;
            _contentChanged = false;
        }

        if (auto ph = _placeholder)
            ph.wrap(clientBox.w);

        box = geom;
    }

    override protected Size measureVisibleText()
    {
        Font font = font();
        _lineHeight = font.height;

        int numVisibleLines = linesOnScreen;
        if (_firstVisibleLine >= _content.length)
        {
            _firstVisibleLine = max(_content.length - numVisibleLines + 1, 0);
            _caretPos.line = _content.length - 1;
            _caretPos.pos = 0;
        }
        numVisibleLines = max(numVisibleLines, 1);
        if (_firstVisibleLine + numVisibleLines > _content.length)
            numVisibleLines = max(_content.length - _firstVisibleLine, 1);

        _visibleLines.length = numVisibleLines;

        Size sz;
        foreach (i, ref line; _visibleLines)
        {
            line.str = _content[_firstVisibleLine + cast(int)i];
            const len = line.str.length;
            if (line.positions.length < len)
                line.positions.length = len;
            if (line.highlightBuf.length < len)
                line.highlightBuf.length = len;
            line.highlight = handleCustomLineHighlight(_firstVisibleLine + cast(int)i, line.str, line.highlightBuf);
            const int charsMeasured = font.measureText(line.str, line.positions, int.max, tabSize);
            line.width = charsMeasured > 0 ? line.positions[charsMeasured - 1] : 0;
            // width - max from visible lines
            sz.w = max(sz.w, line.width);
        }
        sz.w = _maxLineWidth;
        sz.h = _lineHeight * _content.length; // height - for all lines
        return sz;
    }

    /// Override to custom highlight of line background
    protected void drawLineBackground(DrawBuf buf, int lineIndex, Rect lineRect, Rect visibleRect)
    {
        // highlight odd lines
        //if ((lineIndex & 1))
        //    buf.fillRect(visibleRect, 0xF4808080);

        if (!_selectionRange.empty && _selectionRange.start.line <= lineIndex && _selectionRange.end.line >= lineIndex)
        {
            // line inside selection
            const int selStart = textPosToClient(_selectionRange.start).x;
            const int selEnd = textPosToClient(_selectionRange.end).x;
            const int startx = lineIndex == _selectionRange.start.line ? selStart + clientBox.x : lineRect.left;
            const int endx = lineIndex == _selectionRange.end.line ? selEnd + clientBox.x
                : lineRect.right + _spaceWidth;
            Rect rc = lineRect;
            rc.left = startx;
            rc.right = endx;
            if (!rc.empty && _wordWrap)
            {
                wordWrapFillRect(buf, lineIndex, rc, focused ? _selectionColorFocused : _selectionColorNormal);
            }
            else if (!rc.empty)
            {
                // draw selection rect for line
                buf.fillRect(rc, focused ? _selectionColorFocused : _selectionColorNormal);
            }
        }

        highlightTextPattern(buf, lineIndex, lineRect, visibleRect);

        if (_matchingBraces.start.line == lineIndex)
        {
            const r = TextRange(_matchingBraces.start, _matchingBraces.start.offset(1));
            highlightLineRange(buf, lineRect, _matchingBracketHighlightColor, r);
        }
        if (_matchingBraces.end.line == lineIndex)
        {
            const r = TextRange(_matchingBraces.end, _matchingBraces.end.offset(1));
            highlightLineRange(buf, lineRect, _matchingBracketHighlightColor, r);
        }

        // frame around current line
        if (focused && lineIndex == _caretPos.line && _selectionRange.singleLine &&
                _selectionRange.start.line == _caretPos.line)
        {
            //TODO: Figure out why a little slow to catch up
            if (_wordWrap)
                visibleRect.offset(0, -caretHeightOffset);
            buf.drawFrame(visibleRect, Color(0xA0808080), Insets(1));
        }
    }

    override protected void drawExtendedArea(DrawBuf buf)
    {
        if (_leftPaneWidth <= 0)
            return;

        const cb = clientBox;
        Box lineBox = Box(cb.x - _leftPaneWidth, cb.y, _leftPaneWidth, _lineHeight);
        int i = _firstVisibleLine;
        const int lc = lineCount;
        while (true)
        {
            if (lineBox.y > cb.y + cb.h)
                break;
            drawLeftPane(buf, Rect(lineBox), i < lc ? i : -1);
            lineBox.y += _lineHeight;
            if (_wordWrap)
            {
                int currentWrap = 1;
                while (true)
                {
                    LineSpan curSpan = getSpan(i);
                    if (currentWrap > curSpan.len - 1)
                        break;
                    if (lineBox.y > cb.y + cb.h)
                        break;
                    drawLeftPane(buf, Rect(lineBox), -1);
                    lineBox.y += _lineHeight;

                    currentWrap++;
                }
            }
            i++;
        }
    }

    private CustomCharProps[ubyte] _tokenHighlightColors;

    /// Set highlight options for particular token category
    void setTokenHighlightColor(ubyte tokenCategory, Color color, bool underline = false, bool strikeThrough = false)
    {
        _tokenHighlightColors[tokenCategory] = CustomCharProps(color, underline, strikeThrough);
    }
    /// Clear highlight colors
    void clearTokenHighlightColors()
    {
        destroy(_tokenHighlightColors);
    }

    /**
        Custom text color and style highlight (using text highlight) support.

        Return `null` if no syntax highlight required for line.
     */
    protected CustomCharProps[] handleCustomLineHighlight(int line, dstring txt, ref CustomCharProps[] buf)
    {
        if (!_tokenHighlightColors)
            return null; // no highlight colors set
        TokenPropString tokenProps = _content.lineTokenProps(line);
        if (tokenProps.length > 0)
        {
            bool hasNonzeroTokens;
            foreach (t; tokenProps)
                if (t)
                {
                    hasNonzeroTokens = true;
                    break;
                }
            if (!hasNonzeroTokens)
                return null; // all characters are of unknown token type (or white space)
            if (buf.length < tokenProps.length)
                buf.length = tokenProps.length;
            CustomCharProps[] colors = buf[0 .. tokenProps.length]; //new CustomCharProps[tokenProps.length];
            for (int i = 0; i < tokenProps.length; i++)
            {
                const ubyte p = tokenProps[i];
                if (p in _tokenHighlightColors)
                    colors[i] = _tokenHighlightColors[p];
                else if ((p & TOKEN_CATEGORY_MASK) in _tokenHighlightColors)
                    colors[i] = _tokenHighlightColors[(p & TOKEN_CATEGORY_MASK)];
                else
                    colors[i].color = style.textColor;
                if (colors[i].color.isFullyTransparent)
                    colors[i].color = style.textColor;
            }
            return colors;
        }
        return null;
    }

    private TextRange _matchingBraces;

    /// Find max tab mark column position for line
    protected int findMaxTabMarkColumn(int lineIndex) const
    {
        if (lineIndex < 0 || lineIndex >= content.length)
            return -1;
        int maxSpace = -1;
        auto space = content.getLineWhiteSpace(lineIndex);
        maxSpace = space.firstNonSpaceColumn;
        if (maxSpace >= 0)
            return maxSpace;
        foreach_reverse (i; 0 .. lineIndex)
        {
            space = content.getLineWhiteSpace(i);
            if (!space.empty)
            {
                maxSpace = space.firstNonSpaceColumn;
                break;
            }
        }
        foreach (i; lineIndex + 1 .. content.length)
        {
            space = content.getLineWhiteSpace(i);
            if (!space.empty)
            {
                if (maxSpace < 0 || maxSpace < space.firstNonSpaceColumn)
                    maxSpace = space.firstNonSpaceColumn;
                break;
            }
        }
        return maxSpace;
    }

    void drawTabPositionMarks(DrawBuf buf, ref FontRef font, int lineIndex, Rect lineRect)
    {
        const int maxCol = findMaxTabMarkColumn(lineIndex);
        if (maxCol > 0)
        {
            const int spaceWidth = font.charWidth(' ');
            Rect rc = lineRect;
            Color color = style.textColor;
            color.addAlpha(0xC0);
            for (int i = 0; i < maxCol; i += tabSize)
            {
                rc.left = lineRect.left + i * spaceWidth;
                rc.right = rc.left + 1;
                buf.fillRectPattern(rc, color, PatternType.dotted);
            }
        }
    }

    void drawWhiteSpaceMarks(DrawBuf buf, ref FontRef font, dstring txt, TabSize tabSize, Rect lineRect, Rect visibleRect)
    {
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
        const bool spacesOnly = txt.length > 0 && firstNonSpace < 0;
        if (firstNonSpace <= 0 && lastNonSpace >= txt.length && !hasTabs && !spacesOnly)
            return;
        Color color = style.textColor;
        color.addAlpha(0xC0);
        static int[] textSizeBuffer;
        const int charsMeasured = font.measureText(txt, textSizeBuffer, MAX_WIDTH_UNSPECIFIED, tabSize);
        for (int i = 0; i < txt.length && i < charsMeasured; i++)
        {
            const ch = txt[i];
            const bool outsideText = (i < firstNonSpace || i >= lastNonSpace || spacesOnly);
            if ((ch == ' ' && outsideText) || ch == '\t')
            {
                Rect rc = lineRect;
                rc.left = lineRect.left + (i > 0 ? textSizeBuffer[i - 1] : 0);
                rc.right = lineRect.left + textSizeBuffer[i];
                const int h = rc.height;
                if (rc.intersects(visibleRect))
                {
                    // draw space mark
                    if (ch == ' ')
                    {
                        // space
                        int sz = h / 6;
                        if (sz < 1)
                            sz = 1;
                        rc.top += h / 2 - sz / 2;
                        rc.bottom = rc.top + sz;
                        rc.left += rc.width / 2 - sz / 2;
                        rc.right = rc.left + sz;
                        buf.fillRect(rc, color);
                    }
                    else if (ch == '\t')
                    {
                        // tab
                        Point p1 = Point(rc.left + 1, rc.top + h / 2);
                        Point p2 = p1;
                        p2.x = rc.right - 1;
                        int sz = h / 4;
                        if (sz < 2)
                            sz = 2;
                        if (sz > p2.x - p1.x)
                            sz = p2.x - p1.x;
                        buf.drawLine(p1, p2, color);
                        buf.drawLine(p2, Point(p2.x - sz, p2.y - sz), color);
                        buf.drawLine(p2, Point(p2.x - sz, p2.y + sz), color);
                    }
                }
            }
        }
    }

    /// Clear _span
    void resetVisibleSpans()
    {
        //TODO: Don't erase spans which have not been modified, cache them
        _span = [];
    }

    private bool _needRewrap = true;
    private int lastStartingLine;

    override protected void drawClient(DrawBuf buf)
    {
        // update matched braces
        if (!content.findMatchedBraces(_caretPos, _matchingBraces))
        {
            _matchingBraces.start.line = -1;
            _matchingBraces.end.line = -1;
        }

        const b = clientBox;

        if (_contentChanged)
            _needRewrap = true;
        if (lastStartingLine != _firstVisibleLine)
        {
            _needRewrap = true;
            lastStartingLine = _firstVisibleLine;
        }
        if (b.width <= 0 && _wordWrap)
        {
            //Prevent drawClient from getting stuck in loop
            return;
        }
        bool doRewrap;
        if (_needRewrap && _wordWrap)
        {
            resetVisibleSpans();
            _needRewrap = false;
            doRewrap = true;
        }

        if (auto ph = _placeholder)
        {
            // draw the placeholder when no text
            const ls = _content.lines;
            if (ls.length == 0 || (ls.length == 1 && ls[0].length == 0))
                ph.draw(buf, b.x - _scrollPos.x, b.y, b.w);
        }

        FontRef font = font();
        int previousWraps;
        foreach (i; 0 .. cast(int)_visibleLines.length)
        {
            const dstring txt = _visibleLines[i].str;
            Rect lineRect;
            lineRect.left = b.x - _scrollPos.x;
            lineRect.right = lineRect.left + calcLineWidth(_content[_firstVisibleLine + i]);
            lineRect.top = b.y + i * _lineHeight;
            lineRect.bottom = lineRect.top + _lineHeight;
            Rect visibleRect = lineRect;
            visibleRect.left = b.x;
            visibleRect.right = b.x + b.w;
            drawLineBackground(buf, _firstVisibleLine + i, lineRect, visibleRect);
            if (_showTabPositionMarks)
                drawTabPositionMarks(buf, font, _firstVisibleLine + i, lineRect);
            if (!txt.length && !_wordWrap)
                continue;
            if (_showWhiteSpaceMarks)
            {
                Rect whiteSpaceRc = lineRect;
                Rect whiteSpaceRcVisible = visibleRect;
                for (int z; z < previousWraps; z++)
                {
                    whiteSpaceRc.offset(0, _lineHeight);
                    whiteSpaceRcVisible.offset(0, _lineHeight);
                }
                drawWhiteSpaceMarks(buf, font, txt, _content.tabSize, whiteSpaceRc, whiteSpaceRcVisible);
            }
            if (_leftPaneWidth > 0)
            {
                Rect leftPaneRect = visibleRect;
                leftPaneRect.right = leftPaneRect.left;
                leftPaneRect.left -= _leftPaneWidth;
                drawLeftPane(buf, leftPaneRect, 0);
            }
            if (txt.length > 0 || _wordWrap)
            {
                CustomCharProps[] highlight = _visibleLines[i].highlight;
                if (_wordWrap)
                {
                    dstring[] wrappedLine;
                    if (doRewrap)
                        wrappedLine = wrapLine(txt, _firstVisibleLine + i);
                    else if (i < _span.length)
                        wrappedLine = _span[i].wrappedContent;
                    int accumulativeLength;
                    CustomCharProps[] wrapProps;
                    foreach (q, curWrap; wrappedLine)
                    {
                        const int lineOffset = cast(int)q + i + wrapsUpTo(i + _firstVisibleLine);
                        const x = b.x - _scrollPos.x;
                        const y = b.y + lineOffset * _lineHeight;
                        if (highlight)
                        {
                            wrapProps = highlight[accumulativeLength .. $];
                            accumulativeLength += curWrap.length;
                            font.drawColoredText(buf, x, y, curWrap, wrapProps, tabSize);
                        }
                        else
                            font.drawText(buf, x, y, curWrap, style.textColor, tabSize);
                    }
                    previousWraps += cast(int)wrappedLine.length - 1;
                }
                else
                {
                    const x = b.x - _scrollPos.x;
                    const y = b.y + i * _lineHeight;
                    if (highlight)
                        font.drawColoredText(buf, x, y, txt, highlight, tabSize);
                    else
                        font.drawText(buf, x, y, txt, style.textColor, tabSize);
                }
            }
        }

        drawCaret(buf);
    }

    private FindPanel _findPanel;

    dstring selectionText(bool singleLineOnly = false) const
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

    protected void findNext(bool backward)
    {
        createFindPanel(false, false);
        _findPanel.findNext(backward);
        // don't change replace mode
    }

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
        requestLayout();
        return res;
    }

    /// Close find panel
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
                requestLayout();
            }
        }
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;
        super.onDraw(buf);
        if (_findPanel && _findPanel.visibility == Visibility.visible)
        {
            _findPanel.onDraw(buf);
        }
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
        enabled = false;
        // allow font zoom with Ctrl + MouseWheel
        minFontSize = 8;
        maxFontSize = 36;
        onThemeChanged();
    }

    /// Append lines to the end of text
    void appendText(dstring text)
    {
        import std.array : split;

        if (text.length == 0)
            return;
        dstring[] lines = text.split("\n");
        //lines ~= ""d; // append new line after last line
        content.appendLines(lines);
        if (_maxLines > 0 && lineCount > _maxLines)
        {
            TextRange range;
            range.end.line = lineCount - _maxLines;
            auto op = new EditOperation(EditAction.replace, range, [""d]);
            _content.performOperation(op, this);
            _contentChanged = true;
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
        if (_content.length == 0)
            return res;
        if (_content.lineLength(_content.length - 1) == 0 && _content.length > 1)
            res.line = _content.length - 2;
        else
            res.line = _content.length - 1;
        return res;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        if (_scrollLock)
        {
            measureVisibleText();
            _caretPos = lastLineBegin();
            ensureCaretVisible();
        }
    }
}

class FindPanel : Row
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
                childByID("rowReplace").visibility = newMode ? Visibility.visible : Visibility.gone;
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
        EditLine _edFind;
        EditLine _edReplace;
        Button _cbCaseSensitive;
        Button _cbWholeWords;
        CheckBox _cbSelection;
        Button _btnFindNext;
        Button _btnFindPrev;
        bool _replaceMode;
    }

    this(EditBox editor, bool selectionOnly, bool replace, dstring initialText = ""d)
    {
        _editor = editor;
        _replaceMode = replace;

        auto main = new Column;
            Row rowFind = new Row;
                _edFind = new EditLine(initialText);
                _btnFindNext = new Button("Find next");
                _btnFindPrev = new Button("Find previous");
                Row findSettings = new Row;
                    _cbCaseSensitive = new Button(null, "find_case_sensitive");
                    _cbWholeWords = new Button(null, "find_whole_words");
                    _cbSelection = new CheckBox("Sel");
            Row rowReplace = new Row;
                _edReplace = new EditLine(initialText);
                auto btnReplace = new Button("Replace");
                auto btnReplaceAndFind = new Button("Replace and find");
                auto btnReplaceAll = new Button("Replace all");
        auto closeBtn = new Button(null, "close");

        with (main) {
            add(rowFind, rowReplace);
            with (rowFind) {
                add(_edFind).setFillWidth(true);
                add(_btnFindNext, _btnFindPrev, findSettings);
                with (findSettings) {
                    add(_cbCaseSensitive, _cbWholeWords, _cbSelection);
                    with (_cbCaseSensitive) {
                        allowsToggle = true;
                        tooltipText = "Case sensitive";
                    }
                    with (_cbWholeWords) {
                        allowsToggle = true;
                        tooltipText = "Whole words";
                    }
                }
            }
            with (rowReplace) {
                id = "rowReplace";
                add(_edReplace).setFillWidth(true);
                add(btnReplace, btnReplaceAndFind, btnReplaceAll);
            }
        }
        add(main).setFillWidth(true);
        add(closeBtn).setFillHeight(false);

        _edFind.enterKeyPressed ~= { findNext(_backDirection); return true; };
        _edFind.contentChanged ~= &onFindTextChange;

        _btnFindNext.clicked ~= { findNext(false); };
        _btnFindPrev.clicked ~= { findNext(true); };

        _cbCaseSensitive.toggled ~= &onCaseSensitiveToggling;
        _cbWholeWords.toggled ~= &onCaseSensitiveToggling;
        _cbSelection.toggled ~= &onCaseSensitiveToggling;

        if (!replace)
            rowReplace.visibility = Visibility.gone;

        btnReplace.clicked ~= { replaceOne(); };
        btnReplaceAndFind.clicked ~= {
            replaceOne();
            findNext(_backDirection);
        };
        btnReplaceAll.clicked ~= { replaceAll(); };

        closeBtn.clicked ~= &close;

        focusGroup = true;

        setDirection(false);
        updateHighlight();
    }

    void activate()
    {
        _edFind.setFocus();
        const currentText = _edFind.text;
        debug (editors)
            Log.d("activate.currentText=", currentText);
        _edFind.setCaretPos(0, cast(int)currentText.length, true);
    }

    void close()
    {
        _editor.setTextToHighlight(null, TextSearchOptions.none);
        _editor.closeFindPanel();
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (event.key == Key.tab)
            return super.onKeyEvent(event);
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
            _editor.selectionRange = TextRange(pos, TextPosition(pos.line, pos.pos + cast(int)currentText.length));
            _editor.ensureCaretVisible();
            //_editor.setCaretPos(pos.line, pos.pos, true);
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
            _editor.selectionRange = TextRange(pos, TextPosition(pos.line, pos.pos + cast(int)currentText.length));
            _editor.replaceSelectionText(newText);
            _editor.selectionRange = TextRange(pos, TextPosition(pos.line, pos.pos + cast(int)newText.length));
            _editor.ensureCaretVisible();
            //_editor.setCaretPos(pos.line, pos.pos, true);
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

    void onFindTextChange(EditableContent source)
    {
        debug (editors)
            Log.d("onFindTextChange");
        updateHighlight();
    }

    void onCaseSensitiveToggling(bool checkValue)
    {
        updateHighlight();
    }
}
