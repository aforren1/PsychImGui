// Native GL smoke test for the psychimgui core.
//
// Psychtoolbox is not installed on every developer machine, but the GL path
// still has to be proven. This program creates a hidden window with a legacy
// compatibility context, the same kind PTB creates, and runs the exact core
// calls the MEX makes: Init, NewFrame, a few widgets, Render, Shutdown. It
// links src/core without MATLAB, so a failure here is a binding failure, not a
// marshaling failure.
//
// Exit code 0 means the whole path ran with GL_NO_ERROR.

#include <stdio.h>
#include <string.h>

#include "core/psychimgui_core.h"
#include "imgui.h"

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <GL/gl.h>

namespace {

HWND g_wnd;
HDC g_dc;
HGLRC g_rc;

bool create_context() {
    WNDCLASSA wc;
    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.lpszClassName = "psychimgui_smoke";
    wc.style = CS_OWNDC;
    if (!RegisterClassA(&wc)) {
        printf("smoke_gl: RegisterClass failed (%lu)\n", GetLastError());
        return false;
    }
    // WS_POPUP without WS_VISIBLE keeps the window off screen, which matters on
    // a build agent with no interactive session.
    g_wnd = CreateWindowExA(0, wc.lpszClassName, "psychimgui smoke", WS_POPUP, 0, 0, 320, 240,
                            NULL, NULL, wc.hInstance, NULL);
    if (!g_wnd) {
        printf("smoke_gl: CreateWindow failed (%lu)\n", GetLastError());
        return false;
    }
    g_dc = GetDC(g_wnd);

    PIXELFORMATDESCRIPTOR pfd;
    memset(&pfd, 0, sizeof(pfd));
    pfd.nSize = sizeof(pfd);
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 24;
    pfd.cStencilBits = 8;
    int pf = ChoosePixelFormat(g_dc, &pfd);
    if (!pf || !SetPixelFormat(g_dc, pf, &pfd)) {
        printf("smoke_gl: no usable pixel format\n");
        return false;
    }
    // wglCreateContext, not wglCreateContextAttribsARB: PTB does the same, so
    // the driver hands back its highest compatibility profile.
    g_rc = wglCreateContext(g_dc);
    if (!g_rc || !wglMakeCurrent(g_dc, g_rc)) {
        printf("smoke_gl: wglCreateContext failed (%lu)\n", GetLastError());
        return false;
    }
    return true;
}

void destroy_context() {
    if (g_rc) {
        wglMakeCurrent(NULL, NULL);
        wglDeleteContext(g_rc);
    }
    if (g_dc) ReleaseDC(g_wnd, g_dc);
    if (g_wnd) DestroyWindow(g_wnd);
}

void swap() { SwapBuffers(g_dc); }

}  // namespace

#elif defined(__APPLE__)

// macOS has no windowless GL context the way WGL and GLX do, so this path uses
// CGL directly and renders into a framebuffer object. There is no window and
// nothing reaches the screen, which is what a CI runner needs.
//
// No kCGLPFAOpenGLProfile attribute, so this is the legacy profile: OpenGL
// 2.1, exactly what Psychtoolbox creates on macOS, which is the context this
// binding has to work in. The core dispatches to imgui_impl_opengl2 there,
// because imgui_impl_opengl3 calls glGenVertexArrays unconditionally and a 2.1
// profile has no core vertex array objects.
//
// glext.h is safe to include here: this file never includes the Dear ImGui
// loader, whose generated function pointer names would collide with it. Do not
// include an Apple GL header in a translation unit that pulls in
// imgui_impl_opengl3.cpp's loader.
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>

namespace {

CGLContextObj g_ctx;
GLuint g_fbo;
GLuint g_rbo;

CGLError make_context(bool software) {
    CGLPixelFormatAttribute attribs[10];
    int n = 0;
    attribs[n++] = kCGLPFAColorSize;
    attribs[n++] = (CGLPixelFormatAttribute)24;
    attribs[n++] = kCGLPFAAlphaSize;
    attribs[n++] = (CGLPixelFormatAttribute)8;
    attribs[n++] = kCGLPFADepthSize;
    attribs[n++] = (CGLPixelFormatAttribute)24;
    if (software) {
        // Apple's software renderer, for a runner with no usable GPU.
        attribs[n++] = kCGLPFARendererID;
        attribs[n++] = (CGLPixelFormatAttribute)kCGLRendererGenericFloatID;
    }
    attribs[n++] = (CGLPixelFormatAttribute)0;

    CGLPixelFormatObj pix = NULL;
    GLint npix = 0;
    CGLError e = CGLChoosePixelFormat(attribs, &pix, &npix);
    if (e != kCGLNoError || pix == NULL) {
        return (e == kCGLNoError) ? kCGLBadPixelFormat : e;
    }
    e = CGLCreateContext(pix, NULL, &g_ctx);
    CGLDestroyPixelFormat(pix);
    return e;
}

bool create_context() {
    CGLError e = make_context(false);
    if (e != kCGLNoError) {
        printf("smoke_gl: hardware CGL pixel format failed (%s), trying the "
               "software renderer\n", CGLErrorString(e));
        e = make_context(true);
    }
    if (e != kCGLNoError || g_ctx == NULL) {
        printf("smoke_gl: CGLCreateContext failed: %s\n", CGLErrorString(e));
        return false;
    }
    if (CGLSetCurrentContext(g_ctx) != kCGLNoError) {
        printf("smoke_gl: CGLSetCurrentContext failed\n");
        return false;
    }

    // A context with no drawable needs a framebuffer object to render into.
    // The EXT names are the ones Apple's 2.1 profile guarantees, through
    // GL_EXT_framebuffer_object.
    glGenFramebuffersEXT(1, &g_fbo);
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, g_fbo);
    glGenRenderbuffersEXT(1, &g_rbo);
    glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, g_rbo);
    glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_RGBA8, 320, 240);
    glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT,
                                 GL_RENDERBUFFER_EXT, g_rbo);
    if (glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT) !=
        GL_FRAMEBUFFER_COMPLETE_EXT) {
        printf("smoke_gl: the offscreen framebuffer is not complete\n");
        return false;
    }
    glViewport(0, 0, 320, 240);
    return true;
}

void destroy_context() {
    if (!g_ctx) return;
    if (g_rbo) glDeleteRenderbuffersEXT(1, &g_rbo);
    if (g_fbo) glDeleteFramebuffersEXT(1, &g_fbo);
    CGLSetCurrentContext(NULL);
    CGLDestroyContext(g_ctx);
}

// Nothing is on screen, so there is nothing to swap. Flush so the driver is
// made to do the work rather than discard it.
void swap() { glFlush(); }

}  // namespace

#else

#include <GL/glx.h>
#include <X11/Xlib.h>

namespace {

Display* g_dpy;
Window g_win;
GLXContext g_ctx;
Colormap g_cmap;

bool create_context() {
    g_dpy = XOpenDisplay(NULL);
    if (!g_dpy) {
        printf("smoke_gl: cannot open an X display. Set DISPLAY, or run under "
               "xvfb-run, which is what CI does.\n");
        return false;
    }
    int screen = DefaultScreen(g_dpy);

    // glXChooseVisual and glXCreateContext, not glXCreateContextAttribsARB:
    // Psychtoolbox creates a legacy compatibility context the same way, so the
    // driver hands back its highest compatibility profile.
    int attribs[] = {GLX_RGBA,      GLX_DOUBLEBUFFER, GLX_RED_SIZE,   8,
                     GLX_GREEN_SIZE, 8,               GLX_BLUE_SIZE,  8,
                     GLX_ALPHA_SIZE, 8,               GLX_DEPTH_SIZE, 24,
                     GLX_STENCIL_SIZE, 8,             None};
    XVisualInfo* vi = glXChooseVisual(g_dpy, screen, attribs);
    if (!vi) {
        printf("smoke_gl: no usable GLX visual. On a software only runner, "
               "install libgl1-mesa-dri and set LIBGL_ALWAYS_SOFTWARE=1.\n");
        return false;
    }

    Window root = RootWindow(g_dpy, vi->screen);
    g_cmap = XCreateColormap(g_dpy, root, vi->visual, AllocNone);
    XSetWindowAttributes swa;
    memset(&swa, 0, sizeof(swa));
    swa.colormap = g_cmap;
    swa.event_mask = StructureNotifyMask;
    // override_redirect keeps a window manager from decorating or moving the
    // window. Under Xvfb, which is where CI runs this, nothing is on screen at
    // all.
    swa.override_redirect = True;
    g_win = XCreateWindow(g_dpy, root, 0, 0, 320, 240, 0, vi->depth, InputOutput,
                          vi->visual, CWColormap | CWEventMask | CWOverrideRedirect,
                          &swa);
    if (!g_win) {
        printf("smoke_gl: XCreateWindow failed\n");
        XFree(vi);
        return false;
    }
    // The window has to be viewable before glXMakeCurrent, or GLX may reject
    // the drawable. Wait for the MapNotify rather than guessing a delay.
    XMapWindow(g_dpy, g_win);
    XEvent ev;
    XIfEvent(g_dpy, &ev,
             [](Display*, XEvent* e, XPointer arg) -> Bool {
                 return (e->type == MapNotify && e->xmap.window == *(Window*)arg) ? True
                                                                                  : False;
             },
             (XPointer)&g_win);

    g_ctx = glXCreateContext(g_dpy, vi, NULL, True);
    XFree(vi);
    if (!g_ctx || !glXMakeCurrent(g_dpy, g_win, g_ctx)) {
        printf("smoke_gl: glXCreateContext or glXMakeCurrent failed\n");
        return false;
    }
    return true;
}

void destroy_context() {
    if (!g_dpy) return;
    if (g_ctx) {
        glXMakeCurrent(g_dpy, None, NULL);
        glXDestroyContext(g_dpy, g_ctx);
    }
    if (g_win) XDestroyWindow(g_dpy, g_win);
    if (g_cmap) XFreeColormap(g_dpy, g_cmap);
    XCloseDisplay(g_dpy);
}

void swap() { glXSwapBuffers(g_dpy, g_win); }

}  // namespace

// X11 leaks None, Bool, True, False and Status as object-like macros. main()
// below writes pig::Renderer::None, so drop them now that the GLX code above
// has had its use of them.
#undef None
#undef Bool
#undef True
#undef False
#undef Status
#undef Success

#endif

int main(int argc, char** argv) {
    // "smoke_gl none" exercises the headless path the engine tests run on,
    // which needs no window at all. "smoke_gl gl2" forces the fixed function
    // backend, which is the one a legacy OpenGL 2.1 context gets, so the macOS
    // path can be exercised on a machine that has a modern context.
    bool headless = (argc > 1 && strcmp(argv[1], "none") == 0);
    bool forceGl2 = (argc > 1 && strcmp(argv[1], "gl2") == 0);
    if (!headless && !create_context()) return 2;

    if (headless) {
        printf("smoke_gl: headless, renderer=none\n");
    } else {
        printf("smoke_gl: GL_VERSION  %s\n", (const char*)glGetString(GL_VERSION));
        printf("smoke_gl: GL_RENDERER %s\n", (const char*)glGetString(GL_RENDERER));
    }

    pig::InitOpts opts;
    memset(&opts, 0, sizeof(opts));
    opts.renderer = headless  ? pig::Renderer::None
                    : forceGl2 ? pig::Renderer::OpenGL2
                               : pig::Renderer::Auto;
    opts.displayW = 320;
    opts.displayH = 240;
    opts.implot = true;
    // glslVersion left empty: Init picks it from the live context.

    pig::Error err;
    memset(&err, 0, sizeof(err));
    if (!pig::init(opts, NULL, 0, err)) {
        printf("smoke_gl: Init failed: %s: %s\n", err.id, err.msg);
        if (!headless) destroy_context();
        return 3;
    }

    int rc = 0;
    double v = 0.5f;
    for (int frame = 0; frame < 3; ++frame) {
        pig::InputFrame in;
        memset(&in, 0, sizeof(in));
        double buttons[5] = {0, 0, 0, 0, 0};
        in.buttons = buttons;
        in.nButtons = 5;
        in.mouseX = 10;
        in.mouseY = 10;
        in.mouseValid = 1;
        in.displayW = 320;
        in.displayH = 240;
        in.focus = 1;
        in.fbscale = 1.0;
        in.time = 0.016 * frame;
        pig::newFrame(in);

        ImGui::Begin("smoke");
        ImGui::Text("%s", "hello from the smoke test");
        ImGui::Button("press");
        float fv = (float)v;
        ImGui::SliderFloat("gain", &fv, 0.0f, 1.0f);
        v = fv;
        static bool flag = false;
        ImGui::Checkbox("flag", &flag);
        ImGui::End();

        if (!headless) {
            glClearColor(0.1f, 0.1f, 0.15f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
        }
        memset(&err, 0, sizeof(err));
        if (!pig::render(err)) {
            printf("smoke_gl: Render failed: %s: %s\n", err.id, err.msg);
            rc = 4;
            break;
        }
        if (pig::assertPending()) {
            pig::assertTake(err);
            printf("smoke_gl: %s: %s\n", err.id, err.msg);
            rc = 5;
            break;
        }
        if (!headless) swap();
    }

    const pig::FrameStats& fs = pig::frameStats();
    pig::VersionInfo vi;
    pig::versionInfo(vi);
    printf("smoke_gl: backend %s%s%s\n", vi.renderer,
           vi.glslVersion[0] ? ", GLSL " : "", vi.glslVersion);

    printf("smoke_gl: last frame drawCalls=%llu vertices=%llu newFrameNs=%llu renderCpuNs=%llu\n",
           (unsigned long long)fs.drawCalls, (unsigned long long)fs.vertices,
           (unsigned long long)fs.newFrameNs, (unsigned long long)fs.renderCpuNs);

    if (rc == 0 && fs.vertices == 0) {
        printf("smoke_gl: no vertices were produced, the frame drew nothing\n");
        rc = 6;
    }

    bool skipped = false;
    pig::shutdown(&skipped);
    if (!headless) {
        GLenum e = glGetError();
        if (e != GL_NO_ERROR) {
            printf("smoke_gl: GL error 0x%04X after shutdown\n", (unsigned)e);
            rc = 7;
        }
        destroy_context();
    }
    printf(rc == 0 ? "smoke_gl: PASS\n" : "smoke_gl: FAIL\n");
    return rc;
}
