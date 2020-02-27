/**
Chart widgets. Currently only SimpleBarChart.

Synopsis:
---
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
import beamui.text.simple;
import beamui.text.sizetest;
import beamui.text.style;
import beamui.widgets.widget;

class SimpleBarChart : Widget
{
    this(dstring title = null)
    {
        allowsClick = false;
        allowsFocus = false;
        allowsHover = false;
        _axisX.arrowSize = 1;
        this.title = title ? title : tr("New chart");
        _minDescSizeTester.str = "aaaaaaaaaa";
        handleFontChange();
    }

    struct BarData
    {
        double y;
        SimpleText title;
        Color color;

        this(double y, Color color, dstring title)
        {
            this.y = y;
            this.color = color;
            this.title.str = title;
        }
    }

    private BarData*[] _bars;
    private double _maxY = 0;

    @property size_t barCount() const
    {
        return _bars.length;
    }

    void addBar(double y, Color color, dstring barTitle)
    {
        if (y < 0)
            return; // current limitation only positive values
        _bars ~= new BarData(y, color, barTitle);
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

    struct AxisData
    {
        Size maxDescriptionSize = Size(30, 20);
        float thickness = 1;
        float segmentTagLength = 4;
        float zeroValueDist = 3;
        float lengthFromZeroToArrow = 200;
        float arrowSize = 20;
    }

    AxisData _axisX;
    AxisData _axisY;

    private
    {
        SimpleText _title;
        bool _showTitle = true;
        int _marginAfterTitle = 2;

        Color _backgroundColor = Color(0xffffff);
        Color _axisColor = Color(0xc0c0c0);
        Color _segmentTagColor = Color(0xc0c0c0);

        SimpleText _axisYMaxValueDesc;
        SimpleText _axisYAvgValueDesc;
        double cachedMaxYValue;
        double cachedAvgYValue;

        double _axisRatio = 0.6;

        int _minBarWidth = 10;
        int _barWidth = 10;
        int _barSpacing = 3;

        int _axisXMinWfromZero = 150;
        int _axisYMinDescWidth = 30;

        TextSizeTester _minDescSizeTester;
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

        Color chartBackgroundColor() const { return _backgroundColor; }
        /// ditto
        void chartBackgroundColor(Color value)
        {
            if (_backgroundColor != value)
            {
                _backgroundColor = value;
                invalidate();
            }
        }

        Color chartAxisColor() const { return _axisColor; }
        /// ditto
        void chartAxisColor(Color value)
        {
            if (_axisColor != value)
            {
                _axisColor = value;
                invalidate();
            }
        }

        Color chartSegmentTagColor() const { return _segmentTagColor; }
        /// ditto
        void chartSegmentTagColor(Color value)
        {
            if (_segmentTagColor != value)
            {
                _segmentTagColor = value;
                invalidate();
            }
        }

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

    override void handleThemeChange()
    {
        super.handleThemeChange();
        _backgroundColor = currentTheme.getColor("chart_background", Color(0xffffff));
        _axisColor = currentTheme.getColor("chart_axis", Color(0xc0c0c0));
        _segmentTagColor = currentTheme.getColor("chart_segment_tag", Color(0xc0c0c0));
        handleFontChange();
    }

    override protected void handleFontChange()
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
            bar.title.wrap(_barWidth);
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
        _axisYMaxValueDesc.measure();
        _axisYAvgValueDesc.measure();
        Size maxSize = _axisYMaxValueDesc.size;
        Size avgSize = _axisYAvgValueDesc.size;
        return Size(max(maxSize.w, avgSize.w, _axisYMinDescWidth),
                    max(maxSize.h, avgSize.h));
    }

    override protected Boundaries computeBoundaries()
    {
        const extraSizeX = _axisY.thickness + _axisY.segmentTagLength + _axisX.zeroValueDist + _axisX.arrowSize;
        const extraSizeY = _axisX.thickness + _axisX.segmentTagLength + _axisY.zeroValueDist + _axisY.arrowSize;

        _axisY.maxDescriptionSize = measureAxisYDesc();

        const currentMinBarWidth = max(_minBarWidth, _minDescSizeTester.getSize().w);

        const minAxisXLength = max(barCount * (currentMinBarWidth + _barSpacing), _axisXMinWfromZero);
        const minAxixYLength = round(_axisRatio * minAxisXLength);

        Boundaries bs;
        bs.min.w = _axisY.maxDescriptionSize.w + minAxisXLength + extraSizeX;
        bs.min.h = minAxixYLength + extraSizeY;
        if (_showTitle)
        {
            _title.measure();
            Size ts = _title.size;
            bs.nat.w = max(bs.min.w, ts.w);
            bs.min.h += ts.h + _marginAfterTitle;
        }
        return bs;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        setBox(geom);
        const inner = innerBox;

        const extraSizeX = _axisY.thickness + _axisY.segmentTagLength + _axisX.zeroValueDist + _axisX.arrowSize;
        const extraSizeY = _axisX.thickness + _axisX.segmentTagLength + _axisY.zeroValueDist + _axisY.arrowSize;

        // X axis length
        _axisX.lengthFromZeroToArrow = inner.w - _axisY.maxDescriptionSize.w - extraSizeX;

        // update bars width
        if (barCount > 0)
            _barWidth = cast(int)((_axisX.lengthFromZeroToArrow - _barSpacing * barCount) / barCount);

        // compute X axis max description height (necessary to know _barWidth here)
        _axisX.maxDescriptionSize = measureAxisXDesc();

        // Y axis length
        _axisY.lengthFromZeroToArrow = inner.h - _axisX.maxDescriptionSize.h - extraSizeY -
            (_showTitle ? _title.size.h + _marginAfterTitle : 0);
    }

    override protected void drawContent(Painter pr)
    {
        const b = innerBox;

        const x1 = b.x + _axisY.maxDescriptionSize.w + _axisY.segmentTagLength;
        const x2 = b.x + _axisY.maxDescriptionSize.w + _axisY.segmentTagLength + _axisY.thickness +
            _axisX.zeroValueDist + _axisX.lengthFromZeroToArrow + _axisX.arrowSize;
        const y1 = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength - _axisX.thickness -
            _axisY.zeroValueDist - _axisY.lengthFromZeroToArrow - _axisY.arrowSize;
        const y2 = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength;

        // draw title first
        if (_showTitle)
        {
            // align to the center of chart view
            _title.style.color = style.textColor;
            _title.style.alignment = TextAlign.center;
            _title.draw(pr, x1, b.y, x2 - x1);
        }

        // draw axes
        pr.fillRect(x1, y1, x2 - x1, y2 - y1, _backgroundColor);
        // y axis
        pr.drawLine(x1, y1, x1, y2, _axisColor);
        // x axis
        pr.drawLine(x1, y2, x2, y2, _axisColor);
        // top line - will be optional in the future
        pr.drawLine(x1, y1, x2, y1, _axisColor);
        // right line - will be optional in the future
        pr.drawLine(x2, y1, x2, y2, _axisColor);

        // draw bars

        float firstBarX = x1 + _axisY.thickness + _axisX.zeroValueDist;
        const firstBarY = y2 - _axisX.thickness - _axisY.zeroValueDist;

        foreach (ref bar; _bars)
        {
            // draw bar
            const h = barYValueToPixels(_axisY.lengthFromZeroToArrow, bar.y);
            pr.fillRect(firstBarX, firstBarY - h, _barWidth, h, bar.color);

            // draw x axis segment under bar
            pr.drawLine(
                firstBarX + _barWidth / 2, y2,
                firstBarX + _barWidth / 2, y2 + _axisX.segmentTagLength,
                _segmentTagColor,
            );

            // draw x axis description
            bar.title.style.color = style.textColor;
            bar.title.style.alignment = TextAlign.center;
            const yoffset = (_axisX.maxDescriptionSize.h + bar.title.size.h) / 2;
            bar.title.draw(pr, firstBarX, b.y + b.h - yoffset, _barWidth);

            firstBarX += _barWidth + _barSpacing;
        }

        // draw segments on y axis and values (now only max and max/2)

        const yZero = b.y + b.h - _axisX.maxDescriptionSize.h - _axisX.segmentTagLength -
            _axisX.thickness - _axisY.zeroValueDist;
        const yMax = yZero - _axisY.lengthFromZeroToArrow;
        const yAvg = (yZero + yMax) / 2;
        const axisYWidth = _axisY.maxDescriptionSize.w;
        const horTagStart = b.x + axisYWidth;

        pr.drawLine(horTagStart, yMax, horTagStart + _axisY.segmentTagLength, yMax, _segmentTagColor);
        pr.drawLine(horTagStart, yAvg, horTagStart + _axisY.segmentTagLength, yAvg, _segmentTagColor);

        _axisYMaxValueDesc.style.color = style.textColor;
        _axisYAvgValueDesc.style.color = style.textColor;
        _axisYMaxValueDesc.style.alignment = TextAlign.end;
        _axisYAvgValueDesc.style.alignment = TextAlign.end;
        _axisYMaxValueDesc.draw(pr, b.x, yMax - _axisY.maxDescriptionSize.h / 2, axisYWidth);
        _axisYAvgValueDesc.draw(pr, b.x, yAvg - _axisY.maxDescriptionSize.h / 2, axisYWidth);
    }

    protected float barYValueToPixels(float axisInPixels, double barYValue)
    {
        double currentMaxValue = _maxY;
        if (approxEqual(_maxY, 0, 0.0000001, 0.0000001))
            currentMaxValue = 100;

        double pixValue = axisInPixels / currentMaxValue;
        return cast(float)round(barYValue * pixValue);
    }
}
