/**


Copyright: Vadim Lopatin 2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.parseutils;

nothrow @safe:

import std.uni : isAlpha, isLower, isNumber, isUpper;

/// Returns true whether `ch` is an alphabetic unicode char or `_`
bool isWordChar(dchar ch)
{
    return ch == '_' || isAlpha(ch);
}
/// Returns true whether char is an upper alphabetic unicode char
alias isUpperWordChar = isUpper;
/// Returns true whether `ch` is a lower alphabetic unicode char or `_`
bool isLowerWordChar(dchar ch)
{
    return ch == '_' || isLower(ch);
}
/// Returns true whether char is a digit
alias isDigit = isNumber;

bool isAlNum(dchar ch)
{
    return isDigit(ch) || isWordChar(ch);
}

bool isPunct(dchar ch)
{
    return ch == '.' || ch == ',' || ch == ';' || ch == '?' || ch == '!';
}

//===============================================================
// Brackets

/// Returns true if the char is a `()[]{}` bracket
bool isBracket(dchar ch)
{
    return ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}';
}

/// Returns the paired bracket for the , if it's one of `()[]{}`, otherwise returns 0
dchar getPairedBracket(dchar ch)
{
    // dfmt off
    switch (ch)
    {
        case '(': return ')';
        case ')': return '(';
        case '{': return '}';
        case '}': return '{';
        case '[': return ']';
        case ']': return '[';
        default: return 0; // not a bracket
    }
    // dfmt on
}

/// Returns true if the char is an opening bracket
bool isOpeningBracket(dchar ch)
{
    return ch == '(' || ch == '{' || ch == '[';
}

/// Returns true if the char is a closing bracket
bool isClosingBracket(dchar ch)
{
    return ch == ')' || ch == '}' || ch == ']';
}

/// Basic stack to count matching brackets
struct BracketStack
{
nothrow:
    import beamui.core.collections : Buf;

    enum Match
    {
        continue_,
        found,
        error
    }

    private Buf!dchar buf;
    private bool reverse;

    void initialize(bool reverse)
    {
        this.reverse = reverse;
        buf.clear();
    }

    BracketStack.Match process(dchar ch)
    {
        if (reverse)
        {
            if (isClosingBracket(ch))
            {
                push(ch);
                return Match.continue_;
            }
            else
            {
                if (pop() != getPairedBracket(ch))
                    return Match.error;
                if (buf.length == 0)
                    return Match.found;
                return Match.continue_;
            }
        }
        else
        {
            if (isOpeningBracket(ch))
            {
                push(ch);
                return Match.continue_;
            }
            else
            {
                if (pop() != getPairedBracket(ch))
                    return Match.error;
                if (buf.length == 0)
                    return Match.found;
                return Match.continue_;
            }
        }
    }

    private void push(dchar ch)
    {
        buf.put(ch);
    }

    private dchar pop()
    {
        if (buf.length > 0)
        {
            const ret = buf[$ - 1];
            buf.shrink(1);
            return ret;
        }
        else
            return 0;
    }
}

//===============================================================
// Number parsing

/// Decodes hex digit (0..9, a..f, A..F), returns uint.max if invalid
uint parseHexDigit(T)(T ch)
{
    if (ch >= '0' && ch <= '9')
        return ch - '0';
    else if (ch >= 'a' && ch <= 'f')
        return ch - 'a' + 10;
    else if (ch >= 'A' && ch <= 'F')
        return ch - 'A' + 10;
    return uint.max;
}

long parseLong(inout string v, long defValue = 0)
{
    int len = cast(int)v.length;
    if (len == 0)
        return defValue;
    int sign = 1;
    long value = 0;
    int digits = 0;
    foreach (i; 0 .. len)
    {
        char ch = v[i];
        if (ch == '-')
        {
            if (i != 0)
                return defValue;
            sign = -1;
        }
        else if (ch >= '0' && ch <= '9')
        {
            digits++;
            value = value * 10 + (ch - '0');
        }
        else
        {
            return defValue;
        }
    }
    return digits > 0 ? (sign > 0 ? value : -value) : defValue;
}

ulong parseULong(inout string v, ulong defValue = 0)
{
    int len = cast(int)v.length;
    if (len == 0)
        return defValue;
    ulong value = 0;
    int digits = 0;
    foreach (i; 0 .. len)
    {
        char ch = v[i];
        if (ch >= '0' && ch <= '9')
        {
            digits++;
            value = value * 10 + (ch - '0');
        }
        else
        {
            return defValue;
        }
    }
    return digits > 0 ? value : defValue;
}

/// Parse 4 comma delimited integers
/// NOT USED
bool parseList4(T)(string value, ref T[4] items)
{
    int index = 0;
    int p = 0;
    int start = 0;
    for (; p < value.length && index < 4; p++)
    {
        while (p < value.length && value[p] != ',')
            p++;
        if (p > start)
        {
            int end = p;
            string s = value[start .. end];
            items[index++] = to!T(s);
            start = p + 1;
        }
    }
    return index == 4;
}
