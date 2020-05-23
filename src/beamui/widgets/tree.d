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

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.tree;

import beamui.widgets.controls : ImageWidget;
import beamui.widgets.text : Label;
import beamui.widgets.widget;

/// Abstract tree item
abstract class TreeItemWidgetBase : WidgetGroupOf!Widget
{
    /// True if this item is expanded
    bool expanded;

    protected TreeItemWidgetBase[] _items;
    protected TreeItemWidgetBase _parent;
    protected uint _index;
    protected uint _level;

    protected bool _selected;
    protected bool _default;

    final void setItems(size_t count, scope TreeItemWidgetBase delegate(size_t) generator)
    {
        if (count == 0 || !generator)
            return;

        _items = arena.allocArray!TreeItemWidgetBase(count);
        foreach (i; 0 .. count)
            _items[i] = generator(i);
    }

    /// Returns true if the item has subitems and so may collapse or expand itself
    protected @property bool canExpandOrCollapse() const
    {
        return _items.length > 0;
    }

    protected void select()
    {
        TreeWidget tree = cast(TreeWidget)parent;
        if (tree && tree.onSelect)
            tree.onSelect(getPath());
    }

    protected void toggle()
    {
        TreeWidget tree = cast(TreeWidget)parent;
        if (tree && tree.onExpandToggle)
            tree.onExpandToggle(getPath());
    }

    private uint[] getPath()
    {
        uint[] path;
        getPath(path);
        return path;
    }

    private void getPath(ref uint[] path)
    {
        if (_parent)
        {
            _parent.getPath(path);
            path ~= _index;
        }
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.applyState(State.selected, _selected);
        el.applyState(State.default_, _default);
    }
}

private class ClickableImage : ImageWidget
{
    void delegate() onClick;

    this()
    {
        allowsHover = true;
    }

    override protected Element createElement()
    {
        auto el = super.createElement();
        el.allowsClick = true;
        return el;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.onClick.clear();
        if (onClick)
            el.onClick ~= onClick;
    }
}

/// Tree item widget with a label and icon
class TreeItemWidget : TreeItemWidgetBase
{
    dstring text;
    string iconID;

    this()
    {
        allowsFocus = true;
        allowsHover = true;
    }

    private alias wrap = typeof(super).wrap;

    override protected void build()
    {
        ClickableImage expander;
        if (canExpandOrCollapse)
        {
            expander = render!ClickableImage;
            expander.imageID = expanded ? "arrow_right_down_black" : "arrow_right_hollow";
            expander.onClick = &toggle;
            expander.namespace = null;
        }
        ImageWidget image;
        if (iconID.length)
        {
            image = render!ImageWidget;
            image.imageID = iconID;
            image.namespace = null;
        }
        Label label;
        if (text.length)
        {
            label = render!Label;
            label.text = text;
            label.namespace = null;
        }
        wrap(
            expander,
            render((Panel p) {
                p.namespace = null;
            }).wrap(
                image,
                label,
            )
        );
    }

    override protected Element createElement()
    {
        auto el = new ElemPanel;
        el.allowsClick = true;
        return el;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.style.marginLeft = _level * el.font.size * 2;

        el.onClick.clear();
        el.onClick ~= &select;
    }
}

class TreeWidget : Widget
{
    /// Invisible topmost item
    TreeItemWidgetBase root;

    uint[] selected;
    uint[] marked;

    void delegate(uint[] path) onSelect;
    void delegate(uint[] path) onExpandToggle;

    override protected void build()
    {
        if (root)
        {
            root.expanded = true;
            configureItem(root, 0);

            if (auto item = findItem(root, selected))
                item._selected = true;
            if (auto item = findItem(root, marked))
                item._default = true;
        }
    }

    private void configureItem(TreeItemWidgetBase item, uint level)
    {
        foreach (i, subitem; item._items)
        {
            if (subitem)
            {
                subitem._parent = item;
                subitem._index = cast(uint)i;
                subitem._level = level;
                configureItem(subitem, level + 1);
            }
        }
    }

    private TreeItemWidgetBase findItem(TreeItemWidgetBase root, uint[] path)
    {
        TreeItemWidgetBase item = root;
        foreach (i; path)
        {
            if (item && i < item._items.length)
                item = item._items[i];
            else
                return null;
        }
        return item;
    }

    override int opApply(scope int delegate(size_t, Widget) callback)
    {
        uint i;
        iterateOver(root, i, callback);
        return 0;
    }

    private void iterateOver(TreeItemWidgetBase item, ref uint i, scope int delegate(size_t, Widget) callback)
    {
        if (!item || !item.expanded)
            return;
        foreach (wt; item._items)
        {
            callback(i, wt);
            i++;
            iterateOver(wt, i, callback);
        }
    }

    private bool handleEvent(KeyEvent e)
    {
        if (e.action == KeyAction.keyDown && e.noModifiers)
        {
        }
        return false;
    }

    override protected Element createElement()
    {
        return new ElemPanel;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.onKeyEvent ~= &handleEvent;

        foreach (i, item; this)
        {
            if (item)
                el.addChild(mountChild(item, el, i));
        }
    }
}
/+
import beamui.core.stdaction;
import beamui.widgets.menu;
import beamui.widgets.popup;
import beamui.widgets.scroll;
import beamui.widgets.scrollbar : ScrollAction;

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

        bool canExpandOrCollapse() const
        {
            return root.canExpandOrCollapseItem(this);
        }

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

class TreeItemWidget : Panel
{
    Listener!(Menu delegate(TreeItem)) popupMenuBuilder;

    private
    {
        long lastClickTime;
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
                    auto popup = window.showPopup(menu);
                    popup.anchor = WeakRef!Widget(this);
                    popup.alignment = PopupAlign.point | PopupAlign.right;
                    popup.point = Point(event.x, event.y);
                    return true;
                }
            }
        }
        return super.handleMouseEvent(event);
    }
}

class TreeWidgetBase : ScrollArea, ActionOperator
{
    Signal!(void delegate(TreeItem, bool activated)) onSelect;

    /// Allows to provide individual popup menu for items
    Listener!(Menu delegate(TreeItem)) popupMenuBuilder;

    private
    {
        RootTreeItem _tree;

        bool _needUpdateWidgets = true;
    }

    this(ScrollBarMode hscrollbarMode = ScrollBarMode.automatic,
         ScrollBarMode vscrollbarMode = ScrollBarMode.automatic)
    {
        _tree = new RootTreeItem;
        _tree.onSelect = &handleTreeItemSelection;

        bindActions();
    }

    ~this()
    {
        unbindActions();
        eliminate(_tree);
    }

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

    override protected Boundaries computeBoundaries()
    {
        if (_needUpdateWidgets)
            updateWidgets();
        return super.computeBoundaries();
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
        ACTION_PAGE_BEGIN.bind(this, &scrollTopEdge);
        ACTION_PAGE_END.bind(this, &scrollBottomEdge);

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
