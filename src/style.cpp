// Dear ImGui themes: GetStyle, SetStyle, and SetGlobalScale (SPEC.md 14.16).
//
// Each context keeps a base style without the global scale. The live style
// is the base with the 50 sizes that ImGuiStyle::ScaleAllSizes knows
// multiplied by the scale. Scaling the live style in place, as ScaleAllSizes
// does, would compound over two SetGlobalScale calls and lose precision to
// its truncation, so every change goes base first, then live.
//
// ShowStyleEditor edits the live style directly. sync() folds such edits back
// into the base before anything reads or rebuilds it: a scaled field whose
// live value is no longer the base value scaled was edited, and its new base
// is the live value divided by the scale.

#include <float.h>

#include "imgui_psych.h"

#include "imgui_internal.h"

#include "core/psychimgui_core.h"
#include "gen_style_imgui.h"
#include "marshal.h"
#include "mex.h"

namespace pig {

namespace {

// ScaleAllSizes truncates every product, and leaves 0, a negative size, and
// FLT_MAX ("no limit") alone where it can meet them.
float scale_size(float v, float s) {
    return (v > 0.0f && v != FLT_MAX) ? ImTrunc(v * s) : v;
}

float unscale_size(float live, float base, float s) {
    return live == scale_size(base, s) ? base : live / s;
}

size_t field_size(uint8_t kind) {
    switch (kind) {
    case kStyleFloat: return sizeof(float);
    case kStyleVec2: return sizeof(ImVec2);
    case kStyleBool: return sizeof(bool);
    default: return sizeof(int);
    }
}

// A pushed style variable, color, or font is in the live style until its pop
// restores the value saved at the push. Reading it into the base would make a
// temporary value permanent, and rebuilding under it would be undone by the
// pop, so these calls wait for the stacks to empty. NewFrame pushes the
// default font, so one font entry is the empty state inside a frame.
bool stacks_empty(const char* cmd) {
    ImGuiContext& g = *GImGui;
    if (g.StyleVarStack.Size == 0 && g.ColorStack.Size == 0 && g.FontStack.Size <= 1)
        return true;
    mrs::fail("psychimgui:Usage",
              "%s: pop every PushStyleVar, PushStyleColor, and PushFont first.", cmd);
    return false;
}

void sync() {
    char* b = (char*)styleBase();
    const char* l = (const char*)&ImGui::GetStyle();
    float s = styleScale();
    const StyleDesc& d = kImGuiStyleDesc;
    for (int i = 0; i < d.nFields; ++i) {
        const StyleField& f = d.fields[i];
        if (!f.scaled) {
            memcpy(b + f.offset, l + f.offset, field_size(f.kind));
            continue;
        }
        float* bp = (float*)(b + f.offset);
        const float* lp = (const float*)(l + f.offset);
        int n = f.kind == kStyleVec2 ? 2 : 1;
        for (int k = 0; k < n; ++k) bp[k] = unscale_size(lp[k], bp[k], s);
    }
    memcpy(b + d.colorsOffset, l + d.colorsOffset, sizeof(ImGuiStyle::Colors));
}

void apply() {
    const char* b = (const char*)styleBase();
    ImGuiStyle& live = ImGui::GetStyle();
    char* l = (char*)&live;
    float s = styleScale();
    const StyleDesc& d = kImGuiStyleDesc;
    for (int i = 0; i < d.nFields; ++i) {
        const StyleField& f = d.fields[i];
        if (!f.scaled) {
            memcpy(l + f.offset, b + f.offset, field_size(f.kind));
            continue;
        }
        const float* bp = (const float*)(b + f.offset);
        float* lp = (float*)(l + f.offset);
        int n = f.kind == kStyleVec2 ? 2 : 1;
        for (int k = 0; k < n; ++k) lp[k] = scale_size(bp[k], s);
    }
    memcpy(l + d.colorsOffset, b + d.colorsOffset, sizeof(ImGuiStyle::Colors));
    live.FontScaleMain = s;
    live._MainScale = s;
    // Dear ImGui sets FontSizeBase from the current font whenever the font
    // changes inside a frame; the next NewFrame takes this one instead.
    if (live.FontSizeBase > 0.0f) live._NextFrameFontSizeBase = live.FontSizeBase;
}

}  // namespace

void bi_GetStyle(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    if (nargin != 0) {
        mrs::usage("GetStyle", "s = PsychImGui('GetStyle')");
        return;
    }
    if (!stacks_empty("GetStyle")) return;
    sync();
    if (nlhs > 0) plhs[0] = styleToStruct(kImGuiStyleDesc, styleBase());
}

void bi_SetStyle(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin != 1) {
        mrs::usage("SetStyle", "PsychImGui('SetStyle', s)");
        return;
    }
    if (!stacks_empty("SetStyle")) return;
    sync();
    ImGuiStyle next = *styleBase();
    if (!styleFromStruct(kImGuiStyleDesc, args[0], &next)) return;
    *styleBase() = next;
    apply();
}

void bi_SetGlobalScale(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin != 1) {
        mrs::usage("SetGlobalScale", "PsychImGui('SetGlobalScale', s)");
        return;
    }
    double s = mrs::getScalar(args[0], "s");
    if (mrs::failed()) return;
    if (!(s > 0.0)) {
        mrs::fail("psychimgui:Range", "SetGlobalScale needs a positive scale, got %g.", s);
        return;
    }
    if (!stacks_empty("SetGlobalScale")) return;
    sync();
    setStyleScale((float)s);
    apply();
}

}  // namespace pig
