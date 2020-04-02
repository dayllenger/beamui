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

/// Static image widget. Can accept any drawable instead of the image (e.g. a gradient)
class ImageWidget : Widget
{
    protected string imageID;
    protected Drawable drawable;

    /// Make with a resource id for this image
    static ImageWidget make(string imageID)
    {
        ImageWidget w = arena.make!ImageWidget;
        w.imageID = imageID;
        return w;
    }
    /// Use a custom drawable to show (not one from resources) instead of an image
    static ImageWidget make(DrawableRef drawable)
    {
        ImageWidget w = arena.make!ImageWidget;
        w.drawable = drawable;
        return w;
    }

    override protected Element createElement()
    {
        return new ElemImage;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemImage el = fastCast!ElemImage(element);
        if (drawable)
            el.drawable = DrawableRef(drawable);
        else
            el.imageID = imageID;
    }
}

class ButtonLike : Panel
{
    protected dstring text;
    protected string icon;

    static ButtonLike make(dstring text, string icon)
    {
        ButtonLike w = arena.make!ButtonLike;
        w.text = text;
        w.icon = icon;
        return w;
    }

    this()
    {
        allowsHover = true;
        isolateStyle = true;
    }

    protected alias attach = typeof(super).attach;

    override protected void build()
    {
        ImageWidget image;
        if (icon.length)
        {
            image = ImageWidget.make(icon);
            image.setAttribute("icon");
            image.inheritState = true;
        }
        Label label;
        if (text.length)
        {
            label = Label.make(text);
            label.setAttribute("label");
            label.inheritState = true;
        }
        attach(image, label);
    }
}

class Button : ButtonLike
{
    protected void delegate() onClick;

    static Button make(dstring text, void delegate() onClick)
    {
        Button w = arena.make!Button;
        w.text = text;
        w.onClick = onClick;
        return w;
    }

    static Button make(dstring text, string icon, void delegate() onClick)
    {
        Button w = arena.make!Button;
        w.text = text;
        w.icon = icon;
        w.onClick = onClick;
        return w;
    }

    this()
    {
        allowsFocus = true;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPanel el = fastCast!ElemPanel(element);
        el.onClick.clear();
        if (onClick)
        {
            el.allowsClick = true;
            el.onClick ~= onClick;
        }
    }
}

/// Hyperlink button. May wrap any widget
class Link : WidgetWrapper
{
    import beamui.platforms.common.platform : platform;

    protected string url;

    static Link make(string url)
    {
        Link w = arena.make!Link;
        w.url = url;
        return w;
    }

    this()
    {
        allowsFocus = true;
    }

    override protected void build()
    {
        if (_content)
            _content.inheritState = true;
    }

    override protected Element createElement()
    {
        return new ElemPanel;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPanel el = fastCast!ElemPanel(element);
        el.onClick.clear();
        if (url.length)
        {
            el.allowsClick = true;
            el.onClick ~= &handleClick;
        }
    }

    private void handleClick()
    {
        platform.openURL(url);
    }
}

/// Switch (on/off) widget
class SwitchButton : Widget
{
    protected bool checked;
    protected void delegate(bool) onToggle;

    static SwitchButton make(bool checked, void delegate(bool) onToggle)
    {
        SwitchButton w = arena.make!SwitchButton;
        w.checked = checked;
        w.onToggle = onToggle;
        return w;
    }

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

    protected alias enabled = typeof(super).enabled;

    override protected void build()
    {
        enabled = onToggle !is null;
    }

    override protected Element createElement()
    {
        return new ElemSwitch;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemSwitch el = fastCast!ElemSwitch(element);
        el.allowsClick = true;
        el.applyState(State.checked, checked);
        el.onClick.clear();
        if (onToggle)
            el.onClick ~= &handleClick;
    }

    private void handleClick()
    {
        onToggle(!checked);
    }
}

/// Check button that can be toggled on or off
class CheckBox : Panel
{
    protected dstring text;
    protected bool checked;
    protected void delegate(bool) onToggle;

    static CheckBox make(dstring text, bool checked, void delegate(bool) onToggle)
    {
        CheckBox w = arena.make!CheckBox;
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

    protected alias enabled = typeof(super).enabled;
    protected alias attach = typeof(super).attach;

    override protected void build()
    {
        enabled = onToggle !is null;

        Label label;
        if (text.length)
        {
            label = Label.make(text);
            label.setAttribute("label");
            label.inheritState = true;
        }
        auto image = Widget.make();
        image.setAttribute("icon");
        image.inheritState = true;
        attach(image, label);
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPanel el = fastCast!ElemPanel(element);
        el.allowsClick = true;
        el.applyState(State.checked, checked);
        el.onClick.clear();
        if (onToggle)
            el.onClick ~= &handleClick;
    }

    private void handleClick()
    {
        onToggle(!checked);
    }
}

/// Mutually exclusive check button
class RadioButton : Panel
{
    protected dstring text;
    protected bool checked;
    protected void delegate(bool) onToggle;

    static RadioButton make(dstring text, bool checked, void delegate(bool) onToggle)
    {
        RadioButton w = arena.make!RadioButton;
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

    protected alias enabled = typeof(super).enabled;
    protected alias attach = typeof(super).attach;

    override protected void build()
    {
        enabled = onToggle !is null;

        Label label;
        if (text.length)
        {
            label = Label.make(text);
            label.setAttribute("label");
            label.inheritState = true;
        }
        auto image = Widget.make();
        image.setAttribute("icon");
        image.inheritState = true;
        attach(image, label);
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemPanel el = fastCast!ElemPanel(element);
        el.allowsClick = true;
        el.applyState(State.checked, checked);
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
            if (auto rb = cast(RadioButton)item)
            {
                // deactivate siblings
                if (rb.checked && rb.onToggle)
                    rb.onToggle(false);
            }
        }
        onToggle(true);
    }
}

/// Canvas widget - draw arbitrary graphics on it by providing a callback
class CanvasWidget : Widget
{
    protected void delegate(Painter, Size) onDraw;

    static CanvasWidget make(void delegate(Painter, Size) onDraw)
    {
        CanvasWidget w = arena.make!CanvasWidget;
        w.onDraw = onDraw;
        return w;
    }

    override protected Element createElement()
    {
        return new ElemCanvas;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemCanvas el = fastCast!ElemCanvas(element);
        el.onDraw = onDraw;
    }
}

class ElemImage : Element
{
    @property
    {
        string imageID() const { return _imageID; }
        /// ditto
        void imageID(string id)
        {
            if (_imageID == id)
                return;
            _imageID = id;
            _drawable.clear();
            if (id.length)
            {
                if (Bitmap bm = imageCache.get(id))
                    _drawable = new ImageDrawable(bm);
            }
            requestLayout();
        }

        void drawable(DrawableRef img)
        {
            if (_drawable is img)
                return;
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
class ElemButton : ElemPanel, ActionHolder
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
                _icon = new ElemImage(id);
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
                _icon = new ElemImage;
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
                _checkable = _action.checkable;
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
                _label = new ElemLabel(s);
                _label.setAttribute("label");
                _label.state = State.parent;
                add(_label);
            }
        }
    }

    private
    {
        bool _checkable;

        ElemImage _icon;
        ElemLabel _label;

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
        _checkable = checkable;
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
        applyState(State.enabled, _action.enabled);
        applyState(State.checked, _action.checked);
        visibility = _action.visible ? Visibility.visible : Visibility.gone;
    }
    override protected void handleClick()
    {
        if (_action)
        {
            if (auto w = window)
                w.call(_action);
        }
        if (_checkable)
            applyState(State.checked, !(state & State.checked));
    }
}

class ElemSwitch : Element
{
    override protected Boundaries computeBoundaries()
    {
        const Drawable bg = style.backgroundImage;
        const sz = bg ? Size(bg.width, bg.height) : Size(0, 0);
        return Boundaries(sz);
    }
}

class ElemCanvas : Element
{
    Listener!(void delegate(Painter painter, Size size)) onDraw;

    override protected void drawContent(Painter pr)
    {
        const b = innerBox;
        pr.clipIn(BoxI.from(b));
        pr.translate(b.x, b.y);
        onDraw(pr, b.size);
    }
}
