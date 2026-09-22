// Include this instead of <imgui.h> from any translation unit the engine's mex
// command compiles.
//
// IMGUI_USER_CONFIG has to be a quoted string on the compiler command line, and
// MATLAB's mex strips the quotes out of a -D argument on Windows. Defining the
// macro in a header the unit includes first avoids the quoting problem and
// keeps the MEX and the static library on the same configuration.
#pragma once

#ifndef IMGUI_USER_CONFIG
#  define IMGUI_USER_CONFIG "imconfig_psych.h"
#endif
#ifndef IMGUI_DISABLE_OBSOLETE_FUNCTIONS
#  define IMGUI_DISABLE_OBSOLETE_FUNCTIONS
#endif

#include "imgui.h"
