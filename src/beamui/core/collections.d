/**
Simple object collection.

Wrapper around array of objects, providing a set of useful operations, and handling of object ownership.

Synopsis:
---
import beamui.core.collections;

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

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.collections;

/**
    Array based collection of items.

    Retains item order during add/remove operations.
    When instantiated with ownItems = true, container will destroy items on its destruction and on shrinking.
*/
struct Collection(T, bool ownItems = false)
{
    import std.traits : hasElaborateDestructor;
    import beamui.core.ownership : isReferenceType;

    private T[] list;
    private size_t len;

    private enum mayNeedToDestroy = isReferenceType!T || hasElaborateDestructor!T;

    ~this()
    {
        clear();
    }

    /// Number of items in collection
    @property size_t count() const { return len; }
    /// ditto
    @property void count(size_t newCount)
    {
        if (newCount < len)
        {
            // shrink
            static if (mayNeedToDestroy)
            {
                // clear list
                static if (ownItems)
                {
                    foreach (i; newCount .. len)
                        destroy(list[i]);
                }
                // clear references
                static if (isReferenceType!T)
                    list[newCount .. len] = null;
            }
        }
        else if (newCount > len)
        {
            // expand
            if (list.length < newCount)
                list.length = newCount;
        }
        len = newCount;
    }
    /// ditto
    size_t opDollar() const { return len; }

    /// Returns true if there are no items in collection
    @property bool empty() const
    {
        return len == 0;
    }

    /// Returns currently allocated capacity (may be more than length)
    @property size_t size() const
    {
        return list.length;
    }
    /// Change capacity (e.g. to reserve big space to avoid multiple reallocations)
    @property void size(size_t newSize)
    {
        if (len > newSize)
            count = newSize; // shrink
        list.length = newSize;
    }

    /// Access item by index
    ref inout(T) opIndex(size_t index) inout
    {
        assert(index < len, "Index is out of range");
        return list[index];
    }

    /// Returns index of the first occurrence of item, returns -1 if not found
    ptrdiff_t indexOf(const(T) item) const
    {
        foreach (i; 0 .. len)
            if (list[i] is item)
                return i;
        return -1;
    }
    static if (__traits(hasMember, T, "compareID"))
    {
        /// Find child index for item by id, returns -1 if not found
        ptrdiff_t indexOf(string id) const
        {
            foreach (i; 0 .. len)
                if (list[i].compareID(id))
                    return i;
            return -1;
        }
    }
    /// True if collection contains such item
    bool opBinaryRight(string op : "in")(const(T) item) const
    {
        foreach (i; 0 .. len)
            if (list[i] is item)
                return true;
        return false;
    }

    /// Append item to the end of collection
    void append(T item)
    {
        if (list.length <= len) // need to resize
            list.length = list.length < 4 ? 4 : list.length * 2;
        list[len++] = item;
    }
    /// Insert item before specified position
    void insert(size_t index, T item)
    {
        assert(index <= len, "Index is out of range");
        if (list.length <= len) // need to resize
            list.length = list.length < 4 ? 4 : list.length * 2;
        if (index < len)
        {
            foreach_reverse (i; index .. len + 1)
                list[i] = list[i - 1];
        }
        list[index] = item;
        len++;
    }

    /// Remove single item and return it
    T remove(size_t index)
    {
        assert(index < len, "Index is out of range");
        T result = list[index];
        foreach (i; index .. len - 1)
            list[i] = list[i + 1];
        len--;
        list[len] = T.init;
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
        else
            return false;
    }

    /// Replace one item with another by index. Returns removed item.
    T replace(size_t index, T item)
    {
        assert(index < len, "Index is out of range");
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

    /// Remove all items and optionally destroy them
    void clear(bool destroyItems = ownItems)
    {
        static if (mayNeedToDestroy)
        {
            if (destroyItems)
            {
                foreach (i; 0 .. len)
                    destroy(list[i]);
            }
            // clear references
            static if (isReferenceType!T)
                list[] = null;
        }
        len = 0;
        list = null;
    }

    /// Support for appending (~=) and removing by value (-=)
    void opOpAssign(string op : "~")(T item)
    {
        append(item);
    }
    /// ditto
    void opOpAssign(string op : "-")(T item)
    {
        removeValue(item);
    }

    /// Support of foreach with reference
    int opApply(scope int delegate(size_t i, ref T) callback)
    {
        int result;
        foreach (i; 0 .. len)
        {
            result = callback(i, list[i]);
            if (result)
                break;
        }
        return result;
    }
    /// ditto
    int opApply(scope int delegate(ref T) callback)
    {
        int result;
        foreach (i; 0 .. len)
        {
            result = callback(list[i]);
            if (result)
                break;
        }
        return result;
    }

    /// Get slice of items. Don't try to resize it!
    T[] data()
    {
        return len > 0 ? list[0 .. len] : null;
    }

    //=================================
    // stack/queue-like ops

    /// Pick the first item
    @property T front()
    {
        return len > 0 ? list[0] : T.init;
    }
    /// Remove the first item and return it
    @property T popFront()
    {
        return len > 0 ? remove(0) : T.init;
    }
    /// Insert item at the beginning of collection
    void pushFront(T item)
    {
        insert(0, item);
    }

    /// Pick the last item
    @property T back()
    {
        return len > 0 ? list[len - 1] : T.init;
    }
    /// Remove the last item and return it
    @property T popBack()
    {
        return len > 0 ? remove(len - 1) : T.init;
    }
    /// Insert item at the end of collection
    void pushBack(T item)
    {
        append(item);
    }
}
