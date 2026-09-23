# PsychImGui specification

Status: implemented through phase 3. Specification version 0.1,
2026-09-23. Section 14 records where the code differs from sections 1
to 13 and why.

`PsychImGui` is a MEX binding of Dear ImGui for MATLAB and GNU Octave. It draws
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

- One Dear ImGui context per PTB onscreen window, up to eight in one MATLAB
  or Octave process, in phase 3. Section 5.1.
- Generated bindings for about 100 core Dear ImGui functions, selected by an
  allowlist. The list grows by editing one file.
- Mouse, wheel, keyboard, and text input from PTB functions.
- GPU rendering through `imgui_impl_opengl3`.
- Extensions from the cimgui family, compiled into the same MEX and bound by
  the same generator. ImPlot is in phase 1.5. Section 5.4 lists the policy and
  the candidates.
- Tables, draw lists through handles, and images from Psychtoolbox textures,
  in phase 2. Sections 5.2, 5.6, and 5.7.
- The GUI in both eyes of the PTB stereo modes, GPU timing, Tracy zones,
  ImPlot3D, and ImGuiFileDialog, in phase 3. Sections 5.1, 5.4, 9.2, 9.3.
- MATLAB R2023a and Octave 10.1 on Windows, verified. Linux verified in CI
  and in WSL. macOS on Apple silicon (`maca64`) is a CI target; see section
  14 for what is and is not verified there.

### 1.3 Out of scope

- Dear ImGui multi-viewport and docking branches.
- Extensions without machine-readable metadata, unless hand-written and small.
- Callbacks from Dear ImGui into MATLAB code.
- Raw `ImDrawList` pointers, and draw list methods other than those of
  section 5.6.
- One context that draws into more than one PTB window. Each window gets a
  context of its own; section 5.1.
- Any code shared with other bindings. This project is self-contained.

## 2. Dependencies and pinned versions

| Dependency | Version | Location | Reason |
|---|---|---|---|
| cimgui | commit tracking Dear ImGui v1.92.9b | `third_party/cimgui` (git submodule) | Provides `generator/output/definitions.json` and `structs_and_enums.json` as machine-readable API metadata. The submodule also contains Dear ImGui as a nested submodule, so the two stay version-matched. cimgui C sources are not compiled. |
| Dear ImGui | v1.92.9b (through cimgui) | `third_party/cimgui/imgui` | Core library plus `backends/imgui_impl_opengl3.*`. |
| cimplot | commit from the same date as the cimgui pin | `third_party/cimplot` (git submodule) | Provides `generator/output/definitions.json` for ImPlot and contains ImPlot as a nested submodule. The cimgui project updates cimgui and cimplot together, so pins from the same day match. cimplot C sources are not compiled. |
| ImPlot | v1.x (through cimplot) | `third_party/cimplot/implot` | `implot.cpp`, `implot_items.cpp`, `implot_demo.cpp`. Compiled with `PSYCHIMGUI_IMPLOT=ON` (default). |
| cimplot3d | commit from the same day as the cimplot pin | `third_party/cimplot3d` (plain clone, phase 3) | `definitions.json` for ImPlot3D, and ImPlot3D as a nested submodule. |
| ImPlot3D | v0.4 (through cimplot3d) | `third_party/cimplot3d/implot3d` | `implot3d.cpp`, `implot3d_items.cpp`, `implot3d_meshes.cpp`, `implot3d_demo.cpp`. Compiled with `PSYCHIMGUI_IMPLOT3D=ON` (default). |
| ImGuiFileDialog | `master`, 0.6.9 WIP | `third_party/ImGuiFileDialog` (plain clone, phase 3) | File dialog, hand-written binding. Compiled with `PSYCHIMGUI_FILEDIALOG=ON` (default). |
| Tracy | 0.11.1 | `third_party/tracy` (plain clone, optional, not fetched) | Profiler client, compiled only with `PSYCHIMGUI_TRACY=ON`. |
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
| PsychImGui MEX (C++17)                                       |
|  dispatch: sorted name table + opcode fast path              |
|  marshal:  mxArray <-> C types (generated per function)      |
|  input:    PTB events -> ImGuiIO                             |
|  state:    a context per window, keymap, stats, deferred error|
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

Four helper M-files own the `Screen('BeginOpenGL')` and `Screen('EndOpenGL')`
pairs, so a script writes none itself. This is the form to write:

```matlab
% Setup, once
InitializeMatlabOpenGL(1);                      % required by Screen('BeginOpenGL')
[win, rect] = PsychImaging('OpenWindow', screenid, 0);
ig = PsychImGuiOpen(win);                       % Init plus the keyboard queue

% Every frame
ig = PsychImGuiFrame('Begin', ig);              % Poll, BeginOpenGL, NewFrame
if PsychImGui('Begin', 'Controls')
    [~, gain] = PsychImGui('SliderFloat', 'Gain', gain, 0, 1);
end
PsychImGui('End');
PsychImGuiFrame('End', ig);                     % Render, EndOpenGL
Screen('Flip', win);

% A subcommand that needs the GL context outside a frame
idx = PsychImGuiGL(ig, 'AddFontFromFileTTF', fontPath, 18);

% Teardown, once
PsychImGuiClose(ig);                            % Shutdown plus the queue
sca;
```

Each helper leaves the userspace OpenGL context through an `onCleanup` or a
`catch`, so an error inside the wrapped region still returns PTB to 2D mode.
Without that, the next `Screen` call aborts the script with a message about
the wrong thing. `PsychImGuiGL` asks `Screen('GetOpenGLDrawMode')` first and
skips the wrapping when a frame already opened the region, because PTB does
not nest those regions.

The same sequence in raw subcommands, which is what the helpers do and what
the MEX contract is written against:

```matlab
% Setup, once
InitializeMatlabOpenGL(1);
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
| R9 | With several windows, the current context and the current GL context belong to the same window. After `SetContext`, call `Screen('BeginOpenGL', win)` for that context's window before any GL subcommand. | Verified in `Windows/Screen/PsychWindowGlue.c`: every onscreen window has its own `contextObject` and `glusercontextObject`, and objects are shared between them only through `wglShareLists`, which PTB calls only for the slave window of a dual window stereo mode. The font texture and shader of one context name nothing, or another window's objects, in another window's context. `Init` records the current GL context handle, and every GL subcommand compares it with the current one and raises `psychimgui:Context` on a mismatch. |
| R10 | In a stereo mode, `Render` once and `RenderAgain` once, each inside its own `Screen('SelectStereoDrawBuffer')` and `BeginOpenGL`, `EndOpenGL` pair. | Verified in `SCREENglMatrixFunctionWrappers.c`: `BeginOpenGL` binds the framebuffer object of the selected eye when the imaging pipeline is on, which `PsychImaging` always turns on, and calls `PsychSwitchFixedFunctionStereoDrawbuffer` otherwise. `SelectStereoDrawBuffer` is a `Screen` call, so it cannot happen inside the region. |

## 5. MATLAB API reference

All functions accept a subcommand name as the first argument, or a numeric
opcode (section 9.1). Names are case sensitive and match Dear ImGui names.
`PsychImGui` with no arguments prints the list of subcommands.
`PsychImGui('Name?')` prints the help for one subcommand, like `Screen`.

### 5.1 Lifecycle subcommands

| Subcommand | Signature | Notes |
|---|---|---|
| Init | `ctx = PsychImGui('Init', win, rect, keymap [, opts])` | `rect` is `Screen('Rect', win)`. `keymap` is `int32(256,1)` from `PsychImGuiKeymap`. `opts` struct fields: `renderer` (`'auto'` default, `'opengl3'`, `'opengl2'`, `'none'` for tests), `glslVersion` (from the context by default), `iniFile` (path or `''` to disable), `logFile`, `implot`, `implot3d`. Makes a context for window `win`, makes it current, and returns its handle, a double. Calls `mexLock` for the first context. Error `psychimgui:AlreadyInit` if a context for the same `win` exists, `psychimgui:Context` when eight exist. |
| Shutdown | `PsychImGui('Shutdown' [, ctx or 'all'])` | Destroys the backend and the context: the current one, the one with handle `ctx`, or all. The current context stays current when another one is shut down; nothing is current after the current one is. Calls `mexUnlock` when no context is left. Safe to call when not initialized, and with a handle that is already shut down. |
| SetContext | `PsychImGui('SetContext', ctx)` | Makes `ctx` current. Every other subcommand acts on the current context. A handle that was never issued or is shut down raises `psychimgui:InvalidHandle`. Retires every draw list handle. |
| GetContext | `[ctx, all] = PsychImGui('GetContext')` | The current handle, 0 for none, and a row vector of every live handle. |
| NewFrame | `PsychImGui('NewFrame', in)` | `in` is the input struct from section 6.1. Feeds `ImGuiIO`, sets `DisplaySize` and `DeltaTime`, calls `ImGui::NewFrame`. A GL subcommand from phase 3 on, because the OpenGL 3 backend creates its shader and font texture on the first frame. |
| Render | `PsychImGui('Render')` | `ImGui::Render`, then `ImGui_ImplOpenGL3_RenderDrawData`, then GL error drain. With `renderer='none'` the draw data is discarded. |
| RenderAgain | `PsychImGui('RenderAgain')` | Submits the draw data of the last `Render` again, for the second eye of a stereo mode, without building a frame. Legal after `Render` and before the next `NewFrame` or `EndFrame`; `psychimgui:Usage` elsewhere. Rule R10. |
| EndFrame | `PsychImGui('EndFrame')` | `ImGui::EndFrame` without rendering. For frames the script decides not to draw. |
| Version | `v = PsychImGui('Version')` | Struct: `imgui` (string), `imguiNum`, `psychimgui`, `renderer`, `glslVersion`, `glVersion`, `glRenderer`, `build` (compiler, engine, date), `implot`, `implotVersion`, `implot3d`, `implot3dVersion`, `fileDialog`, `fileDialogVersion`, `gpuTimer`, `tracy`, `context`. The context fields describe the current context. |
| Opcode | `op = PsychImGui('Opcode', 'SliderFloat')` | Numeric opcode for the fast path. |
| Stats | `s = PsychImGui('Stats' [, 'reset'])` | Struct array per subcommand: `name`, `calls`, `totalNs`, `maxNs`. Plus `frame` struct: `newFrameNs`, `renderCpuNs`, `renderGpuNs` (0 when unavailable), `drawCalls`, `vertices`. Per context: each context counts its own calls, and `reset` clears the current context's counters only. |
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
| Tables (phase 2) | BeginTable, EndTable, TableNextRow, TableNextColumn, TableSetColumnIndex, TableSetupColumn, TableSetupScrollFreeze, TableHeadersRow, TableHeader, TableGetColumnCount, TableGetColumnIndex, TableSetBgColor |
| Draw lists (phase 2) | GetWindowDrawList, GetBackgroundDrawList, GetForegroundDrawList. They return a handle; see section 5.6 |

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
open                 = PsychImGui('BeginTable', strId, columns [, flags=0] [, outerSize=[0 0]] [, innerWidth=0])
PsychImGui('TableSetBgColor', target, color [, columnN=-1])
```

A table call sequence, the same as in C++:

```matlab
if PsychImGui('BeginTable', 'log', 3, {'ImGuiTableFlags_Borders', 'ImGuiTableFlags_RowBg'})
    PsychImGui('TableSetupColumn', 'trial');
    PsychImGui('TableSetupColumn', 'response');
    PsychImGui('TableSetupColumn', 'rt');
    PsychImGui('TableHeadersRow');
    for k = 1:numel(rt)
        PsychImGui('TableNextRow');
        PsychImGui('TableNextColumn'); PsychImGui('Text', sprintf('%d', k));
        PsychImGui('TableNextColumn'); PsychImGui('Text', resp{k});
        PsychImGui('TableNextColumn'); PsychImGui('Text', sprintf('%.3f', rt(k)));
    end
    PsychImGui('EndTable');
end
```

Call `EndTable` only when `BeginTable` returned true. `TableNextRow`,
`TableSetColumnIndex`, `TableHeader`, and `TableSetBgColor` raise
`psychimgui:Usage` outside a table or before the row or cell they need, and
`BeginTable` raises `psychimgui:Range` for a column count outside 1 to 511.
Section 14.10 says why the binding checks this itself.

### 5.3 Helper M-files

| File | Purpose |
|---|---|
| `m/PsychImGui.m` | Help text only. The MEX shadows it once built. Generated. |
| `m/PsychImGuiOpen.m` | `ig = PsychImGuiOpen(win [, opts])`. Checks that 3D graphics are on, runs `Init` inside one OpenGL region, starts the keyboard queue, and returns the handle struct the other three take. Fields: `win`, `rect`, `kq`, `opened`, `opts`, `in`, `ctx` (the handle `Init` returned), `stereo` (from `Screen('GetWindowInfo').StereoMode`, or `opts.stereo`). |
| `m/PsychImGuiFrame.m` | `ig = PsychImGuiFrame('Begin', ig)` and `PsychImGuiFrame('End', ig)`. Poll, `BeginOpenGL`, `SetContext`, `NewFrame`; then `Render`, `EndOpenGL`. With `ig.stereo`, `End` renders eye 0 and submits eye 1 with `RenderAgain`, each in its own region after `SelectStereoDrawBuffer`. The older `('Begin', win, kq)` form still works. |
| `m/PsychImGuiClose.m` | `PsychImGuiClose(ig)`. `Shutdown` of the handle's context inside one OpenGL region of its window, then stops the queue. Other windows' contexts stay open. Safe to call twice and safe after the window has closed, so it suits an `onCleanup`. |
| `m/PsychImGuiGL.m` | `PsychImGuiGL(ig, 'Subcommand', ...)`. One subcommand inside the OpenGL region, for calls such as `AddFontFromFileTTF` outside a frame, after `SetContext` for a handle from `PsychImGuiOpen`. Calls straight through when a frame already opened the region. |
| `m/PsychImGuiSetup.m` | Puts `dist/<arch>` ahead of `m/` on the path. `('arch')`, `('distdir')`, and `('nocheck')` for the parts of that. |
| `m/PsychImGuiInput.m` | `Start`, `Poll`, `Stop`, `Empty`. Wraps `KbQueueCreate`, `KbQueueStart`, `KbEventGet`, `GetMouse`, `GetMouseWheel`, `GetSecs`. Returns the input struct of section 6.1. |
| `m/PsychImGuiKeymap.m` | Builds the 256-entry PTB keycode to `ImGuiKey` table. |
| `m/PsychImGuiOp.m` | Generated struct of opcodes for the fast path. A namespace is a nested struct: `op.ImPlot.BeginPlot`, `op.DrawList.AddLine`. |
| `m/PsychImGuiImage.m` | `tex = PsychImGuiImage(ig, ptbTexture [, filter])`. Describes a Psychtoolbox texture for `Image` and `ImageButton`. Section 5.7. |
| `m/PsychImGuiDemo.m` | Demo: PTB window with a Gabor patch, a control panel with sliders and a file dialog button, an ImPlot panel, an ImPlot3D panel, a panel with a table and an `Image` of a PTB texture, a draw list overlay, and `ShowDemoWindow`. `PsychImGuiDemo(n, opts)` takes `opts.rect`, `opts.capture`, and `opts.animate`; the panels follow the window size. |
| `m/PsychImGuiStereoDemo.m` | Stereo demo: a disc with a disparity from a slider in each eye, and the control panel in both eyes. Mode 4 with two displays, mode 8 with one; `PsychImGuiStereoDemo(10)` for mode 10. |
| `tools/CaptureReadmeScreenshot.m` | Runs the demo at 1280x720 and writes the README screenshot, `docs/images/psychimgui-demo.png`. |

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
| ImPlot3D (`brenocq/implot3d`) | `cimgui/cimplot3d` | Medium. Eye or hand trajectories in 3D. | Phase 3, implemented |
| ImGuiFileDialog (`aiekick/ImGuiFileDialog`) | none, C++ API | Medium. File chooser for stimulus or data files. Eight subcommands, hand-written. | Phase 3, implemented |
| ImAnim (`soufianekhiat/ImAnim`, MIT, 2025) | none. C-style `iam_*` API of about 200 functions with structs, plus one fluent C++ class for motion paths. Parseable with libclang, not with pycparser. | Medium. Tweens, springs, easing presets, oscillators, noise channels, motion paths, and keyframe clips with save and load. Useful for smooth GUI transitions and for previewing a stimulus time course; the math parts duplicate what MATLAB does natively. Keyed by `ImGuiID` and driven by `io.DeltaTime`, so it fits the frame model without extra plumbing. | Not bound in phase 3; section 14.11 says why |
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

ImPlot3D lifecycle and allowlist (phase 3): `Init` calls
`ImPlot3D::CreateContext()` when compiled in and `opts.implot3d` is not
false, and `Shutdown` destroys it with the other two. The `[ImPlot3D]`
allowlist section:

| Group | Subcommands (`ImPlot3D.` prefix omitted) |
|---|---|
| Plot frame | BeginPlot, EndPlot |
| Setup | SetupAxis, SetupAxes, SetupAxisLimits, SetupAxesLimits, SetupAxisTicks (values form), SetupBoxRotation (elevation and azimuth form), SetupBoxScale, SetupLegend |
| Items | PlotLine, PlotScatter, PlotTriangle, PlotQuad, PlotSurface, PlotMesh, PlotText |
| Queries | PlotToPixels (x, y, z form), GetPlotRectPos, GetPlotRectSize |
| Colormaps | PushColormap (by name or index), PopColormap, GetColormapCount, GetColormapName, SampleColormap |
| Style | StyleColorsAuto, StyleColorsDark, StyleColorsLight, StyleColorsClassic, PushStyleColor, PopStyleColor, PushStyleVar (float and Vec2 forms), PopStyleVar |
| Diagnostics | ShowDemoWindow, ShowMetricsWindow |

```
open = PsychImGui('ImPlot3D.BeginPlot', titleId [, size=[-1 0]] [, flags=0])
PsychImGui('ImPlot3D.PlotLine', labelId, xs, ys, zs [, spec...])
PsychImGui('ImPlot3D.PlotSurface', labelId, X, Y, Z [, scaleMin=0.0] [, scaleMax=0.0] [, spec...])
PsychImGui('ImPlot3D.PlotMesh', labelId, xs, ys, zs, faces [, spec...])
pix = PsychImGui('ImPlot3D.PlotToPixels', x, y, z)
```

`PlotSurface` reads the grid size from the shape of `X`: rows are ImPlot3D's
`x_count`, because the first dimension of a column major matrix varies
fastest. `PlotMesh` takes `faces` as an Mx3 matrix of 1-based vertex indices,
the `Faces` of `patch`; section 14.11.

ImGuiFileDialog subcommands (phase 3, hand-written):

| Subcommand | Signature |
|---|---|
| FileDialog.Open | `PsychImGui('FileDialog.Open', key, title, filters [, path='.'] [, fileName=''] [, maxSelection=1] [, flags=0])` |
| FileDialog.Display | `[done, open] = PsychImGui('FileDialog.Display', key [, minSize=[0 0]] [, maxSize=[FLT_MAX FLT_MAX]] [, windowFlags=ImGuiWindowFlags_NoCollapse])` |
| FileDialog.IsOk | `ok = PsychImGui('FileDialog.IsOk')` |
| FileDialog.GetFilePathName | `path = PsychImGui('FileDialog.GetFilePathName')` |
| FileDialog.GetSelection | `paths = PsychImGui('FileDialog.GetSelection')`, a 1xN cellstr |
| FileDialog.GetCurrentPath | `path = PsychImGui('FileDialog.GetCurrentPath')` |
| FileDialog.IsOpened | `open = PsychImGui('FileDialog.IsOpened' [, key])` |
| FileDialog.Close | `PsychImGui('FileDialog.Close')` |

An empty `filters` makes a directory chooser. `flags` takes the
`ImGuiFileDialogFlags_` names, which the generator reads from
`ImGuiFileDialog.h` into the enum table. `Display` needs an open frame. Each
context owns one dialog object, created by the first `Open`.

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
| `psychimgui:InvalidHandle` | A draw list handle is not live: it comes from an earlier frame, from before `Render` or `EndFrame`, from another context, or from before a `Shutdown`, or it was never issued. Section 5.6. Also a context handle that was never issued or is shut down, for `SetContext`. |
| `psychimgui:Context` | The current GL context is not the one of the current PsychImGui context's window (rule R9), or `Init` found all eight contexts in use. |
| `psychimgui:Texture` | A texture is not one the OpenGL backends can sample: not `GL_TEXTURE_2D`, or not a valid texture name. Section 5.7. |

### 5.6 Draw lists

`GetWindowDrawList`, `GetBackgroundDrawList`, and `GetForegroundDrawList`
return a handle, a double. The `DrawList.` subcommands take it as their first
argument:

| Subcommand | Signature |
|---|---|
| DrawList.AddLine | `PsychImGui('DrawList.AddLine', h, p1, p2, col [, thickness=1])` |
| DrawList.AddRect | `PsychImGui('DrawList.AddRect', h, pMin, pMax, col [, rounding=0] [, thickness=1] [, flags=0])` |
| DrawList.AddRectFilled | `PsychImGui('DrawList.AddRectFilled', h, pMin, pMax, col [, rounding=0] [, flags=0])` |
| DrawList.AddCircle | `PsychImGui('DrawList.AddCircle', h, center, radius, col [, numSegments=0] [, thickness=1])` |
| DrawList.AddCircleFilled | `PsychImGui('DrawList.AddCircleFilled', h, center, radius, col [, numSegments=0])` |
| DrawList.AddTriangle | `PsychImGui('DrawList.AddTriangle', h, p1, p2, p3, col [, thickness=1])` |
| DrawList.AddTriangleFilled | `PsychImGui('DrawList.AddTriangleFilled', h, p1, p2, p3, col)` |
| DrawList.AddText | `PsychImGui('DrawList.AddText', h, pos, col, text)` |
| DrawList.AddPolyline | `PsychImGui('DrawList.AddPolyline', h, points, col, thickness [, flags=0])` |
| DrawList.AddConvexPolyFilled | `PsychImGui('DrawList.AddConvexPolyFilled', h, points, col)` |
| DrawList.PushClipRect | `PsychImGui('DrawList.PushClipRect', h, clipRectMin, clipRectMax [, intersectWithCurrentClipRect=false])` |
| DrawList.PopClipRect | `PsychImGui('DrawList.PopClipRect', h)` |

Points are 1x2 `[x y]` in window pixels, top left origin. A point list is an
Nx2 double. Colors follow the rule of section 7.3: 1x4 `[r g b a]` in 0 to 1,
or a packed scalar. `flags` takes `ImDrawFlags_` names.

Handle rules:

- A handle is valid only between `NewFrame` and `Render`, or `EndFrame`, of
  the frame that returned it. Get it again every frame. Any other handle
  raises `psychimgui:InvalidHandle`; the MEX never follows a stale pointer.
- The handle encodes a generation and a slot in a per-frame table of draw
  list pointers: `generation * 256 + slot`. The generation moves on at every
  `NewFrame`, `Render`, `EndFrame`, `Init`, and `Shutdown` and is never
  reset, so a handle from an earlier frame or an earlier context cannot match
  again, even when Dear ImGui reuses the pointer. The same draw list gives the
  same handle within a frame.
- One frame holds 256 distinct draw lists. A 257th raises `psychimgui:Range`.
- The getters raise `psychimgui:Usage` outside a frame, because Dear ImGui
  would dereference a null window there.
- `DrawList.PopClipRect` pops only what `DrawList.PushClipRect` pushed on the
  same draw list in the same frame, and raises `psychimgui:Usage` otherwise.
  A push left open at the end of the frame is harmless; Dear ImGui resets the
  stack.

```matlab
fg = PsychImGui('GetForegroundDrawList');
PsychImGui('DrawList.AddRect', fg, [100 100], [356 356], [1 0.85 0.2 1], 6, 2);
PsychImGui('DrawList.AddPolyline', fg, [x(:) y(:)], [0 1 0 1], 2);
```

### 5.7 Images

| Subcommand | Signature | Notes |
|---|---|---|
| Image | `PsychImGui('Image', tex, size [, uv0=[0 0]] [, uv1=[1 1]] [, bgCol=[0 0 0 0]] [, tintCol=[1 1 1 1]])` | Dear ImGui's `ImageWithBg`. `Image` with no colors is Dear ImGui's `Image`. |
| ImageButton | `pressed = PsychImGui('ImageButton', strId, tex, size [, uv0=[0 0]] [, uv1=[1 1]] [, bgCol=[0 0 0 0]] [, tintCol=[1 1 1 1]])` | |
| SetTextureFilter | `PsychImGui('SetTextureFilter', glId [, mode='linear'])` | Needs the GL context. Sets the texture's own minification and magnification filter. A no-op with the `none` renderer. |

`tex` is the struct from `PsychImGuiImage`, or an OpenGL texture name for a
`GL_TEXTURE_2D` texture stored top row first. `uv0` and `uv1` select a part of
the image, in image coordinates from 0 to 1, top left origin, whatever the
texture's storage order. Call `Image` and `ImageButton` between `NewFrame` and
`Render`; outside a frame they raise `psychimgui:Usage`.

The texture must be `GL_TEXTURE_2D`. `imgui_impl_opengl3` and
`imgui_impl_opengl2` bind every texture to `GL_TEXTURE_2D`, and the OpenGL 3
shader samples a `sampler2D`. Psychtoolbox makes `GL_TEXTURE_RECTANGLE`
textures by default; binding one of those names to `GL_TEXTURE_2D` fails with
`GL_INVALID_OPERATION`, which `Render` would report as `psychimgui:GLError`.
So the binding refuses such a texture up front with `psychimgui:Texture`, and
the script creates the texture with `specialFlags` 1:

```matlab
ptbTex = Screen('MakeTexture', win, img, [], 1);   % GL_TEXTURE_2D
tex = PsychImGuiImage(ig, ptbTex);                  % once, after MakeTexture
...
PsychImGui('Image', tex, tex.size);                 % every frame
```

`Screen('OpenOffscreenWindow', win, color, rect, [], 1)` gives a
`GL_TEXTURE_2D` offscreen window, which works the same way.

`PsychImGuiImage` reads the texture name and target with
`Screen('GetOpenGLTexture', win, ptbTexture)` and returns a struct with the
fields `glId`, `glTarget`, `size`, `uvMap`, `orientation`, `filter`, and
`ptbTexture`. The MEX does not call `Screen` (rule R6), so it takes this
struct instead of the PTB texture handle.

Psychtoolbox stores a texture made from a MATLAB matrix transposed: texture
`u` runs down the image and `v` across it. It stores an offscreen window
bottom row first. `PsychImGuiImage` finds out which, by asking
`Screen('GetOpenGLTexture')` to map the top left image position, and records
the answer as `uvMap = [u0 v0 dudx dvdx dudy dvdy]`, an affine map from image
coordinates to texture coordinates. `Image` maps the four corners of
`[uv0, uv1]` through it. When the map keeps `u` on `x`, as for an offscreen
window, the corners go to Dear ImGui's own `ImageWithBg` or `ImageButton`.
When it swaps the axes, which a `uv0`, `uv1` pair cannot express, Dear ImGui
still lays out and draws the item, with a transparent tint so it skips its own
image quad, and the binding adds the image as a quad with one texture
coordinate per corner (`ImDrawList::AddImageQuad`). Layout, hover, click, and
the button frame stay Dear ImGui's.

`filter` is `'linear'` or `'nearest'`. `Image` applies it per draw through
Dear ImGui's sampler callbacks (`ImGuiPlatformIO::DrawCallback_SetSamplerNearest`
and `DrawCallback_SetSamplerLinear`), because the OpenGL 3 backend binds its
own linear sampler object on GL 3.3 and later, which overrides the texture's
filter. `PsychImGuiImage` also sets the filter on the texture once, through
`SetTextureFilter`: Psychtoolbox leaves a new texture at the OpenGL default
minification filter, `GL_NEAREST_MIPMAP_LINEAR`, with one mipmap level, which
makes the texture incomplete, and a conforming driver samples an incomplete
texture as black.

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
| `ImU32` named `col`, `color`, or `col_*` (`TableSetBgColor`, the `DrawList.` subcommands) | 1x4 double in 0 to 1, or a double scalar packed ABGR | 1x4 double |
| `const ImVec2* points` with `int num_points` | Nx2 double `[x y]`; the count argument is removed. Up to 128 points convert on the stack. | none |
| `ImDrawList* self` (the object of an `ImDrawList` method) | draw list handle, section 5.6 | |
| `ImDrawList*` return value | | draw list handle, section 5.6 |
| `const char* fmt, ...` | one char argument. The handler calls the function with `"%s", str`. | none |
| `const char* const items[]` with `int items_count` | cellstr; the count argument is removed | none |
| `char* buf, size_t buf_size` (InputText) | see section 7.5 | see section 7.5 |
| `bool* p_open` | optional double or logical | extra output when supplied |
| `ImGuiInputTextCallback`, `void* user_data`, `ImDrawList*` other than the two rows above, `ImFont*`, `ImGuiViewport*`, `ImGuiStorage*`, `ImGuiPayload*`, `ImGuiListClipper*` | not supported. The generator refuses the entry, or passes the default when the argument has one. | |

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

A table of eight `State` structs in `src/core/psychimgui_core.cpp`, one per
context, and a pointer to the current one (phase 3; section 14.11). Each
holds:

| Member | Content |
|---|---|
| `ctx` | `ImGuiContext*`, plus the ImPlot and ImPlot3D contexts |
| `serial`, `win`, `glctx` | the handle, the PTB window, the GL context `Init` ran in |
| `renderer` | `OpenGL3`, `OpenGL2`, or `None` |
| `keymap[257]` | `ImGuiKey` per PTB keycode, 1-based |
| `modState` | held modifier bitset |
| `buttonState` | previous frame button bits |
| `lastTime` | previous `in.time` |
| `fonts[16]` | `ImFont*` table |
| `stats` | fixed arrays, section 9; the per-subcommand rows live in `psychimgui.cpp`, one per context |
| `gpu` | the timestamp query ring of section 9.2 |
| `dialog` | the ImGuiFileDialog object, created by the first `FileDialog.Open` |
| `deferredError` | flag, id, message buffer of 512 bytes; one for the process |

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
- Phase 3, several contexts: `Init` makes a context, makes it current, and
  records the current GL context handle; the MEX locks while any context
  lives. `Shutdown` deletes the GL objects only when the recorded GL context
  is current, and unlocks when no context is left. `atExit` shuts down every
  context and stops the Tracy profiler. Section 14.11.

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
time is read two frames later to avoid a stall. Implemented in phase 3 by
`src/core/gpu_timer.cpp`; section 14.11.

### 9.3 Tracy

CMake option `PSYCHIMGUI_TRACY` (default OFF) compiles `TracyClient.cpp` into
the MEX and adds `ZoneScopedN` in dispatch, `NewFrame`, `Render`, and the
InputText conversion, plus `FrameMark` at the end of `Render`. Capture with
`tracy-capture`, export with `tracy-csvexport` for text analysis. Phase 3
implements this with a GPU zone around each submission; section 14.11 lists
what differs.

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
    gen_dispatch_implot3d.cpp  generated, committed (phase 3)
    filedialog.cpp        the FileDialog subcommands (phase 3)
    igfd_psych.h, igfd_config_psych.h  ImGuiFileDialog configuration (phase 3)
    plotdata_marshal.h, implot3d_marshal.h  plot data and ImPlot3D rules (phase 3)
    core/gpu_timer.cpp    GL_TIMESTAMP queries and the Tracy GPU zone (phase 3)
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
    cimplot3d/            plain clone (contains implot3d/ submodule), phase 3
    ImGuiFileDialog/      plain clone, phase 3
    tracy/                plain clone, optional
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
on Windows through the official GNU Octave Windows zip. CI runs the
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
- `test_tables.m`: a table call sequence over several frames, and the
  checks that refuse a table call outside a table, row, or cell.
- `test_drawlist.m`: handles, every `DrawList.` subcommand, point lists and
  colors, the clip stack count, and stale handles after `Render`, `EndFrame`,
  the next `NewFrame`, and `Shutdown`.
- `test_image.m`: `Image`, `ImageButton`, and `SetTextureFilter` argument
  rules, and `PsychImGuiImage` against the recording `Screen` stub.
- `test_contexts.m` (phase 3): two contexts, switching, interleaved frames,
  per-context Stats, a draw list handle that does not cross contexts, stale
  context handles, the MEX lock, and the limit of eight.
- `test_stereo.m` (phase 3): when `RenderAgain` is legal.
- `test_filedialog.m` (phase 3): the `FileDialog.` argument rules, the open,
  display, and close cycle, and a path outside ASCII.
- `test_helpers_p3.m` (phase 3): the helpers with two windows and with a
  stereo window, against the recording `Screen` stub.

### 11.2 With PTB and a GPU

`tests/gl/test_gl_render.m` opens a 640x480 PTB window, draws a filled window
with a known background color, calls `Screen('GetImage')` after `Flip`, and
checks the mean color inside the window rectangle within a tolerance. It also
checks that `Render` raises `psychimgui:GLError` when a GL error is injected
through a debug subcommand compiled only in test builds.

`tests/gl/test_gl_phase2.m` draws three images, a table with colored cells,
and draw list primitives at known positions in one frame and checks the pixel
colors: each quadrant of a test pattern in a transposed texture and in an
upright offscreen window, a sharp quadrant edge with `'nearest'` and a blended
one with `'linear'`, both cell backgrounds, a clip rectangle, and the
foreground and background draw lists. `test_gl_phase2('opengl2')` runs it on
the fixed function backend.

Phase 3 adds three. `tests/gl/test_gl_contexts.m` opens two windows with a
context each, draws a red and a blue panel, reads both back, checks
`psychimgui:Context` for `NewFrame` and `Render` with the other window's
context current, shuts one context down from the other window's context, and
reads the GPU timer. `tests/gl/test_gl_stereo.m` opens stereo modes 4 and 8,
which work on one display, draws a panel with `PsychImGuiFrame`, and reads
each eye with `Screen('SelectStereoDrawBuffer')` and
`Screen('GetImage', win, [], 'drawBuffer')`; a control frame that skips
`RenderAgain` leaves eye 1 empty. `tests/gl/test_gl_implot3d.m` draws a red
helix, a surface, and a blue mesh triangle, counts their pixels, and checks
that `ImPlot3D.PlotToPixels` lands on the helix. All GL tests skip when
`Screen` is missing or does not load.

Every script that opens a PTB window goes through one helper,
`tests/gl/ptb_test_window.m`, which sets `Screen('Preference',
'SkipSyncTests', 2)` and `Screen('Preference', 'VisualDebugLevel', 0)` before
`PsychImaging('OpenWindow')`, so a test run pays for neither the display
timing calibration nor the startup splash screen.

### 11.3 Interactive

`PsychImGuiDemo.m`: a Gabor patch whose contrast, spatial frequency, and
orientation come from sliders; a text field; `ShowDemoWindow`; a table of the
slider values; an `Image` of a PTB texture; a draw list overlay that marks the
patch outline, center, and rotation angle. `perf_frame.m`:
200 sliders per frame for 600 frames, prints `Stats` and a frame time
histogram.

## 12. Risks, alternatives considered, open questions

### 12.1 Risks

| Risk | Mitigation |
|---|---|
| `IM_ASSERT` aborts the MATLAB process | Redirected to a deferred error, section 8.3. Error recovery enabled. |
| PTB imaging pipeline with float FBOs or sRGB blending changes GUI colors | Document. Offer `opts.srgb` to gamma-adjust style colors. |
| Stereo modes or panel fitter change the client rectangle | `display` is re-read every frame. Per-eye GUI rendering came with `RenderAgain` in phase 3. |
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
| Support for macOS? | Apple silicon only, through CI on `macos-latest`. The GL 2.1 compatibility context is handled by dispatching to the fixed function `imgui_impl_opengl2` backend, not by a GLSL version alone. Not CI-blocking until the first green run. |

## 13. Phasing

| Phase | Content |
|---|---|
| 1 | Lifecycle, input, generator, allowlist of section 5.2, `Stats`, `renderer='none'` tests, demo. |
| 1.5 | ImPlot: context lifecycle, section 7.6 rules, allowlist of section 5.4, generated tests, a demo panel with a live trace and a heat map. |
| 2 | Tables (`BeginTable`, `TableNextRow`, `TableNextColumn`, `TableSetupColumn`, `TableHeadersRow`), `ImDrawList` through an opaque handle for the window and background draw lists (`AddLine`, `AddRect`, `AddCircle`, `AddText`), `PsychImGui('Image', ptbTexture, size)` by reading the GL texture id with `Screen('GetOpenGLTexture')`. Implemented; section 14.10 lists what differs. |
| 3 | Tracy GPU zones, per-eye rendering for stereo modes, multiple contexts for multiple PTB windows, ImPlot3D through `cimplot3d`, ImGuiFileDialog hand-written. Implemented; section 14.11 lists what differs. |

## 14. Deviations from version 0.1

This section records every place where the implementation differs from the
specification above, and why. Section 13 phases 1, 1.5, 2, and 3 are
implemented.

### 14.1 Dependencies

| Deviation | Reason |
|---|---|
| `third_party/cimgui` and `third_party/cimplot` are git submodules, pinned at the commits in `third_party/PINS.md`. They started as plain clones while phase 1 was written and were registered as submodules at the same paths and commits on 2026-09-22. | The repository did not exist while phase 1 was written. |
| The cimplot pin is not from the same day as the cimgui pin. | cimgui is pinned at 2026-09-14 (Dear ImGui 1.92.9b) and cimplot at 2026-08-13 (ImPlot 1.1 WIP), which is the newest cimplot commit. ImPlot 1.1 compiles and links against Dear ImGui 1.92.9b unchanged, and the whole ImPlot test suite passes. |
| `third_party/tracy` is not cloned. Phase 3 clones it for profiling builds, 14.11. | Tracy is optional. See 14.5. |

### 14.2 Build

| Deviation | Reason |
|---|---|
| `IMGUI_USER_CONFIG` reaches the MEX through `src/imgui_psych.h` instead of a `-D` flag. | MATLAB's `mex` strips the quotes out of `-DIMGUI_USER_CONFIG="imconfig_psych.h"` on Windows, and the compiler then fails on an empty `#include`. The header defines the macro and then includes `imgui.h`; every MEX translation unit includes it first. The CMake library keeps the compile definition, so both halves share one configuration. |
| Octave on Windows configures CMake with the "MSYS Makefiles" generator and explicit tool paths. | Section 10.2 suggests "MinGW Makefiles". That generator refuses to run while `sh.exe` is on PATH, and Git for Windows always puts one there. Octave's toolchain lives in `mingw64/bin` and its `make` in `usr/bin`, which Octave does not put on PATH, so `build.m` names the compiler, `ar`, `ranlib`, and `make` by absolute path. `MEX_CMAKE_GENERATOR` still overrides the generator. |
| Octave gets C++17 through the `CXXFLAGS` environment variable, not a `CXXFLAGS=...` argument to `mex`. | Octave's `mex` rejects a `NAME=value` argument; `mkoctfile` reads its flags from the environment. `build.m` sets and restores the variable around the call. |
| `tools/smoke_gl.cpp` and the `PSYCHIMGUI_SMOKE_GL` CMake option are new. | Psychtoolbox was not installed when the binding was written, so the OpenGL path needed a proof that does not depend on it. `smoke_gl` creates a hidden window with a legacy compatibility context, the same kind PTB creates, and runs the core through Init, three frames, and Shutdown. `smoke_gl none` runs the headless path. |
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
| Four helper M-files own the `Screen('BeginOpenGL')` and `Screen('EndOpenGL')` pairs: `PsychImGuiOpen`, `PsychImGuiFrame`, `PsychImGuiClose`, and `PsychImGuiGL`. | Section 5.3 listed only `PsychImGuiFrame`, so `Init`, `Shutdown`, and a one-off call such as `AddFontFromFileTTF` each left the script to write the pair itself. Every such pair is a chance to leave Psychtoolbox in 3D mode after an error, which makes the next `Screen` call abort with a message about the wrong thing. The helpers close the region through an `onCleanup` or a `catch`, and `PsychImGuiGL` reads `Screen('GetOpenGLDrawMode')` so it nests safely inside a frame. `PsychImGuiOpen` also fails early, with `psychimgui:No3DGraphics`, when `Screen('Preference', 'Enable3DGraphics')` is 0, which is what a missing `InitializeMatlabOpenGL` looks like. Section 4.2 now shows this form first and the raw subcommands second. The older `PsychImGuiFrame('Begin', win, kq)` still works. |
| `tests/test_helpers.m` and `tests/tf_screen.m` test the helpers without Psychtoolbox. | The wrapping logic is what the helpers have to get right, and it needs no GPU. `tf_screen` writes a recording `Screen` stub, plus `GetMouse`, `GetMouseWheel`, and `GetSecs`, into a temporary folder at the front of the path, so `run_tests` can check the exact sequence of OpenGL region calls, including the ones after an error. The stubs live in a temporary folder rather than in the repository, so no stray path entry can shadow the real `Screen` outside the test. |
| `tests/gl/test_gl_demo_gabor.m` and a first frame check inside the demo. | Section 11.3 specifies the demo but nothing measured its output, and a procedural Gabor fails silently. `CreateProceduralGabor` scales the contrast by `1/(sqrt(2*pi)*sc)` unless `disableNorm` is 1, about 1/125 at `sc = 50`, so the demo's contrast of 0.6 drew an amplitude of 0.005 and the patch looked like a plain gray square with no error anywhere. The demo now calls `PsychDefaultSetup(2)` before the window opens, which is the standard Psychtoolbox opening line and switches every later `PsychImaging('OpenWindow')` to the normalized 0 to 1 color range, passes `disableNorm = 1` and `contrastPreMultiplicator = 0.5` so the slider is Michelson contrast, and measures its own first frame. Measured: pixel standard deviation 0.0021 before the fix, 0.0734 after, and a central Michelson contrast of 0.592 for a slider at 0.6. |
| `tf_screen` never calls `rehash`, and `run_tests`, not `test_helpers`, takes the stub folder off the path. | Octave 10.1 on Linux segfaulted during `test_helpers` in CI (`gnuoctave/octave:10.1.0`, Ubuntu 24.04, gcc 13.3), after all 51 assertions had run and before the summary line printed, which places it in the teardown. The same image passed the same commit 58 times locally, so it did not reproduce here, but a backtrace from the sibling PsychLVGL project in the same image identifies the mechanism: after `library ... not reloaded due to existing references`, the stack holds more than 35000 alternating frames of `octave::out_of_date_check` and `octave::bp_table::remove_all_breakpoints_from_function`, because `out_of_date_check` asks the breakpoint table to drop the breakpoints of the function it is about to reload and that lookup re-enters `out_of_date_check`, until the stack is exhausted. A load path change, or `rehash`, while a locked MEX is loaded starts the cycle; Octave 6.4 has no such cycle and MATLAB is unaffected. The fix removes the trigger, not the Octave bug: this test no longer mutates the load path or calls `rehash` while the MEX is loaded, `run_tests` puts the stub directory on the path before the first call loads the MEX, and `PsychImGuiSetup` only calls `addpath` when a directory is missing from the path, because `PsychImGuiOpen` runs it on every open and `addpath` of a directory that is already present still counts as a path change. What went is `rehash`, an `rmpath` in the middle of a run, and two `onCleanup` objects destroyed at function exit. `rehash` was never needed, because the stub files are written before their folder joins the path, and both engines pick up a new path entry on their own; it is also the only call in the suite that rebuilds the interpreter's function cache. The single remaining `rmpath` now runs in `run_tests`, after the last test and the last `Shutdown`. |
| The renderer is chosen from the context, and a second Dear ImGui backend is compiled in. | Sections 5.1 and 8.2 name one backend, `imgui_impl_opengl3`, and `opts.renderer` of `'opengl3'` or `'none'`. That backend cannot drive the OpenGL 2.1 context Psychtoolbox creates on macOS: it calls `glGenVertexArrays`, `glBindVertexArray` and `glDeleteVertexArrays` in `RenderDrawData`, guarded only by the compile time `IMGUI_IMPL_OPENGL_USE_VERTEX_ARRAY`, which is on for every desktop build, and a 2.1 profile has no core vertex array objects. `#version 120` fixes the shaders and not this. So `imgui_impl_opengl2`, Dear ImGui's own fixed function backend, is compiled in too, and `Init` reads `GL_VERSION` and dispatches: below 3.0 the OpenGL 2 backend, otherwise the OpenGL 3 one. `opts.renderer` gained `'auto'`, which is the new default, and `'opengl2'`. `PsychImGui('Version')` reports the backend that is running and the GLSL version it chose. The GLSL default is now taken from the context as well: `#version 120` below GL 3.0, `#version 150` on macOS above it, because Apple's core profiles support 1.50 and 4.10 and never 1.30, and `#version 130` elsewhere. |
| macOS is a CI target on Apple silicon only, and its jobs do not fail the run yet. | Nobody on the team has a Mac, so `macos-latest` is the only test bed and the first CI run is the first real test. `build.m` names the OpenGL framework, `PsychImGuiSetup` maps Octave's `aarch64-apple-darwin` arch string onto `maca64`, `tools/smoke_gl.cpp` grew a CGL path that makes a legacy 2.1 context and renders into a framebuffer object because macOS has no windowless context, and `GL_SILENCE_DEPRECATION` keeps the build log readable. The first CI run (2026-09-22) settled part of it: `smoke_gl` got a CGL context on the runner (`GL_VERSION 2.1 APPLE-23.1.1`, Apple Software Renderer, GLSL 1.20; the runner offers no accelerated pixel format), exercised `imgui_impl_opengl2`, and passed, so that job is blocking now. The MATLAB build linked with `LDFLAGS=$LDFLAGS -framework OpenGL` and failed on undefined `_mexFunctionAdapter`, `_mexCreateMexFunction`, and `_mexDestroyMexFunction`, the C++ MEX Data API exports, and warned that the static library targeted macOS 26.0 while `mex` links for 11.0; the framework now goes through `LINKLIBS=$LINKLIBS -framework OpenGL`, which leaves MATLAB's own `LDFLAGS` and export list alone, `mex -v` is on under CI so the link line is in the log, and CMake sets `CMAKE_OSX_DEPLOYMENT_TARGET` 11.0 on Apple. The Homebrew Octave build failed because `mkoctfile -p CXX` answers `clang++ -std=gnu++17` and `build.m` handed the whole string to CMake as the compiler path; it now splits the program from the flags. Round 2 (same day): the Homebrew Octave job passed and is blocking. The MATLAB job failed again, and its `mex -v` log named the cause: MATLAB's `clang++` configuration appends `LINKEXPORTCPP`, that is `-Wl,-U` for the three C++ MEX Data API entry points plus `-exported_symbols_list cppMexFunction.map`, for every C++ MEX file, on top of the classic `mexFunction.map`. The classic ld64 tolerated the undefined exports because of `-U`; the linker in Xcode 26 reports them as `<initial-undefines>`. `build.m` now passes `LINKEXPORTCPP=` on macOS, which clears that set for this classic `mexFunction` file. The MATLAB job stays `continue-on-error` until it passes. Intel Macs are not covered: the MATLAB floor is R2023b, the first native Apple silicon release. What was verified without a Mac: the OpenGL 2 backend itself, through `smoke_gl gl2` on Windows, which forces it on a 4.6 context and passes. What was not: CGL context creation, the Apple GL headers, the Homebrew Octave build, and the MATLAB macOS build. |
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
| `Stats.frame.renderGpuNs` is always 0. Superseded in phase 3, section 14.11. | Section 9.2 asks for a `GL_TIMESTAMP` query pair. The GL entry points for timer queries live in the backend's private loader (`imgui_impl_opengl3_loader.h`), and a second GL loader inside the MEX for one counter was not worth it in phase 1. Everything else in 9.2 is recorded: per-opcode `calls`, `totalNs`, and `maxNs`, and per-frame `newFrameNs`, `renderCpuNs`, `drawCalls`, and `vertices`. |
| `PSYCHIMGUI_TRACY` compiles the client but adds no zones. Superseded in phase 3, section 14.11. | The option sets `TRACY_ENABLE` and compiles `TracyClient.cpp` when `third_party/tracy` is present, but no `ZoneScopedN` or `FrameMark` call exists yet, and the clone is not there. Section 9.3 stays open. |

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
| `tools/smoke_gl.cpp` grew a GLX path. | 14.2 recorded it as Windows only. CI needs it on Linux, so the GLX branch now creates an override-redirect X window, waits for its MapNotify, and calls `glXCreateContext`, which is the legacy call Psychtoolbox uses. macOS came later; see the macOS row in 14.3. |

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

### 14.10 Phase 2

| Deviation | Reason |
|---|---|
| The `ImDrawList` methods are subcommands with a `DrawList.` prefix, such as `PsychImGui('DrawList.AddLine', h, ...)`. | Section 13 names them `AddLine`, `AddRect`, and so on. `ImGui::PushClipRect` and `ImDrawList::PushClipRect` are different functions with the same name, so without a prefix one of them could never be bound. The prefix follows the namespace rule of section 5.4, and `PsychImGuiOp` returns the opcodes as `op.DrawList.AddLine`. `PsychImGuiOp` now nests every dotted namespace the same way instead of special casing `ImPlot`. |
| The draw list methods and the three getters are generated, from a `[DrawList]` allowlist section, not hand-written. | Their `definitions.json` signatures fit once the generator knows four more types, which section 7.3 now lists: `ImDrawList* self` and an `ImDrawList*` return value as a handle, `ImU32` named `col`, `color`, or `col_*` as a color, and `const ImVec2*` with a `num_*` count as an Nx2 array. `text_end` of `AddText` keeps its `NULL` default through the allowlist's `-text_end`, and `text_begin` is called `text` on the MATLAB side. |
| The handlers of `[DrawList]` carry the prefix in their C++ symbols (`h_DrawList_AddLine`). | They live in `gen_dispatch.cpp` next to the `[ImGui]` handlers, and a later `ImGui::PushClipRect` binding would otherwise collide with `h_PushClipRect`. |
| Twelve table subcommands, not five, all generated. `TableSetupColumn` drops `user_data`. | The task list for phase 2 added `TableSetColumnIndex`, `TableHeader`, `TableGetColumnCount`, `TableGetColumnIndex`, `TableSetupScrollFreeze`, `TableSetBgColor`, and `EndTable`. Every signature fits section 7.3 as it is; none is hand-written. `user_data` is only read back through `TableGetSortSpecs`, which is not bound, so it keeps its default of 0. |
| The generator grew `CALL_HOOKS`: C++ statements that run just before or after the call of one generated handler. | Some invariants depend on Dear ImGui state, not on argument types, so no marshaling rule can express them. The hooks hold the checks in the next three rows, next to the rule they protect, and the generated handler stays one function. |
| `BeginTable` refuses a column count outside 1 to 511 with `psychimgui:Range`. `TableNextRow`, `TableHeader`, `TableSetBgColor`, and `TableSetColumnIndex` refuse to run outside a table, before the row or cell they need, with `columnN` out of range, or with target `ImGuiTableBgTarget_None`, with `psychimgui:Usage` or `psychimgui:Range`. | Dear ImGui guards these with an `IM_ASSERT` or with nothing, and then dereferences or indexes: `TableNextRow` reads `g.CurrentTable->IsLayoutLocked` with no null check, `TableHeader` indexes `Columns[-1]` before a cell, and `BeginTable` allocates with the bad count after its assert. Section 14.4 describes why a deferred assert turns such a guard into a crash. The generated test found one more that has no assert at all: `TableSetColumnIndex` before the first `TableNextRow` begins a cell in no row, and it crashed MATLAB with an access violation. The checks use public API only (`TableGetColumnCount` is 0 outside a table, `TableGetRowIndex` is -1 before the first row). One behavior changes against Dear ImGui: `TableSetColumnIndex` outside a table raises instead of returning false. `TableNextColumn` still returns false there, because Dear ImGui handles that case safely. |
| The draw list getters raise `psychimgui:Usage` outside a frame. | `ImGui::GetWindowDrawList` dereferences `g.CurrentWindow`, which is null between `Render` and `NewFrame`. |
| `DrawList.PopClipRect` raises `psychimgui:Usage` unless the same draw list has an open `DrawList.PushClipRect` from this frame. | `ImDrawList::PopClipRect` pops without a bounds check once `IM_ASSERT` returns, and a pop of Dear ImGui's own clip rectangle leaves the `End` that owns it to pop past the bottom of the stack. The binding counts its own pushes per draw list slot. |
| A draw list handle is a double, `generation * 256 + slot`, validated against a per-frame table in `src/core`, with the generation kept outside the state that `Init` and `Shutdown` clear. A frame holds 256 distinct draw lists. | The task asks that a stale handle raise `psychimgui:InvalidHandle` and never dereference a dead pointer. A pointer cast to a double cannot be checked; a slot plus a generation can, with one compare, and a double holds the value exactly for 2^45 frames. Keeping the generation across `Shutdown` stops a handle from before a restart from matching a new context that reuses the same pointers. The linear scan over the table beats hashing at a few dozen windows. |
| `Image` and `ImageButton` are hand-written, and take the struct from `m/PsychImGuiImage.m` or a GL texture name, not the PTB texture handle of section 13. | The MEX cannot call `Screen` (rule R6), so the PTB side, `PsychImGuiImage`, reads the name with `Screen('GetOpenGLTexture')`. The generator cannot bind `igImage` because `ImTextureRef` has no MATLAB rule, and one would not be enough: a PTB texture made from a matrix is stored transposed, and Dear ImGui's `uv0`, `uv1` pair cannot express a transpose. Section 5.7 describes the texture coordinate map and the quad that draws it. `Image` merges Dear ImGui's `Image` and `ImageWithBg`, because the two differ only in the two color arguments. |
| Only `GL_TEXTURE_2D` textures are accepted, and the script creates them with `Screen('MakeTexture', win, img, [], 1)`. Anything else raises `psychimgui:Texture`, from `PsychImGuiImage`, from `Image` and `ImageButton` for a struct whose `glTarget` is not 3553, and from `SetTextureFilter` when the name will not bind to `GL_TEXTURE_2D`. | Verified in the PTB source: `PsychGetTextureTarget` (`PsychTextureSupport.c`) picks `GL_TEXTURE_RECTANGLE_EXT` whenever the extension exists, and `SCREENMakeTexture.c` switches to `GL_TEXTURE_2D` only for `specialFlags` 1. Both Dear ImGui backends bind `GL_TEXTURE_2D` only. The alternatives were a per-frame copy of a rectangle texture into a 2D one through a framebuffer object, or a draw callback that swaps in a `sampler2DRect` shader. Both put GL code outside the unmodified backends, the second would work only with the OpenGL 3 backend, and both cost more than the one flag they save. `PsychImGuiImage` checks the target it reads from `Screen`; the MEX check catches a struct built by hand. |
| `PsychImGuiImage` detects the storage order by mapping image position (0, 0) with `Screen('GetOpenGLTexture', win, tex, 0, 0)`. | `PsychMapTexCoord` (`PsychTextureSupport.c`) returns `v` near 0 for a transposed texture (`textureOrientation` 0 or 1) and near 1 for one stored bottom row first (`textureOrientation` 2, offscreen windows and textures made with `textureOrientation` 1 or 2). PTB reports the orientation nowhere else. Orientations 3 and 4 come from the movie and video capture engines, which make rectangle textures, so they never reach this test. |
| `SetTextureFilter` is a new hand-written subcommand, and `PsychImGuiImage` calls it once per texture. The struct also carries a `filter` that `Image` applies to every draw through Dear ImGui's sampler callbacks. | Measured with `glGetTexParameteriv` after `Screen('MakeTexture', win, img, [], 1)`: `GL_TEXTURE_MIN_FILTER` is `0x2702` (`GL_NEAREST_MIPMAP_LINEAR`), `GL_GENERATE_MIPMAP` is 0, and mipmap level 1 has width 0, the same with `specialFlags` 9. PTB sets a filter only while it draws. By the OpenGL specification that texture is incomplete and samples as black. On the development machine (Intel Iris Xe, driver 32.0.101.7088) it sampled correctly anyway, with both backends and with minification, so the black image was not reproduced; the call is there for conforming drivers, macOS among them. It does not decide the filter the user sees on GL 3.3 and later: `imgui_impl_opengl3` binds its own linear sampler object there, which overrides the texture's filter. So `Image` wraps the draw in `DrawCallback_SetSamplerNearest` and `DrawCallback_SetSamplerLinear` when the struct asks for `'nearest'`. Measured in `test_gl_phase2` with a 4x magnification, one pixel left of a red to green quadrant edge: `'nearest'` gives [1.00 0.00 0.00] and `'linear'` gives [0.62 0.38 0.00], with both backends. |
| A transposed image ignores `style.ImageRounding` and the rounding `ImageButton` derives from `FrameRounding`. | `ImDrawList` has no rounded variant of `AddImageQuad`. Upright images go through Dear ImGui's own drawing and keep the rounding. |
| `src/imgui_marshal.h` is new. `Image`, `ImageButton`, and the draw list getters raise `psychimgui:Usage` outside a frame, which the core now tracks with `pig::frameOpen()`. | The color, point list, and handle rules need `imgui.h`; `marshal.h` stays free of it, as `implot_marshal.h` does for the ImPlot rules. |
| `tests/test_tables.m`, `tests/test_drawlist.m`, `tests/test_image.m`, and `tests/gl/test_gl_phase2.m` are new, and the `Screen` stub of `tests/tf_screen.m` answers `GetOpenGLTexture` and `Rect` for three stub textures. | The headless suite covers the argument rules, the handle lifetime, and `PsychImGuiImage`'s decisions; only the GL test can see a transposed or black image. `test_image` resets the stub's call record when it ends, because `test_helpers` reads that record from an empty start. |
| `tests/perf_dispatch.m` measures `DrawList.AddLine` too. | The draw list calls are the hot path of an overlay. Measured on the development machine, 200000 calls: MATLAB R2023a 2.17 us per call by name, 2.04 us by opcode, 0.42 us inside the MEX (`Stats`); Octave 10.1 8.86 us by name, 8.90 us by opcode, 0.65 us inside the MEX. The MEX side includes `ImDrawList::AddLine` itself and allocates nothing: the handle check is a table lookup, the points convert on the stack, and the color packs in place. `Button` measured 0.25 us inside the MEX in the same run, against 0.14 us in section 14.5, so this machine ran slower that day. |

Phase 2 results on the development machine (Windows 11, MATLAB R2023a,
Octave 10.1, Psychtoolbox 3.0.22): the headless suite passes 754 of 754
under MATLAB and under Octave; `test_gl_phase2` passes 29 of 29 with the
OpenGL 3 backend and with the OpenGL 2 backend; `test_gl_render` and
`test_gl_demo_gabor` still pass; `PsychImGuiDemo(120)` runs clean.

### 14.11 Phase 3

Several windows:

| Deviation | Reason |
|---|---|
| A context handle is a double serial number, never reused in the process, and `Init` knows a context by its `win` argument. `Init` for a window that already has a context raises `psychimgui:AlreadyInit`; `Init` for another window makes a second context. | Every single-window script keeps working: it ignores the output of `Init`, and its second `Init` for the same window still raises. A serial number cannot match a newer context the way a reused slot or pointer could, which is the draw list rule of 14.10 applied to contexts. |
| Eight contexts at most, in a fixed table, scanned linearly. | Section 8.1 has one static struct; eight of them cost no heap per context and cover an operator display plus a dual display stereo rig. A ninth `Init` raises `psychimgui:Context`. |
| `GetContext` and `Shutdown(ctx)` and `Shutdown('all')` are new. `Shutdown` with no argument shuts down the current context and leaves none current; `Shutdown` of a handle that is already shut down does nothing. | A script with two windows has to name the next context itself, and a guess would send its widgets to the wrong window. `Shutdown` stays safe to repeat, as section 5.1 asks, so cleanup code can run it without knowing what an error left behind. `run_tests` uses `'all'`, because a test with several windows can leave more than one context, and the MEX has to unlock before the test stub leaves the path (14.6). |
| Every GL subcommand compares the current platform GL context (`wglGetCurrentContext`, `glXGetCurrentContext`, `CGLGetCurrentContext`) with the one `Init` recorded, and raises `psychimgui:Context` on a mismatch. `NewFrame` is a GL subcommand now. | The task asked for the check at `Render`. `AddFontFromFileTTF`, `SetTextureFilter`, and `RenderAgain` touch the same objects, and `NewFrame` creates the OpenGL 3 backend's shader and font texture on the first frame, so a `NewFrame` in the wrong window would create them where the context's own window cannot see them. One behavior changes: with a real renderer, `NewFrame` outside `BeginOpenGL` now raises `psychimgui:NoGLContext`. Rule R1 already required the region. |
| `Shutdown` deletes the backend's GL objects only when the GL context `Init` recorded is current, not whenever any context is. | In another window's context the same object names belong to that window, so the old rule would have deleted the other window's font texture. Measured in `test_gl_contexts`: a `Shutdown` of window A's context inside window B's region warns `psychimgui:NoGLContext`, and window B draws correctly afterwards. |
| `SetContext` retires every draw list handle. Each context has its own row of Stats counters, and calls made with no context current count in a row of their own. | The draw list table of 14.10 is one per process; retiring it at a switch keeps a handle from one context from reaching another context's lists. |
| The glyph range buffer of `AddFontFromFileTTF` is one per font of each context. | It was one static buffer. Dear ImGui 1.92 reads glyph ranges when it bakes a glyph, long after the call, so a second font, or a second context, overwrote the ranges of the first. |
| The helper handle has two new fields, `ctx` and `stereo`, and every helper calls `SetContext` with `ctx` first. `PsychImGuiClose` shuts down its own context by handle. `PsychImGuiFrame('Begin')` with a closed handle raises `psychimgui:NotInit`, as it did in phase 1; `PsychImGuiGL` with a closed handle raises `psychimgui:InvalidHandle`. | A script with a handle per window then never switches contexts itself. The handle of an older script has no `ctx` field and uses the current context, as before. |

Stereo:

| Deviation | Reason |
|---|---|
| `RenderAgain` is the second submission, not a `Render` option. | The task offered either form. A separate subcommand keeps `Render`'s signature, and its opcode, unchanged, and makes the rule simple to check: legal from `Render` to the next `NewFrame` or `EndFrame`. |
| `PsychImGuiFrame('End')` of a stereo window leaves the region `Begin` opened, then enters it again once per eye. | `SelectStereoDrawBuffer` is a `Screen` call and cannot run inside the region, and the eye that was selected at `Begin` is whatever the script drew last. The cost is one more `BeginOpenGL` and `EndOpenGL` pair per stereo frame. |
| `test_gl_stereo` reads each eye with `Screen('GetImage', win, [], 'drawBuffer')` after `SelectStereoDrawBuffer`, not with `'backLeftBuffer'` and `'backRightBuffer'`. | `SCREENGetImage.c` accepts those two names only when the framebuffer is GL stereo or in modes 11 and 12. Measured in modes 4 and 8: `Screen` raises "Invalid or unknown 'bufferName'" and closes every window. `'drawBuffer'` reads the framebuffer object of the selected eye. A control frame that skips `RenderAgain` reads black in eye 1, so the check can fail. |
| `PsychImGuiStereoDemo` picks mode 4 with two or more displays and mode 8 with one; mode 10 is available by argument. | Mode 10 needs each display to be a separate Psychtoolbox screen, which a Windows desktop spanning two monitors is not by default. Mode 4 needs one window across both displays, which screen 0 gives on Windows. |

Profiling:

| Deviation | Reason |
|---|---|
| The GPU timer runs in every build, not only with Tracy, and fills `Stats.frame.renderGpuNs`. It reports the most recent submission whose result has arrived, at least one submission old, and never waits: a slot still in flight when the ring of eight comes round is skipped. `RenderAgain` is timed as well. | Section 9.2 asked for it and 14.5 recorded it as missing. The entry points come from `wglGetProcAddress`, `glXGetProcAddressARB`, or `dlsym`, per context, after a check for OpenGL 3.3 or `GL_ARB_timer_query`; without them timing is off and no entry point is called, which is the case for the OpenGL 2.1 context of macOS. `PsychImGui('Version').gpuTimer` reports it. |
| One Tracy CPU zone per dispatched call, from a table of source locations built once from the dispatch table, plus zones in `NewFrame`, `Render`, and `RenderAgain`. The InputText conversion has no zone of its own. | The per-call zone covers every subcommand without an allocation per call. A zone per conversion inside a call adds nothing a per-call zone does not show. The zone closes before the dispatch layer raises, because `mexErrMsgIdAndTxt` leaves by `longjmp` and would skip its destructor. |
| One Tracy GPU zone, "Render (GPU)", per submission, emitted through Tracy's C API with the timer's own queries. | Tracy's `TracyOpenGL.hpp` needs its GL entry points from a loader; the timer above has them already. The GPU context id comes from Tracy's own counter, so it cannot collide with another GPU context in the process. |
| `FrameMark` for the first context slot and `FrameMarkNamed` for the others. | Frames of a second window would otherwise cut into the timeline of the first. |
| The Tracy client is built with `TRACY_DELAYED_INIT`, `TRACY_MANUAL_LIFETIME`, and `TRACY_NO_CRASH_HANDLER`, starts on the first MEX call, and stops in `mexAtExit`. `build.m` turns it on with the environment variable `PSYCHIMGUI_TRACY=1` and stops with the clone command when `third_party/tracy` is missing; CMake stops with the same command. | A MEX file is loaded and unloaded inside a long-running host, so static constructors are the wrong time to start threads. MATLAB's JVM raises access violations on purpose and handles them; the sibling PsychNanoVG project found that Tracy's crash handler takes the first one for a crash and hangs MATLAB in `Screen('CloseAll')`. With the handler off, MATLAB exited normally after the capture below. |

Measured on the development machine (Windows 11, Intel Iris Xe, driver
32.0.101.7088, OpenGL 4.6, MATLAB R2023a): a Tracy 0.11.1 capture of
`PsychImGuiDemo(300)` at 640x480, read with a scratch program against
Tracy's server library because `tracy-csvexport` 0.11.1 exports CPU zones
only, gives "Render (GPU)" a median of 147 us per frame (minimum 142 us, 95th
percentile 153 us, maximum 174 us, 299 frames). The CPU `Render` zone has a
mean of 0.88 ms in the same capture. The timestamp queries alone, through
`Stats`, read 43 us for the 12 vertex panel of `test_gl_contexts` and 38 us
for the `smoke_gl` frame. With Tracy off, `perf_dispatch` measures `Button`
at 0.155 us inside the MEX, against 0.14 us in 14.5.

ImPlot3D:

| Deviation | Reason |
|---|---|
| `third_party/cimplot3d` and `third_party/ImGuiFileDialog` are plain clones pinned in `PINS.md`, not submodules. `tools/fetch_third_party.sh` clones each missing dependency, and `build.m` stops with the command when one is missing. | The repository owner converts clones to submodules. The CI fetch step already runs the script in every job, so the workflow needs no change. |
| The allowlist binds 37 subcommands, not the whole API. | The task named a curated set. Left out: `PlotImage` (an `ImTextureRef`, section 5.7 would apply), the quaternion forms of the box rotation, custom formatters and transforms, and `AddColormap`. |
| `PlotSurface` takes `X`, `Y`, `Z` as matrices of one size and reads `x_count` and `y_count` from the shape of `X`. | ImPlot3D takes the counts as arguments. The shape of a `meshgrid` matrix already says them, and a count that disagreed with the arrays would read past their end. |
| `PlotMesh` takes an Mx3 matrix of 1-based vertex indices, any numeric class, and copies it into a transposed, 0-based `unsigned` list, on the stack up to 1024 triangles. Every index is checked against the vertex count. | This is the one copy in the plot data path. It is the `Faces` convention of `patch` and `delaunay`, which is column major and 1-based, while ImPlot3D reads three consecutive 0-based indices per triangle. ImPlot3D indexes the vertex arrays without a check, so an index out of range would read outside the MATLAB array; it raises `psychimgui:Range` instead. |
| The trailing spec pairs map onto `ImPlot3DSpec`, which has no `Size` field; `Marker` takes `ImPlot3DMarker_` names. | The ImPlot3D struct differs from `ImPlotSpec` in exactly these two ways. The data rules moved to `src/plotdata_marshal.h`, shared by both extensions, so either builds without the other. |
| ImPlot and ImPlot3D subcommands that need an open plot raise `psychimgui:Usage` outside `BeginPlot` and `EndPlot`. `ImPlot3D.SetupBoxScale` raises `psychimgui:Range` for a scale that is not positive. | Both libraries guard these with `IM_ASSERT_USER_ERROR` and then dereference the current plot, which is null there; the deferred assert of section 8.3 returns, so the host crashed. For ImPlot this is a change against phases 1.5 and 2, from a crash to an error. A zero scale passes ImPlot3D's assert and then turns every vertex into NaN. |

ImGuiFileDialog:

| Deviation | Reason |
|---|---|
| Eight subcommands, not five. `IsOpened` and `GetCurrentPath` are added. | `IsOpened` lets a script keep a button disabled while its dialog is open, and `GetCurrentPath` makes the UTF-8 path round trip testable without a user. |
| `Display` returns `[done, open]`. `done` is ImGuiFileDialog's own result, true on the frame the user presses OK or Cancel; `open` is true while the dialog stays open. | The task described the return as whether the dialog is still open. ImGuiFileDialog's documented loop reads its own result, `if Display(...) ... Close()`, so the first output keeps that meaning and the second output gives the other. |
| On Windows the dialog lists folders with `std::filesystem`; on Linux and macOS with POSIX `dirent`. `src/igfd_config_psych.h` sets this. | The `dirent` shim ImGuiFileDialog ships for Windows converts names with the process code page, so a name outside it cannot be opened again; `std::filesystem` goes through the wide API. MSVC 2022 and the MinGW g++ 14 of Octave 10.1 both have it. On Linux the names are UTF-8 bytes already, and leaving `std::filesystem` out keeps the MEX independent of the libstdc++ that MATLAB loads, which can be older than the compiler's. Measured: a folder named with U+00FC and U+20AC comes back from `GetCurrentPath` unchanged under MATLAB and Octave on Windows and under Octave 6.4 on Linux. |
| ImGuiFileDialog compiles into the static library through `src/core/igfd_unit.cpp`, and the core owns the dialog objects through two functions in that file. | `ImGuiFileDialog.h` needs `IMGUI_DEFINE_MATH_OPERATORS` before the first `imgui.h` of a unit, and the core includes `imgui.h` first. Its flag names come into the enum table from its header, because it has no JSON metadata. |
| Exceptions from ImGuiFileDialog, for example `std::regex_error` from a filter, become `psychimgui:Usage`. | An exception must not cross the MEX boundary. |

Other:

| Deviation | Reason |
|---|---|
| The opcode numbers of many subcommands changed. | The new names sort into the one table. `PsychImGuiOp` is generated from the same table, as section 9.1 says. |
| `tests/gl/test_gl_render.m` and `test_gl_demo_gabor.m` skip when `Screen` does not load, as `test_gl_phase2` does. `tests/gl/ptb_test_window.m` takes a stereo mode, a screen, and `'full'`. | They counted a `Screen` that does not load under Octave on Windows as a failure. |
| `tools/smoke_gl.cpp` opens a second context in the same GL context, interleaves frames, and submits each frame twice. | The Linux CI job runs `smoke_gl` against Mesa, which is the only GL coverage CI has for the context switch and `RenderAgain`. |
| `PsychImGuiDemo(n, opts)` takes a window rectangle, a capture file, and an animated contrast, and `tools/CaptureReadmeScreenshot.m` makes `docs/images/psychimgui-demo.png` with them at 1280x720. | The README shows the demo, and the image has to be reproducible after the look of the GUI changes. The release zips do not carry it. |

ImAnim stays out of phase 3. Section 5.4 put it in phase 3 on the condition
that a libclang generator path exists, and none does: the generator reads
cimgui-family JSON with the standard library only, and ImAnim publishes
neither JSON nor a cimgui-family binding. Its C-style `iam_*` API has about
200 functions that pass and return structs, far past the ten functions that
section 5.4 allows for a hand-written binding, and its motion path API is a
fluent C++ class that no rule of section 7.3 can express. What it offers an
experiment, easing curves and springs for GUI transitions, MATLAB can compute
itself and pass in as values. It becomes worth binding when either a
cimgui-family repository publishes `definitions.json` for it, so the existing
generator applies unchanged, or the generator gains a libclang front end,
which would also open the other extensions of section 5.4 that lack metadata.

Phase 3 results on the development machine (Windows 11, MATLAB R2023a,
Octave 10.1, Psychtoolbox 3.0.22): the headless suite passes 918 of 918
under MATLAB, under Octave 10.1 on Windows, and under Octave 6.4 with g++ 11
in WSL Ubuntu 22.04. The 754 tests of phase 2 are among them, unchanged. The
GL tests pass under MATLAB: `test_gl_render` 18 of 18, `test_gl_demo_gabor`
6 of 6, `test_gl_phase2` 29 of 29 with each backend, `test_gl_contexts` 14 of
14, `test_gl_stereo` 12 of 12, and `test_gl_implot3d` 6 of 6 with each
backend. Under Octave, where `Screen` does not load on this machine, all six
skip. `smoke_gl` passes with the OpenGL 3 backend, the OpenGL 2 backend, and
the headless path. `PsychImGuiDemo` and `PsychImGuiStereoDemo` in modes 4 and
8 run clean.
