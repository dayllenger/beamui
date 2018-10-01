/**

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.computed_style;

import beamui.core.functions;
import beamui.core.types;
import beamui.core.units;
import beamui.graphics.colors;
import beamui.graphics.drawables;
import beamui.graphics.fonts;
import beamui.style.style;
import beamui.style.types;

struct ComputedStyle
{
    @property
    {
        //===================================================
        // layout properties

        int width() const
        {
            return _width.toDevice;
        }
        /// ditto
        void width(Dimension value)
        {
            _width = value;
            elementStyle.width = value;
        }
        int height() const
        {
            return _height.toDevice;
        }
        /// ditto
        void height(Dimension value)
        {
            _height = value;
            elementStyle.height = value;
        }
        int minWidth() const
        {
            return _minWidth.toDevice;
        }
        /// Min width constraint, Dimension.zero or Dimension.none to unset limit
        void minWidth(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.zero;
            _minWidth = value;
            elementStyle.minWidth = value;
        }
        int maxWidth() const
        {
            return _maxWidth.toDevice;
        }
        /// Max width constraint, Dimension.none to unset limit
        void maxWidth(Dimension value)
        {
            _maxWidth = value;
            elementStyle.maxWidth = value;
        }
        int minHeight() const
        {
            return _minHeight.toDevice;
        }
        /// Min height constraint, Dimension.zero or Dimension.none to unset limit
        void minHeight(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.zero;
            _minHeight = value;
            elementStyle.minHeight = value;
        }
        int maxHeight() const
        {
            return _maxHeight.toDevice;
        }
        /// Max height constraint, Dimension.none to unset limit
        void maxHeight(Dimension value)
        {
            _maxHeight = value;
            elementStyle.maxHeight = value;
        }
        int weight() const pure
        {
            return _weight;
        }
        /// ditto
        void weight(int value)
        {
            _weight = value;
            elementStyle.weight = value;
        }

        Align alignment() const
        {
            return _alignment;
        }
        /// ditto
        void alignment(Align value)
        {
            _alignment = value;
            elementStyle.alignment = value;
        }
        Insets margins() const
        {
            return Insets(0);
        }
        /// ditto
        void margins(Insets value)
        {
            _margins = value;
            elementStyle.margins = value;
        }
        Insets padding() const
        {
            return _padding.toPixels;
        }
        /// ditto
        void padding(Insets value)
        {
            _padding = value;
            elementStyle.padding = value;
        }

        //===================================================
        // background properties

        uint backgroundColor() const pure
        {
            return _backgroundColor;
        }
        /// ditto
        void backgroundColor(uint value)
        {
            _backgroundColor = value;
            _backgroundDrawable.clear();
            elementStyle.backgroundColor = value;
        }
        inout(Drawable) backgroundImage() inout pure
        {
            return _backgroundImage;
        }
        /// ditto
        void backgroundImage(Drawable value)
        {
            _backgroundImage = value;
            _backgroundDrawable.clear();
            elementStyle.backgroundImage = value;
        }
        inout(BorderDrawable) border() inout pure
        {
            return _border;
        }
        /// ditto
        void border(BorderDrawable value)
        {
            _border = value;
            _backgroundDrawable.clear();
            elementStyle.border = value;
        }
        inout(BoxShadowDrawable) boxShadow() inout pure
        {
            return _boxShadow;
        }
        /// ditto
        void boxShadow(BoxShadowDrawable value)
        {
            _boxShadow = value;
            _backgroundDrawable.clear();
            elementStyle.boxShadow = value;
        }

        //===================================================
        // text properties

        string fontFace() const pure
        {
            return _fontFace;
        }
        /// ditto
        void fontFace(string value)
        {
            if (_fontFace != value)
                _font.clear();
            _fontFace = value;
            elementStyle.fontFace = value;
        }
        FontFamily fontFamily() const pure
        {
            return _fontFamily;
        }
        /// ditto
        void fontFamily(FontFamily value)
        {
            if (_fontFamily != value)
                _font.clear();
            _fontFamily = value;
            elementStyle.fontFamily = value;
        }
        int fontSize() const
        {
            return _fontSize.toDevice;
        }
        /// ditto
        void fontSize(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.pt(9);

            if (_fontSize != value)
                _font.clear();
            _fontSize = value;
            elementStyle.fontSize = value;
        }
        FontStyle fontStyle() const pure
        {
            return _fontStyle;
        }
        /// ditto
        void fontStyle(FontStyle value)
        {
            if (_fontStyle != value)
                _font.clear();
            _fontStyle = value;
            elementStyle.fontStyle = value;
        }
        ushort fontWeight() const pure
        {
            return _fontWeight;
        }
        /// ditto
        void fontWeight(ushort value)
        {
            if (_fontWeight != value)
                _font.clear();
            _fontWeight = value;
            elementStyle.fontWeight = value;
        }
        TextFlag textFlags() const pure
        {
            return _textFlags;
        }
        /// ditto
        void textFlags(TextFlag value)
        {
            _textFlags = value;
            elementStyle.textFlags = value;
        }
        int maxLines() const pure
        {
            return _maxLines;
        }
        /// ditto
        void maxLines(int value)
        {
            _maxLines = value;
            elementStyle.maxLines = value;
        }

        //===================================================
        // color properties

        /// Alpha (0 = opaque ... 255 = transparent)
        ubyte alpha() const pure
        {
            return _alpha;
        }
        /// ditto
        void alpha(ubyte value)
        {
            _alpha = value;
            elementStyle.alpha = value;
        }
        uint textColor() const pure
        {
            return _textColor;
        }
        /// ditto
        void textColor(uint value)
        {
            _textColor = value;
            elementStyle.textColor = value;
        }
        /// Colors to draw focus rectangle (one for solid, two for vertical gradient) or null if no focus rect should be drawn for style
        uint focusRectColor() const pure
        {
            return _focusRectColor;
        }
        /// ditto
        void focusRectColor(uint value)
        {
            _focusRectColor = value;
            elementStyle.focusRectColor = value;
        }

        //===================================================
        // DERIVATIVES

        /// Get background drawable for this style
        ref DrawableRef backgroundDrawable() const
        {
            ComputedStyle* s = cast(ComputedStyle*)&this;
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
            ComputedStyle* s = cast(ComputedStyle*)&this;
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

        //===================================================

        Style elementStyle()
        {
            if (!_elementStyle)
                _elementStyle = new Style;
            return _elementStyle;
        }
    }

    private
    {
        // layout
        Dimension _width = void;
        Dimension _height = void;
        Dimension _minWidth = void;
        Dimension _maxWidth = void;
        Dimension _minHeight = void;
        Dimension _maxHeight = void;
        int _weight = void;
        Align _alignment = void;
        Insets _margins = void;
        Insets _padding = void;
        // background
        uint _backgroundColor = void;
        Drawable _backgroundImage = void;
        BorderDrawable _border = void;
        BoxShadowDrawable _boxShadow = void;
        // text
        string _fontFace = void;
        FontFamily _fontFamily = void;
        Dimension _fontSize = void;
        FontStyle _fontStyle = void;
        ushort _fontWeight = void;
        TextFlag _textFlags = void;
        int _maxLines = void;
        // colors
        ubyte _alpha = void;
        uint _textColor = void;
        uint _focusRectColor = void;

        DrawableRef _backgroundDrawable;
        FontRef _font;

        Style _elementStyle;
    }

    @disable this();

    this(Selector initial)
    {
        recompute(initial);
    }

    ~this()
    {
        eliminate(_backgroundImage);
        eliminate(_border);
        eliminate(_boxShadow);
        _font.clear();
        _backgroundDrawable.clear();
        eliminate(_elementStyle);
    }

    void recompute(Selector selector)
    {
    }

    void onThemeChanged()
    {
        _backgroundDrawable.clear();
        _font.clear();
    }
}
