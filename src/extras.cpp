// Hand-written Dear ImGui subcommands that the generator cannot express:
// the double precision sliders, whose C form takes void pointers and a data
// type, and the table sort specs, which come back as a struct array.
// See SPEC.md section 14.15.

#include "imgui_psych.h"

#include "imgui_marshal.h"
#include "marshal.h"
#include "mex.h"

namespace pig {

namespace {

// More components than this make a row of widgets too narrow to use, and the
// limit keeps the values on the stack.
constexpr int kMaxComponents = 16;

// v as 1 to kMaxComponents doubles, copied to out. Returns the count.
int get_components(const mxArray* a, const char* cmd, double* out) {
    if (mrs::failed()) return 0;
    if (!a || !mxIsDouble(a) || mxIsComplex(a) || mxIsEmpty(a) ||
        mxGetNumberOfElements(a) > (size_t)kMaxComponents) {
        mrs::fail("psychimgui:Type", "%s: v must be a real double vector of 1 to %d elements.",
                  cmd, kMaxComponents);
        return 0;
    }
    int n = (int)mxGetNumberOfElements(a);
    const double* p = mxGetPr(a);
    for (int i = 0; i < n; ++i) out[i] = p[i];
    return n;
}

}  // namespace

void bi_SliderDouble(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    static const char kSig[] =
        "[changed, v] = PsychImGui('SliderDouble', label, v, vMin, vMax [, format='%.3f'] "
        "[, flags=0])";
    if (nargin < 4 || nargin > 6) {
        mrs::usage("SliderDouble", kSig);
        return;
    }
    mrs::StrBuf<256> bLabel;
    mrs::StrBuf<64> bFmt;
    const char* label = mrs::toUtf8(args[0], "label", bLabel);
    double v[kMaxComponents];
    int n = get_components(args[1], "SliderDouble", v);
    double vMin = mrs::getScalar(args[2], "vMin");
    double vMax = mrs::getScalar(args[3], "vMax");
    const char* fmt = "%.3f";
    if (nargin > 4 && !mxIsEmpty(args[4])) fmt = mrs::toUtf8(args[4], "format", bFmt);
    int flags = 0;
    if (nargin > 5) flags = (int)mrs::getFlags(args[5], "flags");
    if (mrs::failed() || !mrs::checkDoubleFormat(fmt, "format")) return;
    bool changed = ImGui::SliderScalarN(label, ImGuiDataType_Double, v, n, &vMin, &vMax, fmt,
                                        (ImGuiSliderFlags)flags);
    if (nlhs > 0) plhs[0] = mrs::outBool(changed);
    if (nlhs > 1) plhs[1] = mrs::outVec(v, n);
}

void bi_DragDouble(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    static const char kSig[] =
        "[changed, v] = PsychImGui('DragDouble', label, v [, vSpeed=1.0] [, vMin=0.0] "
        "[, vMax=0.0] [, format='%.3f'] [, flags=0])";
    if (nargin < 2 || nargin > 7) {
        mrs::usage("DragDouble", kSig);
        return;
    }
    mrs::StrBuf<256> bLabel;
    mrs::StrBuf<64> bFmt;
    const char* label = mrs::toUtf8(args[0], "label", bLabel);
    double v[kMaxComponents];
    int n = get_components(args[1], "DragDouble", v);
    float speed = 1.0f;
    double vMin = 0.0, vMax = 0.0;
    if (nargin > 2) speed = (float)mrs::getScalar(args[2], "vSpeed");
    if (nargin > 3) vMin = mrs::getScalar(args[3], "vMin");
    if (nargin > 4) vMax = mrs::getScalar(args[4], "vMax");
    const char* fmt = "%.3f";
    if (nargin > 5 && !mxIsEmpty(args[5])) fmt = mrs::toUtf8(args[5], "format", bFmt);
    int flags = 0;
    if (nargin > 6) flags = (int)mrs::getFlags(args[6], "flags");
    if (mrs::failed() || !mrs::checkDoubleFormat(fmt, "format")) return;
    // Dear ImGui treats vMin >= vMax as no bounds, as DragFloat does.
    bool changed = ImGui::DragScalarN(label, ImGuiDataType_Double, v, n, speed, &vMin, &vMax,
                                      fmt, (ImGuiSliderFlags)flags);
    if (nlhs > 0) plhs[0] = mrs::outBool(changed);
    if (nlhs > 1) plhs[1] = mrs::outVec(v, n);
}

// The specs are cleared as they are read, so `dirty` is true once per change.
// That is the read-sort-clear sequence of Dear ImGui's own examples, in one
// call.
void bi_TableGetSortSpecs(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    static const char kSig[] = "[specs, dirty] = PsychImGui('TableGetSortSpecs')";
    if (nargin != 0) {
        mrs::usage("TableGetSortSpecs", kSig);
        return;
    }
    // Dear ImGui dereferences the current table after an assert that returns.
    if (ImGui::TableGetColumnCount() == 0) {
        mrs::fail("psychimgui:Usage",
                  "TableGetSortSpecs needs an open table: call it between BeginTable and "
                  "EndTable.");
        return;
    }
    static const char* kFields[] = {"columnIndex", "sortOrder", "direction"};
    ImGuiTableSortSpecs* ss = ImGui::TableGetSortSpecs();
    int n = ss ? ss->SpecsCount : 0;
    bool dirty = ss && ss->SpecsDirty;
    if (nlhs > 0) {
        plhs[0] = mxCreateStructMatrix((mwSize)n, 1, 3, kFields);
        for (int i = 0; i < n; ++i) {
            const ImGuiTableColumnSortSpecs& c = ss->Specs[i];
            mxSetFieldByNumber(plhs[0], i, 0, mxCreateDoubleScalar(c.ColumnIndex));
            mxSetFieldByNumber(plhs[0], i, 1, mxCreateDoubleScalar(c.SortOrder));
            // The words of MATLAB's sort, so sort(x, s.direction) works.
            mxSetFieldByNumber(plhs[0], i, 2,
                               mxCreateString(c.SortDirection == ImGuiSortDirection_Descending
                                                  ? "descend"
                                                  : "ascend"));
        }
    }
    if (nlhs > 1) plhs[1] = mrs::outBool(dirty);
    if (ss) ss->SpecsDirty = false;
}

}  // namespace pig
