/**
Chart widgets. Currently only SimpleBarChart.

Synopsis:
---
import beamui.widgets.charts;

// creation of simple bar chart
auto chart = new SimpleBarChart("Chart");

// add bars
chart.addBar(12.2, Color(255, 0, 0), "new bar"c);

// update bar with index 0
chart.updateBar(0, 10, Color(255, 255, 0), "new bar updated"c);
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
import beamui.graphics.text;
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
        _minDescSizeTester.str = "aaaaaaaaaa";
        handleFontChanged();
    }

    struct BarData
    {
        double y;
        PlainText title;
        Color color;

        this(double y, Color color, dstring title)
        {
            this.y = y;
            this.color = color;
            this.title.str = title;
        }
    }

    private BarData[] _bars;
    private double _maxY = 0;

    @property size_t barCount()
    {
        return _bars.length;
    }

    void addBar(double y, Color color, dstring barTitle)
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

    void updateBar(size_t index, double y, Color color, dstring barTitle)
    {
        if (y < 0)
            return; // current limitation only positive values
        _bars[index].y = y;
        _bars[index].color = color;
        _bars[index].title.str = barTitle;

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

    private
    {
        PlainText _title;
        bool _showTitle = true;
        int _marginAfterTitle = 2;
    }

    @property
    {
        /// Title to show
        dstring title() const { return _title.str; }
        /// ditto
        void title(dstring s)
        {
            _title.str = s;
            if (_showTitle)
                requestLayout();
        }

        /// Show title?
        bool showTitle() const { return _showTitle; }
        /// ditto
        void showTitle(bool show)
        {
            if (_showTitle != show)
            {
                _showTitle = show;
                requestLayout();
            }
        }

        Color chartBackgroundColor() const
        {
            return currentTheme.getColor("chart_background", Color(0xffffff));
        }
        void chartBackgroundColor(Color newColor)
        {
            //ownStyle.setCustomColor("chart_background", newColor); // TODO
            invalidate();
        }

        Color chartAxisColor() const
        {
            return currentTheme.getColor("chart_axis", Color(0xc0c0c0));
        }
        void chartAxisColor(Color newColor)
        {
            //ownStyle.setCustomColor("chart_axis", newColor); // TODO
            invalidate();
        }

        Color chartSegmentTagColor() const
        {
            return currentTheme.getColor("chart_segment_tag", Color(0xc0c0c0));
        }
        void chartSegmentTagColor(Color newColor)
        {
            //ownStyle.setCustomColor("chart_segment_tag", newColor); // TODO
            invalidate();
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

    private
    {
        SingleLineText _axisYMaxValueDesc;
        SingleLineText _axisYAvgValueDesc;
        double cachedMaxYValue;
        double cachedAvgYValue;

        double _axisRatio = 0.6;

        int _minBarWidth = 10;
        int _barWidth = 10;
        int _barSpacing = 3;

        int _axisXMinWfromZero = 150;
        int _axisYMinDescWidth = 30;

        SingleLineText _minDescSizeTester;
    }

    @property
    {
        double axisRatio() const { return _axisRatio; }

        void axisRatio(double newRatio)
        {
            _axisRatio = newRatio;
            requestLayout();
        }

        dstring minDescSizeTester() const { return _minDescSizeTester.str; }

        void minDescSizeTester(dstring txt)
        {
            _minDescSizeTester.str = txt;
            requestLayout();
        }
    }

    override protected void handleFontChanged()
    {
        Font fnt = font.get;
        _title.style.font = fnt;
        _axisYMaxValueDesc.style.font = fnt;
        _axisYAvgValueDesc.style.font = fnt;
        _minDescSizeTester.style.font = fnt;
    }

    protected Size measureAxisXDesc()
    {
        Font fnt = font.get;
        Size sz;
        foreach (ref bar; _bars)
        {
            bar.title.style.font = fnt;
            bar.title.wrapLines(_barWidth);
            Size ts = bar.title.size;
            sz.w = max(sz.w, ts.w);
            sz.h = max(sz.h, ts.h);
        }
        return sz;
    }

    protected Size measureAxisYDesc()
    {
        double currentMaxValue = _maxY;
        if (approxEqual(_maxY, 0, 0.0000001, 0.0000001))
            currentMaxValue = 100;

        if (cachedMaxYValue != currentMaxValue)
        {
            cachedMaxYValue = currentMaxValue;
            _axisYMaxValueDesc.str = to!dstring(currentMaxValue);
        }
        double avgValue = currentMaxValue / 2;
        if (cachedAvgYValue != avgValue)
        {
            cachedAvgYValue = avgValue;
            _axisYAvgValueDesc.str = to!dstring(avgValue);
        }
        Size maxSize = _axisYMaxValueDesc.size;
        Size avgSize = _axisYAvgValueDesc.size;
        return Size(max(maxSize.w, avgSize.w, _axisYMinDescWidth),
                    max(maxSize.h, avgSize.h));
    }

    override Boundaries computeBoundaries()
    {
        int extraSizeX = _axisY.thickness + _axisY.segmentTagLength + _axisX.zeroValueDist + _axisX.arrowSize;
        int extraSizeY = _axisX.thickness + _axisX.segmentTagLength + _axisY.zeroValueDist + _axisY.arrowSize;

        _axisY.maxDescriptionSize = measureAxisYDesc();

        int currentMinBarWidth = max(_minBarWidth, _minDescSizeTester.size.w);

        int minAxisXLength = max(cast(int)barCount * (currentMinBarWidth + _barSpacing), _axisXMinWfromZero);
        int minAxixYLength = cast(int)round(_axisRatio * minAxisXLength);

        Boundaries bs;
        bs.min.w = _axisY.maxDescriptionSize.w + minAxisXLength + extraSizeX;
        bs.min.h = minAxixYLength + extraSizeY;
        if (_showTitle)
        {
            Size ts = _title.size;
            bs.nat.w = max(bs.min.w, ts.w);
            bs.min.h += ts.h + _marginAfterTitle;
        }

        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        box = geom;
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
            (_showTitle ? _title.size.h + _marginAfterTitle : 0);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;
        super.onDraw(buf);

        Box b = box;
        applyPadding(b);

        auto saver = ClipRectSaver(buf, b, alpha);

        int x1 = b.x + _axisY.maxDescriptionSize.w + _axisY.segmentTagLength;
        int x2 = b.x + _axisY.maxDescriptionSize.w + _axisY.segmentTagLength + _axisY.thickness +
            _axisX.zeroValueDist + _axisX.lengthFromZeroToArrow + _axisX.arrowSize;
        int y1 = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength - _axisX.thickness -
            _axisY.zeroValueDist - _axisY.lengthFromZeroToArrow - _axisY.arrowSize;
        int y2 = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength;

        // draw title first
        if (_showTitle)
        {
            // align to the center of chart view
            _title.style.color = textColor;
            _title.draw(buf, Point(x1, b.y), x2 - x1, TextAlign.center);
        }

        // draw axes
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

        foreach (ref bar; _bars)
        {
            // draw bar
            buf.fillRect(Rect(firstBarX, firstBarY - barYValueToPixels(_axisY.lengthFromZeroToArrow,
                    bar.y), firstBarX + _barWidth, firstBarY), bar.color);

            // draw x axis segment under bar
            buf.drawLine(Point(firstBarX + _barWidth / 2, y2), Point(firstBarX + _barWidth / 2,
                    y2 + _axisX.segmentTagLength), chartSegmentTagColor);

            // draw x axis description
            bar.title.style.color = textColor;
            int yoffset = (_axisX.maxDescriptionSize.h + bar.title.size.h) / 2;
            bar.title.draw(buf, Point(firstBarX, b.y + b.h - yoffset), _barWidth, TextAlign.center);

            firstBarX += _barWidth + _barSpacing;
        }

        // draw segments on y axis and values (now only max and max/2)

        int yZero = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength -
            _axisX.thickness - _axisY.zeroValueDist;
        int yMax = yZero - _axisY.lengthFromZeroToArrow;
        int yAvg = (yZero + yMax) / 2;
        int axisYWidth = _axisY.maxDescriptionSize.w;
        int horTagStart = b.x + axisYWidth;

        buf.drawLine(Point(horTagStart, yMax), Point(horTagStart + _axisY.segmentTagLength, yMax),
                     chartSegmentTagColor);
        buf.drawLine(Point(horTagStart, yAvg), Point(horTagStart + _axisY.segmentTagLength, yAvg),
                     chartSegmentTagColor);

        _axisYMaxValueDesc.style.color = textColor;
        _axisYAvgValueDesc.style.color = textColor;
        _axisYMaxValueDesc.draw(buf, Point(b.x, yMax - _axisY.maxDescriptionSize.h / 2), axisYWidth, TextAlign.end);
        _axisYAvgValueDesc.draw(buf, Point(b.x, yAvg - _axisY.maxDescriptionSize.h / 2), axisYWidth, TextAlign.end);
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
