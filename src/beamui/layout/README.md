## Implementation notes

> These notes relate to `Element` and `ElemPanel` classes too.

All elements are rectangles.
All computations are performed in Cartesian coordinate system
with the origin in top-left corner and Y axis going down.

Element positions are made relative to the top-left corner of parent container.

### Phases

The element layout is done in two phases: "measure" and "layout".

In "measure" phase, you can imagine element as a floating body with equal pressure inside and outside.
It provides size constraints as the result of this phase.

In "layout" phase, container computes chidren rectangles (sizes first, positions next) based on their constraints,
and then informs each element: "This is your box, set up yourself and place your children".

### Intrinsic and extrinsic sizes

Intrinsic sizes are based on the content, e.g. text width and height.
Extrinsic ones are based on computed style values and may be unspecified.

The element has a preferred size ("nat" for short) - the optimal size,
in which the element doesn't need to enlarge anymore to show the content.
It also has minimal and maximal sizes that restrict contraction and stretching of the element.

Extrinsic min and nat sizes have higher priority on "measure" phase.
They, if set, rewrite intrinsic sizes of the element.
Max size will rewrite only a larger intrinsic size.

### Re-layout optimization

We always propagate `needLayout` and `needDraw` flags to the root of element hierarchy.

In such case, "measure" phase depends on `needLayout` flag only,
"layout" depends on `needLayout` flag and the box, coming from the parent container.
Therefore, we can skip measure and/or layout of a subtree entirely,
if `needLayout` flag is false and box stays the same.

Relative coordinates also help to eliminate a lot of unnecessary layout computations,
because most of the time boxes don't move against their parents.
