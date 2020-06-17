/**
Actions.

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
import beamui.widgets.widget : Element;

/// Defines where the user can invoke the action
enum ActionContext
{
    widget, /// Only in associated widget, when it has focus
    widgetTree, /// In the widget and its children
    window, /// In a window the widget belongs
    application /// In the whole application (modal windows will not pass shortcuts, though)
}

/// Action state bit flags
private enum ActionState
{
    enabled = 1,
    visible = 2,
    checked = 4
}

/** UI action, used in menus, toolbars, etc.

    Actions are stored globally, and you can fetch them with `findBy*` functions.
*/
final class Action
{
    @property
    {
        string id() const
        {
            return toUTF8(_label);
        }

        /// Label unicode string to show in UI
        dstring label() const { return _label; }

        /// Icon resource id
        string iconID() const { return _iconID; }

        /// Action shortcut, `Shortcut.init` if none
        Shortcut shortcut() const { return _shortcut; }
        /// ditto
        void shortcut(Shortcut sc)
        {
            shortcutMap.remove(_shortcut);
            _shortcut = sc;
            shortcutMap.add(this);
            onChange();
        }
        /// Returns text description for the action shortcut, `null` if none
        dstring shortcutText() const
        {
            return _shortcut != Shortcut.init ? _shortcut.label : null;
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
            onChange();
        }

        /// When false, action cannot be called and control showing this action should be disabled
        bool enabled() const
        {
            return (_state & ActionState.enabled) != 0;
        }
        /// ditto
        void enabled(bool flag)
        {
            const newstate = flag ? (_state | ActionState.enabled) : (_state & ~ActionState.enabled);
            if (_state != newstate)
            {
                _state = newstate;
                onStateChange();
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
            const newstate = flag ? (_state | ActionState.visible) : (_state & ~ActionState.visible);
            if (_state != newstate)
            {
                _state = newstate;
                onStateChange();
            }
        }

        /// When true, action is intended to use with checkbox/radiobutton-like controls
        bool checkable() const { return _checkable; }

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
            const newstate = flag ? (_state | ActionState.checked) : (_state & ~ActionState.checked);
            if (_state != newstate)
            {
                _state = newstate;
                onStateChange();
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
    /// Chained version of `checked`
    Action setChecked(bool flag)
    {
        checked = flag;
        return this;
    }

    /// Signals when action is called
    Signal!(void delegate()) onCall;
    /// Signals when action content is changed
    Signal!(void delegate()) onChange;
    /// Signals when action state is changed
    Signal!(void delegate()) onStateChange;

    private
    {
        void delegate()[WeakRef!Element] receivers;

        dstring _label;
        string _iconID;
        bool _checkable;
        Shortcut _shortcut;

        ActionContext _context = ActionContext.window;
        ActionState _state = ActionState.enabled | ActionState.visible;

        static struct ActionGroup
        {
            private Action[] actions;

            /// Check an action and uncheck others
            void check(Action that)
            {
                foreach (a; actions)
                {
                    a.checked = that is a;
                }
            }

            /// Remove action from group
            void remove(Action that)
            {
                foreach (ref a; actions)
                    if (that is a)
                        a = null;
                actions = actions.remove!(a => a is null);
            }
        }
        ActionGroup* actionGroup;

        static Action[string] nameMap;
        static ActionShortcutMap shortcutMap;
    }

    /// Create an action. All parameters are optional
    this(dstring label, Key key = Key.none, KeyMods modifiers = KeyMods.none)
    {
        _label = label;
        _shortcut = Shortcut(key, modifiers);
        shortcutMap.add(this);
        if (label)
            nameMap[id] = this;
    }
    /// ditto
    this(dstring label, string iconID, Key key = Key.none, KeyMods modifiers = KeyMods.none)
    {
        _label = label;
        _iconID = iconID;
        _shortcut = Shortcut(key, modifiers);
        shortcutMap.add(this);
        if (label)
            nameMap[id] = this;
    }
    /// Create a checkable action. All parameters are optional
    static Action makeCheckable(dstring label, Key key = Key.none, KeyMods modifiers = KeyMods.none)
    {
        auto a = new Action(label, key, modifiers);
        a._checkable = true;
        return a;
    }
    /// ditto
    static Action makeCheckable(dstring label, string iconID, Key key = Key.none, KeyMods modifiers = KeyMods.none)
    {
        auto a = new Action(label, iconID, key, modifiers);
        a._checkable = true;
        return a;
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
            a.onChange();
        }
    }

    /// Returns true if shortcut matches provided key code and flags
    bool matchShortcut(Key key, KeyMods modifiers) const
    {
        const sc = _shortcut;
        if (sc.key == key)
        {
            // match, counting left/right if needed
            if ((sc.modifiers & KeyMods.common) == (modifiers & KeyMods.common))
                if ((sc.modifiers & modifiers) == sc.modifiers)
                    return true;
        }
        return false;
    }

    /// Assign a delegate and a widget, which will be used to determine action context
    void bind(Element parent, void delegate() func)
    {
        if (func)
        {
            if (parent)
            {
                receivers[weakRef(parent)] = func;
            }
            else
            {
                receivers[WeakRef!Element.init] = func;
                context = ActionContext.application;
            }
        }
    }

    /// Unbind action from the widget, if action is associated with it
    void unbind(Element parent)
    {
        receivers.remove(weakRef(parent));
    }

    /// Process the action
    bool call(scope bool delegate(Element) chooser)
        in(chooser)
    {
        // do not call deactivated action
        if (!enabled)
            return false;

        foreach (wt, slot; receivers)
        {
            const matched = chooser(wt.get);
            if (!wt)
            {
                // clean up destroyed widgets
                receivers.remove(wt);
            }
            if (matched)
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
                onCall();
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

    /// Add an action
    void add(Action a)
    {
        if (a.shortcut != Shortcut.init)
            _map[a.shortcut] = a;
    }

    /// Remove an action by shortcut
    void remove(Shortcut sc)
    {
        _map.remove(sc);
    }

    static private immutable KeyMods[] modMasks = [
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
                assert(p.matchShortcut(key, modifiers));
                return *p;
            }
        }
        return null;
    }

    /// Ability to foreach action by shortcut
    int opApply(scope int delegate(ref Action) op)
    {
        foreach (sc; _map.byKey)
        {
            if (const result = op(_map[sc]))
                break;
        }
        return 0;
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
