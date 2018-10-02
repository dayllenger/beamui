/**
This module contains event types declarations.

Event types: MouseEvent, KeyEvent, ScrollEvent.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.events;

import beamui.widgets.widget;

/// Mouse action codes for MouseEvent
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
    /// Pointer is back inside widget while button is down after FocusOut
    focusIn,
    /// Pointer moved outside of widget while button was down (if handler returns true, Move events will be sent even while pointer is outside widget)
    focusOut,
    /// Scroll wheel movement
    wheel,
    //hover,    // pointer entered widget which while button was not down (return true to track Hover state)
    /// Pointer left widget which has before processed Move message, while button was not down
    leave
}

/// Mouse flag bits (mouse buttons and keyboard modifiers) for MouseEvent
enum MouseFlag : uint
{
    // mouse buttons
    /// Left mouse button is down
    lbutton = 0x0001,
    /// Middle mouse button is down
    mbutton = 0x0010,
    /// Right mouse button is down
    rbutton = 0x0002,
    /// X1 mouse button is down
    xbutton1 = 0x0020,
    /// X2 mouse button is down
    xbutton2 = 0x0040,

    // keyboard modifiers
    /// Ctrl key is down
    control = 0x0008,
    /// Shift key is down
    shift = 0x0004,
    /// Alt key is down
    alt = 0x0080,

    /// Mask for mouse button flags
    buttonsMask = lbutton | mbutton | rbutton | xbutton1 | xbutton2,
    /// Mask for keyboard flags
    keyMask = control | shift | alt,
}

/// Mouse button codes for MouseEvent
enum MouseButton : uint
{
    /// No button
    none,
    /// Left mouse button
    left = MouseFlag.lbutton,
    /// Right mouse button
    right = MouseFlag.rbutton,
    /// Right mouse button
    middle = MouseFlag.mbutton,
    /// Additional mouse button 1
    xbutton1 = MouseFlag.xbutton1, // additional button 1
    /// Additional mouse button 2
    xbutton2 = MouseFlag.xbutton2, // additional button 2
}

/// Converts MouseButton to MouseFlag
ushort mouseButtonToFlag(MouseButton btn)
{
    switch (btn) with (MouseButton)
    {
    case left:
        return MouseFlag.lbutton;
    case right:
        return MouseFlag.rbutton;
    case middle:
        return MouseFlag.mbutton;
    case xbutton1:
        return MouseFlag.xbutton1;
    case xbutton2:
        return MouseFlag.xbutton2;
    default:
        return 0;
    }
}

/// Double click max interval, milliseconds; may be changed by platform
__gshared long DOUBLE_CLICK_THRESHOLD_MS = 400;

/// Mouse button state details for MouseEvent
struct ButtonDetails
{
    protected
    {
        /// Clock.currStdTime() for down event of this button (0 if button is up) set after double click to time when first click occured.
        long _prevDownTs;
        /// Clock.currStdTime() for down event of this button (0 if button is up).
        long _downTs;
        /// Clock.currStdTime() for up event of this button (0 if button is still down).
        long _upTs;
        /// x coordinates of down event
        short _downX;
        /// y coordinates of down event
        short _downY;
        /// Mouse button flags when down event occured
        ushort _downFlags;
        /// True if button is made down shortly after up - valid if button is down
        bool _doubleClick;
        /// True if button is made down twice shortly after up - valid if button is down
        bool _tripleClick;
    }

    @property
    {
        /// Returns true if button is made down shortly after up
        bool doubleClick() const
        {
            return _doubleClick;
        }

        /// Returns true if button is made down twice shortly after up
        bool tripleClick() const
        {
            return _tripleClick;
        }
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
            long ts = std.datetime.Clock.currStdTime;
            return cast(int)(ts - _downTs);
        }
        /// X coordinate of point where button was pressed Down last time
        short downX() const
        {
            return _downX;
        }
        /// Y coordinate of point where button was pressed Down last time
        short downY() const
        {
            return _downY;
        }
        /// Bit set of mouse flags saved on button down
        ushort downFlags() const
        {
            return _downFlags;
        }
    }

    void reset()
    {
        _downTs = _upTs = 0;
        _downFlags = 0;
        _downX = _downY = 0;
    }

    /// Update for button down
    void down(short x, short y, ushort flags)
    {
        static import std.datetime;

        long oldDownTs = _downTs;
        _downX = x;
        _downY = y;
        _downFlags = flags;
        _upTs = 0;
        _downTs = std.datetime.Clock.currStdTime;
        long downIntervalMs = (_downTs - oldDownTs) / 10000;
        long prevDownIntervalMs = (_downTs - _prevDownTs) / 10000;
        _tripleClick = (prevDownIntervalMs && prevDownIntervalMs < DOUBLE_CLICK_THRESHOLD_MS * 2);
        _doubleClick = !_tripleClick && (oldDownTs && downIntervalMs < DOUBLE_CLICK_THRESHOLD_MS);
        _prevDownTs = _doubleClick ? oldDownTs : 0;
    }
    /// Update for button up
    void up(short x, short y, ushort flags)
    {
        static import std.datetime;

        _doubleClick = false;
        _tripleClick = false;
        _upTs = std.datetime.Clock.currStdTime;
    }
}

/**
    Mouse event
*/
final class MouseEvent
{
    protected
    {
        /// Timestamp of event
        long _eventTimestamp;
        /// Mouse action code
        MouseAction _action;
        /// Mouse button code for ButtonUp/ButtonDown
        MouseButton _button;
        /// x coordinate of pointer
        short _x;
        /// y coordinate of pointer
        short _y;
        /// Flags bit set - usually from MouseFlag enum
        ushort _flags;
        /// Wheel delta
        short _wheelDelta;
        /// Widget which currently tracks mouse events
        WeakRef!Widget _trackingWidget;
        /// Left button state details
        ButtonDetails _lbutton;
        /// Middle button state details
        ButtonDetails _mbutton;
        /// Right button state details
        ButtonDetails _rbutton;
        /// When true, no tracking of mouse on ButtonDown is necessary
        bool _doNotTrackButtonDown;
    }

    /// Construct mouse event from data
    this(MouseAction a, MouseButton b, ushort f, short x, short y, short wheelDelta = 0)
    {
        static import std.datetime;

        _eventTimestamp = std.datetime.Clock.currStdTime;
        _action = a;
        _button = b;
        _flags = f;
        _x = x;
        _y = y;
        _wheelDelta = wheelDelta;
    }
    /// Copy constructor
    this(MouseEvent e)
    {
        _eventTimestamp = e._eventTimestamp;
        _action = e._action;
        _button = e._button;
        _flags = e._flags;
        _x = e._x;
        _y = e._y;
        _lbutton = e._lbutton;
        _rbutton = e._rbutton;
        _mbutton = e._mbutton;
        _wheelDelta = e._wheelDelta;
    }

    @property
    {
        /// Left button state details
        ref inout(ButtonDetails) lbutton() inout
        {
            return _lbutton;
        }
        /// Right button state details
        ref inout(ButtonDetails) rbutton() inout
        {
            return _rbutton;
        }
        /// Middle button state details
        ref inout(ButtonDetails) mbutton() inout
        {
            return _mbutton;
        }
        /// Button state details for event's button
        ref inout(ButtonDetails) buttonDetails() inout
        {
            if (_button == MouseButton.right)
                return _rbutton;
            if (_button == MouseButton.middle)
                return _mbutton;
            return _lbutton;
        }
        /// Button which caused ButtonUp or ButtonDown action
        MouseButton button() const
        {
            return _button;
        }
        /// Action
        MouseAction action() const
        {
            return _action;
        }
        /// Returns flags (buttons and keys state)
        ushort flags() const
        {
            return _flags;
        }
        /// Returns mouse button flags only
        ushort buttonFlags() const
        {
            return _flags & MouseFlag.buttonsMask;
        }
        /// Returns keyboard modifier flags only
        ushort keyFlags() const
        {
            return _flags & MouseFlag.keyMask;
        }
        /// Returns delta for Wheel event
        short wheelDelta() const
        {
            return _wheelDelta;
        }
        /// x coordinate of mouse pointer (relative to window client area)
        short x() const
        {
            return _x;
        }
        /// y coordinate of mouse pointer (relative to window client area)
        short y() const
        {
            return _y;
        }

        /// Returns point for mouse cursor position
        Point pos() const
        {
            return Point(_x, _y);
        }

        /// Returns true if no modifier flags are set
        bool noModifiers() const
        {
            return (_flags & (MouseFlag.control | MouseFlag.alt | MouseFlag.shift)) == 0;
        }
        /// Returns true if any modifier flag is set
        bool hasModifiers() const
        {
            return !noModifiers;
        }

        /// Returns true for ButtonDown event when button is pressed second time in short interval after pressing first time
        bool doubleClick() const
        {
            if (_action != MouseAction.buttonDown)
                return false;
            return buttonDetails.doubleClick;
        }

        /// Returns true for ButtonDown event when button is pressed third time in short interval after pressing first time
        bool tripleClick() const
        {
            if (_action != MouseAction.buttonDown)
                return false;
            return buttonDetails.tripleClick;
        }

        /// Get event tracking widget to override
        WeakRef!Widget trackingWidget()
        {
            return _trackingWidget;
        }
        /// Mouse button tracking flag
        bool doNotTrackButtonDown() const
        {
            return _doNotTrackButtonDown;
        }
        /// ditto
        void doNotTrackButtonDown(bool flag)
        {
            _doNotTrackButtonDown = flag;
        }
    }

    /// Override action code (for usage from platform code)
    void changeAction(MouseAction a)
    {
        _action = a;
    }
    /// Override mouse tracking widget
    void track(WeakRef!Widget w)
    {
        _trackingWidget = w;
    }

    override string toString() const
    {
        return format("MouseEvent(%s, %s, %04x, (%s, %s))", _action, cast(MouseButton)_button, _flags, _x, _y);
    }
}

/// Keyboard actions for KeyEvent
enum KeyAction : uint
{
    /// Key is pressed
    keyDown,
    /// Key is released
    keyUp,
    /// Text is entered
    text,
    /// Repeated key down
    repeat,
}

/// Keyboard flags for KeyEvent
enum KeyFlag : uint
{
    /// Ctrl key is down
    control = 0x0001,
    /// Shift key is down
    shift = 0x0002,
    /// Alt key is down
    alt = 0x0004,
    option = alt,
    /// Menu key
    menu = 0x0008,
    command = menu,
    // Flags not counting left or right difference
    mainFlags = 0xFF,
    /// Right Ctrl key is down
    rcontrol = 0x0101,
    /// Right Shift key is down
    rshift = 0x0202,
    /// Right Alt key is down
    ralt = 0x0404,
    /// Right Menu/Win key is down
    rmenu = 0x0808,
    /// Left Ctrl key is down
    lcontrol = 0x1001,
    /// Left Shift key is down
    lshift = 0x2002,
    /// Left Alt key is down
    lalt = 0x4004,
    /// Left Menu/Win key is down
    lmenu = 0x8008,

    lrcontrol = lcontrol | rcontrol, // both left and right
    lralt = lalt | ralt, // both left and right
    lrshift = lshift | rshift, // both left and right
    lrmenu = lmenu | rmenu, // both left and right
}

/// Key code constants for KeyEvent
enum KeyCode : uint
{
    none = 0,
    /// Backspace
    backspace = 8,
    /// Tab
    tab = 9,
    /// Return / enter key
    enter = 0x0D,
    /// Shift
    shift = 0x10,
    /// Ctrl
    control = 0x11,
    /// Alt
    alt = 0x12, // VK_MENU
    /// Pause
    pause = 0x13,
    /// Caps lock
    caps = 0x14, // VK_CAPITAL, caps lock
    /// Esc
    escape = 0x1B, // esc
    /// Space
    space = 0x20,
    /// Page up
    pageUp = 0x21, // VK_PRIOR
    /// Page down
    pageDown = 0x22, // VK_NEXT
    /// End
    end = 0x23, // VK_END
    /// Home
    home = 0x24, // VK_HOME
    /// Left arrow
    left = 0x25,
    /// Up arrow
    up = 0x26,
    /// Right arrow
    right = 0x27,
    /// Down arrow
    down = 0x28,
    /// Ins
    ins = 0x2D,
    /// Delete
    del = 0x2E,
    /// 0 on the alphanumeric part of keyboard
    alpha0 = 0x30,
    /// 1 on the alphanumeric part of keyboard
    alpha1 = 0x31,
    /// 2 on the alphanumeric part of keyboard
    alpha2 = 0x32,
    /// 3 on the alphanumeric part of keyboard
    alpha3 = 0x33,
    /// 4 on the alphanumeric part of keyboard
    alpha4 = 0x34,
    /// 5 on the alphanumeric part of keyboard
    alpha5 = 0x35,
    /// 6 on the alphanumeric part of keyboard
    alpha6 = 0x36,
    /// 7 on the alphanumeric part of keyboard
    alpha7 = 0x37,
    /// 8 on the alphanumeric part of keyboard
    alpha8 = 0x38,
    /// 9 on the alphanumeric part of keyboard
    alpha9 = 0x39,
    /// A
    A = 0x41,
    /// B
    B = 0x42,
    /// C
    C = 0x43,
    /// D
    D = 0x44,
    /// E
    E = 0x45,
    /// F
    F = 0x46,
    /// G
    G = 0x47,
    /// H
    H = 0x48,
    /// I
    I = 0x49,
    /// J
    J = 0x4a,
    /// K
    K = 0x4b,
    /// L
    L = 0x4c,
    /// M
    M = 0x4d,
    /// N
    N = 0x4e,
    /// O
    O = 0x4f,
    /// P
    P = 0x50,
    /// Q
    Q = 0x51,
    /// R
    R = 0x52,
    /// S
    S = 0x53,
    /// T
    T = 0x54,
    /// U
    U = 0x55,
    /// V
    V = 0x56,
    /// W
    W = 0x57,
    /// X
    X = 0x58,
    /// Y
    Y = 0x59,
    /// Z
    Z = 0x5a,
    /// [
    bracketOpen = 0xDB,
    /// ]
    bracketClose = 0xDD,
    /// Key +
    add = 0x6B,
    /// Key -
    subtract = 0x6D,
    /// Key *
    multiply = 0x6A,
    /// Key /
    divide = 0x6F,
    /// Key ,
    comma = 0xBC,
    /// Key .
    period = 0xBE,
    /// Left win key
    lwin = 0x5b,
    /// Right win key
    rwin = 0x5c,
    /// Numpad 0
    num0 = 0x60,
    /// Numpad 1
    num1 = 0x61,
    /// Numpad 2
    num2 = 0x62,
    /// Numpad 3
    num3 = 0x63,
    /// Numpad 4
    num4 = 0x64,
    /// Numpad 5
    num5 = 0x65,
    /// Numpad 6
    num6 = 0x66,
    /// Numpad 7
    num7 = 0x67,
    /// Numpad 8
    num8 = 0x68,
    /// Numpad 9
    num9 = 0x69,
    /// Numpad +
    numAdd = 0x6B,
    /// Numpad -
    numSub = 0x6D,
    /// Numpad *
    numMul = 0x6A,
    /// Numpad /
    numDiv = 0x6F,
    /// Numpad .
    numPeriod = 0x6E,
    /// F1
    F1 = 0x70,
    /// F2
    F2 = 0x71,
    /// F3
    F3 = 0x72,
    /// F4
    F4 = 0x73,
    /// F5
    F5 = 0x74,
    /// F6
    F6 = 0x75,
    /// F7
    F7 = 0x76,
    /// F8
    F8 = 0x77,
    /// F9
    F9 = 0x78,
    /// F10
    F10 = 0x79,
    /// F11
    F11 = 0x7a,
    /// F12
    F12 = 0x7b,
    /// F13
    F13 = 0x7c,
    /// F14
    F14 = 0x7d,
    /// F15
    F15 = 0x7e,
    /// F16
    F16 = 0x7f,
    /// F17
    F17 = 0x80,
    /// F18
    F18 = 0x81,
    /// F19
    F19 = 0x82,
    /// F20
    F20 = 0x83,
    /// F21
    F21 = 0x84,
    /// F22
    F22 = 0x85,
    /// F23
    F23 = 0x86,
    /// F24
    F24 = 0x87,
    /// Num lock
    numlock = 0x90,
    /// Scroll lock
    scroll = 0x91,
    /// Left shift
    lshift = 0xA0,
    /// Right shift
    rshift = 0xA1,
    /// Left ctrl
    lcontrol = 0xA2,
    /// Right ctrl
    rcontrol = 0xA3,
    /// Left alt
    lalt = 0xA4,
    /// Right alt
    ralt = 0xA5,
    //LMENU = 0xA4, //VK_LMENU
    //RMENU = 0xA5,
    /// ;
    semicolon = 0x201,
    /// ~
    tilde = 0x202,
    /// '
    quote = 0x203,
    /// /
    slash = 0x204,
    /// \
    backslash = 0x205,
    /// =
    equal = 0x206,
}

/// Keyboard event
final class KeyEvent
{
    protected
    {
        /// Action
        KeyAction _action;
        /// Key code, usually from KeyCode enum
        uint _keyCode;
        /// Key flags bit set, usually combined from KeyFlag enum
        uint _flags;
        /// Entered text
        dstring _text;
    }

    /// Create key event
    this(KeyAction action, uint keyCode, uint flags, dstring text = null)
    {
        _action = action;
        _keyCode = keyCode;
        _flags = flags;
        _text = text;
    }

    @property
    {
        /// Key action (KeyDown, KeyUp, Text, Repeat)
        KeyAction action() const
        {
            return _action;
        }
        /// Key code (usually from KeyCode enum)
        uint keyCode() const
        {
            return _keyCode;
        }
        /// Flags (shift, ctrl, alt...) - KeyFlag enum
        uint flags() const
        {
            return _flags;
        }
        /// Entered text, for Text action
        dstring text() const
        {
            return _text;
        }

        /// Returns true if no modifier flags are set
        bool noModifiers() const
        {
            return modifiers == 0;
        }
        /// Returns true if any modifier flag is set
        bool hasModifiers() const
        {
            return !noModifiers;
        }
        /// Returns modifier flags filtered for KeyFlag.control | KeyFlag.alt | KeyFlag.menu | KeyFlag.shift only
        uint modifiers() const
        {
            return (_flags & (KeyFlag.control | KeyFlag.alt | KeyFlag.menu | KeyFlag.shift));
        }
    }

    override string toString() const
    {
        return format("KeyEvent(%s, %s, %04x, %s)", _action, cast(KeyCode)_keyCode, _flags, _text);
    }
}

/// Scroll bar / slider action codes for ScrollEvent.
enum ScrollAction : ubyte
{
    /// Space above indicator pressed
    pageUp,
    /// Space below indicator pressed
    pageDown,
    /// Up/left button pressed
    lineUp,
    /// Down/right button pressed
    lineDown,
    /// Slider pressed
    sliderPressed,
    /// Dragging in progress
    sliderMoved,
    /// Dragging finished
    sliderReleased
}

/// Slider/scrollbar event
final class ScrollEvent
{
    private
    {
        ScrollAction _action;
        int _minValue;
        int _maxValue;
        int _pageSize;
        int _position;
        bool _positionChanged;
    }

    /// Create scroll event
    this(ScrollAction action, int minValue, int maxValue, int pageSize, int position)
    {
        _action = action;
        _minValue = minValue;
        _maxValue = maxValue;
        _pageSize = pageSize;
        _position = position;
    }

    @property
    {
        /// Action
        ScrollAction action() const
        {
            return _action;
        }
        /// Min value
        int minValue() const
        {
            return _minValue;
        }
        /// Max value
        int maxValue() const
        {
            return _maxValue;
        }
        /// Visible part size
        int pageSize() const
        {
            return _pageSize;
        }
        /// Current position
        int position() const
        {
            return _position;
        }
        /// Returns true if position has been changed using position property setter
        bool positionChanged() const
        {
            return _positionChanged;
        }
        /// Change position in event handler to update slider position
        void position(int newPosition)
        {
            _position = newPosition;
            _positionChanged = true;
        }
    }

    /// Default update position for actions like PageUp/PageDown, LineUp/LineDown
    int defaultUpdatePosition()
    {
        int delta = 0;
        switch (_action) with (ScrollAction)
        {
        case lineUp:
            delta = _pageSize / 20;
            if (delta < 1)
                delta = 1;
            delta = -delta;
            break;
        case lineDown:
            delta = _pageSize / 20;
            if (delta < 1)
                delta = 1;
            break;
        case pageUp:
            delta = _pageSize * 3 / 4;
            if (delta < 1)
                delta = 1;
            delta = -delta;
            break;
        case pageDown:
            delta = _pageSize * 3 / 4;
            if (delta < 1)
                delta = 1;
            break;
        default:
            return position;
        }
        int newPosition = _position + delta;
        if (newPosition > _maxValue - _pageSize)
            newPosition = _maxValue - _pageSize;
        if (newPosition < _minValue)
            newPosition = _minValue;
        if (_position != newPosition)
            position = newPosition;
        return position;
    }
}

/**
    Converts key name to KeyCode enum value

    For unknown key code, returns 0.
*/
uint parseKeyName(string name) pure nothrow @nogc
{
    switch (name)
    {
    case "A":
    case "a":
        return KeyCode.A;
    case "B":
    case "b":
        return KeyCode.B;
    case "C":
    case "c":
        return KeyCode.C;
    case "D":
    case "d":
        return KeyCode.D;
    case "E":
    case "e":
        return KeyCode.E;
    case "F":
    case "f":
        return KeyCode.F;
    case "G":
    case "g":
        return KeyCode.G;
    case "H":
    case "h":
        return KeyCode.H;
    case "I":
    case "i":
        return KeyCode.I;
    case "J":
    case "j":
        return KeyCode.J;
    case "K":
    case "k":
        return KeyCode.K;
    case "L":
    case "l":
        return KeyCode.L;
    case "M":
    case "m":
        return KeyCode.M;
    case "N":
    case "n":
        return KeyCode.N;
    case "O":
    case "o":
        return KeyCode.O;
    case "P":
    case "p":
        return KeyCode.P;
    case "Q":
    case "q":
        return KeyCode.Q;
    case "R":
    case "r":
        return KeyCode.R;
    case "S":
    case "s":
        return KeyCode.S;
    case "T":
    case "t":
        return KeyCode.T;
    case "U":
    case "u":
        return KeyCode.U;
    case "V":
    case "v":
        return KeyCode.V;
    case "W":
    case "w":
        return KeyCode.W;
    case "X":
    case "x":
        return KeyCode.X;
    case "Y":
    case "y":
        return KeyCode.Y;
    case "Z":
    case "z":
        return KeyCode.Z;
    case "F1":
        return KeyCode.F1;
    case "F2":
        return KeyCode.F2;
    case "F3":
        return KeyCode.F3;
    case "F4":
        return KeyCode.F4;
    case "F5":
        return KeyCode.F5;
    case "F6":
        return KeyCode.F6;
    case "F7":
        return KeyCode.F7;
    case "F8":
        return KeyCode.F8;
    case "F9":
        return KeyCode.F9;
    case "F10":
        return KeyCode.F10;
    case "F11":
        return KeyCode.F11;
    case "F12":
        return KeyCode.F12;
    case "F13":
        return KeyCode.F13;
    case "F14":
        return KeyCode.F14;
    case "F15":
        return KeyCode.F15;
    case "F16":
        return KeyCode.F16;
    case "F17":
        return KeyCode.F17;
    case "F18":
        return KeyCode.F18;
    case "F19":
        return KeyCode.F19;
    case "F20":
        return KeyCode.F20;
    case "F21":
        return KeyCode.F21;
    case "F22":
        return KeyCode.F22;
    case "F23":
        return KeyCode.F23;
    case "F24":
        return KeyCode.F24;
    case "/":
        return KeyCode.divide;
    case "*":
        return KeyCode.multiply;
    case "Tab":
        return KeyCode.tab;
    case "PageUp":
        return KeyCode.pageUp;
    case "PageDown":
        return KeyCode.pageDown;
    case "Home":
        return KeyCode.home;
    case "End":
        return KeyCode.end;
    case "Left":
        return KeyCode.left;
    case "Right":
        return KeyCode.right;
    case "Up":
        return KeyCode.up;
    case "Down":
        return KeyCode.down;
    case "Ins":
        return KeyCode.ins;
    case "Del":
        return KeyCode.del;
    case "[":
        return KeyCode.bracketOpen;
    case "]":
        return KeyCode.bracketClose;
    case ",":
        return KeyCode.comma;
    case ".":
        return KeyCode.period;
    case "Backspace":
        return KeyCode.backspace;
    case "Enter":
        return KeyCode.enter;
    case "Space":
        return KeyCode.space;
    default:
        return 0;
    }
}

/**
    Converts KeyCode enum value to human readable key name

    For unknown key code, prints its hex value.
*/
string keyName(uint keyCode) pure
{
    switch (keyCode)
    {
    case KeyCode.A:
        return "A";
    case KeyCode.B:
        return "B";
    case KeyCode.C:
        return "C";
    case KeyCode.D:
        return "D";
    case KeyCode.E:
        return "E";
    case KeyCode.F:
        return "F";
    case KeyCode.G:
        return "G";
    case KeyCode.H:
        return "H";
    case KeyCode.I:
        return "I";
    case KeyCode.J:
        return "J";
    case KeyCode.K:
        return "K";
    case KeyCode.L:
        return "L";
    case KeyCode.M:
        return "M";
    case KeyCode.N:
        return "N";
    case KeyCode.O:
        return "O";
    case KeyCode.P:
        return "P";
    case KeyCode.Q:
        return "Q";
    case KeyCode.R:
        return "R";
    case KeyCode.S:
        return "S";
    case KeyCode.T:
        return "T";
    case KeyCode.U:
        return "U";
    case KeyCode.V:
        return "V";
    case KeyCode.W:
        return "W";
    case KeyCode.X:
        return "X";
    case KeyCode.Y:
        return "Y";
    case KeyCode.Z:
        return "Z";
    case KeyCode.alpha0:
        return "0";
    case KeyCode.alpha1:
        return "1";
    case KeyCode.alpha2:
        return "2";
    case KeyCode.alpha3:
        return "3";
    case KeyCode.alpha4:
        return "4";
    case KeyCode.alpha5:
        return "5";
    case KeyCode.alpha6:
        return "6";
    case KeyCode.alpha7:
        return "7";
    case KeyCode.alpha8:
        return "8";
    case KeyCode.alpha9:
        return "9";
    case KeyCode.divide:
        return "/";
    case KeyCode.multiply:
        return "*";
    case KeyCode.tab:
        return "Tab";
    case KeyCode.F1:
        return "F1";
    case KeyCode.F2:
        return "F2";
    case KeyCode.F3:
        return "F3";
    case KeyCode.F4:
        return "F4";
    case KeyCode.F5:
        return "F5";
    case KeyCode.F6:
        return "F6";
    case KeyCode.F7:
        return "F7";
    case KeyCode.F8:
        return "F8";
    case KeyCode.F9:
        return "F9";
    case KeyCode.F10:
        return "F10";
    case KeyCode.F11:
        return "F11";
    case KeyCode.F12:
        return "F12";
    case KeyCode.F13:
        return "F13";
    case KeyCode.F14:
        return "F14";
    case KeyCode.F15:
        return "F15";
    case KeyCode.F16:
        return "F16";
    case KeyCode.F17:
        return "F17";
    case KeyCode.F18:
        return "F18";
    case KeyCode.F19:
        return "F19";
    case KeyCode.F20:
        return "F20";
    case KeyCode.F21:
        return "F21";
    case KeyCode.F22:
        return "F22";
    case KeyCode.F23:
        return "F23";
    case KeyCode.F24:
        return "F24";
    case KeyCode.pageUp:
        return "PageUp";
    case KeyCode.pageDown:
        return "PageDown";
    case KeyCode.home:
        return "Home";
    case KeyCode.end:
        return "End";
    case KeyCode.left:
        return "Left";
    case KeyCode.right:
        return "Right";
    case KeyCode.up:
        return "Up";
    case KeyCode.down:
        return "Down";
    case KeyCode.ins:
        return "Ins";
    case KeyCode.del:
        return "Del";
    case KeyCode.bracketOpen:
        return "[";
    case KeyCode.bracketClose:
        return "]";
    case KeyCode.backspace:
        return "Backspace";
    case KeyCode.space:
        return "Space";
    case KeyCode.enter:
        return "Enter";
    case KeyCode.add:
        return ` "+"`;
    case KeyCode.subtract:
        return ` "-"`;
    default:
        return format("0x%08x", keyCode);
    }
}

/// Base class for custom events
class CustomEvent
{
    protected
    {
        int _id;
        uint _uniqueID;

        static __gshared uint _uniqueIDGenerator;

        WeakRef!Widget _destinationWidget;
        Object _objectParam;
        int _intParam;
    }

    this(int ID)
    {
        _id = ID;
        _uniqueID = ++_uniqueIDGenerator;
    }

    @property
    {
        // event id
        int id() const
        {
            return _id;
        }

        uint uniqueID() const
        {
            return _uniqueID;
        }

        WeakRef!Widget destinationWidget()
        {
            return _destinationWidget;
        }

        Object objectParam()
        {
            return _objectParam;
        }
        CustomEvent objectParam(Object value)
        {
            _objectParam = value;
            return this;
        }

        int intParam() const
        {
            return _intParam;
        }
        CustomEvent intParam(int value)
        {
            _intParam = value;
            return this;
        }
    }
}

immutable int CUSTOM_RUNNABLE = 1;

/// Operation to execute (usually sent from background threads to run some code in UI thread)
class RunnableEvent : CustomEvent
{
    protected void delegate() _action;

    this(int ID, WeakRef!Widget destinationWidget, void delegate() action)
    {
        super(ID);
        _destinationWidget = destinationWidget;
        _action = action;
    }

    void run()
    {
        _action();
    }
}

/**
Queue destroy event.

This event allows delayed widget destruction and is used internally by
$(LINK2 $(DDOX_ROOT_DIR)beamui/platforms/common/platform/Window.queueWidgetDestroy.html, Window.queueWidgetDestroy()).
*/
class QueueDestroyEvent : RunnableEvent
{
    private Widget _widgetToDestroy;

    this(Widget widgetToDestroy)
    {
        _widgetToDestroy = widgetToDestroy;
        super(1, WeakRef!Widget(null), delegate void() {
            if (_widgetToDestroy.parent)
                _widgetToDestroy.parent.removeChild(_widgetToDestroy);
            destroy(_widgetToDestroy);
        });
    }
}

interface CustomEventTarget
{
    /// Post event to handle in UI thread (this method can be used from background thread)
    void postEvent(CustomEvent event);

    /// Post task to execute in UI thread (this method can be used from background thread)
    void executeInUiThread(void delegate() runnable);
}
