// Engine-independent core of psychimgui.
//
// Nothing here includes mex.h. The MEX marshaling layer sits on top, and
// tools/smoke_gl.cpp links this core without MATLAB or Octave so the GL path
// can be exercised on a machine that has no Psychtoolbox.
#pragma once

#include <stddef.h>
#include <stdint.h>

struct ImFont;
struct ImGuiContext;

namespace pig {

enum class Renderer { None = 0, OpenGL3 = 1 };

// Error ids and messages travel as plain buffers because only the dispatch
// layer is allowed to raise, and it must do so after every destructor has run.
struct Error {
    bool set;
    char id[64];
    char msg[512];
};

struct InitOpts {
    Renderer renderer;
    bool iniEnabled;
    bool implot;
    double displayW, displayH;
    char glslVersion[32];
    char iniFile[512];
    char logFile[512];
};

// One frame of PTB input. Pointers stay owned by the caller and are read only
// during the newFrame call, so nothing is copied onto the heap.
struct InputFrame {
    double mouseX, mouseY;
    int mouseValid;
    const double* buttons;  // 1xB, left right middle x1 x2
    int nButtons;
    double wheelV, wheelH;
    const double* keys;  // Nx4 column major, [keycode pressed cookedKey time]
    int nKeys;
    double displayW, displayH;
    double time;
    int focus;
    double fbscale;
};

struct FrameStats {
    uint64_t newFrameNs;
    uint64_t renderCpuNs;
    uint64_t renderGpuNs;
    uint64_t drawCalls;
    uint64_t vertices;
};

struct VersionInfo {
    const char* imgui;
    int imguiNum;
    const char* psychimgui;
    const char* renderer;
    const char* glVersion;
    const char* glRenderer;
    const char* build;
    bool implot;
    const char* implotVersion;
};

// Lifecycle. init returns false and fills err on failure.
bool init(const InitOpts& opts, const int32_t* keymap, int keymapN, Error& err);
void shutdown(bool* skippedGL);
bool isInit();
Renderer renderer();
bool implotEnabled();

void newFrame(const InputFrame& in);
bool render(Error& err);
void endFrame();

void wantCapture(bool* mouse, bool* keyboard, bool* text);

// Fonts. addFont returns the font index, or -1 on failure with err filled.
int addFont(const char* path, double sizePx, const uint16_t* ranges, int nRanges, Error& err);
bool pushFont(int idx, double sizePx, Error& err);
void popFont();
int fontCount();

void setGlobalScale(double s);
void styleColors(int which);  // 0 dark, 1 light, 2 classic

void versionInfo(VersionInfo& out);
const FrameStats& frameStats();
void resetFrameStats();

// Deferred IM_ASSERT plumbing. The assert handler is C linkage so
// imconfig_psych.h can declare it without pulling in this header.
bool assertPending();
void assertTake(Error& err);
void assertClear();

// Monotonic nanosecond clock used by the Stats counters.
uint64_t nowNs();

// True when a GL context is current on this thread.
bool glContextCurrent();

}  // namespace pig
