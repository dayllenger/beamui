/**
This module contains tree widgets implementation


TreeWidgetBase - abstract tree widget

TreeWidget - Tree widget with items which can have icons and labels


Synopsis:
---
import beamui.widgets.tree;

// tree view example
auto tree = new TreeWidget;
tree.fillH();
TreeItem tree1 = tree.items.newChild("group1", "Group 1"d, "document-open");
tree1.newChild("g1_1", "Group 1 item 1"d);
tree1.newChild("g1_2", "Group 1 item 2"d);
tree1.newChild("g1_3", "Group 1 item 3"d);
TreeItem tree2 = tree.items.newChild("group2", "Group 2"d, "document-save");
tree2.newChild("g2_1", "Group 2 item 1"d, "edit-copy");
tree2.newChild("g2_2", "Group 2 item 2"d, "edit-cut");
tree2.newChild("g2_3", "Group 2 item 3"d, "edit-paste");
tree2.newChild("g2_4", "Group 2 item 4"d);
TreeItem tree3 = tree.items.newChild("group3", "Group 3"d);
tree3.newChild("g3_1", "Group 3 item 1"d);
tree3.newChild("g3_2", "Group 3 item 2"d);
TreeItem tree32 = tree3.newChild("g3_3", "Group 3 item 3"d);
tree3.newChild("g3_4", "Group 3 item 4"d);
tree32.newChild("group3_2_1", "Group 3 item 2 subitem 1"d);
tree32.newChild("group3_2_2", "Group 3 item 2 subitem 2"d);
tree32.newChild("group3_2_3", "Group 3 item 2 subitem 3"d);
tree32.newChild("group3_2_4", "Group 3 item 2 subitem 4"d);
tree32.newChild("group3_2_5", "Group 3 item 2 subitem 5"d);
tree3.newChild("g3_5", "Group 3 item 5"d);
tree3.newChild("g3_6", "Group 3 item 6"d);

auto treeLayout = new Row;
auto treeControlledPanel = new Column;
treeLayout.fillW();
treeControlledPanel.fillWH();
auto treeItemLabel = new Label("Sample text"d);
treeItemLabel.fillWH();
treeItemLabel.alignment = Align.center;
treeControlledPanel.addChild(treeItemLabel);
treeLayout.addChild(tree);
treeLayout.addResizer();
treeLayout.addChild(treeControlledPanel);

tree.itemSelected = delegate(TreeItems source, TreeItem selectedItem, bool activated) {
    dstring label = "Selected item: "d ~ toUTF32(selectedItem.id) ~ (activated ? " selected + activated"d : " selected"d);
    treeItemLabel.text = label;
};

tree.items.selectItem(tree.items.child(0));
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.tree;

import beamui.core.stdaction;
import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.scroll;
import beamui.widgets.widget;

/// Tree widget item data container
class TreeItem
{
    @property
    {
        /// Returns true if item supports collapse
        bool canCollapse()
        {
            if (auto r = root)
                return r.canCollapse(this);
            return true;
        }

        /// Returns topmost item
        TreeItems root()
        {
            TreeItem p = this;
            while (p._parent)
                p = p._parent;
            return cast(TreeItems)p;
        }

        /// Returns true if this item is root item
        bool isRoot()
        {
            return false;
        }

        TreeItem parent()
        {
            return _parent;
        }

        protected TreeItem parent(TreeItem p)
        {
            _parent = p;
            return this;
        }

        string id()
        {
            return _id;
        }

        TreeItem id(string id)
        {
            _id = id;
            return this;
        }

        string iconRes()
        {
            return _iconRes;
        }

        TreeItem iconRes(string res)
        {
            _iconRes = res;
            return this;
        }

        int level()
        {
            return _level;
        }

        protected TreeItem level(int level)
        {
            _level = level;
            foreach (i; 0 .. childCount)
                child(i).level = _level + 1;
            return this;
        }

        bool expanded()
        {
            return _expanded;
        }

        protected TreeItem expanded(bool expanded)
        {
            _expanded = expanded;
            return this;
        }
        /// Returns true if this item and all parents are expanded
        bool isFullyExpanded()
        {
            if (!_expanded)
                return false;
            if (!_parent)
                return true;
            return _parent.isFullyExpanded;
        }
        /// Returns true if all parents are expanded
        bool isVisible()
        {
            if (_parent)
                return _parent.isFullyExpanded;
            return false;
        }

        TreeItem selectedItem()
        {
            return root.selectedItem();
        }

        TreeItem defaultItem()
        {
            return root.defaultItem();
        }

        bool isSelected()
        {
            return (selectedItem is this);
        }

        bool isDefault()
        {
            return (defaultItem is this);
        }

        /// Get widget text
        dstring text()
        {
            return _text;
        }
        /// Set text to show
        TreeItem text(dstring s)
        {
            _text = s;
            return this;
        }

        TreeItem topParent()
        {
            if (!_parent)
                return this;
            return _parent.topParent;
        }

        int intParam()
        {
            return _intParam;
        }

        TreeItem intParam(int value)
        {
            _intParam = value;
            return this;
        }

        Object objectParam()
        {
            return _objectParam;
        }

        TreeItem objectParam(Object value)
        {
            _objectParam = value;
            return this;
        }
    }

    protected
    {
        TreeItem _parent;
        string _id;
        string _iconRes;
        int _level;
        dstring _text;
        ObjectList!TreeItem _children;
        bool _expanded;

        int _intParam;
        Object _objectParam;
    }

    this(string id)
    {
        _id = id;
        _expanded = true;
    }

    this(string id, dstring label, string iconRes = null)
    {
        _id = id;
        _expanded = true;
        _iconRes = iconRes;
        _text = label;
    }

    bool compareID(string id)
    {
        return _id !is null && _id == id;
    }

    void expand()
    {
        _expanded = true;
        if (_parent)
            _parent.expand();
    }

    void collapse()
    {
        _expanded = false;
    }
    /// Expand this node and all children
    void expandAll()
    {
        foreach (c; _children)
        {
            if (!c._expanded && c.canCollapse) //?
                c.expandAll();
        }
        if (!expanded)
            toggleExpand(this);
    }
    /// Expand this node and all children
    void collapseAll()
    {
        foreach (c; _children)
        {
            if (c._expanded && c.canCollapse)
                c.collapseAll();
        }
        if (expanded)
            toggleExpand(this);
    }

    /// Create and add new child item
    TreeItem newChild(string id, dstring label, string iconRes = null)
    {
        auto res = new TreeItem(id, label, iconRes);
        addChild(res);
        return res;
    }

    void clear()
    {
        foreach (c; _children)
        {
            c.parent = null;
            if (c is root.selectedItem)
                root.selectItem(null);
        }
        _children.clear();
        root.onUpdate(this);
    }

    /// Returns true if item has at least one child
    @property bool hasChildren()
    {
        return childCount > 0;
    }

    /// Returns number of children of this widget
    @property int childCount()
    {
        return _children.count;
    }
    /// Returns child by index
    TreeItem child(int index)
    {
        return _children.get(index);
    }
    /// Adds child, returns added item
    TreeItem addChild(TreeItem item, int index = -1)
    {
        TreeItem res = _children.insert(item, index).parent(this).level(_level + 1);
        root.onUpdate(res);
        return res;
    }
    /// Removes child, returns removed item
    TreeItem removeChild(int index)
    {
        if (index < 0 || index >= _children.count)
            return null;
        TreeItem res = _children.remove(index);
        TreeItem newSelection = null;
        if (res !is null)
        {
            res.parent = null;
            if (root && root.selectedItem is res)
            {
                if (index < _children.count)
                    newSelection = _children[index];
                else if (index > 0)
                    newSelection = _children[index - 1];
                else
                    newSelection = this;
            }
        }
        root.selectItem(newSelection);
        root.onUpdate(this);
        return res;
    }
    /// Removes child by reference, returns removed item
    TreeItem removeChild(TreeItem child)
    {
        TreeItem res = null;
        int index = _children.indexOf(child);
        return removeChild(index);
    }
    /// Removes child by ID, returns removed item
    TreeItem removeChild(string ID)
    {
        TreeItem res = null;
        int index = _children.indexOf(ID);
        return removeChild(index);
    }
    /// Returns index of widget in child list, -1 if passed widget is not a child of this widget
    int childIndex(TreeItem item)
    {
        return _children.indexOf(item);
    }
    /// Notify listeners
    protected void onUpdate(TreeItem item)
    {
        if (root)
            root.onUpdate(item);
    }

    protected void toggleExpand(TreeItem item)
    {
        root.toggleExpand(item);
    }

    protected void selectItem(TreeItem item)
    {
        root.selectItem(item);
    }

    protected void activateItem(TreeItem item)
    {
        root.activateItem(item);
    }

    protected TreeItem nextVisible(TreeItem item, ref bool found)
    {
        if (this is item)
            found = true;
        else if (found && isVisible)
            return this;
        foreach (i; 0 .. childCount)
        {
            TreeItem res = child(i).nextVisible(item, found);
            if (res)
                return res;
        }
        return null;
    }

    protected TreeItem prevVisible(TreeItem item, ref TreeItem prevFoundVisible)
    {
        if (this is item)
            return prevFoundVisible;
        else if (isVisible)
            prevFoundVisible = this;
        foreach (i; 0 .. childCount)
        {
            TreeItem res = child(i).prevVisible(item, prevFoundVisible);
            if (res)
                return res;
        }
        return null;
    }

    /// Returns item by id, null if not found
    TreeItem findItemByID(string id)
    {
        if (_id == id)
            return this;
        for (int i = 0; i < childCount; i++)
        {
            TreeItem res = child(i).findItemByID(id);
            if (res)
                return res;
        }
        return null;
    }
}

class TreeItems : TreeItem
{
    Listener!(void delegate(TreeItems)) contentChanged;
    Listener!(void delegate(TreeItems)) stateChanged;
    Listener!(void delegate(TreeItems, TreeItem)) expandChanged;
    Listener!(void delegate(TreeItems, TreeItem, bool activated)) itemSelected;

    bool noCollapseForSingleTopLevelItem;

    protected TreeItem _selectedItem;
    protected TreeItem _defaultItem;

    this()
    {
        super("tree");
    }

    /// Returns true if this item is root item
    override @property bool isRoot()
    {
        return true;
    }

    /// Notify listeners
    override protected void onUpdate(TreeItem item)
    {
        contentChanged(this);
    }

    bool canCollapse(TreeItem item)
    {
        if (!noCollapseForSingleTopLevelItem)
            return true;
        if (!hasChildren)
            return false;
        if (_children.count == 1 && _children[0] is item)
            return false;
        return true;
    }

    bool canCollapseTopLevel()
    {
        if (!noCollapseForSingleTopLevelItem)
            return true;
        if (!hasChildren)
            return false;
        if (_children.count == 1)
            return false;
        return true;
    }

    override void toggleExpand(TreeItem item)
    {
        bool changed;
        if (item.expanded)
        {
            if (item.canCollapse())
            {
                item.collapse();
                changed = true;
            }
        }
        else
        {
            item.expand();
            changed = true;
        }
        stateChanged(this);
        if (changed)
            expandChanged(this, item);
    }

    override void selectItem(TreeItem item)
    {
        if (_selectedItem is item)
            return;
        _selectedItem = item;
        stateChanged(this);
        itemSelected(this, _selectedItem, false);
    }

    void setDefaultItem(TreeItem item)
    {
        _defaultItem = item;
        stateChanged(this);
    }

    override void activateItem(TreeItem item)
    {
        if (!(_selectedItem is item))
        {
            _selectedItem = item;
            stateChanged(this);
        }
        itemSelected(this, _selectedItem, true);
    }

    override @property TreeItem selectedItem()
    {
        return _selectedItem;
    }

    override @property TreeItem defaultItem()
    {
        return _defaultItem;
    }

    void selectNext()
    {
        if (!hasChildren)
            return;
        if (!_selectedItem)
            selectItem(child(0));
        bool found = false;
        TreeItem next = nextVisible(_selectedItem, found);
        if (next)
            selectItem(next);
    }

    void selectPrevious()
    {
        if (!hasChildren)
            return;
        TreeItem found = null;
        TreeItem prev = prevVisible(_selectedItem, found);
        if (prev)
            selectItem(prev);
    }
}

const int DOUBLE_CLICK_TIME_MS = 250;

/// Item widget for displaying in trees
class TreeItemWidget : Row
{
    protected
    {
        TreeItem _item;
        Widget _indent;
        ImageWidget _expander;
        ImageWidget _icon;
        Label _label;
        Row _body;
        long lastClickTime;
    }

    Listener!(Menu delegate(TreeItems, TreeItem)) popupMenuBuilder;

    @property TreeItem item()
    {
        return _item;
    }

    this(TreeItem item)
    {
        super(0);
        id = item.id;

        clickable = true;
        focusable = true;
        trackHover = true;

        _item = item;
        _indent = new Widget("tree-item-indent");
        int level = _item.level - 1;
        if (!_item.root.canCollapseTopLevel())
            level--;
        level = max(level, 0);
        int w = level * style.font.size * 3 / 4;
        _indent.minWidth = w;
        _indent.maxWidth = w;
        if (_item.canCollapse())
        {
            _expander = new ImageWidget(_item.hasChildren && _item.expanded ?
                    "arrow_right_down_black" : "arrow_right_hollow");
            _expander.id = "tree-item-expander";
            _expander.bindSubItem(this, "expander");
            _expander.clickable = true;
            _expander.trackHover = true;
            _expander.visibility = _item.hasChildren ? Visibility.visible : Visibility.invisible;
            //_expander.setState(State.parent);

            _expander.clicked = delegate(Widget source) {
                _item.selectItem(_item);
                _item.toggleExpand(_item);
                return true;
            };
        }
        clicked = delegate(Widget source) {
            long ts = currentTimeMillis();
            _item.selectItem(_item);
            if (ts - lastClickTime < DOUBLE_CLICK_TIME_MS)
            {
                if (_item.hasChildren)
                {
                    _item.toggleExpand(_item);
                }
                else
                {
                    _item.activateItem(_item);
                }
            }
            lastClickTime = ts;
            return true;
        };
        _body = new Row(0);
        _body.id = "tree-item-body";
        _body.bindSubItem(this, "body");
        _body.setState(State.parent);
        if (_item.iconRes.length > 0)
        {
            _icon = new ImageWidget(_item.iconRes);
            _icon.id = "tree-item-icon";
            _icon.bindSubItem(this, "icon");
            _icon.setState(State.parent);
            _body.addChild(_icon);
        }
        _label = new Label(_item.text);
        _label.id = "tree-item-label";
        _label.bindSubItem(this, "label");
        _label.setState(State.parent);
        _body.addChild(_label);
        // append children
        addChild(_indent);
        if (_expander)
            addChild(_expander);
        addChild(_body);
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (keyEvent.assigned && keyEvent(this, event))
            return true; // processed by external handler
        if (!focused || !visible)
            return false;
        if (event.action != KeyAction.keyDown)
            return false;
        int action = 0;
        if (event.keyCode == KeyCode.space || event.keyCode == KeyCode.enter)
        {
            if (_item.hasChildren)
                _item.toggleExpand(_item);
            else
                _item.activateItem(_item);
            return true;
        }
        return false;
    }

    override bool onMouseEvent(MouseEvent event)
    {
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.right)
        {
            if (popupMenuBuilder.assigned)
            {
                if (auto menu = popupMenuBuilder(_item.root, _item))
                {
                    auto popup = window.showPopup(menu, WeakRef!Widget(this),
                            PopupAlign.point | PopupAlign.right, event.x, event.y);
                    return true;
                }
            }
        }
        return super.onMouseEvent(event);
    }

    void updateWidget()
    {
        if (_expander)
        {
            _expander.imageID = _item.expanded ? "arrow_right_down_black" : "arrow_right_hollow";
        }
        if (_item.isVisible)
            visibility = Visibility.visible;
        else
            visibility = Visibility.gone;
        if (_item.isSelected)
            setState(State.selected);
        else
            resetState(State.selected);
        if (_item.isDefault)
            setState(State.default_);
        else
            resetState(State.default_);
    }
}

/// Abstract tree widget
class TreeWidgetBase : ScrollArea, ActionOperator
{
    @property
    {
        ref TreeItems items()
        {
            return _tree;
        }

        bool noCollapseForSingleTopLevelItem() const
        {
            return _noCollapseForSingleTopLevelItem;
        }

        TreeWidgetBase noCollapseForSingleTopLevelItem(bool flag)
        {
            _noCollapseForSingleTopLevelItem = flag;
            if (_tree)
                _tree.noCollapseForSingleTopLevelItem = flag;
            return this;
        }
    }

    Signal!(void delegate(TreeItems, TreeItem, bool activated)) itemSelected;
    Signal!(void delegate(TreeItems, TreeItem)) expandChanged;

    /// Allows to provide individual popup menu for items
    Listener!(Menu delegate(TreeItems, TreeItem)) popupMenuBuilder;

    protected
    {
        TreeItems _tree;

        bool _needUpdateWidgets;
        bool _needUpdateWidgetStates;

        bool _noCollapseForSingleTopLevelItem;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        contentWidget = new Column(0);
        _tree = new TreeItems;
        _tree.contentChanged = &onTreeContentChange;
        _tree.stateChanged = &onTreeStateChange;
        _tree.itemSelected = &onTreeItemSelected;
        _tree.expandChanged = &onTreeItemExpanded;

        _needUpdateWidgets = true;
        _needUpdateWidgetStates = true;

        bindActions();
    }

    ~this()
    {
        unbindActions();
        eliminate(_tree);
    }

    /// Override to use custom tree item widgets
    protected Widget createItemWidget(TreeItem item)
    {
        auto res = new TreeItemWidget(item);
        res.popupMenuBuilder = &popupMenuBuilder.opCall;
        return res;
    }

    /// Returns item by id, null if not found
    TreeItem findItemByID(string id)
    {
        return _tree.findItemByID(id);
    }

    void clearAllItems()
    {
        items.clear();
        updateWidgets();
        requestLayout();
    }

    protected void addWidgets(TreeItem item)
    {
        if (item.level > 0)
            _contentWidget.addChild(createItemWidget(item));
        foreach (i; 0 .. item.childCount)
            addWidgets(item.child(i));
    }

    protected void updateWidgets()
    {
        _contentWidget.removeAllChildren();
        addWidgets(_tree);
        _needUpdateWidgets = false;
    }

    protected void updateWidgetStates()
    {
        foreach (i; 0 .. _contentWidget.childCount)
        {
            (cast(TreeItemWidget)_contentWidget.child(i)).maybe.updateWidget();
        }
        _needUpdateWidgetStates = false;
    }

    override Boundaries computeBoundaries()
    {
        if (_needUpdateWidgets)
            updateWidgets();
        if (_needUpdateWidgetStates)
            updateWidgetStates();
        return super.computeBoundaries();
    }

    protected void onTreeContentChange(TreeItems source)
    {
        _needUpdateWidgets = true;
        requestLayout();
    }

    protected void onTreeStateChange(TreeItems source)
    {
        _needUpdateWidgetStates = true;
        requestLayout();
    }

    protected void onTreeItemExpanded(TreeItems source, TreeItem item)
    {
        expandChanged(source, item);
    }

    protected void onTreeItemSelected(TreeItems source, TreeItem selectedItem, bool activated)
    {
        TreeItemWidget selected = findItemWidget(selectedItem);
        if (selected && selected.visibility == Visibility.visible)
        {
            selected.setFocus();
            makeWidgetVisible(selected, false, true);
        }
        itemSelected(source, selectedItem, activated);
    }

    TreeItemWidget findItemWidget(TreeItem item)
    {
        foreach (i; 0 .. _contentWidget.childCount)
        {
            TreeItemWidget child = cast(TreeItemWidget)_contentWidget.child(i);
            if (child && child.item is item)
                return child;
        }
        return null;
    }

    void makeItemVisible(TreeItem item)
    {
        TreeItemWidget widget = findItemWidget(item);
        if (widget && widget.visibility == Visibility.visible)
        {
            makeWidgetVisible(widget, false, true);
        }
    }

    void clearSelection()
    {
        _tree.selectItem(null);
    }

    void selectItem(TreeItem item, bool makeVisible = true)
    {
        if (!item)
        {
            clearSelection();
            return;
        }
        _tree.selectItem(item);
        if (makeVisible)
            makeItemVisible(item);
    }

    void selectItem(string itemID, bool makeVisible = true)
    {
        TreeItem item = findItemByID(itemID);
        selectItem(item, makeVisible);
    }

    protected void bindActions()
    {
        debug (trees)
            Log.d("Tree `", id, "`: bind actions");

        // TODO: implement page up
        ACTION_PAGE_UP.bind(this, &_tree.selectPrevious);
        // TODO: implement page down
        ACTION_PAGE_DOWN.bind(this, &_tree.selectNext);
        ACTION_PAGE_BEGIN.bind(this, { _vscrollbar.maybe.sendScrollEvent(ScrollAction.pageUp); });
        ACTION_PAGE_END.bind(this, { _vscrollbar.maybe.sendScrollEvent(ScrollAction.pageDown); });

        // TODO: ctrl+up, ctrl+left, ctrl+home, etc.
    }

    protected void unbindActions()
    {
        bunch(
            ACTION_PAGE_UP,
            ACTION_PAGE_DOWN,
            ACTION_PAGE_BEGIN,
            ACTION_PAGE_END
        ).unbind(this);
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (event.action == KeyAction.keyDown && event.flags == 0)
        {
            switch (event.keyCode) with (KeyCode)
            {
            case up:
                _tree.selectPrevious();
                return true;
            case down:
                _tree.selectNext();
                return true;
            case left:
                _hscrollbar.maybe.sendScrollEvent(ScrollAction.lineUp);
                return true;
            case right:
                _hscrollbar.maybe.sendScrollEvent(ScrollAction.lineDown);
                return true;
            default:
                break;
            }
        }
        return super.onKeyEvent(event);
    }
}

/// Tree widget with items which can have icons and labels
class TreeWidget : TreeWidgetBase
{
    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
    }
}
