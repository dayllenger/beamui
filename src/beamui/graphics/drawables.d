/**
Drawables and widget background.

imageCache is RAM cache of decoded images (as DrawBuf).

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
import beamui.core.types;
import beamui.core.units;
import beamui.graphics.bitmap;
import beamui.graphics.brush;
import beamui.graphics.colors;
import beamui.graphics.painter : Painter, PaintSaver;
import beamui.graphics.path;
import beamui.graphics.resources;
static if (BACKEND_GUI)
{
    import beamui.graphics.images;
}

/// Base abstract class for all drawables
class Drawable : RefCountedObject
{
    debug static __gshared int _instanceCount;
    debug @property static int instanceCount()
    {
        return _instanceCount;
    }

    this()
    {
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created drawable ", getShortClassName(this), ", count: ", _instanceCount);
    }

    ~this()
    {
        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed drawable ", getShortClassName(this), ", count: ", _instanceCount);
    }

    abstract void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0);

    abstract @property float width() const;
    abstract @property float height() const;
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

    override @property float width() const
    {
        return 0;
    }

    override @property float height() const
    {
        return 0;
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

    override @property float width() const
    {
        return 1;
    }

    override @property float height() const
    {
        return 1;
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

    override @property float width() const
    {
        return 1;
    }

    override @property float height() const
    {
        return 1;
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
    private int _offsetX;
    private int _offsetY;
    private int _blurSize;
    private Color _color;
    private ColorDrawBuf _bitmap;

    this(int offsetX, int offsetY, uint blurSize = 0, Color color = Color.black)
    {
        _offsetX = offsetX;
        _offsetY = offsetY;
        _blurSize = blurSize;
        _color = color;
        if (blurSize == 0)
            return;

        // now create a bitmap that will contain the shadow
        const size = 4 * blurSize + 1;
        _bitmap = new ColorDrawBuf(size, size);
        // draw a square in center of the bitmap
        _bitmap.fillRect(RectI(blurSize, blurSize, size - blurSize, size - blurSize), color);
        // blur the square
        blurBitmapARGB8(_bitmap, blurSize);
        _bitmap.preMultiplyAlpha();
        // set 9-patch frame
        const sz = _blurSize * 2;
        _bitmap.ninePatch = new NinePatch(InsetsI(sz), InsetsI(sz));
    }

    ~this()
    {
        eliminate(_bitmap);
    }

    override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
    {
        // move and expand the shadow
        b.x += _offsetX;
        b.y += _offsetY;
        b.expand(Insets(_blurSize));

        // now draw
        if (_blurSize > 0)
        {
            pr.drawNinePatch(_bitmap, RectI(0, 0, _bitmap.width, _bitmap.height), Rect(b), 1);
            // debug
            // pr.drawImage(_bitmap, b.x, b.y, 1);
        }
        else
        {
            pr.fillRect(b.x, b.y, b.w, b.h, _color);
        }
    }

    override @property float width() const
    {
        return 1;
    }

    override @property float height() const
    {
        return 1;
    }
}

/// Apply Gaussian blur to the bitmap. This is a slow function, but it's fine for box shadows for now
private void blurBitmapARGB8(ColorDrawBuf bitmap, uint blurSize)
    in(bitmap.format == PixelFormat.argb8)
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
    abstract class ConsoleDrawBuf : DrawBuf
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

        override @property float width() const
        {
            return _width;
        }

        override @property float height() const
        {
            return _height;
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

        private static int wrapNinePatch(int v, int width, int ninewidth, int left, int right)
        {
            if (v < left)
                return v;
            if (v >= width - right)
                return v - (width - right) + (ninewidth - right);
            return left + (ninewidth - left - right) * (v - left) / (width - left - right);
        }

        private void drawTo(DrawBuf drawbuf, Box b, float tilex0 = 0, float tiley0 = 0)
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
    private DrawBufRef _image;
    private bool _tiled;

    debug static __gshared int _instanceCount;
    debug @property static int instanceCount()
    {
        return _instanceCount;
    }

    this(DrawBufRef image, bool tiled = false)
    {
        _image = image;
        _tiled = tiled;
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created ImageDrawable, count: ", _instanceCount);
    }

    ~this()
    {
        _image.clear();
        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed ImageDrawable, count: ", _instanceCount);
    }

    override @property float width() const
    {
        if (_image.isNull)
            return 0;
        if (_image.hasNinePatch)
            return _image.width - 2;
        return _image.width;
    }

    override @property float height() const
    {
        if (_image.isNull)
            return 0;
        if (_image.hasNinePatch)
            return _image.height - 2;
        return _image.height;
    }

    override @property Insets padding() const
    {
        if (!_image.isNull && _image.hasNinePatch)
            return Insets.from(_image.ninePatch.padding);
        else
            return Insets(0);
    }

    override void drawTo(Painter pr, Box b, float tilex0 = 0, float tiley0 = 0)
    {
        if (_image.isNull)
            return;

        ColorDrawBuf img = cast(ColorDrawBuf)_image;
        if (!img)
            return;
        assert(img.width > 0 && img.height > 0);

        if (img.hasNinePatch)
        {
            pr.drawNinePatch(img, RectI(1, 1, img.width - 1, img.height - 1), Rect(b), 1);
        }
        else if (_tiled)
        {
            static Path path;
            path.reset();
            path.lineBy(b.w, 0).lineBy(0, b.h).lineBy(-b.w, 0).close();
            const brush = Brush.fromPattern(img, Mat2x3.translation(Vec2(tilex0, tiley0)));
            pr.translate(b.x, b.y);
            pr.fill(path, brush);
            pr.translate(-b.x, -b.y);
        }
        else
        {
            PaintSaver sv;
            pr.save(sv);
            pr.translate(b.x, b.y);
            pr.scale(b.w / cast(float)img.width, b.h / cast(float)img.height);
            pr.drawImage(img, 0, 0, 1);
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

        override @property float width() const
        {
            return 20; // dummy size
        }

        override @property float height() const
        {
            return 20; // dummy size
        }
    }
}

struct BgPosition
{
    LayoutLength x = LayoutLength.percent(0);
    LayoutLength y = LayoutLength.percent(0);
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
}

/// Tiling options for one image axis
enum Tiling
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

enum BorderStyle
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
    float[2] topLeft = 0;
    float[2] topRight = 0;
    float[2] bottomLeft = 0;
    float[2] bottomRight = 0;
}

/// Standard widget background. It can combine together background color,
/// image (raster, gradient, etc.), borders and box shadows.
class Background
{
    Color color = Color.transparent;
    Drawable image;
    Border border;
    BorderRadii radii;
    BoxShadowDrawable shadow;

    @property float width() const
    {
        const th = border.left.thickness + border.right.thickness;
        return image ? image.width + th : th;
    }

    @property float height() const
    {
        const th = border.top.thickness + border.bottom.thickness;
        return image ? image.height + th : th;
    }

    @property Insets padding() const
    {
        const bs = border.getSize;
        return image ? image.padding + bs : bs;
    }

    void drawTo(Painter pr, Box b)
    {
        // shadow
        shadow.maybe.drawTo(pr, b);
        // make background image smaller to fit borders
        const bs = border.getSize();
        Box back = b;
        back.shrink(bs);
        // color
        pr.fillRect(back.x, back.y, back.w, back.h, color);
        // image
        image.maybe.drawTo(pr, back);
        // border
        pr.translate(b.x, b.y);
        drawBorder(pr, b.size);
        pr.translate(-b.x, -b.y);
    }

    private void drawBorder(Painter pr, Size sz)
    {
        Insets th;
        if (border.top.style != BorderStyle.none)
            th.top = border.top.thickness;
        if (border.right.style != BorderStyle.none)
            th.right = border.right.thickness;
        if (border.bottom.style != BorderStyle.none)
            th.bottom = border.bottom.thickness;
        if (border.left.style != BorderStyle.none)
            th.left = border.left.thickness;

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
    private DrawBufRef[string] _map;

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
            item.clear();
        destroy(_map);
    }

    /// Find an image by resource ID, load and cache it
    DrawBufRef get(string imageID)
    {
        // console images are not supported for now in any way
        static if (BACKEND_GUI)
        {
            if (auto p = imageID in _map)
                return *p;

            DrawBuf bitmap;

            string filename = resourceList.getPathByID(imageID);
            auto data = loadResourceBytes(filename);
            if (data)
            {
                bitmap = loadImage(data, filename);
                if (filename.endsWith(".9.png") || filename.endsWith(".9.PNG"))
                    bitmap.detectNinePatch();
            }
            _map[imageID] = bitmap;
            return DrawBufRef(bitmap);
        }
        else
            return DrawBufRef.init;
    }

    /// Remove an image with resource ID `imageID` from the cache
    void remove(string imageID)
    {
        _map.remove(imageID);
    }
}
