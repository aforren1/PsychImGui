// Compiles ImGuiFileDialog with this project's configuration.
//
// Including the source here, after igfd_psych.h has defined the configuration
// macro, keeps the library and the MEX on one configuration without a
// per-file compile definition that some generators quote differently.
#include "igfd_psych.h"

#include "ImGuiFileDialog.cpp"

// The core owns one dialog per context but must not include
// ImGuiFileDialog.h, which needs IMGUI_DEFINE_MATH_OPERATORS before the
// core's own first imgui.h. These two keep the class out of the core.
namespace pig {
void* igfd_create() { return new IGFD::FileDialog(); }
void igfd_destroy(void* d) { delete (IGFD::FileDialog*)d; }
const char* igfd_version() { return IGFD_VERSION; }
}  // namespace pig
