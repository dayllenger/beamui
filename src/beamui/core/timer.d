/**


Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.platforms.common.timer;

import core.thread;
import beamui.core.functions;
import beamui.core.logger : currentTimeMillis;

/// Timers queue
class TimerQueue
{
    protected TimerInfo[] queue;

    /// Add new timer, returns timer id
    ulong add(long intervalMillis, bool delegate() handler)
    {
        TimerInfo item = TimerInfo(intervalMillis, handler);
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

    /// Returns timestamp in milliseconds of the next scheduled event or 0 if no events queued
    long nextTimestamp() const
    {
        if (!queue.length || !queue[0].valid)
            return 0;
        return queue[0].nextTimestamp;
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
                timer.notify();
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
    private
    {
        ulong _id;
        long _interval;
        long _initialTimestamp;
        long _nextTimestamp;
        bool delegate() _handler;
    }

    static __gshared ulong nextID;

    @disable this();

    this(long intervalMillis, bool delegate() handler)
    {
        assert(intervalMillis >= 0 && intervalMillis < 7 * 24 * 60 * 60 * 1000L);
        _id = ++nextID;
        _interval = intervalMillis;
        _initialTimestamp = currentTimeMillis;
        _nextTimestamp = _initialTimestamp + _interval;
        _handler = handler;
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
        /// Next timestamp to invoke timer at, milliseconds
        long nextTimestamp() const
        {
            return _nextTimestamp;
        }
        /// Returns true if timer is not yet cancelled
        bool valid() const
        {
            return _handler !is null;
        }
    }

    /// Notify the target widget
    void notify()
    {
        if (_handler)
        {
            if (!_handler())
            {
                _handler = null;
            }
            else
            {
                // find next timestamp to tick
                long ticksElapsed = (currentTimeMillis - _initialTimestamp) / _interval;
                _nextTimestamp = _initialTimestamp + (ticksElapsed + 1) * _interval;
            }
        }
    }

    /// Cancel timer
    void cancel()
    {
        _handler = null;
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

final class TimerThread : Thread
{
    import core.atomic;
    import core.sync.condition;
    import core.sync.mutex;

    private
    {
        Mutex mutex;
        Condition condition;
        long timestamp = long.max;
        void delegate() callback;

        shared bool stopped;
    }

    this(void delegate() timerCallback)
    {
        super(&run);
        callback = timerCallback;
        mutex = new Mutex;
        condition = new Condition(mutex);
        start();
    }

    ~this()
    {
        stop();
        destroy(condition);
        destroy(mutex);
    }

    void notifyOn(long timestamp)
    {
        mutex.lock();
        if (this.timestamp > timestamp)
        {
            this.timestamp = timestamp;
            condition.notify();
        }
        mutex.unlock();
    }

    private void run()
    {
        while (!atomicLoad(stopped))
        {
            mutex.lock();

            bool expired;
            if (timestamp != long.max)
            {
                long timeToWait = timestamp - currentTimeMillis;
                if (timeToWait > 0)
                    expired = !condition.wait(dur!"msecs"(timeToWait));
                else
                    expired = true;
                if (expired)
                    timestamp = long.max;
            }
            else
                condition.wait();

            mutex.unlock();

            if (expired)
                callback();
        }
    }

    void stop()
    {
        if (atomicLoad(stopped))
            return;

        atomicStore(stopped, true);
        mutex.lock();
        condition.notify();
        mutex.unlock();
        join();
    }
}
