/**
Basic math utilities.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.core.math;

nothrow @safe:

import std.math : fabs;

/// Check that a `float` number is equal to zero in first 6 signs after point
pragma(inline, true) bool fzero6(float a) {
    return -1e-6f < a && a < 1e-6f;
}
/// Check that a `float` number is closer to zero than `0.01`
pragma(inline, true) bool fzero2(float a) {
    return -0.00999999f < a && a < 0.00999999f;
}

/// Check that two `float` numbers are equal in first 6 signs after point
pragma(inline, true) bool fequal6(float a, float b) {
    return fabs(a - b) < 1e-6f;
}
/// Check that two `float` numbers differ in less than `0.01`
pragma(inline, true) bool fequal2(float a, float b) {
    return fabs(a - b) < 0.0099999f;
}
// dfmt off
pragma(inline, true)
T min(T)(T a, T b) { return a < b ? a : b; }
T min(T)(T a, T b, T c) { return min(a, min(b, c)); }
T min(T)(T a, T b, T c, T d) { return min(a, min(b, min(c, d))); }
T min(T)(T a, T b, T c, T d, T e) { return min(a, min(b, min(c, min(d, e)))); }

pragma(inline, true)
T max(T)(T a, T b) { return a > b ? a : b; }
T max(T)(T a, T b, T c) { return max(a, max(b, c)); }
T max(T)(T a, T b, T c, T d) { return max(a, max(b, max(c, d))); }
T max(T)(T a, T b, T c, T d, T e) { return max(a, max(b, max(c, max(d, e)))); }

pragma(inline, true)
T clamp(T)(T v, T min, T max) { return v < min ? min : v > max ? max : v; }
// dfmt on
