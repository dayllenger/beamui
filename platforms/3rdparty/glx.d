/**
GLX (base + extensions) dynamic bindings, converted from Derelict to BindBC.

Requires x11 package.

Copyright: Michael D. Parker, dayllenger
License:   Boost License 1.0
*/
module glx;

version (Posix)  : import bindbc.loader.sharedlib;

private SharedLib lib;

bool hasLoadedGLX() {
        return lib != invalidHandle;
}

// no need to unload, because OpenGL bindings handle it

/// Load basic GLX functions, without extensions
bool loadGLX() {
        const(char)[][2] libNames = ["libGL.so.1", "libGL.so"];

        foreach (name; libNames) {
                lib = load(name.ptr);
                if (lib != invalidHandle)
                        break;
        }
        if (lib == invalidHandle)
                return false;

        const errCount = errorCount();

        bindSymbol(lib, cast(void**)&glXChooseVisual, "glXChooseVisual");
        bindSymbol(lib, cast(void**)&glXCopyContext, "glXCopyContext");
        bindSymbol(lib, cast(void**)&glXCreateContext, "glXCreateContext");
        bindSymbol(lib, cast(void**)&glXCreateGLXPixmap, "glXCreateGLXPixmap");
        bindSymbol(lib, cast(void**)&glXDestroyContext, "glXDestroyContext");
        bindSymbol(lib, cast(void**)&glXDestroyGLXPixmap, "glXDestroyGLXPixmap");
        bindSymbol(lib, cast(void**)&glXGetConfig, "glXGetConfig");
        bindSymbol(lib, cast(void**)&glXGetCurrentContext, "glXGetCurrentContext");
        bindSymbol(lib, cast(void**)&glXGetCurrentDrawable, "glXGetCurrentDrawable");
        bindSymbol(lib, cast(void**)&glXIsDirect, "glXIsDirect");
        bindSymbol(lib, cast(void**)&glXMakeCurrent, "glXMakeCurrent");
        bindSymbol(lib, cast(void**)&glXQueryExtension, "glXQueryExtension");
        bindSymbol(lib, cast(void**)&glXQueryVersion, "glXQueryVersion");
        bindSymbol(lib, cast(void**)&glXSwapBuffers, "glXSwapBuffers");
        bindSymbol(lib, cast(void**)&glXUseXFont, "glXUseXFont");
        bindSymbol(lib, cast(void**)&glXWaitGL, "glXWaitGL");
        bindSymbol(lib, cast(void**)&glXWaitX, "glXWaitX");
        bindSymbol(lib, cast(void**)&glXGetClientString, "glXGetClientString");
        bindSymbol(lib, cast(void**)&glXQueryServerString, "glXQueryServerString");
        bindSymbol(lib, cast(void**)&glXQueryExtensionsString, "glXQueryExtensionsString");

        bindSymbol(lib, cast(void**)&glXGetFBConfigs, "glXGetFBConfigs");
        bindSymbol(lib, cast(void**)&glXChooseFBConfig, "glXChooseFBConfig");
        bindSymbol(lib, cast(void**)&glXGetFBConfigAttrib, "glXGetFBConfigAttrib");
        bindSymbol(lib, cast(void**)&glXGetVisualFromFBConfig, "glXGetVisualFromFBConfig");
        bindSymbol(lib, cast(void**)&glXCreateWindow, "glXCreateWindow");
        bindSymbol(lib, cast(void**)&glXDestroyWindow, "glXDestroyWindow");
        bindSymbol(lib, cast(void**)&glXCreatePixmap, "glXCreatePixmap");
        bindSymbol(lib, cast(void**)&glXDestroyPixmap, "glXDestroyPixmap");
        bindSymbol(lib, cast(void**)&glXCreatePbuffer, "glXCreatePbuffer");
        bindSymbol(lib, cast(void**)&glXDestroyPbuffer, "glXDestroyPbuffer");
        bindSymbol(lib, cast(void**)&glXQueryDrawable, "glXQueryDrawable");
        bindSymbol(lib, cast(void**)&glXCreateNewContext, "glXCreateNewContext");
        bindSymbol(lib, cast(void**)&glXMakeContextCurrent, "glXMakeContextCurrent");
        bindSymbol(lib, cast(void**)&glXGetCurrentReadDrawable, "glXGetCurrentReadDrawable");
        bindSymbol(lib, cast(void**)&glXGetCurrentDisplay, "glXGetCurrentDisplay");
        bindSymbol(lib, cast(void**)&glXQueryContext, "glXQueryContext");
        bindSymbol(lib, cast(void**)&glXSelectEvent, "glXSelectEvent");
        bindSymbol(lib, cast(void**)&glXGetSelectedEvent, "glXGetSelectedEvent");

        bindSymbol(lib, cast(void**)&glXGetProcAddress, "glXGetProcAddressARB");

        return errorCount() == errCount;
}

void loadGLXExtensions(Display* display) {
        const char* extensions = glXQueryExtensionsString(display, DefaultScreen(display));
        if (!extensions)
                return;

        if (hasExtension(extensions, "GLX_ARB_create_context")) {
                _GLX_ARB_create_context =
                        bindGLXFunc(cast(void**)&glXCreateContextAttribsARB, "glXCreateContextAttribsARB");
        }
        if (hasExtension(extensions, "GLX_ARB_get_proc_address")) {
                _GLX_ARB_get_proc_address =
                        bindGLXFunc(cast(void**)&glXGetProcAddressARB, "glXGetProcAddressARB");
        }
        if (hasExtension(extensions, "GLX_EXT_import_context")) {
                _GLX_EXT_import_context =
                        bindGLXFunc(cast(void**)&glXGetCurrentDisplayEXT, "glXGetCurrentDisplayEXT") &&
                        bindGLXFunc(cast(void**)&glXQueryContextInfoEXT, "glXQueryContextInfoEXT") &&
                        bindGLXFunc(cast(void**)&glXGetContextIDEXT, "glXGetContextIDEXT") &&
                        bindGLXFunc(cast(void**)&glXImportContextEXT, "glXImportContextEXT") &&
                        bindGLXFunc(cast(void**)&glXFreeContextEXT, "glXFreeContextEXT");
        }
        if (hasExtension(extensions, "GLX_EXT_swap_control")) {
                _GLX_EXT_swap_control =
                        bindGLXFunc(cast(void**)&glXSwapIntervalEXT, "glXSwapIntervalEXT");
        }
        if (hasExtension(extensions, "GLX_EXT_texture_from_pixmap")) {
                _GLX_EXT_texture_from_pixmap =
                        bindGLXFunc(cast(void**)&glXBindTexImageEXT, "glXBindTexImageEXT") &&
                        bindGLXFunc(cast(void**)&glXReleaseTexImageEXT, "glXReleaseTexImageEXT");
        }
        if (hasExtension(extensions, "GLX_MESA_agp_offset")) {
                _GLX_MESA_agp_offset =
                        bindGLXFunc(cast(void**)&glXGetAGPOffsetMESA, "glXGetAGPOffsetMESA");
        }
        if (hasExtension(extensions, "GLX_MESA_swap_control")) {
                _GLX_MESA_swap_control =
                        bindGLXFunc(cast(void**)&glXSwapIntervalMESA, "glXSwapIntervalMESA");
        }
        if (hasExtension(extensions, "GLX_MESA_pixmap_colormap")) {
                _GLX_MESA_pixmap_colormap =
                        bindGLXFunc(cast(void**)&glXCreateGLXPixmapMESA, "glXCreateGLXPixmapMESA");
        }
        if (hasExtension(extensions, "GLX_MESA_release_buffers")) {
                _GLX_MESA_release_buffers =
                        bindGLXFunc(cast(void**)&glXReleaseBuffersMESA, "glXReleaseBuffersMESA");
        }
        if (hasExtension(extensions, "GLX_MESA_set_3dfx_mode")) {
                _GLX_MESA_set_3dfx_mode =
                        bindGLXFunc(cast(void**)&glXSet3DfxModeMESA, "glXSet3DfxModeMESA");
        }
        if (hasExtension(extensions, "GLX_NV_copy_image")) {
                _GLX_NV_copy_image =
                        bindGLXFunc(cast(void**)&glXCopyImageSubDataNV, "glXCopyImageSubDataNV");
        }
        if (hasExtension(extensions, "GLX_NV_present_video")) {
                _GLX_NV_present_video =
                        bindGLXFunc(cast(void**)&glXEnumerateVideoDevicesNV, "glXEnumerateVideoDevicesNV") &&
                        bindGLXFunc(cast(void**)&glXBindVideoDeviceNV, "glXBindVideoDeviceNV");
        }
        if (hasExtension(extensions, "GLX_NV_swap_group")) {
                _GLX_NV_swap_group =
                        bindGLXFunc(cast(void**)&glXJoinSwapGroupNV, "glXJoinSwapGroupNV") &&
                        bindGLXFunc(cast(void**)&glXBindSwapBarrierNV, "glXBindSwapBarrierNV") &&
                        bindGLXFunc(cast(void**)&glXQuerySwapGroupNV, "glXQuerySwapGroupNV") &&
                        bindGLXFunc(cast(void**)&glXQueryMaxSwapGroupsNV, "glXQueryMaxSwapGroupsNV") &&
                        bindGLXFunc(cast(void**)&glXQueryFrameCountNV, "glXQueryFrameCountNV") &&
                        bindGLXFunc(cast(void**)&glXResetFrameCountNV, "glXResetFrameCountNV");
        }
        if (hasExtension(extensions, "GLX_NV_video_capture")) {
                _GLX_NV_video_capture =
                        bindGLXFunc(cast(void**)&glXBindVideoCaptureDeviceNV, "glXBindVideoCaptureDeviceNV") &&
                        bindGLXFunc(cast(void**)&glXEnumerateVideoCaptureDevicesNV, "glXEnumerateVideoCaptureDevicesNV") &&
                        bindGLXFunc(cast(void**)&glXLockVideoCaptureDeviceNV, "glXLockVideoCaptureDeviceNV") &&
                        bindGLXFunc(cast(void**)&glXQueryVideoCaptureDeviceNV, "glXQueryVideoCaptureDeviceNV") &&
                        bindGLXFunc(
                                cast(void**)&glXReleaseVideoCaptureDeviceNV, "glXReleaseVideoCaptureDeviceNV");
        }
        if (hasExtension(extensions, "GLX_NV_video_output")) {
                _GLX_NV_video_output =
                        bindGLXFunc(cast(void**)&glXGetVideoDeviceNV, "glXGetVideoDeviceNV") &&
                        bindGLXFunc(cast(void**)&glXReleaseVideoDeviceNV, "glXReleaseVideoDeviceNV") &&
                        bindGLXFunc(cast(void**)&glXBindVideoImageNV, "glXBindVideoImageNV") &&
                        bindGLXFunc(cast(void**)&glXReleaseVideoImageNV, "glXReleaseVideoImageNV") &&
                        bindGLXFunc(cast(void**)&glXSendPbufferToVideoNV, "glXSendPbufferToVideoNV") &&
                        bindGLXFunc(cast(void**)&glXGetVideoInfoNV, "glXGetVideoInfoNV");
        }
        if (hasExtension(extensions, "GLX_OML_sync_control")) {
                _GLX_OML_sync_control =
                        bindGLXFunc(cast(void**)&glXGetSyncValuesOML, "glXGetSyncValuesOML") &&
                        bindGLXFunc(cast(void**)&glXGetMscRateOML, "glXGetMscRateOML") &&
                        bindGLXFunc(cast(void**)&glXSwapBuffersMscOML, "glXSwapBuffersMscOML") &&
                        bindGLXFunc(cast(void**)&glXWaitForMscOML, "glXWaitForMscOML") &&
                        bindGLXFunc(cast(void**)&glXWaitForSbcOML, "glXWaitForSbcOML");
        }
        if (hasExtension(extensions, "GLX_SGIX_fbconfig")) {
                _GLX_SGIX_fbconfig =
                        bindGLXFunc(cast(void**)&glXGetFBConfigAttribSGIX, "glXGetFBConfigAttribSGIX") &&
                        bindGLXFunc(cast(void**)&glXChooseFBConfigSGIX, "glXChooseFBConfigSGIX") &&
                        bindGLXFunc(cast(void**)&glXCreateGLXPixmapWithConfigSGIX, "glXCreateGLXPixmapWithConfigSGIX") &&
                        bindGLXFunc(cast(void**)&glXCreateContextWithConfigSGIX, "glXCreateContextWithConfigSGIX") &&
                        bindGLXFunc(cast(void**)&glXGetVisualFromFBConfigSGIX, "glXGetVisualFromFBConfigSGIX") &&
                        bindGLXFunc(
                                cast(void**)&glXGetFBConfigFromVisualSGIX, "glXGetFBConfigFromVisualSGIX");
        }
        if (hasExtension(extensions, "GLX_SGIX_hyperpipe")) {
                _GLX_SGIX_hyperpipe =
                        bindGLXFunc(cast(void**)&glXQueryHyperpipeNetworkS, "glXQueryHyperpipeNetworkS") &&
                        bindGLXFunc(cast(void**)&glXHyperpipeConfigSGIX, "glXHyperpipeConfigSGIX") &&
                        bindGLXFunc(cast(void**)&glXQueryHyperpipeConfigSGIX, "glXQueryHyperpipeConfigSGIX") &&
                        bindGLXFunc(cast(void**)&glXDestroyHyperpipeConfigSGIX, "glXDestroyHyperpipeConfigSGIX") &&
                        bindGLXFunc(cast(void**)&glXBindHyperpipeSGIX, "glXBindHyperpipeSGIX") &&
                        bindGLXFunc(cast(void**)&glXQueryHyperpipeBestAttribSGIX, "glXQueryHyperpipeBestAttribSGIX") &&
                        bindGLXFunc(cast(void**)&glXHyperpipeAttribSGIX, "glXHyperpipeAttribSGIX") &&
                        bindGLXFunc(cast(void**)&glXQueryHyperpipeAttribSGIX, "glXQueryHyperpipeAttribSGIX");
        }
        if (hasExtension(extensions, "GLX_SGIX_pbuffer")) {
                _GLX_SGIX_pbuffer =
                        bindGLXFunc(cast(void**)&glXCreateGLXPbufferSGIX, "glXCreateGLXPbufferSGIX") &&
                        bindGLXFunc(cast(void**)&glXDestroyGLXPbufferSGIX, "glXDestroyGLXPbufferSGIX") &&
                        bindGLXFunc(cast(void**)&glXQueryGLXPbufferSGIX, "glXQueryGLXPbufferSGIX") &&
                        bindGLXFunc(cast(void**)&glXSelectEventSGIX, "glXSelectEventSGIX") &&
                        bindGLXFunc(cast(void**)&glXGetSelectedEventSGIX, "glXGetSelectedEventSGIX");
        }
        if (hasExtension(extensions, "GLX_SGIX_swap_barrier")) {
                _GLX_SGIX_swap_barrier =
                        bindGLXFunc(cast(void**)&glXBindSwapBarrierSGIX, "glXBindSwapBarrierSGIX") &&
                        bindGLXFunc(cast(void**)&glXQueryMaxSwapBarriersSGIX, "glXQueryMaxSwapBarriersSGIX");
        }
        if (hasExtension(extensions, "GLX_SGIX_swap_group")) {
                _GLX_SGIX_swap_group =
                        bindGLXFunc(cast(void**)&glXJoinSwapGroupSGIX, "glXJoinSwapGroupSGIX");
        }
        if (hasExtension(extensions, "GLX_SGIX_video_source")) {
                _GLX_SGIX_video_source =
                        bindGLXFunc(cast(void**)&glXBindChannelToWindowSGIX, "glXBindChannelToWindowSGIX") &&
                        bindGLXFunc(cast(void**)&glXChannelRectSGIX, "glXChannelRectSGIX") &&
                        bindGLXFunc(cast(void**)&glXQueryChannelRectSGIX, "glXQueryChannelRectSGIX") &&
                        bindGLXFunc(cast(void**)&glXQueryChannelDeltasSGIX, "glXQueryChannelDeltasSGIX") &&
                        bindGLXFunc(cast(void**)&glXChannelRectSyncSGIX, "glXChannelRectSyncSGIX");
        }
        if (hasExtension(extensions, "GLX_SGI_cushion")) {
                _GLX_SGI_cushion =
                        bindGLXFunc(cast(void**)&glXCushionSGI, "glXCushionSGI");
        }
        if (hasExtension(extensions, "GLX_SGI_swap_control")) {
                _GLX_SGI_swap_control =
                        bindGLXFunc(cast(void**)&glXSwapIntervalSGI, "glXSwapIntervalSGI");
        }
        if (hasExtension(extensions, "GLX_SGI_video_sync")) {
                _GLX_SGI_video_sync =
                        bindGLXFunc(cast(void**)&glXGetVideoSyncSGI, "glXGetVideoSyncSGI") &&
                        bindGLXFunc(cast(void**)&glXWaitVideoSyncSGI, "glXWaitVideoSyncSGI");
        }
        if (hasExtension(extensions, "GLX_SUN_get_transparent_index")) {
                _GLX_SUN_get_transparent_index =
                        bindGLXFunc(cast(void**)&glXGetTransparentIndexSUN, "glXGetTransparentIndexSUN");
        }
}

private bool bindGLXFunc(void** ptr, const(char)* name) {
        if (auto sym = glXGetProcAddress(name)) {
                *ptr = cast(void*)sym;
                return true;
        }
        return false;
}

private bool hasExtension(const(char)* extensions, const(char)* name) {
        import core.stdc.string : strlen, strstr;

        const len = strlen(name);
        const(char)* ext = strstr(extensions, name);
        while (ext) {
                // It's possible that the extension name is actually a
                // substring of another extension. If not, then the
                // character following the name in the extension string
                // should be a space (or possibly the null character).
                if (ext[len] == ' ' || ext[len] == '\0')
                        return true;
                ext = strstr(ext + len, name);
        }
        return false;
}

//===============================================================

import core.stdc.config : c_ulong;
import x11.X : Colormap, Font, Pixmap, VisualID, Window, XID;
import x11.Xlib : Bool, Display, Status, Visual, XExtData, XPointer, DefaultScreen;
import x11.Xutil : XVisualInfo;

private {
        alias GLenum = uint;
        alias GLboolean = ubyte;
        alias GLint = int;
        alias GLsizei = int;
        alias GLubyte = ubyte;
        alias GLuint = uint;
}

struct __GLXcontextRec;
struct __GLXFBConfigRec;

alias GLXContentID = uint;
alias GLXPixmap = uint;
alias GLXDrawable = uint;
alias GLXPbuffer = uint;
alias GLXWindow = uint;
alias GLXFBConfigID = uint;

alias GLXContext = __GLXcontextRec*;
alias GLXFBConfig = __GLXFBConfigRec*;
alias GLXFBConfigSGIX = __GLXFBConfigRec*;

alias int64_t = long;
alias uint64_t = ulong;
alias int32_t = int;
alias GLXContextID = XID;
alias GLXVideoCaptureDeviceNV = XID;
alias GLXPbufferSGIX = XID;
alias GLXVideoDeviceNV = uint;

struct GLXPbufferClobberEvent {
        int event_type;
        int draw_type;
        uint serial;
        Bool send_event;
        Display* display;
        GLXDrawable drawable;
        uint buffer_mask;
        uint aux_buffer;
        int x, y;
        int width, height;
        int count;
}

union GLXEvent {
        GLXPbufferClobberEvent glxpbufferclobber;
        int[24] pad;
}

extern (C) @nogc nothrow {
        alias p_ChooseVisual = XVisualInfo* function(Display*, int, int*);
        alias p_CopyContext = void function(Display*, GLXContext, GLXContext, uint);
        alias p_CreateContext = GLXContext function(Display*, XVisualInfo*, GLXContext, Bool);
        alias p_CreateGLXPixmap = GLXPixmap function(Display*, XVisualInfo*, Pixmap);
        alias p_DestroyContext = void function(Display*, GLXContext);
        alias p_DestroyGLXPixmap = void function(Display*, GLXPixmap);
        alias p_GetConfig = int function(Display*, XVisualInfo*, int, int*);
        alias p_GetCurrentContext = GLXContext function();
        alias p_GetCurrentDrawable = GLXDrawable function();
        alias p_IsDirect = Bool function(Display*, GLXContext);
        alias p_MakeCurrent = Bool function(Display*, GLXDrawable, GLXContext);
        alias p_QueryExtension = Bool function(Display*, int*, int*);
        alias p_QueryVersion = Bool function(Display*, int*, int*);
        alias p_SwapBuffers = void function(Display*, GLXDrawable);
        alias p_UseXFont = void function(Font, int, int, int);
        alias p_WaitGL = void function();
        alias p_WaitX = void function();
        alias p_GetClientString = char* function(Display*, int);
        alias p_QueryServerString = char* function(Display*, int, int);
        alias p_QueryExtensionsString = char* function(Display*, int);

        // GLX 1.3
        alias p_GetFBConfigs = GLXFBConfig* function(Display*, int, int*);
        alias p_ChooseFBConfig = GLXFBConfig* function(Display*, int, int*, int*);
        alias p_GetFBConfigAttrib = int function(Display*, GLXFBConfig, int, int*);
        alias p_GetVisualFromFBConfig = XVisualInfo* function(Display*, GLXFBConfig);
        alias p_CreateWindow = GLXWindow function(Display*, GLXFBConfig, Window, int*);
        alias p_DestroyWindow = void function(Display*, GLXWindow);
        alias p_CreatePixmap = GLXPixmap function(Display*, GLXFBConfig, Pixmap, int*);
        alias p_DestroyPixmap = void function(Display*, GLXPixmap);
        alias p_CreatePbuffer = GLXPbuffer function(Display*, GLXFBConfig, int*);
        alias p_DestroyPbuffer = void function(Display*, GLXPbuffer);
        alias p_QueryDrawable = void function(Display*, GLXDrawable, int, uint*);
        alias p_CreateNewContext = GLXContext function(Display*, GLXFBConfig,
                int, GLXContext, Bool);
        alias p_MakeContextCurrent = Bool function(Display*, GLXDrawable, GLXDrawable, GLXContext);
        alias p_GetCurrentReadDrawable = GLXDrawable function();
        alias p_GetCurrentDisplay = Display* function();
        alias p_QueryContext = int function(Display*, GLXContext, int, int*);
        alias p_SelectEvent = void function(Display*, GLXDrawable, uint);
        alias p_GetSelectedEvent = void function(Display*, GLXDrawable, uint*);

        // GLX 1.4+
        alias p_GetProcAddress = void* function(const(char)*);

        // function types
        alias __GLXextFuncPtr = void function();

        // GLX_ARB_create_context
        alias p_CreateContextAttribsARB = GLXContext function(Display* dpy, GLXFBConfig config,
                GLXContext share_context, Bool direct, const int* attrib_list);

        // GLX_ARB_get_proc_address
        alias p_GetProcAddressARB = __GLXextFuncPtr function(const GLubyte* procName);

        // GLX_EXT_import_context
        alias p_GetCurrentDisplayEXT = Display* function();
        alias p_QueryContextInfoEXT = int function(Display* dpy, GLXContext context,
                int attribute, int* value);
        alias p_GetContextIDEXT = GLXContextID function(const GLXContext context);
        alias p_ImportContextEXT = GLXContext function(Display* dpy, GLXContextID contextID);
        alias p_FreeContextEXT = void function(Display* dpy, GLXContext context);

        // GLX_EXT_swap_control
        alias p_SwapIntervalEXT = void function(Display* dpy, GLXDrawable drawable, int interval);

        // GLX_EXT_texture_from_pixmap
        alias p_BindTexImageEXT = void function(Display* dpy, GLXDrawable drawable, int buffer,
                const int* attrib_list);
        alias p_ReleaseTexImageEXT = void function(Display* dpy, GLXDrawable drawable, int buffer);

        // GLX_MESA_agp_offset
        alias p_GetAGPOffsetMESA = uint function(const void* pointer);

        // GLX_MESA_swap_control
        alias p_SwapIntervalMESA = int function(uint interval);

        // GLX_MESA_pixmap_colormap
        alias p_CreateGLXPixmapMESA = GLXPixmap function(Display* dpy,
                XVisualInfo* visual, Pixmap pixmap, Colormap cmap);

        // GLX_MESA_release_buffers
        alias p_ReleaseBuffersMESA = Bool function(Display* dpy, GLXDrawable drawable);

        // GLX_MESA_set_3dfx_mode
        alias p_Set3DfxModeMESA = Bool function(int mode);

        // GLX_NV_copy_image
        alias p_CopyImageSubDataNV = void function(Display* dpy, GLXContext srcCtx, GLuint srcName, GLenum srcTarget,
                GLint srcLevel, GLint srcX, GLint srcY, GLint srcZ, GLXContext dstCtx, GLuint dstName,
                GLenum dstTarget, GLint dstLevel, GLint dstX, GLint dstY, GLint dstZ,
                GLsizei width, GLsizei height, GLsizei depth);

        // GLX_NV_present_video
        alias p_EnumerateVideoDevicesNV = uint* function(Display* dpy, int screen, int* nelements);
        alias p_BindVideoDeviceNV = int function(Display* dpy, uint video_slot,
                uint video_device, const int* attrib_list);

        // GLX_NV_swap_group
        alias p_JoinSwapGroupNV = Bool function(Display* dpy, GLXDrawable drawable, GLuint group);
        alias p_BindSwapBarrierNV = Bool function(Display* dpy, GLuint group, GLuint barrier);
        alias p_QuerySwapGroupNV = Bool function(Display* dpy,
                GLXDrawable drawable, GLuint* group, GLuint* barrier);
        alias p_QueryMaxSwapGroupsNV = Bool function(Display* dpy, int screen,
                GLuint* maxGroups, GLuint* maxBarriers);
        alias p_QueryFrameCountNV = Bool function(Display* dpy, int screen, GLuint* count);
        alias p_ResetFrameCountNV = Bool function(Display* dpy, int screen);

        // GLX_NV_video_capture
        alias p_BindVideoCaptureDeviceNV = int function(Display* dpy,
                uint video_capture_slot, GLXVideoCaptureDeviceNV device);
        alias p_EnumerateVideoCaptureDevicesNV = GLXVideoCaptureDeviceNV* function(
                Display* dpy, int screen, int* nelements);
        alias p_LockVideoCaptureDeviceNV = void function(Display* dpy,
                GLXVideoCaptureDeviceNV device);
        alias p_QueryVideoCaptureDeviceNV = int function(Display* dpy,
                GLXVideoCaptureDeviceNV device, int attribute, int* value);
        alias p_ReleaseVideoCaptureDeviceNV = void function(Display* dpy,
                GLXVideoCaptureDeviceNV device);

        // GLX_NV_video_output
        alias p_GetVideoDeviceNV = int function(Display* dpy, int screen,
                int numVideoDevices, GLXVideoDeviceNV* pVideoDevice);
        alias p_ReleaseVideoDeviceNV = int function(Display* dpy, int screen,
                GLXVideoDeviceNV VideoDevice);
        alias p_BindVideoImageNV = int function(Display* dpy,
                GLXVideoDeviceNV VideoDevice, GLXPbuffer pbuf, int iVideoBuffer);
        alias p_ReleaseVideoImageNV = int function(Display* dpy, GLXPbuffer pbuf);
        alias p_SendPbufferToVideoNV = int function(Display* dpy,
                GLXPbuffer pbuf, int iBufferType, ulong* pulCounterPbuffer, GLboolean bBlock);
        alias p_GetVideoInfoNV = int function(Display* dpy, int screen,
                GLXVideoDeviceNV VideoDevice, ulong* pulCounterOutputPbuffer,
                ulong* pulCounterOutputVideo);

        // GLX_OML_sync_control
        alias p_GetSyncValuesOML = Bool function(Display* dpy,
                GLXDrawable drawable, int64_t* ust, int64_t* msc, int64_t* sbc);
        alias p_GetMscRateOML = Bool function(Display* dpy,
                GLXDrawable drawable, int32_t* numerator, int32_t* denominator);
        alias p_SwapBuffersMscOML = int64_t function(Display* dpy,
                GLXDrawable drawable, int64_t target_msc, int64_t divisor, int64_t remainder);
        alias p_WaitForMscOML = Bool function(Display* dpy, GLXDrawable drawable, int64_t target_msc,
                int64_t divisor, int64_t remainder, int64_t* ust, int64_t* msc, int64_t* sbc);
        alias p_WaitForSbcOML = Bool function(Display* dpy, GLXDrawable drawable,
                int64_t target_sbc, int64_t* ust, int64_t* msc, int64_t* sbc);

        // GLX_SGIX_fbconfig
        alias p_GetFBConfigAttribSGIX = int function(Display* dpy,
                GLXFBConfigSGIX config, int attribute, int* value);
        alias p_ChooseFBConfigSGIX = GLXFBConfigSGIX* function(Display* dpy,
                int screen, int* attrib_list, int* nelements);
        alias p_CreateGLXPixmapWithConfigSGIX = GLXPixmap function(Display* dpy,
                GLXFBConfigSGIX config, Pixmap pixmap);
        alias p_CreateContextWithConfigSGIX = GLXContext function(Display* dpy,
                GLXFBConfigSGIX config, int render_type, GLXContext share_list, Bool direct);
        alias p_GetVisualFromFBConfigSGIX = XVisualInfo* function(Display* dpy,
                GLXFBConfigSGIX config);
        alias p_GetFBConfigFromVisualSGIX = GLXFBConfigSGIX function(Display* dpy, XVisualInfo* vis);

        // GLX_SGIX_hyperpipe
        alias p_QueryHyperpipeNetworkS = GLXHyperpipeNetworkSGIX* function(Display* dpy,
                int* npipes);
        alias p_HyperpipeConfigSGIX = int function(Display* dpy, int networkId,
                int npipes, GLXHyperpipeConfigSGIX* cfg, int* hpId);
        alias p_QueryHyperpipeConfigSGIX = GLXHyperpipeConfigSGIX* function(
                Display* dpy, int hpId, int* npipes);
        alias p_DestroyHyperpipeConfigSGIX = int function(Display* dpy, int hpId);
        alias p_BindHyperpipeSGIX = int function(Display* dpy, int hpId);
        alias p_QueryHyperpipeBestAttribSGIX = int function(Display* dpy,
                int timeSlice, int attrib, int size, void* attribList, void* returnAttribList);
        alias p_HyperpipeAttribSGIX = int function(Display* dpy, int timeSlice,
                int attrib, int size, void* attribList);
        alias p_QueryHyperpipeAttribSGIX = int function(Display* dpy,
                int timeSlice, int attrib, int size, void* returnAttribList);

        // GLX_SGIX_pbuffer
        alias p_CreateGLXPbufferSGIX = GLXPbufferSGIX function(Display* dpy,
                GLXFBConfigSGIX config, uint width, uint height, int* attrib_list);
        alias p_DestroyGLXPbufferSGIX = void function(Display* dpy, GLXPbufferSGIX pbuf);
        alias p_QueryGLXPbufferSGIX = int function(Display* dpy,
                GLXPbufferSGIX pbuf, int attribute, uint* value);
        alias p_SelectEventSGIX = void function(Display* dpy, GLXDrawable drawable, ulong mask);
        alias p_GetSelectedEventSGIX = void function(Display* dpy, GLXDrawable drawable,
                ulong* mask);

        // GLX_SGIX_swap_barrier
        alias p_BindSwapBarrierSGIX = void function(Display* dpy, GLXDrawable drawable, int barrier);
        alias p_QueryMaxSwapBarriersSGIX = Bool function(Display* dpy, int screen, int* max);

        // GLX_SGIX_swap_group
        alias p_JoinSwapGroupSGIX = void function(Display* dpy,
                GLXDrawable drawable, GLXDrawable member);

        // GLX_SGIX_video_source
        alias p_BindChannelToWindowSGIX = int function(Display* display,
                int screen, int channel, Window window);
        alias p_ChannelRectSGIX = int function(Display* display, int screen,
                int channel, int x, int y, int w, int h);
        alias p_QueryChannelRectSGIX = int function(Display* display,
                int screen, int channel, int* dx, int* dy, int* dw, int* dh);
        alias p_QueryChannelDeltasSGIX = int function(Display* display,
                int screen, int channel, int* x, int* y, int* w, int* h);
        alias p_ChannelRectSyncSGIX = int function(Display* display, int screen,
                int channel, GLenum synctype);

        // GLX_SGI_cushion
        alias p_CushionSGI = void function(Display* dpy, Window window, float cushion);

        // GLX_SGI_swap_control
        alias p_SwapIntervalSGI = int function(int interval);

        // GLX_SGI_video_sync
        alias p_GetVideoSyncSGI = int function(uint* count);
        alias p_WaitVideoSyncSGI = int function(int divisor, int remainder, uint* count);

        // GLX_SUN_get_transparent_index
        alias p_GetTransparentIndexSUN = Status function(Display* dpy,
                Window overlay, Window underlay, long* pTransparentIndex);
}

__gshared {
        p_ChooseVisual glXChooseVisual;
        p_CopyContext glXCopyContext;
        p_CreateContext glXCreateContext;
        p_CreateGLXPixmap glXCreateGLXPixmap;
        p_DestroyContext glXDestroyContext;
        p_DestroyGLXPixmap glXDestroyGLXPixmap;
        p_GetConfig glXGetConfig;
        p_GetCurrentContext glXGetCurrentContext;
        p_GetCurrentDrawable glXGetCurrentDrawable;
        p_IsDirect glXIsDirect;
        p_MakeCurrent glXMakeCurrent;
        p_QueryExtension glXQueryExtension;
        p_QueryVersion glXQueryVersion;
        p_SwapBuffers glXSwapBuffers;
        p_UseXFont glXUseXFont;
        p_WaitGL glXWaitGL;
        p_WaitX glXWaitX;
        p_GetClientString glXGetClientString;
        p_QueryServerString glXQueryServerString;
        p_QueryExtensionsString glXQueryExtensionsString;

        // GLX 1.3
        p_GetFBConfigs glXGetFBConfigs;
        p_ChooseFBConfig glXChooseFBConfig;
        p_GetFBConfigAttrib glXGetFBConfigAttrib;
        p_GetVisualFromFBConfig glXGetVisualFromFBConfig;
        p_CreateWindow glXCreateWindow;
        p_DestroyWindow glXDestroyWindow;
        p_CreatePixmap glXCreatePixmap;
        p_DestroyPixmap glXDestroyPixmap;
        p_CreatePbuffer glXCreatePbuffer;
        p_DestroyPbuffer glXDestroyPbuffer;
        p_QueryDrawable glXQueryDrawable;
        p_CreateNewContext glXCreateNewContext;
        p_MakeContextCurrent glXMakeContextCurrent;
        p_GetCurrentReadDrawable glXGetCurrentReadDrawable;
        p_GetCurrentDisplay glXGetCurrentDisplay;
        p_QueryContext glXQueryContext;
        p_SelectEvent glXSelectEvent;
        p_GetSelectedEvent glXGetSelectedEvent;

        // GLX 1.4+
        p_GetProcAddress glXGetProcAddress;

        // GLX_ARB_create_context
        p_CreateContextAttribsARB glXCreateContextAttribsARB;

        // GLX_ARB_get_proc_address
        p_GetProcAddressARB glXGetProcAddressARB;

        // GLX_EXT_import_context
        p_GetCurrentDisplayEXT glXGetCurrentDisplayEXT;
        p_QueryContextInfoEXT glXQueryContextInfoEXT;
        p_GetContextIDEXT glXGetContextIDEXT;
        p_ImportContextEXT glXImportContextEXT;
        p_FreeContextEXT glXFreeContextEXT;

        // GLX_EXT_swap_control
        p_SwapIntervalEXT glXSwapIntervalEXT;

        // GLX_EXT_texture_from_pixmap
        p_BindTexImageEXT glXBindTexImageEXT;
        p_ReleaseTexImageEXT glXReleaseTexImageEXT;

        // GLX_MESA_agp_offset
        p_GetAGPOffsetMESA glXGetAGPOffsetMESA;

        // GLX_MESA_swap_control
        p_SwapIntervalMESA glXSwapIntervalMESA;

        // GLX_MESA_pixmap_colormap
        p_CreateGLXPixmapMESA glXCreateGLXPixmapMESA;

        // GLX_MESA_release_buffers
        p_ReleaseBuffersMESA glXReleaseBuffersMESA;

        // GLX_MESA_set_3dfx_mode
        p_Set3DfxModeMESA glXSet3DfxModeMESA;

        // GLX_NV_copy_image
        p_CopyImageSubDataNV glXCopyImageSubDataNV;

        // GLX_NV_present_video
        p_EnumerateVideoDevicesNV glXEnumerateVideoDevicesNV;
        p_BindVideoDeviceNV glXBindVideoDeviceNV;

        // GLX_NV_swap_group
        p_JoinSwapGroupNV glXJoinSwapGroupNV;
        p_BindSwapBarrierNV glXBindSwapBarrierNV;
        p_QuerySwapGroupNV glXQuerySwapGroupNV;
        p_QueryMaxSwapGroupsNV glXQueryMaxSwapGroupsNV;
        p_QueryFrameCountNV glXQueryFrameCountNV;
        p_ResetFrameCountNV glXResetFrameCountNV;

        // GLX_NV_video_capture
        p_BindVideoCaptureDeviceNV glXBindVideoCaptureDeviceNV;
        p_EnumerateVideoCaptureDevicesNV glXEnumerateVideoCaptureDevicesNV;
        p_LockVideoCaptureDeviceNV glXLockVideoCaptureDeviceNV;
        p_QueryVideoCaptureDeviceNV glXQueryVideoCaptureDeviceNV;
        p_ReleaseVideoCaptureDeviceNV glXReleaseVideoCaptureDeviceNV;

        // GLX_NV_video_output
        p_GetVideoDeviceNV glXGetVideoDeviceNV;
        p_ReleaseVideoDeviceNV glXReleaseVideoDeviceNV;
        p_BindVideoImageNV glXBindVideoImageNV;
        p_ReleaseVideoImageNV glXReleaseVideoImageNV;
        p_SendPbufferToVideoNV glXSendPbufferToVideoNV;
        p_GetVideoInfoNV glXGetVideoInfoNV;

        // GLX_OML_sync_control
        p_GetSyncValuesOML glXGetSyncValuesOML;
        p_GetMscRateOML glXGetMscRateOML;
        p_SwapBuffersMscOML glXSwapBuffersMscOML;
        p_WaitForMscOML glXWaitForMscOML;
        p_WaitForSbcOML glXWaitForSbcOML;

        // GLX_SGIX_fbconfig
        p_GetFBConfigAttribSGIX glXGetFBConfigAttribSGIX;
        p_ChooseFBConfigSGIX glXChooseFBConfigSGIX;
        p_CreateGLXPixmapWithConfigSGIX glXCreateGLXPixmapWithConfigSGIX;
        p_CreateContextWithConfigSGIX glXCreateContextWithConfigSGIX;
        p_GetVisualFromFBConfigSGIX glXGetVisualFromFBConfigSGIX;
        p_GetFBConfigFromVisualSGIX glXGetFBConfigFromVisualSGIX;

        // GLX_SGIX_hyperpipe
        p_QueryHyperpipeNetworkS glXQueryHyperpipeNetworkS;
        p_HyperpipeConfigSGIX glXHyperpipeConfigSGIX;
        p_QueryHyperpipeConfigSGIX glXQueryHyperpipeConfigSGIX;
        p_DestroyHyperpipeConfigSGIX glXDestroyHyperpipeConfigSGIX;
        p_BindHyperpipeSGIX glXBindHyperpipeSGIX;
        p_QueryHyperpipeBestAttribSGIX glXQueryHyperpipeBestAttribSGIX;
        p_HyperpipeAttribSGIX glXHyperpipeAttribSGIX;
        p_QueryHyperpipeAttribSGIX glXQueryHyperpipeAttribSGIX;

        // GLX_SGIX_pbuffer
        p_CreateGLXPbufferSGIX glXCreateGLXPbufferSGIX;
        p_DestroyGLXPbufferSGIX glXDestroyGLXPbufferSGIX;
        p_QueryGLXPbufferSGIX glXQueryGLXPbufferSGIX;
        p_SelectEventSGIX glXSelectEventSGIX;
        p_GetSelectedEventSGIX glXGetSelectedEventSGIX;

        // GLX_SGIX_swap_barrier
        p_BindSwapBarrierSGIX glXBindSwapBarrierSGIX;
        p_QueryMaxSwapBarriersSGIX glXQueryMaxSwapBarriersSGIX;

        // GLX_SGIX_swap_group
        p_JoinSwapGroupSGIX glXJoinSwapGroupSGIX;

        // GLX_SGIX_video_source
        p_BindChannelToWindowSGIX glXBindChannelToWindowSGIX;
        p_ChannelRectSGIX glXChannelRectSGIX;
        p_QueryChannelRectSGIX glXQueryChannelRectSGIX;
        p_QueryChannelDeltasSGIX glXQueryChannelDeltasSGIX;
        p_ChannelRectSyncSGIX glXChannelRectSyncSGIX;

        // GLX_SGI_cushion
        p_CushionSGI glXCushionSGI;

        // GLX_SGI_swap_control
        p_SwapIntervalSGI glXSwapIntervalSGI;

        // GLX_SGI_video_sync
        p_GetVideoSyncSGI glXGetVideoSyncSGI;
        p_WaitVideoSyncSGI glXWaitVideoSyncSGI;

        // GLX_SUN_get_transparent_index
        p_GetTransparentIndexSUN glXGetTransparentIndexSUN;
}

@nogc nothrow @property {
        bool GLX_ARB_create_context() {
                return _GLX_ARB_create_context;
        }

        bool GLX_ARB_get_proc_address() {
                return _GLX_ARB_get_proc_address;
        }

        bool GLX_EXT_import_context() {
                return _GLX_EXT_import_context;
        }

        bool GLX_EXT_swap_control() {
                return _GLX_EXT_swap_control;
        }

        bool GLX_EXT_texture_from_pixmap() {
                return _GLX_EXT_texture_from_pixmap;
        }

        bool GLX_MESA_agp_offset() {
                return _GLX_MESA_agp_offset;
        }

        bool GLX_MESA_swap_control() {
                return _GLX_MESA_swap_control;
        }

        bool GLX_MESA_pixmap_colormap() {
                return _GLX_MESA_pixmap_colormap;
        }

        bool GLX_MESA_release_buffers() {
                return _GLX_MESA_release_buffers;
        }

        bool GLX_MESA_set_3dfx_mode() {
                return _GLX_MESA_set_3dfx_mode;
        }

        bool GLX_NV_copy_image() {
                return _GLX_NV_copy_image;
        }

        bool GLX_NV_present_video() {
                return _GLX_NV_present_video;
        }

        bool GLX_NV_swap_group() {
                return _GLX_NV_swap_group;
        }

        bool GLX_NV_video_capture() {
                return _GLX_NV_video_capture;
        }

        bool GLX_NV_video_output() {
                return _GLX_NV_video_output;
        }

        bool GLX_OML_sync_control() {
                return _GLX_OML_sync_control;
        }

        bool GLX_SGIX_fbconfig() {
                return _GLX_SGIX_fbconfig;
        }

        bool GLX_SGIX_hyperpipe() {
                return _GLX_SGIX_hyperpipe;
        }

        bool GLX_SGIX_pbuffer() {
                return _GLX_SGIX_pbuffer;
        }

        bool GLX_SGIX_swap_barrier() {
                return _GLX_SGIX_swap_barrier;
        }

        bool GLX_SGIX_swap_group() {
                return _GLX_SGIX_swap_group;
        }

        bool GLX_SGIX_video_source() {
                return _GLX_SGIX_video_source;
        }

        bool GLX_SGI_cushion() {
                return _GLX_SGI_cushion;
        }

        bool GLX_SGI_swap_control() {
                return _GLX_SGI_swap_control;
        }

        bool GLX_SGI_video_sync() {
                return _GLX_SGI_video_sync;
        }

        bool GLX_SUN_get_transparent_index() {
                return _GLX_SUN_get_transparent_index;
        }
}

private __gshared {
        bool _GLX_ARB_create_context;
        bool _GLX_ARB_get_proc_address;
        bool _GLX_EXT_import_context;
        bool _GLX_EXT_swap_control;
        bool _GLX_EXT_texture_from_pixmap;
        bool _GLX_MESA_agp_offset;
        bool _GLX_MESA_swap_control;
        bool _GLX_MESA_pixmap_colormap;
        bool _GLX_MESA_release_buffers;
        bool _GLX_MESA_set_3dfx_mode;
        bool _GLX_NV_copy_image;
        bool _GLX_NV_present_video;
        bool _GLX_NV_swap_group;
        bool _GLX_NV_video_capture;
        bool _GLX_NV_video_output;
        bool _GLX_OML_sync_control;
        bool _GLX_SGIX_fbconfig;
        bool _GLX_SGIX_hyperpipe;
        bool _GLX_SGIX_pbuffer;
        bool _GLX_SGIX_swap_barrier;
        bool _GLX_SGIX_swap_group;
        bool _GLX_SGIX_video_source;
        bool _GLX_SGI_cushion;
        bool _GLX_SGI_swap_control;
        bool _GLX_SGI_video_sync;
        bool _GLX_SUN_get_transparent_index;
}

enum {
        GLX_USE_GL = 1,
        GLX_BUFFER_SIZE = 2,
        GLX_LEVEL = 3,
        GLX_RGBA = 4,
        GLX_DOUBLEBUFFER = 5,
        GLX_STEREO = 6,
        GLX_AUX_BUFFERS = 7,
        GLX_RED_SIZE = 8,
        GLX_GREEN_SIZE = 9,
        GLX_BLUE_SIZE = 10,
        GLX_ALPHA_SIZE = 11,
        GLX_DEPTH_SIZE = 12,
        GLX_STENCIL_SIZE = 13,
        GLX_ACCUM_RED_SIZE = 14,
        GLX_ACCUM_GREEN_SIZE = 15,
        GLX_ACCUM_BLUE_SIZE = 16,
        GLX_ACCUM_ALPHA_SIZE = 17,
        GLX_BAD_SCREEN = 1,
        GLX_BAD_ATTRIBUTE = 2,
        GLX_NO_EXTENSION = 3,
        GLX_BAD_VISUAL = 4,
        GLX_BAD_CONTEXT = 5,
        GLX_BAD_VALUE = 6,
        GLX_BAD_ENUM = 7,
        GLX_CONFIG_CAVEAT = 0x20,
        GLX_DONT_CARE = 0xFFFFFFFF,
        GLX_X_VISUAL_TYPE = 0x22,
        GLX_TRANSPARENT_TYPE = 0x23,
        GLX_TRANSPARENT_INDEX_VALUE = 0x24,
        GLX_TRANSPARENT_RED_VALUE = 0x25,
        GLX_TRANSPARENT_GREEN_VALUE = 0x26,
        GLX_TRANSPARENT_BLUE_VALUE = 0x27,
        GLX_TRANSPARENT_ALPHA_VALUE = 0x28,
        GLX_WINDOW_BIT = 0x00000001,
        GLX_PIXMAP_BIT = 0x00000002,
        GLX_PBUFFER_BIT = 0x00000004,
        GLX_AUX_BUFFERS_BIT = 0x00000010,
        GLX_FRONT_LEFT_BUFFER_BIT = 0x00000001,
        GLX_FRONT_RIGHT_BUFFER_BIT = 0x00000002,
        GLX_BACK_LEFT_BUFFER_BIT = 0x00000004,
        GLX_BACK_RIGHT_BUFFER_BIT = 0x00000008,
        GLX_DEPTH_BUFFER_BIT = 0x00000020,
        GLX_STENCIL_BUFFER_BIT = 0x00000040,
        GLX_ACCUM_BUFFER_BIT = 0x00000080,
        GLX_NONE = 0x8000,
        GLX_SLOW_CONFIG = 0x8001,
        GLX_TRUE_COLOR = 0x8002,
        GLX_DIRECT_COLOR = 0x8003,
        GLX_PSEUDO_COLOR = 0x8004,
        GLX_STATIC_COLOR = 0x8005,
        GLX_GRAY_SCALE = 0x8006,
        GLX_STATIC_GRAY = 0x8007,
        GLX_TRANSPARENT_RGB = 0x8008,
        GLX_TRANSPARENT_INDEX = 0x8009,
        GLX_VISUAL_ID = 0x800B,
        GLX_SCREEN = 0x800C,
        GLX_NON_CONFORMANT_CONFIG = 0x800D,
        GLX_DRAWABLE_TYPE = 0x8010,
        GLX_RENDER_TYPE = 0x8011,
        GLX_X_RENDERABLE = 0x8012,
        GLX_FBCONFIG_ID = 0x8013,
        GLX_RGBA_TYPE = 0x8014,
        GLX_COLOR_INDEX_TYPE = 0x8015,
        GLX_MAX_PBUFFER_WIDTH = 0x8016,
        GLX_MAX_PBUFFER_HEIGHT = 0x8017,
        GLX_MAX_PBUFFER_PIXELS = 0x8018,
        GLX_PRESERVED_CONTENTS = 0x801B,
        GLX_LARGEST_PBUFFER = 0x801C,
        GLX_WIDTH = 0x801D,
        GLX_HEIGHT = 0x801E,
        GLX_EVENT_MASK = 0x801F,
        GLX_DAMAGED = 0x8020,
        GLX_SAVED = 0x8021,
        GLX_WINDOW = 0x8022,
        GLX_PBUFFER = 0x8023,
        GLX_PBUFFER_HEIGHT = 0x8040,
        GLX_PBUFFER_WIDTH = 0x8041,
        GLX_RGBA_BIT = 0x00000001,
        GLX_COLOR_INDEX_BIT = 0x00000002,
        GLX_PBUFFER_CLOBBER_MASK = 0x08000000,
        GLX_SAMPLE_BUFFERS = 0x186a0,
        GLX_SAMPLES = 0x186a1,
}

enum : uint {
        GLX_CONTEXT_DEBUG_BIT_ARB = 0x00000001,
        GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x00000002,
        GLX_CONTEXT_MAJOR_VERSION_ARB = 0x2091,
        GLX_CONTEXT_MINOR_VERSION_ARB = 0x2092,
        GLX_CONTEXT_FLAGS_ARB = 0x2094,
        GLX_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001,
        GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB = 0x00000002,
        GLX_CONTEXT_PROFILE_MASK_ARB = 0x9126,
        GLX_CONTEXT_ROBUST_ACCESS_BIT_ARB = 0x00000004,
        GLX_LOSE_CONTEXT_ON_RESET_ARB = 0x8252,
        GLX_CONTEXT_RESET_NOTIFICATION_STRATEGY_ARB = 0x8256,
        GLX_NO_RESET_NOTIFICATION_ARB = 0x8261,
        GLX_RGBA_FLOAT_TYPE_ARB = 0x20B9,
        GLX_RGBA_FLOAT_BIT_ARB = 0x00000004,
        GLX_FRAMEBUFFER_SRGB_CAPABLE_ARB = 0x20B2,
        GLX_SAMPLE_BUFFERS_ARB = 100000,
        GLX_SAMPLES_ARB = 100001,
        GLX_CONTEXT_RESET_ISOLATION_BIT_ARB = 0x00000008,
        GLX_SAMPLE_BUFFERS_3DFX = 0x8050,
        GLX_SAMPLES_3DFX = 0x8051,
        GLX_GPU_VENDOR_AMD = 0x1F00,
        GLX_GPU_RENDERER_STRING_AMD = 0x1F01,
        GLX_GPU_OPENGL_VERSION_STRING_AMD = 0x1F02,
        GLX_GPU_FASTEST_TARGET_GPUS_AMD = 0x21A2,
        GLX_GPU_RAM_AMD = 0x21A3,
        GLX_GPU_CLOCK_AMD = 0x21A4,
        GLX_GPU_NUM_PIPES_AMD = 0x21A5,
        GLX_GPU_NUM_SIMD_AMD = 0x21A6,
        GLX_GPU_NUM_RB_AMD = 0x21A7,
        GLX_GPU_NUM_SPI_AMD = 0x21A8,
        GLX_BACK_BUFFER_AGE_EXT = 0x20F4,
        GLX_CONTEXT_ES2_PROFILE_BIT_EXT = 0x00000004,
        GLX_CONTEXT_ES_PROFILE_BIT_EXT = 0x00000004,
        GLX_RGBA_UNSIGNED_FLOAT_TYPE_EXT = 0x20B1,
        GLX_RGBA_UNSIGNED_FLOAT_BIT_EXT = 0x00000008,
        GLX_FRAMEBUFFER_SRGB_CAPABLE_EXT = 0x20B2,
        GLX_SHARE_CONTEXT_EXT = 0x800A,
        GLX_VISUAL_ID_EXT = 0x800B,
        GLX_SCREEN_EXT = 0x800C,
        GLX_SWAP_INTERVAL_EXT = 0x20F1,
        GLX_MAX_SWAP_INTERVAL_EXT = 0x20F2,
        GLX_LATE_SWAPS_TEAR_EXT = 0x20F3,
        GLX_TEXTURE_1D_BIT_EXT = 0x00000001,
        GLX_TEXTURE_2D_BIT_EXT = 0x00000002,
        GLX_TEXTURE_RECTANGLE_BIT_EXT = 0x00000004,
        GLX_BIND_TO_TEXTURE_RGB_EXT = 0x20D0,
        GLX_BIND_TO_TEXTURE_RGBA_EXT = 0x20D1,
        GLX_BIND_TO_MIPMAP_TEXTURE_EXT = 0x20D2,
        GLX_BIND_TO_TEXTURE_TARGETS_EXT = 0x20D3,
        GLX_Y_INVERTED_EXT = 0x20D4,
        GLX_TEXTURE_FORMAT_EXT = 0x20D5,
        GLX_TEXTURE_TARGET_EXT = 0x20D6,
        GLX_MIPMAP_TEXTURE_EXT = 0x20D7,
        GLX_TEXTURE_FORMAT_NONE_EXT = 0x20D8,
        GLX_TEXTURE_FORMAT_RGB_EXT = 0x20D9,
        GLX_TEXTURE_FORMAT_RGBA_EXT = 0x20DA,
        GLX_TEXTURE_1D_EXT = 0x20DB,
        GLX_TEXTURE_2D_EXT = 0x20DC,
        GLX_TEXTURE_RECTANGLE_EXT = 0x20DD,
        GLX_FRONT_LEFT_EXT = 0x20DE,
        GLX_FRONT_RIGHT_EXT = 0x20DF,
        GLX_BACK_LEFT_EXT = 0x20E0,
        GLX_BACK_RIGHT_EXT = 0x20E1,
        GLX_FRONT_EXT = 0x20DE,
        GLX_BACK_EXT = 0x20E0,
        GLX_AUX0_EXT = 0x20E2,
        GLX_AUX1_EXT = 0x20E3,
        GLX_AUX2_EXT = 0x20E4,
        GLX_AUX3_EXT = 0x20E5,
        GLX_AUX4_EXT = 0x20E6,
        GLX_AUX5_EXT = 0x20E7,
        GLX_AUX6_EXT = 0x20E8,
        GLX_AUX7_EXT = 0x20E9,
        GLX_AUX8_EXT = 0x20EA,
        GLX_AUX9_EXT = 0x20EB,
        GLX_X_VISUAL_TYPE_EXT = 0x22,
        GLX_TRANSPARENT_TYPE_EXT = 0x23,
        GLX_TRANSPARENT_INDEX_VALUE_EXT = 0x24,
        GLX_TRANSPARENT_RED_VALUE_EXT = 0x25,
        GLX_TRANSPARENT_GREEN_VALUE_EXT = 0x26,
        GLX_TRANSPARENT_BLUE_VALUE_EXT = 0x27,
        GLX_TRANSPARENT_ALPHA_VALUE_EXT = 0x28,
        GLX_NONE_EXT = 0x8000,
        GLX_TRUE_COLOR_EXT = 0x8002,
        GLX_DIRECT_COLOR_EXT = 0x8003,
        GLX_PSEUDO_COLOR_EXT = 0x8004,
        GLX_STATIC_COLOR_EXT = 0x8005,
        GLX_GRAY_SCALE_EXT = 0x8006,
        GLX_STATIC_GRAY_EXT = 0x8007,
        GLX_TRANSPARENT_RGB_EXT = 0x8008,
        GLX_TRANSPARENT_INDEX_EXT = 0x8009,
        GLX_VISUAL_CAVEAT_EXT = 0x20,
        GLX_SLOW_VISUAL_EXT = 0x8001,
        GLX_NON_CONFORMANT_VISUAL_EXT = 0x800D,
        GLX_BUFFER_SWAP_COMPLETE_INTEL_MASK = 0x04000000,
        GLX_EXCHANGE_COMPLETE_INTEL = 0x8180,
        GLX_COPY_COMPLETE_INTEL = 0x8181,
        GLX_FLIP_COMPLETE_INTEL = 0x8182,
        GLX_3DFX_WINDOW_MODE_MESA = 0x1,
        GLX_3DFX_FULLSCREEN_MODE_MESA = 0x2,
        GLX_FLOAT_COMPONENTS_NV = 0x20B0,
        GLX_COVERAGE_SAMPLES_NV = 100001,
        GLX_COLOR_SAMPLES_NV = 0x20B3,
        GLX_DEVICE_ID_NV = 0x20CD,
        GLX_UNIQUE_ID_NV = 0x20CE,
        GLX_NUM_VIDEO_CAPTURE_SLOTS_NV = 0x20CF,
        GLX_VIDEO_OUT_COLOR_NV = 0x20C3,
        GLX_VIDEO_OUT_ALPHA_NV = 0x20C4,
        GLX_VIDEO_OUT_DEPTH_NV = 0x20C5,
        GLX_VIDEO_OUT_COLOR_AND_ALPHA_NV = 0x20C6,
        GLX_VIDEO_OUT_COLOR_AND_DEPTH_NV = 0x20C7,
        GLX_VIDEO_OUT_FRAME_NV = 0x20C8,
        GLX_VIDEO_OUT_FIELD_1_NV = 0x20C9,
        GLX_VIDEO_OUT_FIELD_2_NV = 0x20CA,
        GLX_VIDEO_OUT_STACKED_FIELDS_1_2_NV = 0x20CB,
        GLX_VIDEO_OUT_STACKED_FIELDS_2_1_NV = 0x20CC,
        GLX_SWAP_METHOD_OML = 0x8060,
        GLX_SWAP_EXCHANGE_OML = 0x8061,
        GLX_SWAP_COPY_OML = 0x8062,
        GLX_SWAP_UNDEFINED_OML = 0x8063,
        GLX_BLENDED_RGBA_SGIS = 0x8025,
        GLX_SAMPLE_BUFFERS_SGIS = 100000,
        GLX_SAMPLES_SGIS = 100001,
        GLX_MULTISAMPLE_SUB_RECT_WIDTH_SGIS = 0x8026,
        GLX_MULTISAMPLE_SUB_RECT_HEIGHT_SGIS = 0x8027,
        GLX_WINDOW_BIT_SGIX = 0x00000001,
        GLX_PIXMAP_BIT_SGIX = 0x00000002,
        GLX_RGBA_BIT_SGIX = 0x00000001,
        GLX_COLOR_INDEX_BIT_SGIX = 0x00000002,
        GLX_DRAWABLE_TYPE_SGIX = 0x8010,
        GLX_RENDER_TYPE_SGIX = 0x8011,
        GLX_X_RENDERABLE_SGIX = 0x8012,
        GLX_FBCONFIG_ID_SGIX = 0x8013,
        GLX_RGBA_TYPE_SGIX = 0x8014,
        GLX_COLOR_INDEX_TYPE_SGIX = 0x8015,
        GLX_HYPERPIPE_PIPE_NAME_LENGTH_SGIX = 80,
        GLX_BAD_HYPERPIPE_CONFIG_SGIX = 91,
        GLX_BAD_HYPERPIPE_SGIX = 92,
        GLX_HYPERPIPE_DISPLAY_PIPE_SGIX = 0x00000001,
        GLX_HYPERPIPE_RENDER_PIPE_SGIX = 0x00000002,
        GLX_PIPE_RECT_SGIX = 0x00000001,
        GLX_PIPE_RECT_LIMITS_SGIX = 0x00000002,
        GLX_HYPERPIPE_STEREO_SGIX = 0x00000003,
        GLX_HYPERPIPE_PIXEL_AVERAGE_SGIX = 0x00000004,
        GLX_HYPERPIPE_ID_SGIX = 0x8030,
        GLX_PBUFFER_BIT_SGIX = 0x00000004,
        GLX_BUFFER_CLOBBER_MASK_SGIX = 0x08000000,
        GLX_FRONT_LEFT_BUFFER_BIT_SGIX = 0x00000001,
        GLX_FRONT_RIGHT_BUFFER_BIT_SGIX = 0x00000002,
        GLX_BACK_LEFT_BUFFER_BIT_SGIX = 0x00000004,
        GLX_BACK_RIGHT_BUFFER_BIT_SGIX = 0x00000008,
        GLX_AUX_BUFFERS_BIT_SGIX = 0x00000010,
        GLX_DEPTH_BUFFER_BIT_SGIX = 0x00000020,
        GLX_STENCIL_BUFFER_BIT_SGIX = 0x00000040,
        GLX_ACCUM_BUFFER_BIT_SGIX = 0x00000080,
        GLX_SAMPLE_BUFFERS_BIT_SGIX = 0x00000100,
        GLX_MAX_PBUFFER_WIDTH_SGIX = 0x8016,
        GLX_MAX_PBUFFER_HEIGHT_SGIX = 0x8017,
        GLX_MAX_PBUFFER_PIXELS_SGIX = 0x8018,
        GLX_OPTIMAL_PBUFFER_WIDTH_SGIX = 0x8019,
        GLX_OPTIMAL_PBUFFER_HEIGHT_SGIX = 0x801A,
        GLX_PRESERVED_CONTENTS_SGIX = 0x801B,
        GLX_LARGEST_PBUFFER_SGIX = 0x801C,
        GLX_WIDTH_SGIX = 0x801D,
        GLX_HEIGHT_SGIX = 0x801E,
        GLX_EVENT_MASK_SGIX = 0x801F,
        GLX_DAMAGED_SGIX = 0x8020,
        GLX_SAVED_SGIX = 0x8021,
        GLX_WINDOW_SGIX = 0x8022,
        GLX_PBUFFER_SGIX = 0x8023,
        GLX_SYNC_FRAME_SGIX = 0x00000000,
        GLX_SYNC_SWAP_SGIX = 0x00000001,
        GLX_VISUAL_SELECT_GROUP_SGIX = 0x8028,
}

struct GLXHyperpipeNetworkSGIX {
        char[GLX_HYPERPIPE_PIPE_NAME_LENGTH_SGIX] pipeName;
        int networkId;
}

struct GLXHyperpipeConfigSGIX {
        char[GLX_HYPERPIPE_PIPE_NAME_LENGTH_SGIX] pipeName;
        int chann;
        uint participationType;
        int timeSlice;
}

struct GLXPipeRect {
        char[GLX_HYPERPIPE_PIPE_NAME_LENGTH_SGIX] pipeName;
        int srcXOrigin, srcYOrigin, srcWidth, srcHeight;
        int destXOrigin, destYOrigin, destWidth, destHeight;
}

struct GLXPipeRectLimits {
        char[GLX_HYPERPIPE_PIPE_NAME_LENGTH_SGIX] pipeName;
        int XOrigin, YOrigin, maxHeight, maxWidth;
}
