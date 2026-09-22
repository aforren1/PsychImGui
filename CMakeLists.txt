cmake_minimum_required(VERSION 3.16)
project(psychimgui_deps CXX)

# This file builds only the static libraries that the MEX links. build.m runs
# the mex command itself, because only the engine knows its own compiler flags.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(PSYCHIMGUI_IMPLOT "Compile ImPlot into the binding" ON)
option(PSYCHIMGUI_TRACY "Compile the Tracy profiler client" OFF)
option(PSYCHIMGUI_SMOKE_GL "Build the native GL smoke test executable" ON)
set(PSYCHIMGUI_STATS 1 CACHE STRING "Compile the per-subcommand Stats counters")

set(IMGUI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/cimgui/imgui)
set(IMPLOT_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/cimplot/implot)

if(NOT EXISTS ${IMGUI_DIR}/imgui.cpp)
  message(FATAL_ERROR
    "Dear ImGui sources not found at ${IMGUI_DIR}. "
    "See third_party/PINS.md for the clone commands.")
endif()

add_library(imgui_static STATIC
  ${IMGUI_DIR}/imgui.cpp
  ${IMGUI_DIR}/imgui_draw.cpp
  ${IMGUI_DIR}/imgui_tables.cpp
  ${IMGUI_DIR}/imgui_widgets.cpp
  ${IMGUI_DIR}/imgui_demo.cpp
  ${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/src/core/psychimgui_core.cpp
  ${CMAKE_CURRENT_SOURCE_DIR}/src/core/gl_current.cpp
)

target_include_directories(imgui_static PUBLIC
  ${IMGUI_DIR}
  ${IMGUI_DIR}/backends
  ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# IMGUI_USER_CONFIG redirects IM_ASSERT away from abort(); see src/imconfig_psych.h.
target_compile_definitions(imgui_static PUBLIC
  IMGUI_USER_CONFIG="imconfig_psych.h"
  IMGUI_DISABLE_OBSOLETE_FUNCTIONS
  PSYCHIMGUI_STATS=${PSYCHIMGUI_STATS}
)

# imgui_impl_opengl3 resolves its GL entry points with dlopen, so the archive
# needs libdl. CMAKE_DL_LIBS is empty on Windows and on glibc 2.34 and newer,
# where libdl folded into libc, and is "dl" on older Linux such as Ubuntu 20.04.
target_link_libraries(imgui_static PUBLIC ${CMAKE_DL_LIBS})

string(TIMESTAMP PSYCHIMGUI_BUILD_DATE "%Y-%m-%d")
target_compile_definitions(imgui_static PRIVATE
  PSYCHIMGUI_BUILD_STR="${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}, ${PSYCHIMGUI_BUILD_DATE}")

if(PSYCHIMGUI_IMPLOT)
  if(NOT EXISTS ${IMPLOT_DIR}/implot.cpp)
    message(FATAL_ERROR
      "ImPlot sources not found at ${IMPLOT_DIR}. "
      "Clone cimplot or configure with -DPSYCHIMGUI_IMPLOT=OFF.")
  endif()
  target_sources(imgui_static PRIVATE
    ${IMPLOT_DIR}/implot.cpp
    ${IMPLOT_DIR}/implot_items.cpp
    ${IMPLOT_DIR}/implot_demo.cpp
  )
  target_include_directories(imgui_static PUBLIC ${IMPLOT_DIR})
  target_compile_definitions(imgui_static PUBLIC
    PSYCHIMGUI_IMPLOT
    IMPLOT_DISABLE_OBSOLETE_FUNCTIONS
  )
endif()

if(PSYCHIMGUI_TRACY)
  set(TRACY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tracy)
  if(NOT EXISTS ${TRACY_DIR}/public/TracyClient.cpp)
    message(FATAL_ERROR "Tracy sources not found at ${TRACY_DIR}.")
  endif()
  target_sources(imgui_static PRIVATE ${TRACY_DIR}/public/TracyClient.cpp)
  target_include_directories(imgui_static PUBLIC ${TRACY_DIR}/public)
  target_compile_definitions(imgui_static PUBLIC TRACY_ENABLE PSYCHIMGUI_TRACY)
endif()

if(MSVC)
  target_compile_options(imgui_static PRIVATE /W3 /wd4244 /wd4267)
else()
  target_compile_options(imgui_static PRIVATE -Wall -Wno-unused-function)
endif()

install(TARGETS imgui_static ARCHIVE DESTINATION lib)
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/src/imconfig_psych.h DESTINATION include)

# ---------------------------------------------------------------------------
# Native GL smoke test.
#
# Psychtoolbox is not needed to prove that the core, the backend, and a real
# compatibility GL context work together. smoke_gl links the same core the MEX
# uses, without MATLAB.
# ---------------------------------------------------------------------------
if(PSYCHIMGUI_SMOKE_GL)
  add_executable(smoke_gl ${CMAKE_CURRENT_SOURCE_DIR}/tools/smoke_gl.cpp)
  target_link_libraries(smoke_gl PRIVATE imgui_static)
  if(WIN32)
    target_link_libraries(smoke_gl PRIVATE opengl32 gdi32 user32)
  elseif(APPLE)
    target_link_libraries(smoke_gl PRIVATE "-framework OpenGL")
  else()
    target_link_libraries(smoke_gl PRIVATE GL X11)
  endif()
endif()
