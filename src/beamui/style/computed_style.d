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
import beamui.style.theme : currentTheme;
import beamui.style.types;

struct ComputedStyle
{
    @property
    {
        //===================================================
        // layout properties

        int width() const
        {
            return sp.width.toDevice;
        }
        /// ditto
        void width(Dimension value)
        {
            sp.width = value;
            elementStyle.width = value;
        }
        int height() const
        {
            return sp.height.toDevice;
        }
        /// ditto
        void height(Dimension value)
        {
            sp.height = value;
            elementStyle.height = value;
        }
        int minWidth() const
        {
            return sp.minWidth.toDevice;
        }
        /// Min width constraint, Dimension.zero or Dimension.none to unset limit
        void minWidth(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.zero;
            sp.minWidth = value;
            elementStyle.minWidth = value;
        }
        int maxWidth() const
        {
            return sp.maxWidth.toDevice;
        }
        /// Max width constraint, Dimension.none to unset limit
        void maxWidth(Dimension value)
        {
            sp.maxWidth = value;
            elementStyle.maxWidth = value;
        }
        int minHeight() const
        {
            return sp.minHeight.toDevice;
        }
        /// Min height constraint, Dimension.zero or Dimension.none to unset limit
        void minHeight(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.zero;
            sp.minHeight = value;
            elementStyle.minHeight = value;
        }
        int maxHeight() const
        {
            return sp.maxHeight.toDevice;
        }
        /// Max height constraint, Dimension.none to unset limit
        void maxHeight(Dimension value)
        {
            sp.maxHeight = value;
            elementStyle.maxHeight = value;
        }
        int weight() const pure
        {
            return sp.weight;
        }
        /// ditto
        void weight(int value)
        {
            sp.weight = value;
            elementStyle.weight = value;
        }

        Align alignment() const
        {
            return sp.alignment;
        }
        /// ditto
        void alignment(Align value)
        {
            sp.alignment = value;
            elementStyle.alignment = value;
        }
        Insets margins() const
        {
            return Insets(0);
        }
        /// ditto
        void margins(Insets value)
        {
            sp.marginTop = Dimension(value.top);
            sp.marginRight = Dimension(value.right);
            sp.marginBottom = Dimension(value.bottom);
            sp.marginLeft = Dimension(value.left);
            elementStyle.marginTop = Dimension(value.top);
            elementStyle.marginRight = Dimension(value.right);
            elementStyle.marginBottom = Dimension(value.bottom);
            elementStyle.marginLeft = Dimension(value.left);
        }
        Insets padding() const
        {
            return Insets(sp.paddingTop.toDevice, sp.paddingRight.toDevice,
                          sp.paddingBottom.toDevice, sp.paddingLeft.toDevice);
        }
        /// ditto
        void padding(Insets value)
        {
            sp.paddingTop = Dimension(value.top);
            sp.paddingRight = Dimension(value.right);
            sp.paddingBottom = Dimension(value.bottom);
            sp.paddingLeft = Dimension(value.left);
            elementStyle.paddingTop = Dimension(value.top);
            elementStyle.paddingRight = Dimension(value.right);
            elementStyle.paddingBottom = Dimension(value.bottom);
            elementStyle.paddingLeft = Dimension(value.left);
        }

        //===================================================
        // background properties

        uint borderColor() const pure
        {
            return sp.borderColor;
        }
        /// ditto
        void borderColor(uint value)
        {
            sp.borderColor = value;
            _backgroundDrawable.clear();
            elementStyle.borderColor = value;
        }
        Insets borderWidth() const
        {
            return Insets(sp.borderWidthTop.toDevice, sp.borderWidthRight.toDevice,
                          sp.borderWidthBottom.toDevice, sp.borderWidthLeft.toDevice);
        }
        /// ditto
        void borderWidth(Insets value)
        {
            _backgroundDrawable.clear();
            sp.borderWidthTop = Dimension(value.top);
            sp.borderWidthRight = Dimension(value.right);
            sp.borderWidthBottom = Dimension(value.bottom);
            sp.borderWidthLeft = Dimension(value.left);
            elementStyle.borderWidthTop = Dimension(value.top);
            elementStyle.borderWidthRight = Dimension(value.right);
            elementStyle.borderWidthBottom = Dimension(value.bottom);
            elementStyle.borderWidthLeft = Dimension(value.left);
        }
        uint backgroundColor() const pure
        {
            return sp.backgroundColor;
        }
        /// ditto
        void backgroundColor(uint value)
        {
            sp.backgroundColor = value;
            _backgroundDrawable.clear();
            elementStyle.backgroundColor = value;
        }
        inout(Drawable) backgroundImage() inout pure
        {
            return sp.backgroundImage;
        }
        /// ditto
        void backgroundImage(Drawable value)
        {
            sp.backgroundImage = value;
            _backgroundDrawable.clear();
            elementStyle.backgroundImage = value;
        }
        inout(BoxShadowDrawable) boxShadow() inout pure
        {
            return sp.boxShadow;
        }
        /// ditto
        void boxShadow(BoxShadowDrawable value)
        {
            sp.boxShadow = value;
            _backgroundDrawable.clear();
            elementStyle.boxShadow = value;
        }

        //===================================================
        // text properties

        string fontFace() const pure
        {
            return sp.fontFace;
        }
        /// ditto
        void fontFace(string value)
        {
            if (sp.fontFace != value)
                _font.clear();
            sp.fontFace = value;
            elementStyle.fontFace = value;
        }
        FontFamily fontFamily() const pure
        {
            return sp.fontFamily;
        }
        /// ditto
        void fontFamily(FontFamily value)
        {
            if (sp.fontFamily != value)
                _font.clear();
            sp.fontFamily = value;
            elementStyle.fontFamily = value;
        }
        int fontSize() const
        {
            return sp.fontSize.toDevice;
        }
        /// ditto
        void fontSize(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.pt(9);

            if (sp.fontSize != value)
                _font.clear();
            sp.fontSize = value;
            elementStyle.fontSize = value;
        }
        FontStyle fontStyle() const pure
        {
            return sp.fontStyle;
        }
        /// ditto
        void fontStyle(FontStyle value)
        {
            if (sp.fontStyle != value)
                _font.clear();
            sp.fontStyle = value;
            elementStyle.fontStyle = value;
        }
        ushort fontWeight() const pure
        {
            return sp.fontWeight;
        }
        /// ditto
        void fontWeight(ushort value)
        {
            if (sp.fontWeight != value)
                _font.clear();
            sp.fontWeight = value;
            elementStyle.fontWeight = value;
        }
        TextFlag textFlags() const pure
        {
            return sp.textFlags;
        }
        /// ditto
        void textFlags(TextFlag value)
        {
            sp.textFlags = value;
            elementStyle.textFlags = value;
        }
        int maxLines() const pure
        {
            return sp.maxLines;
        }
        /// ditto
        void maxLines(int value)
        {
            sp.maxLines = value;
            elementStyle.maxLines = value;
        }

        //===================================================
        // color properties

        /// Alpha (0 = opaque ... 255 = transparent)
        ubyte alpha() const pure
        {
            return sp.alpha;
        }
        /// ditto
        void alpha(ubyte value)
        {
            sp.alpha = value;
            elementStyle.alpha = value;
        }
        uint textColor() const pure
        {
            return sp.textColor;
        }
        /// ditto
        void textColor(uint value)
        {
            sp.textColor = value;
            elementStyle.textColor = value;
        }
        /// Colors to draw focus rectangle (one for solid, two for vertical gradient) or null if no focus rect should be drawn for style
        uint focusRectColor() const pure
        {
            return sp.focusRectColor;
        }
        /// ditto
        void focusRectColor(uint value)
        {
            sp.focusRectColor = value;
            elementStyle.focusRectColor = value;
        }

        //===================================================
        // DERIVATIVES

        /// Get background drawable for this style
        DrawableRef backgroundDrawable() const
        {
            ComputedStyle* s = cast(ComputedStyle*)&this;
            if (!s._backgroundDrawable.isNull)
                return s._backgroundDrawable;

            // create border drawable if needed
            BorderDrawable borders;
            uint borderColor = s.borderColor;
            Insets borderWidth = s.borderWidth;
            if (borderColor != COLOR_UNSPECIFIED && borderWidth != Insets(0))
            {
                borders = new BorderDrawable(borderColor, borderWidth);
            }
            uint color = backgroundColor;
            Drawable image = s.backgroundImage;
            BoxShadowDrawable shadows = s.boxShadow;
            // here we can only create drawables, we can't capture existing one e.g. background image
            if (borders || shadows || image)
            {
                s._backgroundDrawable = new CombinedDrawable(color, image, borders, shadows);
            }
            else
            {
                s._backgroundDrawable = isFullyTransparentColor(color) ?
                    new EmptyDrawable : new SolidFillDrawable(color);
            }
            return s._backgroundDrawable;
        }

        /// Get font
        FontRef font() const
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

        /// Widget's own style
        Style elementStyle()
        {
            if (!_elementStyle)
                _elementStyle = new Style;
            return _elementStyle;
        }
    }

    private
    {
        StyleProperties sp = void;
        Style _elementStyle;

        DrawableRef _backgroundDrawable;
        FontRef _font;
    }

    ~this()
    {
        _backgroundDrawable.clear();
        _font.clear();
        eliminate(_elementStyle);
    }

    /// Resolve style cascading and update all properties
    void recompute(Selector selector)
    {
        Style[] chain = currentTheme.selectChain(selector);

        if (selector.state != State.normal)
        {
            Style last = chain[$ - 1];
            Style st = last.forState(selector.state);
            if (st !is last)
                chain ~= st;
        }
        if (_elementStyle)
            chain ~= _elementStyle;

        _backgroundDrawable.clear();
        _font.clear();
        static foreach (i; 0 .. StyleProperties.tupleof.length)
        {
            // find nearest written property
            foreach_reverse (st; chain)
            {
                if (st.written[i])
                {
                    // copy it directly
                    sp.tupleof[i] = st.properties.tupleof[i];
                    break;
                }
            }
        }
    }
}
