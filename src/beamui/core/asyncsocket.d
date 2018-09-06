/**


Copyright: Vadim Lopatin 2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
// TODO: it was needed for IRC client, remove it?
module beamui.core.asyncsocket;

import core.thread;
import std.socket;
import beamui.core.logger;
import beamui.core.queue;

/// Socket state
enum SocketState
{
    disconnected,
    connecting,
    connected
}

/// Asynchronous socket interface
interface AsyncSocket
{
    @property SocketState state();
    void connect(string host, ushort port);
    void disconnect();
    void send(ubyte[] data);
}

/// Socket error code
enum SocketError
{
    connectError,
    writeError,
    notConnected,
    alreadyConnected,
}

/// Callback interface for using by AsyncSocket implementations
interface AsyncSocketCallback
{
    void onDataReceived(AsyncSocket socket, ubyte[] data);
    void onConnect(AsyncSocket socket);
    void onDisconnect(AsyncSocket socket);
    void onError(AsyncSocket socket, SocketError error, string msg);
}

/// Proxy for AsyncConnectionHandler - to call in GUI thread
class AsyncSocketCallbackProxy : AsyncSocketCallback
{
private:
    AsyncSocketCallback _handler;
    void delegate(void delegate() runnable) _executor;

public:
    this(AsyncSocketCallback handler, void delegate(void delegate() runnable) executor)
    {
        _executor = executor;
        _handler = handler;
    }

    void onDataReceived(AsyncSocket socket, ubyte[] data)
    {
        _executor(delegate() { _handler.onDataReceived(socket, data); });
    }

    void onConnect(AsyncSocket socket)
    {
        _executor(delegate() { _handler.onConnect(socket); });
    }

    void onDisconnect(AsyncSocket socket)
    {
        _executor(delegate() { _handler.onDisconnect(socket); });
    }

    void onError(AsyncSocket socket, SocketError error, string msg)
    {
        _executor(delegate() { _handler.onError(socket, error, msg); });
    }
}

/// Asynchrous socket which uses separate thread for operation
class AsyncClientConnection : Thread, AsyncSocket
{
    protected
    {
        Socket _sock;
        SocketSet _readSet;
        SocketSet _writeSet;
        SocketSet _errorSet;
        RunnableQueue _queue;
        AsyncSocketCallback _callback;
        SocketState _state = SocketState.disconnected;
    }

    this(AsyncSocketCallback cb)
    {
        super(&threadProc);
        _callback = cb;
        _queue = new RunnableQueue;
        start();
    }

    ~this()
    {
        _queue.close();
        join();
    }

    @property SocketState state()
    {
        return _state;
    }

    protected void threadProc()
    {
        ubyte[] readBuf = new ubyte[65536];
        Log.d("entering ClientConnection thread proc");
        while (true)
        {
            if (_queue.closed)
                break;
            Runnable task;
            if (_queue.get(task, _sock ? 10 : 1000))
            {
                if (_queue.closed)
                    break;
                task();
            }
            if (_sock)
            {
                _readSet.reset();
                _writeSet.reset();
                _errorSet.reset();
                _readSet.add(_sock);
                _writeSet.add(_sock);
                _errorSet.add(_sock);
                if (Socket.select(_readSet, _writeSet, _errorSet, dur!"msecs"(10)) > 0)
                {
                    if (_writeSet.isSet(_sock))
                    {
                        if (_state == SocketState.connecting)
                        {
                            _state = SocketState.connected;
                            _callback.onConnect(this);
                        }
                    }
                    if (_readSet.isSet(_sock))
                    {
                        long bytesRead = _sock.receive(readBuf);
                        if (bytesRead > 0)
                        {
                            _callback.onDataReceived(this, readBuf[0 .. cast(int)bytesRead].dup);
                        }
                    }
                    if (_errorSet.isSet(_sock))
                    {
                        doDisconnect();
                    }
                }
            }
        }
        doDisconnect();
        Log.d("exiting ClientConnection thread proc");
    }

    protected void doDisconnect()
    {
        if (_sock)
        {
            _sock.shutdown(SocketShutdown.BOTH);
            _sock.close();
            destroy(_sock);
            _sock = null;
            if (_state != SocketState.disconnected)
            {
                _state = SocketState.disconnected;
                _callback.onDisconnect(this);
            }
        }
    }

    void connect(string host, ushort port)
    {
        _queue.put(delegate() {
            if (_state == SocketState.connecting)
            {
                _callback.onError(this, SocketError.notConnected, "socket is already connecting");
                return;
            }
            if (_state == SocketState.connected)
            {
                _callback.onError(this, SocketError.notConnected, "socket is already connected");
                return;
            }
            doDisconnect();
            _sock = new TcpSocket;
            _sock.blocking = false;
            _readSet = new SocketSet;
            _writeSet = new SocketSet;
            _errorSet = new SocketSet;
            _state = SocketState.connecting;
            _sock.connect(new InternetAddress(host, port));
        });
    }

    void disconnect()
    {
        _queue.put(delegate() {
            if (!_sock)
                return;
            doDisconnect();
        });
    }

    void send(ubyte[] data)
    {
        _queue.put(delegate() {
            if (!_sock)
            {
                _callback.onError(this, SocketError.notConnected, "socket is not connected");
                return;
            }
            while (true)
            {
                long bytesSent = _sock.send(data);
                if (bytesSent == Socket.ERROR)
                {
                    _callback.onError(this, SocketError.writeError, "error while writing to connection");
                    return;
                }
                else
                {
                    //Log.d("Bytes sent:" ~ to!string(bytesSent));
                    if (bytesSent >= data.length)
                        return;
                    data = data[cast(int)bytesSent .. $];
                }
            }
        });
    }
}
