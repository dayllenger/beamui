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
        Label textAlign(TextAlign a)
        {
            setProperty!"_textAlign" = a;
            return this;
        }
        private alias textAlign_effect = invalidate;

        /// Text to show
        override dstring text() const { return textobj.text; }
        /// ditto
        override Label text(dstring s)
        {
            textobj.text = s;
            requestLayout();
            return this;
        }
    }

    private
    {
        SingleLineText textobj;

        @forCSS("text-align") TextAlign _textAlign = TextAlign.start;

        immutable dstring minSizeTester = "aaaaa"; // TODO: test all this stuff
    }

    this(dstring txt = null)
    {
        textobj.text = txt;
    }

    mixin SupportCSS;

    override protected void handleFontChanged()
    {
        textobj.font = font;
    }

    override Size computeMinSize()
    {
        dstring txt = text.length < minSizeTester.length * 2 ? text : minSizeTester;
        return font.textSize(txt, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
    }

    override Size computeNaturalSize()
    {
        textobj.measure(textFlags);
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

        // align vertically to center
        Size sz = Size(b.w, textobj.size.h);
        applyAlign(b, sz, Align.unspecified, Align.vcenter);
        textobj.draw(buf, b.pos, b.w, textColor, textAlign, textFlags);
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
        MultilineLabel textAlign(TextAlign a)
        {
            setProperty!"_textAlign" = a;
            return this;
        }
        private alias textAlign_effect = invalidate;

        /// Text to show
        override dstring text() const { return textobj.text; }
        /// ditto
        override MultilineLabel text(dstring s)
        {
            textobj.text = s;
            requestLayout();
            return this;
        }
    }

    private
    {
        PlainText textobj;

        @forCSS("text-align") TextAlign _textAlign = TextAlign.start;

        immutable dstring minSizeTester = "aaaaa\na";
        immutable dstring natSizeTester =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
    }

    this(dstring txt = null)
    {
        textobj.text = txt;
        heightDependsOnWidth = true;
    }

    mixin SupportCSS;

    override protected void handleFontChanged()
    {
        textobj.font = font;
    }

    override Size computeMinSize()
    {
        dstring txt = text.length < minSizeTester.length ? text : minSizeTester;
        return font.measureMultilineText(txt, 0, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
    }

    override Size computeNaturalSize()
    {
        textobj.measure(textFlags);
        if (text.length < natSizeTester.length)
            return textobj.size;
        else
            return font.measureMultilineText(natSizeTester, 0, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        int w = width - p.w;
        textobj.wrapLines(w);
        return textobj.size.h + p.h;
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = box;
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);

        textobj.draw(buf, b.pos, b.w, textColor, textAlign, textFlags);
    }
}

/// Multiline text widget with inner formatting
class MarkupLabel : Widget
{
}
