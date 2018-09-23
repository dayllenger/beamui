/**
This module contains declaration of themes and styles implementation.

Style - style container
Theme - parent for all styles


Synopsis:
---
import beamui.widgets.styles;
---

Recent changes:
     Dimensions like fontSize, padding, margins, min/max width and height can be specified in points, e.g. minWidth = "3pt" margins="1pt,2pt,1pt,2pt"
     % for font size, based on parent font size, e.g. fontSize="120.5%" means parentStyle.fontSize * 120.5 / 100.0;

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.widgets.styles;

import beamui.core.config;

import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types;
import beamui.core.units;
import beamui.css.css;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.graphics.drawbuf;
import beamui.graphics.fonts;
import beamui.graphics.resources;

/// Align option bit constants
enum Align : uint
{
    /// Alignment is not specified
    unspecified = 0,
    /// Horizontally align to the left of box
    left = 1,
    /// Horizontally align to the right of box
    right = 2,
    /// Horizontally align to the center of box
    hcenter = 1 | 2,
    /// Vertically align to the top of box
    top = 4,
    /// Vertically align to the bottom of box
    bottom = 8,
    /// Vertically align to the center of box
    vcenter = 4 | 8,
    /// Align to the center of box (vcenter | hcenter)
    center = vcenter | hcenter,
    /// Align to the top left corner of box (left | top)
    topleft = left | top,
}

/// Text drawing flag bits
enum TextFlag : uint
{
    /// Not set
    unspecified = 0,
    /// Text contains hot key prefixed with & char (e.g. "&File")
    hotkeys = 1,
    /// Underline hot key when drawing
    underlineHotkeys = 2,
    /// Underline hot key when Alt is pressed
    underlineHotkeysOnAlt = 4,
    /// Underline text when drawing
    underline = 8,
    /// Strikethrough text when drawing
    strikeThrough = 16, // TODO:
    /// Use text flags from parent widget
    parent = 32
}

/// Custom drawable attribute container for styles
class DrawableAttribute
{
    @property
    {
        string id() const
        {
            return _id;
        }

        string drawableID() const
        {
            return _drawableID;
        }

        void drawableID(string newDrawable)
        {
            _drawableID = newDrawable;
            clear();
        }

        ref DrawableRef drawable() const
        {
            if (!_drawable.isNull)
                return (cast(DrawableAttribute)this)._drawable;
            (cast(DrawableAttribute)this)._drawable = drawableCache.get(_drawableID);
            (cast(DrawableAttribute)this)._initialized = true;
            return (cast(DrawableAttribute)this)._drawable;
        }
    }

    protected
    {
        string _id;
        string _drawableID;
        DrawableRef _drawable;
        bool _initialized;
    }

    this(string id, string drawableID)
    {
        _id = id;
        _drawableID = drawableID;
    }

    ~this()
    {
        clear();
    }

    void clear()
    {
        _drawable.clear();
        _initialized = false;
    }

    void onThemeChanged()
    {
        if (!_drawableID)
        {
            _drawable.clear();
            _initialized = false;
        }
    }
}

struct DrawableAttributeList
{
    DrawableAttribute[string] _customDrawables;

    ~this()
    {
        clear();
    }

    void clear()
    {
        eliminate(_customDrawables);
    }

    bool hasKey(string key) const
    {
        return (key in _customDrawables) !is null;
    }

    ref DrawableRef drawable(string id) const
    {
        return _customDrawables[id].drawable;
    }
    /// Get custom drawable attribute
    string drawableID(string id) const
    {
        return _customDrawables[id].drawableID;
    }

    void set(string id, string resourceID)
    {
        if (id in _customDrawables)
        {
            _customDrawables[id].drawableID = resourceID;
        }
        else
        {
            _customDrawables[id] = new DrawableAttribute(id, resourceID);
        }
    }

    void copyFrom(ref DrawableAttributeList v)
    {
        clear();
        foreach (key, value; v._customDrawables)
        {
            set(key, value.drawableID);
        }
    }

    void onThemeChanged()
    {
        foreach (key, ref value; _customDrawables)
        {
            if (value)
            {
                value.onThemeChanged();
            }
        }
    }
}

/// Style - widget property container
final class Style
{
private:
    // layout
    Dimension _width = Dimension.none;
    Dimension _height = Dimension.none;
    Dimension _minWidth = Dimension.zero;
    Dimension _maxWidth = Dimension.none;
    Dimension _minHeight = Dimension.zero;
    Dimension _maxHeight = Dimension.none;
    int _weight = 1;
    Align _alignment = Align.topleft;
    RectOffset _margins = RectOffset(0);
    RectOffset _padding = RectOffset(0);
    // background
    string _border;
    string _backgroundImageID;
    BoxShadowDrawable _boxShadow;
    // text
    string _fontFace = "Arial"; // TODO(dlangui): from settings
    FontFamily _fontFamily = FontFamily.sans_serif;
    Dimension _fontSize = Dimension.pt(9); // TODO(dlangui): from settings or screen properties / DPI
    FontStyle _fontStyle = FontStyle.normal;
    ushort _fontWeight = 400;
    TextFlag _textFlags = TextFlag.unspecified;
    int _maxLines = 1;
    // colors
    uint _backgroundColor = COLOR_TRANSPARENT;
    ubyte _alpha = 0;
    uint _textColor = 0x000000; // black
    uint _focusRectColor = COLOR_UNSPECIFIED; // disabled by default
    // 24 overall

    /// This is a bitmap which indicates which style properties are overriden (true) or inherited (false)
    bool[24] overrideMap;
    // WARNING: if you're adding a new property, carefully check all indices of overrideMap in the code

    /// State descriptor
    struct StateStyle
    {
        Style s;
        State specified;
        State enabled;
    }

    Style parent;
    StateStyle[] stateStyles;

    FontRef _font;
    DrawableRef _backgroundDrawable;

public:
    /// Find substyle based on widget state (e.g. focused, pressed, ...)
    const(Style) forState(State state) const
    {
        if (state == State.normal)
            return this;
        foreach (s; stateStyles)
        {
            if ((s.specified & state) == s.enabled)
                return s.s;
        }
        // not found - fallback to normal
        return this;
    }

@property
{
    //===================================================
    // SETTERS
    //===================================================
    // layout properties

    Style width(Dimension value)
    {
        _width = value;
        overrideMap[0] = true;
        return this;
    }
    Style height(Dimension value)
    {
        _height = value;
        overrideMap[1] = true;
        return this;
    }
    /// Min width constraint, Dimension.zero or Dimension.none to unset limit
    Style minWidth(Dimension value)
    {
        if (value == Dimension.none)
            value = Dimension.zero;
        _minWidth = value;
        overrideMap[2] = true;
        return this;
    }
    /// Max width constraint, Dimension.none to unset limit
    Style maxWidth(Dimension value)
    {
        _maxWidth = value;
        overrideMap[3] = true;
        return this;
    }
    /// Min height constraint, Dimension.zero or Dimension.none to unset limit
    Style minHeight(Dimension value)
    {
        if (value == Dimension.none)
            value = Dimension.zero;
        _minHeight = value;
        overrideMap[4] = true;
        return this;
    }
    /// Max height constraint, Dimension.none to unset limit
    Style maxHeight(Dimension value)
    {
        _maxHeight = value;
        overrideMap[5] = true;
        return this;
    }
    Style weight(int value)
    {
        _weight = value;
        overrideMap[6] = true;
        return this;
    }
    Style alignment(Align value)
    {
        _alignment = value;
        overrideMap[7] = true;
        return this;
    }
    Style margins(RectOffset value)
    {
        _margins = value;
        overrideMap[8] = true;
        return this;
    }
    Style padding(RectOffset value)
    {
        _padding = value;
        overrideMap[9] = true;
        return this;
    }

    //===================================================
    // background properties

    Style border(string value)
    {
        _border = value;
        _backgroundDrawable.clear();
        overrideMap[10] = true;
        return this;
    }
    Style backgroundImageID(string value)
    {
        _backgroundImageID = value;
        _backgroundDrawable.clear();
        overrideMap[11] = true;
        return this;
    }
    Style boxShadow(BoxShadowDrawable value)
    {
        _boxShadow = value;
        _backgroundDrawable.clear();
        overrideMap[12] = true;
        return this;
    }

    //===================================================
    // text properties

    Style fontFace(string value)
    {
        if (_fontFace != value)
            clearCachedObjects();
        _fontFace = value;
        overrideMap[13] = true;
        return this;
    }
    Style fontFamily(FontFamily value)
    {
        if (_fontFamily != value)
            clearCachedObjects();
        _fontFamily = value;
        overrideMap[14] = true;
        return this;
    }
    Style fontSize(Dimension value)
    {
        if (value == Dimension.none)
            value = Dimension.pt(9);

        if (_fontSize != value)
            clearCachedObjects();
        _fontSize = value;
        overrideMap[15] = true;
        return this;
    }
    Style fontStyle(FontStyle value)
    {
        if (_fontStyle != value)
            clearCachedObjects();
        _fontStyle = value;
        overrideMap[16] = true;
        return this;
    }
    Style fontWeight(ushort value)
    {
        if (_fontWeight != value)
            clearCachedObjects();
        _fontWeight = value;
        overrideMap[17] = true;
        return this;
    }
    Style textFlags(TextFlag value)
    {
        _textFlags = value;
        overrideMap[18] = true;
        return this;
    }
    Style maxLines(int value)
    {
        _maxLines = value;
        overrideMap[19] = true;
        return this;
    }

    //===================================================
    // color properties

    Style backgroundColor(uint value)
    {
        _backgroundColor = value;
        _backgroundImageID = COLOR_DRAWABLE;
        _backgroundDrawable.clear();
        overrideMap[20] = true;
        return this;
    }
    /// Alpha (0 = opaque ... 255 = transparent)
    Style alpha(ubyte value)
    {
        _alpha = value;
        overrideMap[21] = true;
        return this;
    }
    Style textColor(uint value)
    {
        _textColor = value;
        overrideMap[22] = true;
        return this;
    }
    /// Returns colors to draw focus rectangle (one for solid, two for vertical gradient) or null if no focus rect should be drawn for style
    Style focusRectColor(uint value)
    {
        _focusRectColor = value;
        overrideMap[23] = true;
        return this;
    }

    //===================================================
    // GETTERS
    //===================================================
    // layout properties

    int width() const
    {
        if (parent && !overrideMap[0])
            return parent.width;
        return _width.toDevice;
    }
    int height() const
    {
        if (parent && !overrideMap[1])
            return parent.height;
        return _height.toDevice;
    }
    int minWidth() const
    {
        if (parent && !overrideMap[2])
            return parent.minWidth;
        return _minWidth.toDevice;
    }
    int maxWidth() const
    {
        if (parent && !overrideMap[3])
            return parent.maxWidth;
        return _maxWidth.toDevice;
    }
    int minHeight() const
    {
        if (parent && !overrideMap[4])
            return parent.minHeight;
        return _minHeight.toDevice;
    }
    int maxHeight() const
    {
        if (parent && !overrideMap[5])
            return parent.maxHeight;
        return _maxHeight.toDevice;
    }
    int weight() const pure
    {
        if (parent && !overrideMap[6])
            return parent.weight;
        return _weight;
    }
    Align alignment() const
    {
        if (parent && !overrideMap[7])
            return parent.alignment;
        return _alignment;
    }
    RectOffset margins() const
    {
        if (parent && !overrideMap[8]) // FIXME: _stateMask || ????
            return parent.margins;
        return RectOffset(0);//_margins.toPixels;
    }
    RectOffset padding() const
    {
        if (parent && !overrideMap[9])
            return parent.padding;
        return _padding.toPixels;
    }

    //===================================================
    // background properties

    string border() const pure
    {
        if (parent && !overrideMap[10])
            return parent.border;
        return _border;
    }
    string backgroundImageID() const pure
    {
        if (parent && !overrideMap[11])
            return parent.backgroundImageID;
        if (_backgroundImageID == COLOR_DRAWABLE)
            return null;
        return _backgroundImageID != COLOR_DRAWABLE ? _backgroundImageID : null;
    }
    inout(BoxShadowDrawable) boxShadow() inout pure
    {
        if (parent && !overrideMap[12])
            return parent.boxShadow;
        return _boxShadow;
    }

    //===================================================
    // text properties

    string fontFace() const pure
    {
        if (parent && !overrideMap[13])
            return parent.fontFace;
        return _fontFace;
    }
    FontFamily fontFamily() const pure
    {
        if (parent && !overrideMap[14])
            return parent.fontFamily;
        return _fontFamily;
    }
    int fontSize() const
    {
        if (parent && !overrideMap[15])
            return parent.fontSize;
        int res = _fontSize.toDevice;
        if (_fontSize.is_em)
            return parent.fontSize * res / 100;
        if (_fontSize.is_percent)
            return parent.fontSize * res / 10000;
        return res;
    }
    FontStyle fontStyle() const pure
    {
        if (parent && !overrideMap[16])
            return parent.fontStyle;
        return _fontStyle;
    }
    ushort fontWeight() const pure
    {
        if (parent && !overrideMap[17])
            return parent.fontWeight;
        return _fontWeight;
    }
    TextFlag textFlags() const pure
    {
        if (parent && !overrideMap[18])
            return parent.textFlags;
        return _textFlags;
    }
    int maxLines() const pure
    {
        if (parent && !overrideMap[19])
            return parent.maxLines;
        return _maxLines;
    }

    //===================================================
    // color properties

    uint backgroundColor() const pure
    {
        if (parent && !overrideMap[20])
            return parent.backgroundColor;
        return _backgroundColor;
    }
    ubyte alpha() const pure
    {
        if (parent && !overrideMap[21])
            return parent.alpha;
        return _alpha;
    }
    uint textColor() const pure
    {
        if (parent && !overrideMap[22])
            return parent.textColor;
        return _textColor;
    }
    uint focusRectColor() const pure
    {
        if (parent && !overrideMap[23])
            return parent.focusRectColor;
        return _focusRectColor;
    }

    //===================================================
    // DERIVATIVES

    /// Get background drawable for this style
    ref DrawableRef backgroundDrawable() const
    {
        Style s = cast(Style)this;
        if (!s._backgroundDrawable.isNull)
            return s._backgroundDrawable;

        uint color = backgroundColor;
        string image = backgroundImageID;
        string borders = border;
        BoxShadowDrawable shadows = s.boxShadow;
        if (borders || shadows)
        {
            s._backgroundDrawable = new CombinedDrawable(color, image, borders, shadows);
        }
        else if (image)
        {
            s._backgroundDrawable = drawableCache.get(image);
        }
        else
        {
            s._backgroundDrawable = isFullyTransparentColor(color) ?
                new EmptyDrawable : new SolidFillDrawable(color);
        }
        return s._backgroundDrawable;
    }

    /// Get font
    ref FontRef font() const
    {
        Style s = cast(Style)this;
        if (!s._font.isNull)
            return s._font;
        s._font = FontManager.instance.getFont(fontSize, fontWeight, fontItalic, fontFamily, fontFace);
        return s._font;
    }

    /// Check if font style is italic
    bool fontItalic() const
    {
        return fontStyle == FontStyle.italic;
    }
}

    /// Reinherit modified (owned by widget) style to another parent
    void reinherit(Style newParent)
    {
        parent = newParent;
    }

    void onThemeChanged()
    {
        _font.clear();
        _backgroundDrawable.clear();
        foreach (s; stateStyles)
            s.s.onThemeChanged();
    }

    void clearCachedObjects()
    {
        onThemeChanged();
    }

    /// Print all style properties (for debugging purposes)
    debug void printStats() const
    {
        Log.d("--- Style stats ---");
        static foreach (i, p; [
            "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
            "weight", "alignment", "margins", "padding",
            "border", "backgroundImageID", "boxShadow", "fontFace", "fontFamily",
            "fontSize", "fontStyle", "fontWeight", "textFlags", "maxLines",
            "backgroundColor", "alpha", "textColor", "focusRectColor"])
        {
            Log.d(overrideMap[i] ? p ~ " (o): " : p ~ ": ", mixin(p));
        }
    }

    debug @property static int instanceCount() { return _instanceCount; }

private:
    debug static __gshared int _instanceCount;

    this() pure
    {
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created style, count: ", _instanceCount);
    }

    ~this()
    {
        parent = null;
        foreach (s; stateStyles)
            eliminate(s.s);
        destroy(stateStyles);
        stateStyles = null;
        _font.clear();
        _backgroundDrawable.clear();
        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed style, count: ", _instanceCount);
    }

    /// Create a style with the same properties
    Style clone()
    {
        auto res = new Style;
        res._width = _width;
        res._height = _height;
        res._minWidth = _minWidth;
        res._maxWidth = _maxWidth;
        res._minHeight = _minHeight;
        res._maxHeight = _maxHeight;
        res._weight = _weight;
        res._alignment = _alignment;
        res._margins = _margins;
        res._padding = _padding;
        res._border = _border;
        res._backgroundImageID = _backgroundImageID;
        res._boxShadow = _boxShadow;
        res._fontFace = _fontFace;
        res._fontFamily = _fontFamily;
        res._fontSize = _fontSize;
        res._fontStyle = _fontStyle;
        res._fontWeight = _fontWeight;
        res._textFlags = _textFlags;
        res._maxLines = _maxLines;
        res._backgroundColor = _backgroundColor;
        res._alpha = _alpha;
        res._textColor = _textColor;
        res._focusRectColor = _focusRectColor;
        res.overrideMap = overrideMap;
        return res;
    }

    /// Find exact existing state style or create new if no matched styles found
    Style getOrCreateState(State specified, State enabled)
    {
        if (specified == State.unspecified)
            return this;
        foreach (s; stateStyles)
            if (s.specified == specified && s.enabled == enabled)
                return s.s;
        // not found
        debug (styles)
            Log.d("Creating substate: ", specified);
        // TODO: inherit from parent state style
        // TODO: inherit from less specific state style
        auto s = new Style;
        s.parent = this;
        stateStyles ~= StateStyle(s, specified, enabled);

        import core.bitop;

        // sort state styles by state value and its bit count
        stateStyles.sort!((a, b) => a.specified * a.specified * popcnt(a.specified) >
                                    b.specified * b.specified * popcnt(b.specified));
        return s;
    }
}

/// Theme - a collection of widget styles, custom colors and drawables
final class Theme
{
private:
    struct StyleID
    {
        string name; // name of a widget or custom name
        string widgetID; // id, #id from css
        string sub; // subitem, ::sub from css
    }

    string _name;
    Style defaultStyle;
    Style[StyleID] styles;
    DrawableAttributeList drawables;
    uint[string] colors;

public:
    /// Unique name of theme
    @property string name() const pure { return _name; }

    /// Create empty theme called `name`
    this(string name)
    {
        _name = name;
        defaultStyle = new Style;
    }

    ~this()
    {
        Log.d("Destroying theme");
        eliminate(defaultStyle);
        eliminate(styles);
        destroy(drawables);
    }

    /// A root of style hierarchy. Same as `theme.get(null)`
    @property Style root()
    {
        return defaultStyle;
    }

    /// Get a style OR create it if it's not exist
    Style get(TypeInfo_Class widgetType, string widgetID = null, string sub = null)
    {
        // TODO: check correctness
        if (!widgetType)
            return defaultStyle;

        import std.string : split;
        // get short name
        string name = widgetType.name.split('.')[$ - 1];
        // try to find exact style
        auto p = StyleID(name, widgetID, sub) in styles;
        if (!p && widgetID)
        {
            // try to find a style without widget id
            // because otherwise it will create an empty style for every widget
            p = StyleID(name, null, sub) in styles;
        }
        if (p)
        {
            auto style = *p;
            // if this style was created by stylesheet loader, parent may not be set
            // because class hierarhy is not known there
            if (!style.parent)
                style.parent = getParent(widgetType, sub);
            return style;
        }
        else
        {
            // creating style without widget id
            auto style = new Style;
            style.parent = getParent(widgetType, sub);
            styles[StyleID(name, null, sub)] = style;
            return style;
        }
    }

    /// ditto
    private Style get(string widgetTypeName, string widgetID = null, string sub = null)
    {
        if (!widgetTypeName)
            return defaultStyle;

        auto id = StyleID(widgetTypeName, widgetID, sub);
        if (auto p = id in styles)
            return *p;
        else
        {
            auto style = new Style;
            // set parent for #id styles
            if (widgetID)
                style.parent = get(widgetTypeName, null, sub);
            styles[id] = style;
            return style;
        }
    }

    /// Utility - find parent of style
    private Style getParent(TypeInfo_Class widgetType, string sub)
    {
        import std.string : split;
        // if this class is not on top of hierarhy
        if (widgetType.base !is typeid(Object))
        {
            if (sub)
            {
                // inherit only if parent subitem exists
                if (auto psub = StyleID(widgetType.base.name.split('.')[$ - 1], null, sub) in styles)
                    return *psub;
            }
            else
                return get(widgetType.base);
        }
        return defaultStyle;
    }

    /// Create wrapper style of an existing - to modify some base style properties in widget
    Style modifyStyle(Style parent)
    {
        if (parent && parent !is defaultStyle)
        {
            auto s = new Style;
            s.parent = parent;
            // clone state styles
            foreach (item; parent.stateStyles)
            {
                auto clone = item.s.clone();
                clone.parent = s;
                s.stateStyles ~= Style.StateStyle(clone, item.specified, item.enabled);
            }
            return s;
        }
        else
        {
            return new Style;
        }
    }

    /// Get custom drawable
    ref DrawableRef getDrawable(string name) const
    {
        if (drawables.hasKey(name))
            return drawables.drawable(name);
        return (cast(Theme)this)._emptyDrawable;
    }
    private DrawableRef _emptyDrawable;

    /// Get drawable id of custom drawable
    string getDrawableID(string name) const
    {
        if (drawables.hasKey(name))
            return drawables.drawableID(name);
        return null;
    }

    /// Set custom drawable for theme
    Theme setDrawable(string name, string id)
    {
        drawables.set(name, id);
        return this;
    }

    /// Get custom color - transparent by default
    uint getColor(string name, uint defaultColor = COLOR_TRANSPARENT)
    {
        return colors.get(name, defaultColor);
    }

    /// Set custom color for theme
    Theme setColor(string name, uint color)
    {
        colors[name] = color;
        return this;
    }

    void onThemeChanged()
    {
        defaultStyle.onThemeChanged();
        foreach (s; styles)
        {
            s.onThemeChanged();
        }
        drawables.onThemeChanged();
    }

    /// Print out theme stats
    void printStats()
    {
        Log.fd("Theme: %s, styles: %s, drawables: %s, colors: %s", _name, styles.length,
            drawables._customDrawables.length, colors.length);
    }
}

private __gshared Theme _currentTheme;
/// Current theme accessor
@property Theme currentTheme()
{
    return _currentTheme;
}
/// Set new theme to be current
@property void currentTheme(Theme theme)
{
    eliminate(_currentTheme);
    _currentTheme = theme;
}

/// Returns custom drawable replacement id for specified id from current theme, or returns passed value if not found or no current theme
string overrideCustomDrawableID(string id)
{
    string res = currentTheme ? currentTheme.getDrawableID(id) : id;
    return !res ? id : res;
}

shared static ~this()
{
    currentTheme = null;
}

immutable ATTR_SCROLLBAR_BUTTON_UP = "scrollbar_button_up";
immutable ATTR_SCROLLBAR_BUTTON_DOWN = "scrollbar_button_down";
immutable ATTR_SCROLLBAR_BUTTON_LEFT = "scrollbar_button_left";
immutable ATTR_SCROLLBAR_BUTTON_RIGHT = "scrollbar_button_right";
immutable ATTR_SCROLLBAR_INDICATOR_VERTICAL = "scrollbar_indicator_vertical";
immutable ATTR_SCROLLBAR_INDICATOR_HORIZONTAL = "scrollbar_indicator_horizontal";

Theme createDefaultTheme()
{
    Log.d("Creating default theme");
    auto theme = new Theme("default");

    version (Windows)
    {
        theme.root.fontFace = "Verdana";
    }
    static if (BACKEND_GUI)
    {
        theme.root.fontSize = Dimension.pt(12);

        auto label = theme.get("Label");
        label.alignment(Align.left | Align.vcenter).padding(RectOffset(4.pt, 2.pt));
        label.getOrCreateState(State.enabled, State.unspecified).textColor(0xa0000000);

        auto mlabel = theme.get("MultilineLabel");
        mlabel.padding(RectOffset(1.pt)).maxLines(0);

        auto tooltip = theme.get("Label", "tooltip");
        tooltip.padding(RectOffset(3.pt)).boxShadow(new BoxShadowDrawable(0, 2, 7, 0x888888)).
            backgroundColor(0x222222).textColor(0xeeeeee);

        auto button = theme.get("Button");
        button.alignment(Align.center).padding(RectOffset(4.pt)).border("#aaa,1").
            textFlags(TextFlag.underlineHotkeys).focusRectColor(0xbbbbbb);
        button.getOrCreateState(State.hovered | State.checked, State.hovered).
            border("#4e93da,1");
    }
    else // console
    {
        theme.root.fontSize = 1;
    }
    return theme;
}

/// Load theme from file, null if failed
Theme loadTheme(string name)
{
    string filename = resourceList.getPathByID((BACKEND_CONSOLE ? "console_" ~ name : name) ~ ".css");

    if (!filename)
        return null;

    Log.d("Loading theme from file ", filename);
    string src = cast(string)loadResourceBytes(filename);
    if (!src)
        return null;

    auto theme = new Theme(name);
    auto stylesheet = createStyleSheet(src);
    loadThemeFromCSS(theme, stylesheet);
    return theme;
}

private void loadThemeFromCSS(Theme theme, StyleSheet stylesheet)
{
    foreach (r; stylesheet.atRules)
    {
        applyAtRule(theme, r);
    }
    foreach (r; stylesheet.rulesets)
    {
        foreach (sel; r.selectors)
        {
            applyRule(theme, sel, r.properties);
        }
    }
}

private void applyAtRule(Theme theme, AtRule rule)
{
    auto kw = rule.keyword;
    auto ps = rule.properties;
    assert(ps.length > 0);

    if (kw == "define-colors")
    {
        foreach (p; ps)
        {
            string id = p.name;
            uint color = decodeColorCSS(p.value);
            theme.setColor(id, color);
        }
    }
    else if (kw == "define-drawables")
    {
        foreach (p; ps)
        {
            string id = p.name;
            string bg = decodeBackgroundCSS(p.value);
            theme.setDrawable(id, bg);
        }
    }
    else
        Log.w("CSS: unknown at-rule keyword: ", kw);
}

private void applyRule(Theme theme, Selector selector, Property[] properties)
{
    auto style = selectStyle(theme, selector);
    if (!style)
        return;
    foreach (p; properties)
    {
        assert(p.value.length > 0);
        switch (p.name)
        {
        case "width":
            style.width = decodeDimensionCSS(p.value[0]);
            break;
        case "height":
            style.height = decodeDimensionCSS(p.value[0]);
            break;
        case "min-width":
            style.minWidth = decodeDimensionCSS(p.value[0]);
            break;
        case "max-width":
            style.maxWidth = decodeDimensionCSS(p.value[0]);
            break;
        case "min-height":
            style.minHeight = decodeDimensionCSS(p.value[0]);
            break;
        case "max-height":
            style.maxHeight = decodeDimensionCSS(p.value[0]);
            break;/+
        case "weight":
            style.weight = to!int(p.value[0].text); // TODO
            break;+/
        case "align":
            style.alignment = decodeAlignmentCSS(p.value);
            break;
        case "margin":
            style.margins = decodeRectOffsetCSS(p.value);
            break;
        case "padding":
            style.padding = decodeRectOffsetCSS(p.value);
            break;
        case "border":
            style.border = decodeBorderCSS(p.value);
            break;
        case "background":
            style.backgroundImageID = decodeBackgroundCSS(p.value);
            break;
        case "box-shadow":
            style.boxShadow = decodeBoxShadowCSS(p.value);
            break;
        case "font-face":
            style.fontFace = p.value[0].text;
            break;
        case "font-family":
            style.fontFamily = decodeFontFamilyCSS(p.value);
            break;
        case "font-size":
            style.fontSize = decodeDimensionCSS(p.value[0]);
            break;
        case "font-weight":
            style.fontWeight = cast(ushort)decodeFontWeightCSS(p.value);
            break;
        case "text-flags":
            style.textFlags = decodeTextFlagsCSS(p.value);
            break;
        case "max-lines":
            style.maxLines = to!int(p.value[0].text);
            break;
        case "background-color":
            style.backgroundColor = decodeColorCSS(p.value);
            break;
        case "opacity":
            style.alpha = opacityToAlpha(to!float(p.value[0].text));
            break;
        case "color":
            style.textColor = decodeColorCSS(p.value);
            break;
        case "focus-rect-color":
            style.focusRectColor = decodeColorCSS(p.value);
            break;
        default:
            break;
        }
    }
}

private Style selectStyle(Theme theme, Selector selector)
{
    auto es = selector.entries;
    assert(es.length > 0);

    if (es.length == 1 && es[0].type == SelectorEntryType.universal)
        return theme.defaultStyle;

    import std.algorithm : find;
    // find first element entry
    es = es.find!(a => a.type == SelectorEntryType.element);
    if (es.length == 0)
    {
        Log.fe("CSS(%s): there must be an element entry in selector", selector.line);
        return null;
    }
    auto hash = es.find!(a => a.type == SelectorEntryType.id);
    auto pseudoElement = es.find!(a => a.type == SelectorEntryType.pseudoElement);
    string id = hash.length > 0 ? hash[0].text : null;
    string sub = pseudoElement.length > 0 ? pseudoElement[0].text : null;
    // find base style
    auto style = theme.get(es[0].text, id, sub);
    // extract state
    State specified;
    State enabled;
    void applyStateFlag(string flag, string stateName, State state)
    {
        bool yes = flag[0] != '!';
        string s = yes ? flag : flag[1 .. $];
        if (s == stateName)
        {
            specified |= state;
            if (yes)
                enabled |= state;
        }
    }
    foreach (e; es)
    {
        if (e.type == SelectorEntryType.pseudoClass)
        {
            applyStateFlag(e.text, "pressed", State.pressed);
            applyStateFlag(e.text, "focused", State.focused);
            applyStateFlag(e.text, "default", State.default_);
            applyStateFlag(e.text, "hovered", State.hovered);
            applyStateFlag(e.text, "selected", State.selected);
            applyStateFlag(e.text, "checkable", State.checkable);
            applyStateFlag(e.text, "checked", State.checked);
            applyStateFlag(e.text, "enabled", State.enabled);
            applyStateFlag(e.text, "activated", State.activated);
            applyStateFlag(e.text, "window-focused", State.windowFocused);
        }
    }
    return style.getOrCreateState(specified, enabled);
}

/// Parses CSS token sequence like "left vcenter" to Align bit set
Align decodeAlignmentCSS(Token[] tokens)
{
    Align res = Align.unspecified;
    foreach (t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            Log.fe("CSS(%s): alignment should be an identifier, not '%s'", t.line, t.type);
            break;
        }
        switch (t.text)
        {
        case "left": res |= Align.left; break;
        case "right": res |= Align.right; break;
        case "top": res |= Align.top; break;
        case "bottom": res |= Align.bottom; break;
        case "hcenter": res |= Align.hcenter; break;
        case "vcenter": res |= Align.vcenter; break;
        case "center": res |= Align.center; break;
        case "top-left": res |= Align.topleft; break;
        default:
            Log.fe("CSS(%s): unknown alignment: %s", t.line, t.text);
            break;
        }
    }
    return res;
}

/// Parses CSS rectangle declaration to RectOffset
RectOffset decodeRectOffsetCSS(Token[] tokens)
{
    uint[4] values;
    size_t valueCount;
    foreach (t; tokens)
    {
        if (t.type == TokenType.number || t.type == TokenType.dimension)
            values[valueCount++] = decodeDimensionCSS(t).toDevice;
        else
        {
            Log.fe("CSS(%s): rectangle value should be numeric, not '%s'", t.line, t.type);
            break;
        }
        if (valueCount > 4)
        {
            Log.fe("CSS(%s): too much values for rectangle", t.line);
            break;
        }
    }
    // TODO: rotate. Should be: top right bottom left
    // or adapt?
    if (valueCount == 1) // same value for all dimensions
        return RectOffset(values[0]);
    else if (valueCount == 2) // one value of horizontal, and one for vertical
        return RectOffset(values[0], values[1]);
    else if (valueCount == 3) // values for left, right, and one for vertical
        return RectOffset(values[0], values[1], values[2], values[1]);
    else if (valueCount == 4) // separate left, top, right, bottom
        return RectOffset(values[0], values[1], values[2], values[3]);
    Log.fe("CSS(%s): empty rectangle", tokens[0].line);
    return RectOffset(0);
}

/// Decode dimension, e.g. 1px, 20%, 1.2em or `none`
Dimension decodeDimensionCSS(Token t)
{
    if (t.type == TokenType.ident)
    {
        if (t.text == "none")
            return Dimension.none;
        else
            Log.fe("CSS(%s): unknown length identifier: '%s'", t.line, t.text);
    }
    else if (t.type == TokenType.number)
    {
        if (t.text == "0")
            return Dimension.zero;
        else
            Log.fe("CSS(%s): length units are mandatory", t.line);
    }
    else if (t.type == TokenType.dimension)
    {
        Dimension u = Dimension.parse(t.text, t.dimensionUnit);
        if (u != Dimension.none)
            return u;
        else
            Log.fe("CSS(%s): can't parse length", t.line);
    }
    else if (t.type == TokenType.percentage)
    {
        Dimension u = Dimension.parse(t.text, "%");
        if (u != Dimension.none)
            return u;
        else
            Log.fe("CSS(%s): can't parse percent", t.line);
    }
    else
        Log.fe("CSS(%s): invalid length: '%s'", t.line, t.type);

    return Dimension.none;
}

string decodeBorderCSS(Token[] tokens) pure nothrow
{
    import std.string : join;

    return tokens.emap!((t) {
        if (t.type == TokenType.func || t.type == TokenType.hash)
            return "#" ~ t.text;
        if (t.type == TokenType.number)
            return t.text;
        return null;
    }).efilter!(t => t !is null).join(',');
}

string decodeBackgroundCSS(Token[] tokens) pure nothrow
{
    import std.string : join;

    return tokens.emap!((t) {
        if (t.type == TokenType.func || t.type == TokenType.hash)
            return "#" ~ t.text;
        if (t.type == TokenType.number || t.type == TokenType.dimension ||
            t.type == TokenType.ident || t.type == TokenType.str)
            return t.text;
        return null;
    }).efilter!(t => t !is null).join(',');
}

/// Create a drawable from box-shadow property
BoxShadowDrawable decodeBoxShadowCSS(Token[] tokens)
{
    if (tokens.length < 4)
    {
        Log.fe("CSS(%s): correct form for box-shadow is: 'h-offset v-offset blur color'", tokens[0].line);
        return null;
    }

    Dimension xoffset = decodeDimensionCSS(tokens[0]);
    if (xoffset == Dimension.none)
    {
        Log.fe("CSS(%s): invalid x-offset value", tokens[0].line);
        return null;
    }
    Dimension yoffset = decodeDimensionCSS(tokens[1]);
    if (yoffset == Dimension.none)
    {
        Log.fe("CSS(%s): invalid y-offset value", tokens[1].line);
        return null;
    }
    Dimension blur = decodeDimensionCSS(tokens[2]);
    if (blur == Dimension.none)
    {
        Log.fe("CSS(%s): invalid blur value", tokens[2].line);
        return null;
    }
    uint color = decodeColorCSS(tokens[3 .. $]);

    return new BoxShadowDrawable(xoffset.toDevice, yoffset.toDevice, blur.toDevice, color);
}

FontFamily decodeFontFamilyCSS(Token[] tokens)
{
    if (tokens[0].type != TokenType.ident)
    {
        Log.fe("CSS(%s): font family should be an identifier, not '%s'", tokens[0].line, tokens[0].type);
        return FontFamily.sans_serif;
    }
    string s = tokens[0].text;
    if (s == "sans-serif")
        return FontFamily.sans_serif;
    if (s == "serif")
        return FontFamily.serif;
    if (s == "cursive")
        return FontFamily.cursive;
    if (s == "fantasy")
        return FontFamily.fantasy;
    if (s == "monospace")
        return FontFamily.monospace;
    if (s == "none")
        return FontFamily.unspecified;
    Log.fe("CSS(%s): unknown font family: %s", tokens[0].line, s);
    return FontFamily.sans_serif;
}

FontWeight decodeFontWeightCSS(Token[] tokens)
{
    auto t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): font weight should be an identifier, not '%s'", t.line, t.type);
        return FontWeight.normal;
    }
    string s = tokens[0].text;
    if (s == "bold")
        return FontWeight.bold;
    if (s == "normal")
        return FontWeight.normal;
    Log.fe("CSS(%s): unknown font weight: %s", t.line, s);
    return FontWeight.normal;
}

/// Parses CSS token sequence like "hotkeys underline-hotkeys-alt" to TextFlag bit set
TextFlag decodeTextFlagsCSS(Token[] tokens)
{
    TextFlag res;
    foreach (t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            Log.fe("CSS(%s): text flag should be an identifier, not '%s'", t.line, t.type);
            break;
        }
        switch (t.text)
        {
        case "hotkeys":
            res |= TextFlag.hotkeys;
            break;
        case "underline":
            res |= TextFlag.underline;
            break;
        case "underline-hotkeys":
            res |= TextFlag.underlineHotkeys;
            break;
        case "underline-hotkeys-on-alt":
            res |= TextFlag.underlineHotkeysOnAlt;
            break;
        case "parent":
            res |= TextFlag.parent;
            break;
        default:
            Log.fe("CSS(%s): unknown text flag: %s", t.line, t.text);
            break;
        }
    }
    return res;
}

uint decodeColorCSS(Token[] tokens)
{
    auto t = tokens[0];
    if (t.type == TokenType.hash)
        return decodeHexColor("#" ~ t.text);
    if (t.type == TokenType.ident)
        return decodeTextColor(t.text);
    if (t.type == TokenType.func)
    {
        if (tokens[$ - 1].type != TokenType.closeParen)
        {
            Log.fe("CSS(%s): expected closing parenthesis", t.line);
            return 0;
        }
        string fn = t.text;
        if (fn == "rgb" || fn == "rgba")
        {
            tokens = tokens.efilter!(t => t.type == TokenType.number);
            auto convert = (size_t idx) => tokens.length > idx ? clamp(to!uint(tokens[idx].text), 0, 255) : 0;
            uint r = convert(0);
            uint g = convert(1);
            uint b = convert(2);
            uint a = tokens.length > 3 ? opacityToAlpha(to!float(tokens[3].text)) : 0;
            return makeRGBA(r, g, b, a);
        }
        // TODO: hsl, hsla
        else
        {
            Log.fe("CSS(%s): unknown color function: %s", t.line, fn);
            return 0;
        }
    }
    return 0;
}
