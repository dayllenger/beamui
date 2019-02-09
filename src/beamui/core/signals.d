/**
Signal and slot mechanism.

$(LINK2 https://en.wikipedia.org/wiki/Signals_and_slots, Signals and slots),
$(LINK2 https://en.wikipedia.org/wiki/Observer_pattern, Observer pattern)

Mainly used for communication between widgets.

Signal is a holder of several slots. You can connect and disconnect slots to it.
When you invoke signal, slots are called one by one.
All actions are performed in the caller thread.

Slot is a delegate with any types of parameters and return value.
It may be a struct or class method (overridden, maybe),
some nested or global function, or a lambda.

Listener here stands for a signal with single slot, which 'listens' the signal,
so don't be confused by a name.
Listener has smaller memory footprint.

Caution: unlike std.signals, it does not disconnect signal from slots belonging to destroyed objects.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.signals;

import std.traits;

///
unittest
{
    import std.stdio;

    struct S
    {
        Listener!(bool delegate()) fired;
        Signal!(bool delegate(string)) multiFired;

        void fire()
        {
            // call the signal, which calls a listener
            // may be called with explicit fired.emit()
            bool done = fired();
            assert(done);
        }

        void multiFire()
        {
            bool done = multiFired("world");
            assert(done);
        }
    }

    struct Z
    {
        static int goodbyeCount = 0;

        bool hello(string what)
        {
            writeln("Hello, ", what);
            return true;
        }

        bool goodbye(string what)
        {
            writeln("Goodbye, ", what);
            goodbyeCount++;
            return false;
        }
    }

    S s;
    Z z;
    // assign a lambda to the signal
    // there are 10 ways to declare a lambda, here we use short {} syntax
    s.fired = { return z.hello("world"); };
    // check if any listener is connected
    assert(s.fired.assigned);
    s.fire();

    Z z1, z2;
    // connect methods by reference
    // may be connected with explicit .connect()
    s.multiFired ~= &z.goodbye;
    s.multiFired ~= &z1.hello;
    s.multiFired ~= &z2.goodbye;
    s.multiFire();
    // signal invokes slots one by one in order they added
    // by default, signal stops on first nonzero value, returned by a slot
    // and returns this value
    // so z2.goodbye will not be called
    // this behaviour can be changed by passing ReturnPolicy.late as a second Signal parameter
    assert(Z.goodbyeCount == 1);

    // you can disconnect individual slots using disconnect()
    s.multiFired.disconnect(&z1.hello);
    // or -= operator
    s.multiFired -= &z2.goodbye;
}

/// Single listener; parameter is some delegate
struct Listener(slot_t) if (isDelegate!slot_t)
{
    alias return_t = ReturnType!slot_t;
    alias params_t = Parameters!slot_t;
    private slot_t _listener;

    /// Returns true if listener is assigned
    bool assigned()
    {
        return _listener !is null;
    }

    void opAssign(slot_t listener)
    {
        _listener = listener;
    }

    /// Call the listener if assigned
    return_t opCall(params_t params)
    {
        static if (is(return_t == void))
        {
            if (_listener !is null)
                _listener(params);
        }
        else
        {
            if (_listener !is null)
                return _listener(params);
            return return_t.init;
        }
    }

    slot_t get()
    {
        return _listener;
    }

    /// Disconnect listener
    void clear()
    {
        _listener = null;
    }
}

/// Determines when signal returns value
enum ReturnPolicy
{
    eager, /// stop iterating if return value is nonzero, return this value
    late   /// call all slots and return the last value
}

/// Multiple listeners; parameter is some delegate
struct Signal(slot_t, ReturnPolicy policy = ReturnPolicy.eager) if (isDelegate!slot_t)
{
    alias return_t = ReturnType!slot_t;
    alias params_t = Parameters!slot_t;
    private slot_t[] _listeners;

    /// Returns true if listener is assigned
    bool assigned()
    {
        return _listeners.length > 0;
    }

    @disable void opAssign(Args...)(Args a);

    /// Call all listeners
    return_t emit(params_t params)
    {
        static if (is(return_t == void))
        {
            foreach (listener; _listeners)
                listener(params);
        }
        else static if (policy == ReturnPolicy.eager)
        {
            foreach (listener; _listeners)
            {
                return_t res = listener(params);
                if (res) // TODO: use .init value as zero?
                    return res;
            }
            return return_t.init;
        }
        else
        {
            foreach (listener; _listeners[0 .. $ - 1])
            {
                listener(params);
            }
            return _listeners[$ - 1](params);
        }
    }
    /// ditto
    alias opCall = emit;

    /// Add a listener
    void connect(slot_t listener)
    {
        _listeners ~= listener;
    }
    /// ditto
    alias opOpAssign(string op : "~") = connect;

    /// Remove a listener
    void disconnect(slot_t listener)
    {
        foreach (i, item; _listeners)
        {
            if (listener is item)
            {
                foreach (j; i .. _listeners.length - 1)
                    _listeners[j] = _listeners[j + 1];
                _listeners.length--;
                break;
            }
        }
    }
    /// ditto
    alias opOpAssign(string op : "-") = disconnect;

    /// Disconnect all listeners
    void clear()
    {
        _listeners.length = 0;
    }
}
