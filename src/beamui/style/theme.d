/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.theme;

import beamui.core.config;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types : StateFlags;
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

    private
    {
        struct Store
        {
            Style[] list;
            Style[] listNormal;
            Style[Selector] map;
        }

        string _name;
        Store[string] _styles;
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
        foreach (ref store; _styles)
            eliminate(store.list);
        foreach (ref dr; drawables)
            dr.clear();
        destroy(drawables);
    }

    /// Get all styles from a specific set
    Style[] getStyles(string namespace, bool normalState)
    {
        Store* store = namespace in _styles;
        if (store)
            return normalState ? store.listNormal : store.list;
        else
            return null;
    }

    /// Get a style OR create it if it's not exist
    Style get(ref Selector selector, string namespace)
    {
        Store* store = namespace in _styles;
        if (store)
        {
            if (auto p = selector in store.map)
                return *p;
        }
        else
        {
            _styles[namespace] = Store.init;
            store = namespace in _styles;
        }
        auto st = new Style(selector);
        if ((selector.specifiedState & StateFlags.normal) == selector.enabledState)
            store.listNormal ~= st;
        store.list ~= st;
        store.map[selector] = st;
        return st;
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
        Log.fd("Theme: %s, styles: %s, drawables: %s, colors: %s", _name, 999999999, // FIXME
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
        loadThemeFromCSS(theme, defaultStyleSheet, "beamui");
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
    loadThemeFromCSS(theme, defaultStyleSheet, "beamui");
    loadThemeFromCSS(theme, stylesheet, "beamui");
    return theme;
}

/// Add style sheet rules from the CSS source to the theme
void setStyleSheet(Theme theme, string source, string namespace = "beamui")
{
    const stylesheet = CSS.createStyleSheet(source);
    loadThemeFromCSS(theme, stylesheet, namespace);
}

private void loadThemeFromCSS(Theme theme, const CSS.StyleSheet stylesheet, string ns)
    in(ns.length)
{
    foreach (r; stylesheet.atRules)
    {
        applyAtRule(theme, r, ns);
    }
    foreach (r; stylesheet.rulesets)
    {
        foreach (sel; r.selectors)
        {
            applyRule(theme, sel, r.properties, ns);
        }
    }
}

private void importStyleSheet(Theme theme, string resourceID, string ns)
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
    loadThemeFromCSS(theme, stylesheet, ns);
}

private void applyAtRule(Theme theme, const CSS.AtRule rule, string ns)
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
                importStyleSheet(theme, t.text, ns);
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

private void applyRule(Theme theme, const CSS.Selector selector, const CSS.Property[] properties, string ns)
{
    // find style
    auto style = theme.get(*makeSelector(selector), ns);
    foreach (p; properties)
    {
        assert(p.value.length > 0);
        style.setRawProperty(p.name, p.value);
    }
}

private Selector* makeSelector(const CSS.Selector selector)
{
    const(CSS.SelectorEntry)[] es = selector.entries;
    assert(es.length > 0);
    // construct selector chain
    auto sel = new Selector;
    while (true)
    {
        const combinator = makeSelectorPart(sel, es, selector.line);
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
    return sel;
}

import std.typecons : Nullable, nullable;
// mutates `entries`
private Nullable!(Selector.Combinator) makeSelectorPart(Selector* sel, ref const(CSS.SelectorEntry)[] entries, size_t line)
{
    Nullable!(Selector.Combinator) result;

    StateFlags specified;
    StateFlags enabled;
    // state extraction
    void applyStateFlag(StateFlags state, bool positive)
    {
        specified |= state;
        if (positive)
            enabled |= state;
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
            const positive = s[0] != '!';
            switch (positive ? s : s[1 .. $])
            {
            case "pressed":
                applyStateFlag(StateFlags.pressed, positive);
                break;
            case "focused":
                applyStateFlag(StateFlags.focused, positive);
                break;
            case "hovered":
                applyStateFlag(StateFlags.hovered, positive);
                break;
            case "selected":
                applyStateFlag(StateFlags.selected, positive);
                break;
            case "checked":
                applyStateFlag(StateFlags.checked, positive);
                break;
            case "enabled":
                applyStateFlag(StateFlags.enabled, positive);
                break;
            case "default":
                applyStateFlag(StateFlags.default_, positive);
                break;
            case "read-only":
                applyStateFlag(StateFlags.readOnly, positive);
                break;
            case "activated":
                applyStateFlag(StateFlags.activated, positive);
                break;
            case "focus-within":
                applyStateFlag(StateFlags.focusWithin, positive);
                break;
            case "root":
                sel.position = Selector.TreePosition.root;
                break;
            default:
            }
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
