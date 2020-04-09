/**
Support of tool bars.

ToolBarHost is layout to hold one or more toolbars.

ToolBar is bar with tool buttons and other controls arranged horizontally.

Copyright: Vadim Lopatin 2015-2017
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.toolbars;

import beamui.core.actions : Action;
// import beamui.widgets.combobox;
import beamui.widgets.controls;
import beamui.widgets.widget : Panel, render, Widget;

class ToolBarSeparator : Widget
{
}

/// Button for toolbar
class ToolBarButton : ActionWidgetWrapper
{
    protected alias wrap = typeof(super).wrap;

    // TODO: image only / image + text / text only?
    override protected void build()
    {
        super.build();
        tooltip = action.tooltipText;

        if (!action.checkable)
        {
            Button btn = render!Button;
            btn.allowsFocus = false;
            if (action.iconID.length)
                btn.icon = action.iconID;
            else
                btn.text = action.label;
            if (action.enabled)
                btn.onClick = &call;
            wrap(btn);
        }
        else
        {
            CheckButton btn = render!CheckButton;
            btn.allowsFocus = false;
            if (action.iconID.length)
                btn.icon = action.iconID;
            else
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
/+
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
+/
/// Layout with buttons
class ToolBar : Panel
{
    /// Shorthand to create a toolbar button
    static ToolBarButton button(Action action)
        in(action)
    {
        auto b = render!ToolBarButton;
        b.action = action;
        return b;
    }
    /// Shorthand to create a separator between toolbar items
    static ToolBarSeparator separator()
    {
        return render!ToolBarSeparator;
    }
}
/+
/// Layout with several toolbars
class ToolBarHost : Panel
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
+/
