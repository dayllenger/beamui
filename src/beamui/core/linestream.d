/**
Line stream reader and writer.

Implements class LineStream for reading of unicode text from stream and returning it by lines.

Support utf8, utf16, utf32 be and le encodings, and line endings - according to D language source file specification.

Low resource consuming. Doesn't flood with GC allocations. Dup line if you want to store it somewhere.

Tracks line number.


Synopsis:
---
import beamui.core.linestream;
import std.stdio : writeln, writefln;

string filename = "somefile.d";
writeln("opening file");
auto fstream = new FileInputStream(filename);
scope (exit)
    fstream.close();

try
{
    auto lines = LineStream.create(fstream, filename);
    while (true)
    {
        dchar[] s = lines.readLine();
        if (s is null)
            break;
        writefln("line %s: %s", lines.line, s);
    }
    if (lines.errorCode != 0)
    {
        writefln("Error(%s,%s) %s: %s", lines.errorLine, lines.errorPos, lines.errorCode, lines.errorMessage);
    }
    else
    {
        writeln("EOF reached");
    }
}
catch (Exception e)
{
    writeln("Exception " ~ e.toString);
}
---

Copyright: Vadim Lopatin 2014-2015
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.linestream;

public import beamui.core.streams;
import std.conv : to;
import std.utf : encode;

/// File encoding
enum EncodingType
{
    /// Utf-8 unicode
    UTF8,
    /// Utf-16 unicode big endian
    UTF16BE,
    /// Utf-16 unicode little endian
    UTF16LE,
    /// Utf-32 unicode big endian
    UTF32BE,
    /// Utf-32 unicode little endian
    UTF32LE,
    /// Plain ASCII (character codes must be <= 127)
    ASCII,
    /// Encoding is unknown
    UNKNOWN
}
/// Line ending style
enum LineEnding
{
    /// LF (0x0A) - unix style
    LF,
    /// CR followed by LF (0x0D,0x0A) - windows style
    CRLF,
    /// CR (0x0D) - mac style
    CR,
    /// Unknown line ending
    UNKNOWN,
    /// Mixed line endings detected
    MIXED
}

/// Text file format
struct TextFileFormat
{
    /// Character encoding
    EncodingType encoding;
    /// Line ending style
    LineEnding lineEnding;
    /// Byte order mark character flag
    bool bom;

    string toString() const
    {
        return to!string(encoding) ~ " " ~ to!string(lineEnding) ~ (bom ? " bom" : "");
    }
}

/// Text file writer which supports different text file formats
class OutputLineStream
{
    private
    {
        OutputStream _stream;
        string _filename;
        TextFileFormat _format;
        bool _firstLine;
        char[] _buf;
        int _len;

        static immutable int MAX_BUFFER_SIZE = 0x10000; // 64K
    }

    /// Create
    this(OutputStream stream, string filename, TextFileFormat format)
    {
        _stream = stream;
        _filename = filename;
        _format = format;
        _firstLine = true;
        // fix format
        if (_format.encoding == EncodingType.UNKNOWN || _format.encoding == EncodingType.ASCII)
            _format.encoding = EncodingType.UTF8;
        if (_format.lineEnding == LineEnding.UNKNOWN || _format.lineEnding == LineEnding.MIXED)
        {
            version (Windows)
            {
                _format.lineEnding = LineEnding.CRLF;
            }
            else
            {
                _format.lineEnding = LineEnding.LF;
            }
        }
    }

    protected void flush()
    {
        if (_len > 0)
        {
            _stream.write(cast(ubyte[])_buf[0 .. _len]);
            _len = 0;
        }
    }

    /// Convert character encoding and write to output stream
    protected void convertAndWrite(dstring s)
    {
        /// Reserve buf space
        if (_buf.length < _len + s.length * 4 + 4)
            _buf.length = _len + s.length * 4 + 4;
        switch (_format.encoding) with (EncodingType)
        {
        case UTF8:
        default:
            char[4] d;
            foreach (i; 0 .. s.length)
            {
                size_t bytes = encode(d, s[i]);
                foreach (j; 0 .. bytes)
                    _buf[_len++] = d[j];
            }
            break;
        case UTF16BE:
            wchar[2] d;
            foreach (i; 0 .. s.length)
            {
                size_t n = encode(d, s[i]);
                foreach (j; 0 .. n)
                {
                    _buf[_len++] = cast(char)(d[j] >> 8);
                    _buf[_len++] = cast(char)(d[j] & 0xFF);
                }
            }
            break;
        case UTF16LE:
            wchar[2] d;
            foreach (i; 0 .. s.length)
            {
                size_t n = encode(d, s[i]);
                foreach (j; 0 .. n)
                {
                    _buf[_len++] = cast(char)(d[j] & 0xFF);
                    _buf[_len++] = cast(char)(d[j] >> 8);
                }
            }
            break;
        case UTF32LE:
            foreach (i; 0 .. s.length)
            {
                dchar ch = s[i];
                _buf[_len++] = cast(char)((ch >> 0) & 0xFF);
                _buf[_len++] = cast(char)((ch >> 8) & 0xFF);
                _buf[_len++] = cast(char)((ch >> 16) & 0xFF);
                _buf[_len++] = cast(char)((ch >> 24) & 0xFF);
            }
            break;
        case UTF32BE:
            foreach (i; 0 .. s.length)
            {
                dchar ch = s[i];
                _buf[_len++] = cast(char)((ch >> 24) & 0xFF);
                _buf[_len++] = cast(char)((ch >> 16) & 0xFF);
                _buf[_len++] = cast(char)((ch >> 8) & 0xFF);
                _buf[_len++] = cast(char)((ch >> 0) & 0xFF);
            }
            break;
        }
        if (_len > MAX_BUFFER_SIZE)
            flush();
    }

    /// Write single line
    void writeLine(dstring line)
    {
        if (_firstLine)
        {
            if (_format.bom)
                convertAndWrite("\uFEFF"d); // write BOM
            _firstLine = false;
        }
        convertAndWrite(line);
        switch (_format.lineEnding)
        {
        case LineEnding.LF:
            convertAndWrite("\n"d);
            break;
        case LineEnding.CR:
            convertAndWrite("\r"d);
            break;
        default:
        case LineEnding.CRLF:
            convertAndWrite("\r\n"d);
            break;
        }
    }

    /// Close stream
    void close()
    {
        flush();
        _stream.close();
        _buf = null;
    }
}

/**
    Support reading of file (or string in memory) by lines

    Support utf8, utf16, utf32 be and le encodings, and line endings - according to D language source file specification.

    Low resource consuming. Doesn't flood with GC allocations. Dup line if you want to store it somewhere.

    Tracks line number.
*/
class LineStream
{
    @property
    {
        /// Returns file name
        string filename() const { return _filename; }
        /// Returns current line number
        uint line() const { return _line; }
        /// Returns file encoding EncodingType
        EncodingType encoding() const { return _encoding; }

        TextFileFormat textFormat() const
        {
            LineEnding le = LineEnding.CRLF;
            if (_crlfCount)
            {
                if (_crCount == _lfCount)
                    le = LineEnding.CRLF;
                else
                    le = LineEnding.MIXED;
            }
            else if (_crCount > _lfCount)
            {
                le = LineEnding.CR;
            }
            else if (_lfCount > _crCount)
            {
                le = LineEnding.LF;
            }
            else
            {
                le = LineEnding.MIXED;
            }
            return TextFileFormat(_encoding, le, _bomDetected);
        }

        /// Returns error code
        int errorCode() const { return _errorCode; }
        /// Returns error message
        string errorMessage() const { return _errorMessage; }
        /// Returns line where error is found
        int errorLine() const { return _errorLine; }
        /// Returns line position (number of character in line) where error is found
        int errorPos() const { return _errorPos; }
    }

    /// Error codes
    enum ErrorCodes
    {
        /// Invalid character for current encoding
        INVALID_CHARACTER
    }

    private
    {
        InputStream _stream;
        string _filename;
        ubyte[] _buf; /// Stream reading buffer
        uint _pos; /// Reading position of stream buffer
        uint _len; /// Number of bytes in stream buffer
        bool _streamEof; // True if input stream is in EOF state
        uint _line; /// Current line number

        uint _textPos; /// Start of text line in text buffer
        uint _textLen; /// Position of last filled char in text buffer + 1
        dchar[] _textBuf; /// Text buffer
        bool _eof; /// End of file, no more lines

        immutable EncodingType _encoding;

        int _errorCode;
        string _errorMessage;
        uint _errorLine;
        uint _errorPos;

        bool _bomDetected;
        int _crCount;
        int _lfCount;
        int _crlfCount;
    }

    /// Open file with known encoding
    protected this(InputStream stream, string filename, EncodingType encoding, ubyte[] buf, uint offset, uint len)
    {
        _filename = filename;
        _stream = stream;
        _encoding = encoding;
        _buf = buf;
        _len = len;
        _pos = offset;
        _streamEof = _stream.eof;
    }

    /// This constructor was created for unittests only
    protected this()
    {
        _encoding = EncodingType.UTF8;
    }

    /// Returns slice of bytes available in buffer
    protected uint readBytes()
    {
        uint bytesLeft = _len - _pos;
        if (_streamEof || bytesLeft > QUARTER_BYTE_BUFFER_SIZE)
            return bytesLeft;
        if (_pos > 0)
        {
            foreach (i; 0 .. bytesLeft)
                _buf[i] = _buf[i + _pos];
            _len = bytesLeft;
            _pos = 0;
        }
        uint bytesRead = cast(uint)_stream.read(_buf[_len .. BYTE_BUFFER_SIZE]);
        _len += bytesRead;
        _streamEof = _stream.eof;
        return _len - _pos; //_buf[_pos .. _len];
    }

    /// When bytes consumed from byte buffer, call this method to update position
    protected void consumedBytes(uint count)
    {
        _pos += count;
    }

    /// Reserve text buffer for specified number of characters, and return pointer to first free character in buffer
    protected dchar* reserveTextBuf(uint len)
    {
        // create new text buffer if necessary
        if (_textBuf == null)
        {
            if (len < TEXT_BUFFER_SIZE)
                len = TEXT_BUFFER_SIZE;
            _textBuf = new dchar[len];
            return _textBuf.ptr;
        }
        uint spaceLeft = cast(uint)_textBuf.length - _textLen;
        if (spaceLeft >= len)
            return _textBuf.ptr + _textLen;
        // move text to beginning of buffer, if necessary
        if (_textPos > _textBuf.length / 2)
        {
            uint charCount = _textLen - _textPos;
            dchar* p = _textBuf.ptr;
            foreach (i; 0 .. charCount)
                p[i] = p[i + _textPos];
            _textLen = charCount;
            _textPos = 0;
        }
        // resize buffer if necessary
        if (_textLen + len > _textBuf.length)
        {
            // resize buffer
            uint newsize = cast(uint)_textBuf.length * 2;
            if (newsize < _textLen + len)
                newsize = _textLen + len;
            _textBuf.length = newsize;
        }
        return _textBuf.ptr + _textLen;
    }

    protected void appendedText(uint len)
    {
        _textLen += len;
    }

    protected void setError(int code, string message, uint errorLine, uint errorPos)
    {
        _errorCode = code;
        _errorMessage = message;
        _errorLine = errorLine;
        _errorPos = errorPos;
    }

    // override to decode text
    abstract protected uint decodeText();

    /// Unknown line position
    immutable static uint LINE_POSITION_UNDEFINED = uint.max;

    /// Read line from stream. Returns null on end of file or read error
    dchar[] readLine()
    {
        if (_errorCode != 0)
            return null; // error detected
        if (_eof)
            return null;

        _line++;
        uint p = 0;
        uint eol = LINE_POSITION_UNDEFINED;
        uint eof = LINE_POSITION_UNDEFINED;
        uint lastchar = LINE_POSITION_UNDEFINED;
        do
        {
            if (_errorCode != 0)
            {
                return null; // error detected
            }
            uint charsLeft = _textLen - _textPos;
            if (p >= charsLeft)
            {
                uint decodedChars = decodeText();
                if (_errorCode != 0)
                {
                    return null; // error detected
                }
                charsLeft = _textLen - _textPos;
                if (decodedChars == 0)
                {
                    eol = charsLeft;
                    eof = charsLeft;
                    lastchar = charsLeft;
                    break;
                }
            }
            for (; p < charsLeft; p++)
            {
                dchar ch = _textBuf[_textPos + p];
                if (ch == '\r')
                { // CR
                    lastchar = p;
                    if (p == charsLeft - 1)
                    {
                        // need one more char to check if it's 0D0A or just 0D eol
                        //writeln("read one more char for 0D0A detection");
                        decodeText();
                        if (_errorCode != 0)
                        {
                            return null; // error detected
                        }
                        charsLeft = _textLen - _textPos;
                    }
                    dchar ch2 = (p < charsLeft - 1) ? _textBuf[_textPos + p + 1] : 0;
                    if (ch2 == '\n')
                    { // LF
                        // CRLF
                        eol = p + 2;
                        _lfCount++;
                        _crCount++;
                        _crlfCount++;
                    }
                    else
                    {
                        // just CR
                        eol = p + 1;
                        _crCount++;
                    }
                    break;
                }
                else if (ch == '\n' || ch == 0x2028 || ch == 0x2029)
                {
                    // single char eoln
                    lastchar = p;
                    eol = p + 1;
                    _lfCount++;
                    break;
                }
                else if (ch == 0 || ch == 0x001A)
                {
                    // eof
                    //writeln("EOF char found");
                    lastchar = p;
                    eol = eof = p + 1;
                    break;
                }
            }
        }
        while (eol == LINE_POSITION_UNDEFINED);
        uint lineStart = _textPos;
        uint lineEnd = _textPos + lastchar;
        _textPos += eol; // consume text
        if (eof != LINE_POSITION_UNDEFINED)
        {
            _eof = true;
            if (lineStart >= lineEnd)
            {
                return null; // eof
            }
        }
        // return slice with decoded line
        return _textBuf[lineStart .. lineEnd];
    }

    protected immutable static int TEXT_BUFFER_SIZE = 1024;
    protected immutable static int BYTE_BUFFER_SIZE = 512;
    protected immutable static int QUARTER_BYTE_BUFFER_SIZE = BYTE_BUFFER_SIZE / 4;

    /// Factory method for string parser
    static LineStream create(string code, string filename = "")
    {
        uint len = cast(uint)code.length;
        ubyte[] data = new ubyte[len + 3];
        foreach (i; 0 .. len)
            data[i + 3] = code[i];
        // BOM for UTF8
        data[0] = 0xEF;
        data[1] = 0xBB;
        data[2] = 0xBF;
        InputStream stream = new MemoryInputStream(data);
        return create(stream, filename);
    }

    /// Factory for InputStream parser
    static LineStream create(InputStream stream, string filename, bool autodetectUTFIfNoBOM = true)
    {
        ubyte[] buf = new ubyte[BYTE_BUFFER_SIZE];
        buf[0] = buf[1] = buf[2] = buf[3] = 0;
        if (!stream.isOpen)
            return null;
        uint len = cast(uint)stream.read(buf);
        LineStream res = null;
        if (buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF)
        {
            res = new Utf8LineStream(stream, filename, buf, len, 3);
        }
        else if (buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0xFE && buf[3] == 0xFF)
        {
            res = new Utf32beLineStream(stream, filename, buf, len);
        }
        else if (buf[0] == 0xFF && buf[1] == 0xFE && buf[2] == 0x00 && buf[3] == 0x00)
        {
            res = new Utf32leLineStream(stream, filename, buf, len);
        }
        else if (buf[0] == 0xFE && buf[1] == 0xFF)
        {
            res = new Utf16beLineStream(stream, filename, buf, len);
        }
        else if (buf[0] == 0xFF && buf[1] == 0xFE)
        {
            res = new Utf16leLineStream(stream, filename, buf, len);
        }
        if (res)
        {
            res._bomDetected = true;
        }
        else
        {
            if (autodetectUTFIfNoBOM)
            {
                res = new Utf8LineStream(stream, filename, buf, len, 0);
            }
            else
            {
                res = new AsciiLineStream(stream, filename, buf, len);
            }
        }
        return res;
    }

    protected bool invalidCharFlag;
    protected void invalidCharError()
    {
        uint pos = _textLen - _textPos + 1;
        setError(ErrorCodes.INVALID_CHARACTER,
                "Invalid character in line " ~ to!string(_line) ~ ":" ~ to!string(pos), _line, pos);
    }
}

private class AsciiLineStream : LineStream
{
    this(InputStream stream, string filename, ubyte[] buf, uint len)
    {
        super(stream, filename, EncodingType.ASCII, buf, 0, len);
    }

    override uint decodeText()
    {
        if (invalidCharFlag)
        {
            invalidCharError();
            return 0;
        }
        uint bytesAvailable = readBytes();
        if (bytesAvailable == 0)
            return 0; // nothing to decode
        uint len = bytesAvailable;
        ubyte* bytes = _buf.ptr + _pos;
        dchar* text = reserveTextBuf(len);
        uint i;
        for (; i < len; i++)
        {
            ubyte ch = bytes[i];
            if (ch & 0x80)
            {
                // invalid character
                invalidCharFlag = true;
                break;
            }
            text[i] = ch;
        }
        consumedBytes(i);
        appendedText(i);
        return len;
    }
}

private class Utf8LineStream : LineStream
{
    this(InputStream stream, string filename, ubyte[] buf, uint len, int skip)
    {
        super(stream, filename, EncodingType.UTF8, buf, skip, len);
    }

    uint decodeBytes(ubyte* b, in uint bleft, out uint ch, out bool needMoreFlag)
    {
        uint bread = 0;
        uint ch0 = b[0];
        if (!(ch0 & 0x80))
        {
            // 0x00..0x7F single byte
            // 0x80 == 10000000
            // !(ch0 & 0x80) => ch0 < 10000000
            ch = ch0;
            bread = 1;
        }
        else if ((ch0 & 0xE0) == 0xC0)
        {
            // two bytes 110xxxxx 10xxxxxx
            if (bleft < 2)
            {
                needMoreFlag = true;
                return 0;
            }
            uint ch1 = b[1];
            if ((ch1 & 0xC0) != 0x80)
            {
                return 0;
            }
            ch = ((ch0 & 0x1F) << 6) | (ch1 & 0x3F);
            bread = 2;
        }
        else if ((ch0 & 0xF0) == 0xE0)
        {
            // three bytes 1110xxxx 10xxxxxx 10xxxxxx
            if (bleft < 3)
            {
                needMoreFlag = true;
                return 0;
            }
            uint ch1 = b[1];
            uint ch2 = b[2];
            if ((ch1 & 0xC0) != 0x80 || (ch2 & 0xC0) != 0x80)
            {
                return 0;
            }
            ch = ((ch0 & 0x0F) << 12) | ((ch1 & 0x3F) << 6) | (ch2 & 0x3F);
            bread = 3;
        }
        else if ((ch0 & 0xF8) == 0xF0)
        {
            // four bytes 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
            if (bleft < 4)
            {
                needMoreFlag = true;
                return 0;
            }
            uint ch1 = b[1];
            uint ch2 = b[2];
            uint ch3 = b[3];
            if ((ch1 & 0xC0) != 0x80 || (ch2 & 0xC0) != 0x80 || (ch3 & 0xC0) != 0x80)
            {
                return 0;
            }
            ch = ((ch0 & 0x07) << 18) | ((ch1 & 0x3F) << 12) | ((ch2 & 0x3F) << 6) | (ch3 & 0x3F);
            bread = 4;
        }
        else if ((ch0 & 0xFC) == 0xF8)
        {
            // five bytes 111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
            if (bleft < 5)
            {
                needMoreFlag = true;
                return 0;
            }
            uint ch1 = b[1];
            uint ch2 = b[2];
            uint ch3 = b[3];
            uint ch4 = b[4];
            if ((ch1 & 0xC0) != 0x80 || (ch2 & 0xC0) != 0x80 || (ch3 & 0xC0) != 0x80 || (ch4 & 0xC0) != 0x80)
            {
                return 0;
            }
            ch = ((ch0 & 0x03) << 24) | ((ch1 & 0x3F) << 18) | ((ch2 & 0x3F) << 12) | ((ch3 & 0x3F) << 6) | (ch4 & 0x3F);
            bread = 5;
        }
        else if ((ch0 & 0xFE) == 0xFC)
        {
            // six bytes 1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
            if (bleft < 6)
            {
                needMoreFlag = true;
                return 0;
            }

            uint ch1 = b[1];
            uint ch2 = b[2];
            uint ch3 = b[3];
            uint ch4 = b[4];
            uint ch5 = b[5];
            if ((ch1 & 0xC0) != 0x80 || (ch2 & 0xC0) != 0x80 || (ch3 & 0xC0) != 0x80 ||
                    (ch4 & 0xC0) != 0x80 || (ch5 & 0xC0) != 0x80)
            {
                return 0;
            }
            ch = ((ch0 & 0x01) << 30) | ((ch1 & 0x3F) << 24) | ((ch2 & 0x3F) << 18) | (
                    (ch3 & 0x3F) << 12) | ((ch4 & 0x3F) << 6) | (ch5 & 0x3F);
            bread = 5;
        }
        if ((ch >= 0xd800 && ch < 0xe000) || (ch > 0x10FFFF))
        {
            return 0;
        }
        return bread;
    }

    /// This constructor was created for unittests only
    protected this()
    {

    }

    unittest
    {
        auto o = new Utf8LineStream;
        ubyte[] buffer = new ubyte[4];
        ubyte* bytes = buffer.ptr;
        uint ch;
        bool needMoreFlag;
        uint bread;

        //convert simple character
        buffer[0] = '/';
        bread = o.decodeBytes(bytes, 1, ch, needMoreFlag);
        assert(!needMoreFlag);
        assert(bread == 1);
        assert(ch == '/');
        //writefln("/ as hex: 0x%32x,0x%32x", ch,'/');

        //convert 2byte character
        buffer[0] = 0xc3;
        buffer[1] = 0x84;
        bread = o.decodeBytes(bytes, 1, ch, needMoreFlag);
        assert(needMoreFlag);

        bread = o.decodeBytes(bytes, 2, ch, needMoreFlag);
        assert(!needMoreFlag);
        assert(bread == 2);
        assert(ch == 'Ä');
        //writefln("Ä as hex: 0x%32x,0x%32x", ch,'Ä');

        //convert 3byte character
        buffer[0] = 0xe0;
        buffer[1] = 0xa4;
        buffer[2] = 0xb4;
        bread = o.decodeBytes(bytes, 2, ch, needMoreFlag);
        assert(needMoreFlag);

        bread = o.decodeBytes(bytes, 3, ch, needMoreFlag);
        assert(!needMoreFlag);
        assert(bread == 3);
        //writefln("ऴ as hex: 0x%32x,0x%32x", ch,'ऴ');
        assert(ch == 'ऴ');

        //regression test for https://github.com/buggins/dlangide/issues/65
        buffer[0] = 0xEB;
        buffer[1] = 0xB8;
        buffer[2] = 0x94;
        bread = o.decodeBytes(bytes, 3, ch, needMoreFlag);
        assert(!needMoreFlag);
        assert(bread == 3);
        //writefln("블 as hex: 0x%32x,0x%32x", ch,'블');
        assert(ch == '블');
    }

    override uint decodeText()
    {
        //number of bytesAvailable
        uint len = readBytes();
        if (len == 0)
            return 0; // nothing to decode

        if (invalidCharFlag)
        {
            invalidCharError();
            return 0;
        }
        ubyte* b = _buf.ptr + _pos;
        uint chars;
        uint maxResultingBytes = len * 2; //len*2 because worst case is if all input chars are singelbyte and resulting in two bytes
        dchar* text = reserveTextBuf(maxResultingBytes);
        uint i;
        bool needMoreFlag = false;
        for (; i < len; i++)
        {
            uint ch = 0;
            uint bleft = len - i;
            uint bread = decodeBytes(b + i, bleft, ch, needMoreFlag);

            if (needMoreFlag)
            {
                //decodeBytes needs more bytes, but nore more bytes left in the buffer
                break;
            }

            if (bread == 0)
            {
                //decodeBytes could not read any charater. stop procesing
                invalidCharFlag = true;
                break;
            }

            if (ch < 0x10000)
            {
                text[chars++] = ch;
            }
            else
            {
                uint lo = ch & 0x3FF;
                uint hi = ch >> 10;
                text[chars++] = (0xd800 | hi);
                text[chars++] = (0xdc00 | lo);
            }
            i += bread - 1;
        }
        consumedBytes(i);
        appendedText(chars);
        uint bleft = len - i;
        if (_streamEof && bleft > 0)
            invalidCharFlag = true; // incomplete character at end of stream
        return chars;
    }
}

private class Utf16beLineStream : LineStream
{
    this(InputStream stream, string filename, ubyte[] buf, uint len)
    {
        super(stream, filename, EncodingType.UTF16BE, buf, 2, len);
    }

    override uint decodeText()
    {
        if (invalidCharFlag)
        {
            invalidCharError();
            return 0;
        }
        uint bytesAvailable = readBytes();
        if (bytesAvailable == 0)
            return 0; // nothing to decode
        uint len = bytesAvailable;
        uint chars;
        ubyte* b = _buf.ptr + _pos;
        dchar* text = reserveTextBuf(len / 2 + 1);
        uint i;
        for (; i < len - 1; i += 2)
        {
            uint ch0 = b[i];
            uint ch1 = b[i + 1];
            uint ch = (ch0 << 8) | ch1;
            // TODO: check special cases
            text[chars++] = ch;
        }
        consumedBytes(i);
        appendedText(chars);
        uint bleft = len - i;
        if (_streamEof && bleft > 0)
            invalidCharFlag = true; // incomplete character at end of stream
        return chars;
    }
}

private class Utf16leLineStream : LineStream
{
    this(InputStream stream, string filename, ubyte[] buf, uint len)
    {
        super(stream, filename, EncodingType.UTF16LE, buf, 2, len);
    }

    override uint decodeText()
    {
        if (invalidCharFlag)
        {
            invalidCharError();
            return 0;
        }
        uint bytesAvailable = readBytes();
        if (bytesAvailable == 0)
            return 0; // nothing to decode
        uint len = bytesAvailable;
        uint chars;
        ubyte* b = _buf.ptr + _pos;
        dchar* text = reserveTextBuf(len / 2 + 1);
        uint i;
        for (; i < len - 1; i += 2)
        {
            uint ch0 = b[i];
            uint ch1 = b[i + 1];
            uint ch = (ch1 << 8) | ch0;
            // TODO: check special cases
            text[chars++] = ch;
        }
        consumedBytes(i);
        appendedText(chars);
        uint bleft = len - i;
        if (_streamEof && bleft > 0)
            invalidCharFlag = true; // incomplete character at end of stream
        return chars;
    }
}

private class Utf32beLineStream : LineStream
{
    this(InputStream stream, string filename, ubyte[] buf, uint len)
    {
        super(stream, filename, EncodingType.UTF32BE, buf, 4, len);
    }

    override uint decodeText()
    {
        if (invalidCharFlag)
        {
            invalidCharError();
            return 0;
        }
        uint bytesAvailable = readBytes();
        if (bytesAvailable == 0)
            return 0; // nothing to decode
        uint len = bytesAvailable;
        uint chars;
        ubyte* b = _buf.ptr + _pos;
        dchar* text = reserveTextBuf(len / 2 + 1);
        uint i;
        for (; i < len - 3; i += 4)
        {
            uint ch0 = b[i];
            uint ch1 = b[i + 1];
            uint ch2 = b[i + 2];
            uint ch3 = b[i + 3];
            uint ch = (ch0 << 24) | (ch1 << 16) | (ch2 << 8) | ch3;
            if ((ch >= 0xd800 && ch < 0xe000) || (ch > 0x10FFFF))
            {
                invalidCharFlag = true;
                break;
            }
            text[chars++] = ch;
        }
        consumedBytes(i);
        appendedText(chars);
        uint bleft = len - i;
        if (_streamEof && bleft > 0)
            invalidCharFlag = true; // incomplete character at end of stream
        return chars;
    }
}

private class Utf32leLineStream : LineStream
{
    this(InputStream stream, string filename, ubyte[] buf, uint len)
    {
        super(stream, filename, EncodingType.UTF32LE, buf, 4, len);
    }

    override uint decodeText()
    {
        if (invalidCharFlag)
        {
            invalidCharError();
            return 0;
        }
        uint bytesAvailable = readBytes();
        if (bytesAvailable == 0)
            return 0; // nothing to decode
        uint len = bytesAvailable;
        uint chars;
        ubyte* b = _buf.ptr + _pos;
        dchar* text = reserveTextBuf(len / 2 + 1);
        uint i;
        for (; i < len - 3; i += 4)
        {
            uint ch3 = b[i];
            uint ch2 = b[i + 1];
            uint ch1 = b[i + 2];
            uint ch0 = b[i + 3];
            uint ch = (ch0 << 24) | (ch1 << 16) | (ch2 << 8) | ch3;
            if ((ch >= 0xd800 && ch < 0xe000) || (ch > 0x10FFFF))
            {
                invalidCharFlag = true;
                break;
            }
            text[chars++] = ch;
        }
        consumedBytes(i);
        appendedText(chars);
        uint bleft = len - i;
        if (_streamEof && bleft > 0)
            invalidCharFlag = true; // incomplete character at end of stream
        return chars;
    }
}
