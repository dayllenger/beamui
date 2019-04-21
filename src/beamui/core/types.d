/**
Basic data types to use in the library.

Contains reference counting support, character glyph struct, etc.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.types;

import beamui.core.config;

struct Tup(T...)
{
    T expand;
    alias expand this;
}

Tup!T tup(T...)(T args)
{
    return Tup!T(args);
}

struct Result(T)
{
    T val;
    bool err = true;

    bool opCast(To : bool)() const
    {
        return !err;
    }

    inout(Result!T) failed(T)(lazy scope Result!T fallback) inout
    {
        return err ? fallback : this;
    }
}

Result!T Ok(T)(T val)
{
    return Result!T(val, false);
}

Result!T Err(T)(T val = T.init)
{
    return Result!T(val, true);
}

/// Widget state bit flags
enum State : uint
{
    /// Indefinite state
    unspecified = 0, // TODO: think about it
    /// State not specified / normal
    normal = enabled | windowFocused,

    /// Mouse pointer is over this widget, buttons not pressed
    hovered = 1 << 0,
    /// Widget is activated
    activated = 1 << 1,
    /// Widget is selected
    selected = 1 << 2,
    /// Widget is checked
    checked = 1 << 3,
    /// Widget has focus
    focused = 1 << 4,
    /// Pressed (e.g. clicked by mouse)
    pressed = 1 << 5,
    /// Widget can process mouse and key events
    enabled = 1 << 6,
    /// Window is focused
    windowFocused = 1 << 7,
    /// Widget is default control for form (should be focused when window gains focus first time)
    default_ = 1 << 8,
    /// Widget has been focused by keyboard navigation
    keyboardFocused = 1 << 9,
    /// Returns state of parent instead of widget's state when requested
    parent = 1 << 20,
}

/**
    Base class for reference counted objects, maintains reference counter inplace.

    If some class is not inherited from RefCountedObject, additional object will be required to hold counters.
*/
class RefCountedObject
{
    /// Count of references to this object from Ref
    size_t refCount;
}

/**
    Reference counting support.

    Implemented for case when T is RefCountedObject.
    Similar to shared_ptr in C++.
    Allows to share object, destroying it when no more references left.

    Useful for automatic destroy of objects.
*/
struct Ref(T) if (is(T : RefCountedObject))
{
    private T _data;
    alias get this;

    /// Returns true if object is not assigned
    @property bool isNull() const
    {
        return _data is null;
    }
    /// Returns counter of references
    @property size_t refCount() const
    {
        return _data !is null ? _data.refCount : 0;
    }
    /// Init from T
    this(T data)
    {
        _data = data;
        addRef();
    }
    /// After blit
    this(this)
    {
        addRef();
    }
    /// Assign from another refcount by reference
    ref Ref opAssign(ref Ref data)
    {
        if (data._data == _data)
            return this;
        releaseRef();
        _data = data._data;
        addRef();
        return this;
    }
    /// Assign from another refcount by value
    ref Ref opAssign(Ref data)
    {
        if (data._data == _data)
            return this;
        releaseRef();
        _data = data._data;
        addRef();
        return this;
    }
    /// Assign object
    ref Ref opAssign(T data)
    {
        if (data == _data)
            return this;
        releaseRef();
        _data = data;
        addRef();
        return this;
    }
    /// Clear reference
    void clear()
    {
        releaseRef();
    }
    /// Returns object reference (null if not assigned)
    @property T get()
    {
        return _data;
    }
    /// Returns const reference from const object
    @property const(T) get() const
    {
        return _data;
    }
    /// Increment reference counter
    void addRef()
    {
        if (_data !is null)
            _data.refCount++;
    }
    /// Decrement reference counter, destroy object if no more references left
    void releaseRef()
    {
        if (_data !is null)
        {
            if (_data.refCount <= 1) // FIXME: why <=?
                destroy(_data);
            else
                _data.refCount--;
            _data = null;
        }
    }
    /// Decreases counter and destroys object if no more references left
    ~this()
    {
        releaseRef();
    }
}

/**
    This struct allows to not execute some code if some variables was not changed since the last check.
    Used for optimizations.

    Reference types, arrays and pointers are compared by reference.

    NOT USED
*/
struct CalcSaver(Params...)
{
    Tup!Params values;

    bool check(Params args)
    {
        bool changed;
        foreach (i, arg; args)
        {
            if (values[i]!is arg)
            {
                values[i] = arg;
                changed = true;
            }
        }
        return changed;
    }
}

///
unittest
{
    class A
    {
    }

    CalcSaver!(uint, double[], A) saver;

    uint x = 5;
    double[] arr = [1, 2, 3];
    A a = new A;

    assert(saver.check(x, arr, a));
    // values are not changing
    assert(!saver.check(x, arr, a));
    assert(!saver.check(x, arr, a));
    assert(!saver.check(x, arr, a));

    x = 8;
    arr ~= 25;
    // values are changed
    assert(saver.check(x, arr, a));
    assert(!saver.check(x, arr, a));

    a = new A;
    // values are changed
    assert(saver.check(x, arr, a));
    assert(!saver.check(x, arr, a));
}

/// String values string list adapter - each item can have optional string or integer id, and optional icon resource id
struct StringListValue
{
    /// Integer id for item
    int intID;
    /// String id for item
    string stringID;
    /// Icon resource id
    string iconID;
    /// Label to show for item
    dstring label;

    this(string id, dstring name, string iconID = null)
    {
        this.stringID = id;
        this.label = name;
        this.iconID = iconID;
    }

    this(int id, dstring name, string iconID = null)
    {
        this.intID = id;
        this.label = name;
        this.iconID = iconID;
    }

    this(dstring name, string iconID = null)
    {
        this.label = name;
        this.iconID = iconID;
    }
}
