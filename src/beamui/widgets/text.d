/**
Widgets to show plain or formatted single- and multiline text.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.widgets.text;

import beamui.text.simple;
import beamui.text.sizetest;
import beamui.text.style : TextHotkey;
import beamui.widgets.widget;

/// Single-line text widget
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
        SimpleText textobj;
        TextSizeTester minSizeTester;
    }

    this(dstring txt = null)
    {
        textobj.str = txt;
        minSizeTester.str = "aaaaa";
        handleFontChange();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            textobj.style.tabSize = style.tabSize;
            break;
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorColor:
            textobj.style.decoration.color = style.textDecorColor;
            break;
        case textDecorLine:
            textobj.style.decoration.line = style.textDecorLine;
            break;
        case textDecorStyle:
            textobj.style.decoration.style = style.textDecorStyle;
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
        textobj.measure();

        Boundaries bs;
        const sz = textobj.size;
        const tmin = minSizeTester.getSize();
        bs.min.w = min(sz.w, tmin.w);
        bs.min.h = min(sz.h, tmin.h);
        bs.nat = sz;
        setBoundaries(bs);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        // align vertically to center
        const sz = Size(b.w, textobj.size.h);
        b = alignBox(b, sz, Align.vcenter);
        textobj.draw(buf, b.x, b.y, b.w);
    }
}

/// Efficient single-line text widget. Can contain `&` character to underline a mnemonic
class ShortLabel : Widget
{
    @property
    {
        /// Text to show
        override dstring text() const { return original; }
        /// ditto
        override void text(dstring s)
        {
            if (style.textHotkey != TextHotkey.ignore)
            {
                auto r = extractMnemonic(s);
                textobj.str = r[0];
                hotkeyIndex = r[1];
            }
            else
            {
                textobj.str = s;
                hotkeyIndex = -1;
            }
            original = s;
            requestLayout();
        }

        /// Get the hotkey (mnemonic) character for the label (e.g. 'F' for `&File`).
        /// 0 if no hotkey or if disabled in styles
        dchar hotkey() const
        {
            import std.uni : toUpper;

            if (hotkeyIndex >= 0)
                return toUpper(textobj.str[hotkeyIndex]);
            else
                return 0;
        }
    }

    private
    {
        dstring original;
        int hotkeyIndex = -1;
        SimpleText textobj;
        TextSizeTester minSizeTester;
    }

    this(dstring txt = null)
    {
        text = txt;
        minSizeTester.str = "aaaaa";
        handleFontChange();
    }

    override void handleStyleChange(StyleProperty ptype)
    {
        super.handleStyleChange(ptype);

        switch (ptype) with (StyleProperty)
        {
        case tabSize:
            textobj.style.tabSize = style.tabSize;
            break;
        case textHotkey:
            // recompute the mnemonic
            if (hotkeyIndex == -1 && style.textHotkey != TextHotkey.ignore)
            {
                auto r = extractMnemonic(original);
                textobj.str = r[0];
                hotkeyIndex = r[1];
            }
            else if (hotkeyIndex >= 0 && style.textHotkey == TextHotkey.ignore)
            {
                textobj.str = original;
                hotkeyIndex = -1;
            }
            break;
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorColor:
            textobj.style.decoration.color = style.textDecorColor;
            break;
        case textDecorLine:
            textobj.style.decoration.line = style.textDecorLine;
            break;
        case textDecorStyle:
            textobj.style.decoration.style = style.textDecorStyle;
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
        textobj.measure();

        Boundaries bs;
        const sz = textobj.size;
        const tmin = minSizeTester.getSize();
        bs.min.w = min(sz.w, tmin.w);
        bs.min.h = min(sz.h, tmin.h);
        bs.nat = sz;
        setBoundaries(bs);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        textobj.style.underlinedCharIndex = textHotkey == TextHotkey.underline ? hotkeyIndex : -1;

        // align vertically to center
        Size sz = Size(b.w, textobj.size.h);
        b = alignBox(b, sz, Align.vcenter);
        textobj.draw(buf, b.x, b.y, b.w);
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
        SimpleText textobj;
        TextSizeTester minSizeTester;
        TextSizeTester natSizeTester;
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
        case tabSize:
            textobj.style.tabSize = style.tabSize;
            break;
        case textAlign:
            textobj.style.alignment = style.textAlign;
            break;
        case textColor:
            textobj.style.color = style.textColor;
            break;
        case textDecorColor:
            textobj.style.decoration.color = style.textDecorColor;
            break;
        case textDecorLine:
            textobj.style.decoration.line = style.textDecorLine;
            break;
        case textDecorStyle:
            textobj.style.decoration.style = style.textDecorStyle;
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
        textobj.measure();

        Boundaries bs;
        const sz = textobj.size;
        const tmin = minSizeTester.getSize();
        const tnat = natSizeTester.getSize();
        bs.min.w = min(sz.w, tmin.w);
        bs.min.h = min(sz.h, tmin.h);
        bs.nat.w = min(sz.w, tnat.w);
        bs.nat.h = min(sz.h, tnat.h);
        setBoundaries(bs);
    }

    override int heightForWidth(int width)
    {
        Size p = padding.size;
        int w = width - p.w;
        textobj.wrap(w);
        return textobj.sizeAfterWrap.h + p.h;
    }

    override void layout(Box geom)
    {
        if (visibility == Visibility.gone)
            return;

        super.layout(geom);
        // wrap again in case the parent widget had not called heightForWidth
        // must be cached when width is the same
        int w = geom.w - padding.width;
        textobj.wrap(w);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = innerBox;
        auto saver = ClipRectSaver(buf, b, style.alpha);

        textobj.draw(buf, b.x, b.y, b.w);
    }
}

/// Multiline text widget with inner formatting
class MarkupLabel : Widget
{
}

private Tup!(dstring, int) extractMnemonic(dstring s)
{
    if (s.length < 2)
        return tup(s, -1);

    const len = cast(int)s.length;
    bool found;
    foreach (i; 0 .. len - 1)
    {
        if (s[i] == '&')
        {
            found = true;
            break;
        }
    }
    if (found)
    {
        dchar[] result = new dchar[len];
        int pos = -1;
        found = false;
        int j;
        foreach (i; 0 .. len)
        {
            if (s[i] == '&' && !found)
                found = true;
            else
            {
                if (found && pos == -1 && s[i] != '&')
                    pos = j;
                result[j++] = s[i];
                found = false;
            }
        }
        return tup(cast(dstring)result[0 .. j], pos);
    }
    else
        return tup(s, -1);
}

unittest
{
    assert(extractMnemonic(""d) == tup(""d, -1));
    assert(extractMnemonic("a"d) == tup("a"d, -1));
    assert(extractMnemonic("&"d) == tup("&"d, -1));
    assert(extractMnemonic("abc123"d) == tup("abc123"d, -1));
    assert(extractMnemonic("&File"d) == tup("File"d, 0));
    assert(extractMnemonic("A && B"d) == tup("A & B"d, -1));
    assert(extractMnemonic("A &&& &B"d) == tup("A & B"d, 3));
    assert(extractMnemonic("&A&B&C&&D"d) == tup("ABC&D"d, 0));
    assert(extractMnemonic("a &"d) == tup("a &"d, -1));
}
