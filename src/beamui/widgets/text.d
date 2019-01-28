/**
Widgets to show plain or formatted single- and multiline text.

Synopsis:
---
import beamui.widgets.text;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.text;

import beamui.graphics.text;
import beamui.widgets.widget;

/// Single-line text widget. Can contain `&` character for underlined hotkeys.
class Label : Widget
{
    @property
    {
        /// Text to show
        override dstring text() const { return textobj.str; }
        /// ditto
        override void text(dstring s)
        {
            textobj.str = s;
            requestLayout();
        }
    }

    private
    {
        SingleLineText textobj;
        SingleLineText minSizeTester;
    }

    this(dstring txt = null)
    {
        textobj.str = txt;
        minSizeTester.str = "aaaaa"; // TODO: test all this stuff
        handleFontChange();
    }

    override protected void handleFontChange()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
    }

    override Size computeMinSize()
    {
        textobj.style.hotkey = textHotkey;
        minSizeTester.style.hotkey = textHotkey;
        if (textobj.str.length < minSizeTester.str.length * 2)
        {
            textobj.measure();
            return textobj.size;
        }
        else
        {
            minSizeTester.measure();
            return minSizeTester.size;
        }
    }

    override Size computeNaturalSize()
    {
        textobj.measure();
        return textobj.size;
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        textobj.style.color = style.textColor;
        textobj.style.decoration = style.textDecoration;
        textobj.style.hotkey = textHotkey;
        textobj.style.overflow = style.textOverflow;
        // align vertically to center
        Size sz = Size(b.w, textobj.size.h);
        applyAlign(b, sz, Align.unspecified, Align.vcenter);
        textobj.draw(buf, b.pos, b.w, style.textAlign);
    }
}

/// Multiline text widget
class MultilineLabel : Widget
{
    @property
    {
        /// Text to show
        override dstring text() const { return textobj.str; }
        /// ditto
        override void text(dstring s)
        {
            textobj.str = s;
            requestLayout();
        }
    }

    private
    {
        PlainText textobj;
        PlainText minSizeTester;
        PlainText natSizeTester;
    }

    this(dstring txt = null)
    {
        textobj.str = txt;
        minSizeTester.str = "aaaaa\na";
        natSizeTester.str =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
        heightDependsOnWidth = true;
        handleFontChange();
    }

    override protected void handleFontChange()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
        natSizeTester.style.font = fnt;
    }

    override Size computeMinSize()
    {
        textobj.style.hotkey = textHotkey;
        minSizeTester.style.hotkey = textHotkey;
        if (textobj.lines[0].length < minSizeTester.lines[0].length)
        {
            textobj.measure();
            return textobj.size;
        }
        else
        {
            minSizeTester.measure();
            return minSizeTester.size;
        }
    }

    override Size computeNaturalSize()
    {
        natSizeTester.style.hotkey = textHotkey;
        if (textobj.lines[0].length < natSizeTester.lines[0].length)
        {
            textobj.measure();
            return textobj.size;
        }
        else
        {
            natSizeTester.measure();
            return natSizeTester.size;
        }
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        int w = width - p.w;
        textobj.wrapLines(w);
        return textobj.size.h + p.h;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        // wrap again in case the parent widget had not called heightForWidth
        // must be cached when width is the same
        int w = geom.w - padding.width;
        textobj.wrapLines(w);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        textobj.style.color = style.textColor;
        textobj.style.decoration = style.textDecoration;
        textobj.style.hotkey = textHotkey;
        textobj.style.overflow = style.textOverflow;
        textobj.draw(buf, b.pos, b.w, style.textAlign);
    }
}

/// Multiline text widget with inner formatting
class MarkupLabel : Widget
{
}
