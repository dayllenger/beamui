/**
Various utility and sugar functions.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.functions;

nothrow:

// some useful imports from Phobos
public import std.algorithm : move, remove, sort, startsWith, endsWith;
public import std.conv : to;
public import std.format : format;
public import std.exception : collectException;
public import std.utf : toUTF8, toUTF32;
public import beamui.core.math : clamp, max, min;
import std.traits;
import beamui.core.ownership : isReferenceType;

auto caching(T)(T obj) if (is(T == class))
{
    return cast()obj;
}

Derived fastCast(Derived, Base)(Base base)
if ((is(Base == class) || is(Base == interface)) && is(Derived : Base))
{
    debug
    {
        assert(base);
        Derived obj = cast(Derived)base;
        assert(obj, "Failed downcast");
        return obj;
    }
    else
        return cast(Derived)cast(void*)base;
}

/// Conversion from wchar z-string
wstring fromWStringz(T)(const(T) s) if (is(T == wchar[]) || is(T == wchar*))
{
    if (s is null)
        return null;
    int i = 0;
    while (s[i])
        i++;
    return cast(wstring)(s[0 .. i].dup);
}

/// Normalize end of line style - convert to '\n'
T normalizeEOLs(T)(T s) if (isSomeString!T)
{
    alias xchar = Unqual!(ForeachType!T);
    bool crFound = false;
    foreach (ch; s)
    {
        if (ch == '\r')
        {
            crFound = true;
            break;
        }
    }
    if (!crFound)
        return s;
    xchar[] res;
    res.reserve(s.length);
    xchar prevCh = 0;
    foreach (ch; s)
    {
        if (ch == '\r')
        {
            res ~= '\n';
        }
        else if (ch == '\n')
        {
            if (prevCh != '\r')
                res ~= '\n';
        }
        else
        {
            res ~= ch;
        }
        prevCh = ch;
    }
    return cast(T)res;
}
///
unittest
{
    assert("hello\nworld" == normalizeEOLs("hello\r\nworld"));
    assert("hello\nworld" == normalizeEOLs("hello\rworld"));
    assert("hello\n\nworld" == normalizeEOLs("hello\n\rworld"));
    assert("hello\nworld\n" == normalizeEOLs("hello\nworld\r"));
}

/// Simple bloat-free eager map
auto emap(alias func, S)(S[] s)
{
    alias Ret = typeof(func(s[0]));
    auto arr = new Ret[s.length];
    foreach (i, elem; s)
        arr[i] = func(elem);
    return arr;
}
///
unittest
{
    import std.algorithm : equal;

    bool[] res = "stuff".emap!(c => c == 'f');

    assert(res.equal([ false, false, false, true, true ]));

    struct C
    {
        int i;
    }

    C*[] cs = [ new C(5), new C(10) ];
    int[] ires = cs.emap!(a => a.i);

    assert(ires.equal([ 5, 10 ]));
}

static if (__VERSION__ < 2088)
{
    private void destr(T)(auto ref T val)
    {
        try
            destroy(val);
        catch (Exception)
            assert(0);
    }
}
else
{
    private alias destr = destroy;
}

/// Destroys object and nullifies its reference. Does nothing if `value` is null.
void eliminate(T)(ref T value) if (is(T == class) || is(T == interface))
{
    if (value !is null)
    {
        destr(value);
        value = null;
    }
}
/// ditto
void eliminate(T)(ref T* value) if (is(T == struct))
{
    if (value !is null)
    {
        destr(*value);
        value = null;
    }
}
/// Destroys every element of the array and nullifies everything
void eliminate(T)(ref T[] values) if (__traits(compiles, eliminate(values[0])))
{
    if (values !is null)
    {
        foreach (item; values)
            eliminate(item);
        destr(values);
        values = null;
    }
}
/// Destroys every key (if needed) and value in the associative array, nullifies everything
void eliminate(T, S)(ref T[S] values) if (__traits(compiles, eliminate(values[S.init])))
{
    if (values !is null)
    {
        try
        {
            foreach (k, v; values)
            {
                static if (__traits(compiles, eliminate(k)))
                    eliminate(k);
                eliminate(v);
            }
        }
        catch (Exception e)
        {
            import core.stdc.stdio : printf;

            printf("An exception during associative array iteration: %.*s\n", e.msg.length, e.msg.ptr);
        }
        destr(values);
        values = null;
    }
}
///
unittest
{
    class A
    {
        static int dtorCalls = 0;
        int i = 10;

        ~this()
        {
            dtorCalls++;
        }
    }

    A a = new A;
    a.i = 25;

    eliminate(a);
    assert(a is null && A.dtorCalls == 1);
    eliminate(a);
    assert(a is null && A.dtorCalls == 1);
    A.dtorCalls = 0;

    A[][] as = [[new A, new A], [new A], [new A, new A]];
    eliminate(as);
    assert(as is null && A.dtorCalls == 5);
    eliminate(as);
    assert(as is null && A.dtorCalls == 5);
    A.dtorCalls = 0;

    A[int] amap1 = [1 : new A, 6 : new A];
    eliminate(amap1);
    assert(amap1 is null && A.dtorCalls == 2);
    eliminate(amap1);
    assert(amap1 is null && A.dtorCalls == 2);
    A.dtorCalls = 0;

    A[A] amap2 = [new A : new A, new A : new A];
    eliminate(amap2);
    assert(amap2 is null && A.dtorCalls == 4);
    eliminate(amap2);
    assert(amap2 is null && A.dtorCalls == 4);
    A.dtorCalls = 0;
}

/// Get the short class name, i.e. without module path. `obj` must not be `null`
string getShortClassName(const Object obj)
{
    assert(obj);
    string name = obj.classinfo.name;
    int i = cast(int)name.length;
    while (i > 0 && name[i - 1] != '.')
        i--;
    return name[i .. $];
}
///
unittest
{
    class A {}
    A a = new A;
    assert(getShortClassName(a) == "A");
}

/// Check whether first name of class is equal to a string
bool equalShortClassName(TypeInfo_Class type, string shortName)
{
    assert(type);
    if (shortName.length == 0)
        return false;
    string name = type.name;
    if (shortName.length >= name.length)
        return false;
    if (shortName != name[$ - shortName.length .. $])
        return false;
    return name[$ - shortName.length - 1] == '.';
}
///
unittest
{
    TypeInfo_Class t = typeid(Exception);
    assert(equalShortClassName(t, "Exception"));
    assert(!equalShortClassName(t, "Exceptio"));
    assert(!equalShortClassName(t, "xception"));
    assert(!equalShortClassName(t, ".Exception"));
}

/// Move index into [first, last] range in a cyclic manner
int wrapAround(int index, int first, int last)
{
    assert(first <= last, "First must be less or equal than last");
    const diff = last - first + 1;
    return first + (index % diff + diff) % diff;
}
///
unittest
{
    assert(wrapAround(10, 0, 9) == 0);
    assert(wrapAround(12, 0, 9) == 2);
    assert(wrapAround(25, 0, 9) == 5);
    assert(wrapAround(-2, 0, 9) == 8);
    assert(wrapAround(-15, 0, 9) == 5);
    assert(wrapAround(0, 0, 9) == 0);
    assert(wrapAround(9, 0, 9) == 9);
}
