/**
Combo Box controls, simple and editable.

Synopsis:
---
dstring[] list = ["value 1", "value 2", "value 3"];

// creation of simple combo box
auto cbox = new ComboBox(list);

// select the first item
cbox.selectedItemIndex = 0;

// get selected item text
writeln(cbox.text);
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2019-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.combobox;

import beamui.widgets.controls : Button, ImageWidget;
import beamui.widgets.editors : EditLine;
import beamui.widgets.lists : ElemListView, ListView, ListMouseBehavior;
import beamui.widgets.popup;
import beamui.widgets.text : Label;
import beamui.widgets.widget;

private class ComboListView : ListView
{
    bool focus;

    override protected Element createElement()
    {
        auto el = new ElemListView;
        el.mouseSelectBehavior = ListMouseBehavior.activateOnRelease;
        el.sumItemSizes = true;
        return el;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        if (focus)
            el.setFocus();
    }
}

/** Abstract combobox widget.

    CSS_nodes:
    ---
    ComboBoxBase.opened?
    ├── .body
    ╰── .arrow
    ---
    ---
    Popup.combobox
    ╰── ListView
        ├── .item
        ...
    ---
*/
abstract class ComboBoxBase : Panel
{
    /// Triggers when the user drags the mouse on the list items and hovers over different items
    void delegate(int) onPreview;
    /// Triggers on item selection and passes integer index of the item
    void delegate(int) onSelect;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
        onKeyEvent = &handleKeyEvent;
        onWheelEvent = &handleWheelEvent;
    }

    private bool handleKeyEvent(KeyEvent event)
    {
        const oldIndex = use!State.selectedItemIndex;
        int newIndex = int.min;
        if (event.action == KeyAction.keyDown)
        {
            if (event.key == Key.down)
                newIndex = oldIndex + 1;
            else if (event.key == Key.up)
                newIndex = oldIndex - 1;
            else if (event.key == Key.home)
                newIndex = 0;
            else if (event.key == Key.end)
                newIndex = itemCount - 1;
        }
        if (newIndex == int.min)
            return false;

        select(clamp(newIndex, 0, itemCount - 1));
        return true;
    }

    private bool handleWheelEvent(WheelEvent event)
    {
        const delta = event.deltaY > 0 ? 1 : -1;
        const oldIndex = use!State.selectedItemIndex;
        const newIndex = clamp(oldIndex + delta, 0, itemCount - 1);
        select(newIndex);
        return oldIndex != newIndex;
    }

protected:

    static class State : WidgetState
    {
        int selectedItemIndex;
        bool opened;

        bool needToMoveFocus;
    }

    override State createState()
    {
        return new State;
    }

    void open()
    {
        if (itemCount > 0) // don't show empty popup
        {
            State st = use!State;
            setState(st.opened, true);
            st.needToMoveFocus = true;
        }
    }

    void close()
    {
        State st = use!State;
        setState(st.opened, false);
        st.needToMoveFocus = true;
    }

    void select(int index)
    {
        State st = use!State;
        if (st.selectedItemIndex != index)
        {
            setState(st.selectedItemIndex, index);
            if (onPreview)
                onPreview(index);
            if (onSelect)
                onSelect(index);
        }
    }

    override void build()
    {
        Widget body = buildBody();
        Widget arrow = buildArrow();
        body.attributes["body"];
        arrow.attributes["arrow"];
        body.namespace = null;
        arrow.namespace = null;
        wrap(body, arrow);

        State st = use!State;
        if (st.opened)
        {
            attributes["opened"];

            ListView v = buildList();
            v.itemCount = itemCount;
            v.onSelect = onPreview;
            v.onItemClick = (i) {
                select(i);
                close();
            };
            v.onKeyEvent = (KeyEvent e) {
                if (e.action == KeyAction.keyDown && e.key == Key.escape && e.noModifiers)
                {
                    close();
                    return true;
                }
                return false;
            };
            // FIXME: this is a wacky way to move focus, need a more general solution
            if (auto clv = cast(ComboListView)v)
            {
                clv.focus = st.needToMoveFocus;
                st.needToMoveFocus = false;
            }

            Popup p = render!Popup;
            p.attributes["combobox"];
            p.anchor = this;
            p.alignment = PopupAlign.below | PopupAlign.fitAnchorSize;
            p.wrap(v);
            window.showPopup(p);
        }
    }

    override void updateElement(Element el)
    {
        super.updateElement(el);

        State st = use!State;
        if (st.needToMoveFocus)
        {
            el.setFocus();
            st.needToMoveFocus = false;
        }
    }

    abstract int itemCount() const;
    abstract Widget buildBody() out(w; w);
    abstract Widget buildArrow() out(w; w);
    abstract ListView buildList() out(w; w);
}

/// Combobox with list of strings
class ComboBox : ComboBoxBase
{
    const(dstring)[] items;

protected:

    override int itemCount() const
    {
        return cast(int)items.length;
    }

    override Widget buildBody()
    {
        Label t = render!Label;
        t.text = items[use!State.selectedItemIndex];
        return t;
    }

    override Widget buildArrow()
    {
        ImageWidget img = render!ImageWidget;
        img.imageID = "scrollbar_btn_down";
        return img;
    }

    override ListView buildList()
    {
        ListView v = render!ComboListView;
        v.itemBuilder = i => v.item(items[i]);
        return v;
    }

    override Element createElement()
    {
        auto el = new ElemPanel;
        el.allowsClick = true;
        return el;
    }

    override void updateElement(Element el)
    {
        super.updateElement(el);
        el.onClick.clear();
        el.onClick ~= &open;
    }
}

/// Combobox with list of strings with icons
class IconTextComboBox : ComboBoxBase
{
    const(StringListValue)[] items;

protected:

    override int itemCount() const
    {
        return cast(int)items.length;
    }

    override Widget buildBody()
    {
        Label t = render!Label;
        t.text = items[use!State.selectedItemIndex].label;
        return t;
    }

    override Widget buildArrow()
    {
        ImageWidget img = render!ImageWidget;
        img.imageID = "scrollbar_btn_down";
        return img;
    }

    override ListView buildList()
    {
        ListView v = render!ComboListView;
        v.itemBuilder = i => v.item(items[i]);
        return v;
    }

    override Element createElement()
    {
        auto el = new ElemPanel;
        el.allowsClick = true;
        return el;
    }

    override void updateElement(Element el)
    {
        super.updateElement(el);
        el.onClick.clear();
        el.onClick ~= &open;
    }
}

/// Editable combobox with list of strings
class ComboEdit : ComboBoxBase
{
    const(dstring)[] items;
    bool readOnly;

    this()
    {
        allowsFocus = false;
    }

protected:

    override int itemCount() const
    {
        return cast(int)items.length;
    }

    override Widget buildBody()
    {
        EditLine ed = render!EditLine;
        ed.text = items[use!State.selectedItemIndex];
        ed.readOnly = readOnly;
        return ed;
    }

    override Widget buildArrow()
    {
        Button btn = render!Button;
        btn.iconID = "scrollbar_btn_down";
        btn.onClick = &open;
        return btn;
    }

    override ListView buildList()
    {
        ListView v = render!ComboListView;
        v.itemBuilder = i => v.item(items[i]);
        return v;
    }
}
