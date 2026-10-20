// Hand-written ImPlot3D subcommands. See SPEC.md section 14.15.

#ifdef PSYCHIMGUI_IMPLOT3D

#include "imgui_psych.h"

#include "implot3d.h"

#include "implot3d_marshal.h"
#include "marshal.h"
#include "mex.h"
#include "texture_marshal.h"

namespace pig {

// ImPlot3D takes one uv per corner, so the texture map of a transposed
// Psychtoolbox texture goes straight in. The nearest filter of a texture
// struct is not applied: ImPlot3D sorts its triangles into its own draw list
// at EndPlot, where a sampler callback around this call would not reach.
void bi_ImPlot3DPlotImage(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {
    (void)nlhs;
    (void)plhs;
    static const char kCmd[] = "ImPlot3D.PlotImage";
    if (nargin < 3) {
        mrs::usage(kCmd,
                   "PsychImGui('ImPlot3D.PlotImage', labelId, tex, corners "
                   "[, tintCol=[1 1 1 1]] [, spec...])");
        return;
    }
    if (!mrs::implot3dPlotOpen()) {
        mrs::fail("psychimgui:Usage",
                  "%s needs an open plot: call it between ImPlot3D.BeginPlot and "
                  "ImPlot3D.EndPlot.",
                  kCmd);
        return;
    }
    mrs::StrBuf<256> bLabel;
    const char* label = mrs::toUtf8(args[0], "labelId", bLabel);
    TexDesc t;
    get_texture(args[1], "tex", t);
    if (mrs::failed()) return;
    const mxArray* c = args[2];
    if (!mxIsDouble(c) || mxIsComplex(c) || mxGetM(c) != 4 || mxGetN(c) != 3) {
        mrs::fail("psychimgui:Type",
                  "%s: corners must be a 4x3 double matrix, one [x y z] row per image corner: "
                  "top left, top right, bottom right, bottom left.",
                  kCmd);
        return;
    }
    const double* p = mxGetPr(c);
    ImPlot3DPoint q[4];
    for (int i = 0; i < 4; ++i) q[i] = ImPlot3DPoint(p[i], p[4 + i], p[8 + i]);
    int specAt = mrs::specStart3D(args, nargin, 3);
    double tint[4] = {1, 1, 1, 1};
    if (specAt > 3 && !mxIsEmpty(args[3])) mrs::getVec(args[3], "tintCol", tint, 4);
    ImPlot3DSpec spec;
    mrs::getSpec(args, nargin, specAt, spec, sizeof(double));
    if (mrs::failed()) return;
    // ImPlot3D flips v of every corner (v = 1 - v), its convention for an
    // image with v = 0 at the bottom. Flipping here first cancels that, so
    // the texture coordinates reach the GPU as tex_map gives them.
    static const double kCorner[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
    ImVec2 uv[4];
    for (int i = 0; i < 4; ++i) {
        tex_map(t, kCorner[i][0], kCorner[i][1], uv[i]);
        uv[i].y = 1.0f - uv[i].y;
    }
    ImPlot3D::PlotImage(label, ImTextureRef(t.id), q[0], q[1], q[2], q[3], uv[0], uv[1], uv[2],
                        uv[3], ImVec4((float)tint[0], (float)tint[1], (float)tint[2],
                                      (float)tint[3]),
                        spec);
}

}  // namespace pig

#endif  // PSYCHIMGUI_IMPLOT3D
