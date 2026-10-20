// Style structs as MATLAB structs (SPEC.md section 14.16), shared by
// GetStyle and SetStyle of Dear ImGui, ImPlot, and ImPlot3D. The field
// tables are generated from the cimgui metadata into gen_style_*.h, so a
// field added or renamed upstream follows without a hand edit.
#pragma once

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "imgui_psych.h"
#include "marshal.h"
#include "mex.h"

namespace pig {

enum StyleKind : uint8_t {
    kStyleFloat,
    kStyleVec2,
    kStyleBool,
    kStyleInt,
    kStyleEnum,      // int with the range lo to hi
    kStyleFlags,     // int, by number or by names as other flags arguments
    kStyleColormap,  // int, below the colormap count of the library
};

struct StyleField {
    const char* name;
    uint32_t offset;
    uint8_t kind;
    uint8_t scaled;  // ImGuiStyle::ScaleAllSizes multiplies it
    int16_t lo, hi;
};

struct StyleDesc {
    const char* cmd;
    const StyleField* fields;
    int nFields;
    uint32_t colorsOffset;
    const char* const* colors;  // without the ImGuiCol_ style prefix
    int nColors;
    int (*colormapCount)();
};

constexpr int kMaxStyleFields = 128;

inline const StyleField* styleField(const StyleDesc& d, const char* name) {
    for (int i = 0; i < d.nFields; ++i)
        if (strcmp(d.fields[i].name, name) == 0) return &d.fields[i];
    return nullptr;
}

inline mxArray* styleToStruct(const StyleDesc& d, const void* style) {
    const char* names[kMaxStyleFields + 1];
    for (int i = 0; i < d.nFields; ++i) names[i] = d.fields[i].name;
    names[d.nFields] = "Colors";
    mxArray* s = mxCreateStructMatrix(1, 1, d.nFields + 1, names);
    const char* base = (const char*)style;
    for (int i = 0; i < d.nFields; ++i) {
        const StyleField& f = d.fields[i];
        const char* p = base + f.offset;
        mxArray* v = nullptr;
        switch (f.kind) {
        case kStyleFloat: v = mxCreateDoubleScalar(*(const float*)p); break;
        case kStyleVec2: {
            const ImVec2& q = *(const ImVec2*)p;
            double t[2] = {q.x, q.y};
            v = mrs::outVec(t, 2);
            break;
        }
        case kStyleBool: v = mxCreateLogicalScalar(*(const bool*)p); break;
        default: v = mxCreateDoubleScalar(*(const int*)p); break;
        }
        mxSetFieldByNumber(s, 0, i, v);
    }
    mxArray* c = mxCreateStructMatrix(1, 1, d.nColors, (const char**)d.colors);
    const ImVec4* col = (const ImVec4*)(base + d.colorsOffset);
    for (int i = 0; i < d.nColors; ++i) {
        double t[4] = {col[i].x, col[i].y, col[i].z, col[i].w};
        mxSetFieldByNumber(c, 0, i, mrs::outVec(t, 4));
    }
    mxSetFieldByNumber(s, 0, d.nFields, c);
    return s;
}

// Writes every field of the MATLAB struct s into style. The caller passes a
// copy and keeps it only when this returns true, so a bad field changes
// nothing. An unknown name is an error: a misspelled field would otherwise
// leave the theme silently unchanged.
inline bool styleFromStruct(const StyleDesc& d, const mxArray* s, void* style) {
    if (mrs::failed()) return false;
    if (!s || !mxIsStruct(s) || mxGetNumberOfElements(s) != 1) {
        mrs::fail("psychimgui:Type", "%s: the style must be one struct, as GetStyle returns.",
                  d.cmd);
        return false;
    }
    char* base = (char*)style;
    int nf = mxGetNumberOfFields(s);
    for (int i = 0; i < nf; ++i) {
        const char* name = mxGetFieldNameByNumber(s, i);
        const mxArray* v = mxGetFieldByNumber(s, 0, i);
        if (strcmp(name, "Colors") == 0) {
            if (!v || !mxIsStruct(v) || mxGetNumberOfElements(v) != 1) {
                mrs::fail("psychimgui:Type", "%s: Colors must be one struct of 1x4 colors.",
                          d.cmd);
                return false;
            }
            ImVec4* col = (ImVec4*)(base + d.colorsOffset);
            int nc = mxGetNumberOfFields(v);
            for (int j = 0; j < nc; ++j) {
                const char* cn = mxGetFieldNameByNumber(v, j);
                int k = 0;
                while (k < d.nColors && strcmp(d.colors[k], cn) != 0) ++k;
                if (k == d.nColors) {
                    mrs::fail("psychimgui:Usage", "%s: unknown color '%s'.", d.cmd, cn);
                    return false;
                }
                double t[4] = {0, 0, 0, 1};
                mrs::getVec(mxGetFieldByNumber(v, 0, j), cn, t, 4);
                if (mrs::failed()) return false;
                col[k] = ImVec4((float)t[0], (float)t[1], (float)t[2], (float)t[3]);
            }
            continue;
        }
        const StyleField* f = styleField(d, name);
        if (!f) {
            mrs::fail("psychimgui:Usage", "%s: unknown style field '%s'.", d.cmd, name);
            return false;
        }
        char* p = base + f->offset;
        switch (f->kind) {
        case kStyleFloat: {
            double x = mrs::getScalar(v, name);
            if (!mrs::failed() && x != x) {
                mrs::fail("psychimgui:Range", "%s: %s must not be NaN.", d.cmd, name);
                return false;
            }
            *(float*)p = (float)x;
            break;
        }
        case kStyleVec2: {
            double t[2] = {0, 0};
            mrs::getVec(v, name, t, 2);
            if (!mrs::failed() && (t[0] != t[0] || t[1] != t[1])) {
                mrs::fail("psychimgui:Range", "%s: %s must not be NaN.", d.cmd, name);
                return false;
            }
            *(ImVec2*)p = ImVec2((float)t[0], (float)t[1]);
            break;
        }
        case kStyleBool: *(bool*)p = mrs::getBool(v, name); break;
        case kStyleInt: *(int*)p = mrs::getInt(v, name); break;
        case kStyleEnum: *(int*)p = (int)mrs::getEnumRanged(v, name, f->lo, f->hi); break;
        case kStyleFlags: *(int*)p = (int)mrs::getFlags(v, name); break;
        case kStyleColormap: {
            int n = d.colormapCount ? d.colormapCount() : 0;
            int c = mrs::getInt(v, name);
            if (!mrs::failed() && (c < 0 || c >= n)) {
                mrs::fail("psychimgui:Range", "%s: %s %d is not a colormap index in [0, %d].",
                          d.cmd, name, c, n - 1);
                return false;
            }
            *(int*)p = c;
            break;
        }
        }
        if (mrs::failed()) return false;
    }
    return true;
}

}  // namespace pig
