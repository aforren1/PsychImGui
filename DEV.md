# Developing PsychImGui

This file is for contributors. It tells you how to build the binding from
source, how to run the tests, how CI works, how to profile, and how to add a
subcommand. [README.md](README.md) is for users of a release.
[SPEC.md](SPEC.md) is the design reference. [RELEASING.md](RELEASING.md) is
the release checklist.

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

```
git clone --recurse-submodules https://github.com/aforren1/PsychImGui.git
```

Dear ImGui and ImPlot come in through the `third_party/cimgui` and
`third_party/cimplot` submodules. ImPlot3D and ImGuiFileDialog come in through
`third_party/cimplot3d` and `third_party/ImGuiFileDialog`, which are not
submodules yet. One script clones every one of them that is missing, at the
commit that `third_party/PINS.md` records:

```
bash tools/fetch_third_party.sh
```

The script does nothing when the directories are already populated, so it is
safe to run either way, and it is what CI runs. `build` stops with the same
command in its message when a directory is missing.

## Build

From MATLAB or from Octave, in the repository root:

```matlab
build
```

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

Build without ImPlot with `-DPSYCHIMGUI_IMPLOT=OFF`. The subcommands then
raise `psychimgui:UnknownCommand`, and the opcodes of the other subcommands do
not move. Build without ImPlot3D with `-DPSYCHIMGUI_IMPLOT3D=OFF`.

### Put the build on the path

`PsychImGuiSetup` puts the right directory on the path. The repository root
has the same layout as a release zip, so the README install steps work in a
checkout too:

```matlab
addpath(psychimgui_dir);
PsychImGuiSetup();          % dist/<arch> first, then m/

PsychImGuiSetup('arch')     % the platform name
PsychImGuiSetup('distdir')  % the directory, without touching the path
PsychImGuiSetup('nocheck')  % add the paths without requiring the MEX
PsychImGuiSetup save        % add, then savepath
PsychImGuiSetup remove      % unload the MEX, then take the paths off again
```

It raises `psychimgui:NotBuilt`, naming the file it looked for and the command
that builds it, when this platform has no MEX yet. In a folder without
`build.m`, as in a release zip, the message says to download the zip for this
engine and platform instead. `run_tests`, the demo, the GL test, and the perf
scripts all go through it.

`PsychImGuiSetup.m` exists twice, byte for byte: in the repository root, so a
fresh unzip can call it with nothing on the path, and in `m/`, so the helpers
find it once `m/` is on the path. Each copy finds the package root from its
own location. One copy cannot call the other by name: a function that calls
its own name recurses, and the current folder comes first in the lookup.
Edit `m/PsychImGuiSetup.m`, then copy it over the root file.
`tests/test_setup.m` fails when the two differ.

## Run the tests

```matlab
cd tests
run_tests
```

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
| `test_input.m` | `PsychImGuiInput` device indices, the wheel path of each system, the wheel sign, `in.events` fields and times, `PsychImGuiEvents('filter')`, `Devices`, against the input stubs in `tf_input_stub.m` |
| `test_setup.m` | The two `PsychImGuiSetup` copies are identical; install, `remove` with the MEX locked, and a second `remove`, against a scratch package in `tempdir` |

### Tests that need a GPU

These tests need a real Psychtoolbox window. Run them by hand:

```matlab
addpath(fullfile(pwd, 'tests'), fullfile(pwd, 'tests', 'gl'));
test_gl_render        % the binding draws into a PTB window
test_gl_demo_gabor    % the demo's Gabor really is a Gabor
test_gl_phase2        % tables, draw lists, and images, pixel by pixel
test_gl_phase2('opengl2')   % the same on the fixed function backend
test_gl_contexts      % two windows, one context each, and the GPU timer
test_gl_stereo        % the panel in both eyes of stereo modes 4 and 8
test_gl_implot3d      % a 3D line plot, a surface, and a mesh
test_gl_implot3d('opengl2')
```

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
measures timing must not set those preferences. The shipped demos use their
own copies, `m/private/psychimgui_demo_window.m` and
`m/private/psychimgui_gabor_std.m`, so no shipped function calls `addpath`.
A path change while the locked MEX is loaded crashes Octave 10.1 on Linux
(`SPEC.md` section 14.6), and a demo run twice in one session would do that.
Keep each pair in step when you change one of them.

### The native smoke test

`smoke_gl` proves the OpenGL path without MATLAB and without Psychtoolbox. It
creates a hidden window with a legacy compatibility context, the same kind PTB
creates, and runs the core through one Init, a few frames, and Shutdown. Then
it opens a second context, interleaves frames between the two, and submits
every frame twice with `RenderAgain`, as for the two eyes of a stereo mode.

```
build-matlab-windows/Release/smoke_gl.exe       # the OpenGL 3 backend
build-matlab-windows/Release/smoke_gl.exe none  # the headless path
build-octave-linux/smoke_gl                     # same, on Linux
```

Windows uses WGL and Linux uses GLX, both with the legacy context call
Psychtoolbox uses, so the driver hands back its highest compatibility profile.
On a machine with no display, run it under a virtual one:

```
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a ./build-octave-linux/smoke_gl
```

The executable links `src/core`, which holds the engine independent half of the
binding, so a failure there is a binding failure, not a marshaling failure.
Turn it off with `-DPSYCHIMGUI_SMOKE_GL=OFF`. macOS has no context path yet.

### Performance

```matlab
perf_dispatch        % cost per call, name path against opcode path
perf_frame           % 200 sliders per frame, frame time histogram
```

Both run headless. `PsychImGui('Stats')` reports the same counters from inside
the MEX at any time, in any build.

### Check Linux from WSL

On a Windows machine, WSL runs the Linux build of the same checkout. The
per-platform directories keep the two builds apart. WSL needs Octave, CMake,
g++, and the OpenGL and X11 headers, as the CI Linux jobs install them:

```
sudo apt-get install -y octave cmake build-essential libgl1-mesa-dev libx11-dev
```

Then, from Windows:

```
wsl -e bash -lc "cd /mnt/c/path/to/psychimgui && octave-cli --no-gui --eval 'build test'"
```

The build writes `build-octave-linux/` and `dist/glnxa64/PsychImGui.mex`. A
MEX built with one Octave era does not load in the other: a build from
Octave 10 needs `liboctmex.so.1`, which Octave 6.4 does not have. Build with
the Octave you test with.

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

```
PsychImGuiSetup.m
dist/<arch>/PsychImGui.<mexext>
m/                               with m/private/, the demos' helpers
docs/images/psychimgui-demo.png  so the README renders from an unzipped package
README.md
SPEC.md
```

Artifacts are named `psychimgui-matlab-macos`, `psychimgui-octave-macos`,
`psychimgui-matlab-linux`, `psychimgui-matlab-windows`,
`psychimgui-octave-linux-6.4`, `psychimgui-octave-linux-10`, and
`psychimgui-octave-windows`. A `v*` tag turns each one into a zip on the
release page. The forward test jobs download an artifact over a fresh
checkout, so the files in it replace their checked-out copies with the same
content.

`third_party/cimplot3d` and `third_party/ImGuiFileDialog` are not submodules
yet, so every build job runs `tools/fetch_third_party.sh` first. That script
clones, at the commits recorded in `third_party/PINS.md`, each dependency that
`checkout` with `submodules: recursive` did not fill, and does nothing once
all of them are there.

## Profile with Tracy

`PsychImGui('Stats')` reports per-subcommand counts and times in every build,
and `frame.renderGpuNs`, the GPU time of the last finished `Render`, from
`GL_TIMESTAMP` queries read one or more frames later so they never stall.
The timer needs OpenGL 3.3 or `GL_ARB_timer_query`; without them, as on the
OpenGL 2.1 context of macOS, it reports 0 and `PsychImGui('Version').gpuTimer`
is false.

For a timeline, build with the Tracy client:

```
git clone --branch v0.11.1 https://github.com/wolfpld/tracy.git third_party/tracy
```

```matlab
setenv('PSYCHIMGUI_TRACY', '1'); build
```

That build has one Tracy CPU zone per subcommand call, zones for `NewFrame`
and `Render`, one frame mark per `Render`, and a Tracy GPU zone,
"Render (GPU)", around each draw data submission. Capture with
`tracy-capture -o run.tracy` from the Tracy 0.11.1 tools while the script
runs. The client is built with `TRACY_NO_CRASH_HANDLER`: MATLAB's JVM raises
access violations on purpose and handles them, and Tracy's handler would take
the first one for a crash and hang the session. Build without
`PSYCHIMGUI_TRACY` to take the client out again.

## Regenerate the bindings

The binding surface comes from the cimgui metadata. To add a function, add its
`ov_cimguiname` to `gen/allowlist.txt` and regenerate:

```
uv run --project gen python gen/generate.py
```

The generator writes `src/gen_dispatch.cpp`, `src/gen_dispatch_implot.cpp`,
`src/gen_dispatch_implot3d.cpp`, `m/PsychImGui.m`, `m/PsychImGuiOp.m`, and
`tests/test_gen_marshal.m`. All six are committed, because they are build
inputs. The generator refuses a function
whose arguments have no marshaling rule, and prints the reason.

## Make the README screenshot again

```matlab
cd tools; CaptureReadmeScreenshot
```

`tools/CaptureReadmeScreenshot` runs the demo at 1280x720 and writes
`docs/images/psychimgui-demo.png`. Run it after a change to the look of the
GUI.

## Layout

```
PsychImGuiSetup.m       puts the MEX and m/ on the path; same file as m/PsychImGuiSetup.m
build.m                 build driver for both engines
CMakeLists.txt          builds imgui_static and smoke_gl
DEV.md                  this file
README.md               install and use, for users
RELEASING.md            the release checklist
SPEC.md                 the design reference
dist/<arch>/            the built MEX, one directory per platform
docs/images/            the README screenshot
gen/                    generator and allowlist
m/                      PsychImGui help text and the helper M-files
m/private/              window and pixel helpers of the shipped demos
src/                    MEX sources
src/core/               engine independent core, also linked by smoke_gl
src/imgui_marshal.h     color, point list, and draw list handle rules
tests/                  test suite
tests/gl/               tests that need Psychtoolbox and a GPU
third_party/            cimgui, cimplot, cimplot3d, and ImGuiFileDialog, see PINS.md
tools/smoke_gl.cpp      native OpenGL smoke test
tools/CaptureReadmeScreenshot.m   makes docs/images/psychimgui-demo.png again; source tree only
tools/fetch_third_party.sh   clones the PINS.md commits, for CI
.github/workflows/ci.yml     the CI workflow
```

## Release

A release is a `v*` tag; CI builds and publishes the packages. The
step-by-step checklist, including where the version string lives and how to
recover from a failed release job, is in [RELEASING.md](RELEASING.md).
