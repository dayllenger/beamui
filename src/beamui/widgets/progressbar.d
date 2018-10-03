/**
This module contains progress bar controls implementation.

ProgressBar - progress bar control


Synopsis:
---
import beamui.widgets.progressbar;

auto pb = new ProgressBar;
// set progress
pb.progress = 300; // 0 .. 1000
// set animation interval
pb.animationInterval = 50; // 50 milliseconds

// for indeterminate state: set progress to PROGRESS_INDETERMINATE (-1)
pb.progress = PROGRESS_INDETERMINATE;
---

Copyright: Vadim Lopatin 2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.progressbar;

import beamui.widgets.widget;

enum PROGRESS_INDETERMINATE = -1;
enum PROGRESS_HIDDEN = -2;
enum PROGRESS_ANIMATION_OFF = 0;
enum PROGRESS_MAX = 1000;

/// Base for different progress bar controls
class AbstractProgressBar : Widget
{
    @property
    {
        /// Current progress value, 0 .. 1000; -1 == indeterminate, -2 == hidden
        int progress() const
        {
            return _progress;
        }
        /// ditto
        AbstractProgressBar progress(int progress)
        {
            progress = clamp(progress, -2, 1000);
            if (_progress != progress)
            {
                _progress = progress;
                invalidate();
            }
            requestLayout();
            return this;
        }
        /// Returns true if progress bar is in indeterminate state
        bool indeterminate() const
        {
            return _progress == PROGRESS_INDETERMINATE;
        }

        /// Animation interval in milliseconds, if 0 - no animation
        int animationInterval() const
        {
            return _animationInterval;
        }
        /// ditto
        AbstractProgressBar animationInterval(int animationIntervalMillis)
        {
            animationIntervalMillis = clamp(animationIntervalMillis, 0, 5000);
            if (_animationInterval != animationIntervalMillis)
            {
                _animationInterval = animationIntervalMillis;
                if (!animationIntervalMillis)
                    stopAnimation();
                else
                    scheduleAnimation();
            }
            return this;
        }
    }

    protected int _progress = PROGRESS_INDETERMINATE;
    protected int _animationInterval = 0; // no animation by default

    this(int progress = PROGRESS_INDETERMINATE)
    {
        super(null);
        _progress = progress;
    }

    protected ulong _animationTimerID;
    protected void scheduleAnimation()
    {
        if (!visible || !_animationInterval)
        {
            if (_animationTimerID)
                stopAnimation();
            return;
        }
        stopAnimation();
        _animationTimerID = setTimer(_animationInterval);
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

    protected int _animationSpeedPixelsPerSecond = 20;
    protected long _animationPhase;
    protected long _lastAnimationTs;
    /// Called on animation timer
    protected void onAnimationTimer(long millisElapsed)
    {
        _animationPhase += millisElapsed;
        invalidate();
    }

    override bool onTimer(ulong id)
    {
        if (id == _animationTimerID)
        {
            if (!visible || _progress == PROGRESS_HIDDEN)
            {
                stopAnimation();
                return false;
            }
            long elapsed = 0;
            long ts = currentTimeMillis;
            if (_lastAnimationTs)
            {
                elapsed = clamp(ts - _lastAnimationTs, 0, 5000);
            }
            _lastAnimationTs = ts;
            onAnimationTimer(elapsed);
            return _animationInterval != 0;
        }
        // return true to repeat after the same interval, false to stop timer
        return super.onTimer(id);
    }
}

/// Progress bar widget
class ProgressBar : AbstractProgressBar
{
    this(int progress = PROGRESS_INDETERMINATE)
    {
        super(progress);
    }

    override Size computeNaturalSize()
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
        return sz;
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = _box;
        applyMargins(b);
        applyPadding(b);
        DrawableRef animDrawable;
        if (_progress >= 0)
        {
            DrawableRef gaugeDrawable = currentTheme.getDrawable("progress_bar_gauge");
            animDrawable = currentTheme.getDrawable("progress_bar_gauge_animation");
            int w = _progress * b.width / PROGRESS_MAX;
            if (!gaugeDrawable.isNull)
            {
                gaugeDrawable.drawTo(buf, Box(b.x, b.y, w, b.h));
            }
        }
        else
        {
            DrawableRef indeterminateDrawable = currentTheme.getDrawable("progress_bar_indeterminate");
            if (!indeterminateDrawable.isNull)
            {
                indeterminateDrawable.drawTo(buf, b);
            }
            animDrawable = currentTheme.getDrawable("progress_bar_indeterminate_animation");
        }
        if (!animDrawable.isNull && _animationInterval)
        {
            if (!_animationTimerID)
                scheduleAnimation();
            int w = animDrawable.width;
            _animationPhase %= w * 1000;
            animDrawable.drawTo(buf, b, cast(int)(_animationPhase * _animationSpeedPixelsPerSecond / 1000), 0);
            //Log.d("progress animation draw ", _animationPhase, " b=", b);
        }
    }
}
