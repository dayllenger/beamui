/**
Image loading functions.

Support of PNG and JPEG loading is provided by a part of dlib (located in 3rdparty/dimage).

Copyright: Vadim Lopatin 2014-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.images;

import beamui.core.config;

static if (BACKEND_GUI):
import std.conv : to;
static import std.file;

import dimage.image;
static import dimage.jpeg;
static import dimage.png;
static import dimage.stream;

import beamui.core.logger;
import beamui.graphics.drawbuf;
import beamui.graphics.xpm.reader;

/// Load and decode image from file to ColorDrawBuf, returns null if loading or decoding is failed
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

/// Decode image from the byte array to ColorDrawBuf, returns null if decoding is failed
ColorDrawBuf loadImage(immutable ubyte[] data, string filename)
{
    try
    {
        if (isXPM(filename))
            return parseXPM(data);

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
    int w = image.width;
    int h = image.height;
    auto buf = new ColorDrawBuf(w, h);
    foreach (y; 0 .. h)
    {
        uint* dstLine = buf.scanLine(y);
        foreach (x; 0 .. w)
        {
            uint pixel = image[x, y];
            dstLine[x] = pixel ^ 0xFF000000;
        }
    }
    return buf;
}

import std.algorithm : endsWith;

/// Is it PNG?
bool isPNG(in string filename)
{
    return filename.endsWith(".png") || filename.endsWith(".PNG");
}

/// Is it JPG?
bool isJPEG(in string filename)
{
    return filename.endsWith(".jpg") || filename.endsWith(".jpeg") ||
           filename.endsWith(".JPG") || filename.endsWith(".JPEG");
}

/// Is it XPM?
bool isXPM(in string filename)
{
    return filename.endsWith(".xpm") || filename.endsWith(".XPM");
}

/// Is it an image?
bool isImage(in string filename)
{
    return isPNG(filename) || isJPEG(filename) || isXPM(filename);
}
