// ImPlot specific marshaling helpers (SPEC.md section 7.6).
//
// ImPlot's data functions are C++ templates over the element type, so the
// generated handlers call them with the mxArray data pointer straight from
// mxGetData. Nothing is copied: the pointer only has to stay valid for the
// duration of the call, which is all ImPlot needs, because it copies what it
// draws into the draw list.
#pragma once

#include "implot.h"
#include "marshal.h"

namespace mrs {

// A data argument: real, numeric, and of a class ImPlot has an instantiation
// for. Logical is rejected on purpose, per the specification.
inline bool isPlotData(const mxArray* a) {
    if (!a || mxIsComplex(a) || mxIsSparse(a)) return false;
    switch (mxGetClassID(a)) {
        case mxDOUBLE_CLASS:
        case mxSINGLE_CLASS:
        case mxINT8_CLASS:
        case mxUINT8_CLASS:
        case mxINT16_CLASS:
        case mxUINT16_CLASS:
        case mxINT32_CLASS:
        case mxUINT32_CLASS:
        case mxINT64_CLASS:
        case mxUINT64_CLASS:
            return true;
        default:
            return false;
    }
}

// How many leading arguments form one data set. Arguments belong to the same
// data set when they share a class and an element count, which is what tells
// PlotShaded(xs, ys, yref) from PlotShaded(xs, ys1, ys2).
inline int dataArgCount(const mxArray** args, int nargin, int first, int maxN) {
    if (first >= nargin || !isPlotData(args[first])) return 0;
    mxClassID c0 = mxGetClassID(args[first]);
    size_t n0 = mxGetNumberOfElements(args[first]);
    int n = 1;
    while (n < maxN && first + n < nargin) {
        const mxArray* a = args[first + n];
        if (!isPlotData(a) || mxGetClassID(a) != c0 || mxGetNumberOfElements(a) != n0)
            break;
        ++n;
    }
    return n;
}

// Check a data set and report its class and element count.
inline mxClassID checkData(const mxArray** args, int first, int n, const char* cmd,
                           int* count) {
    *count = 0;
    if (failed()) return mxUNKNOWN_CLASS;
    for (int i = 0; i < n; ++i) {
        const mxArray* a = args[first + i];
        if (!a || mxIsLogical(a)) {
            fail("psychimgui:Type",
                 "%s: logical data is not supported. Convert it with double().", cmd);
            return mxUNKNOWN_CLASS;
        }
        if (!isPlotData(a)) {
            fail("psychimgui:Type", "%s: argument %d must be a real numeric array.", cmd,
                 first + i + 1);
            return mxUNKNOWN_CLASS;
        }
        if (mxGetClassID(a) != mxGetClassID(args[first]) ||
            mxGetNumberOfElements(a) != mxGetNumberOfElements(args[first])) {
            fail("psychimgui:Type",
                 "%s: the data arrays must share one class and one element count.", cmd);
            return mxUNKNOWN_CLASS;
        }
    }
    *count = (int)mxGetNumberOfElements(args[first]);
    return mxGetClassID(args[first]);
}

// An Nx4 or Nx3 colormap matrix as ImVec4. Colormaps are set up once, not per
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

// ImPlotPoint and ImPlotRange are a 1x2 double on the MATLAB side, ImPlotRect a
// 1x4 [xMin xMax yMin yMax].
template <typename V>
inline V getPoint2(const mxArray* a, const char* argname) {
    double t[2] = {0, 0};
    getVec(a, argname, t, 2);
    return V(t[0], t[1]);
}

template <typename V>
inline V getRect4(const mxArray* a, const char* argname) {
    double t[4] = {0, 0, 0, 0};
    getVec(a, argname, t, 4);
    return V(t[0], t[1], t[2], t[3]);
}

// ------------------------------------------------------------- ImPlotSpec --

inline bool isSpecName(const char* s) {
    static const char* kNames[] = {"LineColor",  "LineWeight",      "FillColor",
                                   "FillAlpha",  "Marker",          "MarkerSize",
                                   "MarkerLineColor", "MarkerFillColor", "Size",
                                   "Offset",     "Stride",          "Flags"};
    for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); ++i)
        if (strcmp(s, kNames[i]) == 0) return true;
    return false;
}

// Where the trailing ImPlotSpec begins. Optional positional arguments come
// first, so the scan stops at the first struct or at the first char that names
// a spec property. A format string such as '%.1f' is not a property name, which
// is what keeps PlotHeatmap's labelFmt unambiguous.
inline int specStart(const mxArray** args, int nargin, int firstOpt) {
    for (int i = firstOpt; i < nargin; ++i) {
        const mxArray* a = args[i];
        if (mxIsStruct(a)) return i;
        if (mxIsChar(a)) {
            char buf[32];
            if (mxGetString(a, buf, sizeof(buf)) == 0 && isSpecName(buf)) return i;
        }
    }
    return nargin;
}

inline ImVec4 specColor(const mxArray* a, const char* field) {
    if (mxIsChar(a)) {
        char buf[16];
        if (mxGetString(a, buf, sizeof(buf)) == 0 && strcmp(buf, "Auto") == 0)
            return IMPLOT_AUTO_COL;
        fail("psychimgui:Usage", "ImPlotSpec.%s accepts a 1x4 color or 'Auto'.", field);
        return IMPLOT_AUTO_COL;
    }
    double t[4] = {0, 0, 0, 1};
    getVec(a, field, t, 4);
    return ImVec4((float)t[0], (float)t[1], (float)t[2], (float)t[3]);
}

inline int specMarker(const mxArray* a) {
    if (!mxIsChar(a)) return (int)getScalar(a, "Marker");
    StrBuf<64> b;
    const char* n = toUtf8(a, "Marker", b);
    if (failed()) return 0;
    double v = 0.0;
    if (enum_lookup(n, &v)) return (int)v;
    char full[80];
    snprintf(full, sizeof(full), "ImPlotMarker_%s", n);
    if (enum_lookup(full, &v)) return (int)v;
    fail("psychimgui:Usage", "ImPlotSpec.Marker: unknown marker name '%s'.", n);
    return 0;
}

// One (name, value) pair. elemSize converts Stride from elements to bytes,
// because ImPlot counts a stride in bytes and MATLAB counts in elements.
inline void specField(ImPlotSpec& spec, const char* name, const mxArray* v,
                      size_t elemSize) {
    if (strcmp(name, "LineColor") == 0) spec.LineColor = specColor(v, "LineColor");
    else if (strcmp(name, "FillColor") == 0) spec.FillColor = specColor(v, "FillColor");
    else if (strcmp(name, "MarkerLineColor") == 0)
        spec.MarkerLineColor = specColor(v, "MarkerLineColor");
    else if (strcmp(name, "MarkerFillColor") == 0)
        spec.MarkerFillColor = specColor(v, "MarkerFillColor");
    else if (strcmp(name, "LineWeight") == 0)
        spec.LineWeight = (float)getScalar(v, "LineWeight");
    else if (strcmp(name, "FillAlpha") == 0)
        spec.FillAlpha = (float)getScalar(v, "FillAlpha");
    else if (strcmp(name, "MarkerSize") == 0)
        spec.MarkerSize = (float)getScalar(v, "MarkerSize");
    else if (strcmp(name, "Size") == 0) spec.Size = (float)getScalar(v, "Size");
    else if (strcmp(name, "Marker") == 0) spec.Marker = (ImPlotMarker)specMarker(v);
    else if (strcmp(name, "Offset") == 0) spec.Offset = getInt(v, "Offset");
    else if (strcmp(name, "Stride") == 0)
        spec.Stride = (int)(getInt(v, "Stride") * (int)elemSize);
    else if (strcmp(name, "Flags") == 0)
        spec.Flags = (ImPlotItemFlags)getFlags(v, "Flags");
    else
        fail("psychimgui:Usage", "ImPlotSpec has no property named '%s'.", name);
}

// Trailing name-value pairs, or one struct with the same field names.
inline void getSpec(const mxArray** args, int nargin, int at, ImPlotSpec& spec,
                    size_t elemSize) {
    if (failed() || at >= nargin) return;
    if (mxIsStruct(args[at])) {
        if (nargin - at != 1) {
            fail("psychimgui:Usage",
                 "An ImPlotSpec struct must be the last argument.");
            return;
        }
        int nf = mxGetNumberOfFields(args[at]);
        for (int i = 0; i < nf; ++i) {
            const char* nm = mxGetFieldNameByNumber(args[at], i);
            const mxArray* v = mxGetFieldByNumber(args[at], 0, i);
            if (v && !mxIsEmpty(v)) specField(spec, nm, v, elemSize);
            if (failed()) return;
        }
        return;
    }
    if (((nargin - at) % 2) != 0) {
        fail("psychimgui:Usage",
             "The ImPlotSpec arguments must be name and value pairs.");
        return;
    }
    for (int i = at; i + 1 < nargin; i += 2) {
        char name[32];
        if (!mxIsChar(args[i]) || mxGetString(args[i], name, sizeof(name)) != 0) {
            fail("psychimgui:Usage",
                 "Argument %d must be an ImPlotSpec property name.", i + 1);
            return;
        }
        specField(spec, name, args[i + 1], elemSize);
        if (failed()) return;
    }
}

}  // namespace mrs
