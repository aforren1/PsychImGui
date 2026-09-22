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

// The CGL path is not implemented. Run tests/gl/test_gl_render.m under
// Psychtoolbox on macOS instead.
#include <OpenGL/gl.h>
namespace {
bool create_context() {
    printf("smoke_gl: no context creation path for macOS yet. "
           "Run the Psychtoolbox test in tests/gl instead.\n");
    return false;
}
void destroy_context() {}
void swap() {}
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
    // which needs no window at all.
    bool headless = (argc > 1 && strcmp(argv[1], "none") == 0);
    if (!headless && !create_context()) return 2;

    if (headless) {
        printf("smoke_gl: headless, renderer=none\n");
    } else {
        printf("smoke_gl: GL_VERSION  %s\n", (const char*)glGetString(GL_VERSION));
        printf("smoke_gl: GL_RENDERER %s\n", (const char*)glGetString(GL_RENDERER));
    }

    pig::InitOpts opts;
    memset(&opts, 0, sizeof(opts));
    opts.renderer = headless ? pig::Renderer::None : pig::Renderer::OpenGL3;
    opts.displayW = 320;
    opts.displayH = 240;
    opts.implot = true;
    snprintf(opts.glslVersion, sizeof(opts.glslVersion), "#version 130");

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
