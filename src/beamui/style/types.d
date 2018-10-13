/**

Copyright: Vadim Lopatin 2014-2017, dayllenger 2018
License:   Boost License 1.0
Authors:   Vadim Lopatin, dayllenger
*/
module beamui.style.types;

import beamui.core.types : State;

/// Align option bit constants
enum Align : uint
{
    /// Alignment is not specified
    unspecified = 0,
    /// Horizontally align to the left of box
    left = 1,
    /// Horizontally align to the right of box
    right = 2,
    /// Horizontally align to the center of box
    hcenter = 1 | 2,
    /// Vertically align to the top of box
    top = 4,
    /// Vertically align to the bottom of box
    bottom = 8,
    /// Vertically align to the center of box
    vcenter = 4 | 8,
    /// Align to the center of box (vcenter | hcenter)
    center = vcenter | hcenter,
    /// Align to the top left corner of box (left | top)
    topleft = left | top,
}

/// Text drawing flag bits
enum TextFlag : uint
{
    /// Not set
    unspecified = 0,
    /// Text contains hot key prefixed with & char (e.g. "&File")
    hotkeys = 1,
    /// Underline hot key when drawing
    underlineHotkeys = 2,
    /// Underline hot key when Alt is pressed
    underlineHotkeysOnAlt = 4,
    /// Underline text when drawing
    underline = 8,
    /// Strikethrough text when drawing
    strikeThrough = 16, // TODO:
    /// Use text flags from parent widget
    parent = 32
}

struct Selector
{
    TypeInfo_Class widgetType;
    string id;
    string pseudoElement;
    State state = State.normal;
}

enum SpecialCSSType
{
    none,
    fontWeight, /// ushort
    image, /// Drawable
    opacity, /// ubyte
    time, /// uint
    transitionProperty, /// string
}

/// Annotate widget property with @forCSS before using it in a style sheet
struct forCSS
{
    /// Property name as it should look in CSS
    string name;
    SpecialCSSType specialType;
}

struct shorthandBorder
{
    string name;
    string topWidth;
    string rightWidth;
    string bottomWidth;
    string leftWidth;
    string color;
}

struct shorthandDrawable
{
    string name;
    string color;
    string image;
}

struct shorthandInsets
{
    string name;
    string top;
    string right;
    string bottom;
    string left;
}

struct shorthandTransition
{
    string name;
    string property;
    string duration;
    string timingFunction;
    string delay;
}

/// Annotate CSS property with @animatable to enable animations for it
struct animatable
{
}
