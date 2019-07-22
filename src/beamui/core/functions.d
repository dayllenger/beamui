/**
Various utility and sugar functions.

Sugar templates are very efficient, don't worry about performance.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.functions;

// some useful imports from Phobos
public import std.algorithm : move, remove, sort, startsWith, endsWith;
public import std.conv : to;
public import std.format : format;
public import std.utf : toUTF8, toUTF32;
public import beamui.core.math : clamp, max, min;
import std.traits;
import beamui.core.ownership : isReferenceType;

auto caching(T)(T obj) if (is(T == class))
{
    return cast()obj;
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

/// Simple eager filter
S[] efilter(alias pred, S)(S[] s)
{
    S[] arr;
    foreach (elem; s)
        if (pred(elem))
            arr ~= elem;
    return arr;
}
///
unittest
{
    // similar to std.algorithm.filter, but returns dynamic array
    assert("stuff".efilter!(c => c == 'f') == "ff");

    struct C
    {
        int i;
        bool ok;
    }

    C*[] cs = [ new C(5, false), new C(10, true) ];
    C*[] res = cs.efilter!(a => a.ok);

    assert(res.length == 1 && res[0].i == 10);
}

/// Destroys object and nullifies its reference. Does nothing if `value` is null.
void eliminate(T)(ref T value) if (is(T == class) || is(T == interface))
{
    if (value !is null)
    {
        destroy(value);
        value = null;
    }
}
/// ditto
void eliminate(T)(ref T* value) if (is(T == struct))
{
    if (value !is null)
    {
        destroy(*value);
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
        destroy(values);
        values = null;
    }
}
/// Destroys every key (if needed) and value in the associative array, nullifies everything
void eliminate(T, S)(ref T[S] values) if (__traits(compiles, eliminate(values[S.init])))
{
    if (values !is null)
    {
        foreach (k, v; values)
        {
            static if (__traits(compiles, eliminate(k)))
                eliminate(k);
            eliminate(v);
        }
        destroy(values);
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

/// Call some method for several objects.
/// Limitations: return values are not supported currently; `super` cannot be passed as a parameter.
auto bunch(TS...)(TS vars) if (TS.length > 0)
{
    static struct Result
    {
        TS vars;

        void opDispatch(string m, Args...)(auto ref Args args)
        {
            enum string expr = "vars[i]." ~ m ~ "(args)";
            static foreach (i, T; TS)
            {
                static if (!__traits(compiles, mixin(expr)))
                {
                    import std.format : format;

                    enum string t = T.stringof;
                    static if (!__traits(hasMember, T, m))
                        pragma(msg, "'bunch' template: no method '%s' for type '%s'".format(m, t));
                    else
                        pragma(msg, "'bunch' template: incorrect parameters in '%s.%s(...)'".format(t, m));
                }
                mixin(expr ~ ";");
            }
        }
    }
    return Result(vars);
}
///
unittest
{
    class C
    {
        static int count = 0;
        int i;

        this(int i)
        {
            this.i = i;
        }

        void render(bool dummy)
        {
            count += i;
        }
    }

    class D : C
    {
        this(int i)
        {
            super(i);
        }
    }

    C a = new C(1);
    C b = new C(2);
    C c = new C(3);
    D d = new D(4);
    /*
    same as:
    a.render(true);
    b.render(true);
    c.render(true);
    d.render(true);
    */
    bunch(a, b, c, d).render(true);
    assert(C.count == 10);
}

/// Do not evaluate a method if object is null, return .init value in this case
auto maybe(T)(T var) if (isReferenceType!T)
{
    static struct Result
    {
        T var;

        auto opDispatch(string m, Args...)(auto ref Args args)
        {
            static if (Args.length > 0)
                enum string expr = "var." ~ m ~ "(args)";
            else
                enum string expr = "var." ~ m;
            static if (!__traits(compiles, mixin(expr)))
            {
                import std.format : format;

                enum string t = T.stringof;
                static if (!__traits(hasMember, T, m))
                    pragma(msg, "'maybe' template: no method '%s' for type '%s'".format(m, t));
                else
                    pragma(msg, "'maybe' template: incorrect parameters in '%s.%s(...)'".format(t, m));
            }

            alias return_t = ReturnType!((T var, Args args) => mixin(expr));
            static if (is(return_t == void))
            {
                if (var !is null)
                    mixin(expr ~ ";");
            }
            else
            {
                if (var !is null)
                    return mixin(expr);
                else
                    return return_t.init;
            }
        }
    }
    return Result(var);
}
///
unittest
{
    class C
    {
        static int count;
        int i = 5;

        void render(bool dummy)
        {
            count++;
        }
    }

    C a;
    C b = new C;
    a.maybe.render(true); // does nothing
    b.maybe.render(true);
    assert(C.count == 1);

    // you may do it also this way
    bunch(a.maybe, b.maybe).render(true);
    assert(C.count == 2);

    assert(a.maybe.i == 0);
    assert(b.maybe.i == 5);
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
