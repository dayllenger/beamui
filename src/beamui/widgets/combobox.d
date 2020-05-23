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
import beamui.widgets.lists : ElemListView, ListView;
import beamui.widgets.popup;
import beamui.widgets.text : Label;
import beamui.widgets.widget;

private class ComboListView : ListView
{
    override protected Element createElement()
    {
        auto el = new ElemListView;
        el.sumItemSizes = true;
        return el;
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
    /// Triggers on item selection and passes integer index of the item
    void delegate(int) onSelect;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
        onWheelEvent = &handleWheelEvent;
    }

    private bool handleWheelEvent(WheelEvent event)
    {
        const delta = event.deltaY > 0 ? 1 : -1;
        const oldIndex = getState().selectedItemIndex;
        const newIndex = clamp(oldIndex + delta, 0, itemCount - 1);
        select(newIndex);
        return oldIndex != newIndex;
    }

protected:

    static class State : IState
    {
        int selectedItemIndex;
        bool opened;
    }

    State getState()
    {
        return useState(new State);
    }

    void open()
    {
        if (itemCount > 0) // don't show empty popup
        {
            setState(getState().opened, true);
        }
    }

    void close()
    {
        setState(getState().opened, false);
        // TODO: focus combobox back
    }

    void select(int index)
    {
        auto st = getState();
        if (st.selectedItemIndex != index)
        {
            setState(st.selectedItemIndex, index);
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
        wrap(body, arrow);

        const st = getState();
        if (st.opened)
        {
            attributes["opened"];

            // TODO: focus list
            ListView v = buildList();
            v.itemCount = itemCount;
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

            Popup p = render!Popup;
            p.attributes["combobox"];
            p.anchor = this;
            p.alignment = PopupAlign.below | PopupAlign.fitAnchorSize;
            p.wrap(v);
            window.showPopup(p);
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
        const st = getState();
        Label t = render!Label;
        t.text = items[st.selectedItemIndex];
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
        const st = getState();
        Label t = render!Label;
        t.text = items[st.selectedItemIndex].label;
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
        onKeyEvent = &handleKeyEvent;
    }

    private bool handleKeyEvent(KeyEvent event)
    {
        if (event.action == KeyAction.keyDown)
        {
            if (event.key == Key.down)
            {
                open();
                return true;
            }
            if ((event.key == Key.space || event.key == Key.enter) && readOnly)
            {
                open();
                return true;
            }
        }
        return false;
    }

protected:

    override int itemCount() const
    {
        return cast(int)items.length;
    }

    override Widget buildBody()
    {
        const st = getState();
        EditLine ed = render!EditLine;
        ed.text = items[st.selectedItemIndex];
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
