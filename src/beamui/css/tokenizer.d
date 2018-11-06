/**
CSS tokenizer.

The tokenizer follows this document: https://www.w3.org/TR/css-syntax-3

Tokenizer does not parse numbers.
cdo and cdc tokens are not included into result.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.css.tokenizer;

/// Transform a CSS source code into a token range
TokenRange tokenizeCSS(string source) pure nothrow
{
    return TokenRange(source);
}

/// Lazy input range of CSS tokens
struct TokenRange
{
    private Tokenizer* tokenizer;
    private Token _front;

pure nothrow:

    /// Construct a new token range from a source code
    this(string source)
    {
        tokenizer = new Tokenizer(preprocessInput(source));
        popFront();
    }

    /// Current token. Check for empty before get it
    @property Token front()
    {
        assert(!empty);
        return _front;
    }

    /// Go for the next token. Check for empty before this
    void popFront()
    {
        assert(!empty);
        do
        {
            _front = tokenizer.consumeToken();
        }
        while (_front.type == TokenType.cdo || _front.type == TokenType.cdc);
        _front.line = tokenizer.line;
    }

    /// Is EOF reached?
    @property bool empty() const
    {
        return _front.type == TokenType.eof;
    }

    /// Line in the source file where current token is
    @property size_t line()
    {
        return tokenizer.line;
    }
}

/// CSS token
struct Token
{
    TokenType type;
    string text;
    string dimensionUnit;
    bool typeFlagID;
    bool typeFlagInteger;
    dchar[2] unicodeRange;
    size_t line;

pure nothrow @nogc:

    this(TokenType type)
    {
        this.type = type;
    }

    this(TokenType type, string text)
    {
        this.type = type;
        this.text = text;
    }

    this(TokenType type, string repr, bool typeFlagInteger)
    {
        this.type = type;
        this.text = repr;
        this.typeFlagInteger = typeFlagInteger;
    }

    this(TokenType type, dchar unicodeStart, dchar unicodeEnd)
    {
        this.type = type;
        this.unicodeRange[0] = unicodeStart;
        this.unicodeRange[1] = unicodeEnd;
    }
}

enum TokenType
{
    ident, /// identifier
    func, /// function(
    atKeyword, /// @someKeyword - text will contain keyword w/o @ prefix
    hash, /// #
    str, /// string in '' or ""
    badStr, /// string ended with newline character
    url, /// url()
    badUrl, /// bad url()
    delim, /// delimiter (may be unknown token or error)
    number, /// +12345.324e-3
    percentage, /// 120%
    dimension, /// 1.23px - number with dimension
    unicodeRange, /// U+XXX-XXX
    includeMatch, /// ~=
    dashMatch, /// |=
    prefixMatch, /// ^=
    suffixMatch, /// $=
    substringMatch, /// *=
    column, /// ||
    whitespace, /// space, tab or newline
    cdo, /// <!--
    cdc, /// -->
    colon, /// :
    semicolon, /// ;
    comma, /// ,
    openParen, /// (
    closeParen, /// )
    openSquare, /// [
    closeSquare, /// ]
    openCurly, /// {
    closeCurly, /// }
    eof /// end of file
}

/**
Before sending the input stream to the tokenizer, implementations must make the following code point substitutions:
    * Replace any U+000D CARRIAGE RETURN (CR) code point, U+000C FORM FEED (FF) code point,
        or pairs of U+000D CARRIAGE RETURN (CR) followed by U+000A LINE FEED (LF)
        by a single U+000A LINE FEED (LF) code point.
    * Replace any U+0000 NULL code point with U+FFFD REPLACEMENT CHARACTER.
*/
private dstring preprocessInput(string src) pure nothrow
{
    import std.array : appender;
    import std.utf : byDchar;

    auto res = appender!(dchar[]);
    res.reserve(src.length / 2);
    bool wasCR;
    foreach (c; src.byDchar)
    {
        if (c == 0)
            res ~= 0xFFFD;
        else if (c == '\r' || c == '\f')
            res ~= '\n';
        else if (c == '\n' && !wasCR || c != '\n')
            res ~= c;
        wasCR = (c == '\r');
    }
    res ~= "\0\0\0"d; // append enough EOFs to not worry about it
    return cast(dstring)res.data;
}

// Here are not many comments because that document is very descriptive.
// Parsing order was slightly changed.
private struct Tokenizer
{
    import std.array : Appender;
    import std.ascii;
    import std.uni : icmp, isSurrogate;
    import std.utf : toUTF8;
    import beamui.core.parseutils : parseHexDigit;

    /// Range of characters
    dstring r;
    /// Current cursor position in the source range
    size_t i;
    /// Current line in source file
    size_t line = 1;
    /// Just a buffer for names and numbers
    Appender!(dchar[]) appender;

pure nothrow:

    this(dstring str)
    {
        r = str;
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

    static bool isNonPrintable(dchar c)
    {
        return 0 <= c && c <= 0x08 || 0x0E <= c && c <= 0x1F || c == 0x0B || c == 0x7F;
    }

    static bool isEOF(dchar c)
    {
        return c == 0;
    }

    bool startsValidEscape(dchar c1, dchar c2)
    {
        return c1 == '\\' && c2 != '\n';
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

    bool startsWithNumber()
    {
        if (r[i] == '+' || r[i] == '-')
            return isDigit(r[i + 1]) || r[i + 1] == '.' && isDigit(r[i + 2]);
        else if (r[i] == '.')
            return isDigit(r[i + 1]);
        else if (isDigit(r[i]))
            return true;
        else
            return false;
    }

    Token consumeToken()
    {
        dchar c = r[i];
        i++;

        if (isWhiteSpace(c))
        {
            if (c == '\n')
                line++;
            consumeWhiteSpace();
            return Token(TokenType.whitespace);
        }
        if (c == '"' || c == '\'')
        {
            return consumeString(c);
        }
        if (c == '#')
        {
            if (isName(r[i]) || startsValidEscape(r[i], r[i + 1]))
            {
                auto t = Token(TokenType.hash);
                if (startsWithIdent())
                    t.typeFlagID = true;
                t.text = consumeName();
                return t;
            }
            else
                return delim(c);
        }
        if (c == '+')
        {
            i--;
            if (startsWithNumber())
                return consumeNumeric();
            else
            {
                i++;
                return delim(c);
            }
        }
        if (c == '-')
        {
            i--;
            if (startsWithNumber())
                return consumeNumeric();
            else if (startsWithIdent())
                return consumeIdentLike();
            else if (r[i + 1] == '-' && r[i + 2] == '>')
            {
                i += 3;
                return Token(TokenType.cdc);
            }
            else
            {
                i++;
                return delim(c);
            }
        }
        if (c == '.')
        {
            i--;
            if (startsWithNumber())
                return consumeNumeric();
            else
            {
                i++;
                return delim(c);
            }
        }
        if (c == '/')
        {
            if (r[i] == '*')
            {
                i++;
                while (!(r[i] == '*' && r[i + 1] == '/') && !isEOF(r[i + 2]))
                {
                    if (r[i] == '\n')
                        line++;
                    i++;
                }
                i += 2;
                return consumeToken();
            }
            else
                return delim(c);
        }
        if (c == '<')
        {
            if (r[i] == '!' && r[i + 1] == '-' && r[i + 2] == '-')
            {
                i += 3;
                return Token(TokenType.cdo);
            }
            else
                return delim(c);
        }
        if (c == '@')
        {
            if (startsWithIdent())
            {
                return Token(TokenType.atKeyword, consumeName());
            }
            else
                return delim(c);
        }
        if (c == '\\')
        {
            if (startsValidEscape(r[i], r[i + 1]))
            {
                i--;
                return consumeIdentLike();
            }
            else
                return delim(c);
        }
        if (c == '~')
        {
            if (r[i] == '=')
            {
                i++;
                return Token(TokenType.includeMatch);
            }
            else
                return delim(c);
        }
        if (c == '|')
        {
            if (r[i] == '=')
            {
                i++;
                return Token(TokenType.dashMatch);
            }
            else if (r[i] == '|')
            {
                i++;
                return Token(TokenType.column);
            }
            else
                return delim(c);
        }
        if (c == '^')
        {
            if (r[i] == '=')
            {
                i++;
                return Token(TokenType.prefixMatch);
            }
            else
                return delim(c);
        }
        if (c == '$')
        {
            if (r[i] == '=')
            {
                i++;
                return Token(TokenType.suffixMatch);
            }
            else
                return delim(c);
        }
        if (c == '*')
        {
            if (r[i] == '=')
            {
                i++;
                return Token(TokenType.substringMatch);
            }
            else
                return delim(c);
        }
        if (c == ',')
            return Token(TokenType.comma);
        if (c == ':')
            return Token(TokenType.colon);
        if (c == ';')
            return Token(TokenType.semicolon);
        if (c == '(')
            return Token(TokenType.openParen);
        if (c == ')')
            return Token(TokenType.closeParen);
        if (c == '[')
            return Token(TokenType.openSquare);
        if (c == ']')
            return Token(TokenType.closeSquare);
        if (c == '{')
            return Token(TokenType.openCurly);
        if (c == '}')
            return Token(TokenType.closeCurly);
        if (isDigit(c))
        {
            i--;
            return consumeNumeric();
        }
        if (c == 'U' || c == 'u')
        {
            if (r[i] == '+' && (isHexDigit(r[i + 1]) || r[i + 1] == '?'))
            {
                i++;
                return consumeUnicodeRange();
            }
            else
            {
                i--;
                return consumeIdentLike();
            }
        }
        if (isNameStart(c))
        {
            i--;
            return consumeIdentLike();
        }
        if (isEOF(c))
            return Token(TokenType.eof);

        return delim(c);
    }

    Token delim(dchar c)
    {
        auto t = Token(TokenType.delim);
        t.text ~= c;
        return t;
    }

    void consumeWhiteSpace()
    {
        while (isWhiteSpace(r[i]))
        {
            if (r[i] == '\n')
                line++;
            i++;
        }
    }

    Token consumeString(dchar ending)
    {
        auto t = Token(TokenType.str, "");
        while (true)
        {
            dchar c = r[i];
            i++;
            if (isEOF(c) || c == ending)
                return t;
            if (c == '\n')
            {
                i--;
                return Token(TokenType.badStr);
            }
            if (c == '\\')
            {
                if (isEOF(r[i]))
                    continue;
                else if (r[i] == '\n')
                {
                    line++;
                    i++;
                }
                else if (startsValidEscape(c, r[i]))
                    t.text ~= consumeEscaped();
            }
            else
                t.text ~= c;
        }
    }

    string consumeName()
    {
        appender.clear();
        while (true)
        {
            dchar c = r[i];
            i++;
            if (isName(c))
                appender ~= c;
            else if (startsValidEscape(c, r[i]))
                appender ~= consumeEscaped();
            else
            {
                i--;
                return appender.data.toUTF8;
            }
        }
    }

    dchar consumeEscaped()
    {
        dchar c = r[i];
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
        else if (isEOF(c))
            return 0xFFFD;
        else
            return c;
    }

    Token consumeNumeric()
    {
        auto n = consumeNumber();
        if (startsWithIdent())
        {
            auto t = Token(TokenType.dimension, n.repr, n.integer);
            t.dimensionUnit = consumeName();
            return t;
        }
        else if (r[i] == '%')
        {
            i++;
            return Token(TokenType.percentage, n.repr);
        }
        else
            return Token(TokenType.number, n.repr, n.integer);
    }

    auto consumeNumber()
    {
        appender.clear();
        bool integer = true; // true - integer, false - number
        // whyever non-integer is called 'number'?
        if (r[i] == '+' || r[i] == '-')
        {
            appender ~= r[i];
            i++;
        }
        while (isDigit(r[i]))
        {
            appender ~= r[i];
            i++;
        }
        if (r[i] == '.' && isDigit(r[i + 1]))
        {
            appender ~= r[i];
            appender ~= r[i + 1];
            i += 2;
            integer = false;
            while (isDigit(r[i]))
            {
                appender ~= r[i];
                i++;
            }
        }
        if (r[i] == 'e' || r[i] == 'E')
        {
            if (isDigit(r[i + 1]) ||
                (r[i + 1] == '-' || r[i + 1] == '+') && isDigit(r[i + 2]))
            {
                appender ~= r[i];
                appender ~= r[i + 1];
                i += 2;
                integer = false;
                while (isDigit(r[i]))
                {
                    appender ~= r[i];
                    i++;
                }
            }
        }
        static struct Result
        {
            string repr;
            bool integer;
        }
        return Result(appender.data.toUTF8, integer);
    }

    Token consumeIdentLike()
    {
        string s = consumeName();
        if (s.icmp("url") == 0 && r[i] == '(')
        {
            i++;
            return consumeURL();
        }
        else if (r[i] == '(')
        {
            i++;
            return Token(TokenType.func, s);
        }
        else
            return Token(TokenType.ident, s);
    }

    Token consumeURL()
    {
        auto t = Token(TokenType.url);
        consumeWhiteSpace();
        if (isEOF(r[i]))
            return t;
        if (r[i] == '"' || r[i] == '\'')
        {
            dchar ending = r[i];
            i++;
            Token st = consumeString(ending);
            if (st.type == TokenType.badStr)
                return badUrl();
            t.text = st.text;
            consumeWhiteSpace();
            if (r[i] == ')' || isEOF(r[i]))
            {
                i++;
                return t;
            }
            else
                return badUrl();
        }
        while (true)
        {
            dchar c = r[i];
            i++;
            if (c == ')' || isEOF(c))
                return t;
            if (isWhiteSpace(c))
            {
                consumeWhiteSpace();
                if (r[i] == ')' || isEOF(r[i]))
                {
                    i++;
                    return t;
                }
                else
                    return badUrl();
            }
            if (c == '"' || c == '\'' || c == '(' || isNonPrintable(c))
                return badUrl();
            if (c == '\\')
            {
                if (startsValidEscape(c, r[i]))
                    t.text ~= consumeEscaped();
                else
                    return badUrl();
            }
            else
                t.text ~= c;
        }
    }

    Token badUrl()
    {
        // consuming remnants of a bad url
        while (true)
        {
            dchar c = r[i];
            i++;
            if (c == ')' || isEOF(c))
                break;
            if (startsValidEscape(c, r[i + 1]))
                consumeEscaped();
        }
        return Token(TokenType.badUrl);
    }

    Token consumeUnicodeRange()
    {
        dchar[6] hex;
        size_t j;
        bool questionMarks;
        for (; j < 6 && isHexDigit(r[i]); j++, i++)
            hex[j] = r[i];
        for (; j < 6 && r[i] == '?'; j++, i++)
        {
            hex[j] = '?';
            questionMarks = true;
        }
        for (; j < 6; j++)
            hex[j] = 0;
        dchar start = 0;
        dchar end = 0;
        if (questionMarks)
        {
            for (size_t k = 0; k < 6 && hex[k] != 0; k++)
            {
                start <<= 4;
                end   <<= 4;
                start |= hex[k] == '?' ? 0x0 : parseHexDigit(hex[k]);
                end   |= hex[k] == '?' ? 0xF : parseHexDigit(hex[k]);
            }
            return Token(TokenType.unicodeRange, start, end);
        }
        else
        {
            for (size_t k = 0; k < 6 && hex[k] != 0; k++)
            {
                start <<= 4;
                start |= parseHexDigit(hex[k]);
            }
        }
        if (r[i] == '-' && isHexDigit(r[i + 1]))
        {
            i++;
            for (size_t k = 0; k < 6 && isHexDigit(r[i]); k++, i++)
            {
                end <<= 4;
                end |= parseHexDigit(hex[k]);
            }
        }
        else
            end = start;

        return Token(TokenType.unicodeRange, start, end);
    }
}

unittest
{
    auto tr = Tokenizer(preprocessInput(`
        identifier-1#id[*=12345] {
            'str1' "str2"
            -moz-what: 1.23px 0.75em /* the comment */
            @keyword U+140?! -.234e+5;
            url(  'stuff.css')
            url(bad url);
            url('apparently, \
good'
)
            url( ok )
            function(120%);
            '\30 \31'
        }
    `));

    Token next() { return tr.consumeToken(); }

    assert(next == Token(TokenType.whitespace));
    assert(next == Token(TokenType.ident, "identifier-1"));
    Token t = next;
    assert(t.type == TokenType.hash);
    assert(t.text == "id");
    assert(t.typeFlagID == true);
    assert(next == Token(TokenType.openSquare));
    assert(next == Token(TokenType.substringMatch));
    assert(next == Token(TokenType.number, "12345", true));
    assert(next == Token(TokenType.closeSquare));
    assert(next == Token(TokenType.whitespace));
    assert(next == Token(TokenType.openCurly));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.str, "str1"));
    assert(next == Token(TokenType.whitespace));
    assert(next == Token(TokenType.str, "str2"));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.ident, "-moz-what"));
    assert(next == Token(TokenType.colon));
    assert(next == Token(TokenType.whitespace));
    t = next;
    assert(t.type == TokenType.dimension);
    assert(t.text == "1.23");
    assert(t.typeFlagInteger == false);
    assert(t.dimensionUnit == "px");
    assert(next == Token(TokenType.whitespace));
    t = next;
    assert(t.type == TokenType.dimension);
    assert(t.text == "0.75");
    assert(t.typeFlagInteger == false);
    assert(t.dimensionUnit == "em");
    assert(next == Token(TokenType.whitespace));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.atKeyword, "keyword"));
    assert(next == Token(TokenType.whitespace));
    assert(next == Token(TokenType.unicodeRange, 0x1400, 0x140F));
    assert(next == Token(TokenType.delim, "!"));
    assert(next == Token(TokenType.whitespace));
    assert(next == Token(TokenType.number, "-.234e+5", false));
    assert(next == Token(TokenType.semicolon));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.url, "stuff.css"));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.badUrl));
    assert(next == Token(TokenType.semicolon));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.url, "apparently, good"));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.url, "ok"));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.func, "function"));
    assert(next == Token(TokenType.percentage, "120"));
    assert(next == Token(TokenType.closeParen));
    assert(next == Token(TokenType.semicolon));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.str, "01"));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.closeCurly));
    assert(next == Token(TokenType.whitespace));

    assert(next == Token(TokenType.eof));
}
