/**
This module contains drawables implementation.

imageCache is RAM cache of decoded images (as DrawBuf).

drawableCache is cache of various Drawables.

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
            Log.d("Created drawable ", this.classinfo.name, ", count: ", _instanceCount);
    }

    ~this()
    {
        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed drawable ", this.classinfo.name, ", count: ", _instanceCount);
    }

    abstract void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0);
    abstract @property int width();
    abstract @property int height();
    @property RectOffset padding()
    {
        return RectOffset(0);
    }
}

alias DrawableRef = Ref!Drawable;

class EmptyDrawable : Drawable
{
    override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
    {
    }

    override @property int width()
    {
        return 0;
    }

    override @property int height()
    {
        return 0;
    }
}

class SolidFillDrawable : Drawable
{
    protected uint _color;

    this(uint color)
    {
        _color = color;
    }

    override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
    {
        if (!_color.isFullyTransparentColor)
            buf.fillRect(Rect(b), _color);
    }

    override @property int width()
    {
        return 1;
    }

    override @property int height()
    {
        return 1;
    }
}

class GradientDrawable : Drawable
{
    protected uint _color1; // top left
    protected uint _color2; // bottom left
    protected uint _color3; // top right
    protected uint _color4; // bottom right

    this(float angle, uint color1, uint color2)
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
                _color1 = blendARGB(color1, color2, cast(uint)(255 * c));
                _color2 = color2;
                _color3 = color1;
                _color4 = blendARGB(color1, color2, cast(uint)(255 * s));
            }
            else
            {
                // 90-180 degrees
                _color1 = color2;
                _color2 = blendARGB(color1, color2, cast(uint)(255 * -c));
                _color3 = blendARGB(color1, color2, cast(uint)(255 * s));
                _color4 = color1;
            }
        }
        else
        {
            if (c < 0)
            {
                // 180-270 degrees
                _color1 = blendARGB(color1, color2, cast(uint)(255 * -s));
                _color2 = color1;
                _color3 = color2;
                _color4 = blendARGB(color1, color2, cast(uint)(255 * -c));
            }
            else
            {
                // 270-360 degrees
                _color1 = color1;
                _color2 = blendARGB(color1, color2, cast(uint)(255 * -s));
                _color3 = blendARGB(color1, color2, cast(uint)(255 * c));
                _color4 = color2;
            }
        }
    }

    override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
    {
        buf.fillGradientRect(Rect(b), _color1, _color2, _color3, _color4);
    }

    override @property int width()
    {
        return 1;
    }

    override @property int height()
    {
        return 1;
    }
}

/// Solid borders (may have different width) and, optionally, solid inner area
class BorderDrawable : Drawable
{
    protected uint _borderColor;
    protected RectOffset _borderWidths; // border widths, in pixels
    protected uint _middleColor; // middle area color (may be transparent)

    this(uint borderColor, RectOffset borderWidths, uint innerAreaColor = 0xFFFFFFFF)
    {
        _borderColor = borderColor;
        _borderWidths = borderWidths;
        _middleColor = innerAreaColor;
    }

    this(uint borderColor, int borderWidth, uint innerAreaColor = 0xFFFFFFFF)
    {
        _borderColor = borderColor;
        _borderWidths = RectOffset(borderWidth, borderWidth, borderWidth, borderWidth);
        _middleColor = innerAreaColor;
    }

    override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
    {
        buf.drawFrame(Rect(b), _borderColor, _borderWidths, _middleColor);
    }

    override @property int width()
    {
        return 1 + _borderWidths.left + _borderWidths.right;
    }

    override @property int height()
    {
        return 1 + _borderWidths.top + _borderWidths.bottom;
    }

    override @property RectOffset padding()
    {
        return _borderWidths;
    }
}

/// Box shadows drawable, can be blurred
class BoxShadowDrawable : Drawable
{
    protected int _offsetX;
    protected int _offsetY;
    protected int _blurSize;
    protected uint _color;
    protected Ref!ColorDrawBuf texture;

    this(int offsetX, int offsetY, uint blurSize = 0, uint color = 0x0)
    {
        _offsetX = offsetX;
        _offsetY = offsetY;
        _blurSize = blurSize;
        _color = color;
        // now create a texture which will contain the shadow
        uint size = 4 * blurSize + 1;
        texture = new ColorDrawBuf(size, size); // TODO: get from/put to cache
        // clear
        texture.fill(color | 0xFF000000);
        // draw a square in center of the texture
        texture.fillRect(Rect(blurSize, blurSize, size - blurSize, size - blurSize), color);
        // blur the square
        texture.blur(blurSize);
        // set 9-patch frame
        uint sz = _blurSize * 2;
        texture.ninePatch = new NinePatch(RectOffset(sz), RectOffset(sz));
    }

    ~this()
    {
        texture.clear();
    }

    override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
    {
        // move and expand the shadow
        b.x += _offsetX;
        b.y += _offsetY;
        b.expand(RectOffset(_blurSize));

        // apply new clipping to the DrawBuf to draw outside of the widget
        auto saver = ClipRectSaver(buf, Rect(b), 0, false);

        // now draw
        if (_blurSize > 0)
        {
            buf.drawNinePatch(Rect(b), texture.get, Rect(0, 0, texture.width, texture.height));
            // debug
            // buf.drawFragment(b.x, b.y, texture.get, Rect(0, 0, texture.width, texture.height));
        }
        else
        {
            buf.fillRect(Rect(b), _color);
        }
    }

    override @property int width()
    {
        return 1;
    }

    override @property int height()
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
        abstract void drawChar(int x, int y, dchar ch, uint color, uint bgcolor);
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
            uint[] _bgColors;
            uint[] _textColors;
            RectOffset _padding;
            Rect _ninePatch;
            bool _tiled;
            bool _stretched;
            bool _hasNinePatch;
        }

        this(int dx, int dy, dstring text, uint textColor, uint bgColor)
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
                        _bgColors ~= tokens[i].intvalue;
                        break;
                    case Mode.TextColor:
                    case Mode.Text:
                        _textColors ~= tokens[i].intvalue;
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
            _padding = RectOffset(pad[0], pad[1], pad[2], pad[3]);
            _ninePatch = Rect(nine[0], nine[1], nine[2], nine[3]);
            // pad colors
            for (int k = 1; k <= _width * _height; k++)
            {
                if (_textColors.length < k)
                    _textColors ~= _textColors.length ? _textColors[$ - 1] : 0;
                if (_bgColors.length < k)
                    _bgColors ~= _bgColors.length ? _bgColors[$ - 1] : 0xFFFFFFFF;
            }
        }

        override @property int width()
        {
            return _width;
        }

        override @property int height()
        {
            return _height;
        }

        override @property RectOffset padding()
        {
            return _padding;
        }

        protected void drawChar(ConsoleDrawBuf buf, int srcx, int srcy, int dstx, int dsty)
        {
            if (srcx < 0 || srcx >= _width || srcy < 0 || srcy >= _height)
                return;
            int index = srcy * _width + srcx;
            if (_textColors[index].isFullyTransparentColor && _bgColors[index].isFullyTransparentColor)
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

        override void drawTo(DrawBuf drawbuf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
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
    protected DrawBufRef _image;
    protected bool _tiled;

    debug static __gshared int _instanceCount;
    debug @property static int instanceCount()
    {
        return _instanceCount;
    }

    this(ref DrawBufRef image, bool tiled = false)
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

    override @property int width()
    {
        if (_image.isNull)
            return 0;
        if (_image.hasNinePatch)
            return _image.width - 2;
        return _image.width;
    }

    override @property int height()
    {
        if (_image.isNull)
            return 0;
        if (_image.hasNinePatch)
            return _image.height - 2;
        return _image.height;
    }

    override @property RectOffset padding()
    {
        if (!_image.isNull && _image.hasNinePatch)
            return _image.ninePatch.padding;
        else
            return RectOffset(0);
    }

    override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
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
        private OpenGLDrawableDelegate _drawHandler;

        @property OpenGLDrawableDelegate drawHandler()
        {
            return _drawHandler;
        }

        @property OpenGLDrawable drawHandler(OpenGLDrawableDelegate handler)
        {
            _drawHandler = handler;
            return this;
        }

        this(OpenGLDrawableDelegate drawHandler = null)
        {
            _drawHandler = drawHandler;
        }

        void onDraw(Rect windowRect, Rect rc)
        {
            // either override this method or assign draw handler
            if (_drawHandler)
            {
                _drawHandler(windowRect, rc);
            }
        }

        override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
        {
            buf.drawCustomOpenGLScene(Rect(b), &onDraw);
        }

        override @property int width()
        {
            return 20; // dummy size
        }

        override @property int height()
        {
            return 20; // dummy size
        }
    }
}

/// Drawable which allows to combine together background image, gradient, borders, box shadows, etc.
class CombinedDrawable : Drawable
{
    DrawableRef boxShadow;
    DrawableRef backgroundColor;
    DrawableRef backgroundImage;
    DrawableRef border;

    this(uint backgroundColor, Drawable backgroundImage, BorderDrawable border, BoxShadowDrawable boxShadow)
    {
        this.boxShadow = boxShadow ? boxShadow : new EmptyDrawable;
        this.backgroundColor = !backgroundColor.isFullyTransparentColor ?
            new SolidFillDrawable(backgroundColor) : new EmptyDrawable;
        this.backgroundImage = backgroundImage ? backgroundImage : new EmptyDrawable;
        this.border = border ? border : new EmptyDrawable;
    }

    ~this()
    {
        boxShadow.clear();
        backgroundColor.clear();
        backgroundImage.clear();
        border.clear();
    }

    override void drawTo(DrawBuf buf, Box b, uint state = 0, int tilex0 = 0, int tiley0 = 0)
    {
        boxShadow.drawTo(buf, b, state, tilex0, tiley0);
        // make background image smaller to fit borders
        Box back = b;
        back.shrink(border.padding);
        backgroundColor.drawTo(buf, back, state, tilex0, tiley0);
        backgroundImage.drawTo(buf, back, state, tilex0, tiley0);
        border.drawTo(buf, b, state, tilex0, tiley0);
    }

    override @property int width()
    {
        return backgroundImage.width + border.padding.left + border.padding.right;
    }

    override @property int height()
    {
        return backgroundImage.height + border.padding.top + border.padding.bottom;
    }

    override @property RectOffset padding()
    {
        return backgroundImage.padding + border.padding;
    }
}

__gshared DrawableCache _drawableCache;
/// Drawable cache singleton
@property DrawableCache drawableCache()
{
    return _drawableCache;
}
/// Drawable cache singleton
@property void drawableCache(DrawableCache cache)
{
    eliminate(_drawableCache);
    _drawableCache = cache;
}

final class DrawableCache
{
    private DrawableRef[string] _map;
    private DrawableRef _nullDrawable;

    this()
    {
        debug Log.i("Creating DrawableCache");
    }

    ~this()
    {
        debug (resalloc)
            Log.e("Drawable instance count before destroying of DrawableCache: ", Drawable.instanceCount);

        Log.i("Destroying DrawableCache");
        clear();

        debug if (Drawable.instanceCount)
            Log.e("Drawable instance count after destroying of DrawableCache: ", Drawable.instanceCount);
    }

    /// Clear cache
    void clear()
    {
        foreach (k, item; _map)
            item.clear();
        destroy(_map);
    }

    /// Returns drawable (loads from file if necessary)
    DrawableRef get(string id)
    {
        if (!id)
            return _nullDrawable;
        id = id.strip;
        if (id == "@null" || id == "none")
            return _nullDrawable;
        if (id in _map)
            return _map[id];
        // not found - create it
        auto dr = makeDrawableFromID(id);
        _map[id] = dr;
        return DrawableRef(dr);
    }
}

/// This function takes an id and creates a drawable
/// ID may be a name of resource, #directive, color or json
private Drawable makeDrawableFromID(string id)
{
    bool tiled;
    if (id.endsWith(".tiled"))
    {
        id = id[0 .. $ - 6]; // remove .tiled
        tiled = true;
    }
    string filename = resourceList.getPathByID(id);
    if (filename)
        id = filename;

    if (id.endsWith(".xml") || id.endsWith(".XML"))
    {
        Log.d("XML drawables are not supported anymore: ", id);
    }
    else if (id.endsWith(".tim") || id.endsWith(".TIM"))
    {
        static if (BACKEND_CONSOLE)
        {
            try
            {
                // .tim (text image) drawables support
                string s = cast(string)loadResourceBytes(id);
                if (s.length)
                {
                    auto d = new TextDrawable(s);
                    if (d.width && d.height)
                    {
                        return d;
                    }
                }
            }
            catch (Exception e)
            {
                // cannot find drawable file
            }
        }
    }
    else if (id.startsWith("#"))
    {
        Log.d("Color drawable: ", id);
    }
    else if (id.startsWith("{"))
    {
        // json in {} with text drawable description
        static if (BACKEND_CONSOLE)
        {
            return createTextDrawable(id);
        }
    }
    else
    {
        static if (BACKEND_GUI)
        {
            // PNG/JPEG drawables support
            DrawBufRef image = imageCache.get(id);
            if (!image.isNull)
                return new ImageDrawable(image, tiled);
            else
                Log.e("Failed to load image from ", id);
        }
    }
    return null;
}


static if (BACKEND_GUI):

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
        foreach (item; _map)
            item.clear();
        destroy(_map);
    }

    /// Find an image by resource ID, load and cache it
    DrawBufRef get(string imageID)
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

    /// Remove an image with resource ID `imageID` from the cache
    void remove(string imageID)
    {
        _map.remove(imageID);
    }
}
