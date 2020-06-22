/**
Keyboard shortcuts.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.events.shortcut;

public import beamui.events.keyboard : Key, KeyMods;
import beamui.core.functions;
import beamui.events.keyboard : keyName, parseKeyName;

/// Keyboard shortcut (key + modifiers)
struct Shortcut
{
nothrow:
    /// Key code from `Key` enum
    Key key;
    /// Key modifiers bit set
    KeyMods modifiers;

    /// Get shortcut text description. For serialization use `toString` instead
    @property dstring label() const
    {
        dstring buf;
        version (OSX) // FIXME
        {
            static if (true)
            {
                if (modifiers & KeyMods.control)
                    buf ~= "Command+";
                if (modifiers & KeyMods.shift)
                    buf ~= "Shift+";
                if (modifiers & KeyMods.alt)
                    buf ~= "Option+";
                if (modifiers & KeyMods.meta)
                    buf ~= "Control+";
            }
            else
            {
                if (modifiers & KeyMods.control)
                    buf ~= "⌘+";
                if (modifiers & KeyMods.shift)
                    buf ~= "⇧+";
                if (modifiers & KeyMods.alt)
                    buf ~= "⌥+";
                if (modifiers & KeyMods.meta)
                    buf ~= "⌃+";
            }
            buf ~= toUTF32(keyName(key));
        }
        else
        {
            if ((modifiers & KeyMods.lrcontrol) == KeyMods.lrcontrol)
                buf ~= "LCtrl+RCtrl+";
            else if ((modifiers & KeyMods.lcontrol) == KeyMods.lcontrol)
                buf ~= "LCtrl+";
            else if ((modifiers & KeyMods.rcontrol) == KeyMods.rcontrol)
                buf ~= "RCtrl+";
            else if (modifiers & KeyMods.control)
                buf ~= "Ctrl+";
            if ((modifiers & KeyMods.lralt) == KeyMods.lralt)
                buf ~= "LAlt+RAlt+";
            else if ((modifiers & KeyMods.lalt) == KeyMods.lalt)
                buf ~= "LAlt+";
            else if ((modifiers & KeyMods.ralt) == KeyMods.ralt)
                buf ~= "RAlt+";
            else if (modifiers & KeyMods.alt)
                buf ~= "Alt+";
            if ((modifiers & KeyMods.lrshift) == KeyMods.lrshift)
                buf ~= "LShift+RShift+";
            else if ((modifiers & KeyMods.lshift) == KeyMods.lshift)
                buf ~= "LShift+";
            else if ((modifiers & KeyMods.rshift) == KeyMods.rshift)
                buf ~= "RShift+";
            else if (modifiers & KeyMods.shift)
                buf ~= "Shift+";
            if ((modifiers & KeyMods.lrmeta) == KeyMods.lrmeta)
                buf ~= "LMeta+RMeta+";
            else if ((modifiers & KeyMods.lmeta) == KeyMods.lmeta)
                buf ~= "LMeta+";
            else if ((modifiers & KeyMods.rmeta) == KeyMods.rmeta)
                buf ~= "RMeta+";
            else if (modifiers & KeyMods.meta)
                buf ~= "Meta+";
            buf ~= toUTF32(keyName(key));
        }
        return cast(dstring)buf;
    }

    /// Serialize accelerator text description
    string toString() const
    {
        char[] buf;
        // ctrl
        if ((modifiers & KeyMods.lrcontrol) == KeyMods.lrcontrol)
            buf ~= "LCtrl+RCtrl+";
        else if ((modifiers & KeyMods.lcontrol) == KeyMods.lcontrol)
            buf ~= "LCtrl+";
        else if ((modifiers & KeyMods.rcontrol) == KeyMods.rcontrol)
            buf ~= "RCtrl+";
        else if (modifiers & KeyMods.control)
            buf ~= "Ctrl+";
        // alt
        if ((modifiers & KeyMods.lralt) == KeyMods.lralt)
            buf ~= "LAlt+RAlt+";
        else if ((modifiers & KeyMods.lalt) == KeyMods.lalt)
            buf ~= "LAlt+";
        else if ((modifiers & KeyMods.ralt) == KeyMods.ralt)
            buf ~= "RAlt+";
        else if (modifiers & KeyMods.alt)
            buf ~= "Alt+";
        // shift
        if ((modifiers & KeyMods.lrshift) == KeyMods.lrshift)
            buf ~= "LShift+RShift+";
        else if ((modifiers & KeyMods.lshift) == KeyMods.lshift)
            buf ~= "LShift+";
        else if ((modifiers & KeyMods.rshift) == KeyMods.rshift)
            buf ~= "RShift+";
        else if (modifiers & KeyMods.shift)
            buf ~= "Shift+";
        // meta
        if ((modifiers & KeyMods.lrmeta) == KeyMods.lrmeta)
            buf ~= "LMeta+RMeta+";
        else if ((modifiers & KeyMods.lmeta) == KeyMods.lmeta)
            buf ~= "LMeta+";
        else if ((modifiers & KeyMods.rmeta) == KeyMods.rmeta)
            buf ~= "RMeta+";
        else if (modifiers & KeyMods.meta)
            buf ~= "Meta+";
        buf ~= keyName(key);
        return cast(string)buf;
    }

    /// Parse shortcut from a string
    bool parse(string s)
    {
        import std.string : strip;

        key = Key.none;
        modifiers = KeyMods.none;
        collectException(strip(s), s);
        if (!s.length)
            return false;

        while (true)
        {
            bool found;
            if (s.startsWith("Ctrl+"))
            {
                modifiers |= KeyMods.control;
                s = s[5 .. $];
                found = true;
            }
            if (s.startsWith("LCtrl+"))
            {
                modifiers |= KeyMods.lcontrol;
                s = s[5 .. $];
                found = true;
            }
            if (s.startsWith("RCtrl+"))
            {
                modifiers |= KeyMods.rcontrol;
                s = s[5 .. $];
                found = true;
            }
            if (s.startsWith("Alt+"))
            {
                modifiers |= KeyMods.alt;
                s = s[4 .. $];
                found = true;
            }
            if (s.startsWith("LAlt+"))
            {
                modifiers |= KeyMods.lalt;
                s = s[4 .. $];
                found = true;
            }
            if (s.startsWith("RAlt+"))
            {
                modifiers |= KeyMods.ralt;
                s = s[4 .. $];
                found = true;
            }
            if (s.startsWith("Shift+"))
            {
                modifiers |= KeyMods.shift;
                s = s[6 .. $];
                found = true;
            }
            if (s.startsWith("LShift+"))
            {
                modifiers |= KeyMods.lshift;
                s = s[6 .. $];
                found = true;
            }
            if (s.startsWith("RShift+"))
            {
                modifiers |= KeyMods.rshift;
                s = s[6 .. $];
                found = true;
            }
            if (s.startsWith("Meta+"))
            {
                modifiers |= KeyMods.meta;
                s = s[5 .. $];
                found = true;
            }
            if (s.startsWith("LMeta+"))
            {
                modifiers |= KeyMods.lmeta;
                s = s[5 .. $];
                found = true;
            }
            if (s.startsWith("RMeta+"))
            {
                modifiers |= KeyMods.rmeta;
                s = s[5 .. $];
                found = true;
            }
            if (!found)
                break;
            collectException(strip(s), s);
        }
        key = parseKeyName(s);
        return key != Key.none;
    }
}
