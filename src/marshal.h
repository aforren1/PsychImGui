// mxArray to C marshaling helpers shared by the hand-written and the generated
// subcommands.
//
// No helper raises. Dear ImGui is not exception safe and mexErrMsgIdAndTxt
// unwinds with longjmp, so every failure is recorded in a single pending Error
// and the dispatch layer raises it once the handler has returned and every
// destructor has run. Helpers return early when an error is already pending, so
// a handler can run a whole chain of conversions and test once at the end.
#pragma once

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mex.h"

namespace mrs {

struct Error {
    bool set;
    char id[64];
    char msg[512];
};

extern Error g_err;

inline bool failed() { return g_err.set; }
inline void clear() { g_err.set = false; }

inline void fail(const char* id, const char* fmt, ...) {
    if (g_err.set) return;  // the first failure is the one worth reporting
    g_err.set = true;
    snprintf(g_err.id, sizeof(g_err.id), "%s", id);
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(g_err.msg, sizeof(g_err.msg), fmt, ap);
    va_end(ap);
}

inline void usage(const char* cmd, const char* sig) {
    fail("psychimgui:Usage", "PsychImGui('%s'): wrong number of arguments.\n  Usage: %s", cmd, sig);
}

// Implemented in the generated dispatch file, which owns the enum value table.
bool enum_lookup(const char* name, double* out);

// ---------------------------------------------------------------- strings ---

#ifdef PSYCHIMGUI_OCTAVE
// Octave keeps char arrays as UTF-8 bytes widened into mxChar, so a truncating
// copy already yields the UTF-8 Dear ImGui wants.
inline size_t utf8_len_of(const mxChar* s, size_t n) { return n; }
inline void utf8_copy(const mxChar* s, size_t n, char* d) {
    for (size_t i = 0; i < n; ++i) d[i] = (char)(s[i] & 0xFF);
    d[n] = 0;
}
#else
// MATLAB keeps char arrays as UTF-16 code units.
inline size_t utf8_len_of(const mxChar* s, size_t n) {
    size_t len = 0;
    for (size_t i = 0; i < n; ++i) {
        unsigned c = s[i];
        if (c >= 0xD800u && c <= 0xDBFFu && i + 1 < n && s[i + 1] >= 0xDC00u &&
            s[i + 1] <= 0xDFFFu) {
            len += 4;
            ++i;
        } else if (c < 0x80u) {
            len += 1;
        } else if (c < 0x800u) {
            len += 2;
        } else {
            len += 3;
        }
    }
    return len;
}
inline void utf8_copy(const mxChar* s, size_t n, char* d) {
    size_t o = 0;
    for (size_t i = 0; i < n; ++i) {
        unsigned c = s[i];
        if (c >= 0xD800u && c <= 0xDBFFu && i + 1 < n && s[i + 1] >= 0xDC00u &&
            s[i + 1] <= 0xDFFFu) {
            unsigned lo = s[++i];
            c = 0x10000u + ((c - 0xD800u) << 10) + (lo - 0xDC00u);
        }
        if (c < 0x80u) {
            d[o++] = (char)c;
        } else if (c < 0x800u) {
            d[o++] = (char)(0xC0u | (c >> 6));
            d[o++] = (char)(0x80u | (c & 0x3Fu));
        } else if (c < 0x10000u) {
            d[o++] = (char)(0xE0u | (c >> 12));
            d[o++] = (char)(0x80u | ((c >> 6) & 0x3Fu));
            d[o++] = (char)(0x80u | (c & 0x3Fu));
        } else {
            d[o++] = (char)(0xF0u | (c >> 18));
            d[o++] = (char)(0x80u | ((c >> 12) & 0x3Fu));
            d[o++] = (char)(0x80u | ((c >> 6) & 0x3Fu));
            d[o++] = (char)(0x80u | (c & 0x3Fu));
        }
    }
    d[o] = 0;
}
#endif

// A char argument converted to UTF-8. N bytes live on the stack; only a string
// longer than that touches the heap, which keeps the per-call path allocation
// free for labels and format strings.
template <size_t N>
struct StrBuf {
    char inl[N];
    char* heap;
    StrBuf() : heap(nullptr) { inl[0] = 0; }
    ~StrBuf() {
        if (heap) free(heap);
    }
    StrBuf(const StrBuf&) = delete;
    StrBuf& operator=(const StrBuf&) = delete;
};

template <size_t N>
const char* toUtf8(const mxArray* a, const char* argname, StrBuf<N>& buf) {
    if (failed()) return "";
    if (!a || !mxIsChar(a)) {
        if (a && mxIsClass(a, "string"))
            fail("psychimgui:Type",
                 "Argument '%s' must be a char row vector. MATLAB string is not accepted, "
                 "because Octave has no string class.",
                 argname);
        else
            fail("psychimgui:Type", "Argument '%s' must be a char row vector.", argname);
        return "";
    }
    size_t n = mxGetNumberOfElements(a);
    const mxChar* s = mxGetChars(a);
    size_t need = utf8_len_of(s, n);
    if (need + 1 <= N) {
        utf8_copy(s, n, buf.inl);
        return buf.inl;
    }
    buf.heap = (char*)malloc(need + 1);
    if (!buf.heap) {
        fail("psychimgui:Usage", "Out of memory converting argument '%s'.", argname);
        return "";
    }
    utf8_copy(s, n, buf.heap);
    return buf.heap;
}

// A UTF-8 C string as an engine char array. Built through mxChar rather than
// mxCreateString so the code unit width is right on both engines regardless of
// the process code page.
inline mxArray* fromUtf8(const char* s) {
    if (!s) s = "";
#ifdef PSYCHIMGUI_OCTAVE
    size_t n = strlen(s);
    mwSize dims[2] = {(mwSize)(n ? 1 : 0), (mwSize)n};
    mxArray* out = mxCreateCharArray(2, dims);
    mxChar* d = mxGetChars(out);
    for (size_t i = 0; i < n; ++i) d[i] = (mxChar)(unsigned char)s[i];
    return out;
#else
    size_t units = 0;
    for (const unsigned char* p = (const unsigned char*)s; *p;) {
        unsigned c = *p;
        if (c < 0x80u) {
            p += 1;
            units += 1;
        } else if ((c & 0xE0u) == 0xC0u) {
            p += 2;
            units += 1;
        } else if ((c & 0xF0u) == 0xE0u) {
            p += 3;
            units += 1;
        } else {
            p += 4;
            units += 2;
        }
    }
    mwSize dims[2] = {(mwSize)(units ? 1 : 0), (mwSize)units};
    mxArray* out = mxCreateCharArray(2, dims);
    mxChar* d = mxGetChars(out);
    size_t o = 0;
    for (const unsigned char* p = (const unsigned char*)s; *p;) {
        unsigned c = *p;
        unsigned cp;
        if (c < 0x80u) {
            cp = c;
            p += 1;
        } else if ((c & 0xE0u) == 0xC0u) {
            cp = ((c & 0x1Fu) << 6) | (p[1] & 0x3Fu);
            p += 2;
        } else if ((c & 0xF0u) == 0xE0u) {
            cp = ((c & 0x0Fu) << 12) | ((p[1] & 0x3Fu) << 6) | (p[2] & 0x3Fu);
            p += 3;
        } else {
            cp = ((c & 0x07u) << 18) | ((p[1] & 0x3Fu) << 12) | ((p[2] & 0x3Fu) << 6) |
                 (p[3] & 0x3Fu);
            p += 4;
        }
        if (cp < 0x10000u) {
            d[o++] = (mxChar)cp;
        } else {
            cp -= 0x10000u;
            d[o++] = (mxChar)(0xD800u + (cp >> 10));
            d[o++] = (mxChar)(0xDC00u + (cp & 0x3FFu));
        }
    }
    return out;
#endif
}

// -------------------------------------------------------------- scalars -----

inline double getScalar(const mxArray* a, const char* argname) {
    if (failed()) return 0.0;
    if (!a || !(mxIsNumeric(a) || mxIsLogical(a)) || mxIsComplex(a) ||
        mxGetNumberOfElements(a) != 1) {
        fail("psychimgui:Type", "Argument '%s' must be a real numeric or logical scalar.",
             argname);
        return 0.0;
    }
    return mxGetScalar(a);
}

inline bool getBool(const mxArray* a, const char* argname) {
    return getScalar(a, argname) != 0.0;
}

inline double getIntRanged(const mxArray* a, const char* argname, double lo, double hi) {
    double v = getScalar(a, argname);
    if (failed()) return 0.0;
    if (v != v || v < lo || v > hi) {
        fail("psychimgui:Range", "Argument '%s' (%g) is out of range [%g, %g].", argname, v,
             lo, hi);
        return 0.0;
    }
    return v;
}

inline int getInt(const mxArray* a, const char* argname) {
    return (int)getIntRanged(a, argname, -2147483648.0, 2147483647.0);
}

inline unsigned getUInt(const mxArray* a, const char* argname) {
    return (unsigned)getIntRanged(a, argname, 0.0, 4294967295.0);
}

inline int64_t getInt64(const mxArray* a, const char* argname) {
    return (int64_t)getIntRanged(a, argname, -9223372036854775808.0, 9223372036854775807.0);
}

inline uint64_t getUInt64(const mxArray* a, const char* argname) {
    return (uint64_t)getIntRanged(a, argname, 0.0, 18446744073709551615.0);
}

// Flags accept a number, one enum name, or a cellstr of names combined with OR.
inline double getFlags(const mxArray* a, const char* argname) {
    if (failed()) return 0.0;
    if (!a) return 0.0;
    if (mxIsChar(a)) {
        StrBuf<128> b;
        const char* n = toUtf8(a, argname, b);
        double v = 0.0;
        if (!enum_lookup(n, &v)) {
            fail("psychimgui:Usage", "Argument '%s': unknown enum name '%s'.", argname, n);
            return 0.0;
        }
        return v;
    }
    if (mxIsCell(a)) {
        double acc = 0.0;
        size_t n = mxGetNumberOfElements(a);
        for (size_t i = 0; i < n; ++i) {
            const mxArray* e = mxGetCell(a, (mwIndex)i);
            StrBuf<128> b;
            const char* nm = toUtf8(e, argname, b);
            if (failed()) return 0.0;
            double v = 0.0;
            if (!enum_lookup(nm, &v)) {
                fail("psychimgui:Usage", "Argument '%s': unknown enum name '%s'.", argname, nm);
                return 0.0;
            }
            acc = (double)((int64_t)acc | (int64_t)v);
        }
        return acc;
    }
    return getScalar(a, argname);
}

// ------------------------------------------------------------- vectors ------

inline void getVec(const mxArray* a, const char* argname, double* out, int n) {
    if (failed()) return;
    if (!a || !(mxIsNumeric(a) || mxIsLogical(a)) || mxIsComplex(a) ||
        (int)mxGetNumberOfElements(a) != n) {
        fail("psychimgui:Type", "Argument '%s' must be a real %d element numeric vector.",
             argname, n);
        return;
    }
    if (mxIsDouble(a)) {
        const double* p = mxGetPr(a);
        for (int i = 0; i < n; ++i) out[i] = p[i];
        return;
    }
    // Rare path: a single, integer, or logical vector. Class dispatch here avoids
    // mexCallMATLAB, which raises on failure and so may not run inside a handler.
    const void* v = mxGetData(a);
    switch (mxGetClassID(a)) {
        case mxSINGLE_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const float*)v)[i];
            break;
        case mxLOGICAL_CLASS:
            for (int i = 0; i < n; ++i) out[i] = ((const mxLogical*)v)[i] ? 1.0 : 0.0;
            break;
        case mxINT8_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const int8_T*)v)[i];
            break;
        case mxUINT8_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const uint8_T*)v)[i];
            break;
        case mxINT16_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const int16_T*)v)[i];
            break;
        case mxUINT16_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const uint16_T*)v)[i];
            break;
        case mxINT32_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const int32_T*)v)[i];
            break;
        case mxUINT32_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const uint32_T*)v)[i];
            break;
        case mxINT64_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const int64_T*)v)[i];
            break;
        case mxUINT64_CLASS:
            for (int i = 0; i < n; ++i) out[i] = (double)((const uint64_T*)v)[i];
            break;
        default:
            fail("psychimgui:Type", "Argument '%s' has an unsupported numeric class.", argname);
            break;
    }
}

inline void getVecF(const mxArray* a, const char* argname, float* out, int n) {
    double tmp[8];
    if (n > 8) n = 8;
    getVec(a, argname, tmp, n);
    if (failed()) return;
    for (int i = 0; i < n; ++i) out[i] = (float)tmp[i];
}

inline void getVecI(const mxArray* a, const char* argname, int* out, int n) {
    double tmp[8];
    if (n > 8) n = 8;
    getVec(a, argname, tmp, n);
    if (failed()) return;
    for (int i = 0; i < n; ++i) out[i] = (int)tmp[i];
}

// A float array argument. Short arrays stay on the stack.
struct FloatVec {
    float inl[256];
    float* heap;
    int n;
    FloatVec() : heap(nullptr), n(0) {}
    ~FloatVec() {
        if (heap) free(heap);
    }
    FloatVec(const FloatVec&) = delete;
    FloatVec& operator=(const FloatVec&) = delete;
};

inline const float* getFloatArray(const mxArray* a, const char* argname, FloatVec& v) {
    if (failed()) return nullptr;
    if (!a || !mxIsDouble(a) || mxIsComplex(a)) {
        fail("psychimgui:Type", "Argument '%s' must be a real double array.", argname);
        return nullptr;
    }
    size_t n = mxGetNumberOfElements(a);
    const double* p = mxGetPr(a);
    float* d = v.inl;
    if (n > sizeof(v.inl) / sizeof(v.inl[0])) {
        v.heap = (float*)malloc(n * sizeof(float));
        if (!v.heap) {
            fail("psychimgui:Usage", "Out of memory converting argument '%s'.", argname);
            return nullptr;
        }
        d = v.heap;
    }
    for (size_t i = 0; i < n; ++i) d[i] = (float)p[i];
    v.n = (int)n;
    return d;
}

// A real double array, passed to C without a copy. The pointer stays valid for
// the duration of the call, which is all the consumers below need.
inline const double* getDoubleArray(const mxArray* a, const char* argname, int* n) {
    *n = 0;
    if (failed()) return nullptr;
    if (!a || !mxIsDouble(a) || mxIsComplex(a)) {
        fail("psychimgui:Type", "Argument '%s' must be a real double array.", argname);
        return nullptr;
    }
    *n = (int)mxGetNumberOfElements(a);
    return mxGetPr(a);
}

// A cellstr argument flattened into one UTF-8 arena plus a pointer table.
struct CellStr {
    const char* inlPtr[64];
    char inlBuf[2048];
    const char** ptr;
    char* heapBuf;
    const char** heapPtr;
    int n;
    CellStr() : ptr(nullptr), heapBuf(nullptr), heapPtr(nullptr), n(0) {}
    ~CellStr() {
        if (heapBuf) free(heapBuf);
        if (heapPtr) free(heapPtr);
    }
    CellStr(const CellStr&) = delete;
    CellStr& operator=(const CellStr&) = delete;
};

inline const char* const* getCellStr(const mxArray* a, const char* argname, CellStr& cs) {
    if (failed()) return nullptr;
    if (!a || !mxIsCell(a)) {
        fail("psychimgui:Type", "Argument '%s' must be a cell array of char row vectors.",
             argname);
        return nullptr;
    }
    int n = (int)mxGetNumberOfElements(a);
    cs.n = n;
    size_t need = 0;
    for (int i = 0; i < n; ++i) {
        const mxArray* e = mxGetCell(a, i);
        if (!e || !mxIsChar(e)) {
            fail("psychimgui:Type", "Argument '%s{%d}' must be a char row vector.", argname,
                 i + 1);
            return nullptr;
        }
        need += utf8_len_of(mxGetChars(e), mxGetNumberOfElements(e)) + 1;
    }
    char* buf = cs.inlBuf;
    if (need > sizeof(cs.inlBuf)) {
        cs.heapBuf = (char*)malloc(need ? need : 1);
        if (!cs.heapBuf) {
            fail("psychimgui:Usage", "Out of memory converting argument '%s'.", argname);
            return nullptr;
        }
        buf = cs.heapBuf;
    }
    const char** tab = cs.inlPtr;
    if (n > (int)(sizeof(cs.inlPtr) / sizeof(cs.inlPtr[0]))) {
        cs.heapPtr = (const char**)malloc((size_t)n * sizeof(char*));
        if (!cs.heapPtr) {
            fail("psychimgui:Usage", "Out of memory converting argument '%s'.", argname);
            return nullptr;
        }
        tab = cs.heapPtr;
    }
    size_t off = 0;
    for (int i = 0; i < n; ++i) {
        const mxArray* e = mxGetCell(a, i);
        size_t m = mxGetNumberOfElements(e);
        utf8_copy(mxGetChars(e), m, buf + off);
        tab[i] = buf + off;
        off += utf8_len_of(mxGetChars(e), m) + 1;
    }
    cs.ptr = tab;
    return tab;
}

// An editable text buffer for InputText. Section 7.5: the script owns the text,
// so the MEX keeps nothing between calls.
struct TextBuf {
    char inl[1024];
    char* heap;
    char* p;
    size_t cap;
    TextBuf() : heap(nullptr), p(inl), cap(sizeof(inl)) { inl[0] = 0; }
    ~TextBuf() {
        if (heap) free(heap);
    }
    TextBuf(const TextBuf&) = delete;
    TextBuf& operator=(const TextBuf&) = delete;
};

inline void fillText(const mxArray* a, const char* argname, int bufSize, TextBuf& tb) {
    if (failed()) return;
    if (!a || !mxIsChar(a)) {
        fail("psychimgui:Type", "Argument '%s' must be a char row vector.", argname);
        return;
    }
    if (bufSize < 256) bufSize = 256;
    size_t n = mxGetNumberOfElements(a);
    size_t need = utf8_len_of(mxGetChars(a), n) + 1;
    size_t cap = (size_t)bufSize;
    if (cap > sizeof(tb.inl)) {
        tb.heap = (char*)malloc(cap);
        if (!tb.heap) {
            fail("psychimgui:Usage", "Out of memory for the text buffer of '%s'.", argname);
            return;
        }
        tb.p = tb.heap;
    }
    tb.cap = cap;
    if (need <= cap) {
        utf8_copy(mxGetChars(a), n, tb.p);
    } else {
        // Truncation is on a UTF-8 boundary so the result stays decodable.
        char* tmp = (char*)malloc(need);
        if (!tmp) {
            fail("psychimgui:Usage", "Out of memory for the text buffer of '%s'.", argname);
            return;
        }
        utf8_copy(mxGetChars(a), n, tmp);
        size_t cut = cap - 1;
        while (cut > 0 && ((unsigned char)tmp[cut] & 0xC0u) == 0x80u) --cut;
        memcpy(tb.p, tmp, cut);
        tb.p[cut] = 0;
        free(tmp);
    }
}

// --------------------------------------------------------------- outputs ----

inline mxArray* outBool(bool v) { return mxCreateLogicalScalar(v); }
inline mxArray* outDouble(double v) { return mxCreateDoubleScalar(v); }

inline mxArray* outVec(const double* v, int n) {
    mxArray* a = mxCreateDoubleMatrix(1, n, mxREAL);
    double* p = mxGetPr(a);
    for (int i = 0; i < n; ++i) p[i] = v[i];
    return a;
}

inline mxArray* outVecF(const float* v, int n) {
    mxArray* a = mxCreateDoubleMatrix(1, n, mxREAL);
    double* p = mxGetPr(a);
    for (int i = 0; i < n; ++i) p[i] = (double)v[i];
    return a;
}

inline mxArray* outVecI(const int* v, int n) {
    mxArray* a = mxCreateDoubleMatrix(1, n, mxREAL);
    double* p = mxGetPr(a);
    for (int i = 0; i < n; ++i) p[i] = (double)v[i];
    return a;
}

}  // namespace mrs
