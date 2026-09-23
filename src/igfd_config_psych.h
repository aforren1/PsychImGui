// CUSTOM_IMGUIFILEDIALOG_CONFIG for psychimgui (SPEC.md section 14.11).
//
// On Windows the dialog lists directories through std::filesystem, because
// the dirent shim it ships converts file names with the process code page, so
// a name outside that code page arrives as '?' and cannot be opened again.
// std::filesystem goes through the wide Windows API and ImGuiFileDialog turns
// the result into UTF-8. MSVC 2022 and the MinGW g++ of Octave 10.1 both have
// it.
//
// Linux and macOS keep the POSIX dirent path, whose names are UTF-8 bytes
// already. That also keeps std::filesystem out of the Linux MEX: MATLAB loads
// its own libstdc++, which can be older than the compiler's and lack the
// std::filesystem symbols, and the MEX would then fail to load.
#pragma once

#if defined(_WIN32)
#  define USE_STD_FILESYSTEM
#endif
