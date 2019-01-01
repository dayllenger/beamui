/**
Basic geometric data types.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.geometry;

import beamui.core.math3d : Vec2, Vec2i;

/// Size is undefined constant
enum int SIZE_UNSPECIFIED = 1 << 29; // not too much to safely sum two such values

alias Point = Vec2i;
alias PointInt = Vec2i;

/// 2D size
struct Size
{
    int width;
    int height;
    alias w = width;
    alias h = height;

    enum none = Size(SIZE_UNSPECIFIED, SIZE_UNSPECIFIED);

pure nothrow @nogc:

    Size opBinary(string op : "+")(Size v) const
    {
        return Size(w + v.w, h + v.h);
    }
    Size opBinary(string op : "-")(Size v) const
    {
        return Size(w - v.w, h - v.h);
    }
    Size opBinary(string op : "*")(int n) const
    {
        return Size(w * n, h * n);
    }
    Size opBinary(string op : "/")(int n) const
    {
        return Size(w / n, h / n);
    }

    void opOpAssign(string op : "+")(Size v)
    {
        w += v.w;
        h += v.h;
    }
    void opOpAssign(string op : "-")(Size v)
    {
        w -= v.w;
        h -= v.h;
    }
    void opOpAssign(string op : "*")(int n)
    {
        w *= n;
        h *= n;
    }
    void opOpAssign(string op : "/")(int n)
    {
        w /= n;
        h /= n;
    }
}

/// Holds minimum, maximum and natural (preferred) size for widget
struct Boundaries
{
    static import std.algorithm;

    Size min;
    Size nat;
    Size max = Size.none;

pure nothrow @nogc:

    /// Special add operator: it clamps result between 0 and SIZE_UNSPECIFIED
    static int clampingAdd(int a, int b)
    {
        return std.algorithm.clamp(a + b, 0, SIZE_UNSPECIFIED);
    }

    /// Special subtract operator: it clamps result between 0 and SIZE_UNSPECIFIED
    static int clampingSub(int a, int b)
    {
        return std.algorithm.clamp(a - b, 0, SIZE_UNSPECIFIED);
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

    @property const
    {
        /// Returns average of left, right
        int middlex()
        {
            return (left + right) / 2;
        }
        /// Returns average of top, bottom
        int middley()
        {
            return (top + bottom) / 2;
        }
        /// Returns middle point
        Point middle()
        {
            return Point(middlex, middley);
        }

        /// Returns top left point of rectangle
        Point topLeft()
        {
            return Point(left, top);
        }
        /// Returns bottom right point of rectangle
        Point bottomRight()
        {
            return Point(right, bottom);
        }

        /// Returns size (right - left, bottom - top)
        Size size()
        {
            return Size(right - left, bottom - top);
        }
        /// Get width of rectangle (right - left)
        int width()
        {
            return right - left;
        }
        /// Get height of rectangle (bottom - top)
        int height()
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
        return rc.left < right && rc.top < bottom && rc.right > left && rc.bottom > top;
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

    Insets opBinary(string op : "+")(Insets ins) const
    {
        return Insets(top + ins.top, right + ins.right, bottom + ins.bottom, left + ins.left);
    }

    Insets opBinary(string op : "-")(Insets ins) const
    {
        return Insets(top - ins.top, right - ins.right, bottom - ins.bottom, left - ins.left);
    }

    Insets opBinary(string op : "*")(float factor) const
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
