/**
Common definitions for input events and custom events.

Copyright: Vadim Lopatin 2014-2017, Andrzej Kilijański 2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.events.event;

nothrow:

import beamui.core.ownership;
import beamui.widgets.widget : Element;

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
