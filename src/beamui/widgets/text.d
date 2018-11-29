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
        /// Text alignment - start, center, end, or justify
        TextAlign textAlign() const
        {
            updateStyles();
            return _textAlign;
        }
        /// ditto
        void textAlign(TextAlign a)
        {
            setProperty!"_textAlign" = a;
        }
        private alias textAlign_effect = invalidate;

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

        @forCSS("text-align") TextAlign _textAlign = TextAlign.start;
    }

    this(dstring txt = null)
    {
        textobj.str = txt;
        minSizeTester.str = "aaaaa"; // TODO: test all this stuff
        handleFontChanged();
    }

    mixin SupportCSS;

    override protected void handleFontChanged()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
    }

    override Size computeMinSize()
    {
        textobj.style.flags = textFlags;
        minSizeTester.style.flags = textFlags;
        if (textobj.str.length < minSizeTester.str.length * 2)
            return textobj.size;
        else
            return minSizeTester.size;
    }

    override Size computeNaturalSize()
    {
        return textobj.size;
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = box;
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);

        textobj.style.color = textColor;
        textobj.style.flags = textFlags;
        // align vertically to center
        Size sz = Size(b.w, textobj.size.h);
        applyAlign(b, sz, Align.unspecified, Align.vcenter);
        textobj.draw(buf, b.pos, b.w, textAlign);
    }
}

/// Multiline text widget
class MultilineLabel : Widget
{
    @property
    {
        /// Text alignment - start, center, end, or justify
        TextAlign textAlign() const
        {
            updateStyles();
            return _textAlign;
        }
        /// ditto
        void textAlign(TextAlign a)
        {
            setProperty!"_textAlign" = a;
        }
        private alias textAlign_effect = invalidate;

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

        @forCSS("text-align") TextAlign _textAlign = TextAlign.start;
    }

    this(dstring txt = null)
    {
        textobj.str = txt;
        minSizeTester.str = "aaaaa\na";
        natSizeTester.str =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
        heightDependsOnWidth = true;
        handleFontChanged();
    }

    mixin SupportCSS;

    override protected void handleFontChanged()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
        natSizeTester.style.font = fnt;
    }

    override Size computeMinSize()
    {
        textobj.style.flags = textFlags;
        minSizeTester.style.flags = textFlags;
        if (textobj.lines[0].length < minSizeTester.lines[0].length)
            return textobj.size;
        else
            return minSizeTester.size;
    }

    override Size computeNaturalSize()
    {
        natSizeTester.style.flags = textFlags;
        if (textobj.lines[0].length < natSizeTester.lines[0].length)
            return textobj.size;
        else
            return natSizeTester.size;
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
        Box b = box;
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);

        textobj.style.color = textColor;
        textobj.style.flags = textFlags;
        textobj.draw(buf, b.pos, b.w, textAlign);
    }
}

/// Multiline text widget with inner formatting
class MarkupLabel : Widget
{
}
