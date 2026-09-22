#include "gl_current.h"

#if defined(_WIN32)
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  include <windows.h>
// wglGetCurrentContext is declared by wingdi.h and exported by opengl32.dll,
// which the MEX links anyway for the backend loader.
#elif defined(__APPLE__)
#  include <OpenGL/OpenGL.h>
#else
#  include <GL/glx.h>
#endif

namespace pig {

bool gl_context_is_current() {
#if defined(_WIN32)
    return wglGetCurrentContext() != nullptr;
#elif defined(__APPLE__)
    return CGLGetCurrentContext() != nullptr;
#else
    return glXGetCurrentContext() != nullptr;
#endif
}

}  // namespace pig
