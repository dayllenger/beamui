/**
Contains implementations of smart references.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.ownership;

import std.traits : isImplicitlyConvertible;

enum bool isReferenceType(T) = is(T == class) || is(T == interface) || is(T == U*, U);

enum bool hasDestructionFlag(T) = isImplicitlyConvertible!(
            typeof(__traits(getMember, T, "destructionFlag")), const(bool*));

/// Shortcut for `WeakRef!T(object)`
WeakRef!T weakRef(T)(T object)
{
    return WeakRef!T(object);
}

/**
Extremely simple intrusive weak reference implementation.

WeakRef serves one task: to notice a dangling pointer after object destruction.
For example, class A owns object B, and class C needs to temporarily save B.
So C accepts WeakRef of B. If object A decides to destroy B, C will stay with null reference.

Object B must satisfy some requirements, because of intrusive nature of WeakRef. See example below.

Limitations: WeakRef cannot forward custom `opEquals` and `toHash` calls,
because their results need to be consistent before and after object destruction.
*/
struct WeakRef(T) if (isReferenceType!T && hasDestructionFlag!T)
{
    private T data;
    private const(bool)* flag;

    /// Create a weak reference. `object` must be valid, of course.
    this(T object)
    {
        if (object)
        {
            data = object;
            flag = object.destructionFlag;
        }
    }

    /// Get the object reference
    inout(T) get() inout
    {
        return flag && !(*flag) ? data : null;
    }

    /// Set this reference to point nowhere
    void nullify()
    {
        data = null;
        flag = null;
    }

    /// True if the object exists
    bool opCast(To : bool)() const
    {
        return data && flag && !(*flag);
    }

    /// Allows to use WeakRef with destroyed item as key in associative arrays
    size_t toHash() const nothrow @trusted
    {
        const void* p = &this;
        return hashOf(p[0 .. this.sizeof]);
    }
    /// ditto
    bool opEquals(ref const typeof(this) s) const
    {
        return data is s.data && flag is s.flag;
    }
}

///
unittest
{
    class B
    {
        bool* destructionFlag;

        this()
        {
            destructionFlag = new bool;
        }

        ~this()
        {
            *destructionFlag = true;
        }
    }

    WeakRef!B reference;
    assert(!reference);

    B b = new B;
    reference = weakRef(b);

    assert(b == reference.get);
    assert(reference);

    WeakRef!B ref2 = reference;
    ref2.nullify();
    assert(!ref2);

    destroy(b);
    assert(!reference);
}

unittest
{
    // toHash testing
    class B
    {
        bool* destructionFlag;

        this()
        {
            destructionFlag = new bool;
        }

        ~this()
        {
            *destructionFlag = true;
        }
    }

    int[WeakRef!B] map;
    foreach (i; 0 .. 100)
    {
        B b = new B;
        map[weakRef(b)] = i;
        if (i % 2 == 0)
            destroy(b);
    }
    int count;
    foreach (r, i; map)
    {
        if (!r)
        {
            map.remove(r); // must not crash
            count++;
        }
    }
    assert(count == 50);
    assert(map.length == 50);
}
