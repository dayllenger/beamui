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

alias ElemImage = ImageWidget;
alias ElemSwitch = SwitchButton;
alias ElemCanvas = CanvasWidget;

class NgImageWidget : NgWidget
{
    string imageID;

    static NgImageWidget make(string imageID)
    {
        NgImageWidget w = arena.make!NgImageWidget;
        w.imageID = imageID;
        return w;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemImage;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemImage el = fastCast!ElemImage(element);
        el.imageID = imageID;
    }
}

class NgButton : NgPanel
{
    dstring text;
    string icon;
    void delegate() onClick;

    static NgButton make(dstring text, void delegate() onClick)
    {
        NgButton w = arena.make!NgButton;
        w.text = text;
        w.onClick = onClick;
        return w;
    }

    static NgButton make(dstring text, string icon, void delegate() onClick)
    {
        NgButton w = arena.make!NgButton;
        w.text = text;
        w.icon = icon;
        w.onClick = onClick;
        return w;
    }

    this()
    {
        allowsFocus = true;
        allowsHover = true;
        isolateStyle = true;
    }

    override protected void build()
    {
        NgImageWidget image;
        if (icon.length)
        {
            image = NgImageWidget.make(icon);
            image.setAttribute("icon");
            image.inheritState = true;
        }
        NgLabel label;
        if (text.length)
        {
            label = NgLabel.make(text);
            label.setAttribute("label");
            label.inheritState = true;
        }
        attach(image, label);
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPanel el = fastCast!ElemPanel(element);
        el.allowsClick = true;
        el.onClick.clear();
        if (onClick)
            el.onClick ~= onClick;
    }
}

class NgLinkButton : NgButton
{
    import beamui.platforms.common.platform : platform;

    private string url;

    static NgLinkButton make(dstring text, string url, string icon = "applications-internet")
    {
        NgLinkButton w = arena.make!NgLinkButton;
        w.text = text;
        w.icon = icon;
        if (url.length)
        {
            w.url = url;
            w.onClick = &w.handleClick;
        }
        return w;
    }

    private void handleClick()
    {
        platform.openURL(url);
    }
}

class NgSwitchButton : NgWidget
{
    bool checked;
    void delegate(bool) onToggle;

    static NgSwitchButton make(bool checked, void delegate(bool) onToggle)
    {
        NgSwitchButton w = arena.make!NgSwitchButton;
        w.checked = checked;
        w.onToggle = onToggle;
        return w;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemSwitch;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemSwitch el = fastCast!ElemSwitch(element);
        el.checked = checked;
        el.onToggle.clear();
        if (onToggle)
            el.onToggle ~= onToggle;
    }
}

class NgCheckBox : NgPanel
{
    dstring text;
    bool checked;
    void delegate(bool) onToggle;

    static NgCheckBox make(dstring text, bool checked, void delegate(bool) onToggle)
    {
        NgCheckBox w = arena.make!NgCheckBox;
        w.text = text;
        w.checked = checked;
        w.onToggle = onToggle;
        return w;
    }

    this()
    {
        allowsFocus = true;
        allowsHover = true;
        isolateStyle = true;
    }

    override protected void build()
    {
        enabled = onToggle !is null;

        NgLabel label;
        if (text.length)
        {
            label = NgLabel.make(text);
            label.setAttribute("label");
            label.inheritState = true;
        }
        auto image = NgWidget.make();
        image.setAttribute("icon");
        image.inheritState = true;
        attach(image, label);
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPanel el = fastCast!ElemPanel(element);
        el.allowsClick = true;
        el.checked = checked;
        el.onClick.clear();
        if (onToggle)
            el.onClick ~= &handleClick;
    }

    private void handleClick()
    {
        onToggle(!checked);
    }
}

class NgRadioButton : NgPanel
{
    dstring text;
    bool checked;
    void delegate(bool) onToggle;

    static NgRadioButton make(dstring text, bool checked, void delegate(bool) onToggle)
    {
        NgRadioButton w = arena.make!NgRadioButton;
        w.text = text;
        w.checked = checked;
        w.onToggle = onToggle;
        return w;
    }

    this()
    {
        allowsFocus = true;
        allowsHover = true;
        isolateStyle = true;
    }

    override protected void build()
    {
        enabled = onToggle !is null;

        NgLabel label;
        if (text.length)
        {
            label = NgLabel.make(text);
            label.setAttribute("label");
            label.inheritState = true;
        }
        auto image = NgWidget.make();
        image.setAttribute("icon");
        image.inheritState = true;
        attach(image, label);
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPanel el = fastCast!ElemPanel(element);
        el.allowsClick = true;
        el.checked = checked;
        el.onClick.clear();
        if (onToggle)
            el.onClick ~= &handleClick;
    }

    private void handleClick()
    {
        if (checked || !parent)
            return;

        foreach (i, item; parent)
        {
            if (this is item)
                continue;
            if (auto rb = cast(NgRadioButton)item)
            {
                // deactivate siblings
                if (rb.checked && rb.onToggle)
                    rb.onToggle(false);
            }
        }
        onToggle(true);
    }
}

class NgCanvasWidget : NgWidget
{
    void delegate(Painter, Size) onDraw;

    static NgCanvasWidget make(void delegate(Painter, Size) onDraw)
    {
        NgCanvasWidget w = arena.make!NgCanvasWidget;
        w.onDraw = onDraw;
        return w;
    }

    override protected Element fetchElement()
    {
        return fetchEl!ElemCanvas;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemCanvas el = fastCast!ElemCanvas(element);
        el.onDraw = onDraw;
    }
}

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
                if (Bitmap bm = imageCache.get(id))
                    _drawable = new ImageDrawable(bm);
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

    override protected Boundaries computeBoundaries()
    {
        Size sz;
        DrawableRef img = _drawable;
        if (!img.isNull)
            sz = Size(img.width, img.height);
        return Boundaries(sz);
    }

    override protected void drawContent(Painter pr)
    {
        DrawableRef img = _drawable;
        if (!img.isNull)
        {
            const sz = Size(img.width, img.height);
            const ib = alignBox(innerBox, sz, Align.center);
            img.drawTo(pr, ib);
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
                _icon.setAttribute("icon");
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
                _icon.setAttribute("icon");
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
                iconID = _action.iconID;
                text = _action.label;
                allowsToggle = _action.checkable;
                a.onChange ~= &updateContent;
                a.onStateChange ~= &updateState;
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
                _label.setAttribute("label");
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
        isolateStyle();
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
    }

    protected void updateState()
    {
        enabled = _action.enabled;
        checked = _action.checked;
        visibility = _action.visible ? Visibility.visible : Visibility.gone;
    }

    override protected void handleClick()
    {
        if (_action)
        {
            if (auto w = window)
                w.call(_action);
        }
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

    override CursorType getCursorType(float x, float y) const // doesn't work for actual text, FIXME!
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

    override protected Boundaries computeBoundaries()
    {
        const Drawable bg = style.backgroundImage;
        const sz = bg ? Size(bg.width, bg.height) : Size(0, 0);
        return Boundaries(sz);
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
        isolateStyle();
        _icon = new Widget;
        _label = new Label(labelText);
        _icon.setAttribute("icon");
        _label.setAttribute("label");
        _icon.state = State.parent;
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
class RadioButton : Panel
{
    private
    {
        Widget _icon;
        Label _label;
    }

    this(dstring labelText = null)
    {
        isolateStyle();
        _icon = new Widget;
        _label = new Label(labelText);
        _icon.setAttribute("icon");
        _label.setAttribute("label");
        _icon.state = State.parent;
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
    Listener!(void delegate(Painter painter, Size size)) onDraw;

    void doDraw(Painter pr, Size size)
    {
        if (onDraw.assigned)
            onDraw(pr, size);
    }

    override protected void drawContent(Painter pr)
    {
        const b = innerBox;
        pr.clipIn(BoxI.from(b));
        pr.translate(b.x, b.y);
        doDraw(pr, b.size);
    }
}
