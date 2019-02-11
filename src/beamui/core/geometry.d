/**
Basic geometric data types.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.geometry;

import std.math : isFinite;
import std.traits;
import beamui.core.math3d : Vector;

/// True if size is sane, e.g. not `-infinity`. Used primarly in contracts
bool isValidSize(float floating)
{
    return (isFinite(floating) || floating == SIZE_UNSPECIFIED!float) && floating != SIZE_UNSPECIFIED!int;
}
/// ditto
bool isValidSize(int integer)
{
    return integer != int.min;
}
/// True if size is finite, i.e. not `SIZE_UNSPECIFIED`
bool isDefinedSize(float floating)
{
    assert(isValidSize(floating), "Invalid floating point size");
    return floating != SIZE_UNSPECIFIED!float;
}
/// ditto
bool isDefinedSize(int integer)
{
    assert(isValidSize(integer), "Invalid integer size, could be cast from NaN or infinity");
    return integer < SIZE_UNSPECIFIED!int;
}

/// Size is undefined constant
enum float SIZE_UNSPECIFIED(T : float) = float.infinity;
/// ditto
enum int SIZE_UNSPECIFIED(T : int) = 1 << 29; // not too much to safely sum two such values

alias PointOf(T) = Vector!(T, 2);
alias Point = PointOf!int;
alias PointI = PointOf!int;

/// 2D size
struct SizeOf(T) if (is(T == float) || is(T == int))
{
    T width = 0;
    T height = 0;
    alias w = width;
    alias h = height;

    enum none = SizeOf(SIZE_UNSPECIFIED!T, SIZE_UNSPECIFIED!T);

    SizeOf opBinary(string op : "+")(SizeOf v) const
    {
        return SizeOf(w + v.w, h + v.h);
    }
    SizeOf opBinary(string op : "-")(SizeOf v) const
    {
        return SizeOf(w - v.w, h - v.h);
    }
    SizeOf opBinary(string op : "*")(T n) const
    {
        return SizeOf(w * n, h * n);
    }
    SizeOf opBinary(string op : "/")(T n) const
    {
        return SizeOf(w / n, h / n);
    }

    void opOpAssign(string op : "+")(SizeOf v)
    {
        w += v.w;
        h += v.h;
    }
    void opOpAssign(string op : "-")(SizeOf v)
    {
        w -= v.w;
        h -= v.h;
    }
    void opOpAssign(string op : "*")(T n)
    {
        w *= n;
        h *= n;
    }
    void opOpAssign(string op : "/")(T n)
    {
        w /= n;
        h /= n;
    }
}

alias Size = SizeOf!int;
alias SizeI = SizeOf!int;

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
        return std.algorithm.clamp(a + b, 0, SIZE_UNSPECIFIED!int);
    }

    /// Special subtract operator: it clamps result between 0 and SIZE_UNSPECIFIED
    static int clampingSub(int a, int b)
    {
        return std.algorithm.clamp(a - b, 0, SIZE_UNSPECIFIED!int);
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
struct BoxOf(T) if (is(T == float) || is(T == int))
{
    /// x coordinate of the top left corner
    T x = 0;
    /// y coordinate of the top left corner
    T y = 0;
    /// Rectangle width
    T width = 0;
    /// Rectangle height
    T height = 0;
    alias w = width;
    alias h = height;

    static if (is(T == int))
    {
        /// 'rectangle is not set' value
        enum none = BoxOf(int.min, int.min, int.min, int.min);
    }

    /// Construct a box using x, y, width and height
    this(T x, T y, T width, T height)
    {
        this.x = x;
        this.y = y;
        this.w = width;
        this.h = height;
    }
    /// Construct a box using position and size
    this(PointOf!T p, SizeOf!T sz)
    {
        x = p.x;
        y = p.y;
        w = sz.w;
        h = sz.h;
    }
    /// Construct a box using `Rect`
    this(RectOf!T rc)
    {
        x = rc.left;
        y = rc.top;
        w = rc.width;
        h = rc.height;
    }
    /// Construct a box from another BoxOf through casting
    this(U)(BoxOf!U source)
    {
        x = cast(U)source.x;
        y = cast(U)source.y;
        w = cast(U)source.w;
        h = cast(U)source.h;
    }

    /// Get box position
    @property PointOf!T pos() const
    {
        return PointOf!T(x, y);
    }
    /// Get box size
    @property SizeOf!T size() const
    {
        return SizeOf!T(w, h);
    }
    /// Set box position
    @property void pos(PointOf!T p)
    {
        x = p.x;
        y = p.y;
    }
    /// Set box size
    @property void size(SizeOf!T s)
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
    @property PointOf!T middle() const
    {
        return PointOf!T(x + w / 2, y + h / 2);
    }
    /// Returns x coordinate of the center
    @property T middlex() const
    {
        return x + w / 2;
    }
    /// Returns y coordinate of the center
    @property T middley() const
    {
        return y + h / 2;
    }

    /// Returns true if point is inside of this rectangle
    bool isPointInside(T px, T py) const
    {
        return x <= px && px < x + w && y <= py && py < y + h;
    }
    /// Returns true if this box is completely inside of `b`
    bool isInsideOf(BoxOf b) const
    {
        return b.x <= x && x + w <= b.x + b.w && b.y <= y && y + h <= b.y + b.h;
    }

    /// Return a box expanded by a margin
    BoxOf expanded(InsetsOf!T ins) const
    {
        return Box(x - ins.left, y - ins.top, w + ins.left + ins.right, h + ins.top + ins.bottom);
    }
    /// Return a box shrinked by a margin
    BoxOf shrinked(InsetsOf!T ins) const
    {
        return Box(x + ins.left, y + ins.top, w - ins.left - ins.right, h - ins.top - ins.bottom);
    }

    /// Expand box dimensions by a margin
    void expand(InsetsOf!T ins)
    {
        x -= ins.left;
        y -= ins.top;
        w += ins.left + ins.right;
        h += ins.top + ins.bottom;
    }
    /// Shrink box dimensions by a margin
    void shrink(InsetsOf!T ins)
    {
        x += ins.left;
        y += ins.top;
        w -= ins.left + ins.right;
        h -= ins.top + ins.bottom;
    }

    /// Move this box to fit `b` bounds, retaining the same size
    void moveToFit(const ref BoxOf b)
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

alias Box = BoxOf!int;
alias BoxI = BoxOf!int;

/**
    2D rectangle

    It differs from Box in that it stores coordinates of the top-left and bottom-right corners.
    Box is more convenient when dealing with widgets, Rect is better in drawing procedures.

    Note: Rect(0,0,20,10) has size 20x10, but right and bottom sides are non-inclusive.
    If you draw such rect, rightmost drawn pixel will be x=19 and bottom pixel y=9
*/
struct RectOf(T) if (is(T == float) || is(T == int))
{
    /// x coordinate of top left corner
    T left = 0;
    /// y coordinate of top left corner
    T top = 0;
    /// x coordinate of bottom right corner (non-inclusive)
    T right = 0;
    /// y coordinate of bottom right corner (non-inclusive)
    T bottom = 0;

    /// Construct a rectangle using left, top, right, bottom coordinates
    this(T x0, T y0, T x1, T y1)
    {
        left = x0;
        top = y0;
        right = x1;
        bottom = y1;
    }
    /// Construct a rectangle using two points - (left, top), (right, bottom) coordinates
    this(PointOf!T pt0, PointOf!T pt1)
    {
        left = pt0.x;
        top = pt0.y;
        right = pt1.x;
        bottom = pt1.y;
    }
    /// Construct a rectangle from a box
    this(BoxOf!T b)
    {
        left = b.x;
        top = b.y;
        right = b.x + b.w;
        bottom = b.y + b.h;
    }
    /// Construct a rectangle from another RectOf through casting
    this(U)(RectOf!U source)
    {
        left = cast(U)source.left;
        top = cast(U)source.top;
        right = cast(U)source.right;
        bottom = cast(U)source.bottom;
    }

    @property const
    {
        /// Returns average of left, right
        T middlex()
        {
            return (left + right) / 2;
        }
        /// Returns average of top, bottom
        T middley()
        {
            return (top + bottom) / 2;
        }
        /// Returns middle point
        PointOf!T middle()
        {
            return PointOf!T(middlex, middley);
        }

        /// Returns top left point of rectangle
        PointOf!T topLeft()
        {
            return PointOf!T(left, top);
        }
        /// Returns bottom right point of rectangle
        PointOf!T bottomRight()
        {
            return PointOf!T(right, bottom);
        }

        /// Returns size (right - left, bottom - top)
        SizeOf!T size()
        {
            return SizeOf!T(right - left, bottom - top);
        }
        /// Get width of rectangle (right - left)
        T width()
        {
            return right - left;
        }
        /// Get height of rectangle (bottom - top)
        T height()
        {
            return bottom - top;
        }
        /// Returns true if rectangle is empty (right <= left || bottom <= top)
        bool empty()
        {
            return right <= left || bottom <= top;
        }
    }

    /// Add offset to horizontal and vertical coordinates
    void offset(T dx, T dy)
    {
        left += dx;
        right += dx;
        top += dy;
        bottom += dy;
    }
    /// Expand rectangle dimensions
    void expand(T dx, T dy)
    {
        left -= dx;
        right += dx;
        top -= dy;
        bottom += dy;
    }
    /// Shrink rectangle dimensions
    void shrink(T dx, T dy)
    {
        left += dx;
        right -= dx;
        top += dy;
        bottom -= dy;
    }
    /// For all fields, sets this.field to rc.field if rc.field > this.field
    void setMax(RectOf rc)
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
    void moveToFit(ref RectOf rc)
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
    bool intersect(RectOf rc)
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
    bool intersects(RectOf rc) const
    {
        return rc.left < right && rc.top < bottom && rc.right > left && rc.bottom > top;
    }
    /// Returns true if point is inside of this rectangle
    bool isPointInside(PointOf!T pt) const
    {
        return left <= pt.x && pt.x < right && top <= pt.y && pt.y < bottom;
    }
    /// Returns true if point is inside of this rectangle
    bool isPointInside(T x, T y) const
    {
        return left <= x && x < right && top <= y && y < bottom;
    }
    /// This rectangle is completely inside rc
    bool isInsideOf(RectOf rc) const
    {
        return left >= rc.left && right <= rc.right && top >= rc.top && bottom <= rc.bottom;
    }

    bool opEquals(RectOf rc) const
    {
        return left == rc.left && right == rc.right && top == rc.top && bottom == rc.bottom;
    }
}

alias Rect = RectOf!int;
alias RectI = RectOf!int;

/// Represents area around rectangle. Used for margin, border and padding
struct InsetsOf(T) if (is(T == float) || is(T == int))
{
    T top = 0, right = 0, bottom = 0, left = 0;

    /// Create equal offset on all sides
    this(T all)
    {
        top = right = bottom = left = all;
    }
    /// Create separate horizontal and vertical offsets
    this(T v, T h)
    {
        top = bottom = v;
        right = left = h;
    }
    /// Create offsets one by one
    this(T top, T right, T bottom, T left)
    {
        this.top = top;
        this.right = right;
        this.bottom = bottom;
        this.left = left;
    }
    /// Create offsets from another InsetsOf through casting
    this(U)(InsetsOf!U source)
    {
        top = cast(U)source.top;
        right = cast(U)source.right;
        bottom = cast(U)source.bottom;
        left = cast(U)source.left;
    }

    /// Get total offset
    @property SizeOf!T size() const
    {
        return SizeOf!T(left + right, top + bottom);
    }
    /// Get total horizontal offset
    @property T width() const
    {
        return left + right;
    }
    /// Get total vertical offset
    @property T height() const
    {
        return top + bottom;
    }

    InsetsOf opBinary(string op : "+")(InsetsOf ins) const
    {
        return InsetsOf(top + ins.top, right + ins.right, bottom + ins.bottom, left + ins.left);
    }

    InsetsOf opBinary(string op : "-")(InsetsOf ins) const
    {
        return InsetsOf(top - ins.top, right - ins.right, bottom - ins.bottom, left - ins.left);
    }

    InsetsOf opBinary(string op : "*")(float factor) const
    {
        return InsetsOf(cast(T)(top * factor), cast(T)(right * factor),
                        cast(T)(bottom * factor), cast(T)(left * factor));
    }

    /// Sum two areas
    void add(InsetsOf ins)
    {
        top += ins.top;
        right += ins.right;
        bottom += ins.bottom;
        left += ins.left;
    }
}

alias Insets = InsetsOf!int;
alias InsetsI = InsetsOf!int;
