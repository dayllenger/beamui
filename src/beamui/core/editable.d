/**
Editable text content and related data structures.

Synopsis:
---
import beamui.core.editable;
---

Copyright: Vadim Lopatin 2014-2017, James Johnson 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.editable;

import beamui.core.collections;
import beamui.core.functions;
import beamui.core.linestream;
import beamui.core.logger;
import beamui.core.parseutils;
import beamui.core.signals;
import beamui.core.streams;

immutable dchar EOL = '\n';

const ubyte TOKEN_CATEGORY_SHIFT = 4;
const ubyte TOKEN_CATEGORY_MASK = 0xF0; // token category 0..15
const ubyte TOKEN_SUBCATEGORY_MASK = 0x0F; // token subcategory 0..15
const ubyte TOKEN_UNKNOWN = 0;

/*
Bit mask:
7654 3210
cccc ssss
|    |
|    \ ssss = token subcategory
|
\ cccc = token category

*/
/// Token category for syntax highlight
enum TokenCategory : ubyte
{
    WhiteSpace = (0 << TOKEN_CATEGORY_SHIFT),
    WhiteSpace_Space = (0 << TOKEN_CATEGORY_SHIFT) | 1,
    WhiteSpace_Tab = (0 << TOKEN_CATEGORY_SHIFT) | 2,

    Comment = (1 << TOKEN_CATEGORY_SHIFT),
    Comment_SingleLine = (1 << TOKEN_CATEGORY_SHIFT) | 1, // single line comment
    Comment_SingleLineDoc = (1 << TOKEN_CATEGORY_SHIFT) | 2, // documentation in single line comment
    Comment_MultyLine = (1 << TOKEN_CATEGORY_SHIFT) | 3, // multiline coment
    Comment_MultyLineDoc = (1 << TOKEN_CATEGORY_SHIFT) | 4, // documentation in multiline comment
    Comment_Documentation = (1 << TOKEN_CATEGORY_SHIFT) | 5, // documentation comment

    Identifier = (2 << TOKEN_CATEGORY_SHIFT), // identifier (exact subcategory is unknown)
    Identifier_Class = (2 << TOKEN_CATEGORY_SHIFT) | 1, // class name
    Identifier_Struct = (2 << TOKEN_CATEGORY_SHIFT) | 2, // struct name
    Identifier_Local = (2 << TOKEN_CATEGORY_SHIFT) | 3, // local variable
    Identifier_Member = (2 << TOKEN_CATEGORY_SHIFT) | 4, // struct or class member
    Identifier_Deprecated = (2 << TOKEN_CATEGORY_SHIFT) | 15, // usage of this identifier is deprecated
    /// String literal
    String = (3 << TOKEN_CATEGORY_SHIFT),
    /// Character literal
    Character = (4 << TOKEN_CATEGORY_SHIFT),
    /// Integer literal
    Integer = (5 << TOKEN_CATEGORY_SHIFT),
    /// Floating point number literal
    Float = (6 << TOKEN_CATEGORY_SHIFT),
    /// Keyword
    Keyword = (7 << TOKEN_CATEGORY_SHIFT),
    /// Operator
    Op = (8 << TOKEN_CATEGORY_SHIFT),
    // add more here
    //....
    /// Error - unparsed character sequence
    Error = (15 << TOKEN_CATEGORY_SHIFT),
    /// Invalid token - generic
    Error_InvalidToken = (15 << TOKEN_CATEGORY_SHIFT) | 1,
    /// Invalid number token - error occured while parsing number
    Error_InvalidNumber = (15 << TOKEN_CATEGORY_SHIFT) | 2,
    /// Invalid string token - error occured while parsing string
    Error_InvalidString = (15 << TOKEN_CATEGORY_SHIFT) | 3,
    /// Invalid identifier token - error occured while parsing identifier
    Error_InvalidIdentifier = (15 << TOKEN_CATEGORY_SHIFT) | 4,
    /// Invalid comment token - error occured while parsing comment
    Error_InvalidComment = (15 << TOKEN_CATEGORY_SHIFT) | 7,
    /// Invalid comment token - error occured while parsing comment
    Error_InvalidOp = (15 << TOKEN_CATEGORY_SHIFT) | 8,
}

/// Extracts token category, clearing subcategory
ubyte tokenCategory(ubyte t)
{
    return t & 0xF0;
}

/// Split dstring by delimiters
dstring[] splitDString(dstring source, dchar delimiter = EOL)
{
    int start = 0;
    dstring[] res;
    for (int i = 0; i <= source.length; i++)
    {
        if (i == source.length || source[i] == delimiter)
        {
            if (i >= start)
            {
                dchar prevchar = i > 1 && i > start + 1 ? source[i - 1] : 0;
                int end = i;
                if (delimiter == EOL && prevchar == '\r') // windows CR/LF
                    end--;
                dstring line = i > start ? cast(dstring)(source[start .. end].dup) : ""d;
                res ~= line;
            }
            start = i + 1;
        }
    }
    return res;
}

version (Windows)
{
    immutable dstring SYSTEM_DEFAULT_EOL = "\r\n";
}
else
{
    immutable dstring SYSTEM_DEFAULT_EOL = "\n";
}

/// Concat strings from array using delimiter
dstring concatDStrings(dstring[] lines, dstring delimiter = SYSTEM_DEFAULT_EOL)
{
    dchar[] buf;
    foreach (i, line; lines)
    {
        if (i > 0)
            buf ~= delimiter;
        buf ~= line;
    }
    return cast(dstring)buf;
}

/// Replace end of lines with spaces
dstring replaceEOLsWithSpaces(dstring source)
{
    dchar[] buf;
    dchar lastch;
    foreach (ch; source)
    {
        if (ch == '\r')
        {
            buf ~= ' ';
        }
        else if (ch == '\n')
        {
            if (lastch != '\r')
                buf ~= ' ';
        }
        else
        {
            buf ~= ch;
        }
        lastch = ch;
    }
    return cast(dstring)buf;
}

/// Text content position
struct TextPosition
{
    /// Line number, zero based
    int line;
    /// Character position in line (0 == before first character)
    int pos;

    /// Compares two positions
    int opCmp(ref const TextPosition v) const
    {
        if (line < v.line)
            return -1;
        if (line > v.line)
            return 1;
        if (pos < v.pos)
            return -1;
        if (pos > v.pos)
            return 1;
        return 0;
    }

    bool opEquals(ref inout TextPosition v) inout
    {
        return line == v.line && pos == v.pos;
    }

    string toString() const
    {
        return to!string(line) ~ ":" ~ to!string(pos);
    }

    /// Adds deltaPos to position and returns result
    TextPosition offset(int deltaPos)
    {
        return TextPosition(line, pos + deltaPos);
    }
}

/// Text content range
struct TextRange
{
    TextPosition start;
    TextPosition end;

    bool intersects(const ref TextRange v) const
    {
        if (start >= v.end)
            return false;
        if (end <= v.start)
            return false;
        return true;
    }
    /// Returns true if position is inside this range
    bool isInside(TextPosition p) const
    {
        return start <= p && end > p;
    }
    /// Returns true if position is inside this range or right after this range
    bool isInsideOrNext(TextPosition p) const
    {
        return start <= p && end >= p;
    }
    /// Returns true if range is empty
    @property bool empty() const
    {
        return end <= start;
    }
    /// Returns true if start and end located at the same line
    @property bool singleLine() const
    {
        return end.line == start.line;
    }
    /// Returns count of lines in range
    @property int lines() const
    {
        return end.line - start.line + 1;
    }

    string toString() const
    {
        return "[" ~ start.toString ~ ":" ~ end.toString ~ "]";
    }
}

/// Action performed with editable contents
enum EditAction
{
    /// Insert content into specified position (range.start)
    //insert,
    /// Delete content in range
    //delete,
    /// Replace range content with new content
    replace,

    /// Replace whole content
    replaceContent,
    /// Saved content
    saveContent,
}

/// Values for editable line state
enum EditStateMark : ubyte
{
    /// Content is unchanged - e.g. after loading from file
    unchanged,
    /// Content is changed and not yet saved
    changed,
    /// Content is changed, but already saved to file
    saved,
}

/// Edit operation details for EditableContent
class EditOperation
{
    private
    {
        EditAction _action;
        TextRange _range;
        TextRange _newRange;
        dstring[] _content;
        EditStateMark[] _oldEditMarks;
        dstring[] _oldContent;
    }

    this(EditAction action)
    {
        _action = action;
    }

    this(EditAction action, TextPosition pos, dstring text)
    {
        this(action, TextRange(pos, pos), text);
    }

    this(EditAction action, TextRange range, dstring text)
    {
        _action = action;
        _range = range;
        _content.length = 1;
        _content[0] = text.dup;
    }

    this(EditAction action, TextRange range, dstring[] text)
    {
        _action = action;
        _range = range;
        _content.length = text.length;
        foreach (i; 0 .. text.length)
            _content[i] = text[i].dup;
    }

    @property
    {
        /// Action performed
        EditAction action() const { return _action; }

        /// Source range to replace with new content
        ref TextRange range() { return _range; }

        /// New range after operation applied
        ref TextRange newRange() { return _newRange; }

        /// New content for range (if required for this action)
        ref dstring[] content() { return _content; }

        /// Line edit marks for old range
        ref EditStateMark[] oldEditMarks() { return _oldEditMarks; }

        /// Old content for range
        ref dstring[] oldContent() { return _oldContent; }
    }

    /// Try to merge two operations (simple entering of characters in the same line), return true if succeded
    bool merge(EditOperation op)
    {
        if (_range.start.line != op._range.start.line) // both ops whould be on the same line
            return false;
        if (_content.length != 1 || op._content.length != 1) // both ops should operate the same line
            return false;
        // appending of single character
        if (_range.empty && op._range.empty && op._content[0].length == 1 && _newRange.end.pos == op._range.start.pos)
        {
            _content[0] ~= op._content[0];
            _newRange.end.pos++;
            return true;
        }
        // removing single character
        if (_newRange.empty && op._newRange.empty && op._oldContent[0].length == 1)
        {
            if (_newRange.end.pos == op._range.end.pos)
            {
                // removed char before
                _range.start.pos--;
                _newRange.start.pos--;
                _newRange.end.pos--;
                _oldContent[0] = (op._oldContent[0].dup ~ _oldContent[0].dup).dup;
                return true;
            }
            else if (_newRange.end.pos == op._range.start.pos)
            {
                // removed char after
                _range.end.pos++;
                _oldContent[0] = (_oldContent[0].dup ~ op._oldContent[0].dup).dup;
                return true;
            }
        }
        return false;
    }

    void modified(bool all = true)
    {
        foreach (i; 0 .. _oldEditMarks.length)
        {
            if (all || _oldEditMarks[i] == EditStateMark.saved)
                _oldEditMarks[i] = EditStateMark.changed;
        }
    }

    /// Returns true if it's insert new line operation
    @property bool isInsertNewLine() const
    {
        return _content.length == 2 && _content[0].length == 0 && _content[1].length == 0;
    }

    /// If new content is single char, return it, otherwise return 0
    @property dchar singleChar() const
    {
        return _content.length == 1 && _content[0].length == 1 ? _content[0][0] : 0;
    }
}

/// Undo/Redo buffer
class UndoBuffer
{
    private Collection!EditOperation _undoList;
    private Collection!EditOperation _redoList;

    /// Returns true if buffer contains any undo items
    @property bool hasUndo() const
    {
        return !_undoList.empty;
    }

    /// Returns true if buffer contains any redo items
    @property bool hasRedo() const
    {
        return !_redoList.empty;
    }

    /// Add undo operation
    void saveForUndo(EditOperation op)
    {
        _redoList.clear();
        if (!_undoList.empty)
        {
            if (_undoList.back.merge(op))
            {
                //_undoList.back.modified();
                return; // merged - no need to add new operation
            }
        }
        _undoList.pushBack(op);
    }

    /// Returns operation to be undone (put it to redo), null if no undo ops available
    EditOperation undo()
    {
        if (!hasUndo)
            return null; // no undo operations
        EditOperation result = _undoList.popBack();
        _redoList.pushBack(result);
        return result;
    }

    /// Returns operation to be redone (put it to undo), null if no undo ops available
    EditOperation redo()
    {
        if (!hasRedo)
            return null; // no undo operations
        EditOperation result = _redoList.popBack();
        _undoList.pushBack(result);
        return result;
    }

    /// Clear both undo and redo buffers
    void clear()
    {
        _undoList.clear();
        _redoList.clear();
        _savedState = null;
    }

    private EditOperation _savedState;

    /// Current state is saved
    void saved()
    {
        _savedState = _undoList.back;
        foreach (op; _undoList)
        {
            op.modified();
        }
        foreach (op; _redoList)
        {
            op.modified();
        }
    }

    /// Returns true if saved state is in redo buffer
    bool savedInRedo()
    {
        if (!_savedState)
            return false;
        return _savedState in _redoList;
    }

    /// Returns true if content has been changed since last saved() or clear() call
    @property bool modified() const
    {
        return _savedState !is _undoList.back;
    }
}

/// Editable Content change listener
alias onContentChangeHandler = void delegate(EditOperation operation,
        ref TextRange rangeBefore, ref TextRange rangeAfter, Object source);

alias onEditableContentMarksChangeHandler = void delegate(LineIcon[] movedMarks, LineIcon[] removedMarks);

/// TokenCategory holder
alias TokenProp = ubyte;
/// TokenCategory string
alias TokenPropString = TokenProp[];

struct LineSpan
{
    /// Start index of line
    int start;
    /// Number of lines it spans
    int len;
    /// The wrapping points
    WrapPoint[] wrapPoints;
    /// The wrapped text
    dstring[] wrappedContent;

    enum WrapPointInfo : bool
    {
        position,
        width,
    }

    ///Adds up either positions or widths to a wrapLine
    int accumulation(int wrapLine, bool wrapPointInfo) const
    {
        int total;
        for (int i; i < wrapLine; i++)
        {
            if (i < this.wrapPoints.length - 1)
            {
                int curVal;
                curVal = wrapPointInfo ? this.wrapPoints[i].wrapWidth : this.wrapPoints[i].wrapPos;
                total += curVal;
            }
        }
        return total;
    }
}

///Holds info about a word wrapping point
struct WrapPoint
{
    ///The relative wrapping position (related to TextPosition.pos)
    int wrapPos;
    ///The associated calculated width of the wrapLine
    int wrapWidth;
}

/// Interface for custom syntax highlight, comments toggling, smart indents, and other language dependent features for source code editors
interface SyntaxSupport
{
    /// Returns editable content
    @property EditableContent content();
    /// Set editable content
    @property SyntaxSupport content(EditableContent content);

    /// Categorize characters in content by token types
    void updateHighlight(dstring[] lines, TokenPropString[] props, int changeStartLine, int changeEndLine);

    /// Returns true if toggle line comment is supported for file type
    @property bool supportsToggleLineComment();
    /// Returns true if can toggle line comments for specified text range
    bool canToggleLineComment(TextRange range);
    /// Toggle line comments for specified text range
    void toggleLineComment(TextRange range, Object source);

    /// Returns true if toggle block comment is supported for file type
    @property bool supportsToggleBlockComment();
    /// Returns true if can toggle block comments for specified text range
    bool canToggleBlockComment(TextRange range);
    /// Toggle block comments for specified text range
    void toggleBlockComment(TextRange range, Object source);

    /// Returns paired bracket {} () [] for char at position p, returns paired char position or p if not found or not bracket
    TextPosition findPairedBracket(TextPosition p);

    /// Returns true if smart indent is supported
    bool supportsSmartIndents() const;
    /// Apply smart indent after edit operation, if needed
    void applySmartIndent(EditOperation op, Object source);
}

/// Measure line text (tabs, spaces, and nonspace positions)
struct TextLineMeasure
{
    /// Line length
    int len;
    /// First non-space index in line
    int firstNonSpace = -1;
    /// First non-space position according to tab size
    int firstNonSpaceX;
    /// Last non-space character index in line
    int lastNonSpace = -1;
    /// Last non-space position based on tab size
    int lastNonSpaceX;
    /// True if line has zero length or consists of spaces and tabs only
    @property bool empty() const
    {
        return len == 0 || firstNonSpace < 0;
    }
}

/// Represents size of tab character in spaces, in range from 1 to 16
struct TabSize
{
    int value() const { return sz; }
    alias value this;

    private int sz = 4;

    this(int size)
    {
        sz = clamp(size, 1, 16);
    }
}

/// Editable plain text (single/multiline)
class EditableContent
{
    @property
    {
        bool modified() const
        {
            return _undoBuffer.modified;
        }

        inout(SyntaxSupport) syntaxSupport() inout { return _syntaxSupport; }
        /// ditto
        void syntaxSupport(SyntaxSupport syntaxSupport)
        {
            _syntaxSupport = syntaxSupport;
            if (_syntaxSupport)
            {
                _syntaxSupport.content = this;
                updateTokenProps(0, cast(int)_lines.length);
            }
        }

        const(dstring[]) lines() const { return _lines; }

        /// Returns true if content has syntax highlight handler set
        bool hasSyntaxHighlight() const
        {
            return _syntaxSupport !is null;
        }

        ref LineIcons lineIcons() { return _lineIcons; }

        /// True if smart indents are supported
        bool supportsSmartIndents() const
        {
            return _syntaxSupport && _syntaxSupport.supportsSmartIndents;
        }

        /// Returns true if miltiline content is supported
        bool multiline() const { return _multiline; }

        EditStateMark[] editMarks() { return _editMarks; }

        /// Returns all lines concatenated delimited by '\n'
        dstring text() const
        {
            if (_lines.length == 0)
                return "";
            if (_lines.length == 1)
                return _lines[0];
            // concat lines
            dchar[] buf;
            foreach (index, item; _lines)
            {
                if (index)
                    buf ~= EOL;
                buf ~= item;
            }
            return cast(dstring)buf;
        }

        /// Returns line count
        int length() const
        {
            return cast(int)_lines.length;
        }
    }

    bool readOnly;
    /// Tab size (in number of spaces)
    TabSize tabSize;
    /// Tab key behavior flag: when true, spaces will be inserted instead of tabs
    bool useSpacesForTabs = true;
    /// True if smart indents are enabled
    bool smartIndents;
    /// True if smart indents are enabled
    bool smartIndentsAfterPaste;

    /// Listeners for edit operations
    Signal!onContentChangeHandler contentChanged;
    /// Listeners for mark changes after edit operation
    Signal!onEditableContentMarksChangeHandler marksChanged;

    private
    {
        UndoBuffer _undoBuffer;
        SyntaxSupport _syntaxSupport;
        LineIcons _lineIcons;

        bool _multiline;

        /// Text content by lines
        dstring[] _lines;
        /// Token properties by lines - for syntax highlight
        TokenPropString[] _tokenProps;

        /// Line edit marks
        EditStateMark[] _editMarks;
    }

    this(bool multiline)
    {
        _multiline = multiline;
        _lines.length = 1; // initial state: single empty line
        _editMarks.length = 1;
        _undoBuffer = new UndoBuffer;
    }

    /// Append one or more lines at end
    void appendLines(dstring[] lines...)
    {
        TextRange rangeBefore;
        rangeBefore.start = rangeBefore.end = lineEnd(_lines.length ? cast(int)_lines.length - 1 : 0);
        auto op = new EditOperation(EditAction.replace, rangeBefore, lines);
        performOperation(op, this);
    }

    static alias isAlphaForWordSelection = isAlNum;

    /// Get word bounds by position
    TextRange wordBounds(TextPosition pos)
    {
        TextRange res;
        res.start = pos;
        res.end = pos;
        if (pos.line < 0 || pos.line >= _lines.length)
            return res;
        dstring s = line(pos.line);
        int p = pos.pos;
        if (p < 0 || p > s.length || s.length == 0)
            return res;
        const leftChar = p > 0 ? s[p - 1] : 0;
        const rightChar = p < s.length - 1 ? s[p + 1] : 0;
        const centerChar = p < s.length ? s[p] : 0;
        if (isAlphaForWordSelection(centerChar))
        {
            // ok
        }
        else if (isAlphaForWordSelection(leftChar))
        {
            p--;
        }
        else if (isAlphaForWordSelection(rightChar))
        {
            p++;
        }
        else
        {
            return res;
        }
        int start = p;
        int end = p;
        while (start > 0 && isAlphaForWordSelection(s[start - 1]))
            start--;
        while (end + 1 < s.length && isAlphaForWordSelection(s[end + 1]))
            end++;
        end++;
        res.start.pos = start;
        res.end.pos = end;
        return res;
    }

    /// Call listener to say that whole content is replaced e.g. by loading from file
    void notifyContentReplaced()
    {
        clearEditMarks();
        TextRange rangeBefore;
        TextRange rangeAfter;
        // notify about content change
        handleContentChange(new EditOperation(EditAction.replaceContent), rangeBefore, rangeAfter, this);
    }

    /// Call listener to say that content is saved
    void notifyContentSaved()
    {
        // mark all changed lines as saved
        foreach (i; 0 .. _editMarks.length)
        {
            if (_editMarks[i] == EditStateMark.changed)
                _editMarks[i] = EditStateMark.saved;
        }
        TextRange rangeBefore;
        TextRange rangeAfter;
        // notify about content change
        handleContentChange(new EditOperation(EditAction.saveContent), rangeBefore, rangeAfter, this);
    }

    bool findMatchedBraces(TextPosition p, out TextRange range)
    {
        if (!_syntaxSupport)
            return false;
        const TextPosition p2 = _syntaxSupport.findPairedBracket(p);
        if (p == p2)
            return false;
        if (p < p2)
        {
            range.start = p;
            range.end = p2;
        }
        else
        {
            range.start = p2;
            range.end = p;
        }
        return true;
    }

    protected void updateTokenProps(int startLine, int endLine)
    {
        clearTokenProps(startLine, endLine);
        if (_syntaxSupport)
        {
            _syntaxSupport.updateHighlight(_lines, _tokenProps, startLine, endLine);
        }
    }

    protected void markChangedLines(int startLine, int endLine)
    {
        foreach (i; startLine .. endLine)
        {
            _editMarks[i] = EditStateMark.changed;
        }
    }

    /// Set props arrays size equal to text line sizes, bit fill with unknown token
    protected void clearTokenProps(int startLine, int endLine)
    {
        foreach (i; startLine .. endLine)
        {
            if (hasSyntaxHighlight)
            {
                const int len = cast(int)_lines[i].length;
                _tokenProps[i].length = len;
                foreach (j; 0 .. len)
                    _tokenProps[i][j] = TOKEN_UNKNOWN;
            }
            else
            {
                _tokenProps[i] = null; // no token props
            }
        }
    }

    void clearEditMarks()
    {
        _editMarks.length = _lines.length;
        foreach (i; 0 .. _editMarks.length)
            _editMarks[i] = EditStateMark.unchanged;
    }

    /// Replace whole text with another content
    @property void text(dstring newContent)
    {
        clearUndo();
        _lines.length = 0;
        if (_multiline)
        {
            _lines = splitDString(newContent);
            _tokenProps.length = _lines.length;
            updateTokenProps(0, cast(int)_lines.length);
        }
        else
        {
            _lines.length = 1;
            _lines[0] = replaceEOLsWithSpaces(newContent);
            _tokenProps.length = 1;
            updateTokenProps(0, cast(int)_lines.length);
        }
        clearEditMarks();
        notifyContentReplaced();
    }

    /// Clear content
    void clear()
    {
        clearUndo();
        clearEditMarks();
        _lines.length = 0;
    }

    dstring opIndex(int index) const
    {
        return line(index);
    }

    /// Returns line text by index, "" if index is out of bounds
    dstring line(int index) const
    {
        return index >= 0 && index < _lines.length ? _lines[index] : ""d;
    }

    /// Returns character at position lineIndex, pos
    dchar opIndex(int lineIndex, int pos)
    {
        const s = line(lineIndex);
        if (pos >= 0 && pos < s.length)
            return s[pos];
        return 0;
    }
    /// Returns character at position lineIndex, pos
    dchar opIndex(TextPosition p)
    {
        const s = line(p.line);
        if (p.pos >= 0 && p.pos < s.length)
            return s[p.pos];
        return 0;
    }

    /// Returns line token properties one item per character (index is 0 based line number)
    TokenPropString lineTokenProps(int index)
    {
        return index >= 0 && index < _tokenProps.length ? _tokenProps[index] : null;
    }

    /// Returns token properties character position
    TokenProp tokenProp(TextPosition p)
    {
        return p.line >= 0 && p.line < _tokenProps.length && p.pos >= 0 &&
            p.pos < _tokenProps[p.line].length ? _tokenProps[p.line][p.pos] : 0;
    }

    /// Returns position for end of last line
    @property TextPosition endOfFile() const
    {
        return TextPosition(cast(int)_lines.length - 1, cast(int)_lines[$ - 1].length);
    }

    /// Returns access to line edit mark by line index (0 based)
    ref EditStateMark editMark(int index)
    {
        assert(index >= 0 && index < _editMarks.length);
        return _editMarks[index];
    }

    /// Returns text position for end of line lineIndex
    TextPosition lineEnd(int lineIndex) const
    {
        return TextPosition(lineIndex, lineLength(lineIndex));
    }

    /// Returns text position for begin of line lineIndex (if lineIndex > number of lines, returns end of last line)
    TextPosition lineBegin(int lineIndex) const
    {
        if (lineIndex >= _lines.length)
            return lineEnd(lineIndex - 1);
        return TextPosition(lineIndex, 0);
    }

    /// Returns previous character position
    TextPosition prevCharPos(TextPosition p) const
    {
        if (p.line < 0)
            return TextPosition(0, 0);
        p.pos--;
        while (true)
        {
            if (p.line < 0)
                return TextPosition(0, 0);
            if (p.pos >= 0 && p.pos < lineLength(p.line))
                return p;
            p.line--;
            p.pos = lineLength(p.line) - 1;
        }
    }

    /// Returns previous character position
    TextPosition nextCharPos(TextPosition p) const
    {
        TextPosition eof = endOfFile();
        if (p >= eof)
            return eof;
        p.pos++;
        while (true)
        {
            if (p >= eof)
                return eof;
            if (p.pos >= 0 && p.pos < lineLength(p.line))
                return p;
            p.line++;
            p.pos = 0;
        }
    }

    /// Returns text range for whole line lineIndex
    TextRange lineRange(int lineIndex) const
    {
        return TextRange(TextPosition(lineIndex, 0), lineIndex < cast(int)_lines.length - 1 ?
                lineBegin(lineIndex + 1) : lineEnd(lineIndex));
    }

    /// Find nearest next tab position
    int nextTab(int pos) const
    {
        return (pos + tabSize) / tabSize * tabSize;
    }

    /// To return information about line space positions
    static struct LineWhiteSpace
    {
        int firstNonSpaceIndex = -1;
        int firstNonSpaceColumn = -1;
        int lastNonSpaceIndex = -1;
        int lastNonSpaceColumn = -1;

        @property bool empty() const
        {
            return firstNonSpaceColumn < 0;
        }
    }

    LineWhiteSpace getLineWhiteSpace(int lineIndex) const
    {
        LineWhiteSpace res;
        if (lineIndex < 0 || lineIndex >= _lines.length)
            return res;
        const s = _lines[lineIndex];
        int x = 0;
        for (int i = 0; i < s.length; i++)
        {
            const ch = s[i];
            if (ch == '\t')
            {
                x = (x + tabSize) / tabSize * tabSize;
            }
            else if (ch == ' ')
            {
                x++;
            }
            else
            {
                if (res.firstNonSpaceIndex < 0)
                {
                    res.firstNonSpaceIndex = i;
                    res.firstNonSpaceColumn = x;
                }
                res.lastNonSpaceIndex = i;
                res.lastNonSpaceColumn = x;
                x++;
            }
        }
        return res;
    }

    /// Returns spaces/tabs for filling from the beginning of line to specified position
    dstring fillSpace(int pos) const
    {
        dchar[] buf;
        int x = 0;
        while (x + tabSize <= pos)
        {
            if (useSpacesForTabs)
            {
                foreach (i; 0 .. tabSize)
                    buf ~= ' ';
            }
            else
            {
                buf ~= '\t';
            }
            x += tabSize;
        }
        while (x < pos)
        {
            buf ~= ' ';
            x++;
        }
        return cast(dstring)buf;
    }

    /// Measures line non-space start and end positions
    TextLineMeasure measureLine(int lineIndex) const
    {
        TextLineMeasure res;
        const s = _lines[lineIndex];
        res.len = cast(int)s.length;
        if (lineIndex < 0 || lineIndex >= _lines.length)
            return res;
        int x = 0;
        for (int i = 0; i < s.length; i++)
        {
            const ch = s[i];
            if (ch == ' ')
            {
                x++;
            }
            else if (ch == '\t')
            {
                x = (x + tabSize) / tabSize * tabSize;
            }
            else
            {
                if (res.firstNonSpace < 0)
                {
                    res.firstNonSpace = i;
                    res.firstNonSpaceX = x;
                }
                res.lastNonSpace = i;
                res.lastNonSpaceX = x;
                x++;
            }
        }
        return res;
    }

    /// Returns true if line with index lineIndex is empty (has length 0 or consists only of spaces and tabs)
    bool lineIsEmpty(int lineIndex) const
    {
        if (lineIndex < 0 || lineIndex >= _lines.length)
            return true;
        foreach (ch; _lines[lineIndex])
            if (ch != ' ' && ch != '\t')
                return false;
        return true;
    }

    /// Corrent range to cover full lines
    TextRange fullLinesRange(TextRange r) const
    {
        r.start.pos = 0;
        if (r.end.pos > 0 || r.start.line == r.end.line)
            r.end = lineBegin(r.end.line + 1);
        return r;
    }

    /// Returns position before first non-space character of line, returns 0 position if no non-space chars
    TextPosition firstNonSpace(int lineIndex) const
    {
        dstring s = line(lineIndex);
        for (int i = 0; i < s.length; i++)
            if (s[i] != ' ' && s[i] != '\t')
                return TextPosition(lineIndex, i);
        return TextPosition(lineIndex, 0);
    }

    /// Returns position after last non-space character of line, returns 0 position if no non-space chars on line
    TextPosition lastNonSpace(int lineIndex) const
    {
        dstring s = line(lineIndex);
        for (int i = cast(int)s.length - 1; i >= 0; i--)
            if (s[i] != ' ' && s[i] != '\t')
                return TextPosition(lineIndex, i + 1);
        return TextPosition(lineIndex, 0);
    }

    /// Returns text position for end of line lineIndex
    int lineLength(int lineIndex) const
    {
        return lineIndex >= 0 && lineIndex < _lines.length ? cast(int)_lines[lineIndex].length : 0;
    }

    /// Returns maximum length of line
    int maxLineLength() const
    {
        int m = 0;
        foreach (s; _lines)
            if (m < s.length)
                m = cast(int)s.length;
        return m;
    }

    void handleContentChange(EditOperation op, ref TextRange rangeBefore, ref TextRange rangeAfter, Object source)
    {
        // update highlight if necessary
        updateTokenProps(rangeAfter.start.line, rangeAfter.end.line + 1);
        LineIcon[] moved;
        LineIcon[] removed;
        if (_lineIcons.updateLinePositions(rangeBefore, rangeAfter, moved, removed))
        {
            if (marksChanged.assigned)
                marksChanged(moved, removed);
        }
        // call listeners
        if (contentChanged.assigned)
            contentChanged(op, rangeBefore, rangeAfter, source);
    }

    /// Returns edit marks for specified range
    EditStateMark[] rangeMarks(TextRange range) const
    {
        EditStateMark[] res;
        if (range.empty)
        {
            res ~= EditStateMark.unchanged;
            return res;
        }
        for (int lineIndex = range.start.line; lineIndex <= range.end.line; lineIndex++)
        {
            res ~= _editMarks[lineIndex];
        }
        return res;
    }

    /// Returns text for specified range
    dstring[] rangeText(TextRange range) const
    {
        dstring[] res;
        if (range.empty)
        {
            res ~= ""d;
            return res;
        }
        for (int lineIndex = range.start.line; lineIndex <= range.end.line; lineIndex++)
        {
            const lineText = line(lineIndex);
            dstring lineFragment = lineText;
            const int startchar = (lineIndex == range.start.line) ? range.start.pos : 0;
            int endchar = (lineIndex == range.end.line) ? range.end.pos : cast(int)lineText.length;
            if (endchar > lineText.length)
                endchar = cast(int)lineText.length;
            if (endchar <= startchar)
                lineFragment = ""d;
            else if (startchar != 0 || endchar != lineText.length)
                lineFragment = lineText[startchar .. endchar].dup;
            res ~= lineFragment;
        }
        return res;
    }

    /// When position is out of content bounds, fix it to nearest valid position
    void correctPosition(ref TextPosition position)
    {
        if (position.line >= length)
        {
            position.line = length - 1;
            position.pos = lineLength(position.line);
        }
        if (position.line < 0)
        {
            position.line = 0;
            position.pos = 0;
        }
        const currentLineLength = lineLength(position.line);
        position.pos = clamp(position.pos, 0, currentLineLength);
    }

    /// When range positions is out of content bounds, fix it to nearest valid position
    void correctRange(ref TextRange range)
    {
        correctPosition(range.start);
        correctPosition(range.end);
    }

    /// Removes removedCount lines starting from start
    protected void removeLines(int start, int removedCount)
    {
        const int end = start + removedCount;
        assert(removedCount > 0 && start >= 0 && end > 0 && start < _lines.length && end <= _lines.length);
        for (int i = start; i < _lines.length - removedCount; i++)
        {
            _lines[i] = _lines[i + removedCount];
            _tokenProps[i] = _tokenProps[i + removedCount];
            _editMarks[i] = _editMarks[i + removedCount];
        }
        for (int i = cast(int)_lines.length - removedCount; i < _lines.length; i++)
        {
            _lines[i] = null; // free unused line references
            _tokenProps[i] = null; // free unused line references
            _editMarks[i] = EditStateMark.unchanged; // free unused line references
        }
        _lines.length -= removedCount;
        _tokenProps.length = _lines.length;
        _editMarks.length = _lines.length;
    }

    /// Inserts count empty lines at specified position
    protected void insertLines(int start, int count)
    {
        assert(count > 0);
        _lines.length += count;
        _tokenProps.length = _lines.length;
        _editMarks.length = _lines.length;
        for (int i = cast(int)_lines.length - 1; i >= start + count; i--)
        {
            _lines[i] = _lines[i - count];
            _tokenProps[i] = _tokenProps[i - count];
            _editMarks[i] = _editMarks[i - count];
        }
        foreach (i; start .. start + count)
        {
            _lines[i] = ""d;
            _tokenProps[i] = null;
            _editMarks[i] = EditStateMark.changed;
        }
    }

    /// Inserts or removes lines, removes text in range
    protected void replaceRange(TextRange before, TextRange after, dstring[] newContent, EditStateMark[] marks = null)
    {
        const dstring firstLineBefore = line(before.start.line);
        const dstring lastLineBefore = before.singleLine ? firstLineBefore : line(before.end.line);
        const dstring firstLineHead = before.start.pos > 0 && before.start.pos <= firstLineBefore.length ?
            firstLineBefore[0 .. before.start.pos] : ""d;
        const dstring lastLineTail = before.end.pos >= 0 && before.end.pos < lastLineBefore.length ?
            lastLineBefore[before.end.pos .. $] : ""d;

        const int linesBefore = before.lines;
        const int linesAfter = after.lines;
        if (linesBefore < linesAfter)
        {
            // add more lines
            insertLines(before.start.line + 1, linesAfter - linesBefore);
        }
        else if (linesBefore > linesAfter)
        {
            // remove extra lines
            removeLines(before.start.line + 1, linesBefore - linesAfter);
        }
        foreach (int i; after.start.line .. after.end.line + 1)
        {
            if (marks)
            {
                //if (i - after.start.line < marks.length)
                _editMarks[i] = marks[i - after.start.line];
            }
            const dstring newline = newContent[i - after.start.line];
            if (i == after.start.line && i == after.end.line)
            {
                dchar[] buf;
                buf ~= firstLineHead;
                buf ~= newline;
                buf ~= lastLineTail;
                //Log.d("merging lines ", firstLineHead, " ", newline, " ", lastLineTail);
                _lines[i] = cast(dstring)buf;
                clearTokenProps(i, i + 1);
                if (!marks)
                    markChangedLines(i, i + 1);
                //Log.d("merge result: ", _lines[i]);
            }
            else if (i == after.start.line)
            {
                dchar[] buf;
                buf ~= firstLineHead;
                buf ~= newline;
                _lines[i] = cast(dstring)buf;
                clearTokenProps(i, i + 1);
                if (!marks)
                    markChangedLines(i, i + 1);
            }
            else if (i == after.end.line)
            {
                dchar[] buf;
                buf ~= newline;
                buf ~= lastLineTail;
                _lines[i] = cast(dstring)buf;
                clearTokenProps(i, i + 1);
                if (!marks)
                    markChangedLines(i, i + 1);
            }
            else
            {
                _lines[i] = newline; // no dup needed
                clearTokenProps(i, i + 1);
                if (!marks)
                    markChangedLines(i, i + 1);
            }
        }
    }

    static bool isWordBound(dchar thischar, dchar nextchar)
    {
        return isAlNum(thischar) && !isAlNum(nextchar) ||
               isPunct(thischar) && !isPunct(nextchar) ||
               isBracket(thischar) && !isBracket(nextchar) ||
               thischar != ' ' && nextchar == ' ';
    }

    /// Change text position to nearest word bound (direction < 0 - back, > 0 - forward)
    TextPosition moveByWord(TextPosition p, int direction, bool camelCasePartsAsWords)
    {
        correctPosition(p);
        const TextPosition firstns = firstNonSpace(p.line);
        const TextPosition lastns = lastNonSpace(p.line);
        const int linelen = lineLength(p.line);
        if (direction < 0) // back
        {
            if (p.pos <= 0)
            {
                // beginning of line - move to prev line
                if (p.line > 0)
                    p = lastNonSpace(p.line - 1);
            }
            else if (p.pos <= firstns.pos)
            { // before first nonspace
                // to beginning of line
                p.pos = 0;
            }
            else
            {
                const txt = line(p.line);
                int found;
                for (int i = p.pos - 1; i > 0; i--)
                {
                    // check if position i + 1 is after word end
                    dchar thischar = i >= 0 && i < linelen ? txt[i] : ' ';
                    if (thischar == '\t')
                        thischar = ' ';
                    dchar nextchar = i - 1 >= 0 && i - 1 < linelen ? txt[i - 1] : ' ';
                    if (nextchar == '\t')
                        nextchar = ' ';
                    if (isWordBound(thischar, nextchar) || (camelCasePartsAsWords &&
                            isUpperWordChar(thischar) && isLowerWordChar(nextchar)))
                    {
                        found = i;
                        break;
                    }
                }
                p.pos = found;
            }
        }
        else if (direction > 0) // forward
        {
            if (p.pos >= linelen)
            {
                // last position of line
                if (p.line < length - 1)
                    p = firstNonSpace(p.line + 1);
            }
            else if (p.pos >= lastns.pos)
            { // before first nonspace
                // to beginning of line
                p.pos = linelen;
            }
            else
            {
                const txt = line(p.line);
                int found = linelen;
                for (int i = p.pos; i < linelen; i++)
                {
                    // check if position i + 1 is after word end
                    dchar thischar = txt[i];
                    if (thischar == '\t')
                        thischar = ' ';
                    dchar nextchar = i < linelen - 1 ? txt[i + 1] : ' ';
                    if (nextchar == '\t')
                        nextchar = ' ';
                    if (isWordBound(thischar, nextchar) || (camelCasePartsAsWords &&
                            isLowerWordChar(thischar) && isUpperWordChar(nextchar)))
                    {
                        found = i + 1;
                        break;
                    }
                }
                p.pos = found;
            }
        }
        return p;
    }

    /// Edit content
    bool performOperation(EditOperation op, Object source)
    {
        if (readOnly)
            throw new Exception("content is readonly");
        if (op.action == EditAction.replace)
        {
            TextRange rangeBefore = op.range;
            assert(rangeBefore.start <= rangeBefore.end);
            //correctRange(rangeBefore);
            dstring[] oldcontent = rangeText(rangeBefore);
            EditStateMark[] oldmarks = rangeMarks(rangeBefore);
            dstring[] newcontent = op.content;
            if (newcontent.length == 0)
                newcontent ~= ""d;
            TextRange rangeAfter = op.range;
            rangeAfter.end = rangeAfter.start;
            if (newcontent.length > 1)
            {
                // different lines
                rangeAfter.end.line = rangeAfter.start.line + cast(int)newcontent.length - 1;
                rangeAfter.end.pos = cast(int)newcontent[$ - 1].length;
            }
            else
            {
                // same line
                rangeAfter.end.pos = rangeAfter.start.pos + cast(int)newcontent[0].length;
            }
            assert(rangeAfter.start <= rangeAfter.end);
            op.newRange = rangeAfter;
            op.oldContent = oldcontent;
            op.oldEditMarks = oldmarks;
            replaceRange(rangeBefore, rangeAfter, newcontent);
            _undoBuffer.saveForUndo(op);
            handleContentChange(op, rangeBefore, rangeAfter, source);
            return true;
        }
        return false;
    }

    //===============================================================
    // Undo/redo

    /// Returns true if there is at least one operation in undo buffer
    @property bool hasUndo() const
    {
        return _undoBuffer.hasUndo;
    }
    /// Returns true if there is at least one operation in redo buffer
    @property bool hasRedo() const
    {
        return _undoBuffer.hasRedo;
    }
    /// Undoes last change
    bool undo(Object source)
    {
        if (!hasUndo)
            return false;
        if (readOnly)
            throw new Exception("content is readonly");
        EditOperation op = _undoBuffer.undo();
        TextRange rangeBefore = op.newRange;
        dstring[] oldcontent = op.content;
        dstring[] newcontent = op.oldContent;
        EditStateMark[] newmarks = op.oldEditMarks; //_undoBuffer.savedInUndo() ?  : null;
        TextRange rangeAfter = op.range;
        //Log.d("Undoing op rangeBefore=", rangeBefore, " contentBefore=`", oldcontent, "` rangeAfter=", rangeAfter, " contentAfter=`", newcontent, "`");
        replaceRange(rangeBefore, rangeAfter, newcontent, newmarks);
        handleContentChange(op, rangeBefore, rangeAfter, source ? source : this);
        return true;
    }

    /// Redoes last undone change
    bool redo(Object source)
    {
        if (!hasRedo)
            return false;
        if (readOnly)
            throw new Exception("content is readonly");
        EditOperation op = _undoBuffer.redo();
        TextRange rangeBefore = op.range;
        dstring[] oldcontent = op.oldContent;
        dstring[] newcontent = op.content;
        TextRange rangeAfter = op.newRange;
        //Log.d("Redoing op rangeBefore=", rangeBefore, " contentBefore=`", oldcontent, "` rangeAfter=", rangeAfter, " contentAfter=`", newcontent, "`");
        replaceRange(rangeBefore, rangeAfter, newcontent);
        handleContentChange(op, rangeBefore, rangeAfter, source ? source : this);
        return true;
    }
    /// Clear undo/redp history
    void clearUndo()
    {
        _undoBuffer.clear();
    }

    //===============================================================
    // Load/save

    private string _filename;
    private TextFileFormat _format;

    /// File used to load editor content
    @property string filename() const { return _filename; }

    /// Load content form input stream
    bool load(InputStream f, string fname = null)
    {
        import beamui.core.linestream;

        clear();
        _filename = fname;
        _format = TextFileFormat.init;
        try
        {
            LineStream lines = LineStream.create(f, fname);
            while (true)
            {
                dchar[] s = lines.readLine();
                if (s is null)
                    break;
                int pos = cast(int)(_lines.length++);
                _tokenProps.length = _lines.length;
                _lines[pos] = s.dup;
                clearTokenProps(pos, pos + 1);
            }
            if (lines.errorCode != 0)
            {
                clear();
                Log.e("Error ", lines.errorCode, " ", lines.errorMessage, " -- at line ",
                        lines.errorLine, " position ", lines.errorPos);
                notifyContentReplaced();
                return false;
            }
            // EOF
            _format = lines.textFormat;
            _undoBuffer.clear();
            debug (FileFormats)
                Log.d("loaded file:", filename, " format detected:", _format);
            notifyContentReplaced();
            return true;
        }
        catch (Exception e)
        {
            Log.e("Exception while trying to read file ", fname, " ", e.toString);
            clear();
            notifyContentReplaced();
            return false;
        }
    }
    /// Load content from file
    bool load(string filename)
    {
        import std.file : exists, isFile;
        import std.exception : ErrnoException;

        clear();
        if (!filename.exists || !filename.isFile)
        {
            Log.e("Editable.load: File not found ", filename);
            return false;
        }
        try
        {
            auto f = new FileInputStream(filename);
            scope (exit) f.close();
            return load(f, filename);
        }
        catch (ErrnoException e)
        {
            Log.e("Editable.load: Exception while trying to read file ", filename, " ", e.toString);
            clear();
            return false;
        }
        catch (Exception e)
        {
            Log.e("Editable.load: Exception while trying to read file ", filename, " ", e.toString);
            clear();
            return false;
        }
    }
    /// Save to output stream in specified format
    bool save(OutputStream stream, string filename, TextFileFormat format)
    {
        if (!filename)
            filename = _filename;
        _format = format;
        try
        {
            import beamui.core.linestream;

            debug (FileFormats)
                Log.d("creating output stream, file=", filename, " format=", format);
            auto writer = new OutputLineStream(stream, filename, format);
            scope (exit) writer.close();
            foreach (line; _lines)
            {
                writer.writeLine(line);
            }
            _undoBuffer.saved();
            notifyContentSaved();
            return true;
        }
        catch (Exception e)
        {
            Log.e("Exception while trying to write file ", filename, " ", e.toString);
            return false;
        }
    }
    /// Save to output stream in current format
    bool save(OutputStream stream, string filename)
    {
        return save(stream, filename, _format);
    }
    /// Save to file in specified format
    bool save(string filename, TextFileFormat format)
    {
        if (!filename)
            filename = _filename;
        try
        {
            auto f = new FileOutputStream(filename);
            scope (exit) f.close();
            return save(f, filename, format);
        }
        catch (Exception e)
        {
            Log.e("Exception while trying to save file ", filename, " ", e.toString);
            return false;
        }
    }
    /// Save to file in current format
    bool save(string filename = null)
    {
        return save(filename, _format);
    }
}

/// Types of text editor line icon marks (bookmark / breakpoint / error / ...)
enum LineIconType
{
    /// Bookmark
    bookmark,
    /// Breakpoint mark
    breakpoint,
    /// Error mark
    error,
}

/// Text editor line icon
class LineIcon
{
    /// Mark type
    LineIconType type;
    /// Line number
    int line;
    /// Arbitrary parameter
    Object objectParam;

    /// Empty
    this()
    {
    }

    this(LineIconType type, int line, Object obj = null)
    {
        this.type = type;
        this.line = line;
        this.objectParam = obj;
    }
}

/// Text editor line icon list
struct LineIcons
{
    private LineIcon[] _items;
    private int _len;

    /// Returns count of items
    @property int length() const { return _len; }

    /// Returns item by index, or null if index out of bounds
    LineIcon opIndex(int index)
    {
        if (index < 0 || index >= _len)
            return null;
        return _items[index];
    }

    private void insert(LineIcon icon, int index)
    {
        index = clamp(index, 0, _len);
        if (_items.length <= index)
            _items.length = index + 16;
        if (index < _len)
        {
            for (size_t i = _len; i > index; i--)
                _items[i] = _items[i - 1];
        }
        _items[index] = icon;
        _len++;
    }

    private int findSortedIndex(int line, LineIconType type)
    {
        // TODO: use binary search
        foreach (i; 0 .. _len)
        {
            if (_items[i].line > line || _items[i].type > type)
            {
                return i;
            }
        }
        return _len;
    }
    /// Add icon mark
    void add(LineIcon icon)
    {
        const int index = findSortedIndex(icon.line, icon.type);
        insert(icon, index);
    }
    /// Add all icons from list
    void addAll(LineIcon[] list)
    {
        foreach (item; list)
            add(item);
    }
    /// Remove icon mark by index
    LineIcon remove(int index)
    {
        if (index < 0 || index >= _len)
            return null;
        LineIcon res = _items[index];
        for (int i = index; i < _len - 1; i++)
            _items[i] = _items[i + 1];
        _items[_len] = null;
        _len--;
        return res;
    }

    /// Remove icon mark
    LineIcon remove(LineIcon icon)
    {
        // same object
        foreach (i; 0 .. _len)
        {
            if (_items[i] is icon)
                return remove(i);
        }
        // has the same objectParam
        foreach (i; 0 .. _len)
        {
            if (_items[i].objectParam !is null && icon.objectParam !is null && _items[i].objectParam is icon
                    .objectParam)
                return remove(i);
        }
        // has same line and type
        foreach (i; 0 .. _len)
        {
            if (_items[i].line == icon.line && _items[i].type == icon.type)
                return remove(i);
        }
        return null;
    }

    /// Remove all icon marks of specified type, return true if any of items removed
    bool removeByType(LineIconType type)
    {
        bool res;
        foreach_reverse (i; 0 .. _len)
        {
            if (_items[i].type == type)
            {
                remove(i);
                res = true;
            }
        }
        return res;
    }
    /// Get array of icons of specified type
    LineIcon[] findByType(LineIconType type)
    {
        LineIcon[] res;
        foreach (i; 0 .. _len)
        {
            if (_items[i].type == type)
                res ~= _items[i];
        }
        return res;
    }
    /// Get array of icons of specified type
    LineIcon findByLineAndType(int line, LineIconType type)
    {
        foreach (i; 0 .. _len)
        {
            if (_items[i].type == type && _items[i].line == line)
                return _items[i];
        }
        return null;
    }
    /// Update mark position lines after text change, returns true if any of marks were moved or removed
    bool updateLinePositions(TextRange rangeBefore, TextRange rangeAfter, ref LineIcon[] moved, ref LineIcon[] removed)
    {
        moved = null;
        removed = null;
        bool res;
        foreach_reverse (i; 0 .. _len)
        {
            LineIcon item = _items[i];
            if (rangeBefore.start.line > item.line && rangeAfter.start.line > item.line)
                continue; // line is before ranges
            else if (rangeBefore.start.line < item.line || rangeAfter.start.line < item.line)
            {
                // line is fully after change
                const int deltaLines = rangeAfter.end.line - rangeBefore.end.line;
                if (!deltaLines)
                    continue;
                if (deltaLines < 0 && rangeBefore.end.line >= item.line && rangeAfter.end.line < item.line)
                {
                    // remove
                    removed ~= item;
                    remove(i);
                    res = true;
                }
                else
                {
                    // move
                    item.line += deltaLines;
                    moved ~= item;
                    res = true;
                }
            }
        }
        return res;
    }

    LineIcon findNext(LineIconType type, int line, int direction)
    {
        LineIcon firstBefore;
        LineIcon firstAfter;
        if (direction < 0)
        {
            // backward
            foreach_reverse (i; 0 .. _len)
            {
                LineIcon item = _items[i];
                if (item.type != type)
                    continue;
                if (!firstBefore && item.line >= line)
                    firstBefore = item;
                else if (!firstAfter && item.line < line)
                    firstAfter = item;
            }
        }
        else
        {
            // forward
            foreach (i; 0 .. _len)
            {
                LineIcon item = _items[i];
                if (item.type != type)
                    continue;
                if (!firstBefore && item.line <= line)
                    firstBefore = item;
                else if (!firstAfter && item.line > line)
                    firstAfter = item;
            }
        }
        if (firstAfter)
            return firstAfter;
        return firstBefore;
    }

    @property bool hasBookmarks() const
    {
        foreach (i; 0 .. _len)
        {
            if (_items[i].type == LineIconType.bookmark)
                return true;
        }
        return false;
    }

    void toggleBookmark(int line)
    {
        LineIcon existing = findByLineAndType(line, LineIconType.bookmark);
        if (existing)
            remove(existing);
        else
            add(new LineIcon(LineIconType.bookmark, line));
    }
}
