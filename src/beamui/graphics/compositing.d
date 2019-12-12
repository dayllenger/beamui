/**
Enums and structs for compositing and blending.

Copyright: dayllenger 2019
License:   Boost License 1.0
Authors:   dayllenger
*/
module beamui.graphics.compositing;

/// Porter-Duff compositing modes
enum CompositeMode
{
    copy,
    sourceOver,
    sourceIn,
    sourceOut,
    sourceAtop,
    destOver,
    destIn,
    destOut,
    destAtop,
    xor,
    lighter,
}

/// Standard W3C blend modes
enum BlendMode
{
    normal,
    multiply,
    screen,
    overlay,
    darken,
    lighten,
    colorDodge,
    colorBurn,
    hardLight,
    softLight,
    difference,
    exclusion,

    hue,
    saturation,
    color,
    luminosity,
}

/// Internal enum that represents common hardware alpha blend factors
enum AlphaBlendFactor
{
    zero,
    one,
    src,
    dst,
    oneMinusSrc,
    oneMinusDst,
}

/// Internal struct that maps `CompositeMode` onto hardware framebuffer blend modes
struct CompositeOperation
{
    AlphaBlendFactor src;
    AlphaBlendFactor dst;
}

/// Get the blend factors of a composite mode (for premultiplied source and destination)
CompositeOperation getBlendFactors(CompositeMode compositeMode)
{
    final switch (compositeMode) with (AlphaBlendFactor)
    {
        case CompositeMode.copy:       return CompositeOperation(one, zero);
        case CompositeMode.sourceOver: return CompositeOperation(one, oneMinusSrc);
        case CompositeMode.sourceIn:   return CompositeOperation(dst, zero);
        case CompositeMode.sourceOut:  return CompositeOperation(oneMinusDst, zero);
        case CompositeMode.sourceAtop: return CompositeOperation(dst, oneMinusSrc);
        case CompositeMode.destOver:   return CompositeOperation(oneMinusDst, one);
        case CompositeMode.destIn:     return CompositeOperation(zero, src);
        case CompositeMode.destOut:    return CompositeOperation(zero, oneMinusSrc);
        case CompositeMode.destAtop:   return CompositeOperation(oneMinusDst, src);
        case CompositeMode.xor:        return CompositeOperation(oneMinusDst, oneMinusSrc);
        case CompositeMode.lighter:    return CompositeOperation(one, one);
    }
}
