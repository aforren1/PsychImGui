// GPU time of the Render submissions, from GL_TIMESTAMP queries.
//
// Feeds PsychImGui('Stats').frame.renderGpuNs and, when the Tracy client is
// compiled in, one Tracy GPU zone per submission (SPEC.md sections 9.2, 9.3).
//
// Results are read back without blocking, at least one submission later,
// because a glGetQueryObject on a result the GPU has not produced yet stalls
// the CPU until the whole frame has drawn. A slot whose result is still
// pending when it comes round again is skipped rather than waited for.
#pragma once

#include <stdint.h>

namespace pig {

// Eight slots cover two submissions per frame, as in a stereo mode, for four
// frames, which is more latency than any driver queues.
const int kGpuSlots = 8;

struct GpuTimer {
    bool ok;             // the context supports timestamp queries
    bool tracy;          // a Tracy GPU context was announced for it
    uint8_t tracyCtx;
    unsigned q[kGpuSlots][2];
    uint8_t pending[kGpuSlots];
    int next;
    uint64_t lastNs;     // GPU time of the most recent completed submission
    // Entry points, per context: on Windows wglGetProcAddress may answer
    // differently for contexts with different pixel formats.
    void* fn[6];
};

// All three need the GL context that owns the timer to be current.
// gpuTimerInit leaves t.ok false, and every other call a no-op, when the
// context has neither OpenGL 3.3 nor GL_ARB_timer_query, which is the case for
// the OpenGL 2.1 context Psychtoolbox creates on macOS. No entry point is
// resolved, and none is called, without that check.
void gpuTimerInit(GpuTimer& t, const char* glVersion, const char* name);
void gpuTimerShutdown(GpuTimer& t);

// Returns the slot for this submission, or -1 when timing is off or the slot
// is still waiting for its result. Harvests finished results first.
int gpuTimerBegin(GpuTimer& t);
void gpuTimerEnd(GpuTimer& t, int slot);

}  // namespace pig
