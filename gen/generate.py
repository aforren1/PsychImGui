#!/usr/bin/env python3
"""Generate the psychimgui binding surface from the cimgui metadata.

Reads third_party/cimgui/generator/output/{definitions,structs_and_enums}.json
and the matching cimplot and cimplot3d files, filters them through
gen/allowlist.txt, and writes:

    src/gen_dispatch.cpp         handlers, sorted name table, enum value table,
                                 including the [DrawList] section
    src/gen_dispatch_implot.cpp  the same for the ImPlot namespace
    src/gen_dispatch_implot3d.cpp  the same for the ImPlot3D namespace
    m/PsychImGui.m               help text with every signature
    m/PsychImGuiOp.m             opcode constants for the fast path
    tests/test_gen_marshal.m     one round trip per subcommand

Standard library only, so the generator runs anywhere Python 3.10 runs. The
outputs are committed, so a user who only builds needs no Python.

Usage:  uv run gen/generate.py [--root <psychimgui dir>]
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

# --------------------------------------------------------------------------
# Hand-written subcommands. They live in src/PsychImGui.cpp, but they share one
# sorted table with the generated ones so dispatch and opcode numbering stay
# uniform.
#
# (MATLAB name, handler symbol, needs Init, needs a GL context, signature)
# --------------------------------------------------------------------------
BUILTINS = [
    ("AddFontFromFileTTF", "bi_AddFontFromFileTTF", True, True,
     "idx = PsychImGui('AddFontFromFileTTF', path, sizePx [, glyphRanges])"),
    ("EndFrame", "bi_EndFrame", True, False, "PsychImGui('EndFrame')"),
    # Image and ImageButton are hand-written: a Psychtoolbox texture is stored
    # transposed, which a uv0/uv1 pair cannot express. See SPEC.md 5.7.
    ("Image", "bi_Image", True, False,
     "PsychImGui('Image', tex, size [, uv0=[0 0]] [, uv1=[1 1]] [, bgCol=[0 0 0 0]] "
     "[, tintCol=[1 1 1 1]])"),
    ("ImageButton", "bi_ImageButton", True, False,
     "pressed = PsychImGui('ImageButton', strId, tex, size [, uv0=[0 0]] [, uv1=[1 1]] "
     "[, bgCol=[0 0 0 0]] [, tintCol=[1 1 1 1]])"),
    # Hand-written in extras.cpp, implot_extras.cpp, and implot3d_extras.cpp:
    # void pointer data, struct results, label arrays, MEX-owned link storage,
    # and transposed textures, which the generator rules cannot express.
    # SPEC.md 14.15. BUILTIN_EXTRA below gives their frame and namespace.
    # Themes: the style as a struct, without the global scale (SPEC.md 14.16).
    ("GetStyle", "bi_GetStyle", True, False, "s = PsychImGui('GetStyle')"),
    ("SetStyle", "bi_SetStyle", True, False, "PsychImGui('SetStyle', s)"),
    ("ImPlot.GetStyle", "bi_ImPlotGetStyle", True, False, "s = PsychImGui('ImPlot.GetStyle')"),
    ("ImPlot.SetStyle", "bi_ImPlotSetStyle", True, False, "PsychImGui('ImPlot.SetStyle', s)"),
    ("ImPlot3D.GetStyle", "bi_ImPlot3DGetStyle", True, False,
     "s = PsychImGui('ImPlot3D.GetStyle')"),
    ("ImPlot3D.SetStyle", "bi_ImPlot3DSetStyle", True, False,
     "PsychImGui('ImPlot3D.SetStyle', s)"),
    ("SliderDouble", "bi_SliderDouble", True, False,
     "[changed, v] = PsychImGui('SliderDouble', label, v, vMin, vMax [, format='%.3f'] "
     "[, flags=0])"),
    ("DragDouble", "bi_DragDouble", True, False,
     "[changed, v] = PsychImGui('DragDouble', label, v [, vSpeed=1.0] [, vMin=0.0] "
     "[, vMax=0.0] [, format='%.3f'] [, flags=0])"),
    ("TableGetSortSpecs", "bi_TableGetSortSpecs", True, False,
     "[specs, dirty] = PsychImGui('TableGetSortSpecs')"),
    ("ImPlot.PlotBarGroups", "bi_ImPlotPlotBarGroups", True, False,
     "PsychImGui('ImPlot.PlotBarGroups', labels, values [, groupSize=0.67] [, shift=0] "
     "[, spec...])"),
    ("ImPlot.PlotPieChart", "bi_ImPlotPlotPieChart", True, False,
     "PsychImGui('ImPlot.PlotPieChart', labels, values, x, y, radius [, labelFmt='%.1f'] "
     "[, angle0=90] [, spec...])"),
    ("ImPlot.PlotImage", "bi_ImPlotPlotImage", True, False,
     "PsychImGui('ImPlot.PlotImage', labelId, tex, boundsMin, boundsMax [, uv0=[0 0]] "
     "[, uv1=[1 1]] [, tintCol=[1 1 1 1]] [, spec...])"),
    ("ImPlot.SetupAxisLinks", "bi_ImPlotSetupAxisLinks", True, False,
     "PsychImGui('ImPlot.SetupAxisLinks', axis, key)"),
    ("ImPlot.SetNextAxisLinks", "bi_ImPlotSetNextAxisLinks", True, False,
     "PsychImGui('ImPlot.SetNextAxisLinks', axis, key)"),
    ("ImPlot.AxisLink", "bi_ImPlotAxisLink", False, False,
     "range = PsychImGui('ImPlot.AxisLink', key [, range])"),
    ("ImPlot3D.PlotImage", "bi_ImPlot3DPlotImage", True, False,
     "PsychImGui('ImPlot3D.PlotImage', labelId, tex, corners [, tintCol=[1 1 1 1]] "
     "[, spec...])"),
    ("Enum", "bi_Enum", False, False,
     "v = PsychImGui('Enum' [, 'ImGuiWindowFlags_NoTitleBar'])"),
    # The FileDialog subcommands are hand-written: ImGuiFileDialog has no
    # cimgui-family metadata. See SPEC.md 5.4 and 14.11.
    ("FileDialog.Close", "bi_FileDialogClose", True, False, "PsychImGui('FileDialog.Close')"),
    ("FileDialog.Display", "bi_FileDialogDisplay", True, False,
     "[done, open] = PsychImGui('FileDialog.Display', key [, minSize=[0 0]] "
     "[, maxSize=[FLT_MAX FLT_MAX]] [, windowFlags=ImGuiWindowFlags_NoCollapse])"),
    ("FileDialog.GetCurrentPath", "bi_FileDialogGetCurrentPath", True, False,
     "path = PsychImGui('FileDialog.GetCurrentPath')"),
    ("FileDialog.GetFilePathName", "bi_FileDialogGetFilePathName", True, False,
     "path = PsychImGui('FileDialog.GetFilePathName')"),
    ("FileDialog.GetSelection", "bi_FileDialogGetSelection", True, False,
     "paths = PsychImGui('FileDialog.GetSelection')"),
    ("FileDialog.IsOk", "bi_FileDialogIsOk", True, False, "ok = PsychImGui('FileDialog.IsOk')"),
    ("FileDialog.IsOpened", "bi_FileDialogIsOpened", True, False,
     "open = PsychImGui('FileDialog.IsOpened' [, key])"),
    ("FileDialog.Open", "bi_FileDialogOpen", True, False,
     "PsychImGui('FileDialog.Open', key, title, filters [, path='.'] [, fileName=''] "
     "[, maxSelection=1] [, flags=0])"),
    ("GetContext", "bi_GetContext", False, False, "[ctx, all] = PsychImGui('GetContext')"),
    ("Init", "bi_Init", False, False, "ctx = PsychImGui('Init', win, rect, keymap [, opts])"),
    # NewFrame needs the window's GL context because the OpenGL 3 backend
    # creates its shader and font texture on the first frame.
    ("NewFrame", "bi_NewFrame", True, True, "PsychImGui('NewFrame', in)"),
    ("Opcode", "bi_Opcode", False, False, "op = PsychImGui('Opcode', 'SliderFloat')"),
    ("PopFont", "bi_PopFont", True, False, "PsychImGui('PopFont')"),
    ("PushFont", "bi_PushFont", True, False, "PsychImGui('PushFont', idx [, sizePx])"),
    ("Render", "bi_Render", True, True, "PsychImGui('Render')"),
    # The second eye of a stereo mode: the same draw data, submitted again.
    ("RenderAgain", "bi_RenderAgain", True, True, "PsychImGui('RenderAgain')"),
    ("SetContext", "bi_SetContext", False, False, "PsychImGui('SetContext', ctx)"),
    ("SetGlobalScale", "bi_SetGlobalScale", True, False, "PsychImGui('SetGlobalScale', s)"),
    ("SetTextureFilter", "bi_SetTextureFilter", True, True,
     "PsychImGui('SetTextureFilter', glId [, mode='linear'])"),
    ("ShowDemoWindow", "bi_ShowDemoWindow", True, False,
     "[open] = PsychImGui('ShowDemoWindow' [, open])"),
    ("ShowMetricsWindow", "bi_ShowMetricsWindow", True, False,
     "[open] = PsychImGui('ShowMetricsWindow' [, open])"),
    ("Shutdown", "bi_Shutdown", False, False, "PsychImGui('Shutdown' [, ctx | 'all'])"),
    ("Stats", "bi_Stats", False, False, "s = PsychImGui('Stats' [, 'reset'])"),
    ("StyleColorsClassic", "bi_StyleColorsClassic", True, False,
     "PsychImGui('StyleColorsClassic')"),
    ("StyleColorsDark", "bi_StyleColorsDark", True, False, "PsychImGui('StyleColorsDark')"),
    ("StyleColorsLight", "bi_StyleColorsLight", True, False, "PsychImGui('StyleColorsLight')"),
    ("Version", "bi_Version", False, False, "v = PsychImGui('Version')"),
    ("WantCapture", "bi_WantCapture", True, False,
     "[mouse, keyboard, text] = PsychImGui('WantCapture')"),
]

# Dispatch details of the hand-written subcommands that are not lifecycle
# calls: whether they need an open frame, and which build option compiles them.
BUILTIN_EXTRA = {
    "GetStyle": {"frame": False},
    "SetStyle": {"frame": False},
    "ImPlot.GetStyle": {"frame": False, "macro": "PIG_IMPLOT_FN"},
    "ImPlot.SetStyle": {"frame": False, "macro": "PIG_IMPLOT_FN"},
    "ImPlot3D.GetStyle": {"frame": False, "macro": "PIG_IMPLOT3D_FN"},
    "ImPlot3D.SetStyle": {"frame": False, "macro": "PIG_IMPLOT3D_FN"},
    "SliderDouble": {"frame": True},
    "DragDouble": {"frame": True},
    "TableGetSortSpecs": {"frame": True},
    "ImPlot.PlotBarGroups": {"frame": True, "macro": "PIG_IMPLOT_FN"},
    "ImPlot.PlotPieChart": {"frame": True, "macro": "PIG_IMPLOT_FN"},
    "ImPlot.PlotImage": {"frame": True, "macro": "PIG_IMPLOT_FN"},
    "ImPlot.SetupAxisLinks": {"frame": True, "macro": "PIG_IMPLOT_FN"},
    "ImPlot.SetNextAxisLinks": {"frame": False, "macro": "PIG_IMPLOT_FN"},
    "ImPlot.AxisLink": {"frame": False, "macro": "PIG_IMPLOT_FN"},
    "ImPlot3D.PlotImage": {"frame": True, "macro": "PIG_IMPLOT3D_FN"},
}

# Cosmetic names for the first output of a value returning function.
RET_NAMES = {
    "Begin": "open", "BeginChild": "visible", "Button": "pressed",
    "SmallButton": "pressed", "InvisibleButton": "pressed", "ArrowButton": "pressed",
    "Selectable": "pressed", "MenuItem": "activated", "TreeNode": "open",
    "CollapsingHeader": "open", "BeginCombo": "open", "BeginListBox": "open",
    "BeginMenu": "open", "BeginMenuBar": "open", "BeginPopup": "open",
    "BeginPopupModal": "open", "BeginTabBar": "open", "BeginTabItem": "open",
    "BeginTooltip": "open", "BeginPlot": "open", "BeginSubplots": "open",
    "BeginTable": "open", "TableNextColumn": "visible", "TableSetColumnIndex": "visible",
    "GetPlotRectPos": "pos", "GetPlotRectSize": "size", "PlotToPixels": "pix",
    "GetWindowDrawList": "drawList", "GetBackgroundDrawList": "drawList",
    "GetForegroundDrawList": "drawList", "TableGetColumnCount": "count",
    "TableGetColumnIndex": "index",
    "TreeNodeEx": "open", "CollapsingHeaderClosable": "open", "BeginMainMenuBar": "open",
    "BeginItemTooltip": "open", "BeginPopupContextItem": "open",
    "BeginPopupContextWindow": "open", "BeginPopupContextVoid": "open",
    "TabItemButton": "pressed", "TextLink": "pressed", "GetKeyName": "name",
    "SaveIniSettingsToMemory": "ini", "BeginAlignedPlots": "open",
    "BeginLegendPopup": "open", "GetPlotSelection": "rect", "GetPlotDrawList": "drawList",
    "ColormapButton": "pressed", "PixelsToPlotPlane": "point",
}

# Test values that differ from the generic one for a kind, because the function
# asserts on the generic value.
TEST_ARG_OVERRIDE = {
    ("ArrowButton", "dir"): "0",
    ("IsKeyPressed", "key"): "'ImGuiKey_A'",
    ("IsKeyDown", "key"): "'ImGuiKey_A'",
    ("IsKeyReleased", "key"): "'ImGuiKey_A'",
    ("GetKeyName", "key"): "'ImGuiKey_A'",
    # The generic 'x' would match a tab left selected by the BeginTabItem test.
    ("TabItemButton", "label"): "'genTabBtn'",
    ("IsKeyChordPressed", "keyChord"): "{'ImGuiMod_Ctrl', 'ImGuiKey_S'}",
    ("Shortcut", "keyChord"): "{'ImGuiMod_Ctrl', 'ImGuiKey_S'}",
    ("PushStyleVarX", "idx"): "'ImGuiStyleVar_ItemSpacing'",
    ("PushStyleVarY", "idx"): "'ImGuiStyleVar_ItemSpacing'",
    ("PushStyleVarX", "valX"): "4",
    ("PushStyleVarY", "valY"): "4",
    ("SliderFloat4", "vMax"): "1",
    ("SliderInt2", "vMax"): "10",
    ("SliderInt3", "vMax"): "10",
    ("SliderInt4", "vMax"): "10",
    ("LoadIniSettingsFromMemory", "iniData"): "''",
    ("ImPlot3D.PushStyleVarInt", "idx"): "'ImPlot3DStyleVar_Marker'",
    ("ImPlot3D.PushStyleVarInt", "val"): "1",
    ("ImPlot3D.AddColormap", "name"): "'genCmap3D'",
    ("InvisibleButton", "size"): "[12 12]",
    ("VSliderFloat", "size"): "[20 60]",
    ("VSliderInt", "size"): "[20 60]",
    ("PushStyleColor", "idx"): "'ImGuiCol_Text'",
    ("PushStyleVar", "idx"): "'ImGuiStyleVar_Alpha'",
    ("PushStyleVar", "val"): "1",
    ("PushStyleVarVec2", "idx"): "'ImGuiStyleVar_ItemSpacing'",
    ("PushStyleVarVec2", "val"): "[4 4]",
    ("SetNextWindowSize", "size"): "[120 80]",
    ("SetNextWindowPos", "pos"): "[10 10]",
    ("BeginChild", "size"): "[60 40]",
    ("SliderFloat", "vMax"): "1",
    ("SliderFloat2", "vMax"): "1",
    ("SliderFloat3", "vMax"): "1",
    ("SliderInt", "vMax"): "10",
    ("VSliderFloat", "vMax"): "1",
    ("VSliderInt", "vMax"): "10",
    ("CheckboxFlags", "flagsValue"): "1",
    ("RadioButtonInt", "vButton"): "0",
    ("PlotLines", "values"): "[0 1 0 -1]",
    ("PlotHistogram", "values"): "[0 1 0 2]",
    ("PushColormapIndex", "cmap"): "0",
    ("ImPlot.SetupAxis", "axis"): "'ImAxis_X1'",
    ("ImPlot.SetupAxisLimits", "axis"): "'ImAxis_X1'",
    ("ImPlot.SetupAxisFormat", "axis"): "'ImAxis_X1'",
    ("ImPlot.SetupAxisTicks", "axis"): "'ImAxis_X1'",
    ("ImPlot.IsAxisHovered", "axis"): "'ImAxis_X1'",
    ("ImPlot.SetNextAxisLimits", "axis"): "'ImAxis_X1'",
    # SetAxes asserts that the second axis is a Y axis.
    ("ImPlot.SetAxes", "yAxis"): "'ImAxis_Y1'",
    # ImPlot asserts that the style variable matches the Push variant.
    ("ImPlot.PushStyleVar", "idx"): "'ImPlotStyleVar_PlotBorderSize'",
    ("ImPlot.PushColormap", "name"): "'Viridis'",
    ("ImPlot.PushStyleVarVec2", "idx"): "'ImPlotStyleVar_PlotPadding'",
    ("ImPlot.PushStyleVarVec2", "val"): "[5 5]",
    ("ImPlot.BeginSubplots", "size"): "[300 200]",
    ("ImPlot.BeginSubplots", "rows"): "1",
    ("ImPlot.BeginSubplots", "cols"): "1",
    ("ImPlot.ColormapScale", "size"): "[60 200]",
    ("BeginTable", "columns"): "3",
    ("ImPlot3D.SetupAxis", "axis"): "'ImAxis3D_X'",
    ("ImPlot3D.SetupAxisLimits", "axis"): "'ImAxis3D_X'",
    ("ImPlot3D.SetupAxisTicks", "axis"): "'ImAxis3D_X'",
    ("ImPlot3D.SetupLegend", "location"): "'ImPlot3DLocation_North'",
    ("ImPlot3D.PushColormap", "name"): "'Viridis'",
    ("ImPlot3D.PushColormapIndex", "cmap"): "0",
    ("ImPlot3D.GetColormapName", "cmap"): "0",
    ("ImPlot3D.PushStyleColor", "idx"): "'ImPlot3DCol_TitleText'",
    ("ImPlot3D.SetupBoxScale", "x"): "1",
    ("ImPlot3D.SetupBoxScale", "y"): "1",
    ("ImPlot3D.SetupBoxScale", "z"): "1",
    ("ImPlot3D.PushStyleVar", "idx"): "'ImPlot3DStyleVar_LineWeight'",
    ("ImPlot3D.PushStyleVar", "val"): "1",
    ("ImPlot3D.PushStyleVarVec2", "idx"): "'ImPlot3DStyleVar_LegendPadding'",
    ("ImPlot3D.PushStyleVarVec2", "val"): "[5 5]",
    ("TableSetBgColor", "target"): "'ImGuiTableBgTarget_CellBg'",
}

# Scope pairing used by the generated test. A True flag means the closer runs
# whatever the opener returned.
PAIRS = {
    "Begin": ("End", True),
    "BeginChild": ("EndChild", True),
    "BeginGroup": ("EndGroup", True),
    "BeginDisabled": ("EndDisabled", True),
    "PushID": ("PopID", True),
    "PushIDInt": ("PopID", True),
    "PushItemWidth": ("PopItemWidth", True),
    "PushStyleColor": ("PopStyleColor", True),
    "PushStyleVar": ("PopStyleVar", True),
    "PushStyleVarVec2": ("PopStyleVar", True),
    "BeginCombo": ("EndCombo", False),
    "BeginListBox": ("EndListBox", False),
    "BeginMenuBar": ("EndMenuBar", False),
    "BeginMenu": ("EndMenu", False),
    "BeginTooltip": ("EndTooltip", False),
    "BeginPopup": ("EndPopup", False),
    "BeginPopupModal": ("EndPopup", False),
    "BeginTabBar": ("EndTabBar", False),
    "BeginTabItem": ("EndTabItem", False),
    "TreeNode": ("TreePop", False),
    "TreeNodeEx": ("TreePop", False),
    "BeginMainMenuBar": ("EndMainMenuBar", False),
    "BeginItemTooltip": ("EndTooltip", False),
    "BeginPopupContextItem": ("EndPopup", False),
    "BeginPopupContextWindow": ("EndPopup", False),
    "BeginPopupContextVoid": ("EndPopup", False),
    "PushItemFlag": ("PopItemFlag", True),
    "PushTextWrapPos": ("PopTextWrapPos", True),
    "PushStyleVarX": ("PopStyleVar", True),
    "PushStyleVarY": ("PopStyleVar", True),
    "BeginTable": ("EndTable", False),
    # The closer takes the same draw list, so it carries its argument along.
    "DrawList.PushClipRect": ("DrawList.PopClipRect', PsychImGui('GetWindowDrawList')", True),
    "ImPlot.BeginPlot": ("ImPlot.EndPlot", False),
    "ImPlot.BeginSubplots": ("ImPlot.EndSubplots", False),
    "ImPlot.BeginAlignedPlots": ("ImPlot.EndAlignedPlots", False),
    "ImPlot.BeginLegendPopup": ("ImPlot.EndLegendPopup", False),
    "ImPlot.PushColormap": ("ImPlot.PopColormap", True),
    "ImPlot.PushColormapIndex": ("ImPlot.PopColormap", True),
    "ImPlot.PushStyleColor": ("ImPlot.PopStyleColor", True),
    "ImPlot.PushStyleVar": ("ImPlot.PopStyleVar", True),
    "ImPlot.PushStyleVarInt": ("ImPlot.PopStyleVar", True),
    "ImPlot.PushStyleVarVec2": ("ImPlot.PopStyleVar", True),
    "ImPlot3D.BeginPlot": ("ImPlot3D.EndPlot", False),
    "ImPlot3D.PushColormap": ("ImPlot3D.PopColormap", True),
    "ImPlot3D.PushColormapIndex": ("ImPlot3D.PopColormap", True),
    "ImPlot3D.PushStyleColor": ("ImPlot3D.PopStyleColor", True),
    "ImPlot3D.PushStyleVar": ("ImPlot3D.PopStyleVar", True),
    "ImPlot3D.PushStyleVarVec2": ("ImPlot3D.PopStyleVar", True),
    "ImPlot3D.PushStyleVarInt": ("ImPlot3D.PopStyleVar", True),
}

# Subcommands the generated test cannot call with any legal argument, so it
# records them instead of guessing. ImPlot 1.1 declares a PushStyleVar(int)
# overload but has no integer style variable, so every call to it asserts.
# IsSubplotsHovered is legal only inside subplots, which the generated test
# has no scope for; test_extras.m covers it.
TEST_SKIP = {"ImPlot.PushStyleVarInt", "ImPlot.IsSubplotsHovered"}

# Subcommands that refuse to run twice with the same arguments. ImPlot keeps a
# colormap name forever, so a second AddColormap with the same name asserts.
TEST_ONCE = {"ImPlot.AddColormap", "ImPlot3D.AddColormap"}

# Statements the generated test needs around one subcommand.
_IN_TABLE = (["tt = PsychImGui('BeginTable', 'genT', 3);"],
             ["if tt, PsychImGui('EndTable'); end"])
_IN_TABLE_ROW = (["tt = PsychImGui('BeginTable', 'genT', 3);",
                  "if tt, PsychImGui('TableNextRow'); PsychImGui('TableNextColumn'); end"],
                 ["if tt, PsychImGui('EndTable'); end"])
TEST_CONTEXT = {
    "BeginTabItem": (["PsychImGui('BeginTabBar', 'genTB');"], ["PsychImGui('EndTabBar');"]),
    # Table calls are legal only between BeginTable and EndTable, and the setup
    # calls only before the first row.
    "TableNextRow": _IN_TABLE,
    "TableNextColumn": _IN_TABLE,
    "TableSetColumnIndex": _IN_TABLE_ROW,
    "TableSetupColumn": _IN_TABLE,
    "TableSetupScrollFreeze": _IN_TABLE,
    "TableHeadersRow": _IN_TABLE,
    "TableGetColumnCount": _IN_TABLE,
    "TableGetColumnIndex": _IN_TABLE,
    "TableHeader": _IN_TABLE_ROW,
    "TableSetBgColor": _IN_TABLE_ROW,
    "TableGetColumnFlags": _IN_TABLE_ROW,
    "TableGetColumnName": _IN_TABLE_ROW,
    "TableAngledHeadersRow": _IN_TABLE,
    # Dear ImGui asserts that the table is hideable before it hides a column.
    "TableSetColumnEnabled": (["tt = PsychImGui('BeginTable', 'genT', 3, "
                               "'ImGuiTableFlags_Hideable');",
                               "if tt, PsychImGui('TableNextRow'); "
                               "PsychImGui('TableNextColumn'); end"],
                              ["if tt, PsychImGui('EndTable'); end"]),
    # A tab bar with only a button would select the button, which asserts.
    "TabItemButton": (["PsychImGui('BeginTabBar', 'genTB');",
                       "if PsychImGui('BeginTabItem', 'genTI'), PsychImGui('EndTabItem'); end"],
                      ["PsychImGui('EndTabBar');"]),
    # A curve continues the path from its last point.
    "PathBezierCubicCurveTo": (["PsychImGui('DrawList.PathLineTo', "
                                "PsychImGui('GetWindowDrawList'), [0 0]);"],
                               ["PsychImGui('DrawList.PathClear', "
                                "PsychImGui('GetWindowDrawList'));"]),
    "PathBezierQuadraticCurveTo": (["PsychImGui('DrawList.PathLineTo', "
                                    "PsychImGui('GetWindowDrawList'), [0 0]);"],
                                   ["PsychImGui('DrawList.PathClear', "
                                    "PsychImGui('GetWindowDrawList'));"]),
    # With no string id these act on the previous item, so there must be one.
    "BeginPopupContextItem": (["PsychImGui('Button', 'genCtx');"], []),
    "OpenPopupOnItemClick": (["PsychImGui('Button', 'genCtx');"], []),
}

# C++ statements around the call of one generated handler, for invariants the
# marshaling rules cannot see. Keyed by the full MATLAB name. Each entry is
# (before the call, after the call).
CALL_HOOKS = {
    # Dear ImGui guards these with an IM_ASSERT and then dereferences or
    # indexes anyway. The deferred IM_ASSERT of section 8.3 returns instead of
    # aborting, so the dereference would follow; see SPEC.md section 14.4.
    # The checks use only public API: TableGetColumnCount is 0 outside a table.
    "BeginTable": ([
         "if (v_columns < 1 || v_columns > 511) { mrs::fail(\"psychimgui:Range\", \"BeginTable: columns must be 1 to 511, got %d.\", v_columns); return; }"], []),
    "TableNextRow": ([
         "if (ImGui::TableGetColumnCount() == 0) { mrs::fail(\"psychimgui:Usage\", \"TableNextRow needs an open table: call it between BeginTable and EndTable.\"); return; }"], []),
    # TableSetColumnIndex before the first TableNextRow begins a cell in no row
    # at all, and Dear ImGui has no check for that.
    "TableSetColumnIndex": ([
         "if (ImGui::TableGetColumnCount() == 0) { mrs::fail(\"psychimgui:Usage\", "
         "\"TableSetColumnIndex needs an open table: call it between BeginTable and "
         "EndTable.\"); return; }",
         "if (ImGui::TableGetRowIndex() < 0) { mrs::fail(\"psychimgui:Usage\", "
         "\"TableSetColumnIndex needs a row: call TableNextRow first.\"); return; }",
         "if (v_column_n < 0 || v_column_n >= ImGui::TableGetColumnCount()) { "
         "mrs::fail(\"psychimgui:Range\", \"TableSetColumnIndex: columnN %d is not a "
         "column of this table.\", v_column_n); return; }"], []),
    "TableHeader": ([
         "if (ImGui::TableGetColumnCount() == 0) { mrs::fail(\"psychimgui:Usage\", \"TableHeader needs an open table: call it between BeginTable and EndTable.\"); return; }",
         "if (ImGui::TableGetColumnIndex() < 0) { mrs::fail(\"psychimgui:Usage\", \"TableHeader needs a current cell: call TableNextRow and TableNextColumn first.\"); return; }"], []),
    "TableSetBgColor": ([
         "if (ImGui::TableGetColumnCount() == 0) { mrs::fail(\"psychimgui:Usage\", \"TableSetBgColor needs an open table: call it between BeginTable and EndTable.\"); return; }",
         "if (v_target == ImGuiTableBgTarget_None) { mrs::fail(\"psychimgui:Usage\", \"TableSetBgColor: target must not be ImGuiTableBgTarget_None.\"); return; }",
         "if (v_column_n < -1 || v_column_n >= ImGui::TableGetColumnCount()) { mrs::fail(\"psychimgui:Range\", \"TableSetBgColor: columnN %d is not -1 or a column of this table.\", v_column_n); return; }",
         "if (v_target == ImGuiTableBgTarget_CellBg && v_column_n == -1 && ImGui::TableGetColumnIndex() < 0) { mrs::fail(\"psychimgui:Usage\", \"TableSetBgColor: a cell color with columnN -1 needs a current cell: call TableNextColumn first.\"); return; }"], []),
    # Dear ImGui indexes its column array with these after an assert.
    "TableGetColumnFlags": (["if (!mrs::checkTableColumn(v_column_n, "
                             "\"TableGetColumnFlags\")) return;"], []),
    "TableGetColumnName": (["if (!mrs::checkTableColumn(v_column_n, "
                            "\"TableGetColumnName\")) return;"], []),
    "TableSetColumnEnabled": (["if (!mrs::checkTableColumn(v_column_n, "
                               "\"TableSetColumnEnabled\")) return;"], []),
    "TableAngledHeadersRow": (["if (ImGui::TableGetColumnCount() == 0) { "
                               "mrs::fail(\"psychimgui:Usage\", \"TableAngledHeadersRow "
                               "needs an open table: call it between BeginTable and "
                               "EndTable.\"); return; }"], []),
    # ImPlot and ImPlot3D assert on these and then index the colormap tables
    # anyway (SPEC.md 14.18). Keyed by the full name: the two libraries share
    # the subcommand names.
    "ImPlot.ColormapSlider": ([
        "if (v_t != v_t) { mrs::fail(\"psychimgui:Range\", \"ImPlot.ColormapSlider: t must "
        "not be NaN.\"); return; }"], []),
    # ColormapButton samples the colormap at style.ButtonTextAlign.x unclamped.
    "ImPlot.ColormapButton": ([
        "{ float a = ImGui::GetStyle().ButtonTextAlign.x; if (!(a >= 0.0f && a <= 1.0f)) { "
        "mrs::fail(\"psychimgui:Usage\", \"ImPlot.ColormapButton needs ButtonTextAlign.x in "
        "[0, 1], got %g.\", (double)a); return; } }"], []),
    "ImPlot.SampleColormap": ([
        "if (v_t != v_t) { mrs::fail(\"psychimgui:Range\", \"ImPlot.SampleColormap: t must not "
        "be NaN.\"); return; }",
        "v_t = v_t < 0.0f ? 0.0f : (v_t > 1.0f ? 1.0f : v_t);"], []),
    "ImPlot.AddColormap": ([
        "if (cv_cols.n < 2) { mrs::fail(\"psychimgui:Usage\", \"ImPlot.AddColormap needs at "
        "least 2 colors, got %d.\", cv_cols.n); return; }",
        "if (ImPlot::GetColormapIndex(v_name) != -1) { mrs::fail(\"psychimgui:Usage\", "
        "\"ImPlot.AddColormap: a colormap named '%s' exists already.\", v_name); return; }"], []),
    "ImPlot.PushColormap": ([
        "if (ImPlot::GetColormapIndex(v_name) == -1) { mrs::fail(\"psychimgui:Usage\", "
        "\"ImPlot.PushColormap: no colormap named '%s'.\", v_name); return; }"], []),
    "ImPlot3D.SampleColormap": ([
        "if (v_t != v_t) { mrs::fail(\"psychimgui:Range\", \"ImPlot3D.SampleColormap: t must not "
        "be NaN.\"); return; }",
        "v_t = v_t < 0.0f ? 0.0f : (v_t > 1.0f ? 1.0f : v_t);"], []),
    "ImPlot3D.AddColormap": ([
        "if (cv_cols.n < 2) { mrs::fail(\"psychimgui:Usage\", \"ImPlot3D.AddColormap needs at "
        "least 2 colors, got %d.\", cv_cols.n); return; }",
        "if (ImPlot3D::GetColormapIndex(v_name) != -1) { mrs::fail(\"psychimgui:Usage\", "
        "\"ImPlot3D.AddColormap: a colormap named '%s' exists already.\", v_name); return; }"], []),
    "ImPlot3D.PushColormap": ([
        "if (ImPlot3D::GetColormapIndex(v_name) == -1) { mrs::fail(\"psychimgui:Usage\", "
        "\"ImPlot3D.PushColormap: no colormap named '%s'.\", v_name); return; }"], []),
    # ImPlot dereferences the current subplot after an assert in both.
    "EndSubplots": (["if (!pig::implotSubplotOpen()) { mrs::fail(\"psychimgui:Usage\", "
                     "\"ImPlot.EndSubplots without an open ImPlot.BeginSubplots. Call it "
                     "only when BeginSubplots returned true.\"); return; }"], []),
    "IsSubplotsHovered": (["if (!pig::implotSubplotOpen()) { mrs::fail(\"psychimgui:Usage\", "
                           "\"ImPlot.IsSubplotsHovered needs open subplots: call it between "
                           "ImPlot.BeginSubplots and ImPlot.EndSubplots.\"); return; }"], []),
    # ImPlot and ImPlot3D take idx modulo the colormap size, which stays
    # negative for a negative idx and then indexes the color table.
    "GetColormapColor": (["if (v_idx < 0) { mrs::fail(\"psychimgui:Range\", "
                          "\"GetColormapColor: idx must not be negative, got %d.\", "
                          "v_idx); return; }"], []),
    # ImDrawList::PopClipRect pops without a bounds check once IM_ASSERT
    # returns, and a pop of Dear ImGui's own clip rectangle corrupts the stack
    # for the End that owns it. Count the pushes made through the binding.
    "DrawList.PushClipRect": ([], ["pig::drawListPushClip(slot_self);"]),
    # The curves start at _Path.back(), which reads before the buffer of an
    # empty path once IM_ASSERT returns.
    "DrawList.PathBezierCubicCurveTo": (["if (v_self->_Path.Size == 0) { mrs::fail("
                                         "\"psychimgui:Usage\", \"DrawList.PathBezierCubicCurveTo "
                                         "needs a current point: call DrawList.PathLineTo "
                                         "first.\"); return; }"], []),
    "DrawList.PathBezierQuadraticCurveTo": (["if (v_self->_Path.Size == 0) { mrs::fail("
                                             "\"psychimgui:Usage\", \"DrawList."
                                             "PathBezierQuadraticCurveTo needs a current point: "
                                             "call DrawList.PathLineTo first.\"); return; }"], []),
    # ImPlot3D asserts on a zero or negative scale and then stores it, which
    # turns every vertex of the plot into NaN.
    "SetupBoxScale": (["if (!(v_x > 0.0 && v_y > 0.0 && v_z > 0.0)) { "
                       "mrs::fail(\"psychimgui:Range\", \"SetupBoxScale: x, y, and z must be "
                       "greater than 0, got %g, %g, %g.\", v_x, v_y, v_z); return; }"], []),
    "DrawList.PopClipRect": (["if (!pig::drawListPopClip(slot_self)) { "
                              "mrs::fail(\"psychimgui:Usage\", \"DrawList.PopClipRect has "
                              "no matching DrawList.PushClipRect on this draw list in this "
                              "frame.\"); return; }"], []),
}

# Subcommands the generated test must call inside an open ImPlot3D plot.
IMPLOT3D_INSIDE_PLOT = {
    "PlotLine", "PlotScatter", "PlotTriangle", "PlotQuad", "PlotSurface", "PlotMesh",
    "PlotText", "PlotToPixels", "GetPlotRectPos", "GetPlotRectSize", "SetupAxis",
    "SetupAxes", "SetupAxisLimits", "SetupAxesLimits", "SetupAxisTicks", "SetupBoxRotation",
    "SetupBoxScale", "SetupLegend", "SetupAxisScale", "SetupAxisLimitsConstraints",
    "SetupAxisZoomConstraints", "SetupBoxInitialRotation", "PixelsToPlotRay",
    "PixelsToPlotPlane", "NextColormapColor", "PlotDummy", "EndPlot",
}

def plot_guard(ns, mat):
    """C++ that refuses a call needing an open plot when none is open.

    ImPlot and ImPlot3D check with IM_ASSERT_USER_ERROR and then dereference
    the current plot, which is null outside BeginPlot and EndPlot. The deferred
    assert of section 8.3 returns, so the dereference would crash the host.
    """
    inside = IMPLOT_INSIDE_PLOT if ns == "ImPlot" else IMPLOT3D_INSIDE_PLOT
    if mat not in inside:
        return []
    fn = "mrs::implotPlotOpen()" if ns == "ImPlot" else "mrs::implot3dPlotOpen()"
    return [f"if (!{fn}) {{ mrs::fail(\"psychimgui:Usage\", \"{ns}.{mat} needs an "
            f"open plot: call it between {ns}.BeginPlot and {ns}.EndPlot.\"); return; }}"]


# Families that look up a colormap color from every data value. NaN and
# infinite values index the colormap table out of bounds (SPEC.md 14.18).
FINITE_FAMILIES = {"ImPlot.PlotHeatmap", "ImPlot3D.PlotSurface"}

# Data argument names of a family whose arrays are not the generic xs and ys,
# keyed by (full name, number of data arrays).
PLOT_DATA_NAMES = {
    ("ImPlot.PlotBubbles", 3): ["xs", "ys", "sizes"],
    ("ImPlot.PlotBubbles", 2): ["values", "sizes"],
}

# Per namespace settings of the templated plot families (SPEC.md 7.6).
PLOT_NS = {
    "ImPlot": {"spec_t": "ImPlotSpec", "spec_start": "mrs::specStart",
               "data_names": {1: ["values"], 2: ["xs", "ys"], 3: ["xs", "ys1", "ys2"],
                              4: ["xs", "ys", "neg", "pos"]}},
    "ImPlot3D": {"spec_t": "ImPlot3DSpec", "spec_start": "mrs::specStart3D",
                 "data_names": {3: ["xs", "ys", "zs"]}},
}

# Subcommands the generated test must call inside an open ImPlot plot.
IMPLOT_INSIDE_PLOT = {
    "PlotLine", "PlotScatter", "PlotStairs", "PlotShaded", "PlotBars", "PlotErrorBars",
    "PlotStems", "PlotInfLines", "PlotHistogram", "PlotHistogram2D", "PlotHeatmap",
    "PlotDigital", "PlotText", "PlotDummy", "SetupAxis", "SetupAxes", "SetupAxisLimits",
    "SetupAxesLimits", "SetupAxisFormat", "SetupAxisTicks", "SetupLegend", "SetupMouseText",
    "SetupFinish", "DragPoint", "DragLineX", "DragLineY", "DragRect", "Annotation", "TagX",
    "TagY", "IsPlotHovered", "IsAxisHovered", "IsLegendEntryHovered", "GetPlotMousePos",
    "GetPlotLimits", "GetPlotSize", "GetPlotPos", "PlotToPixels", "PixelsToPlot",
    "SetupAxisScale", "SetupAxisLimitsConstraints", "SetupAxisZoomConstraints", "SetAxis",
    "SetAxes", "GetPlotSelection", "IsPlotSelected", "CancelPlotSelection",
    "BeginLegendPopup", "NextColormapColor", "EndPlot",
}

UNSUPPORTED_RE = re.compile(
    r"^(void\*|const void\*|ImGuiInputTextCallback|ImDrawList\*|ImFont\*|"
    r"ImGuiViewport\*|ImGuiStorage\*|ImGuiPayload\*|ImGuiListClipper\*|"
    r"ImGuiStyle\*|ImPlotStyle\*|ImPlotFormatter|ImPlotTransform|"
    r"ImPlotColormapData\*|ImPlotGetter|ImPlotPoint\(\*.*|.*\(\*.*|"
    # Callback typedefs such as ImGuiSizeCallback would otherwise match the
    # ImGui name pattern of ENUM_RE and be marshaled as a number.
    r"Im[A-Za-z0-9]*Callback)$"
)

SPEC_TYPES = {"ImPlotSpec", "ImPlot3DSpec"}
VEC2_TYPES = {"ImVec2", "ImVec2_c"}
VEC4_TYPES = {"ImVec4", "ImVec4_c"}
ENUM_RE = re.compile(r"^(ImGui|ImPlot|ImAxis)[A-Za-z0-9]*$")
# String arguments that are printf formats for the widget's value. Dear ImGui
# and ImPlot hand them to snprintf with the number, so the generated handler
# checks the conversion first (mrs::checkNumberFormat). Varargs formats such as
# Text's take the "fmt" kind instead and are always called with "%s".
NUMBER_FORMAT_ARGS = {"format", "formatMax", "labelFmt"}
NUMBER_FORMAT_EXTRA = {("SetupAxisFormat", "fmt")}
INT_FORMAT_RE = re.compile(r"^(Drag|Slider|VSlider)Int")


def format_check(mat_name, a, v):
    """The C++ check of one numeric format argument, or None."""
    if a.mname not in NUMBER_FORMAT_ARGS and (mat_name, a.mname) not in NUMBER_FORMAT_EXTRA:
        return None
    integer = "true" if INT_FORMAT_RE.match(mat_name) else "false"
    return f'mrs::checkNumberFormat({v}, "{a.mname}", {integer});'


# Generated subcommands that are safe and useful outside NewFrame to Render.
# Every other ImGui, ImPlot, and ImPlot3D subcommand gets kEntryNeedsFrame,
# because Dear ImGui has no current window there and dereferences it anyway.
# Draw list handles carry their own frame generation, so DrawList.* needs no
# flag. These only read the input state or edit a stack, a style, or the
# settings of the next window or item.
IMGUI_FRAME_FREE = {
    "GetTime", "GetFrameCount", "GetMousePos", "IsMouseDown", "IsMouseClicked",
    "IsMouseReleased", "IsMouseDoubleClicked", "IsMouseDragging", "GetMouseDragDelta",
    "ResetMouseDragDelta", "GetMouseClickedCount", "IsKeyDown", "IsKeyPressed",
    "IsKeyReleased", "IsKeyChordPressed", "GetKeyName", "IsAnyItemActive",
    "IsAnyItemHovered", "SetNextWindowPos", "SetNextWindowSize", "SetNextWindowCollapsed",
    "SetNextWindowFocus", "SetNextWindowBgAlpha", "SetNextWindowContentSize",
    "SetNextWindowSizeConstraints", "SetNextItemOpen", "SetNextItemWidth",
    "PushStyleColor", "PopStyleColor", "PushStyleVar", "PushStyleVarVec2", "PushStyleVarX",
    "PushStyleVarY", "PopStyleVar", "GetFontSize", "GetTextLineHeight",
    "GetTextLineHeightWithSpacing", "GetFrameHeight", "GetFrameHeightWithSpacing",
    "TableGetRowIndex", "TableGetHoveredColumn", "SaveIniSettingsToMemory",
    "LoadIniSettingsFromMemory",
}
_PLOT_FRAME_FREE = {
    "PushColormap", "PushColormapIndex", "PopColormap", "AddColormap", "GetColormapCount",
    "GetColormapName", "GetColormapIndex", "GetColormapSize", "GetColormapColor",
    "SampleColormap", "StyleColorsAuto", "StyleColorsDark", "StyleColorsLight",
    "StyleColorsClassic", "PushStyleColor", "PopStyleColor", "PushStyleVar",
    "PushStyleVarInt", "PushStyleVarVec2", "PopStyleVar",
}
IMPLOT_FRAME_FREE = _PLOT_FRAME_FREE | {
    "SetNextAxisLimits", "SetNextAxesLimits", "SetNextAxisToFit", "SetNextAxesToFit",
    "HideNextItem", "GetLastItemColor", "MapInputDefault",
    "MapInputReverse",
}
IMPLOT3D_FRAME_FREE = set(_PLOT_FRAME_FREE)


def entry_flags(name):
    """Dispatch flags of one generated subcommand, by its full MATLAB name."""
    ns, _, mat = name.rpartition(".")
    free = {"": IMGUI_FRAME_FREE, "ImPlot": IMPLOT_FRAME_FREE,
            "ImPlot3D": IMPLOT3D_FRAME_FREE}.get(ns)
    if free is None or mat in free:
        return "kEntryNeedsInit"
    return "kEntryNeedsInit | kEntryNeedsFrame"


# Enums the libraries use as array indices, mapped to their valid [lo, hi].
# Filled in main from the enum data: every enum with a <Type>_COUNT member
# that bounds all its other members, plus CLOSED_ENUMS. IM_ASSERT returns
# (SPEC.md 8.3), so the library's own check does not stop a bad index.
ENUM_RANGES = {}
# Closed enums without a _COUNT member that are still worth checking.
CLOSED_ENUMS = {"ImPlotScale", "ImPlot3DScale"}
# Colormap counts change at run time, so their check calls into the library.
COLORMAP_CHECKS = {"ImPlotColormap": "mrs::checkColormap",
                   "ImPlot3DColormap": "mrs::checkColormap3D"}

INT_TYPES = {"int", "ImS32", "ImGuiID", "ImS16", "ImS8", "ImPlotColormap"}
UINT_TYPES = {"unsigned int", "ImU32", "ImU16", "ImU8", "size_t"}


def _is_count(name: str) -> bool:
    """True when this int argument is the element count of the array before it."""
    return (name.endswith("count") or name.startswith("n_") or
            name in ("size", "rows", "cols"))


class Refused(Exception):
    pass


def camel(name: str) -> str:
    parts = [p for p in name.split("_") if p]
    if not parts:
        return name
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def strip_const(t: str) -> str:
    t = t.strip()
    if t.startswith("const "):
        t = t[6:]
    return t.strip()


def norm_type(t: str) -> str:
    t = strip_const(t)
    if t in VEC2_TYPES:
        return "ImVec2"
    if t in VEC4_TYPES:
        return "ImVec4"
    return {"ImPlotPoint_c": "ImPlotPoint", "ImPlotRect_c": "ImPlotRect",
            "ImPlotRange_c": "ImPlotRange", "ImPlotSpec_c": "ImPlotSpec",
            "ImPlot3DSpec_c": "ImPlot3DSpec", "ImPlot3DPoint_c": "ImPlot3DPoint",
            "ImPlot3DRay_c": "ImPlot3DRay"}.get(t, t)


class Arg:
    """One C argument plus how it maps onto the MATLAB side."""

    def __init__(self, name, ctype, default):
        self.name = name
        self.ctype = ctype
        self.default = default
        self.kind = None
        self.exposed = False
        self.io = False
        self.n = 0
        self.mname = camel(name)
        self.idx = -1
        self.cexpr = ""


def classify(fn_name, argsT, defaults, suppress, enum_types):
    args = [Arg(a["name"], a["type"], defaults.get(a["name"])) for a in argsT]
    n = len(args)
    variadic = any(a.ctype == "..." for a in args)
    out = []
    i = 0
    while i < n:
        a = args[i]
        t = norm_type(a.ctype)
        if a.ctype == "...":
            i += 1
            continue
        nxt = args[i + 1] if i + 1 < n else None

        if t in ("const char* const[]", "char* const[]"):
            if nxt is None or norm_type(nxt.ctype) != "int" or not _is_count(nxt.name):
                # No count of its own: an earlier argument already carries it.
                a.kind, a.exposed = "cellstr_nocount", True
                out.append(a)
                i += 1
                continue
            a.kind, a.exposed = "cellstr", True
            nxt.kind, nxt.cexpr = "count_of", f"v_{a.name}_count"
            out += [a, nxt]
            i += 2
            continue

        # A writable buffer and its capacity, as in InputText. A const char*
        # with a size, as in LoadIniSettingsFromMemory, is an ordinary string.
        if (t == "char*" and "const" not in a.ctype and nxt is not None
                and norm_type(nxt.ctype) == "size_t"):
            a.kind, a.exposed, a.io, a.mname = "textbuf", True, True, "str"
            nxt.kind, nxt.exposed, nxt.mname = "bufsize", True, "bufSize"
            nxt.default = "16384" if "Multiline" in fn_name else "1024"
            a.cexpr = f"v_{nxt.name}"
            out += [a, nxt]
            i += 2
            continue

        if t in ("const float*", "float*") and nxt is not None and \
                norm_type(nxt.ctype) == "int" and _is_count(nxt.name):
            a.kind, a.exposed = "floatarray", True
            nxt.kind, nxt.cexpr = "count_of", f"fv_{a.name}.n"
            out += [a, nxt]
            i += 2
            continue

        if t in ("const double*", "double*") and nxt is not None and \
                norm_type(nxt.ctype) == "int" and _is_count(nxt.name):
            a.kind, a.exposed = "doublearray", True
            nxt.kind, nxt.cexpr = "count_of", f"n_{a.name}"
            out += [a, nxt]
            i += 2
            continue

        if t == "ImVec2*" and nxt is not None and norm_type(nxt.ctype) == "int" and \
                (_is_count(nxt.name) or nxt.name.startswith("num_")):
            a.kind, a.exposed = "vec2array", True
            nxt.kind, nxt.cexpr = "count_of", f"pv_{a.name}.n"
            out += [a, nxt]
            i += 2
            continue

        if t == "ImDrawList*" and a.name == "self":
            # The object of an ImDrawList method, passed as a handle.
            a.kind, a.exposed, a.mname = "drawlist", True, "drawList"
            out.append(a)
            i += 1
            continue

        if t == "ImVec4*" and nxt is not None and \
                norm_type(nxt.ctype) == "int" and _is_count(nxt.name):
            a.kind, a.exposed = "vec4array", True
            nxt.kind, nxt.cexpr = "count_of", f"cv_{a.name}.n"
            out += [a, nxt]
            i += 2
            continue

        if t in SPEC_TYPES:
            # Trailing name-value pairs, so it takes no positional slot.
            a.kind, a.exposed, a.mname = "spec", False, "spec"
            out.append(a)
            i += 1
            continue

        if a.name in suppress:
            if a.default is None:
                raise Refused(f"{fn_name}: cannot suppress '{a.name}', it has no default")
            a.kind = "suppressed"
            out.append(a)
            i += 1
            continue

        if UNSUPPORTED_RE.match(a.ctype.strip()) or UNSUPPORTED_RE.match(t):
            if a.default is None:
                raise Refused(f"{fn_name}: argument '{a.name}' has type '{a.ctype}', "
                              "which has no marshaling rule")
            a.kind = "suppressed"
            out.append(a)
            i += 1
            continue

        if t in ("const char*", "char*"):
            if variadic and a.name == "fmt":
                a.kind, a.exposed, a.mname = "fmt", True, "text"
            else:
                a.kind, a.exposed = "str", True
                if a.name == "text_begin":
                    a.mname = "text"
        elif t == "bool":
            a.kind, a.exposed = "bool", True
        elif t == "bool*":
            a.kind, a.exposed, a.io = "boolp", True, True
            # p_open reads better as "open" on the MATLAB side.
            if a.name.startswith("p_"):
                a.mname = camel(a.name[2:])
        elif t in ("int*", "ImS32*", "ImGuiID*"):
            a.kind, a.exposed, a.io = "intp", True, True
        elif t in ("unsigned int*", "ImU32*"):
            a.kind, a.exposed, a.io = "uintp", True, True
        elif t == "float*":
            a.kind, a.exposed, a.io = "floatp", True, True
        elif t == "double*":
            a.kind, a.exposed, a.io = "doublep", True, True
        elif t in ("ImS64*", "ImU64*"):
            a.kind, a.exposed, a.io = "s64p", True, True
        elif re.match(r"^float\[\d+\]$", t):
            a.kind, a.exposed, a.io, a.n = "arrf", True, True, int(t[6:-1])
        elif re.match(r"^int\[\d+\]$", t):
            a.kind, a.exposed, a.io, a.n = "arri", True, True, int(t[4:-1])
        elif t == "ImVec2":
            a.kind, a.exposed = "vec2", True
        elif t == "ImVec4":
            a.kind, a.exposed = "vec4", True
        elif t in ("ImPlotPoint", "ImPlotRange"):
            a.kind, a.exposed = "point2", True
        elif t == "ImPlotRect":
            a.kind, a.exposed = "rect4", True
        elif t == "ImU32" and (a.name in ("col", "color") or a.name.startswith("col_")):
            a.kind, a.exposed = "col32", True
        elif t in INT_TYPES:
            a.kind, a.exposed = "int", True
        elif t in UINT_TYPES:
            a.kind, a.exposed = "uint", True
        elif t in ("ImS64", "ImU64"):
            a.kind, a.exposed = "int64", True
        elif t in ("float", "double"):
            a.kind, a.exposed = "double", True
        elif t in enum_types or ENUM_RE.match(t):
            a.kind, a.exposed = "enum", True
        elif a.default is not None:
            a.kind = "suppressed"
        else:
            raise Refused(f"{fn_name}: argument '{a.name}' has type '{a.ctype}', "
                          "which has no marshaling rule")
        out.append(a)
        i += 1

    # A cellstr with no count of its own must match the count of the array
    # before it, or the C function reads past the end of the pointer table.
    last_count = None
    for a in out:
        if a.kind == "count_of":
            last_count = a.cexpr
        elif a.kind == "cellstr_nocount" and last_count:
            a.cexpr = last_count

    exposed = [a for a in out if a.exposed]
    seen_opt = False
    for a in exposed:
        opt = a.default is not None
        if seen_opt and not opt:
            raise Refused(f"{fn_name}: required argument '{a.name}' follows an optional one")
        seen_opt = seen_opt or opt
    for k, a in enumerate(exposed):
        a.idx = k
    return out, exposed


# --------------------------------------------------------------------------
# emission
# --------------------------------------------------------------------------

def cpp_default(a: Arg) -> str:
    d = a.default
    if d is None:
        return ""
    if d in ("NULL", "nullptr", "((void*)0)"):
        return "NULL"
    return d


def mat_default(a: Arg) -> str:
    d = a.default
    if d is None:
        return ""
    if d in ("NULL", "nullptr", "((void*)0)"):
        return "[]"
    m = re.match(r"^(ImVec2|ImVec4|ImPlotPoint|ImPlotRange|ImPlotRect)\((.*)\)$", d)
    if m:
        parts = [re.sub(r"^(-?[\d.]+)f$", r"", x.strip()) for x in m.group(2).split(",")]
        return "[" + " ".join(parts) + "]"
    if d.startswith('"'):
        return "'" + d[1:-1] + "'"
    if re.match(r"^-?[\d.]+f$", d):
        return d[:-1]
    return d


def emit_handler(mat_name, d, args, exposed, sig_const, linkage="static", guard=(),
                 full_name=None):
    fn = "h_" + mat_name.replace(".", "_")
    call = f"{d.get('namespace', 'ImGui')}::{d['funcname']}"
    if any(a.kind == "drawlist" for a in args):
        call = f"v_self->{d['funcname']}"
    hook_pre, hook_post = CALL_HOOKS.get(full_name or mat_name,
                                         CALL_HOOKS.get(mat_name, ([], [])))
    hook_pre = list(guard) + list(hook_pre)
    req = sum(1 for a in exposed if a.default is None)
    tot = len(exposed)

    kw = "static " if linkage == "static" else ""
    has_spec = any(a.kind == "spec" for a in args)
    spec_t = next((norm_type(a.ctype) for a in args if a.kind == "spec"), "ImPlotSpec")
    spec_start = "mrs::specStart3D" if spec_t == "ImPlot3DSpec" else "mrs::specStart"
    first_opt = next((a.idx for a in exposed if a.default is not None), tot)

    L = [f"{kw}void {fn}(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {{"]
    if has_spec:
        # The trailing ImPlotSpec pairs make the argument count open ended.
        L.append(f"    if (nargin < {req}) "
                 f'{{ mrs::usage("{mat_name}", {sig_const}); return; }}')
    elif tot == 0:
        L.append(f'    if (nargin != 0) {{ mrs::usage("{mat_name}", {sig_const}); return; }}')
    else:
        L.append(f"    if (nargin < {req} || nargin > {tot}) "
                 f'{{ mrs::usage("{mat_name}", {sig_const}); return; }}')
    L.append("    (void)nlhs; (void)plhs; (void)args;")
    if has_spec:
        L.append(f"    int specAt = {spec_start}(args, nargin, {first_opt});")

    deferred, outputs, callargs = [], [], []
    for a in args:
        v = f"v_{a.name}"
        k = a.kind
        if a.default is None:
            guard = "    "
        elif has_spec:
            guard = f"    if (nargin > {a.idx} && {a.idx} < specAt) "
        else:
            guard = f"    if (nargin > {a.idx}) "
        if k == "count_of":
            callargs.append(a.cexpr)
        elif k == "drawlist":
            L.append("    int slot_self = -1;")
            L.append(f'    ImDrawList* v_self = mrs::getDrawList(args[{a.idx}], "{a.mname}", '
                     "&slot_self);")
            L.append("    (void)slot_self;")
        elif k == "col32":
            dflt = cpp_default(a) if a.default is not None else "0"
            L.append(f"    ImU32 {v} = (ImU32)({dflt});")
            L.append(f'{guard}{v} = mrs::getColorU32(args[{a.idx}], "{a.mname}");')
            callargs.append(v)
        elif k == "vec2array":
            L.append(f"    mrs::Vec2Vec pv_{a.name};")
            L.append(f'    const ImVec2* {v} = mrs::getVec2Array(args[{a.idx}], '
                     f'"{a.mname}", pv_{a.name});')
            callargs.append(v)
        elif k == "suppressed":
            callargs.append(cpp_default(a))
        elif k == "bufsize":
            L.append(f"    int {v} = {a.default};")
            L.append(f'    if (nargin > {a.idx}) {v} = mrs::getInt(args[{a.idx}], "bufSize");')
        elif k == "spec":
            L.append(f"    {spec_t} v_spec;")
            deferred.append("    mrs::getSpec(args, nargin, specAt, v_spec, sizeof(double));")
            callargs.append("v_spec")
        elif k == "doublearray":
            L.append(f"    int n_{a.name} = 0;")
            L.append(f'    const double* {v} = mrs::getDoubleArray(args[{a.idx}], '
                     f'"{a.mname}", &n_{a.name});')
            callargs.append(v)
        elif k == "vec4array":
            L.append(f"    mrs::Vec4Vec cv_{a.name};")
            L.append(f'    const ImVec4* {v} = mrs::getVec4Array(args[{a.idx}], '
                     f'"{a.mname}", cv_{a.name});')
            callargs.append(v)
        elif k == "cellstr_nocount":
            L.append(f"    mrs::CellStr cs_{a.name};")
            L.append(f"    const char* const* {v} = NULL;")
            g = (f"    if (nargin > {a.idx} && !mxIsEmpty(args[{a.idx}])) "
                 if a.default is not None else "    ")
            L.append(f'{g}{v} = mrs::getCellStr(args[{a.idx}], "{a.mname}", cs_{a.name});')
            if a.cexpr:
                L.append(f"    if ({v} && cs_{a.name}.n != {a.cexpr}) {{")
                L.append(f'        mrs::fail("psychimgui:Usage", "{a.mname} must have the '
                         f'same number of entries as the values array (%d, not %d).", '
                         f"{a.cexpr}, cs_{a.name}.n);")
                L.append("        return;")
                L.append("    }")
            callargs.append(v)
        elif k in ("str", "fmt"):
            cap = 512 if k == "fmt" else 256
            L.append(f"    mrs::StrBuf<{cap}> b_{a.name};")
            L.append(f'    const char* {v} = {cpp_default(a) if a.default is not None else chr(34)*2};')
            if a.default is None:
                L.append(f'    {v} = mrs::toUtf8(args[{a.idx}], "{a.mname}", b_{a.name});')
            else:
                extra = f" && {a.idx} < specAt" if has_spec else ""
                L.append(f"    if (nargin > {a.idx}{extra} && !mxIsEmpty(args[{a.idx}])) "
                         f'{v} = mrs::toUtf8(args[{a.idx}], "{a.mname}", b_{a.name});')
            chk = format_check(mat_name, a, v) if k == "str" else None
            if chk:
                deferred.append(f"    {chk}")
            callargs.append(f'"%s", {v}' if k == "fmt" else v)
        elif k == "bool":
            L.append(f"    bool {v} = {cpp_default(a) if a.default is not None else 'false'};")
            L.append(f'{guard}{v} = mrs::getBool(args[{a.idx}], "{a.mname}");')
            callargs.append(v)
        elif k == "boolp":
            L.append(f"    bool {v} = false;")
            if a.default is None:
                L.append(f'    {v} = mrs::getBool(args[{a.idx}], "{a.mname}");')
                callargs.append(f"&{v}")
            else:
                L.append(f"    bool has_{a.name} = (nargin > {a.idx}) && "
                         f"!mxIsEmpty(args[{a.idx}]);")
                L.append(f'    if (has_{a.name}) {v} = mrs::getBool(args[{a.idx}], "{a.mname}");')
                callargs.append(f"has_{a.name} ? &{v} : NULL")
            outputs.append(("bool", v))
        elif k in ("intp", "uintp"):
            ct, getter = ("int", "getInt") if k == "intp" else ("unsigned", "getUInt")
            L.append(f'    {ct} {v} = mrs::{getter}(args[{a.idx}], "{a.mname}");')
            callargs.append(f"({strip_const(a.ctype)})&{v}")
            outputs.append(("double", v))
        elif k == "floatp":
            L.append(f'    float {v} = (float)mrs::getScalar(args[{a.idx}], "{a.mname}");')
            callargs.append(f"&{v}")
            outputs.append(("double", v))
        elif k == "doublep":
            L.append(f'    double {v} = mrs::getScalar(args[{a.idx}], "{a.mname}");')
            callargs.append(f"&{v}")
            outputs.append(("double", v))
        elif k == "s64p":
            base = strip_const(a.ctype)[:-1]
            L.append(f'    {base} {v} = ({base})mrs::getInt64(args[{a.idx}], "{a.mname}");')
            callargs.append(f"&{v}")
            outputs.append(("double", v))
        elif k == "arrf":
            L.append(f"    float {v}[{a.n}] = {{0}};")
            L.append(f'    mrs::getVecF(args[{a.idx}], "{a.mname}", {v}, {a.n});')
            callargs.append(v)
            outputs.append((f"vecf{a.n}", v))
        elif k == "arri":
            L.append(f"    int {v}[{a.n}] = {{0}};")
            L.append(f'    mrs::getVecI(args[{a.idx}], "{a.mname}", {v}, {a.n});')
            callargs.append(v)
            outputs.append((f"veci{a.n}", v))
        elif k in ("vec2", "vec4", "point2", "rect4"):
            ctor = {"vec2": ("ImVec2", 2, "ImVec2(0,0)"), "vec4": ("ImVec4", 4, "ImVec4(0,0,0,1)"),
                    "point2": (strip_const(norm_type(a.ctype)), 2, None),
                    "rect4": ("ImPlotRect", 4, "ImPlotRect(0,1,0,1)")}[k]
            cty, cnt, fallback = ctor
            dflt = cpp_default(a) if a.default is not None else (fallback or f"{cty}(0,0)")
            L.append(f"    {cty} {v} = {dflt};")
            zeros = ", ".join(["0"] * cnt)
            L.append(f"{guard}{{ double t[{cnt}] = {{{zeros}}}; "
                     f'mrs::getVec(args[{a.idx}], "{a.mname}", t, {cnt}); '
                     f"{v} = {cty}({', '.join(f'(float)t[{j}]' if k in ('vec2', 'vec4') else f't[{j}]' for j in range(cnt))}); }}")
            callargs.append(v)
        elif k in ("int", "uint", "int64", "double", "enum"):
            ct = strip_const(a.ctype)
            dflt = cpp_default(a) if a.default is not None else "0"
            L.append(f"    {ct} {v} = ({ct})({dflt});")
            L.append(f"{guard}{v} = {scalar_getter(a, k, ct, f'args[{a.idx}]')};")
            if ct in COLORMAP_CHECKS:
                auto = "true" if dflt in ("IMPLOT_AUTO", "IMPLOT3D_AUTO", "-1") else "false"
                L.append(f'{guard}{COLORMAP_CHECKS[ct]}({v}, {auto}, "{a.mname}");')
            callargs.append(v)
        elif k == "floatarray":
            L.append(f"    mrs::FloatVec fv_{a.name};")
            L.append(f'    const float* {v} = mrs::getFloatArray(args[{a.idx}], '
                     f'"{a.mname}", fv_{a.name});')
            callargs.append(v)
        elif k == "cellstr":
            L.append(f"    mrs::CellStr cs_{a.name};")
            L.append(f'    const char* const* {v} = mrs::getCellStr(args[{a.idx}], '
                     f'"{a.mname}", cs_{a.name});')
            L.append(f"    int {v}_count = cs_{a.name}.n;")
            callargs.append(v)
        elif k == "textbuf":
            L.append(f"    mrs::TextBuf tb_{a.name};")
            deferred.append(f'    mrs::fillText(args[{a.idx}], "str", {a.cexpr}, tb_{a.name});')
            callargs.append(f"tb_{a.name}.p")
            callargs.append(f"tb_{a.name}.cap")
            outputs.append(("text", f"tb_{a.name}.p"))
        else:
            raise Refused(f"{mat_name}: unhandled kind {k}")

    L += deferred
    L.append("    if (mrs::failed()) return;")
    L += [f"    {h}" for h in hook_pre]

    ret = norm_type(d.get("ret", "void"))
    argstr = ", ".join(callargs)
    if ret == "void":
        L.append(f"    {call}({argstr});")
        rets = outputs
    elif ret == "ImDrawList*":
        L.append(f"    double ret = mrs::drawListOut({call}({argstr}));")
        L.append("    if (mrs::failed()) return;")
        rets = [("double", "ret")] + outputs
    else:
        decl = "const char*" if ret == "char*" else ret
        L.append(f"    {decl} ret = {call}({argstr});")
        rk = {"bool": "bool", "ImVec2": "xy", "ImVec4": "xyzw", "ImPlotPoint": "xy",
              "ImPlotRange": "range2", "ImPlotRect": "rect4x", "ImPlot3DPoint": "xyz",
              "char*": "text"}.get(ret, "double")
        if ret == "ImPlot3DRay":
            rets = [("xyz", "ret.Origin"), ("xyz", "ret.Direction")] + outputs
        else:
            rets = [(rk, "ret")] + outputs
    L += [f"    {h}" for h in hook_post]

    for oi, (kind, expr) in enumerate(rets):
        if kind == "bool":
            stmt = f"plhs[{oi}] = mrs::outBool({expr});"
        elif kind == "double":
            stmt = f"plhs[{oi}] = mrs::outDouble((double)({expr}));"
        elif kind == "text":
            stmt = f"plhs[{oi}] = mrs::fromUtf8({expr});"
        elif kind == "xy":
            stmt = (f"{{ double t[2] = {{(double){expr}.x, (double){expr}.y}}; "
                    f"plhs[{oi}] = mrs::outVec(t, 2); }}")
        elif kind == "xyz":
            stmt = (f"{{ double t[3] = {{{expr}.x, {expr}.y, {expr}.z}}; "
                    f"plhs[{oi}] = mrs::outVec(t, 3); }}")
        elif kind == "xyzw":
            stmt = (f"{{ double t[4] = {{(double){expr}.x, (double){expr}.y, "
                    f"(double){expr}.z, (double){expr}.w}}; "
                    f"plhs[{oi}] = mrs::outVec(t, 4); }}")
        elif kind == "range2":
            stmt = (f"{{ double t[2] = {{{expr}.Min, {expr}.Max}}; "
                    f"plhs[{oi}] = mrs::outVec(t, 2); }}")
        elif kind == "rect4x":
            stmt = (f"{{ double t[4] = {{{expr}.X.Min, {expr}.X.Max, {expr}.Y.Min, "
                    f"{expr}.Y.Max}}; plhs[{oi}] = mrs::outVec(t, 4); }}")
        elif kind.startswith("vecf"):
            stmt = f"plhs[{oi}] = mrs::outVecF({expr}, {kind[4:]});"
        elif kind.startswith("veci"):
            stmt = f"plhs[{oi}] = mrs::outVecI({expr}, {kind[4:]});"
        else:
            raise Refused(f"{mat_name}: unhandled output kind {kind}")
        L.append(f"    if (nlhs > {oi}) {stmt}")
    L.append("}")
    return "\n".join(L), len(rets), ret


# --------------------------------------------------------------------------
# ImPlot templated overload families (SPEC.md section 7.6).
#
# cimplot exposes one C overload per element type, for example
# ImPlot_PlotLine_doublePtrdoublePtr and ImPlot_PlotLine_S16PtrS16Ptr. The C++
# API they wrap is a single template, so the generator groups the overloads by
# shape and emits one function template per shape plus a switch on the MATLAB
# class of the data. The mxArray data pointer reaches ImPlot without a copy.
# --------------------------------------------------------------------------

TEMPLATE_ELEMS = {
    "double": "mxDOUBLE_CLASS", "float": "mxSINGLE_CLASS",
    "ImS8": "mxINT8_CLASS", "ImU8": "mxUINT8_CLASS",
    "ImS16": "mxINT16_CLASS", "ImU16": "mxUINT16_CLASS",
    "ImS32": "mxINT32_CLASS", "ImU32": "mxUINT32_CLASS",
    "ImS64": "mxINT64_CLASS", "ImU64": "mxUINT64_CLASS",
}

TEMPLATE_ORDER = ["double", "float", "ImS8", "ImU8", "ImS16", "ImU16",
                  "ImS32", "ImU32", "ImS64", "ImU64"]

def elem_of(ctype):
    """The element type of a pointer to a templated numeric type, or None."""
    t = strip_const(ctype).strip()
    if not t.endswith("*"):
        return None
    base = t[:-1].strip()
    return base if base in TEMPLATE_ELEMS else None


def shape_of(ov):
    """A key equal for two overloads that differ only in the element type."""
    return tuple((a["name"], "DATA" if elem_of(a["type"]) else norm_type(a["type"]))
                 for a in ov["argsT"])


def roles_of(argsT):
    """Tag every argument of one overload with its role in the family."""
    roles = []
    for idx, a in enumerate(argsT):
        t = norm_type(a["type"])
        if elem_of(a["type"]):
            roles.append("data")
        elif t in SPEC_TYPES:
            roles.append("spec")
        elif t == "int" and a["name"] in ("count", "rows", "cols"):
            roles.append(a["name"])
        elif t == "int" and a["name"] == "vtx_count":
            roles.append("count")
        elif t == "int" and a["name"] in ("x_count", "y_count", "idx_count"):
            # ImPlot3D's surface grid and mesh index list, both taken from the
            # shape of a MATLAB array rather than passed.
            roles.append(a["name"])
        elif t == "unsigned int*" and a["name"] == "idxs":
            roles.append("faces")
        elif idx == 0 and t in ("const char*", "char*"):
            roles.append("label")
        else:
            roles.append("extra")
    return roles


def extra_param(a):
    """C type, initializer, and getter expression for one extra argument."""
    k = a.kind
    dflt = cpp_default(a) if a.default is not None else None
    cty = strip_const(a.ctype)
    if k == "double":
        return cty, f"({cty})({dflt if dflt is not None else 0})", \
            f'({cty})mrs::getScalar(args[{a.idx}], "{a.mname}")'
    if k in ("int", "uint", "int64", "enum"):
        if cty in COLORMAP_CHECKS:
            raise Refused(f"colormap argument '{a.name}' is not supported in a templated family")
        return cty, f"({cty})({dflt if dflt is not None else 0})", \
            scalar_getter(a, k, cty, f"args[{a.idx}]")
    if k == "bool":
        return "bool", (dflt if dflt is not None else "false"), \
            f'mrs::getBool(args[{a.idx}], "{a.mname}")'
    if k in ("point2", "vec2"):
        vt = strip_const(norm_type(a.ctype))
        return vt, (dflt if dflt is not None else f"{vt}()"), \
            f'mrs::getPoint2<{vt}>(args[{a.idx}], "{a.mname}")'
    if k == "rect4":
        vt = strip_const(norm_type(a.ctype))
        return vt, (dflt if dflt is not None else f"{vt}()"), \
            f'mrs::getRect4<{vt}>(args[{a.idx}], "{a.mname}")'
    if k == "str":
        return "const char*", (dflt if dflt is not None else '""'), \
            f'mrs::toUtf8(args[{a.idx}], "{a.mname}", b_{a.name})'
    raise Refused(f"extra argument kind '{k}' is not supported in a templated family")


def emit_implot_group(mat_name, overloads, enum_types, sig_const, ns="ImPlot"):
    """Emit the handler, the per-shape templates, the signatures, and the tests."""
    conf = PLOT_NS[ns]
    prefix = ns + "."
    shapes = {}
    for ov in overloads:
        elems = {elem_of(a["type"]) for a in ov["argsT"]}
        elems.discard(None)
        if len(elems) != 1:
            continue
        shapes.setdefault(shape_of(ov), {})[elems.pop()] = ov
    shapes = {k: v for k, v in shapes.items() if len(v) >= 2}
    if not shapes:
        raise Refused(f"{mat_name}: no templated overload family found")

    by_count = {}
    fn_name = None
    for variants in shapes.values():
        rep = variants.get("double") or next(iter(variants.values()))
        roles = roles_of(rep["argsT"])
        n_data = roles.count("data")
        if n_data in by_count:
            raise Refused(f"{mat_name}: two shapes take {n_data} data arrays")
        by_count[n_data] = (rep, roles, variants)
        fn_name = rep["funcname"]

    max_data = max(by_count)
    body, sigs, tests = [], [], []

    H = [f"void h_{mat_name}(int nlhs, mxArray** plhs, int nargin, const mxArray** args) {{"]
    H.append(f'    if (nargin < 2) {{ mrs::usage("{prefix}{mat_name}", {sig_const}); return; }}')
    H += [f"    {g}" for g in plot_guard(ns, mat_name)]
    H.append("    mrs::StrBuf<256> b_label;")
    H.append('    const char* v_label = mrs::toUtf8(args[0], "labelId", b_label);')
    H.append(f"    int nData = mrs::dataArgCount(args, nargin, 1, {max_data});")
    H.append("    int count = 0;")
    H.append(f'    mxClassID cid = mrs::checkData(args, 1, nData, "{prefix}{mat_name}", &count);')
    H.append("    if (mrs::failed()) return;")

    branch_kw = "    if"
    for n_data in sorted(by_count, reverse=True):
        rep, roles, variants = by_count[n_data]
        argsT = rep["argsT"]
        defaults = rep.get("defaults", {}) or {}

        extras_argsT = [a for a, r in zip(argsT, roles) if r == "extra"]
        extras, extras_exposed = classify(mat_name, extras_argsT, defaults, set(), enum_types)
        has_faces = "faces" in roles
        has_grid = "x_count" in roles
        base = 1 + n_data + (1 if has_faces else 0)
        for a in extras_exposed:
            a.idx += base
        by_name = {a.name: a for a in extras}
        req_extra = sum(1 for a in extras_exposed if a.default is None)
        first_opt = base + req_extra

        has_rows = "rows" in roles
        params = ["const char* v_label", "const mxArray** args", "int nargin", "int specAt"]
        if "count" in roles:
            params.append("int count")
        if has_rows:
            params += ["int rows", "int cols"]
        if has_grid:
            params += ["int xCount", "int yCount"]
        if has_faces:
            params += ["const unsigned* v_faces", "int idxCount"]
        passed = [a for a in extras if a.exposed]
        for a in passed:
            cty, _, _ = extra_param(a)
            params.append(f"{cty} v_{a.name}")

        callargs, data_i = [], 0
        for a, r in zip(argsT, roles):
            if r == "label":
                callargs.append("v_label")
            elif r == "data":
                callargs.append(f"(const T_*)mxGetData(args[{1 + data_i}])")
                data_i += 1
            elif r in ("count", "rows", "cols"):
                callargs.append(r)
            elif r == "x_count":
                callargs.append("xCount")
            elif r == "y_count":
                callargs.append("yCount")
            elif r == "faces":
                callargs.append("v_faces")
            elif r == "idx_count":
                callargs.append("idxCount")
            elif r == "spec":
                callargs.append("v_spec")
            else:
                arg = by_name[a["name"]]
                callargs.append(f"v_{arg.name}" if arg.exposed else cpp_default(arg))

        tname = f"tp_{mat_name}_{n_data}"
        T = ["template <typename T_>",
             f"static void {tname}(int nlhs, mxArray** plhs, " + ", ".join(params) + ") {"]
        T.append("    (void)nlhs; (void)plhs;")
        T.append(f"    {conf['spec_t']} v_spec;")
        T.append("    mrs::getSpec(args, nargin, specAt, v_spec, sizeof(T_));")
        if "count" in roles and not has_faces:
            T.append("    count = mrs::specCount(v_spec, count, sizeof(T_));")
        else:
            T.append(f'    mrs::specNoStride(v_spec, "{prefix}{mat_name}");')
        T.append("    if (mrs::failed()) return;")
        if prefix + mat_name in FINITE_FAMILIES:
            for i in range(n_data):
                T.append(f"    if (!mrs::allFinite((const T_*)mxGetData(args[{1 + i}]), "
                         f"mxGetNumberOfElements(args[{1 + i}]))) {{ mrs::fail("
                         f'"psychimgui:Range", "{prefix}{mat_name}: the data must be finite. '
                         f'Replace NaN and Inf first, for example with fillmissing."); return; }}')
        if has_rows:
            T.append("    // MATLAB stores a matrix column major, so let ImPlot read it")
            T.append("    // that way instead of transposing a copy.")
            T.append("    v_spec.Flags = (ImPlotItemFlags)(v_spec.Flags | "
                     "ImPlotHeatmapFlags_ColMajor);")
        ret = norm_type(rep.get("ret", "void"))
        call = f"{ns}::{fn_name}(" + ", ".join(callargs) + ")"
        if ret == "void":
            T.append(f"    {call};")
        else:
            T.append(f"    {ret} ret = {call};")
            T.append("    if (nlhs > 0) plhs[0] = mrs::outDouble((double)ret);")
        T.append("}")
        body.append("\n".join(T))
        body.append("")

        H.append(f"{branch_kw} (nData == {n_data}) {{")
        branch_kw = "    } else if"
        H.append(f"        int specAt = {conf['spec_start']}(args, nargin, {first_opt});")
        if has_rows:
            H.append("        int rows = (int)mxGetM(args[1]);")
            H.append("        int cols = (int)mxGetN(args[1]);")
        if has_grid:
            H.append("        // A grid from meshgrid is column major, so its first dimension")
            H.append("        // is the one that varies fastest, which is ImPlot3D's x.")
            H.append("        int xCount = (int)mxGetM(args[1]);")
            H.append("        int yCount = (int)mxGetN(args[1]);")
        if has_faces:
            H.append(f"        if (nargin <= {1 + n_data}) {{ mrs::usage(\"{prefix}{mat_name}\", "
                     f"{sig_const}); return; }}")
            H.append("        mrs::Faces fc;")
            H.append(f'        const unsigned* v_faces = mrs::getFaces(args[{1 + n_data}], '
                     '"faces", count, fc);')
            H.append("        int idxCount = fc.n;")
        for a in passed:
            cty, init, getter = extra_param(a)
            if a.kind == "str":
                H.append(f"        mrs::StrBuf<128> b_{a.name};")
            H.append(f"        {cty} v_{a.name} = {init};")
            if a.default is None:
                H.append(f"        v_{a.name} = {getter};")
            else:
                H.append(f"        if (nargin > {a.idx} && {a.idx} < specAt) "
                         f"v_{a.name} = {getter};")
            chk = format_check(mat_name, a, f"v_{a.name}") if a.kind == "str" else None
            if chk:
                H.append(f"        {chk}")
        H.append("        if (mrs::failed()) return;")
        H.append("        switch (cid) {")
        names = ["nlhs", "plhs", "v_label", "args", "nargin", "specAt"]
        if "count" in roles:
            names.append("count")
        if has_rows:
            names += ["rows", "cols"]
        if has_grid:
            names += ["xCount", "yCount"]
        if has_faces:
            names += ["v_faces", "idxCount"]
        names += [f"v_{a.name}" for a in passed]
        callstr = ", ".join(names)
        for elem in TEMPLATE_ORDER:
            if elem in variants:
                H.append(f"        case {TEMPLATE_ELEMS[elem]}: "
                         f"{tname}<{elem}>({callstr}); break;")
        H.append(f'        default: mrs::fail("psychimgui:Type", '
                 f'"{prefix}{mat_name}: unsupported data class."); break;')
        H.append("        }")

        data_names = PLOT_DATA_NAMES.get((prefix + mat_name, n_data)) or \
            conf["data_names"].get(n_data, [f"d{i}" for i in range(n_data)])
        if has_rows:
            data_names = ["values"]
        if has_grid:
            data_names = ["X", "Y", "Z"]
        if has_faces:
            data_names = data_names + ["faces"]
        sig = f"PsychImGui('{prefix}{mat_name}', labelId, " + ", ".join(data_names)
        for a in extras_exposed:
            if a.default is None:
                sig += f", {a.mname}"
            else:
                dv = mat_default(a)
                sig += f" [, {a.mname}={dv}]" if dv != "" else f" [, {a.mname}]"
        sig += " [, spec...])"
        if ret != "void":
            sig = "ret = " + sig
        sigs.append(sig)
        tests.append((n_data, extras_exposed, has_rows or has_grid, ret, has_faces))

    H.append("    } else {")
    H.append(f'        mrs::usage("{prefix}{mat_name}", {sig_const});')
    H.append("    }")
    H.append("}")
    body.append("\n".join(H))
    body.append("")
    return body, sigs, tests


def mat_signature(mat_name, exposed, nouts, ret, prefix, has_spec=False):
    outs = []
    if ret == "ImPlot3DRay":
        outs += ["origin", "direction"]
    elif ret != "void":
        outs.append(RET_NAMES.get(mat_name, "changed" if nouts > 1 else "ret"))
    outs += [a.mname for a in exposed if a.io]
    outs = outs[:nouts]

    call = f"PsychImGui('{prefix}{mat_name}'"
    for a in exposed:
        if a.default is None:
            call += f", {a.mname}"
        else:
            dv = mat_default(a)
            call += f" [, {a.mname}={dv}]" if dv != "" else f" [, {a.mname}]"
    if has_spec:
        call += " [, spec...]"
    call += ")"
    if not outs:
        return call
    if len(outs) == 1:
        return f"{outs[0]} = {call}"
    return f"[{', '.join(outs)}] = {call}"


NAME_VALUES = {
    "xscale": "1", "scale": "1", "bins": "10", "xBins": "5", "yBins": "5",
    "barSize": "0.5", "barScale": "1",
    "xAxis": "'ImAxis_X1'", "yAxis": "'ImAxis_Y1'",
}


def test_value(mat_name, a: Arg) -> str:
    key = (mat_name, a.mname)
    if key in TEST_ARG_OVERRIDE:
        return TEST_ARG_OVERRIDE[key]
    if a.mname in NAME_VALUES:
        return NAME_VALUES[a.mname]
    k = a.kind
    return {
        "str": "'x'", "fmt": "'x'", "bool": "false", "boolp": "true",
        "intp": "0", "uintp": "0", "int": "0", "uint": "0", "int64": "0",
        "enum": "0", "bufsize": "64", "floatp": "0", "doublep": "0", "double": "0",
        "vec2": "[0 0]", "vec4": "[0 0 0 1]", "point2": "[0 0]",
        "rect4": "[0 1 0 1]", "floatarray": "[0 1 2 3]", "cellstr": "{'a', 'b'}",
        "textbuf": "'txt'", "doublearray": "[0 1 2 3]", "cellstr_nocount": "{'a', 'b', 'c', 'd'}",
        "vec4array": "[1 0 0 1; 0 1 0 1]",
        "col32": "[1 0 0 1]", "vec2array": "[0 0; 10 10; 20 0]",
        "drawlist": "PsychImGui('GetWindowDrawList')",
    }.get(k, f"zeros(1, {a.n})" if k in ("arrf", "arri") else "0")


# --------------------------------------------------------------------------

def parse_allowlist(path: Path):
    sections, cur = {}, None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
            sections.setdefault(cur, [])
            continue
        if cur is None:
            raise SystemExit(f"allowlist entry before any section: {raw}")
        toks = line.split()
        name, suppress = None, []
        for t in toks[1:]:
            if t.startswith("-"):
                suppress.append(t[1:])
            elif name is None:
                name = t
        sections[cur].append((toks[0], name, suppress))
    return sections


def index_definitions(defs):
    return {o["ov_cimguiname"]: o for group in defs.values() for o in group}


def collect_igfd_enums(header: Path):
    """ImGuiFileDialog's flag names, parsed from its header.

    ImGuiFileDialog has no JSON metadata, but its flags are one plain enum of
    shifts and ORs of earlier names, which a restricted evaluation reads.
    """
    out = {}
    if not header.exists():
        return out
    text = header.read_text("utf-8", errors="ignore")
    m = re.search(r"enum ImGuiFileDialogFlags_\s*\{(.*?)\};", text, re.S)
    if not m:
        return out
    body = re.sub(r"//[^\n]*", "", m.group(1))
    for part in body.split(","):
        part = part.strip()
        if not part or "=" not in part:
            continue
        name, expr = [x.strip() for x in part.split("=", 1)]
        # An OR spread over several lines is one expression to eval.
        expr = " ".join(expr.split())
        for k in sorted(out, key=len, reverse=True):
            expr = expr.replace(k, str(out[k]))
        if not re.fullmatch(r"[\d\s()<|]+", expr):
            raise SystemExit(f"ImGuiFileDialog flag {name}: cannot evaluate '{expr}'")
        out[name] = int(eval(expr, {"__builtins__": {}}))
    return out


# --------------------------------------------------------------------------
# Style field tables (SPEC.md 14.16). One table per style struct, from the
# struct members of the metadata, for GetStyle and SetStyle.
# --------------------------------------------------------------------------

# Members that are not part of a theme: the global scale, which SetGlobalScale
# owns, the DPI factor, and Dear ImGui's private bookkeeping.
STYLE_SKIP = {"FontScaleMain", "FontScaleDpi"}

# An int member that holds an enum, for the range check.
STYLE_FIELD_ENUMS = {("ImPlot3DStyle", "Marker"): "ImPlot3DMarker"}


def scaled_style_fields(imgui_cpp: Path):
    """The ImGuiStyle members that ScaleAllSizes multiplies, from its body."""
    text = imgui_cpp.read_text("utf-8", errors="ignore")
    m = re.search(r"void ImGuiStyle::ScaleAllSizes\(float scale_factor\)\s*\{(.*?)\n\}", text, re.S)
    if not m:
        raise SystemExit("ImGuiStyle::ScaleAllSizes not found in imgui.cpp")
    return set(re.findall(r"^\s*(\w+) = .*\b\1 \* scale_factor", m.group(1), re.M))


def style_table(se, struct, color_enum, cmd, colormap_count=None, scaled=frozenset()):
    """C++ for one StyleDesc: the field table, the color names, the descriptor."""
    rows, colors_member = [], None
    for m in se["structs"][struct]:
        name, t = m["name"], m["type"]
        if name.startswith("Colors["):
            colors_member = name.split("[")[0]
            continue
        if name.startswith("_") or name in STYLE_SKIP:
            continue
        lo = hi = 0
        enum_t = STYLE_FIELD_ENUMS.get((struct, name), t)
        if t == "float":
            kind = "kStyleFloat"
        elif t == "ImVec2":
            kind = "kStyleVec2"
        elif t == "bool":
            kind = "kStyleBool"
        elif t.endswith("Colormap"):
            kind = "kStyleColormap"
        elif enum_t in ENUM_RANGES:
            kind = "kStyleEnum"
            lo, hi = ENUM_RANGES[enum_t]
        elif t.endswith("Flags"):
            kind = "kStyleFlags"
        elif t == "int":
            kind = "kStyleInt"
        else:
            raise SystemExit(f"{struct}.{name}: style member type {t} has no rule")
        sc = 1 if name in scaled else 0
        rows.append(f'    {{"{name}", (uint32_t)offsetof({struct}, {name}), {kind}, {sc}, '
                    f"{lo}, {hi}}},")
    if colors_member is None:
        raise SystemExit(f"{struct} has no Colors member")
    prefix = color_enum + "_"
    entries = se["enums"].get(prefix) or se["enums"][color_enum]
    cols = sorted((int(e["calc_value"]), e["name"][len(prefix):]) for e in entries
                  if e["name"] != prefix + "COUNT")
    names = ", ".join(f'"{n}"' for _, n in cols)
    ident = struct
    cm = colormap_count or "nullptr"
    return "\n".join([
        f"static const StyleField k{ident}Fields[] = {{",
        *rows,
        "};",
        f"static const char* const k{ident}Colors[] = {{{names}}};",
        f"static_assert(sizeof((({struct}*)nullptr)->Colors) / sizeof(ImVec4) == {len(cols)},",
        f'              "{struct}: the color count of the metadata and the header differ");',
        f"static const StyleDesc k{ident}Desc = {{",
        f'    "{cmd}", k{ident}Fields, {len(rows)}, (uint32_t)offsetof({struct}, Colors),',
        f"    k{ident}Colors, {len(cols)}, {cm}}};",
    ])


def write_style_header(root, filename, includes, body, imgui_ver):
    out = [GEN_BANNER.format(imgui=imgui_ver, implot=""), "#pragma once", ""]
    out += [f'#include "{h}"' for h in includes]
    out += ['#include "style_marshal.h"', "", "namespace pig {", "", body, "", "}  // namespace pig", ""]
    (root / "src" / filename).write_text("\n".join(out), encoding="utf-8")



def collect_enum_ranges(se):
    for ename, entries in se.get("enums", {}).items():
        t = ename.rstrip("_")
        vals = {e["name"]: int(e["calc_value"]) for e in entries}
        count = vals.pop(t + "_COUNT", None)
        if not vals:
            continue
        lo, hi = min(vals.values()), max(vals.values())
        if count is not None and hi < count:
            ENUM_RANGES[t] = (lo, count - 1)
        elif t in CLOSED_ENUMS:
            ENUM_RANGES[t] = (lo, hi)


def scalar_getter(a, k, ct, argexpr):
    """The C++ expression that reads one int, double, or enum argument."""
    if k == "enum" and ct == "ImGuiKey":
        return f'mrs::getKey({argexpr}, "{a.mname}")'
    if k == "enum" and ct == "ImGuiKeyChord":
        return f'mrs::getKeyChord({argexpr}, "{a.mname}")'
    if k == "enum" and ct in ENUM_RANGES:
        lo, hi = ENUM_RANGES[ct]
        # IMPLOT_AUTO (-1) selects the current axis where it is the default.
        if a.default in ("IMPLOT_AUTO", "IMPLOT3D_AUTO", "-1"):
            lo = min(lo, -1)
        return f'({ct})mrs::getEnumRanged({argexpr}, "{a.mname}", {lo}, {hi})'
    getter = {"int": "getInt", "uint": "getUInt", "int64": "getInt64",
              "double": "getScalar", "enum": "getFlags"}[k]
    return f'({ct})mrs::{getter}({argexpr}, "{a.mname}")'


def collect_enums(se):
    out, locs = {}, se.get("locations", {})
    for ename, entries in se.get("enums", {}).items():
        if "internal" in locs.get(ename, ""):
            continue
        for e in entries:
            if e["name"].endswith("_COUNT"):
                continue
            out[e["name"]] = int(e["calc_value"])
    return out


def build_section(entries_in, by_ov, enum_types, prefix, linkage="static", cpp_ns="",
                  groups=None, prefixed_symbols=False, plot_ns="ImPlot"):
    entries, helps, tests, refused, body = [], [], [], [], []
    groups = groups or {}
    for ov, name, suppress in entries_in:
        d = by_ov.get(ov)
        if d is None and ov in groups:
            # A templated overload family, dispatched on the MATLAB data class.
            mat = name or ov.split("_", 1)[1]
            sig_const = "kSig_" + mat
            try:
                gbody, gsigs, gtests = emit_implot_group(mat, groups[ov], enum_types,
                                                         sig_const, plot_ns)
            except Refused as e:
                refused.append((ov, str(e)))
                continue
            kw = "static" if linkage == "static" else "extern"
            joined = "\\n    ".join(gsigs)
            body.append(f'{kw} const char {sig_const}[] =\n    "{joined}";')
            body += gbody
            qual = (cpp_ns + "::") if cpp_ns else ""
            entries.append((prefix + mat, qual + "h_" + mat, qual + sig_const))
            for g in gsigs:
                helps.append((prefix + mat, g))
            tests.append((prefix + mat, mat, "implot_group", gtests, ""))
            continue
        if d is None:
            refused.append((ov, "not found in definitions.json"))
            continue
        mat = name or d["funcname"]
        # A prefixed section compiled into the same file as [ImGui] carries the
        # prefix into its symbols, so DrawList.PushClipRect cannot collide with
        # a later ImGui PushClipRect.
        hmat = (prefix + mat) if prefixed_symbols else mat
        try:
            args, exposed = classify(mat, d["argsT"], d.get("defaults", {}) or {},
                                     set(suppress), enum_types)
            sig_const = "kSig_" + hmat.replace(".", "_")
            guard = plot_guard(plot_ns, mat) if prefix in ("ImPlot.", "ImPlot3D.") else []
            src, nouts, ret = emit_handler(hmat, d, args, exposed, sig_const, linkage, guard,
                                           full_name=prefix + mat)
        except Refused as e:
            refused.append((ov, str(e)))
            continue
        sig = mat_signature(mat, exposed, nouts, ret, prefix,
                            any(a.kind == "spec" for a in args))
        kw = "static" if linkage == "static" else "extern"
        body.append(f'{kw} const char {sig_const}[] =\n    "{sig}";')
        body.append(src)
        body.append("")
        qual = (cpp_ns + "::") if cpp_ns else ""
        entries.append((prefix + mat, qual + "h_" + hmat.replace(".", "_"),
                        qual + sig_const))
        helps.append((prefix + mat, sig))
        tests.append((prefix + mat, mat, exposed, nouts, ret))
    return entries, helps, tests, refused, body


GEN_BANNER = """// GENERATED by gen/generate.py from the cimgui metadata. Do not edit by hand.
// Dear ImGui {imgui}{implot}
"""


def bi_ident(name):
    """A C identifier for a hand-written subcommand name, which may hold a dot."""
    return name.replace(".", "_")


def write_ext_decls(out, entries, ns, macro, opt, what):
    """Declarations of one extension's handlers, or stubs when it is compiled out.

    The table slots stay in place either way so the opcode of a core
    subcommand does not move with the build options.
    """
    out.append(f"#ifdef {macro}")
    out.append(f"namespace {ns} {{")
    for name, sym, sig_const in entries:
        bare = sym.split("::")[-1]
        bare_sig = sig_const.split("::")[-1]
        out.append(f"void {bare}(int nlhs, mxArray** plhs, int nargin, "
                   "const mxArray** args);")
        out.append(f"extern const char {bare_sig}[];")
    out.append(f"}}  // namespace {ns}")
    out.append("#else")
    out.append(f"static void h_{ns}_unavailable(int, mxArray**, int, const mxArray**) {{")
    out.append('    mrs::fail("psychimgui:UnknownCommand",')
    out.append(f'              "This build has {what} disabled. Rebuild with '
               f'-D{opt}=ON.");')
    out.append("}")
    out.append(f"namespace {ns} {{")
    for name, sym, sig_const in entries:
        bare_sig = sig_const.split("::")[-1]
        out.append(f'static const char {bare_sig}[] = "{name}: not compiled in";')
    out.append(f"}}  // namespace {ns}")
    out.append("#endif")
    out.append("")


def write_gen_dispatch(root, ig, implot_entries, enums, imgui_ver, implot_ver,
                       implot3d_entries=()):
    entries, helps, tests, refused, body = ig
    out = [GEN_BANNER.format(imgui=imgui_ver, implot=(", ImPlot " + implot_ver) if implot_ver else "")]
    out.append('#include "imgui_psych.h"')
    out.append("")
    out.append('#include "marshal.h"')
    out.append('#include "imgui_marshal.h"')
    out.append('#include "dispatch.h"')
    out.append("")
    out.append("namespace mrs { Error g_err; }")
    out.append("")
    out.append("namespace pig {")
    out.append("")
    out.append("// Hand-written subcommands, defined in psychimgui.cpp.")
    for name, sym, _, _, _ in BUILTINS:
        out.append(f"void {sym}(int nlhs, mxArray** plhs, int nargin, const mxArray** args);")
    out.append("")
    out.append("}  // namespace pig")
    out.append("")
    out.append("using namespace pig;")
    out.append("")
    out.append("\n".join(body))

    # ImPlot and ImPlot3D handlers live in their own generated files and are
    # compiled only with their build options.
    write_ext_decls(out, implot_entries, "pig_implot", "PSYCHIMGUI_IMPLOT",
                    "PSYCHIMGUI_IMPLOT", "ImPlot")
    write_ext_decls(out, implot3d_entries, "pig_implot3d", "PSYCHIMGUI_IMPLOT3D",
                    "PSYCHIMGUI_IMPLOT3D", "ImPlot3D")

    # enum value table, sorted for binary search
    out.append("namespace {")
    out.append("struct EnumEntry { const char* name; double value; };")
    out.append("const EnumEntry kEnumTable[] = {")
    for k in sorted(enums):
        out.append(f'    {{"{k}", {enums[k]}.0}},')
    out.append("};")
    out.append(f"const int kEnumCount = {len(enums)};")
    out.append("}  // namespace")
    out.append("")
    out.append("namespace mrs {")
    out.append("bool enum_lookup(const char* name, double* out) {")
    out.append("    int lo = 0, hi = kEnumCount - 1;")
    out.append("    while (lo <= hi) {")
    out.append("        int mid = (lo + hi) / 2;")
    out.append("        int c = strcmp(name, kEnumTable[mid].name);")
    out.append("        if (c == 0) { *out = kEnumTable[mid].value; return true; }")
    out.append("        if (c < 0) hi = mid - 1; else lo = mid + 1;")
    out.append("    }")
    out.append("    return false;")
    out.append("}")
    out.append("int enum_count() { return kEnumCount; }")
    out.append("const char* enum_name(int i) { return kEnumTable[i].name; }")
    out.append("double enum_value(int i) { return kEnumTable[i].value; }")
    out.append("}  // namespace mrs")
    out.append("")

    # the dispatch table
    rows = []
    for name, sym, sig_const in entries:
        rows.append((name, sym, sig_const, entry_flags(name)))
    for name, sym, _, needs_init, _ in [(b[0], b[1], None, b[2], b[3]) for b in BUILTINS]:
        pass
    for bname, bsym, binit, bgl, bsig in BUILTINS:
        flags = []
        if binit:
            flags.append("kEntryNeedsInit")
        if bgl:
            flags.append("kEntryNeedsGL")
        extra = BUILTIN_EXTRA.get(bname, {})
        if extra.get("frame"):
            flags.append("kEntryNeedsFrame")
        sym = f"{extra['macro']}({bsym})" if "macro" in extra else bsym
        rows.append((bname, sym, f"kSigBi_{bi_ident(bname)}",
                     " | ".join(flags) if flags else "0"))
    for name, sym, sig_const in implot_entries:
        rows.append((name, "PIG_IMPLOT_FN(" + sym + ")", sig_const, entry_flags(name)))
    for name, sym, sig_const in implot3d_entries:
        rows.append((name, "PIG_IMPLOT3D_FN(" + sym + ")", sig_const, entry_flags(name)))

    for bname, bsym, binit, bgl, bsig in BUILTINS:
        out.append(f'static const char kSigBi_{bi_ident(bname)}[] = "{bsig}";')
    out.append("")
    out.append("#ifdef PSYCHIMGUI_IMPLOT")
    out.append("#  define PIG_IMPLOT_FN(x) x")
    out.append("#else")
    out.append("#  define PIG_IMPLOT_FN(x) h_pig_implot_unavailable")
    out.append("#endif")
    out.append("#ifdef PSYCHIMGUI_IMPLOT3D")
    out.append("#  define PIG_IMPLOT3D_FN(x) x")
    out.append("#else")
    out.append("#  define PIG_IMPLOT3D_FN(x) h_pig_implot3d_unavailable")
    out.append("#endif")
    out.append("")
    out.append("namespace pig {")
    out.append("const Entry kTable[] = {")
    for name, sym, sig_const, flags in sorted(rows, key=lambda r: r[0]):
        out.append(f'    {{"{name}", {sym}, {sig_const}, {flags}}},')
    out.append("};")
    out.append(f"const int kTableCount = {len(rows)};")
    out.append("}  // namespace pig")
    out.append("")
    (root / "src" / "gen_dispatch.cpp").write_text("\n".join(out) + "\n", encoding="utf-8")
    return sorted(rows, key=lambda r: r[0])


def write_gen_ext(root, body, imgui_ver, ext_label, macro, marshal_h, ns, filename):
    out = [GEN_BANNER.format(imgui=imgui_ver, implot=", " + ext_label)]
    out.append(f"#ifdef {macro}")
    out.append('#include "imgui_psych.h"')
    out.append("")
    out.append('#include "marshal.h"')
    out.append('#include "dispatch.h"')
    out.append(f'#include "{marshal_h}"')
    out.append("")
    out.append("// Its own namespace: a few subcommand names exist in several namespaces,")
    out.append("// and the handlers need external linkage for the shared dispatch table.")
    out.append(f"namespace {ns} {{")
    out.append("")
    out.append("\n".join(body))
    out.append(f"}}  // namespace {ns}")
    out.append(f"#endif  // {macro}")
    (root / "src" / filename).write_text("\n".join(out) + "\n", encoding="utf-8")


def write_gen_implot(root, body, imgui_ver, implot_ver, entries):
    write_gen_ext(root, body, imgui_ver, "ImPlot " + implot_ver, "PSYCHIMGUI_IMPLOT",
                  "implot_marshal.h", "pig_implot", "gen_dispatch_implot.cpp")


def write_help(root, rows, helps, imgui_ver, implot_ver):
    L = ["function varargout = PsychImGui(varargin)",
         "% PsychImGui  Dear ImGui panels inside a Psychtoolbox window.",
         "%",
         "%   This file is help text only. The MEX in dist/ shadows it once built.",
         "%   GENERATED by gen/generate.py. Do not edit by hand.",
         "%",
         f"%   Dear ImGui {imgui_ver}" + (f", ImPlot {implot_ver}" if implot_ver else ""),
         "%",
         "%   Call every subcommand between Screen('BeginOpenGL', win) and",
         "%   Screen('EndOpenGL', win). See README.md and SPEC.md.",
         "%",
         "%   Lifecycle subcommands",
         "%   ---------------------"]
    for bname, bsym, binit, bgl, bsig in BUILTINS:
        if bname not in BUILTIN_EXTRA:
            L.append(f"%     {bsig}")
    L.append("%")
    L.append("%   Hand-written widget and plot subcommands")
    L.append("%   ----------------------------------------")
    for bname, bsym, binit, bgl, bsig in BUILTINS:
        if bname in BUILTIN_EXTRA:
            L.append(f"%     {bsig}")
    L.append("%")
    L.append("%   Generated subcommands")
    L.append("%   ---------------------")
    for name, sig in helps:
        L.append(f"%     {sig}")
    L.append("%")
    L.append("%   Draw lists")
    L.append("%   ----------")
    L.append("%   GetWindowDrawList, GetBackgroundDrawList, and GetForegroundDrawList")
    L.append("%   return a handle for the DrawList subcommands. A handle is valid only")
    L.append("%   between NewFrame and Render of the frame that returned it; a stale")
    L.append("%   handle raises psychimgui:InvalidHandle. Colors are 1x4 [r g b a] in")
    L.append("%   0 to 1, points are 1x2 [x y] in window pixels, and point lists are")
    L.append("%   Nx2.")
    L.append("%")
    L.append("%   Images")
    L.append("%   ------")
    L.append("%   Image and ImageButton take the struct from PsychImGuiImage, or an")
    L.append("%   OpenGL GL_TEXTURE_2D texture name. Make the Psychtoolbox texture")
    L.append("%   with Screen('MakeTexture', win, img, [], 1); the default")
    L.append("%   GL_TEXTURE_RECTANGLE texture raises psychimgui:Texture.")
    L.append("%")
    L.append("%   Several windows")
    L.append("%   ---------------")
    L.append("%   Init returns a context handle and makes that context current. Every")
    L.append("%   other subcommand acts on the current context. SetContext switches;")
    L.append("%   enter that window with Screen('BeginOpenGL', win) before any call")
    L.append("%   that draws, or it raises psychimgui:Context. Shutdown takes an")
    L.append("%   optional handle or 'all'. A handle of a context that was shut down")
    L.append("%   raises psychimgui:InvalidHandle.")
    L.append("%")
    L.append("%   Stereo")
    L.append("%   ------")
    L.append("%   Render builds and draws the frame for the eye selected with")
    L.append("%   Screen('SelectStereoDrawBuffer'). RenderAgain draws the same frame")
    L.append("%   into the other eye, inside its own BeginOpenGL and EndOpenGL pair.")
    L.append("%   PsychImGuiFrame('End', ig) does both when ig.stereo is true.")
    L.append("%")
    L.append("%   File dialog")
    L.append("%   -----------")
    L.append("%   FileDialog.Open starts a dialog; call FileDialog.Display every frame")
    L.append("%   until it returns true, then read FileDialog.IsOk and")
    L.append("%   FileDialog.GetFilePathName or FileDialog.GetSelection, and call")
    L.append("%   FileDialog.Close. An empty filter chooses a directory.")
    L.append("%")
    L.append("%   The four helpers own the Screen('BeginOpenGL') and")
    L.append("%   Screen('EndOpenGL') pairs, so a script writes none itself:")
    L.append("%")
    L.append("%     ig = PsychImGuiOpen(win [, opts])")
    L.append("%     ig = PsychImGuiFrame('Begin', ig)")
    L.append("%     PsychImGuiFrame('End', ig)")
    L.append("%     PsychImGuiClose(ig)")
    L.append("%     PsychImGuiGL(ig, 'Subcommand', ...)")
    L.append("%")
    L.append("%   See also PsychImGuiOpen, PsychImGuiFrame, PsychImGuiClose,")
    L.append("%   PsychImGuiGL, PsychImGuiImage, PsychImGuiSetup, PsychImGuiInput,")
    L.append("%   PsychImGuiKeymap, PsychImGuiOp, PsychImGuiDemo,")
    L.append("%   PsychImGuiStereoDemo.")
    L.append("")
    L.append("    error('psychimgui:NotBuilt', ...")
    L.append("        ['The PsychImGui MEX is not on the path. Run PsychImGuiSetup, ' ...")
    L.append("         'or build first.']);")
    L.append("end")
    (root / "m" / "PsychImGui.m").write_text("\n".join(L) + "\n", encoding="utf-8")


def write_opcodes(root, rows):
    L = ["function op = PsychImGuiOp()",
         "% PsychImGuiOp  Numeric opcodes for the PsychImGui fast path.",
         "%",
         "%   op = PsychImGuiOp(); PsychImGui(op.SliderFloat, 'Gain', g, 0, 1);",
         "%",
         "%   An opcode skips the name lookup in the MEX. The values match the",
         "%   sorted dispatch table and change when the allowlist changes, so call",
         "%   this function again after a rebuild.",
         "%",
         "%   GENERATED by gen/generate.py. Do not edit by hand.",
         "",
         "    persistent cached",
         "    if ~isempty(cached)",
         "        op = cached;",
         "        return;",
         "    end",
         "    op = struct();"]
    # A dotted name belongs to a namespace, which becomes a nested struct:
    # op.ImPlot.BeginPlot, op.DrawList.AddLine.
    spaces = {}
    for i, (name, sym, sig_const, flags) in enumerate(rows):
        if "." in name:
            ns, short = name.split(".", 1)
            spaces.setdefault(ns, []).append((short, i))
        else:
            L.append(f"    op.{name} = {i};")
    for ns in sorted(spaces):
        L.append("    ns = struct();")
        for short, i in spaces[ns]:
            L.append(f"    ns.{short} = {i};")
        L.append(f"    op.{ns} = ns;")
    L.append("    cached = op;")
    L.append("end")
    (root / "m" / "PsychImGuiOp.m").write_text("\n".join(L) + "\n", encoding="utf-8")


def _implot_lines(tests, inside_set=None, begin="tf_plot_begin", end="tf_plot_end"):
    """MATLAB statements for the ImPlot or ImPlot3D half of the generated test."""
    inside_set = IMPLOT_INSIDE_PLOT if inside_set is None else inside_set
    L = []
    closers = {c.split("'")[0] for c, _ in PAIRS.values()}
    for entry in tests:
        full, mat = entry[0], entry[1]
        if full in closers:
            L.append(f"    % {full} is exercised by its opener.")
            continue
        if full in TEST_SKIP:
            L.append(f"    % {full} has no legal argument in this ImPlot version.")
            continue
        inside = mat in inside_set
        if entry[2] == "implot_group":
            for n_data, extras, has_rows, ret, has_faces in entry[3]:
                if has_rows:
                    data = ["[1 2; 3 4]"] * n_data
                else:
                    data = ["[0 1 2 3]"] * n_data
                if has_faces:
                    data = data + ["[1 2 3; 2 3 4]"]
                base = [f"'{full}'", "'x'"] + data
                req = base + [test_value(full, a) for a in extras if a.default is None]
                allv = base + [test_value(full, a) for a in extras]
                for label, vals in (("defaults", req),
                                    ("full", allv + ["'LineColor'", "[1 0 0 1]"])):
                    L += _implot_case(f"{full} {n_data}d {label}", vals, True, 0, "void",
                                      None, begin, end)
            continue
        exposed, nouts, ret = entry[2], entry[3], entry[4]
        req = [f"'{full}'"] + [test_value(full, a) for a in exposed if a.default is None]
        allv = [f"'{full}'"] + [test_value(full, a) for a in exposed]
        closer = PAIRS.get(full)
        variants = (("defaults", req),) if full in TEST_ONCE else             (("defaults", req), ("full", allv))
        for label, vals in variants:
            L += _implot_case(f"{full} {label}", vals, inside, nouts, ret, closer, begin, end)
    return L


def _implot_case(name, vals, inside, nouts, ret, closer=None, begin="tf_plot_begin",
                 end="tf_plot_end"):
    L = []
    if inside:
        L.append(f"    p = {begin}();")
        L.append("    if p")
    else:
        L.append("    tf_begin();")
    ind = "        " if inside else "    "
    call = ", ".join(vals)

    body = []
    if nouts == 0:
        body.append(f"PsychImGui({call});")
        body.append(f"t_ok('{name}', true);")
    else:
        body.append(f"o = cell(1, {nouts});")
        body.append(f"[o{{1:{nouts}}}] = PsychImGui({call});")
        body.append(f"t_ok('{name}', numel(o) == {nouts});")
    # An unconditional closer belongs inside the try, so a failed opener is not
    # followed by a close that asserts on its own.
    if closer is not None and closer[1]:
        body.append(f"PsychImGui('{closer[0]}');")

    L.append(f"{ind}try")
    for b in body:
        L.append(f"{ind}    {b}")
    L.append(f"{ind}catch e")
    L.append(f"{ind}    t_ok('{name}', false);")
    L.append(f"{ind}    fprintf(2, '        %s: %s\\n', e.identifier, e.message);")
    if nouts > 0:
        L.append(f"{ind}    o = {{}};")
    L.append(f"{ind}end")

    if closer is not None and not closer[1]:
        L.append(f"{ind}if exist('o', 'var') && ~isempty(o) && islogical(o{{1}}) && o{{1}}")
        L.append(f"{ind}    PsychImGui('{closer[0]}');")
        L.append(f"{ind}end")

    if inside:
        L.append("    else")
        L.append(f"        t_ok('{name}', false);")
        L.append("    end")
        L.append(f"    {end}(p);")
    else:
        L.append("    tf_end();")
    L.append("")
    return L


def write_tests(root, tests, prefix_label, implot_tests, implot3d_tests=()):
    L = ["function test_gen_marshal()",
         "% TEST_GEN_MARSHAL  One round trip per generated subcommand.",
         "%",
         "%   Each subcommand is called twice inside a headless frame: once with",
         "%   only its required arguments, once with every optional argument. The",
         "%   test checks the output count and class, not the widget behavior.",
         "%",
         "%   GENERATED by gen/generate.py. Do not edit by hand.",
         "",
         ""]
    closers = {c.split("'")[0] for c, _ in PAIRS.values()}
    for full, mat, exposed, nouts, ret in tests:
        if full in closers:
            L.append(f"    % {full} is exercised by its opener.")
            continue
        req = [a for a in exposed if a.default is None]
        allargs = exposed
        pre, post = TEST_CONTEXT.get(mat, ([], []))
        for label, arglist in (("defaults", req), ("full", allargs)):
            L.append(f"    %% {full} ({label})")
            L.append("    tf_begin();")
            for s in pre:
                L.append(f"    {s}")
            vals = ", ".join([f"'{full}'"] + [test_value(mat, a) for a in arglist])
            if nouts == 0:
                L.append("    try")
                L.append(f"        PsychImGui({vals});")
                L.append(f"        t_ok('{full} {label}', true);")
                L.append("    catch e")
                L.append(f"        t_ok('{full} {label}', false);")
                L.append("        fprintf(2, '        %s: %s\\n', e.identifier, e.message);")
                L.append("    end")
            else:
                L.append("    try")
                L.append(f"        o = cell(1, {nouts});")
                L.append(f"        [o{{1:{nouts}}}] = PsychImGui({vals});")
                L.append(f"        t_ok('{full} {label}', numel(o) == {nouts});")
                if ret == "bool":
                    L.append(f"        t_ok('{full} {label} class', islogical(o{{1}}));")
                elif ret in ("char*", "const char*"):
                    L.append(f"        t_ok('{full} {label} class', ischar(o{{1}}));")
                elif ret != "void":
                    L.append(f"        t_ok('{full} {label} class', isnumeric(o{{1}}));")
                else:
                    L.append(f"        t_ok('{full} {label} class', ~isempty(class(o{{1}})));")
                L.append("    catch e")
                L.append(f"        t_ok('{full} {label}', false);")
                L.append("        fprintf(2, '        %s: %s\\n', e.identifier, e.message);")
                L.append("        o = {};")
                L.append("    end")
            if mat in PAIRS or full in PAIRS:
                closer, always = PAIRS.get(full, PAIRS.get(mat))
                if always:
                    L.append(f"    PsychImGui('{closer}');")
                else:
                    L.append("    if exist('o', 'var') && ~isempty(o) && "
                             "islogical(o{1}) && o{1}")
                    L.append(f"        PsychImGui('{closer}');")
                    L.append("    end")
            for s in post:
                L.append(f"    {s}")
            L.append("    tf_end();")
            L.append("")
    L.append("    %% ---- ImPlot ----")
    L.append("    v = PsychImGui('Version');")
    L.append("    if ~v.implot")
    L.append("        fprintf('  ImPlot is not compiled in, skipping its cases.\\n');")
    L.append("        return;")
    L.append("    end")
    L.append("    % Dear ImGui hides a window on the frame it first appears, and a plot")
    L.append("    % inside a hidden window does not open, so warm the window up first.")
    L.append("    for warm = 1:3")
    L.append("        tf_plot_end(tf_plot_begin());")
    L.append("    end")
    L.append("")
    L += _implot_lines(implot_tests)
    L.append("")
    L.append("    %% ---- ImPlot3D ----")
    L.append("    if ~v.implot3d")
    L.append("        fprintf('  ImPlot3D is not compiled in, skipping its cases.\\n');")
    L.append("        return;")
    L.append("    end")
    L.append("    for warm = 1:3")
    L.append("        tf_plot3d_end(tf_plot3d_begin());")
    L.append("    end")
    L.append("")
    L += _implot_lines(implot3d_tests, IMPLOT3D_INSIDE_PLOT, "tf_plot3d_begin",
                       "tf_plot3d_end")
    L.append("end")
    L.append("")
    L.append("function ok = tf_plot3d_begin()")
    L.append("    PsychImGui('NewFrame', tf_input());")
    L.append("    PsychImGui('Begin', 'genplot3dw', [], 1024);")
    L.append("    ok = PsychImGui('ImPlot3D.BeginPlot', 'genplot3d', [300 200]);")
    L.append("end")
    L.append("")
    L.append("function tf_plot3d_end(ok)")
    L.append("    if ok")
    L.append("        PsychImGui('ImPlot3D.EndPlot');")
    L.append("    end")
    L.append("    PsychImGui('End');")
    L.append("    PsychImGui('Render');")
    L.append("end")
    L.append("")
    L.append("function ok = tf_plot_begin()")
    L.append("    PsychImGui('NewFrame', tf_input());")
    L.append("    PsychImGui('Begin', 'genplotw', [], 1024);")
    L.append("    ok = PsychImGui('ImPlot.BeginPlot', 'genplot', [300 200]);")
    L.append("end")
    L.append("")
    L.append("function tf_plot_end(ok)")
    L.append("    if ok")
    L.append("        PsychImGui('ImPlot.EndPlot');")
    L.append("    end")
    L.append("    PsychImGui('End');")
    L.append("    PsychImGui('Render');")
    L.append("end")
    L.append("")
    L.append("function tf_begin()")
    L.append("    PsychImGui('NewFrame', tf_input());")
    L.append("    % ImGuiWindowFlags_MenuBar, so the menu bar subcommands are legal.")
    L.append("    PsychImGui('Begin', 'genw', [], 1024);")
    L.append("end")
    L.append("")
    L.append("function tf_end()")
    L.append("    PsychImGui('End');")
    L.append("    PsychImGui('Render');")
    L.append("end")
    L.append("")
    L.append("function ok(name, cond)")
    L.append("    global TST_PASS TST_FAIL %#ok<GVMIS>")
    L.append("    if cond")
    L.append("        TST_PASS = TST_PASS + 1;")
    L.append("    else")
    L.append("        TST_FAIL = TST_FAIL + 1;")
    L.append("        fprintf(2, '  FAIL  %s\\n', name);")
    L.append("    end")
    L.append("end")
    (root / "tests" / "test_gen_marshal.m").write_text("\n".join(L) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=None)
    args = ap.parse_args()
    root = Path(args.root) if args.root else Path(__file__).resolve().parent.parent

    cimgui = root / "third_party" / "cimgui"
    cimplot = root / "third_party" / "cimplot"
    defs = json.loads((cimgui / "generator/output/definitions.json").read_text("utf-8"))
    se = json.loads((cimgui / "generator/output/structs_and_enums.json").read_text("utf-8"))
    by_ov = index_definitions(defs)
    enums = collect_enums(se)
    collect_enum_ranges(se)
    enum_types = {k.rstrip("_") for k in se.get("enums", {})} | set(se.get("enumtypes", {}))

    imgui_ver = "unknown"
    m = re.search(r'#define\s+IMGUI_VERSION\s+"([^"]+)"',
                  (cimgui / "imgui" / "imgui.h").read_text("utf-8", errors="ignore"))
    if m:
        imgui_ver = m.group(1)

    implot_ver = ""
    by_ov_p, pdefs = {}, {}
    if (cimplot / "generator/output/definitions.json").exists():
        pdefs = json.loads((cimplot / "generator/output/definitions.json").read_text("utf-8"))
        pse = json.loads((cimplot / "generator/output/structs_and_enums.json").read_text("utf-8"))
        by_ov_p = index_definitions(pdefs)
        enums.update(collect_enums(pse))
        collect_enum_ranges(pse)
        enum_types |= {k.rstrip("_") for k in pse.get("enums", {})} | set(pse.get("enumtypes", {}))
        m = re.search(r'#define\s+IMPLOT_VERSION\s+"([^"]+)"',
                      (cimplot / "implot" / "implot.h").read_text("utf-8", errors="ignore"))
        if m:
            implot_ver = m.group(1)

    implot3d_ver = ""
    by_ov_p3, p3defs = {}, {}
    cimplot3d = root / "third_party" / "cimplot3d"
    if (cimplot3d / "generator/output/definitions.json").exists():
        p3defs = json.loads((cimplot3d / "generator/output/definitions.json").read_text("utf-8"))
        p3se = json.loads((cimplot3d / "generator/output/structs_and_enums.json")
                          .read_text("utf-8"))
        by_ov_p3 = index_definitions(p3defs)
        enums.update(collect_enums(p3se))
        collect_enum_ranges(p3se)
        enum_types |= ({k.rstrip("_") for k in p3se.get("enums", {})} |
                       set(p3se.get("enumtypes", {})))
        m = re.search(r'#define\s+IMPLOT3D_VERSION\s+"([^"]+)"',
                      (cimplot3d / "implot3d" / "implot3d.h").read_text("utf-8",
                                                                        errors="ignore"))
        if m:
            implot3d_ver = m.group(1)
    enums.update(collect_igfd_enums(root / "third_party" / "ImGuiFileDialog" /
                                    "ImGuiFileDialog.h"))

    sections = parse_allowlist(root / "gen" / "allowlist.txt")

    write_style_header(root, "gen_style_imgui.h", ["imgui_psych.h"],
                       style_table(se, "ImGuiStyle", "ImGuiCol", "SetStyle",
                                   scaled=scaled_style_fields(cimgui / "imgui" / "imgui.cpp")),
                       imgui_ver)
    if pdefs:
        write_style_header(root, "gen_style_implot.h", ["imgui_psych.h", "implot.h"],
                           style_table(pse, "ImPlotStyle", "ImPlotCol", "ImPlot.SetStyle",
                                       "ImPlot::GetColormapCount"), imgui_ver)
    if p3defs:
        write_style_header(root, "gen_style_implot3d.h", ["imgui_psych.h", "implot3d.h"],
                           style_table(p3se, "ImPlot3DStyle", "ImPlot3DCol",
                                       "ImPlot3D.SetStyle", "ImPlot3D::GetColormapCount"),
                           imgui_ver)

    ig = build_section(sections.get("ImGui", []), by_ov, enum_types, "")
    dl = build_section(sections.get("DrawList", []), by_ov, enum_types, "DrawList.",
                       prefixed_symbols=True)
    ig = tuple(a + b for a, b in zip(ig, dl))
    ip = build_section(sections.get("ImPlot", []), by_ov_p, enum_types, "ImPlot.",
                       linkage="extern", cpp_ns="pig_implot", groups=pdefs)

    ip3 = build_section(sections.get("ImPlot3D", []), by_ov_p3, enum_types, "ImPlot3D.",
                        linkage="extern", cpp_ns="pig_implot3d", groups=p3defs,
                        plot_ns="ImPlot3D")

    rows = write_gen_dispatch(root, ig, ip[0], enums, imgui_ver, implot_ver, ip3[0])
    write_gen_implot(root, ip[4], imgui_ver, implot_ver, ip[0])
    write_gen_ext(root, ip3[4], imgui_ver, "ImPlot3D " + implot3d_ver, "PSYCHIMGUI_IMPLOT3D",
                  "implot3d_marshal.h", "pig_implot3d", "gen_dispatch_implot3d.cpp")
    write_help(root, rows, ig[1] + ip[1] + ip3[1], imgui_ver, implot_ver)
    write_opcodes(root, rows)
    write_tests(root, ig[2], "", ip[2], ip3[2])

    print(f"generated {len(ig[0]) - len(dl[0])} ImGui, {len(dl[0])} DrawList, "
          f"{len(ip[0])} ImPlot, and {len(ip3[0])} ImPlot3D subcommands, "
          f"{len(BUILTINS)} built in, {len(enums)} enum names")
    for ov, why in ig[3] + ip[3] + ip3[3]:
        print(f"  refused {ov}: {why}")


if __name__ == "__main__":
    main()
