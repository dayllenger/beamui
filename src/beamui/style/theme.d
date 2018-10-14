/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.theme;

import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types : State;
import CSS = beamui.css.css;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.style.style;
import beamui.style.types : Selector, SpecialCSSType;

/// Theme - collection of widget styles, custom colors and drawables
final class Theme
{
    /// Unique name of theme
    @property string name() const { return _name; }

    /// The root of style hierarchy. Same as `theme.get(Selector())`
    @property Style root() { return defaultStyle; }

    private
    {
        struct StyleID
        {
            string name; // name of a widget or custom name
            string widgetID; // id, #id from css
            string sub; // subitem, ::pseudo-element from css
        }

        string _name;
        Style defaultStyle;
        Style[StyleID] styles;
        DrawableRef[string] drawables;
        Color[string] colors;
    }

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
        foreach (ref dr; drawables)
            dr.clear();
        destroy(drawables);
    }

    /// Returns an inheritance chain for the selector, least specific first
    Style[] selectChain(Selector selector)
    {
        Style[] result = selectChainImpl(selector);
        if (selector.state != State.normal)
        {
            // add nearest state style to the chain
            foreach_reverse (last; result)
            {
                Style st = last.forState(selector.state);
                if (st !is last)
                {
                    result ~= st;
                    break;
                }
            }
        }
        return result;
    }
    private Style[] selectChainImpl(Selector selector)
    {
        // TODO: review carefully
        TypeInfo_Class wtype = selector.widgetType;
        if (!wtype)
            return [defaultStyle];

        // get short type name
        string name = wtype.name;
        for (size_t i = name.length - 1; i >= 0; i--)
        {
            if (name[i] == '.')
            {
                name = name[i + 1 .. $];
                break;
            }
        }
        // try to find exact style
        auto p = StyleID(name, selector.id, selector.pseudoElement) in styles;

        Style[] chain;
        if (selector.id)
        {
            // SomeWidget#id::subelement -> SomeWidget::subelement
            selector.id = null;
            chain = selectChainImpl(selector);
        }
        else
        {
            // if this class is not on top of hierarhy and has no subwidgets
            if (wtype.base !is typeid(Object) && !selector.pseudoElement)
            {
                // SomeWidget -> BaseWidget
                selector.widgetType = wtype.base;
                chain = selectChainImpl(selector);
            }
            else
            {
                // SomeWidget or SomeWidget::subelement
                chain = [defaultStyle];
            }
        }
        return p ? chain ~ *p : chain;
    }

    /// Get a style OR create it if it's not exist
    Style get(Selector selector)
    {
        TypeInfo_Class wtype = selector.widgetType;
        string widgetID = selector.id;
        string sub = selector.pseudoElement;
        if (!wtype)
            return defaultStyle;

        // get short type name
        string name = wtype.name;
        for (size_t i = name.length - 1; i >= 0; i--)
        {
            if (name[i] == '.')
            {
                name = name[i + 1 .. $];
                break;
            }
        }
        // try to find exact style
        auto p = StyleID(name, widgetID, sub) in styles;
        if (!p && widgetID)
        {
            // try to find a style without widget id
            p = StyleID(name, null, sub) in styles;
        }
        if (p)
        {
            return *p;
        }
        else
        {
            // create a style
            return styles[StyleID(name, widgetID, sub)] = new Style;
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
            return styles[id] = new Style;
    }

    /// Get custom drawable
    ref DrawableRef getDrawable(string name)
    {
        if (auto p = name in drawables)
            return *p;
        else
            return _emptyDrawable;
    }
    private DrawableRef _emptyDrawable;

    /// Set custom drawable for theme
    Theme setDrawable(string name, Drawable dr)
    {
        drawables[name] = dr;
        return this;
    }

    /// Get custom color - transparent by default
    Color getColor(string name, Color defaultColor = Color.transparent)
    {
        return colors.get(name, defaultColor);
    }

    /// Set custom color for theme
    Theme setColor(string name, Color color)
    {
        colors[name] = color;
        return this;
    }

    /// Print out theme stats
    void printStats()
    {
        Log.fd("Theme: %s, styles: %s, drawables: %s, colors: %s", _name, styles.length,
            drawables.length, colors.length);
    }
}

private __gshared Theme _currentTheme;
/// Current theme accessor
@property Theme currentTheme()
{
    return _currentTheme;
}
/// Set a new theme to be current
@property void currentTheme(Theme theme)
{
    eliminate(_currentTheme);
    _currentTheme = theme;
}

shared static ~this()
{
    currentTheme = null;
}

Theme createDefaultTheme()
{
    import beamui.core.config;

    Log.d("Creating default theme");
    auto theme = new Theme("default");

    version (Windows)
    {
//         theme.root.fontFace = "Verdana";
    }
    static if (BACKEND_GUI)
    {
//         theme.root.fontSize = Dimension.pt(12);

        auto label = theme.get("Label");
        // TODO
    }
    else // console
    {
//         theme.root.fontSize = Dimension(1);
    }
    return theme;
}

/// Load theme from file, null if failed
Theme loadTheme(string name)
{
    import beamui.core.config;
    import beamui.graphics.resources;

    string filename = resourceList.getPathByID((BACKEND_CONSOLE ? "console_" ~ name : name) ~ ".css");

    if (!filename)
        return null;

    Log.d("Loading theme from file ", filename);
    string src = cast(string)loadResourceBytes(filename);
    if (!src)
        return null;

    auto theme = new Theme(name);
    auto stylesheet = CSS.createStyleSheet(src);
    loadThemeFromCSS(theme, stylesheet);
    return theme;
}

/// Add style sheet rules from the CSS source to the theme
void setStyleSheet(Theme theme, string source)
{
    auto stylesheet = CSS.createStyleSheet(source);
    loadThemeFromCSS(theme, stylesheet);
}

private void loadThemeFromCSS(Theme theme, CSS.StyleSheet stylesheet)
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

private void applyAtRule(Theme theme, CSS.AtRule rule)
{
    import beamui.style.decode_css;

    auto kw = rule.keyword;
    auto ps = rule.properties;
    assert(ps.length > 0);

    if (kw == "define-colors")
    {
        foreach (p; ps)
        {
            string id = p.name;
            Color color = void;
            if (decode(p.value, color))
                theme.setColor(id, color);
        }
    }
    else if (kw == "define-drawables")
    {
        foreach (p; ps)
        {
            CSS.Token[] tokens = p.value;
            string id = p.name;

            // color, image, or none
            if (startsWithColor(tokens))
            {
                Color color = void;
                if (decode(tokens, color))
                    theme.setDrawable(id, new SolidFillDrawable(color));
            }
            else if (tokens.length > 0)
            {
                Drawable dr = void;
                if (decode!(SpecialCSSType.image)(tokens, dr))
                    theme.setDrawable(id, dr);
            }
        }
    }
    else
        Log.w("CSS: unknown at-rule keyword: ", kw);
}

private void applyRule(Theme theme, CSS.Selector selector, CSS.Property[] properties)
{
    auto style = selectStyle(theme, selector);
    if (!style)
        return;
    foreach (p; properties)
    {
        assert(p.value.length > 0);
        style.setRawProperty(p.name, p.value);
    }
}

private Style selectStyle(Theme theme, CSS.Selector selector)
{
    auto es = selector.entries;
    assert(es.length > 0);

    if (es.length == 1 && es[0].type == CSS.SelectorEntryType.universal)
        return theme.defaultStyle;

    import std.algorithm : find;
    // find first element entry
    es = es.find!(a => a.type == CSS.SelectorEntryType.element);
    if (es.length == 0)
    {
        Log.fe("CSS(%s): there must be an element entry in selector", selector.line);
        return null;
    }
    auto hash = es.find!(a => a.type == CSS.SelectorEntryType.id);
    auto pseudoElement = es.find!(a => a.type == CSS.SelectorEntryType.pseudoElement);
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
        if (e.type == CSS.SelectorEntryType.pseudoClass)
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
