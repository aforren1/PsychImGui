// Include this instead of ImGuiFileDialog.h from any translation unit.
//
// The configuration header travels as a macro, and MATLAB's mex strips the
// quotes out of a -D argument on Windows, so the macro is defined here, the
// same way imgui_psych.h passes IMGUI_USER_CONFIG. The library build and the
// MEX then see the same class layout.
#pragma once

// ImGuiFileDialog uses Dear ImGui's vector operators, which imgui.h declares
// only when this is defined before its first inclusion in the unit. Include
// this header before anything else that includes imgui.h.
#ifndef IMGUI_DEFINE_MATH_OPERATORS
#  define IMGUI_DEFINE_MATH_OPERATORS
#endif

#include "imgui_psych.h"

#ifndef CUSTOM_IMGUIFILEDIALOG_CONFIG
#  define CUSTOM_IMGUIFILEDIALOG_CONFIG "igfd_config_psych.h"
#endif

#include "ImGuiFileDialog.h"
