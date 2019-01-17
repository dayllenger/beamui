/**


Copyright: Vadim Lopatin 2015-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.streams;

import std.stdio;

interface Closeable
{
    @property bool isOpen() const;
    void close();
}

interface InputStream : Closeable
{
    @property bool eof() const;
    size_t read(ubyte[] buffer);
}

interface OutputStream : Closeable
{
    void write(ubyte[] data);
}

class FileInputStream : InputStream
{
    private File _file;

    this(string filename)
    {
        _file = File(filename, "rb");
    }

    @property bool isOpen() const
    {
        return _file.isOpen;
    }

    @property bool eof() const
    {
        return _file.eof;
    }

    void close()
    {
        if (isOpen)
            _file.close();
    }

    size_t read(ubyte[] buffer)
    {
        ubyte[] res = _file.rawRead(buffer);
        return res.length;
    }
}

class FileOutputStream : OutputStream
{
    private File _file;

    this(string filename)
    {
        _file = File(filename, "wb");
    }

    @property bool isOpen() const
    {
        return _file.isOpen;
    }

    void close()
    {
        _file.close();
    }

    void write(ubyte[] data)
    {
        _file.rawWrite(data);
    }
}

class MemoryInputStream : InputStream
{
    private ubyte[] _data;
    private size_t _pos;
    private bool _closed;

    this(ubyte[] data)
    {
        _data = data;
        _closed = false;
        _pos = 0;
    }

    @property bool isOpen() const
    {
        return !_closed;
    }

    @property bool eof() const
    {
        return _closed || (_pos >= _data.length);
    }

    void close()
    {
        _closed = true;
    }

    size_t read(ubyte[] buffer)
    {
        size_t bytesRead = 0;
        for (size_t i = 0; i < buffer.length && _pos < _data.length; bytesRead++)
        {
            buffer[i++] = _data[_pos++];
        }
        return bytesRead;
    }
}
