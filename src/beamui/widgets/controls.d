/**
This module contains simple controls widgets implementation.


Label - static text

ImageWidget - image

Button - button with text and image

LinkButton - URL link button

SwitchButton - switch widget

CheckBox - button with check mark

RadioButton - radio button

CanvasWidget - for drawing arbitrary graphics


Synopsis:
---
import beamui.widgets.controls;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.controls;

import beamui.core.stdaction;
import beamui.widgets.layouts;
import beamui.widgets.widget;

/// Static text widget
class Label : Widget
{
    @property
    {
        /// Max lines to show
        int maxLines() const
        {
            return style.maxLines;
        }
        /// Set max lines to show
        Label maxLines(int n)
        {
            ownStyle.maxLines = n;
            heightDependsOnWidth = n != 1;
            return this;
        }

        /// Get widget text
        override dstring text() const
        {
            return _text;
        }
        /// Set text to show
        override Label text(dstring s)
        {
            _text = s;
            requestLayout();
            return this;
        }
    }

    protected
    {
        dstring _text;
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
        Box b = _box;
        applyMargins(b);
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b, alpha);

        FontRef font = font();
        if (maxLines == 1)
        {
            Size sz = font.textSize(text);
            applyAlign(b, sz);
            font.drawText(buf, b.x, b.y, text, textColor, 4, 0, textFlags);
        }
        else
        {
            SimpleTextFormatter fmt;
            Size sz = fmt.format(text, font, maxLines, b.width, 4, 0, textFlags);
            applyAlign(b, sz);
            // TODO: apply align to alignment lines
            fmt.draw(buf, b.x, b.y, font, textColor);
        }
    }
}

/// Static text widget with multiline text
class MultilineLabel : Label
{
    this(dstring txt = null)
    {
        super(txt);
    }
}

/// Static image widget
class ImageWidget : Widget
{
    @property
    {
        /// Get drawable image id
        string drawableID() const
        {
            return _drawableID;
        }
        /// Set drawable image id
        ImageWidget drawableID(string id)
        {
            _drawableID = id;
            _drawable.clear();
            requestLayout();
            return this;
        }
        /// Get drawable
        ref DrawableRef drawable()
        {
            if (!_drawable.isNull)
                return _drawable;
            if (_drawableID !is null)
                _drawable = drawableCache.get(overrideCustomDrawableID(_drawableID));
            return _drawable;
        }
        /// Set custom drawable (not one from resources)
        ImageWidget drawable(DrawableRef img)
        {
            _drawable = img;
            _drawableID = null;
            return this;
        }
        /// Set custom drawable (not one from resources)
        ImageWidget drawable(string drawableID)
        {
            if (_drawableID == drawableID)
                return this;
            _drawableID = drawableID;
            _drawable.clear();
            requestLayout();
            return this;
        }
    }

    /// Set string property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setStringProperty", "string", "drawableID"));

    protected string _drawableID; // TODO: humanify
    protected DrawableRef _drawable;

    this(string drawableID = null)
    {
        _drawableID = drawableID;
    }

    ~this()
    {
        _drawable.clear();
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        if (_drawableID !is null)
            _drawable.clear(); // remove cached drawable
    }

    override Size computeMinSize()
    {
        DrawableRef img = drawable;
        if (!img.isNull)
            return Size(img.width, img.height);
        else
            return Size(0, 0);
    }

    override Size computeNaturalSize()
    {
        DrawableRef img = drawable;
        if (!img.isNull)
            return Size(img.width, img.height);
        else
            return Size(0, 0);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = _box;
        applyMargins(b);
        auto saver = ClipRectSaver(buf, b, alpha);
        applyPadding(b);
        DrawableRef img = drawable;
        if (!img.isNull)
        {
            Size sz = Size(img.width, img.height);
            applyAlign(b, sz);
            uint st = state;
            img.drawTo(buf, b, st);
        }
    }
}

/// Button, which can have icon, label, and can be checkable
class Button : LinearLayout, ActionHolder
{
    @property
    {
        /// Get icon drawable id
        string drawableID() const
        {
            return _icon.drawableID;
        }
        /// Set icon drawable
        Button drawableID(string id)
        {
            if (!id)
            {
                removeChild(_icon);
            }
            else if (!_icon)
            {
                _icon = new ImageWidget(id);
                _icon.id = "icon";
                _icon.bindSubItem(this, "icon");
                _icon.state = State.parent;
                addChild(_icon);
            }
            else
                _icon.drawableID = id;
            requestLayout();
            return this;
        }

        /// Action to emit on click
        Action action()
        {
            return _action;
        }
        /// ditto
        void action(Action a)
        {
            _action = a;
            a.changed ~= &updateContent;
            a.stateChanged ~= &updateState;
            updateContent();
            updateState();
        }
    }

    override @property
    {
        /// Orientation: vertical - image top, horizontal - image left
        Orientation orientation() const
        {
            return super.orientation;
        }
        /// ditto
        Button orientation(Orientation value)
        {
            super.orientation = value;
            if (_icon && _label && value != orientation)
            {
                if (value == Orientation.horizontal)
                {
                    _icon.alignment = Align.left | Align.vcenter;
                    _label.alignment = Align.right | Align.vcenter;
                }
                else
                {
                    _icon.alignment = Align.top | Align.hcenter;
                    _label.alignment = Align.bottom | Align.hcenter;
                }
                requestLayout();
            }
            return this;
        }

        /// Get label text
        dstring text() const
        {
            return _label ? _label.text : null;
        }
        /// Set label plain unicode string
        Button text(dstring s)
        {
            if (!s)
            {
                removeChild(_label);
            }
            else if (!_label)
            {
                _label = new Label(s);
                _label.id = "label";
                _label.fillW();
                _label.bindSubItem(this, "label");
                _label.state = State.parent;
                addChild(_label);
            }
            else
                _label.text = s;
            requestLayout();
            return this;
        }

        uint textColor() const
        {
            return _label ? _label.textColor : 0;
        }
        Button textColor(string colorString)
        {
            _label.maybe.textColor(colorString);
            return this;
        }
        Button textColor(uint value)
        {
            _label.maybe.textColor(value);
            return this;
        }

        TextFlag textFlags() const
        {
            return _label ? _label.textFlags : TextFlag.unspecified;
        }
        Button textFlags(TextFlag value)
        {
            _label.maybe.textFlags(value);
            return this;
        }

        string fontFace() const
        {
            return _label ? _label.fontFace : null;
        }
        Button fontFace(string face)
        {
            _label.maybe.fontFace(face);
            return this;
        }

        FontFamily fontFamily() const
        {
            return _label ? _label.fontFamily : FontFamily.unspecified;
        }
        Button fontFamily(FontFamily family)
        {
            _label.maybe.fontFamily(family);
            return this;
        }

        bool fontItalic() const
        {
            return _label ? _label.fontItalic : false;
        }
        Button fontItalic(bool italic)
        {
            _label.maybe.fontItalic(italic);
            return this;
        }

        int fontSize() const
        {
            return _label ? _label.fontSize : 0;
        }
        Button fontSize(int size)
        {
            _label.maybe.fontSize(size);
            return this;
        }

        ushort fontWeight() const
        {
            return _label ? _label.fontWeight : 0;
        }
        Button fontWeight(int weight)
        {
            _label.maybe.fontWeight(weight);
            return this;
        }

        FontRef font() const
        {
            return _label ? _label.font : FontRef.init;
        }
    }

    protected
    {
        ImageWidget _icon;
        Label _label;

        Action _action;
    }

    this(dstring caption = null, string drawableID = null, bool checkable = false)
    {
        super(Orientation.horizontal);
        this.drawableID = drawableID;
        this.text = caption;
        this.checkable = checkable;
        clickable = true;
        focusable = true;
        trackHover = true;
    }

    /// Constructor from action by click
    this(Action a)
    {
        this();
        id = "button-action-" ~ to!string(a.label);
        action = a;
    }

    ~this()
    {
        if (_action)
        {
            _action.changed -= &updateContent;
            _action.stateChanged -= &updateState;
        }
    }

    protected void updateContent()
    {
        drawableID = _action.iconID;
        text = _action.label;
        checkable = _action.checkable;
    }

    protected void updateState()
    {
        enabled = _action.enabled;
        checked = _action.checked;
        visibility = _action.visible ? Visibility.visible : Visibility.gone;
    }

    override protected bool handleClick()
    {
        if (auto w = window)
            w.call(_action);
        if (checkable)
            checked = !checked;
        return super.handleClick();
    }

    override @property bool hasTooltip()
    {
        return action && action.label;
    }

    override Widget createTooltip(int mouseX, int mouseY, ref PopupAlign alignment, ref int x, ref int y)
    {
        return new Label(action.tooltipText).id("tooltip");
    }

    /// Set string property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setStringProperty", "string", "drawableID"));
}

/// Button looking like URL, executing specified action
class LinkButton : Button // FIXME: in horizontal layout this button expands horizontally
{
    this(dstring labelText, string url, string icon = "applications-internet")
    {
        import beamui.platforms.common.platform;

        super(labelText, icon);
        auto a = new Action(labelText, icon); // TODO: consider link hotkeys
        a.bind(this, { platform.openURL(url); });
        action = a;
    }

    override CursorType getCursorType(int x, int y) // doesn't work for actual text, FIXME!
    {
        return CursorType.hand;
    }
}

/// Switch (on/off) widget
class SwitchButton : Widget
{
    this()
    {
        clickable = true;
        focusable = true;
        trackHover = true;
    }

    override protected bool handleClick()
    {
        checked = !checked;
        return super.handleClick();
    }

    override Size computeMinSize()
    {
        DrawableRef img = backgroundDrawable;
        if (!img.isNull)
            return Size(img.width, img.height);
        else
            return Size(0, 0);
    }

    override Size computeNaturalSize()
    {
        DrawableRef img = backgroundDrawable;
        if (!img.isNull)
            return Size(img.width, img.height);
        else
            return Size(0, 0);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        Box b = _box;
        applyMargins(b);
        auto saver = ClipRectSaver(buf, b, alpha);
        DrawableRef img = backgroundDrawable;
        if (!img.isNull)
        {
            Size sz = Size(img.width, img.height);
            applyAlign(b, sz);
            uint st = state;
            img.drawTo(buf, b, st);
        }
        _needDraw = false;
    }
}

/// Check box
class CheckBox : LinearLayout
{
    protected
    {
        Widget _icon;
        Label _label;
    }

    this(dstring labelText = null)
    {
        super(Orientation.horizontal);
        this.checkable = checkable;
        _icon = new Widget("icon");
        _icon.bindSubItem(this, "icon");
        _icon.state = State.parent;
        _label = new Label(labelText);
        _label.id = "label";
        _label.bindSubItem(this, "label");
        _label.state = State.parent;
        addChild(_icon);
        addChild(_label);
        if (!labelText)
            spacing = 0;
        clickable = true;
        focusable = true;
        trackHover = true;
    }

    override protected bool handleClick()
    {
        checked = !checked;
        return super.handleClick();
    }
}

/// Radio button
class RadioButton : CheckBox
{
    this(dstring labelText = null)
    {
        super(labelText);
    }

    private bool blockUnchecking = false;

    void uncheckSiblings()
    {
        Widget p = parent;
        if (!p)
            return;
        foreach (i; 0 .. p.childCount)
        {
            Widget child = p.child(i);
            if (child is this)
                continue;
            auto rb = cast(RadioButton)child;
            if (rb)
            {
                // deactivate siblings
                rb.blockUnchecking = true;
                scope (exit)
                    rb.blockUnchecking = false;
                rb.checked = false;
            }
        }
    }

    override protected bool handleClick()
    {
        uncheckSiblings();
        return super.handleClick();
    }

    override protected void handleCheckChange(bool checked)
    {
        if (!blockUnchecking)
            uncheckSiblings();
    }
}

/// Canvas widget - draw on it either by overriding of doDraw() or by assigning of `drawCalled`
class CanvasWidget : Widget
{
    Listener!(void delegate(DrawBuf buf, Box area)) drawCalled;

    void doDraw(DrawBuf buf, Box area)
    {
        if (drawCalled.assigned)
            drawCalled(buf, area);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        Box b = _box;
        applyMargins(b);
        auto saver = ClipRectSaver(buf, b, alpha);
        applyPadding(b);
        doDraw(buf, b);
    }
}
