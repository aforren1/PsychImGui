# PsychImGui

`PsychImGui` is a MEX binding of [Dear ImGui](https://github.com/ocornut/imgui)
for MATLAB and GNU Octave. It draws immediate mode GUI panels inside a
Psychtoolbox (PTB) onscreen window. A script describes the GUI once per frame
and reads widget values back from the return values of the same calls. It
also binds [ImPlot](https://github.com/epezent/implot) for live plots,
[ImPlot3D](https://github.com/brenocq/implot3d) for 3D plots, and
[ImGuiFileDialog](https://github.com/aiekick/ImGuiFileDialog) for a file
chooser.

Typical uses: operator control panels, parameter sliders, live status readouts,
calibration tools, and debugging overlays. Pick PsychImGui when the GUI
changes with the experiment state every frame, when you want to write the
panel inline in the trial loop, or when you need plots and debug views
quickly. The cost is one MEX call per widget per frame.

![PsychImGuiDemo in a 1280x720 Psychtoolbox window: a control panel, an ImPlot
trace and heat map, a 3D gaze plot above a surface, a log table, and a draw
list overlay around a Gabor patch](docs/images/psychimgui-demo.png)

The image shows `PsychImGuiDemo` over its Gabor patch, captured from the
Psychtoolbox window.

## Install

You do not need a compiler. Each release has one zip per engine and platform,
with the compiled MEX file inside.

> The first release is pending. Until it is published, build from source as
> [DEV.md](DEV.md) tells you.

### 1. Download the zip for your engine and platform

Open the [Releases page](https://github.com/aforren1/PsychImGui/releases) and
download the asset that matches the engine you run and your operating system:

| Asset | Use it with |
|---|---|
| `psychimgui-matlab-windows.zip` | MATLAB R2022b or later on Windows |
| `psychimgui-matlab-linux.zip` | MATLAB R2021b or later on Linux |
| `psychimgui-matlab-macos.zip` | MATLAB R2023b or later on Apple silicon Macs |
| `psychimgui-octave-windows.zip` | Octave 10 on Windows |
| `psychimgui-octave-linux-10.zip` | Octave 10 or later on Linux |
| `psychimgui-octave-linux-6.4.zip` | Octave 6.4 to 9.x on Linux |
| `psychimgui-octave-macos.zip` | Homebrew Octave on Apple silicon Macs |

A zip for one engine does not work in the other engine, and a zip for one
operating system does not work on another.

### 2. Unzip it into its own folder

The zip has no top folder. Unzip it into a new, empty folder, for example
`C:\toolboxes\PsychImGui` or `~/toolboxes/PsychImGui`. The folder then holds:

```
PsychImGuiSetup.m          adds the folders below to the path
dist/<arch>/PsychImGui.*   the MEX file for this engine and platform
m/                         the helper functions, the demos, and the help text
docs/images/               the screenshot this README shows
README.md
SPEC.md
```

### 3. Add it to the path

In MATLAB or Octave, add the folder and run `PsychImGuiSetup` from it:

```matlab
addpath('C:\toolboxes\PsychImGui');
PsychImGuiSetup;
```

`PsychImGuiSetup` puts `dist/<arch>` and `m/` on the path, with the MEX file
first. These forms do the same without the PsychImGui folder itself on the
path:

```matlab
run('C:\toolboxes\PsychImGui\PsychImGuiSetup.m');
```

```matlab
cd('C:\toolboxes\PsychImGui');
PsychImGuiSetup;
```

When the folder has no MEX file for this engine and platform,
`PsychImGuiSetup` stops with `psychimgui:NotBuilt` and names the file it looked
for. Download the zip that matches your engine and operating system.

### 4. Verify

```matlab
disp(PsychImGui('Version'))
```

The output is a struct. `psychimgui` is the version of the binding, and
`imgui`, `implotVersion`, and `implot3dVersion` are the versions of the
libraries. For example:

```
                imgui: '1.92.9b'
             imguiNum: 19291
           psychimgui: '0.1.0'
             renderer: 'none'
                  ...
```

`renderer` is `'none'` until a window initializes the binding.

### 5. Keep it on the path

The path change lasts for the current session. To keep it for later
sessions, add `save` in step 3:

```matlab
addpath('C:\toolboxes\PsychImGui');
PsychImGuiSetup save
```

`PsychImGuiSetup save` runs `savepath` for you. MATLAB writes its
`pathdef.m`, and Octave writes a section of `~/.octaverc`. If `savepath` cannot
write the file, `PsychImGuiSetup` warns with `psychimgui:SavePath`. Then use
one of these instead:

- MATLAB: put the two lines of step 3 in your `startup.m`.
- Octave: put the two lines of step 3 in your `~/.octaverc`.
- Either engine: put the two lines where you already add Psychtoolbox.

Do not change the path while a script uses PsychImGui. On Octave 10.1 for
Linux, a path change while the MEX file is loaded crashes Octave.
`PsychImGuiSetup` changes the path only when the path is not correct yet, so
you can run it again at any time.

### Remove it

```matlab
PsychImGuiSetup remove          % for this session
PsychImGuiSetup remove save     % and for later sessions
```

`remove` takes `dist/<arch>`, `m/`, and the PsychImGui folder off the path.
First it shuts down every PsychImGui context and unloads the MEX file, so the
path change is safe on Octave. If the MEX file stays loaded, `remove` warns
with `psychimgui:StillLoaded`, tells you what to do, and does not change the
path.

When PsychImGui is not on the path, `remove` does nothing. After a remove,
`PsychImGuiSetup` itself is off the path; call it from the PsychImGui folder,
as in step 3, to add PsychImGui again. To uninstall, remove it with `save`,
then delete the folder.

## A first example

This script shows a disc from Psychtoolbox and a panel with a slider that
sets the radius of the disc. It runs for about 10 seconds, or until you press
Quit.

```matlab
PsychDefaultSetup(2);
InitializeMatlabOpenGL(1);                    % before the window, or Open refuses
screenid = max(Screen('Screens'));
[win, rect] = PsychImaging('OpenWindow', screenid, 0, [0 0 800 600]);
ig = PsychImGuiOpen(win);
radius = 100;
done = false;
for frame = 1:600                             % about 10 s at 60 Hz
    disc = CenterRectOnPoint([0 0 2 2] * radius, rect(3) / 2, rect(4) / 2);
    Screen('FillOval', win, [1 1 1], disc);   % the stimulus, drawn by PTB
    ig = PsychImGuiFrame('Begin', ig);
    if PsychImGui('Begin', 'Controls')
        [~, radius] = PsychImGui('SliderFloat', 'radius', radius, 10, 250);
        done = PsychImGui('Button', 'Quit');
    end
    PsychImGui('End');
    PsychImGuiFrame('End', ig);
    Screen('Flip', win);
    if done, break; end
end
PsychImGuiClose(ig);
sca;
```

Drag the slider with the mouse. The disc follows on the next frame. The
script owns the value: `SliderFloat` returns the new radius, and the script
passes it back in on the next frame.

If Psychtoolbox stops with a synchronization failure, as it can on a laptop,
add `Screen('Preference', 'SkipSyncTests', 1);` at the top to try the example.
Do not keep that line in an experiment that measures timing.

"Use it in an experiment" below explains each helper.

## Run the demo

```matlab
PsychImGuiDemo
```

The demo opens a 640x480 Psychtoolbox window with a Gabor patch and a control
panel. The sliders drive the contrast, the spatial frequency, and the
orientation. The contrast slider is the Michelson contrast of the patch, from
0 to 1. The "Open file..." button opens the file dialog. With ImPlot compiled
in, a second panel shows a live trace of the contrast and a heat map of the
patch envelope. With ImPlot3D compiled in, a third panel shows a simulated
gaze trace in 3D above a surface of the patch envelope. A fourth panel has a
table of the slider values and a Psychtoolbox texture shown with
`PsychImGui('Image')`. A draw list overlay marks the outline, the center, and
the rotation angle of the patch; the "overlay" check box turns it off. Press
the Quit button or ESCAPE to stop. `PsychImGuiDemo(120)` runs 120 frames and
returns, and `PsychImGuiDemo(120, struct('rect', [0 0 1280 720]))` runs in a
larger window; the panels follow the window size.

### The stereo demo

```matlab
PsychImGuiStereoDemo
```

The stereo demo draws a disc inside a frame into each eye, with a disparity
that the control panel sets, and draws the panel into both eyes. With two or
more displays it uses stereo mode 4, one window split across the displays.
With one display it uses mode 8, red-blue anaglyph. `PsychImGuiStereoDemo(10)`
uses mode 10, one window per display.

The demo opens with `PsychDefaultSetup(2)`, as every Psychtoolbox demo does,
so colors are in the normalized 0 to 1 range.

The demo measures its own first frame and stops with `psychimgui:FlatGabor` if
the patch came out flat. A procedural Gabor fails silently, so this is the only
way to notice.

Both demos skip the Psychtoolbox display synchronization tests, so they start
fast. An experiment that measures timing must not do that.

## Use it in an experiment

Four helpers own the `Screen('BeginOpenGL')` and `Screen('EndOpenGL')` pairs,
so your script writes none itself:

```matlab
% Setup, once
InitializeMatlabOpenGL(1);          % before the window, or Open refuses
[win, rect] = PsychImaging('OpenWindow', screenid, 0);
ig = PsychImGuiOpen(win);

% Every frame
ig = PsychImGuiFrame('Begin', ig);
if PsychImGui('Begin', 'Controls')
    [~, gain] = PsychImGui('SliderFloat', 'Gain', gain, 0, 1);
end
PsychImGui('End');
PsychImGuiFrame('End', ig);
Screen('Flip', win);

% Teardown, once
PsychImGuiClose(ig);
sca;
```

| Helper | What it does |
|---|---|
| `ig = PsychImGuiOpen(win [, opts])` | Puts the MEX on the path, runs `Init` inside the OpenGL context, starts the keyboard queue, returns the handle |
| `ig = PsychImGuiFrame('Begin', ig)` | Reads the devices, enters the context, starts the frame. `ig.in` holds this frame's input |
| `PsychImGuiFrame('End', ig)` | Renders and leaves the context |
| `PsychImGuiClose(ig)` | Shuts the MEX down and stops the queue. Safe to call twice, and after the window has closed |
| `PsychImGuiGL(ig, 'Cmd', ...)` | One subcommand inside the context, for calls outside a frame |
| `tex = PsychImGuiImage(ig, ptbTexture [, filter])` | Describes a Psychtoolbox texture for `PsychImGui('Image')` |

`opts` is the option struct of `PsychImGui('Init')`: `renderer`,
`glslVersion`, `iniFile`, `logFile`, `implot`, `implot3d`. `PsychImGuiOpen`
also reads `opts.stereo`, which overrides the stereo mode it reads from the
window.

The handle carries the context of its window in `ig.ctx` and whether the
window is stereo in `ig.stereo`. Each helper makes the handle's context
current first, so a script that uses the helpers never switches contexts
itself.

Use `PsychImGuiGL` for a subcommand that needs the OpenGL context but does not
belong to a frame:

```matlab
idx = PsychImGuiGL(ig, 'AddFontFromFileTTF', fontPath, 18);
```

Inside a frame the context is already active, and Psychtoolbox does not nest
those regions, so `PsychImGuiGL` checks `Screen('GetOpenGLDrawMode')` and calls
straight through. That makes it safe anywhere.

`PsychImGuiClose` suits an `onCleanup`, so an error still releases the MEX:

```matlab
ig = PsychImGuiOpen(win);
guard = onCleanup(@() PsychImGuiClose(ig));
```

`PsychImGui('Stats')` reports per-subcommand call counts and times, and the
GPU time of the last `Render`, at any time and in any build.

### The low-level form

The helpers are M-files over the subcommands. This is the same sequence
written out, which is what the MEX contract in `SPEC.md` section 4.2 is
written against:

```matlab
% Setup, once
InitializeMatlabOpenGL(1);
[win, rect] = PsychImaging('OpenWindow', screenid, 0);
Screen('BeginOpenGL', win);
PsychImGui('Init', win, rect, PsychImGuiKeymap());
Screen('EndOpenGL', win);
kq = PsychImGuiInput('Start', win);

% Every frame
in = PsychImGuiInput('Poll', kq, win);
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

Write it this way only when your script already manages the OpenGL context for
its own drawing. Every pair you write is a chance to leave Psychtoolbox in 3D
mode after an error, which makes the next `Screen` call abort the script with a
message about the wrong thing.

Rules to follow:

1. Call every `PsychImGui` subcommand between `Screen('BeginOpenGL')` and
   `Screen('EndOpenGL')`. The MEX raises `psychimgui:NoGLContext` when a GL
   subcommand runs outside. The four helpers do this for you.
2. Call `PsychImGui` only from the main thread.
3. The script owns the widget values. Dear ImGui is immediate mode, and the MEX
   stores nothing between frames.
4. With several windows, enter the window of the current context. After
   `PsychImGui('SetContext', ctx)`, call `Screen('BeginOpenGL', win)` for that
   context's window before any subcommand that draws. The MEX raises
   `psychimgui:Context` otherwise.

### Several windows

Each Psychtoolbox window gets its own context: its own Dear ImGui state, font
atlas, input state, OpenGL objects, and Stats. Psychtoolbox gives every
onscreen window its own OpenGL context and shares no objects between windows,
so one context cannot draw into two windows.

```matlab
igA = PsychImGuiOpen(winA);             % operator screen
igB = PsychImGuiOpen(winB);             % a second display
igA = PsychImGuiFrame('Begin', igA);    % widgets for window A
PsychImGuiFrame('End', igA);
igB = PsychImGuiFrame('Begin', igB);    % widgets for window B
PsychImGuiFrame('End', igB);
Screen('Flip', winA); Screen('Flip', winB);
...
PsychImGuiClose(igA); PsychImGuiClose(igB);
```

The subcommands behind this, for scripts that manage the OpenGL regions
themselves:

| Subcommand | What it does |
|---|---|
| `ctx = PsychImGui('Init', win, rect, keymap [, opts])` | Makes a context for window `win` and makes it current. A second `Init` for the same window raises `psychimgui:AlreadyInit`. Eight contexts at most |
| `PsychImGui('SetContext', ctx)` | Makes `ctx` current. A handle of a context that was shut down raises `psychimgui:InvalidHandle` |
| `[ctx, all] = PsychImGui('GetContext')` | The current handle, 0 for none, and every live handle |
| `PsychImGui('Shutdown' [, ctx or 'all'])` | Shuts down the current context, the context `ctx`, or all of them. With no context left, the MEX unlocks |

Every other subcommand acts on the current context. A handle is never reused,
so a stale handle cannot select a newer context. A draw list handle is valid
only in the context and frame that returned it.

### Stereo

In a Psychtoolbox stereo mode each eye is a separate buffer. Dear ImGui builds
one frame; `Render` draws it into the selected eye, and `RenderAgain` draws
the same frame into the other one. The frame reads its input once.

```matlab
for eye = 0:1
    Screen('SelectStereoDrawBuffer', win, eye);
    ... draw that eye's stimulus ...
end
ig = PsychImGuiFrame('Begin', ig);      % ig.stereo is true
... widgets, once ...
PsychImGuiFrame('End', ig);             % Render into eye 0, RenderAgain into eye 1
Screen('Flip', win);
```

`PsychImGuiOpen` reads the stereo mode with `Screen('GetWindowInfo')`, so
`PsychImGuiFrame('End')` does both eyes on its own. Without the helper:

```matlab
Screen('EndOpenGL', win);
Screen('SelectStereoDrawBuffer', win, 0);
Screen('BeginOpenGL', win);  PsychImGui('Render');       Screen('EndOpenGL', win);
Screen('SelectStereoDrawBuffer', win, 1);
Screen('BeginOpenGL', win);  PsychImGui('RenderAgain');  Screen('EndOpenGL', win);
```

`RenderAgain` is legal after `Render` and before the next `NewFrame`; anywhere
else it raises `psychimgui:Usage`. `PsychImGuiStereoDemo` shows the whole
pattern.

### Which OpenGL backend

`PsychImGui('Init')` reads `GL_VERSION` and picks a Dear ImGui backend:
`imgui_impl_opengl3` for OpenGL 3.0 and later, and the fixed function
`imgui_impl_opengl2` below that. `PsychImGui('Version')` reports which one is
running, in `renderer`, along with the GLSL version in `glslVersion`.

The split matters on macOS. Psychtoolbox creates a legacy OpenGL 2.1 context
there, and `imgui_impl_opengl3` calls `glGenVertexArrays` on every frame with
only a compile time guard, so it cannot work in a 2.1 profile. The OpenGL 2
backend has no such call.

`opts.renderer` overrides the choice: `'auto'` (the default), `'opengl3'`,
`'opengl2'`, or `'none'` for the headless tests.

## Plot with ImPlot

ImPlot is compiled in by default. Its subcommands carry the namespace with a
dot:

```matlab
if PsychImGui('ImPlot.BeginPlot', 'signal', [-1 200])
    PsychImGui('ImPlot.SetupAxes', 'time', 'volts');
    PsychImGui('ImPlot.PlotLine', 'trace', t, v, ...
               'LineColor', [0.2 0.8 1 1], 'LineWeight', 2);
    PsychImGui('ImPlot.PlotHeatmap', 'field', responseMatrix);
    PsychImGui('ImPlot.EndPlot');
end
```

Data arrays go to ImPlot without a copy. Pass double, single, or any integer
class; every array in one call must share a class and a length. A matrix, as
for a heat map, is read in MATLAB's own column major order, so no transpose is
needed. Logical arrays are rejected; convert them with `double()`.

The trailing name-value pairs set the `ImPlotSpec` of the item: `LineColor`,
`LineWeight`, `FillColor`, `FillAlpha`, `Marker`, `MarkerSize`,
`MarkerLineColor`, `MarkerFillColor`, `Size`, `Offset`, `Stride`, and `Flags`.
A struct with the same field names works too. Colors are a 1x4 double in 0 to
1 or the word `'Auto'`; `Marker` takes a name such as `'Circle'`; `Flags` takes
a number, a name, or a cellstr of names.

A build without ImPlot (see [DEV.md](DEV.md)) raises
`psychimgui:UnknownCommand` for these subcommands. `PsychImGui('Version').implot`
tells you whether ImPlot is in.

## Plot in 3D with ImPlot3D

ImPlot3D is compiled in by default. Its subcommands follow the ImPlot rules:

```matlab
if PsychImGui('ImPlot3D.BeginPlot', 'gaze', [-1 300])
    PsychImGui('ImPlot3D.SetupAxes', 'x', 'y', 'time');
    PsychImGui('ImPlot3D.PlotLine', 'eye', x, y, t, 'LineColor', [1 0.8 0.2 1]);
    PsychImGui('ImPlot3D.PlotSurface', 'field', X, Y, Z);     % meshgrid matrices
    PsychImGui('ImPlot3D.PlotMesh', 'shape', vx, vy, vz, faces);
    PsychImGui('ImPlot3D.EndPlot');
end
```

Data arrays go to ImPlot3D without a copy, in any numeric class. `PlotSurface`
takes three same-size matrices, as `meshgrid` makes them, and reads the grid
size from their shape. `PlotMesh` takes the vertex coordinates and an Mx3
matrix of 1-based vertex indices, one row per triangle, which is the `Faces`
matrix of `patch`; an index outside the vertices raises `psychimgui:Range`.
The trailing name-value pairs set the `ImPlot3DSpec` of the item, with the
ImPlot names except `Size`.

| Group | Subcommands (`ImPlot3D.` prefix omitted) |
|---|---|
| Plot frame | `BeginPlot`, `EndPlot` |
| Setup | `SetupAxis`, `SetupAxes`, `SetupAxisLimits`, `SetupAxesLimits`, `SetupAxisTicks`, `SetupBoxRotation`, `SetupBoxScale`, `SetupLegend` |
| Items | `PlotLine`, `PlotScatter`, `PlotTriangle`, `PlotQuad`, `PlotSurface`, `PlotMesh`, `PlotText` |
| Queries | `PlotToPixels`, `GetPlotRectPos`, `GetPlotRectSize` |
| Colormaps | `PushColormap`, `PushColormapIndex`, `PopColormap`, `GetColormapCount`, `GetColormapName`, `SampleColormap` |
| Style | `StyleColorsAuto`, `StyleColorsDark`, `StyleColorsLight`, `StyleColorsClassic`, `PushStyleColor`, `PopStyleColor`, `PushStyleVar`, `PushStyleVarVec2`, `PopStyleVar` |
| Diagnostics | `ShowDemoWindow`, `ShowMetricsWindow` |

A subcommand that needs an open plot raises `psychimgui:Usage` outside
`BeginPlot` and `EndPlot`, for ImPlot and ImPlot3D both.

## Choose a file

The `FileDialog.` subcommands bind ImGuiFileDialog. Open the dialog once,
display it every frame until it is done, then read the choice and close it:

```matlab
if PsychImGui('Button', 'Open data file')
    PsychImGui('FileDialog.Open', 'data', 'Choose a data file', '.csv,.mat', pwd);
end
if PsychImGui('FileDialog.Display', 'data', [500 320])
    if PsychImGui('FileDialog.IsOk')
        file = PsychImGui('FileDialog.GetFilePathName');
    end
    PsychImGui('FileDialog.Close');
end
```

| Subcommand | What it does |
|---|---|
| `FileDialog.Open` | `(key, title, filters [, path] [, fileName] [, maxSelection] [, flags])`. An empty filter makes a directory chooser. `flags` takes `ImGuiFileDialogFlags_` names |
| `FileDialog.Display` | `[done, open] = (key [, minSize] [, maxSize] [, windowFlags])`. `done` is true on the frame the user presses OK or Cancel; `open` is true while the dialog stays open. Call it inside a frame |
| `FileDialog.IsOk` | True when the user pressed OK |
| `FileDialog.GetFilePathName` | The chosen path |
| `FileDialog.GetSelection` | Every chosen path as a cellstr, for `maxSelection` above 1 |
| `FileDialog.GetCurrentPath` | The folder the dialog shows |
| `FileDialog.IsOpened` | True while a dialog, or the dialog with `key`, is open |
| `FileDialog.Close` | Closes the dialog |

Paths are UTF-8 inside the MEX. MATLAB's UTF-16 char arrays and Octave's
UTF-8 ones both convert, so a folder name outside ASCII works on both. Each
context has its own dialog.

## Show a table

Tables use the Dear ImGui call sequence:

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

| Subcommand | What it does |
|---|---|
| `BeginTable`, `EndTable` | Open and close a table. Call `EndTable` only when `BeginTable` returned true |
| `TableSetupColumn`, `TableSetupScrollFreeze`, `TableHeadersRow`, `TableHeader` | Column names, frozen rows and columns, header cells |
| `TableNextRow`, `TableNextColumn`, `TableSetColumnIndex` | Move to the next row or cell |
| `TableGetColumnCount`, `TableGetColumnIndex` | Where you are |
| `TableSetBgColor` | Row or cell background, a 1x4 color |

A table call in the wrong place, for example `TableNextRow` outside a table,
raises `psychimgui:Usage`. Dear ImGui itself would crash there.

## Draw shapes and text

A draw list takes shapes in window pixels. Get a handle every frame, from one
of three draw lists:

| Getter | Draws |
|---|---|
| `GetWindowDrawList` | Into the current window, clipped to it |
| `GetBackgroundDrawList` | Behind every window |
| `GetForegroundDrawList` | Over every window |

```matlab
fg = PsychImGui('GetForegroundDrawList');
PsychImGui('DrawList.AddRect', fg, [100 100], [356 356], [1 0.85 0.2 1], 6, 2);
PsychImGui('DrawList.AddCircleFilled', fg, [228 228], 4, [1 0 0 1]);
PsychImGui('DrawList.AddPolyline', fg, [x(:) y(:)], [0 1 0 1], 2);
PsychImGui('DrawList.AddText', fg, [100 80], [1 1 1 1], 'target');
```

The `DrawList.` subcommands are `AddLine`, `AddRect`, `AddRectFilled`,
`AddCircle`, `AddCircleFilled`, `AddTriangle`, `AddTriangleFilled`, `AddText`,
`AddPolyline`, `AddConvexPolyFilled`, `PushClipRect`, and `PopClipRect`.
Points are `[x y]`, point lists are Nx2, and colors are `[r g b a]` from 0 to
1. `PsychImGui('DrawList.AddLine?')` prints a full signature.

A handle is valid only between `NewFrame` and `Render` of the frame that
returned it. After that it raises `psychimgui:InvalidHandle`, so a stale
handle can never draw into freed memory.

## Show a Psychtoolbox texture

`Image` and `ImageButton` show a Psychtoolbox texture. Make the texture with
`specialFlags` 1, and describe it once with `PsychImGuiImage`:

```matlab
ptbTex = Screen('MakeTexture', win, img, [], 1);   % GL_TEXTURE_2D
tex = PsychImGuiImage(ig, ptbTex);
...
PsychImGui('Image', tex, tex.size);                 % inside a frame
if PsychImGui('ImageButton', 'pick', tex, [64 32])
    ...
end
```

Dear ImGui's OpenGL backends sample `GL_TEXTURE_2D` textures only.
Psychtoolbox makes `GL_TEXTURE_RECTANGLE` textures unless `specialFlags` is 1,
and those raise `psychimgui:Texture`. An offscreen window from
`Screen('OpenOffscreenWindow', win, color, rect, [], 1)` works too.

`PsychImGuiImage` also finds out how Psychtoolbox stored the texture. A
texture made from a matrix is stored transposed, and `Image` turns it upright,
so `uv0` and `uv1` select a part of the image as you see it, from the top
left. `PsychImGuiImage(ig, ptbTex, 'nearest')` shows the pixels without
smoothing.

## Find a subcommand

```matlab
PsychImGui                     % list every subcommand
PsychImGui('SliderFloat?')     % print the signature of one subcommand
help PsychImGui                % every signature, from m/PsychImGui.m
```

For the fast path, replace the name with an opcode:

```matlab
op = PsychImGuiOp();
PsychImGui(op.SliderFloat, 'Gain', gain, 0, 1);
```

An opcode skips the name lookup in the MEX. Get the opcodes from
`PsychImGuiOp` in the same session, and do not store them in files: the
values follow the dispatch table, which can change from one release or build
to the next.

## Requirements

- Psychtoolbox 3.0.19 or later.
- One of these engines. The release zips are built on the oldest release in
  each row:

  | Platform | MATLAB | GNU Octave |
  |---|---|---|
  | Windows | R2022b or later | 10.x |
  | Linux | R2021b or later | 6.4 or later |
  | macOS, Apple silicon only | R2023b or later | Homebrew's current release |

  The development machine runs MATLAB R2023a and Octave 10.1 on Windows and
  Octave 6.4 on Linux. The macOS builds are tested in CI only, without a GPU.
- OpenGL 2.1 or later. PsychImGui uses the OpenGL 3 backend on OpenGL 3.0 and
  later, and the OpenGL 2 backend below that, as on macOS. The GPU timer in
  `Stats` needs OpenGL 3.3 or `GL_ARB_timer_query`.
- No compiler. A release zip holds the compiled MEX file. You need a compiler
  only to build from source; [DEV.md](DEV.md) lists what that takes.

## Where to go next

- [DEV.md](DEV.md): build from source, run the tests, CI, profiling with
  Tracy, and how to add a subcommand. For contributors.
- [SPEC.md](SPEC.md): the design reference. Section 5 is the API reference,
  and section 14 lists every place the code differs from the specification.
- [RELEASING.md](RELEASING.md): how a release is made and what each zip
  holds.

## License

PsychImGui is MIT licensed; see `LICENSE`.

The libraries compiled into the MEX file have their own licenses, all MIT:
Dear ImGui, cimgui, ImPlot, cimplot, ImPlot3D, and ImGuiFileDialog. The
license texts are in `third_party/` of the source repository. Tracy, used
only in profiling builds that are not released, is BSD 3-Clause.
