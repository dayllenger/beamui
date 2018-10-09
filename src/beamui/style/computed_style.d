/**

Copyright: dayllenger 2018
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.computed_style;

import beamui.core.animations;
import beamui.core.functions;
import beamui.core.logger;
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
            set!"width"(value);
            elementStyle.width = value;
        }
        int height() const
        {
            return sp.height.toDevice;
        }
        /// ditto
        void height(Dimension value)
        {
            set!"height"(value);
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
            set!"minWidth"(value);
            elementStyle.minWidth = value;
        }
        int maxWidth() const
        {
            return sp.maxWidth.toDevice;
        }
        /// Max width constraint, Dimension.none to unset limit
        void maxWidth(Dimension value)
        {
            set!"maxWidth"(value);
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
            set!"minHeight"(value);
            elementStyle.minHeight = value;
        }
        int maxHeight() const
        {
            return sp.maxHeight.toDevice;
        }
        /// Max height constraint, Dimension.none to unset limit
        void maxHeight(Dimension value)
        {
            set!"maxHeight"(value);
            elementStyle.maxHeight = value;
        }
        int weight() const pure
        {
            return sp.weight;
        }
        /// ditto
        void weight(int value)
        {
            set!"weight"(value);
            elementStyle.weight = value;
        }

        Align alignment() const
        {
            return sp.alignment;
        }
        /// ditto
        void alignment(Align value)
        {
            set!"alignment"(value);
            elementStyle.alignment = value;
        }
        Insets margins() const
        {
            return Insets(0);
        }
        /// ditto
        void margins(Insets value)
        {
            set!"marginTop"(Dimension(value.top));
            set!"marginRight"(Dimension(value.right));
            set!"marginBottom"(Dimension(value.bottom));
            set!"marginLeft"(Dimension(value.left));
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
            set!"paddingTop"(Dimension(value.top));
            set!"paddingRight"(Dimension(value.right));
            set!"paddingBottom"(Dimension(value.bottom));
            set!"paddingLeft"(Dimension(value.left));
            elementStyle.paddingTop = Dimension(value.top);
            elementStyle.paddingRight = Dimension(value.right);
            elementStyle.paddingBottom = Dimension(value.bottom);
            elementStyle.paddingLeft = Dimension(value.left);
        }

        //===================================================
        // background properties

        Color borderColor() const pure
        {
            return sp.borderColor;
        }
        /// ditto
        void borderColor(Color value)
        {
            set!"borderColor"(value);
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
            set!"borderWidthTop"(Dimension(value.top));
            set!"borderWidthRight"(Dimension(value.right));
            set!"borderWidthBottom"(Dimension(value.bottom));
            set!"borderWidthLeft"(Dimension(value.left));
            elementStyle.borderWidthTop = Dimension(value.top);
            elementStyle.borderWidthRight = Dimension(value.right);
            elementStyle.borderWidthBottom = Dimension(value.bottom);
            elementStyle.borderWidthLeft = Dimension(value.left);
        }
        Color backgroundColor() const pure
        {
            return sp.backgroundColor;
        }
        /// ditto
        void backgroundColor(Color value)
        {
            set!"backgroundColor"(value);
            elementStyle.backgroundColor = value;
        }
        inout(Drawable) backgroundImage() inout pure
        {
            return sp.backgroundImage;
        }
        /// ditto
        void backgroundImage(Drawable value)
        {
            set!"backgroundImage"(value);
            elementStyle.backgroundImage = value;
        }
        inout(BoxShadowDrawable) boxShadow() inout pure
        {
            return sp.boxShadow;
        }
        /// ditto
        void boxShadow(BoxShadowDrawable value)
        {
            set!"boxShadow"(value);
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
            set!"fontFace"(value);
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
            set!"fontFamily"(value);
            elementStyle.fontFamily = value;
        }
        int fontSize() const // TODO: em and percent
        {
            int res = sp.fontSize.toDevice;
            if (sp.fontSize.is_em)
                return res / 100;
            if (sp.fontSize.is_percent)
                return res / 10000;
            return res;
        }
        /// ditto
        void fontSize(Dimension value)
        {
            if (value == Dimension.none)
                value = Dimension.pt(9);

            if (sp.fontSize != value)
                _font.clear();
            set!"fontSize"(value);
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
            set!"fontStyle"(value);
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
            set!"fontWeight"(value);
            elementStyle.fontWeight = value;
        }
        TextFlag textFlags() const pure
        {
            return sp.textFlags;
        }
        /// ditto
        void textFlags(TextFlag value)
        {
            set!"textFlags"(value);
            elementStyle.textFlags = value;
        }
        TextAlign textAlign() const pure
        {
            return sp.textAlign;
        }
        /// ditto
        void textAlign(TextAlign value)
        {
            set!"textAlign"(value);
            elementStyle.textAlign = value;
        }
        int maxLines() const pure
        {
            return sp.maxLines;
        }
        /// ditto
        void maxLines(int value)
        {
            set!"maxLines"(value);
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
            set!"alpha"(value);
            elementStyle.alpha = value;
        }
        Color textColor() const pure
        {
            return sp.textColor;
        }
        /// ditto
        void textColor(Color value)
        {
            set!"textColor"(value);
            elementStyle.textColor = value;
        }
        /// Colors to draw focus rectangle (one for solid, two for vertical gradient) or null if no focus rect should be drawn for style
        Color focusRectColor() const pure
        {
            return sp.focusRectColor;
        }
        /// ditto
        void focusRectColor(Color value)
        {
            set!"focusRectColor"(value);
            elementStyle.focusRectColor = value;
        }

        //===================================================
        // DERIVATIVES

        /// Get widget background for this style. The background object has the same lifetime as the style.
        Background background()
        {
            if (backgroundPropertiesChanged)
            {
                _background.border.color = sp.borderColor;
                _background.border.size = borderWidth;
                _background.color = sp.backgroundColor;
                _background.image = sp.backgroundImage;
                _background.shadow = sp.boxShadow;
                backgroundPropertiesChanged = false;
            }
            return _background;
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

        /// When true, some property is being animated now
        bool hasActiveAnimations() const
        {
            return animations.length > 0;
        }

        /// Check whether the style can make transition for a property
        bool hasTransitionFor(string property) const
        {
            return (sp.transitionProperty == "all" || sp.transitionProperty == property) &&
                    sp.transitionTimingFunction !is null && sp.transitionDuration > 0;
        }

        //===================================================

        /// Widget's own style
        Style elementStyle()
        {
            if (!_elementStyle)
                _elementStyle = new Style;
            return _elementStyle;
        }

        /// Set a property value, taking transitions into account
        private void set(string name, T)(T value)
        {
            auto current = mixin("sp." ~ name);
            static if (isAnimatable(name))
            {
                if (hasTransitionFor(name))
                {
                    if (current !is value)
                    {
                        auto tr = new Transition(sp.transitionDuration,
                                                 sp.transitionTimingFunction,
                                                 sp.transitionDelay);
                        animations[name] = Animation(tr.duration * ONE_SECOND / 1000,
                            delegate(double t) {
                                mixin("sp." ~ name) = tr.mix(current, value, t);
                                static if (isLayoutProperty(name))
                                    layoutPropertiesChanged = true;
                                static if (isVisualProperty(name))
                                    visualPropertiesChanged = true;
                                static if (isBackgroundProperty(name))
                                    backgroundPropertiesChanged = true;
                        });
                    }
                    return;
                }
            }
            if (current !is value)
            {
                static if (isLayoutProperty(name))
                    layoutPropertiesChanged = true;
                static if (isVisualProperty(name))
                    visualPropertiesChanged = true;
                static if (isBackgroundProperty(name))
                    backgroundPropertiesChanged = true;
                // copy it directly otherwise
                mixin("sp." ~ name) = value;
            }
        }
    }

    package (beamui)
    {
        bool layoutPropertiesChanged;
        bool visualPropertiesChanged;
    }

    private
    {
        StyleProperties sp; // TODO: void?
        Style _elementStyle;

        Background _background;
        FontRef _font;

        Animation[string] animations; // key is a property name

        bool backgroundPropertiesChanged = true;
    }

    ~this()
    {
        _font.clear();
        eliminate(_background);
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

        if (_background is null)
            _background = new Background;
        _font.clear();

        static foreach (i; 0 .. StyleProperties.tupleof.length)
        {
            // find nearest written property
            foreach_reverse (st; chain)
            {
                if (st.written[i])
                {
                    set!(StyleProperties.tupleof[i].stringof)(st.properties.tupleof[i]);
                    break;
                }
            }
        }
    }

    void tickAnimations(long interval)
    {
        bool someAnimationsFinished;
        foreach (ref a; animations)
        {
            if (!a.isAnimating)
            {
                a.start();
            }
            else
            {
                a.tick(interval);
                if (!a.isAnimating)
                {
                    a.handler = null;
                    someAnimationsFinished = true;
                }
            }
        }
        if (someAnimationsFinished)
        {
            foreach (k, a; animations)
                if (a.handler is null)
                    animations.remove(k);
        }
    }
}
