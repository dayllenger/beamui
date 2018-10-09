/**
This module contains declaration of tabbed view controls.

Mostly you will use only TabWidget class. Other classes are ancillary.

Synopsis:
---
import beamui.widgets.tabs;

// create tab widget
auto tabs = new TabWidget;
// and add tabs
// content widgets must have different non-null ids
tabs.addTab(new Label("1st tab content"d).id("tab1"), "Tab 1");
tabs.addTab(new Label("2st tab content"d).id("tab2"), "Tab 2");
// tab widget consists of two parts: tabControl and tabHost
tabs.tabHost.padding = 12;
tabs.tabHost.backgroundColor = 0xbbbbbb;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.widgets.tabs;

import beamui.widgets.controls;
import beamui.widgets.layouts;
import beamui.widgets.menu;
import beamui.widgets.popup;

/// Current tab is changed handler
alias tabChangedHandler = void delegate(string newActiveTabID, string previousTabID);
/// Tab close button pressed handler
alias tabClosedHandler = void delegate(string tabID);

/// Tab item metadata
class TabItem
{
    @property
    {
        string iconID() const
        {
            return _iconRes;
        }

        string id() const
        {
            return _id;
        }

        dstring text() const
        {
            return _label;
        }

        void text(dstring s)
        {
            _label = s;
        }

        TabItem iconID(string id)
        {
            _iconRes = id;
            return this;
        }

        TabItem id(string id)
        {
            _id = id;
            return this;
        }

        long lastAccessTs() const
        {
            return _lastAccessTs;
        }

        void lastAccessTs(long ts)
        {
            _lastAccessTs = ts;
        }

        /// Tooltip text
        dstring tooltipText() const
        {
            return _tooltipText;
        }
        /// Tooltip text
        void tooltipText(dstring text)
        {
            _tooltipText = text;
        }

        Object objectParam()
        {
            return _objectParam;
        }

        TabItem objectParam(Object value)
        {
            _objectParam = value;
            return this;
        }

        int intParam() const
        {
            return _intParam;
        }

        TabItem intParam(int value)
        {
            _intParam = value;
            return this;
        }
    }

    protected
    {
        static __gshared long _lastAccessCounter;
        string _iconRes;
        string _id;
        dstring _label;
        dstring _tooltipText;
        long _lastAccessTs;

        Object _objectParam;
        int _intParam;
    }

    this(string id, dstring labelText, string iconRes = null, dstring tooltipText = null)
    {
        _id = id;
        _label = labelText;
        _iconRes = iconRes;
        _lastAccessTs = _lastAccessCounter++;
        _tooltipText = tooltipText;
    }

    void updateAccessTs()
    {
        _lastAccessTs = _lastAccessCounter++;
    }
}

/// Tab item widget - to show tab header
class TabItemWidget : Row
{
    @property
    {
        TabItem tabItem()
        {
            return _item;
        }

        TabControl tabControl()
        {
            return cast(TabControl)parent;
        }

        override dstring tooltipText()
        {
            return _item.tooltipText;
        }

        override Widget tooltipText(dstring text)
        {
            bunch(_icon, _label, _closeButton, _item).tooltipText(text);
            return this;
        }

        TabItem item()
        {
            return _item;
        }
    }

    Signal!tabClosedHandler tabClosed;

    protected
    {
        ImageWidget _icon;
        Label _label;
        Button _closeButton;
        TabItem _item;
        bool _enableCloseButton;
    }

    this(TabItem item, bool enableCloseButton = true)
    {
        styleID = "TabUpButton";
        spacing = 0;
        _enableCloseButton = enableCloseButton;
        _icon = new ImageWidget;
        _label = new Label;
        _label.bindSubItem(this, "label");
        _label.state = State.parent;
        _closeButton = new Button(null, "close");
        _closeButton.id = "CLOSE";
        _closeButton.bindSubItem(this, "close"); // FIXME: was Button.transparent
        _closeButton.clicked = (Widget w) { tabClosed(_item.id); return true; };
        _closeButton.visibility = _enableCloseButton ? Visibility.visible : Visibility.gone;
        addChild(_icon);
        addChild(_label);
        addChild(_closeButton);
        setItem(item);
        clickable = true;
        trackHover = true;
        _label.trackHover = true;
        bunch(_icon, _label, _closeButton).tooltipText(_item.tooltipText); // FIXME: needed?
    }

    void setItem(TabItem item)
    {
        _item = item;
        if (item.iconID !is null)
        {
            _icon.visibility = Visibility.visible;
            _icon.imageID = item.iconID;
        }
        else
        {
            _icon.visibility = Visibility.gone;
        }
        _label.text = item.text;
        id = item.id;
    }

    void setStyles(string tabButtonStyle, string tabButtonTextStyle)
    {
        styleID = tabButtonStyle;
        _label.styleID = tabButtonTextStyle;
    }
}

/// Tab header - tab labels, with optional More button
class TabControl : WidgetGroupDefaultDrawing
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

        string selectedTabID() const
        {
            return _selectedTabID;
        }
    }

    /// Signal of tab change (e.g. by clicking on tab header)
    Signal!tabChangedHandler tabChanged;
    /// Signal on tab close button
    Signal!tabClosedHandler tabClosed;
    /// On more button click
    Signal!(void delegate(Widget)) moreButtonClicked;
    /// Handler for more button popup menu
    Signal!(Menu delegate(Widget)) moreButtonPopupMenuBuilder;

    /// When true, shows close buttons in tabs
    bool enableCloseButton;
    /// When true, more button is visible
    bool enableMoreButton = true;

    Align tabAlignment;

    import std.typecons : Tuple, tuple;

    protected
    {
        TabItem[] _items;
        Button _moreButton;
        Tuple!(TabItem, size_t)[] _sortedItems;

        string _tabStyle;
        string _tabButtonStyle;
        string _tabButtonTextStyle;

        string _selectedTabID;
    }

    this(Align tabAlign = Align.top)
    {
        super(null);
        tabAlignment = tabAlign;
        setStyles("TabUp", "TabUpButton", "TabUpButtonText");
        _moreButton = new Button(null, "tab_more");
        _moreButton.id = "MORE";
        _moreButton.bindSubItem(this, "more");
        _moreButton.mouseEvent = &onMouseMoreBtn;
        enableCloseButton = true;
        styleID = _tabStyle;
        addChild(_moreButton); // first child is always MORE button, the rest corresponds to tab list
    }

    void setStyles(string tabStyle, string tabButtonStyle, string tabButtonTextStyle)
    {
        _tabStyle = tabStyle;
        _tabButtonStyle = tabButtonStyle;
        _tabButtonTextStyle = tabButtonTextStyle;
        styleID = _tabStyle;
        foreach (i; 1 .. childCount)
        {
            TabItemWidget w = cast(TabItemWidget)child(i);
            if (w)
            {
                w.setStyles(_tabButtonStyle, _tabButtonTextStyle);
            }
        }
    }

    /// Returns tab count
    @property int tabCount() const
    {
        return cast(int)_items.length;
    }
    /// Returns tab item by index (null if index is out of range)
    TabItem tab(int index)
    {
        if (index < tabCount)
            return _items[index];
        else
            return null;
    }
    /// Returns tab item by id (null if not found)
    inout(TabItem) tab(string id) inout
    {
        foreach (item; _items)
            if (item.id == id)
                return item;
        return null;
    }
    /// Get tab index by tab id (-1 if not found)
    int tabIndex(string id)
    {
        foreach (i, item; _items)
            if (item.id == id)
                return cast(int)i;
        return -1;
    }

    protected void updateTabs()
    {
        // TODO:
    }

    protected Tuple!(TabItem, size_t)[] sortedItems()
    {
        _sortedItems.length = _items.length;
        foreach (i, it; _items)
        {
            _sortedItems[i][0] = it;
            _sortedItems[i][1] = i;
        }
        _sortedItems.sort!((a, b) => a[0].lastAccessTs > b[0].lastAccessTs);
        return _sortedItems;
    }

    /// Find next or previous tab index, based on access time
    int getNextItemIndex(int direction)
    {
        if (_items.length == 0)
            return -1;
        if (_items.length == 1)
            return 0;
        auto items = sortedItems();
        foreach (i; 0 .. items.length)
        {
            if (items[i][0].id == _selectedTabID)
            {
                size_t next = i + direction;
                if (next < 0)
                    next = items.length - 1;
                if (next >= items.length)
                    next = 0;
                return tabIndex(items[next][0].id);
            }
        }
        return -1;
    }

    /// Add new tab
    TabControl addTab(TabItem item, int index = -1, bool enableCloseButton = false)
    {
        import std.array : insertInPlace;

        if (index != -1)
            _items.insertInPlace(index, item);
        else
            _items ~= item;
        auto widget = new TabItemWidget(item, enableCloseButton);
        widget.parent = this;
        widget.mouseEvent = &onMouseTabBtn;
        widget.setStyles(_tabButtonStyle, _tabButtonTextStyle);
        widget.tabClosed = &onTabClose;
        insertChild(widget, index);
        updateTabs();
        requestLayout();
        return this;
    }
    /// Add new tab by id and label string
    TabControl addTab(string id, dstring label, string iconID = null, bool enableCloseButton = false,
            dstring tooltipText = null)
    {
        TabItem item = new TabItem(id, label, iconID, tooltipText);
        return addTab(item, -1, enableCloseButton);
    }

    /// Remove tab
    TabControl removeTab(string id)
    {
        string nextID;
        if (id == _selectedTabID)
        {
            // current tab is being closed: remember next tab id
            int nextIndex = getNextItemIndex(1);
            if (nextIndex < 0)
                nextIndex = getNextItemIndex(-1);
            if (nextIndex >= 0)
                nextID = _items[nextIndex].id;
        }
        int index = tabIndex(id);
        if (index >= 0)
        {
            Widget w = removeChild(index + 1);
            if (w)
                destroy(w);
            _items = _items.remove(index);
            if (id == _selectedTabID)
                _selectedTabID = null;
            requestLayout();
        }
        if (nextID)
        {
            index = tabIndex(nextID);
            if (index >= 0)
            {
                selectTab(index, true);
            }
        }
        return this;
    }

    /// Change name of tab
    void renameTab(string ID, dstring name)
    {
        int index = tabIndex(id);
        if (index >= 0)
        {
            renameTab(index, name);
        }
    }

    /// Change name of tab
    void renameTab(int index, dstring name)
    {
        _items[index].text = name;
        foreach (i; 0 .. childCount)
        {
            auto widget = cast(TabItemWidget)child(i);
            if (widget && widget.item is _items[index])
            {
                widget.setItem(_items[index]);
                requestLayout();
                break;
            }
        }
    }

    /// Change name and id of tab
    void renameTab(int index, string id, dstring name)
    {
        _items[index].text = name;
        _items[index].id = id;
        foreach (i; 0 .. childCount)
        {
            auto widget = cast(TabItemWidget)child(i);
            if (widget && widget.item is _items[index])
            {
                widget.setItem(_items[index]);
                requestLayout();
                break;
            }
        }
    }

    protected void onTabClose(string tabID)
    {
        tabClosed(tabID);
    }

    void updateAccessTs()
    {
        tab(_selectedTabID).maybe.updateAccessTs();
    }

    void selectTab(int index, bool updateAccess)
    {
        if (index < 0 || index + 1 >= childCount)
        {
            Log.e("Tried to access tab out of bounds (index = %d, count = %d)", index, childCount - 1);
            return;
        }
        if (child(index + 1).compareID(_selectedTabID))
        {
            if (updateAccess)
                updateAccessTs();
            return; // already selected
        }
        string previousSelectedTab = _selectedTabID;
        foreach (i; 1 .. childCount)
        {
            if (index == i - 1)
            {
                child(i).state = State.selected;
                _selectedTabID = child(i).id;
                if (updateAccess)
                    updateAccessTs();
            }
            else
            {
                child(i).state = State.normal;
            }
        }
        tabChanged(_selectedTabID, previousSelectedTab);
    }

    protected bool onMouseTabBtn(Widget source, MouseEvent event)
    {
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            string id = source.id;
            int index = tabIndex(id);
            if (index >= 0)
            {
                selectTab(index, true);
            }
        }
        return true;
    }

    protected bool onMouseMoreBtn(Widget source, MouseEvent event)
    {
        if (event.action == MouseAction.buttonDown && event.button == MouseButton.left)
        {
            if (handleMorePopupMenu())
                return true;
            moreButtonClicked(this); // FIXME: emit signal every time?
        }
        return false;
    }

    /// Try to invoke popup menu, return true if popup menu is shown
    protected bool handleMorePopupMenu()
    {
        if (auto menu = getMoreButtonPopupMenu())
        {
            auto popup = window.showPopup(menu, WeakRef!Widget(_moreButton),
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
                res.addAction(_items[idx].text).bind(this, { selectTab(idx, true); });
            }(i - 1);
        }
        return res;
    }

    Size[] itemSizes;
    override Boundaries computeBoundaries()
    {
        if (itemSizes.length < childCount)
            itemSizes.length = childCount;

        Boundaries bs;
        // measure 'more' button
        if (enableMoreButton)
        {
            bs = _moreButton.computeBoundaries();
            itemSizes[0] = bs.nat;
        }
        // measure tab buttons
        foreach (i; 1 .. childCount)
        {
            Widget tab = child(i);
            tab.visibility = Visibility.visible;
            Boundaries wbs = tab.computeBoundaries();
            itemSizes[i] = wbs.nat;

            bs.addWidth(wbs);
            bs.maximizeHeight(wbs);
        }

        applyStyle(bs);
        return bs;
    }

    override void layout(Box geom)
    {
        _needLayout = false;
        if (visibility == Visibility.gone)
            return;

        _box = geom;
        applyPadding(geom);

        // consider more button space if it is enabled
        if (enableMoreButton)
            geom.w -= itemSizes[0].w;

        // tabs
        // update visibility
        bool needMoreButton;
        int w = 0;
        foreach (item; sortedItems())
        {
            size_t idx = item[1] + 1;
            auto widget = child(cast(int)idx);
            if (w + itemSizes[idx].w <= geom.w)
            {
                w += itemSizes[idx].w;
                widget.visibility = Visibility.visible;
            }
            else
            {
                widget.visibility = Visibility.gone;
                needMoreButton = true;
            }
        }
        // more button
        if (enableMoreButton && needMoreButton)
        {
            _moreButton.visibility = Visibility.visible;
            Size msz = itemSizes[0];
            _moreButton.layout(Box(geom.x + geom.w, geom.y + (geom.h - msz.h) / 2, // TODO: generalize?
                                   msz.w, geom.h));
        }
        else
        {
            _moreButton.visibility = Visibility.gone;
        }
        // layout visible items
        int pen;
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

    override void onDraw(DrawBuf buf)
    {
        if (visibility != Visibility.visible)
            return;

        super.Widget.onDraw(buf);
        Box b = _box;
        applyMargins(b);
        applyPadding(b);
        auto saver = ClipRectSaver(buf, b);
        // draw all items except selected
        for (int i = childCount - 1; i >= 0; i--)
        {
            Widget item = child(i);
            if (item.visibility != Visibility.visible)
                continue;
            if (item.id == _selectedTabID) // skip selected
                continue;
            item.onDraw(buf);
        }
        // draw selected item
        for (int i = 0; i < childCount; i++)
        {
            Widget item = child(i);
            if (item.visibility != Visibility.visible)
                continue;
            if (item.id != _selectedTabID) // skip all except selected
                continue;
            item.onDraw(buf);
        }
    }
}

/// Container for widgets controlled by TabControl
class TabHost : FrameLayout
{
    @property
    {
        /// Get currently set control widget
        TabControl tabControl()
        {
            return _tabControl;
        }
        /// Set new control widget
        TabHost tabControl(TabControl newWidget)
        {
            _tabControl = newWidget;
            if (_tabControl !is null)
                _tabControl.tabChanged ~= &onTabChanged;
            return this;
        }

        Visibility hiddenTabsVisibility()
        {
            return _hiddenTabsVisibility;
        }

        void hiddenTabsVisibility(Visibility v)
        {
            _hiddenTabsVisibility = v;
        }
    }

    /// Signal of tab change (e.g. by clicking on tab header)
    Signal!tabChangedHandler tabChanged;

    protected TabControl _tabControl;
    protected Visibility _hiddenTabsVisibility = Visibility.invisible;

    this(TabControl tabControl = null)
    {
        _tabControl = tabControl;
        if (_tabControl !is null)
            _tabControl.tabChanged ~= &onTabChanged;
    }

    protected void onTabChanged(string newActiveTabID, string previousTabID)
    {
        if (newActiveTabID !is null)
        {
            showChild(newActiveTabID, _hiddenTabsVisibility, true);
        }
        tabChanged(newActiveTabID, previousTabID);
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
    TabHost removeTab(string id)
    {
        assert(_tabControl !is null, "No TabControl set for TabHost");
        Widget child = removeChild(id);
        eliminate(child);
        _tabControl.removeTab(id);
        requestLayout();
        return this;
    }

    /// Add new tab by id and label string
    TabHost addTab(Widget widget, dstring label, string iconID = null, bool enableCloseButton = false,
            dstring tooltipText = null)
    {
        assert(_tabControl !is null, "No TabControl set for TabHost");
        assert(widget.id !is null, "ID for tab host page is mandatory");
        assert(childIndex(widget.id) == -1, "duplicate ID for tab host page");
        _tabControl.addTab(widget.id, label, iconID, enableCloseButton, tooltipText);
        tabInitialization(widget);
        //widget.focusGroup = true; // doesn't allow move focus outside of tab content
        addChild(widget);
        return this;
    }

    // handles initial tab selection & hides subsequently added tabs so
    // they don't appear in the same frame
    private void tabInitialization(Widget widget)
    {
        if (_tabControl.selectedTabID is null)
        {
            selectTab(_tabControl.tab(0).id, false);
        }
        else
        {
            widget.visibility = Visibility.invisible;
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

/// Compound widget - contains from TabControl widget (tabs header) and TabHost (content pages)
class TabWidget : Column
{
    @property
    {
        TabControl tabControl()
        {
            return _tabControl;
        }

        TabHost tabHost()
        {
            return _tabHost;
        }

        Visibility hiddenTabsVisibility()
        {
            return _tabHost.hiddenTabsVisibility;
        }

        void hiddenTabsVisibility(Visibility v)
        {
            _tabHost.hiddenTabsVisibility = v;
        }

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
    Signal!tabChangedHandler tabChanged;
    /// Signal on tab close button
    Signal!tabClosedHandler tabClosed;

    protected TabControl _tabControl;
    protected TabHost _tabHost;

    /// Construct a new tab widget with top or bottom tab control placement
    this(Align tabAlignment = Align.top)
    {
        spacing = 0;
        _tabControl = new TabControl(tabAlignment);
        _tabControl.tabChanged ~= &onTabChanged;
        _tabControl.tabClosed ~= &onTabClose;
        _tabHost = new TabHost(_tabControl);
        _tabHost.fillH();
        if (tabAlignment == Align.top)
        {
            addChild(_tabControl);
            addChild(_tabHost);
        }
        else
        {
            addChild(_tabHost);
            addChild(_tabControl);
        }
        focusGroup = true;
    }

    protected void onTabChanged(string newActiveTabID, string previousTabID)
    {
        // forward to listener
        tabChanged(newActiveTabID, previousTabID);
    }

    protected void onTabClose(string tabID)
    {
        tabClosed(tabID);
    }

    /// Add new tab by id and label (raw value)
    TabWidget addTab(Widget widget, dstring label, string iconID = null, bool enableCloseButton = false,
            dstring tooltipText = null)
    {
        _tabHost.addTab(widget, label, iconID, enableCloseButton, tooltipText);
        return this;
    }

    /// Remove tab by id
    TabWidget removeTab(string id)
    {
        _tabHost.removeTab(id);
        requestLayout();
        return this;
    }

    /// Change name of tab
    void renameTab(string ID, dstring name)
    {
        _tabControl.renameTab(ID, name);
    }

    /// Change name of tab
    void renameTab(int index, dstring name)
    {
        _tabControl.renameTab(index, name);
    }

    /// Change name of tab
    void renameTab(int index, string id, dstring name)
    {
        _tabControl.renameTab(index, id, name);
    }

    /// Select tab
    void selectTab(string ID, bool updateAccess = true)
    {
        _tabHost.selectTab(ID, updateAccess);
    }

    /// Select tab
    void selectTab(int index, bool updateAccess = true)
    {
        _tabControl.selectTab(index, updateAccess);
    }

    /// Get tab content widget by id
    Widget tabBody(string id)
    {
        return _tabHost.tabBody(id);
    }

    /// Get tab content widget by id
    Widget tabBody(int index)
    {
        string id = _tabControl.tab(index).id;
        return _tabHost.tabBody(id);
    }

    /// Returns tab item by id (null if index out of range)
    TabItem tab(int index)
    {
        return _tabControl.tab(index);
    }
    /// Returns tab item by id (null if not found)
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

    /// Change style ids
    void setStyles(string tabWidgetStyle, string tabStyle, string tabButtonStyle,
            string tabButtonTextStyle, string tabHostStyle = null)
    {
        styleID = tabWidgetStyle;
        _tabControl.setStyles(tabStyle, tabButtonStyle, tabButtonTextStyle);
        _tabHost.styleID = tabHostStyle;
    }

    private bool _tabNavigationInProgress;

    override bool onKeyEvent(KeyEvent event)
    {
        if (_tabNavigationInProgress)
        {
            if (event.action == KeyAction.keyDown || event.action == KeyAction.keyUp)
            {
                if (!(event.flags & KeyFlag.control))
                {
                    _tabNavigationInProgress = false;
                    _tabControl.updateAccessTs();
                }
            }
        }
        if (event.action == KeyAction.keyDown)
        {
            if (event.keyCode == KeyCode.tab && (event.flags & KeyFlag.control))
            {
                // support Ctrl+Tab and Ctrl+Shift+Tab for navigation
                _tabNavigationInProgress = true;
                int direction = (event.flags & KeyFlag.shift) ? -1 : 1;
                int index = _tabControl.getNextItemIndex(direction);
                if (index >= 0)
                    selectTab(index, false);
                return true;
            }
        }
        return super.onKeyEvent(event);
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
