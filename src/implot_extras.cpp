// Hand-written ImPlot subcommands that the generator cannot express. See
// SPEC.md section 14.15.
//
// This is the one unit that includes implot_internal.h. The internal header
// wants IMGUI_DEFINE_MATH_OPERATORS before the first imgui.h of the unit,
// which the generated units cannot promise.

#ifdef PSYCHIMGUI_IMPLOT

#ifndef IMGUI_DEFINE_MATH_OPERATORS
#  define IMGUI_DEFINE_MATH_OPERATORS
#endif
#include "imgui_psych.h"

#include <string.h>

#include <type_traits>

#include "implot.h"
#include "implot_internal.h"

#include "implot_marshal.h"
#include "marshal.h"
#include "mex.h"
#include "gen_style_implot.h"
#include "texture_marshal.h"

namespace pig {

bool implotSubplotOpen() { return GImPlot != nullptr && GImPlot->CurrentSubplot != nullptr; }

namespace {

// Calls f with a null pointer of the element type of class c. The plot
// templates are instantiated for these ten types only.
template <typename F>
void with_class(mxClassID c, const char* cmd, F&& f) {
    switch (c) {
    case mxDOUBLE_CLASS: f((const double*)nullptr); break;
    case mxSINGLE_CLASS: f((const float*)nullptr); break;
    case mxINT8_CLASS: f((const ImS8*)nullptr); break;
    case mxUINT8_CLASS: f((const ImU8*)nullptr); break;
    case mxINT16_CLASS: f((const ImS16*)nullptr); break;
    case mxUINT16_CLASS: f((const ImU16*)nullptr); break;
    case mxINT32_CLASS: f((const ImS32*)nullptr); break;
    case mxUINT32_CLASS: f((const ImU32*)nullptr); break;
    case mxINT64_CLASS: f((const ImS64*)nullptr); break;
    case mxUINT64_CLASS: f((const ImU64*)nullptr); break;
    default: mrs::fail("psychimgui:Type", "%s: unsupported data class.", cmd); break;
    }
}

template <typename P>
using elem_t = std::remove_const_t<std::remove_pointer_t<P>>;

bool need_plot(const char* cmd) {
    if (mrs::implotPlotOpen()) return true;
    mrs::fail("psychimgui:Usage",
              "%s needs an open plot: call it between ImPlot.BeginPlot and ImPlot.EndPlot.",
              cmd);
    return false;
}

double opt_scalar(const mxArray** args, int specAt, int i, const char* name, double dflt) {
    if (i >= specAt || mxIsEmpty(args[i])) return dflt;
    return mrs::getScalar(args[i], name);
}

// ------------------------------------------------------------ axis links --

// ImPlot keeps the two pointers of a link across frames and writes the axis
// range back through them at EndPlot, so the storage must outlive every plot.
// A fixed table gives stable addresses, no allocation per call, and no
// pointer that a later call could free. Links are shared by every context.
constexpr int kMaxLinks = 64;
constexpr int kMaxLinkName = 48;

struct AxisLink {
    char name[kMaxLinkName];
    double range[2];
};

AxisLink g_links[kMaxLinks];
int g_linkCount = 0;

AxisLink* find_link(const char* name) {
    for (int i = 0; i < g_linkCount; ++i)
        if (strcmp(g_links[i].name, name) == 0) return &g_links[i];
    return nullptr;
}

// The link named by args[i], created with range lo, hi when it is new.
AxisLink* get_link(const mxArray* a, const char* cmd, double lo, double hi) {
    mrs::StrBuf<kMaxLinkName + 16> b;
    const char* name = mrs::toUtf8(a, "key", b);
    if (mrs::failed()) return nullptr;
    size_t len = strlen(name);
    if (len == 0 || len >= (size_t)kMaxLinkName) {
        mrs::fail("psychimgui:Usage", "%s: key must have 1 to %d characters.", cmd,
                  kMaxLinkName - 1);
        return nullptr;
    }
    AxisLink* l = find_link(name);
    if (l) return l;
    if (g_linkCount == kMaxLinks) {
        mrs::fail("psychimgui:Range", "%s: there are already %d axis links.", cmd, kMaxLinks);
        return nullptr;
    }
    l = &g_links[g_linkCount++];
    memcpy(l->name, name, len + 1);
    l->range[0] = lo;
    l->range[1] = hi;
    return l;
}

// ----------------------------------------------------------------- style --

// A pushed style variable, color, or colormap is in the live style until its
// pop restores the saved value, which would undo or freeze part of a theme.
bool implot_stacks_empty(const char* cmd) {
    if (GImPlot->StyleModifiers.Size == 0 && GImPlot->ColorModifiers.Size == 0 &&
        GImPlot->ColormapModifiers.Size == 0)
        return true;
    mrs::fail("psychimgui:Usage",
              "%s: pop every ImPlot.PushStyleVar, PushStyleColor, and PushColormap first.", cmd);
    return false;
}

}  // namespace

void bi_ImPlotGetStyle(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)args;
    if (nargin != 0) {
        mrs::usage("ImPlot.GetStyle", "s = PsychImGui('ImPlot.GetStyle')");
        return;
    }
    if (!GImPlot) {
        mrs::fail("psychimgui:Usage", "ImPlot.GetStyle: ImPlot is off for this context.");
        return;
    }
    if (!implot_stacks_empty("ImPlot.GetStyle")) return;
    if (nlhs > 0) plhs[0] = styleToStruct(kImPlotStyleDesc, &ImPlot::GetStyle());
}

void bi_ImPlotSetStyle(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin != 1) {
        mrs::usage("ImPlot.SetStyle", "PsychImGui('ImPlot.SetStyle', s)");
        return;
    }
    if (!GImPlot) {
        mrs::fail("psychimgui:Usage", "ImPlot.SetStyle: ImPlot is off for this context.");
        return;
    }
    if (!implot_stacks_empty("ImPlot.SetStyle")) return;
    ImPlotStyle next = ImPlot::GetStyle();
    if (!styleFromStruct(kImPlotStyleDesc, args[0], &next)) return;
    ImPlot::GetStyle() = next;
    // Items keep the colormap colors they were given; a new theme recolors them.
    ImPlot::BustColorCache();
}

namespace {

}  // namespace

void bi_ImPlotSetupAxisLinks(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin != 2) {
        mrs::usage("ImPlot.SetupAxisLinks", "PsychImGui('ImPlot.SetupAxisLinks', axis, key)");
        return;
    }
    int axis = (int)mrs::getEnumRanged(args[0], "axis", 0, ImAxis_COUNT - 1);
    if (mrs::failed() || !need_plot("ImPlot.SetupAxisLinks")) return;
    // A new link starts at the axis's range, so SetupAxisLimits before this
    // call sets the first range of every plot that shares the link.
    const ImPlotRange& r = GImPlot->CurrentPlot->Axes[axis].Range;
    AxisLink* l = get_link(args[1], "ImPlot.SetupAxisLinks", r.Min, r.Max);
    if (!l) return;
    ImPlot::SetupAxisLinks(axis, &l->range[0], &l->range[1]);
}

void bi_ImPlotSetNextAxisLinks(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    if (nargin != 2) {
        mrs::usage("ImPlot.SetNextAxisLinks", "PsychImGui('ImPlot.SetNextAxisLinks', axis, key)");
        return;
    }
    int axis = (int)mrs::getEnumRanged(args[0], "axis", 0, ImAxis_COUNT - 1);
    // ImPlot's default range, since no plot is open to take one from.
    AxisLink* l = get_link(args[1], "ImPlot.SetNextAxisLinks", 0.0, 1.0);
    if (!l) return;
    ImPlot::SetNextAxisLinks(axis, &l->range[0], &l->range[1]);
}

void bi_ImPlotAxisLink(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    if (nargin < 1 || nargin > 2) {
        mrs::usage("ImPlot.AxisLink", "range = PsychImGui('ImPlot.AxisLink', key [, range])");
        return;
    }
    if (nargin == 2) {
        double r[2] = {0, 1};
        mrs::getVec(args[1], "range", r, 2);
        AxisLink* l = get_link(args[0], "ImPlot.AxisLink", r[0], r[1]);
        if (!l) return;
        l->range[0] = r[0];
        l->range[1] = r[1];
        if (nlhs > 0) plhs[0] = mrs::outVec(l->range, 2);
        return;
    }
    mrs::StrBuf<kMaxLinkName + 16> b;
    const char* name = mrs::toUtf8(args[0], "key", b);
    if (mrs::failed()) return;
    AxisLink* l = find_link(name);
    if (!l) {
        mrs::fail("psychimgui:Usage",
                  "ImPlot.AxisLink: no axis link named '%s'. SetupAxisLinks, SetNextAxisLinks, "
                  "or AxisLink with a range creates one.",
                  name);
        return;
    }
    if (nlhs > 0) plhs[0] = mrs::outVec(l->range, 2);
}

// ------------------------------------------------------------ bar groups --

// values is groups x items, one column per item, as MATLAB's bar takes it.
// Column major storage then puts item i, group g at i * groups + g, which is
// the order ImPlot reads, so no copy is needed.
void bi_ImPlotPlotBarGroups(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    static const char kCmd[] = "ImPlot.PlotBarGroups";
    if (nargin < 2) {
        mrs::usage(kCmd,
                   "PsychImGui('ImPlot.PlotBarGroups', labels, values [, groupSize=0.67] "
                   "[, shift=0] [, spec...])");
        return;
    }
    if (!need_plot(kCmd)) return;
    mrs::CellStr cs;
    const char* const* labels = mrs::getCellStr(args[0], "labels", cs);
    int count = 0;
    mxClassID cid = mrs::checkData(args, 1, 1, kCmd, &count);
    if (mrs::failed()) return;
    int groups = (int)mxGetM(args[1]);
    int items = (int)mxGetN(args[1]);
    if (cs.n != items) {
        mrs::fail("psychimgui:Usage",
                  "%s: %d labels for %d columns of values. Give one label per column.", kCmd,
                  cs.n, items);
        return;
    }
    int specAt = mrs::specStart(args, nargin, 2);
    double groupSize = opt_scalar(args, specAt, 2, "groupSize", 0.67);
    double shift = opt_scalar(args, specAt, 3, "shift", 0.0);
    if (mrs::failed()) return;
    with_class(cid, kCmd, [&](auto tag) {
        using T = elem_t<decltype(tag)>;
        ImPlotSpec spec;
        mrs::getSpec(args, nargin, specAt, spec, sizeof(T));
        if (mrs::failed()) return;
        ImPlot::PlotBarGroups(labels, (const T*)mxGetData(args[1]), items, groups, groupSize,
                              shift, spec);
    });
}

// ------------------------------------------------------------- pie chart --

void bi_ImPlotPlotPieChart(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    static const char kCmd[] = "ImPlot.PlotPieChart";
    if (nargin < 5) {
        mrs::usage(kCmd,
                   "PsychImGui('ImPlot.PlotPieChart', labels, values, x, y, radius "
                   "[, labelFmt='%.1f'] [, angle0=90] [, spec...])");
        return;
    }
    if (!need_plot(kCmd)) return;
    mrs::CellStr cs;
    const char* const* labels = mrs::getCellStr(args[0], "labels", cs);
    int count = 0;
    mxClassID cid = mrs::checkData(args, 1, 1, kCmd, &count);
    if (mrs::failed()) return;
    if (cs.n != count) {
        mrs::fail("psychimgui:Usage", "%s: %d labels for %d values. Give one label per value.",
                  kCmd, cs.n, count);
        return;
    }
    double x = mrs::getScalar(args[2], "x");
    double y = mrs::getScalar(args[3], "y");
    double radius = mrs::getScalar(args[4], "radius");
    int specAt = mrs::specStart(args, nargin, 5);
    mrs::StrBuf<64> bFmt;
    // [] hides the slice labels, as a NULL format does in ImPlot.
    const char* fmt = "%.1f";
    if (specAt > 5) fmt = mxIsEmpty(args[5]) ? nullptr : mrs::toUtf8(args[5], "labelFmt", bFmt);
    double angle0 = opt_scalar(args, specAt, 6, "angle0", 90.0);
    if (mrs::failed() || !mrs::checkDoubleFormat(fmt, "labelFmt")) return;
    with_class(cid, kCmd, [&](auto tag) {
        using T = elem_t<decltype(tag)>;
        ImPlotSpec spec;
        mrs::getSpec(args, nargin, specAt, spec, sizeof(T));
        if (mrs::failed()) return;
        // ImPlot's string form hands a NULL format to snprintf. No labels
        // is the formatter form with no formatter.
        if (fmt)
            ImPlot::PlotPieChart(labels, (const T*)mxGetData(args[1]), count, x, y, radius,
                                 fmt, angle0, spec);
        else
            ImPlot::PlotPieChart(labels, (const T*)mxGetData(args[1]), count, x, y, radius,
                                 (ImPlotFormatter) nullptr, nullptr, angle0, spec);
    });
}

// ----------------------------------------------------------------- image --

// ImPlot draws an image with one uv pair, which cannot turn a transposed
// Psychtoolbox texture upright. For such a texture ImPlot still adds the item,
// for the legend and the fit, with a transparent tint, and the image goes on
// top as a quad with one uv per corner, as Image does (SPEC.md 5.7).
void bi_ImPlotPlotImage(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    static const char kCmd[] = "ImPlot.PlotImage";
    if (nargin < 4) {
        mrs::usage(kCmd,
                   "PsychImGui('ImPlot.PlotImage', labelId, tex, boundsMin, boundsMax "
                   "[, uv0=[0 0]] [, uv1=[1 1]] [, tintCol=[1 1 1 1]] [, spec...])");
        return;
    }
    if (!need_plot(kCmd)) return;
    mrs::StrBuf<256> bLabel;
    const char* label = mrs::toUtf8(args[0], "labelId", bLabel);
    TexDesc t;
    get_texture(args[1], "tex", t);
    double bmin[2] = {0, 0}, bmax[2] = {1, 1};
    mrs::getVec(args[2], "boundsMin", bmin, 2);
    mrs::getVec(args[3], "boundsMax", bmax, 2);
    int specAt = mrs::specStart(args, nargin, 4);
    double uv0[2] = {0, 0}, uv1[2] = {1, 1}, tint[4] = {1, 1, 1, 1};
    if (specAt > 4 && !mxIsEmpty(args[4])) mrs::getVec(args[4], "uv0", uv0, 2);
    if (specAt > 5 && !mxIsEmpty(args[5])) mrs::getVec(args[5], "uv1", uv1, 2);
    if (specAt > 6 && !mxIsEmpty(args[6])) mrs::getVec(args[6], "tintCol", tint, 4);
    ImPlotSpec spec;
    mrs::getSpec(args, nargin, specAt, spec, sizeof(double));
    if (mrs::failed()) return;

    ImVec2 tl, tr, br, bl;
    tex_map(t, uv0[0], uv0[1], tl);
    tex_map(t, uv1[0], uv0[1], tr);
    tex_map(t, uv1[0], uv1[1], br);
    tex_map(t, uv0[0], uv1[1], bl);
    bool aligned = (t.map[3] == 0.0 && t.map[4] == 0.0);
    ImVec4 tintCol((float)tint[0], (float)tint[1], (float)tint[2], (float)tint[3]);
    ImTextureRef ref(t.id);
    ImPlotPoint pMin(bmin[0], bmin[1]), pMax(bmax[0], bmax[1]);

    const ImGuiPlatformIO& pio = ImGui::GetPlatformIO();
    bool nearest = t.nearest && pio.DrawCallback_SetSamplerNearest &&
                   pio.DrawCallback_SetSamplerLinear;
    ImDrawList* dl = ImPlot::GetPlotDrawList();
    if (nearest) dl->AddCallback(pio.DrawCallback_SetSamplerNearest, nullptr);
    ImPlot::PlotImage(label, ref, pMin, pMax, tl, br, aligned ? tintCol : ImVec4(0, 0, 0, 0),
                      spec);
    if (!aligned) {
        ImPlotItem* item = ImPlot::GetItem(label);
        ImU32 col = ImGui::ColorConvertFloat4ToU32(tintCol);
        // The legend shows the item's color, which the transparent tint set.
        if (item) item->Color = col;
        if (item && item->Show) {
            // Image top left is the plot's (xMin, yMax), as in ImPlot.
            ImVec2 p0 = ImPlot::PlotToPixels(pMin.x, pMax.y, IMPLOT_AUTO, IMPLOT_AUTO);
            ImVec2 p1 = ImPlot::PlotToPixels(pMax.x, pMax.y, IMPLOT_AUTO, IMPLOT_AUTO);
            ImVec2 p2 = ImPlot::PlotToPixels(pMax.x, pMin.y, IMPLOT_AUTO, IMPLOT_AUTO);
            ImVec2 p3 = ImPlot::PlotToPixels(pMin.x, pMin.y, IMPLOT_AUTO, IMPLOT_AUTO);
            ImPlot::PushPlotClipRect();
            dl->AddImageQuad(ref, p0, p1, p2, p3, tl, tr, br, bl, col);
            ImPlot::PopPlotClipRect();
        }
    }
    if (nearest) dl->AddCallback(pio.DrawCallback_SetSamplerLinear, nullptr);
}

}  // namespace pig

#endif  // PSYCHIMGUI_IMPLOT
