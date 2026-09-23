#include "psychimgui_core.h"

#include <float.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "gl_current.h"
#include "gpu_timer.h"
#include "imgui.h"
#include "imgui_impl_opengl2.h"
#include "imgui_impl_opengl3.h"

#ifdef PSYCHIMGUI_IMPLOT
#  include "implot.h"
#endif
#ifdef PSYCHIMGUI_IMPLOT3D
#  include "implot3d.h"
#endif
#ifdef TRACY_ENABLE
#  include "client/TracyProfiler.hpp"
#  include "tracy/Tracy.hpp"
#  define PIG_ZONE(name) ZoneScopedN(name)
#else
#  define PIG_ZONE(name)
#endif

#if defined(_WIN32)
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  include <windows.h>
#  include <GL/gl.h>
#elif defined(__APPLE__)
#  include <OpenGL/gl.h>
#  include <mach/mach_time.h>
#else
#  include <GL/gl.h>
#  include <time.h>
#endif

#define PSYCHIMGUI_VERSION_STR "0.1.0"

#ifndef PSYCHIMGUI_BUILD_STR
#  define PSYCHIMGUI_BUILD_STR "unknown build"
#endif

namespace pig {

#ifdef PSYCHIMGUI_FILEDIALOG
void* igfd_create();
void igfd_destroy(void* d);
const char* igfd_version();
#endif

namespace {

// Everything one Psychtoolbox window's GUI needs, so two windows share
// nothing but the process. The struct is zeroed as a whole, so a failed Init
// leaves no partially live state behind.
struct State {
    double serial;          // the handle; 0 marks a free slot
    double win;
    void* glctx;            // the GL context Init ran in
    ImGuiContext* ctx;
#ifdef PSYCHIMGUI_IMPLOT
    ImPlotContext* plot;
#endif
#ifdef PSYCHIMGUI_IMPLOT3D
    ImPlot3DContext* plot3d;
#endif
#ifdef PSYCHIMGUI_FILEDIALOG
    void* dialog;           // IGFD::FileDialog, see igfd_unit.cpp
#endif
    Renderer rend;
    bool implot;
    bool implot3d;
    int32_t keymap[257];  // indexed by PTB keycode, which is 1 based
    unsigned buttonState;
    unsigned modState;  // bit 0 ctrl, 1 shift, 2 alt, 3 super
    double lastTime;
    bool haveLastTime;
    bool focusState;
    unsigned pendingHighSurrogate;
    ImFont* fonts[16];
    // Dear ImGui 1.92 reads glyph ranges when it bakes a glyph, long after
    // AddFontFromFileTTF returns, so each font keeps its own copy.
    ImWchar ranges[16][64];
    int nFonts;
    FrameStats frame;
    GpuTimer gpu;
    char glVersion[128];
    char glRenderer[128];
    char glslVersion[32];
    char iniPath[512];      // io.IniFilename points here for the context's life
    char gpuName[32];
    bool frameOpen;
    bool rendered;          // render ran since the last newFrame
};

State g_slots[kMaxContexts];
State* g_cur = nullptr;
// Serials are never reused, so a stale handle cannot select a new context.
double g_nextSerial = 1.0;
const FrameStats kNoStats = {0, 0, 0, 0, 0};

inline State& cur() { return *g_cur; }

// Dear ImGui, ImPlot, and ImPlot3D each keep one global current context, and
// their CreateContext calls do not always switch to the new one, so every
// switch sets all three together.
void make_current(State* st) {
    g_cur = st;
    ImGui::SetCurrentContext(st ? st->ctx : nullptr);
#ifdef PSYCHIMGUI_IMPLOT
    ImPlot::SetCurrentContext(st ? st->plot : nullptr);
#endif
#ifdef PSYCHIMGUI_IMPLOT3D
    ImPlot3D::SetCurrentContext(st ? st->plot3d : nullptr);
#endif
}

State* find_handle(double h) {
    if (!(h > 0.0)) return nullptr;
    for (int i = 0; i < kMaxContexts; ++i)
        if (g_slots[i].serial == h) return &g_slots[i];
    return nullptr;
}

// Draw list handles. Kept out of State so the generation survives the memset
// in init and shutdown: a handle taken before a Shutdown must stay stale after
// the next Init, even when the new context reuses the same pointers.
//
// 256 slots cover one draw list per window for far more windows than a GUI
// panel has; the table is scanned linearly, which beats hashing at this size.
const int kDrawListSlots = 256;
struct DrawListTable {
    uint64_t gen;
    int n;
    ImDrawList* ptr[kDrawListSlots];
    int clipDepth[kDrawListSlots];
};
DrawListTable g_dl = {1, 0, {}, {}};

void drawlists_invalidate() {
    ++g_dl.gen;
    g_dl.n = 0;
}

const char* gl_error_name(unsigned e) {
    switch (e) {
        case 0x0500: return "GL_INVALID_ENUM";
        case 0x0501: return "GL_INVALID_VALUE";
        case 0x0502: return "GL_INVALID_OPERATION";
        case 0x0503: return "GL_STACK_OVERFLOW";
        case 0x0504: return "GL_STACK_UNDERFLOW";
        case 0x0505: return "GL_OUT_OF_MEMORY";
        case 0x0506: return "GL_INVALID_FRAMEBUFFER_OPERATION";
        default: return "GL_UNKNOWN_ERROR";
    }
}

void set_error(Error& err, const char* id, const char* fmt, ...) {
    err.set = true;
    snprintf(err.id, sizeof(err.id), "%s", id);
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err.msg, sizeof(err.msg), fmt, ap);
    va_end(ap);
}

// The GLSL version the backend should compile its shaders as, for a context we
// have just been handed. opts.glslVersion overrides this.
//
// A Psychtoolbox window gives a legacy compatibility context, and on macOS that
// means OpenGL 2.1, whose shading language is 1.20. Elsewhere it is whatever
// the driver's highest compatibility version is, which is 3.0 or better on any
// machine that can run this binding, so 1.30 is the safe floor. macOS is the
// exception again above 2.1: Apple's core profiles support 1.50 and 4.10 only,
// never 1.30 or 1.40.
int gl_version_number(const char* gl_version) {
    int major = 0, minor = 0;
    if (gl_version) sscanf(gl_version, "%d.%d", &major, &minor);
    return major * 10 + minor;
}

const char* default_glsl_version(const char* gl_version) {
    int v = gl_version_number(gl_version);
#if defined(__APPLE__)
    return (v > 0 && v < 30) ? "#version 120" : "#version 150";
#else
    return (v > 0 && v < 30) ? "#version 120" : "#version 130";
#endif
}

// Modifier bits are derived from the mapped ImGuiKey, not from the PTB name, so
// one keymap covers every platform.
int modifier_bit(ImGuiKey k) {
    switch (k) {
        case ImGuiKey_LeftCtrl:
        case ImGuiKey_RightCtrl: return 1 << 0;
        case ImGuiKey_LeftShift:
        case ImGuiKey_RightShift: return 1 << 1;
        case ImGuiKey_LeftAlt:
        case ImGuiKey_RightAlt: return 1 << 2;
        case ImGuiKey_LeftSuper:
        case ImGuiKey_RightSuper: return 1 << 3;
        default: return 0;
    }
}

}  // namespace

// Filled by the IM_ASSERT redirection in imconfig_psych.h. Kept out of State so
// an assert during Init or Shutdown survives the state reset.
Error g_assert;

uint64_t nowNs() {
#if defined(_WIN32)
    static LARGE_INTEGER freq = {};
    if (freq.QuadPart == 0) QueryPerformanceFrequency(&freq);
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    // Split to keep the product inside 64 bits for counters near 1e7 Hz.
    return (uint64_t)(c.QuadPart / freq.QuadPart) * 1000000000ull +
           (uint64_t)((c.QuadPart % freq.QuadPart) * 1000000000ull / freq.QuadPart);
#elif defined(__APPLE__)
    static mach_timebase_info_data_t tb = {};
    if (tb.denom == 0) mach_timebase_info(&tb);
    return mach_absolute_time() * tb.numer / tb.denom;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
#endif
}

bool glContextCurrent() { return gl_context_is_current(); }

#ifdef TRACY_ENABLE
static bool g_profiler = false;
#endif

void profilerStartup() {
#if defined(TRACY_ENABLE) && defined(TRACY_MANUAL_LIFETIME)
    if (!g_profiler) tracy::StartupProfiler();
#endif
#ifdef TRACY_ENABLE
    g_profiler = true;
#endif
}

void profilerShutdown() {
#if defined(TRACY_ENABLE) && defined(TRACY_MANUAL_LIFETIME)
    if (g_profiler) tracy::ShutdownProfiler();
#endif
#ifdef TRACY_ENABLE
    g_profiler = false;
#endif
}

const char* renderer_name(Renderer r) {
    switch (r) {
        case Renderer::OpenGL3: return "opengl3";
        case Renderer::OpenGL2: return "opengl2";
        case Renderer::Auto: return "auto";
        default: return "none";
    }
}

bool isInit() { return g_cur != nullptr; }
Renderer renderer() { return g_cur ? g_cur->rend : Renderer::None; }
bool implotEnabled() { return g_cur && g_cur->implot; }

bool assertPending() { return g_assert.set; }
void assertTake(Error& err) {
    err = g_assert;
    g_assert.set = false;
}
void assertClear() { g_assert.set = false; }

double currentHandle() { return g_cur ? g_cur->serial : 0.0; }
int currentSlot() { return g_cur ? (int)(g_cur - g_slots) : -1; }

int contextCount() {
    int n = 0;
    for (int i = 0; i < kMaxContexts; ++i)
        if (g_slots[i].serial != 0.0) ++n;
    return n;
}

int liveHandles(double* out, int maxN) {
    int n = 0;
    for (int i = 0; i < kMaxContexts && n < maxN; ++i)
        if (g_slots[i].serial != 0.0) out[n++] = g_slots[i].serial;
    return n;
}

bool setContext(double h, Error& err) {
    State* st = find_handle(h);
    if (!st) {
        set_error(err, "psychimgui:InvalidHandle",
                  "%g is not a live PsychImGui context handle. It was never returned by "
                  "Init, or its context has been shut down.",
                  h);
        return false;
    }
    if (st != g_cur) {
        // Draw list handles name pointers of one context; a switch retires
        // them so one can never reach another context's lists.
        drawlists_invalidate();
        make_current(st);
    }
    return true;
}

GLState glState() {
    void* now = gl_current_context();
    if (!now) return GLState::NoContext;
    if (g_cur && g_cur->glctx && now != g_cur->glctx) return GLState::Mismatch;
    return GLState::Match;
}

bool init(const InitOpts& opts, const int32_t* keymap, int keymapN, Error& err) {
    for (int i = 0; i < kMaxContexts; ++i) {
        if (g_slots[i].serial != 0.0 && g_slots[i].win == opts.win) {
            set_error(err, "psychimgui:AlreadyInit",
                      "PsychImGui is already initialized for window %g. Call "
                      "PsychImGui('Shutdown') first.",
                      opts.win);
            return false;
        }
    }
    State* st = nullptr;
    for (int i = 0; i < kMaxContexts && !st; ++i)
        if (g_slots[i].serial == 0.0) st = &g_slots[i];
    if (!st) {
        set_error(err, "psychimgui:Context",
                  "All %d PsychImGui contexts are in use. Shut one down first.",
                  kMaxContexts);
        return false;
    }
    if (opts.renderer != Renderer::None && !gl_context_is_current()) {
        set_error(err, "psychimgui:NoGLContext",
                  "No current OpenGL context. Call Screen('BeginOpenGL', win) before "
                  "PsychImGui('Init', ...).");
        return false;
    }

    profilerStartup();
    State* prev = g_cur;
    memset(st, 0, sizeof(*st));
    assertClear();
    drawlists_invalidate();

    IMGUI_CHECKVERSION();
    ImGuiContext* ctx = ImGui::CreateContext();
    if (!ctx) {
        set_error(err, "psychimgui:GLInit", "ImGui::CreateContext failed.");
        return false;
    }
    // CreateContext keeps an existing context current, and the backend and
    // ImPlot below attach to whichever one is current, so switch all three
    // libraries away from the previous context first.
    make_current(nullptr);
    st->ctx = ctx;
    g_cur = st;
    ImGui::SetCurrentContext(ctx);
    State& g = *st;
    g.win = opts.win;
    g.rend = opts.renderer;
    snprintf(g.glslVersion, sizeof(g.glslVersion), "%s", opts.glslVersion);

    ImGuiIO& io = ImGui::GetIO();
    if (opts.iniEnabled && opts.iniFile[0]) {
        snprintf(g.iniPath, sizeof(g.iniPath), "%s", opts.iniFile);
        io.IniFilename = g.iniPath;
    } else {
        io.IniFilename = nullptr;
    }
    io.LogFilename = nullptr;
    io.BackendPlatformName = "psychimgui (Psychtoolbox)";
    // Error recovery keeps a missing End() from cascading into the next frame,
    // which matters because the script, not the MEX, owns the Begin/End pairing.
    io.ConfigErrorRecovery = true;
    io.ConfigErrorRecoveryEnableAssert = true;
    io.ConfigErrorRecoveryEnableDebugLog = false;
    io.ConfigErrorRecoveryEnableTooltip = true;
    // Rule R5: the client rectangle arrives at Init and again every frame.
    io.DisplaySize = ImVec2(opts.displayW > 0 ? (float)opts.displayW : 640.0f,
                            opts.displayH > 0 ? (float)opts.displayH : 480.0f);
    io.DeltaTime = 1.0f / 60.0f;

    if (keymap && keymapN > 0) {
        int n = keymapN < 257 ? keymapN : 257;
        for (int i = 0; i < n; ++i) g.keymap[i] = keymap[i];
    }

    if (opts.renderer != Renderer::None) {
        // Read the context before the backend does, so both the backend and
        // the GLSL version can be chosen from it. A context is already
        // current; Init checked that.
        g.glctx = gl_current_context();
        const char* v = (const char*)glGetString(GL_VERSION);
        const char* r = (const char*)glGetString(GL_RENDERER);
        snprintf(g.glVersion, sizeof(g.glVersion), "%s", v ? v : "unknown");
        snprintf(g.glRenderer, sizeof(g.glRenderer), "%s", r ? r : "unknown");

        if (g.rend == Renderer::Auto) {
            g.rend = (gl_version_number(v) < 30) ? Renderer::OpenGL2
                                                 : Renderer::OpenGL3;
        }

        bool ok;
        if (g.rend == Renderer::OpenGL2) {
            g.glslVersion[0] = 0;   // fixed function, no shaders
            ok = ImGui_ImplOpenGL2_Init();
        } else {
            if (!g.glslVersion[0]) {
                snprintf(g.glslVersion, sizeof(g.glslVersion), "%s",
                         default_glsl_version(v));
            }
            ok = ImGui_ImplOpenGL3_Init(g.glslVersion);
        }
        if (!ok) {
            char gv[128], gs[32];
            snprintf(gv, sizeof(gv), "%s", g.glVersion);
            snprintf(gs, sizeof(gs), "%s", g.glslVersion);
            ImGui::DestroyContext(ctx);
            memset(st, 0, sizeof(*st));
            make_current(prev);
            set_error(err, "psychimgui:GLInit",
                      "The %s backend failed to start on '%s'%s%s.",
                      renderer_name(opts.renderer == Renderer::Auto
                                        ? Renderer::OpenGL3
                                        : opts.renderer),
                      gv, gs[0] ? " with GLSL " : "", gs);
            return false;
        }
        snprintf(g.gpuName, sizeof(g.gpuName), "PsychImGui window %g", opts.win);
        gpuTimerInit(g.gpu, g.glVersion, g.gpuName);
    } else {
        // Without a renderer nothing claims ImGuiBackendFlags_RendererHasTextures,
        // so the atlas never gets built by a backend. NewFrame then dereferences
        // a null builder, so build it here in software once. Render discards the
        // draw data afterwards. This is the path the engine-only tests run on.
        snprintf(g.glVersion, sizeof(g.glVersion), "%s", "none");
        snprintf(g.glRenderer, sizeof(g.glRenderer), "%s", "none");
        g.glslVersion[0] = 0;   // no shaders without a renderer
        io.BackendRendererName = "none";
        // Claim texture support so Dear ImGui builds the atlas itself. Without
        // the flag the 1.92 atlas waits for a legacy backend to build it, and
        // the next NewFrame dereferences a null builder. The texture requests
        // are answered in render() below.
        io.BackendFlags |= ImGuiBackendFlags_RendererHasTextures;
    }

#ifdef PSYCHIMGUI_IMPLOT
    if (opts.implot) {
        g.plot = ImPlot::CreateContext();
        g.implot = true;
    }
#else
    (void)opts.implot;
#endif
#ifdef PSYCHIMGUI_IMPLOT3D
    if (opts.implot3d) {
        g.plot3d = ImPlot3D::CreateContext();
        g.implot3d = true;
    }
#else
    (void)opts.implot3d;
#endif

    g.focusState = true;
    g.serial = g_nextSerial;
    g_nextSerial += 1.0;
    make_current(st);
    if (g_assert.set) {
        err = g_assert;
        g_assert.set = false;
        return false;
    }
    return true;
}

namespace {

// Tears down one context. The GL objects of the backend and the timer queries
// belong to the context's own window, so they are deleted only while that
// window's context is current. Otherwise Psychtoolbox frees them with the
// window, and deleting the same names in another window's context would
// destroy that window's objects instead.
void destroy_state(State* st, bool* skippedGL) {
    State* keep = (g_cur == st) ? nullptr : g_cur;
    make_current(st);
    State& g = *st;
#ifdef PSYCHIMGUI_FILEDIALOG
    if (g.dialog) igfd_destroy(g.dialog);
    g.dialog = nullptr;
#endif
#ifdef PSYCHIMGUI_IMPLOT3D
    if (g.plot3d) ImPlot3D::DestroyContext(g.plot3d);
#endif
#ifdef PSYCHIMGUI_IMPLOT
    if (g.plot) ImPlot::DestroyContext(g.plot);
#endif
    if (g.rend != Renderer::None) {
        void* now = gl_current_context();
        if (now && now == g.glctx) {
            gpuTimerShutdown(g.gpu);
            if (g.rend == Renderer::OpenGL2)
                ImGui_ImplOpenGL2_Shutdown();
            else
                ImGui_ImplOpenGL3_Shutdown();
        } else if (skippedGL) {
            // PTB frees the GL objects with the context, so leaking them here is
            // recoverable; crashing inside a dead context is not.
            *skippedGL = true;
        }
    }
    ImGui::DestroyContext(g.ctx);
    memset(st, 0, sizeof(*st));
    make_current(keep);
    assertClear();
    drawlists_invalidate();
}

}  // namespace

void shutdown(bool* skippedGL) {
    if (skippedGL) *skippedGL = false;
    if (!g_cur) return;
    destroy_state(g_cur, skippedGL);
}

bool shutdownHandle(double h, bool* skippedGL, Error& err) {
    if (skippedGL) *skippedGL = false;
    State* st = find_handle(h);
    if (!st) {
        set_error(err, "psychimgui:InvalidHandle",
                  "%g is not a live PsychImGui context handle.", h);
        return false;
    }
    destroy_state(st, skippedGL);
    return true;
}

void shutdownAll(bool* skippedGL) {
    if (skippedGL) *skippedGL = false;
    for (int i = 0; i < kMaxContexts; ++i) {
        if (g_slots[i].serial == 0.0) continue;
        bool sk = false;
        destroy_state(&g_slots[i], &sk);
        if (skippedGL && sk) *skippedGL = true;
    }
}

void newFrame(const InputFrame& in) {
    PIG_ZONE("NewFrame");
    uint64_t t0 = nowNs();
    State& g = cur();
    ImGuiIO& io = ImGui::GetIO();

    bool focus = in.focus != 0;
    if (focus != g.focusState) {
        io.AddFocusEvent(focus);
        g.focusState = focus;
        if (!focus) g.buttonState = 0;
    }

    if (in.mouseValid)
        io.AddMousePosEvent((float)in.mouseX, (float)in.mouseY);
    else
        io.AddMousePosEvent(-FLT_MAX, -FLT_MAX);

    unsigned newButtons = 0;
    int nb = in.nButtons < 5 ? in.nButtons : 5;
    for (int i = 0; i < nb; ++i)
        if (in.buttons[i] != 0.0) newButtons |= (1u << i);
    if (newButtons != g.buttonState) {
        for (int i = 0; i < 5; ++i) {
            unsigned bit = 1u << i;
            if ((newButtons & bit) != (g.buttonState & bit))
                io.AddMouseButtonEvent(i, (newButtons & bit) != 0);
        }
        g.buttonState = newButtons;
    }

    if (in.wheelV != 0.0 || in.wheelH != 0.0)
        io.AddMouseWheelEvent((float)in.wheelH, (float)in.wheelV);

    // Key rows arrive in time order from the KbEventGet drain, and the column
    // major layout means column c of row r sits at keys[c * nKeys + r].
    for (int r = 0; r < in.nKeys; ++r) {
        int code = (int)in.keys[0 * in.nKeys + r];
        bool pressed = in.keys[1 * in.nKeys + r] != 0.0;
        int cooked = (int)in.keys[2 * in.nKeys + r];

        if (code >= 1 && code <= 256) {
            ImGuiKey k = (ImGuiKey)g.keymap[code];
            if (k != ImGuiKey_None) {
                io.AddKeyEvent(k, pressed);
                int bit = modifier_bit(k);
                if (bit) {
                    unsigned before = g.modState;
                    if (pressed)
                        g.modState |= (unsigned)bit;
                    else
                        g.modState &= ~(unsigned)bit;
                    if (before != g.modState) {
                        ImGuiKey mod = (bit == 1)   ? ImGuiMod_Ctrl
                                       : (bit == 2) ? ImGuiMod_Shift
                                       : (bit == 4) ? ImGuiMod_Alt
                                                    : ImGuiMod_Super;
                        io.AddKeyEvent(mod, pressed);
                    }
                }
            }
        }

        if (pressed && cooked >= 32 && cooked != 127) {
            unsigned c = (unsigned)cooked;
            // PTB reports CookedKey as UTF-16 on Windows, so an astral code
            // point arrives as two rows carrying the surrogate halves.
            if (c >= 0xD800u && c <= 0xDBFFu) {
                g.pendingHighSurrogate = c;
            } else if (c >= 0xDC00u && c <= 0xDFFFu && g.pendingHighSurrogate) {
                unsigned full = 0x10000u + ((g.pendingHighSurrogate - 0xD800u) << 10) +
                                (c - 0xDC00u);
                g.pendingHighSurrogate = 0;
                io.AddInputCharacter(full);
            } else {
                g.pendingHighSurrogate = 0;
                io.AddInputCharacter(c);
            }
        }
    }

    if (in.displayW > 0.0 && in.displayH > 0.0)
        io.DisplaySize = ImVec2((float)in.displayW, (float)in.displayH);
    float fb = in.fbscale > 0.0 ? (float)in.fbscale : 1.0f;
    io.DisplayFramebufferScale = ImVec2(fb, fb);

    double dt = 1.0 / 60.0;
    if (g.haveLastTime) {
        dt = in.time - g.lastTime;
        if (dt < 0.0001) dt = 0.0001;
        if (dt > 0.1) dt = 0.1;
    }
    g.lastTime = in.time;
    g.haveLastTime = true;
    io.DeltaTime = (float)dt;

    if (g.rend == Renderer::OpenGL2)
        ImGui_ImplOpenGL2_NewFrame();
    else if (g.rend == Renderer::OpenGL3)
        ImGui_ImplOpenGL3_NewFrame();
    ImGui::NewFrame();
    drawlists_invalidate();
    g.frameOpen = true;
    g.rendered = false;

    g.frame.newFrameNs = nowNs() - t0;
}

namespace {

// Hands the draw data to the backend once and checks rule R3. Render and
// RenderAgain share it, so the second eye of a stereo pair gets exactly the
// same treatment as the first.
bool submit(State& g, ImDrawData* dd, const char* cmd, Error& err) {
    if (g.rend == Renderer::None || !dd) return true;
    int slot = gpuTimerBegin(g.gpu);
    if (g.rend == Renderer::OpenGL2)
        ImGui_ImplOpenGL2_RenderDrawData(dd);
    else
        ImGui_ImplOpenGL3_RenderDrawData(dd);
    gpuTimerEnd(g.gpu, slot);
    // Rule R3: Screen('EndOpenGL') aborts the script on a pending GL error,
    // so drain here and name the subcommand that caused it.
    unsigned e = (unsigned)glGetError();
    if (e != 0) {
        unsigned first = e;
        int guard = 0;
        while (e != 0 && guard++ < 64) e = (unsigned)glGetError();
        set_error(err, "psychimgui:GLError",
                  "OpenGL error %s (0x%04X) after PsychImGui('%s').", gl_error_name(first),
                  first, cmd);
        return false;
    }
    return true;
}

}  // namespace

bool render(Error& err) {
    PIG_ZONE("Render");
    uint64_t t0 = nowNs();
    State& g = cur();
    // Render consumes the draw lists, so every handle dies here, before it.
    drawlists_invalidate();
    g.frameOpen = false;
    ImGui::Render();
    ImDrawData* dd = ImGui::GetDrawData();
    if (dd) {
        g.frame.drawCalls = 0;
        g.frame.vertices = (uint64_t)dd->TotalVtxCount;
        for (int i = 0; i < dd->CmdLists.Size; ++i)
            g.frame.drawCalls += (uint64_t)dd->CmdLists[i]->CmdBuffer.Size;
    }

    if (g.rend == Renderer::None && dd && dd->Textures) {
        // The smallest renderer that satisfies the 1.92 texture protocol: hand
        // every request a placeholder id and mark it done. Nothing is uploaded,
        // because nothing is drawn.
        for (ImTextureData* tex : *dd->Textures) {
            if (tex->Status == ImTextureStatus_WantCreate) {
                tex->SetTexID((ImTextureID)1);
                tex->SetStatus(ImTextureStatus_OK);
            } else if (tex->Status == ImTextureStatus_WantUpdates) {
                tex->SetStatus(ImTextureStatus_OK);
            } else if (tex->Status == ImTextureStatus_WantDestroy) {
                tex->SetTexID(ImTextureID_Invalid);
                tex->SetStatus(ImTextureStatus_Destroyed);
            }
        }
    }

    bool ok = submit(g, dd, "Render", err);
    g.rendered = ok;
    // The timer reads results at least one submission late, so this is the
    // GPU time of an earlier frame, which is what a non-blocking read can give.
    g.frame.renderGpuNs = g.gpu.lastNs;
    g.frame.renderCpuNs = nowNs() - t0;
#ifdef TRACY_ENABLE
    // One frame set per window, so a second window's frames do not cut into
    // the first window's timeline.
    static const char* kFrameNames[kMaxContexts] = {
        "PsychImGui ctx 1", "PsychImGui ctx 2", "PsychImGui ctx 3", "PsychImGui ctx 4",
        "PsychImGui ctx 5", "PsychImGui ctx 6", "PsychImGui ctx 7", "PsychImGui ctx 8"};
    if (g_cur == &g_slots[0])
        FrameMark;
    else
        FrameMarkNamed(kFrameNames[currentSlot()]);
#endif
    return ok;
}

bool renderAgain(Error& err) {
    PIG_ZONE("RenderAgain");
    State& g = cur();
    if (!g.rendered) {
        set_error(err, "psychimgui:Usage",
                  "RenderAgain submits the draw data of the last Render again, so it needs "
                  "a Render in this frame first, after NewFrame and before the next one.");
        return false;
    }
    // The first Render has already answered the texture requests, so the
    // backend finds nothing left to upload and only draws.
    bool ok = submit(g, ImGui::GetDrawData(), "RenderAgain", err);
    g.frame.renderGpuNs = g.gpu.lastNs;
    return ok;
}

void endFrame() {
    State& g = cur();
    drawlists_invalidate();
    g.frameOpen = false;
    g.rendered = false;
    ImGui::EndFrame();
}

bool frameOpen() { return g_cur != nullptr && g_cur->frameOpen; }

double drawListHandle(ImDrawList* dl) {
    if (!dl) return 0.0;
    int slot = -1;
    for (int i = 0; i < g_dl.n; ++i) {
        if (g_dl.ptr[i] == dl) {
            slot = i;
            break;
        }
    }
    if (slot < 0) {
        if (g_dl.n >= kDrawListSlots) return 0.0;
        slot = g_dl.n++;
        g_dl.ptr[slot] = dl;
        g_dl.clipDepth[slot] = 0;
    }
    // Exact in a double up to 2^53, that is 2^45 frames.
    return (double)(g_dl.gen * (uint64_t)kDrawListSlots + (uint64_t)slot);
}

ImDrawList* drawListFromHandle(double h, int* slot) {
    if (slot) *slot = -1;
    if (!frameOpen() || !(h >= 0.0) || h > 9007199254740992.0) return nullptr;
    uint64_t v = (uint64_t)h;
    if ((double)v != h) return nullptr;
    uint64_t gen = v / (uint64_t)kDrawListSlots;
    int s = (int)(v % (uint64_t)kDrawListSlots);
    if (gen != g_dl.gen || s >= g_dl.n) return nullptr;
    if (slot) *slot = s;
    return g_dl.ptr[s];
}

void drawListPushClip(int slot) {
    if (slot >= 0 && slot < g_dl.n) ++g_dl.clipDepth[slot];
}

bool drawListPopClip(int slot) {
    if (slot < 0 || slot >= g_dl.n || g_dl.clipDepth[slot] <= 0) return false;
    --g_dl.clipDepth[slot];
    return true;
}

bool setTextureFilter(unsigned glId, bool linear, Error& err) {
    if (renderer() == Renderer::None) return true;
    // An error left by someone else would read as ours below. It would abort
    // Screen('EndOpenGL') anyway, so dropping it here loses nothing useful.
    for (int guard = 0; guard < 64 && glGetError() != GL_NO_ERROR; ++guard) {
    }
    GLint prev = 0;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev);
    // Binding a name that already has another target, such as a PTB
    // GL_TEXTURE_RECTANGLE texture, fails with GL_INVALID_OPERATION. That is
    // exactly the texture the backends cannot sample, so report it.
    glBindTexture(GL_TEXTURE_2D, (GLuint)glId);
    GLenum e = glGetError();
    if (e != GL_NO_ERROR) {
        glBindTexture(GL_TEXTURE_2D, (GLuint)prev);
        while (glGetError() != GL_NO_ERROR) {
        }
        set_error(err, "psychimgui:Texture",
                  "OpenGL texture %u is not a GL_TEXTURE_2D texture (%s on bind). Dear "
                  "ImGui samples GL_TEXTURE_2D only; create the PTB texture with "
                  "Screen('MakeTexture', win, img, [], 1).",
                  glId, gl_error_name((unsigned)e));
        return false;
    }
    // PTB never sets a minification filter when it creates a texture, and the
    // GL default is a mipmap filter. A texture PTB has not drawn yet has no
    // mipmaps, so it is incomplete and samples as black until this runs.
    GLint f = linear ? GL_LINEAR : GL_NEAREST;
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, f);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, f);
    glBindTexture(GL_TEXTURE_2D, (GLuint)prev);
    e = glGetError();
    if (e != GL_NO_ERROR) {
        set_error(err, "psychimgui:GLError", "OpenGL error %s (0x%04X) in SetTextureFilter.",
                  gl_error_name((unsigned)e), (unsigned)e);
        return false;
    }
    return true;
}

void wantCapture(bool* mouse, bool* keyboard, bool* text) {
    ImGuiIO& io = ImGui::GetIO();
    if (mouse) *mouse = io.WantCaptureMouse;
    if (keyboard) *keyboard = io.WantCaptureKeyboard;
    if (text) *text = io.WantTextInput;
}

int addFont(const char* path, double sizePx, const uint16_t* ranges, int nRanges, Error& err) {
    State& g = cur();
    if (g.nFonts + 1 >= (int)(sizeof(g.fonts) / sizeof(g.fonts[0]))) {
        set_error(err, "psychimgui:Font", "Font table is full (%d entries).",
                  (int)(sizeof(g.fonts) / sizeof(g.fonts[0])));
        return -1;
    }
    FILE* f = fopen(path, "rb");
    if (!f) {
        set_error(err, "psychimgui:Font", "Cannot open font file '%s'.", path);
        return -1;
    }
    fclose(f);

    ImGuiIO& io = ImGui::GetIO();
    ImWchar* rangeBuf = g.ranges[g.nFonts + 1];
    const ImWchar* rp = nullptr;
    if (ranges && nRanges >= 2) {
        int n = nRanges < 63 ? nRanges : 62;
        for (int i = 0; i < n; ++i) rangeBuf[i] = (ImWchar)ranges[i];
        rangeBuf[n] = 0;
        rp = rangeBuf;
    }
    ImFontConfig cfg;
    ImFont* font = io.Fonts->AddFontFromFileTTF(path, (float)sizePx, &cfg, rp);
    if (!font) {
        set_error(err, "psychimgui:Font", "Failed to load font '%s'.", path);
        return -1;
    }
    g.fonts[++g.nFonts] = font;  // index 0 stays the default font
    return g.nFonts;
}

int fontCount() { return g_cur ? g_cur->nFonts + 1 : 0; }

bool pushFont(int idx, double sizePx, Error& err) {
    State& g = cur();
    if (idx < 0 || idx > g.nFonts) {
        set_error(err, "psychimgui:Usage", "Font index %d is out of range (0 to %d).",
                  idx, g.nFonts);
        return false;
    }
    ImFont* f = (idx == 0) ? nullptr : g.fonts[idx];
    ImGui::PushFont(f, (float)sizePx);
    return true;
}

void popFont() { ImGui::PopFont(); }

void setGlobalScale(double s) {
    ImGuiStyle& st = ImGui::GetStyle();
    st.FontScaleMain = (float)s;
    st.ScaleAllSizes((float)s);
}

void styleColors(int which) {
    if (which == 1) ImGui::StyleColorsLight();
    else if (which == 2) ImGui::StyleColorsClassic();
    else ImGui::StyleColorsDark();
}

void versionInfo(VersionInfo& out) {
    const State* g = g_cur;
    out.imgui = IMGUI_VERSION;
    out.imguiNum = IMGUI_VERSION_NUM;
    out.psychimgui = PSYCHIMGUI_VERSION_STR;
    out.renderer = renderer_name(g ? g->rend : Renderer::None);
    out.glslVersion = g ? g->glslVersion : "";
    out.glVersion = g ? g->glVersion : "";
    out.glRenderer = g ? g->glRenderer : "";
    out.build = PSYCHIMGUI_BUILD_STR;
#ifdef PSYCHIMGUI_IMPLOT
    out.implot = true;
    out.implotVersion = IMPLOT_VERSION;
#else
    out.implot = false;
    out.implotVersion = "";
#endif
#ifdef PSYCHIMGUI_IMPLOT3D
    out.implot3d = true;
    out.implot3dVersion = IMPLOT3D_VERSION;
#else
    out.implot3d = false;
    out.implot3dVersion = "";
#endif
#ifdef PSYCHIMGUI_FILEDIALOG
    out.fileDialog = true;
    out.fileDialogVersion = igfd_version();
#else
    out.fileDialog = false;
    out.fileDialogVersion = "";
#endif
    out.gpuTimer = g && g->gpu.ok;
#ifdef TRACY_ENABLE
    out.tracy = true;
#else
    out.tracy = false;
#endif
    out.context = g ? g->serial : 0.0;
}

void* fileDialog(bool create) {
#ifdef PSYCHIMGUI_FILEDIALOG
    if (!g_cur) return nullptr;
    if (!g_cur->dialog && create) g_cur->dialog = igfd_create();
    return g_cur->dialog;
#else
    (void)create;
    return nullptr;
#endif
}

const FrameStats& frameStats() { return g_cur ? g_cur->frame : kNoStats; }
void resetFrameStats() {
    if (g_cur) memset(&g_cur->frame, 0, sizeof(g_cur->frame));
}

}  // namespace pig

extern "C" void psychimgui_assert_failed(const char* expr, const char* file, int line) {
    if (pig::g_assert.set) return;  // keep the first failure, later ones follow from it
    pig::g_assert.set = true;
    snprintf(pig::g_assert.id, sizeof(pig::g_assert.id), "psychimgui:ImGuiAssert");
    const char* base = file;
    for (const char* p = file; *p; ++p)
        if (*p == '/' || *p == '\\') base = p + 1;
    snprintf(pig::g_assert.msg, sizeof(pig::g_assert.msg),
             "Dear ImGui assertion failed: %s (%s:%d)", expr, base, line);
}
