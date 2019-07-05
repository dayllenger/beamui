/**

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.layout.alignment;

/// Box alignment options
enum Align : uint
{
    /// Alignment is not specified
    unspecified = 0,
    /// Horizontally align to the left of box
    left = 1,
    /// Horizontally align to the right of box
    right = 2,
    /// Horizontally align to the center of box
    hcenter = left | right,
    /// Vertically align to the top of box
    top = 4,
    /// Vertically align to the bottom of box
    bottom = 8,
    /// Vertically align to the center of box
    vcenter = top | bottom,
    /// Align to the center of box (hcenter | vcenter)
    center = hcenter | vcenter,
    /// Align to the top left corner of box (left | top)
    topleft = left | top,
}

/// Controls whether widget occupies all available width/height in a linear layout
enum Stretch
{
    none,
    /// Applies along main axis, i.e. by width in horizontal layouts and by height in vertical ones
    main,
    /// Applies along secondary axis, i.e. by height in horizontal layouts and by width in vertical ones
    cross,
    both,
}
