/**

Synopsis:
---
import beamui.style.style;
---

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.style;

import beamui.core.functions;
import beamui.core.logger;
import beamui.core.types;
import beamui.core.units;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.graphics.fonts;
import beamui.style.types;

/// Style - widget property container
final class Style
{
private:
    // layout
    Dimension _width = Dimension.none;
    Dimension _height = Dimension.none;
    Dimension _minWidth = Dimension.zero;
    Dimension _maxWidth = Dimension.none;
    Dimension _minHeight = Dimension.zero;
    Dimension _maxHeight = Dimension.none;
    int _weight = 1;
    Align _alignment = Align.topleft;
    Insets _margins = Insets(0);
    Insets _padding = Insets(0);
    // background
    uint _backgroundColor = COLOR_TRANSPARENT;
    Drawable _backgroundImage;
    BorderDrawable _border;
    BoxShadowDrawable _boxShadow;
    // text
    string _fontFace = "Arial"; // TODO(dlangui): from settings
    FontFamily _fontFamily = FontFamily.sans_serif;
    Dimension _fontSize = Dimension.pt(9); // TODO(dlangui): from settings or screen properties / DPI
    FontStyle _fontStyle = FontStyle.normal;
    ushort _fontWeight = 400;
    TextFlag _textFlags = TextFlag.unspecified;
    int _maxLines = 1;
    // colors
    ubyte _alpha = 0;
    uint _textColor = 0x000000; // black
    uint _focusRectColor = COLOR_UNSPECIFIED; // disabled by default
    // 24 overall

    /// This is a bitmap which indicates which style properties are overriden (true) or inherited (false)
    bool[24] overrideMap;
    // WARNING: if you're adding a new property, carefully check all indices of overrideMap in the code

    FontRef _font;
    DrawableRef _backgroundDrawable;

package (beamui.style):
    /// State descriptor
    struct StateStyle
    {
        Style s;
        State specified;
        State enabled;
    }

    Style parent;
    StateStyle[] stateStyles;

public:
    /// Find substyle based on widget state (e.g. focused, pressed, ...)
    const(Style) forState(State state) const
    {
        if (state == State.normal)
            return this;
        foreach (s; stateStyles)
        {
            if ((s.specified & state) == s.enabled)
                return s.s;
        }
        // not found - fallback to normal
        return this;
    }

@property
{
    //===================================================
    // SETTERS
    //===================================================
    // layout properties

    Style width(Dimension value)
    {
        _width = value;
        overrideMap[0] = true;
        return this;
    }
    Style height(Dimension value)
    {
        _height = value;
        overrideMap[1] = true;
        return this;
    }
    /// Min width constraint, Dimension.zero or Dimension.none to unset limit
    Style minWidth(Dimension value)
    {
        if (value == Dimension.none)
            value = Dimension.zero;
        _minWidth = value;
        overrideMap[2] = true;
        return this;
    }
    /// Max width constraint, Dimension.none to unset limit
    Style maxWidth(Dimension value)
    {
        _maxWidth = value;
        overrideMap[3] = true;
        return this;
    }
    /// Min height constraint, Dimension.zero or Dimension.none to unset limit
    Style minHeight(Dimension value)
    {
        if (value == Dimension.none)
            value = Dimension.zero;
        _minHeight = value;
        overrideMap[4] = true;
        return this;
    }
    /// Max height constraint, Dimension.none to unset limit
    Style maxHeight(Dimension value)
    {
        _maxHeight = value;
        overrideMap[5] = true;
        return this;
    }
    Style weight(int value)
    {
        _weight = value;
        overrideMap[6] = true;
        return this;
    }
    Style alignment(Align value)
    {
        _alignment = value;
        overrideMap[7] = true;
        return this;
    }
    Style margins(Insets value)
    {
        _margins = value;
        overrideMap[8] = true;
        return this;
    }
    Style padding(Insets value)
    {
        _padding = value;
        overrideMap[9] = true;
        return this;
    }

    //===================================================
    // background properties

    Style backgroundColor(uint value)
    {
        _backgroundColor = value;
        _backgroundDrawable.clear();
        overrideMap[10] = true;
        return this;
    }
    Style backgroundImage(Drawable value)
    {
        _backgroundImage = value;
        _backgroundDrawable.clear();
        overrideMap[11] = true;
        return this;
    }
    Style border(BorderDrawable value)
    {
        _border = value;
        _backgroundDrawable.clear();
        overrideMap[12] = true;
        return this;
    }
    Style boxShadow(BoxShadowDrawable value)
    {
        _boxShadow = value;
        _backgroundDrawable.clear();
        overrideMap[13] = true;
        return this;
    }

    //===================================================
    // text properties

    Style fontFace(string value)
    {
        if (_fontFace != value)
            clearCachedObjects();
        _fontFace = value;
        overrideMap[14] = true;
        return this;
    }
    Style fontFamily(FontFamily value)
    {
        if (_fontFamily != value)
            clearCachedObjects();
        _fontFamily = value;
        overrideMap[15] = true;
        return this;
    }
    Style fontSize(Dimension value)
    {
        if (value == Dimension.none)
            value = Dimension.pt(9);

        if (_fontSize != value)
            clearCachedObjects();
        _fontSize = value;
        overrideMap[16] = true;
        return this;
    }
    Style fontStyle(FontStyle value)
    {
        if (_fontStyle != value)
            clearCachedObjects();
        _fontStyle = value;
        overrideMap[17] = true;
        return this;
    }
    Style fontWeight(ushort value)
    {
        if (_fontWeight != value)
            clearCachedObjects();
        _fontWeight = value;
        overrideMap[18] = true;
        return this;
    }
    Style textFlags(TextFlag value)
    {
        _textFlags = value;
        overrideMap[19] = true;
        return this;
    }
    Style maxLines(int value)
    {
        _maxLines = value;
        overrideMap[20] = true;
        return this;
    }

    //===================================================
    // color properties

    /// Alpha (0 = opaque ... 255 = transparent)
    Style alpha(ubyte value)
    {
        _alpha = value;
        overrideMap[21] = true;
        return this;
    }
    Style textColor(uint value)
    {
        _textColor = value;
        overrideMap[22] = true;
        return this;
    }
    /// Returns colors to draw focus rectangle (one for solid, two for vertical gradient) or null if no focus rect should be drawn for style
    Style focusRectColor(uint value)
    {
        _focusRectColor = value;
        overrideMap[23] = true;
        return this;
    }

    //===================================================
    // GETTERS
    //===================================================
    // layout properties

    int width() const
    {
        if (parent && !overrideMap[0])
            return parent.width;
        return _width.toDevice;
    }
    int height() const
    {
        if (parent && !overrideMap[1])
            return parent.height;
        return _height.toDevice;
    }
    int minWidth() const
    {
        if (parent && !overrideMap[2])
            return parent.minWidth;
        return _minWidth.toDevice;
    }
    int maxWidth() const
    {
        if (parent && !overrideMap[3])
            return parent.maxWidth;
        return _maxWidth.toDevice;
    }
    int minHeight() const
    {
        if (parent && !overrideMap[4])
            return parent.minHeight;
        return _minHeight.toDevice;
    }
    int maxHeight() const
    {
        if (parent && !overrideMap[5])
            return parent.maxHeight;
        return _maxHeight.toDevice;
    }
    int weight() const pure
    {
        if (parent && !overrideMap[6])
            return parent.weight;
        return _weight;
    }
    Align alignment() const
    {
        if (parent && !overrideMap[7])
            return parent.alignment;
        return _alignment;
    }
    Insets margins() const
    {
        if (parent && !overrideMap[8]) // FIXME: _stateMask || ????
            return parent.margins;
        return Insets(0);//_margins.toPixels;
    }
    Insets padding() const
    {
        if (parent && !overrideMap[9])
            return parent.padding;
        return _padding.toPixels;
    }

    //===================================================
    // background properties

    uint backgroundColor() const pure
    {
        if (parent && !overrideMap[10])
            return parent.backgroundColor;
        return _backgroundColor;
    }
    inout(Drawable) backgroundImage() inout pure
    {
        if (parent && !overrideMap[11])
            return parent.backgroundImage;
        return _backgroundImage;
    }
    inout(BorderDrawable) border() inout pure
    {
        if (parent && !overrideMap[12])
            return parent.border;
        return _border;
    }
    inout(BoxShadowDrawable) boxShadow() inout pure
    {
        if (parent && !overrideMap[13])
            return parent.boxShadow;
        return _boxShadow;
    }

    //===================================================
    // text properties

    string fontFace() const pure
    {
        if (parent && !overrideMap[14])
            return parent.fontFace;
        return _fontFace;
    }
    FontFamily fontFamily() const pure
    {
        if (parent && !overrideMap[15])
            return parent.fontFamily;
        return _fontFamily;
    }
    int fontSize() const
    {
        if (parent && !overrideMap[16])
            return parent.fontSize;
        int res = _fontSize.toDevice;
        if (_fontSize.is_em)
            return parent.fontSize * res / 100;
        if (_fontSize.is_percent)
            return parent.fontSize * res / 10000;
        return res;
    }
    FontStyle fontStyle() const pure
    {
        if (parent && !overrideMap[17])
            return parent.fontStyle;
        return _fontStyle;
    }
    ushort fontWeight() const pure
    {
        if (parent && !overrideMap[18])
            return parent.fontWeight;
        return _fontWeight;
    }
    TextFlag textFlags() const pure
    {
        if (parent && !overrideMap[19])
            return parent.textFlags;
        return _textFlags;
    }
    int maxLines() const pure
    {
        if (parent && !overrideMap[20])
            return parent.maxLines;
        return _maxLines;
    }

    //===================================================
    // color properties

    ubyte alpha() const pure
    {
        if (parent && !overrideMap[21])
            return parent.alpha;
        return _alpha;
    }
    uint textColor() const pure
    {
        if (parent && !overrideMap[22])
            return parent.textColor;
        return _textColor;
    }
    uint focusRectColor() const pure
    {
        if (parent && !overrideMap[23])
            return parent.focusRectColor;
        return _focusRectColor;
    }

    //===================================================
    // DERIVATIVES

    /// Get background drawable for this style
    ref DrawableRef backgroundDrawable() const
    {
        Style s = cast(Style)this;
        if (!s._backgroundDrawable.isNull)
            return s._backgroundDrawable;

        uint color = backgroundColor;
        Drawable image = s.backgroundImage;
        BorderDrawable borders = s.border;
        BoxShadowDrawable shadows = s.boxShadow;
        if (borders || shadows)
        {
            s._backgroundDrawable = new CombinedDrawable(color, image, borders, shadows);
        }
        else if (image)
        {
            s._backgroundDrawable = image;
        }
        else
        {
            s._backgroundDrawable = isFullyTransparentColor(color) ?
                new EmptyDrawable : new SolidFillDrawable(color);
        }
        return s._backgroundDrawable;
    }

    /// Get font
    ref FontRef font() const
    {
        Style s = cast(Style)this;
        if (!s._font.isNull)
            return s._font;
        s._font = FontManager.instance.getFont(fontSize, fontWeight, fontItalic, fontFamily, fontFace);
        return s._font;
    }

    /// Check if font style is italic
    bool fontItalic() const
    {
        return fontStyle == FontStyle.italic;
    }
}

    /// Reinherit modified (owned by widget) style to another parent
    void reinherit(Style newParent)
    {
        parent = newParent;
    }

    void onThemeChanged()
    {
        _font.clear();
        _backgroundDrawable.clear();
        foreach (s; stateStyles)
            s.s.onThemeChanged();
    }

    void clearCachedObjects()
    {
        onThemeChanged();
    }

    /// Print all style properties (for debugging purposes)
    debug void printStats() const
    {
        Log.d("--- Style stats ---");
        static foreach (i, p; [
            "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
            "weight", "alignment", "margins", "padding",
            "backgroundColor", "backgroundImage", "border", "boxShadow",
            "fontFace", "fontFamily", "fontSize", "fontStyle", "fontWeight",
            "textFlags", "maxLines",
            "alpha", "textColor", "focusRectColor"])
        {{
            static if (is(typeof(mixin("Style." ~ p)) == class)) // print only type of drawable
                enum msg = p ~ " ? typeid(this." ~ p ~ ").name : `-`";
            else
                enum msg = p;

            Log.d(overrideMap[i] ? p ~ " (o): " : p ~ ": ", mixin(msg));
        }}
    }

    debug @property static int instanceCount() { return _instanceCount; }

package (beamui.style):

    debug static __gshared int _instanceCount;

    this() pure
    {
        debug _instanceCount++;
        debug (resalloc)
            Log.d("Created style, count: ", _instanceCount);
    }

    ~this()
    {
        parent = null;
        foreach (s; stateStyles)
            eliminate(s.s);
        destroy(stateStyles);
        stateStyles = null;

        destroy(_backgroundImage);
        destroy(_border);
        destroy(_boxShadow);
        _font.clear();
        _backgroundDrawable.clear();

        debug _instanceCount--;
        debug (resalloc)
            Log.d("Destroyed style, count: ", _instanceCount);
    }

    /// Create a style with the same properties
    Style clone()
    {
        auto res = new Style;
        res._width = _width;
        res._height = _height;
        res._minWidth = _minWidth;
        res._maxWidth = _maxWidth;
        res._minHeight = _minHeight;
        res._maxHeight = _maxHeight;
        res._weight = _weight;
        res._alignment = _alignment;
        res._margins = _margins;
        res._padding = _padding;
        res._backgroundColor = _backgroundColor;
        res._backgroundImage = _backgroundImage;
        res._border = _border; // TODO: deep copy
        res._boxShadow = _boxShadow;
        res._fontFace = _fontFace;
        res._fontFamily = _fontFamily;
        res._fontSize = _fontSize;
        res._fontStyle = _fontStyle;
        res._fontWeight = _fontWeight;
        res._textFlags = _textFlags;
        res._maxLines = _maxLines;
        res._alpha = _alpha;
        res._textColor = _textColor;
        res._focusRectColor = _focusRectColor;
        res.overrideMap = overrideMap;
        return res;
    }

    /// Find exact existing state style or create new if no matched styles found
    Style getOrCreateState(State specified, State enabled)
    {
        if (specified == State.unspecified)
            return this;
        foreach (s; stateStyles)
            if (s.specified == specified && s.enabled == enabled)
                return s.s;
        // not found
        debug (styles)
            Log.d("Creating substate: ", specified);
        // TODO: inherit from parent state style
        // TODO: inherit from less specific state style
        auto s = new Style;
        s.parent = this;
        stateStyles ~= StateStyle(s, specified, enabled);

        import core.bitop;

        // sort state styles by state value and its bit count
        stateStyles.sort!((a, b) => a.specified * a.specified * popcnt(a.specified) >
                                    b.specified * b.specified * popcnt(b.specified));
        return s;
    }
}
