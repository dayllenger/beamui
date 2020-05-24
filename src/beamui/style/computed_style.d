/**

Copyright: dayllenger 2018-2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.computed_style;

import beamui.core.animations;
import beamui.core.editable : TabSize;
import beamui.core.functions : clamp, eliminate, format;
import beamui.core.geometry : Insets, isDefinedSize;
import beamui.core.types : Result, Ok;
import beamui.core.units : Length, LayoutLength;
import beamui.graphics.colors : Color, decodeHexColor, decodeTextColor;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables;
import beamui.layout.alignment;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.style;
import beamui.style.types;
import beamui.text.fonts;
import beamui.text.style;
import beamui.widgets.widget : CursorType, Element;
debug (styles) import beamui.core.logger;

/// Enumeration of all supported style properties. NOTE: DON'T use `case .. case` slices on them,
/// because order may be changed in the future.
enum StyleProperty
{
    // layout
    display,
    // box model
    width,
    height,
    minWidth,
    maxWidth,
    minHeight,
    maxHeight,
    paddingTop,
    paddingRight,
    paddingBottom,
    paddingLeft,
    borderTopWidth,
    borderRightWidth,
    borderBottomWidth,
    borderLeftWidth,
    marginTop,
    marginRight,
    marginBottom,
    marginLeft,
    // placement
    left,
    top,
    right,
    bottom,
    alignment,
    stretch,
    justifyContent,
    justifyItems,
    justifySelf,
    alignContent,
    alignItems,
    alignSelf,
    rowGap,
    columnGap,
    order,
    zIndex,
    // flexbox-specific
    flexDirection,
    flexWrap,
    flexGrow,
    flexShrink,
    flexBasis,
    // grid-specific
    gridTemplateRows,
    gridTemplateColumns,
    gridTemplateAreas,
    gridAutoFlow,
    gridAutoRows,
    gridAutoColumns,
    gridRowStart,
    gridRowEnd,
    gridColumnStart,
    gridColumnEnd,
    // background
    bgColor,
    bgImage,
    bgPosition,
    bgSize,
    bgRepeat,
    bgOrigin,
    bgClip,
    borderTopStyle,
    borderRightStyle,
    borderBottomStyle,
    borderLeftStyle,
    borderTopLeftRadius,
    borderTopRightRadius,
    borderBottomLeftRadius,
    borderBottomRightRadius,
    boxShadow,
    // text
    fontFace,
    fontFamily,
    fontSize,
    fontStyle,
    fontWeight,
    letterSpacing,
    lineHeight,
    tabSize,
    textAlign,
    textDecorLine,
    textDecorStyle,
    textHotkey,
    textIndent,
    textOverflow,
    textTransform,
    whiteSpace,
    wordSpacing,
    // colors
    textColor,
    focusRectColor,
    // depend on text color, so must be computed after
    borderTopColor,
    borderRightColor,
    borderBottomColor,
    borderLeftColor,
    textDecorColor,
    // effects
    opacity,
    mixBlendMode,
    // transitions and animations
    transitionProperty,
    transitionTimingFunction,
    transitionDuration,
    transitionDelay,
    // misc
    cursor,
}

/// Provides default style values for most of properties
private static ComputedStyle defaults;

struct ComputedStyle
{
    @property // written mostly at single line for compactness
    {
        /// A kind of layout this widget may apply to its children list
        string display() const { return _display; }
        /// ditto
        void display(string name) { setProperty!"display" = name; }

        /// Widget natural (preferred) width (`SIZE_UNSPECIFIED` or `Length.none` to unset)
        LayoutLength width() const { return applyEM(_width); }
        /// ditto
        void width(Length len) { setProperty!"width" = len; }
        /// ditto
        void width(float px) { setProperty!"width" = Length.px(px); }
        /// Widget natural (preferred) height (`SIZE_UNSPECIFIED` or `Length.none` to unset)
        LayoutLength height() const { return applyEM(_height); }
        /// ditto
        void height(Length len) { setProperty!"height" = len; }
        /// ditto
        void height(float px) { setProperty!"height" = Length.px(px); }

        /// Widget min width constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
        LayoutLength minWidth() const { return applyEM(_minWidth); }
        /// ditto
        void minWidth(Length len) { setProperty!"minWidth" = len; }
        /// ditto
        void minWidth(float px) { setProperty!"minWidth" = Length.px(px); }
        /// Widget min height constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
        LayoutLength minHeight() const { return applyEM(_minHeight); }
        /// ditto
        void minHeight(Length len) { setProperty!"minHeight" = len; }
        /// ditto
        void minHeight(float px) { setProperty!"minHeight" = Length.px(px); }

        /// Widget max width constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
        LayoutLength maxWidth() const { return applyEM(_maxWidth); }
        /// ditto
        void maxWidth(Length len) { setProperty!"maxWidth" = len; }
        /// ditto
        void maxWidth(float px) { setProperty!"maxWidth" = Length.px(px); }
        /// Widget max height constraint (`SIZE_UNSPECIFIED` or `Length.none` to unset)
        LayoutLength maxHeight() const { return applyEM(_maxHeight); }
        /// ditto
        void maxHeight(Length len) { setProperty!"maxHeight" = len; }
        /// ditto
        void maxHeight(float px) { setProperty!"maxHeight" = Length.px(px); }

        /// Padding (between background bounds and content of widget)
        Insets padding() const
        {
            return Insets(applyOnlyEM(_paddingTop), applyOnlyEM(_paddingRight),
                          applyOnlyEM(_paddingBottom), applyOnlyEM(_paddingLeft));
        }
        /// ditto
        void padding(Insets px4)
        {
            if (isDefinedSize(px4.top))
                setProperty!"paddingTop" = Length.px(px4.top);
            if (isDefinedSize(px4.right))
                setProperty!"paddingRight" = Length.px(px4.right);
            if (isDefinedSize(px4.bottom))
                setProperty!"paddingBottom" = Length.px(px4.bottom);
            if (isDefinedSize(px4.left))
                setProperty!"paddingLeft" = Length.px(px4.left);
        }
        /// ditto
        void padding(Length len)
        {
            assert(len != Length.none);
            setProperty!"paddingTop" = len;
            setProperty!"paddingRight" = len;
            setProperty!"paddingBottom" = len;
            setProperty!"paddingLeft" = len;
        }
        /// ditto
        void padding(float px) { padding = Length.px(px); }
        /// Top padding value
        float paddingTop() const { return applyOnlyEM(_paddingTop); }
        /// ditto
        void paddingTop(Length len)
        {
            assert(len != Length.none);
            setProperty!"paddingTop" = len;
        }
        /// ditto
        void paddingTop(float px)
        {
            assert(isDefinedSize(px));
            paddingTop = Length.px(px);
        }
        /// Right padding value
        float paddingRight() const { return applyOnlyEM(_paddingRight); }
        /// ditto
        void paddingRight(Length len)
        {
            assert(len != Length.none);
            setProperty!"paddingRight" = len;
        }
        /// ditto
        void paddingRight(float px)
        {
            assert(isDefinedSize(px));
            paddingRight = Length.px(px);
        }
        /// Bottom padding value
        float paddingBottom() const { return applyOnlyEM(_paddingBottom); }
        /// ditto
        void paddingBottom(Length len)
        {
            assert(len != Length.none);
            setProperty!"paddingBottom" = len;
        }
        /// ditto
        void paddingBottom(float px)
        {
            assert(isDefinedSize(px));
            paddingBottom = Length.px(px);
        }
        /// Left padding value
        float paddingLeft() const { return applyOnlyEM(_paddingLeft); }
        /// ditto
        void paddingLeft(Length len)
        {
            assert(len != Length.none);
            setProperty!"paddingLeft" = len;
        }
        /// ditto
        void paddingLeft(float px)
        {
            assert(isDefinedSize(px));
            paddingLeft = Length.px(px);
        }

        Insets borderWidth() const
        {
            return Insets(applyOnlyEM(_borderTopWidth), applyOnlyEM(_borderRightWidth),
                          applyOnlyEM(_borderBottomWidth), applyOnlyEM(_borderLeftWidth));
        }
        /// ditto
        void borderWidth(Insets px4)
        {
            if (isDefinedSize(px4.top))
                setProperty!"borderTopWidth" = Length.px(px4.top);
            if (isDefinedSize(px4.right))
                setProperty!"borderRightWidth" = Length.px(px4.right);
            if (isDefinedSize(px4.bottom))
                setProperty!"borderBottomWidth" = Length.px(px4.bottom);
            if (isDefinedSize(px4.left))
                setProperty!"borderLeftWidth" = Length.px(px4.left);
        }
        /// ditto
        void borderWidth(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderTopWidth" = len;
            setProperty!"borderRightWidth" = len;
            setProperty!"borderBottomWidth" = len;
            setProperty!"borderLeftWidth" = len;
        }
        /// ditto
        void borderWidth(float px) { borderWidth = Length.px(px); }

        float borderTopWidth() const { return applyOnlyEM(_borderTopWidth); }
        /// ditto
        void borderTopWidth(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderTopWidth" = len;
        }
        /// ditto
        void borderTopWidth(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderTopWidth" = Length.px(px);
        }

        float borderRightWidth() const { return applyOnlyEM(_borderRightWidth); }
        /// ditto
        void borderRightWidth(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderRightWidth" = len;
        }
        /// ditto
        void borderRightWidth(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderRightWidth" = Length.px(px);
        }

        float borderBottomWidth() const { return applyOnlyEM(_borderBottomWidth); }
        /// ditto
        void borderBottomWidth(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderBottomWidth" = len;
        }
        /// ditto
        void borderBottomWidth(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderBottomWidth" = Length.px(px);
        }

        float borderLeftWidth() const { return applyOnlyEM(_borderLeftWidth); }
        /// ditto
        void borderLeftWidth(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderLeftWidth" = len;
        }
        /// ditto
        void borderLeftWidth(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderLeftWidth" = Length.px(px);
        }

        /// Margins around widget (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
        Insets margins() const
        {
            return Insets(applyOnlyEM(_marginTop), applyOnlyEM(_marginRight),
                          applyOnlyEM(_marginBottom), applyOnlyEM(_marginLeft));
        }
        /// ditto
        void margins(Insets px4)
        {
            setProperty!"marginTop" = Length.px(px4.top);
            setProperty!"marginRight" = Length.px(px4.right);
            setProperty!"marginBottom" = Length.px(px4.bottom);
            setProperty!"marginLeft" = Length.px(px4.left);
        }
        /// ditto
        void margins(Length len)
        {
            setProperty!"marginTop" = len;
            setProperty!"marginRight" = len;
            setProperty!"marginBottom" = len;
            setProperty!"marginLeft" = len;
        }
        /// ditto
        void margins(float px) { margins = Length.px(px); }
        /// Top margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
        float marginTop() const { return applyOnlyEM(_marginTop); }
        /// ditto
        void marginTop(Length len) { setProperty!"marginTop" = len; }
        /// ditto
        void marginTop(float px) { setProperty!"marginTop" = Length.px(px); }
        /// Right margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
        float marginRight() const { return applyOnlyEM(_marginRight); }
        /// ditto
        void marginRight(Length len) { setProperty!"marginRight" = len; }
        /// ditto
        void marginRight(float px) { setProperty!"marginRight" = Length.px(px); }
        /// Bottom margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
        float marginBottom() const { return applyOnlyEM(_marginBottom); }
        /// ditto
        void marginBottom(Length len) { setProperty!"marginBottom" = len; }
        /// ditto
        void marginBottom(float px) { setProperty!"marginBottom" = Length.px(px); }
        /// Left margin value (`SIZE_UNSPECIFIED` or `Length.none` for `auto`)
        float marginLeft() const { return applyOnlyEM(_marginLeft); }
        /// ditto
        void marginLeft(Length len) { setProperty!"marginLeft" = len; }
        /// ditto
        void marginLeft(float px) { setProperty!"marginLeft" = Length.px(px); }

        LayoutLength left() const { return applyEM(_left); }
        /// ditto
        void left(Length len) { setProperty!"left" = len; }
        /// ditto
        void left(float px) { setProperty!"left" = Length.px(px); }

        LayoutLength top() const { return applyEM(_top); }
        /// ditto
        void top(Length len) { setProperty!"top" = len; }
        /// ditto
        void top(float px) { setProperty!"top" = Length.px(px); }

        LayoutLength right() const { return applyEM(_right); }
        /// ditto
        void right(Length len) { setProperty!"right" = len; }
        /// ditto
        void right(float px) { setProperty!"right" = Length.px(px); }

        LayoutLength bottom() const { return applyEM(_bottom); }
        /// ditto
        void bottom(Length len) { setProperty!"bottom" = len; }
        /// ditto
        void bottom(float px) { setProperty!"bottom" = Length.px(px); }

        /// Alignment (combined vertical and horizontal)
        Align alignment() const { return _alignment; }
        /// ditto
        void alignment(Align value) { setProperty!"alignment" = value; }
        /// Returns horizontal alignment
        Align halign() const { return _alignment & Align.hcenter; }
        /// Returns vertical alignment
        Align valign() const { return _alignment & Align.vcenter; }

        /** Controls whether widget occupies all available width/height in a linear layout.

            `Stretch.cross` by default.
        */
        Stretch stretch() const { return _stretch; }
        /// ditto
        void stretch(Stretch value) { setProperty!"stretch" = value; }

        /// Content distribution by main and cross axes
        Distribution[2] placeContent() const { return [_justifyContent, _alignContent]; }
        /// ditto
        void placeContent(Distribution[2] value)
        {
            setProperty!"justifyContent" = value[0];
            setProperty!"alignContent" = value[1];
        }

        /// Default alignment by main and cross axes for all layout items
        AlignItem[2] placeItems() const { return [_justifyItems, _alignItems]; }
        /// ditto
        void placeItems(AlignItem[2] value)
            in(value[0] != AlignItem.unspecified)
            in(value[1] != AlignItem.unspecified)
        {
            setProperty!"justifyItems" = value[0];
            setProperty!"alignItems" = value[1];
        }

        /// Item alignment by main and cross axes
        AlignItem[2] placeSelf() const { return [_justifySelf, _alignSelf]; }
        /// ditto
        void placeSelf(AlignItem[2] value)
        {
            setProperty!"justifySelf" = value[0];
            setProperty!"alignSelf" = value[1];
        }

        /// Set one value for row and column gaps
        void gap(Length len)
        {
            assert(len != Length.none);
            setProperty!"rowGap" = len;
            setProperty!"columnGap" = len;
        }
        /// ditto
        void gap(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"rowGap" = Length.px(px);
            setProperty!"columnGap" = Length.px(px);
        }
        /// Space between rows in layouts (e.g. in vertical linear layout)
        LayoutLength rowGap() const { return applyEM(_rowGap); }
        /// ditto
        void rowGap(Length len)
        {
            assert(len != Length.none);
            setProperty!"rowGap" = len;
        }
        /// ditto
        void rowGap(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"rowGap" = Length.px(px);
        }
        /// Space between columns in layouts (e.g. in horizontal linear layout)
        LayoutLength columnGap() const { return applyEM(_columnGap); }
        /// ditto
        void columnGap(Length len)
        {
            assert(len != Length.none);
            setProperty!"columnGap" = len;
        }
        /// ditto
        void columnGap(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"columnGap" = Length.px(px);
        }

        /// Controls item reordering in some layouts
        int order() const { return _order; }
        /// ditto
        void order(int i) { setProperty!"order" = i; }

        /// Widget stack order (`int.min` if unspecified)
        int zIndex() const { return _zIndex; }
        /// ditto
        void zIndex(int z) { setProperty!"zIndex" = z; }

        /// Specifies flexbox main axis and its start and end sides
        FlexDirection flexDirection() const { return _flexDirection; }
        /// ditto
        void flexDirection(FlexDirection value) { setProperty!"flexDirection" = value; }
        /// Controls whether flexbox breaks items across several lines
        FlexWrap flexWrap() const { return _flexWrap; }
        /// ditto
        void flexWrap(FlexWrap value) { setProperty!"flexWrap" = value; }

        /// Sets how much flex item will grow relative to other flexible items in the container
        float flexGrow() const { return _flexGrow; }
        /// ditto
        void flexGrow(float value) { setProperty!"flexGrow" = value; }
        /// Sets how much flex item will shrink relative to other flexible items in the container
        float flexShrink() const { return _flexShrink; }
        /// ditto
        void flexShrink(float value) { setProperty!"flexShrink" = value; }
        /// The initial size by main axis of the flexible item
        LayoutLength flexBasis() const { return applyEM(_flexBasis); }
        /// ditto
        void flexBasis(Length len) { setProperty!"flexBasis" = len; }
        /// ditto
        void flexBasis(float px) { setProperty!"flexBasis" = Length.px(px); }

        const(TrackSize[]) gridTemplateRows() const { return _gridTemplateRows; }
        const(TrackSize[]) gridTemplateColumns() const { return _gridTemplateColumns; }
        const(GridNamedAreas) gridTemplateAreas() const { return _gridTemplateAreas; }

        /// Specifies how auto-placed items get inserted in the grid
        GridFlow gridAutoFlow() const { return _gridAutoFlow; }
        /// ditto
        void gridAutoFlow(GridFlow value) { setProperty!"gridAutoFlow" = value; }
        /// Default size for grid rows
        TrackSize gridAutoRows() const { return _gridAutoRows; }
        /// ditto
        void gridAutoRows(TrackSize sz) { return setProperty!"gridAutoRows" = sz; }
        /// Default size for grid columns
        TrackSize gridAutoColumns() const { return _gridAutoColumns; }
        /// ditto
        void gridAutoColumns(TrackSize sz) { return setProperty!"gridAutoColumns" = sz; }

        /// (row-start, column-start, row-end, column-end)
        GridLineName[4] gridArea() const { return [_gridRowStart, _gridColumnStart, _gridRowEnd, _gridColumnEnd]; }

        void gridRowStart(GridLineName value) { setProperty!"gridRowStart" = value; }
        void gridRowEnd(GridLineName value) { setProperty!"gridRowEnd" = value; }
        void gridColumnStart(GridLineName value) { setProperty!"gridColumnStart" = value; }
        void gridColumnEnd(GridLineName value) { setProperty!"gridColumnEnd" = value; }

        /// Background color of the widget
        Color backgroundColor() const { return _bgColor; }
        /// ditto
        void backgroundColor(Color value) { setProperty!"bgColor" = value; }
        /// Set background color from string like "#5599CC" or "white"
        void backgroundColor(string str)
        {
            setProperty!"bgColor" =
                decodeHexColor(str)
                    .failed(decodeTextColor(str))
                    .failed(Ok(Color.transparent))
                    .val;
        }
        /// Background image drawable
        inout(Drawable) backgroundImage() inout { return _bgImage; }
        /// ditto
        void backgroundImage(Drawable image) { setProperty!"bgImage" = image; }

        BgPosition backgroundPosition() const
        {
            return BgPosition(applyEM(_bgPosition.x), applyEM(_bgPosition.y));
        }

        BgSize backgroundSize() const
        {
            const t = _bgSize.type;
            if (t == BgSizeType.length)
                return BgSize(t, applyEM(_bgSize.x), applyEM(_bgSize.y));
            else
                return BgSize(t);
        }

        RepeatStyle backgroundRepeat() const { return _bgRepeat; }
        /// ditto
        void backgroundRepeat(RepeatStyle value) { setProperty!"bgRepeat" = value; }

        BoxType backgroundOrigin() const { return _bgOrigin; }
        /// ditto
        void backgroundOrigin(BoxType box) { setProperty!"bgOrigin" = box; }

        BoxType backgroundClip() const { return _bgClip; }
        /// ditto
        void backgroundClip(BoxType box) { setProperty!"bgClip" = box; }

        /// Set a color for all four border sides
        void borderColor(Color value)
        {
            setProperty!"borderTopColor" = value;
            setProperty!"borderRightColor" = value;
            setProperty!"borderBottomColor" = value;
            setProperty!"borderLeftColor" = value;
        }
        /// Color of the top widget border
        Color borderTopColor() const { return _borderTopColor; }
        /// ditto
        void borderTopColor(Color value) { setProperty!"borderTopColor" = value; }
        /// Color of the right widget border
        Color borderRightColor() const { return _borderRightColor; }
        /// ditto
        void borderRightColor(Color value) { setProperty!"borderRightColor" = value; }
        /// Color of the bottom widget border
        Color borderBottomColor() const { return _borderBottomColor; }
        /// ditto
        void borderBottomColor(Color value) { setProperty!"borderBottomColor" = value; }
        /// Color of the left widget border
        Color borderLeftColor() const { return _borderLeftColor; }
        /// ditto
        void borderLeftColor(Color value) { setProperty!"borderLeftColor" = value; }

        /// Set a line style for all four border sides
        void borderStyle(BorderStyle value)
        {
            setProperty!"borderTopStyle" = value;
            setProperty!"borderRightStyle" = value;
            setProperty!"borderBottomStyle" = value;
            setProperty!"borderLeftStyle" = value;
        }
        /// Line style of the top widget border
        BorderStyle borderTopStyle() const { return _borderTopStyle; }
        /// ditto
        void borderTopStyle(BorderStyle value) { setProperty!"borderTopStyle" = value; }
        /// Line style of the right widget border
        BorderStyle borderRightStyle() const { return _borderRightStyle; }
        /// ditto
        void borderRightStyle(BorderStyle value) { setProperty!"borderRightStyle" = value; }
        /// Line style of the bottom widget border
        BorderStyle borderBottomStyle() const { return _borderBottomStyle; }
        /// ditto
        void borderBottomStyle(BorderStyle value) { setProperty!"borderBottomStyle" = value; }
        /// Line style of the left widget border
        BorderStyle borderLeftStyle() const { return _borderLeftStyle; }
        /// ditto
        void borderLeftStyle(BorderStyle value) { setProperty!"borderLeftStyle" = value; }

        /// Set a border radius for all corners simultaneously
        void borderRadius(Insets px4)
        {
            if (isDefinedSize(px4.top))
                setProperty!"borderTopLeftRadius" = Length.px(px4.top);
            if (isDefinedSize(px4.right))
                setProperty!"borderTopRightRadius" = Length.px(px4.right);
            if (isDefinedSize(px4.bottom))
                setProperty!"borderBottomLeftRadius" = Length.px(px4.bottom);
            if (isDefinedSize(px4.left))
                setProperty!"borderBottomRightRadius" = Length.px(px4.left);
        }
        /// ditto
        void borderRadius(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderTopLeftRadius" = len;
            setProperty!"borderTopRightRadius" = len;
            setProperty!"borderBottomLeftRadius" = len;
            setProperty!"borderBottomRightRadius" = len;
        }
        /// ditto
        void borderRadius(float px) { borderRadius = Length.px(px); }

        LayoutLength borderTopLeftRadius() const { return applyEM(_borderTopLeftRadius); }
        /// ditto
        void borderTopLeftRadius(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderTopLeftRadius" = len;
        }
        /// ditto
        void borderTopLeftRadius(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderTopLeftRadius" = Length.px(px);
        }

        LayoutLength borderTopRightRadius() const { return applyEM(_borderTopRightRadius); }
        /// ditto
        void borderTopRightRadius(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderTopRightRadius" = len;
        }
        /// ditto
        void borderTopRightRadius(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderTopRightRadius" = Length.px(px);
        }

        LayoutLength borderBottomLeftRadius() const { return applyEM(_borderBottomLeftRadius); }
        /// ditto
        void borderBottomLeftRadius(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderBottomLeftRadius" = len;
        }
        /// ditto
        void borderBottomLeftRadius(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderBottomLeftRadius" = Length.px(px);
        }

        LayoutLength borderBottomRightRadius() const { return applyEM(_borderBottomRightRadius); }
        /// ditto
        void borderBottomRightRadius(Length len)
        {
            assert(len != Length.none);
            setProperty!"borderBottomRightRadius" = len;
        }
        /// ditto
        void borderBottomRightRadius(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"borderBottomRightRadius" = Length.px(px);
        }

        inout(BoxShadowDrawable) boxShadow() inout { return _boxShadow; }
        /// ditto
        void boxShadow(BoxShadowDrawable shadow) { setProperty!"boxShadow" = shadow; }

        /// Font face for widget
        string fontFace() const { return _fontFace; }
        /// ditto
        void fontFace(string value) { setProperty!"fontFace" = value; }
        /// Font family for widget
        FontFamily fontFamily() const { return _fontFamily; }
        /// ditto
        void fontFamily(FontFamily value) { setProperty!"fontFamily" = value; }
        /// Font style (italic/normal) for widget
        bool fontItalic() const { return _fontStyle == FontStyle.italic; }
        /// ditto
        void fontItalic(bool italic) { setProperty!"fontStyle" = italic ? FontStyle.italic : FontStyle.normal; }
        /// Computed font size in device-independent pixels
        int fontSize() const
        {
            const Length fs = _fontSize;
            const Element p = element.parent;
            const int def = FontManager.defaultFontSize;
            if (!fs.is_rem && (!p || isolated) && (fs.is_em || fs.is_percent))
                return def;
            const LayoutLength ll = fs.toLayout;
            const int base = p && !fs.is_rem ? p.style.fontSize : def;
            return cast(int)ll.applyPercent(base);
        }
        /// ditto
        void fontSize(Length len)
        {
            assert(len != Length.none);
            setProperty!"fontSize" = len;
        }
        /// ditto
        void fontSize(float px)
        {
            assert(isDefinedSize(px));
            fontSize = Length.px(px);
        }
        /// Font weight for widget
        ushort fontWeight() const { return _fontWeight; }
        /// ditto
        void fontWeight(ushort value) { setProperty!"fontWeight" = cast(ushort)clamp(value, 100, 900); }

        /// Tab stop size, in number of spaces from 1 to 16
        TabSize tabSize() const { return _tabSize; }
        /// ditto
        void tabSize(TabSize sz) { setProperty!"tabSize" = sz; }
        /// ditto
        void tabSize(int i) { setProperty!"tabSize" = TabSize(i); }

        /// Text alignment - start, center, end, or justify
        TextAlign textAlign() const { return _textAlign; }
        /// ditto
        void textAlign(TextAlign a) { setProperty!"textAlign" = a; }

        /// Text decoration - underline, overline, and so on
        TextDecor textDecor() const
        {
            return TextDecor(_textDecorLine, _textDecorColor, _textDecorStyle);
        }
        /// ditto
        void textDecor(TextDecor compound)
        {
            setProperty!"textDecorLine" = compound.line;
            setProperty!"textDecorColor" = compound.color;
            setProperty!"textDecorStyle" = compound.style;
        }
        /// The color of text decorations, set with `textDecorLine`
        Color textDecorColor() const { return _textDecorColor; }
        /// ditto
        void textDecorColor(Color color) { setProperty!"textDecorColor" = color; }
        /// Place where text decoration line(s) appears. Required to be not `none` to draw something
        TextDecorLine textDecorLine() const { return _textDecorLine; }
        /// ditto
        void textDecorLine(TextDecorLine line) { setProperty!"textDecorLine" = line; }
        /// Style of the line drawn for text decoration - solid, dashed, and the like
        TextDecorStyle textDecorStyle() const { return _textDecorStyle; }
        /// ditto
        void textDecorStyle(TextDecorStyle style) { setProperty!"textDecorStyle" = style; }

        /// Controls how text with `&` hotkey marks should be displayed
        TextHotkey textHotkey() const { return _textHotkey; }
        /// ditto
        void textHotkey(TextHotkey value) { setProperty!"textHotkey" = value; }
        /// Specifies how text that doesn't fit and is not displayed should behave
        TextOverflow textOverflow() const { return _textOverflow; }
        /// ditto
        void textOverflow(TextOverflow value) { setProperty!"textOverflow" = value; }
        /// Controls capitalization of text
        TextTransform textTransform() const { return _textTransform; }
        /// ditto
        void textTransform(TextTransform value) { setProperty!"textTransform" = value; }

        float letterSpacing() const { return applyOnlyEM(_letterSpacing); }
        /// ditto
        void letterSpacing(Length len)
        {
            assert(len != Length.none);
            setProperty!"letterSpacing" = len;
        }
        /// ditto
        void letterSpacing(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"letterSpacing" = Length.px(px);
        }

        float lineHeight() const { return applyOnlyEM(_lineHeight); }
        /// ditto
        void lineHeight(Length len)
        {
            assert(len != Length.none);
            setProperty!"lineHeight" = len;
        }
        /// ditto
        void lineHeight(float px)
        {
            assert(isDefinedSize(px));
            lineHeight = Length.px(px);
        }

        LayoutLength textIndent() const { return applyEM(_textIndent); }
        /// ditto
        void textIndent(Length len)
        {
            assert(len != Length.none);
            setProperty!"textIndent" = len;
        }
        /// ditto
        void textIndent(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"textIndent" = Length.px(px);
        }

        float wordSpacing() const { return applyOnlyEM(_wordSpacing); }
        /// ditto
        void wordSpacing(Length len)
        {
            assert(len != Length.none);
            setProperty!"wordSpacing" = len;
        }
        /// ditto
        void wordSpacing(float px)
        {
            assert(isDefinedSize(px));
            setProperty!"wordSpacing" = Length.px(px);
        }

        /// Controls whether text wrapping is enabled
        bool wordWrap() const { return _whiteSpace == WhiteSpace.preWrap; }
        /// ditto
        void wordWrap(bool value) { setProperty!"whiteSpace" = value ? WhiteSpace.preWrap : WhiteSpace.pre; }

        /// Text color
        Color textColor() const { return _textColor; }
        /// ditto
        void textColor(Color value) { setProperty!"textColor" = value; }
        /// Set text color from string like "#5599CC" or "white"
        void textColor(string str)
        {
            setProperty!"textColor" =
                decodeHexColor(str)
                    .failed(decodeTextColor(str))
                    .failed(Ok(Color.transparent))
                    .val;
        }

        /// Get color to draw focus rectangle, `Color.transparent` if no focus rect
        Color focusRectColor() const { return _focusRectColor; }

        /// Opacity of the whole widget, always clamped to [0..1] range, where 0.0 - invisible, 1.0 - normal
        float opacity() const { return _opacity; }
        /// ditto
        void opacity(float value) { setProperty!"opacity" = clamp(value, 0, 1); }

        /// Specifies how widget blends with a backdrop
        BlendMode mixBlendMode() const { return _mixBlendMode; }
        /// ditto
        void mixBlendMode(BlendMode value) { setProperty!"mixBlendMode" = value; }

        /// Specifies the type of mouse cursor when pointing over the widget
        CursorType cursor() const { return _cursor; }
        /// ditto
        void cursor(CursorType value) { setProperty!"cursor" = value; }
    }

    package(beamui) Element element;
    package(beamui) bool isolated;

    private
    {
        import core.bitop : bt, bts, btr;

        enum bits = StyleProperty.max + 1;
        /// Explicitly set to inherit value from parent widget
        size_t[bits / (8 * size_t.sizeof) + 1] inheritBitArray;
        /// Overriden by user
        size_t[bits / (8 * size_t.sizeof) + 1] overridenBitArray;

        // layout
        string _display;
        // box model
        Length _width = Length.none;
        Length _height = Length.none;
        Length _minWidth = Length.none;
        Length _maxWidth = Length.none;
        Length _minHeight = Length.none;
        Length _maxHeight = Length.none;
        Length _paddingTop = Length.zero;
        Length _paddingRight = Length.zero;
        Length _paddingBottom = Length.zero;
        Length _paddingLeft = Length.zero;
        Length _borderTopWidth = Length.zero;
        Length _borderRightWidth = Length.zero;
        Length _borderBottomWidth = Length.zero;
        Length _borderLeftWidth = Length.zero;
        Length _marginTop = Length.zero;
        Length _marginRight = Length.zero;
        Length _marginBottom = Length.zero;
        Length _marginLeft = Length.zero;
        // placement
        Length _left = Length.none;
        Length _top = Length.none;
        Length _right = Length.none;
        Length _bottom = Length.none;
        Align _alignment;
        Stretch _stretch = Stretch.cross;
        Distribution _justifyContent = Distribution.stretch;
        AlignItem _justifyItems = AlignItem.stretch;
        AlignItem _justifySelf = AlignItem.unspecified;
        Distribution _alignContent = Distribution.stretch;
        AlignItem _alignItems = AlignItem.stretch;
        AlignItem _alignSelf = AlignItem.unspecified;
        Length _rowGap = Length.zero;
        Length _columnGap = Length.zero;
        int _order = 0;
        int _zIndex = int.min;
        // flexbox-specific
        FlexDirection _flexDirection = FlexDirection.row;
        FlexWrap _flexWrap = FlexWrap.off;
        float _flexGrow = 0;
        float _flexShrink = 1;
        Length _flexBasis = Length.none;
        // grid-specific
        TrackSize[] _gridTemplateRows;
        TrackSize[] _gridTemplateColumns;
        GridNamedAreas _gridTemplateAreas;
        GridFlow _gridAutoFlow = GridFlow.row;
        TrackSize _gridAutoRows = TrackSize.automatic;
        TrackSize _gridAutoColumns = TrackSize.automatic;
        GridLineName _gridRowStart;
        GridLineName _gridRowEnd;
        GridLineName _gridColumnStart;
        GridLineName _gridColumnEnd;
        // background
        Color _bgColor = Color.transparent;
        Drawable _bgImage;
        BgPositionRaw _bgPosition;
        BgSizeRaw _bgSize;
        RepeatStyle _bgRepeat;
        BoxType _bgOrigin = BoxType.padding;
        BoxType _bgClip = BoxType.border;
        BorderStyle _borderTopStyle = BorderStyle.none;
        BorderStyle _borderRightStyle = BorderStyle.none;
        BorderStyle _borderBottomStyle = BorderStyle.none;
        BorderStyle _borderLeftStyle = BorderStyle.none;
        Length _borderTopLeftRadius = Length.zero;
        Length _borderTopRightRadius = Length.zero;
        Length _borderBottomLeftRadius = Length.zero;
        Length _borderBottomRightRadius = Length.zero;
        BoxShadowDrawable _boxShadow;
        // text
        string _fontFace = "Arial";
        FontFamily _fontFamily = FontFamily.sans_serif;
        Length _fontSize = Length.rem(1);
        FontStyle _fontStyle = FontStyle.normal;
        ushort _fontWeight = 400;
        Length _letterSpacing = Length.zero;
        Length _lineHeight = Length.rem(1.2);
        TabSize _tabSize;
        TextAlign _textAlign = TextAlign.start;
        TextDecorLine _textDecorLine = TextDecorLine.none;
        TextDecorStyle _textDecorStyle = TextDecorStyle.solid;
        TextHotkey _textHotkey = TextHotkey.ignore;
        Length _textIndent = Length.zero;
        TextOverflow _textOverflow = TextOverflow.clip;
        TextTransform _textTransform = TextTransform.none;
        WhiteSpace _whiteSpace = WhiteSpace.pre;
        Length _wordSpacing = Length.zero;
        // colors
        Color _textColor = Color.black;
        Color _focusRectColor = Color.transparent;
        // depend on text color
        Color _borderTopColor = Color.transparent;
        Color _borderRightColor = Color.transparent;
        Color _borderBottomColor = Color.transparent;
        Color _borderLeftColor = Color.transparent;
        Color _textDecorColor = Color.black;
        // effects
        float _opacity = 1;
        BlendMode _mixBlendMode = BlendMode.normal;
        // transitions and animations
        string _transitionProperty;
        TimingFunction _transitionTimingFunction;
        uint _transitionDuration;
        uint _transitionDelay;
        // misc
        CursorType _cursor = CursorType.automatic;
    }

    ~this()
    {
        if (isOverriden(StyleProperty.boxShadow))
            eliminate(_boxShadow);
        if (isOverriden(StyleProperty.bgImage))
            eliminate(_bgImage);
    }

    private LayoutLength applyEM(Length value) const
    {
        const LayoutLength ll = value.toLayout;
        if (value.is_rem)
        {
            const int def = FontManager.defaultFontSize;
            return LayoutLength(ll.applyPercent(def));
        }
        else if (value.is_em)
            return LayoutLength(ll.applyPercent(fontSize));
        else
            return ll;
    }

    /// ...without percent
    private float applyOnlyEM(Length value) const
    {
        const LayoutLength ll = value.toLayout;
        if (value.is_rem)
        {
            const int def = FontManager.defaultFontSize;
            return ll.applyPercent(def);
        }
        else if (value.is_em)
            return ll.applyPercent(fontSize);
        else
            return ll.applyPercent(0);
    }

    /// Set the property to inherit its value from parent widget
    void inherit(StyleProperty property)
    {
        bts(inheritBitArray.ptr, property);
        bts(overridenBitArray.ptr, property);
    }

    /// Set the property to its initial value
    void initialize(StyleProperty property)
    {
        final switch (property)
        {
            static foreach (name; __traits(allMembers, StyleProperty))
            {
                case mixin(`StyleProperty.` ~ name):
                    setDefault!name(true); // set by user
                    return;
            }
        }
    }

    /// Resolve style cascading and inheritance, update all properties
    void recompute(Style[] chain)
    {
        debug (styles)
            Log.d("--- Recomputing style for ", element.dbgname, " ---");

        // explode shorthands first
        foreach_reverse (st; chain)
            explodeShorthands(st);

        // find that we are not tied, being the root of style scope
        Element parent = element.parent;
        const bool canInherit = parent && !isolated;
        /// iterate through all properties
        static foreach (name; __traits(allMembers, StyleProperty))
        {{
            alias T = typeof(mixin(`_` ~ name));
            enum ptype = mixin(`StyleProperty.` ~ name);
            enum specialCSSType = getSpecialCSSType(ptype);
            enum cssname = StrHash(getCSSName(ptype));
            enum bool inheritsByDefault = inherited(ptype);

            const setByUser = isOverriden(ptype);
            bool setInStyles;
            // search in style chain if not overriden
            if (!setByUser)
            {
                bool inh;
                // find nearest written property
                foreach_reverse (st; chain)
                {
                    static if (!inheritsByDefault)
                    {
                        if (st.isInherited(cssname))
                        {
                            inh = true;
                            setInStyles = true;
                            break;
                        }
                    }
                    if (st.isInitial(cssname))
                    {
                        setDefault!name(false);
                        setInStyles = true;
                        break;
                    }
                    // get value here, also pass predicate that checks sanity of value
                    if (auto p = st.peek!(T, specialCSSType)(cssname, &sanitizeProperty!(ptype, T)))
                    {
                        setProperty!name(*p, false);
                        setInStyles = true;
                        break;
                    }
                }
                // set/reset 'inherit' flag
                if (inh)
                    bts(inheritBitArray.ptr, ptype);
                else
                    btr(inheritBitArray.ptr, ptype);
            }

            const noValue = !setByUser && !setInStyles;
            // resolve inherited properties
            if (inheritsByDefault && noValue || isInherited(ptype))
            {
                if (canInherit)
                    setProperty!name(mixin(`parent.style._` ~ name), false);
                else
                    setDefault!name(false);
            }
            else if (noValue)
            {
                // if nothing there - return value to defaults
                setDefault!name(false);
            }
        }}

        debug (styles)
            Log.d("--- End style recomputing ---");
    }

    private bool isInherited(StyleProperty ptype)
    {
        return bt(inheritBitArray.ptr, ptype) != 0;
    }

    private bool isOverriden(StyleProperty ptype)
    {
        return bt(overridenBitArray.ptr, ptype) != 0;
    }

    private void overrideProperty(StyleProperty ptype)
    {
        bts(overridenBitArray.ptr, ptype);
    }

    /// Checks bounds, like disallowed negative values
    private bool sanitizeProperty(StyleProperty ptype, T)(ref const(T) value)
    {
        with (StyleProperty)
        {
            static if (ptype == fontSize)
                return value.toLayout.applyPercent(100) >= 1;
            else static if (ptype == bgSize)
                return value.x.toLayout.applyPercent(100) >= 0 && value.y.toLayout.applyPercent(100) >= 0;
            else static if (
                ptype == width ||
                ptype == height ||
                ptype == minWidth ||
                ptype == maxWidth ||
                ptype == minHeight ||
                ptype == maxHeight ||
                ptype == flexBasis ||
                ptype == lineHeight
            )
                return value.toLayout.applyPercent(100) >= 0;
            else static if (
                ptype == paddingTop ||
                ptype == paddingRight ||
                ptype == paddingBottom ||
                ptype == paddingLeft ||
                ptype == borderTopWidth ||
                ptype == borderRightWidth ||
                ptype == borderBottomWidth ||
                ptype == borderLeftWidth ||
                ptype == borderTopLeftRadius ||
                ptype == borderTopRightRadius ||
                ptype == borderBottomLeftRadius ||
                ptype == borderBottomRightRadius ||
                ptype == rowGap ||
                ptype == columnGap
            )
                return value !is Length.none && value.toLayout.applyPercent(100) >= 0;
            else static if (
                ptype == flexGrow ||
                ptype == flexShrink
            )
                return value >= 0;
            else static if (
                ptype == justifyItems ||
                ptype == alignItems
            )
                return value != AlignItem.unspecified;
            else
                return true;
        }
    }

    /// Check whether the style can make transition for a CSS property
    bool hasTransitionFor(string property) const
    {
        if (_transitionTimingFunction is null || _transitionDuration <= 0)
            return false;
        if (_transitionProperty == "all" || _transitionProperty == property)
            return true;

        if (_transitionProperty == "padding")
            return property == "padding-top" || property == "padding-right" ||
                   property == "padding-bottom" || property == "padding-left";

        if (_transitionProperty == "background")
            return property == "background-color";

        const bprefix = "border-";
        const bplen = bprefix.length;
        if (_transitionProperty == "border-width")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-width" || rest == "right-width" ||
                   rest == "bottom-width" || rest == "left-width";
        }
        if (_transitionProperty == "border-color")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-color" || rest == "right-color" ||
                   rest == "bottom-color" || rest == "left-color";
        }
        if (_transitionProperty == "border")
        {
            if (property.length <= bplen || property[0 .. bplen] != bprefix)
                return false;
            const rest = property[bplen .. $];
            return rest == "top-width" || rest == "right-width" ||
                   rest == "bottom-width" || rest == "left-width" ||
                   rest == "top-color" || rest == "right-color" ||
                   rest == "bottom-color" || rest == "left-color";
        }

        if (_transitionProperty == "gap")
            return property == "row-gap" || property == "column-gap";

        return false;
    }

    private void setDefault(string name)(bool byUser)
    {
        enum ptype = mixin(`StyleProperty.` ~ name);

        static if (
            ptype == StyleProperty.borderTopColor ||
            ptype == StyleProperty.borderRightColor ||
            ptype == StyleProperty.borderBottomColor ||
            ptype == StyleProperty.borderLeftColor ||
            ptype == StyleProperty.textDecorColor)
        {
            // must be computed before
            setProperty!name(_textColor, byUser);
        }
        else
            setProperty!name(mixin(`defaults._` ~ name), byUser);
    }

    /// Set a property value, taking transitions into account
    private void setProperty(string name, T)(T newValue, bool byUser = true)
    {
        import std.meta : Alias;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`StyleProperty.` ~ name);

        if (byUser)
            overrideProperty(ptype);

        // do nothing if changed nothing
        if (field is newValue)
        {
            static if (isAnimatable(ptype))
            {
                // cancel possible animation
                element.cancelAnimation(name);
            }
            return;
        }
        // check animation
        static if (isAnimatable(ptype))
        {
            enum string cssname = getCSSName(ptype);
            if (hasTransitionFor(cssname))
            {
                animateProperty!name(newValue);
                return;
            }
        }
        // set it directly otherwise
        field = newValue;
        // invoke side effects
        element.handleStyleChange(ptype);
    }

    private void animateProperty(string name, T)(T ending)
    {
        import std.meta : Alias;
        import beamui.core.animations : Transition;

        alias field = Alias!(mixin("_" ~ name));
        enum ptype = mixin(`StyleProperty.` ~ name);

        T starting = field;
        auto tr = new Transition(_transitionDuration, _transitionTimingFunction, _transitionDelay);
        element.addAnimation(name, tr.duration,
            (double t) {
                field = tr.mix(starting, ending, t);
                element.handleStyleChange(ptype);
            }
        );
    }
}

private void explodeShorthands(Style st)
{
    static immutable margin = ShorthandInsets(
        StrHash("margin"),
        StrHash("margin-top"),
        StrHash("margin-right"),
        StrHash("margin-bottom"),
        StrHash("margin-left"));
    static immutable padding = ShorthandInsets(
        StrHash("padding"),
        StrHash("padding-top"),
        StrHash("padding-right"),
        StrHash("padding-bottom"),
        StrHash("padding-left"));
    static immutable placeContent = ShorthandPair!Distribution(
        StrHash("place-content"),
        StrHash("align-content"),
        StrHash("justify-content"));
    static immutable placeItems = ShorthandPair!AlignItem(
        StrHash("place-items"),
        StrHash("align-items"),
        StrHash("justify-items"));
    static immutable placeSelf = ShorthandPair!AlignItem(
        StrHash("place-self"),
        StrHash("align-self"),
        StrHash("justify-self"));
    static immutable gap = ShorthandPair!Length(
        StrHash("gap"),
        StrHash("row-gap"),
        StrHash("column-gap"));
    static immutable flexFlow = ShorthandFlexFlow(
        StrHash("flex-flow"),
        StrHash("flex-direction"),
        StrHash("flex-wrap"));
    static immutable flex = ShorthandFlex(
        StrHash("flex"),
        StrHash("flex-grow"),
        StrHash("flex-shrink"),
        StrHash("flex-basis"));
    static immutable gridArea = ShorthandGridArea(
        StrHash("grid-area"),
        StrHash("grid-row-start"),
        StrHash("grid-row-end"),
        StrHash("grid-column-start"),
        StrHash("grid-column-end"));
    static immutable gridRow = ShorthandGridLine(
        StrHash("grid-row"),
        StrHash("grid-row-start"),
        StrHash("grid-row-end"));
    static immutable gridColumn = ShorthandGridLine(
        StrHash("grid-column"),
        StrHash("grid-column-start"),
        StrHash("grid-column-end"));
    static immutable bg = ShorthandDrawable(
        StrHash("background"),
        StrHash("background-color"),
        StrHash("background-image"));
    static immutable border = ShorthandBorder(
        StrHash("border"),
        StrHash("border-top-width"),
        StrHash("border-top-style"),
        StrHash("border-top-color"),
        StrHash("border-right-width"),
        StrHash("border-right-style"),
        StrHash("border-right-color"),
        StrHash("border-bottom-width"),
        StrHash("border-bottom-style"),
        StrHash("border-bottom-color"),
        StrHash("border-left-width"),
        StrHash("border-left-style"),
        StrHash("border-left-color"));
    static immutable borderWidth = ShorthandInsets(
        StrHash("border-width"),
        StrHash("border-top-width"),
        StrHash("border-right-width"),
        StrHash("border-bottom-width"),
        StrHash("border-left-width"));
    static immutable borderStyle = ShorthandBorderStyle(
        StrHash("border-style"),
        StrHash("border-top-style"),
        StrHash("border-right-style"),
        StrHash("border-bottom-style"),
        StrHash("border-left-style"));
    static immutable borderColor = ShorthandColors(
        StrHash("border-color"),
        StrHash("border-top-color"),
        StrHash("border-right-color"),
        StrHash("border-bottom-color"),
        StrHash("border-left-color"));
    static immutable borderTop = ShorthandBorderSide(
        StrHash("border-top"),
        StrHash("border-top-width"),
        StrHash("border-top-style"),
        StrHash("border-top-color"));
    static immutable borderRight = ShorthandBorderSide(
        StrHash("border-right"),
        StrHash("border-right-width"),
        StrHash("border-right-style"),
        StrHash("border-right-color"),);
    static immutable borderBottom = ShorthandBorderSide(
        StrHash("border-bottom"),
        StrHash("border-bottom-width"),
        StrHash("border-bottom-style"),
        StrHash("border-bottom-color"));
    static immutable borderLeft = ShorthandBorderSide(
        StrHash("border-left"),
        StrHash("border-left-width"),
        StrHash("border-left-style"),
        StrHash("border-left-color"));
    static immutable borderRadii = ShorthandInsets(
        StrHash("border-radius"),
        StrHash("border-top-left-radius"),
        StrHash("border-top-right-radius"),
        StrHash("border-bottom-left-radius"),
        StrHash("border-bottom-right-radius"));
    static immutable textDecor = ShorthandTextDecor(
        StrHash("text-decoration"),
        StrHash("text-decoration-line"),
        StrHash("text-decoration-color"),
        StrHash("text-decoration-style"));
    static immutable transition = ShorthandTransition(
        StrHash("transition"),
        StrHash("transition-property"),
        StrHash("transition-duration"),
        StrHash("transition-timing-function"),
        StrHash("transition-delay"));
    st.explode(margin);
    st.explode(padding);
    st.explode(placeContent);
    st.explode(placeItems);
    st.explode(placeSelf);
    st.explode(gap);
    st.explode(flexFlow);
    st.explode(flex);
    st.explode(gridArea);
    st.explode(gridRow);
    st.explode(gridColumn);
    st.explode(bg);
    st.explode(border);
    st.explode(borderWidth);
    st.explode(borderStyle);
    st.explode(borderColor);
    st.explode(borderTop);
    st.explode(borderRight);
    st.explode(borderBottom);
    st.explode(borderLeft);
    st.explode(borderRadii);
    st.explode(textDecor);
    st.explode(transition);
}

/// Get property name how it looks in CSS
string getCSSName(StyleProperty ptype)
{
    final switch (ptype) with (StyleProperty)
    {
        case display: return "display";
        case width:     return "width";
        case height:    return "height";
        case minWidth:  return "min-width";
        case maxWidth:  return "max-width";
        case minHeight: return "min-height";
        case maxHeight: return "max-height";
        case paddingTop:    return "padding-top";
        case paddingRight:  return "padding-right";
        case paddingBottom: return "padding-bottom";
        case paddingLeft:   return "padding-left";
        case marginTop:    return "margin-top";
        case marginRight:  return "margin-right";
        case marginBottom: return "margin-bottom";
        case marginLeft:   return "margin-left";
        case left:   return "left";
        case top:    return "top";
        case right:  return "right";
        case bottom: return "bottom";
        case alignment: return "align";
        case stretch:   return "stretch";
        case justifyContent: return "justify-content";
        case justifyItems:   return "justify-items";
        case justifySelf:    return "justify-self";
        case alignContent:   return "align-content";
        case alignItems:     return "align-items";
        case alignSelf:      return "align-self";
        case rowGap:    return "row-gap";
        case columnGap: return "column-gap";
        case order:  return "order";
        case zIndex: return "z-index";
        case flexDirection: return "flex-direction";
        case flexWrap:      return "flex-wrap";
        case flexGrow:      return "flex-grow";
        case flexShrink:    return "flex-shrink";
        case flexBasis:     return "flex-basis";
        case gridTemplateRows:    return "grid-template-rows";
        case gridTemplateColumns: return "grid-template-columns";
        case gridTemplateAreas:   return "grid-template-areas";
        case gridAutoFlow:    return "grid-auto-flow";
        case gridAutoRows:    return "grid-auto-rows";
        case gridAutoColumns: return "grid-auto-columns";
        case gridRowStart:    return "grid-row-start";
        case gridRowEnd:      return "grid-row-end";
        case gridColumnStart: return "grid-column-start";
        case gridColumnEnd:   return "grid-column-end";
        case bgColor:    return "background-color";
        case bgImage:    return "background-image";
        case bgPosition: return "background-position";
        case bgSize:     return "background-size";
        case bgRepeat:   return "background-repeat";
        case bgOrigin:   return "background-origin";
        case bgClip:     return "background-clip";
        case borderTopWidth:    return "border-top-width";
        case borderRightWidth:  return "border-right-width";
        case borderBottomWidth: return "border-bottom-width";
        case borderLeftWidth:   return "border-left-width";
        case borderTopColor:    return "border-top-color";
        case borderRightColor:  return "border-right-color";
        case borderBottomColor: return "border-bottom-color";
        case borderLeftColor:   return "border-left-color";
        case borderTopStyle:    return "border-top-style";
        case borderRightStyle:  return "border-right-style";
        case borderBottomStyle: return "border-bottom-style";
        case borderLeftStyle:   return "border-left-style";
        case borderTopLeftRadius: return "border-top-left-radius";
        case borderTopRightRadius: return "border-top-right-radius";
        case borderBottomLeftRadius: return "border-bottom-left-radius";
        case borderBottomRightRadius: return "border-bottom-right-radius";
        case boxShadow:  return "box-shadow";
        case fontFace:   return "font-face";
        case fontFamily: return "font-family";
        case fontSize:   return "font-size";
        case fontStyle:  return "font-style";
        case fontWeight: return "font-weight";
        case letterSpacing: return "letter-spacing";
        case lineHeight:    return "line-height";
        case tabSize:       return "tab-size";
        case textAlign:     return "text-align";
        case textDecorColor: return "text-decoration-color";
        case textDecorLine:  return "text-decoration-line";
        case textDecorStyle: return "text-decoration-style";
        case textHotkey:    return "text-hotkey";
        case textIndent:    return "text-indent";
        case textOverflow:  return "text-overflow";
        case textTransform: return "text-transform";
        case whiteSpace:    return "white-space";
        case wordSpacing:   return "word-spacing";
        case textColor:      return "color";
        case focusRectColor: return "focus-rect-color";
        case opacity:        return "opacity";
        case mixBlendMode:   return "mix-blend-mode";
        case transitionProperty:       return "transition-property";
        case transitionTimingFunction: return "transition-timing-function";
        case transitionDuration:       return "transition-duration";
        case transitionDelay:          return "transition-delay";
        case cursor: return "cursor";
    }
}

private SpecialCSSType getSpecialCSSType(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case zIndex:     return SpecialCSSType.zIndex;
        case bgImage:    return SpecialCSSType.image;
        case fontWeight: return SpecialCSSType.fontWeight;
        case opacity:    return SpecialCSSType.opacity;
        case transitionProperty: return SpecialCSSType.transitionProperty;
        case transitionDuration: return SpecialCSSType.time;
        case transitionDelay:    return SpecialCSSType.time;
        default: return SpecialCSSType.none;
    }
}

/// Returns true whether the property can be animated
bool isAnimatable(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case width: .. case marginLeft:
        case left: .. case bottom:
        case rowGap:
        case columnGap:
        case bgColor:
        case bgPosition:
        case bgSize:
        case letterSpacing:
        case lineHeight:
        case wordSpacing:
        case textColor:
        case focusRectColor:
        case borderTopColor: .. case borderLeftColor:
        case textDecorColor:
        case opacity:
            return true;
        default:
            return false;
    }
}

/// Returns true whether the property value implicitly inherits from parent widget
bool inherited(StyleProperty ptype)
{
    switch (ptype) with (StyleProperty)
    {
        case fontFace: .. case fontWeight:
        case letterSpacing:
        case lineHeight:
        case tabSize:
        case textAlign:
        case textIndent:
        case textTransform:
        case whiteSpace:
        case wordSpacing:
        case textColor:
        case cursor:
            return true;
        default:
            return false;
    }
}
