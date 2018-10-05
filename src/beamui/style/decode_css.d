/**

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

/// Parses CSS rectangle declaration to Dimension[]
Dimension[] decodeInsets(Token[] tokens)
{
    Dimension[] values;
    values.reserve(4);
    foreach (t; tokens)
    {
        if (t.type == TokenType.number || t.type == TokenType.dimension)
        {
            auto dm = decodeDimension(t);
            if (dm != Dimension.none)
                values ~= dm;
        }
        else
        {
            Log.fe("CSS(%s): rectangle value should be numeric, not '%s'", t.line, t.type);
            break;
        }
        if (values.length > 4)
        {
            Log.fw("CSS(%s): too many values for rectangle", t.line);
            break;
        }
    }
    if (values.length > 0)
        return values;
    else
    {
        Log.fe("CSS(%s): empty rectangle", tokens[0].line);
        return null;
    }
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
void decodeBackground(Token[] tokens, out Color color, out Drawable image)
{
    if (startsWithColor(tokens))
        color = decodeColor(tokens);
    else
        color = Color.transparent;

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
        Color color1, color2;
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

/// Decode shortcut border property
void decodeBorder(Token[] tokens, ref Color color, ref Dimension width)
{
    Token t0 = tokens[0];
    if (t0.type == TokenType.ident && t0.text == "none")
    {
        color = Color.transparent;
        width = Dimension(0);
        return;
    }

    if (tokens.length < 3)
    {
        Log.fe("CSS(%s): correct form for border is: 'width style color'", t0.line);
        return;
    }

    width = decodeDimension(tokens[0]);
    if (width == Dimension.none)
    {
        Log.fe("CSS(%s): invalid border width", tokens[0].line);
        return;
    }
    // style is not implemented yet
    Token[] rest = tokens[2 .. $];
    color = decodeColor(rest);
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
    Color color = decodeColor(rest);

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
Color decodeColor(ref Token[] tokens)
{
    Token t = tokens[0];
    if (t.type == TokenType.hash)
    {
        tokens = tokens[1 .. $];
        return decodeHexColor("#" ~ t.text, Color.none);
    }
    if (t.type == TokenType.ident)
    {
        tokens = tokens[1 .. $];
        return decodeTextColor(t.text, Color.none);
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
            return Color.none;
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
            return Color(r, g, b, a);
        }
        // TODO: hsl, hsla
        else
        {
            Log.fe("CSS(%s): unknown color function: %s", t.line, fn);
            return Color.none;
        }
    }
    return Color.none;
}

/// Decode seconds or milliseconds in CSS. Returns time in msecs.
uint decodeTime(Token t)
{
    if (t.type == TokenType.dimension)
    {
        uint res = to!uint(t.text);
        if (t.dimensionUnit == "s")
            return res * 1000;
        if (t.dimensionUnit == "ms")
            return res;
    }
    Log.fe("CSS(%s): time must be like 200ms or 1s", t.line);
    return 0;
}

/// Decode name of property which is a subject of transition
string decodeTransitionProperty(Token t)
{
    if (t.type == TokenType.ident)
    {
        switch (t.text)
        {
        case "all":
        case "width":
        case "height":
            return t.text;
        case "min-width":
            return "minWidth";
        case "max-width":
            return "maxWidth";
        case "min-height":
            return "minHeight";
        case "max-height":
            return "maxHeight";
        case "margin-top":
            return "marginTop";
        case "margin-right":
            return "marginRight";
        case "margin-bottom":
            return "marginBottom";
        case "margin-left":
            return "marginLeft";
        case "padding-top":
            return "paddingTop";
        case "padding-right":
            return "paddingRight";
        case "padding-bottom":
            return "paddingBottom";
        case "padding-left":
            return "paddingLeft";
        case "border-color":
            return "borderColor";
        case "border-top-width":
            return "borderWidthTop";
        case "border-right-width":
            return "borderWidthRight";
        case "border-bottom-width":
            return "borderWidthBottom";
        case "border-left-width":
            return "borderWidthLeft";
        case "background-color":
            return "backgroundColor";
        case "opacity":
            return "alpha";
        case "color":
            return "textColor";
        default:
            Log.fe("CSS(%s): unknown or unsupported transition property: %s", t.line, t.text);
        }
    }
    else
        Log.fe("CSS(%s): transition property must be an identifier", t.line);
    return null;
}

/// Decode transition timing function like linear or ease-in-out
TimingFunction decodeTransitionTimingFunction(Token t)
{
    if (t.type == TokenType.ident)
    {
        switch (t.text)
        {
        case "linear":
            return cast(TimingFunction)TimingFunction.linear;
        case "ease":
            return cast(TimingFunction)TimingFunction.ease;
        case "ease-in":
            return cast(TimingFunction)TimingFunction.easeIn;
        case "ease-out":
            return cast(TimingFunction)TimingFunction.easeOut;
        case "ease-in-out":
            return cast(TimingFunction)TimingFunction.easeInOut;
        default:
            Log.fe("CSS(%s): unknown or unsupported transition timing function: %s", t.line, t.text);
            break;
        }
    }
    else
        Log.fe("CSS(%s): transition timing function must be an identifier", t.line);
    return null;
}

/// Decode shorthand transition property
void decodeTransition(Token[] tokens, ref string property, ref TimingFunction func, ref uint dur, ref uint delay)
{
    if (tokens.length > 0)
        property = decodeTransitionProperty(tokens[0]);
    if (tokens.length > 1)
        dur = decodeTime(tokens[1]);
    if (tokens.length > 2)
        func = decodeTransitionTimingFunction(tokens[2]);
    if (tokens.length > 3)
        delay = decodeTime(tokens[3]);
    if (tokens.length > 4)
        Log.fw("CSS(%s): too many values for transition", tokens[0].line);
}
