/**
Contains implementations of smart references.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.ownership;

import std.traits : isImplicitlyConvertible;

enum bool isReferenceType(T) = is(T == class) || is(T == interface) || is(T == U*, U);

enum bool hasMemberLike(T, string member, Y) =
    isImplicitlyConvertible!(typeof(__traits(getMember, T, member)), const(Y));

/**
Extremely simple intrusive weak reference implementation.

WeakRef serves one task: to notice a dangling pointer after object destruction.
For example, class A owns object B, and class C needs to temporarily save B.
So C accepts WeakRef of B. If object A decides to destroy B, C will stay with null reference.

Object B must satisfy some requirements, because of intrusive nature of WeakRef. See example below.
*/
struct WeakRef(T) if (isReferenceType!T && hasMemberLike!(T, "isDestroyed", bool*))
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

    destroy(b);
    assert(reference.isNull);
}

/// Shortcut for WeakRef!T(object)
WeakRef!T weakRef(T)(T object)
{
    return WeakRef!T(object);
}
