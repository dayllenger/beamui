/**
CSS decoding functions: take token array, convert it to some type.

Each function takes a token array as the first parameter and returns result in other `out`
parameters and success flag in the return value.

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.decode_css;

import beamui.core.animations : TimingFunction;
import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types;
import beamui.core.units;
import beamui.css.tokenizer : Token, TokenType;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.graphics.fonts : FontFamily, FontStyle, FontWeight;
import beamui.graphics.text : TextAlign;
import beamui.style.types;

/// Decode integer property
bool decode(const Token[] tokens, out int result)
{
    const t = tokens[0];
    if (t.type == TokenType.number)
    {
        if (t.typeFlagInteger)
        {
            result = to!int(t.text);
            return true;
        }
        else
        {
            Log.fe("CSS(%s): expected integer, got floating", t.line);
            return false;
        }
    }
    else
    {
        Log.fe("CSS(%s): expected number, not '%s'", t.line, t.type);
        return false;
    }
}

/// Decode raw string property
bool decode(const Token[] tokens, out string result)
{
    result = tokens[0].text;
    return true;
}

/// Decode CSS token sequence like "left vcenter" to `Align` bit set
bool decode(const Token[] tokens, out Align result)
{
    foreach (t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            Log.fe("CSS(%s): alignment should be an identifier, not '%s'", t.line, t.type);
            return false;
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
                return false;
        }
    }
    return true;
}

/// Decode CSS rectangle declaration to `Dimension[]`
bool decodeInsets(const Token[] tokens, out Dimension[] result)
{
    result.reserve(4);
    foreach (t; tokens)
    {
        if (t.type == TokenType.number || t.type == TokenType.dimension)
        {
            Dimension dm = void;
            if (decode((&t)[0 .. 1], dm))
                result ~= dm;
        }
        else
        {
            Log.fe("CSS(%s): rectangle value should be numeric, not '%s'", t.line, t.type);
            return false;
        }
        if (result.length > 4)
        {
            Log.fw("CSS(%s): too many values for rectangle", t.line);
            return false;
        }
    }
    if (result.length > 0)
        return true;
    else
    {
        Log.fe("CSS(%s): empty rectangle", tokens[0].line);
        return false;
    }
}

/// Decode dimension, e.g. 1px, 20%, 1.2em, or "none"
bool decode(const Token[] tokens, out Dimension result)
{
    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        if (t.text == "none")
        {
            result = Dimension.none;
            return true;
        }
        else
            Log.fe("CSS(%s): unknown length identifier: '%s'", t.line, t.text);
    }
    else if (t.type == TokenType.number)
    {
        if (t.text == "0")
        {
            result = Dimension.zero;
            return true;
        }
        else
            Log.fe("CSS(%s): length units are mandatory", t.line);
    }
    else if (t.type == TokenType.dimension)
    {
        result = Dimension.parse(t.text, t.dimensionUnit);
        if (result != Dimension.none)
            return true;
        else
            Log.fe("CSS(%s): can't parse length", t.line);
    }
    else if (t.type == TokenType.percentage)
    {
        result = Dimension.parse(t.text, "%");
        if (result != Dimension.none)
            return true;
        else
            Log.fe("CSS(%s): can't parse percent", t.line);
    }
    else
        Log.fe("CSS(%s): invalid length: '%s'", t.line, t.type);

    return false;
}

/// Decode shortcut background property
bool decodeBackground(const(Token)[] tokens, out Color color, out Drawable image)
{
    if (startsWithColor(tokens))
    {
        if (!decode(tokens, color))
            return false;
    }
    else
        color = Color.transparent;

    if (tokens.length > 0)
        if (!decode!(SpecialCSSType.image)(tokens, image))
            return false;

    return true;
}

/// Decode background image. This function mutates the range - skips found values
bool decode(SpecialCSSType t : SpecialCSSType.image)(ref const(Token)[] tokens, out Drawable result)
{
    import beamui.core.config : BACKEND_GUI;
    import beamui.graphics.drawbuf : DrawBufRef;

    const t0 = tokens[0];
    // #0: none
    if (t0.type == TokenType.ident)
    {
        if (t0.text == "none")
            return true;
        else
        {
            Log.fe("CSS(%s): unknown image identifier: '%s'", t0.line, t0.text);
            return false;
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
            {
                result = new ImageDrawable(image, tiled);
                return true;
            }
        }
        return false;
    }
    // #2: gradient
    if (t0.type == TokenType.func && t0.text == "linear")
    {
        import std.math : isNaN;

        float angle;
        Color color1, color2;
        if (tokens[1].type == TokenType.dimension)
        {
            angle = parseAngle(tokens[1].text, tokens[1].dimensionUnit);
        }
        if (angle.isNaN)
        {
            Log.fe("CSS(%s): 1st linear gradient parameter should be angle (deg, grad, rad or turn)", tokens[1].line);
            return false;
        }
        else
            tokens = tokens[2 .. $];

        if (tokens[0].type == TokenType.comma)
            tokens = tokens[1 .. $];

        if (!decode(tokens, color1))
            return false;

        if (tokens[0].type == TokenType.comma)
            tokens = tokens[1 .. $];

        if (!decode(tokens, color2))
            return false;

        if (tokens[0].type == TokenType.closeParen)
            tokens = tokens[1 .. $];

        result = new GradientDrawable(angle, color1, color2);
        return true;
    }
    return false;
}

/// Decode shortcut border property
bool decodeBorder(const Token[] tokens, out Color color, out Dimension width)
{
    const t0 = tokens[0];
    if (t0.type == TokenType.ident && t0.text == "none")
    {
        color = Color.transparent;
        width = Dimension(0);
        return true;
    }

    if (tokens.length < 3)
    {
        Log.fe("CSS(%s): correct form for border is: 'width style color'", t0.line);
        return false;
    }

    if (!decode(tokens[0 .. 1], width) || width == Dimension.none)
    {
        Log.fe("CSS(%s): invalid border width", t0.line);
        return false;
    }

    // style is not implemented yet
    const(Token)[] rest = tokens[2 .. $];
    return decode(rest, color);
}

/// Create a drawable from `box-shadow` property
bool decode(const Token[] tokens, out BoxShadowDrawable result)
{
    const t0 = tokens[0];
    if (t0.type == TokenType.ident && t0.text == "none")
        return true;

    if (tokens.length < 4)
    {
        Log.fe("CSS(%s): correct form for box-shadow is: 'h-offset v-offset blur color'", t0.line);
        return false;
    }

    Dimension xoffset = void;
    if (!decode(tokens[0 .. 1], xoffset) || xoffset == Dimension.none)
    {
        Log.fe("CSS(%s): invalid x-offset value", tokens[0].line);
        return false;
    }
    Dimension yoffset = void;
    if (!decode(tokens[1 .. 2], yoffset) || yoffset == Dimension.none)
    {
        Log.fe("CSS(%s): invalid y-offset value", tokens[1].line);
        return false;
    }
    Dimension blur = void;
    if (!decode(tokens[2 .. 3], blur) || blur == Dimension.none)
    {
        Log.fe("CSS(%s): invalid blur value", tokens[2].line);
        return false;
    }
    const(Token)[] rest = tokens[3 .. $];
    Color color = void;
    if (!decode(rest, color))
        return false;

    result = new BoxShadowDrawable(xoffset.toDevice, yoffset.toDevice, blur.toDevice, color);
    return true;
}

/// Decode font family
bool decode(const Token[] tokens, out FontFamily result)
{
    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): font family should be an identifier, not '%s'", t.line, t.type);
        return false;
    }
    switch (t.text)
    {
        case "sans-serif": result = FontFamily.sans_serif; break;
        case "serif": result = FontFamily.serif; break;
        case "cursive": result = FontFamily.cursive; break;
        case "fantasy": result = FontFamily.fantasy; break;
        case "monospace": result = FontFamily.monospace; break;
        case "none": result = FontFamily.unspecified; break;
        default:
            Log.fe("CSS(%s): unknown font family: %s", t.line, t.text);
            return false;
    }
    return true;
}

/// Decode font style
bool decode(const Token[] tokens, out FontStyle result)
{
    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): font style should be an identifier, not '%s'", t.line, t.type);
        return false;
    }
    if (t.text == "normal")
        result = FontStyle.normal;
    else if (t.text == "italic")
        result = FontStyle.italic;
    else
    {
        Log.fe("CSS(%s): unknown font style: %s", t.line, t.text);
        return false;
    }
    return true;
}

/// Decode font weight
bool decode(SpecialCSSType t : SpecialCSSType.fontWeight)(const Token[] tokens, out ushort result)
{
    const t = tokens[0];
    if (t.type != TokenType.ident && t.type != TokenType.number)
    {
        Log.fe("CSS(%s): font weight should be an identifier or number, not '%s'", t.line, t.type);
        return false;
    }
    switch (t.text)
    {
        case "lighter":
        case "100": result = 100; break;
        case "normal":
        case "400": result = 400; break;
        case "bold":
        case "700": result = 700; break;
        case "bolder":
        case "900": result = 900; break;
        case "200": result = 200; break;
        case "300": result = 300; break;
        case "500": result = 500; break;
        case "600": result = 600; break;
        case "800": result = 800; break;
        default:
            Log.fe("CSS(%s): unknown font weight: %s", t.line, t.text);
            return false;
    }
    return true;
}

/// Decode CSS token sequence like "hotkeys underline-hotkeys-alt" to `TextFlag` bit set
bool decode(const Token[] tokens, out TextFlag result)
{
    foreach (t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            Log.fe("CSS(%s): text flag should be an identifier, not '%s'", t.line, t.type);
            return false;
        }
        switch (t.text)
        {
            case "hotkeys": result |= TextFlag.hotkeys; break;
            case "underline": result |= TextFlag.underline; break;
            case "underline-hotkeys": result |= TextFlag.underlineHotkeys; break;
            case "underline-hotkeys-on-alt": result |= TextFlag.underlineHotkeysOnAlt; break;
            case "parent": result |= TextFlag.parent; break;
            default:
                Log.fe("CSS(%s): unknown text flag: %s", t.line, t.text);
                return false;
        }
    }
    return true;
}

/// Decode text alignment
bool decode(const Token[] tokens, out TextAlign result)
{
    const t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): text-align should be an identifier, '%s'", t.line, t.type);
        return false;
    }
    switch (t.text)
    {
        case "start": result = TextAlign.start; break;
        case "center": result = TextAlign.center; break;
        case "end": result = TextAlign.end; break;
        case "justify": result = TextAlign.justify; break;
        default:
            Log.fe("CSS(%s): unknown text alignment: %s", t.line, t.text);
            return false;
    }
    return true;
}

/// Returns true whether token sequence starts with color property
bool startsWithColor(const Token[] tokens)
{
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

/// Decode CSS color. This function mutates the range - skips found color value
bool decode(ref const(Token)[] tokens, out Color result)
{
    const t = tokens[0];
    if (t.type == TokenType.hash)
    {
        tokens = tokens[1 .. $];
        result = decodeHexColor("#" ~ t.text, Color.none);
        return result != Color.none;
    }
    if (t.type == TokenType.ident)
    {
        tokens = tokens[1 .. $];
        result = decodeTextColor(t.text, Color.none);
        return result != Color.none;
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
            return false;
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
            result = Color(r, g, b, a);
        }
        // TODO: hsl, hsla
        else
        {
            Log.fe("CSS(%s): unknown color function: %s", t.line, fn);
            return false;
        }
    }
    return true;
}

/// Decode opacity
bool decode(SpecialCSSType t : SpecialCSSType.opacity)(const Token[] tokens, out ubyte result)
{
    result = opacityToAlpha(to!float(tokens[0].text));
    return true;
}

/// Decode seconds or milliseconds in CSS. Returns time in msecs.
bool decode(SpecialCSSType t : SpecialCSSType.time)(const Token[] tokens, out uint result)
{
    const t = tokens[0];
    if (t.type == TokenType.dimension)
    {
        uint res = to!uint(t.text);
        if (t.dimensionUnit == "s")
            result = res * 1000;
        else if (t.dimensionUnit == "ms")
            result = res;
        else
        {
            Log.fe("CSS(%s): unknown time dimension: %s", t.line, t.dimensionUnit);
            return false;
        }
    }
    else
    {
        Log.fe("CSS(%s): time must have dimension units", t.line);
        return false;
    }
    return true;
}

/// Decode name of property which is a subject of transition
bool decode(SpecialCSSType t : SpecialCSSType.transitionProperty)(const Token[] tokens, out string result)
{
    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        result = t.text;
        return true;
    }
    else
    {
        Log.fe("CSS(%s): transition property must be an identifier", t.line);
        return false;
    }
}

/// Decode transition timing function like linear or ease-in-out
bool decode(const Token[] tokens, out TimingFunction result)
{
    const t = tokens[0];
    if (t.type == TokenType.ident)
    {
        switch (t.text)
        {
        case "linear":
            result = cast(TimingFunction)TimingFunction.linear;
            break;
        case "ease":
            result = cast(TimingFunction)TimingFunction.ease;
            break;
        case "ease-in":
            result = cast(TimingFunction)TimingFunction.easeIn;
            break;
        case "ease-out":
            result = cast(TimingFunction)TimingFunction.easeOut;
            break;
        case "ease-in-out":
            result = cast(TimingFunction)TimingFunction.easeInOut;
            break;
        default:
            Log.fe("CSS(%s): unknown or unsupported transition timing function: %s", t.line, t.text);
            return false;
        }
    }
    else
    {
        Log.fe("CSS(%s): transition timing function must be an identifier", t.line);
        return false;
    }
    return true;
}

/// Decode shorthand transition property
bool decodeTransition(const Token[] tokens, out string property, out TimingFunction func,
    out uint duration, out uint delay)
{
    if (tokens.length > 0)
        if (!decode!(SpecialCSSType.transitionProperty)(tokens[0 .. 1], property))
            return false;
    if (tokens.length > 1)
        if (!decode!(SpecialCSSType.time)(tokens[1 .. 2], duration))
            return false;
    if (tokens.length > 2)
        if (!decode(tokens[2 .. 3], func))
            return false;
    if (tokens.length > 3)
        if (!decode!(SpecialCSSType.time)(tokens[3 .. 4], delay))
            return false;
    if (tokens.length > 4)
        Log.fw("CSS(%s): too many values for transition", tokens[0].line);
    return true;
}
