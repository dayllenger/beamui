/**
Progress bar control.

Synopsis:
---
auto pb = new ProgressBar;
// set progress
pb.data.progress = 300; // 0 .. 1000
// set animation interval
pb.animationInterval = 50; // 50 milliseconds

// for indeterminate state: set progress to PROGRESS_INDETERMINATE (-1)
pb.data.progress = PROGRESS_INDETERMINATE;
---

Copyright: Vadim Lopatin 2016, dayllenger 2019
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.progressbar;

import beamui.widgets.widget;

enum int PROGRESS_HIDDEN = -2;
enum int PROGRESS_INDETERMINATE = -1;
enum int PROGRESS_MAX = 1000;

alias ElemProgressBar = ProgressBar;

class NgProgressBar : NgWidget
{
    int progress;

    static NgProgressBar make(int progress)
    {
        NgProgressBar w = arena.make!NgProgressBar;
        w.progress = progress;
        return w;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemProgressBar;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemProgressBar el = fastCast!ElemProgressBar(element);
        el.data.progress = progress;
        el.animationInterval = 50;
    }
}

/// Basic component for different progress bar controls
class ProgressData
{
    @property
    {
        /// Current progress value, 0 .. 1000; -1 == indeterminate, -2 == hidden
        int progress() const { return _progress; }
        /// ditto
        void progress(int value)
        {
            value = clamp(value, PROGRESS_HIDDEN, PROGRESS_MAX);
            if (_progress != value)
            {
                _progress = value;
                onChange();
            }
        }
        /// Returns true if progress bar is in indeterminate state
        bool indeterminate() const
        {
            return _progress == PROGRESS_INDETERMINATE;
        }
    }

    Signal!(void delegate()) onChange;

    private int _progress = PROGRESS_INDETERMINATE;

    this(int progress)
    {
        _progress = progress;
    }
}

/// Progress bar widget
class ProgressBar : Widget
{
    @property
    {
        /// Progress data
        inout(ProgressData) data() inout { return _data; }

        /// Animation interval in milliseconds, if 0 - no animation
        int animationInterval() const { return _animationInterval; }
        /// ditto
        void animationInterval(int interval)
        {
            interval = clamp(interval, 0, 5000);
            if (_animationInterval != interval)
            {
                _animationInterval = interval;
                if (interval > 0)
                    scheduleAnimation();
                else
                    stopAnimation();
            }
        }
    }

    private
    {
        ProgressData _data;
        int _animationInterval = 0; // no animation by default

        ulong _animationTimerID;
        int _animationSpeedPixelsPerSecond = 20;
        long _animationPhase;
        long _lastAnimationTs;
    }

    this(int progress = PROGRESS_INDETERMINATE)
    {
        _data = new ProgressData(progress);
        _data.onChange ~= &invalidate;
    }

    protected void scheduleAnimation()
    {
        if (!visible || !_animationInterval)
        {
            if (_animationTimerID)
                stopAnimation();
            return;
        }
        stopAnimation();
        _animationTimerID = setTimer(_animationInterval,
            delegate() {
                if (!visible || _data.progress == PROGRESS_HIDDEN)
                {
                    _lastAnimationTs = 0;
                    _animationTimerID = 0;
                    return false;
                }
                long elapsed = 0;
                long ts = currentTimeMillis;
                if (_lastAnimationTs)
                {
                    elapsed = clamp(ts - _lastAnimationTs, 0, 5000);
                }
                _lastAnimationTs = ts;
                handleAnimationTimer(elapsed);
                return _animationInterval != 0;
            });
        invalidate();
    }

    protected void stopAnimation()
    {
        if (_animationTimerID)
        {
            cancelTimer(_animationTimerID);
            _animationTimerID = 0;
        }
        _lastAnimationTs = 0;
    }

    /// Called on animation timer
    protected void handleAnimationTimer(long millisElapsed)
    {
        _animationPhase += millisElapsed;
        invalidate();
    }

    override protected Boundaries computeBoundaries()
    {
        DrawableRef gaugeDrawable = currentTheme.getDrawable("progress_bar_gauge");
        DrawableRef indeterminateDrawable = currentTheme.getDrawable("progress_bar_indeterminate");
        Size sz;
        if (!gaugeDrawable.isNull)
        {
            sz.h = max(sz.h, gaugeDrawable.height);
        }
        if (!indeterminateDrawable.isNull)
        {
            sz.h = max(sz.h, indeterminateDrawable.height);
        }
        return Boundaries(Size(0, 0), sz);
    }

    override protected void drawContent(Painter pr)
    {
        const b = innerBox;
        pr.clipIn(BoxI.from(b));

        DrawableRef animDrawable;
        if (_data.progress >= 0)
        {
            DrawableRef gaugeDrawable = currentTheme.getDrawable("progress_bar_gauge");
            animDrawable = currentTheme.getDrawable("progress_bar_gauge_animation");
            const w = _data.progress * b.w / PROGRESS_MAX;
            if (!gaugeDrawable.isNull)
            {
                gaugeDrawable.drawTo(pr, Box(b.x, b.y, w, b.h));
            }
        }
        else
        {
            DrawableRef indeterminateDrawable = currentTheme.getDrawable("progress_bar_indeterminate");
            if (!indeterminateDrawable.isNull)
            {
                indeterminateDrawable.drawTo(pr, b);
            }
            animDrawable = currentTheme.getDrawable("progress_bar_indeterminate_animation");
        }
        if (!animDrawable.isNull && _animationInterval)
        {
            if (!_animationTimerID)
                scheduleAnimation();
            const w = animDrawable.width;
            _animationPhase %= cast(long)(w * 1000);
            animDrawable.drawTo(pr, b, _animationPhase * _animationSpeedPixelsPerSecond / 1000.0f, 0);
        }
    }
}
