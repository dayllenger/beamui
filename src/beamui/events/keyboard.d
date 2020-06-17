/**
Keyboard events.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.events.keyboard;

/// Keyboard actions for `KeyEvent`
enum KeyAction : uint
{
    keyDown, /// Key is pressed
    keyUp,   /// Key is released
    text,    /// Text is entered
    repeat,  /// Repeated key down
}

/** Keyboard modifier flags for `KeyEvent`.

    Note that on macOS, for better portability, modifiers are converted to their
    Windows/Linux analogs (Command to Ctrl, Option to Alt, and Control to Meta).
*/
enum KeyMods : uint
{
    none = 0,

    control = 1, /// Ctrl key (Command on macOS)
    shift = 2, /// Shift key
    alt = 4, /// Alt key (Option on macOS)
    meta = 8, /// Meta/Win key (Control on macOS)

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
    nothrow:

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
        /// True if has no modifiers applied
        bool noModifiers() const
        {
            return _mods == KeyMods.none;
        }
    }

    /// Check whether all of `mod` modifiers are applied
    bool alteredBy(KeyMods mod) const
    {
        return (_mods & mod) == mod;
    }

    override string toString() const
    {
        try
            return format("KeyEvent(%s, %s, %s, %s)", _action, _key, _mods, _text);
        catch (Exception)
            return null;
    }
}

/** Convert key name to `Key` enum item.

    For unknown key code, returns `Key.none`.
*/
Key parseKeyName(string name)
{
    switch (name)
    {
        case "A": case "a": return Key.A;
        case "B": case "b": return Key.B;
        case "C": case "c": return Key.C;
        case "D": case "d": return Key.D;
        case "E": case "e": return Key.E;
        case "F": case "f": return Key.F;
        case "G": case "g": return Key.G;
        case "H": case "h": return Key.H;
        case "I": case "i": return Key.I;
        case "J": case "j": return Key.J;
        case "K": case "k": return Key.K;
        case "L": case "l": return Key.L;
        case "M": case "m": return Key.M;
        case "N": case "n": return Key.N;
        case "O": case "o": return Key.O;
        case "P": case "p": return Key.P;
        case "Q": case "q": return Key.Q;
        case "R": case "r": return Key.R;
        case "S": case "s": return Key.S;
        case "T": case "t": return Key.T;
        case "U": case "u": return Key.U;
        case "V": case "v": return Key.V;
        case "W": case "w": return Key.W;
        case "X": case "x": return Key.X;
        case "Y": case "y": return Key.Y;
        case "Z": case "z": return Key.Z;
        case "0": return Key.alpha0;
        case "1": return Key.alpha1;
        case "2": return Key.alpha2;
        case "3": return Key.alpha3;
        case "4": return Key.alpha4;
        case "5": return Key.alpha5;
        case "6": return Key.alpha6;
        case "7": return Key.alpha7;
        case "8": return Key.alpha8;
        case "9": return Key.alpha9;
        case "[": return Key.bracketOpen;
        case "]": return Key.bracketClose;
        case "+": return Key.add;
        case "-": return Key.subtract;
        case "*": return Key.multiply;
        case "/": return Key.divide;
        case ",": return Key.comma;
        case ".": return Key.period;
        case ";": return Key.semicolon;
        case "~": return Key.tilde;
        case "'": return Key.quote;
        case "\\": return Key.backslash;
        case "=": return Key.equal;
        case "F1": return Key.F1;
        case "F2": return Key.F2;
        case "F3": return Key.F3;
        case "F4": return Key.F4;
        case "F5": return Key.F5;
        case "F6": return Key.F6;
        case "F7": return Key.F7;
        case "F8": return Key.F8;
        case "F9": return Key.F9;
        case "F10": return Key.F10;
        case "F11": return Key.F11;
        case "F12": return Key.F12;
        case "F13": return Key.F13;
        case "F14": return Key.F14;
        case "F15": return Key.F15;
        case "F16": return Key.F16;
        case "F17": return Key.F17;
        case "F18": return Key.F18;
        case "F19": return Key.F19;
        case "F20": return Key.F20;
        case "F21": return Key.F21;
        case "F22": return Key.F22;
        case "F23": return Key.F23;
        case "F24": return Key.F24;
        case "Backspace": return Key.backspace;
        case "Tab": return Key.tab;
        case "Enter": return Key.enter;
        case "Esc": return Key.escape;
        case "Space": return Key.space;
        case "PageUp": return Key.pageUp;
        case "PageDown": return Key.pageDown;
        case "End": return Key.end;
        case "Home": return Key.home;
        case "Left": return Key.left;
        case "Up": return Key.up;
        case "Right": return Key.right;
        case "Down": return Key.down;
        case "Ins": return Key.ins;
        case "Del": return Key.del;
        case "Pause": return Key.pause;
        case "CapsLock": return Key.caps;
        case "NumLock": return Key.numlock;
        case "ScrollLock": return Key.scroll;
        default:
            return Key.none;
    }
}

/** Convert `Key` enum item into a human readable key name.

    For unknown key code, prints its hex value.
*/
string keyName(Key key)
{
    switch (key)
    {
        case Key.A: return "A";
        case Key.B: return "B";
        case Key.C: return "C";
        case Key.D: return "D";
        case Key.E: return "E";
        case Key.F: return "F";
        case Key.G: return "G";
        case Key.H: return "H";
        case Key.I: return "I";
        case Key.J: return "J";
        case Key.K: return "K";
        case Key.L: return "L";
        case Key.M: return "M";
        case Key.N: return "N";
        case Key.O: return "O";
        case Key.P: return "P";
        case Key.Q: return "Q";
        case Key.R: return "R";
        case Key.S: return "S";
        case Key.T: return "T";
        case Key.U: return "U";
        case Key.V: return "V";
        case Key.W: return "W";
        case Key.X: return "X";
        case Key.Y: return "Y";
        case Key.Z: return "Z";
        case Key.alpha0: return "0";
        case Key.alpha1: return "1";
        case Key.alpha2: return "2";
        case Key.alpha3: return "3";
        case Key.alpha4: return "4";
        case Key.alpha5: return "5";
        case Key.alpha6: return "6";
        case Key.alpha7: return "7";
        case Key.alpha8: return "8";
        case Key.alpha9: return "9";
        case Key.bracketOpen: return "[";
        case Key.bracketClose: return "]";
        case Key.add: return ` "+"`;
        case Key.subtract: return ` "-"`;
        case Key.multiply: return "*";
        case Key.divide: return "/";
        case Key.comma: return ",";
        case Key.period: return ".";
        case Key.semicolon: return ";";
        case Key.tilde: return "~";
        case Key.quote: return "'";
        case Key.backslash: return "\\";
        case Key.equal: return "=";
        case Key.F1: return "F1";
        case Key.F2: return "F2";
        case Key.F3: return "F3";
        case Key.F4: return "F4";
        case Key.F5: return "F5";
        case Key.F6: return "F6";
        case Key.F7: return "F7";
        case Key.F8: return "F8";
        case Key.F9: return "F9";
        case Key.F10: return "F10";
        case Key.F11: return "F11";
        case Key.F12: return "F12";
        case Key.F13: return "F13";
        case Key.F14: return "F14";
        case Key.F15: return "F15";
        case Key.F16: return "F16";
        case Key.F17: return "F17";
        case Key.F18: return "F18";
        case Key.F19: return "F19";
        case Key.F20: return "F20";
        case Key.F21: return "F21";
        case Key.F22: return "F22";
        case Key.F23: return "F23";
        case Key.F24: return "F24";
        case Key.backspace: return "Backspace";
        case Key.tab: return "Tab";
        case Key.enter: return "Enter";
        case Key.escape: return "Esc";
        case Key.space: return "Space";
        case Key.pageUp: return "PageUp";
        case Key.pageDown: return "PageDown";
        case Key.end: return "End";
        case Key.home: return "Home";
        case Key.left: return "Left";
        case Key.up: return "Up";
        case Key.right: return "Right";
        case Key.down: return "Down";
        case Key.ins: return "Ins";
        case Key.del: return "Del";
        case Key.pause: return "Pause";
        case Key.caps: return "CapsLock";
        case Key.numlock: return "NumLock";
        case Key.scroll: return "ScrollLock";
        default:
            try
                return format("0x%08x", key);
            catch (Exception)
                assert(0);
    }
}
