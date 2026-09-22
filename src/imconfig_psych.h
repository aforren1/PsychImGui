// IMGUI_USER_CONFIG for psychimgui.
//
// Dear ImGui and ImPlot call IM_ASSERT on programmer error. The stock macro
// calls assert(), which aborts the whole MATLAB or Octave process and loses the
// user's workspace. A MEX file may not do that. The replacement records the
// failure and returns, so the dispatch layer can raise psychimgui:ImGuiAssert
// after the call unwinds. Dear ImGui is not exception safe and PTB owns the GL
// context, so neither throw nor longjmp is available here.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Defined in src/core/psychimgui_core.cpp. Records only the first failure of a
// call, because later failures are usually consequences of the first.
void psychimgui_assert_failed(const char* expr, const char* file, int line);

#ifdef __cplusplus
}
#endif

// Expression form, not a do/while block, so IM_ASSERT keeps working in the few
// places Dear ImGui uses it inside a comma expression or an if without braces.
#define IM_ASSERT(_EXPR) \
    ((void)((_EXPR) ? (void)0 : psychimgui_assert_failed(#_EXPR, __FILE__, __LINE__)))

#ifndef IMGUI_DISABLE_OBSOLETE_FUNCTIONS
#  define IMGUI_DISABLE_OBSOLETE_FUNCTIONS
#endif
