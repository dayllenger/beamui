/**
CSS Flexible Box Layout.

Copyright: dayllenger 2020
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.flex;

enum FlexDirection : ubyte
{
    row,
    rowReverse,
    column,
    columnReverse,
}

enum FlexWrap : ubyte
{
    off,
    on,
    reverse,
}
