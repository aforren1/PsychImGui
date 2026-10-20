// Psychtoolbox texture arguments (SPEC.md section 5.7), shared by Image,
// ImageButton, and the PlotImage subcommands of ImPlot and ImPlot3D.
#pragma once

#include <stdint.h>
#include <string.h>

#include "imgui_psych.h"
#include "marshal.h"
#include "mex.h"

namespace pig {

inline const mxArray* texField(const mxArray* s, const char* name) {
    int n = mxGetFieldNumber(s, name);
    return n < 0 ? nullptr : mxGetFieldByNumber(s, 0, n);
}

constexpr double kGL_TEXTURE_2D = 3553.0;         // 0x0DE1
constexpr double kGL_TEXTURE_RECTANGLE = 34037.0;  // 0x84F5

// A texture argument resolved to a GL name and the affine map from image
// coordinates to texture coordinates:
//   u = map[0] + x * map[2] + y * map[4]
//   v = map[1] + x * map[3] + y * map[5]
// x and y run from 0 to 1 over the image, left to right and top to bottom.
// Psychtoolbox stores a texture made from a MATLAB matrix transposed, so its u
// follows y. A uv0/uv1 pair cannot say that; this map can.
struct TexDesc {
    ImTextureID id;
    double map[6];
    bool nearest;
};

inline void tex_map(const TexDesc& t, double x, double y, ImVec2& out) {
    out.x = (float)(t.map[0] + x * t.map[2] + y * t.map[4]);
    out.y = (float)(t.map[1] + x * t.map[3] + y * t.map[5]);
}

// Accepts a GL texture name, which is taken as an upright GL_TEXTURE_2D
// texture, or the struct from PsychImGuiImage.
inline void get_texture(const mxArray* a, const char* argname, TexDesc& t) {
    static const double kIdentity[6] = {0, 0, 1, 0, 0, 1};
    memcpy(t.map, kIdentity, sizeof(kIdentity));
    t.id = ImTextureID_Invalid;
    t.nearest = false;
    if (mrs::failed()) return;

    const mxArray* idArr = a;
    if (a && mxIsStruct(a)) {
        if (mxGetNumberOfElements(a) != 1) {
            mrs::fail("psychimgui:Type", "Argument '%s' must be one texture struct.", argname);
            return;
        }
        idArr = texField(a, "glId");
        const mxArray* target = texField(a, "glTarget");
        if (!idArr || !target) {
            mrs::fail("psychimgui:Type",
                      "Argument '%s' needs the fields glId and glTarget. Make it with "
                      "PsychImGuiImage(ig, ptbTexture).",
                      argname);
            return;
        }
        double tg = mrs::getScalar(target, "glTarget");
        if (mrs::failed()) return;
        if (tg != kGL_TEXTURE_2D) {
            mrs::fail("psychimgui:Texture",
                      "Argument '%s' is a %s texture (target 0x%04X). Dear ImGui's OpenGL "
                      "backends sample GL_TEXTURE_2D only. Create the Psychtoolbox texture "
                      "with specialFlags 1: Screen('MakeTexture', win, img, [], 1).",
                      argname, tg == kGL_TEXTURE_RECTANGLE ? "GL_TEXTURE_RECTANGLE" : "non 2D",
                      (unsigned)tg);
            return;
        }
        const mxArray* m = texField(a, "uvMap");
        if (m && !mxIsEmpty(m)) mrs::getVec(m, "uvMap", t.map, 6);
        const mxArray* fl = texField(a, "filter");
        if (fl && mxIsChar(fl)) {
            mrs::StrBuf<16> b;
            const char* f = mrs::toUtf8(fl, "filter", b);
            if (strcmp(f, "nearest") == 0)
                t.nearest = true;
            else if (strcmp(f, "linear") != 0)
                mrs::fail("psychimgui:Usage",
                          "Argument '%s': filter must be 'linear' or 'nearest', got '%s'.",
                          argname, f);
        }
    } else if (!a || !(mxIsNumeric(a) || mxIsLogical(a))) {
        mrs::fail("psychimgui:Type",
                  "Argument '%s' must be an OpenGL texture name or the struct from "
                  "PsychImGuiImage.",
                  argname);
        return;
    }
    // GL names are unsigned 32 bit, and 0 is ImTextureID_Invalid, which Dear
    // ImGui treats as "no texture".
    double id = mrs::getScalar(idArr, "glId");
    if (mrs::failed()) return;
    if (!(id >= 1.0 && id <= 4294967295.0) || id != (double)(uint64_t)id) {
        mrs::fail("psychimgui:Texture",
                  "Argument '%s': %g is not an OpenGL texture name (an integer from 1 to "
                  "2^32-1).",
                  argname, id);
        return;
    }
    t.id = (ImTextureID)(uint64_t)id;
}

}  // namespace pig
