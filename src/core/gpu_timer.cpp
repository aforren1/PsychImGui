#include "gpu_timer.h"

#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  include <windows.h>
#  include <GL/gl.h>
#elif defined(__APPLE__)
#  include <OpenGL/gl.h>
#  include <dlfcn.h>
#else
#  include <GL/gl.h>
#  include <GL/glx.h>
#endif

#ifdef TRACY_ENABLE
#  include "client/TracyProfiler.hpp"
#  include "tracy/TracyC.h"
#endif

#ifndef APIENTRY
#  define APIENTRY
#endif

namespace pig {

namespace {

const unsigned kGL_TIMESTAMP = 0x8E28;
const unsigned kGL_QUERY_RESULT = 0x8866;
const unsigned kGL_QUERY_RESULT_AVAILABLE = 0x8867;

typedef void(APIENTRY* PfnGenQueries)(GLsizei, GLuint*);
typedef void(APIENTRY* PfnDeleteQueries)(GLsizei, const GLuint*);
typedef void(APIENTRY* PfnQueryCounter)(GLuint, GLenum);
typedef void(APIENTRY* PfnGetQueryObjectiv)(GLuint, GLenum, GLint*);
typedef void(APIENTRY* PfnGetQueryObjectui64v)(GLuint, GLenum, uint64_t*);
typedef void(APIENTRY* PfnGetInteger64v)(GLenum, int64_t*);

enum { kGen, kDelete, kCounter, kObjiv, kObjui64v, kInt64v };

void* proc(const char* name) {
#if defined(_WIN32)
    // Some drivers answer 1, 2, 3, or -1 instead of NULL for a missing name.
    void* p = (void*)wglGetProcAddress(name);
    intptr_t v = (intptr_t)p;
    if (v == 0 || v == 1 || v == 2 || v == 3 || v == -1) return nullptr;
    return p;
#elif defined(__APPLE__)
    return dlsym(RTLD_DEFAULT, name);
#else
    return (void*)glXGetProcAddressARB((const GLubyte*)name);
#endif
}

// A whole-token match in the legacy extension string. A compatibility
// context still answers glGetString(GL_EXTENSIONS); a core one returns NULL,
// and then the version decides alone.
bool has_extension(const char* name) {
    const char* all = (const char*)glGetString(GL_EXTENSIONS);
    if (!all) return false;
    size_t n = strlen(name);
    for (const char* p = strstr(all, name); p; p = strstr(p + 1, name)) {
        bool startOk = (p == all) || p[-1] == ' ';
        bool endOk = p[n] == ' ' || p[n] == 0;
        if (startOk && endOk) return true;
    }
    return false;
}

int version_number(const char* v) {
    int major = 0, minor = 0;
    if (v) sscanf(v, "%d.%d", &major, &minor);
    return major * 10 + minor;
}

#ifdef TRACY_ENABLE
const ___tracy_source_location_data kGpuZone = {"Render (GPU)", "pig::render", __FILE__,
                                                (uint32_t)__LINE__, 0};
#endif

// Reads every finished slot, oldest first, and never waits.
void harvest(GpuTimer& t) {
    PfnGetQueryObjectiv objiv = (PfnGetQueryObjectiv)t.fn[kObjiv];
    PfnGetQueryObjectui64v obj64 = (PfnGetQueryObjectui64v)t.fn[kObjui64v];
    for (int k = 1; k <= kGpuSlots; ++k) {
        int s = (t.next + k) % kGpuSlots;
        if (!t.pending[s]) continue;
        GLint avail = 0;
        // The end query finishes last, so its availability covers both.
        objiv(t.q[s][1], kGL_QUERY_RESULT_AVAILABLE, &avail);
        if (!avail) continue;
        uint64_t t0 = 0, t1 = 0;
        obj64(t.q[s][0], kGL_QUERY_RESULT, &t0);
        obj64(t.q[s][1], kGL_QUERY_RESULT, &t1);
        t.pending[s] = 0;
        t.lastNs = t1 >= t0 ? t1 - t0 : 0;
#ifdef TRACY_ENABLE
        if (t.tracy) {
            ___tracy_emit_gpu_time_serial({(int64_t)t0, (uint16_t)(s * 2), t.tracyCtx});
            ___tracy_emit_gpu_time_serial({(int64_t)t1, (uint16_t)(s * 2 + 1), t.tracyCtx});
        }
#endif
    }
}

}  // namespace

void gpuTimerInit(GpuTimer& t, const char* glVersion, const char* name) {
    memset(&t, 0, sizeof(t));
    int v = version_number(glVersion);
    if (v < 33 && !has_extension("GL_ARB_timer_query")) return;

    // glGenQueries is OpenGL 1.5 and glQueryCounter comes with 3.3 or
    // GL_ARB_timer_query, which names its entry points without a suffix.
    static const char* kNames[6] = {"glGenQueries",        "glDeleteQueries",
                                    "glQueryCounter",      "glGetQueryObjectiv",
                                    "glGetQueryObjectui64v", "glGetInteger64v"};
    for (int i = 0; i < 6; ++i) t.fn[i] = proc(kNames[i]);
    // glGetInteger64v is 3.2 or GL_ARB_sync, and only the Tracy calibration
    // below uses it, so its absence does not turn timing off.
    if (v < 32 && !has_extension("GL_ARB_sync")) t.fn[kInt64v] = nullptr;
    for (int i = 0; i < 5; ++i)
        if (!t.fn[i]) return;

    // A failure here would read as a Render error later, so drain first and
    // give up on timing if the calls themselves raise one.
    for (int guard = 0; guard < 64 && glGetError() != GL_NO_ERROR; ++guard) {
    }
    ((PfnGenQueries)t.fn[kGen])(kGpuSlots * 2, &t.q[0][0]);
    if (glGetError() != GL_NO_ERROR) {
        memset(t.q, 0, sizeof(t.q));
        return;
    }
    t.ok = true;

#ifdef TRACY_ENABLE
    // The server places GPU times on its timeline from one reference
    // timestamp taken now. Without glGetInteger64v the reference comes from a
    // query this call waits for, once, at Init.
    int64_t now = 0;
    if (t.fn[kInt64v]) {
        ((PfnGetInteger64v)t.fn[kInt64v])(kGL_TIMESTAMP, &now);
    } else {
        uint64_t r = 0;
        ((PfnQueryCounter)t.fn[kCounter])(t.q[0][0], kGL_TIMESTAMP);
        ((PfnGetQueryObjectui64v)t.fn[kObjui64v])(t.q[0][0], kGL_QUERY_RESULT, &r);
        now = (int64_t)r;
    }
    if (glGetError() == GL_NO_ERROR) {
        t.tracyCtx = tracy::GetGpuCtxCounter().fetch_add(1, std::memory_order_relaxed);
        ___tracy_emit_gpu_new_context_serial({now, 1.0f, t.tracyCtx, 0, 1 /* OpenGL */});
        if (name && name[0])
            ___tracy_emit_gpu_context_name_serial(
                {t.tracyCtx, name, (uint16_t)strlen(name)});
        t.tracy = true;
    }
#else
    (void)name;
#endif
}

void gpuTimerShutdown(GpuTimer& t) {
    if (t.ok) ((PfnDeleteQueries)t.fn[kDelete])(kGpuSlots * 2, &t.q[0][0]);
    memset(&t, 0, sizeof(t));
}

int gpuTimerBegin(GpuTimer& t) {
    if (!t.ok) return -1;
    harvest(t);
    int s = t.next;
    if (t.pending[s]) return -1;  // still in flight; waiting would stall
    t.next = (t.next + 1) % kGpuSlots;
    ((PfnQueryCounter)t.fn[kCounter])(t.q[s][0], kGL_TIMESTAMP);
#ifdef TRACY_ENABLE
    if (t.tracy)
        ___tracy_emit_gpu_zone_begin_serial(
            {(uint64_t)(uintptr_t)&kGpuZone, (uint16_t)(s * 2), t.tracyCtx});
#endif
    return s;
}

void gpuTimerEnd(GpuTimer& t, int s) {
    if (!t.ok || s < 0) return;
    ((PfnQueryCounter)t.fn[kCounter])(t.q[s][1], kGL_TIMESTAMP);
    t.pending[s] = 1;
#ifdef TRACY_ENABLE
    if (t.tracy) ___tracy_emit_gpu_zone_end_serial({(uint16_t)(s * 2 + 1), t.tracyCtx});
#endif
}

}  // namespace pig
