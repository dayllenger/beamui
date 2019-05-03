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
    /// Key code from `Key` enum
    Key key;
    /// Key modifiers bit set
    KeyMods modifiers;

    /// Get shortcut text description. For serialization use `toString` instead
    @property dstring label() const
    {
        dstring buf;
        version (OSX)
        {
            static if (true)
            {
                if (modifiers & KeyMods.control)
                    buf ~= "Ctrl+";
                if (modifiers & KeyMods.shift)
                    buf ~= "Shift+";
                if (modifiers & KeyMods.option)
                    buf ~= "Opt+";
                if (modifiers & KeyMods.command)
                    buf ~= "Cmd+";
            }
            else
            {
                if (modifiers & KeyMods.control)
                    buf ~= "⌃";
                if (modifiers & KeyMods.shift)
                    buf ~= "⇧";
                if (modifiers & KeyMods.option)
                    buf ~= "⌥";
                if (modifiers & KeyMods.command)
                    buf ~= "⌘";
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

    /// Parse accelerator from string
    bool parse(string s)
    {
        import std.string : strip;

        key = Key.none;
        modifiers = KeyMods.none;
        s = s.strip;
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
            s = s.strip;
        }
        key = parseKeyName(s);
        return key != Key.none;
    }
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
    this(dstring label, Key key = Key.none, KeyMods modifiers = KeyMods.none)
    {
        _label = label;
        if (key != Key.none)
            addShortcut(key, modifiers);
        if (label)
            nameMap[id] = this;
    }

    /// Create an action with label, icon ID and, optionally, shortcut
    this(dstring label, string iconID, Key key = Key.none, KeyMods modifiers = KeyMods.none)
    {
        _label = label;
        _iconID = iconID;
        if (key != Key.none)
            addShortcut(key, modifiers);
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
    Action addShortcut(Key key, KeyMods modifiers = KeyMods.none)
    {
        version (OSX)
        {
            if (modifiers & KeyMods.control)
            {
                _shortcuts ~= Shortcut(key, (modifiers & ~KeyMods.control) | KeyMods.command);
            }
        }
        _shortcuts ~= Shortcut(key, modifiers);
        shortcutMap.add(this);
        changed();
        return this;
    }

    /// Returns true if shortcut matches provided key code and flags
    bool hasShortcut(Key key, KeyMods modifiers) const
    {
        foreach (s; _shortcuts)
        {
            if (s.key == key)
            {
                // match, counting left/right if needed
                if ((s.modifiers & KeyMods.common) == (modifiers & KeyMods.common))
                    if ((s.modifiers & modifiers) == s.modifiers)
                        return true;
            }
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
    static Action findByShortcut(Key key, KeyMods modifiers)
    {
        return shortcutMap.find(key, modifiers);
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

    private static immutable KeyMods[] modMasks = [
        KeyMods.lrcontrol | KeyMods.lralt | KeyMods.lrshift | KeyMods.lrmeta,

        KeyMods.lrcontrol | KeyMods.lralt | KeyMods.lrshift | KeyMods.lrmeta,
        KeyMods.lrcontrol | KeyMods.alt | KeyMods.lrshift | KeyMods.lrmeta,
        KeyMods.lrcontrol | KeyMods.lralt | KeyMods.shift | KeyMods.lrmeta,
        KeyMods.lrcontrol | KeyMods.lralt | KeyMods.lrshift | KeyMods.meta,

        KeyMods.control | KeyMods.alt | KeyMods.lrshift | KeyMods.lrmeta,
        KeyMods.control | KeyMods.lralt | KeyMods.shift | KeyMods.lrmeta,
        KeyMods.control | KeyMods.lralt | KeyMods.lrshift | KeyMods.meta,
        KeyMods.lrcontrol | KeyMods.alt | KeyMods.shift | KeyMods.lrmeta,
        KeyMods.lrcontrol | KeyMods.alt | KeyMods.lrshift | KeyMods.meta,
        KeyMods.lrcontrol | KeyMods.lralt | KeyMods.shift | KeyMods.meta,

        KeyMods.control | KeyMods.alt | KeyMods.shift | KeyMods.lrmeta,
        KeyMods.control | KeyMods.alt | KeyMods.lrshift | KeyMods.meta,
        KeyMods.control | KeyMods.lralt | KeyMods.shift | KeyMods.meta,
        KeyMods.lrcontrol | KeyMods.alt | KeyMods.shift | KeyMods.meta,

        KeyMods.control | KeyMods.alt | KeyMods.shift | KeyMods.meta
    ];

    /// Find action by shortcut, returns `null` if not found
    Action find(Key key, KeyMods modifiers)
    {
        Shortcut sc;
        sc.key = key;
        foreach (mask; modMasks)
        {
            sc.modifiers = modifiers & mask;
            if (auto p = sc in _map)
            {
                assert(p.hasShortcut(key, modifiers));
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
