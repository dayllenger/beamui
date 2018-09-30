/**
This module declares basic data types for usage in the library.

Contains reference counting support, point and rect structures, character glyph structure, misc utility functions.

Synopsis:
---
import beamui.core.types;

// points
Point p(5, 10);

// rectangles
Rect r(5, 13, 120, 200);
writeln(r);

// reference counted objects, useful for RAII / resource management.
class Foo : RefCountedObject
{
    int[] resource;
    ~this()
    {
        writeln("freeing Foo resources");
    }
}
{
    Ref!Foo ref1;
    {
        Ref!Foo fooRef = new RefCountedObject;
        ref1 = fooRef;
    }
    // RAII: will destroy object when no more references
}
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.types;

import std.algorithm : clamp, max, min;
import beamui.core.config;

/// Size is undefined constant
enum int SIZE_UNSPECIFIED = 1 << 29; // not too much to safely sum two such values

/// 2D point
struct Point
{
    int x;
    int y;

    Point opBinary(string op)(Point v) const if (op == "+")
    {
        return Point(x + v.x, y + v.y);
    }

    Point opBinary(string op)(Point v) const if (op == "-")
    {
        return Point(x - v.x, y - v.y);
    }

    Point opBinary(string op)(int n) const if (op == "*")
    {
        return Point(x * n, y * n);
    }

    Point opUnary(string op)() const if (op == "-")
    {
        return Point(-x, -y);
    }

    int opCmp(ref const Point b) const
    {
        if (x == b.x)
            return y - b.y;
        return x - b.x;
    }
}

/// 2D size
struct Size
{
    int width;
    int height;
    alias w = width;
    alias h = height;

    enum none = Size(SIZE_UNSPECIFIED, SIZE_UNSPECIFIED);

    Size opBinary(string op)(Size v) const if (op == "+")
    {
        return Size(w + v.w, h + v.h);
    }

    Size opBinary(string op)(Size v) const if (op == "-")
    {
        return Size(w - v.w, h - v.h);
    }

    Size opBinary(string op)(int n) const if (op == "*")
    {
        return Size(w * n, h * n);
    }

    Size opBinary(string op)(int n) const if (op == "/")
    {
        return Size(w / n, h / n);
    }
}

/// Holds minimum, maximum and natural (preferred) size for widget
struct Boundaries
{
    static import std.algorithm;

    Size min;
    Size nat;
    Size max = Size.none;

    /// Special add operator: it clamps result between 0 and SIZE_UNSPECIFIED
    static int clampingAdd(int a, int b)
    {
        return clamp(a + b, 0, SIZE_UNSPECIFIED);
    }

    /// Special subtract operator: it clamps result between 0 and SIZE_UNSPECIFIED
    static int clampingSub(int a, int b)
    {
        return clamp(a - b, 0, SIZE_UNSPECIFIED);
    }

    void addWidth(const ref Boundaries from)
    {
        max.w = clampingAdd(max.w, from.max.w);
        nat.w += from.nat.w;
        min.w += from.min.w;
    }

    void maximizeWidth(const ref Boundaries from)
    {
        max.w = std.algorithm.max(max.w, from.max.w);
        nat.w = std.algorithm.max(nat.w, from.nat.w);
        min.w = std.algorithm.max(min.w, from.min.w);
    }

    void addHeight(const ref Boundaries from)
    {
        max.h = clampingAdd(max.h, from.max.h);
        nat.h += from.nat.h;
        min.h += from.min.h;
    }

    void maximizeHeight(const ref Boundaries from)
    {
        max.h = std.algorithm.max(max.h, from.max.h);
        nat.h = std.algorithm.max(nat.h, from.nat.h);
        min.h = std.algorithm.max(min.h, from.min.h);
    }
}

/// 2D box
struct Box
{
    /// x coordinate of the top left corner
    int x;
    /// y coordinate of the top left corner
    int y;
    /// Rectangle width
    int width;
    /// Rectangle height
    int height;
    alias w = width;
    alias h = height;

    /// 'rectangle is not set' value
    enum none = Box(int.min, int.min, int.min, int.min);

pure nothrow @nogc:

    /// Construct a box using x, y, width and height
    this(int x, int y, int width, int height)
    {
        this.x = x;
        this.y = y;
        this.w = width;
        this.h = height;
    }
    /// Construct a box using position and size
    this(Point p, Size sz)
    {
        x = p.x;
        y = p.y;
        w = sz.w;
        h = sz.h;
    }
    /// Construct a box using `Rect`
    this(Rect rc)
    {
        x = rc.left;
        y = rc.top;
        w = rc.width;
        h = rc.height;
    }

    /// Get box position
    @property Point pos() const
    {
        return Point(x, y);
    }
    /// Get box size
    @property Size size() const
    {
        return Size(w, h);
    }
    /// Set box position
    @property void pos(Point p)
    {
        x = p.x;
        y = p.y;
    }
    /// Set box size
    @property void size(Size s)
    {
        w = s.w;
        h = s.h;
    }

    /// Returns true if box is empty
    @property bool empty() const
    {
        return w <= 0 || h <= 0;
    }

    /// Returns center of the box
    @property Point middle() const
    {
        return Point(x + w / 2, y + h / 2);
    }
    /// Returns x coordinate of the center
    @property int middlex() const
    {
        return x + w / 2;
    }
    /// Returns y coordinate of the center
    @property int middley() const
    {
        return y + h / 2;
    }

    /// Returns true if point is inside of this rectangle
    bool isPointInside(int px, int py) const
    {
        return x <= px && px < x + w && y <= py && py < y + h;
    }
    /// Returns true if this box is completely inside of `b`
    bool isInsideOf(Box b) const
    {
        return b.x <= x && x + w <= b.x + b.w && b.y <= y && y + h <= b.y + b.h;
    }

    /// Expand box dimensions by a margin
    void expand(Insets ins)
    {
        x -= ins.left;
        y -= ins.top;
        w += ins.left + ins.right;
        h += ins.top + ins.bottom;
    }
    /// Shrink box dimensions by a margin
    void shrink(Insets ins)
    {
        x += ins.left;
        y += ins.top;
        w -= ins.left + ins.right;
        h -= ins.top + ins.bottom;
    }

    /// Move this box to fit `b` bounds, retaining the same size
    void moveToFit(const ref Box b)
    {
        if (x + w > b.x + b.w)
            x = b.x + b.w - w;
        if (y + h > b.y + b.h)
            y = b.y + b.h - h;
        if (x < b.x)
            x = b.x;
        if (y < b.y)
            y = b.y;
    }
}

/**
    2D rectangle

    It differs from Box in that it stores coordinates of the top-left and bottom-right corners.
    Box is more convenient when dealing with widgets, Rect is better in drawing procedures.

    Note: Rect(0,0,20,10) has size 20x10, but right and bottom sides are non-inclusive.
    If you draw such rect, rightmost drawn pixel will be x=19 and bottom pixel y=9
*/
struct Rect
{
    /// x coordinate of top left corner
    int left;
    /// y coordinate of top left corner
    int top;
    /// x coordinate of bottom right corner (non-inclusive)
    int right;
    /// y coordinate of bottom right corner (non-inclusive)
    int bottom;

pure nothrow @nogc:

    /// Construct a rectangle using left, top, right, bottom coordinates
    this(int x0, int y0, int x1, int y1)
    {
        left = x0;
        top = y0;
        right = x1;
        bottom = y1;
    }
    /// Construct a rectangle using two points - (left, top), (right, bottom) coordinates
    this(Point pt0, Point pt1)
    {
        left = pt0.x;
        top = pt0.y;
        right = pt1.x;
        bottom = pt1.y;
    }
    /// Construct a rectangle from a box
    this(Box b)
    {
        left = b.x;
        top = b.y;
        right = b.x + b.w;
        bottom = b.y + b.h;
    }

    /// Returns average of left, right
    @property int middlex() const
    {
        return (left + right) / 2;
    }
    /// Returns average of top, bottom
    @property int middley() const
    {
        return (top + bottom) / 2;
    }
    /// Returns middle point
    @property Point middle() const
    {
        return Point(middlex, middley);
    }

    /// Returns top left point of rectangle
    @property Point topLeft() const
    {
        return Point(left, top);
    }
    /// Returns bottom right point of rectangle
    @property Point bottomRight() const
    {
        return Point(right, bottom);
    }

    /// Returns size (right - left, bottom - top)
    @property Size size() const
    {
        return Size(right - left, bottom - top);
    }
    /// Get width of rectangle (right - left)
    @property int width() const
    {
        return right - left;
    }
    /// Get height of rectangle (bottom - top)
    @property int height() const
    {
        return bottom - top;
    }
    /// Returns true if rectangle is empty (right <= left || bottom <= top)
    @property bool empty() const
    {
        return right <= left || bottom <= top;
    }

    /// Add offset to horizontal and vertical coordinates
    void offset(int dx, int dy)
    {
        left += dx;
        right += dx;
        top += dy;
        bottom += dy;
    }
    /// Expand rectangle dimensions
    void expand(int dx, int dy)
    {
        left -= dx;
        right += dx;
        top -= dy;
        bottom += dy;
    }
    /// Shrink rectangle dimensions
    void shrink(int dx, int dy)
    {
        left += dx;
        right -= dx;
        top += dy;
        bottom -= dy;
    }
    /// For all fields, sets this.field to rc.field if rc.field > this.field
    void setMax(Rect rc)
    {
        if (left < rc.left)
            left = rc.left;
        if (right < rc.right)
            right = rc.right;
        if (top < rc.top)
            top = rc.top;
        if (bottom < rc.bottom)
            bottom = rc.bottom;
    }
    /// Translate rectangle coordinates by (x,y) - add deltax to x coordinates, and deltay to y coordinates
    alias moveBy = offset;
    /// Moves this rect to fit rc bounds, retaining the same size
    void moveToFit(ref Rect rc)
    {
        if (right > rc.right)
            moveBy(rc.right - right, 0);
        if (bottom > rc.bottom)
            moveBy(0, rc.bottom - bottom);
        if (left < rc.left)
            moveBy(rc.left - left, 0);
        if (top < rc.top)
            moveBy(0, rc.top - top);

    }
    /// Update this rect to intersection with rc, returns true if result is non empty
    bool intersect(Rect rc)
    {
        if (left < rc.left)
            left = rc.left;
        if (top < rc.top)
            top = rc.top;
        if (right > rc.right)
            right = rc.right;
        if (bottom > rc.bottom)
            bottom = rc.bottom;
        return right > left && bottom > top;
    }
    /// Returns true if this rect has nonempty intersection with rc
    bool intersects(Rect rc) const
    {
        if (rc.left >= right || rc.top >= bottom || rc.right <= left || rc.bottom <= top)
            return false;
        return true;
    }
    /// Returns true if point is inside of this rectangle
    bool isPointInside(Point pt) const
    {
        return left <= pt.x && pt.x < right && top <= pt.y && pt.y < bottom;
    }
    /// Returns true if point is inside of this rectangle
    bool isPointInside(int x, int y) const
    {
        return left <= x && x < right && top <= y && y < bottom;
    }
    /// This rectangle is completely inside rc
    bool isInsideOf(Rect rc) const
    {
        return left >= rc.left && right <= rc.right && top >= rc.top && bottom <= rc.bottom;
    }

    bool opEquals(Rect rc) const
    {
        return left == rc.left && right == rc.right && top == rc.top && bottom == rc.bottom;
    }
}

/// Represents area around rectangle. Used for margin, border and padding
struct Insets
{
    int top, right, bottom, left;

pure nothrow @nogc:

    /// Create equal offset on all sides
    this(int all)
    {
        top = right = bottom = left = all;
    }
    /// Create separate horizontal and vertical offsets
    this(int v, int h)
    {
        top = bottom = v;
        right = left = h;
    }
    /// Create offsets one by one
    this(int top, int right, int bottom, int left)
    {
        this.top = top;
        this.right = right;
        this.bottom = bottom;
        this.left = left;
    }

    /// Get total offset
    @property Size size() const
    {
        return Size(left + right, top + bottom);
    }
    /// Get total horizontal offset
    @property int width() const
    {
        return left + right;
    }
    /// Get total vertical offset
    @property int height() const
    {
        return top + bottom;
    }

    Insets opBinary(string op)(Insets ins) const if (op == "+")
    {
        return Insets(top + ins.top, right + ins.right, bottom + ins.bottom, left + ins.left);
    }

    Insets opBinary(string op)(Insets ins) const if (op == "-")
    {
        return Insets(top - ins.top, right - ins.right, bottom - ins.bottom, left - ins.left);
    }

    Insets opBinary(string op)(float factor) const if (op == "*")
    {
        return Insets(cast(int)(top * factor), cast(int)(right * factor),
                      cast(int)(bottom * factor), cast(int)(left * factor));
    }

    /// Sum two areas
    void add(Insets ins)
    {
        top += ins.top;
        right += ins.right;
        bottom += ins.bottom;
        left += ins.left;
     }
}

/// Widget state bit flags
enum State : uint
{
    /// Indefinite state
    unspecified = 0, // TODO: think about it
    /// State not specified / normal
    normal = enabled | windowFocused,

    /// Mouse pointer is over this widget
    hovered = 1, // mouse pointer is over control, buttons not pressed
    /// Widget is activated
    activated = 1 << 1,
    /// Widget is selected
    selected = 1 << 2,
    /// Widget can be checked
    checkable = 1 << 3,
    /// Widget is checked
    checked = 1 << 4,
    /// Widget has focus
    focused = 1 << 5,
    /// Pressed (e.g. clicked by mouse)
    pressed = 1 << 6,
    /// Widget can process mouse and key events
    enabled = 1 << 7,
    /// Window is focused
    windowFocused = 1 << 8,
    /// Widget is default control for form (should be focused when window gains focus first time)
    default_ = 1 << 9,
    /// Widget has been focused by keyboard navigation
    keyboardFocused = 1 << 10,
    /// Returns state of parent instead of widget's state when requested
    parent = 1 << 20,
}

/// Subpixel rendering mode for fonts (aka ClearType)
enum SubpixelRenderingMode : ubyte
{
    /// No sub
    none,
    /// Subpixel rendering on, subpixel order on device: B,G,R
    bgr,
    /// Subpixel rendering on, subpixel order on device: R,G,B
    rgb,
}

/**
    Character glyph.

    Holder for glyph metrics as well as image.
*/
align(1) struct Glyph
{
    static if (USE_OPENGL)
    {
        /// 0: unique id of glyph (for drawing in hardware accelerated scenes)
        uint id;
    }

    /// 0: width of glyph black box
    ushort blackBoxX;

    @property ushort correctedBlackBoxX()
    {
        return subpixelMode ? (blackBoxX + 2) / 3 : blackBoxX;
    }

    /// 2: height of glyph black box
    ubyte blackBoxY;
    /// 3: X origin for glyph
    byte originX;
    /// 4: Y origin for glyph
    byte originY;

    /// 5: full width of glyph
    ubyte widthPixels;
    /// 6: full width of glyph scaled * 64
    ushort widthScaled;
    /// 8: subpixel rendering mode - if !=SubpixelRenderingMode.none, glyph data contains 3 bytes per pixel instead of 1
    SubpixelRenderingMode subpixelMode;
    /// 9: usage flag, to handle cleanup of unused glyphs
    ubyte lastUsage;

    ///< 10: glyph data, arbitrary size (blackBoxX * blackBoxY)
    ubyte[] glyph;
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
    import std.typecons : Tuple;

    Tuple!Params values;

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

/// C malloc allocated array wrapper
struct MallocBuf(T)
{
    import core.stdc.stdlib : realloc, free;

    private T* _allocated;
    private size_t _allocatedSize;
    private size_t _length;

    /// Get pointer
    @property T* ptr()
    {
        return _allocated;
    }
    /// Get length
    @property size_t length()
    {
        return _length;
    }
    /// Set new length
    @property void length(size_t len)
    {
        if (len > _allocatedSize)
        {
            reserve(_allocatedSize ? len * 2 : len);
        }
        _length = len;
    }
    /// Const array[index];
    T opIndex(size_t index) const
    {
        assert(index < _length);
        return _allocated[index];
    }
    /// Ref array[index];
    ref T opIndex(size_t index)
    {
        assert(index < _length);
        return _allocated[index];
    }
    /// Array[index] = value;
    void opIndexAssign(size_t index, T value)
    {
        assert(index < _length);
        _allocated[index] = value;
    }
    /// Array[index] = value;
    void opIndexAssign(size_t index, T[] values)
    {
        assert(index + values.length < _length);
        _allocated[index .. index + values.length] = values[];
    }
    /// Array[a..b]
    T[] opSlice(size_t a, size_t b)
    {
        assert(a <= b && b <= _length);
        return _allocated[a .. b];
    }
    /// Array[]
    T[] opSlice()
    {
        return _allocated ? _allocated[0 .. _length] : null;
    }
    /// Array[$]
    size_t opDollar()
    {
        return _length;
    }

    ~this()
    {
        clear();
    }
    /// Free allocated memory, set length to 0
    void clear()
    {
        if (_allocated)
            free(_allocated);
        _allocatedSize = 0;
        _length = 0;
    }
    /// Make sure buffer capacity is at least (size) items
    void reserve(size_t size)
    {
        if (_allocatedSize < size)
        {
            _allocated = cast(T*)realloc(_allocated, T.sizeof * size);
            _allocatedSize = size;
        }
    }
    /// Fill buffer with specified value
    void fill(T value)
    {
        if (_length)
        {
            _allocated[0 .. _length] = value;
        }
    }
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
