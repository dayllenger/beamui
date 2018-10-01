/**

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.decode_css;

import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types;
import beamui.core.units;
import beamui.css.css;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.graphics.fonts;
import beamui.style.types;

/// Parses CSS token sequence like "left vcenter" to Align bit set
Align decodeAlignment(Token[] tokens)
{
    Align res = Align.unspecified;
    foreach (t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            Log.fe("CSS(%s): alignment should be an identifier, not '%s'", t.line, t.type);
            break;
        }
        switch (t.text)
        {
        case "left": res |= Align.left; break;
        case "right": res |= Align.right; break;
        case "top": res |= Align.top; break;
        case "bottom": res |= Align.bottom; break;
        case "hcenter": res |= Align.hcenter; break;
        case "vcenter": res |= Align.vcenter; break;
        case "center": res |= Align.center; break;
        case "top-left": res |= Align.topleft; break;
        default:
            Log.fe("CSS(%s): unknown alignment: %s", t.line, t.text);
            break;
        }
    }
    return res;
}

/// Parses CSS rectangle declaration to Insets
Insets decodeInsets(Token[] tokens)
{
    uint[4] values;
    size_t valueCount;
    foreach (t; tokens)
    {
        if (t.type == TokenType.number || t.type == TokenType.dimension)
            values[valueCount++] = decodeDimension(t).toDevice;
        else
        {
            Log.fe("CSS(%s): rectangle value should be numeric, not '%s'", t.line, t.type);
            break;
        }
        if (valueCount > 4)
        {
            Log.fe("CSS(%s): too much values for rectangle", t.line);
            break;
        }
    }
    if (valueCount == 1) // same value for all dimensions
        return Insets(values[0]);
    else if (valueCount == 2) // one value for vertical, one for horizontal
        return Insets(values[0], values[1]);
    else if (valueCount == 3) // values for top, bottom, and one for horizontal
        return Insets(values[0], values[1], values[2], values[1]);
    else if (valueCount == 4) // separate top, right, bottom, left
        return Insets(values[0], values[1], values[2], values[3]);
    Log.fe("CSS(%s): empty rectangle", tokens[0].line);
    return Insets(0);
}

/// Decode dimension, e.g. 1px, 20%, 1.2em or `none`
Dimension decodeDimension(Token t)
{
    if (t.type == TokenType.ident)
    {
        if (t.text == "none")
            return Dimension.none;
        else
            Log.fe("CSS(%s): unknown length identifier: '%s'", t.line, t.text);
    }
    else if (t.type == TokenType.number)
    {
        if (t.text == "0")
            return Dimension.zero;
        else
            Log.fe("CSS(%s): length units are mandatory", t.line);
    }
    else if (t.type == TokenType.dimension)
    {
        Dimension u = Dimension.parse(t.text, t.dimensionUnit);
        if (u != Dimension.none)
            return u;
        else
            Log.fe("CSS(%s): can't parse length", t.line);
    }
    else if (t.type == TokenType.percentage)
    {
        Dimension u = Dimension.parse(t.text, "%");
        if (u != Dimension.none)
            return u;
        else
            Log.fe("CSS(%s): can't parse percent", t.line);
    }
    else
        Log.fe("CSS(%s): invalid length: '%s'", t.line, t.type);

    return Dimension.none;
}

/// Decode shortcut background property
void decodeBackground(Token[] tokens, out uint color, out Drawable image)
{
    if (startsWithColor(tokens))
        color = decodeColor(tokens);
    else
        color = COLOR_TRANSPARENT;

    if (tokens.length > 0)
        image = decodeBackgroundImage(tokens);
}

/// Decode background image. This function mutates the range - skips found values
Drawable decodeBackgroundImage(ref Token[] tokens)
{
    import beamui.core.config;
    import beamui.graphics.drawbuf;

    Token t0 = tokens[0];
    // #0: none
    if (t0.type == TokenType.ident)
    {
        if (t0.text == "none")
            return null;
        else
            Log.fe("CSS(%s): unknown image identifier: '%s'", t0.line, t0.text);
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
                return new ImageDrawable(image, tiled);
        }
        return null;
    }
    // #2: gradient
    if (t0.type == TokenType.func && t0.text == "linear")
    {
        import std.math : isNaN;

        float angle;
        uint color1, color2;
        if (tokens[1].type == TokenType.dimension)
        {
            angle = parseAngle(tokens[1].text, tokens[1].dimensionUnit);
        }
        if (angle.isNaN)
        {
            Log.fe("CSS(%s): 1st linear gradient parameter should be angle (deg, grad, rad or turn)", tokens[1].line);
            return null;
        }
        else
            tokens = tokens[2 .. $];

        if (tokens[0].type == TokenType.comma)
            tokens = tokens[1 .. $];

        color1 = decodeColor(tokens);

        if (tokens[0].type == TokenType.comma)
            tokens = tokens[1 .. $];

        color2 = decodeColor(tokens);

        if (tokens[0].type == TokenType.closeParen)
            tokens = tokens[1 .. $];

        return new GradientDrawable(angle, color1, color2);
    }
    return null;
}

/// Create a drawable from border property
BorderDrawable decodeBorder(Token[] tokens)
{
    Token t0 = tokens[0];
    if (t0.type == TokenType.ident && t0.text == "none")
        return null;

    if (tokens.length < 3)
    {
        Log.fe("CSS(%s): correct form for border is: 'width style color'", t0.line);
        return null;
    }

    Dimension width = decodeDimension(tokens[0]);
    if (width == Dimension.none)
    {
        Log.fe("CSS(%s): invalid border width", tokens[0].line);
        return null;
    }
    // style is not implemented yet
    Token[] rest = tokens[2 .. $];
    uint color = decodeColor(rest);

    return new BorderDrawable(color, width.toDevice);
}

/// Create a drawable from box-shadow property
BoxShadowDrawable decodeBoxShadow(Token[] tokens)
{
    Token t0 = tokens[0];
    if (t0.type == TokenType.ident && t0.text == "none")
        return null;

    if (tokens.length < 4)
    {
        Log.fe("CSS(%s): correct form for box-shadow is: 'h-offset v-offset blur color'", t0.line);
        return null;
    }

    Dimension xoffset = decodeDimension(tokens[0]);
    if (xoffset == Dimension.none)
    {
        Log.fe("CSS(%s): invalid x-offset value", tokens[0].line);
        return null;
    }
    Dimension yoffset = decodeDimension(tokens[1]);
    if (yoffset == Dimension.none)
    {
        Log.fe("CSS(%s): invalid y-offset value", tokens[1].line);
        return null;
    }
    Dimension blur = decodeDimension(tokens[2]);
    if (blur == Dimension.none)
    {
        Log.fe("CSS(%s): invalid blur value", tokens[2].line);
        return null;
    }
    Token[] rest = tokens[3 .. $];
    uint color = decodeColor(rest);

    return new BoxShadowDrawable(xoffset.toDevice, yoffset.toDevice, blur.toDevice, color);
}

FontFamily decodeFontFamily(Token[] tokens)
{
    if (tokens[0].type != TokenType.ident)
    {
        Log.fe("CSS(%s): font family should be an identifier, not '%s'", tokens[0].line, tokens[0].type);
        return FontFamily.sans_serif;
    }
    string s = tokens[0].text;
    if (s == "sans-serif")
        return FontFamily.sans_serif;
    if (s == "serif")
        return FontFamily.serif;
    if (s == "cursive")
        return FontFamily.cursive;
    if (s == "fantasy")
        return FontFamily.fantasy;
    if (s == "monospace")
        return FontFamily.monospace;
    if (s == "none")
        return FontFamily.unspecified;
    Log.fe("CSS(%s): unknown font family: %s", tokens[0].line, s);
    return FontFamily.sans_serif;
}

FontWeight decodeFontWeight(Token[] tokens)
{
    auto t = tokens[0];
    if (t.type != TokenType.ident)
    {
        Log.fe("CSS(%s): font weight should be an identifier, not '%s'", t.line, t.type);
        return FontWeight.normal;
    }
    string s = tokens[0].text;
    if (s == "bold")
        return FontWeight.bold;
    if (s == "normal")
        return FontWeight.normal;
    Log.fe("CSS(%s): unknown font weight: %s", t.line, s);
    return FontWeight.normal;
}

/// Parses CSS token sequence like "hotkeys underline-hotkeys-alt" to TextFlag bit set
TextFlag decodeTextFlags(Token[] tokens)
{
    TextFlag res;
    foreach (t; tokens)
    {
        if (t.type != TokenType.ident)
        {
            Log.fe("CSS(%s): text flag should be an identifier, not '%s'", t.line, t.type);
            break;
        }
        switch (t.text)
        {
        case "hotkeys":
            res |= TextFlag.hotkeys;
            break;
        case "underline":
            res |= TextFlag.underline;
            break;
        case "underline-hotkeys":
            res |= TextFlag.underlineHotkeys;
            break;
        case "underline-hotkeys-on-alt":
            res |= TextFlag.underlineHotkeysOnAlt;
            break;
        case "parent":
            res |= TextFlag.parent;
            break;
        default:
            Log.fe("CSS(%s): unknown text flag: %s", t.line, t.text);
            break;
        }
    }
    return res;
}

bool startsWithColor(Token[] tokens)
{
    Token t = tokens[0];
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
uint decodeColor(ref Token[] tokens)
{
    Token t = tokens[0];
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
        Token[] func;
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
            return 0;
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
            return makeRGBA(r, g, b, a);
        }
        // TODO: hsl, hsla
        else
        {
            Log.fe("CSS(%s): unknown color function: %s", t.line, fn);
            return 0;
        }
    }
    return 0;
}
