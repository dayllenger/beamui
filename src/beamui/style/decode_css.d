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
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types : Result, Ok, Err, Tup;
import beamui.core.units;
import beamui.css.tokenizer : Token, TokenType;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.style.types;
import beamui.text.fonts : FontFamily, FontStyle, FontWeight;
import beamui.text.style;

void logInvalidValue(const Token[] tokens)
{
    assert(tokens.length > 0);

    Log.fe("CSS(%s): invalid value", tokens[0].line);
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
        Log.fe("CSS(%s): expected number, not '%s'", t.line, t.type);
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
        Log.fe("CSS(%s): expected number, not '%s'", t.line, t.type);
        return Err(0);
    }
}

/// Decode raw string property
Result!string decode(T : string)(const Token[] tokens)
{
    assert(tokens.length > 0);

    return Ok(tokens[0].text);
}

/// Decode CSS token sequence like 'left vcenter' to `Align` bit set
Result!Align decode(T : Align)(const Token[] tokens)
{
    assert(tokens.length > 0);

    Align result;
    foreach (t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            Log.fe("CSS(%s): alignment should be an identifier, not '%s'", t.line, t.type);
            return Err!Align;
        }
        switch (t.text)
        {
            case "center": result |= Align.center; break;
            case "left": result |= Align.left; break;
            case "right": result |= Align.right; break;
            case "top": result |= Align.top; break;
            case "bottom": result |= Align.bottom; break;
            case "hcenter": result |= Align.hcenter; break;
            case "vcenter": result |= Align.vcenter; break;
            case "top-left": result |= Align.topleft; break;
            default:
                Log.fe("CSS(%s): unknown alignment: %s", t.line, t.text);
                return Err!Align;
        }
    }
    return Ok(result);
}

/// Decode CSS rectangle declaration to `Length[]`
Length[] decodeInsets(const Token[] tokens)
{
    assert(tokens.length > 0);

    Length[] result;
    result.reserve(4);
    foreach (t; tokens)
    {
        if (t.type == TokenType.number || t.type == TokenType.dimension)
        {
            if (const dm = decode!Length((&t)[0 .. 1]))
                result ~= dm.val;
        }
        else
        {
            Log.fe("CSS(%s): rectangle value should be numeric, not '%s'", t.line, t.type);
            return null;
        }
        if (result.length > 4)
        {
            Log.fw("CSS(%s): too many values for rectangle", t.line);
            return null;
        }
    }
    if (result.length > 0)
        return result;
    else
    {
        Log.fe("CSS(%s): empty rectangle", tokens[0].line);
        return null;
    }
}
/// Decode dimension, e.g. 1px, 20%, 1.2em, or 'none'
Result!Length decode(T : Length)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        if (t.text == "none")
            return Ok(Length.none);
        else
            Log.fe("CSS(%s): unknown length identifier: '%s'", t.line, t.text);
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

alias BackgroundHere = Tup!(Result!Color, Result!Drawable);
/// Decode shortcut background property
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
            Log.fw("CSS(%s): too many values for background", line);
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
    import beamui.graphics.drawbuf : DrawBufRef;

    const t0 = tokens[0];
    // #0: none
    if (t0.type == TokenType.ident)
    {
        if (t0.text == "none")
            return Ok!Drawable(null);
        else
        {
            Log.fe("CSS(%s): unknown image identifier: '%s'", t0.line, t0.text);
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
            DrawBufRef image = imageCache.get(id);
            if (!image.isNull)
                return Ok!Drawable(new ImageDrawable(image, tiled));
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
        if (angle.isNaN)
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

alias BorderHere = Tup!(Result!Color, Result!Length);
/// Decode shortcut border property
Result!BorderHere decodeBorder(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const line = tokens[0].line;
    alias E = Err!BorderHere;
    BorderHere result;

    if (tokens[0].type == TokenType.ident && tokens[0].text == "none")
    {
        result[0] = Ok(Color.transparent);
        result[1] = Ok(Length.zero);
        return Ok(result);
    }
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
                result[1] = res;
        }
        else
            return E();
        tokens = tokens[1 .. $];
    }
    // style is not implemented yet
    if (tokens.length > 0)
        tokens = tokens[1 .. $];
    if (startsWithColor(tokens))
    {
        if (const res = decode!Color(tokens))
            result[0] = res;
        else
            return E();
    }

    if (result[0] || result[1])
    {
        if (tokens.length > 0)
            Log.fw("CSS(%s): too many values for border", line);
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

/// Decode font family
Result!FontFamily decode(T : FontFamily)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): font family should be an identifier, not '%s'", t.line, t.type);
        return Err!FontFamily;
    }
    switch (t.text)
    {
        case "sans-serif": return Ok(FontFamily.sans_serif);
        case "serif": return Ok(FontFamily.serif);
        case "cursive": return Ok(FontFamily.cursive);
        case "fantasy": return Ok(FontFamily.fantasy);
        case "monospace": return Ok(FontFamily.monospace);
        case "none": return Ok(FontFamily.unspecified);
        default:
            Log.fe("CSS(%s): unknown font family: %s", t.line, t.text);
            return Err!FontFamily;
    }
}
/// Decode font style
Result!FontStyle decode(T : FontStyle)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): font style should be an identifier, not '%s'", t.line, t.type);
        return Err!FontStyle;
    }
    switch (t.text)
    {
        case "normal": return Ok(FontStyle.normal);
        case "italic": return Ok(FontStyle.italic);
        default:
            Log.fe("CSS(%s): unknown font style: %s", t.line, t.text);
            return Err!FontStyle;
    }
}
/// Decode font weight
Result!ushort decode(SpecialCSSType t : SpecialCSSType.fontWeight)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident && t.type != TokenType.number)
    {
        Log.fe("CSS(%s): font weight should be an identifier or number, not '%s'", t.line, t.type);
        return Err!ushort;
    }
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
            Log.fe("CSS(%s): unknown font weight: %s", t.line, t.text);
            return Err!ushort;
    }
}

/// Decode text alignment
Result!TextAlign decode(T : TextAlign)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): text alignment should be an identifier, not '%s'", t.line, t.type);
        return Err!TextAlign;
    }
    switch (t.text)
    {
        case "start": return Ok(TextAlign.start);
        case "center": return Ok(TextAlign.center);
        case "end": return Ok(TextAlign.end);
        case "justify": return Ok(TextAlign.justify);
        default:
            Log.fe("CSS(%s): unknown text alignment: %s", t.line, t.text);
            return Err!TextAlign;
    }
}

/// Decode text decoration line
Result!(TextDecoration.Line) decode(T : TextDecoration.Line)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): text decoration line should be an identifier, not '%s'", t.line, t.type);
        return Err!(TextDecoration.Line);
    }
    switch (t.text)
    {
        case "none": return Ok(TextDecoration.Line.none);
        case "overline": return Ok(TextDecoration.Line.overline);
        case "underline": return Ok(TextDecoration.Line.underline);
        case "line-through": return Ok(TextDecoration.Line.lineThrough);
        default:
            Log.fe("CSS(%s): unknown text decoration line: %s", t.line, t.text);
            return Err!(TextDecoration.Line);
    }
}
/// Decode text decoration style
Result!(TextDecoration.Style) decode(T : TextDecoration.Style)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): text decoration style should be an identifier, not '%s'", t.line, t.type);
        return Err!(TextDecoration.Style);
    }
    switch (t.text)
    {
        case "solid": return Ok(TextDecoration.Style.solid);
        case "double": return Ok(TextDecoration.Style.doubled);
        case "dotted": return Ok(TextDecoration.Style.dotted);
        case "dashed": return Ok(TextDecoration.Style.dashed);
        case "wavy": return Ok(TextDecoration.Style.wavy);
        default:
            Log.fe("CSS(%s): unknown text decoration style: %s", t.line, t.text);
            return Err!(TextDecoration.Style);
    }
}
alias TextDecorationHere = Tup!(TextDecoration.Line, Result!Color, Result!(TextDecoration.Style));
/// Decode whole shorthand text decoration property
Result!TextDecorationHere decodeTextDecoration(const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const line = tokens[0].line;
    alias E = Err!TextDecorationHere;
    TextDecorationHere result;
    // required
    {
        if (const res = decode!(TextDecoration.Line)(tokens))
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
    if (startsWithTextDecorationStyle(tokens))
    {
        if (const res = decode!(TextDecoration.Style)(tokens))
            result[2] = res;
        else
            return E();
        tokens = tokens[1 .. $];
    }
    if (tokens.length > 0)
        Log.fw("CSS(%s): too many values for text-decoration", line);
    return Ok(result);
}

/// Decode text hotkey option
Result!TextHotkey decode(T : TextHotkey)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): text hotkey option should be an identifier, not '%s'", t.line, t.type);
        return Err!TextHotkey;
    }
    switch (t.text)
    {
        case "ignore": return Ok(TextHotkey.ignore);
        case "hidden": return Ok(TextHotkey.hidden);
        case "underline": return Ok(TextHotkey.underline);
        case "underline-on-alt": return Ok(TextHotkey.underlineOnAlt);
        default:
            Log.fe("CSS(%s): unknown text hotkey option: %s", t.line, t.text);
            return Err!TextHotkey;
    }
}

/// Decode text overflow
Result!TextOverflow decode(T : TextOverflow)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): text overflow should be an identifier, not '%s'", t.line, t.type);
        return Err!TextOverflow;
    }
    switch (t.text)
    {
        case "clip": return Ok(TextOverflow.clip);
        case "ellipsis": return Ok(TextOverflow.ellipsis);
        case "ellipsis-middle": return Ok(TextOverflow.ellipsisMiddle);
        default:
            Log.fe("CSS(%s): unknown text overflow: %s", t.line, t.text);
            return Err!TextOverflow;
    }
}

/// Decode text transform
Result!TextTransform decode(T : TextTransform)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): text transform should be an identifier, not '%s'", t.line, t.type);
        return Err!TextTransform;
    }
    switch (t.text)
    {
        case "none": return Ok(TextTransform.none);
        case "capitalize": return Ok(TextTransform.capitalize);
        case "uppercase": return Ok(TextTransform.uppercase);
        case "lowercase": return Ok(TextTransform.lowercase);
        default:
            Log.fe("CSS(%s): unknown text transform: %s", t.line, t.text);
            return Err!TextTransform;
    }
}

/// Decode CSS color. This function mutates the range - skips found color value
Result!Color decode(T : Color)(ref const(Token)[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.hash)
    {
        tokens = tokens[1 .. $];
        return decodeHexColor("#" ~ t.text);
    }
    if (t.type == TokenType.ident)
    {
        tokens = tokens[1 .. $];
        return decodeTextColor(t.text);
    }
    if (t.type == TokenType.func)
    {
        const(Token)[] func;
        foreach (i, tok; tokens)
        {
            if (tok.type == TokenType.closeParen)
            {
                func = tokens[0 .. i];
                break;
            }
        }
        if (func is null)
        {
            Log.fe("CSS(%s): expected closing parenthesis", t.line);
            return Err!Color;
        }
        else
            tokens = tokens[func.length + 1 .. $];

        string fn = t.text;
        if (fn == "rgb" || fn == "rgba")
        {
            func = func.efilter!(t => t.type == TokenType.number);
            auto convert = (size_t idx) => func.length > idx ? clamp(to!uint(func[idx].text), 0, 255) : 0;
            uint r = convert(0);
            uint g = convert(1);
            uint b = convert(2);
            uint a = func.length > 3 ? opacityToAlpha(to!float(func[3].text)) : 0;
            return Ok(Color(r, g, b, a));
        }
        // TODO: hsl, hsla
        else
        {
            Log.fe("CSS(%s): unknown color function: %s", t.line, fn);
            return Err!Color;
        }
    }
    return Err!Color;
}

/// Decode opacity
Result!ubyte decode(SpecialCSSType t : SpecialCSSType.opacity)(const Token[] tokens)
{
    assert(tokens.length > 0);

    return Ok(opacityToAlpha(to!float(tokens[0].text)));
}

/// Decode seconds or milliseconds in CSS. Returns time in msecs.
Result!uint decode(SpecialCSSType t : SpecialCSSType.time)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.dimension)
    {
        uint res = to!uint(t.text);
        if (t.dimensionUnit == "s")
            return Ok(res * 1000);
        else if (t.dimensionUnit == "ms")
            return Ok(res);
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
        Log.fe("CSS(%s): transition property must be an identifier", t.line);
        return Err!string;
    }
}
/// Decode transition timing function like 'linear' or 'ease-in-out'
Result!TimingFunction decode(T : TimingFunction)(const Token[] tokens)
{
    assert(tokens.length > 0);

    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        switch (t.text)
        {
            case "linear": return Ok(cast(TimingFunction)TimingFunction.linear);
            case "ease": return Ok(cast(TimingFunction)TimingFunction.ease);
            case "ease-in": return Ok(cast(TimingFunction)TimingFunction.easeIn);
            case "ease-out": return Ok(cast(TimingFunction)TimingFunction.easeOut);
            case "ease-in-out": return Ok(cast(TimingFunction)TimingFunction.easeInOut);
            default:
                Log.fe("CSS(%s): unknown or unsupported transition timing function: %s", t.line, t.text);
                return Err!TimingFunction;
        }
    }
    else
    {
        Log.fe("CSS(%s): transition timing function must be an identifier", t.line);
        return Err!TimingFunction;
    }
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
        if (auto res = decode!TimingFunction(tokens))
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
            Log.fw("CSS(%s): too many values for transition", line);
        return Ok(result);
    }
    else
    {
        Log.fe("CSS(%s): malformed transition shorthand", line);
        return E();
    }
}

//===============================================================
// `startsWith` functions, needed to decode shorthands

/// True if token sequence starts with `<length>` value
bool startsWithLength(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
        return t.text == "none";
    if (t.type == TokenType.number)
        return t.text == "0";
    if (t.type == TokenType.dimension)
        return true;
    if (t.type == TokenType.percentage)
        return true;
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
    {
        string fn = t.text;
        if (fn == "rgb" || fn == "rgba" || fn == "hsl" || fn == "hsla")
            return true;
    }
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
    {
        switch (t.text)
        {
            case "sans-serif":
            case "serif":
            case "cursive":
            case "fantasy":
            case "monospace":
            case "none":
                return true;
            default:
                return false;
        }
    }
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
        return t.text == "lighter" || t.text == "normal" ||
               t.text == "bold" || t.text == "bolder";
    if (t.type == TokenType.number)
    {
        if (t.text.length == 3 && t.text[1 .. 3] == "00")
        {
            const ch = t.text[0];
            return ch == '1' || ch == '2' || ch == '3' ||
                   ch == '4' || ch == '5' || ch == '6' ||
                   ch == '7' || ch == '8' || ch == '9';
        }
    }
    return false;
}

/// True if token sequence starts with `<text-decoration-style>` value
bool startsWithTextDecorationStyle(const Token[] tokens)
{
    if (tokens.length == 0)
        return false;

    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        switch (t.text)
        {
            case "solid":
            case "double":
            case "dotted":
            case "dashed":
            case "wavy":
                return true;
            default:
                return false;
        }
    }
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
    {
        switch (t.text)
        {
            case "linear":
            case "ease":
            case "ease-in":
            case "ease-out":
            case "ease-in-out":
                return true;
            default:
                return false;
        }
    }
    return false;
}
