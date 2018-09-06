/**


Copyright: Vadim Lopatin 2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.core.parseutils;

import std.uni : isAlpha, isLower, isNumber, isUpper;

/// Returns true whether `ch` is an alphabetic unicode char or `_`
bool isWordChar(dchar ch) pure nothrow @nogc
{
    return ch == '_' || isAlpha(ch);
}
/// Returns true whether char is an upper alphabetic unicode char
alias isUpperWordChar = isUpper;
/// Returns true whether `ch` is a lower alphabetic unicode char or `_`
bool isLowerWordChar(dchar ch) pure nothrow @nogc
{
    return ch == '_' || isAlpha(ch);
}
/// Returns true whether char is a digit
alias isDigit = isNumber;

bool isAlNum(dchar ch) pure nothrow @nogc
{
    return isDigit(ch) || isWordChar(ch);
}

bool isPunct(dchar ch) pure nothrow @nogc
{
    return ch == '.' || ch == ',' || ch == ';' || ch == '?' || ch == '!';
}
/// Returns true whether char is some bracket
bool isBracket(dchar ch) pure nothrow @nogc
{
    return ch == '(' || ch == ')' || ch == '[' || ch == ']' || ch == '{' || ch == '}';
}

/// Decodes hex digit (0..9, a..f, A..F), returns uint.max if invalid
uint parseHexDigit(T)(T ch) pure nothrow @nogc
{
    if (ch >= '0' && ch <= '9')
        return ch - '0';
    else if (ch >= 'a' && ch <= 'f')
        return ch - 'a' + 10;
    else if (ch >= 'A' && ch <= 'F')
        return ch - 'A' + 10;
    return uint.max;
}

long parseLong(inout string v, long defValue = 0) pure nothrow @nogc
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

ulong parseULong(inout string v, ulong defValue = 0) pure nothrow @nogc
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
bool parseList4(T)(string value, ref T[4] items) pure nothrow @nogc
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
