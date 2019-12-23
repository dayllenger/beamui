/**
Basic geometric data types.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.geometry;

nothrow:

import std.conv : to;
import std.format : format;
import std.math : isFinite;
import std.traits;
import beamui.core.linalg : Vector;
import beamui.core.math : clamp, max;

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

/// 2D size
struct SizeOf(T) if (is(T == float) || is(T == int))
{
    nothrow:

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

    string toString() const
    {
        try
            return format("[%s, %s]", w, h);
        catch (Exception e)
            return null;
    }
}

/// Holds minimum, maximum and natural (preferred) size for widget
struct Boundaries
{
    nothrow:

    Size min;
    Size nat;
    Size max = Size.none;

    /// Special add operator: it clamps result between 0 and SIZE_UNSPECIFIED
    static int clampingAdd(int a, int b)
    {
        return .clamp(a + b, 0, SIZE_UNSPECIFIED!int);
    }

    /// Special subtract operator: it clamps result between 0 and SIZE_UNSPECIFIED
    static int clampingSub(int a, int b)
    {
        return .clamp(a - b, 0, SIZE_UNSPECIFIED!int);
    }

    void addWidth(ref const Boundaries from)
    {
        max.w = clampingAdd(max.w, from.max.w);
        nat.w += from.nat.w;
        min.w += from.min.w;
    }

    void addHeight(ref const Boundaries from)
    {
        max.h = clampingAdd(max.h, from.max.h);
        nat.h += from.nat.h;
        min.h += from.min.h;
    }

    void maximizeWidth(ref const Boundaries from)
    {
        max.w = .max(max.w, from.max.w);
        nat.w = .max(nat.w, from.nat.w);
        min.w = .max(min.w, from.min.w);
    }

    void maximizeHeight(ref const Boundaries from)
    {
        max.h = .max(max.h, from.max.h);
        nat.h = .max(nat.h, from.nat.h);
        min.h = .max(min.h, from.min.h);
    }

    void maximize(ref const Boundaries from)
    {
        max.w = .max(max.w, from.max.w);
        nat.w = .max(nat.w, from.nat.w);
        min.w = .max(min.w, from.min.w);
        max.h = .max(max.h, from.max.h);
        nat.h = .max(nat.h, from.nat.h);
        min.h = .max(min.h, from.min.h);
    }

    string toString() const
    {
        try
            return format("{[%s, %s], [%s, %s], [%s, %s]}",
                min.w, min.h, nat.w, nat.h,
                isDefinedSize(max.w) ? to!string(max.w) : "max",
                isDefinedSize(max.h) ? to!string(max.h) : "max",
            );
        catch (Exception e)
            return null;
    }
}

/// 2D box
struct BoxOf(T) if (is(T == float) || is(T == int))
{
    nothrow:

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

    /// Construct from a box with another base type via casting
    static BoxOf from(U)(BoxOf!U source)
    {
        return BoxOf!T(cast(T)source.x, cast(T)source.y, cast(T)source.w, cast(T)source.h);
    }

    @property
    {
        /// Position as `PointOf!T`
        PointOf!T pos() const
        {
            return PointOf!T(x, y);
        }
        /// ditto
        void pos(PointOf!T p)
        {
            x = p.x;
            y = p.y;
        }

        /// Size as `SizeOf!T`
        SizeOf!T size() const
        {
            return SizeOf!T(w, h);
        }
        /// ditto
        void size(SizeOf!T s)
        {
            w = s.w;
            h = s.h;
        }

        /// True if the box is empty
        bool empty() const
        {
            return w <= 0 || h <= 0;
        }

        /// The center point
        PointOf!T middle() const
        {
            return PointOf!T(x + w / 2, y + h / 2);
        }
        /// The midpoint of X side
        T middleX() const
        {
            return x + w / 2;
        }
        /// The midpoint of Y side
        T middleY() const
        {
            return y + h / 2;
        }
    }

    /// Returns true if `b` is completely inside the box
    bool contains(BoxOf b) const
    {
        return x <= b.x && b.x + b.w <= x + w && y <= b.y && b.y + b.h <= y + h;
    }
    /// Returns true if `pt` is inside the box
    bool contains(PointOf!T pt) const
    {
        return x <= pt.x && pt.x < x + w && y <= pt.y && pt.y < y + h;
    }
    /// Returns true if `(px, py)` point is inside the rectangle
    bool contains(T px, T py) const
    {
        return x <= px && px < x + w && y <= py && py < y + h;
    }
    /// Returns true if `px` is between left and right sides
    bool containsX(T px) const
    {
        return x <= px && px < x + w;
    }
    /// Returns true if `py` is between top and bottom sides
    bool containsY(T py) const
    {
        return y <= py && py < y + h;
    }

    /// Return a box expanded by a margin
    BoxOf expanded(InsetsOf!T ins) const
    {
        return BoxOf(x - ins.left, y - ins.top, w + ins.left + ins.right, h + ins.top + ins.bottom);
    }
    /// Return a box shrinked by a margin
    BoxOf shrinked(InsetsOf!T ins) const
    {
        return BoxOf(x + ins.left, y + ins.top, w - ins.left - ins.right, h - ins.top - ins.bottom);
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
    void moveToFit(BoxOf b)
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

    string toString() const
    {
        try
            return format("{(%s, %s), [%s, %s]}", x, y, w, h);
        catch (Exception e)
            return null;
    }
}

/** 2D rectangle.

    It differs from `Box` in that it stores coordinates of the top-left and bottom-right corners.
    `Box` is more convenient when dealing with widgets, `Rect` is better in drawing procedures.

    Note: `Rect(0,0,20,10)` has size 20x10, but right and bottom sides are non-inclusive.
    If you draw such rect, rightmost drawn pixel will be x=19 and bottom pixel y=9
*/
struct RectOf(T) if (is(T == float) || is(T == int))
{
    nothrow:

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

    /// Construct from a rectangle with another base type via casting
    static RectOf from(U)(RectOf!U source)
    {
        return RectOf!T(
            cast(T)source.left,
            cast(T)source.top,
            cast(T)source.right,
            cast(T)source.bottom,
        );
    }

    @property const
    {
        /// Top left point
        PointOf!T topLeft()
        {
            return PointOf!T(left, top);
        }
        /// Bottom right point
        PointOf!T bottomRight()
        {
            return PointOf!T(right, bottom);
        }

        /// Size (i.e. `right - left, bottom - top`)
        SizeOf!T size()
        {
            return SizeOf!T(right - left, bottom - top);
        }
        /// Width (i.e. `right - left`)
        T width()
        {
            return right - left;
        }
        /// Height (i.e. `bottom - top`)
        T height()
        {
            return bottom - top;
        }

        /// True if the rectangle is empty (i.e. `right <= left || bottom <= top`)
        bool empty()
        {
            return right <= left || bottom <= top;
        }

        /// The center point
        PointOf!T middle()
        {
            return PointOf!T((left + right) / 2, (top + bottom) / 2);
        }
        /// The midpoint of X side
        T middleX()
        {
            return (left + right) / 2;
        }
        /// The midpoint of Y side
        T middleY()
        {
            return (top + bottom) / 2;
        }
    }

    /// Returns true if `rc` is completely inside the rectangle
    bool contains(RectOf rc) const
    {
        return left <= rc.left && right >= rc.right && top <= rc.top && bottom >= rc.bottom;
    }
    /// Returns true if `pt` is inside the rectangle
    bool contains(PointOf!T pt) const
    {
        return left <= pt.x && pt.x < right && top <= pt.y && pt.y < bottom;
    }
    /// Returns true if `(x, y)` point is inside the rectangle
    bool contains(T x, T y) const
    {
        return left <= x && x < right && top <= y && y < bottom;
    }
    /// Returns true if `x` is between left and right sides
    bool containsX(T x) const
    {
        return left <= x && x < right;
    }
    /// Returns true if `y` is between top and bottom sides
    bool containsY(T y) const
    {
        return top <= y && y < bottom;
    }

    /// Translate the rectangle by `(dx, dy)`
    void translate(T dx, T dy)
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

    /// Moves this rect to fit `rc` bounds, retaining the same size
    void moveToFit(RectOf rc)
    {
        if (right > rc.right)
            translate(rc.right - right, 0);
        if (bottom > rc.bottom)
            translate(0, rc.bottom - bottom);
        if (left < rc.left)
            translate(rc.left - left, 0);
        if (top < rc.top)
            translate(0, rc.top - top);
    }

    /// Update this rect to intersection with `rc`, returns true if it's not empty after that
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
    /// Returns true if this rect has nonempty intersection with `rc`
    bool intersects(RectOf rc) const
    {
        return rc.left < right && rc.top < bottom && rc.right > left && rc.bottom > top;
    }

    /// Expand this rectangle to include `rc`
    void include(RectOf rc)
    {
        if (left > rc.left)
            left = rc.left;
        if (top > rc.top)
            top = rc.top;
        if (right < rc.right)
            right = rc.right;
        if (bottom < rc.bottom)
            bottom = rc.bottom;
    }

    string toString() const
    {
        try
            return format("{(%s, %s), (%s, %s)}", left, top, right, bottom);
        catch (Exception e)
            return null;
    }
}

/// Represents area around rectangle. Used for margin, border and padding
struct InsetsOf(T) if (is(T == float) || is(T == int))
{
    nothrow:

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

    /// Construct from offsets with another base type via casting
    static InsetsOf from(U)(InsetsOf!U source)
    {
        return InsetsOf!T(
            cast(T)source.top,
            cast(T)source.right,
            cast(T)source.bottom,
            cast(T)source.left
        );
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

    string toString() const
    {
        try
            return format("{%s, %s, %s, %s}", top, right, bottom, left);
        catch (Exception e)
            return null;
    }
}

alias PointOf(T) = Vector!(T, 2);
alias Point = PointOf!int;
alias PointI = PointOf!int;
alias Size = SizeOf!int;
alias SizeI = SizeOf!int;
alias Box = BoxOf!int;
alias BoxI = BoxOf!int;
alias Rect = RectOf!int;
alias RectF = RectOf!float;
alias RectI = RectOf!int;
alias Insets = InsetsOf!int;
alias InsetsI = InsetsOf!int;
