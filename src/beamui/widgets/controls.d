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

    override void measure()
    {
        Size sz;
        DrawableRef img = _drawable;
        if (!img.isNull)
            sz = Size(img.width, img.height);
        setBoundaries(Boundaries(sz, sz));
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.onDraw(buf);
        const saver = ClipRectSaver(buf, box, style.alpha);
        Box b = innerBox;
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
        inout(Action) action() inout { return _action; }
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
                add(_label).setFillWidth(true).setFillHeight(false);
            }
            else
                _label.text = s;
            requestLayout();
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

    override CursorType getCursorType(int x, int y) const // doesn't work for actual text, FIXME!
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

    override void measure()
    {
        const bg = background;
        const sz = Size(bg.width, bg.height);
        setBoundaries(Boundaries(sz, sz, sz));
    }

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        Box b = box;
        auto saver = ClipRectSaver(buf, b, style.alpha);

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
        add(_label).setFillHeight(false);
        if (!labelText)
            _label.visibility = Visibility.gone;
        clickable = true;
        focusable = true;
        trackHover = true;
    }

    override protected void handleClick()
    {
        checked = !checked;
        clicked();
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
        clicked();
    }

    override protected void handleToggling(bool checked)
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
        const saver = ClipRectSaver(buf, box, style.alpha);
        doDraw(buf, innerBox);
    }
}
