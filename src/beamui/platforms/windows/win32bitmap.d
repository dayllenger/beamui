/**
Win32 bitmap.

Part of Win32 platform support.

Usually you don't need to use this module directly.

Copyright: Vadim Lopatin 2014-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.windows.win32bitmap;

version (Windows):
import beamui.core.config;

static if (BACKEND_GUI):
import core.sys.windows.windows;
import beamui.graphics.bitmap : BitmapData, PixelFormat;

/// Win32 context ARGB8 bitmap container
final class Win32BitmapData : BitmapData
{
    private void* _pixels;
    private HDC _drawdc;
    private HBITMAP _drawbmp;

    /// Returns handle of win32 device context
    @property HDC dc() { return _drawdc; }
    /// Returns handle of win32 bitmap
    @property HBITMAP bmp() { return _drawdc; }

    this(uint width, uint height)
    {
        super(width, height, 4, PixelFormat.argb8);
    }

    this(Win32BitmapData src)
    {
        super(src);
        handleResize();
        pixels[] = src.pixels[];
    }

    ~this()
    {
        clear();
    }

    /// Clear bitmap contents
    private void clear()
    {
        if (_drawbmp)
        {
            DeleteObject(_drawbmp);
            _drawbmp = null;
        }
        if (_drawdc)
        {
            DeleteObject(_drawdc);
            _drawdc = null;
        }
        _pixels = null;
    }

    /// Returns HBITMAP for alpha
    HBITMAP createTransparencyBitmap()
    {
        int hbytes = (((width + 7) / 8) + 1) & 0xFFFFFFFE;
        static __gshared ubyte[] buf;
        buf.length = hbytes * height * 2;
        //for (int y = 0; y < height; y++) {
        //    uint * src = scanLine(y);
        //    ubyte * dst1 = buf.ptr + (height - 1 - y) * hbytes;
        //    ubyte * dst2 = buf.ptr + (height - 1 - y) * hbytes + hbytes * height;
        //    for (int x = 0; x < width; x++) {
        //        ubyte pixel1 = 0x80; //(src[x] >> 24) > 0x80 ? 0 : 0x80;
        //        ubyte pixel2 = (src[x] >> 24) < 0x80 ? 0 : 0x80;
        //        int xi = x >> 3;
        //        dst1[xi] |= (pixel1 >> (x & 7));
        //        dst2[xi] |= (pixel2 >> (x & 7));
        //    }
        //}
        // debug
        for (int i = 0; i < hbytes * height; i++)
            buf[i] = 0xFF;
        for (int i = hbytes * height; i < buf.length; i++)
            buf[i] = 0; //0xFF;

        BITMAP b;
        b.bmWidth = width;
        b.bmHeight = height;
        b.bmWidthBytes = hbytes;
        b.bmPlanes = 1;
        b.bmBitsPixel = 1;
        b.bmBits = buf.ptr;
        return CreateBitmapIndirect(&b);
        //return CreateBitmap(width, height, 1, 1, buf.ptr);
    }

    /// Destroy object, but leave HBITMAP as is
    HBITMAP destroyLeavingBitmap()
    {
        HBITMAP res = _drawbmp;
        _drawbmp = null;
        destroy(this);
        return res;
    }

    /// Draw to win32 device context
    void drawTo(HDC dc)
    {
        BitBlt(dc, 0, 0, width, height, _drawdc, 0, 0, SRCCOPY);
    }

    override inout(void[]) pixels() inout
    {
        return _pixels[0 .. height * rowBytes];
    }

    override void handleResize()
    {
        clear();

        BITMAPINFO bmi;
        bmi.bmiHeader.biSize = bmi.bmiHeader.sizeof;
        bmi.bmiHeader.biWidth = width;
        bmi.bmiHeader.biHeight = -height; // top-down
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;
        bmi.bmiHeader.biSizeImage = 0;
        bmi.bmiHeader.biXPelsPerMeter = 1024;
        bmi.bmiHeader.biYPelsPerMeter = 1024;
        bmi.bmiHeader.biClrUsed = 0;
        bmi.bmiHeader.biClrImportant = 0;
        _drawbmp = CreateDIBSection(NULL, &bmi, DIB_RGB_COLORS, &_pixels, NULL, 0);
        _drawdc = CreateCompatibleDC(NULL);
        SelectObject(_drawdc, _drawbmp);

        rowBytes = width * stride;
    }

    override BitmapData clone()
    {
        return new Win32BitmapData(this);
    }
}
