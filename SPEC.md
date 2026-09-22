# psychimgui specification

Status: implemented through phase 1.5. Specification version 0.1,
2026-09-22. Section 14 records where the code differs from sections 1
to 13 and why.

`psychimgui` is a MEX binding of Dear ImGui for MATLAB and GNU Octave. It draws
immediate-mode GUI panels inside a Psychtoolbox (PTB) onscreen window. The MEX
renders with the Dear ImGui OpenGL 3 backend inside PTB's userspace OpenGL
context.

This document is the design reference for the implementation. Section 3 and
section 4 explain the design. The other sections are reference material.

## 1. Purpose and scope

### 1.1 Purpose

A PTB experiment script calls `PsychImGui(...)` once per frame to describe a
GUI. The MEX renders that GUI into the PTB window before `Screen('Flip')`. The
script reads widget values back from the return values of the same calls.

Typical uses: operator control panels, parameter sliders, live status
readouts, calibration tools, and debugging overlays.

### 1.2 In scope

- One Dear ImGui context per MATLAB or Octave process, bound to one PTB
  onscreen window.
- Generated bindings for about 100 core Dear ImGui functions, selected by an
  allowlist. The list grows by editing one file.
- Mouse, wheel, keyboard, and text input from PTB functions.
- GPU rendering through `imgui_impl_opengl3`.
- Extensions from the cimgui family, compiled into the same MEX and bound by
  the same generator. ImPlot is in phase 1.5. Section 5.4 lists the policy and
  the candidates.
- MATLAB R2023a and Octave 10.1 on Windows, verified. Linux and macOS,
  expected to work, not verified.

### 1.3 Out of scope

- Dear ImGui multi-viewport and docking branches.
- Extensions without machine-readable metadata, unless hand-written and small.
- Callbacks from Dear ImGui into MATLAB code.
- Custom draw list access (`ImDrawList`) in phase 1. See section 13.
- Rendering into more than one PTB window at a time.
- Any code shared with other bindings. This project is self-contained.

## 2. Dependencies and pinned versions

| Dependency | Version | Location | Reason |
|---|---|---|---|
| cimgui | commit tracking Dear ImGui v1.92.9b | `third_party/cimgui` (git submodule) | Provides `generator/output/definitions.json` and `structs_and_enums.json` as machine-readable API metadata. The submodule also contains Dear ImGui as a nested submodule, so the two stay version-matched. cimgui C sources are not compiled. |
| Dear ImGui | v1.92.9b (through cimgui) | `third_party/cimgui/imgui` | Core library plus `backends/imgui_impl_opengl3.*`. |
| cimplot | commit from the same date as the cimgui pin | `third_party/cimplot` (git submodule) | Provides `generator/output/definitions.json` for ImPlot and contains ImPlot as a nested submodule. The cimgui project updates cimgui and cimplot together, so pins from the same day match. cimplot C sources are not compiled. |
| ImPlot | v1.x (through cimplot) | `third_party/cimplot/implot` | `implot.cpp`, `implot_items.cpp`, `implot_demo.cpp`. Compiled with `PSYCHIMGUI_IMPLOT=ON` (default). |
| Tracy | 0.11.x | `third_party/tracy` (git submodule, optional) | Profiler client, compiled only with `PSYCHIMGUI_TRACY=ON`. |
| Psychtoolbox | 3.0.19 or later | user install | `Screen('BeginOpenGL')`, `KbEventGet` with `CookedKey`, `GetMouseWheel`. |
| MATLAB | R2023a verified, R2019b or later expected | user install | C++17 MEX with MSVC 2022. |
| Octave | 10.1 verified, 8.x expected | user install | `mkoctfile --mex` with the bundled MinGW g++. |
| CMake | 3.16 or later | build machine | Builds the static Dear ImGui library. |
| Python and uv | Python 3.10 or later | developer machine only | Runs `gen/generate.py`. Generated files are committed, so users do not need Python. |

Update procedure: move the `cimgui` and `cimplot` submodules to commits from
the same day, confirm that `cimplot/implot` compiles against `cimgui/imgui`
(`IMGUI_VERSION_NUM` check in `implot.h`), run `build.m gen`, review the
generated diff, run the tests.

## 3. Architecture overview

```
MATLAB / Octave script
  |  PsychImGui('NewFrame', in)   PsychImGui('SliderFloat', ...)   PsychImGui('Render')
  v
+--------------------------------------------------------------+
| psychimgui MEX (C++17)                                       |
|  dispatch: sorted name table + opcode fast path              |
|  marshal:  mxArray <-> C types (generated per function)      |
|  input:    PTB events -> ImGuiIO                             |
|  state:    one ImGui context, keymap, stats, deferred error  |
|  render:   ImGui::Render -> imgui_impl_opengl3               |
+--------------------------------------------------------------+
  |  OpenGL calls, only between Screen('BeginOpenGL') and Screen('EndOpenGL')
  v
PTB userspace GL context  -->  PTB imaging pipeline FBO  -->  Screen('Flip')
```

Design choices and why:

- The MEX is a single entry point with string subcommands, like `Screen`. PTB
  users know this pattern. One MEX also keeps the per-call overhead low because
  MATLAB does not need to resolve one M-file per widget.
- The MEX calls `ImGui::` functions directly. cimgui is used only for its JSON
  description of the API. Compiling cimgui would add a second C layer without
  benefit, because the MEX is C++ already.
- The binding surface is generated. Dear ImGui has hundreds of functions with
  default arguments and overloads. A generator applies one set of marshaling
  rules to all of them and produces the help text at the same time.
- Input is gathered in MATLAB with PTB functions and passed to the MEX once per
  frame. PTB already solves per-platform keyboard and mouse access. The MEX does
  not open devices.

## 4. PTB integration contract

### 4.1 Verified PTB behavior

These facts come from the PTB source tree, `PsychSourceGL/Source/Common/Screen/`.

- `Screen('BeginOpenGL', win)` (`SCREENglMatrixFunctionWrappers.c`) switches to
  a separate userspace GL context. That context shares textures, buffers, FBOs,
  and shaders with PTB's own context, but not render state. PTB binds its current
  FBO in the userspace context. On the first call PTB sets the viewport, scissor,
  and projection to the window client rectangle.
- `BeginOpenGL` fails unless the script called `InitializeMatlabOpenGL` first.
- `Screen('EndOpenGL', win)` calls `glGetError`. If an error is pending, PTB
  prints it and aborts the script. PTB also resets the FBO binding.
- PTB windows use a legacy compatibility GL context. On Windows PTB does not call
  `wglCreateContextAttribsARB` (`Windows/Screen/PsychWindowGlue.c`), so the
  driver returns the highest compatibility version it supports.
- PTB and Dear ImGui both use a top-left origin with y pointing down, in pixels.
  `Screen('Rect', win)` returns `[0 0 w h]`. `GetMouse(win)` returns window
  pixel coordinates.

### 4.2 Required call order

```matlab
% Setup, once
InitializeMatlabOpenGL(1);                      % required by Screen('BeginOpenGL')
[win, rect] = PsychImaging('OpenWindow', screenid, 0);
Screen('BeginOpenGL', win);
PsychImGui('Init', win, rect, PsychImGuiKeymap());
Screen('EndOpenGL', win);
kq = PsychImGuiInput('Start', win);             % KbQueueCreate + KbQueueStart, primes GetMouseWheel

% Every frame
in = PsychImGuiInput('Poll', kq, win);          % GetMouse, GetMouseWheel, KbEventGet drain, GetSecs
Screen('BeginOpenGL', win);
PsychImGui('NewFrame', in);
if PsychImGui('Begin', 'Controls')
    [~, gain] = PsychImGui('SliderFloat', 'Gain', gain, 0, 1);
end
PsychImGui('End');
PsychImGui('Render');
Screen('EndOpenGL', win);
Screen('Flip', win);

% Teardown, once
Screen('BeginOpenGL', win);
PsychImGui('Shutdown');
Screen('EndOpenGL', win);
PsychImGuiInput('Stop', kq);
sca;
```

`PsychImGuiFrame('Begin', win, kq)` and `PsychImGuiFrame('End', win)` wrap the
per-frame boilerplate for scripts that prefer two calls.

### 4.3 Rules

| Rule | Statement | Reason |
|---|---|---|
| R1 | Call every `PsychImGui` subcommand between `Screen('BeginOpenGL')` and `Screen('EndOpenGL')`. | `Init`, `Render`, and font functions issue GL calls. The other subcommands do not, but one rule is easier to follow than two. The MEX enforces the rule for GL subcommands by checking for a current GL context and raising `psychimgui:NoGLContext`. |
| R2 | Call `PsychImGui` only from the MATLAB main thread. | MEX functions run on the main thread. GL contexts are thread bound. |
| R3 | `Render` leaves `glGetError` at `GL_NO_ERROR`. | `Screen('EndOpenGL')` aborts the script on a pending error. `Render` drains errors first and raises `psychimgui:GLError` with the error code and the subcommand name. |
| R4 | The MEX restores GL state it changes. | `imgui_impl_opengl3` backs up and restores program, textures, sampler, VAO, VBO, blend, viewport, scissor, and enable bits. PTB's context isolation is a second safety net. |
| R5 | `Init` receives the window rectangle. `NewFrame` receives it again each frame. | Stereo modes and panel fitter tasks change the client rectangle after `OpenWindow`. |
| R6 | The MEX never calls `Screen`. | The MEX has no PTB dependency. This keeps the build independent of PTB internals. |
| R7 | `Shutdown` runs inside `BeginOpenGL` when possible. | GL objects can only be deleted in a current context. If none is current, the MEX skips GL deletion and logs a warning. PTB frees the objects with the context. |
| R8 | The script owns widget values. | Dear ImGui is immediate mode. The MEX stores no widget values between frames, except the text buffer described in section 7.5. |

## 5. MATLAB API reference

All functions accept a subcommand name as the first argument, or a numeric
opcode (section 9.1). Names are case sensitive and match Dear ImGui names.
`PsychImGui` with no arguments prints the list of subcommands.
`PsychImGui('Name?')` prints the help for one subcommand, like `Screen`.

### 5.1 Lifecycle subcommands

| Subcommand | Signature | Notes |
|---|---|---|
| Init | `PsychImGui('Init', win, rect, keymap [, opts])` | `rect` is `Screen('Rect', win)`. `keymap` is `int32(256,1)` from `PsychImGuiKeymap`. `opts` struct fields: `renderer` (`'opengl3'` default, `'none'` for tests), `glslVersion` (`'#version 130'` default), `iniFile` (path or `''` to disable), `logFile`. Calls `mexLock`. Error `psychimgui:AlreadyInit` if called twice without `Shutdown`. |
| Shutdown | `PsychImGui('Shutdown')` | Destroys the backend and the context. Calls `mexUnlock`. Safe to call when not initialized. |
| NewFrame | `PsychImGui('NewFrame', in)` | `in` is the input struct from section 6.1. Feeds `ImGuiIO`, sets `DisplaySize` and `DeltaTime`, calls `ImGui::NewFrame`. |
| Render | `PsychImGui('Render')` | `ImGui::Render`, then `ImGui_ImplOpenGL3_RenderDrawData`, then GL error drain. With `renderer='none'` the draw data is discarded. |
| EndFrame | `PsychImGui('EndFrame')` | `ImGui::EndFrame` without rendering. For frames the script decides not to draw. |
| Version | `v = PsychImGui('Version')` | Struct: `imgui` (string), `imguiNum`, `psychimgui`, `renderer`, `glVersion`, `glRenderer`, `build` (compiler, engine, date). |
| Opcode | `op = PsychImGui('Opcode', 'SliderFloat')` | Numeric opcode for the fast path. |
| Stats | `s = PsychImGui('Stats' [, 'reset'])` | Struct array per subcommand: `name`, `calls`, `totalNs`, `maxNs`. Plus `frame` struct: `newFrameNs`, `renderCpuNs`, `renderGpuNs` (0 when unavailable), `drawCalls`, `vertices`. |
| Enum | `v = PsychImGui('Enum', 'ImGuiWindowFlags_NoTitleBar')` | Numeric value from the generated enum table. `PsychImGui('Enum')` returns the whole table as a struct. |
| WantCapture | `[mouse, keyboard, text] = PsychImGui('WantCapture')` | `io.WantCaptureMouse`, `io.WantCaptureKeyboard`, `io.WantTextInput` after `NewFrame`. Scripts use these to decide whether a click or key belongs to the GUI or to the experiment. |
| AddFontFromFileTTF | `idx = PsychImGui('AddFontFromFileTTF', path, sizePx [, glyphRanges])` | Returns a font index. Index 0 is the default font. |
| PushFont / PopFont | `PsychImGui('PushFont', idx [, sizePx])` | Uses the font index table. |
| StyleColorsDark / StyleColorsLight / StyleColorsClassic | `PsychImGui('StyleColorsDark')` | Direct calls. |
| SetGlobalScale | `PsychImGui('SetGlobalScale', s)` | Sets `style.FontScaleMain` and `style.ScaleAllSizes(s)`. Call after `Init` and before the first `NewFrame`, or between frames. |
| ShowDemoWindow / ShowMetricsWindow | `[open] = PsychImGui('ShowDemoWindow' [, open])` | Diagnostic windows. |

### 5.2 Generated widget subcommands

The generator (section 7) emits one subcommand per allowlist entry. The
initial allowlist, grouped as in `imgui.h`:

| Group | Subcommands |
|---|---|
| Windows | Begin, End, BeginChild, EndChild, SetNextWindowPos, SetNextWindowSize, SetNextWindowCollapsed, SetNextWindowFocus, SetNextWindowBgAlpha, GetWindowPos, GetWindowSize, GetContentRegionAvail, IsWindowHovered, IsWindowFocused |
| Layout | Separator, SeparatorText, SameLine, NewLine, Spacing, Dummy, Indent, Unindent, BeginGroup, EndGroup, GetCursorScreenPos, SetCursorPos, SetNextItemWidth, PushItemWidth, PopItemWidth, CalcTextSize, GetItemRectMin, GetItemRectMax |
| ID stack | PushID (string or integer), PopID |
| Text | Text, TextColored, TextDisabled, TextWrapped, LabelText, BulletText |
| Buttons | Button, SmallButton, InvisibleButton, ArrowButton, Checkbox, CheckboxFlags, RadioButton (bool and integer forms), ProgressBar, Bullet |
| Combo and list | BeginCombo, EndCombo, Combo (cellstr items), BeginListBox, EndListBox, ListBox (cellstr items), Selectable |
| Drag and slider | DragFloat, DragFloat2, DragFloat3, DragInt, SliderFloat, SliderFloat2, SliderFloat3, SliderInt, SliderAngle, VSliderFloat, VSliderInt |
| Input | InputText, InputTextMultiline, InputTextWithHint, InputFloat, InputInt, InputDouble |
| Color | ColorEdit3, ColorEdit4, ColorButton |
| Trees | TreeNode, TreePop, CollapsingHeader, SetNextItemOpen |
| Plots | PlotLines, PlotHistogram |
| Menus | BeginMenuBar, EndMenuBar, BeginMenu, EndMenu, MenuItem |
| Tooltips and popups | BeginTooltip, EndTooltip, SetTooltip, SetItemTooltip, BeginPopup, BeginPopupModal, EndPopup, OpenPopup, CloseCurrentPopup |
| Tabs | BeginTabBar, EndTabBar, BeginTabItem, EndTabItem |
| Item queries | IsItemHovered, IsItemActive, IsItemClicked, IsItemEdited, IsItemDeactivatedAfterEdit, IsAnyItemActive |
| Input queries | IsMouseClicked, IsMouseDown, IsKeyPressed, IsKeyDown, GetMousePos |
| Style | PushStyleColor, PopStyleColor, PushStyleVar (float and Vec2), PopStyleVar, BeginDisabled, EndDisabled |
| Focus and scroll | SetKeyboardFocusHere, SetScrollHereY, SetItemDefaultFocus |
| Misc | GetFrameCount, GetTime |

Every generated subcommand has the return convention of section 7.3. Example
signatures as the generator prints them in `m/PsychImGui.m`:

```
open                 = PsychImGui('Begin', name [, open] [, flags=0])
[changed, v]         = PsychImGui('SliderFloat', label, v, vMin, vMax [, format='%.3f'] [, flags=0])
[changed, str]       = PsychImGui('InputText', label, str [, bufSize=1024] [, flags=0])
[changed, rgb]       = PsychImGui('ColorEdit3', label, rgb [, flags=0])
[changed, idx]       = PsychImGui('Combo', label, idx, items [, popupMaxHeight=-1])
pressed              = PsychImGui('Button', label [, size=[0 0]])
PsychImGui('PlotLines', label, values [, overlay=''] [, scaleMin=FLT_MAX] [, scaleMax=FLT_MAX] [, graphSize=[0 0]])
```

### 5.3 Helper M-files

| File | Purpose |
|---|---|
| `m/PsychImGui.m` | Help text only. The MEX shadows it once built. Generated. |
| `m/PsychImGuiInput.m` | `Start`, `Poll`, `Stop`. Wraps `KbQueueCreate`, `KbQueueStart`, `KbEventGet`, `GetMouse`, `GetMouseWheel`, `GetSecs`. Returns the input struct of section 6.1. |
| `m/PsychImGuiFrame.m` | `Begin` and `End` wrappers around the per-frame sequence. |
| `m/PsychImGuiKeymap.m` | Builds the 256-entry PTB keycode to `ImGuiKey` table. |
| `m/PsychImGuiOp.m` | Generated struct of opcodes for the fast path. |
| `m/PsychImGuiDemo.m` | Demo: PTB window with a Gabor patch, a control panel with sliders, and `ShowDemoWindow`. |

### 5.4 Extensions and ImPlot subcommands

Policy for extensions:

1. The extension must have a cimgui-family C binding with a generated
   `definitions.json`, so the same generator and marshaling rules apply.
   Hand-written bindings are accepted only for extensions with fewer than ten
   functions.
2. The extension is compiled into the same MEX, because it needs the Dear
   ImGui context and draw lists. A separate MEX cannot share them.
3. The extension version is pinned through its cimgui-family repository, which
   pins the Dear ImGui version it was generated against.
4. Each extension is a CMake option, ON or OFF at build time.
   `PsychImGui('Version')` reports which extensions are compiled in.
5. Subcommand names carry the extension namespace with a dot:
   `PsychImGui('ImPlot.BeginPlot', ...)`. The Dear ImGui namespace has no
   prefix. `PsychImGuiOp.m` mirrors this: `op.ImPlot.BeginPlot`.

| Extension | Metadata | Relevance for experiments | Status |
|---|---|---|---|
| ImPlot (`epezent/implot`, v1.x) | `cimgui/cimplot` | High. Live signal traces, psychometric curves, staircases, heat maps of response fields. | Phase 1.5 |
| ImPlot3D (`brenocq/implot3d`) | `cimgui/cimplot3d` | Medium. Eye or hand trajectories in 3D. | Phase 3 |
| ImGuiFileDialog (`aiekick/ImGuiFileDialog`) | none, C++ API | Medium. File chooser for stimulus or data files. Five functions, hand-written. | Phase 3 |
| ImAnim (`soufianekhiat/ImAnim`, MIT, 2025) | none. C-style `iam_*` API of about 200 functions with structs, plus one fluent C++ class for motion paths. Parseable with libclang, not with pycparser. | Medium. Tweens, springs, easing presets, oscillators, noise channels, motion paths, and keyframe clips with save and load. Useful for smooth GUI transitions and for previewing a stimulus time course; the math parts duplicate what MATLAB does natively. Keyed by `ImGuiID` and driven by `io.DeltaTime`, so it fits the frame model without extra plumbing. | Phase 3, after a libclang generator path exists |
| imgui-knobs, imgui_toggle, imspinner, ImGuiNotify | none, small C++ APIs | Low to medium. Rotary knobs, toggle switches, spinners, toast notifications. Each is under ten functions. | Hand-written on request |
| imgui_test_engine (`ocornut/imgui_test_engine`) | none | Not user-facing. Scripted UI interaction for automated tests of the binding itself. | Considered for the test suite in phase 3 |
| ImGuizmo, imnodes, imgui-node-editor, ImGuiColorTextEdit, imgui_markdown | cimgui-family for the first two | Low for experiments. | Not planned |

`pthom/imgui_bundle` is the reference for which extensions are commonly
bundled with Dear ImGui and how their versions are kept in step. Its selection
informs this table, but it is not a dependency.

ImPlot lifecycle: `Init` calls `ImPlot::CreateContext()` after
`ImGui::CreateContext()` when compiled in and `opts.implot` is not false.
`Shutdown` calls `ImPlot::DestroyContext()` before `ImGui::DestroyContext()`.
ImPlot uses `IM_ASSERT` from the Dear ImGui configuration, so the assert
redirection of section 8.3 covers it.

Initial ImPlot allowlist:

| Group | Subcommands (`ImPlot.` prefix omitted) |
|---|---|
| Plot frame | BeginPlot, EndPlot, BeginSubplots, EndSubplots |
| Setup | SetupAxis, SetupAxes, SetupAxisLimits, SetupAxesLimits, SetupAxisFormat (format string form), SetupAxisTicks (values and labels form), SetupLegend, SetupMouseText, SetupFinish, SetNextAxisLimits, SetNextAxesLimits, SetNextAxesToFit |
| Items | PlotLine, PlotScatter, PlotStairs, PlotShaded (xs, y1, y2 form and xs, ys, yref form), PlotBars, PlotErrorBars, PlotStems, PlotInfLines, PlotHistogram, PlotHistogram2D, PlotHeatmap, PlotDigital, PlotText, PlotDummy |
| Tools | DragPoint, DragLineX, DragLineY, DragRect, Annotation (string form), TagX, TagY |
| Queries | IsPlotHovered, IsAxisHovered, IsLegendEntryHovered, GetPlotMousePos, GetPlotLimits, GetPlotSize, GetPlotPos, PlotToPixels, PixelsToPlot |
| Colormaps | PushColormap (by name or index), PopColormap, AddColormap (Nx3 or Nx4 matrix), ColormapScale, SampleColormap, GetColormapCount, GetColormapName |
| Style | StyleColorsAuto, StyleColorsDark, StyleColorsLight, StyleColorsClassic, PushStyleColor, PopStyleColor, PushStyleVar (float, int, Vec2 forms), PopStyleVar |
| Diagnostics | ShowDemoWindow, ShowMetricsWindow |

Example signatures as generated:

```
open = PsychImGui('ImPlot.BeginPlot', title [, size=[-1 0]] [, flags=0])
PsychImGui('ImPlot.SetupAxes', xLabel, yLabel [, xFlags=0] [, yFlags=0])
PsychImGui('ImPlot.PlotLine', label, xs, ys [, 'LineColor', [1 0 0 1], 'Marker', 'Circle', ...])
PsychImGui('ImPlot.PlotLine', label, ys [, spec...])            % xs = 0:numel(ys)-1 overload
PsychImGui('ImPlot.PlotHeatmap', label, values [, scaleMin=0] [, scaleMax=0] [, labelFmt='%.1f'] [, boundsMin=[0 0]] [, boundsMax=[1 1]] [, spec...])
[clicked, x, y] = PsychImGui('ImPlot.DragPoint', id, x, y, col [, size=4] [, flags=0])
pos = PsychImGui('ImPlot.GetPlotMousePos' [, xAxis='X1'] [, yAxis='Y1'])   % 1x2 double
```

Marshaling rules specific to ImPlot are in section 7.6.

### 5.5 Error identifiers

| Identifier | Meaning |
|---|---|
| `psychimgui:Usage` | Wrong number or class of arguments. Message names the subcommand and the expected signature. |
| `psychimgui:UnknownCommand` | Subcommand name or opcode not found. |
| `psychimgui:NotInit` | Subcommand needs `Init` first. |
| `psychimgui:AlreadyInit` | `Init` called twice. |
| `psychimgui:NoGLContext` | GL subcommand called with no current GL context. Message reminds about `Screen('BeginOpenGL')`. |
| `psychimgui:GLInit` | Backend initialization failed. Message contains the GL version string and the backend log. |
| `psychimgui:GLError` | `glGetError` returned an error after a GL subcommand. Message contains the enum name and the subcommand. |
| `psychimgui:ImGuiAssert` | An `IM_ASSERT` fired inside Dear ImGui during the last call. Message contains the assert text, file, and line. |
| `psychimgui:Type` | Argument has the wrong class, for example a `string` scalar where char is required. |
| `psychimgui:Range` | Numeric argument out of range for its C type. |
| `psychimgui:Font` | Font file not found or failed to load. |

## 6. Input handling

### 6.1 Input struct

`PsychImGuiInput('Poll')` returns a struct. All fields are double arrays so the
MEX reads them with `mxGetPr` without conversion.

| Field | Shape | Content | Source |
|---|---|---|---|
| `mouse` | 1x3 | x, y in window pixels, valid flag (0 when the pointer is outside the window or the window has no focus) | `GetMouse(win)` |
| `buttons` | 1xB, B <= 5 | Button states, left, right, middle, x1, x2 | `GetMouse(win)` |
| `wheel` | 1x2 | Vertical and horizontal wheel clicks since the last poll | `GetMouseWheel()`; zeros when unavailable |
| `keys` | Nx4, N may be 0 | Rows `[keycode pressed cookedKey time]` | `KbEventGet(kq)` drained until empty |
| `display` | 1x2 | Width and height of the client rectangle in pixels | `Screen('Rect', win)` |
| `time` | 1x1 | Poll time in seconds | `GetSecs` |
| `focus` | 1x1 | 1 when the PTB window has focus, default 1 | optional |
| `fbscale` | 1x1 | Framebuffer scale, default 1 | optional, for macOS Retina |

`NewFrame` processes the struct in this order: focus, mouse position, buttons,
wheel, key rows in time order, then computes `DeltaTime` from `time` and clamps
it to the range 0.0001 to 0.1 seconds. The first frame uses 1/60 seconds.

Mouse position uses `AddMousePosEvent(x, y)`, or `(-FLT_MAX, -FLT_MAX)` when
`valid` is 0. Buttons use `AddMouseButtonEvent` only for changes since the
previous frame, tracked in the MEX. Wheel uses `AddMouseWheelEvent(wheelH,
wheelV)`.

### 6.2 Keyboard mapping

`PsychImGuiKeymap.m` builds the table once:

1. Call `KbName('UnifyKeyNames')`.
2. For keycode `k` from 1 to 256, get `name = KbName(k)`.
3. Look the name up in a fixed map of about 105 entries from PTB unified names
   to `ImGuiKey` values, for example `'LeftArrow'` to `ImGuiKey_LeftArrow`,
   `'a'` to `ImGuiKey_A`, `'1!'` to `ImGuiKey_1`, `'LeftShift'` to
   `ImGuiKey_LeftShift`, `'Return'` to `ImGuiKey_Enter`, `'KP_Enter'`... to
   `ImGuiKey_KeypadEnter`.
4. Unknown names map to 0, which the MEX ignores.

The table is `int32(256,1)` and is passed to `Init`. Reason for building it in
MATLAB: PTB owns the per-platform keycode differences. The MEX does not need a
per-OS table.

For each key row, the MEX calls `AddKeyEvent(map[keycode], pressed)`. The MEX
tracks Ctrl, Shift, Alt, and Super from the same rows and calls `AddKeyEvent`
for `ImGuiMod_Ctrl`, `ImGuiMod_Shift`, `ImGuiMod_Alt`, `ImGuiMod_Super` when a
modifier state changes.

### 6.3 Text input

PTB's `KbEventGet` returns `CookedKey`, the Unicode code point of the key press
under the current keyboard layout. `CookedKey` is 0 for keys with no character
and -1 when the platform does not support the mapping. The MEX calls
`AddInputCharacter(cookedKey)` for rows with `pressed == 1`, `cookedKey >= 32`,
and `cookedKey ~= 127`. Control characters arrive through key events, not
characters. The code point never passes through a MATLAB `char`, so UTF-16
surrogates are not an issue.

PTB encodes `CookedKey` as UTF-16 on Windows and UTF-32 on Linux and macOS.
Code points above U+FFFF on Windows arrive as two rows with surrogate halves.
The MEX combines a high surrogate followed by a low surrogate into one code
point.

### 6.4 Focus and capture

`in.focus == 0` triggers `AddFocusEvent(false)`, which clears held keys and
buttons. Scripts that share input between the GUI and the experiment call
`PsychImGui('WantCapture')` after `NewFrame` and ignore experiment input while
the GUI wants it.

## 7. Marshaling rules and the generator

### 7.1 Generator

`gen/generate.py` runs with `uv run gen/generate.py`. It reads
`third_party/cimgui/generator/output/definitions.json` and
`structs_and_enums.json`, filters by `gen/allowlist.txt`, and writes:

- `src/gen_dispatch.cpp`: one static handler per function, the sorted name
  table, the opcode enum, and the enum value table.
- `m/PsychImGui.m`: help text with every signature.
- `m/PsychImGuiOp.m`: opcode constants.
- `tests/test_gen_marshal.m`: one round-trip test per function (section 11).

The generator uses only the Python standard library. It fails with a clear
message when an allowlisted function uses a type without a marshaling rule.

### 7.2 Allowlist format

One entry per line: `<ov_cimguiname> [<MatlabName>]`. The MATLAB name defaults
to the `funcname` field. Comments start with `#`.

```
igBegin
igBeginChild_Str        BeginChild
igRadioButton_Bool      RadioButton
igRadioButton_IntPtr    RadioButtonInt
igCombo_Str_arr         Combo
igTextUnformatted       Text
```

`ov_cimguiname` selects the overload. Two overloads that both belong in the API
get distinct MATLAB names.

### 7.3 Type rules

| C type (from `argsT`) | MATLAB input | MATLAB output |
|---|---|---|
| `const char*` | char row vector. MATLAB `string` is rejected with `psychimgui:Type` because Octave has no `string` class. On MATLAB, UTF-16 is converted to UTF-8 into a 4 KB stack buffer, heap above that. On Octave, char is UTF-8 bytes already. | `mxCreateString` from UTF-8 |
| `bool` | double or logical scalar | logical scalar |
| `int`, `unsigned int`, `ImGuiID`, `ImS32`, `ImU32` when not a color | double scalar, range checked, `psychimgui:Range` | double scalar |
| `float`, `double` | double scalar | double scalar |
| `ImGuiXxxFlags`, `ImGuiXxx` enums | double scalar, or a char name, or a cellstr of names combined with OR | double scalar |
| `bool*`, `int*`, `float*`, `double*` (in-out) | input at the same argument position | extra output in argument order, after the return value |
| `float v[N]`, `int v[N]` | 1xN double | 1xN double as extra output |
| `const float* values` with `int values_count` | double vector; the count argument is removed from the MATLAB signature | none |
| `ImVec2`, `const ImVec2&` | 1x2 double | 1x2 double |
| `ImVec4`, `const ImVec4&` | 1x4 double | 1x4 double |
| `ImU32 col` in color positions (`PushStyleColor`, `ColorButton`) | 1x4 double in 0 to 1, or a double scalar packed ABGR | 1x4 double |
| `const char* fmt, ...` | one char argument. The handler calls the function with `"%s", str`. | none |
| `const char* const items[]` with `int items_count` | cellstr; the count argument is removed | none |
| `char* buf, size_t buf_size` (InputText) | see section 7.5 | see section 7.5 |
| `bool* p_open` | optional double or logical | extra output when supplied |
| `ImGuiInputTextCallback`, `void* user_data`, `ImDrawList*`, `ImFont*`, `ImGuiViewport*`, `ImGuiStorage*`, `ImGuiPayload*`, `ImGuiListClipper*` | not supported in phase 1. The generator refuses the entry. | |

### 7.4 Defaults and return convention

Arguments with a value in `defaults{}` become optional trailing arguments. The
generator parses the default literals: numbers, `NULL`, `"%.3f"`, `ImVec2(0,0)`,
`ImVec4(...)`, `FLT_MAX`, and enum names resolved through
`structs_and_enums.json`.

Return convention: `[ret, io1, io2, ...]`. `ret` is the C return value. For a
`void` function the first output is `io1`. Outputs the caller does not request
are not created.

### 7.6 ImPlot rules

ImPlot's data functions are templates over the numeric type, and cimplot
exposes one overload per type, for example `ImPlot_PlotLine_doublePtrdoublePtr`,
`ImPlot_PlotLine_FloatPtrFloatPtr`, `ImPlot_PlotLine_S16PtrS16Ptr`. The
generator groups these overloads under one MATLAB subcommand and dispatches on
the MATLAB class of the data argument:

| MATLAB class | ImPlot type | Copy |
|---|---|---|
| double | `double` | none, `mxGetPr` pointer passed directly |
| single | `float` | none |
| int8, uint8, int16, uint16, int32, uint32, int64, uint64 | `ImS8` to `ImU64` | none |
| logical | rejected, `psychimgui:Type` | |

Rules:

- `const T* xs, const T* ys, int count`: two arrays of the same class and the
  same `numel`. `count` is removed from the MATLAB signature. Complex arrays are
  rejected. The pointer is valid for the duration of the call, which is all
  ImPlot needs, because ImPlot copies what it draws into the draw list.
- `const T* values, int rows, int cols` (heat maps, 2D histograms): one matrix.
  `rows` and `cols` come from `size`. The handler adds
  `ImPlotHeatmapFlags_ColMajor` so MATLAB's column-major layout is read
  without a transpose or copy.
- `const ImPlotSpec spec`: optional trailing name-value pairs, mapped to the
  `ImPlotSpec` scalar fields: `LineColor` (1x4 double 0 to 1, or `'Auto'`),
  `LineWeight`, `FillColor`, `FillAlpha`, `Marker` (name such as `'Circle'`
  or number), `MarkerSize`, `MarkerLineColor`, `MarkerFillColor`, `Size`,
  `Offset`, `Stride` (elements, converted to bytes), `Flags` (number or names).
  A struct with the same field names is also accepted. The per-item pointer
  fields (`LineColors`, `FillColors`, `MarkerSizes`, `MarkerLineColors`,
  `MarkerFillColors`) are phase 2.
- `ImPlotPoint` is a 1x2 double in both directions. `ImPlotRange` is 1x2.
  `ImPlotRect` is 1x4 `[xMin xMax yMin yMax]`.
- `ImAxis` accepts a number or a name `'X1'` to `'X3'`, `'Y1'` to `'Y3'`.
- `ImPlotColormap` accepts an index or a built-in name such as `'Viridis'`.
- `double* x, double* y` in `DragPoint` and `DragLineX` follow the in-out rule
  of section 7.3.
- Excluded: getter-callback forms (`PlotLineG`), `ImPlotFormatter` and
  `ImPlotTransform` callbacks, `SetupAxisScale` with custom transforms,
  `ImPlotColormapData*`.

### 7.5 InputText

The script passes the current text. The MEX copies it into a stack buffer of
`max(bufSize, 256)` bytes (default `bufSize` 1024, heap above 64 KB), calls
`ImGui::InputText`, and returns `[changed, newStr]`. The script stores
`newStr` in its own variable. The MEX keeps no text keyed by widget ID, because
IDs collide across windows and stale entries would leak on `clear`. Cost: one
UTF-8 conversion per call, about one microsecond for short strings.
`InputTextMultiline` uses a default `bufSize` of 16 KB.

## 8. State, lifecycle, and error handling

### 8.1 State

One static `State` struct in `psychimgui.cpp`:

| Member | Content |
|---|---|
| `ctx` | `ImGuiContext*` |
| `renderer` | `OpenGL3` or `None` |
| `keymap[257]` | `ImGuiKey` per PTB keycode, 1-based |
| `modState` | held modifier bitset |
| `buttonState` | previous frame button bits |
| `lastTime` | previous `in.time` |
| `fonts[16]` | `ImFont*` table |
| `stats` | fixed arrays, section 9 |
| `deferredError` | flag, id, message buffer of 512 bytes |

The struct is zero-initialized. No heap allocation happens on the per-frame
path except inside Dear ImGui.

### 8.2 Lifecycle

- `Init`: `mexLock`, `IMGUI_CHECKVERSION`, `CreateContext`, `io.IniFilename`
  from `opts`, `io.BackendFlags` (no flags needed), `ImGui_ImplOpenGL3_Init`
  when `renderer == OpenGL3`, `mexAtExit(atExit)`.
- `Shutdown`: if a GL context is current, `ImGui_ImplOpenGL3_Shutdown`. If not,
  log a warning and skip. Then `DestroyContext`, zero the state, `mexUnlock`.
- `atExit`: same as `Shutdown`. Runs on `clear mex` after `mexUnlock` and on
  MATLAB exit.
- Current context detection: `wglGetCurrentContext`, `glXGetCurrentContext`,
  `CGLGetCurrentContext` behind one `gl_current.h`.

### 8.3 Asserts and errors

`IM_ASSERT` is redefined through `IMGUI_USER_CONFIG`. On failure it writes the
message into `deferredError` and returns. It never calls `abort` and never
`longjmp`s, because Dear ImGui is not exception safe. Each dispatched call
checks `deferredError` on return and raises `psychimgui:ImGuiAssert`. Dear ImGui
error recovery (`io.ConfigErrorRecovery`) is enabled so a missing `End` does not
cascade into the next frame.

`mexErrMsgIdAndTxt` is called only from the dispatch layer, after all C++
objects with destructors have gone out of scope.

## 9. Performance and profiling

### 9.1 Dispatch

- Subcommand names are read with `mxGetString` into a 64-byte stack buffer. No
  `mxArrayToString`, no `malloc`.
- The generated table `static const Entry kTable[]` is sorted by name. Lookup is
  a binary search, about 7 comparisons for 128 entries.
- Fast path: when the first argument is a numeric scalar, the MEX uses it as an
  opcode index after a bounds check. `PsychImGuiOp.m` provides the constants:
  `op = PsychImGuiOp(); PsychImGui(op.SliderFloat, ...)`.

Budgets:

| Item | Target |
|---|---|
| Dispatch plus marshaling, scalar function | under 0.5 us |
| MATLAB MEX call overhead (not ours) | 1 to 3 us on MATLAB, 5 to 10 us on Octave |
| 200 widgets per frame, MATLAB side total | under 1 ms |
| `Render` CPU for 200 widgets | under 0.3 ms |

### 9.2 Built-in Stats

Always compiled unless `PSYCHIMGUI_STATS=0`. Per opcode: `calls`, `totalNs`,
`maxNs` in fixed `uint64` arrays. Timer: `QueryPerformanceCounter` on Windows,
`clock_gettime(CLOCK_MONOTONIC)` elsewhere. Overhead about 30 ns per call.
`Render` also records `drawCalls` and `vertices` from `ImDrawData`, and GPU time
from a `GL_TIMESTAMP` query pair when `GL_ARB_timer_query` is available. GPU
time is read two frames later to avoid a stall.

### 9.3 Tracy

CMake option `PSYCHIMGUI_TRACY` (default OFF) compiles `TracyClient.cpp` into
the MEX and adds `ZoneScopedN` in dispatch, `NewFrame`, `Render`, and the
InputText conversion, plus `FrameMark` at the end of `Render`. Capture with
`tracy-capture`, export with `tracy-csvexport` for text analysis.

### 9.4 What to measure first

1. Per-call overhead, string path against opcode path (`tests/perf_dispatch.m`).
2. `Screen('BeginOpenGL')` plus `Screen('EndOpenGL')` cost per frame, without
   any ImGui call. This is a PTB cost the design cannot remove.
3. `Render` CPU and GPU time for the demo panel.

## 10. Build

### 10.1 Layout

```
PsychImGui/
  CMakeLists.txt          builds imgui_static (imgui core + imgui_impl_opengl3 + optional Tracy)
  build.m                 MATLAB/Octave build driver, mirrors the user's mex-msgpack pattern
  README.md               how to build and run the demo
  SPEC.md                 this document
  src/
    psychimgui.cpp        mexFunction, dispatch, state, lifecycle, input, render
    marshal.h             mxArray <-> C helpers used by generated code
    dispatch.h            Entry table type, opcode enum include
    gen_dispatch.cpp      generated, committed
    gl_current.h          current-context detection per platform
    imconfig_psych.h      IMGUI_USER_CONFIG: IM_ASSERT redirection, IMGUI_DISABLE_OBSOLETE_FUNCTIONS
  gen/
    generate.py           generator
    allowlist.txt         allowlist
    templates/            handler and help templates
  m/
    PsychImGui.m PsychImGuiInput.m PsychImGuiFrame.m PsychImGuiKeymap.m PsychImGuiOp.m PsychImGuiDemo.m
  tests/
    run_tests.m test_dispatch.m test_gen_marshal.m test_inputtext.m test_keymap.m test_stats.m
    perf_dispatch.m perf_frame.m
    gl/test_gl_render.m
  third_party/
    cimgui/               submodule (contains imgui/ submodule)
    cimplot/              submodule (contains implot/ submodule)
    tracy/                submodule, optional
```

`gen/allowlist.txt` has one section per namespace (`[ImGui]`, `[ImPlot]`).
Generated ImPlot handlers live in `src/gen_dispatch_implot.cpp`, compiled only
with `PSYCHIMGUI_IMPLOT=ON`.

### 10.2 Flow

`build.m` follows the `mex-msgpack` pattern: detect the engine with
`exist('OCTAVE_VERSION', 'builtin')`, configure and build the static library
with CMake, then call `mex`.

1. Choose the build directory: `build-matlab/` or `build-octave/`. The two
   engines use different compilers on Windows (MSVC 2022 for MATLAB, MinGW g++
   for Octave), and C++ objects from different compilers must not be linked
   together.
2. CMake configure. For Octave on Windows use `-G "MinGW Makefiles"` and
   `-DCMAKE_CXX_COMPILER` from `mkoctfile -p CXX`. Honor `MEX_CMAKE_GENERATOR`
   as an override. Options: `-DCMAKE_BUILD_TYPE=Release`,
   `-DPSYCHIMGUI_TRACY=OFF`, `-DPSYCHIMGUI_STATS=1`, `-DPSYCHIMGUI_IMPLOT=ON`.
   With ImPlot on, the library also compiles `implot.cpp`, `implot_items.cpp`,
   and `implot_demo.cpp` with `IMPLOT_DISABLE_OBSOLETE_FUNCTIONS`.
3. `cmake --build` and `cmake --build --target install` into `inst-<engine>/`.
4. `mex` with `-R2017b`, C++17 (`COMPFLAGS="$COMPFLAGS /std:c++17"` on MSVC,
   `CXXFLAGS="$CXXFLAGS -std=c++17"` otherwise), include paths for imgui and
   `src/`, the static library, and `opengl32.lib` or `-lGL`. On macOS
   `-framework OpenGL`. Output `dist/PsychImGui.<mexext>`.
5. `build.m gen` runs the generator first. `build.m test` runs `run_tests.m`.

Compile definitions for the library and the MEX: `IMGUI_USER_CONFIG="imconfig_psych.h"`
and `IMGUI_DISABLE_OBSOLETE_FUNCTIONS`. Do not define `IMGUI_IMPL_OPENGL_ES2` or
`IMGUI_IMPL_OPENGL_ES3`; without them the backend uses its embedded desktop GL
loader (`imgui_impl_opengl3_loader.h`), which is what PTB contexts need.

### 10.3 CI

Same shape as `mex-msgpack`: build on the oldest supported release, test the
binary on the newest. Octave through the `gnuoctave/octave` Docker images, Octave
on Windows through MSYS2 with `MEX_CMAKE_GENERATOR=Ninja`. CI runs the
`renderer='none'` tests only. GL tests run on developer machines.

## 11. Testing

### 11.1 Without a GPU

`Init` with `opts.renderer = 'none'` skips the OpenGL backend. Dear ImGui
builds its font atlas in software and `Render` discards the draw data. This
path runs in `run_tests.m` under both engines:

- `test_dispatch.m`: unknown name, opcode path, wrong argument count, `Init`
  twice, subcommand before `Init`.
- `test_gen_marshal.m`: generated. For each allowlisted function, one call
  inside a headless frame with default arguments, plus one call with all
  optional arguments, checking output count and class.
- `test_inputtext.m`: round trip of ASCII and non-ASCII text, `bufSize`
  truncation.
- `test_keymap.m`: table shape, arrows and letters mapped, unknown names 0.
- `test_stats.m`: counters increase, `reset` clears.
- Assert path: a deliberate `End` without `Begin` raises `psychimgui:ImGuiAssert`
  and the next frame works.

### 11.2 With PTB and a GPU

`tests/gl/test_gl_render.m` opens a 640x480 PTB window, draws a filled window
with a known background color, calls `Screen('GetImage')` after `Flip`, and
checks the mean color inside the window rectangle within a tolerance. It also
checks that `Render` raises `psychimgui:GLError` when a GL error is injected
through a debug subcommand compiled only in test builds.

Every script that opens a PTB window goes through one helper,
`tests/gl/ptb_test_window.m`, which sets `Screen('Preference',
'SkipSyncTests', 2)` and `Screen('Preference', 'VisualDebugLevel', 0)` before
`PsychImaging('OpenWindow')`, so a test run pays for neither the display
timing calibration nor the startup splash screen.

### 11.3 Interactive

`PsychImGuiDemo.m`: a Gabor patch whose contrast, spatial frequency, and
orientation come from sliders; a text field; `ShowDemoWindow`. `perf_frame.m`:
200 sliders per frame for 600 frames, prints `Stats` and a frame time
histogram.

## 12. Risks, alternatives considered, open questions

### 12.1 Risks

| Risk | Mitigation |
|---|---|
| `IM_ASSERT` aborts the MATLAB process | Redirected to a deferred error, section 8.3. Error recovery enabled. |
| PTB imaging pipeline with float FBOs or sRGB blending changes GUI colors | Document. Offer `opts.srgb` to gamma-adjust style colors. |
| Stereo modes or panel fitter change the client rectangle | `display` is re-read every frame. Per-eye GUI rendering is not supported in phase 1. |
| Octave char is UTF-8 bytes, MATLAB char is UTF-16 | Compile-time branch in `marshal.h`. Both paths produce UTF-8 for Dear ImGui. |
| `clear all` while a PTB window is open | `mexLock` in `Init` prevents unloading. `Shutdown` unlocks. |
| `BeginOpenGL` and `EndOpenGL` cost | Measure first. Two context switches per frame are expected to cost 50 to 200 us. |
| `GetMouseWheel` unavailable on some setups | `wheel` field is optional and defaults to zeros. |
| Dear ImGui texture API (1.92) changes | The backend owns texture updates. The MEX never touches `ImTextureData`. |
| Generator misses a type | Generator refuses the entry with a message. The allowlist grows only with a rule. |
| ImPlot and Dear ImGui versions drift apart | Both come through cimgui-family submodules pinned on the same day. `implot.h` checks `IMGUI_VERSION_NUM` at compile time. |
| Large plot arrays every frame | Data pointers are passed without a copy. ImPlot itself copies only visible vertices into the draw list. `perf_frame.m` includes a 100k-point line plot. |

### 12.2 Alternatives considered

- Compile cimgui and call the C API. Rejected: the MEX is C++ already. A second
  layer adds nothing.
- One M-file per widget instead of one MEX with subcommands. Rejected: extra
  per-call overhead in MATLAB and hundreds of files. `Screen` sets the precedent.
- Keymap table in C, per platform. Rejected: PTB already unifies key names.
- MEX-side text buffers keyed by ImGui ID. Rejected: ID collisions across
  windows and leaks on `clear`.
- Perfect hash for dispatch. Rejected: binary search over about 130 names costs
  under 100 ns and keeps the generator simple.

### 12.3 Open questions

| Question | Default assumed by this specification |
|---|---|
| MATLAB names verbatim from Dear ImGui, or PTB-style names? | Verbatim. |
| Accept MATLAB `string` scalars? | No, char only, because Octave has no `string` class. |
| Tables and `ImDrawList` in phase 1? | No, phase 2. |
| Is Octave support blocking for CI? | Yes, as in `mex-msgpack`. |
| Support for macOS? | Best effort, GL 2.1 compatibility context, `glslVersion='#version 120'`. Not CI-blocking. |

## 13. Phasing

| Phase | Content |
|---|---|
| 1 | Lifecycle, input, generator, allowlist of section 5.2, `Stats`, `renderer='none'` tests, demo. |
| 1.5 | ImPlot: context lifecycle, section 7.6 rules, allowlist of section 5.4, generated tests, a demo panel with a live trace and a heat map. |
| 2 | Tables (`BeginTable`, `TableNextRow`, `TableNextColumn`, `TableSetupColumn`, `TableHeadersRow`), `ImDrawList` through an opaque handle for the window and background draw lists (`AddLine`, `AddRect`, `AddCircle`, `AddText`), `PsychImGui('Image', ptbTexture, size)` by reading the GL texture id with `Screen('GetOpenGLTexture')`. |
| 3 | Tracy GPU zones, per-eye rendering for stereo modes, multiple contexts for multiple PTB windows, ImPlot3D through `cimplot3d`, ImGuiFileDialog hand-written. |

## 14. Deviations from version 0.1

This section records every place where the implementation differs from the
specification above, and why. Section 13 phases 1 and 1.5 are implemented.

### 14.1 Dependencies

| Deviation | Reason |
|---|---|
| `third_party/cimgui` and `third_party/cimplot` are git submodules, pinned at the commits in `third_party/PINS.md`. They started as plain clones while phase 1 was written and were registered as submodules at the same paths and commits on 2026-09-22. | The repository did not exist while phase 1 was written. |
| The cimplot pin is not from the same day as the cimgui pin. | cimgui is pinned at 2026-09-14 (Dear ImGui 1.92.9b) and cimplot at 2026-08-13 (ImPlot 1.1 WIP), which is the newest cimplot commit. ImPlot 1.1 compiles and links against Dear ImGui 1.92.9b unchanged, and the whole ImPlot test suite passes. |
| `third_party/tracy` is not cloned. | Tracy is optional. See 14.5. |

### 14.2 Build

| Deviation | Reason |
|---|---|
| `IMGUI_USER_CONFIG` reaches the MEX through `src/imgui_psych.h` instead of a `-D` flag. | MATLAB's `mex` strips the quotes out of `-DIMGUI_USER_CONFIG="imconfig_psych.h"` on Windows, and the compiler then fails on an empty `#include`. The header defines the macro and then includes `imgui.h`; every MEX translation unit includes it first. The CMake library keeps the compile definition, so both halves share one configuration. |
| Octave on Windows configures CMake with the "MSYS Makefiles" generator and explicit tool paths. | Section 10.2 suggests "MinGW Makefiles". That generator refuses to run while `sh.exe` is on PATH, and Git for Windows always puts one there. Octave's toolchain lives in `mingw64/bin` and its `make` in `usr/bin`, which Octave does not put on PATH, so `build.m` names the compiler, `ar`, `ranlib`, and `make` by absolute path. `MEX_CMAKE_GENERATOR` still overrides the generator. |
| Octave gets C++17 through the `CXXFLAGS` environment variable, not a `CXXFLAGS=...` argument to `mex`. | Octave's `mex` rejects a `NAME=value` argument; `mkoctfile` reads its flags from the environment. `build.m` sets and restores the variable around the call. |
| `tools/smoke_gl.cpp` and the `PSYCHIMGUI_SMOKE_GL` CMake option are new. | Psychtoolbox was not installed when the binding was written, so the OpenGL path needed a proof that does not depend on it. `smoke_gl` creates a hidden window with a legacy compatibility context, the same kind PTB creates, and runs the core through Init, three frames, and Shutdown. `smoke_gl none` runs the headless path. Only the Windows context path is implemented; GLX and CGL print a clear message and exit. |
| `src/core/`, `src/implot_marshal.h`, and `src/imgui_psych.h` are additions to the 10.1 source layout. | `src/core/` holds the engine independent half, so `smoke_gl` links it without MATLAB. `implot_marshal.h` holds the section 7.6 rules, which need `implot.h` and so cannot live in `marshal.h`. |
| `gen/templates/` does not exist. | The generator emits the handlers and the help text directly. A template directory would add a layer without removing any code. |
| The MEX goes to `dist/<arch>/`, and the build and install directories carry a platform name (`build-octave-linux/`, `inst-matlab-windows/`). | Section 10.2 says `dist/PsychImGui.<mexext>`. Octave names its MEX `PsychImGui.mex` on every operating system, so one flat `dist` lets a Linux build silently replace a Windows one in a checkout shared between Windows and WSL. `<arch>` uses the MATLAB platform names, which Octave does not report, so `m/PsychImGuiSetup` derives them from `ispc`, `ismac`, and `isunix` instead of `computer('arch')`. |
| `m/PsychImGuiSetup.m` is a new helper. | It puts `dist/<arch>` ahead of `m/` on the path and raises `psychimgui:NotBuilt` with the expected file and the build command when this platform has no MEX. `run_tests`, the demo, the GL test, and the perf scripts call it instead of each hard-coding the layout. |
| The Linux MEX and the static library link `-ldl`. | `imgui_impl_opengl3` resolves its GL entry points with `dlopen`. glibc 2.34 and newer fold libdl into libc, so Ubuntu 22.04 links without it, but Ubuntu 20.04, which is the Octave 6.4 Docker image, does not. CMake uses `${CMAKE_DL_LIBS}`, which is empty where the library does not exist. |

### 14.3 Binding surface

| Deviation | Reason |
|---|---|
| The return convention of section 7.4 is applied uniformly, so `Begin` is `[visible, open] = PsychImGui('Begin', name [, open] [, flags])`. | Section 5.2 prints `open = PsychImGui('Begin', ...)` as shorthand. One rule for every generated subcommand is easier to predict than a per-function convention. |
| `Text` binds `igText` and goes through the `fmt` rule, not `igTextUnformatted`. | Section 7.2 shows `igTextUnformatted Text` as an allowlist example, but section 7.3 gives the `const char* fmt, ...` rule. Applying the fmt rule makes Text, TextColored, TextDisabled, TextWrapped, LabelText, and BulletText take exactly one char argument each, with no `text_end` to explain. |
| Overloads that differ only in argument class get separate MATLAB names: `PushID` and `PushIDInt`, `RadioButton` and `RadioButtonInt`, `PushStyleVar` and `PushStyleVarVec2`, `ImPlot.PushColormap` and `ImPlot.PushColormapIndex`, and `ImPlot.PushStyleVar`, `PushStyleVarInt`, `PushStyleVarVec2`. | Section 5.2 lists them as one entry each, but phase 1 dispatches on the subcommand name. Class dispatch exists only for the ImPlot data arrays of section 7.6. |
| `PushStyleColor` binds the `ImVec4` overload only. | Section 7.3 also lists a packed `ImU32` form. In Dear ImGui 1.92 `ColorButton` already takes an `ImVec4`, and the MATLAB type is a 1x4 double in 0 to 1 either way, so the `ImU32` overload adds no capability. |
| `CalcTextSize` drops `text_end`; `PlotLines` and `PlotHistogram` drop `values_offset` and `stride`; `ImPlot.BeginSubplots` drops `row_ratios` and `col_ratios`. | The allowlist grew a `-<arg_name>` token for this, which passes the C default. `text_end` is a pointer into another argument, `stride` is meaningless for a MATLAB vector, and the two ratio arguments are float arrays, which phase 1.5 does not marshal. |
| `PsychImGui('Enum')` returns all 978 public enum names from both namespaces. | Section 5.1 says "the whole table"; this is it, built on request only. |
| The opcode table contains the ImPlot names whether or not `PSYCHIMGUI_IMPLOT` is on. | An opcode that moved with a build option would make `m/PsychImGuiOp.m` wrong for one of the two builds. With ImPlot off, those entries raise `psychimgui:UnknownCommand`. |

### 14.4 renderer='none'

Section 11.1 assumed that without a renderer Dear ImGui builds its font atlas
in software. In 1.92 the opposite happens: a backend that does not set
`ImGuiBackendFlags_RendererHasTextures` leaves `atlas->Builder` null, and the
next `NewFrame` dereferences it. The deferred `IM_ASSERT` of section 8.3
returns instead of aborting, so the null dereference follows immediately.

The `none` renderer therefore sets `ImGuiBackendFlags_RendererHasTextures` and
answers the texture requests in `Render` with a placeholder texture id. The
behavior is what 11.1 asked for: no GPU, no upload, and the draw data
discarded. This is the cost of the deferred assert. An assertion that guards a
later pointer dereference turns a clean abort into a crash, so the `none` path
has to satisfy the invariant rather than rely on the assert. The other asserts
the test suite fires recover as designed.

### 14.5 Profiling

| Deviation | Reason |
|---|---|
| `Stats.frame.renderGpuNs` is always 0. | Section 9.2 asks for a `GL_TIMESTAMP` query pair. The GL entry points for timer queries live in the backend's private loader (`imgui_impl_opengl3_loader.h`), and a second GL loader inside the MEX for one counter was not worth it in phase 1. Everything else in 9.2 is recorded: per-opcode `calls`, `totalNs`, and `maxNs`, and per-frame `newFrameNs`, `renderCpuNs`, `drawCalls`, and `vertices`. |
| `PSYCHIMGUI_TRACY` compiles the client but adds no zones. | The option sets `TRACY_ENABLE` and compiles `TracyClient.cpp` when `third_party/tracy` is present, but no `ZoneScopedN` or `FrameMark` call exists yet, and the clone is not there. Section 9.3 stays open. |

Measured on the development machine (Windows 11, Intel Iris Xe, MSVC 19.44,
Octave 10.1 with GCC 14.2), 200000 calls per case:

| Case | MATLAB R2023a | Octave 10.1 |
|---|---|---|
| `GetFrameCount`, name path | 1.63 us | 2.56 us |
| `GetFrameCount`, opcode path | 0.85 us | 2.72 us |
| `Button(label)`, name path | 1.29 us | 2.75 us |
| `Button(label)`, opcode path | 0.73 us | 3.01 us |
| `Button` inside the MEX (`Stats`) | 0.14 us mean | 0.15 us mean |
| 200 sliders per frame, whole frame | 0.99 ms mean | 3.93 ms mean |

The opcode path saves 0.56 to 0.79 us per call on MATLAB. On Octave it does not
help: Octave's cost of passing a numeric scalar argument is higher than the name
lookup it replaces, and the binary search costs well under 100 ns either way.
The budget of section 9.1, under 0.5 us for dispatch plus marshaling, is met:
the `Stats` counters, which time only the handler, read 0.14 us for `Button`.
The rest is the engine's own MEX call overhead, which the design cannot remove.

### 14.6 Testing

| Deviation | Reason |
|---|---|
| `tests/t_ok.m`, `t_eq.m`, `t_isa.m`, `t_throws.m`, and `tf_input.m` are new files. | Octave cannot share subfunctions across files, so the assertion harness needs one file per function, as in the reference mex-msgpack project. |
| `tests/test_assert.m` is a separate file. | Section 11.1 lists the assert path without naming a file. |
| `tests/gl/ptb_test_window.m` is new, and every script that opens a Psychtoolbox window calls it. | It sets `SkipSyncTests` to 2 and `VisualDebugLevel` to 0 before opening the window, so a test run pays for neither the display timing calibration nor the splash screen. Section 11.2 records the rule. |
| No GL error injection subcommand. | Section 11.2 asks for a debug subcommand, compiled only in test builds, that injects a GL error so `Render` can be seen to raise `psychimgui:GLError`. `tests/gl/test_gl_render.m` checks only that `Render` leaves `glGetError` clean. |
| The generated test skips `ImPlot.PushStyleVarInt` and runs `ImPlot.AddColormap` once. | ImPlot 1.1 declares a `PushStyleVar(int)` overload but has no integer style variable, so every call asserts. ImPlot keeps a colormap name forever, so a second `AddColormap` with the same name asserts. The generator records both in `TEST_SKIP` and `TEST_ONCE` rather than inventing an argument. |
| The non-ASCII cases of `test_inputtext.m` build their strings from numbers, per engine. | MATLAB char holds UTF-16 code units and Octave char holds UTF-8 bytes, so the same three code points are different arrays. Building them from numbers keeps the test independent of how the engine decodes the source file. |

### 14.7 ImPlot

| Deviation | Reason |
|---|---|
| Shape dispatch rule. | Section 7.6 does not say how `PlotShaded(xs, ys, yref)` is told from `PlotShaded(xs, ys1, ys2)`. The rule implemented: the arguments after the label form one data set for as long as they share a class and an element count. A call where every array holds exactly one element is ambiguous and may pick the wrong shape. |
| Where the `ImPlotSpec` pairs begin. | Optional positional arguments and the trailing name-value pairs share one argument list. The boundary is the first struct, or the first char argument that names an `ImPlotSpec` property. A format string such as `'%.1f'` is not a property name, which keeps `PlotHeatmap`'s `labelFmt` unambiguous. |
| The handlers call the ImPlot C++ templates, not the cimplot C overloads. | cimplot's metadata names the overloads, which is what the generator groups by, but ImPlot's public API is one template per shape. Calling the template gives one generated function per shape instead of ten, and the `mxGetData` pointer reaches ImPlot without a cast table. |
| `ImPlot.SetupAxisTicks` binds the values form only; `ImPlot.AddColormap` binds the Nx3 or Nx4 matrix form only. | Section 5.4 names the forms this binds. The `v_min, v_max, n_ticks` tick form and the packed `ImU32` colormap form would each need a second MATLAB name and add nothing the bound form cannot express. |
| `ImPlot.SetupAxisTicks` checks that the label count matches the value count. | ImPlot reads one label per tick. A shorter cellstr made it read past the end of the pointer table, which segfaults. The generator emits the check wherever a cellstr has no count argument of its own. |
| The per-item `ImPlotSpec` pointer fields are not bound. | `LineColors`, `FillColors`, `MarkerSizes`, `MarkerLineColors`, and `MarkerFillColors` are phase 2, as section 7.6 says. |

### 14.8 Continuous integration

Section 10.3 asks for the same shape as the reference mex-msgpack workflow. The
workflow is `.github/workflows/ci.yml`. This project is its own git repository,
named PsychImGui, so the project directory is the repository root and the
workflow needs no path filter to stay out of a sibling project's way.
Differences from 10.3:

| Deviation | Reason |
|---|---|
| The project is its own repository. | Section 10.3 was written while the three bindings shared one tree. Each is now a repository of its own, so `build.m`, `tests/`, and `.github/workflows/ci.yml` all sit at the repository root and nothing in the workflow names a subdirectory. |
| CI runs one OpenGL job, not only the `renderer='none'` suite. | 10.3 says "CI runs the `renderer='none'` tests only". `smoke-gl-linux` builds `tools/smoke_gl.cpp` and runs it against Mesa's llvmpipe under Xvfb, which costs about a minute and is the only automated GL coverage the project can have, since `tests/gl` needs Psychtoolbox and a real window. The engine jobs still run the headless suite only. |
| `tools/fetch_third_party.sh` exists and every build job runs it. | Checkout asks for `submodules: recursive`, which populates them. The script is a no-op in that case and clones the `PINS.md` commits only in a checkout made without submodules. |
| The MATLAB floor is R2021b on Linux and R2022b on Windows. | 10.3 says "the oldest supported release" without naming one. R2022b is the first MATLAB that supports Visual Studio 2022 on a hosted runner. SPEC section 2 names R2023a as the verified release. |
| `tools/smoke_gl.cpp` grew a GLX path. | 14.2 recorded it as Windows only. CI needs it on Linux, so the GLX branch now creates an override-redirect X window, waits for its MapNotify, and calls `glXCreateContext`, which is the legacy call Psychtoolbox uses. macOS is still unimplemented. |

Locally validated before the workflow was written, because the Linux code paths
had never been compiled: Octave 6.4.0 and 10.1.0 in the `gnuoctave/octave`
images and Octave 6.4.0 in WSL all build and pass 550 of 550; the 6.4 build
passes on Octave 9.4.0 and the 10.1 build on Octave 11.3.0 without a rebuild;
`smoke_gl` reports PASS on Mesa llvmpipe 4.5 compatibility under Xvfb on both
Ubuntu 22.04 and Ubuntu 24.04. The workflow itself has not been run: no GitHub
Actions runner was available.

### 14.9 Blocked on Psychtoolbox

`PsychHID.mexw64` on the development machine cannot load, because
`libusb-1.0.dll` is not installed. `PsychImGuiInput('Start')` therefore cannot
create a keyboard queue, and the keyboard and text input path of section 6 has
not been exercised against real key events. `PsychImGuiInput` catches the
failure, warns once, and runs without keyboard input, so the demo and the GL
tests still work. The mouse position, the window rectangle, and the clock come
from `Screen` and `GetSecs` and are unaffected. The marshaling half of the key
path, `PsychImGuiKeymap` and the `in.keys` decoding, is covered by
`test_keymap.m` and by the synthetic input of the headless suite.
