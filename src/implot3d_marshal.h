// ImPlot3D specific marshaling helpers (SPEC.md sections 7.6 and 14.11).
//
// The data arrays follow the ImPlot rules of plotdata_marshal.h. What is
// different: ImPlot3DSpec has no Size field and its own marker enum, and
// PlotMesh takes a triangle index list, which MATLAB writes as the Faces
// matrix of patch.
#pragma once

#include "implot3d.h"
#include "marshal.h"
#include "plotdata_marshal.h"

// From implot3d_internal.h, declared for the reason implot_marshal.h gives.
struct ImPlot3DPlot;
namespace ImPlot3D {
IMPLOT3D_API ImPlot3DPlot* GetCurrentPlot();
}

namespace mrs {

// True between ImPlot3D.BeginPlot and ImPlot3D.EndPlot.
inline bool implot3dPlotOpen() {
    return ImPlot3D::GetCurrentContext() != nullptr && ImPlot3D::GetCurrentPlot() != nullptr;
}

inline bool isSpec3DName(const char* s) {
    static const char* kNames[] = {"LineColor",  "LineWeight",      "FillColor",
                                   "FillAlpha",  "Marker",          "MarkerSize",
                                   "MarkerLineColor", "MarkerFillColor", "Offset",
                                   "Stride",     "Flags"};
    for (size_t i = 0; i < sizeof(kNames) / sizeof(kNames[0]); ++i)
        if (strcmp(s, kNames[i]) == 0) return true;
    return false;
}

// Where the trailing ImPlot3DSpec begins, by the rule of ImPlot's specStart.
inline int specStart3D(const mxArray** args, int nargin, int firstOpt) {
    for (int i = firstOpt; i < nargin; ++i) {
        const mxArray* a = args[i];
        if (mxIsStruct(a)) return i;
        if (mxIsChar(a)) {
            char buf[32];
            if (mxGetString(a, buf, sizeof(buf)) == 0 && isSpec3DName(buf)) return i;
        }
    }
    return nargin;
}

inline ImVec4 spec3DColor(const mxArray* a, const char* field) {
    if (mxIsChar(a)) {
        char buf[16];
        if (mxGetString(a, buf, sizeof(buf)) == 0 && strcmp(buf, "Auto") == 0)
            return IMPLOT3D_AUTO_COL;
        fail("psychimgui:Usage", "ImPlot3DSpec.%s accepts a 1x4 color or 'Auto'.", field);
        return IMPLOT3D_AUTO_COL;
    }
    double t[4] = {0, 0, 0, 1};
    getVec(a, field, t, 4);
    return ImVec4((float)t[0], (float)t[1], (float)t[2], (float)t[3]);
}

inline int spec3DMarker(const mxArray* a) {
    if (!mxIsChar(a)) return (int)getScalar(a, "Marker");
    StrBuf<64> b;
    const char* n = toUtf8(a, "Marker", b);
    if (failed()) return 0;
    double v = 0.0;
    if (strncmp(n, "ImPlot3DMarker_", 15) == 0 && enum_lookup(n, &v)) return (int)v;
    char full[80];
    snprintf(full, sizeof(full), "ImPlot3DMarker_%s", n);
    if (enum_lookup(full, &v)) return (int)v;
    fail("psychimgui:Usage", "ImPlot3DSpec.Marker: unknown marker name '%s'.", n);
    return 0;
}

inline void spec3DField(ImPlot3DSpec& spec, const char* name, const mxArray* v,
                        size_t elemSize) {
    if (strcmp(name, "LineColor") == 0) spec.LineColor = spec3DColor(v, "LineColor");
    else if (strcmp(name, "FillColor") == 0) spec.FillColor = spec3DColor(v, "FillColor");
    else if (strcmp(name, "MarkerLineColor") == 0)
        spec.MarkerLineColor = spec3DColor(v, "MarkerLineColor");
    else if (strcmp(name, "MarkerFillColor") == 0)
        spec.MarkerFillColor = spec3DColor(v, "MarkerFillColor");
    else if (strcmp(name, "LineWeight") == 0)
        spec.LineWeight = (float)getScalar(v, "LineWeight");
    else if (strcmp(name, "FillAlpha") == 0)
        spec.FillAlpha = (float)getScalar(v, "FillAlpha");
    else if (strcmp(name, "MarkerSize") == 0)
        spec.MarkerSize = (float)getScalar(v, "MarkerSize");
    else if (strcmp(name, "Marker") == 0) spec.Marker = (ImPlot3DMarker)spec3DMarker(v);
    else if (strcmp(name, "Offset") == 0) spec.Offset = getInt(v, "Offset");
    else if (strcmp(name, "Stride") == 0)
        spec.Stride = (int)(getInt(v, "Stride") * (int)elemSize);
    else if (strcmp(name, "Flags") == 0)
        spec.Flags = (ImPlot3DItemFlags)getFlags(v, "Flags");
    else
        fail("psychimgui:Usage", "ImPlot3DSpec has no property named '%s'.", name);
}

// Trailing name-value pairs, or one struct with the same field names. The
// same name as ImPlot's getSpec, so the generated handlers read alike.
inline void getSpec(const mxArray** args, int nargin, int at, ImPlot3DSpec& spec,
                    size_t elemSize) {
    if (failed() || at >= nargin) return;
    if (mxIsStruct(args[at])) {
        if (nargin - at != 1) {
            fail("psychimgui:Usage", "An ImPlot3DSpec struct must be the last argument.");
            return;
        }
        int nf = mxGetNumberOfFields(args[at]);
        for (int i = 0; i < nf; ++i) {
            const char* nm = mxGetFieldNameByNumber(args[at], i);
            const mxArray* v = mxGetFieldByNumber(args[at], 0, i);
            if (v && !mxIsEmpty(v)) spec3DField(spec, nm, v, elemSize);
            if (failed()) return;
        }
        return;
    }
    if (((nargin - at) % 2) != 0) {
        fail("psychimgui:Usage", "The ImPlot3DSpec arguments must be name and value pairs.");
        return;
    }
    for (int i = at; i + 1 < nargin; i += 2) {
        char name[32];
        if (!mxIsChar(args[i]) || mxGetString(args[i], name, sizeof(name)) != 0) {
            fail("psychimgui:Usage", "Argument %d must be an ImPlot3DSpec property name.",
                 i + 1);
            return;
        }
        spec3DField(spec, name, args[i + 1], elemSize);
        if (failed()) return;
    }
}

// ------------------------------------------------------------------ faces --

// A triangle list for PlotMesh: an Mx3 matrix of 1-based vertex indices, one
// row per triangle, the Faces matrix of patch and the output of delaunay. It
// arrives column major, so all first corners come first, while ImPlot3D reads
// three consecutive indices per triangle; the copy transposes it and makes it
// 0-based. Up to 1024 triangles convert on the stack.
struct Faces {
    unsigned inl[3 * 1024];
    unsigned* heap;
    int n;  // index count, 3 per triangle
    Faces() : heap(nullptr), n(0) {}
    ~Faces() {
        if (heap) free(heap);
    }
    Faces(const Faces&) = delete;
    Faces& operator=(const Faces&) = delete;
};

// Every index is checked against the vertex count, because ImPlot3D indexes
// the vertex arrays with it unchecked and an index past the end reads outside
// the MATLAB array.
inline const unsigned* getFaces(const mxArray* a, const char* argname, int vtxCount,
                                Faces& f) {
    if (failed()) return nullptr;
    if (!a || !isPlotData(a) || mxGetNumberOfDimensions(a) != 2 ||
        (mxGetN(a) != 3 && !mxIsEmpty(a))) {
        fail("psychimgui:Type",
             "Argument '%s' must be an Mx3 real numeric matrix of 1-based vertex indices, "
             "one row per triangle.",
             argname);
        return nullptr;
    }
    int m = (int)mxGetM(a);
    unsigned* d = f.inl;
    if (m > 1024) {
        f.heap = (unsigned*)malloc((size_t)m * 3 * sizeof(unsigned));
        if (!f.heap) {
            fail("psychimgui:Usage", "Out of memory converting argument '%s'.", argname);
            return nullptr;
        }
        d = f.heap;
    }
    double t[3];
    for (int r = 0; r < m; ++r) {
        for (int c = 0; c < 3; ++c) {
            size_t k = (size_t)c * (size_t)m + (size_t)r;
            double v;
            switch (mxGetClassID(a)) {
                case mxDOUBLE_CLASS: v = ((const double*)mxGetData(a))[k]; break;
                case mxSINGLE_CLASS: v = ((const float*)mxGetData(a))[k]; break;
                case mxINT8_CLASS: v = ((const int8_T*)mxGetData(a))[k]; break;
                case mxUINT8_CLASS: v = ((const uint8_T*)mxGetData(a))[k]; break;
                case mxINT16_CLASS: v = ((const int16_T*)mxGetData(a))[k]; break;
                case mxUINT16_CLASS: v = ((const uint16_T*)mxGetData(a))[k]; break;
                case mxINT32_CLASS: v = ((const int32_T*)mxGetData(a))[k]; break;
                case mxUINT32_CLASS: v = ((const uint32_T*)mxGetData(a))[k]; break;
                case mxINT64_CLASS: v = (double)((const int64_T*)mxGetData(a))[k]; break;
                default: v = (double)((const uint64_T*)mxGetData(a))[k]; break;
            }
            t[c] = v;
        }
        for (int c = 0; c < 3; ++c) {
            if (!(t[c] >= 1.0 && t[c] <= (double)vtxCount) || t[c] != (double)(int64_t)t[c]) {
                fail("psychimgui:Range",
                     "Argument '%s': row %d holds %g, which is not a vertex index from 1 to "
                     "%d.",
                     argname, r + 1, t[c], vtxCount);
                return nullptr;
            }
            d[3 * r + c] = (unsigned)(t[c] - 1.0);
        }
    }
    f.n = 3 * m;
    return d;
}

}  // namespace mrs
