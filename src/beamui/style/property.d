/**

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.style.property;

import beamui.core.animations : TimingFunction;
import beamui.core.editable : TabSize;
import beamui.core.units : Length;
import beamui.graphics.colors : Color;
import beamui.graphics.compositing : BlendMode;
import beamui.graphics.drawables : BorderStyle, BoxShadowDrawable, BoxType, Drawable, RepeatStyle;
import beamui.layout.alignment : Align, AlignItem, Distribution, Stretch;
import beamui.layout.flex : FlexDirection, FlexWrap;
import beamui.layout.grid : GridFlow, GridLineName, GridNamedAreas, TrackSize;
import beamui.style.computed_style : StyleProperty;
import beamui.style.types;
import beamui.text.fonts : FontFamily, FontStyle;
import beamui.text.style;
import beamui.widgets.widget : CursorType;

package union BuiltinPropertyValue
{
    Align _Align;
    AlignItem _AlignItem;
    BgPositionRaw _BgPositionRaw;
    BgSizeRaw _BgSizeRaw;
    BlendMode _BlendMode;
    BorderStyle _BorderStyle;
    BoxShadowDrawable _BoxShadowDrawable;
    BoxType _BoxType;
    Color _Color;
    CursorType _CursorType;
    Distribution _Distribution;
    Drawable _Drawable;
    FlexDirection _FlexDirection;
    FlexWrap _FlexWrap;
    float _float;
    FontFamily _FontFamily;
    FontStyle _FontStyle;
    GridFlow _GridFlow;
    GridLineName _GridLineName;
    GridNamedAreas _GridNamedAreas;
    int _int;
    Length _Length;
    RepeatStyle _RepeatStyle;
    Stretch _Stretch;
    string _string;
    TabSize _TabSize;
    TextAlign _TextAlign;
    TextDecorLine _TextDecorLine;
    TextDecorStyle _TextDecorStyle;
    TextHotkey _TextHotkey;
    TextOverflow _TextOverflow;
    TextTransform _TextTransform;
    TimingFunction _TimingFunction;
    TrackSize _TrackSize;
    uint _uint;
    ushort _ushort;
    WhiteSpace _WhiteSpace;
}

package struct StylePropertyList
{
    enum Pointer : ubyte { none, inherit, initial, some }

    BuiltinPropertyValue[] values;
    Pointer[StyleProperty.max + 1] pointers;

    void set(T)(StyleProperty ptype, T v)
    {
        BuiltinPropertyValue value;
        mixin("value._" ~ T.stringof) = v;

        if (!pointers[ptype])
        {
            values ~= value;
            pointers[ptype] = cast(Pointer)values.length;
        }
        else
        {
            values[pointers[ptype] - Pointer.some] = value;
        }
    }

    void inherit(StyleProperty property)
    {
        pointers[property] = Pointer.inherit;
    }

    void initialize(StyleProperty property)
    {
        pointers[property] = Pointer.initial;
    }
}
