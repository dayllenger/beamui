/**
Menu widgets.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.menu;

import beamui.events.action : Action;
import beamui.widgets.controls : ImageWidget, ElemImage;
import beamui.widgets.lists : ListView, ElemListView;
// import beamui.widgets.popup;
import beamui.widgets.text;
import beamui.widgets.widget;

/** Widget that draws menu item with icon, label, etc.

    CSS_nodes:
    ---
    MenuItem
    ├── Widget?.(radio|check)
    ├── ImageWidget?.icon
    ├── Label.label
    ╰── Label?.shortcut
    ---
    ---
    MenuItem.separator
    ╰── Widget
    ---
*/
class MenuItem : Widget
{
    /// Item action
    Action action;

    private
    {
        Widget _separator;
        Widget _checkbox;
        ImageWidget _icon;
        Label _label;
        Label _shortcut;
    }

    override protected void build()
    {
        if (!action)
        {
            attributes["separator"];
            enabled = false;
            _separator = render!Widget;
            _separator.namespace = null;
            return;
        }
        enabled = action.enabled;
        visible = action.visible;
        // check box or radio button
        if (action.checkable)
        {
            _checkbox = render!Widget;
            _checkbox.attributes[action.isRadio ? "radio" : "check"];
            _checkbox.namespace = null;
        }
        // icon
        if (auto iconID = action.iconID)
        {
            _icon = render!ImageWidget;
            _icon.attributes["icon"];
            _icon.namespace = null;
            _icon.imageID = iconID;
        }
        // label
        _label = render!Label;
        _label.attributes["label"];
        _label.namespace = null;
        _label.text = action.label;
        // shortcut
        if (auto sc = action.shortcutText)
        {
            _shortcut = render!Label;
            _shortcut.attributes["shortcut"];
            _shortcut.namespace = null;
            _shortcut.text = sc;
        }
    }

    override protected Element createElement()
    {
        return new ElemMenuItem;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemMenuItem el = fastCast!ElemMenuItem(element);
        el._horizontal = cast(MenuBar)parent !is null;

        if (!_separator)
        {
            el.applyFlags(StateFlags.checked, action.checked);
            el._separator = null;
            el._checkbox = mountChild(_checkbox, 1);
            el._icon = mountChild(_icon, 2);
            el._label = fastCast!ElemLabel(mountChild(_label, 3));
            el._shortcut = mountChild(_shortcut, 4);
        }
        else
        {
            el.applyFlags(StateFlags.checked, false);
            el._separator = mountChild(_separator, 0);
            el._checkbox = null;
            el._icon = null;
            el._label = null;
            el._shortcut = null;
        }
    }
}

/// Menu widget (vertical by default)
class Menu : ListView
{
    private MenuItem[] _items;

    this()
    {
        selectOnHover = true;
        itemBuilder = &getItem;
    }

    /// Create an item, specific for this types of menu. Null action creates a separator
    MenuItem item(Action action)
    {
        auto item = render!MenuItem;
        item.action = action;
        return item;
    }

    /// Set menu items
    final Menu wrap(MenuItem[] items...)
    {
        if (items.length == 0)
            return this;

        _items = arena.allocArray!MenuItem(items.length);
        _items[] = items[];
        itemCount = cast(int)_items.length;
        return this;
    }

    private MenuItem getItem(int i)
    {
        return _items[i];
    }

    override protected Element createElement()
    {
        return new ElemMenu;
    }

    override protected void updateElement(Element element)
    {
        super.updateElement(element);

        ElemMenu el = fastCast!ElemMenu(element);
    }
}

/// Menu bar (like main menu)
class MenuBar : Menu
{
    this()
    {
        orientation = Orientation.horizontal;
        selectOnHover = false;
    }
}

class ElemMenuItem : ElemGroup
{
    @property
    {
        /// Returns true if item is a separator
        bool isSeparator() const
        {
            return _separator !is null;
        }
    }

    private
    {
        bool _horizontal;

        Element _separator;
        Element _checkbox;
        Element _icon;
        ElemLabel _label;
        Element _shortcut;
        Element _arrow;
        float _checkboxWidth = 0;
        float _iconWidth = 0;
        float _labelWidth = 0;
        float _shortcutWidth = 0;
        float _arrowWidth = 0;
        float _height = 0;
    }

    void measureSubitems(ref float maxHeight, ref float maxCheckBoxWidth, ref float maxLabelWidth,
                         ref float maxIconWidth, ref float maxShortcutWidth, ref float maxMoreBtnWidth)
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

    void setSubitemSizes(float maxHeight, float maxCheckBoxWidth, float maxLabelWidth,
                         float maxIconWidth, float maxShortcutWidth, float maxMoreBtnWidth)
    {
        _checkboxWidth = maxCheckBoxWidth;
        _iconWidth = maxIconWidth;
        _labelWidth = maxLabelWidth;
        _shortcutWidth = maxShortcutWidth;
        _arrowWidth = maxMoreBtnWidth;
        _height = maxHeight;
    }

    override protected Boundaries computeBoundaries()
    {
        Size sz;
        if (isSeparator)
        {
            _separator.measure();
            sz = _separator.natSize;
        }
        else
        {
            if (!_horizontal)
            {
                // for vertical (popup menu)
                sz = Size(_checkboxWidth + _iconWidth + _labelWidth + _shortcutWidth + _arrowWidth, _height);
            }
            else
            {
                // for horizontal (main) menu
                _label.measure();
                sz = _label.natSize;
                _labelWidth = sz.w;
            }
        }
        return Boundaries(sz);
    }

    override protected void arrangeContent()
    {
        Box b = innerBox;

        if (isSeparator)
        {
            _separator.layout(b);
            return;
        }

        b.w = _checkboxWidth;
        if (_checkbox)
            _checkbox.layout(b);
        b.x += b.w;

        b.w = _iconWidth;
        if (_icon)
            _icon.layout(b);
        b.x += b.w;

        b.w = _labelWidth;
        _label.layout(b);
        b.x += b.w;

        b.w = _shortcutWidth;
        if (_shortcut)
            _shortcut.layout(b);
        b.x += b.w;

        b.w = _arrowWidth;
        if (_arrow)
            _arrow.layout(b);
        b.x += b.w;
    }

    override protected void drawContent(Painter pr)
    {
        drawAllChildren(pr);
    }
}
/+
class MenuItem : WidgetGroup, ActionHolder
{
    @property
    {
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
                _arrow.setAttribute("open");
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
        Menu _submenu;
    }

    ~this()
    {
        eliminate(_submenu);
    }

    override void handleThemeChange()
    {
        super.handleThemeChange();
        _submenu.maybe.handleThemeChange();
    }
}
+/
class ElemMenu : ElemListView
{
/+
    /// Menu item click signal. Silences `onItemClick` signal from base class
    Signal!(void delegate(MenuItem)) onMenuItemClick;
    /// Prepare for opening of submenu, return true if opening is allowed
    Signal!(bool delegate(Menu)) openingSubmenu; // FIXME

    private
    {
        Menu _parentMenu;
        Menu _visualParentMenu;
    }

    this(Menu parentMenu = null)
    {
        _parentMenu = parentMenu;
    }
+/
    this()
    {
        sumItemSizes = true;
    }

    protected @property bool isMenuBar() const
    {
        return orientation == Orientation.horizontal;
    }

    /// Get menu item by index
    inout(ElemMenuItem) menuItem(int index) inout
    {
        return cast(inout(ElemMenuItem))itemElement(index);
    }

    @property inout(ElemMenuItem) selectedMenuItem() inout
    {
        return menuItem(selectedItemIndex);
    }
/+
    /// Add an item for submenu, returns an empty submenu
    Menu addSubmenu(dstring label, string iconID = null)
    {
        auto item = add(new Action(label, iconID));
        auto menu = new Menu(this);
        item.submenu = menu;
        return menu;
    }
+/
    /// Find subitem by hotkey character, returns subitem index, -1 if not found
    ptrdiff_t findSubitemByHotkey(dchar ch) const
    {
        import std.uni : toUpper;

        if (!ch)
            return -1;

        ch = toUpper(ch);
        foreach (i; 0 .. itemCount)
        {
            const item = menuItem(i);
            if (!item.isSeparator)
            {
                if (item._label.hotkey == ch)
                    return i;
            }
        }
        return -1;
    }
/+
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
            if (!item.isSeparator)
            {
                if (item._label.hotkey == ch)
                    return item;
            }
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
        submenu._visualParentMenu = this;
        _openedSubmenuIndex = itemIndex;
        auto popup = window.showPopup(submenu);
        popup.anchor = WeakRef!Widget(item);
        popup.alignment = isMenuBar ? PopupAlign.below : PopupAlign.right;
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

    override @property inout(Widget) parent() inout
    {
        return super.parent;
    }
    override @property void parent(Widget p)
    {
        // ok, this menu needs to know whether popup is closed
        // so, when popup sets itself as menu's parent, we add our slot to onPopupClose
        // and remove it on menu close
        if (auto popup = cast(Popup)p)
        {
            if (auto prev = thisPopup)
                prev.onPopupClose -= &handleThisPopupClose;
            popup.onPopupClose ~= &handleThisPopupClose;
        }
        super.parent = p;
    }

    protected void handleThisPopupClose(bool byEvent)
    {
        assert(thisPopup);
        debug (menus)
            Log.d("Menu: closing popup");

        handleClose();
        // remove submenu from the parent
        if (_visualParentMenu)
        {
            _visualParentMenu._openedSubmenu = null;
            _visualParentMenu._openedSubmenuIndex = -1;
        }
        // if clicked outside
        if (byEvent)
        {
            // close the whole menu
            Menu top = _visualParentMenu;
            while (top)
            {
                if (top._visualParentMenu)
                    top = top._visualParentMenu;
                else
                {
                    top.close();
                    break;
                }
            }
        }
        _visualParentMenu = null;

        thisPopup.onPopupClose -= &handleThisPopupClose;
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
            _previousFocusedWidget = _visualParentMenu ? WeakRef!Widget(_visualParentMenu) : window.focusedElement;
        }
        super.handleFocusChange(focused);
    }

    override protected void handleSelection(int index, int previouslySelectedItem = -1)
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

    override protected void handleItemClick(int index)
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
                handleMenuItemClick(item);
            }
        }
    }

    /// Process menu item action in a top level menu
    protected void handleMenuItemClick(MenuItem item)
    {
        if (_visualParentMenu)
            // send up
            _visualParentMenu.handleMenuItemClick(item);
        else
        {
            if (item.isSeparator)
                // do nothing
                return;

            debug (menus)
                Log.d("Menu: process item ", item.action.label);

            // copy stuff we need
            auto menuItemClickedCopy = onMenuItemClick;
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
        if (_visualParentMenu)
            return _visualParentMenu.navigatingUsingKeys;
        else
            return _navigatingUsingKeys;
    }
    protected @property void navigatingUsingKeys(bool flag)
    {
        if (_visualParentMenu)
            _visualParentMenu.navigatingUsingKeys = flag;
        else
            _navigatingUsingKeys = flag;
    }

    /// Menu navigation using keys
    override bool handleKeyEvent(KeyEvent event)
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
                    handleItemClick(selectedItemIndex);
                    return true;
                }
                if (event.key == Key.up)
                {
                    if (_visualParentMenu && _visualParentMenu.orientation == Orientation.vertical)
                    {
                        // parent is a popup menu
                        _visualParentMenu.moveSelection(-1);
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
                    if (_visualParentMenu)
                    {
                        if (_visualParentMenu.orientation == Orientation.vertical)
                        {
                            // back to parent menu on Left key
                            close();
                        }
                        else
                        {
                            // parent is a menu bar
                            _visualParentMenu.moveSelection(-1);
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
                    else if (_visualParentMenu && _visualParentMenu.orientation == Orientation.horizontal)
                    {
                        _visualParentMenu.moveSelection(1);
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
                    handleItemClick(index);
                    return true;
                }
            }
        }
        return super.handleKeyEvent(event);
    }

    override bool handleMouseEvent(MouseEvent event)
    {
        navigatingUsingKeys = false;
        return super.handleMouseEvent(event);
    }
+/
    override protected Boundaries computeBoundaries()
    {
        // align items for vertical menu
        if (orientation == Orientation.vertical)
        {
            float maxHeight = 0;
            float maxCheckBoxWidth = 0;
            float maxLabelWidth = 0;
            float maxIconWidth = 0;
            float maxShortcutWidth = 0;
            float maxMoreBtnWidth = 0;
            // find max dimensions for item subwidgets
            foreach (i; 0 .. itemCount)
            {
                if (auto it = menuItem(i))
                    it.measureSubitems(maxHeight, maxCheckBoxWidth, maxLabelWidth,
                        maxIconWidth, maxShortcutWidth, maxMoreBtnWidth);
            }
            // set equal dimensions for item subwidgets
            foreach (i; 0 .. itemCount)
            {
                if (auto it = menuItem(i))
                    it.setSubitemSizes(maxHeight, maxCheckBoxWidth, maxLabelWidth,
                        maxIconWidth, maxShortcutWidth, maxMoreBtnWidth);
            }
        }
        return super.computeBoundaries();
    }
}
/+
class ElemMenuBar : ElemMenu
{
    override @property bool wantsKeyTracking() const
    {
        return true;
    }

    override protected void handleClose()
    {
        selectOnHover = false;
        super.handleClose();
    }

    override protected void handleSelection(int index, int previouslySelectedItem = -1)
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

    override protected void handleItemClick(int index)
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
                handleMenuItemClick(item);
            }
        }
    }

    private bool _menuToggleState;

    override bool handleKeyEvent(KeyEvent event)
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
                    handleSelection(index, prevIndex);
                    handleItemClick(index);
                }
                return true;
            }
            else
            {
                if (auto item = findSubitemByHotkeyRecursive(hotkey))
                {
                    debug (menus)
                        Log.d("found menu item recursive");
                    handleMenuItemClick(item);
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
        return super.handleKeyEvent(event);
    }
}
+/
