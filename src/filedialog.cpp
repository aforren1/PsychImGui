// FileDialog.* subcommands: ImGuiFileDialog, hand-written (SPEC.md 5.4, 14.11).
//
// ImGuiFileDialog has no cimgui-family metadata and a C++ API of std::string
// and std::map, so the generator cannot bind it. Eight subcommands cover the
// open, poll, read, close cycle. Paths cross the boundary as UTF-8 in both
// directions through the same conversions every other string uses, so a path
// outside the ASCII range survives MATLAB's UTF-16 char arrays and Octave's
// UTF-8 ones alike.
//
// Each context owns its own dialog object (pig::fileDialog), created by the
// first Open, because the dialog records the Dear ImGui frame it drew in.

#ifdef PSYCHIMGUI_FILEDIALOG
// First, because it has to define IMGUI_DEFINE_MATH_OPERATORS before
// anything includes imgui.h.
#  include "igfd_psych.h"

#  include <float.h>

#  include <exception>
#  include <map>
#  include <string>
#endif

#include <string.h>

#include "imgui_psych.h"

#include "core/psychimgui_core.h"
#include "marshal.h"
#include "mex.h"

namespace pig {

#ifdef PSYCHIMGUI_FILEDIALOG

namespace {

IGFD::FileDialog* dialog(bool create) { return (IGFD::FileDialog*)fileDialog(create); }

// ImGuiFileDialog reports some failures by throwing, for example a filter
// that is not a valid regular expression. An exception must not cross the MEX
// boundary, so each call is wrapped and the message becomes a pending error.
template <typename F>
void guarded(const char* cmd, F f) {
    try {
        f();
    } catch (const std::exception& e) {
        mrs::fail("psychimgui:Usage", "FileDialog.%s: %s", cmd, e.what());
    } catch (...) {
        mrs::fail("psychimgui:Usage", "FileDialog.%s failed inside ImGuiFileDialog.", cmd);
    }
}

bool need_frame(const char* cmd) {
    if (frameOpen()) return true;
    mrs::fail("psychimgui:Usage",
              "FileDialog.%s needs an open frame: call it between NewFrame and Render.", cmd);
    return false;
}

}  // namespace

void bi_FileDialogOpen(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin < 3 || nargin > 7) {
        mrs::usage("FileDialog.Open",
                   "PsychImGui('FileDialog.Open', key, title, filters [, path='.'] "
                   "[, fileName=''] [, maxSelection=1] [, flags=0])");
        return;
    }
    mrs::StrBuf<128> bKey, bTitle;
    mrs::StrBuf<256> bFilters;
    mrs::StrBuf<1024> bPath, bName;
    const char* key = mrs::toUtf8(args[0], "key", bKey);
    const char* title = mrs::toUtf8(args[1], "title", bTitle);
    const char* filters = mrs::toUtf8(args[2], "filters", bFilters);
    const char* path = ".";
    const char* name = "";
    int maxSel = 1;
    int flags = 0;
    if (nargin > 3 && !mxIsEmpty(args[3])) path = mrs::toUtf8(args[3], "path", bPath);
    if (nargin > 4 && !mxIsEmpty(args[4])) name = mrs::toUtf8(args[4], "fileName", bName);
    if (nargin > 5 && !mxIsEmpty(args[5])) maxSel = mrs::getInt(args[5], "maxSelection");
    if (nargin > 6 && !mxIsEmpty(args[6])) flags = (int)mrs::getFlags(args[6], "flags");
    if (mrs::failed()) return;
    if (!key[0]) {
        mrs::fail("psychimgui:Usage", "FileDialog.Open: key must not be empty.");
        return;
    }
    if (maxSel < 0) {
        mrs::fail("psychimgui:Range",
                  "FileDialog.Open: maxSelection must be 0 (no limit) or more, got %d.", maxSel);
        return;
    }
    guarded("Open", [&] {
        IGFD::FileDialogConfig cfg;
        cfg.path = path;
        cfg.fileName = name;
        cfg.countSelectionMax = maxSel;
        cfg.flags = flags;
        // An empty filter string is ImGuiFileDialog's nullptr, which makes it
        // a directory chooser.
        dialog(true)->OpenDialog(key, title, filters[0] ? filters : nullptr, cfg);
    });
}

void bi_FileDialogDisplay(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    if (nargin < 1 || nargin > 4) {
        mrs::usage("FileDialog.Display",
                   "[done, open] = PsychImGui('FileDialog.Display', key [, minSize=[0 0]] "
                   "[, maxSize=[FLT_MAX FLT_MAX]] [, windowFlags=ImGuiWindowFlags_NoCollapse])");
        return;
    }
    mrs::StrBuf<128> bKey;
    const char* key = mrs::toUtf8(args[0], "key", bKey);
    double mn[2] = {0, 0}, mx[2] = {FLT_MAX, FLT_MAX};
    int wflags = ImGuiWindowFlags_NoCollapse;
    if (nargin > 1 && !mxIsEmpty(args[1])) mrs::getVec(args[1], "minSize", mn, 2);
    if (nargin > 2 && !mxIsEmpty(args[2])) mrs::getVec(args[2], "maxSize", mx, 2);
    if (nargin > 3 && !mxIsEmpty(args[3])) wflags = (int)mrs::getFlags(args[3], "windowFlags");
    if (mrs::failed() || !need_frame("Display")) return;
    bool done = false, open = false;
    IGFD::FileDialog* d = dialog(false);
    if (d) {
        guarded("Display", [&] {
            done = d->Display(key, wflags, ImVec2((float)mn[0], (float)mn[1]),
                              ImVec2((float)mx[0], (float)mx[1]));
            open = d->IsOpened(key);
        });
    }
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(done);
    if (nlhs > 1) plhs[1] = mxCreateLogicalScalar(open);
}

void bi_FileDialogIsOk(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    if (nargin != 0) {
        mrs::usage("FileDialog.IsOk", "ok = PsychImGui('FileDialog.IsOk')");
        return;
    }
    IGFD::FileDialog* d = dialog(false);
    bool ok = false;
    if (d) guarded("IsOk", [&] { ok = d->IsOk(); });
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(ok);
}

void bi_FileDialogIsOpened(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    if (nargin > 1) {
        mrs::usage("FileDialog.IsOpened", "open = PsychImGui('FileDialog.IsOpened' [, key])");
        return;
    }
    mrs::StrBuf<128> bKey;
    const char* key = nargin == 1 ? mrs::toUtf8(args[0], "key", bKey) : nullptr;
    if (mrs::failed()) return;
    IGFD::FileDialog* d = dialog(false);
    bool open = false;
    if (d) guarded("IsOpened", [&] { open = key ? d->IsOpened(key) : d->IsOpened(); });
    if (nlhs > 0) plhs[0] = mxCreateLogicalScalar(open);
}

void bi_FileDialogGetFilePathName(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    if (nargin != 0) {
        mrs::usage("FileDialog.GetFilePathName",
                   "path = PsychImGui('FileDialog.GetFilePathName')");
        return;
    }
    IGFD::FileDialog* d = dialog(false);
    std::string out;
    if (d) guarded("GetFilePathName", [&] { out = d->GetFilePathName(); });
    if (mrs::failed()) return;
    if (nlhs > 0) plhs[0] = mrs::fromUtf8(out.c_str());
}

void bi_FileDialogGetCurrentPath(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    if (nargin != 0) {
        mrs::usage("FileDialog.GetCurrentPath", "path = PsychImGui('FileDialog.GetCurrentPath')");
        return;
    }
    IGFD::FileDialog* d = dialog(false);
    std::string out;
    if (d) guarded("GetCurrentPath", [&] { out = d->GetCurrentPath(); });
    if (mrs::failed()) return;
    if (nlhs > 0) plhs[0] = mrs::fromUtf8(out.c_str());
}

void bi_FileDialogGetSelection(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    if (nargin != 0) {
        mrs::usage("FileDialog.GetSelection", "paths = PsychImGui('FileDialog.GetSelection')");
        return;
    }
    IGFD::FileDialog* d = dialog(false);
    std::map<std::string, std::string> sel;
    if (d) guarded("GetSelection", [&] { sel = d->GetSelection(); });
    if (mrs::failed() || nlhs == 0) return;
    // The map is keyed by file name, so the paths come back sorted by name.
    mxArray* c = mxCreateCellMatrix(1, (mwSize)sel.size());
    mwIndex i = 0;
    for (const auto& kv : sel) mxSetCell(c, i++, mrs::fromUtf8(kv.second.c_str()));
    plhs[0] = c;
}

void bi_FileDialogClose(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    (void)args;
    if (nargin != 0) {
        mrs::usage("FileDialog.Close", "PsychImGui('FileDialog.Close')");
        return;
    }
    IGFD::FileDialog* d = dialog(false);
    if (d) guarded("Close", [&] { d->Close(); });
}

#else  // PSYCHIMGUI_FILEDIALOG

namespace {
void unavailable() {
    mrs::fail("psychimgui:UnknownCommand",
              "This build has ImGuiFileDialog disabled. Rebuild with "
              "-DPSYCHIMGUI_FILEDIALOG=ON.");
}
}  // namespace

void bi_FileDialogOpen(int, mxArray**, int, const mxArray**) { unavailable(); }
void bi_FileDialogDisplay(int, mxArray**, int, const mxArray**) { unavailable(); }
void bi_FileDialogIsOk(int, mxArray**, int, const mxArray**) { unavailable(); }
void bi_FileDialogIsOpened(int, mxArray**, int, const mxArray**) { unavailable(); }
void bi_FileDialogGetFilePathName(int, mxArray**, int, const mxArray**) { unavailable(); }
void bi_FileDialogGetCurrentPath(int, mxArray**, int, const mxArray**) { unavailable(); }
void bi_FileDialogGetSelection(int, mxArray**, int, const mxArray**) { unavailable(); }
void bi_FileDialogClose(int, mxArray**, int, const mxArray**) { unavailable(); }

#endif  // PSYCHIMGUI_FILEDIALOG

}  // namespace pig
