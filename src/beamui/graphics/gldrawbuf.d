/**
This module contains OpenGL based drawing buffer implementation.

OpenGL support is enabled by default, build with version = NO_OPENGL to disable it.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.gldrawbuf;

import beamui.core.config;

static if (USE_OPENGL):
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.math3d;
import beamui.graphics.colors;
import beamui.graphics.drawbuf;
import beamui.graphics.glsupport;
import beamui.graphics.gl.objects : Tex2D;

/// Drawing buffer - image container which allows to perform some drawing operations
class GLDrawBuf : DrawBuf
{
    private int _w;
    private int _h;

    this(int dx, int dy)
    {
        resize(dx, dy);
    }

    override @property int width() const
    {
        return _w;
    }
    override @property int height() const
    {
        return _h;
    }

    override void beforeDrawing()
    {
        alpha = 0;
        glSupport.setOrthoProjection(Rect(0, 0, _w, _h), Rect(0, 0, _w, _h));
        glSupport.beforeRenderGUI();
    }

    override void afterDrawing()
    {
        glSupport.queue.flush();
        glSupport.flushGL();
    }

    override void resize(int width, int height)
    {
        _w = width;
        _h = height;
        resetClipping();
    }

    override void drawCustomOpenGLScene(Rect rc, OpenGLDrawableDelegate handler)
    {
        if (handler)
        {
            Rect windowRect = Rect(0, 0, width, height);
            glSupport.queue.flush();
            glSupport.setOrthoProjection(windowRect, rc);
            glSupport.clearDepthBuffer();
            handler(windowRect, rc);
            glSupport.setOrthoProjection(windowRect, windowRect);
        }
    }

    override void fill(Color color)
    {
        if (hasClipping)
        {
            fillRect(clipRect, color);
            return;
        }
        applyAlpha(color);
        glSupport.queue.addSolidRect(RectF(0, 0, _w, _h), color);
    }

    override void fillRect(Rect rc, Color color)
    {
        applyAlpha(color);
        if (!color.isFullyTransparent && applyClipping(rc))
            glSupport.queue.addSolidRect(RectF(rc.left, rc.top, rc.right, rc.bottom), color);
    }

    override void fillGradientRect(Rect rc, Color color1, Color color2, Color color3, Color color4)
    {
        applyAlpha(color1);
        applyAlpha(color2);
        applyAlpha(color3);
        applyAlpha(color4);
        if (!(color1.isFullyTransparent && color3.isFullyTransparent) && applyClipping(rc))
            glSupport.queue.addGradientRect(RectF(rc.left, rc.top, rc.right, rc.bottom),
                color1, color2, color3, color4);
    }

    override void drawPixel(int x, int y, Color color)
    {
        if (!clipRect.isPointInside(x, y))
            return;
        applyAlpha(color);
        if (!color.isFullyTransparent)
            glSupport.queue.addSolidRect(RectF(x, y, x + 1, y + 1), color);
    }

    override void drawGlyph(int x, int y, GlyphRef glyph, Color color)
    {
        Rect dstrect = Rect(x, y, x + glyph.correctedBlackBoxX, y + glyph.blackBoxY);
        Rect srcrect = Rect(0, 0, glyph.correctedBlackBoxX, glyph.blackBoxY);
        applyAlpha(color);
        if (!color.isFullyTransparent && applyClipping(dstrect, srcrect))
        {
            if (!glGlyphCache.isInCache(glyph.id))
                glGlyphCache.put(glyph);
            glGlyphCache.drawItem(glyph.id, dstrect, srcrect, color);
        }
    }

    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect)
    {
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        if (applyClipping(dstrect, srcrect))
        {
            if (!glImageCache.isInCache(src.id))
                glImageCache.put(src);
            Color color = Color(0xFFFFFF);
            applyAlpha(color);
            glImageCache.drawItem(src.id, dstrect, srcrect, color);
        }
    }

    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect)
    {
        if (applyClipping(dstrect, srcrect))
        {
            if (!glImageCache.isInCache(src.id))
                glImageCache.put(src);
            Color color = Color(0xFFFFFF);
            applyAlpha(color);
            glImageCache.drawItem(src.id, dstrect, srcrect, color);
        }
    }

    override void drawLine(Point p1, Point p2, Color color)
    {
        if (!clipLine(clipRect, p1, p2))
            return;
        applyAlpha(color);
        if (!color.isFullyTransparent)
            glSupport.queue.addLine(PointF(p1.x, p1.y), PointF(p2.x, p2.y), color, color);
    }

    override protected void fillTriangleFClipped(PointF p1, PointF p2, PointF p3, Color color)
    {
        glSupport.queue.addTriangle(p1, p2, p3, color, color, color);
    }
}

enum MIN_TEX_SIZE = 64;
enum MAX_TEX_SIZE = 4096;
private int nearestPOT(int n)
{
    for (int i = MIN_TEX_SIZE; i <= MAX_TEX_SIZE; i *= 2)
    {
        if (n <= i)
            return i;
    }
    return MIN_TEX_SIZE;
}

private int correctTextureSize(int n)
{
    if (n < 16)
        return 16;
    version (POT_TEXTURE_SIZES)
    {
        return nearestPOT(n);
    }
    else
    {
        return n;
    }
}

/// Object deletion listener callback function type
void onObjectDestroyedCallback(uint pobject)
{
    glImageCache.onCachedObjectDeleted(pobject);
}

/// Object deletion listener callback function type
void onGlyphDestroyedCallback(uint pobject)
{
    glGlyphCache.onCachedObjectDeleted(pobject);
}

private __gshared GLImageCache glImageCache;
private __gshared GLGlyphCache glGlyphCache;

void initGLCaches()
{
    if (!glImageCache)
        glImageCache = new GLImageCache;
    if (!glGlyphCache)
        glGlyphCache = new GLGlyphCache;
}

void destroyGLCaches()
{
    eliminate(glImageCache);
    eliminate(glGlyphCache);
}

private abstract class GLCache
{
    static final class GLCacheItem
    {
        @property GLCachePage page() { return _page; }

        uint _objectID;
        // image size
        Rect _rc;
        bool _deleted;

        this(GLCachePage page, uint objectID)
        {
            _page = page;
            _objectID = objectID;
        }

        private GLCachePage _page;
    }

    static abstract class GLCachePage
    {
        private
        {
            GLCache _cache;
            int _tdx;
            int _tdy;
            ColorDrawBuf _drawbuf;
            int _currentLine;
            int _nextLine;
            int _x;
            bool _closed;
            bool _needUpdateTexture;
            Tex2D _texture;
            int _itemCount;
        }

        this(GLCache cache, int dx, int dy)
        {
            _cache = cache;
            _tdx = correctTextureSize(dx);
            _tdy = correctTextureSize(dy);
            _itemCount = 0;
        }

        ~this()
        {
            eliminate(_drawbuf);
            eliminate(_texture);
        }

        final void updateTexture()
        {
            if (_drawbuf is null)
                return; // no draw buffer!!!
            if (_texture is null || _texture.id == 0)
            {
                _texture = new Tex2D;
                Log.d("updateTexture - new texture id=", _texture.id);
                if (!_texture.id)
                    return;
            }
            uint* pixels = _drawbuf.scanLine(0);
            if (!glSupport.setTextureImage(_texture, _drawbuf.width, _drawbuf.height, cast(ubyte*)pixels))
            {
                eliminate(_texture);
                return;
            }
            _needUpdateTexture = false;
            if (_closed)
            {
                eliminate(_drawbuf);
            }
        }

        final GLCacheItem reserveSpace(uint objectID, int width, int height)
        {
            auto cacheItem = new GLCacheItem(this, objectID);
            if (_closed)
                return null;

            int spacer = (width == _tdx || height == _tdy) ? 0 : 1;

            // next line if necessary
            if (_x + width + spacer * 2 > _tdx)
            {
                // move to next line
                _currentLine = _nextLine;
                _x = 0;
            }
            // check if no room left for glyph height
            if (_currentLine + height + spacer * 2 > _tdy)
            {
                _closed = true;
                return null;
            }
            cacheItem._rc = Rect(_x + spacer, _currentLine + spacer, _x + width + spacer, _currentLine + height + spacer);
            if (height && width)
            {
                if (_nextLine < _currentLine + height + 2 * spacer)
                    _nextLine = _currentLine + height + 2 * spacer;
                if (!_drawbuf)
                {
                    _drawbuf = new ColorDrawBuf(_tdx, _tdy);
                    _drawbuf.fill(Color(0xFF000000));
                }
                _x += width + spacer;
                _needUpdateTexture = true;
            }
            _itemCount++;
            return cacheItem;
        }

        final int deleteItem(GLCacheItem item)
        {
            _itemCount--;
            return _itemCount;
        }

        final void close()
        {
            _closed = true;
            if (_needUpdateTexture)
                updateTexture();
        }

        final void drawItem(GLCacheItem item, Rect dstrc, Rect srcrc, Color color, bool smooth)
        {
            if (_needUpdateTexture)
                updateTexture();
            if (_texture && _texture.id != 0)
            {
                // convert coordinates to cached texture
                srcrc.offset(item._rc.left, item._rc.top);
                if (!dstrc.empty)
                    glSupport.queue.addTexturedRect(_texture, _tdx, _tdy, color, color, color, color,
                            srcrc, dstrc, smooth);
            }
        }
    }

    GLCacheItem[uint] _map;
    GLCachePage[] _pages;
    GLCachePage _activePage;
    int tdx;
    int tdy;

    final void removePage(GLCachePage page)
    {
        if (_activePage is page)
            _activePage = null;
        foreach (i; 0 .. _pages.length)
            if (_pages[i] is page)
            {
                _pages = _pages.remove(i);
                break;
            }
        destroy(page);
    }

    final void updateTextureSize()
    {
        if (!tdx)
        {
            // TODO
            tdx = tdy = 1024; //getMaxTextureSize();
            if (tdx > 1024)
                tdx = tdy = 1024;
        }
    }

    ~this()
    {
        clear();
    }

    /// Check if item is in cache
    final bool isInCache(uint obj)
    {
        return (obj in _map) !is null;
    }
    /// Clears cache
    final void clear()
    {
        eliminate(_pages);
        eliminate(_map);
    }
    /// Handle cached object deletion, mark as deleted
    final void onCachedObjectDeleted(uint objectID)
    {
        if (auto p = objectID in _map)
        {
            GLCacheItem item = *p;
            int itemsLeft = item.page.deleteItem(item);
            if (itemsLeft <= 0)
            {
                removePage(item.page);
            }
            _map.remove(objectID);
            destroy(item);
        }
    }
    /// Remove deleted items - remove page if contains only deleted items
    final void removeDeletedItems()
    {
        uint[] list;
        foreach (GLCacheItem item; _map)
        {
            if (item._deleted)
                list ~= item._objectID;
        }
        foreach (id; list)
        {
            onCachedObjectDeleted(id);
        }
    }
}

/// OpenGL texture cache for ColorDrawBuf objects
private class GLImageCache : GLCache
{
    static class GLImageCachePage : GLCachePage
    {
        this(GLImageCache cache, int dx, int dy)
        {
            super(cache, dx, dy);
            Log.v("created image cache page ", dx, "x", dy);
        }

        void convertPixelFormat(GLCacheItem item)
        {
            Rect rc = item._rc;
            if (rc.top > 0)
                rc.top--;
            if (rc.left > 0)
                rc.left--;
            if (rc.right < _tdx)
                rc.right++;
            if (rc.bottom < _tdy)
                rc.bottom++;
            for (int y = rc.top; y < rc.bottom; y++)
            {
                uint* row = _drawbuf.scanLine(y);
                for (int x = rc.left; x < rc.right; x++)
                {
                    uint cl = row[x];
                    // invert A
                    cl ^= 0xFF000000;
                    // swap R and B
                    uint r = (cl & 0x00FF0000) >> 16;
                    uint b = (cl & 0x000000FF) << 16;
                    row[x] = (cl & 0xFF00FF00) | r | b;
                }
            }
        }

        GLCacheItem addItem(DrawBuf buf)
        {
            GLCacheItem cacheItem = reserveSpace(buf.id, buf.width, buf.height);
            if (cacheItem is null)
                return null;
            buf.onDestroyCallback = &onObjectDestroyedCallback;
            _drawbuf.drawImage(cacheItem._rc.left, cacheItem._rc.top, buf);
            convertPixelFormat(cacheItem);
            _needUpdateTexture = true;
            return cacheItem;
        }
    }

    /// Put new object to cache
    void put(DrawBuf img)
    {
        updateTextureSize();
        GLCacheItem res;
        if (img.width <= tdx / 3 && img.height < tdy / 3)
        {
            // trying to reuse common page for small images
            if (_activePage is null)
            {
                _activePage = new GLImageCachePage(this, tdx, tdy);
                _pages ~= _activePage;
            }
            res = (cast(GLImageCachePage)_activePage).addItem(img);
            if (!res)
            {
                auto page = new GLImageCachePage(this, tdx, tdy);
                _pages ~= page;
                res = page.addItem(img);
                _activePage = page;
            }
        }
        else
        {
            // use separate page for big image
            auto page = new GLImageCachePage(this, img.width, img.height);
            _pages ~= page;
            res = page.addItem(img);
            page.close();
        }
        _map[img.id] = res;
    }
    /// Draw cached item
    void drawItem(uint objectID, Rect dstrc, Rect srcrc, Color color)
    {
        if (auto item = objectID in _map)
            item.page.drawItem(*item, dstrc, srcrc, color, true);
    }
}

private class GLGlyphCache : GLCache
{
    static class GLGlyphCachePage : GLCachePage
    {
        this(GLGlyphCache cache, int dx, int dy)
        {
            super(cache, dx, dy);
            Log.v("created glyph cache page ", dx, "x", dy);
        }

        GLCacheItem addItem(GlyphRef glyph)
        {
            GLCacheItem cacheItem = reserveSpace(glyph.id, glyph.correctedBlackBoxX, glyph.blackBoxY);
            if (cacheItem is null)
                return null;
            _drawbuf.drawGlyphToTexture(cacheItem._rc.left, cacheItem._rc.top, glyph);
            _needUpdateTexture = true;
            return cacheItem;
        }
    }

    /// Put new item to cache
    void put(GlyphRef glyph)
    {
        updateTextureSize();
        if (_activePage is null)
        {
            _activePage = new GLGlyphCachePage(this, tdx, tdy);
            _pages ~= _activePage;
        }
        GLCacheItem res = (cast(GLGlyphCachePage)_activePage).addItem(glyph);
        if (!res)
        {
            auto page = new GLGlyphCachePage(this, tdx, tdy);
            _pages ~= page;
            res = page.addItem(glyph);
            _activePage = page;
        }
        _map[glyph.id] = res;
    }
    /// Draw cached item
    void drawItem(uint objectID, Rect dstrc, Rect srcrc, Color color)
    {
        if (auto item = objectID in _map)
            item.page.drawItem(*item, dstrc, srcrc, color, false);
    }
}
