# PsychImGui

`PsychImGui` is a MEX binding of [Dear ImGui](https://github.com/ocornut/imgui)
for MATLAB and GNU Octave. It draws immediate mode GUI panels inside a
Psychtoolbox (PTB) onscreen window. A script describes the GUI once per frame
and reads widget values back from the return values of the same calls.

Typical uses: operator control panels, parameter sliders, live status readouts,
calibration tools, and debugging overlays.

![PsychImGuiDemo in a 1280x720 Psychtoolbox window: a control panel, an ImPlot
trace and heat map, a 3D gaze plot above a surface, a log table, and a draw
list overlay around a Gabor patch](docs/images/psychimgui-demo.png)

The image shows `PsychImGuiDemo` over its Gabor patch, captured from the
Psychtoolbox window; `tools/CaptureReadmeScreenshot` makes it again.

`SPEC.md` is the design reference. This file tells you how to build the
binding, how to run the tests, and how to run the demo.

Status: phases 1, 1.5, 2, and 3 complete. 140 Dear ImGui subcommands, 12 draw
list subcommands, 66 ImPlot subcommands, 37 ImPlot3D subcommands, and 33
hand-written subcommands, against Dear ImGui 1.92.9b, ImPlot 1.1, ImPlot3D
0.4, and ImGuiFileDialog 0.6.9. Phase 2 added tables, draw lists, and images
from Psychtoolbox textures. Phase 3 added one context per window, both eyes
of the stereo modes, GPU timing and Tracy zones, ImPlot3D, and a file dialog.
`SPEC.md` section 13 has the phase plan and section 14 lists every place the
code differs from the specification.

## Requirements

| Item | Version | Needed for |
|---|---|---|
| MATLAB | R2023a verified on Windows and Linux, R2023b or later on Apple silicon | Building and running the MEX |
| GNU Octave | 10.1 verified on Windows and Linux, Homebrew's on macOS | Building and running the MEX |
| CMake | 3.16 or later | Building the static Dear ImGui library |
| C++17 compiler | MSVC 2022 for MATLAB, the bundled MinGW g++ for Octave, clang on macOS | Building |
| Psychtoolbox | 3.0.19 or later | The demos and the GL tests only |
| Python and uv | Python 3.10 or later | The generator only |
| Tracy | 0.11.1 | Profiling builds only, see "Profile with Tracy" |

The generated files are committed, so you do not need Python to build.

## Get the sources

    git clone --recurse-submodules https://github.com/aforren1/PsychImGui.git

Dear ImGui and ImPlot come in through the `third_party/cimgui` and
`third_party/cimplot` submodules. ImPlot3D and ImGuiFileDialog come in through
`third_party/cimplot3d` and `third_party/ImGuiFileDialog`, which are not
submodules yet. One script clones every one of them that is missing, at the
commit that `third_party/PINS.md` records:

    bash tools/fetch_third_party.sh

The script does nothing when the directories are already populated, so it is
safe to run either way, and it is what CI runs. `build` stops with the same
command in its message when a directory is missing.

## Build

From MATLAB or from Octave, in the repository root:

    build

`build` configures and builds the static library with CMake, then compiles the
MEX. The result is `dist/<arch>/PsychImGui.<mexext>`, where `<arch>` is the
platform name MATLAB uses: `win64`, `glnxa64`, `maci64`, or `maca64`.

One directory per platform, because Octave names its MEX `PsychImGui.mex` on
every operating system. A flat `dist` would let a Linux build silently replace
a Windows one in a checkout shared between Windows and WSL. The two engines can
share a directory, because their file extensions differ.

Build and install directories are named per engine and per platform as well,
for example `build-matlab-windows/` and `build-octave-linux/`. MATLAB uses MSVC
and Octave uses MinGW g++ on Windows, and C++ objects from two compilers must
not be linked together.

`m/PsychImGuiSetup` puts the right directory on the path:

    addpath(fullfile(psychimgui_dir, 'm'));
    PsychImGuiSetup();          % dist/<arch> first, then m/

    PsychImGuiSetup('arch')     % the platform name
    PsychImGuiSetup('distdir')  % the directory, without touching the path
    PsychImGuiSetup('nocheck')  % add the paths without requiring the MEX

It raises `psychimgui:NotBuilt`, naming the file it looked for and the command
that builds it, when this platform has no MEX yet. `run_tests`, the demo, the
GL test, and the perf scripts all go through it.

Other forms:

| Command | Effect |
|---|---|
| `build gen` | Run the binding generator first, then build |
| `build test` | Build, then run the test suite |
| `build clean` | Remove the build and install directories of this engine |

Set the environment variable `MEX_CMAKE_GENERATOR` to choose a different CMake
generator. On Windows, Octave builds with the "MSYS Makefiles" generator,
because the "MinGW Makefiles" generator refuses to run while `sh.exe` is on the
path, and Git for Windows keeps one there.

## Run the tests

    cd tests
    run_tests

`run_tests` initializes the binding with `opts.renderer = 'none'`. The binding
then answers Dear ImGui's texture requests itself and `Render` discards the
draw data, so the suite needs no GPU and no Psychtoolbox. It passes under both
engines. See `SPEC.md` section 14.4 for why the `none` renderer still claims
texture support.

| File | What it checks |
|---|---|
| `test_dispatch.m` | Name lookup, opcode fast path, argument counts, lifecycle errors |
| `test_gen_marshal.m` | One round trip per generated subcommand. Generated |
| `test_inputtext.m` | Text round trip, non-ASCII text, buffer truncation |
| `test_keymap.m` | Shape and content of the PTB keycode table |
| `test_stats.m` | The counters count, and `reset` clears them |
| `test_assert.m` | An `IM_ASSERT` becomes an error instead of an abort |
| `test_tables.m` | Table call sequences, and the refusal of table calls outside a table |
| `test_drawlist.m` | Draw list handles, every `DrawList.` subcommand, stale handles |
| `test_image.m` | `Image`, `ImageButton`, `SetTextureFilter`, and `PsychImGuiImage` arguments |
| `test_helpers.m` | The four convenience helpers, against a recording `Screen` stub |
| `test_contexts.m` | Two contexts: switching, separate frames and Stats, stale handles, the limit of eight |
| `test_stereo.m` | When `RenderAgain` is legal, and that it builds no second frame |
| `test_filedialog.m` | `FileDialog.` argument rules, the open and close cycle, a path outside ASCII |
| `test_helpers_p3.m` | The helpers with two windows and with a stereo window, against the `Screen` stub |

### Tests that need a GPU

These tests need a real Psychtoolbox window. Run them by hand:

    addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
    test_gl_render        % the binding draws into a PTB window
    test_gl_demo_gabor    % the demo's Gabor really is a Gabor
    test_gl_phase2        % tables, draw lists, and images, pixel by pixel
    test_gl_phase2('opengl2')   % the same on the fixed function backend
    test_gl_contexts      % two windows, one context each, and the GPU timer
    test_gl_stereo        % the panel in both eyes of stereo modes 4 and 8
    test_gl_implot3d      % a 3D line plot, a surface, and a mesh
    test_gl_implot3d('opengl2')

Each one prints `SKIP` and returns when Psychtoolbox is not installed, or when
its `Screen` does not load, as on Octave for Windows without the right DLLs.

`test_gl_render` draws a panel with a known background color, reads the frame
back, and checks the color. `test_gl_contexts` draws a red panel into one
window and a blue one into a second window and reads both back.
`test_gl_stereo` reads each eye's framebuffer after
`Screen('SelectStereoDrawBuffer')`, and a control frame drawn into one eye
only proves that the check can fail. `test_gl_phase2` draws a four color test pattern
from a texture and from an offscreen window, a table with colored cells, and
draw list shapes, then checks the color at known pixels. A transposed,
mirrored, or black image fails it. `test_gl_demo_gabor` checks that the demo's patch
has the Michelson contrast its slider asks for, because a procedural Gabor
drawn with the wrong normalization is a plain gray square and raises nothing.

Every script that opens a Psychtoolbox window calls `tests/gl/ptb_test_window`,
which sets `SkipSyncTests` to 2 and `VisualDebugLevel` to 0 first, so a test
run does not wait for the display timing calibration. An experiment that
measures timing must not set those preferences.

### The native smoke test

`smoke_gl` proves the OpenGL path without MATLAB and without Psychtoolbox. It
creates a hidden window with a legacy compatibility context, the same kind PTB
creates, and runs the core through one Init, a few frames, and Shutdown. Then
it opens a second context, interleaves frames between the two, and submits
every frame twice with `RenderAgain`, as for the two eyes of a stereo mode.

    build-matlab-windows/Release/smoke_gl.exe       # the OpenGL 3 backend
    build-matlab-windows/Release/smoke_gl.exe none  # the headless path
    build-octave-linux/smoke_gl                     # same, on Linux

Windows uses WGL and Linux uses GLX, both with the legacy context call
Psychtoolbox uses, so the driver hands back its highest compatibility profile.
On a machine with no display, run it under a virtual one:

    LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a ./build-octave-linux/smoke_gl

The executable links `src/core`, which holds the engine independent half of the
binding, so a failure there is a binding failure, not a marshaling failure.
Turn it off with `-DPSYCHIMGUI_SMOKE_GL=OFF`. macOS has no context path yet.

### Performance

    perf_dispatch        % cost per call, name path against opcode path
    perf_frame           % 200 sliders per frame, frame time histogram

Both run headless. `PsychImGui('Stats')` reports the same counters from inside
the MEX at any time, in any build.

## Run the demo

    PsychImGuiDemo

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

    PsychImGuiStereoDemo

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

## Use it in an experiment

Four helpers own the `Screen('BeginOpenGL')` and `Screen('EndOpenGL')` pairs,
so your script writes none itself:

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

    idx = PsychImGuiGL(ig, 'AddFontFromFileTTF', fontPath, 18);

Inside a frame the context is already active, and Psychtoolbox does not nest
those regions, so `PsychImGuiGL` checks `Screen('GetOpenGLDrawMode')` and calls
straight through. That makes it safe anywhere.

`PsychImGuiClose` suits an `onCleanup`, so an error still releases the MEX:

    ig = PsychImGuiOpen(win);
    guard = onCleanup(@() PsychImGuiClose(ig));

### The low-level form

The helpers are M-files over the subcommands. This is the same sequence
written out, which is what the MEX contract in `SPEC.md` section 4.2 is
written against:

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

    igA = PsychImGuiOpen(winA);             % operator screen
    igB = PsychImGuiOpen(winB);             % a second display
    igA = PsychImGuiFrame('Begin', igA);    % widgets for window A
    PsychImGuiFrame('End', igA);
    igB = PsychImGuiFrame('Begin', igB);    % widgets for window B
    PsychImGuiFrame('End', igB);
    Screen('Flip', winA); Screen('Flip', winB);
    ...
    PsychImGuiClose(igA); PsychImGuiClose(igB);

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

    for eye = 0:1
        Screen('SelectStereoDrawBuffer', win, eye);
        ... draw that eye's stimulus ...
    end
    ig = PsychImGuiFrame('Begin', ig);      % ig.stereo is true
    ... widgets, once ...
    PsychImGuiFrame('End', ig);             % Render into eye 0, RenderAgain into eye 1
    Screen('Flip', win);

`PsychImGuiOpen` reads the stereo mode with `Screen('GetWindowInfo')`, so
`PsychImGuiFrame('End')` does both eyes on its own. Without the helper:

    Screen('EndOpenGL', win);
    Screen('SelectStereoDrawBuffer', win, 0);
    Screen('BeginOpenGL', win);  PsychImGui('Render');       Screen('EndOpenGL', win);
    Screen('SelectStereoDrawBuffer', win, 1);
    Screen('BeginOpenGL', win);  PsychImGui('RenderAgain');  Screen('EndOpenGL', win);

`RenderAgain` is legal after `Render` and before the next `NewFrame`; anywhere
else it raises `psychimgui:Usage`. `test_gl_stereo` checks modes 4 and 8,
which work on one display. `PsychImGuiStereoDemo` shows the whole pattern.

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

## Continuous integration

`.github/workflows/ci.yml` builds and tests the binding on every push and
pull request.

| Job | What it does |
|---|---|
| `matlab-build` | Builds and tests on the oldest supported MATLAB per OS: R2021b on `ubuntu-22.04`, R2022b on `windows-2022`. Uploads the package. On Windows it also checks that `smoke_gl.exe` compiled |
| `matlab-test-forward` | Runs the floor-built binary, downloaded as an artifact, on the newest MATLAB. No rebuild |
| `octave-linux` | Builds and tests in the `gnuoctave/octave` Docker images, one per binary compatible era: 6.4.0 covers Octave 6.4 to 9.4, 10.1.0 covers 10 and later |
| `octave-linux-test-forward` | Runs the 6.4 build on Octave 9.4 and the 10.1 build on Octave 11.3. No rebuild |
| `octave-windows` | Builds and tests with the official GNU Octave Windows zip (10.1.0, cached), using the toolchain and `make` it ships, as on a developer machine |
| `smoke-gl-linux` | Builds `smoke_gl` and runs it against Mesa's llvmpipe under Xvfb |
| `octave-macos` | Installs Homebrew's Octave on `macos-latest`, builds, and runs the headless suite. Not blocking yet |
| `smoke-gl-macos` | Builds `smoke_gl` and runs it against an offscreen CGL context, which exercises the OpenGL 2 backend. Not blocking yet |
| `release` | On a `v*` tag, zips every package and publishes a GitHub Release |

The MATLAB jobs also carry a `macos-latest` matrix entry, on R2023b, the first
MATLAB with a native Apple silicon build.

The three macOS entries are `continue-on-error` while the macOS code paths are
new, because nobody on the team has a Mac to try them on. They become blocking
after the first green run.

Runners have no GPU, so every engine job runs the `renderer='none'` suite. The
OpenGL 3 backend is still compiled, because the MEX links it.

Each artifact holds only its own platform:

    dist/<arch>/PsychImGui.<mexext>
    m/
    README.md
    SPEC.md

Artifacts are named `psychimgui-matlab-macos`, `psychimgui-octave-macos`,
`psychimgui-matlab-linux`, `psychimgui-matlab-windows`,
`psychimgui-octave-linux-6.4`, `psychimgui-octave-linux-10`, and
`psychimgui-octave-windows`. A `v*` tag turns each one into a zip on the
release page.

`third_party/cimplot3d` and `third_party/ImGuiFileDialog` are not submodules
yet, so every build job runs `tools/fetch_third_party.sh` first. That script
clones, at the commits recorded in `third_party/PINS.md`, each dependency that
`checkout` with `submodules: recursive` did not fill, and does nothing once
all of them are there.

## Plot with ImPlot

ImPlot is compiled in by default. Its subcommands carry the namespace with a
dot:

    if PsychImGui('ImPlot.BeginPlot', 'signal', [-1 200])
        PsychImGui('ImPlot.SetupAxes', 'time', 'volts');
        PsychImGui('ImPlot.PlotLine', 'trace', t, v, ...
                   'LineColor', [0.2 0.8 1 1], 'LineWeight', 2);
        PsychImGui('ImPlot.PlotHeatmap', 'field', responseMatrix);
        PsychImGui('ImPlot.EndPlot');
    end

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

Build without ImPlot with `-DPSYCHIMGUI_IMPLOT=OFF`. The subcommands then
raise `psychimgui:UnknownCommand`, and the opcodes of the other subcommands do
not move.

## Plot in 3D with ImPlot3D

ImPlot3D is compiled in by default. Its subcommands follow the ImPlot rules:

    if PsychImGui('ImPlot3D.BeginPlot', 'gaze', [-1 300])
        PsychImGui('ImPlot3D.SetupAxes', 'x', 'y', 'time');
        PsychImGui('ImPlot3D.PlotLine', 'eye', x, y, t, 'LineColor', [1 0.8 0.2 1]);
        PsychImGui('ImPlot3D.PlotSurface', 'field', X, Y, Z);     % meshgrid matrices
        PsychImGui('ImPlot3D.PlotMesh', 'shape', vx, vy, vz, faces);
        PsychImGui('ImPlot3D.EndPlot');
    end

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
`BeginPlot` and `EndPlot`, for ImPlot and ImPlot3D both. Build without
ImPlot3D with `-DPSYCHIMGUI_IMPLOT3D=OFF`.

## Choose a file

The `FileDialog.` subcommands bind ImGuiFileDialog. Open the dialog once,
display it every frame until it is done, then read the choice and close it:

    if PsychImGui('Button', 'Open data file')
        PsychImGui('FileDialog.Open', 'data', 'Choose a data file', '.csv,.mat', pwd);
    end
    if PsychImGui('FileDialog.Display', 'data', [500 320])
        if PsychImGui('FileDialog.IsOk')
            file = PsychImGui('FileDialog.GetFilePathName');
        end
        PsychImGui('FileDialog.Close');
    end

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

    fg = PsychImGui('GetForegroundDrawList');
    PsychImGui('DrawList.AddRect', fg, [100 100], [356 356], [1 0.85 0.2 1], 6, 2);
    PsychImGui('DrawList.AddCircleFilled', fg, [228 228], 4, [1 0 0 1]);
    PsychImGui('DrawList.AddPolyline', fg, [x(:) y(:)], [0 1 0 1], 2);
    PsychImGui('DrawList.AddText', fg, [100 80], [1 1 1 1], 'target');

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

    ptbTex = Screen('MakeTexture', win, img, [], 1);   % GL_TEXTURE_2D
    tex = PsychImGuiImage(ig, ptbTex);
    ...
    PsychImGui('Image', tex, tex.size);                 % inside a frame
    if PsychImGui('ImageButton', 'pick', tex, [64 32])
        ...
    end

Dear ImGui's OpenGL backends sample `GL_TEXTURE_2D` textures only.
Psychtoolbox makes `GL_TEXTURE_RECTANGLE` textures unless `specialFlags` is 1,
and those raise `psychimgui:Texture`. An offscreen window from
`Screen('OpenOffscreenWindow', win, color, rect, [], 1)` works too.

`PsychImGuiImage` also finds out how Psychtoolbox stored the texture. A
texture made from a matrix is stored transposed, and `Image` turns it upright,
so `uv0` and `uv1` select a part of the image as you see it, from the top
left. `PsychImGuiImage(ig, ptbTex, 'nearest')` shows the pixels without
smoothing.

## Profile with Tracy

`PsychImGui('Stats')` reports per-subcommand counts and times in every build,
and `frame.renderGpuNs`, the GPU time of the last finished `Render`, from
`GL_TIMESTAMP` queries read one or more frames later so they never stall.
The timer needs OpenGL 3.3 or `GL_ARB_timer_query`; without them, as on the
OpenGL 2.1 context of macOS, it reports 0 and `PsychImGui('Version').gpuTimer`
is false.

For a timeline, build with the Tracy client:

    git clone --branch v0.11.1 https://github.com/wolfpld/tracy.git third_party/tracy
    setenv('PSYCHIMGUI_TRACY', '1'); build

That build has one Tracy CPU zone per subcommand call, zones for `NewFrame`
and `Render`, one frame mark per `Render`, and a Tracy GPU zone,
"Render (GPU)", around each draw data submission. Capture with
`tracy-capture -o run.tracy` from the Tracy 0.11.1 tools while the script
runs. The client is built with `TRACY_NO_CRASH_HANDLER`: MATLAB's JVM raises
access violations on purpose and handles them, and Tracy's handler would take
the first one for a crash and hang the session. Build without
`PSYCHIMGUI_TRACY` to take the client out again.

## Find a subcommand

    PsychImGui                     % list every subcommand
    PsychImGui('SliderFloat?')     % print the signature of one subcommand
    help PsychImGui                % every signature, from m/PsychImGui.m

For the fast path, replace the name with an opcode:

    op = PsychImGuiOp();
    PsychImGui(op.SliderFloat, 'Gain', gain, 0, 1);

An opcode skips the name lookup in the MEX. Call `PsychImGuiOp` again after a
rebuild, because the values follow the dispatch table.

## Regenerate the bindings

The binding surface comes from the cimgui metadata. To add a function, add its
`ov_cimguiname` to `gen/allowlist.txt` and regenerate:

    uv run --project gen python gen/generate.py

The generator writes `src/gen_dispatch.cpp`, `src/gen_dispatch_implot.cpp`,
`src/gen_dispatch_implot3d.cpp`, `m/PsychImGui.m`, `m/PsychImGuiOp.m`, and
`tests/test_gen_marshal.m`. All six are committed, because they are build
inputs. The generator refuses a function
whose arguments have no marshaling rule, and prints the reason.

## Layout

    build.m                 build driver for both engines
    CMakeLists.txt          builds imgui_static and smoke_gl
    dist/<arch>/            the built MEX, one directory per platform
    docs/images/            the README screenshot
    gen/                    generator and allowlist
    m/                      PsychImGui help text and the helper M-files
    src/                    MEX sources
    src/core/               engine independent core, also linked by smoke_gl
    src/imgui_marshal.h     color, point list, and draw list handle rules
    tests/                  test suite
    tests/gl/               tests that need Psychtoolbox and a GPU
    third_party/            cimgui, cimplot, cimplot3d, and ImGuiFileDialog, see PINS.md
    tools/smoke_gl.cpp      native OpenGL smoke test
    tools/CaptureReadmeScreenshot.m   makes docs/images/psychimgui-demo.png again
    tools/fetch_third_party.sh   clones the PINS.md commits, for CI
    .github/workflows/ci.yml     the CI workflow

## Releasing

A release is a `v*` tag; CI builds and publishes the packages. The
step-by-step checklist, including where the version string lives and how to
recover from a failed release job, is in [RELEASING.md](RELEASING.md).
