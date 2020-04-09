/**
Tree widgets.

Synopsis:
---
// tree example
auto panel = new Panel;
    auto treeItemLabel = new Label;
    auto tree = new TreeWidget;
panel.add(treeItemLabel, tree);

panel.style.display = "column";
treeItemLabel.style.textAlign = TextAlign.center;
tree.style.stretch = Stretch.both;

TreeItem tree1 = tree.items.newChild("g1", "Group 1"d, "folder");
tree1.newChild("g1_1", "item 1"d, "text-plain");
tree1.newChild("g1_2", "item 2"d, "text-plain");
tree1.newChild("g1_3", "item 3"d, "text-plain");
TreeItem tree2 = tree.items.newChild("g2", "Group 2"d);
tree2.newChild("g2_1", "item 1"d);
tree2.newChild("g2_2", "item 2"d);
tree2.newChild("g2_3", "item 3"d);
TreeItem tree2_4 = tree2.newChild("g2_4", "Group 2.1"d);
tree2_4.newChild("g2_4_1", "item 1"d);
tree2_4.newChild("g2_4_2", "item 2"d);
tree2_4.newChild("g2_4_3", "item 3"d);
tree2_4.newChild("g2_4_4", "item 4"d);
tree2_4.newChild("g2_4_5", "item 5"d);
tree2.newChild("g2_5", "item 4"d);

tree.onSelect ~= (TreeItem selectedItem, bool activated) {
    dstring label = "Selected item: "d ~ toUTF32(selectedItem.id) ~ (activated ? " selected + activated"d : " selected"d);
    treeItemLabel.text = label;
};
tree.selectItem("g1");
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.tree;
/+
import beamui.core.stdaction;
import beamui.widgets.controls;
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
        /// Returns topmost item. Tree items are not supposed to be used without root
        inout(RootTreeItem) root() inout
            out(r; r, "No tree root item")
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
            if (_text != s)
            {
                _text = s;
                handleUpdate();
            }
        }
        /// Tree item icon
        string iconID() const { return _iconID; }
        /// ditto
        void iconID(string res)
        {
            if (_iconID != res)
            {
                _iconID = res;
                handleUpdate();
            }
        }

        /// Nesting level of this item
        uint level() const { return _level; }
        /// ditto
        protected void level(uint value)
        {
            _level = value;
            foreach (i; 0 .. childCount)
                child(i).level = _level + 1;
        }

        /// Returns true if item has subitems and can collapse or expand itself
        bool canExpandOrCollapse() const
        {
            return root.canExpandOrCollapseItem(this);
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

        /// Get selected item in the tree, possibly `null`. The root cannot be selected
        TreeItem selectedItem()
        {
            return root.selectedItem;
        }
        /// Get default item in the tree, possibly `null`. The root cannot be default
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
        uint _level;
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
            if (!c._expanded && c.canExpandOrCollapse)
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
            if (c._expanded && c.canExpandOrCollapse)
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
        RootTreeItem root = this.root;
        if (hasDescendant(root.selectedItem))
            root.selectItem(null);
        if (hasDescendant(root.defaultItem))
            root.setDefaultItem(null);
        foreach (c; _children)
        {
            c.parent = null;
            c.level = 0;
        }
        _children.clear();
        root.handleUpdate();
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
        in(item)
    {
        if (index >= 0)
            _children.insert(index, item);
        else
            _children.append(item);
        item.parent = this;
        item.level = _level + 1;
        item.handleUpdate();
        return item;
    }
    /// Removes child, returns removed item
    TreeItem removeChild(int index)
    {
        const count = _children.count;
        if (index < 0 || count <= index)
            return null;

        RootTreeItem root = this.root;
        TreeItem res = _children.remove(index);
        assert(res);
        TreeItem newSelection;
        if (root.selectedItem is res)
        {
            if (index < _children.count)
                newSelection = _children[index];
            else if (index != 0)
                newSelection = _children[index - 1];
            else
                newSelection = res.parent;
        }
        root.selectItem(newSelection);
        if (root.defaultItem is res || res.hasDescendant(root.defaultItem))
            root.setDefaultItem(null);
        res.parent = null;
        res.level = 0;
        root.handleUpdate();
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

    bool hasDescendant(TreeItem item) const
    {
        if (!item)
            return false;
        TreeItem p = item.parent;
        while (p)
        {
            if (this is p)
                return true;
            p = p.parent;
        }
        return false;
    }

    /// Notify listeners
    protected void handleUpdate()
    {
        root.handleUpdate();
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
            if (auto res = child(i).nextVisible(item, found))
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
            if (auto res = child(i).prevVisible(item, prevFoundVisible))
                return res;
        }
        return null;
    }

    /// Get an item of this sub-tree by id, `null` if not found
    TreeItem findItemByID(string id)
    {
        if (_id == id)
            return this;
        foreach (i; 0 .. childCount)
        {
            if (auto res = child(i).findItemByID(id))
                return res;
        }
        return null;
    }
}

/// Invisible root item
class RootTreeItem : TreeItem
{
    override @property TreeItem selectedItem() { return _selectedItem; }
    override @property TreeItem defaultItem() { return _defaultItem; }

    override @property bool isRoot() const
    {
        return true;
    }

    Listener!(void delegate()) onContentChange;
    Listener!(void delegate()) onStateChange;
    Listener!(void delegate(TreeItem)) onToggleExpand;
    Listener!(void delegate(TreeItem, bool activated)) onSelect;

    bool canExpandOrCollapseTopLevel = true;

    private TreeItem _selectedItem;
    private TreeItem _defaultItem;

    this()
    {
        super("root");
    }

    bool canExpandOrCollapseItem(const(TreeItem) item) const
    {
        if (item.level > 0)
        {
            if (item.level > 1 || canExpandOrCollapseTopLevel)
                return item.hasChildren;
        }
        return false;
    }

    override void clear()
    {
        selectItem(null);
        setDefaultItem(null);
        foreach (c; _children)
        {
            c.parent = null;
            c.level = 0;
        }
        _children.clear();
        handleUpdate();
    }

    override protected void handleUpdate()
    {
        onContentChange();
    }

    override void toggleExpand(TreeItem item)
    {
        bool changed;
        if (item.expanded)
        {
            if (item.canExpandOrCollapse)
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
        onStateChange();
        if (changed)
            onToggleExpand(item);
    }

    override void selectItem(TreeItem item)
    {
        if (_selectedItem is item)
            return;
        if (item is this)
            item = null;
        _selectedItem = item;
        onStateChange();
        onSelect(item, false);
    }

    void setDefaultItem(TreeItem item)
    {
        if (item is this)
            item = null;
        _defaultItem = item;
        onStateChange();
    }

    override void activateItem(TreeItem item)
    {
        if (item is this)
            item = null;
        if (_selectedItem !is item)
        {
            _selectedItem = item;
            onStateChange();
        }
        onSelect(item, true);
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
class TreeItemWidget : Panel
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
        Panel _body;
        long lastClickTime;
    }

    this(TreeItem item)
        in(item)
    {
        super(item.id);
        _item = item;

        isolateStyle();
        allowsClick = true;
        allowsFocus = true;
        allowsHover = true;

        int icount = _item.level - 1;
        if (!_item.root.canExpandOrCollapseTopLevel)
            icount--;
        if (icount > 0)
        {
            _indent = new Widget;
            const w = icount * font.size * 2;
            _indent.style.minWidth = w;
            _indent.style.maxWidth = w;
        }
        if (_item.canExpandOrCollapse)
        {
            _expander = new ImageWidget;
            _expander.setAttribute("expander");
            _expander.allowsClick = true;
            _expander.allowsHover = true;

            _expander.onClick ~= {
                _item.selectItem(_item);
                _item.toggleExpand(_item);
            };
        }
        _body = new Panel(null, "body");
        if (_item.iconID.length > 0)
        {
            _icon = new ImageWidget(_item.iconID);
            _icon.setAttribute("icon");
            _body.addChild(_icon);
        }
        _label = new Label(_item.text);
        _label.setAttribute("label");
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
    }

    override bool handleKeyEvent(KeyEvent event)
    {
        if (onKeyEvent.assigned && onKeyEvent(event))
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

    override bool handleMouseEvent(MouseEvent event)
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
        return super.handleMouseEvent(event);
    }

    void updateWidgetState()
    {
        if (_expander)
        {
            _expander.imageID = _item.expanded ? "arrow_right_down_black" : "arrow_right_hollow";
        }
        visibility = _item.isVisible ? Visibility.visible : Visibility.gone;
        applyState(State.selected, _item.selectedItem is _item);
        applyState(State.default_, _item.defaultItem is _item);
    }
}

/// Abstract tree widget
class TreeWidgetBase : ScrollArea, ActionOperator
{
    /// Access tree items
    @property RootTreeItem items() { return _tree; }

    Signal!(void delegate(TreeItem, bool activated)) onSelect;
    Signal!(void delegate(TreeItem)) onToggleExpand;

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
        contentWidget = new Panel;
        _tree = new RootTreeItem;
        _tree.onContentChange = &handleTreeContentChange;
        _tree.onStateChange = &handleTreeStateChange;
        _tree.onSelect = &handleTreeItemSelection;
        _tree.onToggleExpand = &handleTreeItemOpening;

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
        {
            Widget w = createItemWidget(item);
            contentWidget.addChild(w);
            if (item is _tree.selectedItem)
                w.setFocus();
        }
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

    override protected Boundaries computeBoundaries()
    {
        if (_needUpdateWidgets)
            updateWidgets();
        if (_needUpdateWidgetStates)
            updateWidgetStates();
        return super.computeBoundaries();
    }

    protected void handleTreeContentChange()
    {
        _needUpdateWidgets = true;
        requestLayout();
    }

    protected void handleTreeStateChange()
    {
        _needUpdateWidgetStates = true;
        requestLayout();
    }

    protected void handleTreeItemOpening(TreeItem item)
    {
        onToggleExpand(item);
    }

    protected void handleTreeItemSelection(TreeItem selectedItem, bool activated)
    {
        TreeItemWidget selected = findItemWidget(selectedItem);
        if (selected && selected.visibility == Visibility.visible)
        {
            selected.setFocus();
            makeWidgetVisible(selected, false, true);
        }
        onSelect(selectedItem, activated);
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
        foreach (Action a; tup(
            ACTION_PAGE_UP,
            ACTION_PAGE_DOWN,
            ACTION_PAGE_BEGIN,
            ACTION_PAGE_END
        ))
        {
            a.unbind(this);
        }
    }

    override bool handleKeyEvent(KeyEvent event)
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
        return super.handleKeyEvent(event);
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

//===============================================================
// Tests

unittest
{
    auto item = new TreeItem("root");
    assert(!item.parent);
    assert(item.level == 0);
    assert(item.isFullyExpanded);
    assert(!item.isVisible);
    assert(!item.findItemByID("123"));
    assert(item.findItemByID("root") is item);
}

unittest
{
    auto root = new RootTreeItem;
    assert(root.root is root);
    assert(!root.parent);
    assert(root.level == 0);
    assert(!root.canExpandOrCollapse);
    assert(root.expanded);
    root.expandAll();
    root.collapseAll();
    assert(root.expanded);
    assert(root.isFullyExpanded);
    assert(!root.isVisible);
    assert(!root.selectedItem);
    assert(!root.defaultItem);
    root.selectItem(root);
    root.setDefaultItem(root);
    assert(!root.selectedItem);
    assert(!root.defaultItem);
    assert(!root.findItemByID("123"));
    assert(root.findItemByID("root") is root);
}

unittest
{
    auto root = new RootTreeItem;
    auto item = root.newChild("id", null);
    assert(root.childCount == 1);
    assert(root.child(0) is item);
    assert(root.childIndex(item) == 0);
    assert(item.root is root);
    assert(item.parent is root);
    assert(item.level == 1);
    assert(!item.canExpandOrCollapse);
    assert(!root.canExpandOrCollapse);
    root.collapseAll();
    assert(root.expanded);
    assert(item.expanded);
    assert(item.isFullyExpanded);
    assert(item.isVisible);
    root.selectItem(item);
    assert(root.selectedItem is item);
    root.setDefaultItem(item);
    assert(root.defaultItem is item);
    root.selectItem(null);
    assert(root.defaultItem is item);

    root.removeChild(item);
    assert(!item.parent);
    assert(item.level == 0);
    assert(root.childCount == 0);
    assert(!root.selectedItem);
    assert(!root.defaultItem);

    root.addChild(item);
    assert(root.hasChildren);
    assert(root.findItemByID("id") is item);
    root.selectItem(item);
    root.setDefaultItem(item);
    root.clear();
    assert(!root.hasChildren);
    assert(!root.selectedItem);
    assert(!root.defaultItem);
}

unittest
{
    auto root = new RootTreeItem;
    TreeItem tree1 = root.newChild("1", null);
    tree1.newChild("1_1", null);
    tree1.newChild("1_2", null);
    tree1.newChild("1_3", null);
    TreeItem tree1_1 = tree1.newChild("1_4", null);
    tree1_1.newChild("1_4_1", null);
    tree1_1.newChild("1_4_2", null);

    assert(tree1.childCount == 4);
    assert(tree1.canExpandOrCollapse);
    assert(tree1.isFullyExpanded);
    tree1.collapseAll();
    assert(!tree1.isFullyExpanded);
    assert(tree1.isVisible);
    assert(!tree1_1.expanded);
    assert(!tree1_1.isFullyExpanded);
    assert(!tree1_1.isVisible);

    assert(root.findItemByID("1_4_2") is tree1_1.child(1));

    assert(root.hasDescendant(tree1));
    assert(tree1.hasDescendant(tree1_1.child(0)));
    assert(tree1_1.hasDescendant(tree1_1.child(1)));
    assert(!tree1_1.hasDescendant(tree1_1));
    assert(!tree1_1.hasDescendant(tree1));
    assert(!tree1_1.hasDescendant(root));
    assert(!root.hasDescendant(root));

    root.selectItem(tree1_1);
    root.setDefaultItem(tree1_1);
    root.removeChild(tree1);
    assert(!root.hasChildren);
    assert(!root.selectedItem);
    assert(!root.defaultItem);
}
+/
