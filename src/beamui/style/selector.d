/**

Copyright: dayllenger 2018-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.selector;

@safe:

import beamui.core.collections : Buf;
import beamui.core.types : State;

/// CSS element selector
struct Selector
{
    nothrow:

    import std.ascii : isWhite;
    import std.string : indexOf;

    /// Name of a widget or custom name
    string type;
    /// ID, `#id` from CSS
    string id;
    /// List of style classes, `.class` from CSS
    string[] classes;
    /// State that is specified as `:pseudo-class`
    State specifiedState;
    /// State that is enabled, e.g. `pressed|focused` in `:pressed:focused:not(checked)`
    State enabledState;
    /// Subitem, `::pseudo-element` from CSS
    string subitem;

    /// Tree-Structural pseudo-class, e.g. `:root` or `:first-child`
    enum TreePosition
    {
        none,
        root,
    }
    /// ditto
    TreePosition position;

    /// Attribute matcher
    struct Attr
    {
        enum Pattern
        {
            invalid,
            whatever, /// [attr]
            exact, /// [attr=value]
            include, /// [attr~=value]
            dash, /// [attr|=value]
            prefix, /// [attr^=value]
            suffix, /// [attr$=value]
            substring, /// [attr*=value]
        }
        string name;
        private string str;
        private Pattern pattern;

        bool match(string value) const
        {
            final switch (pattern) with (Pattern)
            {
            case invalid:
                return false;
            case whatever:
                return true;
            case exact:
                return str == value;
            case include:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                {
                    const i = indexOf(value, str);
                    if (i == -1)
                        return false;
                    if (i > 0 && !isWhite(value[i - 1]))
                        return false;
                    if (i + str.length < value.length && !isWhite(value[i + str.length]))
                        return false;
                    return true;
                }
                else
                    return false;
            case dash:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                    return value[str.length] == '-' && value[0 .. str.length] == str;
                else
                    return false;
            case prefix:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                    return value[0 .. str.length] == str;
                else
                    return false;
            case suffix:
                if (value.length == str.length)
                    return value == str;
                else if (value.length > str.length)
                    return value[$ - str.length .. $] == str;
                else
                    return false;
            case substring:
                return indexOf(value, str) != -1;
            }
        }
    }
    /// List of attributes, `[attr]` variations from CSS
    Attr[] attributes;

    /// Check if attribute selectors can match something
    void validateAttrs()
    {
        foreach (ref a; attributes) with (Attr.Pattern)
        {
            if (a.pattern == include)
            {
                if (a.str.length > 0)
                {
                    foreach (ch; a.str)
                    {
                        if (isWhite(ch))
                        {
                            a.pattern = invalid;
                            break;
                        }
                    }
                }
                else
                    a.pattern = invalid;
            }
            if (a.pattern == prefix || a.pattern == suffix || a.pattern == substring)
            {
                if (a.str.length == 0)
                    a.pattern = invalid;
            }
        }
    }

    /// Combinator in complex selectors
    enum Combinator
    {
        descendant,
        child,
        next,
        subsequent
    }
    /// ditto
    Combinator combinator;
    /// Points to previous selector in the complex
    Selector* previous;

    /// True if this is a universal selector without id, state, etc.
    bool universal;

    /// Compute `universal` property
    void calculateUniversality()
    {
        universal = !type & !id & !classes & !subitem & !attributes;
        universal &= (specifiedState == State.init) & (position == TreePosition.init);
    }

    /**
    Selector specificity.

    0 - the number of ID selectors,
    1 - the number of class, attribute, and tree-structural selectors,
    2 - special rating of state selectors,
    3 - the number of type selectors and pseudo-elements
    */
    uint[4] specificity;

    /// Calculate specificity of this selector
    void calculateSpecificity()
    {
        import core.bitop : popcnt; // bit count

        Selector* s = &this;
        while (s)
        {
            if (s.universal)
            {
                s = s.previous;
                continue;
            }
            if (s.id)
                specificity[0]++;
            if (s.classes)
                specificity[1] += cast(uint)s.classes.length;
            if (s.attributes)
                specificity[1] += cast(uint)s.attributes.length;
            if (s.position != TreePosition.init)
                specificity[1]++;
            State st = s.specifiedState;
            if (st != State.init)
                specificity[2] += st * st * popcnt(st);
            if (s.type)
                specificity[3]++;
            if (s.subitem)
                specificity[3]++;
            s = s.previous;
        }
    }
}

/** Parse selector from a string. Returns `null` on any error.

    Does not support comma-delimited selectors.
*/
Selector* parseSelector(string str)
{
    static Buf!dchar buf;
    if (!Preprocessor(str).process(buf))
        return null;
    return Parser(buf[]).parse();
}

private enum DELIM = '\0';

private struct Preprocessor
{
    nothrow @nogc:

    import std.ascii;
    import std.uni : isSurrogate;
    import std.utf : byDchar;
    import beamui.core.parseutils : parseHexDigit;

    private static Buf!dchar appender;
    private const(dchar)[] r;
    private size_t i;

    this(string str)
        in(!appender.length)
    {
        bool wasCR;
        foreach (c; str.byDchar)
        {
            if (c == 0)
                appender ~= 0xFFFD;
            else if (c == '\r' || c == '\f')
                appender ~= '\n';
            else if (c == '\n' && !wasCR || c != '\n')
                appender ~= c;
            wasCR = (c == '\r');
        }
        appender ~= "\0\0\0\0\0\0"d; // append enough EOFs to not worry about it
        r = appender[];
    }

    ~this()
    {
        appender.clear();
    }

    bool process(ref Buf!dchar output)
    {
        output.clear();

        while (true)
        {
            skipWhitespace();
            if (isEnd(r[i]))
                return false;
            if (!consumeCompoundSelector(output))
                return false;

            dchar c = r[i];
            const whitespace = isWhiteSpace(c);
            skipWhitespace();
            if (isEnd(r[i]))
                break;

            c = r[i];
            if (c == '>' || c == '+' || c == '~')
            {
                i++;
                output ~= c;
            }
            else if (whitespace)
                output ~= ' ';
            else
                return false;
        }
        return true;
    }

    bool consumeCompoundSelector(ref Buf!dchar output)
    {
        const start = i;
        bool hasID;
        bool hasPseudoElement;

        for (bool firstEntry = true;; firstEntry = false)
        {
            const dchar c = r[i];
            if (isEnd(c))
                break;

            if (c == '*')
            {
                if (firstEntry) // * must be the first
                {
                    i++;
                    output ~= '*';
                    continue;
                }
            }
            else if (startsWithIdent()) // tag
            {
                if (firstEntry) // element entry must be the first
                {
                    consumeIdent(output);
                    continue;
                }
            }
            else if (c == '#') // id
            {
                i++;
                if (startsWithIdent() && !hasID) // there can be only one id
                {
                    output ~= '#';
                    consumeIdent(output);
                    hasID = true;
                    continue;
                }
            }
            else if (c == '.')
            {
                i++;
                if (startsWithIdent())
                {
                    output ~= '.';
                    consumeIdent(output);
                    continue;
                }
            }
            else if (c == ':') // pseudo classes and pseudo elements
            {
                i++;
                output ~= ':';
                if (r[i] == ':')
                {
                    i++;
                    if (startsWithIdent() && !hasPseudoElement) // there can be only one pseudo-element
                    {
                        output ~= ':';
                        consumeIdent(output);
                        hasPseudoElement = true;
                        continue;
                    }
                }
                else
                {
                    const not = r[][i .. i + 4] == "not("d;
                    if (not)
                    {
                        i += 4;
                        skipWhitespace();
                        output ~= '!';
                    }
                    if (startsWithIdent())
                    {
                        consumeIdent(output);
                        if (not)
                        {
                            skipWhitespace();
                            if (r[i] == ')')
                            {
                                i++;
                                continue;
                            }
                        }
                        else
                            continue;
                    }
                }
            }
            else if (c == '[') // attribute
            {
                i++;
                output ~= '[';
                if (consumeAttributeSelector(output))
                    continue;
            }
            else // combinator or something
                break;

            return false; // failed
        }
        return i > start; // if not empty
    }

    bool consumeAttributeSelector(ref Buf!dchar output)
    {
        skipWhitespace();

        dchar c = r[i];

        if (c == '"' || c == '\'')
        {
            i++;
            if (!consumeString(c, output))
                return false;
        }
        else if (startsWithIdent())
        {
            consumeIdent(output);
        }
        else
            return false;

        skipWhitespace();

        c = r[i];
        i++;
        output ~= c;

        if (c == ']')
            return true;

        if (c != '=')
        {
            if (r[i] != '=')
                return false;
            if (c != '~' && c != '|' && c != '^' && c != '$' && c != '*')
                return false;

            i++;
        }

        skipWhitespace();

        c = r[i];
        if (c == '"' || c == '\'')
        {
            i++;
            if (!consumeString(c, output))
                return false;
        }
        else if (startsWithIdent())
        {
            consumeIdent(output);
        }
        else
            return false;

        skipWhitespace();

        if (r[i] == ']')
        {
            i++;
            output ~= ']';
            return true;
        }
        return false;
    }

    bool consumeString(dchar quote, ref Buf!dchar output)
    {
        output ~= DELIM;
        while (true)
        {
            const dchar c = r[i];
            i++;
            if (isEnd(c) || c == quote)
            {
                output ~= DELIM;
                return true;
            }
            if (c == '\n')
                return false;

            if (c == '\\')
            {
                if (isEnd(r[i]))
                    continue;
                else if (r[i] == '\n')
                    i++;
                else if (startsValidEscape(c, r[i]))
                    output ~= consumeEscaped();
            }
            else
                output ~= c;
        }
    }

    void consumeIdent(ref Buf!dchar output)
    {
        output ~= DELIM;
        while (true)
        {
            const dchar c = r[i];
            if (isName(c))
            {
                i++;
                output ~= c;
            }
            else if (startsValidEscape(c, r[i]))
            {
                i++;
                output ~= consumeEscaped();
            }
            else
            {
                output ~= DELIM;
                return;
            }
        }
    }

    dchar consumeEscaped()
    {
        const dchar c = r[i];
        i++;
        if (isHexDigit(c))
        {
            dchar hex = parseHexDigit(c);
            for (size_t j = 0; j < 5 && isHexDigit(r[i]); j++)
            {
                hex <<= 4;
                hex |= parseHexDigit(r[i]);
                i++;
            }
            if (isWhiteSpace(r[i]))
                i++;
            if (hex == 0 || isSurrogate(hex) || hex > 0x10FFFF)
                return 0xFFFD;
            return hex;
        }
        else if (isEnd(c))
            return 0xFFFD;
        else
            return c;
    }

    void skipWhitespace()
    {
        while (isWhiteSpace(r[i]))
            i++;
    }

    bool startsWithIdent()
    {
        if (r[i] == '-')
            return isNameStart(r[i + 1]) || startsValidEscape(r[i + 1], r[i + 2]);
        else if (isNameStart(r[i]))
            return true;
        else if (r[i] == '\\')
            return startsValidEscape(r[i], r[i + 1]);
        else
            return false;
    }

    static bool startsValidEscape(dchar c1, dchar c2)
    {
        return c1 == '\\' && c2 != '\n';
    }

    static bool isWhiteSpace(dchar c)
    {
        return c == ' ' || c == '\t' || c == '\n';
    }

    static bool isNameStart(dchar c)
    {
        return isAlpha(c) || c >= 0x80 || c == '_';
    }

    static bool isName(dchar c)
    {
        return isNameStart(c) || isDigit(c) || c == '-';
    }

    static bool isEnd(dchar c)
    {
        return c == 0;
    }
}

private struct Parser
{
    nothrow:

    import std.utf : toUTF8;

    private const(dchar)[] r;
    private size_t i;

    this(const(dchar)[] str)
        in(str.length)
    {
        r = str;
    }

    Selector* parse()
    {
        auto sel = new Selector;
        while (true)
        {
            if (!consumeCompoundSelector(*sel))
                return null;
            if (isEnd())
                break;

            // chain selectors
            Selector* previous = sel;
            sel = new Selector;
            sel.previous = previous;

            const dchar c = r[i];
            i++;
            if (c == ' ')
                sel.combinator = Selector.Combinator.descendant;
            else if (c == '>')
                sel.combinator = Selector.Combinator.child;
            else if (c == '+')
                sel.combinator = Selector.Combinator.next;
            else if (c == '~')
                sel.combinator = Selector.Combinator.subsequent;
        }
        return sel;
    }

    bool consumeCompoundSelector(ref Selector sel)
    {
        while (!isEnd())
        {
            const dchar c = r[i];
            if (c == DELIM) // tag
            {
                sel.type = consumeIdent();
                continue;
            }
            if (c == '*') // universal
            {
                i++;
                continue;
            }
            if (c == '#') // id
            {
                i++;
                sel.id = consumeIdent();
            }
            else if (c == '.')
            {
                i++;
                sel.classes ~= consumeIdent();
            }
            else if (c == ':') // pseudo classes and pseudo elements
            {
                i++;
                if (r[i] == ':')
                {
                    i++;
                    sel.subitem = consumeIdent();
                }
                else
                {
                    const not = r[i] == '!';
                    if (not)
                        i++;
                    const state = parseState(consumeIdentNoCopy());
                    sel.specifiedState |= state;
                    if (!not)
                        sel.enabledState |= state;
                }
            }
            else if (c == '[') // attribute
            {
                i++;
                sel.attributes ~= consumeAttributeSelector();
            }
            else // combinator
                break;
        }
        sel.validateAttrs();
        sel.calculateUniversality();
        sel.calculateSpecificity();
        return true;
    }

    static State parseState(const dchar[] str)
    {
        switch (str)
        {
            case "pressed": return State.pressed;
            case "focused": return State.focused;
            case "hovered": return State.hovered;
            case "selected": return State.selected;
            case "checked": return State.checked;
            case "enabled": return State.enabled;
            case "default": return State.default_;
            case "read-only": return State.readOnly;
            case "activated": return State.activated;
            case "window-focused": return State.windowFocused;
            default: return State.unspecified;
        }
    }

    Selector.Attr consumeAttributeSelector()
    {
        string name = consumeIdent();

        const dchar c = r[i];
        i++;

        if (c == ']')
            return Selector.Attr(name, null, Selector.Attr.Pattern.whatever);

        Selector.Attr.Pattern pattern;
        if (c == '=')
            pattern = Selector.Attr.Pattern.exact;
        else if (c == '~')
            pattern = Selector.Attr.Pattern.include;
        else if (c == '|')
            pattern = Selector.Attr.Pattern.dash;
        else if (c == '^')
            pattern = Selector.Attr.Pattern.prefix;
        else if (c == '$')
            pattern = Selector.Attr.Pattern.suffix;
        else if (c == '*')
            pattern = Selector.Attr.Pattern.substring;
        else
            assert(0);

        string value = consumeIdent();

        i++; // ]
        return Selector.Attr(name, value, pattern);
    }

    string consumeIdent()
    {
        i++;
        const s = i;
        while (r[i] != DELIM)
            i++;
        const result = toUTF8(r[s .. i]);
        i++;
        return result;
    }

    const(dchar[]) consumeIdentNoCopy()
    {
        i++;
        const s = i;
        while (r[i] != DELIM)
            i++;
        const result = r[s .. i];
        i++;
        return result;
    }

    bool isEnd() const
    {
        return i == r.length;
    }
}

//===============================================================
// Tests

unittest
{
    assert(parseSelector(`*`));
    assert(parseSelector(`a`));
    assert(parseSelector(`#a`));
    assert(parseSelector(`.a`));
    assert(parseSelector(`.a.b.c`));
    assert(parseSelector(`:a`));
    assert(parseSelector(`::a`));
    assert(parseSelector(`:not(a)`));
    assert(parseSelector(`[a]`));
    assert(parseSelector(`[a=b]`));
    assert(parseSelector(`[a|='b']`));
    assert(parseSelector(`["'a'"*='b']`));
    assert(parseSelector(`a b`));
    assert(parseSelector(`a > b`));
    assert(parseSelector(`a + b`));
    assert(parseSelector(`a ~ b`));
}

unittest
{
    assert(!parseSelector(``));
    assert(!parseSelector("\n"));
    assert(!parseSelector(`  `));
    assert(!parseSelector(`**`));
    assert(!parseSelector(`*.`));
    assert(!parseSelector(`..`));
    assert(!parseSelector(`.a*`));
    assert(!parseSelector(`!a`));
    assert(!parseSelector(`a >`));
    assert(!parseSelector(`~a`));
    assert(!parseSelector(`a >~ b`));
    assert(!parseSelector(`[a=`));
    assert(!parseSelector(`a]`));
    assert(!parseSelector(`['str"]`));
}

unittest
{
    const sel = parseSelector(`tag-1.-class__.x123#id[attr*="text"]::sub`);
    assert(sel);
    assert(!sel.previous);
    assert(sel.type == "tag-1");
    assert(sel.id == "id");
    assert(sel.classes == ["-class__", "x123"]);
    assert(sel.subitem == "sub");
    assert(sel.attributes.length == 1);
}

unittest
{
    auto sel = parseSelector(`first ~*

        third#id1:enabled:not(hovered) >fourth::sub .fifth[attr='\30 \31']
    `);
    assert(sel);
    assert(sel.classes == ["fifth"]);
    assert(sel.attributes[0] == Selector.Attr("attr", "01", Selector.Attr.Pattern.exact));
    assert(sel.combinator == Selector.Combinator.descendant);
    sel = sel.previous;
    assert(sel);
    assert(sel.type == "fourth");
    assert(sel.subitem == "sub");
    assert(sel.combinator == Selector.Combinator.child);
    sel = sel.previous;
    assert(sel);
    assert(sel.type == "third");
    assert(sel.id == "id1");
    assert(sel.specifiedState == (State.enabled | State.hovered));
    assert(sel.enabledState == State.enabled);
    assert(sel.combinator == Selector.Combinator.descendant);
    sel = sel.previous;
    assert(sel);
    assert(sel.universal);
    assert(sel.combinator == Selector.Combinator.subsequent);
    sel = sel.previous;
    assert(sel);
    assert(!sel.previous);
    assert(sel.type == "first");
}
