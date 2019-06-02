/**
Menu widgets.

MenuItem - menu item container with icon, label, etc.

Menu - vertical popup menu widget

MenuBar - main menu widget

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.menu;

import beamui.widgets.controls;
import beamui.widgets.lists;
import beamui.widgets.popup;
import beamui.widgets.text;
import beamui.widgets.widget;

/// Widget that draws menu item
class MenuItem : WidgetGroup, ActionHolder
{
    @property
    {
        /// Returns item action
        inout(Action) action() inout { return _action; }

        /// Returns true if item is a separator
        bool isSeparator() const
        {
            return _action is null;
        }

        /// Returns true if item has a submenu
        bool hasSubmenu() const
        {
            return _submenu !is null;
        }

        /// Submenu, opening by hover or click on this item
        inout(Menu) submenu() inout { return _submenu; }
        /// ditto
        void submenu(Menu menu)
        {
            _submenu = menu;
            if (_fromMenuBar)
                return;
            // arrow
            if (menu && !_arrow)
            {
                _arrow = new ImageWidget("scrollbar_btn_right");
                _arrow.id = "menu-open";
                _arrow.bindSubItem(this, "open");
                _arrow.state = State.parent;
                addChild(_arrow);
            }
            else if (!menu && _arrow)
            {
                removeChild(_arrow);
                eliminate(_arrow);
            }
        }
    }

    private
    {
        bool _fromMenuBar;
        Menu _submenu;

        Action _action;

        Widget _separator;
        Widget _checkbox;
        ImageWidget _icon;
        ShortLabel _label;
        ShortLabel _shortcut;
        ImageWidget _arrow;
        int _checkboxWidth;
        int _iconWidth;
        int _labelWidth;
        int _shortcutWidth;
        int _arrowWidth;
        int _height;
    }

    this(Action action, bool fromMenuBar = false)
    {
        _fromMenuBar = fromMenuBar;
        if (action is null)
        {
            id = "menu-separator";
            _separator = new Widget;
            _separator.id = "menu-separator";
            _separator.bindSubItem(this, "separator");
            addChild(_separator);
            enabled = false;
        }
        else
        {
            id = "menu-item";
            _action = action;
            action.changed ~= &updateContent;
            action.stateChanged ~= &updateState;
            allowsClick = true;
            allowsHover = true;

            updateContent();
            updateState();
        }
    }

    ~this()
    {
        eliminate(_submenu);
        if (_action)
        {
            _action.changed -= &updateContent;
            _action.stateChanged -= &updateState;
        }
    }

    protected void updateContent()
    {
        // check box
        if (_action.checkable != allowsToggle)
        {
            allowsToggle = _action.checkable;
            if (allowsToggle && !_checkbox)
            {
                _checkbox = new Widget("menu-checkbox");
                _checkbox.state = State.parent;
                addChild(_checkbox);
            }
            else if (!allowsToggle && _checkbox)
            {
                removeChild(_checkbox);
                eliminate(_checkbox);
            }
        }
        if (_checkbox)
            _checkbox.bindSubItem(this, _action.isRadio ? "radio" : "check");
        // icon
        if (auto iconID = _action.iconID)
        {
            if (!_icon)
            {
                _icon = new ImageWidget(iconID);
                _icon.id = "menu-icon";
                _icon.bindSubItem(this, "icon");
                _icon.state = State.parent;
                addChild(_icon);
            }
            else
                _icon.imageID = iconID;
        }
        else if (_icon)
        {
            removeChild(_icon);
            eliminate(_icon);
        }
        // label
        if (!_label)
        {
            _label = new ShortLabel(_action.label);
            _label.id = "menu-label";
            _label.bindSubItem(this, "label");
            _label.state = State.parent;
            addChild(_label);
        }
        else
            _label.text = _action.label;
        // shortcut
        if (auto sc = _action.shortcutText)
        {
            if (!_shortcut)
            {
                _shortcut = new ShortLabel(sc);
                _shortcut.id = "menu-shortcut";
                _shortcut.bindSubItem(this, "shortcut");
                _shortcut.state = State.parent;
                addChild(_shortcut);
            }
            else
                _shortcut.text = sc;
        }
        else if (_shortcut)
        {
            removeChild(_shortcut);
            eliminate(_shortcut);
        }
    }

    protected void updateState()
    {
        enabled = _action.enabled;
        checked = _action.checked;
        visibility = _action.visible ? Visibility.visible : Visibility.gone;
    }

    void measureSubitems(ref int maxHeight, ref int maxCheckBoxWidth, ref int maxLabelWidth,
                         ref int maxIconWidth, ref int maxShortcutWidth, ref int maxMoreBtnWidth)
    {
        if (isSeparator)
            return;

        {
            _label.measure();
            const sz = _label.natSize;
            maxHeight = max(maxHeight, sz.h);
            maxLabelWidth = max(maxLabelWidth, sz.w);
        }
        if (_checkbox)
        {
            _checkbox.measure();
            const sz = _checkbox.natSize;
            maxHeight = max(maxHeight, sz.h);
            maxCheckBoxWidth = max(maxCheckBoxWidth, sz.w);
        }
        if (_icon)
        {
            _icon.measure();
            const sz = _icon.natSize;
            maxHeight = max(maxHeight, sz.h);
            maxIconWidth = max(maxIconWidth, sz.w);
        }
        if (_shortcut)
        {
            _shortcut.measure();
            const sz = _shortcut.natSize;
            maxHeight = max(maxHeight, sz.h);
            maxShortcutWidth = max(maxShortcutWidth, sz.w);
        }
        if (_arrow)
        {
            _arrow.measure();
            const sz = _arrow.natSize;
            maxHeight = max(maxHeight, sz.h);
            maxMoreBtnWidth = max(maxMoreBtnWidth, sz.w);
        }
    }

    void setSubitemSizes(int maxHeight, int maxCheckBoxWidth, int maxLabelWidth,
                         int maxIconWidth, int maxShortcutWidth, int maxMoreBtnWidth)
    {
        _checkboxWidth = maxCheckBoxWidth;
        _iconWidth = maxIconWidth;
        _labelWidth = maxLabelWidth;
        _shortcutWidth = maxShortcutWidth;
        _arrowWidth = maxMoreBtnWidth;
        _height = maxHeight;
    }

    override void onThemeChanged()
    {
        super.onThemeChanged();
        _submenu.maybe.onThemeChanged();
    }

    override void measure()
    {
        Size sz;
        if (isSeparator)
        {
            _separator.measure();
            sz = _separator.natSize;
        }
        else
        {
            if (!_fromMenuBar)
            {
                // for vertical (popup menu)
                sz = Size(_checkboxWidth + _iconWidth + _labelWidth + _shortcutWidth + _arrowWidth,
                          _height);
            }
            else
            {
                // for horizontal (main) menu
                _label.measure();
                sz = _label.natSize;
                _labelWidth = sz.w;
            }
        }
        setBoundaries(Boundaries(sz, sz, Size.none));
    }

    override void layout(Box b)
    {
        if (visibility == Visibility.gone)
            return;

        box = b;
        b = innerBox;

        if (isSeparator)
        {
            _separator.layout(b);
            return;
        }

        b.w = _checkboxWidth;
        _checkbox.maybe.layout(b);
        b.x += b.w;

        b.w = _iconWidth;
        _icon.maybe.layout(b);
        b.x += b.w;

        b.w = _labelWidth;
        _label.layout(b);
        b.x += b.w;

        b.w = _shortcutWidth;
        _shortcut.maybe.layout(b);
        b.x += b.w;

        b.w = _arrowWidth;
        _arrow.maybe.layout(b);
        b.x += b.w;
    }

    override void onDraw(DrawBuf buf)
    {
        super.onDraw(buf);
        drawAllChildren(buf);
    }
}

/// Base class for menus (vertical by default)
class Menu : ListWidget
{
    /// Menu item click signal. Silences `itemClicked` signal from base class
    Signal!(void delegate(MenuItem)) menuItemClicked;
    /// Prepare for opening of submenu, return true if opening is allowed
    Signal!(bool delegate(Menu)) openingSubmenu;

    private
    {
        Menu _parentMenu;
        Menu visualParentMenu;
    }

    this(Menu parentMenu = null, Orientation orient = Orientation.vertical)
    {
        _parentMenu = parentMenu;
        orientation = orient;
        selectOnHover = true;
        sumItemSizes = true;

        ownAdapter = new WidgetListAdapter;
    }

    protected @property bool isMenuBar() const
    {
        return orientation == Orientation.horizontal;
    }

    /// Get menu item by index
    inout(MenuItem) menuItem(int index) inout
    {
        if (adapter && index >= 0)
            return cast(inout(MenuItem))adapter.itemWidget(index);
        else
            return null;
    }

    @property MenuItem selectedMenuItem()
    {
        return menuItem(selectedItemIndex);
    }

    /// Add menu item
    MenuItem add(MenuItem subitem)
    {
        (cast(WidgetListAdapter)adapter).add(subitem);
        subitem.parent = this;
        return subitem;
    }
    /// Add menu item(s) from one or more actions (will return item for last action)
    MenuItem add(Action[] subitemActions...)
    {
        MenuItem res;
        foreach (a; subitemActions)
        {
            res = add(new MenuItem(a, isMenuBar));
        }
        return res;
    }
    /// Convenient function to add menu item by the action arguments
    Action addAction(dstring label, string iconID = null, Key key = Key.none, KeyMods modifiers = KeyMods.none)
    {
        auto a = new Action(label, iconID, key, modifiers);
        add(a);
        return a;
    }
    /// Add several actions as a group - to be radio button items
    Menu addActionGroup(Action[] actions...)
    {
        Action.groupActions(actions);
        foreach (a; actions)
        {
            add(a);
        }
        return this;
    }

    /// Add separator item
    MenuItem addSeparator()
    {
        return add(new MenuItem(cast(Action)null, isMenuBar));
    }

    /// Add an item for submenu, returns an empty submenu
    Menu addSubmenu(dstring label, string iconID = null)
    {
        auto item = add(new Action(label, iconID));
        auto menu = new Menu(this);
        item.submenu = menu;
        return menu;
    }

    /// Find subitem by hotkey character, returns subitem index, -1 if not found
    ptrdiff_t findSubitemByHotkey(dchar ch) const
    {
        import std.uni : toUpper;

        if (!ch)
            return -1;

        ch = toUpper(ch);
        foreach (i; 0 .. itemCount)
        {
            if (menuItem(i)._label.hotkey == ch)
                return i;
        }
        return -1;
    }

    /// Find subitem by hotkey character, returns an item, `null` if not found
    inout(MenuItem) findSubitemByHotkeyRecursive(dchar ch) inout
    {
        import std.uni : toUpper;

        if (!ch)
            return null;

        ch = toUpper(ch);
        // search here
        foreach (i; 0 .. itemCount)
        {
            auto item = menuItem(i);
            if (item._label.hotkey == ch)
                return item;
        }
        // search in submenus
        foreach (i; 0 .. itemCount)
        {
            auto item = menuItem(i);
            if (item.hasSubmenu)
            {
                if (auto res = item.submenu.findSubitemByHotkeyRecursive(ch))
                    return res;
            }
        }
        return null;
    }

    /// Returns popup this menu is located in
    protected @property Popup thisPopup()
    {
        return cast(Popup)parent;
    }

    private ulong _submenuOpenTimer = 0;
    private int _submenuOpenItemIndex = -1;
    private enum MENU_OPEN_DELAY_MS = 200; // TODO: make changeable

    protected void scheduleSubmenuOpening(int itemIndex)
    {
        cancelSubmenuOpening();
        _submenuOpenItemIndex = itemIndex;
        _submenuOpenTimer = setTimer(MENU_OPEN_DELAY_MS,
            delegate() {
                debug (menus)
                    Log.d("Menu: opening submenu by timer");
                openSubmenu(_submenuOpenItemIndex);
                _submenuOpenTimer = 0;
                return false;
            });
    }

    protected void cancelSubmenuOpening()
    {
        if (_submenuOpenTimer)
        {
            cancelTimer(_submenuOpenTimer);
            _submenuOpenTimer = 0;
        }
    }

    private Menu _openedSubmenu;
    private int _openedSubmenuIndex;

    protected void openSubmenu(int itemIndex)
    {
        debug (menus)
            Log.d("Menu: opening submenu ", itemIndex);

        cancelSubmenuOpening();

        auto item = menuItem(itemIndex);
        assert(item && item.hasSubmenu);

        Menu submenu = _openedSubmenu = item.submenu;
        submenu.visualParentMenu = this;
        _openedSubmenuIndex = itemIndex;
        auto popup = window.showPopup(submenu, WeakRef!Widget(item),
                orientation == Orientation.horizontal ? PopupAlign.below : PopupAlign.right);
        popup.ownContent = false;

        if (navigatingUsingKeys)
        {
            debug (menus)
                Log.d("Menu: selecting first item");
            _openedSubmenu.selectItem(0);
        }
    }

    protected void closeSubmenu()
    {
        cancelSubmenuOpening();
        _openedSubmenu.maybe.close();
    }

    /// Close or deactivate (if no popup) this menu and its submenus
    void close()
    {
        debug (menus)
            Log.d("Menu: closing menu");

        if (auto p = thisPopup)
            p.close();
        else
            handleClose();
    }

    override @property Widget parent() const
    {
        return super.parent;
    }
    override @property void parent(Widget p)
    {
        // ok, this menu needs to know whether popup is closed
        // so, when popup sets itself as menu's parent, we add our slot to popupClosed
        // and remove it on menu close
        if (auto popup = cast(Popup)p)
        {
            if (auto prev = thisPopup)
                prev.popupClosed -= &onThisPopupClosed;
            popup.popupClosed ~= &onThisPopupClosed;
        }
        super.parent = p;
    }

    protected void onThisPopupClosed(bool byEvent)
    {
        assert(thisPopup);
        debug (menus)
            Log.d("Menu: closing popup");

        handleClose();
        // remove submenu from the parent
        if (visualParentMenu)
        {
            visualParentMenu._openedSubmenu = null;
            visualParentMenu._openedSubmenuIndex = -1;
        }
        // if clicked outside
        if (byEvent)
        {
            // close the whole menu
            Menu top = visualParentMenu;
            while (top)
            {
                if (top.visualParentMenu)
                    top = top.visualParentMenu;
                else
                {
                    top.close();
                    break;
                }
            }
        }
        visualParentMenu = null;

        thisPopup.popupClosed -= &onThisPopupClosed;
    }

    protected void handleClose()
    {
        closeSubmenu();
        // deselect items
        selectItem(-1);
        setHoverItem(-1);
        // revert focus
        if (_previousFocusedWidget)
        {
            window.setFocus(_previousFocusedWidget);
            _previousFocusedWidget.nullify();
        }
    }

    private WeakRef!Widget _previousFocusedWidget;

    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false)
    {
        if (focused && !_previousFocusedWidget)
        {
            // on activating
            _previousFocusedWidget = visualParentMenu ? WeakRef!Widget(visualParentMenu) : window.focusedWidget;
        }
        super.handleFocusChange(focused);
    }

    override protected void onSelectionChanged(int index, int previouslySelectedItem = -1)
    {
        debug (menus)
            Log.d("Menu: selection changed from ", previouslySelectedItem, " to ", index);

        closeSubmenu();
        if (!navigatingUsingKeys)
        {
            if (auto item = menuItem(index))
            {
                if (item.hasSubmenu)
                {
                    scheduleSubmenuOpening(index);
                }
            }
        }
    }

    override protected void onItemClicked(int index)
    {
        if (auto item = menuItem(index))
        {
            debug (menus)
                Log.d("Menu: item ", index, " clicked ");

            if (item.hasSubmenu)
            {
                if (!_openedSubmenu)
                    openSubmenu(index);
            }
            else
            {
                onMenuItem(item);
            }
        }
    }

    /// Process menu item action in a top level menu
    protected void onMenuItem(MenuItem item)
    {
        if (visualParentMenu)
            // send up
            visualParentMenu.onMenuItem(item);
        else
        {
            if (item.isSeparator)
                // do nothing
                return;

            debug (menus)
                Log.d("Menu: process item ", item.action.label);

            // copy stuff we need
            auto menuItemClickedCopy = menuItemClicked;
            auto w = window;
            auto a = item.action;

            close();

            // call item's action
            if (w)
                w.call(a);

            // `this` pointer now can be invalid - if popup removed
            menuItemClickedCopy(item); // FIXME: `item` can be invalid too
        }
    }

    private bool _navigatingUsingKeys;
    protected @property bool navigatingUsingKeys() const
    {
        if (visualParentMenu)
            return visualParentMenu.navigatingUsingKeys;
        else
            return _navigatingUsingKeys;
    }
    protected @property void navigatingUsingKeys(bool flag)
    {
        if (visualParentMenu)
            visualParentMenu.navigatingUsingKeys = flag;
        else
            _navigatingUsingKeys = flag;
    }

    /// Menu navigation using keys
    override bool onKeyEvent(KeyEvent event)
    {
        navigatingUsingKeys = true;
        if (event.action == KeyAction.keyDown && event.key == Key.escape && event.noModifiers)
        {
            close();
            return true;
        }
        if (orientation == Orientation.horizontal)
        {
            if (selectedItemIndex >= 0 && event.action == KeyAction.keyDown)
            {
                if (event.key == Key.down)
                {
                    onItemClicked(selectedItemIndex);
                    return true;
                }
                if (event.key == Key.up)
                {
                    if (visualParentMenu && visualParentMenu.orientation == Orientation.vertical)
                    {
                        // parent is a popup menu
                        visualParentMenu.moveSelection(-1);
                    }
                    else
                    {
                        // deactivate
                        close();
                    }
                    return true;
                }
            }
        }
        else
        {
            // for vertical (popup) menu
            if (!focused)
                return false;
            if (event.action == KeyAction.keyDown)
            {
                if (event.key == Key.left)
                {
                    if (visualParentMenu)
                    {
                        if (visualParentMenu.orientation == Orientation.vertical)
                        {
                            // back to parent menu on Left key
                            close();
                        }
                        else
                        {
                            // parent is a menu bar
                            visualParentMenu.moveSelection(-1);
                        }
                    }
                    return true;
                }
                if (event.key == Key.right)
                {
                    auto item = selectedMenuItem;
                    if (item && item.hasSubmenu)
                    {
                        if (!_openedSubmenu)
                            openSubmenu(selectedItemIndex);
                    }
                    else if (visualParentMenu && visualParentMenu.orientation == Orientation.horizontal)
                    {
                        visualParentMenu.moveSelection(1);
                    }
                    return true;
                }
            }
            else if (event.action == KeyAction.keyUp)
            {
                if (event.key == Key.left || event.key == Key.right)
                {
                    return true;
                }
            }
            else if (event.action == KeyAction.text && event.noModifiers)
            {
                dchar ch = event.text[0];
                int index = cast(int)findSubitemByHotkey(ch);
                if (index >= 0)
                {
                    onItemClicked(index);
                    return true;
                }
            }
        }
        return super.onKeyEvent(event);
    }

    override bool onMouseEvent(MouseEvent event)
    {
        navigatingUsingKeys = false;
        return super.onMouseEvent(event);
    }

    override void measure()
    {
        // align items for vertical menu
        if (orientation == Orientation.vertical)
        {
            int maxHeight;
            int maxCheckBoxWidth;
            int maxLabelWidth;
            int maxIconWidth;
            int maxShortcutWidth;
            int maxMoreBtnWidth;
            // find max dimensions for item subwidgets
            foreach (i; 0 .. itemCount)
            {
                menuItem(i).maybe.measureSubitems(maxHeight,
                    maxCheckBoxWidth, maxLabelWidth, maxIconWidth, maxShortcutWidth, maxMoreBtnWidth);
            }
            // set equal dimensions for item subwidgets
            foreach (i; 0 .. itemCount)
            {
                menuItem(i).maybe.setSubitemSizes(maxHeight,
                    maxCheckBoxWidth, maxLabelWidth, maxIconWidth, maxShortcutWidth, maxMoreBtnWidth);
            }
        }
        super.measure();
    }
}

/// Menu bar (like main menu)
class MenuBar : Menu
{
    override @property bool wantsKeyTracking() const
    {
        return true;
    }

    this()
    {
        super(null, Orientation.horizontal);
        selectOnHover = false;
    }

    override protected void handleClose()
    {
        selectOnHover = false;
        super.handleClose();
    }

    override protected void onSelectionChanged(int index, int previouslySelectedItem = -1)
    {
        debug (menus)
            Log.d("MenuBar: selection changed from ", previouslySelectedItem, " to ", index);

        if (auto item = menuItem(index))
        {
            if (item.hasSubmenu)
            {
                closeSubmenu();
                selectOnHover = true;
                openSubmenu(index);
            }
        }
    }

    override protected void onItemClicked(int index)
    {
        if (!navigatingUsingKeys) // open submenu here by enter/space/down keys only
            return;

        if (auto item = menuItem(index))
        {
            debug (menus)
                Log.d("MenuBar: item `", item.action.label, "` clicked");

            if (item.hasSubmenu)
            {
                if (!_openedSubmenu)
                    openSubmenu(index);
            }
            else
            {
                onMenuItem(item);
            }
        }
    }

    private bool _menuToggleState;

    override bool onKeyEvent(KeyEvent event)
    {
        // handle Alt key
        const bool altPressed = event.alteredBy(KeyMods.alt);
        const bool noOtherModifiers = !event.alteredBy(KeyMods.shift | KeyMods.control);
        const bool noAltGrKey = !event.alteredBy(KeyMods.ralt);

        dchar hotkey = 0;
        if (altPressed && noOtherModifiers && noAltGrKey)
        {
            if (event.action == KeyAction.keyDown && Key.A <= event.key && event.key <= Key.Z)
                hotkey = cast(dchar)((event.key - Key.A) + 'a');
            else if (event.action == KeyAction.text)
                hotkey = event.text[0];
        }
        if (hotkey)
        {
            int index = cast(int)findSubitemByHotkey(hotkey); // TODO: doesn't work with non-latin keys
            if (index >= 0)
            {
                int prevIndex = selectedItemIndex;
                if (index != prevIndex)
                {
                    selectItem(index);
                    onSelectionChanged(index, prevIndex);
                    onItemClicked(index);
                }
                return true;
            }
            else
            {
                if (auto item = findSubitemByHotkeyRecursive(hotkey))
                {
                    debug (menus)
                        Log.d("found menu item recursive");
                    onMenuItem(item);
                    return true;
                }
                return false;
            }
        }

        // toggle menu by single Alt press - for Windows only!
        version (Windows)
        {
            const isAlt = event.key == Key.alt  || event.key == Key.lalt || event.key == Key.ralt;
            bool toggleMenu;
            if (event.action == KeyAction.keyDown && isAlt && noOtherModifiers)
            {
                _menuToggleState = true;
            }
            else if (event.action == KeyAction.keyUp && isAlt && noOtherModifiers)
            {
                if (_menuToggleState)
                    toggleMenu = true;
                _menuToggleState = false;
            }
            else
            {
                _menuToggleState = false;
            }
            if (toggleMenu)
            {
                // if activated - deactivate
                if (focused || selectedItemIndex >= 0 || _openedSubmenu !is null)
                {
                    close();
                }
                else
                {
                    window.setFocus(WeakRef!Widget(this));
                    selectItem(0);
                }
                return true;
            }
        }
        return super.onKeyEvent(event);
    }
}
