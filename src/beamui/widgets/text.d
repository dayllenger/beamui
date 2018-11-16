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
        /// Max lines to show, 0 if no limit
        int maxLines() const
        {
            updateStyles();
            return _maxLines;
        }
        /// ditto
        Label maxLines(int n)
        {
            setProperty!"_maxLines" = n;
            return this;
        }
        private void maxLines_effect(int n)
        {
            heightDependsOnWidth = n != 1;
        }

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

        @forCSS("max-lines") int _maxLines = 1;
        @forCSS("text-align") TextAlign _textAlign = TextAlign.start;

        immutable dstring minSizeTesterS = "aaaaa"; // TODO: test all this stuff
        immutable dstring minSizeTesterM = "aaaaa\na";
        immutable dstring natSizeTesterM =
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\na";
    }

    this(dstring txt = null)
    {
        _text = txt;
        heightDependsOnWidth = maxLines != 1;
    }

    mixin SupportCSS;

    override Size computeMinSize()
    {
        FontRef f = font();
        if (maxLines == 1)
        {
            dstring txt = text.length < minSizeTesterS.length * 2 ? text : minSizeTesterS;
            return f.textSize(txt, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
        }
        else
        {
            dstring txt = text.length < minSizeTesterM.length ? text : minSizeTesterM;
            return f.measureMultilineText(txt, maxLines, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
        }
    }

    override Size computeNaturalSize()
    {
        FontRef f = font();
        if (maxLines == 1)
            return f.textSize(text, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
        else
        {
            dstring txt = text.length < natSizeTesterM.length ? text : natSizeTesterM;
            return f.measureMultilineText(txt, maxLines, MAX_WIDTH_UNSPECIFIED, 4, 0, textFlags);
        }
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        int w = width - p.w;
        FontRef f = font();
        return f.measureMultilineText(text, maxLines, w, 4, 0, textFlags).h + p.h;
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = box;
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);

        FontRef font = font();
        if (maxLines == 1)
        {
            // until text align will be fully implemented
            Align ha;
            if (textAlign == TextAlign.center)
                ha = Align.hcenter;
            else if (textAlign == TextAlign.end)
                ha = Align.right;
            else
                ha = Align.left;
            Size sz = font.textSize(text);
            applyAlign(b, sz, ha, Align.vcenter);
            font.drawText(buf, b.x, b.y, text, textColor, 4, 0, textFlags);
        }
        else
        {
            SimpleTextFormatter fmt;
            Size sz = fmt.format(text, font, maxLines, b.width, 4, 0, textFlags);
            fmt.draw(buf, b.x, b.y, font, textColor, textAlign);
        }
    }
}

/// Multiline text widget
class MultilineLabel : Label
{
    this(dstring txt = null)
    {
        super(txt);
    }
}

/// Multiline text widget with inner formatting
class MarkupLabel : Widget
{
}
