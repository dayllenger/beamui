/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.theme;

import beamui.core.collections : Buf;
import beamui.core.config;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.resources;
import beamui.core.types : Result, StateFlags;
import beamui.core.units : Length;
import beamui.graphics.colors : Color;
import beamui.graphics.drawables : BorderStyle, Drawable;
import beamui.layout.alignment : AlignItem, Distribution;
import beamui.style.decode_css;
import beamui.style.media;
import beamui.style.property;
import beamui.style.selector;
import beamui.style.style;
import beamui.style.types : SpecialCSSType;
import CSS = beamui.css.css;

/// Theme - a collection of widget styles
final class Theme
{
    private
    {
        struct Bag
        {
            Style[] all;
            Style[] normal;
        }

        struct Store
        {
            Bag[string] byTag;
            Style[Selector* ] map;
        }

        Store[string] _styles;

        uint[] _activeMediaQueries;
    }

    ~this()
    {
        Log.d("Destroying theme");
        foreach (ref store; _styles)
            foreach (ref bag; store.byTag)
                eliminate(bag.all);
    }

    /// Get all styles from a specific set
    Style[] getStyles(string namespace, string tag, bool normalState)
    {
        if (Store* store = namespace in _styles)
        {
            if (Bag* bag = tag in store.byTag)
                return normalState ? bag.normal : bag.all;
        }
        return null;
    }

    bool updateMediaQueries(MediaQueryInput input)
    {
        return false;
    }

    /// Print out theme stats
    void printStats() const
    {
        size_t total;
        foreach (store; _styles)
            foreach (bag; store.byTag)
                total += bag.all.length;
        Log.fd("Theme { namespaces: %d, styles: %d }", _styles.length, total);
    }
}

private __gshared Theme _currentTheme;
/// Current theme accessor
Theme currentTheme()
{
    return _currentTheme;
}
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

/// A CSS file resource ID with some additional data
struct StyleResource
{
    string resourceID;
    string namespace = "beamui";
}

Theme createDefaultTheme()
{
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
    auto ctx = Context(new Theme, "beamui");
    loadThemeFromCSS(ctx, defaultStyleSheet);
    return ctx.theme;
}

/// Append style sheet rules from CSS `resource` to `theme`
void setStyleSheetFromResource(Theme theme, StyleResource resource)
{
    import std.utf : validate, UTFException;

    if (!theme || !resource.resourceID.length)
        return;

    Log.fv("CSS: loading '%s'", resource.resourceID);

    const filename = resourceList.getPathByID(resource.resourceID);
    if (!filename.length)
        return;
    if (!filename.endsWith(".css"))
    {
        // disallow files without this extension for now
        Log.fe("CSS: not a CSS file: '%s'", filename);
        return;
    }

    const source = cast(string)loadResourceBytes(filename);
    if (!source.length)
        return;
    try
    {
        validate(source);
    }
    catch (UTFException u)
    {
        Log.fe("CSS: file '%s' contains invalid UTF-8", filename);
        return;
    }

    // TODO: cache embedded stylesheets
    auto ctx = Context(theme, resource.namespace);
    const css = CSS.createStyleSheet(source);
    loadThemeFromCSS(ctx, css);
}

private:

alias Decoder = void function(ref StylePropertyList, const(CSS.Token)[]);

struct Context
{
    Theme theme;
    string namespace;
    Decoder[string] decoders;
    Theme.Store* store;

    @disable this();
    @disable this(this);

    this(Theme theme, string namespace)
    in (theme)
    in (namespace.length)
    {
        this.theme = theme;
        this.namespace = namespace;
        decoders = createDecoders();

        store = namespace in theme._styles;
        if (!store)
        {
            theme._styles[namespace] = Theme.Store.init;
            store = namespace in theme._styles;
        }
    }

    this(ref Context ctx)
    {
        theme = ctx.theme;
        namespace = ctx.namespace;
        decoders = ctx.decoders;

        store = namespace in theme._styles;
        if (!store)
        {
            theme._styles[namespace] = Theme.Store.init;
            store = namespace in theme._styles;
        }
    }

    /// Get a style OR create it if it's not exist
    Style get(Selector* selector)
    in (selector)
    {
        Theme.Bag* bag = selector.type in store.byTag;
        if (!bag)
        {
            store.byTag[selector.type] = Theme.Bag.init;
            bag = selector.type in store.byTag;
        }

        auto st = new Style(*selector);
        if ((selector.specifiedState & StateFlags.normal) == selector.enabledState)
            bag.normal ~= st;
        bag.all ~= st;
        store.map[selector] = st;
        return st;
    }
}

void loadThemeFromCSS(ref Context ctx, const CSS.StyleSheet stylesheet)
{
    foreach (r; stylesheet.atRules)
    {
        applyAtRule(ctx, r);
    }
    foreach (r; stylesheet.rulesets)
    {
        foreach (sel; r.selectors)
        {
            auto style = ctx.get(makeSelector(sel));
            appendStyleDeclaration(style._props, ctx.decoders, r.properties);
        }
    }
}

void importStyleSheet(ref Context ctx, string resourceID)
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
    loadThemeFromCSS(ctx, stylesheet);
}

void applyAtRule(ref Context ctx, const CSS.AtRule rule)
{
    const kw = rule.keyword;
    const rs = rule.rulesets;
    const ps = rule.properties;

    if (kw == "import")
    {
        if (rule.prelude.length > 0)
        {
            const t = rule.prelude[0];
            if (t.type == CSS.TokenType.url)
                importStyleSheet(ctx, t.text);
            else
                Log.e("CSS: in @import only 'url(resource-id)' is allowed for now");
        }
        else
            Log.e("CSS: empty @import");
        if (rs.length > 0 || ps.length > 0)
            Log.w("CSS: @import cannot have non-empty block");
    }
    else if (kw == "media")
    {
        auto ctxWithMQ = Context(ctx);
        foreach (r; rs)
        {
            foreach (sel; r.selectors)
            {
                auto style = ctxWithMQ.get(makeSelector(sel));
                appendStyleDeclaration(style._props, ctxWithMQ.decoders, r.properties);
            }
        }
    }
    else
        Log.w("CSS: unknown at-rule keyword: ", kw);
}

Selector* makeSelector(const CSS.Selector selector)
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
Nullable!(Selector.Combinator) makeSelectorPart(Selector* sel, ref const(CSS.SelectorEntry)[] entries, size_t line)
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
            case "empty":
                sel.position = Selector.TreePosition.empty;
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

void appendStyleDeclaration(ref StylePropertyList list, Decoder[string] decoders, const CSS.Property[] props)
{
    foreach (p; props)
    {
        assert(p.name.length && p.value.length);
        if (isVarName(p.name))
        {
            list.customProperties[p.name] = p.value;
        }
        else if (auto pdg = p.name in decoders)
        {
            (*pdg)(list, p.value);
        }
        else
            Log.fe("CSS(%d): unknown property '%s'", p.value[0].line, p.name);
    }
}

Decoder[string] createDecoders()
{
    Decoder[string] map;

    static foreach (p; PropTypes.tupleof)
    {
        {
            enum ptype = __traits(getMember, StyleProperty, __traits(identifier, p));
            enum cssname = getCSSName(ptype);
            map[cssname] = &decodeLonghand!(ptype, typeof(p));
        }
    }

    // explode shorthands
    map["margin"] = &decodeShorthandMargin;
    map["padding"] = &decodeShorthandPadding;
    map["place-content"] = &decodeShorthandPlaceContent;
    map["place-items"] = &decodeShorthandPlaceItems;
    map["place-self"] = &decodeShorthandPlaceSelf;
    map["gap"] = &decodeShorthandGap;
    map["flex-flow"] = &decodeShorthandFlexFlow;
    map["flex"] = &decodeShorthandFlex;
    map["grid-area"] = &decodeShorthandGridArea;
    map["grid-row"] = &decodeShorthandGridRow;
    map["grid-column"] = &decodeShorthandGridColumn;
    map["background"] = &decodeShorthandDrawable;
    map["border"] = &decodeShorthandBorder;
    map["border-color"] = &decodeShorthandBorderColors;
    map["border-style"] = &decodeShorthandBorderStyle;
    map["border-width"] = &decodeShorthandBorderWidth;
    map["border-top"] = &decodeShorthandBorderTop;
    map["border-right"] = &decodeShorthandBorderRight;
    map["border-bottom"] = &decodeShorthandBorderBottom;
    map["border-left"] = &decodeShorthandBorderLeft;
    map["border-radius"] = &decodeShorthandBorderRadii;
    map["text-decoration"] = &decodeShorthandTextDecor;
    map["transition"] = &decodeShorthandTransition;

    return map;
}

alias P = StyleProperty;

void decodeLonghand(P ptype, T)(ref StylePropertyList list, const(CSS.Token)[] tokens)
in (tokens.length)
{
    if (setMeta(list, tokens, ptype))
        return;

    enum specialType = getSpecialCSSType(ptype);
    static if (specialType != SpecialCSSType.none)
        Result!T result = decode!specialType(tokens);
    else
        Result!T result = decode!T(tokens);

    if (result.err)
        return;

    if (!sanitizeProperty!ptype(result.val))
    {
        logInvalidValue(tokens);
        return;
    }

    list.set(ptype, result.val);
}

bool setMeta(ref StylePropertyList list, const CSS.Token[] tokens, P[] ps...)
{
    const t0 = tokens[0];
    if (tokens.length == 1 && t0.type == CSS.TokenType.ident)
    {
        if (t0.text == "inherit")
        {
            foreach (p; ps)
                list.inherit(p);
            return true;
        }
        if (t0.text == "initial")
        {
            foreach (p; ps)
                list.initialize(p);
            return true;
        }
    }
    else if (t0.type == CSS.TokenType.func && t0.text == "var")
    {
        if (tokens.length == 3)
        {
            if (tokens[1].type == CSS.TokenType.ident && tokens[2].type == CSS.TokenType.closeParen)
            {
                if (isVarName(tokens[1].text))
                {
                    foreach (p; ps)
                        list.setToVarName(p, tokens[1].text);
                    return true;
                }
            }
        }
        Log.fe("CSS(%d): invalid var() syntax", t0.line);
        return true;
    }
    return false;
}

void setOrInitialize(P ptype, T)(ref StylePropertyList list, const CSS.Token[] tokens, bool initial, ref T v)
{
    if (initial)
    {
        list.initialize(ptype);
        return;
    }
    if (!sanitizeProperty!ptype(v))
    {
        logInvalidValue(tokens);
        list.initialize(ptype);
        return;
    }
    list.set(ptype, v);
}

void decodeShorthandPair(T, P first, P second)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, first, second))
        return;

    if (auto res = decodePair!T(tokens))
    {
        setOrInitialize!first(list, tokens, false, res.val[0]);
        setOrInitialize!second(list, tokens, false, res.val[1]);
    }
}

void decodeShorthandInsets(P top, P right, P bottom, P left)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, top, right, bottom, left))
        return;

    auto arr = decodeInsets(tokens);
    if (arr.length > 0)
    {
        // [all], [vertical horizontal], [top horizontal bottom], [top right bottom left]
        setOrInitialize!top(list, tokens, false, arr[0]);
        setOrInitialize!right(list, tokens, false, arr[arr.length > 1 ? 1 : 0]);
        setOrInitialize!bottom(list, tokens, false, arr[arr.length > 2 ? 2 : 0]);
        setOrInitialize!left(list, tokens, false, arr[arr.length == 4 ? 3 : arr.length == 1 ? 0 : 1]);
    }
}

void decodeShorthandBorderSide(P width, P style, P color)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, width, style, color))
        return;

    if (auto res = decodeBorder(tokens))
    {
        setOrInitialize!width(list, tokens, res.val[0].err, res.val[0].val);
        setOrInitialize!style(list, tokens, false, res.val[1]);
        setOrInitialize!color(list, tokens, res.val[2].err, res.val[2].val);
    }
}

void decodeShorthandGridLine(P start, P end)(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, start, end))
        return;

    if (auto res = decodeGridArea(tokens))
    {
        const ln = res.val;
        setOrInitialize!start(list, tokens, false, ln);
        setOrInitialize!end(list, tokens, false, ln);
    }
}

void decodeShorthandMargin(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.marginTop, P.marginRight, P.marginBottom, P.marginLeft)(list, tokens);
}

void decodeShorthandPadding(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.paddingTop, P.paddingRight, P.paddingBottom, P.paddingLeft)(list, tokens);
}

void decodeShorthandPlaceContent(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(Distribution, P.alignContent, P.justifyContent)(list, tokens);
}

void decodeShorthandPlaceItems(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(AlignItem, P.alignItems, P.justifyItems)(list, tokens);
}

void decodeShorthandPlaceSelf(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(AlignItem, P.alignSelf, P.justifySelf)(list, tokens);
}

void decodeShorthandGap(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandPair!(Length, P.rowGap, P.columnGap)(list, tokens);
}

void decodeShorthandDrawable(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.bgColor, P.bgImage))
        return;

    if (auto res = decodeBackground(tokens))
    {
        Result!Color color = res.val[0];
        Result!Drawable image = res.val[1];
        setOrInitialize!(P.bgColor)(list, tokens, color.err, color.val);
        setOrInitialize!(P.bgImage)(list, tokens, image.err, image.val);
    }
}

void decodeShorthandFlexFlow(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.flexDirection, P.flexWrap))
        return;

    if (auto res = decodeFlexFlow(tokens))
    {
        setOrInitialize!(P.flexDirection)(list, tokens, res.val[0].err, res.val[0].val);
        setOrInitialize!(P.flexWrap)(list, tokens, res.val[1].err, res.val[1].val);
    }
}

void decodeShorthandFlex(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.flexGrow, P.flexShrink, P.flexBasis))
        return;

    if (auto res = decodeFlex(tokens))
    {
        setOrInitialize!(P.flexGrow)(list, tokens, false, res.val[0]);
        setOrInitialize!(P.flexShrink)(list, tokens, false, res.val[1]);
        setOrInitialize!(P.flexBasis)(list, tokens, false, res.val[2]);
    }
}

void decodeShorthandGridArea(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.gridRowStart, P.gridRowEnd, P.gridColumnStart, P.gridColumnEnd))
        return;

    if (auto res = decodeGridArea(tokens))
    {
        const ln = res.val;
        setOrInitialize!(P.gridRowStart)(list, tokens, false, ln);
        setOrInitialize!(P.gridRowEnd)(list, tokens, false, ln);
        setOrInitialize!(P.gridColumnStart)(list, tokens, false, ln);
        setOrInitialize!(P.gridColumnEnd)(list, tokens, false, ln);
    }
}

void decodeShorthandGridRow(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandGridLine!(P.gridRowStart, P.gridRowEnd)(list, tokens);
}

void decodeShorthandGridColumn(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandGridLine!(P.gridColumnStart, P.gridColumnEnd)(list, tokens);
}

void decodeShorthandBorder(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    // dfmt off
    if (setMeta(list, tokens,
            P.borderTopColor, P.borderRightColor, P.borderBottomColor, P.borderLeftColor,
            P.borderTopStyle, P.borderRightStyle, P.borderBottomStyle, P.borderLeftStyle,
            P.borderTopWidth, P.borderRightWidth, P.borderBottomWidth, P.borderLeftWidth
    ))
        return;
    // dfmt on

    if (auto res = decodeBorder(tokens))
    {
        auto wv = res.val[0].val;
        auto sv = res.val[1];
        auto cv = res.val[2].val;
        const wreset = res.val[0].err;
        const creset = res.val[2].err;
        setOrInitialize!(P.borderTopWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderTopStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderTopColor)(list, tokens, creset, cv);
        setOrInitialize!(P.borderRightWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderRightStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderRightColor)(list, tokens, creset, cv);
        setOrInitialize!(P.borderBottomWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderBottomStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderBottomColor)(list, tokens, creset, cv);
        setOrInitialize!(P.borderLeftWidth)(list, tokens, wreset, wv);
        setOrInitialize!(P.borderLeftStyle)(list, tokens, false, sv);
        setOrInitialize!(P.borderLeftColor)(list, tokens, creset, cv);
    }
}

void decodeShorthandBorderColors(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.borderTopColor, P.borderRightColor, P.borderBottomColor, P.borderLeftColor))
        return;

    if (auto res = decode!Color(tokens))
    {
        auto v = res.val;
        setOrInitialize!(P.borderTopColor)(list, tokens, false, v);
        setOrInitialize!(P.borderRightColor)(list, tokens, false, v);
        setOrInitialize!(P.borderBottomColor)(list, tokens, false, v);
        setOrInitialize!(P.borderLeftColor)(list, tokens, false, v);
    }
}

void decodeShorthandBorderStyle(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.borderTopStyle, P.borderRightStyle, P.borderBottomStyle, P.borderLeftStyle))
        return;

    if (auto res = decode!BorderStyle(tokens))
    {
        auto v = res.val;
        setOrInitialize!(P.borderTopStyle)(list, tokens, false, v);
        setOrInitialize!(P.borderRightStyle)(list, tokens, false, v);
        setOrInitialize!(P.borderBottomStyle)(list, tokens, false, v);
        setOrInitialize!(P.borderLeftStyle)(list, tokens, false, v);
    }
}

void decodeShorthandBorderWidth(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.borderTopWidth, P.borderRightWidth, P.borderBottomWidth, P.borderLeftWidth)(list, tokens);
}

void decodeShorthandBorderTop(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderTopWidth, P.borderTopStyle, P.borderTopColor)(list, tokens);
}

void decodeShorthandBorderRight(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderRightWidth, P.borderRightStyle, P.borderRightColor)(list, tokens);
}

void decodeShorthandBorderBottom(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderBottomWidth, P.borderBottomStyle, P.borderBottomColor)(list, tokens);
}

void decodeShorthandBorderLeft(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandBorderSide!(P.borderLeftWidth, P.borderLeftStyle, P.borderLeftColor)(list, tokens);
}

void decodeShorthandBorderRadii(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    decodeShorthandInsets!(P.borderTopLeftRadius, P.borderTopRightRadius, P.borderBottomLeftRadius, P
            .borderBottomRightRadius)(list, tokens);
}

void decodeShorthandTextDecor(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.textDecorLine, P.textDecorColor, P.textDecorStyle))
        return;

    if (auto res = decodeTextDecor(tokens))
    {
        auto line = res.val[0];
        auto color = res.val[1];
        auto style = res.val[2];
        setOrInitialize!(P.textDecorLine)(list, tokens, false, line);
        setOrInitialize!(P.textDecorColor)(list, tokens, color.err, color.val);
        setOrInitialize!(P.textDecorStyle)(list, tokens, style.err, style.val);
    }
}

void decodeShorthandTransition(ref StylePropertyList list, const(CSS.Token)[] tokens)
{
    if (setMeta(list, tokens, P.transitionProperty, P.transitionDuration, P.transitionTimingFunction, P.transitionDelay))
        return;

    if (auto res = decodeTransition(tokens))
    {
        auto prop = res.val[0];
        auto dur = res.val[1];
        auto tfunc = res.val[2];
        auto delay = res.val[3];
        setOrInitialize!(P.transitionProperty)(list, tokens, prop.err, prop.val);
        setOrInitialize!(P.transitionDuration)(list, tokens, dur.err, dur.val);
        setOrInitialize!(P.transitionTimingFunction)(list, tokens, tfunc.err, tfunc.val);
        setOrInitialize!(P.transitionDelay)(list, tokens, delay.err, delay.val);
    }
}
