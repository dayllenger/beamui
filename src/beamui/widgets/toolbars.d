/**
This module implements support of tool bars.

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
import beamui.widgets.widget;

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

/// Button for toolbar
class ToolBarButton : Button
{
    this(Action a)
    {
        super(a);
        focusable = false;
    }
}

/// Separator for toolbars
class ToolBarSeparator : ImageWidget
{
    this()
    {
        super("toolbar_separator");
        id = "separator";
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
    this()
    {
        id = "TOOLBAR";
    }

    this(string ID)
    {
        id = ID;
    }

    void addCustomControl(Widget widget)
    {
        addChild(widget);
    }

    /// Adds image button to toolbar
    void addButtons(Action[] actions...)
    {
        foreach (a; actions)
        {
            auto btn = new ToolBarButton(a); // TODO: image only / image + text / text only
            btn.bindSubItem(this, "button");
            addChild(btn);
        }
    }

    void addControl(Widget widget)
    {
        addChild(widget);
    }

    void addSeparator()
    {
        addChild(new ToolBarSeparator);
    }
}
