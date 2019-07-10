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
import beamui.core.logger;
import beamui.core.types;
import beamui.core.units;
import beamui.graphics.colors;
import beamui.graphics.drawbuf;
static if (BACKEND_GUI)
{
    import beamui.graphics.images;
}
import beamui.graphics.resources;

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

    abstract void drawTo(DrawBuf buf, Box b, int tilex0 = 0, int tiley0 = 0);
    abstract @property int width() const;
    abstract @property int height() const;
    @property Insets padding() const
    {
        return Insets(0);
    }
}

alias DrawableRef = Ref!Drawable;

class EmptyDrawable : Drawable
{
    override void drawTo(DrawBuf buf, Box b, int tilex0 = 0, int tiley0 = 0)
    {
    }

    override @property int width() const
    {
        return 0;
    }

    override @property int height() const
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

    override void drawTo(DrawBuf buf, Box b, int tilex0 = 0, int tiley0 = 0)
    {
        if (!_color.isFullyTransparent)
            buf.fillRect(Rect(b), _color);
    }

    override @property int width() const
    {
        return 1;
    }

    override @property int height() const
    {
        return 1;
    }
}

class GradientDrawable : Drawable
{
    private Color _color1; // top left
    private Color _color2; // bottom left
    private Color _color3; // top right
    private Color _color4; // bottom right

    this(float angle, Color color1, Color color2)
    {
        // rotate a gradient; angle goes clockwise
        import std.math;

        float c = cos(angle);
        float s = sin(angle);
        if (s >= 0)
        {
            if (c >= 0)
            {
                // 0-90 degrees
                _color1 = Color.blend(color1, color2, cast(uint)(255 * c));
                _color2 = color2;
                _color3 = color1;
                _color4 = Color.blend(color1, color2, cast(uint)(255 * s));
            }
            else
            {
                // 90-180 degrees
                _color1 = color2;
                _color2 = Color.blend(color1, color2, cast(uint)(255 * -c));
                _color3 = Color.blend(color1, color2, cast(uint)(255 * s));
                _color4 = color1;
            }
        }
        else
        {
            if (c < 0)
            {
                // 180-270 degrees
                _color1 = Color.blend(color1, color2, cast(uint)(255 * -s));
                _color2 = color1;
                _color3 = color2;
                _color4 = Color.blend(color1, color2, cast(uint)(255 * -c));
            }
            else
            {
                // 270-360 degrees
                _color1 = color1;
                _color2 = Color.blend(color1, color2, cast(uint)(255 * -s));
                _color3 = Color.blend(color1, color2, cast(uint)(255 * c));
                _color4 = color2;
            }
        }
    }

    override void drawTo(DrawBuf buf, Box b, int tilex0 = 0, int tiley0 = 0)
    {
        buf.fillGradientRect(Rect(b), _color1, _color2, _color3, _color4);
    }

    override @property int width() const
    {
        return 1;
    }

    override @property int height() const
    {
        return 1;
    }
}

/// Box shadows drawable, can be blurred
class BoxShadowDrawable : Drawable
{
    private int _offsetX;
    private int _offsetY;
    private int _blurSize;
    private Color _color;
    private ColorDrawBuf texture;

    this(int offsetX, int offsetY, uint blurSize = 0, Color color = Color(0x0))
    {
        _offsetX = offsetX;
        _offsetY = offsetY;
        _blurSize = blurSize;
        _color = color;
        // now create a texture which will contain the shadow
        uint size = 4 * blurSize + 1;
        texture = new ColorDrawBuf(size, size); // TODO: get from/put to cache
        // clear
        Color cc = color;
        cc.a = 0xFF;
        texture.fill(cc);
        // draw a square in center of the texture
        texture.fillRect(Rect(blurSize, blurSize, size - blurSize, size - blurSize), color);
        // blur the square
        texture.blur(blurSize);
        // set 9-patch frame
        uint sz = _blurSize * 2;
        texture.ninePatch = new NinePatch(InsetsI(sz), InsetsI(sz));
    }

    ~this()
    {
        eliminate(texture);
    }

    override void drawTo(DrawBuf buf, Box b, int tilex0 = 0, int tiley0 = 0)
    {
        // move and expand the shadow
        b.x += _offsetX;
        b.y += _offsetY;
        b.expand(Insets(_blurSize));

        // apply new clipping to the DrawBuf to draw outside of the widget
        auto saver = ClipRectSaver(buf, Rect(b), 0, false);

        // now draw
        if (_blurSize > 0)
        {
            buf.drawNinePatch(Rect(b), texture, Rect(0, 0, texture.width, texture.height));
            // debug
            // buf.drawFragment(b.x, b.y, texture, Rect(0, 0, texture.width, texture.height));
        }
        else
        {
            buf.fillRect(Rect(b), _color);
        }
    }

    override @property int width() const
    {
        return 1;
    }

    override @property int height() const
    {
        return 1;
    }
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
                    _textColors ~= _textColors.length ? _textColors[$ - 1] : Color(0x0);
                if (_bgColors.length < k)
                    _bgColors ~= _bgColors.length ? _bgColors[$ - 1] : Color.transparent;
            }
        }

        override @property int width() const
        {
            return _width;
        }

        override @property int height() const
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

        override void drawTo(DrawBuf drawbuf, Box b, int tilex0 = 0, int tiley0 = 0)
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

    override @property int width() const
    {
        if (_image.isNull)
            return 0;
        if (_image.hasNinePatch)
            return _image.width - 2;
        return _image.width;
    }

    override @property int height() const
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

    override void drawTo(DrawBuf buf, Box b, int tilex0 = 0, int tiley0 = 0)
    {
        if (_image.isNull)
            return;
        if (_image.hasNinePatch)
        {
            // draw nine patch
            buf.drawNinePatch(Rect(b), _image.get, Rect(1, 1, width + 1, height + 1));
        }
        else if (_tiled)
        {
            buf.drawTiledImage(Rect(b), _image.get, tilex0, tiley0);
        }
        else
        {
            // rescaled or normal
            if (b.width != _image.width || b.height != _image.height)
                buf.drawRescaled(Rect(b), _image.get, Rect(0, 0, _image.width, _image.height));
            else
                buf.drawImage(b.x, b.y, _image);
        }
    }
}

static if (USE_OPENGL)
{
    /// Custom OpenGL drawing inside a drawable
    class OpenGLDrawable : Drawable
    {
        OpenGLDrawableDelegate drawHandler;

        this(OpenGLDrawableDelegate drawHandler = null)
        {
            this.drawHandler = drawHandler;
        }

        void onDraw(Rect windowRect, Rect rc)
        {
            // either override this method or assign draw handler
            if (drawHandler)
                drawHandler(windowRect, rc);
        }

        override void drawTo(DrawBuf buf, Box b, int tilex0 = 0, int tiley0 = 0)
        {
            buf.drawCustomOpenGLScene(Rect(b), &onDraw);
        }

        override @property int width() const
        {
            return 20; // dummy size
        }

        override @property int height() const
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
    int thickness; /// Thickness in pixels
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

/// 8 border radii in pixels
struct BorderRadii
{
    int[2] topLeft;
    int[2] topRight;
    int[2] bottomLeft;
    int[2] bottomRight;
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

    @property int width() const
    {
        const th = border.left.thickness + border.right.thickness;
        return image ? image.width + th : th;
    }

    @property int height() const
    {
        const th = border.top.thickness + border.bottom.thickness;
        return image ? image.height + th : th;
    }

    @property Insets padding() const
    {
        const bs = border.getSize;
        return image ? image.padding + bs : bs;
    }

    void drawTo(DrawBuf buf, Box b)
    {
        // shadow
        shadow.maybe.drawTo(buf, b);
        // make background image smaller to fit borders
        const bs = border.getSize;
        Box back = b;
        back.shrink(bs);
        // color
        if (!color.isFullyTransparent)
            buf.fillRect(Rect(back), color);
        // image
        image.maybe.drawTo(buf, back);
        // border
        if (border.left.style != BorderStyle.none)
            buf.drawFrame(Rect(b), border.left.color, bs);
    }
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

            DrawBuf drawbuf;

            string filename = resourceList.getPathByID(imageID);
            auto data = loadResourceBytes(filename);
            if (data)
            {
                drawbuf = loadImage(data, filename);
                if (filename.endsWith(".9.png") || filename.endsWith(".9.PNG"))
                    drawbuf.detectNinePatch();
            }
            _map[imageID] = drawbuf;
            return DrawBufRef(drawbuf);
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
