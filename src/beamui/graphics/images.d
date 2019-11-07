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

static if (BACKEND_GUI):
import std.conv : to;
import std.uni : toLower;
static import std.file;

import dimage.image;
static import dimage.jpeg;
static import dimage.png;
static import dimage.stream;

import beamui.core.logger;
import beamui.core.types : Tup, tup;
import beamui.graphics.drawbuf;

alias ImageLoader = ColorDrawBuf function(const ubyte[]);

private Tup!(string, ImageLoader)[] customLoaders;

void registerImageType(string extension, ImageLoader loader)
{
    assert(extension.length && loader);
    customLoaders ~= tup(toLower(extension), loader);
}

/// Load and decode image from file to `ColorDrawBuf`, returns `null` if loading or decoding is failed
ColorDrawBuf loadImage(string filename)
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
        return null;
    }
}

/// Decode image from the byte array to `ColorDrawBuf`, returns `null` if decoding is failed
ColorDrawBuf loadImage(immutable ubyte[] data, string filename)
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
            return null;
        ColorDrawBuf buf = importImage(image);
        destroy(image);
        return buf;
    }
    catch (Exception e)
    {
        Log.e("Failed to decode image from file ", filename);
        Log.e(to!string(e));
        return null;
    }
}

private ColorDrawBuf importImage(SuperImage image)
{
    const int w = image.width;
    const int h = image.height;
    const(uint)[] data = image.data;
    auto buf = new ColorDrawBuf(w, h);
    foreach (y; 0 .. h)
    {
        uint* dstLine = buf.scanLine(y);
        dstLine[0 .. w] = data[0 .. w];
        data = data[w .. $];
    }
    return buf;
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
    return filename.endsWith(".jpg") || filename.endsWith(".jpeg") ||
           filename.endsWith(".JPG") || filename.endsWith(".JPEG");
}
