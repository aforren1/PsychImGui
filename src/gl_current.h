// Current OpenGL context detection, one function per platform.
//
// Rule R1 of the specification: every GL subcommand must run between
// Screen('BeginOpenGL') and Screen('EndOpenGL'). The MEX cannot call Screen, so
// it asks the platform GL layer whether a context is current instead.
#pragma once

namespace pig {

bool gl_context_is_current();

// The platform handle of the current context (HGLRC, GLXContext, or
// CGLContextObj), or nullptr. Compared, never dereferenced: it identifies the
// Psychtoolbox window whose userspace context Screen('BeginOpenGL') selected.
void* gl_current_context();

}  // namespace pig
