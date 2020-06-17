/**
Pointer events.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.events.pointer;

nothrow:

import beamui.core.functions;
import beamui.core.geometry : Point;
import beamui.core.ownership : WeakRef;
import beamui.events.keyboard : KeyMods;
import beamui.widgets.widget : Element;

/// Mouse action codes for `MouseEvent`
enum MouseAction : uint
{
    /// Button down handling is cancelled
    cancel,
    /// Button is down
    buttonDown,
    /// Button is up
    buttonUp,
    /// Mouse pointer is moving
    move,
    /// Pointer is back inside widget while button is down after `focusOut`
    focusIn,
    /// Pointer moved outside of widget while button was down (if handler returns true, Move events will be sent even while pointer is outside widget)
    focusOut,
    //hover,    // pointer entered widget which while button was not down (return true to track Hover state)
    /// Pointer left widget which has before processed `move` message, while button was not down
    leave
}

/// Mouse button codes for `MouseEvent`
enum MouseButton : uint
{
    none, /// No button
    left, /// Left mouse button
    right, /// Right mouse button
    middle, /// Middle mouse button
    xbutton1, /// Additional mouse button 1
    xbutton2, /// Additional mouse button 2
}

/// Represents pressed mouse buttons during `MouseEvent`
enum MouseMods : uint
{
    none = 0,  /// No button
    left = 1,  /// Left mouse button
    right = 2, /// Right mouse button
    middle = 4, /// Middle mouse button
    xbutton1 = 8, /// Additional mouse button 1
    xbutton2 = 16, /// Additional mouse button 2
}

/// Convert `MouseButton` to `MouseMods`
MouseMods toMouseMods(MouseButton btn)
{
    final switch (btn) with (MouseButton)
    {
        case none: return MouseMods.none;
        case left: return MouseMods.left;
        case right: return MouseMods.right;
        case middle: return MouseMods.middle;
        case xbutton1: return MouseMods.xbutton1;
        case xbutton2: return MouseMods.xbutton2;
    }
}

/// Double click max interval, milliseconds; may be changed by platform
__gshared long DOUBLE_CLICK_THRESHOLD_MS = 400;

/// Mouse button state details for `MouseEvent`
struct ButtonDetails
{
    nothrow:

    private
    {
        /// Timestamp of the button press (0 if the button is up)
        long _downTs;
        /// Timestamp of the first press of the last double-click (0 if the button is up)
        long _prevDownTs;
        /// Timestamp of the button release (0 if the button is still pressed)
        long _upTs;
        short _downX;
        short _downY;
        MouseMods _mouseMods;
        KeyMods _keyMods;
        /// True if button is made down shortly after up - valid if button is down
        bool _doubleClick;
        /// True if button is made down twice shortly after up - valid if button is down
        bool _tripleClick;
    }

    @property
    {
        /// Returns true if button is made down shortly after up
        bool doubleClick() const { return _doubleClick; }
        /// Returns true if button is made down twice shortly after up
        bool tripleClick() const { return _tripleClick; }

        /// Returns true if button is currently pressed
        bool isDown() const
        {
            return _downTs != 0 && _upTs == 0;
        }
        /// Returns button down state duration in hnsecs (1/10000 of second).
        int downDuration() const
        {
            static import std.datetime;

            if (_downTs == 0)
                return 0;
            if (_downTs != 0 && _upTs != 0)
                return cast(int)(_upTs - _downTs);
            long ts;
            collectException(std.datetime.Clock.currStdTime, ts);
            return cast(int)(ts - _downTs);
        }
        /// X coordinate of the point where button was pressed down last time
        short downX() const { return _downX; }
        /// Y coordinate of the point where button was pressed down last time
        short downY() const { return _downY; }
        /// Bit set of mouse buttons saved on button down
        MouseMods mouseMods() const { return _mouseMods; }
        /// Bit set of key modifiers saved on button down
        KeyMods keyMods() const { return _keyMods; }
    }

    void reset()
    {
        _downTs = _upTs = 0;
        _mouseMods = MouseMods.none;
        _keyMods = KeyMods.none;
        _downX = _downY = 0;
    }

    /// Update for button down
    void down(short x, short y, MouseMods mouseMods, KeyMods keyMods)
    {
        import std.math : abs;
        static import std.datetime;

        const oldDownTs = _downTs;
        collectException(std.datetime.Clock.currStdTime, _downTs);
        _upTs = 0;
        // allow only slight cursor movements when generating double/triple clicks
        if (_downTs - oldDownTs < DOUBLE_CLICK_THRESHOLD_MS * 10_000 &&
            abs(_downX - x) < 5 && abs(_downY - y) < 5)
        {
            _tripleClick = _downTs - _prevDownTs < DOUBLE_CLICK_THRESHOLD_MS * 20_000;
            _doubleClick = !_tripleClick;
            _prevDownTs = _doubleClick ? oldDownTs : 0;
        }
        else
        {
            _doubleClick = false;
            _tripleClick = false;
        }
        _downX = x;
        _downY = y;
        _mouseMods = mouseMods;
        _keyMods = keyMods;
    }
    /// Update for button up
    void up(short x, short y, MouseMods mouseMods, KeyMods keyMods)
    {
        static import std.datetime;

        _doubleClick = false;
        _tripleClick = false;
        collectException(std.datetime.Clock.currStdTime, _upTs);
    }
}

/**
    Mouse event
*/
final class MouseEvent
{
    nothrow:

    private
    {
        MouseAction _action;
        MouseButton _button;
        short _x;
        short _y;
        MouseMods _mouseMods;
        KeyMods _keyMods;
        /// Widget which currently tracks mouse events
        WeakRef!Element _trackingWidget;
        ButtonDetails _lbutton;
        ButtonDetails _mbutton;
        ButtonDetails _rbutton;
        /// When true, no tracking of mouse on `buttonDown` is necessary
        bool _doNotTrackButtonDown;
    }

    /// Construct mouse event from data
    this(MouseAction a, MouseButton b, MouseMods mouseMods, KeyMods keyMods, short x, short y)
    {
        _action = a;
        _button = b;
        _mouseMods = mouseMods;
        _keyMods = keyMods & KeyMods.common;
        _x = x;
        _y = y;
    }
    /// Copy constructor
    this(MouseEvent e)
    {
        _action = e._action;
        _button = e._button;
        _mouseMods = e._mouseMods;
        _keyMods = e._keyMods;
        _x = e._x;
        _y = e._y;
        _lbutton = e._lbutton;
        _rbutton = e._rbutton;
        _mbutton = e._mbutton;
    }

    @property
    {
        /// Action - `buttonDown`, `move`, etc.
        MouseAction action() const { return _action; }
        /// Button which caused `buttonDown` or `buttonUp` action
        MouseButton button() const { return _button; }
        /// Mouse buttons, pressed during this event
        MouseMods mouseMods() const { return _mouseMods; }
        /// Keyboard modifiers (only common, i.e. not distinguishing left and right)
        KeyMods keyMods() const { return _keyMods; }

        /// Left button state details
        ref inout(ButtonDetails) lbutton() inout { return _lbutton; }
        /// Right button state details
        ref inout(ButtonDetails) rbutton() inout { return _rbutton; }
        /// Middle button state details
        ref inout(ButtonDetails) mbutton() inout { return _mbutton; }
        /// Button state details for event's button
        ref inout(ButtonDetails) buttonDetails() inout
        {
            if (_button == MouseButton.right)
                return _rbutton;
            if (_button == MouseButton.middle)
                return _mbutton;
            return _lbutton;
        }

        /// x coordinate of mouse pointer (relative to window client area)
        short x() const { return _x; }
        /// y coordinate of mouse pointer (relative to window client area)
        short y() const { return _y; }
        /// Returns point for mouse cursor position
        Point pos() const
        {
            return Point(_x, _y);
        }

        /// Returns true for `buttonDown` event when button is pressed second time in short interval after pressing first time
        bool doubleClick() const
        {
            if (_action != MouseAction.buttonDown)
                return false;
            return buttonDetails.doubleClick;
        }
        /// Returns true for `buttonDown` event when button is pressed third time in short interval after pressing first time
        bool tripleClick() const
        {
            if (_action != MouseAction.buttonDown)
                return false;
            return buttonDetails.tripleClick;
        }

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

        /// Get event tracking widget to override
        WeakRef!Element trackingWidget() { return _trackingWidget; }
        /// Mouse button tracking flag
        bool doNotTrackButtonDown() const { return _doNotTrackButtonDown; }
        /// ditto
        void doNotTrackButtonDown(bool flag)
        {
            _doNotTrackButtonDown = flag;
        }
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

    /// Override action code (for usage from platform code)
    void changeAction(MouseAction a)
    {
        _action = a;
    }
    /// Override mouse tracking widget
    void track(WeakRef!Element w)
    {
        _trackingWidget = w;
    }

    override string toString() const
    {
        try
            return format("MouseEvent(%s, %s, %s, %s, (%s, %s))",
                _action, _button, _mouseMods, _keyMods, _x, _y);
        catch (Exception)
            return null;
    }
}
