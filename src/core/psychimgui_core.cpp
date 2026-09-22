#include "psychimgui_core.h"

#include <float.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "gl_current.h"
#include "imgui.h"
#include "imgui_impl_opengl2.h"
#include "imgui_impl_opengl3.h"

#ifdef PSYCHIMGUI_IMPLOT
#  include "implot.h"
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

namespace {

// One context per process. The struct is a single zero-initialized static so
// that a failed Init leaves no partially live state behind.
struct State {
    ImGuiContext* ctx;
    Renderer rend;
    bool implot;
    int32_t keymap[257];  // indexed by PTB keycode, which is 1 based
    unsigned buttonState;
    unsigned modState;  // bit 0 ctrl, 1 shift, 2 alt, 3 super
    double lastTime;
    bool haveLastTime;
    bool focusState;
    unsigned pendingHighSurrogate;
    ImFont* fonts[16];
    int nFonts;
    FrameStats frame;
    char glVersion[128];
    char glRenderer[128];
    char glslVersion[32];
};

State g;

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

const char* renderer_name(Renderer r) {
    switch (r) {
        case Renderer::OpenGL3: return "opengl3";
        case Renderer::OpenGL2: return "opengl2";
        case Renderer::Auto: return "auto";
        default: return "none";
    }
}

bool isInit() { return g.ctx != nullptr; }
Renderer renderer() { return g.rend; }
bool implotEnabled() { return g.implot; }

bool assertPending() { return g_assert.set; }
void assertTake(Error& err) {
    err = g_assert;
    g_assert.set = false;
}
void assertClear() { g_assert.set = false; }

bool init(const InitOpts& opts, const int32_t* keymap, int keymapN, Error& err) {
    if (g.ctx) {
        set_error(err, "psychimgui:AlreadyInit",
                  "PsychImGui is already initialized. Call PsychImGui('Shutdown') first.");
        return false;
    }
    if (opts.renderer != Renderer::None && !gl_context_is_current()) {
        set_error(err, "psychimgui:NoGLContext",
                  "No current OpenGL context. Call Screen('BeginOpenGL', win) before "
                  "PsychImGui('Init', ...).");
        return false;
    }

    memset(&g, 0, sizeof(g));
    assertClear();

    IMGUI_CHECKVERSION();
    g.ctx = ImGui::CreateContext();
    if (!g.ctx) {
        set_error(err, "psychimgui:GLInit", "ImGui::CreateContext failed.");
        return false;
    }
    g.rend = opts.renderer;
    snprintf(g.glslVersion, sizeof(g.glslVersion), "%s", opts.glslVersion);

    ImGuiIO& io = ImGui::GetIO();
    static char iniPath[512];
    if (opts.iniEnabled && opts.iniFile[0]) {
        snprintf(iniPath, sizeof(iniPath), "%s", opts.iniFile);
        io.IniFilename = iniPath;
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
            ImGui::DestroyContext(g.ctx);
            memset(&g, 0, sizeof(g));
            set_error(err, "psychimgui:GLInit",
                      "The %s backend failed to start on '%s'%s%s.",
                      renderer_name(opts.renderer == Renderer::Auto
                                        ? Renderer::OpenGL3
                                        : opts.renderer),
                      v ? v : "an unknown context",
                      g.glslVersion[0] ? " with GLSL " : "",
                      g.glslVersion[0] ? g.glslVersion : "");
            return false;
        }
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
        ImPlot::CreateContext();
        g.implot = true;
    }
#else
    (void)opts.implot;
#endif

    g.focusState = true;
    if (g_assert.set) {
        err = g_assert;
        g_assert.set = false;
        return false;
    }
    return true;
}

void shutdown(bool* skippedGL) {
    if (skippedGL) *skippedGL = false;
    if (!g.ctx) return;

    ImGui::SetCurrentContext(g.ctx);
#ifdef PSYCHIMGUI_IMPLOT
    if (g.implot) ImPlot::DestroyContext();
#endif
    if (g.rend != Renderer::None) {
        if (gl_context_is_current()) {
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
    memset(&g, 0, sizeof(g));
    assertClear();
}

void newFrame(const InputFrame& in) {
    uint64_t t0 = nowNs();
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

    g.frame.newFrameNs = nowNs() - t0;
}

bool render(Error& err) {
    uint64_t t0 = nowNs();
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

    if (g.rend != Renderer::None && dd) {
        if (g.rend == Renderer::OpenGL2)
            ImGui_ImplOpenGL2_RenderDrawData(dd);
        else
            ImGui_ImplOpenGL3_RenderDrawData(dd);
        // Rule R3: Screen('EndOpenGL') aborts the script on a pending GL error,
        // so drain here and name the subcommand that caused it.
        unsigned e = (unsigned)glGetError();
        if (e != 0) {
            unsigned first = e;
            int guard = 0;
            while (e != 0 && guard++ < 64) e = (unsigned)glGetError();
            set_error(err, "psychimgui:GLError",
                      "OpenGL error %s (0x%04X) after PsychImGui('Render').",
                      gl_error_name(first), first);
            g.frame.renderCpuNs = nowNs() - t0;
            return false;
        }
    }
    // GPU timing is reported as 0 until the timer query path of section 9.2 is
    // wired; the backend loader owns the GL entry points it would need.
    g.frame.renderGpuNs = 0;
    g.frame.renderCpuNs = nowNs() - t0;
    return true;
}

void endFrame() { ImGui::EndFrame(); }

void wantCapture(bool* mouse, bool* keyboard, bool* text) {
    ImGuiIO& io = ImGui::GetIO();
    if (mouse) *mouse = io.WantCaptureMouse;
    if (keyboard) *keyboard = io.WantCaptureKeyboard;
    if (text) *text = io.WantTextInput;
}

int addFont(const char* path, double sizePx, const uint16_t* ranges, int nRanges, Error& err) {
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
    static ImWchar rangeBuf[64];
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

int fontCount() { return g.nFonts + 1; }

bool pushFont(int idx, double sizePx, Error& err) {
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
    out.imgui = IMGUI_VERSION;
    out.imguiNum = IMGUI_VERSION_NUM;
    out.psychimgui = PSYCHIMGUI_VERSION_STR;
    out.renderer = renderer_name(g.rend);
    out.glslVersion = g.ctx ? g.glslVersion : "";
    out.glVersion = g.ctx ? g.glVersion : "";
    out.glRenderer = g.ctx ? g.glRenderer : "";
    out.build = PSYCHIMGUI_BUILD_STR;
#ifdef PSYCHIMGUI_IMPLOT
    out.implot = true;
    out.implotVersion = IMPLOT_VERSION;
#else
    out.implot = false;
    out.implotVersion = "";
#endif
}

const FrameStats& frameStats() { return g.frame; }
void resetFrameStats() { memset(&g.frame, 0, sizeof(g.frame)); }

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
