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
    /// Progress value (0 .. 1000; -1 for indeterminate, -2 for hidden)
    int progress = PROGRESS_INDETERMINATE;

    override protected ProgressBarState createState()
    {
        return new ProgressBarState;
    }

    override protected Element createElement()
    {
        return new ElemProgressBar;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemProgressBar el = fastCast!ElemProgressBar(element);
        el.progress = cast(float)progress / PROGRESS_MAX;

        ProgressBarState st = use!ProgressBarState;
        st.element = el;
        st.animationInterval = progress != PROGRESS_HIDDEN ? 50 : 0;
    }
}

class ProgressBarState : WidgetState
{
    final @property
    {
        inout(ElemProgressBar) element() inout { return _el; }
        /// ditto
        void element(ElemProgressBar el)
        {
            if (_el is el)
                return;
            stopAnimation();
            _el = el;
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
            scheduleAnimation();
        }
    }

    private
    {
        ElemProgressBar _el;

        int _animationInterval = 0; // no animation by default

        ulong _animationTimerID;
        long _lastAnimationTs;
    }

    protected void scheduleAnimation()
        in(_el)
    {
        stopAnimation();
        if (_animationInterval == 0 || !_el.visible)
            return;

        _animationTimerID = _el.setTimer(_animationInterval, {
            if (!_el.visible)
            {
                _animationTimerID = 0;
                _lastAnimationTs = 0;
                _el.showAnimation = false;
                return false;
            }
            const ts = currentTimeMillis;
            long elapsed;
            if (_lastAnimationTs != 0)
                elapsed = clamp(ts - _lastAnimationTs, 0, 5000);
            _lastAnimationTs = ts;
            handleAnimationTimer(elapsed);
            return _animationInterval != 0;
        });
        _el.showAnimation = true;
    }

    protected void stopAnimation()
    {
        if (_animationTimerID)
        {
            _el.cancelTimer(_animationTimerID);
            _el.showAnimation = false;
            _animationTimerID = 0;
        }
        _lastAnimationTs = 0;
    }

    /// Called on animation timer
    protected void handleAnimationTimer(long msecElapsed)
        in(_el)
    {
        _el.animationPhase = _el.animationPhase + msecElapsed;
    }
}

class ElemProgressBar : Element
{
    @property
    {
        float progress() { return _fraction; }
        /// ditto
        void progress(float fr)
        {
            fr = clamp(fr, -1, 1);
            if (_fraction == fr)
                return;
            _fraction = fr;
            invalidate();
        }

        bool showAnimation() const { return _showAnimation; }
        /// ditto
        void showAnimation(bool flag)
        {
            if (_showAnimation == flag)
                return;
            _showAnimation = flag;
            invalidate();
        }

        long animationPhase() const { return _animationPhase; }
        /// ditto
        void animationPhase(long msecs)
        {
            if (_animationPhase == msecs)
                return;
            _animationPhase = msecs;
            invalidate();
        }
    }

    private
    {
        float _fraction = -1;

        bool _showAnimation;
        long _animationPhase;
        int _animationSpeedPixelsPerSecond = 20;
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

        DrawableRef drAnim;
        if (_fraction >= 0)
        {
            DrawableRef drGauge = currentTheme.getDrawable("progress_bar_gauge");
            drAnim = currentTheme.getDrawable("progress_bar_gauge_animation");
            if (!drGauge.isNull)
            {
                const w = _fraction * b.w;
                drGauge.drawTo(pr, Box(b.x, b.y, w, b.h));
            }
        }
        else
        {
            DrawableRef drIndeterminate = currentTheme.getDrawable("progress_bar_indeterminate");
            if (!drIndeterminate.isNull)
                drIndeterminate.drawTo(pr, b);
            drAnim = currentTheme.getDrawable("progress_bar_indeterminate_animation");
        }
        // show animation
        if (!drAnim.isNull && _showAnimation)
        {
            const phase = _animationPhase % cast(long)(drAnim.width * 1000);
            drAnim.drawTo(pr, b, phase * _animationSpeedPixelsPerSecond / 1000.0f, 0);
        }
    }
}
