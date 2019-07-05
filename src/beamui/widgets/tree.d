/**
Tree widgets.

Synopsis:
---
// tree example
auto treePane = new Column;
    auto treeItemLabel = new Label;
    auto tree = new TreeWidget;
treePane.add(treeItemLabel, tree);

treeItemLabel.style.textAlign = TextAlign.center;
tree.style.stretch = Stretch.both;

TreeItem tree1 = tree.items.newChild("group1", "Group 1"d, "folder");
tree1.newChild("g1_1", "item 1"d, "text-plain");
tree1.newChild("g1_2", "item 2"d, "text-plain");
tree1.newChild("g1_3", "item 3"d, "text-plain");
TreeItem tree2 = tree.items.newChild("group2", "Group 2"d);
tree2.newChild("g2_1", "item 1"d);
tree2.newChild("g2_2", "item 2"d);
tree2.newChild("g2_3", "item 3"d);
TreeItem tree22 = tree2.newChild("group2_1", "Group 2.1"d);
tree22.newChild("group3_2_1", "item 1"d);
tree22.newChild("group3_2_2", "item 2"d);
tree22.newChild("group3_2_3", "item 3"d);
tree22.newChild("group3_2_4", "item 4"d);
tree22.newChild("group3_2_5", "item 5"d);
tree2.newChild("g2_4", "item 4"d);

tree.itemSelected ~= (TreeItem selectedItem, bool activated) {
    dstring label = "Selected item: "d ~ toUTF32(selectedItem.id) ~ (activated ? " selected + activated"d : " selected"d);
    treeItemLabel.text = label;
};
tree.selectItem("group1");
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
import beamui.widgets.scrollbar : ScrollAction;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Tree widget item data container
class TreeItem
{
    @property
    {
        /// Returns topmost item
        inout(RootTreeItem) root() inout
        {
            TreeItem p = cast()this;
            while (p._parent)
                p = p._parent;
            return cast(inout(RootTreeItem))p;
        }

        /// Returns true if this is the root item
        bool isRoot() const
        {
            return false;
        }

        /// Tree item parent, `null` if it is the root
        inout(TreeItem) parent() inout { return _parent; }
        /// ditto
        protected void parent(TreeItem p)
        {
            _parent = p;
        }

        /// Tree item ID, must be unique if you search or select items by ID
        string id() const { return _id; }
        /// ditto
        void id(string id)
        {
            _id = id;
        }
        /// Tree item text
        dstring text() const { return _text; }
        /// ditto
        void text(dstring s)
        {
            _text = s;
        }
        /// Tree item icon
        string iconID() const { return _iconID; }
        /// ditto
        void iconID(string res)
        {
            _iconID = res;
        }

        /// Nesting level of this item
        int level() const { return _level; }
        /// ditto
        protected void level(int level)
        {
            _level = level;
            foreach (i; 0 .. childCount)
                child(i).level = _level + 1;
        }

        /// Returns true if item has subitems and can collapse or expand itself
        bool canCollapse() const
        {
            return root.canCollapseItem(this);
        }

        /// True if this item is expanded
        bool expanded() const { return _expanded; }
        /// ditto
        protected void expanded(bool expanded)
        {
            _expanded = expanded;
        }
        /// Returns true if this item and all parents are expanded
        bool isFullyExpanded() const
        {
            if (_expanded)
                return _parent ? _parent.isFullyExpanded : true;
            else
                return false;
        }
        /// Returns true if all parents are expanded
        bool isVisible() const
        {
            return _parent ? _parent.isFullyExpanded : false;
        }

        /// Get selected item in the tree
        TreeItem selectedItem()
        {
            return root.selectedItem;
        }
        /// Get default item in the tree
        TreeItem defaultItem()
        {
            return root.defaultItem;
        }

        /// Optional int value, associated with this item
        int intParam() const { return _intParam; }
        /// ditto
        void intParam(int value)
        {
            _intParam = value;
        }
        /// Optional object, associated with this item
        inout(Object) objectParam() inout { return _objectParam; }
        /// ditto
        void objectParam(Object value)
        {
            _objectParam = value;
        }
    }

    private
    {
        TreeItem _parent;
        string _id;
        dstring _text;
        string _iconID;
        int _level;
        Collection!(TreeItem, true) _children;
        bool _expanded;

        int _intParam;
        Object _objectParam;
    }

    this(string id)
    {
        _id = id;
        _expanded = true;
    }

    this(string id, dstring label, string iconID = null)
    {
        _id = id;
        _expanded = true;
        _iconID = iconID;
        _text = label;
    }

    bool compareID(string id) const
    {
        return _id !is null && _id == id;
    }

    protected void expand()
    {
        _expanded = true;
        if (_parent)
            _parent.expand();
    }
    protected void collapse()
    {
        _expanded = false;
    }
    /// Expand this node and all children
    void expandAll()
    {
        foreach (c; _children)
        {
            if (!c._expanded && c.canCollapse)
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
    TreeItem newChild(string id, dstring label, string iconID = null)
    {
        auto res = new TreeItem(id, label, iconID);
        addChild(res);
        return res;
    }

    /// Delete all subitems
    void clear()
    {
        foreach (c; _children)
        {
            c.parent = null;
            if (c is root.selectedItem)
                root.selectItem(null);
        }
        _children.clear();
        root.onUpdate();
    }

    /// Returns true if item has at least one child
    @property bool hasChildren() const
    {
        return _children.count > 0;
    }
    /// Returns number of children of this widget
    @property int childCount() const
    {
        return cast(int)_children.count;
    }
    /// Returns child by index
    TreeItem child(int index)
    {
        return _children[index];
    }
    /// Adds child, returns added item
    TreeItem addChild(TreeItem item, int index = -1)
    {
        if (index >= 0)
            _children.insert(index, item);
        else
            _children.append(item);
        item.parent = this;
        item.level = _level + 1;
        item.onUpdate();
        return item;
    }
    /// Removes child, returns removed item
    TreeItem removeChild(int index)
    {
        if (index < 0 || _children.count <= index)
            return null;
        TreeItem res = _children.remove(index);
        TreeItem newSelection;
        if (res)
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
        root.onUpdate();
        return res;
    }
    /// Removes child by reference, returns removed item
    TreeItem removeChild(TreeItem child)
    {
        int index = cast(int)_children.indexOf(child);
        return removeChild(index);
    }
    /// Removes child by ID, returns removed item
    TreeItem removeChild(string ID)
    {
        int index = cast(int)_children.indexOf(ID);
        return removeChild(index);
    }
    /// Returns index of widget in child list, -1 if passed widget is not a child of this widget
    int childIndex(TreeItem item)
    {
        return cast(int)_children.indexOf(item);
    }

    /// Notify listeners
    protected void onUpdate()
    {
        root.onUpdate();
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

    /// Returns item by id, `null` if not found
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

/// Fake tree root item
class RootTreeItem : TreeItem
{
    override @property TreeItem selectedItem() { return _selectedItem; }
    override @property TreeItem defaultItem() { return _defaultItem; }

    override @property bool isRoot() const
    {
        return true;
    }

    Listener!(void delegate()) contentChanged;
    Listener!(void delegate()) stateChanged;
    Listener!(void delegate(TreeItem)) expandChanged;
    Listener!(void delegate(TreeItem, bool activated)) itemSelected;

    bool canCollapseTopLevel = true;

    private TreeItem _selectedItem;
    private TreeItem _defaultItem;

    this()
    {
        super("root");
    }

    bool canCollapseItem(const(TreeItem) item) const
    {
        if (item.level == 1)
            return canCollapseTopLevel && item.hasChildren;
        else
            return item.hasChildren;
    }

    override protected void onUpdate()
    {
        contentChanged();
    }

    override void toggleExpand(TreeItem item)
    {
        bool changed;
        if (item.expanded)
        {
            if (item.canCollapse)
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
        stateChanged();
        if (changed)
            expandChanged(item);
    }

    override void selectItem(TreeItem item)
    {
        if (_selectedItem is item)
            return;
        _selectedItem = item;
        stateChanged();
        itemSelected(_selectedItem, false);
    }

    void setDefaultItem(TreeItem item)
    {
        _defaultItem = item;
        stateChanged();
    }

    override void activateItem(TreeItem item)
    {
        if (!(_selectedItem is item))
        {
            _selectedItem = item;
            stateChanged();
        }
        itemSelected(_selectedItem, true);
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

/// Item widget for displaying in trees
class TreeItemWidget : Row
{
    /// TreeItem prototype of this widget
    @property TreeItem item() { return _item; }

    Listener!(Menu delegate(TreeItem)) popupMenuBuilder;

    private
    {
        TreeItem _item;
        Widget _indent;
        ImageWidget _expander;
        ImageWidget _icon;
        Label _label;
        Row _body;
        long lastClickTime;
    }

    this(TreeItem item)
    {
        _item = item;
        id = item.id;

        allowsClick = true;
        allowsFocus = true;
        allowsHover = true;

        int icount = _item.level - 1;
        if (!_item.root.canCollapseTopLevel)
            icount--;
        if (icount > 0)
        {
            _indent = new Widget("tree-item-indent");
            int w = icount * font.size * 2;
            _indent.style.minWidth = w;
            _indent.style.maxWidth = w;
        }
        if (_item.canCollapse)
        {
            _expander = new ImageWidget;
            _expander.id = "tree-item-expander";
            _expander.bindSubItem(this, "expander");
            _expander.allowsClick = true;
            _expander.allowsHover = true;

            _expander.clicked ~= {
                _item.selectItem(_item);
                _item.toggleExpand(_item);
            };
        }
        _body = new Row;
        _body.id = "tree-item-body";
        _body.bindSubItem(this, "body");
        _body.setState(State.parent);
        if (_item.iconID.length > 0)
        {
            _icon = new ImageWidget(_item.iconID);
            _icon.id = "tree-item-icon";
            _icon.bindSubItem(this, "icon");
            _icon.setState(State.parent);
            _body.addChild(_icon);
        }
        _label = new Label(_item.text);
        _label.id = "tree-item-label";
        _label.bindSubItem(this, "label");
        _label.setState(State.parent);
        _body.add(_label);
        // append children
        addSome(_indent, _expander, _body);

        updateWidgetState();
    }

    override protected void handleClick()
    {
        import beamui.core.events : DOUBLE_CLICK_THRESHOLD_MS;

        long ts = currentTimeMillis();
        _item.selectItem(_item);
        if (ts - lastClickTime < DOUBLE_CLICK_THRESHOLD_MS)
        {
            if (_item.hasChildren)
                _item.toggleExpand(_item);
            else
                _item.activateItem(_item);
        }
        else
            lastClickTime = ts;
        super.handleClick();
    }

    override bool onKeyEvent(KeyEvent event)
    {
        if (keyEvent.assigned && keyEvent(event))
            return true; // processed by external handler
        if (!focused || !visible)
            return false;
        if (event.action != KeyAction.keyDown)
            return false;
        if (event.key == Key.space || event.key == Key.enter)
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
                if (auto menu = popupMenuBuilder(_item))
                {
                    auto popup = window.showPopup(menu, WeakRef!Widget(this),
                            PopupAlign.point | PopupAlign.right, event.x, event.y);
                    return true;
                }
            }
        }
        return super.onMouseEvent(event);
    }

    void updateWidgetState()
    {
        if (_expander)
        {
            _expander.imageID = _item.expanded ? "arrow_right_down_black" : "arrow_right_hollow";
        }
        if (_item.isVisible)
            visibility = Visibility.visible;
        else
            visibility = Visibility.gone;
        if (_item.selectedItem is _item)
            setState(State.selected);
        else
            resetState(State.selected);
        if (_item.defaultItem is _item)
            setState(State.default_);
        else
            resetState(State.default_);
    }
}

/// Abstract tree widget
class TreeWidgetBase : ScrollArea, ActionOperator
{
    /// Access tree items
    @property RootTreeItem items() { return _tree; }

    Signal!(void delegate(TreeItem, bool activated)) itemSelected;
    Signal!(void delegate(TreeItem)) expandChanged;

    /// Allows to provide individual popup menu for items
    Listener!(Menu delegate(TreeItem)) popupMenuBuilder;

    private
    {
        RootTreeItem _tree;

        bool _needUpdateWidgets;
        bool _needUpdateWidgetStates;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        super(hscrollbarMode, vscrollbarMode);
        contentWidget = new Column(0);
        _tree = new RootTreeItem;
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

    /// Returns item by id, `null` if not found
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
            contentWidget.addChild(createItemWidget(item));
        foreach (i; 0 .. item.childCount)
            addWidgets(item.child(i));
    }

    protected void updateWidgets()
    {
        contentWidget.removeAllChildren();
        addWidgets(_tree);
        _needUpdateWidgets = false;
    }

    protected void updateWidgetStates()
    {
        foreach (i; 0 .. contentWidget.childCount)
        {
            (cast(TreeItemWidget)contentWidget.child(i)).maybe.updateWidgetState();
        }
        _needUpdateWidgetStates = false;
    }

    override void measure()
    {
        if (_needUpdateWidgets)
            updateWidgets();
        if (_needUpdateWidgetStates)
            updateWidgetStates();
        super.measure();
    }

    protected void onTreeContentChange()
    {
        _needUpdateWidgets = true;
        requestLayout();
    }

    protected void onTreeStateChange()
    {
        _needUpdateWidgetStates = true;
        requestLayout();
    }

    protected void onTreeItemExpanded(TreeItem item)
    {
        expandChanged(item);
    }

    protected void onTreeItemSelected(TreeItem selectedItem, bool activated)
    {
        TreeItemWidget selected = findItemWidget(selectedItem);
        if (selected && selected.visibility == Visibility.visible)
        {
            selected.setFocus();
            makeWidgetVisible(selected, false, true);
        }
        itemSelected(selectedItem, activated);
    }

    TreeItemWidget findItemWidget(TreeItem item)
    {
        foreach (i; 0 .. contentWidget.childCount)
        {
            TreeItemWidget child = cast(TreeItemWidget)contentWidget.child(i);
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
        ACTION_PAGE_BEGIN.bind(this, &scrollTopCorner);
        ACTION_PAGE_END.bind(this, &scrollBottomCorner);

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
        if (event.action == KeyAction.keyDown && event.noModifiers)
        {
            switch (event.key)
            {
            case Key.up:
                _tree.selectPrevious();
                return true;
            case Key.down:
                _tree.selectNext();
                return true;
            case Key.left:
                scrollLeft();
                return true;
            case Key.right:
                scrollRight();
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
