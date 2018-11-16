/**
Support of tool bars.

ToolBarHost is layout to hold one or more toolbars.

ToolBar is bar with tool buttons and other controls arranged horizontally.

Synopsis:
---
import beamui.widgets.toolbars;
---

Copyright: Vadim Lopatin 2015-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.toolbars;

import beamui.widgets.combobox;
import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Button for toolbar
class ToolBarButton : Button
{
    /// Construct with action firing on click
    this(Action a)
    {
        super(a);
        focusable = false;
    }

    override protected void updateContent()
    {
         // TODO: image only / image + text / text only
        iconID = action.iconID;
        checkable = action.checkable;
    }

    override @property bool hasTooltip()
    {
        return action && action.label;
    }

    override Widget createTooltip(int mouseX, int mouseY, ref PopupAlign alignment, ref int x, ref int y)
    {
        return new Label(action.tooltipText).id("tooltip");
    }
}

/// Combo box for toolbars
class ToolBarComboBox : ComboBox
{
    this(dstring[] items)
    {
        super(items);
        if (items.length > 0)
            selectedItemIndex = 0;
    }

    // TODO: tooltips
}

/// Layout with buttons
class ToolBar : Row
{
    /// Construct a tool bar with ID
    this(string ID = "TOOLBAR")
    {
        id = ID;
    }

    /// Add image button to the tool bar
    ToolBar addButtons(Action[] actions...)
    {
        foreach (a; actions)
        {
            addChild(new ToolBarButton(a));
        }
        return this;
    }

    /// Add custom control to the tool bar
    ToolBar addControl(Widget w)
    {
        addChild(w);
        return this;
    }

    /// Add separator to the tool bar
    ToolBar addSeparator()
    {
        auto sep = new Widget;
        sep.bindSubItem(this, "separator");
        addChild(sep);
        return this;
    }
}

/// Layout with several toolbars
class ToolBarHost : Row
{
    /// Create and add new toolbar (returns existing one if already exists)
    ToolBar getOrAddToolbar(string ID)
    {
        ToolBar res = getToolbar(ID);
        if (!res)
        {
            res = new ToolBar(ID);
            addChild(res);
        }
        return res;
    }

    /// Get toolbar by id; null if not found
    ToolBar getToolbar(string ID)
    {
        return cast(ToolBar)childByID(ID);
    }
}
