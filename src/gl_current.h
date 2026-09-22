// Current OpenGL context detection, one function per platform.
//
// Rule R1 of the specification: every GL subcommand must run between
// Screen('BeginOpenGL') and Screen('EndOpenGL'). The MEX cannot call Screen, so
// it asks the platform GL layer whether a context is current instead.
#pragma once

namespace pig {

bool gl_context_is_current();

}  // namespace pig
