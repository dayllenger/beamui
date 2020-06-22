/**
Image loading functions.

Support of PNG and JPEG loading is provided by a part of dlib (located in 3rdparty/dimage).

Not available on console backends. Guard image code with `static if (BACKEND_GUI)` condition.

Copyright: Vadim Lopatin 2014-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.images;

import beamui.core.config;

// dfmt off
static if (BACKEND_GUI):
// dfmt on
import std.conv : to;
import std.uni : toLower;
static import std.file;

import dimage.image;
static import dimage.jpeg;
static import dimage.png;
static import dimage.stream;

import beamui.core.logger;
import beamui.core.types : Tup, tup;
import beamui.graphics.bitmap;

alias ImageLoader = Bitmap function(const ubyte[]);

private Tup!(string, ImageLoader)[] customLoaders;

void registerImageType(string extension, ImageLoader loader)
{
    assert(extension.length && loader);
    customLoaders ~= tup(toLower(extension), loader);
}

/// Load and decode image from file to `Bitmap`, returns empty bitmap if loading or decoding failed
Bitmap loadImage(string filename)
{
    Log.d("Loading image from file " ~ filename);

    try
    {
        auto data = cast(immutable ubyte[])std.file.read(filename);
        return loadImage(data, filename);
    }
    catch (Exception e)
    {
        Log.e("Exception while loading image from file ", filename);
        Log.e(to!string(e));
        return Bitmap.init;
    }
}

/// Decode image from the byte array to `Bitmap`, returns empty bitmap if decoding failed
Bitmap loadImage(immutable ubyte[] data, string filename)
{
    try
    {
        // try to find custom loader first
        foreach (type; customLoaders)
        {
            if (filename.length > type[0].length)
            {
                const start = filename.length - type[0].length;
                if (filename[start - 1] == '.')
                {
                    if (type[0] == toLower(filename[start .. $]))
                        return type[1](data);
                }
            }
        }
        // try dlib
        SuperImage image;
        auto stream = new dimage.stream.ArrayStream(cast(ubyte[])data, data.length);
        if (isJPEG(filename))
            image = dimage.jpeg.loadJPEG(stream);
        if (isPNG(filename))
            image = dimage.png.loadPNG(stream);
        if (!image)
            return Bitmap.init;
        Bitmap bm = importImage(image);
        destroy(image);
        return bm;
    }
    catch (Exception e)
    {
        Log.e("Failed to decode image from file ", filename);
        Log.e(to!string(e));
        return Bitmap.init;
    }
}

private Bitmap importImage(SuperImage image)
{
    const int w = image.width;
    const int h = image.height;
    const(uint)[] data = image.data;
    auto bitmap = Bitmap(w, h, PixelFormat.argb8);
    auto pxRef = bitmap.mutate!uint;
    foreach (y; 0 .. h)
    {
        uint* dstLine = pxRef.scanline(y);
        dstLine[0 .. w] = data[0 .. w];
        data = data[w .. $];
    }
    bitmap.preMultiplyAlpha();
    return bitmap;
}

import std.algorithm : endsWith;

/// Is it a PNG filename?
bool isPNG(string filename)
{
    return filename.endsWith(".png") || filename.endsWith(".PNG");
}

/// Is it a JPG filename?
bool isJPEG(string filename)
{
    alias fn = filename;
    return fn.endsWith(".jpg") || fn.endsWith(".jpeg") || fn.endsWith(".JPG") || fn.endsWith(".JPEG");
}
