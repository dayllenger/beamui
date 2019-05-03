/**
Input events, actions, codes and flags; custom events.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.events;

import beamui.widgets.widget;

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
    /// Scroll wheel movement
    wheel,
    //hover,    // pointer entered widget which while button was not down (return true to track Hover state)
    /// Pointer left widget which has before processed `move` message, while button was not down
    leave
}

/// Mouse flag bits (mouse buttons and keyboard modifiers) for `MouseEvent`
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

/// Mouse button codes for `MouseEvent`
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
    xbutton1 = MouseFlag.xbutton1,
    /// Additional mouse button 2
    xbutton2 = MouseFlag.xbutton2,
}

/// Converts `MouseButton` to `MouseFlag`
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

/// Mouse button state details for `MouseEvent`
struct ButtonDetails
{
    private
    {
        /// `Clock.currStdTime` for down event of this button (0 if button is up) set after double click to time when first click occured
        long _prevDownTs;
        /// `Clock.currStdTime` for down event of this button (0 if button is up)
        long _downTs;
        /// `Clock.currStdTime` for up event of this button (0 if button is still down)
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
            long ts = std.datetime.Clock.currStdTime;
            return cast(int)(ts - _downTs);
        }
        /// X coordinate of the point where button was pressed down last time
        short downX() const { return _downX; }
        /// Y coordinate of the point where button was pressed down last time
        short downY() const { return _downY; }
        /// Bit set of mouse flags saved on button down
        ushort downFlags() const { return _downFlags; }
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
    private
    {
        /// Timestamp of event
        long _eventTimestamp;
        /// Mouse action code
        MouseAction _action;
        /// Mouse button code for `buttonDown`/`buttonUp`
        MouseButton _button;
        /// x coordinate of pointer
        short _x;
        /// y coordinate of pointer
        short _y;
        /// Flags bit set - usually from `MouseFlag` enum
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
        /// When true, no tracking of mouse on `buttonDown` is necessary
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
        /// Button which caused `buttonDown` or `buttonUp` action
        MouseButton button() const { return _button; }
        /// Action
        MouseAction action() const { return _action; }
        /// Returns flags (buttons and keys state)
        ushort flags() const { return _flags; }
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
        /// Returns delta for `wheel` event
        short wheelDelta() const { return _wheelDelta; }
        /// x coordinate of mouse pointer (relative to window client area)
        short x() const { return _x; }
        /// y coordinate of mouse pointer (relative to window client area)
        short y() const { return _y; }

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

        /// Get event tracking widget to override
        WeakRef!Widget trackingWidget() { return _trackingWidget; }
        /// Mouse button tracking flag
        bool doNotTrackButtonDown() const { return _doNotTrackButtonDown; }
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

/// Keyboard actions for `KeyEvent`
enum KeyAction : uint
{
    keyDown, /// Key is pressed
    keyUp,   /// Key is released
    text,    /// Text is entered
    repeat,  /// Repeated key down
}

/// Keyboard modifier flags for `KeyEvent`
enum KeyMods : uint
{
    none = 0,

    control = 1, /// Ctrl key
    shift = 2, /// Shift key
    alt = 4, /// Alt key
    meta = 8, /// Meta/Win key

    option = alt,
    command = meta,

    /// Modifiers that don't count the difference between left or right
    common = control | shift | alt | meta,

    lcontrol = control | 64, /// Left Ctrl key (includes `control` flag)
    lshift = shift | 64, /// Left Shift key (includes `shift` flag)
    lalt = alt | 64, /// Left Alt key (includes `alt` flag)
    lmeta = meta | 64, /// Left Meta/Win key (includes `meta` flag)

    rcontrol = control | 128, /// Right Ctrl key (includes `control` flag)
    rshift = shift | 128, /// Right Shift key (includes `shift` flag)
    ralt = alt | 128, /// Right Alt key (includes `alt` flag)
    rmeta = meta | 128, /// Right Meta/Win key (includes `meta` flag)

    lrcontrol = lcontrol | rcontrol, /// Both left and right Ctrl key
    lralt = lalt | ralt, /// Both left and right Alt key
    lrshift = lshift | rshift, /// Both left and right Shift key
    lrmeta = lmeta | rmeta, /// Both left and right Meta key
}

/** Key code constants for `KeyEvent`.

    Letters and numeric keys are sorted, so you can write something like
    `Key.A <= key && key <= Key.Z`.

    The constants are very similar to such in WinAPI, to simplify translation.
*/
enum Key : uint
{
    none = 0,
    backspace = 8, /// Backspace
    tab = 9, /// Tab
    enter = 0x0D, /// Return/enter key
    shift = 0x10,  /// Shift
    control = 0x11, /// Ctrl
    alt = 0x12, /// Alt
    pause = 0x13, /// Pause
    caps = 0x14, /// Caps lock
    escape = 0x1B, /// Esc
    space = 0x20, /// Space
    pageUp = 0x21, /// Page up
    pageDown = 0x22, /// Page down
    end = 0x23, /// End
    home = 0x24, /// Home
    left = 0x25, /// Left arrow
    up = 0x26, /// Up arrow
    right = 0x27, /// Right arrow
    down = 0x28, /// Down arrow
    ins = 0x2D, /// Ins
    del = 0x2E, /// Delete
    alpha0 = 0x30, /// 0 on the alphanumeric part of keyboard
    alpha1 = 0x31, /// 1 on the alphanumeric part of keyboard
    alpha2 = 0x32, /// 2 on the alphanumeric part of keyboard
    alpha3 = 0x33, /// 3 on the alphanumeric part of keyboard
    alpha4 = 0x34, /// 4 on the alphanumeric part of keyboard
    alpha5 = 0x35, /// 5 on the alphanumeric part of keyboard
    alpha6 = 0x36, /// 6 on the alphanumeric part of keyboard
    alpha7 = 0x37, /// 7 on the alphanumeric part of keyboard
    alpha8 = 0x38, /// 8 on the alphanumeric part of keyboard
    alpha9 = 0x39, /// 9 on the alphanumeric part of keyboard
    A = 0x41, /// A
    B = 0x42, /// B
    C = 0x43, /// C
    D = 0x44, /// D
    E = 0x45, /// E
    F = 0x46, /// F
    G = 0x47, /// G
    H = 0x48, /// H
    I = 0x49, /// I
    J = 0x4a, /// J
    K = 0x4b, /// K
    L = 0x4c, /// L
    M = 0x4d, /// M
    N = 0x4e, /// N
    O = 0x4f, /// O
    P = 0x50, /// P
    Q = 0x51, /// Q
    R = 0x52, /// R
    S = 0x53, /// S
    T = 0x54, /// T
    U = 0x55, /// U
    V = 0x56, /// V
    W = 0x57, /// W
    X = 0x58, /// X
    Y = 0x59, /// Y
    Z = 0x5a, /// Z
    bracketOpen = 0xDB, /// [
    bracketClose = 0xDD, /// ]
    add = 0x6B, /// +
    subtract = 0x6D, /// -
    multiply = 0x6A, /// *
    divide = 0x6F, /// /
    comma = 0xBC, /// ,
    period = 0xBE, /// .
    lwin = 0x5b, /// Left win key
    rwin = 0x5c, /// Right win key
    num0 = 0x60, /// Numpad 0
    num1 = 0x61, /// Numpad 1
    num2 = 0x62, /// Numpad 2
    num3 = 0x63, /// Numpad 3
    num4 = 0x64, /// Numpad 4
    num5 = 0x65, /// Numpad 5
    num6 = 0x66, /// Numpad 6
    num7 = 0x67, /// Numpad 7
    num8 = 0x68, /// Numpad 8
    num9 = 0x69, /// Numpad 9
    numAdd = 0x6B, /// Numpad +
    numSub = 0x6D, /// Numpad -
    numMul = 0x6A, /// Numpad *
    numDiv = 0x6F, /// Numpad /
    numPeriod = 0x6E, /// Numpad .
    F1 = 0x70, /// F1
    F2 = 0x71, /// F2
    F3 = 0x72, /// F3
    F4 = 0x73, /// F4
    F5 = 0x74, /// F5
    F6 = 0x75, /// F6
    F7 = 0x76, /// F7
    F8 = 0x77, /// F8
    F9 = 0x78, /// F9
    F10 = 0x79, /// F10
    F11 = 0x7a, /// F11
    F12 = 0x7b, /// F12
    F13 = 0x7c, /// F13
    F14 = 0x7d, /// F14
    F15 = 0x7e, /// F15
    F16 = 0x7f, /// F16
    F17 = 0x80, /// F17
    F18 = 0x81, /// F18
    F19 = 0x82, /// F19
    F20 = 0x83, /// F20
    F21 = 0x84, /// F21
    F22 = 0x85, /// F22
    F23 = 0x86, /// F23
    F24 = 0x87, /// F24
    numlock = 0x90, /// Num lock
    scroll = 0x91, /// Scroll lock
    lshift = 0xA0, /// Left shift
    rshift = 0xA1, /// Right shift
    lcontrol = 0xA2, /// Left ctrl
    rcontrol = 0xA3, /// Right ctrl
    lalt = 0xA4, /// Left alt
    ralt = 0xA5, /// Right alt
    //lmenu = 0xA4,
    //rmenu = 0xA5,
    semicolon = 0x201, /// ;
    tilde = 0x202, /// ~
    quote = 0x203, /// '
    slash = 0x204, /// /
    backslash = 0x205, /// \
    equal = 0x206, /// =
}

/// Keyboard event
final class KeyEvent
{
    private
    {
        KeyAction _action;
        Key _key;
        KeyMods _mods;
        dstring _text;
    }

    this(KeyAction action, Key key, KeyMods mods, dstring text = null)
    {
        _action = action;
        _key = key;
        _mods = mods;
        _text = text;
    }

    @property
    {
        /// Key action (keyDown, keyUp, text, repeat)
        KeyAction action() const { return _action; }
        /// Key code from `Key` enum
        Key key() const { return _key; }
        /// Key modifier bit flags (shift, ctrl, alt...)
        KeyMods allModifiers() const { return _mods; }
        /// Entered text, for `text` action
        dstring text() const { return _text; }

        /// Get modifiers, not counting the difference between left or right
        KeyMods modifiers() const
        {
            return _mods & KeyMods.common;
        }
        /// True if has some modifiers applied
        bool hasModifiers() const
        {
            return _mods != KeyMods.none;
        }
    }

    /// Check whether all of `mod` modifiers are applied
    bool alteredBy(KeyMods mod) const
    {
        return (_mods & mod) == mod;
    }

    override string toString() const
    {
        return format("KeyEvent(%s, %s, %04x, %s)", _action, _key, _mods, _text);
    }
}

/// Scroll bar / slider action codes for `ScrollEvent`
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
        ScrollAction action() const { return _action; }
        /// Min value
        int minValue() const { return _minValue; }
        /// Max value
        int maxValue() const { return _maxValue; }
        /// Visible part size
        int pageSize() const { return _pageSize; }
        /// Current position
        int position() const { return _position; }
        /// Returns true if position has been changed using position property setter
        bool positionChanged() const { return _positionChanged; }
        /// Change position in event handler to update slider position
        void position(int newPosition)
        {
            _position = newPosition;
            _positionChanged = true;
        }
    }

    /// Default update position for actions like pageUp/pageDown, lineUp/lineDown
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

/** Convert key name to `Key` enum item.

    For unknown key code, returns `Key.none`.
*/
Key parseKeyName(string name)
{
    alias KeyCode = Key;
    switch (name)
    {
        case "A": case "a": return KeyCode.A;
        case "B": case "b": return KeyCode.B;
        case "C": case "c": return KeyCode.C;
        case "D": case "d": return KeyCode.D;
        case "E": case "e": return KeyCode.E;
        case "F": case "f": return KeyCode.F;
        case "G": case "g": return KeyCode.G;
        case "H": case "h": return KeyCode.H;
        case "I": case "i": return KeyCode.I;
        case "J": case "j": return KeyCode.J;
        case "K": case "k": return KeyCode.K;
        case "L": case "l": return KeyCode.L;
        case "M": case "m": return KeyCode.M;
        case "N": case "n": return KeyCode.N;
        case "O": case "o": return KeyCode.O;
        case "P": case "p": return KeyCode.P;
        case "Q": case "q": return KeyCode.Q;
        case "R": case "r": return KeyCode.R;
        case "S": case "s": return KeyCode.S;
        case "T": case "t": return KeyCode.T;
        case "U": case "u": return KeyCode.U;
        case "V": case "v": return KeyCode.V;
        case "W": case "w": return KeyCode.W;
        case "X": case "x": return KeyCode.X;
        case "Y": case "y": return KeyCode.Y;
        case "Z": case "z": return KeyCode.Z;
        case "0": return KeyCode.alpha0;
        case "1": return KeyCode.alpha1;
        case "2": return KeyCode.alpha2;
        case "3": return KeyCode.alpha3;
        case "4": return KeyCode.alpha4;
        case "5": return KeyCode.alpha5;
        case "6": return KeyCode.alpha6;
        case "7": return KeyCode.alpha7;
        case "8": return KeyCode.alpha8;
        case "9": return KeyCode.alpha9;
        case "[": return KeyCode.bracketOpen;
        case "]": return KeyCode.bracketClose;
        case "+": return KeyCode.add;
        case "-": return KeyCode.subtract;
        case "*": return KeyCode.multiply;
        case "/": return KeyCode.divide;
        case ",": return KeyCode.comma;
        case ".": return KeyCode.period;
        case ";": return KeyCode.semicolon;
        case "~": return KeyCode.tilde;
        case "'": return KeyCode.quote;
        case "\\": return KeyCode.backslash;
        case "=": return KeyCode.equal;
        case "F1": return KeyCode.F1;
        case "F2": return KeyCode.F2;
        case "F3": return KeyCode.F3;
        case "F4": return KeyCode.F4;
        case "F5": return KeyCode.F5;
        case "F6": return KeyCode.F6;
        case "F7": return KeyCode.F7;
        case "F8": return KeyCode.F8;
        case "F9": return KeyCode.F9;
        case "F10": return KeyCode.F10;
        case "F11": return KeyCode.F11;
        case "F12": return KeyCode.F12;
        case "F13": return KeyCode.F13;
        case "F14": return KeyCode.F14;
        case "F15": return KeyCode.F15;
        case "F16": return KeyCode.F16;
        case "F17": return KeyCode.F17;
        case "F18": return KeyCode.F18;
        case "F19": return KeyCode.F19;
        case "F20": return KeyCode.F20;
        case "F21": return KeyCode.F21;
        case "F22": return KeyCode.F22;
        case "F23": return KeyCode.F23;
        case "F24": return KeyCode.F24;
        case "Backspace": return KeyCode.backspace;
        case "Tab": return KeyCode.tab;
        case "Enter": return KeyCode.enter;
        case "Esc": return KeyCode.escape;
        case "Space": return KeyCode.space;
        case "PageUp": return KeyCode.pageUp;
        case "PageDown": return KeyCode.pageDown;
        case "End": return KeyCode.end;
        case "Home": return KeyCode.home;
        case "Left": return KeyCode.left;
        case "Up": return KeyCode.up;
        case "Right": return KeyCode.right;
        case "Down": return KeyCode.down;
        case "Ins": return KeyCode.ins;
        case "Del": return KeyCode.del;
        case "Pause": return KeyCode.pause;
        case "CapsLock": return KeyCode.caps;
        case "NumLock": return KeyCode.numlock;
        case "ScrollLock": return KeyCode.scroll;
        default:
            return Key.none;
    }
}

/** Convert `Key` enum item into a human readable key name.

    For unknown key code, prints its hex value.
*/
string keyName(Key key)
{
    alias KeyCode = Key;
    switch (key)
    {
        case KeyCode.A: return "A";
        case KeyCode.B: return "B";
        case KeyCode.C: return "C";
        case KeyCode.D: return "D";
        case KeyCode.E: return "E";
        case KeyCode.F: return "F";
        case KeyCode.G: return "G";
        case KeyCode.H: return "H";
        case KeyCode.I: return "I";
        case KeyCode.J: return "J";
        case KeyCode.K: return "K";
        case KeyCode.L: return "L";
        case KeyCode.M: return "M";
        case KeyCode.N: return "N";
        case KeyCode.O: return "O";
        case KeyCode.P: return "P";
        case KeyCode.Q: return "Q";
        case KeyCode.R: return "R";
        case KeyCode.S: return "S";
        case KeyCode.T: return "T";
        case KeyCode.U: return "U";
        case KeyCode.V: return "V";
        case KeyCode.W: return "W";
        case KeyCode.X: return "X";
        case KeyCode.Y: return "Y";
        case KeyCode.Z: return "Z";
        case KeyCode.alpha0: return "0";
        case KeyCode.alpha1: return "1";
        case KeyCode.alpha2: return "2";
        case KeyCode.alpha3: return "3";
        case KeyCode.alpha4: return "4";
        case KeyCode.alpha5: return "5";
        case KeyCode.alpha6: return "6";
        case KeyCode.alpha7: return "7";
        case KeyCode.alpha8: return "8";
        case KeyCode.alpha9: return "9";
        case KeyCode.bracketOpen: return "[";
        case KeyCode.bracketClose: return "]";
        case KeyCode.add: return ` "+"`;
        case KeyCode.subtract: return ` "-"`;
        case KeyCode.multiply: return "*";
        case KeyCode.divide: return "/";
        case KeyCode.comma: return ",";
        case KeyCode.period: return ".";
        case KeyCode.semicolon: return ";";
        case KeyCode.tilde: return "~";
        case KeyCode.quote: return "'";
        case KeyCode.backslash: return "\\";
        case KeyCode.equal: return "=";
        case KeyCode.F1: return "F1";
        case KeyCode.F2: return "F2";
        case KeyCode.F3: return "F3";
        case KeyCode.F4: return "F4";
        case KeyCode.F5: return "F5";
        case KeyCode.F6: return "F6";
        case KeyCode.F7: return "F7";
        case KeyCode.F8: return "F8";
        case KeyCode.F9: return "F9";
        case KeyCode.F10: return "F10";
        case KeyCode.F11: return "F11";
        case KeyCode.F12: return "F12";
        case KeyCode.F13: return "F13";
        case KeyCode.F14: return "F14";
        case KeyCode.F15: return "F15";
        case KeyCode.F16: return "F16";
        case KeyCode.F17: return "F17";
        case KeyCode.F18: return "F18";
        case KeyCode.F19: return "F19";
        case KeyCode.F20: return "F20";
        case KeyCode.F21: return "F21";
        case KeyCode.F22: return "F22";
        case KeyCode.F23: return "F23";
        case KeyCode.F24: return "F24";
        case KeyCode.backspace: return "Backspace";
        case KeyCode.tab: return "Tab";
        case KeyCode.enter: return "Enter";
        case KeyCode.escape: return "Esc";
        case KeyCode.space: return "Space";
        case KeyCode.pageUp: return "PageUp";
        case KeyCode.pageDown: return "PageDown";
        case KeyCode.end: return "End";
        case KeyCode.home: return "Home";
        case KeyCode.left: return "Left";
        case KeyCode.up: return "Up";
        case KeyCode.right: return "Right";
        case KeyCode.down: return "Down";
        case KeyCode.ins: return "Ins";
        case KeyCode.del: return "Del";
        case KeyCode.pause: return "Pause";
        case KeyCode.caps: return "CapsLock";
        case KeyCode.numlock: return "NumLock";
        case KeyCode.scroll: return "ScrollLock";
        default:
            return format("0x%08x", key);
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
        int id() const { return _id; }

        uint uniqueID() const { return _uniqueID; }

        WeakRef!Widget destinationWidget() { return _destinationWidget; }

        Object objectParam() { return _objectParam; }
        /// ditto
        void objectParam(Object value)
        {
            _objectParam = value;
        }

        int intParam() const { return _intParam; }
        /// ditto
        void intParam(int value)
        {
            _intParam = value;
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
