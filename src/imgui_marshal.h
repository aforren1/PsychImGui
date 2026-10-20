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

// A named key or a single modifier. ImGui asserts this and then indexes
// KeysData by the key, and the assert returns (SPEC.md 8.3).
inline ImGuiKey getKey(const mxArray* a, const char* argname) {
    double v = getFlags(a, argname);
    if (failed()) return ImGuiKey_None;
    int k = (int)v;
    bool named = k >= ImGuiKey_NamedKey_BEGIN && k < ImGuiKey_NamedKey_END;
    bool mod = k == ImGuiMod_Ctrl || k == ImGuiMod_Shift || k == ImGuiMod_Alt ||
               k == ImGuiMod_Super;
    if (v != (double)k || !(named || mod)) {
        fail("psychimgui:Range",
             "Argument '%s' (%g) is not a named key or a single ImGuiMod_ modifier.", argname,
             v);
        return ImGuiKey_None;
    }
    return (ImGuiKey)k;
}

// A key chord: one named key with any modifiers, or one modifier alone.
// IsKeyChordPressed and Shortcut index KeysData by the key part, like getKey.
inline ImGuiKeyChord getKeyChord(const mxArray* a, const char* argname) {
    double v = getFlags(a, argname);
    if (failed()) return 0;
    int c = (int)v;
    int key = c & ~ImGuiMod_Mask_;
    int mods = c & ImGuiMod_Mask_;
    bool named = key >= ImGuiKey_NamedKey_BEGIN && key < ImGuiKey_NamedKey_END;
    bool oneMod = key == ImGuiKey_None &&
                  (mods == ImGuiMod_Ctrl || mods == ImGuiMod_Shift || mods == ImGuiMod_Alt ||
                   mods == ImGuiMod_Super);
    if (v != (double)c || !(named || oneMod)) {
        fail("psychimgui:Range",
             "Argument '%s' (%g) is not a named key with optional ImGuiMod_ modifiers, "
             "or a single modifier.",
             argname, v);
        return 0;
    }
    return (ImGuiKeyChord)c;
}

// A column of the current table, -1 meaning the current column. Dear ImGui
// indexes its column array with it after an assert that returns (SPEC.md 8.3).
inline bool checkTableColumn(int column, const char* cmd) {
    if (failed()) return false;
    int n = ImGui::TableGetColumnCount();
    if (n == 0) {
        fail("psychimgui:Usage", "%s needs an open table: call it between BeginTable and EndTable.",
             cmd);
        return false;
    }
    int c = column < 0 ? ImGui::TableGetColumnIndex() : column;
    if (c < 0 || c >= n) {
        fail("psychimgui:Range",
             "%s: column %d is not a column of this table, or -1 with a current cell.", cmd,
             column);
        return false;
    }
    return true;
}

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

// An Nx4 or Nx3 colormap matrix as ImVec4, for ImPlot and ImPlot3D. Colormaps are set up once, not per
// frame, so the copy here is not on the hot path.
struct Vec4Vec {
    ImVec4 inl[64];
    ImVec4* heap;
    int n;
    Vec4Vec() : heap(nullptr), n(0) {}
    ~Vec4Vec() {
        if (heap) free(heap);
    }
    Vec4Vec(const Vec4Vec&) = delete;
    Vec4Vec& operator=(const Vec4Vec&) = delete;
};

inline const ImVec4* getVec4Array(const mxArray* a, const char* argname, Vec4Vec& v) {
    if (failed()) return nullptr;
    if (!a || !mxIsDouble(a) || mxIsComplex(a)) {
        fail("psychimgui:Type", "Argument '%s' must be a real Nx4 or Nx3 double matrix.",
             argname);
        return nullptr;
    }
    int rows = (int)mxGetM(a);
    int cols = (int)mxGetN(a);
    if (cols != 3 && cols != 4) {
        fail("psychimgui:Type", "Argument '%s' must have 3 or 4 columns, not %d.", argname,
             cols);
        return nullptr;
    }
    ImVec4* d = v.inl;
    if (rows > (int)(sizeof(v.inl) / sizeof(v.inl[0]))) {
        v.heap = (ImVec4*)malloc((size_t)rows * sizeof(ImVec4));
        if (!v.heap) {
            fail("psychimgui:Usage", "Out of memory converting argument '%s'.", argname);
            return nullptr;
        }
        d = v.heap;
    }
    const double* p = mxGetPr(a);
    for (int i = 0; i < rows; ++i) {
        d[i] = ImVec4((float)p[i], (float)p[rows + i], (float)p[2 * rows + i],
                      cols == 4 ? (float)p[3 * rows + i] : 1.0f);
    }
    v.n = rows;
    return d;
}

}  // namespace mrs
