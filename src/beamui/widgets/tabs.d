/**
Tabbed controls.

Mostly you will use only TabWidget class. Other classes are ancillary.

Synopsis:
---
// create tab widget
auto tabs = new TabWidget;
// and add tabs
// content widgets must have different non-null ids
tabs.addTab(new Label("1st tab content"d).setID("tab1"), "Tab 1");
tabs.addTab(new Label("2st tab content"d).setID("tab2"), "Tab 2");
// tab widget consists of two parts: tabControl and tabHost
tabs.tabHost.style.padding = 12;
tabs.tabHost.style.backgroundColor = 0xbbbbbb;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.tabs;

import beamui.widgets.controls;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Callback type for tab close button
alias TabCloseHandler = void delegate();

/// Tab header widget
class TabItem : Panel
{
    /// Tab title
    dstring text;
    /// Tab icon resource ID
    string iconID;
    /// If assigned, the tab close button will be visible
    TabCloseHandler onClose;

    this()
    {
        allowsHover = true;
        isolateStyle = true;
    }

    protected alias wrap = typeof(super).wrap;

    override protected void build()
    {
        ImageWidget image;
        if (iconID.length)
        {
            image = render!ImageWidget;
            image.imageID = iconID;
            image.attributes["icon"];
            image.tooltip = tooltip;
        }
        Label label;
        if (text.length)
        {
            label = render!Label;
            label.text = text;
            label.attributes["label"];
            label.tooltip = tooltip;
        }
        Button closeBtn;
        if (onClose)
        {
            closeBtn = render!Button;
            closeBtn.iconID = "close";
            closeBtn.attributes["close"];
            closeBtn.onClick = onClose;
            closeBtn.tooltip = tooltip;
        }
        wrap(image, label, closeBtn);
    }
}

class TabBar : WidgetGroupOf!TabItem
{
    override protected Element createElement()
    {
        return new ElemPanel;
    }
}

abstract class PageStackOf(W : Widget) : WidgetGroupOf!W
{
    int visibleItemIndex;
    bool buildHiddenItems;

    override protected void build()
    {
        const idx = visibleItemIndex;
        W item;
        if (0 <= idx && idx < _children.length)
            item = _children[idx];

        if (!buildHiddenItems)
        {
            _children[] = null;
            if (item)
                _children[idx] = item;
        }
        else
        {
            foreach (ref w; _children)
            {
                if (w && w !is item)
                    w.visible = false;
            }
        }
    }
}

class PageStack : PageStackOf!Widget
{
    override protected Element createElement()
    {
        return new ElemPanel;
    }
}

class TabPane : WidgetWrapperOf!Widget
{
    override protected Element createElement()
    {
        return new ElemPanel;
    }
}

/// Container for tab panels
class TabContent : PageStackOf!TabPane
{
    override protected Element createElement()
    {
        return new ElemPanel;
    }
}

alias TabPair = WidgetPair!(TabItem, Widget);

class TabWidget : Widget
{
    /// Tab bar position - top or bottom
    Align alignment = Align.top;
    bool buildHiddenTabs;

    protected TabBar _bar;
    protected TabContent _content;

    final TabWidget wrap(TabPair[] tabs...)
    {
        if (tabs.length == 0)
            return this;

        _bar = render!TabBar;
        _content = render!TabContent;

        auto items = arena.allocArray!TabItem(tabs.length);
        auto panes = arena.allocArray!TabPane(tabs.length);
        foreach (i, pair; tabs)
        {
            items[i] = pair.a;
            TabPane p = render!TabPane;
            p.wrap(pair.b);
            panes[i] = p;
        }
        _bar.wrap(items);
        _content.wrap(panes);
        return this;
    }

    override int opApply(scope int delegate(size_t, Widget) callback)
    {
        if (const result = callback(0, _bar))
            return result;
        if (const result = callback(1, _content))
            return result;
        return 0;
    }

    override protected void build()
    {
        if (!_bar || !_content)
            return;

        attributes[alignment == Align.top ? "top" : "bottom"];

        _content.buildHiddenItems = buildHiddenTabs;
    }

    override protected Element createElement()
    {
        return new ElemPanel;
    }

    override protected void updateElement(Element el)
    {
        super.updateElement(el);

        el.focusGroup = true;

        if (alignment == Align.top)
        {
            if (_bar)
                el.addChild(mountChild(_bar, el, 0));
            if (_content)
                el.addChild(mountChild(_content, el, 1));
        }
        else
        {
            if (_content)
                el.addChild(mountChild(_content, el, 1));
            if (_bar)
                el.addChild(mountChild(_bar, el, 0));
        }
    }
}
/+
import beamui.widgets.menu;
import beamui.widgets.popup;

/// Current tab is changed handler
alias TabChangeHandler = void delegate(string newActiveTabID, string previousTabID);
alias TabCloseHandler = void delegate(string tabID);

class TabItem : Panel
{
    @property
    {
        /// Tab last access time
        long lastAccessTime() const { return _lastAccessTime; }
    }

    /// Signals tab close button click
    Signal!TabCloseHandler onTabClose;

    private
    {
        static long _lastAccessCounter;
        long _lastAccessTime;
    }

    this(string id)
    {
        super(id);
        allowsClick = true;
        _lastAccessTime = _lastAccessCounter++;
    }

    void updateAccessTime()
    {
        _lastAccessTime = _lastAccessCounter++;
    }
}

/// Tab header - tab labels, with optional More button
class TabControl : WidgetGroup
{
    @property
    {
        /// More button custom icon
        string moreButtonIcon()
        {
            return _moreButton.iconID;
        }
        /// ditto
        void moreButtonIcon(string resourceID)
        {
            _moreButton.iconID = resourceID;
        }

        string selectedTabID() const { return _selectedTabID; }
    }

    /// Signal of tab change (e.g. by clicking on tab header)
    Signal!TabChangeHandler onTabChange;
    /// Signals tab close button click
    Signal!TabCloseHandler onTabClose;
    /// Signals more button click
    Signal!(void delegate()) onMoreButtonClick;
    /// Handler for more button popup menu
    Signal!(Menu delegate(Widget)) moreButtonPopupMenuBuilder;

    /// When true, more button is visible
    bool enableMoreButton = true;

    private
    {
        Button _moreButton;
        Buf!(Tup!(int, long)) _sortedItems;

        string _selectedTabID;

        Align _tabAlignment;
    }

    this(Align tabAlign = Align.top)
    {
        _moreButton = new Button(null, "tab_more");
        _moreButton.isolateThisStyle();
        _moreButton.setAttribute("more");
        _moreButton.onMouseEvent ~= &handleMoreBtnMouse;
        addChild(_moreButton); // first child is always MORE button, the rest corresponds to tab list
    }

    /// Returns tab count
    @property int tabCount() const
    {
        return childCount - 1;
    }
    /// Returns tab item by index (`null` if index is out of range)
    TabItem tab(int index)
    {
        if (0 <= index && index < childCount - 1)
            return cast(TabItem)child(index + 1);
        else
            return null;
    }
    /// Returns tab item by id (`null` if not found)
    inout(TabItem) tab(string id) inout
    {
        foreach (i; 1 .. childCount)
        {
            if (auto wt = cast(inout(TabItem))child(i))
                if (wt.id == id)
                    return wt;
        }
        return null;
    }
    /// Get tab index by tab id (-1 if not found)
    int tabIndex(string id)
    {
        foreach (i; 1 .. childCount)
            if (child(i).id == id)
                return i - 1;
        return -1;
    }

    protected const(Tup!(int, long)[]) sortedItems()
    {
        _sortedItems.resize(tabCount);
        foreach (i, ref item; _sortedItems.unsafe_slice)
        {
            item[0] = cast(int)i + 1;
            if (auto wt = cast(TabItem)child(item[0]))
                item[1] = wt.lastAccessTime;
            else
                item[1] = -1;
        }
        sort!((a, b) => a[1] > b[1])(_sortedItems.unsafe_slice);
        return _sortedItems[];
    }

    /// Find next or previous tab index, based on access time
    int getNextItemIndex(int direction)
    {
        if (tabCount == 0)
            return -1;
        if (tabCount == 1)
            return 0;
        const items = sortedItems();
        int len = cast(int)items.length;
        foreach (i; 0 .. len)
        {
            if (child(items[i][0]).id == _selectedTabID)
            {
                int index = wrapAround(i + direction, 0, len - 1);
                return items[index][0] - 1;
            }
        }
        return -1;
    }

    /// Add new tab
    void addTab(TabItem item, int index = -1)
    {
        item.onMouseEvent ~= (MouseEvent e) { return handleTabBtnMouse(item.id, e); };
        item.onWheelEvent ~= &handleTabBtnWheel;
        item.onTabClose ~= &onTabClose.emit;
        if (index >= 0)
            insertChild(index, item);
        else
            addChild(item);
    }
    /// Add new tab by id and label string
    void addTab(string id, dstring label, string iconID = null, bool enableCloseButton = false,
            dstring tooltipText = null)
    {
        auto item = new TabItem(id, label, iconID, enableCloseButton, tooltipText);
        addTab(item);
    }

    /// Remove tab
    void removeTab(string id)
    {
        string nextID;
        if (id == _selectedTabID)
        {
            _selectedTabID = null;
            // current tab is being closed: remember next tab id
            int nextIndex = getNextItemIndex(1);
            if (nextIndex < 0)
                nextIndex = getNextItemIndex(-1);
            if (nextIndex >= 0)
                nextID = child(nextIndex + 1).id;
        }
        int index = tabIndex(id);
        if (index >= 0)
        {
            Widget w = removeChild(index + 1);
            destroy(w);
        }
        if (nextID)
        {
            index = tabIndex(nextID);
            if (index >= 0)
            {
                selectTab(index, true);
            }
        }
    }

    /// Change name of tab by ID
    void renameTab(string ID, dstring name)
    {
        int index = tabIndex(ID);
        if (index >= 0)
        {
            renameTab(index, name);
        }
    }
    /// Change name of tab by index
    void renameTab(int index, dstring name)
    {
        if (auto wt = cast(TabItem)child(index + 1))
            wt.text = name;
    }
    /// Change name and id of tab
    void renameTab(int index, string id, dstring name)
    {
        if (auto wt = cast(TabItem)child(index + 1))
        {
            wt.text = name;
            wt.id = id;
        }
    }

    void updateAccessTime()
    {
        tab(_selectedTabID).maybe.updateAccessTime();
    }

    void selectTab(int index, bool updateAccess)
    {
        if (index < 0 || index >= tabCount)
        {
            Log.e("Tried to access tab out of bounds (index = %d, count = %d)", index, tabCount);
            return;
        }
        if (child(index + 1).compareID(_selectedTabID))
        {
            if (updateAccess)
                updateAccessTime();
            return; // already selected
        }
        string previousSelectedTab = _selectedTabID;
        foreach (i; 1 .. childCount)
        {
            auto item = child(i);
            if (index == i - 1)
            {
                item.setState(State.selected);
                _selectedTabID = item.id;
                if (updateAccess)
                    updateAccessTime();
            }
            else
            {
                item.resetState(State.selected);
            }
        }
        onTabChange(_selectedTabID, previousSelectedTab);
    }

    protected bool handleTabBtnMouse(string id, MouseEvent event)
    {
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            int index = tabIndex(id);
            if (index >= 0)
            {
                selectTab(index, true);
            }
        }
        return true;
    }

    protected bool handleTabBtnWheel(WheelEvent event)
    {
        // select next or previous tab
        const next = wrapAround(tabIndex(_selectedTabID) + event.deltaX + event.deltaY, 0, tabCount - 1);
        selectTab(next, true);
        return true;
    }

    protected bool handleMoreBtnMouse(MouseEvent event)
    {
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            if (handleMorePopupMenu())
                return true;
            onMoreButtonClick(); // FIXME: emit signal every time?
        }
        return false;
    }

    /// Try to invoke popup menu, return true if popup menu is shown
    protected bool handleMorePopupMenu()
    {
        if (auto menu = getMoreButtonPopupMenu())
        {
            window.showPopup(menu, WeakRef!Widget(_moreButton),
                    tabAlignment == Align.top ? PopupAlign.below : PopupAlign.above);
            menu.selectItem(tabIndex(selectedTabID));
            return true;
        }
        return false;
    }

    protected Menu getMoreButtonPopupMenu()
    {
        if (moreButtonPopupMenuBuilder.assigned)
        {
            if (auto menu = moreButtonPopupMenuBuilder(this))
            {
                return menu;
            }
        }

        if (!tabCount)
            return null;

        auto res = new Menu;
        foreach (i; 1 .. childCount)
        {
            // only hidden tabs should appear in the menu
            if (child(i).visibility == Visibility.visible)
                continue;

            (int idx) // separate function because of the loop
            {
                res.addAction(child(idx).text).bind(this, { selectTab(idx - 1, true); });
            }(i);
        }
        return res;
    }

    private Buf!Size itemSizes;
    override protected Boundaries computeBoundaries()
    {
        itemSizes.resize(childCount);

        Boundaries bs;
        // measure 'more' button
        if (enableMoreButton)
        {
            _moreButton.measure();
            bs = _moreButton.boundaries;
            itemSizes[0] = bs.nat;
        }
        // measure tab buttons
        foreach (i; 1 .. childCount)
        {
            Widget tab = child(i);
            tab.visibility = Visibility.visible;
            tab.measure();
            const wbs = tab.boundaries;
            itemSizes[i] = wbs.nat;

            bs.addWidth(wbs);
            bs.maximizeHeight(wbs);
        }
        return bs;
    }

    override protected void arrangeContent()
    {
        const geom = innerBox;
        float spaceForItems = geom.w;
        bool needMoreButton;
        float w = 0;
        foreach (i; 1 .. itemSizes.length)
        {
            w += itemSizes[i].w;
            if (w > geom.w)
            {
                needMoreButton = true;
                // consider size of the 'more' button
                spaceForItems -= itemSizes[0].w;
                break;
            }
        }
        w = 0;
        if (needMoreButton)
        {
            // update visibility
            foreach (item; sortedItems())
            {
                const idx = item[0];
                auto widget = child(idx);
                if (w + itemSizes[idx].w <= spaceForItems)
                    w += itemSizes[idx].w;
                else
                    widget.visibility = Visibility.gone;
            }
        }
        // 'more' button
        if (enableMoreButton && needMoreButton)
        {
            _moreButton.visibility = Visibility.visible;
            Size msz = itemSizes[0];
            _moreButton.layout(alignBox(geom, msz, Align.right | Align.vcenter));
        }
        else
            _moreButton.visibility = Visibility.gone;
        // layout visible items
        float pen = 0;
        foreach (i; 1 .. childCount)
        {
            Widget tab = child(i);
            if (tab.visibility != Visibility.visible)
                continue;

            w = itemSizes[i].w;
            tab.layout(Box(geom.x + pen, geom.y, w, geom.h));
            pen += w;
        }
    }

    override protected void drawContent(Painter pr)
    {
        // draw all items except selected
        int selected = -1;
        for (int i = childCount - 1; i >= 0; i--)
        {
            Widget item = child(i);
            if (item.visibility != Visibility.visible)
                continue;
            if (item.id == _selectedTabID) // skip selected
            {
                selected = i;
                continue;
            }
            item.draw(pr);
        }
        // draw selected item
        if (selected >= 0)
            child(selected).draw(pr);
    }
}

class TabHost : Panel
{
    /// Signal of tab change (e.g. by clicking on tab header)
    Signal!TabChangeHandler onTabChange;

    private TabControl _tabControl;
    private Visibility _hiddenTabsVisibility = Visibility.hidden;

    this(TabControl tabControl = null)
    {
        _tabControl = tabControl;
        if (_tabControl !is null)
            _tabControl.onTabChange ~= &handleTabChange;
    }

    protected void handleTabChange(string newActiveTabID, string previousTabID)
    {
        if (newActiveTabID !is null)
        {
            showChild(newActiveTabID, _hiddenTabsVisibility, true);
        }
        onTabChange(newActiveTabID, previousTabID);
    }

    /// Get tab content widget by id
    Widget tabBody(string id)
    {
        foreach (i; 0 .. childCount)
        {
            if (child(i).compareID(id))
                return child(i);
        }
        return null;
    }

    /// Remove tab
    void removeTab(string id)
    {
        assert(_tabControl !is null, "No TabControl set for TabHost");
        Widget child = removeChild(id);
        destroy(child);
        _tabControl.removeTab(id);
    }

    /// Add new tab by id and label string
    void addTab(Widget widget, dstring label, string iconID = null, bool enableCloseButton = false,
            dstring tooltipText = null)
    {
        assert(_tabControl !is null, "No TabControl set for TabHost");
        assert(widget.id !is null, "ID for tab host page is mandatory");
        assert(childIndex(widget.id) == -1, "duplicate ID for tab host page");
        _tabControl.addTab(widget.id, label, iconID, enableCloseButton, tooltipText);
        initializateTab(widget);
        addChild(widget);
    }

    // handles initial tab selection & hides subsequently added tabs so
    // they don't appear in the same frame
    private void initializateTab(Widget widget)
    {
        if (_tabControl.selectedTabID is null)
        {
            selectTab(_tabControl.tab(0).id, false);
        }
        else
        {
            widget.visibility = Visibility.hidden;
        }
    }

    /// Select tab
    void selectTab(string ID, bool updateAccess)
    {
        int index = _tabControl.tabIndex(ID);
        if (index != -1)
        {
            _tabControl.selectTab(index, updateAccess);
        }
    }
}

class TabWidget : Panel
{
    @property
    {
        inout(TabItem) selectedTab() inout
        {
            return _tabControl.tab(selectedTabID);
        }

        string selectedTabID() const
        {
            return _tabControl._selectedTabID;
        }
    }

    /// Signal of tab change (e.g. by clicking on tab header)
    Signal!TabChangeHandler onTabChange;
    /// Signal on tab close button
    Signal!TabCloseHandler onTabClose;

    this(Align tabAlignment = Align.top)
    {
        _tabControl = new TabControl(tabAlignment);
        _tabControl.onTabChange ~= &onTabChange.emit;
        _tabControl.onTabClose ~= &onTabClose.emit;
        _tabHost = new TabHost(_tabControl);
    }

    /// Add new tab by id and label (raw value)
    void addTab(Widget widget, dstring label, string iconID = null, bool enableCloseButton = false,
            dstring tooltipText = null)
    {
        _tabHost.addTab(widget, label, iconID, enableCloseButton, tooltipText);
    }

    /// Remove tab by id
    void removeTab(string id)
    {
        _tabHost.removeTab(id);
    }

    /// Change name of the tab
    void renameTab(string ID, dstring name)
    {
        _tabControl.renameTab(ID, name);
    }
    /// ditto
    void renameTab(int index, dstring name)
    {
        _tabControl.renameTab(index, name);
    }
    /// ditto
    void renameTab(int index, string id, dstring name)
    {
        _tabControl.renameTab(index, id, name);
    }

    /// Select tab
    void selectTab(string ID, bool updateAccess = true)
    {
        _tabHost.selectTab(ID, updateAccess);
    }
    /// ditto
    void selectTab(int index, bool updateAccess = true)
    {
        _tabControl.selectTab(index, updateAccess);
    }

    /// Get tab content widget by id
    Widget tabBody(string id)
    {
        return _tabHost.tabBody(id);
    }
    /// Get tab content widget by index
    Widget tabBody(int index)
    {
        string id = _tabControl.tab(index).id;
        return _tabHost.tabBody(id);
    }

    /// Returns tab item by index (`null` if index out of range)
    TabItem tab(int index)
    {
        return _tabControl.tab(index);
    }
    /// Returns tab item by id (`null` if not found)
    TabItem tab(string id)
    {
        return _tabControl.tab(id);
    }
    /// Returns tab count
    @property int tabCount() const
    {
        return _tabControl.tabCount;
    }
    /// Get tab index by tab id (-1 if not found)
    int tabIndex(string id)
    {
        return _tabControl.tabIndex(id);
    }

    private bool _tabNavigationInProgress;

    override bool handleKeyEvent(KeyEvent event)
    {
        if (_tabNavigationInProgress)
        {
            if (event.action == KeyAction.keyDown || event.action == KeyAction.keyUp)
            {
                if (event.alteredBy(KeyMods.control))
                {
                    _tabNavigationInProgress = false;
                    _tabControl.updateAccessTime();
                }
            }
        }
        if (event.action == KeyAction.keyDown)
        {
            if (event.key == Key.tab && event.alteredBy(KeyMods.control))
            {
                // support Ctrl+Tab and Ctrl+Shift+Tab for navigation
                _tabNavigationInProgress = true;
                const direction = event.alteredBy(KeyMods.shift) ? -1 : 1;
                const index = _tabControl.getNextItemIndex(direction);
                if (index >= 0)
                    selectTab(index, false);
                return true;
            }
        }
        return super.handleKeyEvent(event);
    }

    /// Focus selected tab body
    void focusSelectedTab()
    {
        if (!visible)
            return;
        Widget w = selectedTabBody;
        if (w)
            w.setFocus();
    }

    /// Get tab content widget by id
    @property Widget selectedTabBody()
    {
        return _tabHost.tabBody(_tabControl._selectedTabID);
    }
}
+/
