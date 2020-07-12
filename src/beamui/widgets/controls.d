/**
Simple controls - images, buttons, and so on.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.controls;

import beamui.events.action : Action;
import beamui.events.stdactions;
import beamui.layout.alignment : alignBox;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Static image widget. Can accept any drawable instead of the image (e.g. a gradient)
class ImageWidget : Widget
{
    /// Resource id for this image
    string imageID;
    /// Custom drawable to show (not one from resources) instead of an image
    Drawable drawable;

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

/** Widget with an icon and a label.

    CSS_nodes:
    ---
    ButtonLike
    ├── ImageWidget?.icon
    ╰── Label?.label
    ---
*/
class ButtonLike : Panel
{
    dstring text;
    string iconID;

    this()
    {
        allowsHover = true;
    }

    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        ImageWidget image;
        if (iconID.length)
        {
            image = render!ImageWidget;
            image.imageID = iconID;
            image.attributes["icon"];
            image.namespace = null;
        }
        Label label;
        if (text.length)
        {
            label = render!Label;
            label.text = text;
            label.attributes["label"];
            label.namespace = null;
        }
        wrap(image, label);
    }
}

class Button : ButtonLike
{
    void delegate() onClick;

    this()
    {
        allowsFocus = true;
    }

    override protected void build()
    {
        super.build();
        enabled = onClick !is null;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.onClick.clear();
        if (onClick)
        {
            el.allowsClick = true;
            el.onClick ~= onClick;
        }
    }
}

class CheckButton : ButtonLike
{
    bool checked;
    void delegate(bool) onToggle;

    this()
    {
        allowsFocus = true;
    }

    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        super.build();
        enabled = onToggle !is null;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.applyFlags(StateFlags.checked, checked);
        el.onClick.clear();
        if (onToggle)
        {
            el.allowsClick = true;
            el.onClick ~= &handleClick;
        }
    }

    private void handleClick()
    {
        onToggle(!checked);
    }
}

class ActionWidgetWrapper : Panel
{
    /// Action to emit on click
    Action action;

    override protected void build()
    {
        assert(action);
        visible = action.visible;
    }

    final protected void call()
    {
        if (auto w = window)
            w.call(action);
    }
}

class ActionButton : ActionWidgetWrapper
{
    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        super.build();

        if (!action.checkable)
        {
            Button btn = render!Button;
            btn.iconID = action.iconID;
            btn.text = action.label;
            if (action.enabled)
                btn.onClick = &call;
            btn.namespace = null;
            wrap(btn);
        }
        else
        {
            CheckButton btn = render!CheckButton;
            btn.iconID = action.iconID;
            btn.text = action.label;
            if (action.enabled)
                btn.onToggle = &handleToggle;
            btn.namespace = null;
            wrap(btn);
        }
    }

    private void handleToggle(bool)
    {
        call();
    }
}

/// Hyperlink button. May wrap any widget
class Link : WidgetWrapperOf!Widget
{
    import beamui.platforms.common.platform : platform;

    string url;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

    override protected void build()
    {
        enabled = url.length > 0;
        if (_content)
            _content.inheritState = true;
    }

    override protected Element createElement()
    {
        return new ElemPanel;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

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
    bool checked;
    void delegate(bool) onToggle;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

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
        el.applyFlags(StateFlags.checked, checked);
        el.onClick.clear();
        if (onToggle)
        {
            el.allowsClick = true;
            el.onClick ~= &handleClick;
        }
    }

    private void handleClick()
    {
        onToggle(!checked);
    }
}

/** Check box that can be toggled on or off.

    CSS_nodes:
    ---
    CheckBox
    ├── Widget.icon
    ╰── Label?.label
    ---
*/
class CheckBox : Panel
{
    dstring text;
    bool checked;
    void delegate(bool) onToggle;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        enabled = onToggle !is null;

        Label label;
        if (text.length)
        {
            label = render!Label;
            label.text = text;
            label.attributes["label"];
            label.namespace = null;
        }
        Widget image = render!Widget;
        image.attributes["icon"];
        image.namespace = null;
        wrap(image, label);
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.applyFlags(StateFlags.checked, checked);
        el.onClick.clear();
        if (onToggle)
        {
            el.allowsClick = true;
            el.onClick ~= &handleClick;
        }
    }

    private void handleClick()
    {
        onToggle(!checked);
    }
}

/** Mutually exclusive check button.

    CSS_nodes:
    ---
    RadioButton
    ├── Widget.icon
    ╰── Label?.label
    ---
*/
class RadioButton : Panel
{
    dstring text;
    bool checked;
    void delegate(bool) onToggle;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        enabled = onToggle !is null;

        Label label;
        if (text.length)
        {
            label = render!Label;
            label.text = text;
            label.attributes["label"];
            label.namespace = null;
        }
        Widget image = render!Widget;
        image.attributes["icon"];
        image.namespace = null;
        wrap(image, label);
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.applyFlags(StateFlags.checked, checked);
        el.onClick.clear();
        if (onToggle)
        {
            el.allowsClick = true;
            el.onClick ~= &handleClick;
        }
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
class Canvas : Widget
{
    void delegate(Painter, Size) onDraw;

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

    ~this()
    {
        _drawable.clear();
    }

    override protected Boundaries computeBoundaries()
    {
        const Drawable img = _drawable.get;
        const sz = img ? img.size : Size(0, 0);
        return Boundaries(sz);
    }

    override protected void drawContent(Painter pr)
    {
        if (Drawable img = _drawable.get)
        {
            const ib = alignBox(innerBox, img.size, Align.center);
            img.drawTo(pr, ib);
        }
    }
}

class ElemSwitch : Element
{
    override protected Boundaries computeBoundaries()
    {
        const Drawable bg = style.backgroundImage;
        const sz = bg ? bg.size : Size(0, 0);
        return Boundaries(sz);
    }
}

class ElemCanvas : Element
{
    Listener!(void delegate(Painter painter, Size size)) onDraw;

    override protected void drawContent(Painter pr)
    {
        const b = innerBox;
        pr.clipIn(b);
        pr.translate(b.x, b.y);
        onDraw(pr, b.size);
    }
}
