/**
Simple controls - images, buttons, and so on.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
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

/// Widget with an icon and a label
class ButtonLike : Panel
{
    dstring text;
    string icon;

    this()
    {
        allowsHover = true;
        isolateStyle = true;
    }

    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        ImageWidget image;
        if (icon.length)
        {
            image = render!ImageWidget;
            image.imageID = icon;
            image.attributes.set("icon");
        }
        Label label;
        if (text.length)
        {
            label = render!Label;
            label.text = text;
            label.attributes.set("label");
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

        el.applyState(State.checked, checked);
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
    private Element element;

    override protected void build()
    {
        assert(action);
        visible = action.visible;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);
        element = el;
    }

    final protected void call()
    {
        if (auto w = element.window)
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
            btn.icon = action.iconID;
            btn.text = action.label;
            if (action.enabled)
                btn.onClick = &call;
            wrap(btn);
        }
        else
        {
            CheckButton btn = render!CheckButton;
            btn.icon = action.iconID;
            btn.text = action.label;
            if (action.enabled)
                btn.onToggle = &handleToggle;
            wrap(btn);
        }
    }

    private void handleToggle(bool)
    {
        call();
    }
}

/// Hyperlink button. May wrap any widget
class Link : WidgetWrapper
{
    import beamui.platforms.common.platform : platform;

    string url;

    this()
    {
        allowsFocus = true;
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
        el.applyState(State.checked, checked);
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

/// Check button that can be toggled on or off
class CheckBox : Panel
{
    dstring text;
    bool checked;
    void delegate(bool) onToggle;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
        isolateStyle = true;
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
            label.attributes.set("label");
        }
        Widget image = render!Widget;
        image.attributes.set("icon");
        wrap(image, label);
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.applyState(State.checked, checked);
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

/// Mutually exclusive check button
class RadioButton : Panel
{
    dstring text;
    bool checked;
    void delegate(bool) onToggle;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
        isolateStyle = true;
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
            label.attributes.set("label");
        }
        Widget image = render!Widget;
        image.attributes.set("icon");
        wrap(image, label);
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.applyState(State.checked, checked);
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
class CanvasWidget : Widget
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
