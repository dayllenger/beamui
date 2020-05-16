/**
WGL (base + extensions) dynamic bindings, converted from Derelict to BindBC.

Copyright: Michael D. Parker, dayllenger
License:   Boost License 1.0
*/
module wgl;

version (Windows):

import bindbc.loader.sharedlib;

private SharedLib lib;

bool hasLoadedWGL()
{
    return lib != invalidHandle;
}

// no need to unload, because OpenGL bindings handle it

/// Load basic WGL functions, without extensions
bool loadWGL()
{
    const(char)[] libName = "opengl32.dll";

    lib = load(libName.ptr);
    if (lib == invalidHandle)
        return false;

    const errCount = errorCount();

    bindSymbol(lib, cast(void**)&wglCopyContext, "wglCopyContext");
    bindSymbol(lib, cast(void**)&wglCreateContext, "wglCreateContext");
    bindSymbol(lib, cast(void**)&wglCreateLayerContext, "wglCreateLayerContext");
    bindSymbol(lib, cast(void**)&wglDeleteContext, "wglDeleteContext");
    bindSymbol(lib, cast(void**)&wglDescribeLayerPlane, "wglDescribeLayerPlane");
    bindSymbol(lib, cast(void**)&wglGetCurrentContext, "wglGetCurrentContext");
    bindSymbol(lib, cast(void**)&wglGetCurrentDC, "wglGetCurrentDC");
    bindSymbol(lib, cast(void**)&wglGetLayerPaletteEntries, "wglGetLayerPaletteEntries");
    bindSymbol(lib, cast(void**)&wglGetProcAddress, "wglGetProcAddress");
    bindSymbol(lib, cast(void**)&wglMakeCurrent, "wglMakeCurrent");
    bindSymbol(lib, cast(void**)&wglRealizeLayerPalette, "wglRealizeLayerPalette");
    bindSymbol(lib, cast(void**)&wglSetLayerPaletteEntries, "wglSetLayerPaletteEntries");
    bindSymbol(lib, cast(void**)&wglShareLists, "wglShareLists");
    bindSymbol(lib, cast(void**)&wglSwapLayerBuffers, "wglSwapLayerBuffers");
    bindSymbol(lib, cast(void**)&wglUseFontBitmapsW, "wglUseFontBitmapsW");
    bindSymbol(lib, cast(void**)&wglUseFontOutlinesW, "wglUseFontOutlinesW");

    return errorCount() == errCount;
}

/// A context must be activated in order to load extensions
void loadWGLExtensions()
{
    if (!wglGetCurrentContext || wglGetCurrentContext() is null)
        return;

    // This needs to be loaded first. If it fails to load, just abort.
    _WGL_ARB_extensions_string = bindWGLFunc(cast(void**)&wglGetExtensionsStringARB, "wglGetExtensionsStringARB");
    if (!_WGL_ARB_extensions_string)
        return;

    const char* extensions = wglGetExtensionsStringARB(wglGetCurrentDC());
    if (!extensions)
        return;

    if (hasExtension(extensions, "WGL_ARB_buffer_region"))
    {
        _WGL_ARB_buffer_region =
            bindWGLFunc(cast(void**)&wglCreateBufferRegionARB, "wglCreateBufferRegionARB") &&
            bindWGLFunc(cast(void**)&wglDeleteBufferRegionARB, "wglDeleteBufferRegionARB") &&
            bindWGLFunc(cast(void**)&wglSaveBufferRegionARB, "wglSaveBufferRegionARB") &&
            bindWGLFunc(cast(void**)&wglRestoreBufferRegionARB, "wglRestoreBufferRegionARB");
    }
    if (hasExtension(extensions, "WGL_ARB_create_context"))
    {
        _WGL_ARB_create_context =
            bindWGLFunc(cast(void**)&wglCreateContextAttribsARB, "wglCreateContextAttribsARB");
    }

    _WGL_ARB_create_context_profile = hasExtension(extensions, "WGL_ARB_create_context_profile");
    _WGL_ARB_create_context_robustness = hasExtension(extensions, "WGL_ARB_create_context_robustness");
    _WGL_ARB_framebuffer_sRGB = hasExtension(extensions, "WGL_ARB_framebuffer_sRGB");

    if (hasExtension(extensions, "WGL_ARB_make_current_read"))
    {
        _WGL_ARB_make_current_read =
            bindWGLFunc(cast(void**)&wglMakeContextCurrentARB, "wglMakeContextCurrentARB") &&
            bindWGLFunc(cast(void**)&wglGetCurrentReadDCARB, "wglGetCurrentReadDCARB");
    }

    _WGL_ARB_multisample = hasExtension(extensions, "WGL_ARB_multisample");

    if (hasExtension(extensions, "WGL_ARB_pbuffer"))
    {
        _WGL_ARB_pbuffer =
            bindWGLFunc(cast(void**)&wglCreatePbufferARB, "wglCreatePbufferARB") &&
            bindWGLFunc(cast(void**)&wglGetPbufferDCARB, "wglGetPbufferDCARB") &&
            bindWGLFunc(cast(void**)&wglReleasePbufferDCARB, "wglReleasePbufferDCARB") &&
            bindWGLFunc(cast(void**)&wglDestroyPbufferARB, "wglDestroyPbufferARB") &&
            bindWGLFunc(cast(void**)&wglQueryPbufferARB, "wglQueryPbufferARB");
    }
    if (hasExtension(extensions, "WGL_ARB_pixel_format"))
    {
        _WGL_ARB_pixel_format =
            bindWGLFunc(cast(void**)&wglGetPixelFormatAttribivARB, "wglGetPixelFormatAttribivARB") &&
            bindWGLFunc(cast(void**)&wglGetPixelFormatAttribfvARB, "wglGetPixelFormatAttribfvARB") &&
            bindWGLFunc(cast(void**)&wglChoosePixelFormatARB, "wglChoosePixelFormatARB");
    }

    _WGL_ARB_pixel_format_float = hasExtension(extensions, "WGL_ARB_pixel_format_float");

    if (hasExtension(extensions, "WGL_ARB_render_texture"))
    {
        _WGL_ARB_render_texture =
            bindWGLFunc(cast(void**)&wglBindTexImageARB, "wglBindTexImageARB") &&
            bindWGLFunc(cast(void**)&wglReleaseTexImageARB, "wglReleaseTexImageARB") &&
            bindWGLFunc(cast(void**)&wglSetPbufferAttribARB, "wglSetPbufferAttribARB");
    }

    _WGL_ARB_robustness_application_isolation = hasExtension(extensions,
            "WGL_ARB_robustness_application_isolation");
    _WGL_ARB_robustness_share_group_isolation = hasExtension(extensions,
            "WGL_ARB_robustness_share_group_isolation");

    if (hasExtension(extensions, "WGL_EXT_swap_control"))
    {
        _WGL_EXT_swap_control =
            bindWGLFunc(cast(void**)&wglSwapIntervalEXT, "wglSwapIntervalEXT") &&
            bindWGLFunc(cast(void**)&wglGetSwapIntervalEXT, "wglGetSwapIntervalEXT");
    }
}

private bool bindWGLFunc(void** ptr, const(char)* name)
{
    if (auto sym = wglGetProcAddress(name))
    {
        *ptr = cast(void*)sym;
        return true;
    }
    return false;
}

private bool hasExtension(const(char)* extensions, const(char)* name)
{
    import core.stdc.string : strlen, strstr;

    const len = strlen(name);
    const(char)* ext = strstr(extensions, name);
    while(ext)
    {
        // It's possible that the extension name is actually a
        // substring of another extension. If not, then the
        // character following the name in the extension string
        // should be a space (or possibly the null character).
        if(ext[len] == ' ' || ext[len] == '\0')
            return true;
        ext = strstr(ext + len, name);
    }
    return false;
}

//===============================================================

import core.sys.windows.windef;
import core.sys.windows.wingdi : GLYPHMETRICSFLOAT, LAYERPLANEDESCRIPTOR;

alias HPBUFFERARB = HANDLE;

extern (Windows) @nogc nothrow
{
    alias p_CopyContext = BOOL function(void*, void*);
    alias p_CreateContext = void* function(void*);
    alias p_CreateLayerContext = void* function(void*, int);
    alias p_DeleteContext = BOOL function(void*);
    alias p_DescribeLayerPlane = BOOL function(void*, int, int, UINT, LAYERPLANEDESCRIPTOR*);
    alias p_GetCurrentContext = void* function();
    alias p_GetCurrentDC = void* function();
    alias p_GetLayerPaletteEntries = int function(void*, int, int, int, COLORREF*);
    alias p_GetProcAddress = FARPROC function(LPCSTR);
    alias p_MakeCurrent = BOOL function(void*, void*);
    alias p_RealizeLayerPalette = BOOL function(void*, int, BOOL);
    alias p_SetLayerPaletteEntries = int function(void*, int, int, int, COLORREF*);
    alias p_ShareLists = BOOL function(void*, void*);
    alias p_SwapLayerBuffers = BOOL function(void*, UINT);
    alias p_UseFontBitmapsW = BOOL function(void*, DWORD, DWORD, DWORD);
    alias p_UseFontOutlinesW = BOOL function(void*, DWORD, DWORD, DWORD, FLOAT, FLOAT, int, GLYPHMETRICSFLOAT*);

    // WGL_ARB_extensions_string
    alias p_GetExtensionsStringARB = const(char*) function(HDC);

    // WGL_ARB_buffer_region
    alias p_CreateBufferRegionARB = HANDLE function(HDC, int, UINT);
    alias p_DeleteBufferRegionARB = void function(HANDLE);
    alias p_SaveBufferRegionARB = BOOL function(HANDLE, int, int, int, int);
    alias p_RestoreBufferRegionARB = BOOL function(HANDLE, int, int, int, int, int, int);

    // WGL_ARB_create_context
    alias p_CreateContextAttribsARB = HGLRC function(HDC, HGLRC, const(int)*);

    // WGL_ARB_make_current_read
    alias p_MakeContextCurrentARB = BOOL function(HDC, HDC, HGLRC);
    alias p_GetCurrentReadDCARB = HDC function();

    // WGL_ARB_pbuffer
    alias p_CreatePbufferARB = HPBUFFERARB function(HDC, int, int, int, const(int)*);
    alias p_GetPbufferDCARB = HDC function(HPBUFFERARB);
    alias p_ReleasePbufferDCARB = int function(HPBUFFERARB, HDC);
    alias p_DestroyPbufferARB = BOOL function(HPBUFFERARB);
    alias p_QueryPbufferARB = BOOL function(HPBUFFERARB, int, int);

    // WGL_ARB_pixel_format
    alias p_GetPixelFormatAttribivARB = BOOL function(HDC, int, int, UINT, const(int)*, int*);
    alias p_GetPixelFormatAttribfvARB = BOOL function(HDC, int, int, UINT, const(int)*, FLOAT*);
    alias p_ChoosePixelFormatARB = BOOL function(HDC, const(int)*, const(FLOAT)*, UINT, int*, UINT*);

    // WGL_ARB_render_texture
    alias p_BindTexImageARB = BOOL function(HPBUFFERARB, int);
    alias p_ReleaseTexImageARB = BOOL function(HPBUFFERARB, int);
    alias p_SetPbufferAttribARB = BOOL function(HPBUFFERARB, const(int)*);

    // WGL_EXT_swap_control
    alias p_SwapIntervalEXT = BOOL function(int);
    alias p_GetSwapIntervalEXT = int function();
}

__gshared
{
    p_CopyContext wglCopyContext;
    p_CreateContext wglCreateContext;
    p_CreateLayerContext wglCreateLayerContext;
    p_DeleteContext wglDeleteContext;
    p_DescribeLayerPlane wglDescribeLayerPlane;
    p_GetCurrentContext wglGetCurrentContext;
    p_GetCurrentDC wglGetCurrentDC;
    p_GetLayerPaletteEntries wglGetLayerPaletteEntries;
    p_GetProcAddress wglGetProcAddress;
    p_MakeCurrent wglMakeCurrent;
    p_RealizeLayerPalette wglRealizeLayerPalette;
    p_SetLayerPaletteEntries wglSetLayerPaletteEntries;
    p_ShareLists wglShareLists;
    p_SwapLayerBuffers wglSwapLayerBuffers;
    p_UseFontBitmapsW wglUseFontBitmapsW;
    p_UseFontOutlinesW wglUseFontOutlinesW;

    p_GetExtensionsStringARB wglGetExtensionsStringARB;
    p_CreateBufferRegionARB wglCreateBufferRegionARB;
    p_DeleteBufferRegionARB wglDeleteBufferRegionARB;
    p_SaveBufferRegionARB wglSaveBufferRegionARB;
    p_RestoreBufferRegionARB wglRestoreBufferRegionARB;
    p_CreateContextAttribsARB wglCreateContextAttribsARB;
    p_MakeContextCurrentARB wglMakeContextCurrentARB;
    p_GetCurrentReadDCARB wglGetCurrentReadDCARB;
    p_CreatePbufferARB wglCreatePbufferARB;
    p_GetPbufferDCARB wglGetPbufferDCARB;
    p_ReleasePbufferDCARB wglReleasePbufferDCARB;
    p_DestroyPbufferARB wglDestroyPbufferARB;
    p_QueryPbufferARB wglQueryPbufferARB;
    p_GetPixelFormatAttribivARB wglGetPixelFormatAttribivARB;
    p_GetPixelFormatAttribfvARB wglGetPixelFormatAttribfvARB;
    p_ChoosePixelFormatARB wglChoosePixelFormatARB;
    p_BindTexImageARB wglBindTexImageARB;
    p_ReleaseTexImageARB wglReleaseTexImageARB;
    p_SetPbufferAttribARB wglSetPbufferAttribARB;

    p_SwapIntervalEXT wglSwapIntervalEXT;
    p_GetSwapIntervalEXT wglGetSwapIntervalEXT;
}

alias wglUseFontBitmaps = wglUseFontBitmapsW;
alias wglUseFontOutlines = wglUseFontOutlinesW;

@nogc nothrow @property
{
    bool WGL_ARB_extensions_string() { return _WGL_ARB_extensions_string; }
    bool WGL_ARB_buffer_region() { return _WGL_ARB_buffer_region; }
    bool WGL_ARB_create_context() { return _WGL_ARB_create_context; }
    bool WGL_ARB_create_context_profile() { return _WGL_ARB_create_context_profile; }
    bool WGL_ARB_create_context_robustness() { return _WGL_ARB_create_context_robustness; }
    bool WGL_ARB_framebuffer_sRGB() { return _WGL_ARB_framebuffer_sRGB; }
    bool WGL_ARB_make_current_read() { return _WGL_ARB_make_current_read; }
    bool WGL_ARB_multisample() { return _WGL_ARB_multisample; }
    bool WGL_ARB_pbuffer() { return _WGL_ARB_pbuffer; }
    bool WGL_ARB_pixel_format() { return _WGL_ARB_pixel_format; }
    bool WGL_ARB_pixel_format_float() { return _WGL_ARB_pixel_format_float; }
    bool WGL_ARB_render_texture() { return _WGL_ARB_render_texture; }
    bool WGL_ARB_robustness_application_isolation() { return _WGL_ARB_robustness_application_isolation; }
    bool WGL_ARB_robustness_share_group_isolation() { return _WGL_ARB_robustness_share_group_isolation; }
    bool WGL_EXT_swap_control() { return _WGL_EXT_swap_control; }
}

private __gshared
{
    bool _WGL_ARB_extensions_string;
    bool _WGL_ARB_buffer_region;
    bool _WGL_ARB_create_context;
    bool _WGL_ARB_create_context_profile;
    bool _WGL_ARB_create_context_robustness;
    bool _WGL_ARB_framebuffer_sRGB;
    bool _WGL_ARB_make_current_read;
    bool _WGL_ARB_multisample;
    bool _WGL_ARB_pbuffer;
    bool _WGL_ARB_pixel_format;
    bool _WGL_ARB_pixel_format_float;
    bool _WGL_ARB_render_texture;
    bool _WGL_ARB_robustness_application_isolation;
    bool _WGL_ARB_robustness_share_group_isolation;

    bool _WGL_EXT_swap_control;
}

enum
{
    // WGL_ARB_buffer_region
    WGL_FRONT_COLOR_BUFFER_BIT_ARB = 0x00000001,
    WGL_BACK_COLOR_BUFFER_BIT_ARB = 0x00000002,
    WGL_DEPTH_BUFFER_BIT_ARB = 0x00000004,
    WGL_STENCIL_BUFFER_BIT_ARB = 0x00000008,

    // WGL_ARB_create_context
    WGL_CONTEXT_DEBUG_BIT_ARB = 0x0001,
    WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x0002,
    WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091,
    WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092,
    WGL_CONTEXT_LAYER_PLANE_ARB = 0x2093,
    WGL_CONTEXT_FLAGS_ARB = 0x2094,
    ERROR_INVALID_VERSION_ARB = 0x2095,

    // WGL_ARB_create_context_profile
    WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126,
    WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001,
    WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002,
    ERROR_INVALID_PROFILE_ARB = 0x2096,

    // WGL_ARB_create_context_robustness
    WGL_CONTEXT_ROBUST_ACCESS_BIT_ARB = 0x00000004,
    WGL_LOSE_CONTEXT_ON_RESET_ARB = 0x8252,
    WGL_CONTEXT_RESET_NOTIFICATION_STRATEGY_ARB = 0x8256,
    WGL_NO_RESET_NOTIFICATION_ARB = 0x8261,

    // WGL_ARB_framebuffer_sRGB
    WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB = 0x20A9,

    // WGL_ARB_make_current_read
    ERROR_INVALID_PIXEL_TYPE_ARB = 0x2043,
    ERROR_INCOMPATIBLE_DEVICE_CONTEXTS_ARB = 0x2054,

    // WGL_ARB_multisample
    WGL_SAMPLE_BUFFERS_ARB = 0x2041,
    WGL_SAMPLES_ARB = 0x2042,

    // WGL_ARB_pbuffer
    WGL_DRAW_TO_PBUFFER_ARB = 0x202D,
    WGL_MAX_PBUFFER_PIXELS_ARB = 0x202E,
    WGL_MAX_PBUFFER_WIDTH_ARB = 0x202F,
    WGL_MAX_PBUFFER_HEIGHT_ARB = 0x2030,
    WGL_PBUFFER_LARGEST_ARB = 0x2033,
    WGL_PBUFFER_WIDTH_ARB = 0x2034,
    WGL_PBUFFER_HEIGHT_ARB = 0x2035,
    WGL_PBUFFER_LOST_ARB = 0x2036,

    // WGL_ARB_pixel_format
    WGL_NUMBER_PIXEL_FORMATS_ARB = 0x2000,
    WGL_DRAW_TO_WINDOW_ARB = 0x2001,
    WGL_DRAW_TO_BITMAP_ARB = 0x2002,
    WGL_ACCELERATION_ARB = 0x2003,
    WGL_NEED_PALETTE_ARB = 0x2004,
    WGL_NEED_SYSTEM_PALETTE_ARB = 0x2005,
    WGL_SWAP_LAYER_BUFFERS_ARB = 0x2006,
    WGL_SWAP_METHOD_ARB = 0x2007,
    WGL_NUMBER_OVERLAYS_ARB = 0x2008,
    WGL_NUMBER_UNDERLAYS_ARB = 0x2009,
    WGL_TRANSPARENT_ARB = 0x200A,
    WGL_TRANSPARENT_RED_VALUE_ARB = 0x2037,
    WGL_TRANSPARENT_GREEN_VALUE_ARB = 0x2038,
    WGL_TRANSPARENT_BLUE_VALUE_ARB = 0x2039,
    WGL_TRANSPARENT_ALPHA_VALUE_ARB = 0x203A,
    WGL_TRANSPARENT_INDEX_VALUE_ARB = 0x203B,
    WGL_SHARE_DEPTH_ARB = 0x200C,
    WGL_SHARE_STENCIL_ARB = 0x200D,
    WGL_SHARE_ACCUM_ARB = 0x200E,
    WGL_SUPPORT_GDI_ARB = 0x200F,
    WGL_SUPPORT_OPENGL_ARB = 0x2010,
    WGL_DOUBLE_BUFFER_ARB = 0x2011,
    WGL_STEREO_ARB = 0x2012,
    WGL_PIXEL_TYPE_ARB = 0x2013,
    WGL_COLOR_BITS_ARB = 0x2014,
    WGL_RED_BITS_ARB = 0x2015,
    WGL_RED_SHIFT_ARB = 0x2016,
    WGL_GREEN_BITS_ARB = 0x2017,
    WGL_GREEN_SHIFT_ARB = 0x2018,
    WGL_BLUE_BITS_ARB = 0x2019,
    WGL_BLUE_SHIFT_ARB = 0x201A,
    WGL_ALPHA_BITS_ARB = 0x201B,
    WGL_ALPHA_SHIFT_ARB = 0x201C,
    WGL_ACCUM_BITS_ARB = 0x201D,
    WGL_ACCUM_RED_BITS_ARB = 0x201E,
    WGL_ACCUM_GREEN_BITS_ARB = 0x201F,
    WGL_ACCUM_BLUE_BITS_ARB = 0x2020,
    WGL_ACCUM_ALPHA_BITS_ARB = 0x2021,
    WGL_DEPTH_BITS_ARB = 0x2022,
    WGL_STENCIL_BITS_ARB = 0x2023,
    WGL_AUX_BUFFERS_ARB = 0x2024,
    WGL_NO_ACCELERATION_ARB = 0x2025,
    WGL_GENERIC_ACCELERATION_ARB = 0x2026,
    WGL_FULL_ACCELERATION_ARB = 0x2027,
    WGL_SWAP_EXCHANGE_ARB = 0x2028,
    WGL_SWAP_COPY_ARB = 0x2029,
    WGL_SWAP_UNDEFINED_ARB = 0x202A,
    WGL_TYPE_RGBA_ARB = 0x202B,
    WGL_TYPE_COLORINDEX_ARB = 0x202C,

    // WGL_ARB_pixel_format_float
    WGL_TYPE_RGBA_FLOAT_ARB = 0x21A0,

    // WGL_ARB_render_texture
    WGL_BIND_TO_TEXTURE_RGB_ARB = 0x2070,
    WGL_BIND_TO_TEXTURE_RGBA_ARB = 0x2071,
    WGL_TEXTURE_FORMAT_ARB = 0x2072,
    WGL_TEXTURE_TARGET_ARB = 0x2073,
    WGL_MIPMAP_TEXTURE_ARB = 0x2074,
    WGL_TEXTURE_RGB_ARB = 0x2075,
    WGL_TEXTURE_RGBA_ARB = 0x2076,
    WGL_NO_TEXTURE_ARB = 0x2077,
    WGL_TEXTURE_CUBE_MAP_ARB = 0x2078,
    WGL_TEXTURE_1D_ARB = 0x2079,
    WGL_TEXTURE_2D_ARB = 0x207A,
    WGL_MIPMAP_LEVEL_ARB = 0x207B,
    WGL_CUBE_MAP_FACE_ARB = 0x207C,
    WGL_TEXTURE_CUBE_MAP_POSITIVE_X_ARB = 0x207D,
    WGL_TEXTURE_CUBE_MAP_NEGATIVE_X_ARB = 0x207E,
    WGL_TEXTURE_CUBE_MAP_POSITIVE_Y_ARB = 0x207F,
    WGL_TEXTURE_CUBE_MAP_NEGATIVE_Y_ARB = 0x2080,
    WGL_TEXTURE_CUBE_MAP_POSITIVE_Z_ARB = 0x2081,
    WGL_TEXTURE_CUBE_MAP_NEGATIVE_Z_ARB = 0x2082,
    WGL_FRONT_LEFT_ARB = 0x2083,
    WGL_FRONT_RIGHT_ARB = 0x2084,
    WGL_BACK_LEFT_ARB = 0x2085,
    WGL_BACK_RIGHT_ARB = 0x2086,
    WGL_AUX0_ARB = 0x2087,
    WGL_AUX1_ARB = 0x2088,
    WGL_AUX2_ARB = 0x2089,
    WGL_AUX3_ARB = 0x208A,
    WGL_AUX4_ARB = 0x208B,
    WGL_AUX5_ARB = 0x208C,
    WGL_AUX6_ARB = 0x208D,
    WGL_AUX7_ARB = 0x208E,
    WGL_AUX8_ARB = 0x208F,
    WGL_AUX9_ARB = 0x2090,
}
