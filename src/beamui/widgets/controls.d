/**
Simple controls - images, buttons, and so on.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.controls;

import beamui.core.stdaction;
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
            if (id.length)
            {
                auto img = imageCache.get(id);
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
            requestLayout();
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

    override protected void drawContent(DrawBuf buf)
    {
        DrawableRef img = _drawable;
        if (!img.isNull)
        {
            const sz = Size(img.width, img.height);
            const ib = alignBox(innerBox, sz, Align.center);
            img.drawTo(buf, ib);
        }
    }
}

/// Button, which can have icon, label, and can be checkable
class Button : Panel, ActionHolder
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
            const some = id.length > 0;
            if (_icon)
            {
                if (some)
                    _icon.imageID = id;
                _icon.visibility = some ? Visibility.visible : Visibility.gone;
            }
            else if (some)
            {
                _icon = new ImageWidget(id);
                _icon.bindSubItem(this, "icon");
                _icon.state = State.parent;
                add(_icon);
            }
        }

        /// Set custom drawable for icon
        void drawable(DrawableRef img)
        {
            const some = !img.isNull;
            if (_icon)
            {
                if (some)
                    _icon.drawable = img;
                _icon.visibility = some ? Visibility.visible : Visibility.gone;
            }
            else if (some)
            {
                _icon = new ImageWidget;
                _icon.bindSubItem(this, "icon");
                _icon.state = State.parent;
                _icon.drawable = img;
                add(_icon);
            }
        }

        /// Action to emit on click
        inout(Action) action() inout { return _action; }
        /// ditto
        void action(Action a)
        {
            if (_action)
            {
                _action.onChange -= &updateContent;
                _action.onStateChange -= &updateState;
            }
            _action = a;
            if (a)
            {
                a.onChange ~= &updateContent;
                a.onStateChange ~= &updateState;
                updateContent();
                updateState();
            }
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
            const some = s.length > 0;
            if (_label)
            {
                if (some)
                    _label.text = s;
                _label.visibility = some ? Visibility.visible : Visibility.gone;
            }
            else if (some)
            {
                _label = new Label(s);
                _label.bindSubItem(this, "label");
                _label.state = State.parent;
                add(_label);
            }
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
        this.iconID = iconID;
        this.text = caption;
        allowsClick = true;
        allowsFocus = true;
        allowsHover = true;
        allowsToggle = checkable;
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
            _action.onChange -= &updateContent;
            _action.onStateChange -= &updateState;
        }
    }

    protected void updateContent()
    {
        iconID = _action.iconID;
        text = _action.label;
        allowsToggle = _action.checkable;
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
        if (allowsToggle)
            checked = !checked;
    }
}

/// Hyperlink button. Like `Button`, may execute arbitrary actions.
class LinkButton : Button
{
    import beamui.platforms.common.platform : platform;

    this(dstring labelText, string url, string icon = "applications-internet")
    {
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
        allowsClick = true;
        allowsFocus = true;
        allowsHover = true;
    }

    override protected void handleClick()
    {
        checked = !checked;
    }

    override void measure()
    {
        const bg = background;
        const sz = Size(bg.width, bg.height);
        setBoundaries(Boundaries(sz, sz, sz));
    }
}

/// Check button that can be toggled on or off
class CheckBox : Panel
{
    private
    {
        Widget _icon;
        Label _label;
    }

    this(dstring labelText = null)
    {
        _icon = new Widget("icon");
        _icon.bindSubItem(this, "icon");
        _icon.state = State.parent;
        _label = new Label(labelText);
        _label.bindSubItem(this, "label");
        _label.state = State.parent;
        add(_icon, _label);
        if (!labelText)
            _label.visibility = Visibility.gone;
        allowsClick = true;
        allowsFocus = true;
        allowsHover = true;
    }

    override protected void handleClick()
    {
        checked = !checked;
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

/// Canvas widget - draw arbitrary graphics on it either by overriding of `doDraw()` or by setting `onDraw`
class CanvasWidget : Widget
{
    Listener!(void delegate(DrawBuf buf, Box area)) onDraw;

    void doDraw(DrawBuf buf, Box area)
    {
        if (onDraw.assigned)
            onDraw(buf, area);
    }

    override protected void drawContent(DrawBuf buf)
    {
        doDraw(buf, innerBox);
    }
}
