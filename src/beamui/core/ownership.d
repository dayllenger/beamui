/**


Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.ownership;

import std.traits : isImplicitlyConvertible;

///
unittest
{
    class A
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

    WeakRef!A reference;
    assert(reference.isNull);

    A a = new A;
    reference = weakRef(a);

    assert(a == reference.get);
    assert(!reference.isNull);

    destroy(a);
    assert(reference.isNull);
}

enum bool isReferenceType(T) = is(T == class) || is(T == interface) || is(T == U*, U);

enum bool hasMemberLike(T, string member, Y) =
    isImplicitlyConvertible!(typeof(__traits(getMember, T, member)), const(Y));

struct WeakRef(T) if (isReferenceType!T && hasMemberLike!(T, "isDestroyed", bool*))
{
    private T data;
    private bool* isDestroyed;
    alias get this;

    this(T object)
    {
        if (object !is null)
        {
            data = object;
            isDestroyed = cast(bool*)object.isDestroyed;
        }
    }

    inout(T) get() inout
    {
        return isDestroyed && !(*isDestroyed) ? data : null;
    }

    @property bool isNull() const
    {
        return data is null || isDestroyed is null || *isDestroyed;
    }
}

WeakRef!T weakRef(T)(T object)
{
    return WeakRef!T(object);
}
