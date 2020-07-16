/**
Drawables and widget background.

imageCache is RAM cache of decoded images (as Bitmap).

Supports nine-patch PNG images in .9.png files (like in Android).


Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.graphics.drawables;

import std.string;
import beamui.core.config;
import beamui.core.functions;
import beamui.core.geometry;
import beamui.core.linalg : Vec2, Mat2x3;
import beamui.core.logger;
import beamui.core.math;
import beamui.core.resources;
import beamui.core.types;
import beamui.core.units;
import beamui.graphics.bitmap;
import beamui.graphics.brush;
import beamui.graphics.colors;
import beamui.graphics.painter : Painter, PaintSaver;
import beamui.graphics.path;

static if (BACKEND_GUI)
{
    import beamui.graphics.images;
}

/// Base abstract class for all drawables
class Drawable : RefCountedObject
{
    this()
    {
        debug const count = debugPlusInstance();
        debug (resalloc)
            Log.d("Created drawable ", getShortClassName(this), ", count: ", count);
    }

    ~this()
    {
        debug const count = debugMinusInstance();
        debug (resalloc)
            Log.d("Destroyed drawable ", getShortClassName(this), ", count: ", count);
    }

    mixin DebugInstanceCount;

    abstract void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0);

    /// Size of the drawable in device-independent pixels
    @property Size size() const
    {
        return Size(0, 0);
    }
    /// Padding of the drawable in device-independent pixels
    @property Insets padding() const
    {
        return Insets(0);
    }
}

alias DrawableRef = Ref!Drawable;

class EmptyDrawable : Drawable
{
    override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
    {
    }
}

class SolidFillDrawable : Drawable
{
    private Color _color;

    this(Color color)
    {
        _color = color;
    }

    override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
    {
        pr.fillRect(b.x, b.y, b.w, b.h, _color);
    }
}

class GradientDrawable : Drawable
{
    // angle goes clockwise
    private float _angle = 0;
    private GradientBuilder _builder;

    this(float angle, Color color1, Color color2)
    {
        _angle = angle;
        _builder.addStop(0, color1).addStop(1, color2);
    }

    override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
    {
        static Path path;
        path.reset();
        path.lineBy(b.w, 0).lineBy(0, b.h).lineBy(-b.w, 0).close();

        const points = computeGradientLine(b.w, b.h, _angle);
        const brush = _builder.makeLinear(points[0].x, points[0].y, points[1].x, points[1].y);
        pr.translate(b.x, b.y);
        pr.fill(path, brush);
        pr.translate(-b.x, -b.y);
    }
}

private Vec2[2] computeGradientLine(float w, float h, float angle)
{
    // see the illustration at https://www.w3.org/TR/css-images-3/#linear-gradients

    import std.math : isFinite, sin, cos, PI, PI_2;

    angle = angle % (PI * 2);
    if (angle < 0)
        angle += PI * 2;

    if (fequal6(angle, 0))
        return [Vec2(w / 2, 0), Vec2(w / 2, h)];
    if (fequal6(angle, PI_2))
        return [Vec2(0, h / 2), Vec2(w, h / 2)];
    if (fequal6(angle, PI))
        return [Vec2(w / 2, h), Vec2(w / 2, 0)];
    if (fequal6(angle, 3 * PI_2))
        return [Vec2(w, h / 2), Vec2(0, h / 2)];

    const sin_a = sin(angle);
    const cos_a = cos(angle);
    const tan_a = sin_a / cos_a;
    assert(isFinite(tan_a));

    if ((0 <= angle && angle < PI_2) || (PI <= angle && angle < 3 * PI_2))
    {
        const a = h / 2 * tan_a;
        const b = (w / 2 - a) * sin_a;
        const c = b * sin_a;
        const d = b * cos_a;
        const ac = a + c;
        const s = Vec2(w / 2 - ac, h + d);
        const e = Vec2(w / 2 + ac, -d);
        if (angle < PI_2)
            return [s, e];
        else
            return [e, s];
    }
    else
    {
        const a = h / 2 * -tan_a;
        const b = (w / 2 - a) * -sin_a;
        const c = b * -sin_a;
        const d = b * cos_a;
        const ac = a + c;
        const s = Vec2(w / 2 - ac, -d);
        const e = Vec2(w / 2 + ac, h + d);
        if (angle < PI)
            return [s, e];
        else
            return [e, s];
    }
}

/// Box shadows drawable, can be blurred
class BoxShadowDrawable : Drawable
{
    const int offsetX;
    const int offsetY;
    const int blurSize;
    const Color color;
    private Bitmap _bitmap;

    this(int offsetX, int offsetY, uint blurSize = 0, Color color = Color.black)
    {
        this.offsetX = offsetX;
        this.offsetY = offsetY;
        this.blurSize = blurSize;
        this.color = color;
        if (blurSize == 0)
            return;

        // now create a bitmap that will contain the shadow
        const size = 4 * blurSize + 1;
        _bitmap = Bitmap(size, size, PixelFormat.argb8);
        // draw a square in center of the bitmap
        _bitmap.fillRect(RectI(blurSize, blurSize, size - blurSize, size - blurSize), color);
        // blur the square
        blurBitmapARGB8(_bitmap, blurSize);
        _bitmap.preMultiplyAlpha();
        // set 9-patch frame
        const sz = blurSize * 2;
        _bitmap.ninePatch = new NinePatch(InsetsI(sz), InsetsI(sz));
    }

    override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
    {
        // move and expand the shadow
        b.x += offsetX;
        b.y += offsetY;
        b.expand(Insets(blurSize));

        // now draw
        if (blurSize > 0)
        {
            pr.drawNinePatch(_bitmap, RectI(0, 0, _bitmap.width, _bitmap.height), Rect(b), 1);
            // debug
            // pr.drawImage(_bitmap, b.x, b.y, 1);
        }
        else
        {
            pr.fillRect(b.x, b.y, b.w, b.h, color);
        }
    }
}

/// Apply Gaussian blur to the bitmap. This is a slow function, but it's fine for box shadows for now
private void blurBitmapARGB8(ref Bitmap bitmap, uint blurSize)
in (bitmap.format == PixelFormat.argb8)
{
    if (blurSize == 0)
        return; // trivial case

    import std.math : exp, sqrt, PI;
    import beamui.core.collections : Buf;

    // precompute weights
    Buf!float weights;
    weights.reserve(blurSize + 1);
    weights ~= 0;
    const float sigma = blurSize > 2 ? blurSize / 3.0f : blurSize / 2.0f;
    float centerWeight = 1;
    foreach (float x; 1 .. blurSize + 1)
    {
        // Gaussian function
        enum inv_sqrt_2pi = 1 / sqrt(2 * PI);
        const wgh = exp(-x * x / (2 * sigma * sigma)) * inv_sqrt_2pi / sigma;
        weights ~= wgh;
        centerWeight -= 2 * wgh;
    }

    static float[4] conv(uint c)
    {
        const float a = (c >> 24);
        const float r = (c >> 16) & 0xFF;
        const float g = (c >> 8) & 0xFF;
        const float b = (c >> 0) & 0xFF;
        return [r, g, b, a];
    }

    const float* pweights = weights[].ptr;
    const w = bitmap.width;
    const h = bitmap.height;

    // blur horizontally
    void blurH(PixelRef!uint pixels)
    {
        // small intermediate buffer
        Buf!(float[4]) row;
        row.resize(w);
        const float[4]* line = row[].ptr;
        foreach (y; 0 .. h)
        {
            uint* scanline = pixels.scanline(y);
            foreach (x; 0 .. w)
                row[x] = conv(scanline[x]);
            foreach (x; 0 .. w)
            {
                float[4] c = 0;
                foreach (int i; 1 .. blurSize + 1)
                {
                    const float[4] c1 = line[(x + i) % w];
                    const float[4] c2 = line[(x - i + w) % w];
                    c[] += (c1[] + c2[]) * pweights[i];
                }
                c[] += line[x][] * centerWeight;
                scanline[x] = makeRGBA(c[0], c[1], c[2], c[3]);
            }
        }
    }
    // blur vertically
    void blurV(PixelRef!uint pixels)
    {
        // small intermediate buffer
        Buf!(float[4]) col;
        col.resize(h);
        const float[4]* line = col[].ptr;
        foreach (x; 0 .. w)
        {
            foreach (y; 0 .. h)
                col[y] = conv(pixels.scanline(y)[x]);
            foreach (y; 0 .. h)
            {
                uint* scanline = pixels.scanline(y);
                float[4] c = 0;
                foreach (int i; 1 .. blurSize + 1)
                {
                    const float[4] c1 = line[(y + i) % h];
                    const float[4] c2 = line[(y - i + h) % h];
                    c[] += (c1[] + c2[]) * pweights[i];
                }
                c[] += line[y][] * centerWeight;
                scanline[x] = makeRGBA(c[0], c[1], c[2], c[3]);
            }
        }
    }

    blurH(bitmap.mutate!uint);
    blurV(bitmap.mutate!uint);
}

static if (BACKEND_CONSOLE)
{
    /**
    Sample format:
    {
        text: [
            "╔═╗",
            "║ ║",
            "╚═╝"],
        backgroundColor: [0x000080], // put more values for individual colors of cells
        textColor: [0xFF0000], // put more values for individual colors of cells
        ninepatch: [1,1,1,1]
    }
    */
    Drawable createTextDrawable(string s)
    {
        auto drawable = new TextDrawable(s);
        if (drawable.width == 0 || drawable.height == 0)
            return null;
        return drawable;
    }
}

static if (BACKEND_CONSOLE)
{
    abstract class ConsoleDrawBuf : Bitmap
    {
        abstract void drawChar(int x, int y, dchar ch, Color color, Color bgcolor);
    }

    /**
        Text image drawable.
        Resource file extension: .tim
        Image format is JSON based. Sample:
                {
                    text: [
                        "╔═╗",
                        "║ ║",
                        "╚═╝"],
                    backgroundColor: [0x000080],
                    textColor: [0xFF0000],
                    ninepatch: [1,1,1,1]
                }

        Short form:
            {'╔═╗' '║ ║' '╚═╝' bc 0x000080 tc 0xFF0000 ninepatch 1 1 1 1}
    */
    class TextDrawable : Drawable
    {
        private
        {
            int _width;
            int _height;
            dchar[] _text;
            Color[] _bgColors;
            Color[] _textColors;
            Insets _padding;
            Rect _ninePatch;
            bool _tiled;
            bool _stretched;
            bool _hasNinePatch;
        }

        this(int dx, int dy, dstring text, Color textColor, Color bgColor)
        {
            _width = dx;
            _height = dy;
            _text.assumeSafeAppend;
            for (int i = 0; i < text.length && i < dx * dy; i++)
                _text ~= text[i];
            for (int i = cast(int)_text.length; i < dx * dy; i++)
                _text ~= ' ';
            _textColors.assumeSafeAppend;
            _bgColors.assumeSafeAppend;
            for (int i = 0; i < dx * dy; i++)
            {
                _textColors ~= textColor;
                _bgColors ~= bgColor;
            }
        }

        this(string src)
        {
            import std.utf;

            this(toUTF32(src));
        }
        /**
            Create from text drawable source file format:
            {
            text:
            "text line 1"
            "text line 2"
            "text line 3"
            backgroundColor: 0xFFFFFF [,0xFFFFFF]*
            textColor: 0x000000, [,0x000000]*
            ninepatch: left,top,right,bottom
            padding: left,top,right,bottom
            }

            Text lines may be in "" or '' or `` quotes.
            bc can be used instead of backgroundColor, tc instead of textColor

            Sample short form:
            { 'line1' 'line2' 'line3' bc 0xFFFFFFFF tc 0x808080 stretch }
        */
        this(dstring src)
        {
            import std.utf;
            import beamui.dml.tokenizer;

            Token[] tokens = tokenize(toUTF8(src), ["//"], true, true, true);
            dstring[] lines;
            enum Mode
            {
                None,
                Text,
                BackgroundColor,
                TextColor,
                Padding,
                NinePatch,
            }

            Mode mode = Mode.Text;
            uint[] bg;
            uint[] col;
            uint[] pad;
            uint[] nine;
            for (int i; i < tokens.length; i++)
            {
                if (tokens[i].type == TokenType.ident)
                {
                    if (tokens[i].text == "backgroundColor" || tokens[i].text == "bc")
                        mode = Mode.BackgroundColor;
                    else if (tokens[i].text == "textColor" || tokens[i].text == "tc")
                        mode = Mode.TextColor;
                    else if (tokens[i].text == "text")
                        mode = Mode.Text;
                    else if (tokens[i].text == "stretch")
                        _stretched = true;
                    else if (tokens[i].text == "tile")
                        _tiled = true;
                    else if (tokens[i].text == "padding")
                    {
                        mode = Mode.Padding;
                    }
                    else if (tokens[i].text == "ninepatch")
                    {
                        _hasNinePatch = true;
                        mode = Mode.NinePatch;
                    }
                    else
                        mode = Mode.None;
                }
                else if (tokens[i].type == TokenType.integer)
                {
                    switch (mode)
                    {
                    case Mode.BackgroundColor:
                        _bgColors ~= Color(tokens[i].intvalue);
                        break;
                    case Mode.TextColor:
                    case Mode.Text:
                        _textColors ~= Color(tokens[i].intvalue);
                        break;
                    case Mode.Padding:
                        pad ~= tokens[i].intvalue;
                        break;
                    case Mode.NinePatch:
                        nine ~= tokens[i].intvalue;
                        break;
                    default:
                        break;
                    }
                }
                else if (tokens[i].type == TokenType.str && mode == Mode.Text)
                {
                    dstring line = toUTF32(tokens[i].text);
                    lines ~= line;
                    if (_width < line.length)
                        _width = cast(int)line.length;
                }
            }
            // pad and convert text
            _height = cast(int)lines.length;
            if (!_height)
            {
                _width = 0;
                return;
            }
            for (int y = 0; y < _height; y++)
            {
                for (int x = 0; x < _width; x++)
                {
                    if (x < lines[y].length)
                        _text ~= lines[y][x];
                    else
                        _text ~= ' ';
                }
            }
            // pad padding and ninepatch
            for (int k = 1; k <= 4; k++)
            {
                if (nine.length < k)
                    nine ~= 0;
                if (pad.length < k)
                    pad ~= 0;
                //if (pad[k-1] < nine[k-1])
                //    pad[k-1] = nine[k-1];
            }
            _padding = Insets(pad[0], pad[1], pad[2], pad[3]);
            _ninePatch = Rect(nine[0], nine[1], nine[2], nine[3]);
            // pad colors
            for (int k = 1; k <= _width * _height; k++)
            {
                if (_textColors.length < k)
                    _textColors ~= _textColors.length ? _textColors[$ - 1] : Color.black;
                if (_bgColors.length < k)
                    _bgColors ~= _bgColors.length ? _bgColors[$ - 1] : Color.transparent;
            }
        }

        override @property Size size() const
        {
            return Size(_width, _height);
        }

        override @property Insets padding() const
        {
            return _padding;
        }

        protected void drawChar(ConsoleDrawBuf buf, int srcx, int srcy, int dstx, int dsty)
        {
            if (srcx < 0 || srcx >= _width || srcy < 0 || srcy >= _height)
                return;
            int index = srcy * _width + srcx;
            if (_textColors[index].isFullyTransparent && _bgColors[index].isFullyTransparent)
                return; // do not draw
            buf.drawChar(dstx, dsty, _text[index], _textColors[index], _bgColors[index]);
        }

        static private int wrapNinePatch(int v, int width, int ninewidth, int left, int right)
        {
            if (v < left)
                return v;
            if (v >= width - right)
                return v - (width - right) + (ninewidth - right);
            return left + (ninewidth - left - right) * (v - left) / (width - left - right);
        }

        private void drawTo(Bitmap drawbuf, Box b, float tilex0 = 0, float tiley0 = 0)
        {
            if (!_width || !_height)
                return; // empty image
            auto buf = cast(ConsoleDrawBuf)drawbuf;
            if (!buf) // wrong draw buffer
                return;
            if (_hasNinePatch || _tiled || _stretched)
            {
                for (int y = 0; y < b.height; y++)
                {
                    for (int x = 0; x < b.width; x++)
                    {
                        int srcx = wrapNinePatch(x, b.width, _width, _ninePatch.left, _ninePatch.right);
                        int srcy = wrapNinePatch(y, b.height, _height, _ninePatch.top, _ninePatch.bottom);
                        drawChar(buf, srcx, srcy, b.x + x, b.y + y);
                    }
                }
            }
            else
            {
                for (int y = 0; y < b.height && y < _height; y++)
                {
                    for (int x = 0; x < b.width && x < _width; x++)
                    {
                        drawChar(buf, x, y, b.x + x, b.y + y);
                    }
                }
            }
        }

        override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
        {
        }
    }
}

/// Drawable which just draws images
class ImageDrawable : Drawable
{
    private Bitmap _bitmap;
    private bool _tiled;

    this(Bitmap bitmap, bool tiled = false)
    {
        _bitmap = bitmap;
        _tiled = tiled;
        debug const count = debugPlusInstance();
        debug (resalloc)
            Log.d("Created ImageDrawable, count: ", count);
    }

    ~this()
    {
        debug const count = debugMinusInstance();
        debug (resalloc)
            Log.d("Destroyed ImageDrawable, count: ", count);
    }

    mixin DebugInstanceCount;

    override @property Size size() const
    {
        if (_bitmap)
        {
            Size sz = Size(_bitmap.width, _bitmap.height);
            if (_bitmap.hasNinePatch)
                sz = Size(sz.w - 2, sz.h - 2);

            const idpr = 10.0f / Length.dipToDevice(10);
            return sz * idpr;
        }
        return Size(0, 0);
    }

    override @property Insets padding() const
    {
        if (_bitmap && _bitmap.hasNinePatch)
        {
            const pad = Insets.from(_bitmap.ninePatch.padding);
            const idpr = 10.0f / Length.dipToDevice(10);
            return pad * idpr;
        }
        return Insets(0);
    }

    override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
    {
        if (!_bitmap)
            return;

        if (_bitmap.hasNinePatch)
        {
            pr.drawNinePatch(_bitmap, RectI(1, 1, _bitmap.width - 1, _bitmap.height - 1), Rect(b), 1);
        }
        else if (_tiled)
        {
            static Path path;
            path.reset();
            path.lineBy(b.w, 0).lineBy(0, b.h).lineBy(-b.w, 0).close();
            const brush = Brush.fromPattern(_bitmap, Mat2x3.translation(Vec2(tilex0, tiley0)));
            pr.translate(b.x, b.y);
            pr.fill(path, brush);
            pr.translate(-b.x, -b.y);
        }
        else
        {
            PaintSaver sv;
            pr.save(sv);
            pr.translate(b.x, b.y);
            pr.scale(b.w / cast(float)_bitmap.width, b.h / cast(float)_bitmap.height);
            pr.drawImage(_bitmap, 0, 0, 1);
        }
    }
}

static if (USE_OPENGL)
{
    /// Custom draw delegate for OpenGL direct drawing
    alias DrawHandler = void delegate(RectI windowRect, RectI rc);

    /// Custom OpenGL drawing inside a drawable
    class OpenGLDrawable : Drawable
    {
        DrawHandler onDraw;

        this(DrawHandler drawHandler = null)
        {
            onDraw = drawHandler;
        }

        void doDraw(RectI windowRect, RectI rc)
        {
            // either override this method or assign draw handler
            if (onDraw)
                onDraw(windowRect, rc);
        }

        override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
        {
            // buf.drawCustomOpenGLScene(Rect(b), &doDraw);
        }

        override @property Size size() const
        {
            return Size(20, 20); // dummy size
        }
    }
}

struct BgPosition
{
    LayoutLength x = LayoutLength.percent(0);
    LayoutLength y = LayoutLength.percent(0);

    static BgPosition mix(BgPosition a, BgPosition b, double factor) nothrow
    {
        const x = a.x * (1 - factor) + b.x * factor;
        const y = a.y * (1 - factor) + b.y * factor;
        return BgPosition(x, y);
    }
}

enum BgSizeType
{
    length,
    contain,
    cover,
}

struct BgSize
{
    BgSizeType type;
    LayoutLength x;
    LayoutLength y;

    static BgSize mix(BgSize a, BgSize b, double factor) nothrow
    {
        if (a.type == BgSizeType.length && b.type == BgSizeType.length)
        {
            const x = a.x * (1 - factor) + b.x * factor;
            const y = a.y * (1 - factor) + b.y * factor;
            return BgSize(b.type, x, y);
        }
        else
            return b;
    }
}

/// Tiling options for one image axis
enum Tiling : ubyte
{
    none,
    repeat,
    space,
    round,
}

/// Tiling options for both image axes
struct RepeatStyle
{
    Tiling x;
    Tiling y;
}

enum BoxType
{
    border,
    padding,
    content,
}

enum BorderStyle : ubyte
{
    none,
    solid,
    dotted,
    dashed,
    doubled,
}

struct BorderSide
{
    float thickness = 0; /// Thickness in device-independent pixels
    BorderStyle style;
    Color color = Color.transparent;
}

/// Box border description
struct Border
{
    BorderSide top;
    BorderSide right;
    BorderSide bottom;
    BorderSide left;

    Insets getSize() const
    {
        return Insets(top.thickness, right.thickness, bottom.thickness, left.thickness);
    }
}

/// 8 border radii in device-independent pixels
struct BorderRadii
{
    Size tl;
    Size tr;
    Size bl;
    Size br;
}

/** Standard widget background. It paints before any content of an element.

    It combines together background color, image (raster, gradient, etc.), and box shadows.
*/
class Background
{
    Color color = Color.transparent;
    Drawable image;
    BgPosition position;
    BgSize size;
    BoxType origin;
    BoxType clip;
    Border border;
    BorderRadii radii;
    BoxShadowDrawable shadow;

    Insets stylePadding;

    void drawTo(Painter pr, Box b)
    {
        // consider clipping
        Box bc = b;
        if (clip != BoxType.border)
        {
            bc.shrink(border.getSize());
            if (clip == BoxType.content)
                bc.shrink(stylePadding);
        }
        // get border thickness
        Insets th;
        if (border.top.style != BorderStyle.none)
            th.top = border.top.thickness;
        if (border.right.style != BorderStyle.none)
            th.right = border.right.thickness;
        if (border.bottom.style != BorderStyle.none)
            th.bottom = border.bottom.thickness;
        if (border.left.style != BorderStyle.none)
            th.left = border.left.thickness;

        if (radii == BorderRadii.init)
            drawRectangular(pr, b, bc, th);
        else
            drawRound(pr, b, bc, th);
    }

    // we will use cubic curves to make elliptic arcs
    private enum k = 0.552285f;
    private enum k1 = 1 - k;

    private void drawRound(Painter pr, Box b, Box bc, Insets th)
    {
        // not yet supported stuff
        if (shadow || image)
        {
            drawRectangular(pr, b, bc, th);
            return;
        }
        if (border.left.color != border.right.color || border.top.color != border.bottom.color)
        {
            drawRectangular(pr, b, bc, th);
            return;
        }
        if (border.left.color != border.top.color)
        {
            drawRectangular(pr, b, bc, th);
            return;
        }
        // reduce overlapping corners
        // dfmt off
        const f = min(
            b.w / (radii.tl.w + radii.tr.w),
            b.w / (radii.bl.w + radii.br.w),
            b.h / (radii.tl.h + radii.bl.h),
            b.h / (radii.tr.h + radii.br.h),
        );
        // dfmt on
        if (f < 1)
        {
            radii.tl *= f;
            radii.tr *= f;
            radii.bl *= f;
            radii.br *= f;
        }

        static Path borderPath;
        borderPath.reset();
        // dfmt off
        borderPath
            .moveTo(b.x + radii.tl.w, b.y)
            .lineBy(b.w - radii.tl.w - radii.tr.w, 0)
            .cubicBy(k * radii.tr.w, 0, radii.tr.w, k1 * radii.tr.h, radii.tr.w, radii.tr.h)
            .lineBy(0, b.h - radii.tr.h - radii.br.h)
            .cubicBy(0, k * radii.br.h, -k1 * radii.br.w, radii.br.h, -radii.br.w, radii.br.h)
            .lineBy(-b.w + radii.bl.w + radii.br.w, 0)
            .cubicBy(-k * radii.bl.w, 0, -radii.bl.w, -k1 * radii.bl.h, -radii.bl.w, -radii.bl.h)
            .lineBy(0, -b.h + radii.bl.h + radii.tl.h)
            .cubicBy(0, -k * radii.tl.h, k1 * radii.tl.w, -radii.tl.h, radii.tl.w, -radii.tl.h)
            .close();
        // dfmt on
        bool hasBorder = !border.top.color.isFullyTransparent;
        hasBorder = hasBorder || !fzero2(th.top);
        hasBorder = hasBorder || !fzero2(th.right);
        hasBorder = hasBorder || !fzero2(th.bottom);
        hasBorder = hasBorder || !fzero2(th.left);

        // color
        {
            PaintSaver sv;
            // for GL paint engine, it's better to disable AA when there is a border
            if (hasBorder)
            {
                pr.save(sv);
                pr.antialias = false;
            }
            const br = Brush.fromSolid(color);
            pr.fill(borderPath, br);
        }
        // border
        if (hasBorder)
        {
            drawRoundBorder(pr, b, th, border.top.color);
        }
    }

    private void drawRoundBorder(Painter pr, Box b, Insets th, Color c)
    {
        // dfmt off
        const bInner = b.shrinked(th);
        const rInner = BorderRadii(
            Size(max(radii.tl.w - th.left, 0), max(radii.tl.h - th.top, 0)),
            Size(max(radii.tr.w - th.right, 0), max(radii.tr.h - th.top, 0)),
            Size(max(radii.bl.w - th.left, 0), max(radii.bl.h - th.bottom, 0)),
            Size(max(radii.br.w - th.right, 0), max(radii.br.h - th.bottom, 0)),
        );

        static Path path;
        path.reset();
        // the outer contour goes cw, the inner one goes ccw
        path.moveTo(b.x + radii.tl.w, b.y)
            .lineBy(b.w - radii.tl.w - radii.tr.w, 0)
            .cubicBy(k * radii.tr.w, 0, radii.tr.w, k1 * radii.tr.h, radii.tr.w, radii.tr.h)
            .lineBy(0, b.h - radii.tr.h - radii.br.h)
            .cubicBy(0, k * radii.br.h, -k1 * radii.br.w, radii.br.h, -radii.br.w, radii.br.h)
            .lineBy(-b.w + radii.bl.w + radii.br.w, 0)
            .cubicBy(-k * radii.bl.w, 0, -radii.bl.w, -k1 * radii.bl.h, -radii.bl.w, -radii.bl.h)
            .lineBy(0, -b.h + radii.bl.h + radii.tl.h)
            .cubicBy(0, -k * radii.tl.h, k1 * radii.tl.w, -radii.tl.h, radii.tl.w, -radii.tl.h)
            .close();
        path.moveTo(bInner.x + rInner.tl.w, bInner.y)
            .cubicBy(-k * rInner.tl.w, 0, -rInner.tl.w, k1 * rInner.tl.h, -rInner.tl.w, rInner.tl.h)
            .lineBy(0, bInner.h - rInner.bl.h - rInner.tl.h)
            .cubicBy(0, k * rInner.bl.h, k1 * rInner.bl.w, rInner.bl.h, rInner.bl.w, rInner.bl.h)
            .lineBy(bInner.w - rInner.bl.w - rInner.br.w, 0)
            .cubicBy(k * rInner.br.w, 0, rInner.br.w, -k1 * rInner.br.h, rInner.br.w, -rInner.br.h)
            .lineBy(0, -(bInner.h - rInner.br.h - rInner.tr.h))
            .cubicBy(0, -k * rInner.tr.h, -k1 * rInner.tr.w, -rInner.tr.h, -rInner.tr.w, -rInner.tr.h)
            .lineBy(-(bInner.w - rInner.tl.w - rInner.tr.w), 0)
            .close();

        // nonzero fill rule hides any overlaps inside the inner corners
        const br = Brush.fromSolid(c);
        pr.fill(path, br);
        // dfmt on
    }

    private void drawRectangular(Painter pr, Box b, Box bc, Insets th)
    {
        // shadow
        if (shadow)
            shadow.drawTo(pr, b);
        // color
        pr.fillRect(bc.x, bc.y, bc.w, bc.h, color);
        // image
        if (image)
        {
            PaintSaver sv;
            pr.save(sv);
            pr.clipIn(bc);
            drawImage(pr, b);
        }
        // border
        pr.translate(b.x, b.y);
        drawBorder(pr, b.size, th);
        pr.translate(-b.x, -b.y);
    }

    private void drawImage(Painter pr, Box b)
    {
        // find the containing box
        if (origin != BoxType.border)
        {
            b.shrink(border.getSize());
            if (origin == BoxType.content)
                b.shrink(stylePadding);
        }
        // determine the size
        const isz = image.size;
        float w = isz.w, h = isz.h;
        if (fzero6(w) || fzero6(h))
        {
            w = b.w;
            h = b.h;
        }
        else if (size.type == BgSizeType.contain)
        {
            if (b.w < w)
            {
                w = b.w;
                h = b.w * isz.h / isz.w;
            }
            if (b.h < h)
            {
                h = b.h;
                w = b.h * isz.w / isz.h;
            }
        }
        else if (size.type == BgSizeType.cover)
        {
            if (b.w > w)
            {
                w = b.w;
                h = b.w * isz.h / isz.w;
            }
            if (b.h > h)
            {
                h = b.h;
                w = b.h * isz.w / isz.h;
            }
        }
        else // length
        {
            if (!size.x.isDefined || !size.y.isDefined)
            {
                if (size.x.isDefined)
                {
                    w = size.x.applyPercent(b.w);
                    h = w * isz.h / isz.w;
                }
                else if (size.y.isDefined)
                {
                    h = size.y.applyPercent(b.h);
                    w = h * isz.w / isz.h;
                }
            }
            else
            {
                w = size.x.applyPercent(b.w);
                h = size.y.applyPercent(b.h);
            }
        }
        // determine the position
        assert(position.x.isDefined);
        assert(position.y.isDefined);
        const x = position.x.applyPercent(b.w - w);
        const y = position.y.applyPercent(b.h - h);
        // draw
        image.drawTo(pr, Box(b.x + x, b.y + y, w, h));
    }

    private void drawBorder(Painter pr, Size sz, Insets th)
    {
        // dfmt off
        static Path path;

        if (!fzero2(th.top) && !border.top.color.isFullyTransparent)
        {
            path.reset();
            path.lineTo(sz.w, 0)
                .lineBy(-th.right, th.top)
                .lineTo(th.left, th.top)
                .close();

            const br = Brush.fromSolid(border.top.color);
            pr.fill(path, br);
        }
        if (!fzero2(th.right) && !border.right.color.isFullyTransparent)
        {
            path.reset();
            path.moveTo(sz.w, 0)
                .lineBy(0, sz.h)
                .lineBy(-th.right, -th.bottom)
                .lineTo(sz.w - th.right, th.top)
                .close();

            const br = Brush.fromSolid(border.right.color);
            pr.fill(path, br);
        }
        if (!fzero2(th.bottom) && !border.bottom.color.isFullyTransparent)
        {
            path.reset();
            path.moveTo(0, sz.h)
                .lineBy(sz.w, 0)
                .lineBy(-th.right, -th.bottom)
                .lineTo(th.left, sz.h - th.bottom)
                .close();

            const br = Brush.fromSolid(border.bottom.color);
            pr.fill(path, br);
        }
        if (!fzero2(th.left) && !border.left.color.isFullyTransparent)
        {
            path.reset();
            path.lineBy(0, sz.h)
                .lineBy(th.left, -th.bottom)
                .lineTo(th.left, th.top)
                .close();

            const br = Brush.fromSolid(border.left.color);
            pr.fill(path, br);
        }
        // dfmt on
    }
}

/** Standard widget overlay. It paints after any content of an element.

    It draws borders and outline.
*/
class Overlay
{
    Color focusRectColor;

    void drawTo(Painter pr, Box b)
    {
        // draw an additional frame
        drawFocusRect(pr, b);
    }

    private void drawFocusRect(Painter pr, Box b)
    {
        const c = focusRectColor;
        if (c.isFullyTransparent)
            return;

        enum FOCUS_RECT_PADDING = 2;
        RectI rc = RectI(BoxI.from(b));
        rc.shrink(FOCUS_RECT_PADDING, FOCUS_RECT_PADDING);
        drawDottedLineH(pr, rc.left, rc.right, rc.top, c);
        drawDottedLineH(pr, rc.left, rc.right, rc.bottom - 1, c);
        drawDottedLineV(pr, rc.left, rc.top + 1, rc.bottom - 1, c);
        drawDottedLineV(pr, rc.right - 1, rc.top + 1, rc.bottom - 1, c);
    }
}

package(beamui) void drawDottedLineH(Painter pr, int x0, int x1, int y, Color color)
{
    if (x0 >= x1 || color.isFullyTransparent)
        return;

    const oldAA = pr.antialias;
    pr.antialias = false;
    foreach (int x; x0 .. x1)
    {
        if ((x ^ y) & 1)
            pr.fillRect(x, y, 1, 1, color);
    }
    pr.antialias = oldAA;
}

package(beamui) void drawDottedLineV(Painter pr, int x, int y0, int y1, Color color)
{
    if (y0 >= y1 || color.isFullyTransparent)
        return;

    const oldAA = pr.antialias;
    pr.antialias = false;
    foreach (int y; y0 .. y1)
    {
        if ((y ^ x) & 1)
            pr.fillRect(x, y, 1, 1, color);
    }
    pr.antialias = oldAA;
}

private __gshared ImageCache _imageCache;
/// Image cache singleton
@property ImageCache imageCache()
{
    return _imageCache;
}
/// ditto
@property void imageCache(ImageCache cache)
{
    eliminate(_imageCache);
    _imageCache = cache;
}

/// Decoded raster images cache - access by filenames
final class ImageCache
{
    private Bitmap[string] _map;

    this()
    {
        debug Log.i("Creating ImageCache");
    }

    ~this()
    {
        debug Log.i("Destroying ImageCache");
        clear();
    }

    /// Clear cache
    void clear()
    {
        foreach (ref item; _map)
            item = Bitmap.init;
        destroy(_map);
    }

    /// Find an image by resource ID, load and cache it
    Bitmap get(string imageID)
    {
        // console images are not supported for now in any way
        static if (BACKEND_GUI)
        {
            if (auto p = imageID in _map)
                return *p;

            Bitmap bitmap;

            string filename = resourceList.getPathByID(imageID);
            auto data = loadResourceBytes(filename);
            if (data)
            {
                bitmap = loadImage(data, filename);
                if (filename.endsWith(".9.png") || filename.endsWith(".9.PNG"))
                    bitmap.detectNinePatch();
            }
            _map[imageID] = bitmap;
            return bitmap;
        }
        else
            return Bitmap.init;
    }

    /// Remove an image with resource ID `imageID` from the cache
    void remove(string imageID)
    {
        _map.remove(imageID);
    }
}
