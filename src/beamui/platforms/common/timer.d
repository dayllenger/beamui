/**


Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.common.timer;

import core.thread;
import core.sync.mutex;
import core.sync.condition;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.ownership;
import beamui.widgets.widget : Widget;

/// Timers queue
class TimerQueue
{
    protected TimerInfo[] queue;

    /// Add new timer, returns timer id
    ulong add(WeakRef!Widget destination, long intervalMillis)
    {
        TimerInfo item = TimerInfo(destination, intervalMillis);
        queue ~= item;
        sort(queue);
        return item.id;
    }

    /// Cancel specified timer
    void cancelTimer(ulong timerID)
    {
        foreach_reverse (ref timer; queue)
        {
            if (timer.id == timerID)
            {
                timer.cancel();
                break;
            }
        }
    }

    /// Returns interval if milliseconds of next scheduled event or -1 if no events queued
    long nextIntervalMillis()
    {
        if (!queue.length || !queue[0].valid)
            return -1;
        return max(queue[0].nextTimestamp - currentTimeMillis, 1);
    }

    /// Returns true if at least one widget was notified
    bool notify()
    {
        cleanup();
        if (!queue.length)
            return false;

        bool result;
        long ts = currentTimeMillis;
        foreach (ref timer; queue)
        {
            // if expired
            if (timer.nextTimestamp <= ts)
            {
                /+
                if (timer.id == _tooltip.timerID)
                {
                    // special case for tooltip timer
                    onTooltipTimer();
                    timer.cancel();
                }
                else+/
                {
                    timer.notify();
                }
                result = true;
            }
        }
        cleanup();
        return result;
    }

    /// Delete invalid timers
    private void cleanup()
    {
        if (!queue.length)
            return;
        queue = queue.remove!(t => !t.valid);
        sort(queue);
    }
}

struct TimerInfo
{
    protected
    {
        ulong _id;
        long _interval;
        long _nextTimestamp;
        WeakRef!Widget _targetWidget;
    }

    static __gshared ulong nextID;

    @disable this();

    this(WeakRef!Widget targetWidget, long intervalMillis)
    {
        _id = ++nextID;
        assert(intervalMillis >= 0 && intervalMillis < 7 * 24 * 60 * 60 * 1000L);
        _targetWidget = targetWidget;
        _interval = intervalMillis;
        _nextTimestamp = currentTimeMillis + _interval;
    }

    @property
    {
        /// Unique ID of timer
        ulong id() const
        {
            return _id;
        }
        /// Timer interval, milliseconds
        long interval() const
        {
            return _interval;
        }
        /// Next timestamp to invoke timer at, as per currentTimeMillis()
        long nextTimestamp() const
        {
            return _nextTimestamp;
        }
        /// Widget to route timer event to
        WeakRef!Widget targetWidget()
        {
            return _targetWidget;
        }
        /// Returns true if timer is not yet cancelled
        bool valid() const
        {
            return !_targetWidget.isNull;
        }
    }

    /// Notify the target widget
    void notify()
    {
        if (_targetWidget)
        {
            _nextTimestamp = currentTimeMillis + _interval;
            if (!_targetWidget.onTimer(_id))
            {
                _targetWidget.nullify();
            }
        }
    }

    /// Cancel timer
    void cancel()
    {
        _targetWidget.nullify();
    }

    bool opEquals(const ref TimerInfo b) const
    {
        return b._nextTimestamp == _nextTimestamp;
    }

    int opCmp(const ref TimerInfo b) const
    {
        if (valid && !b.valid)
            return -1;
        if (!valid && b.valid)
            return 1;
        if (!valid && !b.valid)
            return 0;
        if (_nextTimestamp < b._nextTimestamp)
            return -1;
        if (_nextTimestamp > b._nextTimestamp)
            return 1;
        return 0;
    }
}

class TimerThread : Thread
{
    protected
    {
        Mutex mutex;
        Condition condition;
        bool stopped;
        long nextEventTs;
        void delegate() callback;
    }

    this(void delegate() timerCallback)
    {
        callback = timerCallback;
        mutex = new Mutex;
        condition = new Condition(mutex);
        super(&run);
        start();
    }

    ~this()
    {
        stop();
        destroy(condition);
        destroy(mutex);
    }

    void set(long nextTs)
    {
        mutex.lock();
        if (nextEventTs == 0 || nextEventTs > nextTs)
        {
            nextEventTs = nextTs;
            condition.notify();
        }
        mutex.unlock();
    }

    void run()
    {
        while (!stopped)
        {
            bool expired = false;

            mutex.lock();

            long ts = currentTimeMillis;
            long timeToWait = nextEventTs == 0 ? 1000000 : nextEventTs - ts;
            if (timeToWait < 10)
                timeToWait = 10;

            if (nextEventTs == 0)
                condition.wait();
            else
                condition.wait(dur!"msecs"(timeToWait));

            if (stopped)
            {
                mutex.unlock();
                break;
            }
            ts = currentTimeMillis;
            if (nextEventTs && nextEventTs < ts && !stopped)
            {
                expired = true;
                nextEventTs = 0;
            }

            mutex.unlock();

            if (expired)
                callback();
        }
    }

    void stop()
    {
        if (stopped)
            return;
        stopped = true;
        mutex.lock();
        condition.notify();
        mutex.unlock();
        join();
    }
}
