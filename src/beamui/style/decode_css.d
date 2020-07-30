/**
CSS decoding functions: take token array, convert it to some type.

Each decoding function returns `Result` with value and success flag.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.decode_css;

import std.exception : assertNotThrown;
import beamui.core.animations : TimingFunction;
import beamui.core.editable : TabSize;
import beamui.core.functions;
import beamui.core.geometry : RectI, SizeI;
import beamui.core.logger : Log;
import beamui.core.types : Result, Ok, Err, Tup, tup;
import beamui.core.units;
import beamui.css.tokenizer : Token, TokenType;
import beamui.graphics.colors;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables;
import beamui.layout.alignment;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.types;
import beamui.text.fonts : GenericFontFamily, FontStyle, FontWeight;
import beamui.text.style;
import beamui.widgets.widget : CursorType;

void logInvalidValue(const Token[] tokens)
{
    assert(tokens.length > 0);

    Log.fe("CSS(%d): invalid value", tokens[0].line);
}

private void shouldbe(string what, string types, ref const Token t)
{
    Log.fe("CSS(%d): %s should be %s, not '%s'", t.line, what, types, t.type);
}

private void unknown(string what, ref const Token t)
{
    Log.fe("CSS(%d): unknown %s: %s%s", t.line, what, t.text, t.dimensionUnit);
}

private void expected(string what, ref const Token t)
{
    Log.fe("CSS(%d): expected %s, got '%s'", t.line, what, t.type);
}

private void toomany(string what, size_t line)
{
    Log.fw("CSS(%d): too many values for %s", line, what);
}

private Result!T decodeSimpleEnum(T)(const Token[] tokens, string what, const Tup!(string, T)[] map) if (is(T == enum))
{
    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        shouldbe(what, "an identifier", t);
        return Err!T;
    }
    if (tokens.length > 1)
        toomany(what, t.line);

    foreach (pair; map)
    {
        if (pair[0] == t.text)
        {
            T v = pair[1]; // remove constness
            return Ok(v);
        }
    }
    unknown(what, t);
    return Err!T;
}

private Result!(T[2]) decodeSimplePair(T)(const Token[] tokens, string what)
{
    alias E = Err!(T[2]);

    T[2] ret;
    if (tokens.length == 1)
    {
        if (const v = decode!T(tokens[0 .. 1]))
            ret[0] = ret[1] = v.val;
        else
            return E();
    }
    else
    {
        if (tokens.length > 2)
            toomany(what, tokens[0].line);

        if (const a = decode!T(tokens[0 .. 1]))
            ret[0] = a.val;
        else
            return E();

        if (const b = decode!T(tokens[1 .. 2]))
            ret[1] = b.val;
        else
            return E();
    }
    return Ok(ret);
}

/// Decode `<integer>` value
Result!int decode(T : int)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.number)
    {
        if (t.integer)
        {
            int v = assertNotThrown(to!int(t.text));
            return Ok(v);
        }
        else
        {
            Log.fe("CSS(%s): expected integer, got real", t.line);
            return Err(0);
        }
    }
    else
    {
        expected("integer", t);
        return Err(0);
    }
}

/// Decode `<number>` (real) value
Result!float decode(T : float)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.number)
    {
        float v = assertNotThrown(to!float(t.text));
        return Ok(v);
    }
    else
    {
        expected("number", t);
        return Err!float;
    }
}

/// Decode raw string property
Result!string decode(T : string)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = &tokens[0];
    if (t.type != TokenType.ident && t.type != TokenType.str)
    {
        shouldbe("string value", "an identifier or a quoted string", *t);
        return Err!string;
    }
    return Ok(t.text);
}

/// Decode CSS token sequence like 'left vcenter' to `Align` bit set
Result!Align decode(T : Align)(const Token[] tokens)
{
    assert(tokens.length > 0);

    Align result;
    foreach (ref t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            shouldbe("alignment", "an identifier", t);
            return Err!Align;
        }
        // dfmt off
        switch (t.text) with (Align)
        {
            case "center":   result |= center; break;
            case "left":     result |= left; break;
            case "right":    result |= right; break;
            case "top":      result |= top; break;
            case "bottom":   result |= bottom; break;
            case "hcenter":  result |= hcenter; break;
            case "vcenter":  result |= vcenter; break;
            case "top-left": result |= topleft; break;
            default:
                unknown("alignment", t);
                return Err!Align;
        }
        // dfmt on
    }
    return Ok(result);
}

/// Decode stretch property
Result!Stretch decode(T : Stretch)(const Token[] tokens)
{
    with (Stretch)
    {
        // dfmt off
        immutable map = [
            tup("main", main),
            tup("cross", cross),
            tup("both", both),
            tup("none", none),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "stretch", map);
    }
}

/// Decode item alignment property
Result!AlignItem decode(T : AlignItem)(const Token[] tokens)
{
    with (AlignItem)
    {
        // dfmt off
        immutable map = [
            tup("auto", unspecified),
            tup("stretch", stretch),
            tup("start", start),
            tup("end", end),
            tup("center", center),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "item alignment", map);
    }
}

/// Decode content distribution property
Result!Distribution decode(T : Distribution)(const Token[] tokens)
{
    with (Distribution)
    {
        // dfmt off
        immutable map = [
            tup("stretch", stretch),
            tup("start", start),
            tup("end", end),
            tup("center", center),
            tup("space-between", spaceBetween),
            tup("space-around", spaceAround),
            tup("space-evenly", spaceEvenly),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "distribution", map);
    }
}

/// Decode item alignment pair
Result!(AlignItem[2]) decodePair(T : AlignItem)(const Token[] tokens)
{
    return decodeSimplePair!AlignItem(tokens, "alignment pair");
}

/// Decode content distribution pair
Result!(Distribution[2]) decodePair(T : Distribution)(const Token[] tokens)
{
    return decodeSimplePair!Distribution(tokens, "distribution pair");
}

/// Decode CSS rectangle declaration to `Length[]`
Length[] decodeInsets(const Token[] tokens)
{
    assert(tokens.length > 0);

    if (tokens.length > 4)
    {
        toomany("rectangle", tokens[0].line);
        return null;
    }

    Length[] list;
    list.reserve(4);
    foreach (i; 0 .. tokens.length)
    {
        if (const len = decode!Length(tokens[i .. i + 1]))
            list ~= len.val;
        else
            return null;
    }
    return list;
}

/// Decode CSS length pair, e.g. `gap` property
Result!(Length[2]) decodePair(T : Length)(const Token[] tokens)
{
    return decodeSimplePair!Length(tokens, "length pair");
}

/// Decode dimension, e.g. 1px, 20%, 1.2em, or 'none'
Result!Length decode(T : Length)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        if (t.text == "auto" || t.text == "none")
            return Ok(Length.none);
        else
            unknown("length identifier", t);
    }
    else if (t.type == TokenType.number)
    {
        if (t.text == "0")
            return Ok(Length.zero);
        else
            Log.fe("CSS(%s): length units are mandatory", t.line);
    }
    else if (t.type == TokenType.dimension)
    {
        auto result = Length.parse(t.text, t.dimensionUnit);
        if (result != Length.none)
            return Ok(result);
        else
            Log.fe("CSS(%s): can't parse length", t.line);
    }
    else if (t.type == TokenType.percentage)
    {
        auto result = Length.parse(t.text, "%");
        if (result != Length.none)
            return Ok(result);
        else
            Log.fe("CSS(%s): can't parse percent", t.line);
    }
    else
        Log.fe("CSS(%s): invalid length: '%s'", t.line, t.type);

    return Err!Length;
}

/// Decode z-index value (an integer or `auto`)
Result!int decode(SpecialCSSType t : SpecialCSSType.zIndex)(const Token[] tokens)
{
    assert(tokens.length > 0);

    if (tokens[0].type == TokenType.ident)
    {
        if (tokens[0].text != "auto")
        {
            unknown("z-index identifier", tokens[0]);
            return Err(0);
        }
        return Ok(int.min);
    }
    else
        return decode!int(tokens);
}

/// Decode flexbox direction property
Result!FlexDirection decode(T : FlexDirection)(const Token[] tokens)
{
    with (FlexDirection)
    {
        // dfmt off
        immutable map = [
            tup("row", row),
            tup("row-reverse", rowReverse),
            tup("column", column),
            tup("column-reverse", columnReverse),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "flex direction", map);
    }
}

/// Decode flexbox wrap property
Result!FlexWrap decode(T : FlexWrap)(const Token[] tokens)
{
    with (FlexWrap)
    {
        // dfmt off
        immutable map = [
            tup("nowrap", off),
            tup("wrap", on),
            tup("wrap-reverse", reverse),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "flex wrap", map);
    }
}

alias FlexFlowHere = Tup!(Result!FlexDirection, Result!FlexWrap);
alias FlexHere = Tup!(float, float, Length);
/// Decode shorthand flex-flow property
Result!FlexFlowHere decodeFlexFlow(const Token[] tokens)
{
    assert(tokens.length > 0);

    FlexFlowHere result;

    if (isFlexDirection(tokens[0]))
        result[0] = decode!FlexDirection(tokens[0 .. 1]);
    else
        result[1] = decode!FlexWrap(tokens[0 .. 1]);

    if (tokens.length > 1)
    {
        if (isFlexWrap(tokens[1]))
            result[1] = decode!FlexWrap(tokens[1 .. 2]);
        else
            result[0] = decode!FlexDirection(tokens[1 .. 2]);
    }

    if (result[0] || result[1])
    {
        if (tokens.length > 2)
            toomany("flex-flow", tokens[0].line);
        return Ok(result);
    }
    else
    {
        Log.fe("CSS(%s): malformed flex-flow shorthand", tokens[0].line);
        return Err!FlexFlowHere();
    }
}
/// Decode shorthand flex property
Result!FlexHere decodeFlex(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    alias E = Err!FlexHere;

    const t0 = tokens[0];
    if (tokens.length == 1)
    {
        if (t0.type == TokenType.ident)
        {
            if (t0.text == "auto")
                return Ok(FlexHere(1, 1, Length.none));
            if (t0.text == "none")
                return Ok(FlexHere(0, 0, Length.none));
        }
        if (t0.type == TokenType.number)
        {
            const grow = decode!float(tokens).val;
            return Ok(FlexHere(grow, 1, Length.zero));
        }
        unknown("flex", t0);
    }
    else if (tokens.length == 3)
    {
        if (t0.type == TokenType.number && tokens[1].type == TokenType.number)
        {
            if (startsWithLength(tokens[2 .. 3]))
            {
                const grow = decode!float(tokens[0 .. 1]).val;
                const shrink = decode!float(tokens[1 .. 2]).val;
                const basis = decode!Length(tokens[2 .. 3]).val;
                return Ok(FlexHere(grow, shrink, basis));
            }
        }
        unknown("flex", t0);
    }
    else
        toomany("flex", t0.line);

    return E();
}

/// Decode grid automatic flow property
Result!GridFlow decode(T : GridFlow)(const Token[] tokens)
{
    with (GridFlow)
    {
        // dfmt off
        immutable map = [
            tup("row", row),
            tup("column", column),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "grid flow", map);
    }
}

/// Decode grid tracks size, e.g. 50px, 20%, 1fr, 'min-content', 'max-content', `auto`
Result!TrackSize decode(T : TrackSize)(const Token[] tokens)
{
    assert(tokens.length > 0);

    // it's simpler to check for invalid lengths here
    const t0 = tokens[0];
    if (t0.type == TokenType.ident)
    {
        if (t0.text == "auto")
            return Ok(TrackSize.automatic);
        if (t0.text == "min-content")
            return Ok(TrackSize.minContent);
        if (t0.text == "max-content")
            return Ok(TrackSize.maxContent);
    }
    else if (t0.type == TokenType.dimension && t0.dimensionUnit == "fr")
    {
        const fr = assertNotThrown(to!float(t0.text));
        if (fr < 0)
        {
            Log.fe("CSS(%s): fraction cannot be negative", t0.line);
            return Err!TrackSize;
        }
        return Ok(TrackSize.fromFraction(fr));
    }
    else if (startsWithLength(tokens))
    {
        if (const len = decode!Length(tokens))
        {
            const v = len.val;
            if (v.toLayout.applyPercent(100) >= 0)
                return Ok(TrackSize.fromLength(v));
        }
        Log.fe("CSS(%s): bad track size", t0.line);
        return Err!TrackSize;
    }

    unknown("track size", t0);
    return Err!TrackSize;
}

/// Decode grid row or column template sizes
Result!(TrackSize[]) decode(T : TrackSize[])(const Token[] tokens)
{
    assert(tokens.length > 0);

    if (tokens[0].type == TokenType.ident && tokens[0].text == "none")
    {
        if (tokens.length > 1)
            toomany("grid template", tokens[0].line);
        return Ok!(TrackSize[])(null);
    }

    TrackSize[] list = new TrackSize[tokens.length];
    foreach (i; 0 .. tokens.length)
    {
        if (const sz = decode!TrackSize(tokens[i .. i + 1]))
            list[i] = sz.val;
        else
            return Err!(TrackSize[]);
    }
    return Ok(list);
}

/// Decode grid template with area names
Result!GridNamedAreas decode(T : GridNamedAreas)(const Token[] tokens)
{
    assert(tokens.length > 0);

    alias E = Err!GridNamedAreas;

    if (tokens[0].type == TokenType.ident && tokens[0].text == "none")
    {
        if (tokens.length > 1)
            toomany("grid template", tokens[0].line);
        return Ok(GridNamedAreas.init);
    }

    RectI[string] map;
    size_t columns;
    foreach (i, ref tok; tokens)
    {
        if (tok.type == TokenType.str)
        {
            auto row = parseGridTemplateString(tok.text);
            if (!row.length)
            {
                Log.fe("CSS(%d): grid row is empty or malformed", tok.line);
                return E();
            }
            if (columns != row.length)
            {
                if (columns > 0)
                {
                    Log.fe("CSS(%d): grid must be rectangular", tok.line);
                    return E();
                }
                columns = row.length;
            }
            if (!appendGridRow(row, i, map))
            {
                Log.fe("CSS(%d): grid areas must be rectangular", tok.line);
                return E();
            }
        }
        else
        {
            expected("a quoted string", tok);
            return E();
        }
    }
    return Ok(GridNamedAreas(SizeI(cast(int)columns, cast(int)tokens.length), map));
}

private string[] parseGridTemplateString(string txt)
{
    import std.ascii : isAlpha, isDigit, isWhite;
    import std.uni : byCodePoint;

    enum State
    {
        outside,
        name,
        dots,
    }

    State state;

    string[] row;
    string cell;
    foreach (dchar c; byCodePoint(txt))
    {
        if (isAlpha(c) || c >= 0x80 || c == '_') // name start
        {
            if (state == State.dots)
                row ~= cell;
            cell ~= c;
            state = State.name;
        }
        else if (isDigit(c) || c == '-') // inside a name only
        {
            if (state == State.name)
                cell ~= c;
            else
                return null;
        }
        else if (c == '.') // empty cell
        {
            if (state == State.name)
            {
                row ~= cell;
                cell = null;
            }
            state = State.dots;
        }
        else if (isWhite(c)) // delimiters
        {
            if (state != State.outside)
            {
                row ~= cell;
                cell = null;
                state = State.outside;
            }
        }
        else // trash tokens
            return null;
    }
    if (state != State.outside)
        row ~= cell;
    return row;
}

private bool appendGridRow(string[] row, size_t i, ref RectI[string] areas)
in (row.length)
{
    const y = cast(int)i;
    string prev;
    int left, right;

    bool add()
    {
        if (!prev.length) // empty cells don't create a named area
            return true;
        if (RectI* rc = prev in areas)
        {
            assert(rc.bottom <= y);
            // 1. disconnected by vertical axis
            if (rc.bottom < y)
                return false;
            // 2. disconnected by horizontal axis
            if (rc.left != left || rc.right != right)
                return false;
            // 3. fits
            rc.bottom++;
        }
        else // not added yet
        {
            areas[prev] = RectI(left, y, right, y + 1);
        }
        return true;
    }

    foreach (j, curr; row)
    {
        if (curr == prev)
        {
            right++;
            continue;
        }
        if (add())
        {
            left = cast(int)j;
            right = left + 1;
            prev = curr;
        }
        else
            return false;
    }
    // add the last cells
    assert(left < right);
    return add();
}

/// Decode grid line name, e.g. 1, 'span 3', 'header', `auto`
Result!GridLineName decode(T : GridLineName)(const Token[] tokens)
{
    assert(tokens.length > 0);

    alias E = Err!GridLineName;
    const what = "grid line";

    bool span;
    Token t = tokens[0];
    if (t.type == TokenType.ident)
    {
        if (t.text == "span")
        {
            if (tokens.length > 1)
            {
                span = true;
                t = tokens[1];
            }
            else
            {
                Log.fe("CSS(%s): grid line or area can't have name 'span'", t.line);
                return E();
            }
        }
        else
        {
            if (tokens.length > 1)
                toomany(what, t.line);

            if (t.text != "auto")
                return Ok(GridLineName(t.text));
            else
                return Ok(GridLineName.init);
        }
    }
    if (!span && tokens.length > 1 || tokens.length > 2)
        toomany(what, t.line);

    if (t.type == TokenType.number && t.integer)
    {
        const i = assertNotThrown(to!int(t.text));
        if (i <= 0 || i >= 10_000)
        {
            if (span)
            {
                Log.fe("CSS(%d): invalid grid span: %d", t.line, i);
                return E();
            }
            if (i < 0)
            {
                Log.fe("CSS(%d): negative grid line numbers aren't supported", t.line);
                return E();
            }
            else
            {
                Log.fe("CSS(%d): invalid grid line number: %d", t.line, i);
                return E();
            }
        }
        return Ok(GridLineName(span, i));
    }
    else if (!span)
        expected("integer or identifier", t);
    else
        expected("integer", t);

    return E();
}

/// Decode grid area name, that expands to two or four grid line names
Result!GridLineName decodeGridArea(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        if (t.text != "auto")
            return Ok(GridLineName(t.text));
        else
            return Ok(GridLineName.init);
    }
    else
    {
        shouldbe("grid area name", "an identifier", t);
        return Err!GridLineName;
    }
}

//===============================================================
// Background, border, and box shadow

alias BackgroundHere = Tup!(Result!Color, Result!Drawable);
/// Decode shorthand background property
Result!BackgroundHere decodeBackground(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const line = tokens[0].line;
    alias E = Err!BackgroundHere;
    BackgroundHere result;

    if (startsWithColor(tokens))
    {
        if (const res = decode!Color(tokens))
            result[0] = res;
        else
            return E();
    }
    if (startsWithImage(tokens))
    {
        if (auto res = decode!(SpecialCSSType.image)(tokens))
            result[1] = res;
        else
            return E();
    }

    if (result[0] || result[1])
    {
        if (tokens.length > 0)
            toomany("background", line);
        return Ok(result);
    }
    else
    {
        Log.fe("CSS(%s): malformed background shorthand", line);
        return E();
    }
}

/// Decode background image. This function mutates the range - skips found values
Result!Drawable decode(SpecialCSSType t : SpecialCSSType.image)(ref const(Token)[] tokens)
{
    assert(tokens.length > 0);

    import beamui.core.config : BACKEND_GUI;
    import beamui.graphics.bitmap : Bitmap;

    const t0 = tokens[0];
    // #0: none
    if (t0.type == TokenType.ident)
    {
        if (t0.text == "none")
            return Ok!Drawable(null);
        else
        {
            unknown("image identifier", t0);
            return Err!Drawable;
        }
    }
    // #1: image id
    if (t0.type == TokenType.url)
    {
        tokens = tokens[1 .. $];
        static if (BACKEND_GUI)
        {
            string id = t0.text;
            bool tiled;
            if (id.endsWith(".tiled"))
            {
                id = id[0 .. $ - 6]; // remove .tiled
                tiled = true;
            }
            // PNG/JPEG image
            if (Bitmap bm = imageCache.get(id))
                return Ok!Drawable(new ImageDrawable(bm, tiled));
        }
        return Err!Drawable;
    }
    // #2: gradient
    if (t0.type == TokenType.func && t0.text == "linear")
    {
        import std.math : isNaN;

        float angle;
        if (tokens[1].type == TokenType.dimension)
        {
            angle = parseAngle(tokens[1].text, tokens[1].dimensionUnit);
        }
        if (isNaN(angle))
        {
            Log.fe("CSS(%s): 1st linear gradient parameter should be angle (deg, grad, rad or turn)", tokens[1].line);
            return Err!Drawable;
        }
        else
            tokens = tokens[2 .. $];

        if (tokens[0].type == TokenType.comma)
            tokens = tokens[1 .. $];

        const color1 = decode!Color(tokens);
        if (color1.err)
            return Err!Drawable;

        if (tokens[0].type == TokenType.comma)
            tokens = tokens[1 .. $];

        const color2 = decode!Color(tokens);
        if (color2.err)
            return Err!Drawable;

        if (tokens[0].type == TokenType.closeParen)
            tokens = tokens[1 .. $];

        return Ok!Drawable(new GradientDrawable(angle, color1.val, color2.val));
    }
    return Err!Drawable;
}

/// Decode background position property
Result!BgPositionRaw decode(T : BgPositionRaw)(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const what = "background position";
    BgPositionRaw ret;
    if (tokens.length == 1)
    {
        const t = tokens[0];
        ret.x = ret.y = Length.percent(50); // another value should be 'center'
        if (t.type == TokenType.ident)
        {
            // dfmt off
            switch (t.text)
            {
                case "center": break;
                case "left":   ret.x = Length.percent(0);   break;
                case "right":  ret.x = Length.percent(100); break;
                case "top":    ret.y = Length.percent(0);   break;
                case "bottom": ret.y = Length.percent(100); break;
                default:
                    unknown(what, t);
                    return Err!BgPositionRaw;
            }
            // dfmt on
        }
        else
        {
            const x = decode!Length(tokens[0 .. 1]);
            if (x)
                ret.x = x.val;
            else
                return Err!BgPositionRaw;
        }
    }
    else
    {
        const t1 = tokens[0];
        const t2 = tokens[1];
        if (tokens.length > 2)
            toomany(what, t1.line);

        if (t1.type == TokenType.ident)
        {
            // dfmt off
            switch (t1.text)
            {
                case "center":ret.x = Length.percent(50);  break;
                case "left":  ret.x = Length.percent(0);   break;
                case "right": ret.x = Length.percent(100); break;
                default:
                    unknown(what, t1);
                    return Err!BgPositionRaw;
            }
            // dfmt on
        }
        else
        {
            const x = decode!Length(tokens[0 .. 1]);
            if (x)
                ret.x = x.val;
            else
                return Err!BgPositionRaw;
        }
        if (t2.type == TokenType.ident)
        {
            // dfmt off
            switch (t2.text)
            {
                case "center": ret.y = Length.percent(50);  break;
                case "top":    ret.y = Length.percent(0);   break;
                case "bottom": ret.y = Length.percent(100); break;
                default:
                    unknown(what, t2);
                    return Err!BgPositionRaw;
            }
            // dfmt on
        }
        else
        {
            const y = decode!Length(tokens[1 .. 2]);
            if (y)
                ret.y = y.val;
            else
                return Err!BgPositionRaw;
        }
    }
    return Ok(ret);
}

/// Decode background size property
Result!BgSizeRaw decode(T : BgSizeRaw)(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const what = "background size";
    BgSizeRaw ret;
    if (tokens.length == 1)
    {
        const t = tokens[0];
        if (t.type == TokenType.ident)
        {
            // dfmt off
            switch (t.text)
            {
                case "auto": break;
                case "contain": ret.type = BgSizeType.contain; break;
                case "cover":   ret.type = BgSizeType.cover;   break;
                default:
                    unknown(what, t);
                    return Err!BgSizeRaw;
            }
            // dfmt on
        }
        else
        {
            const x = decode!Length(tokens[0 .. 1]);
            if (x)
                ret.x = x.val;
            else
                return Err!BgSizeRaw;
        }
    }
    else
    {
        const t1 = tokens[0];
        const t2 = tokens[1];
        if (tokens.length > 2)
            toomany(what, t1.line);

        if (t1.type != TokenType.ident || t1.text != "auto")
        {
            const x = decode!Length(tokens[0 .. 1]);
            if (x)
                ret.x = x.val;
            else
                return Err!BgSizeRaw;
        }
        if (t2.type != TokenType.ident || t2.text != "auto")
        {
            const y = decode!Length(tokens[1 .. 2]);
            if (y)
                ret.y = y.val;
            else
                return Err!BgSizeRaw;
        }
    }
    return Ok(ret);
}

/// Decode background/image repeat property
Result!RepeatStyle decode(T : RepeatStyle)(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    auto ret = RepeatStyle(Tiling.none, Tiling.none);
    if (tokens.length == 1)
    {
        const t = tokens[0];
        if (t.type == TokenType.ident)
        {
            if (t.text == "repeat-x")
            {
                ret.x = Tiling.repeat;
                return Ok(ret);
            }
            if (t.text == "repeat-y")
            {
                ret.y = Tiling.repeat;
                return Ok(ret);
            }
        }
        const both = decodeTiling(t);
        if (both)
        {
            ret.x = both.val;
            ret.y = both.val;
            return Ok(ret);
        }
    }
    else
    {
        if (tokens.length > 2)
            toomany("repeat style", tokens[0].line);
        const x = decodeTiling(tokens[0]);
        const y = decodeTiling(tokens[1]);
        if (x && y)
        {
            ret.x = x.val;
            ret.y = y.val;
            return Ok(ret);
        }
    }
    return Err!RepeatStyle;
}

private Result!Tiling decodeTiling(ref const Token t)
{
    if (t.type != TokenType.ident)
    {
        shouldbe("repeat style", "an identifier", t);
        return Err!Tiling;
    }
    // dfmt off
    switch (t.text) with (Tiling)
    {
        case "repeat":    return Ok(repeat);
        case "no-repeat": return Ok(none);
        case "space": return Ok(space);
        case "round": return Ok(round);
        default:
            unknown("tiling", t);
            return Err!Tiling;
    }
    // dfmt on
}

/// Decode box property ('border-box', 'padding-box', 'content-box')
Result!BoxType decode(T : BoxType)(const Token[] tokens)
{
    with (BoxType)
    {
        // dfmt off
        immutable map = [
            tup("border-box", border),
            tup("padding-box", padding),
            tup("content-box", content),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "box", map);
    }
}

/// Decode border style property
Result!BorderStyle decode(T : BorderStyle)(const Token[] tokens)
{
    with (BorderStyle)
    {
        // dfmt off
        immutable map = [
            tup("solid", solid),
            tup("none", none),
            tup("dotted", dotted),
            tup("dashed", dashed),
            tup("double", doubled),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "border style", map);
    }
}

alias BorderHere = Tup!(Result!Length, BorderStyle, Result!Color);
/// Decode shorthand border property
Result!BorderHere decodeBorder(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const line = tokens[0].line;
    alias E = Err!BorderHere;
    BorderHere result;

    if (tokens[0].type == TokenType.ident && tokens[0].text == "none")
    {
        result[0] = Ok(Length.zero);
        result[2] = Ok(Color.transparent);
        return Ok(result);
    }
    // width
    if (startsWithLength(tokens))
    {
        if (const res = decode!Length(tokens))
        {
            if (res.val == Length.none)
            {
                Log.fe("CSS(%s): invalid border width", line);
                return E();
            }
            else
                result[0] = res;
        }
        else
            return E();
        tokens = tokens[1 .. $];
    }
    // style
    if (tokens.length > 0)
    {
        const st = decode!BorderStyle(tokens[0 .. 1]);
        if (st)
        {
            result[1] = st.val;
            tokens = tokens[1 .. $];
        }
        else
            return E();
    }
    else
    {
        Log.fe("CSS(%s): border style is required", line);
        return E();
    }
    // color
    if (startsWithColor(tokens))
    {
        if (const res = decode!Color(tokens))
            result[2] = res;
        else
            return E();
    }

    if (result[0] || result[2])
    {
        if (tokens.length > 0)
            toomany("border", line);
        return Ok(result);
    }
    else
    {
        Log.fe("CSS(%s): malformed border shorthand", line);
        return E();
    }
}

/// Create a drawable from `box-shadow` property
Result!BoxShadowDrawable decode(T : BoxShadowDrawable)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t0 = tokens[0];
    if (t0.type == TokenType.ident && t0.text == "none")
        return Ok!BoxShadowDrawable(null);

    if (tokens.length < 4)
    {
        Log.fe("CSS(%s): correct form for box-shadow is: 'h-offset v-offset blur color'", t0.line);
        return Err!BoxShadowDrawable;
    }

    const xoffset = decode!Length(tokens[0 .. 1]);
    if (xoffset.err || xoffset.val == Length.none || xoffset.val.is_percent)
    {
        Log.fe("CSS(%s): invalid x-offset value", tokens[0].line);
        return Err!BoxShadowDrawable;
    }
    const yoffset = decode!Length(tokens[1 .. 2]);
    if (yoffset.err || yoffset.val == Length.none || yoffset.val.is_percent)
    {
        Log.fe("CSS(%s): invalid y-offset value", tokens[1].line);
        return Err!BoxShadowDrawable;
    }
    const blur = decode!Length(tokens[2 .. 3]);
    if (blur.err || blur.val == Length.none || blur.val.is_percent)
    {
        Log.fe("CSS(%s): invalid blur value", tokens[2].line);
        return Err!BoxShadowDrawable;
    }
    const(Token)[] rest = tokens[3 .. $];
    const color = decode!Color(rest);
    if (color.err)
        return Err!BoxShadowDrawable;

    return Ok(new BoxShadowDrawable(xoffset.val.toDevice, yoffset.val.toDevice, blur.val.toDevice, color.val));
}

//===============================================================
// Font and textual

/// Decode font family
Result!GenericFontFamily decode(T : GenericFontFamily)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const what = "font family";
    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        shouldbe(what, "an identifier", t);
        return Err!GenericFontFamily;
    }
    // dfmt off
    switch (t.text) with (GenericFontFamily)
    {
        case "sans-serif": return Ok(sans_serif);
        case "serif":      return Ok(serif);
        case "cursive":    return Ok(cursive);
        case "fantasy":    return Ok(fantasy);
        case "monospace":  return Ok(monospace);
        case "none":       return Ok(unspecified);
        default:
            unknown(what, t);
            return Err!GenericFontFamily;
    }
    // dfmt on
}
/// Decode font style
Result!FontStyle decode(T : FontStyle)(const Token[] tokens)
{
    with (FontStyle)
    {
        // dfmt off
        immutable map = [
            tup("normal", normal),
            tup("italic", italic),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "font style", map);
    }
}
/// Decode font weight
Result!ushort decode(SpecialCSSType t : SpecialCSSType.fontWeight)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const what = "font weight";
    const t = tokens[0];
    if (t.type != TokenType.ident && t.type != TokenType.number)
    {
        shouldbe(what, "an identifier or integer", t);
        return Err!ushort;
    }
    if (tokens.length > 1)
        toomany(what, t.line);
    // dfmt off
    switch (t.text)
    {
        case "lighter":
        case "100": return Ok!ushort(100);
        case "normal":
        case "400": return Ok!ushort(400);
        case "bold":
        case "700": return Ok!ushort(700);
        case "bolder":
        case "900": return Ok!ushort(900);
        case "200": return Ok!ushort(200);
        case "300": return Ok!ushort(300);
        case "500": return Ok!ushort(500);
        case "600": return Ok!ushort(600);
        case "800": return Ok!ushort(800);
        default:
            unknown(what, t);
            return Err!ushort;
    }
    // dfmt on
}

/// Decode tab character size
Result!TabSize decode(T : TabSize)(const Token[] tokens)
{
    assert(tokens.length > 0);

    if (const i = decode!int(tokens))
        return Ok(TabSize(i.val));
    else
        return Err!TabSize;
}

/// Decode text alignment
Result!TextAlign decode(T : TextAlign)(const Token[] tokens)
{
    with (TextAlign)
    {
        // dfmt off
        immutable map = [
            tup("start", start),
            tup("center", center),
            tup("end", end),
            tup("justify", justify),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "text alignment", map);
    }
}

/// Decode text decoration line
Result!TextDecorLine decode(T : TextDecorLine)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const what = "text decoration line";
    TextDecorLine result;
    foreach (ref t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            shouldbe(what, "an identifier", t);
            return Err!TextDecorLine;
        }
        // dfmt off
        switch (t.text) with (TextDecorLine)
        {
            case "overline":     result |= over; break;
            case "underline":    result |= under; break;
            case "line-through": result |= through; break;
            case "none": break;
            default:
                unknown(what, t);
                return Err!TextDecorLine;
        }
        // dfmt on
    }
    return Ok(result);
}
/// Decode text decoration style
Result!TextDecorStyle decode(T : TextDecorStyle)(const Token[] tokens)
{
    with (TextDecorStyle)
    {
        // dfmt off
        immutable map = [
            tup("solid", solid),
            tup("double", doubled),
            tup("dotted", dotted),
            tup("dashed", dashed),
            tup("wavy", wavy),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "text decoration style", map);
    }
}

alias TextDecorHere = Tup!(TextDecorLine, Result!Color, Result!TextDecorStyle);
/// Decode whole shorthand text decoration property
Result!TextDecorHere decodeTextDecor(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const line = tokens[0].line;
    alias E = Err!TextDecorHere;
    TextDecorHere result;
    // required
    {
        if (const res = decode!TextDecorLine(tokens))
            result[0] = res.val;
        else
            return E();
        tokens = tokens[1 .. $];
    }
    // next can be color and style, but we will check style first, because color check is not precise
    if (startsWithColor(tokens))
    {
        if (const res = decode!Color(tokens))
            result[1] = res;
        else
            return E();
    }
    if (startsWithTextDecorStyle(tokens))
    {
        if (const res = decode!TextDecorStyle(tokens[0 .. 1]))
            result[2] = res;
        else
            return E();
        tokens = tokens[1 .. $];
    }
    if (tokens.length > 0)
        toomany("text-decoration", line);
    return Ok(result);
}

/// Decode text hotkey option
Result!TextHotkey decode(T : TextHotkey)(const Token[] tokens)
{
    with (TextHotkey)
    {
        // dfmt off
        immutable map = [
            tup("ignore", ignore),
            tup("hidden", hidden),
            tup("underline", underline),
            tup("underline-on-alt", underlineOnAlt),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "text hotkey option", map);
    }
}

/// Decode text overflow
Result!TextOverflow decode(T : TextOverflow)(const Token[] tokens)
{
    with (TextOverflow)
    {
        // dfmt off
        immutable map = [
            tup("clip", clip),
            tup("ellipsis", ellipsis),
            tup("ellipsis-middle", ellipsisMiddle),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "text overflow", map);
    }
}

/// Decode text transform
Result!TextTransform decode(T : TextTransform)(const Token[] tokens)
{
    with (TextTransform)
    {
        // dfmt off
        immutable map = [
            tup("none", none),
            tup("uppercase", uppercase),
            tup("lowercase", lowercase),
            tup("capitalize", capitalize),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "text transform", map);
    }
}

/// Decode white space collapse and wrapping
Result!WhiteSpace decode(T : WhiteSpace)(const Token[] tokens)
{
    with (WhiteSpace)
    {
        // dfmt off
        immutable map = [
            tup("pre", pre),
            tup("pre-wrap", preWrap),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "white space", map);
    }
}

//===============================================================

/// Decode CSS color. This function mutates the range - skips found color value
Result!Color decode(T : Color)(ref const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.hash)
    {
        tokens = tokens[1 .. $];
        if (const res = decodeHexColor("#" ~ t.text))
            return res;
    }
    if (t.type == TokenType.ident)
    {
        tokens = tokens[1 .. $];
        if (const res = decodeTextColor(t.text))
            return res;
    }
    if (t.type == TokenType.func)
    {
        Tup!(string, bool)[4] args;
        uint argsCount;
        bool closed;
        foreach (i, ref tok; tokens)
        {
            if (tok.type == TokenType.closeParen)
            {
                tokens = tokens[i + 1 .. $];
                closed = true;
                break;
            }
            if (tok.type == TokenType.number || tok.type == TokenType.percentage)
            {
                if (argsCount < 4)
                    args[argsCount] = tup(tok.text, tok.type == TokenType.percentage);
                argsCount++;
            }
        }
        if (!closed)
        {
            Log.fe("CSS(%d): expected closing parenthesis", t.line);
            return Err!Color;
        }
        if (argsCount > 4)
            toomany("color function", t.line);

        const fn = t.text;
        if (fn == "rgb" || fn == "rgba")
        {
            uint r, g, b, a;
            if (argsCount > 0)
            {
                float f = to!float(args[0][0]);
                if (args[0][1])
                    f *= 2.55f;
                r = cast(uint)clamp(f, 0, 255);
            }
            if (argsCount > 1)
            {
                float f = to!float(args[1][0]);
                if (args[1][1])
                    f *= 2.55f;
                g = cast(uint)clamp(f, 0, 255);
            }
            if (argsCount > 2)
            {
                float f = to!float(args[2][0]);
                if (args[2][1])
                    f *= 2.55f;
                b = cast(uint)clamp(f, 0, 255);
            }
            if (argsCount > 3)
            {
                const f = to!float(args[3][0]);
                a = opacityToAlpha(args[3][1] ? f / 100 : f);
            }
            return Ok(Color(r, g, b, a));
        }
        else if (fn == "hsl" || fn == "hsla")
        {
            float h = 0, s = 0, l = 0;
            uint a;
            if (argsCount > 0 && !args[0][1])
            {
                const ih = cast(int)to!float(args[0][0]);
                h = ((ih % 360 + 360) % 360) / 360.0f;
            }
            if (argsCount > 1 && args[1][1])
            {
                s = clamp(to!float(args[1][0]) / 100, 0, 1);
            }
            if (argsCount > 2 && args[2][1])
            {
                l = clamp(to!float(args[2][0]) / 100, 0, 1);
            }
            if (argsCount > 3)
            {
                const f = to!float(args[3][0]);
                a = opacityToAlpha(args[3][1] ? f / 100 : f);
            }
            return Ok(Color.fromHSLA(h, s, l, a));
        }
        else
        {
            unknown("color function", t);
            return Err!Color;
        }
    }
    unknown("color", t);
    return Err!Color;
}

/// Decode transform part
Result!SingleTransformRaw decode(T : SingleTransformRaw)(const Token[] tokens)
{
    import std.math : isNaN;

    assert(tokens.length > 0);

    alias E = Err!SingleTransformRaw;
    SingleTransformRaw result;

    const t0 = tokens[0];
    if (t0.type == TokenType.ident)
    {
        if (t0.text != "none")
        {
            unknown("transform identifier", t0);
            return E();
        }
        return Ok(result);
    }
    if (t0.type != TokenType.func)
    {
        shouldbe("transform", "function or none", t0);
        return E();
    }
    if (tokens[$ - 1].type != TokenType.closeParen)
    {
        Log.fe("CSS(%d): expected closing parenthesis", t0.line);
        return E();
    }

    switch (t0.text)
    {
    case "translate":
        if (tokens.length != 5 || tokens[2].type != TokenType.comma)
        {
            Log.fe("CSS(%d): expected two comma-separated lengths", t0.line);
            return E();
        }
        result.kind = SingleTransformKind.translate;
        if (const len = decode!Length(tokens[1 .. 2]))
            result.a = len.val;
        else
            return E();
        if (const len = decode!Length(tokens[3 .. 4]))
            result.b = len.val;
        else
            return E();
        break;
    case "translateX":
        if (tokens.length > 3)
            toomany(t0.text, t0.line);

        result.kind = SingleTransformKind.translate;
        if (const len = decode!Length(tokens[1 .. 2]))
            result.a = len.val;
        else
            return E();
        break;
    case "translateY":
        if (tokens.length > 3)
            toomany(t0.text, t0.line);

        result.kind = SingleTransformKind.translate;
        if (const len = decode!Length(tokens[1 .. 2]))
            result.b = len.val;
        else
            return E();
        break;
    case "rotate":
        if (tokens.length > 3)
            toomany(t0.text, t0.line);

        float angle;
        if (tokens[1].type == TokenType.dimension)
            angle = parseAngle(tokens[1].text, tokens[1].dimensionUnit);
        if (isNaN(angle))
        {
            unknown("angle", tokens[1]);
            return E();
        }
        result.kind = SingleTransformKind.rotate;
        result.a = Length.px(angle);
        break;
    case "scale":
        if (tokens.length != 5 || tokens[2].type != TokenType.comma)
        {
            Log.fe("CSS(%d): expected two comma-separated numbers", t0.line);
            return E();
        }
        result.kind = SingleTransformKind.scale;
        if (const num = decode!float(tokens[1 .. 2]))
            result.a = Length.px(num.val);
        else
            return E();
        if (const num = decode!float(tokens[3 .. 4]))
            result.b = Length.px(num.val);
        else
            return E();
        break;
    case "scaleX":
        if (tokens.length > 3)
            toomany(t0.text, t0.line);

        result.kind = SingleTransformKind.scale;
        if (const num = decode!float(tokens[1 .. 2]))
            result.a = Length.px(num.val);
        else
            return E();
        break;
    case "scaleY":
        if (tokens.length > 3)
            toomany(t0.text, t0.line);

        result.kind = SingleTransformKind.scale;
        if (const num = decode!float(tokens[1 .. 2]))
            result.b = Length.px(num.val);
        else
            return E();
        break;
    case "skew":
        if (tokens.length != 5 || tokens[2].type != TokenType.comma)
        {
            Log.fe("CSS(%d): expected two comma-separated angles", t0.line);
            return E();
        }
        float[2] angles;
        if (tokens[1].type == TokenType.dimension)
            angles[0] = parseAngle(tokens[1].text, tokens[1].dimensionUnit);
        if (tokens[3].type == TokenType.dimension)
            angles[1] = parseAngle(tokens[3].text, tokens[3].dimensionUnit);
        if (isNaN(angles[0]))
        {
            unknown("angle", tokens[1]);
            return E();
        }
        if (isNaN(angles[1]))
        {
            unknown("angle", tokens[3]);
            return E();
        }
        result.kind = SingleTransformKind.skew;
        result.a = Length.px(angles[0]);
        result.b = Length.px(angles[1]);
        break;
    case "skewX":
        if (tokens.length > 3)
            toomany(t0.text, t0.line);

        float angle;
        if (tokens[1].type == TokenType.dimension)
            angle = parseAngle(tokens[1].text, tokens[1].dimensionUnit);
        if (isNaN(angle))
        {
            unknown("angle", tokens[1]);
            return E();
        }
        result.kind = SingleTransformKind.skew;
        result.a = Length.px(angle);
        break;
    case "skewY":
        if (tokens.length > 3)
            toomany(t0.text, t0.line);

        float angle;
        if (tokens[1].type == TokenType.dimension)
            angle = parseAngle(tokens[1].text, tokens[1].dimensionUnit);
        if (isNaN(angle))
        {
            unknown("angle", tokens[1]);
            return E();
        }
        result.kind = SingleTransformKind.skew;
        result.b = Length.px(angle);
        break;
    default:
        unknown("transform function", t0);
        return E();
    }
    return Ok(result);
}

/// Decode opacity in [0..1] range
Result!float decode(SpecialCSSType t : SpecialCSSType.opacity)(const Token[] tokens)
{
    assert(tokens.length > 0);

    auto f = decode!float(tokens);
    if (f)
        f.val = clamp(f.val, 0, 1);
    return f;
}

/// Decode blend mode
Result!BlendMode decode(T : BlendMode)(const Token[] tokens)
{
    with (BlendMode)
    {
        // dfmt off
        immutable map = [
            tup("normal", normal),
            tup("multiply", multiply),
            tup("screen", screen),
            tup("overlay", overlay),
            tup("darken", darken),
            tup("lighten", lighten),
            tup("color-dodge", colorDodge),
            tup("color-burn", colorBurn),
            tup("hard-light", hardLight),
            tup("soft-light", softLight),
            tup("difference", difference),
            tup("exclusion", exclusion),
            tup("hue", hue),
            tup("saturation", saturation),
            tup("color", color),
            tup("luminosity", luminosity),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "blend mode", map);
    }
}

/// Decode seconds or milliseconds in CSS. Returns time in msecs.
Result!uint decode(SpecialCSSType t : SpecialCSSType.time)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.dimension)
    {
        const res = assertNotThrown(to!float(t.text));
        if (t.dimensionUnit == "s")
            return Ok(cast(uint)(res * 1000));
        else if (t.dimensionUnit == "ms")
            return Ok(cast(uint)res);
        else
        {
            Log.fe("CSS(%s): unknown time dimension: %s", t.line, t.dimensionUnit);
            return Err!uint;
        }
    }
    else
    {
        Log.fe("CSS(%s): time must have dimension units", t.line);
        return Err!uint;
    }
}
/// Decode name of property which is a subject of transition
Result!string decode(SpecialCSSType t : SpecialCSSType.transitionProperty)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return Ok(t.text);
    else
    {
        shouldbe("transition property", "an identifier", t);
        return Err!string;
    }
}
/// Decode transition timing function like 'linear' or 'ease-in-out'
Result!TimingFunction decode(T : TimingFunction)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const what = "transition timing function";
    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        shouldbe(what, "an identifier", t);
        return Err!TimingFunction;
    }
    if (tokens.length > 1)
        toomany(what, t.line);

    // dfmt off
    switch (t.text) with (TimingFunction)
    {
        case "linear": return Ok(cast()linear);
        case "ease": return Ok(cast()ease);
        case "ease-in": return Ok(cast()easeIn);
        case "ease-out": return Ok(cast()easeOut);
        case "ease-in-out": return Ok(cast()easeInOut);
        default:
            unknown(what, t);
            return Err!TimingFunction;
    }
    // dfmt on
}

alias TransitionHere = Tup!(Result!string, Result!uint, Result!TimingFunction, Result!uint);
/// Decode shorthand transition property
Result!TransitionHere decodeTransition(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const line = tokens[0].line;
    alias E = Err!TransitionHere;
    TransitionHere result;

    if (startsWithIdent(tokens))
    {
        if (const res = decode!(SpecialCSSType.transitionProperty)(tokens))
            result[0] = res;
        else
            return E();
        tokens = tokens[1 .. $];
    }
    if (startsWithTime(tokens))
    {
        if (const res = decode!(SpecialCSSType.time)(tokens))
            result[1] = res;
        else
            return E();
        tokens = tokens[1 .. $];
    }
    if (startsWithTimingFunction(tokens))
    {
        if (auto res = decode!TimingFunction(tokens[0 .. 1]))
            result[2] = res;
        else
            return E();
        tokens = tokens[1 .. $];
    }
    if (startsWithTime(tokens))
    {
        if (const res = decode!(SpecialCSSType.time)(tokens))
            result[3] = res;
        else
            return E();
        tokens = tokens[1 .. $];
    }

    if (result[0] || result[1] || result[2] || result[3])
    {
        if (tokens.length > 0)
            toomany("transition", line);
        return Ok(result);
    }
    else
    {
        Log.fe("CSS(%s): malformed transition shorthand", line);
        return E();
    }
}

/// Decode cursor property
Result!CursorType decode(T : CursorType)(const Token[] tokens)
{
    with (CursorType)
    {
        // dfmt off
        immutable map = [
            tup("auto", automatic),
            tup("default", arrow),
            tup("none", none),
            tup("pointer", pointer),
            tup("context-menu", contextMenu),
            tup("help", help),
            tup("progress", progress),
            tup("wait", wait),
            tup("cell", cell),
            tup("crosshair", crosshair),
            tup("text", text),
            tup("vertical-text", textVertical),
            tup("alias", shortcut),
            tup("copy", copy),
            tup("move", move),
            tup("no-drop", noDrop),
            tup("not-allowed", notAllowed),
            tup("grab", grab),
            tup("grabbing", grabbing),
            tup("e-resize", resizeE),
            tup("n-resize", resizeN),
            tup("ne-resize", resizeNE),
            tup("nw-resize", resizeNW),
            tup("s-resize", resizeS),
            tup("se-resize", resizeSE),
            tup("sw-resize", resizeSW),
            tup("w-resize", resizeW),
            tup("ew-resize", resizeEW),
            tup("ns-resize", resizeNS),
            tup("nesw-resize", resizeNESW),
            tup("nwse-resize", resizeNWSE),
            tup("col-resize", resizeCol),
            tup("row-resize", resizeRow),
            tup("all-scroll", scrollAll),
            tup("zoom-in", zoomIn),
            tup("zoom-out", zoomOut),
        ];
        // dfmt on
        return decodeSimpleEnum(tokens, "cursor", map);
    }
}

//===============================================================
// `startsWithXYZ` and `isXYZ` functions, needed to decode shorthands

/// True if token sequence starts with `<length>` value
bool startsWithLength(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return t.text == "auto" || t.text == "none";
    if (t.type == TokenType.number)
        return t.text == "0";
    if (t.type == TokenType.dimension)
        return true;
    if (t.type == TokenType.percentage)
        return true;
    return false;
}

/// True if the token has `<flex-direction>` value
bool isFlexDirection(ref const Token t)
{
    if (t.type == TokenType.ident)
        return isOneOf!(["row", "row-reverse", "column", "column-reverse"])(t.text);
    return false;
}
/// True if the token has `<flex-wrap>` value
bool isFlexWrap(ref const Token t)
{
    if (t.type == TokenType.ident)
        return isOneOf!(["nowrap", "wrap", "wrap-reverse"])(t.text);
    return false;
}

/// True if token sequence starts with `<color>` value
bool startsWithColor(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.hash || t.type == TokenType.ident)
        return true;
    if (t.type == TokenType.func)
        return isOneOf!(["rgb", "rgba", "hsl", "hsla"])(t.text);
    return false;
}

/// True if token sequence starts with image value
bool startsWithImage(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return t.text == "none";
    if (t.type == TokenType.url)
        return true;
    if (t.type == TokenType.func)
        return t.text == "linear";
    return false;
}

/// True if token sequence starts with `<font-family>` value
bool startsWithFontFamily(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return isOneOf!(["sans-serif", "serif", "cursive", "fantasy", "monospace", "none"])(t.text);
    return false;
}
/// True if token sequence starts with `<font-style>` value
bool startsWithFontStyle(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return t.text == "normal" || t.text == "italic";
    return false;
}
/// True if token sequence starts with `<font-weight>` value
bool startsWithFontWeight(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return isOneOf!(["lighter", "normal", "bold", "bolder"])(t.text);
    if (t.type == TokenType.number)
    {
        if (t.text.length == 3 && t.text[1 .. 3] == "00")
        {
            const ch = t.text[0];
            // dfmt off
            return ch == '1' || ch == '2' || ch == '3' ||
                   ch == '4' || ch == '5' || ch == '6' ||
                   ch == '7' || ch == '8' || ch == '9';
            // dfmt on
        }
    }
    return false;
}

/// True if token sequence starts with `<text-decoration-style>` value
bool startsWithTextDecorStyle(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return isOneOf!(["solid", "double", "dotted", "dashed", "wavy"])(t.text);
    return false;
}

/// True if token sequence starts with `<time>` value
bool startsWithTime(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.dimension)
    {
        const u = t.dimensionUnit;
        return u == "s" || u == "ms";
    }
    return false;
}

/// True if token sequence starts with identifier value
bool startsWithIdent(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    return tokens[0].type == TokenType.ident;
}

/// True if token sequence starts with `<timing-function>` value
bool startsWithTimingFunction(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return isOneOf!(["linear", "ease", "ease-in", "ease-out", "ease-in-out"])(t.text);
    return false;
}

private bool isOneOf(string[] list)(string str)
{
    switch (str)
    {
        static foreach (s; list)
        {
    case s:
            return true;
        }
    default:
        return false;
    }
}

//===============================================================
// Tests

unittest
{
    assert(parseGridTemplateString("aaa") == ["aaa"]);
    assert(parseGridTemplateString("a123") == ["a123"]);
    assert(parseGridTemplateString("a---b-") == ["a---b-"]);
    assert(parseGridTemplateString("_____") == ["_____"]);
    assert(parseGridTemplateString("_abc-123") == ["_abc-123"]);
    assert(parseGridTemplateString("a b c") == ["a", "b", "c"]);
    assert(parseGridTemplateString("a     b  \t    \t  c") == ["a", "b", "c"]);
    assert(parseGridTemplateString("     a b     ") == ["a", "b"]);

    assert(parseGridTemplateString(".") == [null]);
    assert(parseGridTemplateString("...") == [null]);
    assert(parseGridTemplateString(". . .") == [null, null, null]);
    assert(parseGridTemplateString("a ... b") == ["a", null, "b"]);
    assert(parseGridTemplateString(".a..b.") == [null, "a", null, "b", null]);

    assert(!parseGridTemplateString(null));
    assert(!parseGridTemplateString(""));
    assert(!parseGridTemplateString("123"));
    assert(!parseGridTemplateString("1st"));
    assert(!parseGridTemplateString("1st 2nd 3rd"));
    assert(!parseGridTemplateString("!@#$"));
    assert(!parseGridTemplateString("% ^ & *"));
    assert(!parseGridTemplateString("(abc)"));
    assert(!parseGridTemplateString("-a"));
}
