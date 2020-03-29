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

Copyright: Vadim Lopatin 2016, dayllenger 2019-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.progressbar;

import beamui.widgets.widget;

enum int PROGRESS_HIDDEN = -2;
enum int PROGRESS_INDETERMINATE = -1;
enum int PROGRESS_MAX = 1000;

/// Progress indicator
class ProgressBar : Widget
{
    protected int progress = PROGRESS_INDETERMINATE;

    /// Construct with progress value (0 .. 1000; -1 for indeterminate, -2 for hidden)
    static ProgressBar make(int progress)
    {
        ProgressBar w = arena.make!ProgressBar;
        w.progress = progress;
        return w;
    }

    override protected Element createElement()
    {
        return new ElemProgressBar;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemProgressBar el = fastCast!ElemProgressBar(element);
        el.progress = progress;
        el.animationInterval = 50;
    }
}

class ElemProgressBar : Element
{
    @property
    {
        int progress() const { return _progress; }
        /// ditto
        void progress(int value)
        {
            value = clamp(value, PROGRESS_HIDDEN, PROGRESS_MAX);
            if (_progress == value)
                return;
            _progress = value;
            invalidate();
        }

        /// Animation interval in milliseconds, if 0 - no animation
        int animationInterval() const { return _animationInterval; }
        /// ditto
        void animationInterval(int value)
        {
            value = clamp(value, 0, 5000);
            if (_animationInterval == value)
                return;
            _animationInterval = value;
            if (value > 0)
                scheduleAnimation();
            else
                stopAnimation();
        }
    }

    private
    {
        int _progress = PROGRESS_INDETERMINATE;
        int _animationInterval = 0; // no animation by default

        ulong _animationTimerID;
        int _animationSpeedPixelsPerSecond = 20;
        long _animationPhase;
        long _lastAnimationTs;
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
                if (!visible || _progress == PROGRESS_HIDDEN)
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
        if (_progress >= 0)
        {
            DrawableRef gaugeDrawable = currentTheme.getDrawable("progress_bar_gauge");
            animDrawable = currentTheme.getDrawable("progress_bar_gauge_animation");
            const w = _progress * b.w / PROGRESS_MAX;
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
