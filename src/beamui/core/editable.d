/**
Editable text content and related data structures.

Copyright: Vadim Lopatin 2014-2017, James Johnson 2018, dayllenger 2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.editable;

public import beamui.core.collections : ListChange;
import beamui.core.collections : ObservableList;
import beamui.core.functions;
import beamui.core.linestream;
import beamui.core.logger;
import beamui.core.parseutils;
import beamui.core.signals;
import beamui.core.streams;
import beamui.core.undo;

immutable dchar EOL = '\n';

version (Windows)
{
    immutable dstring SYSTEM_DEFAULT_EOL = "\r\n";
}
else
{
    immutable dstring SYSTEM_DEFAULT_EOL = "\n";
}

private const ubyte TC_SHIFT = 4;
const ubyte TOKEN_CATEGORY_MASK = 0xF0; // token category 0..15
const ubyte TOKEN_SUBCATEGORY_MASK = 0x0F; // token subcategory 0..15
const ubyte TOKEN_UNKNOWN = 0;

/** Token category for syntax highlight.

    Bit mask:
    ---
    7654 3210
    cccc ssss
    |    |
    |    token subcategory
    |
    token category
    ---
*/
enum TokenCategory : ubyte
{
    /// Whitespace category
    whitespace = (0 << TC_SHIFT),
    /// Space character sequence
    whitespaceSpace = whitespace | 1,
    /// Tab character sequence
    whitespaceTab = whitespace | 2,

    /// Comment category
    comment = (1 << TC_SHIFT),
    /// Single-line comment
    commentSingleLine = comment | 1,
    /// Single-line documentation comment
    commentSingleLineDoc = comment | 2,
    /// Multiline coment
    commentMultiLine = comment | 3,
    /// Multiline documentation comment
    commentMultiLineDoc = comment | 4,
    /// Documentation comment
    commentDoc = comment | 5,

    /// Identifier category
    identifier = (2 << TC_SHIFT),
    /// Class name
    identifierClass = identifier | 1,
    /// Struct name
    identifierStruct = identifier | 2,
    /// Local variable
    identifierLocal = identifier | 3,
    /// Struct or class member
    identifierMember = identifier | 4,
    /// Usage of this identifier is deprecated
    identifierDeprecated = identifier | 15,

    /// String literal
    string = (3 << TC_SHIFT),
    /// Character literal
    character = (4 << TC_SHIFT),
    /// Integer literal
    integer = (5 << TC_SHIFT),
    /// Floating point number literal
    floating = (6 << TC_SHIFT),
    /// Keyword
    keyword = (7 << TC_SHIFT),
    /// Operator
    op = (8 << TC_SHIFT),

    // add more here...

    /// Error category - unparsed character sequence
    error = (15 << TC_SHIFT),
    /// Invalid token - generic
    errorInvalidToken = error | 1,
    /// Invalid number token
    errorInvalidNumber = error | 2,
    /// Invalid string token
    errorInvalidString = error | 3,
    /// Invalid identifier token
    errorInvalidIdentifier = error | 4,
    /// Invalid comment token
    errorInvalidComment = error | 7,
    /// Invalid operator token
    errorInvalidOp = error | 8,
}

/// Extracts token category, clearing subcategory
TokenCategory tokenCategory(TokenCategory t)
{
    return cast(TokenCategory)(t & 0xF0);
}

/// Split dstring by delimiters
dstring[] splitDString(const dstring source, dchar delimiter = EOL)
{
    if (source.length == 0)
        return null;

    dstring[] list;
    int start;
    for (int i; i <= source.length; i++)
    {
        if (i == source.length || source[i] == delimiter)
        {
            if (i > start)
            {
                int end = i;
                // check Windows CR/LF
                if (delimiter == EOL && i > 1 && i > start + 1 && source[i - 1] == '\r')
                    end--;
                list ~= source[start .. end].idup;
            }
            else
                list ~= null;
            start = i + 1;
        }
    }
    return list;
}

/// Concat strings from array using delimiter
dstring concatDStrings(const dstring[] lines, dstring delimiter = SYSTEM_DEFAULT_EOL)
{
    if (lines.length == 0)
        return null;

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
dstring replaceEOLsWithSpaces(const dstring source)
{
    import std.array : uninitializedArray;

    if (source.length == 0)
        return null;

    dchar[] buf = uninitializedArray!(dchar[])(source.length);
    dchar lastch;
    int i;
    foreach (ch; source)
    {
        if (ch == '\r')
        {
            buf[i] = ' ';
        }
        else if (ch == '\n')
        {
            if (lastch != '\r')
                buf[i] = ' ';
            else
                i--;
        }
        else
            buf[i] = ch;
        i++;
        lastch = ch;
    }
    return cast(dstring)buf[0 .. i];
}

unittest
{
    const s1 = "The\nquick\r\nbrown\n\n\nfox jumps\nover the lazy\r\ndog\n"d;
    const s2 = "The\nquick\nbrown\n\n\nfox jumps\nover the lazy\ndog\n"d;
    const s3 = "The quick brown   fox jumps over the lazy dog "d;

    assert(splitDString(s1).length == 9);
    assert(concatDStrings(splitDString(s1), "\n") == s2);
    assert(replaceEOLsWithSpaces(s1) == s3);
    assert(replaceEOLsWithSpaces(s2) == s3);

    assert(splitDString(" \n \n "d) == [" "d, " "d, " "d]);
    assert(replaceEOLsWithSpaces(" \n \r \r\n"d) == "      "d);

    assert(splitDString(null) is null);
    assert(concatDStrings(null) is null);
    assert(replaceEOLsWithSpaces(null) is null);
}

/// Line content range
struct LineRange
{
    int start;
    int end;

    /// Returns true if range is empty
    @property bool empty() const
    {
        return end <= start;
    }
}

/// Edit operation details for single-line editors
class SingleLineEditOperation : UndoOperation
{
    final @property
    {
        /// Source range to replace with new content
        LineRange rangeBefore() const { return _rangeBefore; }
        /// New range after operation applied
        LineRange range() const { return _range; }

        /// Old content for range
        dstring contentBefore() { return _contentBefore; }
        /// New content for range (if required for this action)
        dstring content() { return _content; }
    }

    private
    {
        LineRange _rangeBefore;
        LineRange _range;
        dstring _contentBefore;
        dstring _content;
    }

    this(int pos, dstring text)
    {
        _rangeBefore = LineRange(pos, pos);
        _content = text.idup;
    }

    this(LineRange range, dstring text)
    {
        _rangeBefore = range;
        _content = text.idup;
    }

    void setNewRange(LineRange r, dstring contentBefore)
    {
        _range = r;
        _contentBefore = contentBefore;
    }

    bool merge(UndoOperation unop)
    {
        auto op = cast(SingleLineEditOperation)unop;
        assert(op);

        // appending a single character
        if (_rangeBefore.empty && op._rangeBefore.empty && op._content.length == 1 && _range.end == op._rangeBefore.start)
        {
            _content ~= op._content;
            _range.end++;
            return true;
        }
        // removing a single character
        if (_range.empty && op._range.empty && op._contentBefore.length == 1)
        {
            if (_range.end == op._rangeBefore.end)
            {
                // removed char before
                _rangeBefore.start--;
                _range.start--;
                _range.end--;
                _contentBefore = op._contentBefore ~ _contentBefore.idup;
                return true;
            }
            else if (_range.end == op._rangeBefore.start)
            {
                // removed char after
                _rangeBefore.end++;
                _contentBefore = _contentBefore.idup ~ op._contentBefore;
                return true;
            }
        }
        return false;
    }

    void modified()
    {
    }
}

/// Text content position
struct TextPosition
{
    /// Line number, zero based
    int line;
    /// Character position in line (0 == before the first character)
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

    string toString() const
    {
        return to!string(line) ~ ":" ~ to!string(pos);
    }

    /// Adds `deltaPos` to position and returns result
    TextPosition offset(int deltaPos) const
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

/// Text content by lines
class TextContent : ObservableList!dstring
{
    final @property
    {
        /// Const list array
        alias lines = items;
        /// Total line count
        alias lineCount = count;

        /// Position for the end of the last line
        TextPosition end() const
        {
            const len = lineCount;
            if (len > 0)
                return TextPosition(len - 1, cast(int)lines[len - 1].length);
            else
                return TextPosition(0, 0);
        }
    }

    this(uint emptyLines)
    {
        super(emptyLines);
    }

    this(dstring initialText)
    {
        replaceAll(splitDString(initialText));
    }

final:

    dstring getStr() const
    {
        return concatDStrings(lines);
    }

    void setStr(dstring str)
    {
        replaceAll(splitDString(str));
    }

    /// Get the line string by index, `null` if index is out of bounds
    dstring opIndex(uint i) const
    {
        return i < lineCount ? lines[i] : null;
    }

    /// Returns character at position `(lineIndex, pos)`
    dchar opIndex(int lineIndex, int pos)
    {
        const s = line(lineIndex);
        if (0 <= pos && pos < s.length)
            return s[pos];
        else
            return 0;
    }
    /// ditto
    dchar opIndex(TextPosition p)
    {
        const s = line(p.line);
        if (0 <= p.pos && p.pos < s.length)
            return s[p.pos];
        else
            return 0;
    }

    /// Returns the line string by index, `null` if index is out of bounds
    dstring line(uint i) const
    {
        return i < lineCount ? lines[i] : null;
    }

    /// Returns length of a line by index
    int lineLength(uint i) const
    {
        return i < lineCount ? cast(int)lines[i].length : 0;
    }

    /// Calculate maximum line length
    int getMaxLineLength() const
    {
        size_t m;
        foreach (s; lines)
            if (m < s.length)
                m = s.length;
        return cast(int)m;
    }

    /// Returns text position for the begin of line by index, clamps if necessary
    TextPosition lineBegin(int i) const
    {
        const len = lineCount;
        if (i < 0 || len == 0)
            return TextPosition(0, 0);
        if (i >= len)
            return TextPosition(len - 1, cast(int)lines[len - 1].length);
        return TextPosition(i, 0);
    }

    /// Returns text position for the end of line by index, clamps if necessary
    TextPosition lineEnd(int i) const
    {
        const len = lineCount;
        if (i < 0 || len == 0)
            return TextPosition(0, 0);
        if (i >= len)
            return TextPosition(len - 1, cast(int)lines[len - 1].length);
        return TextPosition(i, cast(int)lines[i].length);
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
            if (0 <= p.pos && p.pos < lineLength(p.line))
                return p;
            p.line--;
            p.pos = lineLength(p.line) - 1;
        }
    }
    /// Returns next character position
    TextPosition nextCharPos(TextPosition p) const
    {
        TextPosition eof = end();
        if (p >= eof)
            return eof;
        p.pos++;
        while (true)
        {
            if (p >= eof)
                return eof;
            if (0 <= p.pos && p.pos < lineLength(p.line))
                return p;
            p.line++;
            p.pos = 0;
        }
    }

    /// Returns text range for whole line `index`
    TextRange lineRange(int index) const
    {
        const start = TextPosition(index, 0);
        const end = index + 1 < lineCount ? lineBegin(index + 1) : lineEnd(index);
        return TextRange(start, end);
    }

    /// Returns text for specified range
    dstring[] rangeText(TextRange range) const
    {
        dstring[] txt;
        if (range.empty)
        {
            txt ~= null;
            return txt;
        }
        for (int i = range.start.line; i <= range.end.line; i++)
        {
            const s = line(i);
            const len = cast(int)s.length;
            const int start = (i == range.start.line) ? range.start.pos : 0;
            const int end = (i == range.end.line) ? min(range.end.pos, len) : len;
            if (start < end)
                txt ~= s[start .. end];
            else
                txt ~= null;
        }
        return txt;
    }

    /// When position is out of content bounds, fix it to nearest valid position
    void correctPosition(ref TextPosition position)
    {
        if (position.line >= lineCount)
        {
            position.line = lineCount - 1;
            position.pos = lineLength(position.line);
        }
        else if (position.line < 0)
        {
            position.line = 0;
            position.pos = 0;
        }
        else
        {
            const currentLineLength = lineLength(position.line);
            position.pos = clamp(position.pos, 0, currentLineLength);
        }
    }

    /// When range positions is out of content bounds, fix it to nearest valid position
    void correctRange(ref TextRange range)
    {
        correctPosition(range.start);
        correctPosition(range.end);
    }
}

/// Action performed with editable contents
enum EditAction
{
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

/// Edit operation details for `EditableContent`
class EditOperation : UndoOperation
{
    final @property
    {
        /// Action performed
        EditAction action() const { return _action; }

        /// Source range to replace with new content
        TextRange rangeBefore() const { return _rangeBefore; }
        /// New range after operation applied
        TextRange range() const { return _range; }

        /// Old content for range
        dstring[] contentBefore() { return _contentBefore; }
        /// New content for range (if required for this action)
        dstring[] content() { return _content; }

        /// Line edit marks for old range
        EditStateMark[] editMarksBefore() { return _editMarksBefore; }
    }

    private
    {
        EditAction _action;
        TextRange _rangeBefore;
        TextRange _range;
        dstring[] _content;
        EditStateMark[] _editMarksBefore;
        dstring[] _contentBefore;
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
        _rangeBefore = range;
        _content.length = 1;
        _content[0] = text.idup;
    }

    this(EditAction action, TextRange range, dstring[] text)
    {
        _action = action;
        _rangeBefore = range;
        _content.length = text.length;
        foreach (i; 0 .. text.length)
            _content[i] = text[i].idup;
    }

    void setNewRange(TextRange r, dstring[] contentBefore, EditStateMark[] editMarksBefore)
    {
        assert(contentBefore.length > 0);
        _range = r;
        _contentBefore = contentBefore;
        _editMarksBefore = editMarksBefore;
    }

    /// Try to merge two operations (simple entering of characters in the same line), return true if succeded
    bool merge(UndoOperation unop)
    {
        auto op = cast(EditOperation)unop;
        assert(op);

        if (_rangeBefore.start.line != op._rangeBefore.start.line) // both ops whould be on the same line
            return false;
        if (_content.length != 1 || op._content.length != 1) // both ops should operate the same line
            return false;
        // appending of single character
        if (_rangeBefore.empty && op._rangeBefore.empty && op._content[0].length == 1 && _range.end.pos == op._rangeBefore.start.pos)
        {
            _content[0] ~= op._content[0];
            _range.end.pos++;
            return true;
        }
        // removing single character
        if (_range.empty && op._range.empty && op._contentBefore[0].length == 1)
        {
            if (_range.end.pos == op._rangeBefore.end.pos)
            {
                // removed char before
                _rangeBefore.start.pos--;
                _range.start.pos--;
                _range.end.pos--;
                _contentBefore[0] = op._contentBefore[0].idup ~ _contentBefore[0].idup;
                return true;
            }
            else if (_range.end.pos == op._rangeBefore.start.pos)
            {
                // removed char after
                _rangeBefore.end.pos++;
                _contentBefore[0] = _contentBefore[0].idup ~ op._contentBefore[0].idup;
                return true;
            }
        }
        return false;
    }

    void modified()
    {
        foreach (i; 0 .. _editMarksBefore.length)
        {
            if (_editMarksBefore[i] == EditStateMark.saved)
                _editMarksBefore[i] = EditStateMark.changed;
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

/// Editable Content change listener
alias ContentChangeHandler = void delegate(EditOperation operation,
        ref TextRange rangeBefore, ref TextRange rangeAfter, Object source);

alias MarksChangeHandler = void delegate(LineIcon[] movedMarks, LineIcon[] removedMarks);

/// TokenCategory holder
alias TokenProp = ubyte;
/// TokenCategory string
alias TokenPropString = TokenProp[];

/// Interface for custom syntax highlight, comments toggling, smart indents,
/// and other language dependent features for source code editors
interface SyntaxSupport
{
    @property
    {
        /// Editable content
        inout(EditableContent) content() inout;
        /// ditto
        void content(EditableContent);

        /// Returns true if supports toggle line comment for that language
        bool supportsToggleLineComment() const;
        /// Returns true if supports toggle block comment for that language
        bool supportsToggleBlockComment() const;
        /// Returns true if supports smart indent for that language
        bool supportsSmartIndents() const;
    }

    /// Categorize characters in content by token types
    void updateHighlight(const dstring[] lines, TokenPropString[] props, int startLine, int endLine);

    /// Find paired bracket `{}` `()` `[]` for char at position `p`.
    /// Returns: Paired char position or `p` if not found or not a bracket.
    TextPosition findPairedBracket(TextPosition p);

    /// Returns true if can toggle line comments for specified text range
    bool canToggleLineComment(TextRange range) const;
    /// Toggle line comments for specified text range
    void toggleLineComment(TextRange range, Object source);

    /// Returns true if can toggle block comments for specified text range
    bool canToggleBlockComment(TextRange range) const;
    /// Toggle block comments for specified text range
    void toggleBlockComment(TextRange range, Object source);

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

    private ubyte sz = 4;

    this(int size)
    {
        sz = cast(ubyte)clamp(size, 1, 16);
    }
}

/// Editable multiline text
class EditableContent : TextContent
{
    @property
    {
        bool modified() const
        {
            return _undoBuffer.modified;
        }

        inout(SyntaxSupport) syntaxSupport() inout { return _syntaxSupport; }
        /// ditto
        void syntaxSupport(SyntaxSupport syntax)
        {
            _syntaxSupport = syntax;
            if (syntax)
            {
                syntax.content = this;
                updateTokenProps(0, lineCount);
            }
        }

        /// Returns true if content has syntax highlight handler set
        bool hasSyntaxHighlight() const
        {
            return _syntaxSupport !is null;
        }

        /// True if smart indents are supported
        bool supportsSmartIndents() const
        {
            return _syntaxSupport && _syntaxSupport.supportsSmartIndents;
        }

        ref LineIcons lineIcons() { return _lineIcons; }

        EditStateMark[] editMarks() { return _editMarks; }

        /// Returns all lines concatenated by '\n' delimiter
        dstring text() const
        {
            if (lineCount == 0)
                return null;
            if (lineCount == 1)
                return lines[0];
            // concat lines
            dchar[] buf;
            foreach (i, item; lines)
            {
                if (i)
                    buf ~= EOL;
                buf ~= item;
            }
            return cast(dstring)buf;
        }
        /// Replace whole text with another content
        void text(dstring newContent)
        {
            clearUndo();
            setStr(newContent);
            if (lineCount == 0)
                append(null);
            updateTokenProps(0, lineCount);
            notifyContentReplaced();
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
    Signal!ContentChangeHandler onContentChange;
    /// Listeners for mark changes after edit operation
    Signal!MarksChangeHandler onMarksChange;

    private
    {
        UndoBuffer _undoBuffer;
        SyntaxSupport _syntaxSupport;
        LineIcons _lineIcons;

        /// Token properties by lines - for syntax highlight
        TokenPropString[] _tokenProps;

        /// Line edit marks
        EditStateMark[] _editMarks;
    }

    this()
    {
        super(1); // initial state: single empty line
        afterChange ~= &handleChange;
        _editMarks.length = 1;
        _undoBuffer = new UndoBuffer;
    }

    protected void handleChange(ListChange op, uint index, uint count)
    {
        if (op == ListChange.replaceAll)
        {
            _tokenProps.length = count;
            _editMarks.length = count;
            _editMarks[] = EditStateMark.unchanged;
            return;
        }
        if (count > 0)
        {
            if (op == ListChange.append)
            {
                _tokenProps.length += count;
                _editMarks.length += count;
            }
            else if (op == ListChange.insert)
            {
                _tokenProps.length += count;
                _editMarks.length += count;
                foreach_reverse (i; index + count .. _tokenProps.length)
                {
                    _tokenProps[i] = _tokenProps[i - count];
                    _editMarks[i] = _editMarks[i - count];
                }
                foreach (i; index .. index + count)
                {
                    _tokenProps[i] = null;
                    _editMarks[i] = EditStateMark.changed;
                }
            }
            else if (op == ListChange.remove)
            {
                foreach (i; index .. _tokenProps.length - count)
                {
                    _tokenProps[i] = _tokenProps[i + count];
                    _editMarks[i] = _editMarks[i + count];
                }
                foreach (i; _tokenProps.length - count .. _tokenProps.length)
                {
                    _tokenProps[i] = null; // free unused line references
                    _editMarks[i] = EditStateMark.unchanged;
                }
                _tokenProps.length -= count;
                _editMarks.length -= count;
            }
        }
    }

    static alias isAlphaForWordSelection = isAlNum;

    static LineRange findWordBoundsInLine(dstring s, int p)
    {
        const len = s.length;
        if (p < 0 || len < p || len == 0)
            return LineRange(p, p);

        const leftChar = p > 0 ? s[p - 1] : 0;
        const rightChar = p + 1 < len ? s[p + 1] : 0;
        const centerChar = p < len ? s[p] : 0;
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
            return LineRange(p, p);

        auto r = LineRange(p, p);
        while (r.start > 0 && isAlphaForWordSelection(s[r.start - 1]))
            r.start--;
        while (r.end + 1 < len && isAlphaForWordSelection(s[r.end + 1]))
            r.end++;
        r.end++;
        return r;
    }

    /// Get word bounds by position
    TextRange wordBounds(TextPosition pos)
    {
        auto r = TextRange(pos, pos);
        if (pos.line < 0 || lineCount <= pos.line)
            return r;

        dstring s = line(pos.line);
        const lr = findWordBoundsInLine(s, pos.pos);
        r.start.pos = lr.start;
        r.end.pos = lr.end;
        return r;
    }

    /// Call listener to say that whole content is replaced e.g. by loading from file
    private void notifyContentReplaced()
    {
        TextRange rangeBefore;
        TextRange rangeAfter;
        // notify about content change
        handleContentChange(new EditOperation(EditAction.replaceContent), rangeBefore, rangeAfter, this);
    }

    /// Call listener to say that content is saved
    private void notifyContentSaved()
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
            _syntaxSupport.updateHighlight(lines, _tokenProps, startLine, endLine);
        }
    }

    protected void markChangedLines(int startLine, int endLine)
    {
        foreach (i; startLine .. endLine)
        {
            _editMarks[i] = EditStateMark.changed;
        }
    }

    /// Set props arrays size equal to text line sizes and fill with unknown token
    protected void clearTokenProps(int startLine, int endLine)
    {
        foreach (i; startLine .. endLine)
        {
            if (hasSyntaxHighlight)
            {
                _tokenProps[i].length = lineLength(i);
                _tokenProps[i][] = TOKEN_UNKNOWN;
            }
            else
                _tokenProps[i] = null; // no token props
        }
    }

    void clearEditMarks()
    {
        _editMarks.length = lineCount;
        _editMarks[] = EditStateMark.unchanged;
    }

    /// Clear content
    void clear()
    {
        removeAll();
        clearUndo();
        clearEditMarks();
    }

    /// Returns line token properties one item per character (index is 0 based line number)
    TokenPropString lineTokenProps(int index)
    {
        return 0 <= index && index < _tokenProps.length ? _tokenProps[index] : null;
    }

    /// Returns token properties character position
    TokenProp tokenProp(TextPosition p)
    {
        if (0 <= p.line && p.line < _tokenProps.length)
            if (0 <= p.pos && p.pos < _tokenProps[p.line].length)
                return _tokenProps[p.line][p.pos];
        return 0;
    }

    /// Returns access to line edit mark by line index (0 based)
    ref EditStateMark editMark(int index)
    {
        assert(0 <= index && index < _editMarks.length);
        return _editMarks[index];
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
        const s = line(lineIndex);
        if (s is null)
            return res;
        int x;
        for (int i; i < s.length; i++)
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
        const s = line(lineIndex);
        if (s is null)
            return res;
        res.len = cast(int)s.length;
        int x;
        for (int i; i < s.length; i++)
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

    /// Returns true if the line with `index` is empty (has length 0 or consists only of spaces and tabs)
    bool lineIsEmpty(int index) const
    {
        foreach (ch; line(index))
            if (ch != ' ' && ch != '\t')
                return false;
        return true;
    }

    /// Convert range to cover full lines
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

    void handleContentChange(EditOperation op, ref TextRange rangeBefore, ref TextRange rangeAfter, Object source)
    {
        // update highlight if necessary
        updateTokenProps(rangeAfter.start.line, rangeAfter.end.line + 1);
        LineIcon[] moved;
        LineIcon[] removed;
        if (_lineIcons.updateLinePositions(rangeBefore, rangeAfter, moved, removed))
        {
            if (onMarksChange.assigned)
                onMarksChange(moved, removed);
        }
        // call listeners
        if (onContentChange.assigned)
            onContentChange(op, rangeBefore, rangeAfter, source);
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

    /// Inserts or removes lines, removes text in range
    protected void replaceRange(TextRange before, TextRange after, dstring[] newContent, EditStateMark[] marks = null)
    {
        const dstring firstLineBefore = line(before.start.line);
        const dstring lastLineBefore = before.singleLine ? firstLineBefore : line(before.end.line);
        const dstring firstLineHead = 0 < before.start.pos && before.start.pos <= firstLineBefore.length ?
            firstLineBefore[0 .. before.start.pos] : null;
        const dstring lastLineTail = 0 <= before.end.pos && before.end.pos < lastLineBefore.length ?
            lastLineBefore[before.end.pos .. $] : null;

        const int linesBefore = before.lines;
        const int linesAfter = after.lines;
        if (linesBefore < linesAfter)
        {
            // add more lines
            dstring[] array = new dstring[linesAfter - linesBefore]; // TODO: remove allocation
            insertItems(before.start.line + 1, array);
        }
        else if (linesBefore > linesAfter)
        {
            // remove extra lines
            removeItems(before.start.line + 1, linesBefore - linesAfter);
        }

        const start = after.start.line;
        const end = after.end.line;
        foreach (int i; start .. end + 1)
        {
            if (i - start < marks.length)
            {
                _editMarks[i] = marks[i - start];
            }
            dstring insertion = newContent[i - start]; // no dup needed
            if (i == start && i == end)
            {
                insertion = firstLineHead ~ insertion ~ lastLineTail;
            }
            else if (i == start)
            {
                insertion = firstLineHead ~ insertion;
            }
            else if (i == end)
            {
                insertion = insertion ~ lastLineTail;
            }
            replace(i, insertion);
        }
        clearTokenProps(start, end + 1);
        if (!marks.length)
            markChangedLines(start, end + 1);
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
                if (p.line < lineCount - 1)
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
            TextRange rangeBefore = op.rangeBefore;
            assert(rangeBefore.start <= rangeBefore.end);
            dstring[] oldcontent = rangeText(rangeBefore);
            EditStateMark[] oldmarks = rangeMarks(rangeBefore);
            dstring[] newcontent = op.content;
            if (newcontent.length == 0)
                newcontent ~= ""d;
            TextRange rangeAfter = op.rangeBefore;
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
            op.setNewRange(rangeAfter, oldcontent, oldmarks);
            replaceRange(rangeBefore, rangeAfter, newcontent);
            _undoBuffer.push(op);
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
        auto op = cast(EditOperation)_undoBuffer.undo();
        TextRange rangeBefore = op.range;
        dstring[] oldcontent = op.content;
        dstring[] newcontent = op.contentBefore;
        EditStateMark[] newmarks = op.editMarksBefore; //_undoBuffer.savedInUndo() ?  : null;
        TextRange rangeAfter = op.rangeBefore;
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
        auto op = cast(EditOperation)_undoBuffer.redo();
        TextRange rangeBefore = op.rangeBefore;
        dstring[] oldcontent = op.contentBefore;
        dstring[] newcontent = op.content;
        TextRange rangeAfter = op.range;
        //Log.d("Redoing op rangeBefore=", rangeBefore, " contentBefore=`", oldcontent, "` rangeAfter=", rangeAfter, " contentAfter=`", newcontent, "`");
        replaceRange(rangeBefore, rangeAfter, newcontent);
        handleContentChange(op, rangeBefore, rangeAfter, source ? source : this);
        return true;
    }

    /// Clear undo/redo history
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
            LineStream stream = LineStream.create(f, fname);
            dstring[] lines;
            while (true)
            {
                dchar[] s = stream.readLine();
                if (s is null)
                    break;
                lines ~= s.idup;
            }
            if (stream.errorCode != 0)
            {
                append(null);
                Log.e("Error ", stream.errorCode, " ", stream.errorMessage, " -- at line ",
                        stream.errorLine, " position ", stream.errorPos);
                notifyContentReplaced();
                return false;
            }
            // EOF
            replaceAll(lines);
            clearTokenProps(0, lineCount);
            _format = stream.textFormat;
            debug (FileFormats)
                Log.d("loaded file:", filename, " format detected:", _format);
            notifyContentReplaced();
            return true;
        }
        catch (Exception e)
        {
            append(null);
            Log.e("Exception while trying to read file ", fname, " ", e.toString);
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
            foreach (line; lines)
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
    bookmark,
    breakpoint,
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

    /// Returns item by index, or `null` if index out of bounds
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
