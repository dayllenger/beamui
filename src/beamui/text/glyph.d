/**
Glyph data type and related entities.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.text.glyph;

import beamui.core.config : USE_OPENGL;
import beamui.core.functions : eliminate;

/// Subpixel rendering mode for fonts (aka ClearType)
enum SubpixelRenderingMode : ubyte
{
    none, /// No sub
    bgr,  /// Subpixel rendering is on, subpixel order on device: B,G,R
    rgb,  /// Subpixel rendering is on, subpixel order on device: R,G,B
}

/** Character glyph.

    Holder for glyph metrics as well as image.
*/
align(1) struct Glyph
{
    static if (USE_OPENGL)
    {
        /// Unique id of glyph (for drawing in hardware accelerated scenes)
        uint id;
    }

    /// Full width of the glyph
    float widthPixels;
    /// Width of the glyph image box
    ushort blackBoxX;
    /// Height of the glyph image box
    ubyte blackBoxY;
    /// X origin for glyph
    byte originX;
    /// Y origin for glyph
    byte originY;

    /// Subpixel rendering mode - if not `none`, the glyph data contains 3 bytes per pixel instead of 1
    SubpixelRenderingMode subpixelMode;

    /// Glyph data, arbitrary size (blackBoxX * blackBoxY)
    ubyte[] glyph;

    // --- 32 bytes ---

    @property ushort correctedBlackBoxX() const nothrow
    {
        return subpixelMode ? (blackBoxX + 2) / 3 : blackBoxX;
    }
}
/// Pointer to immutable `Glyph` instance
alias GlyphRef = immutable(Glyph)*;

/** Glyph image cache.

    Recently used glyphs are marked. `checkpoint` clears usage marks.
    `cleanup` removes all items not accessed since the last `checkpoint`.
*/
struct GlyphCache
{
    private struct Item
    {
        GlyphRef glyph;
        bool inUse;
    }
    private Item[][1024] _glyphs;

    /// Try to find glyph for character in cache, returns `null` if not found
    GlyphRef find(dchar ch)
    {
        ch = ch & 0xF_FFFF;
        const p = ch >> 8;
        Item[] row = _glyphs[p];
        if (!row)
            return null;
        const i = ch & 0xFF;
        Item* item = &row[i];
        if (!item.glyph)
            return null;
        item.inUse = true;
        return item.glyph;
    }

    /// Put character glyph to cache
    GlyphRef put(dchar ch, GlyphRef glyph)
    {
        assert(glyph);
        ch = ch & 0xF_FFFF;
        const p = ch >> 8;
        const i = ch & 0xFF;
        if (_glyphs[p] is null)
            _glyphs[p] = new Item[256];
        _glyphs[p][i] = Item(glyph, true);
        return glyph;
    }

    /// Removes entries not used after last call of `checkpoint()` or `cleanup()`
    void cleanup()
    {
        foreach (part; _glyphs)
        {
            if (!part)
                continue;
            foreach (item; part)
            {
                if (!item.glyph || item.inUse)
                    continue;
                static if (USE_OPENGL)
                {
                    // notify about destroyed glyphs
                    if (_glyphDestroyCallback)
                        _glyphDestroyCallback(item.glyph.id);
                }
                eliminate(item.glyph);
            }
        }
    }

    /// Clear usage flags for all entries
    void checkpoint()
    {
        foreach (part; _glyphs)
        {
            if (!part)
                continue;
            foreach (ref item; part)
                item.inUse = false;
        }
    }

    /// Removes all entries (when built with `USE_OPENGL` version, notify OpenGL cache about removed glyphs)
    void clear()
    {
        foreach (part; _glyphs)
        {
            if (!part)
                continue;
            foreach (item; part)
            {
                if (!item.glyph)
                    continue;
                static if (USE_OPENGL)
                {
                    // notify about destroyed glyphs
                    if (_glyphDestroyCallback)
                        _glyphDestroyCallback(item.glyph.id);
                }
                eliminate(item.glyph);
            }
        }
    }

    ~this()
    {
        clear();
    }
}

static if (USE_OPENGL)
{
    private __gshared void function(uint id) _glyphDestroyCallback;
    private __gshared uint _nextGlyphID;

    /** Glyph destroy callback (to cleanup OpenGL caches).

        This callback is used to tell OpenGL glyph cache that the glyph is
        not more used - to let the cache cleanup its textures.

        Used for resource management. Usually you don't have to call it manually.
    */
    void function(uint id) glyphDestroyCallback() { return _glyphDestroyCallback; }
    /// ditto
    void glyphDestroyCallback(void function(uint id) callback)
    {
        _glyphDestroyCallback = callback;
    }

    /** Generates a unique glyph ID to control the lifetime of OpenGL glyph cache items.

        Used for resource management. Usually you don't have to call it manually.
    */
    uint nextGlyphID()
    {
        return _nextGlyphID++;
    }
}
