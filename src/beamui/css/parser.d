/**
CSS parser. It takes a token sequence and produces style sheet data structure.

This parser is very simple and it has little to do with the CSS Syntax Module.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.css.parser;

import beamui.core.logger;
import beamui.css.tokenizer;

/// Transform a token range into a style sheet
StyleSheet parseCSS(TokenRange tokens)
{
    return Parser(tokens).parseStyleSheet();
}

/// Style sheet contains two lists - at-rules and qualified rules (aka rulesets)
struct StyleSheet
{
    AtRule[] atRules;
    RuleSet[] rulesets;
}

/// At-rule, looking as @keyword values { properties }
struct AtRule
{
    string keyword;
    Token[] content;
    Property[] properties;
}

/// Qualified rule - selector list (comma-separated) and set of style properties
struct RuleSet
{
    Selector[] selectors;
    Property[] properties;
}

/// Complex selector - one selector from the selector list
struct Selector
{
    SelectorEntry[] entries;
    size_t line;
}

/// Simple selector or some combinator
struct SelectorEntry
{
    SelectorEntryType type;
    string identifier;
    string str;
}

/// Type of simple selector or combinator
enum SelectorEntryType
{
    none,

    universal, /// *
    element, /// tag
    class_, /// .class
    id, /// #id
    pseudoClass, /// :pseudo-class
    pseudoElement, /// :pseudo-element
    attr, /// [attr]
    attrExact, /// [attr=value]
    attrInclude, /// [attr~=value]
    attrDash, /// [attr|=value]
    attrPrefix, /// [attr^=value]
    attrSuffix, /// [attr$=value]
    attrSubstring, /// [attr*=value]

    descendant, /// whitespace
    child, /// >
    next, /// +
    subsequent /// ~
}

/// Style property with a name and list of tokens, containing its value
struct Property
{
    string name;
    Token[] value;
}

struct Parser
{
    import std.typecons : Nullable, nullable;

    /// Range of tokens
    private TokenRange r;

    this(TokenRange tokens)
    {
        r = tokens;
    }

    void emitExpected(string what, string where, size_t line)
    {
        Log.fw("CSS(%s): expected %s in %s", line, what, where);
    }

    void emitUnexpected(Token what, string where)
    {
        Log.fw("CSS(%s): unexpected '%s' token in %s", what.line, what.type, where);
    }

    void emitError(string message, size_t line)
    {
        Log.fw("CSS(%s): %s", line, message);
    }

    StyleSheet parseStyleSheet()
    {
        AtRule[] atRules;
        RuleSet[] rulesets;
        while (true) with (TokenType)
        {
            if (r.empty)
                break;
            if (r.front.type == whitespace)
            {
                r.popFront();
                continue;
            }
            if (r.front.type == atKeyword)
            {
                auto atRule = consumeAtRule();
                if (!atRule.isNull)
                    atRules ~= atRule.get;
            }
            else
            {
                auto ruleset = consumeQualifiedRule();
                if (!ruleset.isNull)
                    rulesets ~= ruleset.get;
            }
        }
        return StyleSheet(atRules, rulesets);
    }

    Nullable!AtRule consumeAtRule()
    {
        assert(r.front.type == TokenType.atKeyword);
        enum Null = Nullable!AtRule.init;

        auto rule = AtRule(r.front.text);
        r.popFront();
        if (r.empty)
            return Null;

        Token[] list;
        while (true) with (TokenType)
        {
            if (r.empty)
                break;
            Token t = r.front;
            r.popFront();
            if (t.type == whitespace)
                continue;
            if (t.type == openCurly)
            {
                // consume block
                rule.properties = consumeDeclarationList();
                break;
            }
            if (t.type == semicolon)
                break;
            else
                // consume values
                list ~= t;
        }
        rule.content = list;

        if (rule.content.length > 0 || rule.properties.length > 0)
            return nullable(rule);
        else
            return Null;
    }

    Nullable!RuleSet consumeQualifiedRule()
    {
        enum Null = Nullable!RuleSet.init;

        RuleSet rule;
        while (true) with (TokenType)
        {
            if (r.empty)
                return Null;
            if (r.front.type != openCurly)
            {
                rule.selectors = consumeSelectorList();
            }
            else
            {
                r.popFront();
                rule.properties = consumeDeclarationList();
                return nullable(rule);
            }
        }
    }

    Selector[] consumeSelectorList()
    {
        Selector[] list;
        while (true) with (TokenType)
        {
            if (r.empty || r.front.type == openCurly)
                break;
            auto selector = consumeSelector();
            if (!selector.isNull)
                list ~= selector.get;
            if (r.front.type == comma)
            {
                do
                    r.popFront();
                while (r.front.type == whitespace);
            }
        }
        return list;
    }

    Nullable!Selector consumeSelector()
    {
        enum Null = Nullable!Selector.init;

        Selector sel;
        while (true) with (TokenType)
        {
            if (r.empty || r.front.type == comma || r.front.type == openCurly)
                break;
            // just assign line of the first token
            if (sel.line == 0)
                sel.line = r.front.line;

            sel.entries ~= consumeCompoundSelector();
            if (r.front.type == whitespace || r.front.type == delim)
            {
                auto comb = consumeCombinator();
                if (!comb.isNull)
                    sel.entries ~= comb;
            }
        }
        if (sel.entries.length > 0)
            return nullable(sel);
        else
            return Null;
    }

    SelectorEntry[] consumeCompoundSelector()
    {
        SelectorEntry[] entries;
        while (true) with (TokenType)
        {
            if (r.empty || r.front.type == whitespace || r.front.type == comma || r.front.type == openCurly)
                break;
            Token t = r.front;
            if (t.type == delim) // * .
            {
                if (t.text == "*")
                {
                    entries ~= SelectorEntry(SelectorEntryType.universal);
                    r.popFront();
                }
                else if (t.text == ".")
                {
                    r.popFront();
                    if (r.front.type == ident)
                    {
                        entries ~= SelectorEntry(SelectorEntryType.class_, r.front.text);
                        r.popFront();
                    }
                    else
                        emitExpected("identifier", "class", r.front.line);
                }
                else // combinator or something
                    break;
            }
            else if (t.type == colon) // pseudo classes and pseudo elements
            {
                r.popFront();
                if (r.front.type == colon)
                {
                    r.popFront();
                    if (r.front.type == ident)
                    {
                        entries ~= SelectorEntry(SelectorEntryType.pseudoElement, r.front.text);
                        r.popFront();
                    }
                    else
                        emitExpected("identifier", "pseudo element", r.front.line);
                }
                else if (r.front.type == func && r.front.text == "not")
                {
                    r.popFront();
                    if (!r.empty)
                    {
                        if (r.front.type == closeParen)
                            emitError("not() is empty", r.line);
                        else
                        {
                            if (r.front.type == ident)
                                entries ~= SelectorEntry(SelectorEntryType.pseudoClass, "!" ~ r.front.text);
                            else
                                emitExpected("identifier", "pseudo class", r.front.line);
                            r.popFront();
                        }
                        if (r.front.type == closeParen)
                            r.popFront();
                        else
                            emitExpected("closing parenthesis", "pseudo class", r.front.line);
                    }
                    else
                        emitUnexpected(r.front, "pseudo class");
                }
                else if (r.front.type == ident)
                {
                    entries ~= SelectorEntry(SelectorEntryType.pseudoClass, r.front.text);
                    r.popFront();
                }
                else
                    emitExpected("valid pseudo-class or pseudo-element", "selector", r.front.line);
            }
            else if (t.type == ident) // tag
            {
                entries ~= SelectorEntry(SelectorEntryType.element, t.text);
                r.popFront();
            }
            else if (t.type == hash && t.typeFlagID) // id
            {
                entries ~= SelectorEntry(SelectorEntryType.id, t.text);
                r.popFront();
            }
            else if (t.type == openSquare) // attribute
            {
                r.popFront();
                auto entry = consumeAttributeSelector();
                if (!entry.isNull)
                    entries ~= entry.get;
            }
            else
            {
                emitUnexpected(t, "selector");
                r.popFront();
                break;
            }
        }
        return entries;
    }

    Nullable!SelectorEntry consumeAttributeSelector()
    {
        enum Null = Nullable!SelectorEntry.init;

        auto entry = SelectorEntry(SelectorEntryType.attr);
        while (true) with (TokenType)
        {
            if (r.empty)
                break;
            Token t = r.front;
            if (t.type == closeSquare)
            {
                r.popFront();
                break;
            }
            if (t.type == ident || t.type == str)
            {
                if (!entry.identifier)
                    entry.identifier = t.text;
                else
                    entry.str = t.text;
            }
            else if (t.type == delim && t.text == "=")
                entry.type = SelectorEntryType.attrExact;
            else if (t.type == includeMatch)
                entry.type = SelectorEntryType.attrInclude;
            else if (t.type == dashMatch)
                entry.type = SelectorEntryType.attrDash;
            else if (t.type == prefixMatch)
                entry.type = SelectorEntryType.attrPrefix;
            else if (t.type == suffixMatch)
                entry.type = SelectorEntryType.attrSuffix;
            else if (t.type == substringMatch)
                entry.type = SelectorEntryType.attrSubstring;
            else
            {
                emitUnexpected(t, "attribute selector");
                return Null;
            }
            r.popFront();
        }
        if (entry.identifier.length == 0)
        {
            emitError("attribute selector is empty", r.line);
            return Null;
        }
        return nullable(entry);
    }

    Nullable!SelectorEntry consumeCombinator()
    {
        enum Null = Nullable!SelectorEntry.init;

        auto entry = SelectorEntry(SelectorEntryType.descendant);
        while (true) with (TokenType)
        {
            if (r.empty)
                break;
            Token t = r.front;
            if (t.type == delim) // > + ~
            {
                if (t.text == ">")
                {
                    entry.type = SelectorEntryType.child;
                }
                else if (t.text == "+")
                {
                    entry.type = SelectorEntryType.next;
                }
                else if (t.text == "~")
                {
                    entry.type = SelectorEntryType.subsequent;
                }
                else if (t.text == "*" || t.text == ".")
                    break;
                else
                {
                    emitError("unknown combinator", t.line);
                    r.popFront();
                    return Null;
                }
                r.popFront();
            }
            else if (t.type == whitespace)
                r.popFront();
            else if (t.type == comma || t.type == openCurly)
                return Null;
            else
                break;
        }
        return nullable(entry);
    }

    Property[] consumeDeclarationList()
    {
        Property[] list;
        while (true) with (TokenType)
        {
            if (r.empty)
                break;
            Token t = r.front;
            if (t.type == whitespace)
            {
                r.popFront();
                continue;
            }
            if (t.type == closeCurly)
            {
                r.popFront();
                break;
            }
            if (t.type == ident)
            {
                auto prop = consumeDeclaration();
                if (!prop.isNull)
                    list ~= prop.get;
            }
            else
            {
                emitExpected("property identifier", "block", t.line);
                r.popFront();
            }
        }
        return list;
    }

    Nullable!Property consumeDeclaration()
    {
        enum Null = Nullable!Property.init;

        auto prop = Property(r.front.text);
        with (TokenType)
        {
            r.popFront();
            if (r.empty || r.front.type == closeCurly)
                return Null;
            while (r.front.type == whitespace)
                r.popFront();
            Token t = r.front;
            if (t.type == colon)
            {
                size_t line = r.line;
                r.popFront();
                prop.value = consumeValue();
                if (prop.value.length > 0)
                    return nullable(prop);
                else
                {
                    emitError("declaration is empty", line);
                    return Null;
                }
            }
            else
            {
                emitExpected("colon", "declaration", t.line);
                r.popFront();
                return Null;
            }
        }
    }

    Token[] consumeValue()
    {
        Token[] list;
        while (true) with (TokenType)
        {
            if (r.empty || r.front.type == closeCurly)
                break;
            Token t = r.front;
            r.popFront();
            if (t.type == whitespace)
                continue;
            if (t.type == semicolon)
                break;
            list ~= t;
        }
        return list;
    }
}

unittest
{
    auto tr = tokenizeCSS(
`       @import url('secondary.css');
        @define-colors {
            fg-color: #fff000;
        }

        tag.class#id[attr*='text'], second * {
            color: #fff;
            background: linear(@fg-color, #000);
            transform: rotate(30deg);
            font-size: 120%;
        }

        third#id::sub:not(hovered) >fourth .fifth {
            'malformed': block ;


            #better to url('skip-it'),
            but: save this;
        }
        @define-drawable the-drawable 'the/path';
    `);
    auto css = parseCSS(tr);
    {
        auto rs = css.atRules;
        assert(rs[0].keyword == "import");
        assert(rs[0].content[0].type == TokenType.url);
        assert(rs[0].content[0].text == "secondary.css");
        assert(rs[1].keyword == "define-colors");
        assert(rs[1].content.length == 0);
        assert(rs[1].properties[0].name == "fg-color");
        assert(rs[1].properties[0].value[0].type == TokenType.hash);
        assert(rs[1].properties[0].value[0].text == "fff000");
        assert(rs[2].keyword == "define-drawable");
        assert(rs[2].content[0].text == "the-drawable");
        assert(rs[2].content[1].type == TokenType.str);
        assert(rs[2].content[1].text == "the/path");
    }
    {
        assert(css.rulesets.length == 2);
        auto rs = css.rulesets[0];
        assert(rs.selectors.length == 2);
        auto ss = rs.selectors;
        auto se = ss[0].entries;
        assert(se.length == 4);
        assert(se[0].type == SelectorEntryType.element);
        assert(se[0].identifier == "tag");
        assert(se[1].type == SelectorEntryType.class_);
        assert(se[1].identifier == "class");
        assert(se[2].type == SelectorEntryType.id);
        assert(se[2].identifier == "id");
        assert(se[3].type == SelectorEntryType.attrSubstring);
        assert(se[3].identifier == "attr");
        assert(se[3].str == "text");
        se = ss[1].entries;
        assert(se.length == 3);
        assert(se[0].type == SelectorEntryType.element);
        assert(se[0].identifier == "second");
        assert(se[1].type == SelectorEntryType.descendant);
        assert(se[2].type == SelectorEntryType.universal);

        auto ps = rs.properties;
        assert(ps.length == 4);
        assert(ps[0].name == "color");
        assert(ps[0].value.length == 1);
        assert(ps[1].name == "background");
        assert(ps[1].value.length == 5);
        assert(ps[2].name == "transform");
        assert(ps[2].value.length == 3);
        assert(ps[3].name == "font-size");
        assert(ps[3].value.length == 1);

        rs = css.rulesets[1];
        assert(rs.selectors.length == 1);
        se = rs.selectors[0].entries;
        assert(se.length == 8);
        assert(se[0].type == SelectorEntryType.element);
        assert(se[0].identifier == "third");
        assert(se[1].type == SelectorEntryType.id);
        assert(se[1].identifier == "id");
        assert(se[2].type == SelectorEntryType.pseudoElement);
        assert(se[2].identifier == "sub");
        assert(se[3].type == SelectorEntryType.pseudoClass);
        assert(se[3].identifier == "!hovered");
        assert(se[4].type == SelectorEntryType.child);
        assert(se[5].type == SelectorEntryType.element);
        assert(se[5].identifier == "fourth");
        assert(se[6].type == SelectorEntryType.descendant);
        assert(se[7].type == SelectorEntryType.class_);
        assert(se[7].identifier == "fifth");

        ps = rs.properties;
        assert(ps.length == 1);
        assert(ps[0].name == "but");
        assert(ps[0].value.length == 2);
    }
}
