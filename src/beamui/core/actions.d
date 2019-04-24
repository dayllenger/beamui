/**
Shortcuts and actions.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.core.actions;

public import beamui.core.events;
import beamui.core.collections;
import beamui.core.functions;
import beamui.core.ownership;
import beamui.core.signals;
import beamui.widgets.widget : Widget;

/// Keyboard shortcut (key + modifiers)
struct Shortcut
{
    /// Key code, usually one of `KeyCode` enum items
    uint keyCode;
    /// Key flags bit set, usually one of `KeyFlag` enum items
    uint keyFlags;

    /// Returns accelerator text description
    @property dstring label() const
    {
        dstring buf;
        version (OSX)
        {
            static if (true)
            {
                if (keyFlags & KeyFlag.control)
                    buf ~= "Ctrl+";
                if (keyFlags & KeyFlag.shift)
                    buf ~= "Shift+";
                if (keyFlags & KeyFlag.option)
                    buf ~= "Opt+";
                if (keyFlags & KeyFlag.command)
                    buf ~= "Cmd+";
            }
            else
            {
                if (keyFlags & KeyFlag.control)
                    buf ~= "⌃";
                if (keyFlags & KeyFlag.shift)
                    buf ~= "⇧";
                if (keyFlags & KeyFlag.option)
                    buf ~= "⌥";
                if (keyFlags & KeyFlag.command)
                    buf ~= "⌘";
            }
            buf ~= toUTF32(keyName(keyCode));
        }
        else
        {
            if ((keyFlags & KeyFlag.lcontrol) == KeyFlag.lcontrol && (keyFlags & KeyFlag.rcontrol) == KeyFlag.rcontrol)
                buf ~= "LCtrl+RCtrl+";
            else if ((keyFlags & KeyFlag.lcontrol) == KeyFlag.lcontrol)
                buf ~= "LCtrl+";
            else if ((keyFlags & KeyFlag.rcontrol) == KeyFlag.rcontrol)
                buf ~= "RCtrl+";
            else if (keyFlags & KeyFlag.control)
                buf ~= "Ctrl+";
            if ((keyFlags & KeyFlag.lalt) == KeyFlag.lalt && (keyFlags & KeyFlag.ralt) == KeyFlag.ralt)
                buf ~= "LAlt+RAlt+";
            else if ((keyFlags & KeyFlag.lalt) == KeyFlag.lalt)
                buf ~= "LAlt+";
            else if ((keyFlags & KeyFlag.ralt) == KeyFlag.ralt)
                buf ~= "RAlt+";
            else if (keyFlags & KeyFlag.alt)
                buf ~= "Alt+";
            if ((keyFlags & KeyFlag.lshift) == KeyFlag.lshift && (keyFlags & KeyFlag.rshift) == KeyFlag.rshift)
                buf ~= "LShift+RShift+";
            else if ((keyFlags & KeyFlag.lshift) == KeyFlag.lshift)
                buf ~= "LShift+";
            else if ((keyFlags & KeyFlag.rshift) == KeyFlag.rshift)
                buf ~= "RShift+";
            else if (keyFlags & KeyFlag.shift)
                buf ~= "Shift+";
            if ((keyFlags & KeyFlag.lmenu) == KeyFlag.lmenu && (keyFlags & KeyFlag.rmenu) == KeyFlag.rmenu)
                buf ~= "LMenu+RMenu+";
            else if ((keyFlags & KeyFlag.lmenu) == KeyFlag.lmenu)
                buf ~= "LMenu+";
            else if ((keyFlags & KeyFlag.rmenu) == KeyFlag.rmenu)
                buf ~= "RMenu+";
            else if (keyFlags & KeyFlag.menu)
                buf ~= "Menu+";
            buf ~= toUTF32(keyName(keyCode));
        }
        return cast(dstring)buf;
    }

    /// Serialize accelerator text description
    string toString() const
    {
        char[] buf;
        // ctrl
        if ((keyFlags & KeyFlag.lcontrol) == KeyFlag.lcontrol && (keyFlags & KeyFlag.rcontrol) == KeyFlag.rcontrol)
            buf ~= "LCtrl+RCtrl+";
        else if ((keyFlags & KeyFlag.lcontrol) == KeyFlag.lcontrol)
            buf ~= "LCtrl+";
        else if ((keyFlags & KeyFlag.rcontrol) == KeyFlag.rcontrol)
            buf ~= "RCtrl+";
        else if (keyFlags & KeyFlag.control)
            buf ~= "Ctrl+";
        // alt
        if ((keyFlags & KeyFlag.lalt) == KeyFlag.lalt && (keyFlags & KeyFlag.ralt) == KeyFlag.ralt)
            buf ~= "LAlt+RAlt+";
        else if ((keyFlags & KeyFlag.lalt) == KeyFlag.lalt)
            buf ~= "LAlt+";
        else if ((keyFlags & KeyFlag.ralt) == KeyFlag.ralt)
            buf ~= "RAlt+";
        else if (keyFlags & KeyFlag.alt)
            buf ~= "Alt+";
        // shift
        if ((keyFlags & KeyFlag.lshift) == KeyFlag.lshift && (keyFlags & KeyFlag.rshift) == KeyFlag.rshift)
            buf ~= "LShift+RShift+";
        else if ((keyFlags & KeyFlag.lshift) == KeyFlag.lshift)
            buf ~= "LShift+";
        else if ((keyFlags & KeyFlag.rshift) == KeyFlag.rshift)
            buf ~= "RShift+";
        else if (keyFlags & KeyFlag.shift)
            buf ~= "Shift+";
        // menu
        if ((keyFlags & KeyFlag.lmenu) == KeyFlag.lmenu && (keyFlags & KeyFlag.rmenu) == KeyFlag.rmenu)
            buf ~= "LMenu+RMenu+";
        else if ((keyFlags & KeyFlag.lmenu) == KeyFlag.lmenu)
            buf ~= "LMenu+";
        else if ((keyFlags & KeyFlag.rmenu) == KeyFlag.rmenu)
            buf ~= "RMenu+";
        else if (keyFlags & KeyFlag.menu)
            buf ~= "Menu+";
        buf ~= keyName(keyCode);
        return cast(string)buf;
    }

    /// Parse accelerator from string
    bool parse(string s)
    {
        import std.string : strip;

        keyCode = 0;
        keyFlags = 0;
        s = s.strip;
        while (true)
        {
            bool flagFound;
            if (s.startsWith("Ctrl+"))
            {
                keyFlags |= KeyFlag.control;
                s = s[5 .. $];
                flagFound = true;
            }
            if (s.startsWith("LCtrl+"))
            {
                keyFlags |= KeyFlag.lcontrol;
                s = s[5 .. $];
                flagFound = true;
            }
            if (s.startsWith("RCtrl+"))
            {
                keyFlags |= KeyFlag.rcontrol;
                s = s[5 .. $];
                flagFound = true;
            }
            if (s.startsWith("Alt+"))
            {
                keyFlags |= KeyFlag.alt;
                s = s[4 .. $];
                flagFound = true;
            }
            if (s.startsWith("LAlt+"))
            {
                keyFlags |= KeyFlag.lalt;
                s = s[4 .. $];
                flagFound = true;
            }
            if (s.startsWith("RAlt+"))
            {
                keyFlags |= KeyFlag.ralt;
                s = s[4 .. $];
                flagFound = true;
            }
            if (s.startsWith("Shift+"))
            {
                keyFlags |= KeyFlag.shift;
                s = s[6 .. $];
                flagFound = true;
            }
            if (s.startsWith("LShift+"))
            {
                keyFlags |= KeyFlag.lshift;
                s = s[6 .. $];
                flagFound = true;
            }
            if (s.startsWith("RShift+"))
            {
                keyFlags |= KeyFlag.rshift;
                s = s[6 .. $];
                flagFound = true;
            }
            if (s.startsWith("Menu+"))
            {
                keyFlags |= KeyFlag.menu;
                s = s[5 .. $];
                flagFound = true;
            }
            if (s.startsWith("LMenu+"))
            {
                keyFlags |= KeyFlag.lmenu;
                s = s[5 .. $];
                flagFound = true;
            }
            if (s.startsWith("RMenu+"))
            {
                keyFlags |= KeyFlag.rmenu;
                s = s[5 .. $];
                flagFound = true;
            }
            if (!flagFound)
                break;
            s = s.strip;
        }
        keyCode = parseKeyName(s);
        return keyCode != 0;
    }
}

/// Match key flags
bool matchKeyFlags(uint eventFlags, uint requestedFlags)
{
    if (eventFlags == requestedFlags)
        return true;
    if ((requestedFlags & KeyFlag.rcontrol) == KeyFlag.rcontrol && (eventFlags & KeyFlag.rcontrol) != KeyFlag.rcontrol)
        return false;
    if ((requestedFlags & KeyFlag.lcontrol) == KeyFlag.lcontrol && (eventFlags & KeyFlag.lcontrol) != KeyFlag.lcontrol)
        return false;
    if ((requestedFlags & KeyFlag.rshift) == KeyFlag.rshift && (eventFlags & KeyFlag.rshift) != KeyFlag.rshift)
        return false;
    if ((requestedFlags & KeyFlag.lshift) == KeyFlag.lshift && (eventFlags & KeyFlag.lshift) != KeyFlag.lshift)
        return false;
    if ((requestedFlags & KeyFlag.ralt) == KeyFlag.ralt && (eventFlags & KeyFlag.ralt) != KeyFlag.ralt)
        return false;
    if ((requestedFlags & KeyFlag.lalt) == KeyFlag.lalt && (eventFlags & KeyFlag.lalt) != KeyFlag.lalt)
        return false;
    if ((requestedFlags & KeyFlag.rmenu) == KeyFlag.rmenu && (eventFlags & KeyFlag.rmenu) != KeyFlag.rmenu)
        return false;
    if ((requestedFlags & KeyFlag.lmenu) == KeyFlag.lmenu && (eventFlags & KeyFlag.lmenu) != KeyFlag.lmenu)
        return false;
    if ((requestedFlags & KeyFlag.control) == KeyFlag.control && (eventFlags & KeyFlag.control) != KeyFlag.control)
        return false;
    if ((requestedFlags & KeyFlag.shift) == KeyFlag.shift && (eventFlags & KeyFlag.shift) != KeyFlag.shift)
        return false;
    if ((requestedFlags & KeyFlag.alt) == KeyFlag.alt && (eventFlags & KeyFlag.alt) != KeyFlag.alt)
        return false;
    if ((requestedFlags & KeyFlag.menu) == KeyFlag.menu && (eventFlags & KeyFlag.menu) != KeyFlag.menu)
        return false;
    return true;
}

/// Defines where the user can invoke the action
enum ActionContext
{
    widget, /// Only in associated widget, when it has focus
    widgetTree, /// In the widget and its children
    window, /// In a window the widget belongs
    application /// In the whole application (modal windows will not pass shortcuts, though)
}

/// Action state bit flags
enum ActionState
{
    enabled = 1,
    visible = 2,
    checked = 4
}

/**
    UI action, used in menus, toolbars, etc.

    Actions are stored globally, and you can fetch them with `findBy*` functions.
*/
final class Action
{
    @property
    {
        string id() const
        {
            return _label.toUTF8;
        }

        /// Label unicode string to show in UI
        dstring label() const { return _label; }
        /// ditto
        void label(dstring text)
        {
            _label = text;
            changed();
        }

        /// Icon resource id
        string iconID() const { return _iconID; }
        /// ditto
        void iconID(string id)
        {
            _iconID = id;
            changed();
        }

        /// Array of shortcuts
        inout(Shortcut)[] shortcuts() inout { return _shortcuts; }
        /// ditto
        void shortcuts(Shortcut[] ss)
        {
            shortcutMap.remove(_shortcuts);
            _shortcuts = ss;
            shortcutMap.add(this);
            changed();
        }
        /// Returns text description for the first shortcut of action; `null` if no shortcuts
        dstring shortcutText() const
        {
            if (_shortcuts.length > 0)
                return _shortcuts[0].label;
            else
                return null;
        }

        /// Returns tooltip text for action
        dstring tooltipText() const
        {
            dchar[] buf;
            // strip out & characters
            foreach (ch; label)
            {
                if (ch != '&')
                    buf ~= ch;
            }
            dstring sc = shortcutText;
            if (sc.length > 0)
            {
                buf ~= " ("d;
                buf ~= sc;
                buf ~= ")"d;
            }
            return cast(dstring)buf;
        }

        /// Action context; default is `ActionContext.window`
        ActionContext context() const { return _context; }
        /// ditto
        void context(ActionContext ac)
        {
            _context = ac;
            changed();
        }

        /// When false, action cannot be called and control showing this action should be disabled
        bool enabled() const
        {
            return (_state & ActionState.enabled) != 0;
        }
        /// ditto
        void enabled(bool flag)
        {
            auto newstate = flag ? (_state | ActionState.enabled) : (_state & ~ActionState.enabled);
            if (_state != newstate)
            {
                _state = newstate;
                stateChanged();
            }
        }

        /// When false, control showing this action should be hidden
        bool visible() const
        {
            return (_state & ActionState.visible) != 0;
        }
        /// ditto
        void visible(bool flag)
        {
            auto newstate = flag ? (_state | ActionState.visible) : (_state & ~ActionState.visible);
            if (_state != newstate)
            {
                _state = newstate;
                stateChanged();
            }
        }

        /// When true, action is intended to use with checkbox/radiobutton-like controls
        bool checkable() const { return _checkable; }
        /// ditto
        void checkable(bool flag)
        {
            if (_checkable != flag)
            {
                _checkable = flag;
                changed();
            }
        }

        /// When true, this action is included to a group of radio actions
        bool isRadio() const
        {
            return actionGroup !is null;
        }

        /// When true, checkbox/radiobutton-like controls should be shown as checked
        bool checked() const
        {
            return (_state & ActionState.checked) != 0;
        }
        /// ditto
        void checked(bool flag)
        {
            auto newstate = flag ? (_state | ActionState.checked) : (_state & ~ActionState.checked);
            if (_state != newstate)
            {
                _state = newstate;
                stateChanged();
            }
        }
    }

    /// Chained version of `enabled`
    Action setEnabled(bool flag)
    {
        enabled = flag;
        return this;
    }
    /// Chained version of `visible`
    Action setVisible(bool flag)
    {
        visible = flag;
        return this;
    }
    /// Chained version of `checkable`
    Action setCheckable(bool flag)
    {
        checkable = flag;
        return this;
    }
    /// Chained version of `checked`
    Action setChecked(bool flag)
    {
        checked = flag;
        return this;
    }

    /// Signals when action is called
    Signal!(void delegate()) triggered;
    /// Signals when action content is changed
    Signal!(void delegate()) changed;
    /// Signals when action state is changed
    Signal!(void delegate()) stateChanged;

    private
    {
        void delegate()[WeakRef!Widget] receivers;

        dstring _label;
        string _iconID;
        Shortcut[] _shortcuts;
        ActionContext _context = ActionContext.window;

        bool _checkable;
        ActionState _state = ActionState.enabled | ActionState.visible;

        static struct ActionGroup
        {
            private Action[] actions;

            /// Check an action and uncheck others
            void check(Action what)
            {
                foreach (a; actions)
                {
                    a.checked = a is what;
                }
            }

            /// Remove action from group
            void remove(Action what)
            {
                foreach (ref a; actions)
                    if (a is what)
                        a = null;
                actions = actions.remove!(a => a is null);
            }
        }
        ActionGroup* actionGroup;

        static Action[string] nameMap;
        static ActionShortcutMap shortcutMap;
    }

    /// Create an action with label and, optionally, shortcut
    this(dstring label, uint keyCode = 0, uint keyFlags = 0)
    {
        _label = label;
        if (keyCode)
            addShortcut(keyCode, keyFlags);
        if (label)
            nameMap[id] = this;
    }

    /// Create an action with label, icon ID and, optionally, shortcut
    this(dstring label, string iconID, uint keyCode = 0, uint keyFlags = 0)
    {
        _label = label;
        _iconID = iconID;
        if (keyCode)
            addShortcut(keyCode, keyFlags);
        if (label)
            nameMap[id] = this;
    }

    ~this()
    {
        if (actionGroup)
            actionGroup.remove(this);
    }

    /// Group actions to make them react as radio buttons
    static void groupActions(Action[] actions...)
    {
        auto gr = new ActionGroup(actions);
        foreach (a; actions)
        {
            a.actionGroup = gr;
            a.changed();
        }
    }

    /// Add one more shortcut
    Action addShortcut(uint keyCode, uint keyFlags = 0)
    {
        version (OSX)
        {
            if (keyFlags & KeyFlag.control)
            {
                _shortcuts ~= Shortcut(keyCode, (keyFlags & ~KeyFlag.control) | KeyFlag.command);
            }
        }
        _shortcuts ~= Shortcut(keyCode, keyFlags);
        shortcutMap.add(this);
        changed();
        return this;
    }

    /// Returns true if shortcut matches provided key code and flags
    bool hasShortcut(uint keyCode, uint keyFlags) const
    {
        foreach (s; _shortcuts)
        {
            if (s.keyCode == keyCode && matchKeyFlags(keyFlags, s.keyFlags))
                return true;
        }
        return false;
    }

    /// Assign a delegate and a widget, which will be used to determine action context
    void bind(Widget parent, void delegate() func)
    {
        if (func)
        {
            if (parent)
            {
                receivers[weakRef(parent)] = func;
            }
            else
            {
                receivers[WeakRef!Widget.init] = func;
                context = ActionContext.application;
            }
        }
    }

    /// Unbind action from the widget, if action is associated with it
    void unbind(Widget parent)
    {
        receivers.remove(weakRef(parent));
    }

    /// Process the action
    bool call(bool delegate(Widget) chooser)
    {
        assert(chooser !is null);
        // do not call deactivated action
        if (!enabled)
            return false;

        foreach (wt, slot; receivers)
        {
            if (wt.isNull)
            {
                // clean up destroyed widgets
                receivers.remove(wt);
                continue;
            }
            if (chooser(wt))
            {
                // check/uncheck
                if (checkable)
                {
                    if (actionGroup)
                        actionGroup.check(this);
                    else
                        checked = !checked;
                }
                // call chosen delegate
                slot();
                triggered();
                return true;
            }
        }
        return false;
    }

    override string toString() const
    {
        return "Action `" ~ to!string(_label) ~ "`";
    }

    /// Find action globally by its id
    static Action findByName(string name)
    {
        return nameMap.get(name, null);
    }

    /// Find action globally by a shortcut
    static Action findByShortcut(uint keyCode, uint keyFlags)
    {
        return shortcutMap.find(keyCode, keyFlags);
    }
}

/// `Shortcut` to `Action` map
struct ActionShortcutMap
{
    protected Action[Shortcut] _map;

    /// Add actions
    void add(Action[] items...)
    {
        foreach (a; items)
        {
            foreach (sc; a.shortcuts)
                _map[sc] = a;
        }
    }

    /// Remove actions by shortcut list
    void remove(Shortcut[] shortcuts...)
    {
        foreach (sc; shortcuts)
            _map.remove(sc);
    }

    private static __gshared immutable uint[] flagMasks = [
        KeyFlag.lrcontrol | KeyFlag.lralt | KeyFlag.lrshift | KeyFlag.lrmenu,

        KeyFlag.lrcontrol | KeyFlag.lralt | KeyFlag.lrshift | KeyFlag.lrmenu,
        KeyFlag.lrcontrol | KeyFlag.alt | KeyFlag.lrshift | KeyFlag.lrmenu,
        KeyFlag.lrcontrol | KeyFlag.lralt | KeyFlag.shift | KeyFlag.lrmenu,
        KeyFlag.lrcontrol | KeyFlag.lralt | KeyFlag.lrshift | KeyFlag.menu,

        KeyFlag.control | KeyFlag.alt | KeyFlag.lrshift | KeyFlag.lrmenu,
        KeyFlag.control | KeyFlag.lralt | KeyFlag.shift | KeyFlag.lrmenu,
        KeyFlag.control | KeyFlag.lralt | KeyFlag.lrshift | KeyFlag.menu,
        KeyFlag.lrcontrol | KeyFlag.alt | KeyFlag.shift | KeyFlag.lrmenu,
        KeyFlag.lrcontrol | KeyFlag.alt | KeyFlag.lrshift | KeyFlag.menu,
        KeyFlag.lrcontrol | KeyFlag.lralt | KeyFlag.shift | KeyFlag.menu,

        KeyFlag.control | KeyFlag.alt | KeyFlag.shift | KeyFlag.lrmenu,
        KeyFlag.control | KeyFlag.alt | KeyFlag.lrshift | KeyFlag.menu,
        KeyFlag.control | KeyFlag.lralt | KeyFlag.shift | KeyFlag.menu,
        KeyFlag.lrcontrol | KeyFlag.alt | KeyFlag.shift | KeyFlag.menu,

        KeyFlag.control | KeyFlag.alt | KeyFlag.shift | KeyFlag.menu
    ];

    /// Find action by shortcut, returns `null` if not found
    Action find(uint keyCode, uint flags)
    {
        Shortcut sc;
        sc.keyCode = keyCode;
        foreach (mask; flagMasks)
        {
            sc.keyFlags = flags & mask;
            if (auto p = sc in _map)
            {
                assert(p.hasShortcut(keyCode, flags));
                return *p;
            }
        }
        return null;
    }

    /// Ability to foreach action by shortcut
    int opApply(scope int delegate(ref Action) op)
    {
        int result = 0;
        foreach (ref Shortcut sc; _map.byKey)
        {
            result = op(_map[sc]);

            if (result)
                break;
        }
        return result;
    }
}

// TODO: comments, better names!
interface ActionHolder
{
    @property inout(Action) action() inout;

    protected void updateContent();
    protected void updateState();
}

interface ActionOperator
{
    protected void bindActions();
    protected void unbindActions();
}
