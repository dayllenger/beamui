/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.theme;

import beamui.core.config;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types : State;
import CSS = beamui.css.css;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.graphics.resources;
import beamui.style.style;
import beamui.style.selector;
import beamui.style.types : SpecialCSSType;

/// Theme - collection of widget styles, custom colors and drawables
final class Theme
{
    /// Unique name of theme
    @property string name() const { return _name; }
    /// List of all styles this theme contains
    @property Style[] allStyles() { return styleList; }
    /// List of styles this theme contains for `State.normal`
    @property Style[] normalStyles() { return styleListNormal; }

    private
    {
        string _name;
        Style[] styleList;
        Style[] styleListNormal;
        Style[Selector] styleMap;
        DrawableRef[string] drawables;
        Color[string] colors;
    }

    /// Create empty theme called `name`
    this(string name)
    {
        _name = name;
    }

    ~this()
    {
        Log.d("Destroying theme");
        eliminate(styleList);
        eliminate(styleListNormal);
        eliminate(styleMap);
        foreach (ref dr; drawables)
            dr.clear();
        destroy(drawables);
    }

    /// Get a style OR create it if it's not exist
    Style get(Selector selector)
    {
        if (auto p = selector in styleMap)
            return *p;
        else
        {
            auto st = new Style(selector);
            if ((selector.specifiedState & State.normal) == selector.enabledState)
                styleListNormal ~= st;
            styleList ~= st;
            styleMap[selector] = st;
            return st;
        }
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
    Color getColor(string name, Color defaultColor = Color.transparent) const
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
    void printStats() const
    {
        Log.fd("Theme: %s, styles: %s, drawables: %s, colors: %s", _name, styleList.length,
            drawables.length, colors.length);
    }
}

private __gshared Theme _currentTheme;
/// Current theme accessor
Theme currentTheme() { return _currentTheme; }
/// Set a new theme to be current
void currentTheme(Theme theme)
{
    eliminate(_currentTheme);
    _currentTheme = theme;
}

shared static ~this()
{
    currentTheme = null;
    defaultStyleSheet = CSS.StyleSheet.init;
    defaultIsLoaded = false;
}

private __gshared CSS.StyleSheet defaultStyleSheet;
private __gshared bool defaultIsLoaded;

/// Load theme from file, `null` if failed
Theme loadTheme(string name)
{
    if (!name.length)
        return null;

    if (!defaultIsLoaded)
    {
        version (Windows)
            string fn = `@embedded@\themes\default.css`;
        else
            string fn = `@embedded@/themes/default.css`;
        string src = cast(string)loadResourceBytes(fn);
        assert(src.length > 0);
        defaultStyleSheet = CSS.createStyleSheet(src);
        defaultIsLoaded = true;
    }
    if (name == "default")
    {
        auto theme = new Theme(name);
        loadThemeFromCSS(theme, defaultStyleSheet);
        return theme;
    }

    string id = (BACKEND_CONSOLE ? "console_" ~ name : name) ~ ".css";
    string filename = resourceList.getPathByID(id);
    if (!filename.length)
        return null;

    Log.d("Loading theme from file ", filename);
    string src = cast(string)loadResourceBytes(filename);
    if (!src.length)
        return null;

    auto theme = new Theme(name);
    const stylesheet = CSS.createStyleSheet(src);
    loadThemeFromCSS(theme, defaultStyleSheet);
    loadThemeFromCSS(theme, stylesheet);
    return theme;
}

/// Add style sheet rules from the CSS source to the theme
void setStyleSheet(Theme theme, string source)
{
    const stylesheet = CSS.createStyleSheet(source);
    loadThemeFromCSS(theme, stylesheet);
}

private void loadThemeFromCSS(Theme theme, const CSS.StyleSheet stylesheet)
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

private void importStyleSheet(Theme theme, string resourceID)
{
    if (!resourceID)
        return;
    if (!resourceID.endsWith(".css"))
        resourceID ~= ".css";
    string filename = resourceList.getPathByID(resourceID);
    if (!filename)
        return;
    string src = cast(string)loadResourceBytes(filename);
    if (!src)
        return;
    const stylesheet = CSS.createStyleSheet(src);
    loadThemeFromCSS(theme, stylesheet);
}

private void applyAtRule(Theme theme, const CSS.AtRule rule)
{
    import beamui.style.decode_css;

    const kw = rule.keyword;
    const ps = rule.properties;

    if (kw == "import")
    {
        if (rule.content.length > 0)
        {
            const t = rule.content[0];
            if (t.type == CSS.TokenType.url)
                importStyleSheet(theme, t.text);
            else
                Log.e("CSS: in @import only 'url(resource-id)' is allowed for now");
        }
        else
            Log.e("CSS: empty @import");
        if (ps.length > 0)
            Log.w("CSS: @import cannot have properties");
    }
    else if (kw == "define-colors")
    {
        foreach (p; ps)
        {
            const(CSS.Token)[] tokens = p.value;
            string id = p.name;
            if (const res = decode!Color(tokens))
                theme.setColor(id, res.val);
        }
        if (ps.length == 0)
            Log.w("CSS: empty @define-colors block");
    }
    else if (kw == "define-drawables")
    {
        foreach (p; ps)
        {
            const(CSS.Token)[] tokens = p.value;
            string id = p.name;

            // color, image, or none
            if (startsWithColor(tokens))
            {
                if (const res = decode!Color(tokens))
                    theme.setDrawable(id, new SolidFillDrawable(res.val));
            }
            else if (tokens.length > 0)
            {
                if (auto res = decode!(SpecialCSSType.image)(tokens))
                    theme.setDrawable(id, res.val);
            }
        }
        if (ps.length == 0)
            Log.w("CSS: empty @define-drawables block");
    }
    else
        Log.w("CSS: unknown at-rule keyword: ", kw);
}

private void applyRule(Theme theme, const CSS.Selector selector, const CSS.Property[] properties)
{
    auto style = selectStyle(theme, selector);
    foreach (p; properties)
    {
        assert(p.value.length > 0);
        style.setRawProperty(p.name, p.value);
    }
}

private Style selectStyle(Theme theme, const CSS.Selector selector)
{
    const(CSS.SelectorEntry)[] es = selector.entries;
    assert(es.length > 0);
    // construct selector chain
    auto sel = new Selector;
    while (true)
    {
        const combinator = constructSelector(sel, es, selector.line);
        if (!combinator.isNull)
        {
            Selector* previous = sel;
            sel = new Selector;
            sel.combinator = combinator.get;
            sel.previous = previous;
        }
        else
            break;
    }
    // find style
    return theme.get(*sel);
}

import std.typecons : Nullable, nullable;
// mutates entries
private Nullable!(Selector.Combinator) constructSelector(Selector* sel, ref const(CSS.SelectorEntry)[] entries, size_t line)
{
    Nullable!(Selector.Combinator) result;

    State specified;
    State enabled;
    // state extraction
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

    bool firstEntry = true;
    Loop: foreach (i, e; entries)
    {
        string s = e.identifier;
        switch (e.type) with (CSS.SelectorEntryType)
        {
        case universal:
            if (!firstEntry)
                Log.fw("CSS(%s): * in selector must be first", line);
            break;
        case element:
            if (firstEntry)
                sel.type = s;
            else
                Log.fw("CSS(%s): element entry in selector must be first", line);
            break;
        case id:
            if (!sel.id)
                sel.id = s;
            else
                Log.fw("CSS(%s): there can be only one id in selector", line);
            break;
        case class_:
            sel.classes ~= s;
            break;
        case pseudoElement:
            if (!sel.subitem)
                sel.subitem = s;
            else
                Log.fw("CSS(%s): there can be only one pseudo element in selector", line);
            break;
        case pseudoClass:
            if (s == "root")
            {
                sel.position = Selector.TreePosition.root;
                break;
            }
            applyStateFlag(s, "pressed", State.pressed);
            applyStateFlag(s, "focused", State.focused);
            applyStateFlag(s, "default", State.default_);
            applyStateFlag(s, "hovered", State.hovered);
            applyStateFlag(s, "selected", State.selected);
            applyStateFlag(s, "checked", State.checked);
            applyStateFlag(s, "enabled", State.enabled);
            applyStateFlag(s, "activated", State.activated);
            applyStateFlag(s, "window-focused", State.windowFocused);
            applyStateFlag(s, "read-only", State.readOnly);
            break;
        case attr:
            sel.attributes ~= Selector.Attr(s, null, Selector.Attr.Pattern.whatever);
            break;
        case attrExact:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.exact);
            break;
        case attrInclude:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.include);
            break;
        case attrDash:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.dash);
            break;
        case attrPrefix:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.prefix);
            break;
        case attrSuffix:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.suffix);
            break;
        case attrSubstring:
            sel.attributes ~= Selector.Attr(s, e.str, Selector.Attr.Pattern.substring);
            break;
        case descendant:
            result = nullable(Selector.Combinator.descendant);
            entries = entries[i + 1 .. $];
            break Loop;
        case child:
            result = nullable(Selector.Combinator.child);
            entries = entries[i + 1 .. $];
            break Loop;
        case next:
            result = nullable(Selector.Combinator.next);
            entries = entries[i + 1 .. $];
            break Loop;
        case subsequent:
            result = nullable(Selector.Combinator.subsequent);
            entries = entries[i + 1 .. $];
            break Loop;
        default:
            break;
        }
        firstEntry = false;
    }
    sel.specifiedState = specified;
    sel.enabledState = enabled;
    sel.validateAttrs();
    sel.calculateUniversality();
    sel.calculateSpecificity();
    return result;
}
