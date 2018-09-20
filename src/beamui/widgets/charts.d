/**
This module contains charts widgets implementation.
Currently only SimpleBarChart.


Synopsis:
---
import beamui.widgets.charts;

// creation of simple bar chart
auto chart = new SimpleBarChart("Chart");

// add bars
chart.addBar(12.2, makeRGBA(255, 0, 0, 0), "new bar"c);

// update bar with index 0
chart.updateBar(0, 10, makeRGBA(255, 255, 0, 0), "new bar updated"c);
chart.updateBar(0, 20);

// remove bars with index 0
chart.removeBar(0, 20);

// change title
chart.title = "new title"d;

// change min axis ratio
chart.axisRatio = 0.3; // y axis length will be 0.3 of x axis
---

Copyright: Andrzej Kilijański 2017
License:   Boost License 1.0
Authors:   Andrzej Kilijański
*/
module beamui.widgets.charts;

import std.math;
import beamui.widgets.widget;

class SimpleBarChart : Widget
{
    this(dstring title = null)
    {
        clickable = false;
        focusable = false;
        trackHover = false;
        _axisX.arrowSize = 1;
        this.title = title ? title : tr("New chart");
        measureMinDescSize();
    }

    struct BarData
    {
        double y;
        dstring title;
        private Size _titleSize;
        uint color;

        this(double y, uint color, dstring title)
        {
            this.y = y;
            this.color = color;
            this.title = title;
        }
    }

    protected BarData[] _bars;
    protected double _maxY = 0;

    @property size_t barCount()
    {
        return _bars.length;
    }

    void addBar(double y, uint color, dstring barTitle)
    {
        if (y < 0)
            return; // current limitation only positive values
        _bars ~= BarData(y, color, barTitle);
        if (y > _maxY)
            _maxY = y;
        requestLayout();
    }

    void removeBar(size_t index)
    {
        _bars = remove(_bars, index);
        // update _maxY
        _maxY = 0;
        foreach (ref bar; _bars)
        {
            if (bar.y > _maxY)
                _maxY = bar.y;
        }
        requestLayout();
    }

    void removeAllBars()
    {
        _bars = [];
        _maxY = 0;
        requestLayout();
    }

    void updateBar(size_t index, double y, uint color, dstring barTitle)
    {
        if (y < 0)
            return; // current limitation only positive values
        _bars[index].y = y;
        _bars[index].color = color;
        _bars[index].title = barTitle;

        // update _maxY
        _maxY = 0;
        foreach (ref bar; _bars)
        {
            if (bar.y > _maxY)
                _maxY = bar.y;
        }
        requestLayout();
    }

    void updateBar(size_t index, double y)
    {
        if (y < 0)
            return; // curent limitation only positive values
        _bars[index].y = y;

        // update _maxY
        _maxY = 0;
        foreach (ref bar; _bars)
        {
            if (bar.y > _maxY)
                _maxY = bar.y;
        }
        requestLayout();
    }

    protected
    {
        dstring _title;
        bool _showTitle = true;
        Size _titleSize;
        int _marginAfterTitle = 2;
    }

    @property
    {
        /// Title to show
        dstring title() const
        {
            return _title;
        }
        /// ditto
        SimpleBarChart title(dstring s)
        {
            _title = s;
            measureTitleSize();
            if (_showTitle)
                requestLayout();
            return this;
        }

        /// Show title?
        bool showTitle() const
        {
            return _showTitle;
        }
        /// ditto
        SimpleBarChart showTitle(bool show)
        {
            if (_showTitle != show)
            {
                _showTitle = show;
                requestLayout();
            }
            return this;
        }

        uint chartBackgroundColor() const
        {
            return currentTheme.getColor("chart_background");
        }
        SimpleBarChart chartBackgroundColor(uint newColor)
        {
            //ownStyle.setCustomColor("chart_background", newColor); // TODO
            invalidate();
            return this;
        }

        uint chartAxisColor() const
        {
            return currentTheme.getColor("chart_axis");
        }
        SimpleBarChart chartAxisColor(uint newColor)
        {
            //ownStyle.setCustomColor("chart_axis", newColor); // TODO
            invalidate();
            return this;
        }

        uint chartSegmentTagColor() const
        {
            return currentTheme.getColor("chart_segment_tag");
        }
        SimpleBarChart chartSegmentTagColor(uint newColor)
        {
            //ownStyle.setCustomColor("chart_segment_tag", newColor); // TODO
            invalidate();
            return this;
        }
    }

    struct AxisData
    {
        Size maxDescriptionSize = Size(30, 20);
        int thickness = 1;
        int segmentTagLength = 4;
        int zeroValueDist = 3;
        int lengthFromZeroToArrow = 200;
        int arrowSize = 20;
    }

    AxisData _axisX;
    AxisData _axisY;

    protected
    {
        int _axisYMaxValueDescWidth = 30;
        int _axisYAvgValueDescWidth = 30;

        double _axisRatio = 0.6;

        int _minBarWidth = 10;
        int _barWidth = 10;
        int _barSpacing = 3;

        int _axisXMinWfromZero = 150;
        int _axisYMinDescWidth = 30;

        dstring _minDescSizeTester = "aaaaaaaaaa";
        Size _measuredDescMinSize;
    }

    @property
    {
        double axisRatio() const
        {
            return _axisRatio;
        }

        void axisRatio(double newRatio)
        {
            _axisRatio = newRatio;
            requestLayout();
        }

        dstring minDescSizeTester() const
        {
            return _minDescSizeTester;
        }

        void minDescSizeTester(dstring txt)
        {
            _minDescSizeTester = txt;
            measureMinDescSize();
            requestLayout();
        }
    }

    override protected void handleFontChanged()
    {
        measureTitleSize();
        measureMinDescSize();
    }

    protected void measureTitleSize()
    {
        FontRef f = font();
        _titleSize = f.textSize(_title, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags); // TODO: more than one line title support
    }

    protected void measureMinDescSize()
    {
        FontRef f = font();
        _measuredDescMinSize = f.textSize(_minDescSizeTester, MAX_WIDTH_UNSPECIFIED, 4);
    }

    protected Size measureAxisXDesc()
    {
        FontRef f = font();
        Size sz;
        foreach (ref bar; _bars)
        {
            bar._titleSize = f.measureMultilineText(bar.title, 0, _barWidth, 4, 0, textFlags);
            sz.w = max(sz.w, bar._titleSize.w);
            sz.h = max(sz.h, bar._titleSize.h);
        }
        return sz;
    }

    protected Size measureAxisYDesc()
    {
        int maxDescWidth = _axisYMinDescWidth;
        double currentMaxValue = _maxY;
        if (approxEqual(_maxY, 0, 0.0000001, 0.0000001))
            currentMaxValue = 100;

        FontRef f = font();
        Size sz = f.textSize(to!dstring(currentMaxValue), MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
        maxDescWidth = max(maxDescWidth, sz.w);
        _axisYMaxValueDescWidth = sz.w;
        sz = f.textSize(to!dstring(currentMaxValue / 2), MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
        maxDescWidth = max(maxDescWidth, sz.w);
        _axisYAvgValueDescWidth = sz.w;
        return Size(maxDescWidth, sz.h);
    }

    override Boundaries computeBoundaries()
    {
        int extraSizeX = _axisY.thickness + _axisY.segmentTagLength + _axisX.zeroValueDist + _axisX.arrowSize;
        int extraSizeY = _axisX.thickness + _axisX.segmentTagLength + _axisY.zeroValueDist + _axisY.arrowSize;

        _axisY.maxDescriptionSize = measureAxisYDesc();

        int currentMinBarWidth = max(_minBarWidth, _measuredDescMinSize.w);

        int minAxisXLength = max(cast(int)barCount * (currentMinBarWidth + _barSpacing), _axisXMinWfromZero);
        int minAxixYLength = cast(int)round(_axisRatio * minAxisXLength);

        Boundaries bs;
        bs.min.w = _axisY.maxDescriptionSize.w + minAxisXLength + extraSizeX;
        bs.min.h = minAxixYLength + extraSizeY;
        if (_showTitle)
        {
            bs.min.h += _titleSize.h + _marginAfterTitle;
            bs.nat.w = max(bs.min.w, _titleSize.w);
        }

        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        _box = geom;
        applyPadding(geom);

        int extraSizeX = _axisY.thickness + _axisY.segmentTagLength + _axisX.zeroValueDist + _axisX.arrowSize;
        int extraSizeY = _axisX.thickness + _axisX.segmentTagLength + _axisY.zeroValueDist + _axisY.arrowSize;

        // X axis length
        _axisX.lengthFromZeroToArrow = geom.w - _axisY.maxDescriptionSize.w - extraSizeX;

        // update bars width
        if (barCount > 0)
            _barWidth = cast(int)((_axisX.lengthFromZeroToArrow - _barSpacing * barCount) / barCount);

        // compute X axis max description height (necessary to know _barWidth here)
        _axisX.maxDescriptionSize = measureAxisXDesc();

        // Y axis length
        _axisY.lengthFromZeroToArrow = geom.h - _axisX.maxDescriptionSize.h - extraSizeY -
            (_showTitle ? _titleSize.h + _marginAfterTitle : 0);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;
        super.onDraw(buf);

        Box b = _box;
        applyMargins(b);
        applyPadding(b);

        auto saver = ClipRectSaver(buf, b, alpha);

        FontRef font = font();
        if (_showTitle)
            // align to center
            font.drawText(buf, b.x + (b.w - _titleSize.w) / 2, b.y, _title,
                    textColor, 4, 0, textFlags);

        // draw axes
        int x1 = b.x + _axisY.maxDescriptionSize.w + _axisY.segmentTagLength;
        int x2 = b.x + _axisY.maxDescriptionSize.w + _axisY.segmentTagLength + _axisY.thickness +
            _axisX.zeroValueDist + _axisX.lengthFromZeroToArrow + _axisX.arrowSize;
        int y1 = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength - _axisX.thickness -
            _axisY.zeroValueDist - _axisY.lengthFromZeroToArrow - _axisY.arrowSize;
        int y2 = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength;

        buf.fillRect(Rect(x1, y1, x2, y2), chartBackgroundColor);

        // y axis
        buf.drawLine(Point(x1, y1), Point(x1, y2), chartAxisColor);

        // x axis
        buf.drawLine(Point(x1, y2 - 1), Point(x2, y2 - 1), chartAxisColor);

        // top line - will be optional in the future
        buf.drawLine(Point(x1, y1), Point(x2, y1), chartAxisColor);

        // right line - will be optional in the future
        buf.drawLine(Point(x2 - 1, y1), Point(x2 - 1, y2), chartAxisColor);

        // draw bars

        int firstBarX = x1 + _axisY.thickness + _axisX.zeroValueDist;
        int firstBarY = y2 - _axisX.thickness - _axisY.zeroValueDist;

        SimpleTextFormatter fmt;
        foreach (ref bar; _bars)
        {
            // draw bar
            buf.fillRect(Rect(firstBarX, firstBarY - barYValueToPixels(_axisY.lengthFromZeroToArrow,
                    bar.y), firstBarX + _barWidth, firstBarY), bar.color);

            // draw x axis segment under bar
            buf.drawLine(Point(firstBarX + _barWidth / 2, y2), Point(firstBarX + _barWidth / 2,
                    y2 + _axisX.segmentTagLength), chartSegmentTagColor);

            // draw x axis description
            fmt.format(bar.title, font, 0, _barWidth, 4, 0, textFlags);
            fmt.draw(buf, firstBarX + (_barWidth - bar._titleSize.w) / 2,
                    b.y + b.h - _axisX.maxDescriptionSize.h + (_axisX.maxDescriptionSize.h - bar._titleSize.h) / 2,
                    font, textColor, Align.hcenter);

            firstBarX += _barWidth + _barSpacing;
        }

        // segments on y axis and values (now only max and max/2)
        double currentMaxValue = _maxY;
        if (approxEqual(_maxY, 0, 0.0000001, 0.0000001))
            currentMaxValue = 100;

        int yZero = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength -
            _axisX.thickness - _axisY.zeroValueDist;
        int yMax = yZero - _axisY.lengthFromZeroToArrow;
        int yAvg = (yZero + yMax) / 2;

        int horTagStart = b.x + _axisY.maxDescriptionSize.w;
        buf.drawLine(Point(horTagStart, yMax), Point(horTagStart + _axisY.segmentTagLength, yMax),
                     chartSegmentTagColor);
        buf.drawLine(Point(horTagStart, yAvg), Point(horTagStart + _axisY.segmentTagLength, yAvg),
                     chartSegmentTagColor);

        font.drawText(buf, b.x + (_axisY.maxDescriptionSize.w - _axisYMaxValueDescWidth),
                yMax - _axisY.maxDescriptionSize.h / 2, to!dstring(currentMaxValue), textColor, 4, 0, textFlags);
        font.drawText(buf, b.x + (_axisY.maxDescriptionSize.w - _axisYAvgValueDescWidth),
                yAvg - _axisY.maxDescriptionSize.h / 2, to!dstring(currentMaxValue / 2), textColor, 4, 0, textFlags);
    }

    protected int barYValueToPixels(int axisInPixels, double barYValue)
    {
        double currentMaxValue = _maxY;
        if (approxEqual(_maxY, 0, 0.0000001, 0.0000001))
            currentMaxValue = 100;

        double pixValue = axisInPixels / currentMaxValue;
        return cast(int)round(barYValue * pixValue);
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        handleFontChanged();
    }
}
