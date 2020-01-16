/**
Glyph data type and related entities.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2019
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.text.glyph;

import beamui.core.config : USE_OPENGL;
import beamui.core.functions : eliminate;
import beamui.core.signals : Signal;

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
    /// Unique id of glyph (for drawing in hardware accelerated scenes)
    uint id;

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

    /// Removes entries not used after the `checkpoint` calls (notifies about glyph destruction)
    void cleanup()
    {
        foreach (part; _glyphs)
        {
            foreach (ref item; part)
            {
                if (!item.glyph || item.inUse)
                    continue;
                // notify about destroyed glyphs
                onGlyphDestruction(item.glyph.id);
                eliminate(item.glyph);
            }
        }
    }

    /// Clear usage flags for all entries
    void checkpoint()
    {
        foreach (part; _glyphs)
        {
            foreach (ref item; part)
                item.inUse = false;
        }
    }

    /// Removes all entries (notifies about glyph destruction)
    void clear()
    {
        foreach (part; _glyphs)
        {
            foreach (ref item; part)
            {
                if (!item.glyph)
                    continue;
                // notify about destroyed glyphs
                onGlyphDestruction(item.glyph.id);
                eliminate(item.glyph);
            }
        }
    }

    ~this()
    {
        clear();
    }
}

/** Glyph destruction signal (to tell GPU glyph cache that the glyph with `id` can be removed).

    Used for resource management. Usually you don't have to call it manually.
*/
__gshared Signal!(void delegate(uint id)) onGlyphDestruction;

private __gshared uint _nextGlyphID;

/** Generates a unique glyph ID to control the lifetime of GPU glyph cache items.

    Used for resource management. Usually you don't have to call it manually.
*/
uint nextGlyphID()
{
    return _nextGlyphID++;
}
