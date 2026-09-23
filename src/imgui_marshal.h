// Marshaling rules that need Dear ImGui types: packed colors, point arrays,
// draw list handles, and texture descriptors (SPEC.md sections 5.6, 5.7, 7.3).
//
// Kept apart from marshal.h, which stays free of imgui.h so the generic rules
// read on their own. Include imgui_psych.h and marshal.h first. Like marshal.h,
// nothing here raises; failures go to the pending error.
#pragma once

#include "core/psychimgui_core.h"
#include "marshal.h"

namespace mrs {

// An ImU32 color: a 1x4 double [r g b a] in 0 to 1, the same rule as ImVec4
// colors, or a double scalar that is already packed.
inline ImU32 getColorU32(const mxArray* a, const char* argname) {
    if (failed()) return 0;
    if (a && (mxIsNumeric(a) || mxIsLogical(a)) && !mxIsComplex(a) &&
        mxGetNumberOfElements(a) == 1)
        return (ImU32)getIntRanged(a, argname, 0.0, 4294967295.0);
    double t[4] = {0, 0, 0, 1};
    if (!a || mxGetNumberOfElements(a) != 4) {
        fail("psychimgui:Type",
             "Argument '%s' must be a 1x4 color [r g b a] in 0 to 1, or a packed scalar.",
             argname);
        return 0;
    }
    getVec(a, argname, t, 4);
    return ImGui::ColorConvertFloat4ToU32(
        ImVec4((float)t[0], (float)t[1], (float)t[2], (float)t[3]));
}

// An Nx2 point list. Up to 128 points stay on the stack, which covers the
// polylines a GUI overlay draws per frame without touching the heap.
struct Vec2Vec {
    ImVec2 inl[128];
    ImVec2* heap;
    int n;
    Vec2Vec() : heap(nullptr), n(0) {}
    ~Vec2Vec() {
        if (heap) free(heap);
    }
    Vec2Vec(const Vec2Vec&) = delete;
    Vec2Vec& operator=(const Vec2Vec&) = delete;
};

inline const ImVec2* getVec2Array(const mxArray* a, const char* argname, Vec2Vec& v) {
    if (failed()) return nullptr;
    if (!a || !mxIsDouble(a) || mxIsComplex(a) || mxGetNumberOfDimensions(a) != 2 ||
        (mxGetN(a) != 2 && !mxIsEmpty(a))) {
        fail("psychimgui:Type", "Argument '%s' must be an Nx2 real double array [x y].",
             argname);
        return nullptr;
    }
    int n = (int)mxGetM(a);
    ImVec2* d = v.inl;
    if (n > (int)(sizeof(v.inl) / sizeof(v.inl[0]))) {
        v.heap = (ImVec2*)malloc((size_t)n * sizeof(ImVec2));
        if (!v.heap) {
            fail("psychimgui:Usage", "Out of memory converting argument '%s'.", argname);
            return nullptr;
        }
        d = v.heap;
    }
    // Column major: all x values first, then all y values.
    const double* p = mxGetPr(a);
    for (int i = 0; i < n; ++i) d[i] = ImVec2((float)p[i], (float)p[n + i]);
    v.n = n;
    return d;
}

// A draw list handle from GetWindowDrawList and friends. See
// pig::drawListHandle for why a stale handle can never reach a pointer.
inline ImDrawList* getDrawList(const mxArray* a, const char* argname, int* slot) {
    *slot = -1;
    if (failed()) return nullptr;
    if (!a || !mxIsDouble(a) || mxIsComplex(a) || mxGetNumberOfElements(a) != 1) {
        fail("psychimgui:Type",
             "Argument '%s' must be a draw list handle from GetWindowDrawList, "
             "GetBackgroundDrawList, or GetForegroundDrawList.",
             argname);
        return nullptr;
    }
    ImDrawList* dl = pig::drawListFromHandle(mxGetScalar(a), slot);
    if (!dl)
        fail("psychimgui:InvalidHandle",
             "Argument '%s' is not a live draw list handle. A handle is valid only "
             "between NewFrame and Render of the frame that returned it; get a new "
             "one every frame.",
             argname);
    return dl;
}

inline double drawListOut(ImDrawList* dl) {
    double h = pig::drawListHandle(dl);
    if (h == 0.0)
        fail("psychimgui:Range",
             "Too many distinct draw lists in one frame (the table holds 256).");
    return h;
}

}  // namespace mrs
