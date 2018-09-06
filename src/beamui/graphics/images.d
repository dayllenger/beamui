/**
This module contains image loading functions.

Currently uses FreeImage.

Usage of libpng is not feasible under linux due to conflicts of library and binding versions.

Synopsis:
---
import beamui.graphics.images;
---

Copyright: Vadim Lopatin 2014-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.graphics.images;

import beamui.core.config;

static if (BACKEND_GUI):
//version = USE_DEIMAGE;
//version = USE_DLIBIMAGE;
version = USE_DIMAGE;

version (USE_DEIMAGE)
{
    import devisualization.image;
    import devisualization.image.png;
}
else version (USE_DIMAGE)
{
    //import dimage.io;
    import dimage.image;
    import dimage.png;
    import dimage.jpeg;
}
else version (USE_DLIBIMAGE)
{
    import dlib.image.io.io;
    import dlib.image.image;
    import dlib.image.io.png;
    import dlib.image.io.jpeg;

    version = ENABLE_DLIBIMAGE_JPEG;
}

import std.conv : to;
import std.path;
import beamui.core.logger;
import beamui.core.streams;
import beamui.core.types;
import beamui.graphics.colors;
import beamui.graphics.drawbuf;

/// Load and decode image from file to ColorDrawBuf, returns null if loading or decoding is failed
ColorDrawBuf loadImage(string filename)
{
    static import std.file;

    Log.d("Loading image from file " ~ filename);

    try
    {
        auto data = cast(immutable ubyte[])std.file.read(filename);
        return loadImage(data, filename);
    }
    catch (Exception e)
    {
        Log.e("exception while loading image from file ", filename);
        Log.e(to!string(e));
        return null;
    }
}

/// Load and decode image from input stream to ColorDrawBuf, returns null if loading or decoding is failed
ColorDrawBuf loadImage(immutable ubyte[] data, string filename)
{
    if (isXPM(filename))
    {
        import beamui.graphics.xpm.reader : parseXPM;

        try
        {
            return parseXPM(data);
        }
        catch (Exception e)
        {
            Log.e("Failed to load image from file ", filename);
            Log.e(to!string(e));
            return null;
        }
    }

    version (USE_DEIMAGE)
    {
        try
        {
            Image image = imageFromData(extension(filename)[1 .. $], cast(ubyte[])data); //imageFromFile(filename);
            int w = cast(int)image.width;
            int h = cast(int)image.height;
            ColorDrawBuf buf = new ColorDrawBuf(w, h);
            Color_RGBA[] pixels = image.rgba.allPixels;
            int index = 0;
            foreach (y; 0 .. h)
            {
                uint* dstLine = buf.scanLine(y);
                foreach (x; 0 .. w)
                {
                    Color_RGBA* pixel = &pixels[index + x];
                    dstLine[x] = makeRGBA(pixel.r_ubyte, pixel.g_ubyte, pixel.b_ubyte, pixel.a_ubyte);
                }
                index += w;
            }
            //destroy(image);
            return buf;
        }
        catch (NotAnImageException e)
        {
            Log.e("Failed to load image from file ", filename, " using de_image");
            Log.e(to!string(e));
            return null;
        }
    }
    else version (USE_DLIBIMAGE)
    {
        static import dlib.core.stream;

        try
        {
            version (ENABLE_DLIBIMAGE_JPEG)
            {
            }
            else
            {
                // temporary disabling of JPEG support - until DLIB included it
                if (isJPEG(filename))
                    return null;
            }
            SuperImage image = null;
            auto dlibstream = new dlib.core.stream.ArrayStream(cast(ubyte[])data, data.length);
            if (isJPEG(filename))
                image = dlib.image.io.jpeg.loadJPEG(dlibstream);
            if (isPNG(filename))
                image = dlib.image.io.png.loadPNG(dlibstream);
            //SuperImage image = dlib.image.io.io.loadImage(filename);
            if (!image)
                return null;
            ColorDrawBuf buf = importImage(image);
            destroy(image);
            return buf;
        }
        catch (Exception e)
        {
            Log.e("Failed to load image from file ", filename, " using dlib image");
            Log.e(to!string(e));
            return null;
        }
    }
    else version (USE_DIMAGE)
    {
        static import dimage.stream;

        try
        {
            SuperImage image = null;
            auto dlibstream = new dimage.stream.ArrayStream(cast(ubyte[])data, data.length);
            if (isJPEG(filename))
                image = dimage.jpeg.loadJPEG(dlibstream);
            if (isPNG(filename))
                image = dimage.png.loadPNG(dlibstream);
            //SuperImage image = dlib.image.io.io.loadImage(filename);
            if (!image)
                return null;
            ColorDrawBuf buf = importImage(image);
            destroy(image);
            return buf;
        }
        catch (Exception e)
        {
            Log.e("Failed to load image from file ", filename, " using dlib image");
            Log.e(to!string(e));
            return null;
        }
    }
    else
    {
        try
        {
            std.stream.File f = new std.stream.File(filename);
            scope (exit)
            {
                f.close();
            }
            return loadImage(f);
        }
        catch (Exception e)
        {
            Log.e("exception while loading image from file ", filename);
            Log.e(to!string(e));
            return null;
        }
    }

}

version (USE_DLIBIMAGE)
{
    ColorDrawBuf importImage(SuperImage image)
    {
        int w = image.width;
        int h = image.height;
        ColorDrawBuf buf = new ColorDrawBuf(w, h);
        foreach (y; 0 .. h)
        {
            uint* dstLine = buf.scanLine(y);
            foreach (x; 0 .. w)
            {
                auto pixel = image[x, y].convert(8);
                dstLine[x] = makeRGBA(pixel.r, pixel.g, pixel.b, 255 - pixel.a);
            }
        }
        return buf;
    }
}

version (USE_DIMAGE)
{
    ColorDrawBuf importImage(SuperImage image)
    {
        int w = image.width;
        int h = image.height;
        ColorDrawBuf buf = new ColorDrawBuf(w, h);
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
}

class ImageDecodingException : Exception
{
    this(string msg)
    {
        super(msg);
    }
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
