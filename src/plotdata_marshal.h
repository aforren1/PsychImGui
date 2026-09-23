// Data array rules shared by ImPlot and ImPlot3D (SPEC.md section 7.6).
//
// Both libraries template their plot functions over the element type, and the
// generated handlers pass the mxArray data pointer straight from mxGetData.
// Kept apart from implot.h and implot3d.h so either extension builds without
// the other.
#pragma once

#include "marshal.h"

namespace mrs {

// A data argument: real, numeric, and of a class that ImPlot and ImPlot3D
// have an instantiation for. Logical is rejected on purpose, per the
// specification.
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

}  // namespace mrs
