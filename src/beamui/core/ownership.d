/**
Contains implementations of smart references.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.ownership;

import std.traits : isImplicitlyConvertible;

enum bool isReferenceType(T) = is(T == class) || is(T == interface) || is(T == U*, U);

enum bool hasIsDestroyedMember(T) =
    isImplicitlyConvertible!(typeof(__traits(getMember, T, "isDestroyed")), const(bool*));

/**
Extremely simple intrusive weak reference implementation.

WeakRef serves one task: to notice a dangling pointer after object destruction.
For example, class A owns object B, and class C needs to temporarily save B.
So C accepts WeakRef of B. If object A decides to destroy B, C will stay with null reference.

Object B must satisfy some requirements, because of intrusive nature of WeakRef. See example below.

Limitations: WeakRef cannot forward custom `opEquals` and `toHash` calls,
because their results need to be consistent before and after object destruction.
*/
struct WeakRef(T) if (isReferenceType!T && hasIsDestroyedMember!T)
{
    private T data;
    private bool* isDestroyed;
    alias get this;

    /// Create a weak reference. `object` must be valid, of course.
    this(T object)
    {
        if (object !is null)
        {
            data = object;
            isDestroyed = cast(bool*)object.isDestroyed;
        }
    }

    /// Get the object reference
    inout(T) get() inout
    {
        return isDestroyed && !(*isDestroyed) ? data : null;
    }

    /// Explicitly check for null
    @property bool isNull() const
    {
        return data is null || isDestroyed is null || *isDestroyed;
    }

    /// Set this reference to point nowhere
    void nullify()
    {
        data = null;
        isDestroyed = null;
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
        return data is s.data && isDestroyed is s.isDestroyed;
    }
}

///
unittest
{
    class B
    {
        bool* isDestroyed;

        this()
        {
            isDestroyed = new bool;
        }

        ~this()
        {
            if (isDestroyed !is null)
                *isDestroyed = true;
        }
    }

    WeakRef!B reference;
    assert(reference.isNull);

    B b = new B;
    reference = weakRef(b);

    assert(b == reference.get);
    assert(!reference.isNull);

    WeakRef!B ref2 = reference;
    ref2.nullify();
    assert(ref2.isNull);

    destroy(b);
    assert(reference.isNull);
}

unittest
{
    // toHash testing
    class B
    {
        bool* isDestroyed;
        this()
        {
            isDestroyed = new bool;
        }
        ~this()
        {
            if (isDestroyed !is null)
                *isDestroyed = true;
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
        if (r.isNull)
        {
            map.remove(r); // must not crash
            count++;
        }
    }
    assert(count == 50);
    assert(map.length == 50);
}

/// Shortcut for WeakRef!T(object)
WeakRef!T weakRef(T)(T object)
{
    return WeakRef!T(object);
}
