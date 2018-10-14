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

StyleSheet parseCSS(TokenRange tokens)
{
    return Parser(tokens).parseStyleSheet();
}

struct StyleSheet
{
    AtRule[] atRules;
    RuleSet[] rulesets;
}

struct AtRule
{
    string keyword;
    Token[] content;
    Property[] properties;
}

struct RuleSet
{
    Selector[] selectors;
    Property[] properties;
}

struct Selector
{
    SelectorEntry[] entries;
    size_t line;
}

struct SelectorEntry
{
    SelectorEntryType type;
    string text;
    string str;
}

enum SelectorEntryType
{
    none,
    universal,
    element,
    class_,
    id,
    pseudoClass,
    pseudoElement,
    attr,
    attrExact,
    attrInclude,
    attrDash,
    attrPrefix,
    attrSuffix,
    attrSubstring
}

struct Property
{
    string name;
    Token[] value;
}

struct Parser
{
    import std.typecons : Nullable, nullable;

    alias T = Token;

    /// Range of tokens
    TokenRange r;

    this(TokenRange tokens)
    {
        r = tokens;
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
        auto rule = AtRule(r.front.text);
        r.popFront();
        if (r.empty)
            return Nullable!AtRule.init;

        Token[] list;
        while (true) with (TokenType)
        {
            if (r.empty || r.front.type == closeCurly)
                break;
            T t = r.front;
            r.popFront();
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
            return Nullable!AtRule.init;
    }

    Nullable!RuleSet consumeQualifiedRule()
    {
        RuleSet rule;
        while (true) with (TokenType)
        {
            if (r.empty)
                return Nullable!RuleSet.init;
            if (r.front.type == openCurly)
            {
                r.popFront();
                rule.properties = consumeDeclarationList();
                return nullable(rule);
            }
            rule.selectors ~= consumeSelector();
        }
    }

    Nullable!Selector consumeSelector()
    {
        Selector sel;
        while (true) with (TokenType)
        {
            if (r.empty || r.front.type == openCurly)
                break;
            T t = r.front;
            // just assign line of the first token
            if (sel.line == 0)
                sel.line = t.line;
            r.popFront();
            if (t.type == delim) // * . ~ > +
            {
                if (t.text == "*")
                    sel.entries ~= SelectorEntry(SelectorEntryType.universal);
                else if (t.text == "." && r.front.type == ident)
                {
                    sel.entries ~= SelectorEntry(SelectorEntryType.class_, r.front.text);
                    r.popFront();
                }
            }
            else if (t.type == colon) // pseudo classes and pseudo elements
            {
                if (r.front.type == colon)
                {
                    r.popFront();
                    sel.entries ~= SelectorEntry(SelectorEntryType.pseudoElement, r.front.text);
                }
                else if (r.front.type == func && r.front.text == "not")
                {
                    r.popFront();
                    sel.entries ~= SelectorEntry(SelectorEntryType.pseudoClass, "!" ~ r.front.text);
                    r.popFront();
                    if (r.front.type != closeParen)
                        emitUnexpected(t, "selector");
                }
                else
                    sel.entries ~= SelectorEntry(SelectorEntryType.pseudoClass, r.front.text);
                r.popFront();
            }
            else if (t.type == ident)
                sel.entries ~= SelectorEntry(SelectorEntryType.element, t.text);
            else if (t.type == hash && t.typeFlagID)
                sel.entries ~= SelectorEntry(SelectorEntryType.id, t.text);
            else if (t.type == openSquare)
            {
                auto entry = consumeAttributeSelector();
                if (!entry.isNull)
                    sel.entries ~= entry.get;
            }
            else if (t.type == comma)
                break;
            else
                emitUnexpected(t, "selector");
        }
        return nullable(sel);
    }

    Nullable!SelectorEntry consumeAttributeSelector()
    {
        auto entry = SelectorEntry(SelectorEntryType.attr);
        while (true) with (TokenType)
        {
            if (r.empty)
                break;
            T t = r.front;
            if (t.type == closeSquare)
            {
                r.popFront();
                break;
            }
            if (t.type == ident || t.type == str)
            {
                if (!entry.text)
                    entry.text = t.text;
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
                return Nullable!SelectorEntry.init;
            }
            r.popFront();
        }
        if (entry.text.length == 0)
        {
            emitError("attribute selector is empty", r.line);
            return Nullable!SelectorEntry.init;
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
            T t = r.front;
            if (t.type == closeCurly)
            {
                r.popFront();
                break;
            }
            else if (t.type == ident)
            {
                auto prop = consumeDeclaration();
                if (!prop.isNull)
                    list ~= prop.get;
            }
            else
            {
                emitUnexpected(t, "block");
                r.popFront();
            }
        }
        return list;
    }

    Nullable!Property consumeDeclaration()
    {
        auto prop = Property(r.front.text);
        with (TokenType)
        {
            r.popFront();
            if (r.empty || r.front.type == closeCurly)
                return Nullable!Property.init;
            T t = r.front;
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
                    return Nullable!Property.init;
                }
            }
            else
            {
                emitUnexpected(t, "declaration");
                r.popFront();
                return Nullable!Property.init;
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
            T t = r.front;
            r.popFront();
            if (t.type == semicolon)
                break;
            else
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

        third#id::sub:not(hovered) {
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
        assert(ss[0].entries.length == 4);
        auto se = ss[0].entries;
        assert(se[0].type == SelectorEntryType.element);
        assert(se[0].text == "tag");
        assert(se[1].type == SelectorEntryType.class_);
        assert(se[1].text == "class");
        assert(se[2].type == SelectorEntryType.id);
        assert(se[2].text == "id");
        assert(se[3].type == SelectorEntryType.attrSubstring);
        assert(se[3].text == "attr");
        assert(se[3].str == "text");
        se = ss[1].entries;
        assert(se[0].type == SelectorEntryType.element);
        assert(se[0].text == "second");
        assert(se[1].type == SelectorEntryType.universal);

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
        assert(se.length == 4);
        assert(se[0].type == SelectorEntryType.element);
        assert(se[0].text == "third");
        assert(se[1].type == SelectorEntryType.id);
        assert(se[1].text == "id");
        assert(se[2].type == SelectorEntryType.pseudoElement);
        assert(se[2].text == "sub");
        assert(se[3].type == SelectorEntryType.pseudoClass);
        assert(se[3].text == "!hovered");

        ps = rs.properties;
        assert(ps.length == 1);
        assert(ps[0].name == "but");
        assert(ps[0].value.length == 2);
    }
}
