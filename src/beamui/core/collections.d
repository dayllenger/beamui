/**
Collection types.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.collections;

import std.traits;

/** Array-based collection, that provides a set of useful operations and handles object ownership.

    For class objects only.

    Retains item order during add/remove operations. When instantiated with `ownItems = true`,
    the container will destroy items on its destruction and on shrinking.

    Example:
    ---
    // add
    Collection!Widget widgets;
    widgets ~= new Widget("id1");
    widgets ~= new Widget("id2");
    Widget w3 = new Widget("id3");
    widgets ~= w3;

    // remove by index
    widgets.remove(1);

    // iterate
    foreach (w; widgets)
        writeln("widget: ", w.id);

    // remove by value
    widgets -= w3;
    writeln(widgets[0].id);
    ---
*/
struct Collection(T, bool ownItems = false) if (is(T == class) || is(T == interface))
{
    private T[] list;
    private size_t len;

    /// Number of items in the collection
    @property size_t count() const { return len; }
    /// True if there are no items in the collection
    @property bool empty() const
    {
        return len == 0;
    }
    /// Returns currently allocated size (>= `count`)
    @property size_t capacity() const
    {
        return list.length;
    }

    private this(int);
    @disable this(this);

    ~this()
    {
        clear();
    }

    /// Make sure the capacity is at least `count` items
    /// (e.g. to reserve big space to avoid multiple reallocations)
    void reserve(size_t count)
    {
        if (list.length < count)
            list.length = count;
    }

    /// Append item to the end of collection
    void append(T item)
    {
        if (list.length == len) // need to resize
            list.length = list.length * 3 / 2 + 1;
        list[len++] = item;
    }
    /// Insert item before specified position
    void insert(size_t index, T item)
        in(index <= len, "Index is out of range")
    {
        if (list.length == len) // need to resize
            list.length = list.length * 3 / 2 + 1;
        if (index < len)
        {
            foreach_reverse (i; index .. len)
                list[i + 1] = list[i];
        }
        list[index] = item;
        len++;
    }

    /// Remove single item and return it
    T remove(size_t index)
        in(index < len, "Index is out of range")
    {
        T result = list[index];
        foreach (i; index .. len - 1)
            list[i] = list[i + 1];
        len--;
        return result;
    }
    /// Remove single item by value. Returns true if item was found and removed
    bool removeValue(T value)
    {
        ptrdiff_t index = indexOf(value);
        if (index >= 0)
        {
            remove(index);
            return true;
        }
        return false;
    }

    /// Replace one item with another by index. Returns removed item.
    T replace(size_t index, T item)
    {
        T old = list[index];
        list[index] = item;
        return old;
    }
    /// Replace one item with another. Appends if not found
    void replace(T oldItem, T newItem)
    {
        ptrdiff_t index = indexOf(oldItem);
        if (index >= 0)
            replace(index, newItem);
        else
            append(newItem);
    }

    /// Expand or shrink the collection, possibly destroying items or adding `null` ones
    void resize(size_t count)
    {
        if (count < len)
        {
            // shrink
            // clear list
            static if (ownItems)
            {
                foreach (item; list[count .. len])
                    destroy(item);
            }
            // clear references
            list[count .. len] = null;
        }
        else if (count > len)
        {
            // expand
            if (list.length < count)
                list.length = count;
        }
        len = count;
    }

    /// Remove all items and optionally destroy them
    void clear(bool destroyItems = ownItems)
    {
        if (destroyItems)
        {
            foreach (item; list[0 .. len])
                destroy(item);
        }
        // clear references
        list[] = null;
        len = 0;
    }

    /// Returns index of the first occurrence of item, returns -1 if not found
    ptrdiff_t indexOf(const T item) const
    {
        foreach (i, it; list[0 .. len])
            if (it is item)
                return i;
        return -1;
    }
    static if (__traits(hasMember, T, "compareID"))
    /// Find child index for item by id, returns -1 if not found
    ptrdiff_t indexOf(string id) const
    {
        foreach (i, it; list[0 .. len])
            if (it.compareID(id))
                return i;
        return -1;
    }

    /// Support for appending (~=) and removing by value (-=)
    alias opOpAssign(string op : "~") = append;
    /// ditto
    alias opOpAssign(string op : "-") = removeValue;
    alias opDollar = count;

    /// Foreach support
    int opApply(scope int delegate(size_t i, T) callback)
    {
        int result;
        foreach (i, item; list[0 .. len])
        {
            result = callback(i, item);
            if (result)
                break;
        }
        return result;
    }
    /// ditto
    int opApply(scope int delegate(T) callback)
    {
        int result;
        foreach (item; list[0 .. len])
        {
            result = callback(item);
            if (result)
                break;
        }
        return result;
    }

    inout(T) opIndex(size_t index) inout
    {
        return list[index];
    }

    /// Support for `in` operator (linear search)
    bool opBinaryRight(string op : "in")(const T item) const
    {
        foreach (it; list[0 .. len])
            if (it is item)
                return true;
        return false;
    }

    const(T[]) opIndex() const
    {
        return list[0 .. len];
    }

    /// Get a mutable slice of items. Don't try to resize it!
    T[] unsafe_slice()
    {
        return list[0 .. len];
    }

    //=================================
    // stack/queue-like ops

    /// Pick the first item. Fails if no items
    inout(T) front() inout
        in(len > 0)
    {
        return list[0];
    }
    /// Remove the first item and return it. Fails if no items
    T popFront()
        in(len > 0)
    {
        return remove(0);
    }
    /// Insert item at the beginning of collection
    void pushFront(T item)
    {
        insert(0, item);
    }

    /// Pick the last item. Fails if no items
    inout(T) back() inout
        in(len > 0)
    {
        return list[len - 1];
    }
    /// Remove the last item and return it. Fails if no items
    T popBack()
        in(len > 0)
    {
        return remove(len - 1);
    }
    /// Insert item at the end of collection
    void pushBack(T item)
    {
        append(item);
    }
}

/// List change kind
enum ListChange
{
    replaceAll,
    append,
    insert,
    replace,
    remove,
}

/** Array with ability to track its changes via `beforeChange` and `afterChange` signals.

    Example:
    ---
    import beamui.core.collections;
    import beamui.core.logger;

    auto list = new ObservableList!int;
    list.afterChange ~= (ListChange change, uint index, uint count) {
        Log.fd("%s at %s with %s items", change, index, count);
    };

    list.append(1);
    list.insertItems(0, [1, 2, 3]);
    ---
*/
class ObservableList(T)
if (is(T == struct) || isScalarType!T || isDynamicArray!T)
{
    import std.array : insertInPlace, replaceInPlace;
    import beamui.core.signals : Signal;
    static import std.algorithm;

    final @property
    {
        const(bool)* destructionFlag() const { return _destructionFlag; }

        /// True when there is no items
        bool empty() const
        {
            return _items.length == 0;
        }

        /// Total item count
        int count() const
        {
            return cast(int)_items.length;
        }

        /// Const view on the items
        const(T[]) items() const { return _items; }
    }

    /// Triggers before every change in the list and passes needed information about the change
    Signal!(void delegate(ListChange, uint index, uint count)) beforeChange;
    /// Triggers after every change in the list and passes needed information about the change
    Signal!(void delegate(ListChange, uint index, uint count)) afterChange;

    private T[] _items;
    private bool* _destructionFlag;

    this()
    {
        _destructionFlag = new bool;
    }

    this(uint initialItemCount)
    {
        _items.length = initialItemCount;
        _destructionFlag = new bool;
    }

    ~this()
    {
        *_destructionFlag = true;
    }

final:

    /// Replace the whole content
    void replaceAll(T[] array)
    {
        const len = cast(uint)array.length;
        beforeChange(ListChange.replaceAll, 0, len);
        _items = array;
        afterChange(ListChange.replaceAll, 0, len);
    }
    /// Remove the whole content
    void removeAll()
    {
        if (_items.length > 0)
        {
            beforeChange(ListChange.replaceAll, 0, 0);
            _items.length = 0;
            afterChange(ListChange.replaceAll, 0, 0);
        }
    }

    /// Append one item to the end
    void append(T item)
    {
        const i = cast(uint)_items.length;
        beforeChange(ListChange.append, i, 1);
        _items ~= item;
        afterChange(ListChange.append, i, 1);
    }
    /// Insert one item at `index`. The index must be in range, except it can be == `count` for append
    void insert(uint index, T item)
    {
        assert(index <= _items.length);

        if (index < _items.length)
        {
            beforeChange(ListChange.insert, index, 1);
            insertInPlace(_items, index, item);
            afterChange(ListChange.insert, index, 1);
        }
        else
        {
            beforeChange(ListChange.append, index, 1);
            _items ~= item;
            afterChange(ListChange.append, index, 1);
        }
    }
    /// Replace one item at `index`. The index must be in range
    void replace(uint index, T item)
    {
        assert(index < _items.length);
        beforeChange(ListChange.replace, index, 1);
        _items[index] = item;
        afterChange(ListChange.replace, index, 1);
    }
    /// Remove one item at `index`. The index must be in range
    void remove(uint index)
    {
        assert(index < _items.length);
        beforeChange(ListChange.remove, index, 1);
        _items = std.algorithm.remove(_items, index);
        afterChange(ListChange.remove, index, 1);
    }

    /// Append several items to the end
    void appendItems(T[] array)
    {
        if (array.length > 0)
        {
            const len = cast(uint)array.length;
            const i = cast(uint)_items.length;
            beforeChange(ListChange.append, i, len);
            _items ~= array;
            afterChange(ListChange.append, i, len);
        }
    }
    /// Insert several items at `index`. The index must be in range, except it can be == `count` for append
    void insertItems(uint index, T[] array)
    {
        assert(index <= _items.length);

        const len = cast(uint)array.length;
        if (len > 0)
        {
            if (index < _items.length)
            {
                beforeChange(ListChange.insert, index, len);
                insertInPlace(_items, index, array);
                afterChange(ListChange.insert, index, len);
            }
            else
            {
                beforeChange(ListChange.append, index, len);
                _items ~= array;
                afterChange(ListChange.append, index, len);
            }
        }
    }
    /// Replace `count` items at `index` with items from `array`. The indices must be in range
    void replaceItems(uint index, uint count, T[] array)
    {
        assert(index < _items.length);
        assert(index + count <= _items.length);

        const len = cast(uint)array.length;
        if (count > 0 || len > 0)
        {
            const replaced = count < len ? count : len;
            // several items are replaced
            if (replaced > 0)
                beforeChange(ListChange.replace, index, replaced);
            // but also several may be inserted or removed
            if (count < len)
                beforeChange(ListChange.insert, index + count, len - count);
            else if (count > len)
                beforeChange(ListChange.remove, index + len, count - len);

            replaceInPlace(_items, index, index + count, array);

            if (replaced > 0)
                afterChange(ListChange.replace, index, replaced);
            if (count < len)
                afterChange(ListChange.insert, index + count, len - count);
            else if (count > len)
                afterChange(ListChange.remove, index + len, count - len);
        }
    }
    /// Remove `count` items at `index`. The indices must be in range
    void removeItems(uint index, uint count)
    {
        assert(index < _items.length);
        assert(index + count <= _items.length);

        if (count > 0)
        {
            beforeChange(ListChange.remove, index, count);
            replaceInPlace(_items, index, index + count, cast(T[])null);
            afterChange(ListChange.remove, index, count);
        }
    }

    /// Allows to replace item with `[i]`. The index must be in range
    void opIndexAssign(T item, uint i)
    {
        assert(i < _items.length);
        beforeChange(ListChange.replace, i, 1);
        _items[i] = item;
        afterChange(ListChange.replace, i, 1);
    }

    alias opDollar = count;
}

/** Lightweight `@nogc` dynamic array for memory reuse and fast appending.

    This is a small specialized container, created to optimize recurring demands
    in buffers for simple types. It does not own stored data and doesn't tell
    the GC about references in it. It cannot hold structs with non-trivial
    destructors and copy constructors. The buffer itself is not copyable,
    but it has a moving constructor and `dup` method.

    It was designed to be robust, so it reveals mutable references to its data
    only in `unsafe_*` methods.
*/
struct Buf(T)
if (isMutable!T &&
    !hasElaborateCopyConstructor!T &&
    !hasElaborateAssign!T &&
    !hasElaborateDestructor!T)
{ nothrow @nogc:

    import core.stdc.stdlib : malloc, realloc, free;
    import core.stdc.string : memcpy;

    private T* _data;
    private uint _capacity;
    private uint _length;

    /// The maximum number of items the buffer can store without reallocation
    @property uint capacity() const { return _capacity; }
    /// The number of items in the buffer
    @property uint length() const { return _length; }

    /// Moving constructor, i.e. nullifying the source buffer
    this(ref Buf!T source)
    {
        _data = source._data;
        _capacity = source._capacity;
        _length = source._length;
        source._data = null;
        source._capacity = 0;
        source._length = 0;
    }

    private this(T* dat, uint len)
    {
        _data = dat;
        _capacity = len;
        _length = len;
    }

    @disable this(this);

    ~this()
    {
        free(_data);
    }

    /// Duplicate the buffer. Capacity is not retained
    Buf!T dup() const
    {
        if (_length > 0)
        {
            T* ptr = cast(T*)malloc(_length * T.sizeof);
            if (!ptr)
                assert(0);
            memcpy(ptr, _data, _length * T.sizeof);
            return Buf!T(ptr, _length);
        }
        return Buf!T.init;
    }

    /// Make sure the buffer's capacity is at least `count` items
    void reserve(uint count)
    {
        if (_capacity < count)
        {
            _data = cast(T*)realloc(_data, count * T.sizeof);
            if (!_data)
                assert(0);
            _capacity = count;
        }
    }

    /// Append one element or a whole slice of elements to the end of the buffer
    void put(T value)
    {
        put(value);
    }
    /// ditto
    void put(ref T value)
    {
        if (_length == _capacity)
            reserve(_capacity * 3 / 2 + 1);
        _data[_length] = value;
        _length++;
    }
    /// ditto
    void put(const T[] slice)
    {
        if (slice.length > 0)
        {
            const len = _length + cast(uint)slice.length;
            if (len > _capacity)
                reserve(len);
            memcpy(_data + _length, slice.ptr, slice.length * T.sizeof);
            _length = len;
        }
    }

    /** Change the length of the buffer, possibly filling new items with `initial` value.

        It may shrink the buffer if the requested length is much less than
        the buffer has.
    */
    void resize(uint len, T initial = T.init)
    {
        if (len > _capacity)
        {
            reserve(len * 3 / 2);
        }
        else if (len * 8 < _length)
        {
            const c = len * 3 / 2 + 1;
            _data = cast(T*)realloc(_data, c * T.sizeof);
            if (!_data)
                assert(0);
            _capacity = c;
        }
        if (len > _length)
            _data[_length .. len] = initial;
        _length = len;
    }

    /// Decrease the length of the buffer by some number
    void shrink(uint by)
    {
        assert(by <= _length);
        _length -= by;
    }

    /// Set the length to `0`. Retains allocated memory
    void clear()
    {
        _length = 0;
    }

    alias opOpAssign(string op : "~") = put;
    alias opDollar = length;

    const(T[]) opIndex() const
    {
        return _data[0 .. _length];
    }

    ref const(T) opIndex(size_t i) const
    {
        assert(i < _length);
        return _data[i];
    }

    void opIndexAssign(T value, size_t i)
    {
        assert(i < _length);
        _data[i] = value;
    }

    void opIndexAssign(ref T value, size_t i)
    {
        assert(i < _length);
        _data[i] = value;
    }

    /// Get the pointer to the first element
    inout(T)* unsafe_ptr() inout
    {
        return _data;
    }
    /// Get the mutable reference to i-th element (you can pass negative indices here to start from the end)
    ref T unsafe_ref(ptrdiff_t i)
    {
        const l = cast(ptrdiff_t)_length;
        assert(i < l && -i <= l);
        return _data[i + (i < 0) * l];
    }
    /// Get the mutable slice of the buffer
    inout(T[]) unsafe_slice() inout
    {
        return _data[0 .. _length];
    }
}

//===============================================================
// Tests

unittest
{
    Collection!Object c;
    assert(c.empty);
    c.reserve(10);
    assert(c.empty);
}

unittest
{
    Collection!Object c;
    c.resize(10);
    assert(c.count == 10);
    assert(c.capacity >= c.count);
}

unittest
{
    Collection!Object c;
    c ~= new Object;
    c ~= null;
    c ~= new Object;
    assert(c.count == 3);
    assert(c.capacity >= 3);
    assert(c.front);
    assert(c.back);
    assert(c.front !is c.back);
    assert(c[1] is null);
    assert(c.removeValue(null));
    assert(c.count == 2);
    assert(!c.removeValue(null));
    assert(c.count == 2);
    assert(c.front);
    assert(c.back);
    assert(!c.empty);
    c.clear();
    assert(c.empty);
}

unittest
{
    Collection!Object c;
    auto obj1 = new Object;
    auto obj2 = new Object;
    c ~= null;
    c ~= null;
    c.insert(1, obj1);
    c.insert(2, obj2);
    assert(c.count == 4);
    assert(c.indexOf(obj1) == 1);
    assert(c.indexOf(obj2) == 2);
    assert(c.front is null);
    assert(c.back is null);
    assert(c[1] is obj1);
    assert(c[2] is obj2);
    assert(c.remove(1) is obj1);
    assert(c.remove(1) is obj2);
    assert(c.count == 2);

    c.insert(0, obj1);
    c.insert(c.count, obj2);
    assert(c.count == 4);
    assert(c.indexOf(obj1) == 0);
    assert(c.indexOf(obj2) == 3);
    assert(c.popFront() is obj1);
    assert(c.popBack() is obj2);
    assert(c.count == 2);

    c.pushFront(obj1);
    c.pushBack(obj2);
    assert(c.count == 4);
    assert(c.indexOf(obj1) == 0);
    assert(c.indexOf(obj2) == 3);
    assert(obj1 in c);
    assert(obj2 in c);
    assert(c.removeValue(obj1));
    assert(c.removeValue(obj2));
    assert(c.front is null);
    assert(c.back is null);
}

unittest
{
    Collection!Object c;
    c.resize(10);
    auto obj1 = new Object;
    auto obj2 = new Object;
    assert(c.replace(5, obj1) is null);
    assert(c.replace(5, obj2) is obj1);
    c.replace(obj2, obj1);
    assert(c.indexOf(obj1) == 5);
    assert(obj2 !in c);
    assert(c.count == 10);
}

unittest
{
    static struct Ch
    {
        ListChange change;
        uint index;
        uint count;
    }
    Ch[] changes;

    auto list = new ObservableList!int;
    list.beforeChange ~= (ListChange ch, uint i, uint c) {
        changes ~= Ch(ch, i, c);
    };
    list.afterChange ~= (ListChange ch, uint i, uint c) {
        // we do no test replaceItems here, where calls are not consecutive
        assert(changes[$ - 1] == Ch(ch, i, c));
    };

    list.append(1);
    list.appendItems([5, 2]);
    list.insert(1, 15);
    list.insertItems(1, [1, 2, 3]);
    list.replace(0, 100);
    list[1] = 50;
    list.remove(5);
    list.removeItems(1, 2);
    list.replaceAll([5, 10, 15]);
    list.removeAll();
    assert(changes[0] == Ch(ListChange.append, 0, 1));
    assert(changes[1] == Ch(ListChange.append, 1, 2));
    assert(changes[2] == Ch(ListChange.insert, 1, 1));
    assert(changes[3] == Ch(ListChange.insert, 1, 3));
    assert(changes[4] == Ch(ListChange.replace, 0, 1));
    assert(changes[5] == Ch(ListChange.replace, 1, 1));
    assert(changes[6] == Ch(ListChange.remove, 5, 1));
    assert(changes[7] == Ch(ListChange.remove, 1, 2));
    assert(changes[8] == Ch(ListChange.replaceAll, 0, 3));
    assert(changes[9] == Ch(ListChange.replaceAll, 0, 0));
    assert(changes.length == 10);
}

unittest
{
    class C {}
    struct S {}

    Buf!int b1;
    Buf!(int[2]) b2;
    Buf!(int[]) b3;
    Buf!C b4;
    Buf!S b5;
    Buf!(S*) b6;
    Buf!(immutable(S)*) b7;

    struct T { Buf!S buf; }
    T t;
    Buf!(T*) bt;

    static Buf!int func()
    {
        Buf!int b;
        return b;
    }
}

unittest
{
    Buf!int a;
    Buf!int b;

    foreach (i; 0 .. 100)
    {
        a ~= i;
        b ~= 100 - i;
    }
    assert(a[0] == 0);
    assert(a[$ - 1] == 99);

    a ~= b[];
    assert(a.length == 200);

    Buf!int c = Buf!int(a);
    Buf!int d = b.dup;
    assert(a[] is null);
    assert(c.length == 200);
    assert(c[$ / 2] == 100);
    assert(b[] == d[]);
}

unittest
{
    Buf!dchar s;
    s.reserve(100);
    assert(s.capacity == 100);
    assert(s.length == 0);
    assert(s[].ptr !is null);
}

unittest
{
    Buf!dchar a, b;
    a.resize(50, 'x');
    foreach (_; 0 .. 50)
        b ~= 'x';
    assert(a[] == b[]);
}

unittest
{
    Buf!int a;
    a.resize(100);
    a.resize(20);
    assert(a.capacity == 150);
    a.resize(110);
    assert(a.capacity == 150);
    a.resize(160);
    assert(a.capacity == 240);

    Buf!int b;
    b.resize(100);
    b.resize(10);
    assert(b.capacity < 20);
}

unittest
{
    Buf!int a;
    foreach (i; 0 .. 50)
        a ~= i;
    assert(a.unsafe_ptr is a[].ptr);
    assert(a.unsafe_ref(1) == a[1]);
    assert(a.unsafe_ref(-1) == a[$ - 1]);
    assert(a.unsafe_slice is a[]);

    a[15] = 25;
    assert(a[15] == 25);
}
