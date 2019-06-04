/**
Simple controls - images, buttons, and so on.

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
                _icon.id = "icon";
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
                _icon.id = "icon";
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
                _action.changed -= &updateContent;
                _action.stateChanged -= &updateState;
            }
            _action = a;
            if (a)
            {
                a.changed ~= &updateContent;
                a.stateChanged ~= &updateState;
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
                _label = new ShortLabel(s);
                _label.id = "label";
                _label.bindSubItem(this, "label");
                _label.state = State.parent;
                add(_label).setFillWidth(true).setFillHeight(false);
            }
        }
    }

    private
    {
        ImageWidget _icon;
        ShortLabel _label;

        Action _action;
    }

    this(dstring caption = null, string iconID = null, bool checkable = false)
    {
        super(Orientation.horizontal);
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
            _action.changed -= &updateContent;
            _action.stateChanged -= &updateState;
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
        super.handleClick();
    }
}

/// Hyperlink button. Like `Button`, may execute arbitrary actions.
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
        allowsClick = true;
        allowsFocus = true;
        allowsHover = true;
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
        ShortLabel _label;
    }

    this(dstring labelText = null)
    {
        super(Orientation.horizontal);
        _icon = new Widget("icon");
        _icon.bindSubItem(this, "icon");
        _icon.state = State.parent;
        _label = new ShortLabel(labelText);
        _label.id = "label";
        _label.bindSubItem(this, "label");
        _label.state = State.parent;
        add(_icon);
        add(_label).setFillHeight(false);
        if (!labelText)
            _label.visibility = Visibility.gone;
        allowsClick = true;
        allowsFocus = true;
        allowsHover = true;
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

/// Canvas widget - draw arbitrary graphics on it either by overriding of `doDraw()` or by setting `drawCalled`
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
