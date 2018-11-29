/**
Simple controls - images, buttons, and so on.

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
import beamui.widgets.text;
import beamui.widgets.widget;

/// Static image widget. Can accept any drawable instead of the image (e.g. a gradient).
class ImageWidget : Widget
{
    @property
    {
        /// Resource id for this image
        string imageID() const { return _imageID; }
        /// ditto
        void imageID(string id)
        {
            _imageID = id;
            _drawable.clear();
            if (_imageID)
            {
                auto img = imageCache.get(_imageID);
                if (!img.isNull)
                    _drawable = new ImageDrawable(img);
            }
            requestLayout();
        }

        /// Set custom drawable to show (not one from resources) instead of image
        void drawable(DrawableRef img)
        {
            imageID = null;
            _drawable = img;
        }
    }

    /// Set string property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setStringProperty", "string", "imageID"));

    private string _imageID;
    private DrawableRef _drawable;

    this(string imageID = null)
    {
        this.imageID = imageID;
    }

    ~this()
    {
        _drawable.clear();
    }

    override Size computeMinSize()
    {
        DrawableRef img = _drawable;
        if (!img.isNull)
            return Size(img.width, img.height);
        else
            return Size(0, 0);
    }

    override Size computeNaturalSize()
    {
        DrawableRef img = _drawable;
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
        Box b = box;
        auto saver = ClipRectSaver(buf, b, alpha);
        applyPadding(b);
        DrawableRef img = _drawable;
        if (!img.isNull)
        {
            Size sz = Size(img.width, img.height);
            applyAlign(b, sz, Align.hcenter, Align.vcenter);
            img.drawTo(buf, b);
        }
    }
}

/// Button, which can have icon, label, and can be checkable
class Button : LinearLayout, ActionHolder
{
    @property
    {
        /// Icon id
        string iconID() const
        {
            return _icon ? _icon.imageID : null;
        }
        /// ditto
        void iconID(string id)
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
                add(_icon);
            }
            else
                _icon.imageID = id;
            requestLayout();
        }

        /// Set custom drawable for icon
        void drawable(DrawableRef img)
        {
            if (!_icon)
            {
                _icon = new ImageWidget;
                _icon.id = "icon";
                _icon.bindSubItem(this, "icon");
                _icon.state = State.parent;
                add(_icon);
            }
            _icon.drawable = img;
        }

        /// Action to emit on click
        Action action() { return _action; }
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
        /// Get label text
        dstring text() const
        {
            return _label ? _label.text : null;
        }
        /// Set label plain unicode string
        void text(dstring s)
        {
            if (!s)
            {
                removeChild(_label);
            }
            else if (!_label)
            {
                _label = new Label(s);
                _label.id = "label";
                _label.bindSubItem(this, "label");
                _label.state = State.parent;
                add(_label).fillWidth(true).fillHeight(false);
            }
            else
                _label.text = s;
            requestLayout();
        }

        Color textColor() const
        {
            return _label ? _label.textColor : Color(0x0);
        }
        void textColor(string colorString)
        {
            _label.maybe.textColor(colorString);
        }
        void textColor(Color value)
        {
            _label.maybe.textColor(value);
        }

        string fontFace() const
        {
            return _label ? _label.fontFace : null;
        }
        void fontFace(string face)
        {
            _label.maybe.fontFace(face);
        }

        FontFamily fontFamily() const
        {
            return _label ? _label.fontFamily : FontFamily.unspecified;
        }
        void fontFamily(FontFamily family)
        {
            _label.maybe.fontFamily(family);
        }

        bool fontItalic() const
        {
            return _label ? _label.fontItalic : false;
        }
        void fontItalic(bool italic)
        {
            _label.maybe.fontItalic(italic);
        }

        int fontSize() const
        {
            return _label ? _label.fontSize : 0;
        }
        void fontSize(int size)
        {
            _label.maybe.fontSize(size);
        }

        ushort fontWeight() const
        {
            return _label ? _label.fontWeight : 0;
        }
        void fontWeight(ushort weight)
        {
            _label.maybe.fontWeight(weight);
        }

        FontRef font() const
        {
            return _label ? _label.font : FontRef.init;
        }
    }

    private
    {
        ImageWidget _icon;
        Label _label;

        Action _action;
    }

    this(dstring caption = null, string iconID = null, bool checkable = false)
    {
        super(Orientation.horizontal);
        this.iconID = iconID;
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
        iconID = _action.iconID;
        text = _action.label;
        checkable = _action.checkable;
    }

    protected void updateState()
    {
        enabled = _action.enabled;
        checked = _action.checked;
        visibility = _action.visible ? Visibility.visible : Visibility.gone;
    }

    override protected void handleClick()
    {
        if (auto w = window)
            w.call(_action);
        if (checkable)
            checked = !checked;
        super.handleClick();
    }

    /// Set string property value, for ML loaders
    mixin(generatePropertySettersMethodOverride("setStringProperty", "string", "iconID"));
}

/// Hyperlink button. Like Button, may execute arbitrary actions.
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

    override protected void handleClick()
    {
        checked = !checked;
        super.handleClick();
    }

    override Size computeMinSize()
    {
        auto bg = background;
        return Size(bg.width, bg.height);
    }

    override Size computeNaturalSize()
    {
        auto bg = background;
        return Size(bg.width, bg.height);
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        Box b = box;
        auto saver = ClipRectSaver(buf, b, alpha);

        auto bg = background;
        bg.drawTo(buf, b);

        drawn();
    }
}

/// Check button that can be toggled on or off
class CheckBox : LinearLayout
{
    private
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
        add(_icon);
        add(_label).fillHeight(false);
        if (!labelText)
            spacing = 0;
        clickable = true;
        focusable = true;
        trackHover = true;
    }

    override protected void handleClick()
    {
        checked = !checked;
        if (clicked.assigned)
            clicked(this);
    }
}

/// Radio button control, which is a mutually exclusive check box
class RadioButton : CheckBox
{
    this(dstring labelText = null)
    {
        super(labelText);
    }

    override protected void handleClick()
    {
        checked = true;
        if (clicked.assigned)
            clicked(this);
    }

    override protected void handleCheckChange(bool checked)
    {
        if (!blockUnchecking)
            uncheckSiblings();
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
}

/// Canvas widget - draw arbitrary graphics on it either by overriding of doDraw() or by assigning of `drawCalled`
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
        Box b = box;
        auto saver = ClipRectSaver(buf, b, alpha);
        applyPadding(b);
        doDraw(buf, b);
    }
}
