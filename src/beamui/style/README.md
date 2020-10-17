## Implementation notes

### Kinds of values

According to [CSS Cascading and Inheritance](https://www.w3.org/TR/css-cascade-4/#value-stages), values go through these transformations:
1. declared - collect all raw values applicable to an element
2. cascaded - pick the most specific values using cascading rules
3. specified - assign properties with no values to their defaults
4. computed - resolve relative (like `em`) and inherited values
5. used - compute values based on layout (such as percents)
6. actual - do rounding and other weird adjustments

Now here, `Style` objects (created inside `theme` module) and `InlineStyle` objects (created by user) store step 1 values in `StylePropertyList`.
It holds arrays for built-in and custom properties.
The first is basically a dense map of unions of all built-in value types.
The second is a map of token lists.
At this stage, there are already no repeating values and shorthand properties.

2-4 stages happen in `ComputedStyle`.
It takes a sorted style list, inline style, and parent computed style and does all the job of cascading and resolving values, including custom.
It also propagates all inherited values down the tree.
More so, it setups transitions.
Each element holds one computed style instance, available in `style` property.

Used and actual values in the library are the same, and they are not actually style values anymore.
Elements store them after layout in properties such as `box` and `font`.
Lengths are in platform-independent pixels.
Snapping (but not conversion) to screen pixels happens either immediately after layout, or during painting.
