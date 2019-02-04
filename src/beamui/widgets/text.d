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

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorationColor:
            textobj.style.decoration.color = style.textDecorationColor;
            break;
        case textDecorationLine:
            textobj.style.decoration.line = style.textDecorationLine;
            break;
        case textDecorationStyle:
            textobj.style.decoration.style = style.textDecorationStyle;
            break;
        case textOverflow:
            textobj.style.overflow = style.textOverflow;
            break;
        case textTransform:
            textobj.style.transform = style.textTransform;
            minSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
    }

    override void measure()
    {
        textobj.style.hotkey = textHotkey;
        textobj.measure();

        Boundaries bs;
        // min size
        if (textobj.str.length < minSizeTester.str.length * 2)
        {
            bs.min = textobj.size;
        }
        else
        {
            minSizeTester.style.hotkey = textHotkey;
            minSizeTester.measure();
            bs.min = minSizeTester.size;
        }
        // nat size
        bs.nat = textobj.size;
        setBoundaries(bs);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        textobj.style.hotkey = textHotkey;
        // align vertically to center
        Size sz = Size(b.w, textobj.size.h);
        applyAlign(b, sz, Align.unspecified, Align.vcenter);
        textobj.draw(buf, b.pos, b.w);
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
        dependentSize = DependentSize.height;
        handleFontChange();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorationColor:
            textobj.style.decoration.color = style.textDecorationColor;
            break;
        case textDecorationLine:
            textobj.style.decoration.line = style.textDecorationLine;
            break;
        case textDecorationStyle:
            textobj.style.decoration.style = style.textDecorationStyle;
            break;
        case textOverflow:
            textobj.style.overflow = style.textOverflow;
            break;
        case textTransform:
            textobj.style.transform = style.textTransform;
            minSizeTester.style.transform = style.textTransform;
            natSizeTester.style.transform = style.textTransform;
            break;
        default:
            break;
        }
    }

    override protected void handleFontChange()
    {
        Font fnt = font.get;
        textobj.style.font = fnt;
        minSizeTester.style.font = fnt;
        natSizeTester.style.font = fnt;
    }

    override void measure()
    {
        textobj.style.hotkey = textHotkey;
        textobj.measure();

        Boundaries bs;
        // min size
        if (textobj.lines[0].length < minSizeTester.lines[0].length)
        {
            bs.min = textobj.size;
        }
        else
        {
            minSizeTester.style.hotkey = textHotkey;
            minSizeTester.measure();
            bs.min = minSizeTester.size;
        }
        // nat size
        if (textobj.lines[0].length < natSizeTester.lines[0].length)
        {
            bs.nat = textobj.size;
        }
        else
        {
            natSizeTester.style.hotkey = textHotkey;
            natSizeTester.measure();
            bs.nat = natSizeTester.size;
        }
        setBoundaries(bs);
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

        textobj.style.hotkey = textHotkey;
        textobj.draw(buf, b.pos, b.w);
    }
}

/// Multiline text widget with inner formatting
class MarkupLabel : Widget
{
}
