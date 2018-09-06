/**
This module is DML (DlangUI Markup Language) parser - similar to QML in QtQuick

Synopsis:
---
Widget layout = parseML(q{
    Column {
        Label { text: "Some label" }
        TextLine { id: editor; text: "Some text to edit" }
        Button { id: btnOk; text: "Ok" }
    }
});
---

Copyright: Vadim Lopatin 2015-2016
License:   Boost License 1.0
Authors:   Vadim Lopatin
*/
module beamui.dml.parser;

import std.array : join;
import std.container.slist;
import beamui.core.collections;
import beamui.core.functions;
import beamui.core.linestream;
import beamui.core.types;
import beamui.dml.tokenizer;
import beamui.widgets.metadata;
import beamui.widgets.widget;

/// Parse DML code
T parseML(T = Widget)(string code, string filename = "", Widget context = null)
{
    Widget w = MLParser(code, filename, context).parse();
    T res = cast(T)w;
    if (w && !res && !context)
    {
        destroy(w);
        throw new ParserException("Cannot convert parsed widget to " ~ T.stringof, "", 0, 0);
    }
    return res;
}

/// Tokenize source into array of tokens (excluding EOF)
Token[] tokenizeML(const(dstring[]) lines)
{
    string code = toUTF8(join(lines, "\n"));
    return tokenizeML(code);
}

/// Tokenize source into array of tokens (excluding EOF)
Token[] tokenizeML(const(string[]) lines)
{
    string code = join(lines, "\n");
    return tokenizeML(code);
}

/// Tokenize source into array of tokens (excluding EOF)
Token[] tokenizeML(string code)
{
    Token[] res;
    auto tokenizer = Tokenizer(code, "");
    while (true)
    {
        auto token = tokenizer.nextToken();
        if (token.type == TokenType.eof)
            break;
        res ~= token;
    }
    return res;
}

/// Parser exception - unknown (unregistered) widget name
class UnknownWidgetException : ParserException
{
    protected string _objectName;

    @property string objectName()
    {
        return _objectName;
    }

    this(string msg, string objectName, string file, int line, int pos)
    {
        super(msg is null ? "Unknown widget name: " ~ objectName : msg, file, line, pos);
        _objectName = objectName;
    }
}

/// Parser exception - unknown property for widget
class UnknownPropertyException : UnknownWidgetException
{
    protected string _propName;

    @property string propName()
    {
        return _propName;
    }

    this(string msg, string objectName, string propName, string file, int line, int pos)
    {
        super(msg is null ? "Unknown property " ~ objectName ~ "." ~ propName : msg, objectName, file, line, pos);
    }
}

struct MLParser
{
private:
    string _code;
    string _filename;
    bool _ownContext;
    Widget _context;
    Widget _currentWidget;
    Tokenizer* _tokenizer;
    SList!Widget _treeStack;

    this(string code, string filename = "", Widget context = null)
    {
        _code = code;
        _filename = filename;
        _context = context;
        _tokenizer = new Tokenizer(code, filename);
    }

    Token _token;

    /// Move to next token
    void nextToken()
    {
        _token = _tokenizer.nextToken();
        //Log.d("parsed token: ", _token.type, " ", _token.line, ":", _token.pos, " ", _token.text);
    }

    /// Throw exception if current token is eof
    void checkNoEof()
    {
        if (_token.type == TokenType.eof)
            error("unexpected end of file");
    }

    /// Move to next token, throw exception if eof
    void nextTokenNoEof()
    {
        nextToken();
        checkNoEof();
    }

    void skipWhitespaceAndEols()
    {
        while (true)
        {
            if (_token.type != TokenType.eol && _token.type != TokenType.whitespace && _token.type != TokenType.comment)
                break;
            nextToken();
        }
        if (_token.type == TokenType.error)
            error("error while parsing ML code");
    }

    void skipWhitespaceAndEolsNoEof()
    {
        skipWhitespaceAndEols();
        checkNoEof();
    }

    void skipWhitespaceNoEof()
    {
        skipWhitespace();
        checkNoEof();
    }

    void skipWhitespace()
    {
        while (true)
        {
            if (_token.type != TokenType.whitespace && _token.type != TokenType.comment)
                break;
            nextToken();
        }
        if (_token.type == TokenType.error)
            error("error while parsing ML code");
    }

    void error(string msg)
    {
        _tokenizer.emitError(msg);
    }

    void unknownObjectError(string objectName)
    {
        throw new UnknownWidgetException("Unknown widget type " ~ objectName ~ _tokenizer.getContextSource(),
                objectName, _tokenizer.filename, _tokenizer.line, _tokenizer.pos);
    }

    void unknownPropertyError(string objectName, string propName)
    {
        throw new UnknownPropertyException(
                "Unknown property " ~ objectName ~ "." ~ propName ~ _tokenizer.getContextSource(),
                objectName, propName, _tokenizer.filename, _tokenizer.line, _tokenizer.pos);
    }

    public Widget createWidget(string name)
    {
        auto metadata = findWidgetMetadata(name);
        if (!metadata)
            error("Cannot create widget " ~ name ~ " : unregistered widget class");
        return metadata.create();
    }

    void createContext(string name)
    {
        if (_context)
            error("Context widget is already specified, but identifier " ~ name ~ " is found");
        _context = createWidget(name);
        _ownContext = true;
    }

    int applySuffix(int value, string suffix)
    {
        if (suffix.length > 0)
        {
            if (suffix == "px")
            {
                // do nothing, value is in px by default
            }
            else if (suffix == "pt")
            {
                value = makePointSize(value);
            }
            else if (suffix == "m" || suffix == "em")
            {
                // todo: implement EMs
                value = makePointSize(value);
            }
            else if (suffix == "%")
            {
                value = makePercentSize(value);
            }
            else
                error("unknown number suffix: " ~ suffix);
        }
        return value;
    }

    void setIntProperty(string propName, int value, string suffix = null)
    {
        value = applySuffix(value, suffix);
        if (!_currentWidget.setIntProperty(propName, value))
            error("unknown int property " ~ propName);
    }

    void setBoolProperty(string propName, bool value)
    {
        if (!_currentWidget.setBoolProperty(propName, value))
            error("unknown int property " ~ propName);
    }

    void setFloatProperty(string propName, double value)
    {
        if (!_currentWidget.setDoubleProperty(propName, value))
            error("unknown double property " ~ propName);
    }

    void setStringListValueProperty(string propName, StringListValue[] values)
    {
        if (!_currentWidget.setStringListValueListProperty(propName, values))
            error("unknown string list property " ~ propName);
    }

    void setRectOffsetProperty(string propName, RectOffset value)
    {
        if (!_currentWidget.setRectOffsetProperty(propName, value))
            error("unknown Rect property " ~ propName);
    }

    void setStringProperty(string propName, string value)
    {
        if (propName == "id" || propName == "styleID" || propName == "backgroundImageID")
        {
            if (!_currentWidget.setStringProperty(propName, value))
                error("cannot set " ~ propName ~ " property for widget");
            return;
        }

        dstring v = toUTF32(value);
        if (!_currentWidget.setDstringProperty(propName, v))
        {
            if (!_currentWidget.setStringProperty(propName, value))
                error("unknown string property " ~ propName);
        }
    }

    void setIdentProperty(string propName, string value)
    {
        if (propName == "id" || propName == "styleID" || propName == "backgroundImageID")
        {
            if (!_currentWidget.setStringProperty(propName, value))
                error("cannot set id property for widget");
            return;
        }

        if (value == "true")
            setBoolProperty(propName, true);
        else if (value == "false")
            setBoolProperty(propName, false);
//         else if (value == "fill" || value == "FILL")
//             setIntProperty(propName, SizePolicy.fill);
//         else if (value == "wrap" || value == "WRAP")
//             setIntProperty(propName, SizePolicy.wrap);
        else if (value == "left" || value == "Left")
            setIntProperty(propName, Align.left);
        else if (value == "right" || value == "Right")
            setIntProperty(propName, Align.right);
        else if (value == "top" || value == "Top")
            setIntProperty(propName, Align.top);
        else if (value == "bottom" || value == "Bottom")
            setIntProperty(propName, Align.bottom);
        else if (value == "hcenter" || value == "HCenter")
            setIntProperty(propName, Align.hcenter);
        else if (value == "vcenter" || value == "VCenter")
            setIntProperty(propName, Align.vcenter);
        else if (value == "center" || value == "Center")
            setIntProperty(propName, Align.center);
        else if (value == "topleft" || value == "TopLeft")
            setIntProperty(propName, Align.topleft);
        else if (propName == "orientation" && (value == "vertical" || value == "Vertical"))
            setIntProperty(propName, Orientation.vertical);
        else if (propName == "orientation" && (value == "horizontal" || value == "Horizontal"))
            setIntProperty(propName, Orientation.horizontal);
        else if (!_currentWidget.setStringProperty(propName, value))
            error("unknown ident property " ~ propName);
    }

    void parseRectProperty(string propName)
    {
        // current token is Rect
        int[4] values = [0, 0, 0, 0];
        nextToken();
        skipWhitespaceAndEolsNoEof();
        if (_token.type != TokenType.curlyOpen)
            error("{ expected after Rect");
        nextToken();
        skipWhitespaceAndEolsNoEof();
        int index = 0;
        while (true)
        {
            if (_token.type == TokenType.curlyClose)
                break;
            if (_token.type == TokenType.integer)
            {
                if (index >= 4)
                    error("too many values in Rect");
                int n = applySuffix(_token.intvalue, _token.text);
                values[index++] = n;
                nextToken();
                skipWhitespaceAndEolsNoEof();
                if (_token.type == TokenType.comma || _token.type == TokenType.semicolon)
                {
                    nextToken();
                    skipWhitespaceAndEolsNoEof();
                }
            }
            else if (_token.type == TokenType.ident)
            {
                string name = _token.text;
                nextToken();
                skipWhitespaceAndEolsNoEof();
                if (_token.type != TokenType.colon)
                    error(": expected after property name " ~ name ~ " in Rect definition");
                nextToken();
                skipWhitespaceNoEof();
                if (_token.type != TokenType.integer)
                    error("integer expected as Rect property value");
                int n = applySuffix(_token.intvalue, _token.text);

                if (name == "left")
                    values[0] = n;
                else if (name == "top")
                    values[1] = n;
                else if (name == "right")
                    values[2] = n;
                else if (name == "bottom")
                    values[3] = n;
                else
                    error("unknown property " ~ name ~ " in Rect");

                nextToken();
                skipWhitespaceNoEof();
                if (_token.type == TokenType.comma || _token.type == TokenType.semicolon)
                {
                    nextToken();
                    skipWhitespaceAndEolsNoEof();
                }
            }
            else
            {
                error("invalid Rect definition");
            }

        }
        setRectOffsetProperty(propName, RectOffset(values[0], values[1], values[2], values[3]));
    }

    // something in []
    void parseArrayProperty(string propName)
    {
        // current token is Rect
        nextToken();
        skipWhitespaceAndEolsNoEof();
        StringListValue[] values;
        while (true)
        {
            if (_token.type == TokenType.squareClose)
                break;
            if (_token.type == TokenType.integer)
            {
                if (_token.text.length)
                    error("Integer literal suffixes not allowed for [] items");
                StringListValue value;
                value.intID = _token.intvalue;
                value.label = to!dstring(_token.intvalue);
                values ~= value;
                nextToken();
                skipWhitespaceAndEolsNoEof();
                if (_token.type == TokenType.comma || _token.type == TokenType.semicolon)
                {
                    nextToken();
                    skipWhitespaceAndEolsNoEof();
                }
            }
            else if (_token.type == TokenType.ident)
            {
                string name = _token.text;

                StringListValue value;
                value.stringID = name;
                value.label = name.toUTF32;
                values ~= value;

                nextToken();
                skipWhitespaceAndEolsNoEof();

                if (_token.type == TokenType.comma || _token.type == TokenType.semicolon)
                {
                    nextToken();
                    skipWhitespaceAndEolsNoEof();
                }
            }
            else if (_token.type == TokenType.str)
            {
                string name = _token.text;

                StringListValue value;
                value.stringID = name;
                value.label = name.toUTF32;
                values ~= value;

                nextToken();
                skipWhitespaceAndEolsNoEof();

                if (_token.type == TokenType.comma || _token.type == TokenType.semicolon)
                {
                    nextToken();
                    skipWhitespaceAndEolsNoEof();
                }
            }
            else
            {
                error("invalid [] item");
            }

        }
        setStringListValueProperty(propName, values);
    }

    void parseProperty()
    {
        if (_token.type != TokenType.ident)
            error("identifier expected");
        string propName = _token.text;
        nextToken();
        skipWhitespaceNoEof();
        if (_token.type == TokenType.colon)
        { // :
            nextTokenNoEof(); // skip :
            skipWhitespaceNoEof();
            if (_token.type == TokenType.integer)
                setIntProperty(propName, _token.intvalue, _token.text);
            else if (_token.type == TokenType.minus || _token.type == TokenType.plus)
            {
                int sign = _token.type == TokenType.minus ? -1 : 1;
                nextTokenNoEof(); // skip :
                skipWhitespaceNoEof();
                if (_token.type == TokenType.integer)
                {
                    setIntProperty(propName, _token.intvalue * sign, _token.text);
                }
                else if (_token.type == TokenType.floating)
                {
                    setFloatProperty(propName, _token.floatvalue * sign);
                }
                else
                    error("number expected after + and -");
            }
            else if (_token.type == TokenType.floating)
                setFloatProperty(propName, _token.floatvalue);
            else if (_token.type == TokenType.squareOpen)
                parseArrayProperty(propName);
            else if (_token.type == TokenType.str)
                setStringProperty(propName, _token.text);
            else if (_token.type == TokenType.ident)
            {
                if (_token.text == "Rect")
                {
                    parseRectProperty(propName);
                }
                else
                {
                    setIdentProperty(propName, _token.text);
                }
            }
            else
                error("int, float, string or identifier are expected as property value");
            nextTokenNoEof();
            skipWhitespaceNoEof();
            if (_token.type == TokenType.semicolon)
            {
                // separated by ;
                nextTokenNoEof();
                skipWhitespaceAndEolsNoEof();
                return;
            }
            else if (_token.type == TokenType.eol)
            {
                nextTokenNoEof();
                skipWhitespaceAndEolsNoEof();
                return;
            }
            else if (_token.type == TokenType.curlyClose)
            {
                // it was last property in object
                return;
            }
            error("; eol or } expected after property definition");
        }
        else if (_token.type == TokenType.curlyOpen)
        { // { -- start of object
            Widget s = createWidget(propName);
            parseWidgetProperties(s);
        }
        else
        {
            error(": or { expected after identifier");
        }
    }

    void parseWidgetProperties(Widget w)
    {
        if (_token.type != TokenType.curlyOpen) // {
            error("{ is expected");
        _treeStack.insertFront(w);
        if (_currentWidget)
            _currentWidget.addChild(w);
        _currentWidget = w;
        nextToken(); // skip {
        skipWhitespaceAndEols();
        while (true)
        {
            checkNoEof();
            if (_token.type == TokenType.curlyClose) // end of object's internals
                break;
            parseProperty();
        }
        if (_token.type != TokenType.curlyClose) // {
            error("{ is expected");
        nextToken(); // skip }
        skipWhitespaceAndEols();
        _treeStack.removeFront();
        _currentWidget = !_treeStack.empty ? _treeStack.front : null;
    }

    Widget parse()
    {
        try
        {
            nextToken();
            skipWhitespaceAndEols();
            if (_token.type == TokenType.ident)
            {
                createContext(_token.text);
                nextToken();
                skipWhitespaceAndEols();
            }
            if (_token.type != TokenType.curlyOpen) // {
                error("{ is expected");
            if (!_context)
                error("No context widget is specified!");
            parseWidgetProperties(_context);

            skipWhitespaceAndEols();
            if (_token.type != TokenType.eof) // {
                error("end of file expected");
            return _context;
        }
        catch (Exception e)
        {
            Log.e("exception while parsing ML", e);
            if (_context && _ownContext)
                destroy(_context);
            _context = null;
            throw e;
        }
    }

    ~this()
    {
        eliminate(_tokenizer);
    }

}
