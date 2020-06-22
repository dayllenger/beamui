/**
Wheel events.

Copyright: dayllenger 2019-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.events.wheel;

import beamui.core.functions;
import beamui.core.geometry : Point;
import beamui.events.keyboard : KeyMods;
import beamui.events.pointer : MouseButton, MouseMods, toMouseMods;

/// Mouse/touchpad scroll event
final class WheelEvent
{
nothrow:
    // dfmt off
    @property
    {
        /// Positive when scrolling right, negative when scrolling left
        int deltaX() const { return _deltaX; }
        /// Positive when scrolling down, negative when scrolling up
        int deltaY() const { return _deltaY; }
        /// Positive when scrolling in, negative when scrolling out
        int deltaZ() const { return _deltaZ; }
        /// Last X coordinate of mouse pointer (relative to window client area)
        int x() const { return _x; }
        /// Last Y coordinate of mouse pointer (relative to window client area)
        int y() const { return _y; }
        /// Last mouse pointer position (relative to window client area)
        Point pos() const
        {
            return Point(_x, _y);
        }

        /// Mouse buttons, pressed during this event
        MouseMods mouseMods() const { return _mouseMods; }
        /// Keyboard modifiers (only common, i.e. not distinguishing left and right)
        KeyMods keyMods() const { return _keyMods; }

        /// True if has no mouse buttons pressed during the event
        bool noMouseMods() const
        {
            return _mouseMods == MouseMods.none;
        }
        /// True if has no keyboard modifiers pressed
        bool noKeyMods() const
        {
            return _keyMods == KeyMods.none;
        }
    }
    // dfmt on

    private
    {
        short _deltaX;
        short _deltaY;
        short _deltaZ;
        short _x;
        short _y;
        MouseMods _mouseMods;
        KeyMods _keyMods;
    }

    this(short x, short y, MouseMods mouseMods, KeyMods keyMods, short deltaX, short deltaY, short deltaZ = 0)
    {
        _deltaX = deltaX;
        _deltaY = deltaY;
        _deltaZ = deltaZ;
        _x = x;
        _y = y;
        _mouseMods = mouseMods;
        _keyMods = keyMods & KeyMods.common;
    }
    /// Copy constructor
    this(WheelEvent e)
    {
        _deltaX = e._deltaX;
        _deltaY = e._deltaY;
        _deltaZ = e._deltaZ;
        _x = e._x;
        _y = e._y;
        _mouseMods = e._mouseMods;
        _keyMods = e._keyMods;
    }

    /// Check whether the mouse button is pressed during this event
    bool alteredByButton(MouseButton btn) const
    {
        return (_mouseMods & toMouseMods(btn)) != MouseMods.none;
    }
    /// Check whether all of `mod` keyboard modifiers are applied during this event
    bool alteredBy(KeyMods mod) const
    {
        return (_keyMods & mod) == mod;
    }

    override string toString() const
    {
        try
            return format("WheelEvent(%s, %s, %s, (%s, %s), %s, %s)", _deltaX, _deltaY, _deltaZ, _x, _y, _mouseMods, _keyMods);
        catch (Exception)
            return null;
    }
}
