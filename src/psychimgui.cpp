// psychimgui: Dear ImGui panels inside a Psychtoolbox window.
//
// One MEX with Screen style string subcommands plus a numeric opcode fast path.
// The generated widget handlers live in gen_dispatch.cpp; this file owns the
// dispatch loop, the lifecycle subcommands, and the only place that raises.

#include <string.h>

#include "imgui_psych.h"

#include "core/psychimgui_core.h"
#include "dispatch.h"
#include "marshal.h"
#include "mex.h"

namespace mrs {
int enum_count();
const char* enum_name(int i);
double enum_value(int i);
}  // namespace mrs

namespace pig {

namespace {

// Per-subcommand counters, always compiled unless PSYCHIMGUI_STATS is 0.
// Fixed arrays keyed by opcode, so recording costs one add and one compare.
#ifndef PSYCHIMGUI_STATS
#  define PSYCHIMGUI_STATS 1
#endif

struct OpStats {
    uint64_t calls;
    uint64_t totalNs;
    uint64_t maxNs;
};

OpStats g_stats[512];
bool g_locked = false;

void raise(const char* id, const char* msg) { mexErrMsgIdAndTxt(id, "%s", msg); }

int find_op(const char* name) {
    int lo = 0, hi = kTableCount - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        int c = strcmp(name, kTable[mid].name);
        if (c == 0) return mid;
        if (c < 0)
            hi = mid - 1;
        else
            lo = mid + 1;
    }
    return -1;
}

void print_commands() {
    mexPrintf("PsychImGui subcommands (%d):\n", kTableCount);
    for (int i = 0; i < kTableCount; ++i) mexPrintf("  %s\n", kTable[i].name);
    mexPrintf("\nPsychImGui('Name?') prints the signature of one subcommand.\n");
}

void at_exit() {
    bool skipped = false;
    pig::shutdown(&skipped);
    g_locked = false;
}

// ------------------------------------------------------------ input struct --

const mxArray* field(const mxArray* s, const char* name) {
    if (!mxIsStruct(s)) return nullptr;
    int n = mxGetFieldNumber(s, name);
    if (n < 0) return nullptr;
    return mxGetFieldByNumber(s, 0, n);
}

double field_scalar(const mxArray* s, const char* name, double dflt) {
    const mxArray* f = field(s, name);
    if (!f || mxIsEmpty(f) || !(mxIsNumeric(f) || mxIsLogical(f))) return dflt;
    return mxGetScalar(f);
}

}  // namespace

// ============================================================== built-ins ===

void bi_Init(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin < 3 || nargin > 4) {
        mrs::fail("psychimgui:Usage",
                  "PsychImGui('Init', win, rect, keymap [, opts]) takes 3 or 4 arguments.");
        return;
    }
    InitOpts opts;
    memset(&opts, 0, sizeof(opts));
    opts.renderer = Renderer::OpenGL3;
    opts.implot = true;
    snprintf(opts.glslVersion, sizeof(opts.glslVersion), "#version 130");

    double rect[4] = {0, 0, 640, 480};
    if (!mxIsEmpty(args[1])) mrs::getVec(args[1], "rect", rect, 4);
    opts.displayW = rect[2] - rect[0];
    opts.displayH = rect[3] - rect[1];

    // The keymap is int32(256,1) from PsychImGuiKeymap, stored 1 based so a PTB
    // keycode indexes it directly.
    int32_t keymap[257];
    memset(keymap, 0, sizeof(keymap));
    const mxArray* km = args[2];
    if (km && !mxIsEmpty(km)) {
        if (!mxIsInt32(km)) {
            mrs::fail("psychimgui:Type", "Argument 'keymap' must be int32.");
            return;
        }
        int n = (int)mxGetNumberOfElements(km);
        if (n > 256) n = 256;
        const int32_t* p = (const int32_t*)mxGetData(km);
        for (int i = 0; i < n; ++i) keymap[i + 1] = p[i];
    }

    if (nargin == 4 && !mxIsEmpty(args[3])) {
        const mxArray* o = args[3];
        if (!mxIsStruct(o)) {
            mrs::fail("psychimgui:Type", "Argument 'opts' must be a struct.");
            return;
        }
        const mxArray* f = field(o, "renderer");
        if (f && mxIsChar(f)) {
            mrs::StrBuf<32> b;
            const char* r = mrs::toUtf8(f, "renderer", b);
            if (strcmp(r, "none") == 0)
                opts.renderer = Renderer::None;
            else if (strcmp(r, "opengl3") == 0)
                opts.renderer = Renderer::OpenGL3;
            else {
                mrs::fail("psychimgui:Usage",
                          "opts.renderer must be 'opengl3' or 'none', got '%s'.", r);
                return;
            }
        }
        f = field(o, "glslVersion");
        if (f && mxIsChar(f)) {
            mrs::StrBuf<32> b;
            snprintf(opts.glslVersion, sizeof(opts.glslVersion), "%s",
                     mrs::toUtf8(f, "glslVersion", b));
        }
        f = field(o, "iniFile");
        if (f && mxIsChar(f)) {
            mrs::StrBuf<512> b;
            const char* p = mrs::toUtf8(f, "iniFile", b);
            if (p[0]) {
                snprintf(opts.iniFile, sizeof(opts.iniFile), "%s", p);
                opts.iniEnabled = true;
            }
        }
        f = field(o, "logFile");
        if (f && mxIsChar(f)) {
            mrs::StrBuf<512> b;
            snprintf(opts.logFile, sizeof(opts.logFile), "%s", mrs::toUtf8(f, "logFile", b));
        }
        f = field(o, "implot");
        if (f && !mxIsEmpty(f)) opts.implot = mxGetScalar(f) != 0.0;
    }
    if (mrs::failed()) return;

    Error err;
    memset(&err, 0, sizeof(err));
    if (!init(opts, keymap, 257, err)) {
        mrs::fail(err.id, "%s", err.msg);
        return;
    }
    if (!g_locked) {
        mexLock();
        g_locked = true;
        mexAtExit(at_exit);
    }
}

void bi_Shutdown(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    (void)args;
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('Shutdown') takes no arguments.");
        return;
    }
    bool skipped = false;
    pig::shutdown(&skipped);
    if (skipped)
        mexWarnMsgIdAndTxt("psychimgui:NoGLContext",
                           "Shutdown ran with no current OpenGL context, so the backend "
                           "objects were left to the context owner. Call Shutdown inside "
                           "Screen('BeginOpenGL', win).");
    if (g_locked) {
        mexUnlock();
        g_locked = false;
    }
}

void bi_NewFrame(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin != 1 || !mxIsStruct(args[0])) {
        mrs::fail("psychimgui:Usage",
                  "PsychImGui('NewFrame', in) takes the struct from PsychImGuiInput('Poll').");
        return;
    }
    const mxArray* s = args[0];
    InputFrame in;
    memset(&in, 0, sizeof(in));
    in.focus = (int)field_scalar(s, "focus", 1.0);
    in.fbscale = field_scalar(s, "fbscale", 1.0);
    in.time = field_scalar(s, "time", 0.0);

    const mxArray* f = field(s, "mouse");
    if (f && mxIsDouble(f) && mxGetNumberOfElements(f) >= 2) {
        const double* p = mxGetPr(f);
        in.mouseX = p[0];
        in.mouseY = p[1];
        in.mouseValid = (mxGetNumberOfElements(f) >= 3) ? (int)(p[2] != 0.0) : 1;
    } else {
        in.mouseValid = 0;
    }

    f = field(s, "buttons");
    if (f && mxIsDouble(f)) {
        in.buttons = mxGetPr(f);
        in.nButtons = (int)mxGetNumberOfElements(f);
    }

    f = field(s, "wheel");
    if (f && mxIsDouble(f) && mxGetNumberOfElements(f) >= 1) {
        const double* p = mxGetPr(f);
        in.wheelV = p[0];
        if (mxGetNumberOfElements(f) >= 2) in.wheelH = p[1];
    }

    f = field(s, "keys");
    if (f && mxIsDouble(f) && mxGetNumberOfElements(f) > 0) {
        if (mxGetN(f) != 4) {
            mrs::fail("psychimgui:Usage",
                      "in.keys must be an Nx4 double array [keycode pressed cookedKey time].");
            return;
        }
        in.keys = mxGetPr(f);
        in.nKeys = (int)mxGetM(f);
    }

    f = field(s, "display");
    if (f && mxIsDouble(f) && mxGetNumberOfElements(f) >= 2) {
        const double* p = mxGetPr(f);
        in.displayW = p[0];
        in.displayH = p[1];
    }

    newFrame(in);
}

void bi_Render(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    (void)args;
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('Render') takes no arguments.");
        return;
    }
    Error err;
    memset(&err, 0, sizeof(err));
    if (!render(err)) mrs::fail(err.id, "%s", err.msg);
}

void bi_EndFrame(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    (void)args;
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('EndFrame') takes no arguments.");
        return;
    }
    endFrame();
}

void bi_Version(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nargin;
    (void)args;
    VersionInfo v;
    versionInfo(v);
    const char* fields[] = {"imgui",     "imguiNum", "psychimgui", "renderer", "glVersion",
                            "glRenderer", "build",   "implot",     "implotVersion"};
    mxArray* s = mxCreateStructMatrix(1, 1, 9, fields);
    mxSetField(s, 0, "imgui", mrs::fromUtf8(v.imgui));
    mxSetField(s, 0, "imguiNum", mxCreateDoubleScalar(v.imguiNum));
    mxSetField(s, 0, "psychimgui", mrs::fromUtf8(v.psychimgui));
    mxSetField(s, 0, "renderer", mrs::fromUtf8(v.renderer));
    mxSetField(s, 0, "glVersion", mrs::fromUtf8(v.glVersion));
    mxSetField(s, 0, "glRenderer", mrs::fromUtf8(v.glRenderer));
    mxSetField(s, 0, "build", mrs::fromUtf8(v.build));
    mxSetField(s, 0, "implot", mxCreateLogicalScalar(v.implot));
    mxSetField(s, 0, "implotVersion", mrs::fromUtf8(v.implotVersion));
    if (nlhs > 0)
        plhs[0] = s;
    else
        mxDestroyArray(s);
}

void bi_Opcode(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    if (nargin != 1 || !mxIsChar(args[0])) {
        mrs::fail("psychimgui:Usage", "PsychImGui('Opcode', name) takes one char argument.");
        return;
    }
    mrs::StrBuf<96> b;
    const char* n = mrs::toUtf8(args[0], "name", b);
    if (mrs::failed()) return;
    int op = find_op(n);
    if (op < 0 || (kTable[op].flags & kEntryUnavailable)) {
        mrs::fail("psychimgui:UnknownCommand", "Unknown subcommand '%s'.", n);
        return;
    }
    if (nlhs > 0) plhs[0] = mxCreateDoubleScalar(op);
}

void bi_Enum(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    if (nargin == 0) {
        int n = mrs::enum_count();
        // The whole table at once. This is a diagnostic call, not a per-frame
        // one, so the temporary name array is acceptable.
        const char** names = (const char**)mxMalloc((size_t)n * sizeof(char*));
        for (int i = 0; i < n; ++i) names[i] = mrs::enum_name(i);
        mxArray* s = mxCreateStructMatrix(1, 1, n, names);
        mxFree(names);
        for (int i = 0; i < n; ++i)
            mxSetFieldByNumber(s, 0, i, mxCreateDoubleScalar(mrs::enum_value(i)));
        if (nlhs > 0)
            plhs[0] = s;
        else
            mxDestroyArray(s);
        return;
    }
    if (nargin != 1 || !mxIsChar(args[0])) {
        mrs::fail("psychimgui:Usage", "PsychImGui('Enum' [, name]) takes zero or one char.");
        return;
    }
    mrs::StrBuf<128> b;
    const char* n = mrs::toUtf8(args[0], "name", b);
    if (mrs::failed()) return;
    double v = 0.0;
    if (!mrs::enum_lookup(n, &v)) {
        mrs::fail("psychimgui:UnknownCommand", "Unknown enum name '%s'.", n);
        return;
    }
    if (nlhs > 0) plhs[0] = mxCreateDoubleScalar(v);
}

void bi_Stats(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    bool reset = false;
    if (nargin == 1 && mxIsChar(args[0])) {
        mrs::StrBuf<16> b;
        reset = strcmp(mrs::toUtf8(args[0], "mode", b), "reset") == 0;
    } else if (nargin > 1) {
        mrs::fail("psychimgui:Usage", "PsychImGui('Stats' [, 'reset']) takes at most one arg.");
        return;
    }

    int used = 0;
    for (int i = 0; i < kTableCount; ++i)
        if (g_stats[i].calls) ++used;

    const char* pf[] = {"name", "calls", "totalNs", "maxNs"};
    mxArray* per = mxCreateStructMatrix(used ? 1 : 0, used ? used : 0, 4, pf);
    int k = 0;
    for (int i = 0; i < kTableCount; ++i) {
        if (!g_stats[i].calls) continue;
        mxSetField(per, k, "name", mrs::fromUtf8(kTable[i].name));
        mxSetField(per, k, "calls", mxCreateDoubleScalar((double)g_stats[i].calls));
        mxSetField(per, k, "totalNs", mxCreateDoubleScalar((double)g_stats[i].totalNs));
        mxSetField(per, k, "maxNs", mxCreateDoubleScalar((double)g_stats[i].maxNs));
        ++k;
    }

    const FrameStats& fs = frameStats();
    const char* ff[] = {"newFrameNs", "renderCpuNs", "renderGpuNs", "drawCalls", "vertices"};
    mxArray* frame = mxCreateStructMatrix(1, 1, 5, ff);
    mxSetField(frame, 0, "newFrameNs", mxCreateDoubleScalar((double)fs.newFrameNs));
    mxSetField(frame, 0, "renderCpuNs", mxCreateDoubleScalar((double)fs.renderCpuNs));
    mxSetField(frame, 0, "renderGpuNs", mxCreateDoubleScalar((double)fs.renderGpuNs));
    mxSetField(frame, 0, "drawCalls", mxCreateDoubleScalar((double)fs.drawCalls));
    mxSetField(frame, 0, "vertices", mxCreateDoubleScalar((double)fs.vertices));

    const char* tf[] = {"perOp", "frame"};
    mxArray* out = mxCreateStructMatrix(1, 1, 2, tf);
    mxSetField(out, 0, "perOp", per);
    mxSetField(out, 0, "frame", frame);

    if (reset) {
        memset(g_stats, 0, sizeof(g_stats));
        resetFrameStats();
    }
    if (nlhs > 0)
        plhs[0] = out;
    else
        mxDestroyArray(out);
}

void bi_WantCapture(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('WantCapture') takes no arguments.");
        return;
    }
    bool m = false, k = false, t = false;
    wantCapture(&m, &k, &t);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(m);
    if (nlhs > 1) plhs[1] = mxCreateLogicalScalar(k);
    if (nlhs > 2) plhs[2] = mxCreateLogicalScalar(t);
}

void bi_AddFontFromFileTTF(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    if (nargin < 2 || nargin > 3) {
        mrs::fail("psychimgui:Usage",
                  "PsychImGui('AddFontFromFileTTF', path, sizePx [, glyphRanges])");
        return;
    }
    mrs::StrBuf<512> b;
    const char* path = mrs::toUtf8(args[0], "path", b);
    double px = mrs::getScalar(args[1], "sizePx");
    uint16_t ranges[64];
    int nr = 0;
    if (nargin == 3 && !mxIsEmpty(args[2])) {
        int n = (int)mxGetNumberOfElements(args[2]);
        if (n > 62) n = 62;
        double tmp[62];
        mrs::getVec(args[2], "glyphRanges", tmp, n);
        for (int i = 0; i < n; ++i) ranges[i] = (uint16_t)tmp[i];
        nr = n;
    }
    if (mrs::failed()) return;
    Error err;
    memset(&err, 0, sizeof(err));
    int idx = addFont(path, px, nr ? ranges : nullptr, nr, err);
    if (idx < 0) {
        mrs::fail(err.id, "%s", err.msg);
        return;
    }
    if (nlhs > 0) plhs[0] = mxCreateDoubleScalar(idx);
}

void bi_PushFont(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin < 1 || nargin > 2) {
        mrs::fail("psychimgui:Usage", "PsychImGui('PushFont', idx [, sizePx])");
        return;
    }
    int idx = mrs::getInt(args[0], "idx");
    double px = (nargin == 2) ? mrs::getScalar(args[1], "sizePx") : 0.0;
    if (mrs::failed()) return;
    Error err;
    memset(&err, 0, sizeof(err));
    if (!pushFont(idx, px, err)) mrs::fail(err.id, "%s", err.msg);
}

void bi_PopFont(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    (void)args;
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('PopFont') takes no arguments.");
        return;
    }
    popFont();
}

void bi_SetGlobalScale(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin != 1) {
        mrs::fail("psychimgui:Usage", "PsychImGui('SetGlobalScale', s)");
        return;
    }
    double s = mrs::getScalar(args[0], "s");
    if (mrs::failed()) return;
    if (!(s > 0.0)) {
        mrs::fail("psychimgui:Range", "SetGlobalScale needs a positive scale, got %g.", s);
        return;
    }
    setGlobalScale(s);
}

void bi_StyleColorsDark(int, mxArray**, int nargin, const mxArray**) {
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('StyleColorsDark') takes no arguments.");
        return;
    }
    styleColors(0);
}
void bi_StyleColorsLight(int, mxArray**, int nargin, const mxArray**) {
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('StyleColorsLight') takes no arguments.");
        return;
    }
    styleColors(1);
}
void bi_StyleColorsClassic(int, mxArray**, int nargin, const mxArray**) {
    if (nargin != 0) {
        mrs::fail("psychimgui:Usage", "PsychImGui('StyleColorsClassic') takes no arguments.");
        return;
    }
    styleColors(2);
}

void bi_ShowDemoWindow(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    bool open = true;
    bool has = (nargin >= 1) && !mxIsEmpty(args[0]);
    if (nargin > 1) {
        mrs::fail("psychimgui:Usage", "PsychImGui('ShowDemoWindow' [, open])");
        return;
    }
    if (has) open = mrs::getBool(args[0], "open");
    if (mrs::failed()) return;
    ImGui::ShowDemoWindow(has ? &open : nullptr);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(open);
}

void bi_ShowMetricsWindow(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    bool open = true;
    bool has = (nargin >= 1) && !mxIsEmpty(args[0]);
    if (nargin > 1) {
        mrs::fail("psychimgui:Usage", "PsychImGui('ShowMetricsWindow' [, open])");
        return;
    }
    if (has) open = mrs::getBool(args[0], "open");
    if (mrs::failed()) return;
    ImGui::ShowMetricsWindow(has ? &open : nullptr);
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(open);
}

}  // namespace pig

// ================================================================ dispatch ==

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[]) {
    using namespace pig;

    mrs::clear();
    assertClear();

    if (nrhs == 0) {
        print_commands();
        return;
    }

    int op = -1;
    char name[64];
    name[0] = 0;

    // Fast path: a numeric scalar first argument is an opcode, so no strcmp runs.
    if (!mxIsChar(prhs[0])) {
        if (!mxIsNumeric(prhs[0]) || mxGetNumberOfElements(prhs[0]) != 1) {
            raise("psychimgui:Usage",
                  "The first argument must be a subcommand name or a numeric opcode.");
            return;
        }
        double d = mxGetScalar(prhs[0]);
        op = (int)d;
        if (d != (double)op || op < 0 || op >= kTableCount) {
            raise("psychimgui:UnknownCommand", "Opcode out of range.");
            return;
        }
    } else {
        if (mxGetString(prhs[0], name, sizeof(name)) != 0) {
            raise("psychimgui:UnknownCommand", "Subcommand name is too long.");
            return;
        }
        size_t len = strlen(name);
        if (len > 1 && name[len - 1] == '?') {
            name[len - 1] = 0;
            int i = find_op(name);
            if (i < 0) {
                mexPrintf("PsychImGui: no subcommand named '%s'.\n", name);
                return;
            }
            mexPrintf("  %s\n", kTable[i].sig);
            return;
        }
        op = find_op(name);
        if (op < 0) {
            char msg[160];
            snprintf(msg, sizeof(msg),
                     "Unknown subcommand '%s'. Call PsychImGui with no arguments for the list.",
                     name);
            raise("psychimgui:UnknownCommand", msg);
            return;
        }
    }

    const Entry& e = kTable[op];
    if (e.flags & kEntryUnavailable) {
        raise("psychimgui:UnknownCommand", "This subcommand is not compiled into this build.");
        return;
    }
    if ((e.flags & kEntryNeedsInit) && !isInit()) {
        char msg[160];
        snprintf(msg, sizeof(msg),
                 "PsychImGui('%s') needs PsychImGui('Init', ...) first.", e.name);
        raise("psychimgui:NotInit", msg);
        return;
    }
    if ((e.flags & kEntryNeedsGL) && renderer() == Renderer::OpenGL3 && !glContextCurrent()) {
        char msg[220];
        snprintf(msg, sizeof(msg),
                 "PsychImGui('%s') needs a current OpenGL context. Call it between "
                 "Screen('BeginOpenGL', win) and Screen('EndOpenGL', win).",
                 e.name);
        raise("psychimgui:NoGLContext", msg);
        return;
    }

#if PSYCHIMGUI_STATS
    uint64_t t0 = nowNs();
#endif
    e.fn(nlhs, plhs, nrhs - 1, prhs + 1);
#if PSYCHIMGUI_STATS
    uint64_t dt = nowNs() - t0;
    if (op < (int)(sizeof(g_stats) / sizeof(g_stats[0]))) {
        OpStats& s = g_stats[op];
        s.calls += 1;
        s.totalNs += dt;
        if (dt > s.maxNs) s.maxNs = dt;
    }
#endif

    // Raise only here, once every destructor inside the handler has run.
    if (mrs::failed()) {
        char id[64], msg[512];
        snprintf(id, sizeof(id), "%s", mrs::g_err.id);
        snprintf(msg, sizeof(msg), "%s", mrs::g_err.msg);
        mrs::clear();
        assertClear();
        raise(id, msg);
        return;
    }
    if (assertPending()) {
        Error err;
        memset(&err, 0, sizeof(err));
        assertTake(err);
        char id[64], msg[512];
        snprintf(id, sizeof(id), "%s", err.id);
        snprintf(msg, sizeof(msg), "%s", err.msg);
        raise(id, msg);
        return;
    }
}
