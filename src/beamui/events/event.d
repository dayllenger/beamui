/**
Input events, actions, codes and flags; custom events.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.events;

nothrow:

import beamui.core.functions;
import beamui.core.geometry : Point;
import beamui.core.ownership : WeakRef;
import beamui.widgets.widget : Element;

/// Mouse/touchpad scroll event
final class WheelEvent
{
    nothrow:

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
            return format("WheelEvent(%s, %s, %s, (%s, %s), %s, %s)",
                _deltaX, _deltaY, _deltaZ, _x, _y, _mouseMods, _keyMods);
        catch (Exception)
            return null;
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

        WeakRef!Element _destinationWidget;
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

        WeakRef!Element destinationWidget() { return _destinationWidget; }

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

    this(int ID, WeakRef!Element destinationWidget, void delegate() action)
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
    private Element _widgetToDestroy;

    this(Element widgetToDestroy)
    {
        _widgetToDestroy = widgetToDestroy;
        super(1, WeakRef!Element(null), delegate void() {
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
