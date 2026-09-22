// Dispatch table shared by psychimgui.cpp and the generated handler files.
#pragma once

#include "mex.h"

namespace pig {

// Handlers receive the argument list with the subcommand selector removed, so
// args[0] is the first real argument.
typedef void (*Handler)(int nlhs, mxArray** plhs, int nargin, const mxArray** args);

struct Entry {
    const char* name;  // subcommand name, table sorted by strcmp order
    Handler fn;
    const char* sig;   // one line signature for help and Usage errors
    unsigned flags;    // see kEntryFlag values below
};

enum EntryFlag {
    kEntryNeedsInit = 1u << 0,  // raises psychimgui:NotInit before Init
    kEntryNeedsGL = 1u << 1,    // raises psychimgui:NoGLContext with no context
    kEntryUnavailable = 1u << 2  // compiled out, raises psychimgui:UnknownCommand
};

// Generated in src/gen_dispatch.cpp.
extern const Entry kTable[];
extern const int kTableCount;

}  // namespace pig
