/**
Widget style, that contains named properties and is associated with selector.

Copyright: Vadim Lopatin 2014-2017, dayllenger 2017-2020
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.style;

import std.variant : Variant;

import beamui.core.animations : TimingFunction;
import beamui.core.editable : TabSize;
import beamui.core.functions;
import beamui.core.geometry : Insets, isDefinedSize;
import beamui.core.math : clamp;
import beamui.core.types : Ok, Result;
import beamui.core.units : Length;
import beamui.graphics.colors : Color, decodeHexColor, decodeTextColor;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables : BorderStyle, BoxShadowDrawable, BoxType, Drawable, RepeatStyle;
import beamui.layout.alignment : Align, AlignItem, Distribution, Stretch;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.decode_css;
import beamui.style.property;
import beamui.style.selector;
import beamui.style.types;
import beamui.text.fonts : GenericFontFamily, FontStyle;
import beamui.text.style;
import beamui.widgets.widget : CursorType;

/// Style - holds properties for a single selector
final class Style
{
    /// Style rule selector
    const Selector selector;
    package StylePropertyList _props;

    /// Create style with some selector
    this(const Selector selector)
    {
        this.selector = selector;
        debug const count = debugPlusInstance();
        debug (resalloc)
            Log.d("Created style, count: ", count);
    }

    ~this()
    {
        static foreach (prop; PropTypes.tupleof)
        {
            static if (is(typeof(prop) : Object))
            {
                if (auto p = _props.peek!(__traits(identifier, prop)))
                    destroy(*p);
            }
        }

        debug const count = debugMinusInstance();
        debug (resalloc)
            Log.d("Destroyed style, count: ", count);
    }

    mixin DebugInstanceCount;

    /// Ability to compare styles by their selector specificity
    override int opCmp(Object o) const
    {
        assert(cast(Style)o);
        import std.algorithm.comparison : cmp;

        const(uint[]) a = selector.specificity;
        const(uint[]) b = (cast(Style)o).selector.specificity;
        return cmp(a, b);
    }
}

struct InlineStyle
{
    package StylePropertyList _props;
    private alias P = StyleProperty;

    /// Set the property to inherit its value from parent element
    void inherit(StyleProperty property)
    {
        _props.inherit(property);
    }

    /// Set the property to its initial value
    void initialize(StyleProperty property)
    {
        _props.initialize(property);
    }

    // dfmt off
@property:
    /// A kind of layout this widget may apply to its children list
    void display(string name) { _props.set(P.display, name); }

    /// Widget natural (preferred) width (`SIZE_UNSPECIFIED` or `Length.none` to unset)
    void width(Length len) { _props.set(P.width, len); }
    /// ditto
    void width(float px) { _props.set(P.width, Length.px(px)); }

    /// Widget natural (preferred) height (`SIZE_UNSPECIFIED` or `Length.none` to unset)
    void height(Length len) { _props.set(P.height, len); }
    /// ditto
    void height(float px) { _props.set(P.height, Length.px(px)); }

    /// Widget min width constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
    void minWidth(Length len) { _props.set(P.minWidth, len); }
    /// ditto
    void minWidth(float px) { _props.set(P.minWidth, Length.px(px)); }
    /// Widget min height constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
    void minHeight(Length len) { _props.set(P.minHeight, len); }
    /// ditto
    void minHeight(float px) { _props.set(P.minHeight, Length.px(px)); }

    /// Widget max width constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
    void maxWidth(Length len) { _props.set(P.maxWidth, len); }
    /// ditto
    void maxWidth(float px) { _props.set(P.maxWidth, Length.px(px)); }
    /// Widget max height constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
    void maxHeight(Length len) { _props.set(P.maxHeight, len); }
    /// ditto
    void maxHeight(float px) { _props.set(P.maxHeight, Length.px(px)); }

    /// Padding (between background bounds and content of widget)
    void padding(Insets px4)
    {
        if (isDefinedSize(px4.top))
            _props.set(P.paddingTop, Length.px(px4.top));
        if (isDefinedSize(px4.right))
            _props.set(P.paddingRight, Length.px(px4.right));
        if (isDefinedSize(px4.bottom))
            _props.set(P.paddingBottom, Length.px(px4.bottom));
        if (isDefinedSize(px4.left))
            _props.set(P.paddingLeft, Length.px(px4.left));
    }
    /// ditto
    void padding(Length len)
        in(len != Length.none)
    {
        _props.set(P.paddingTop, len);
        _props.set(P.paddingRight, len);
        _props.set(P.paddingBottom, len);
        _props.set(P.paddingLeft, len);
    }
    /// ditto
    void padding(float px) { padding = Length.px(px); }
    /// Top padding value
    void paddingTop(Length len)
        in(len != Length.none)
    {
        _props.set(P.paddingTop, len);
    }
    /// ditto
    void paddingTop(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.paddingTop, Length.px(px));
    }
    /// Right padding value
    void paddingRight(Length len)
        in(len != Length.none)
    {
        _props.set(P.paddingRight, len);
    }
    /// ditto
    void paddingRight(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.paddingRight, Length.px(px));
    }
    /// Bottom padding value
    void paddingBottom(Length len)
        in(len != Length.none)
    {
        _props.set(P.paddingBottom, len);
    }
    /// ditto
    void paddingBottom(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.paddingBottom, Length.px(px));
    }
    /// Left padding value
    void paddingLeft(Length len)
        in(len != Length.none)
    {
        _props.set(P.paddingLeft, len);
    }
    /// ditto
    void paddingLeft(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.paddingLeft, Length.px(px));
    }

    void borderWidth(Insets px4)
    {
        if (isDefinedSize(px4.top))
            _props.set(P.borderTopWidth, Length.px(px4.top));
        if (isDefinedSize(px4.right))
            _props.set(P.borderRightWidth, Length.px(px4.right));
        if (isDefinedSize(px4.bottom))
            _props.set(P.borderBottomWidth, Length.px(px4.bottom));
        if (isDefinedSize(px4.left))
            _props.set(P.borderLeftWidth, Length.px(px4.left));
    }
    /// ditto
    void borderWidth(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderTopWidth, len);
        _props.set(P.borderRightWidth, len);
        _props.set(P.borderBottomWidth, len);
        _props.set(P.borderLeftWidth, len);
    }
    /// ditto
    void borderWidth(float px) { borderWidth = Length.px(px); }

    void borderTopWidth(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderTopWidth, len);
    }
    /// ditto
    void borderTopWidth(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderTopWidth, Length.px(px));
    }

    void borderRightWidth(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderRightWidth, len);
    }
    /// ditto
    void borderRightWidth(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderRightWidth, Length.px(px));
    }

    void borderBottomWidth(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderBottomWidth, len);
    }
    /// ditto
    void borderBottomWidth(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderBottomWidth, Length.px(px));
    }

    void borderLeftWidth(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderLeftWidth, len);
    }
    /// ditto
    void borderLeftWidth(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderLeftWidth, Length.px(px));
    }

    /// Margins around widget (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
    void margins(Insets px4)
    {
        _props.set(P.marginTop, Length.px(px4.top));
        _props.set(P.marginRight, Length.px(px4.right));
        _props.set(P.marginBottom, Length.px(px4.bottom));
        _props.set(P.marginLeft, Length.px(px4.left));
    }
    /// ditto
    void margins(Length len)
    {
        _props.set(P.marginTop, len);
        _props.set(P.marginRight, len);
        _props.set(P.marginBottom, len);
        _props.set(P.marginLeft, len);
    }
    /// ditto
    void margins(float px) { margins = Length.px(px); }
    /// Top margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
    void marginTop(Length len) { _props.set(P.marginTop, len); }
    /// ditto
    void marginTop(float px) { _props.set(P.marginTop, Length.px(px)); }
    /// Right margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
    void marginRight(Length len) { _props.set(P.marginRight, len); }
    /// ditto
    void marginRight(float px) { _props.set(P.marginRight, Length.px(px)); }
    /// Bottom margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
    void marginBottom(Length len) { _props.set(P.marginBottom, len); }
    /// ditto
    void marginBottom(float px) { _props.set(P.marginBottom, Length.px(px)); }
    /// Left margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
    void marginLeft(Length len) { _props.set(P.marginLeft, len); }
    /// ditto
    void marginLeft(float px) { _props.set(P.marginLeft, Length.px(px)); }

    void left(Length len) { _props.set(P.left, len); }
    /// ditto
    void left(float px) { _props.set(P.left, Length.px(px)); }

    void top(Length len) { _props.set(P.top, len); }
    /// ditto
    void top(float px) { _props.set(P.top, Length.px(px)); }

    void right(Length len) { _props.set(P.right, len); }
    /// ditto
    void right(float px) { _props.set(P.right, Length.px(px)); }

    void bottom(Length len) { _props.set(P.bottom, len); }
    /// ditto
    void bottom(float px) { _props.set(P.bottom, Length.px(px)); }

    /// Alignment (combined vertical and horizontal)
    void alignment(Align value) { _props.set(P.alignment, value); }

    /** Controls whether widget occupies all available width/height in a linear layout.

        `Stretch.cross` by default.
    */
    void stretch(Stretch value) { _props.set(P.stretch, value); }

    /// Content distribution by main and cross axes
    void placeContent(Distribution[2] value)
    {
        _props.set(P.justifyContent, value[0]);
        _props.set(P.alignContent, value[1]);
    }
    /// Default alignment by main and cross axes for all layout items
    void placeItems(AlignItem[2] value)
        in(value[0] != AlignItem.unspecified)
        in(value[1] != AlignItem.unspecified)
    {
        _props.set(P.justifyItems, value[0]);
        _props.set(P.alignItems, value[1]);
    }
    /// Item alignment by main and cross axes
    void placeSelf(AlignItem[2] value)
    {
        _props.set(P.justifySelf, value[0]);
        _props.set(P.alignSelf, value[1]);
    }

    /// Set one value for row and column gaps
    void gap(Length len)
        in(len != Length.none)
    {
        _props.set(P.rowGap, len);
        _props.set(P.columnGap, len);
    }
    /// ditto
    void gap(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.rowGap, Length.px(px));
        _props.set(P.columnGap, Length.px(px));
    }
    /// Space between rows in layouts (e.g. in column flex layout)
    void rowGap(Length len)
        in(len != Length.none)
    {
        _props.set(P.rowGap, len);
    }
    /// ditto
    void rowGap(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.rowGap, Length.px(px));
    }
    /// Space between columns in layouts (e.g. in row flex layout)
    void columnGap(Length len)
        in(len != Length.none)
    {
        _props.set(P.columnGap, len);
    }
    /// ditto
    void columnGap(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.columnGap, Length.px(px));
    }

    /// Controls item reordering in some layouts
    void order(int i) { _props.set(P.order, i); }
    /// Widget stack order (`int.min` to unspecified)
    void zIndex(int z) { _props.set(P.zIndex, z); }

    /// Specifies flexbox main axis and its start and end sides
    void flexDirection(FlexDirection value) { _props.set(P.flexDirection, value); }
    /// Controls whether flexbox breaks items across several lines
    void flexWrap(FlexWrap value) { _props.set(P.flexWrap, value); }

    /// Sets how much flex item will grow relative to other flexible items in the container
    void flexGrow(float value) { _props.set(P.flexGrow, value); }
    /// Sets how much flex item will shrink relative to other flexible items in the container
    void flexShrink(float value) { _props.set(P.flexShrink, value); }
    /// The initial size by main axis of the flexible item
    void flexBasis(Length len) { _props.set(P.flexBasis, len); }
    /// ditto
    void flexBasis(float px) { _props.set(P.flexBasis, Length.px(px)); }

    /// Specifies how auto-placed items get inserted in the grid
    void gridAutoFlow(GridFlow value) { _props.set(P.gridAutoFlow, value); }
    /// Default size for grid rows
    void gridAutoRows(TrackSize sz) { return _props.set(P.gridAutoRows, sz); }
    /// Default size for grid columns
    void gridAutoColumns(TrackSize sz) { return _props.set(P.gridAutoColumns, sz); }

    void gridRowStart(GridLineName value) { _props.set(P.gridRowStart, value); }
    void gridRowEnd(GridLineName value) { _props.set(P.gridRowEnd, value); }
    void gridColumnStart(GridLineName value) { _props.set(P.gridColumnStart, value); }
    void gridColumnEnd(GridLineName value) { _props.set(P.gridColumnEnd, value); }

    /// Background color of the widget
    void backgroundColor(Color value) { _props.set(P.bgColor, value); }
    /// Set background color from string like "#5599CC" or "white"
    void backgroundColor(string str)
    {
        _props.set(P.bgColor,
            decodeHexColor(str).or(
                decodeTextColor(str).or(Color.transparent)));
    }
    /// Background image drawable
    void backgroundImage(Drawable image) { _props.set(P.bgImage, image); }

    void backgroundRepeat(RepeatStyle value) { _props.set(P.bgRepeat, value); }

    void backgroundOrigin(BoxType box) { _props.set(P.bgOrigin, box); }

    void backgroundClip(BoxType box) { _props.set(P.bgClip, box); }

    /// Set a color for all four border sides
    void borderColor(Color value)
    {
        _props.set(P.borderTopColor, value);
        _props.set(P.borderRightColor, value);
        _props.set(P.borderBottomColor, value);
        _props.set(P.borderLeftColor, value);
    }
    /// Color of the top widget border
    void borderTopColor(Color value) { _props.set(P.borderTopColor, value); }
    /// Color of the right widget border
    void borderRightColor(Color value) { _props.set(P.borderRightColor, value); }
    /// Color of the bottom widget border
    void borderBottomColor(Color value) { _props.set(P.borderBottomColor, value); }
    /// Color of the left widget border
    void borderLeftColor(Color value) { _props.set(P.borderLeftColor, value); }
    /// Set a line style for all four border sides
    void borderStyle(BorderStyle value)
    {
        _props.set(P.borderTopStyle, value);
        _props.set(P.borderRightStyle, value);
        _props.set(P.borderBottomStyle, value);
        _props.set(P.borderLeftStyle, value);
    }
    /// Line style of the top widget border
    void borderTopStyle(BorderStyle value) { _props.set(P.borderTopStyle, value); }
    /// Line style of the right widget border
    void borderRightStyle(BorderStyle value) { _props.set(P.borderRightStyle, value); }
    /// Line style of the bottom widget border
    void borderBottomStyle(BorderStyle value) { _props.set(P.borderBottomStyle, value); }
    /// Line style of the left widget border
    void borderLeftStyle(BorderStyle value) { _props.set(P.borderLeftStyle, value); }

    /// Set a border radius for all corners simultaneously
    void borderRadius(Insets px4)
    {
        if (isDefinedSize(px4.top))
            _props.set(P.borderTopLeftRadius, Length.px(px4.top));
        if (isDefinedSize(px4.right))
            _props.set(P.borderTopRightRadius, Length.px(px4.right));
        if (isDefinedSize(px4.bottom))
            _props.set(P.borderBottomLeftRadius, Length.px(px4.bottom));
        if (isDefinedSize(px4.left))
            _props.set(P.borderBottomRightRadius, Length.px(px4.left));
    }
    /// ditto
    void borderRadius(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderTopLeftRadius, len);
        _props.set(P.borderTopRightRadius, len);
        _props.set(P.borderBottomLeftRadius, len);
        _props.set(P.borderBottomRightRadius, len);
    }
    /// ditto
    void borderRadius(float px) { borderRadius = Length.px(px); }

    /// ditto
    void borderTopLeftRadius(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderTopLeftRadius, len);
    }
    /// ditto
    void borderTopLeftRadius(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderTopLeftRadius, Length.px(px));
    }

    void borderTopRightRadius(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderTopRightRadius, len);
    }
    /// ditto
    void borderTopRightRadius(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderTopRightRadius, Length.px(px));
    }

    void borderBottomLeftRadius(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderBottomLeftRadius, len);
    }
    /// ditto
    void borderBottomLeftRadius(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderBottomLeftRadius, Length.px(px));
    }

    void borderBottomRightRadius(Length len)
        in(len != Length.none)
    {
        _props.set(P.borderBottomRightRadius, len);
    }
    /// ditto
    void borderBottomRightRadius(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.borderBottomRightRadius, Length.px(px));
    }

    /// ditto
    void boxShadow(BoxShadowDrawable shadow) { _props.set(P.boxShadow, shadow); }

    /// Font face for widget
    void fontFace(string value) { _props.set(P.fontFace, value); }
    /// Font family for widget
    void fontFamily(GenericFontFamily value) { _props.set(P.fontFamily, value); }
    /// Font style (italic/normal) for widget
    void fontItalic(bool italic) { _props.set(P.fontStyle, italic ? FontStyle.italic : FontStyle.normal); }
    /// Font size for widget
    void fontSize(Length len)
        in(len != Length.none)
    {
        _props.set(P.fontSize, len);
    }
    /// ditto
    void fontSize(float px)
        in(isDefinedSize(px))
    {
        fontSize = Length.px(px);
    }
    /// Font weight for widget
    void fontWeight(ushort value) { _props.set(P.fontWeight, cast(ushort)clamp(value, 100, 900)); }

    /// Tab stop size, in number of spaces from 1 to 16
    void tabSize(TabSize sz) { _props.set(P.tabSize, sz); }
    /// ditto
    void tabSize(int i) { _props.set(P.tabSize, TabSize(i)); }

    /// Text alignment - start, center, end, or justify
    void textAlign(TextAlign a) { _props.set(P.textAlign, a); }

    /// Text decoration - underline, overline, and so on
    void textDecor(TextDecor compound)
    {
        _props.set(P.textDecorLine, compound.line);
        _props.set(P.textDecorColor, compound.color);
        _props.set(P.textDecorStyle, compound.style);
    }
    /// The color of text decorations, set with `textDecorLine`
    void textDecorColor(Color color) { _props.set(P.textDecorColor, color); }
    /// Place where text decoration line(s) appears. Required to be not `none` to draw something
    void textDecorLine(TextDecorLine line) { _props.set(P.textDecorLine, line); }
    /// Style of the line drawn for text decoration - solid, dashed, and the like
    void textDecorStyle(TextDecorStyle style) { _props.set(P.textDecorStyle, style); }

    /// Controls how text with `&` hotkey marks should be displayed
    void textHotkey(TextHotkey value) { _props.set(P.textHotkey, value); }
    /// Specifies how text that doesn't fit and is not displayed should behave
    void textOverflow(TextOverflow value) { _props.set(P.textOverflow, value); }
    /// Controls capitalization of text
    void textTransform(TextTransform value) { _props.set(P.textTransform, value); }

    void letterSpacing(Length len)
        in(len != Length.none)
    {
        _props.set(P.letterSpacing, len);
    }
    /// ditto
    void letterSpacing(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.letterSpacing, Length.px(px));
    }

    void lineHeight(Length len)
        in(len != Length.none)
    {
        _props.set(P.lineHeight, len);
    }
    /// ditto
    void lineHeight(float px)
        in(isDefinedSize(px))
    {
        lineHeight = Length.px(px);
    }

    void textIndent(Length len)
        in(len != Length.none)
    {
        _props.set(P.textIndent, len);
    }
    /// ditto
    void textIndent(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.textIndent, Length.px(px));
    }

    void wordSpacing(Length len)
        in(len != Length.none)
    {
        _props.set(P.wordSpacing, len);
    }
    /// ditto
    void wordSpacing(float px)
        in(isDefinedSize(px))
    {
        _props.set(P.wordSpacing, Length.px(px));
    }

    /// Controls whether text wrapping is enabled
    void wordWrap(bool value) { _props.set(P.whiteSpace, value ? WhiteSpace.preWrap : WhiteSpace.pre); }

    /// Text color
    void textColor(Color value) { _props.set(P.textColor, value); }
    /// Set text color from string like "#5599CC" or "white"
    void textColor(string str)
    {
        _props.set(P.textColor,
            decodeHexColor(str).or(
                decodeTextColor(str).or(Color.transparent)));
    }

    /// Opacity of the whole widget, always clamped to [0..1] range, where 0.0 - invisible, 1.0 - normal
    void opacity(float value) { _props.set(P.opacity, clamp(value, 0, 1)); }
    /// Specifies how widget blends with a backdrop
    void mixBlendMode(BlendMode value) { _props.set(P.mixBlendMode, value); }

    /// Specifies the type of mouse cursor when pointing over the widget
    void cursor(CursorType value) { _props.set(P.cursor, value); }

    // dfmt on
}
