/**


Copyright: Vadim Lopatin 2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.textsource;

import std.array;
import std.utf;

/**
    Source file information.
    Even if contains only file name, it's better to use it instead of string -
    object reference size is twice less than array ref.
*/
class SourceFile
{
    protected string _filename;
    @property string filename()
    {
        return _filename;
    }

    public this(string filename)
    {
        _filename = filename;
    }

    override @property string toString() const
    {
        return _filename;
    }
}

/// Source lines for tokenizer
interface SourceLines
{
    /// Source file
    @property SourceFile file();
    /// Last read line
    @property uint line();
    /// Source encoding
    //@property EncodingType encoding() { return _encoding; }
    /// Error code
    @property int errorCode();
    /// Error message
    @property string errorMessage();
    /// Error line
    @property int errorLine();
    /// Error position
    @property int errorPos();
    /// End of file reached
    @property bool eof();

    /// Read line, return null if EOF reached or error occured
    dchar[] readLine();
}

const TEXT_SOURCE_ERROR_EOF = 1;

/// Simple text source based on array
class ArraySourceLines : SourceLines
{
    protected SourceFile _file;
    protected uint _line;
    protected uint _firstLine;
    protected dstring[] _lines;
    static __gshared protected dchar[] _emptyLine = ""d.dup;

    this()
    {
    }

    this(dstring[] lines, SourceFile file, uint firstLine = 0)
    {
        initialize(lines, file, firstLine);
    }

    this(string code, string filename)
    {
        _lines = (toUTF32(code)).split("\n");
        _file = new SourceFile(filename);
    }

    void close()
    {
        _lines = null;
        _line = 0;
        _firstLine = 0;
        _file = null;
    }

    void initialize(dstring[] lines, SourceFile file, uint firstLine = 0)
    {
        _lines = lines;
        _firstLine = firstLine;
        _line = 0;
        _file = file;
    }

    bool reset(int line)
    {
        _line = line;
        return true;
    }

    /// End of file reached
    override @property bool eof()
    {
        return _line >= _lines.length;
    }
    /// Source file
    override @property SourceFile file()
    {
        return _file;
    }
    /// Last read line
    override @property uint line()
    {
        return _line + _firstLine;
    }
    /// Source encoding
    //@property EncodingType encoding() { return _encoding; }
    /// Error code
    override @property int errorCode()
    {
        return 0;
    }
    /// Error message
    override @property string errorMessage()
    {
        return "";
    }
    /// Error line
    override @property int errorLine()
    {
        return 0;
    }
    /// Error position
    override @property int errorPos()
    {
        return 0;
    }

    /// Read line, return null if EOF reached or error occured
    override dchar[] readLine()
    {
        if (_line < _lines.length)
        {
            if (_lines[_line])
                return cast(dchar[])_lines[_line++];
            _line++;
            return _emptyLine;
        }
        return null; // EOF
    }
}
