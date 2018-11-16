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
        override dstring text() const { return _text; }
        /// ditto
        override Label text(dstring s)
        {
            _text = s;
            requestLayout();
            return this;
        }
    }

    private
    {
        dstring _text;

        @forCSS("text-align") TextAlign _textAlign = TextAlign.start;

        immutable dstring minSizeTester = "aaaaa"; // TODO: test all this stuff
    }

    this(dstring txt = null)
    {
        _text = txt;
    }

    mixin SupportCSS;

    override Size computeMinSize()
    {
        dstring txt = text.length < minSizeTester.length * 2 ? text : minSizeTester;
        return font.textSize(txt, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
    }

    override Size computeNaturalSize()
    {
        return font.textSize(text, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = box;
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);

        FontRef f = font();
        // until text align will be fully implemented
        Align ha;
        if (textAlign == TextAlign.center)
            ha = Align.hcenter;
        else if (textAlign == TextAlign.end)
            ha = Align.right;
        else
            ha = Align.left;
        Size sz = f.textSize(text);
        applyAlign(b, sz, ha, Align.vcenter);
        f.drawText(buf, b.x, b.y, text, textColor, 4, 0, textFlags);
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
        override dstring text() const { return _text; }
        /// ditto
        override MultilineLabel text(dstring s)
        {
            _text = s;
            requestLayout();
            return this;
        }
    }

    private
    {
        dstring _text;

        @forCSS("text-align") TextAlign _textAlign = TextAlign.start;

        immutable dstring minSizeTester = "aaaaa\na";
        immutable dstring natSizeTester =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
    }

    this(dstring txt = null)
    {
        _text = txt;
        heightDependsOnWidth = true;
    }

    mixin SupportCSS;

    override Size computeMinSize()
    {
        dstring txt = text.length < minSizeTester.length ? text : minSizeTester;
        return font.measureMultilineText(txt, 0, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
    }

    override Size computeNaturalSize()
    {
        dstring txt = text.length < natSizeTester.length ? text : natSizeTester;
        return font.measureMultilineText(txt, 0, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        int w = width - p.w;
        return font.measureMultilineText(text, 0, w, 4, 0, textFlags).h + p.h;
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = box;
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);

        FontRef f = font();
        SimpleTextFormatter fmt;
        Size sz = fmt.format(text, f, 0, b.width, 4, 0, textFlags);
        fmt.draw(buf, b.x, b.y, f, textColor, textAlign);
    }
}

/// Multiline text widget with inner formatting
class MarkupLabel : Widget
{
}
