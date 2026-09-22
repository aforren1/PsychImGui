# psychimgui

`psychimgui` is a MEX binding of [Dear ImGui](https://github.com/ocornut/imgui)
for MATLAB and GNU Octave. It draws immediate mode GUI panels inside a
Psychtoolbox (PTB) onscreen window. A script describes the GUI once per frame
and reads widget values back from the return values of the same calls.

Typical uses: operator control panels, parameter sliders, live status readouts,
calibration tools, and debugging overlays.

`SPEC.md` is the design reference. This file tells you how to build the
binding, how to run the tests, and how to run the demo.

Status: phases 1 and 1.5 complete. 125 Dear ImGui subcommands, 66 ImPlot
subcommands, and 19 lifecycle subcommands, against Dear ImGui 1.92.9b and
ImPlot 1.1. `SPEC.md` section 13 has the phase plan and section 14 lists every
place the code differs from the specification.

## Requirements

| Item | Version | Needed for |
|---|---|---|
| MATLAB | R2023a, verified | Building and running the MEX |
| GNU Octave | 10.1, verified | Building and running the MEX |
| CMake | 3.16 or later | Building the static Dear ImGui library |
| C++17 compiler | MSVC 2022 for MATLAB, the bundled MinGW g++ for Octave | Building |
| Psychtoolbox | 3.0.19 or later | The demo and the GL tests only |
| Python and uv | Python 3.10 or later | The generator only |

The generated files are committed, so you do not need Python to build.

## Get the sources

    git clone --recurse-submodules <PsychImGui repository URL>

Dear ImGui and ImPlot come in through `third_party/cimgui` and
`third_party/cimplot`. Where those are not yet submodules, one script fetches
the pinned commits that `third_party/PINS.md` records:

    bash tools/fetch_third_party.sh

The script does nothing when the directories are already populated, so it is
safe to run either way, and it is what CI runs.

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

### Tests that need a GPU

`tests/gl/test_gl_render.m` opens a real Psychtoolbox window, draws a panel
with a known background color, reads the frame back, and checks the color. Run
it by hand:

    addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
    test_gl_render

Every script that opens a Psychtoolbox window calls `tests/gl/ptb_test_window`,
which sets `SkipSyncTests` to 2 and `VisualDebugLevel` to 0 first, so a test
run does not wait for the display timing calibration. An experiment that
measures timing must not set those preferences.

### The native smoke test

`smoke_gl` proves the OpenGL path without MATLAB and without Psychtoolbox. It
creates a hidden window with a legacy compatibility context, the same kind PTB
creates, and runs the core through one Init, a few frames, and Shutdown.

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
orientation. With ImPlot compiled in, a second panel shows a live trace of the
contrast and a heat map of the patch envelope. Press the Quit button or ESCAPE
to stop. `PsychImGuiDemo(120)` runs 120 frames and returns.

## Use it in an experiment

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

`PsychImGuiFrame('Begin', win, kq)` and `PsychImGuiFrame('End', win)` wrap the
per-frame lines for scripts that prefer two calls.

Rules to follow:

1. Call every `PsychImGui` subcommand between `Screen('BeginOpenGL')` and
   `Screen('EndOpenGL')`. The MEX raises `psychimgui:NoGLContext` when a GL
   subcommand runs outside.
2. Call `PsychImGui` only from the main thread.
3. The script owns the widget values. Dear ImGui is immediate mode, and the MEX
   stores nothing between frames.

## Continuous integration

`.github/workflows/ci.yml` builds and tests the binding on every push and
pull request.

| Job | What it does |
|---|---|
| `matlab-build` | Builds and tests on the oldest supported MATLAB per OS: R2021b on `ubuntu-22.04`, R2022b on `windows-2022`. Uploads the package. On Windows it also checks that `smoke_gl.exe` compiled |
| `matlab-test-forward` | Runs the floor-built binary, downloaded as an artifact, on the newest MATLAB. No rebuild |
| `octave-linux` | Builds and tests in the `gnuoctave/octave` Docker images, one per binary compatible era: 6.4.0 covers Octave 6.4 to 9.4, 10.1.0 covers 10 and later |
| `octave-linux-test-forward` | Runs the 6.4 build on Octave 9.4 and the 10.1 build on Octave 11.3. No rebuild |
| `octave-windows` | Builds and tests under MSYS2 with `MEX_CMAKE_GENERATOR=Ninja` |
| `smoke-gl-linux` | Builds `smoke_gl` and runs it against Mesa's llvmpipe under Xvfb. The only automated OpenGL coverage |
| `release` | On a `v*` tag, zips every package and publishes a GitHub Release |

Runners have no GPU, so every engine job runs the `renderer='none'` suite. The
OpenGL 3 backend is still compiled, because the MEX links it.

Each artifact holds only its own platform:

    dist/<arch>/PsychImGui.<mexext>
    m/
    README.md
    SPEC.md

Artifacts are named `psychimgui-matlab-linux`, `psychimgui-matlab-windows`,
`psychimgui-octave-linux-6.4`, `psychimgui-octave-linux-10`, and
`psychimgui-octave-windows`. A `v*` tag turns each one into a zip on the
release page.

`third_party` is not a set of submodules yet, so every build job runs
`tools/fetch_third_party.sh` first. That script does nothing when the
directories are already populated, which is what happens once `checkout` with
`submodules: recursive` fills them; until then it clones the commits recorded
in `third_party/PINS.md`.

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
`m/PsychImGui.m`, `m/PsychImGuiOp.m`, and `tests/test_gen_marshal.m`. All five
are committed, because they are build inputs. The generator refuses a function
whose arguments have no marshaling rule, and prints the reason.

## Layout

    build.m                 build driver for both engines
    CMakeLists.txt          builds imgui_static and smoke_gl
    dist/<arch>/            the built MEX, one directory per platform
    gen/                    generator and allowlist
    m/                      PsychImGui help text and the helper M-files
    src/                    MEX sources
    src/core/               engine independent core, also linked by smoke_gl
    tests/                  test suite
    tests/gl/               tests that need Psychtoolbox and a GPU
    third_party/            cimgui and cimplot clones, see PINS.md
    tools/smoke_gl.cpp      native OpenGL smoke test
    tools/fetch_third_party.sh   clones the PINS.md commits, for CI
    .github/workflows/ci.yml     the CI workflow
