/**

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.memory;

@safe:

import std.conv : emplace;
import beamui.core.ownership : isReferenceType;

struct Arena
{
    private void[] buf;
    private size_t len;

    /// Allocate and construct a class instance
    T make(T, Args...)(Args args) @trusted if (is(T == class))
    {
        // align to 16 bytes
        enum alignedSize = (__traits(classInstanceSize, T) | 0b1111) + 1;

        const site = len;
        len += alignedSize;
        if (buf.length < len)
            buf.length = len * 2;

        return emplace!T(cast(T)&buf[site], args);
    }

    /// Allocate and initialize a struct instance
    T* make(T)() @trusted if (is(T == struct))
    {
        const site = len;
        len += T.sizeof;
        if (buf.length < len)
            buf.length = len * 2;

        T* obj = cast(T*)&buf[site];
        *obj = T.init;
        return obj;
    }

    /// Allocate an array of size `count`, filled with nulls
    T[] allocArray(T)(size_t count) @trusted if (isReferenceType!T)
    {
        if (count == 0)
            return null;

        const site = len;
        len += count * T.sizeof;
        if (buf.length < len)
            buf.length = len * 2;

        T[] array = (cast(T*)&buf[site])[0 .. count];
        array[] = null;
        return array;
    }

    /// Clear the arena, retaining allocated memory
    void clear()
    {
        len = 0;
    }
}
