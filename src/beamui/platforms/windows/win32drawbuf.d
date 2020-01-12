/**
This module contains drawing buffer implementation for Win32 platform

Part of Win32 platform support.

Usually you don't need to use this module directly.

Copyright: Vadim Lopatin 2014-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.windows.win32drawbuf;

version (Windows):
import beamui.core.config;

static if (BACKEND_GUI):
import core.sys.windows.windows;
import beamui.core.logger;
import beamui.core.geometry : RectI;
import beamui.core.math : max;
import beamui.graphics.bitmap;
import beamui.graphics.colors : Color;

/// Win32 context ARGB drawing buffer
class Win32ColorDrawBuf : ColorDrawBufBase
{
    private uint* _pixels;
    private HDC _drawdc;
    private HBITMAP _drawbmp;

    /// Returns handle of win32 device context
    @property HDC dc() { return _drawdc; }
    /// Returns handle of win32 bitmap
    @property HBITMAP bmp() { return _drawdc; }

    this(int width, int height)
    {
        resize(width, height);
    }
    /// Create resized copy of ColorDrawBuf
    this(ColorDrawBuf src, int width, int height)
    {
        resize(width, height);
        fill(Color.transparent);
        blit(src, RectI(0, 0, src.width, src.height), RectI(0, 0, width, height));
    }

    ~this()
    {
        clear();
    }

    /// Invert alpha in buffer content
    void invertAlpha()
    {
        for (int i = _w * _h - 1; i >= 0; i--)
            _pixels[i] ^= 0xFF000000;
    }
    /// Returns HBITMAP for alpha
    HBITMAP createTransparencyBitmap()
    {
        int hbytes = (((_w + 7) / 8) + 1) & 0xFFFFFFFE;
        static __gshared ubyte[] buf;
        buf.length = hbytes * _h * 2;
        //for (int y = 0; y < _h; y++) {
        //    uint * src = scanLine(y);
        //    ubyte * dst1 = buf.ptr + (_h - 1 - y) * hbytes;
        //    ubyte * dst2 = buf.ptr + (_h - 1 - y) * hbytes + hbytes * _h;
        //    for (int x = 0; x < _w; x++) {
        //        ubyte pixel1 = 0x80; //(src[x] >> 24) > 0x80 ? 0 : 0x80;
        //        ubyte pixel2 = (src[x] >> 24) < 0x80 ? 0 : 0x80;
        //        int xi = x >> 3;
        //        dst1[xi] |= (pixel1 >> (x & 7));
        //        dst2[xi] |= (pixel2 >> (x & 7));
        //    }
        //}
        // debug
        for (int i = 0; i < hbytes * _h; i++)
            buf[i] = 0xFF;
        for (int i = hbytes * _h; i < buf.length; i++)
            buf[i] = 0; //0xFF;

        BITMAP b;
        b.bmWidth = _w;
        b.bmHeight = _h;
        b.bmWidthBytes = hbytes;
        b.bmPlanes = 1;
        b.bmBitsPixel = 1;
        b.bmBits = buf.ptr;
        return CreateBitmapIndirect(&b);
        //return CreateBitmap(_w, _h, 1, 1, buf.ptr);
    }
    /// Destroy object, but leave bitmap as is
    HBITMAP destroyLeavingBitmap()
    {
        HBITMAP res = _drawbmp;
        _drawbmp = null;
        destroy(this);
        return res;
    }

    /// Clear buffer contents, set dimension to 0, 0
    private void clear()
    {
        if (_drawbmp !is null || _drawdc !is null)
        {
            if (_drawbmp)
                DeleteObject(_drawbmp);
            if (_drawdc)
                DeleteObject(_drawdc);
            _drawbmp = null;
            _drawdc = null;
            _pixels = null;
            _w = 0;
            _h = 0;
        }
    }

    override protected void* resizeImpl(int width, int height)
    {
        clear();
        if (width > 0 && height > 0)
        {
            BITMAPINFO bmi;
            //memset( &bmi, 0, sizeof(bmi) );
            bmi.bmiHeader.biSize = (bmi.bmiHeader.sizeof);
            bmi.bmiHeader.biWidth = _w;
            bmi.bmiHeader.biHeight = -_h; // top-down
            bmi.bmiHeader.biPlanes = 1;
            bmi.bmiHeader.biBitCount = 32;
            bmi.bmiHeader.biCompression = BI_RGB;
            bmi.bmiHeader.biSizeImage = 0;
            bmi.bmiHeader.biXPelsPerMeter = 1024;
            bmi.bmiHeader.biYPelsPerMeter = 1024;
            bmi.bmiHeader.biClrUsed = 0;
            bmi.bmiHeader.biClrImportant = 0;
            _drawbmp = CreateDIBSection(NULL, &bmi, DIB_RGB_COLORS, cast(void**)(&_pixels), NULL, 0);
            _drawdc = CreateCompatibleDC(NULL);
            SelectObject(_drawdc, _drawbmp);
        }
        return _pixels;
    }

    override void fill(Color color)
    {
        int len = _w * _h;
        _pixels[0 .. len] = color.rgba;
    }

    /// Draw to win32 device context
    void drawTo(HDC dc, int x, int y)
    {
        BitBlt(dc, x, y, _w, _h, _drawdc, 0, 0, SRCCOPY);
    }
}
