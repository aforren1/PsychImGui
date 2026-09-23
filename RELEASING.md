# Releasing PsychImGui

This is the checklist for publishing a release. A release is a `v*` git tag.
CI builds the packages, runs every test, and publishes a GitHub Release with
one zip per engine and platform. You never build release binaries by hand.

## The scripted way

`do_release.ps1` in the repository root runs steps 1, 4, 5 and 6 below from a
clean `main` and stops at the first failed check:

```
.\do_release.ps1 -Version 0.2.0
```

It starts only from a tree identical to a green `origin/main`, sets the version,
commits, tags, and pushes commit and tag in one go, so CI runs once, on the tag,
and that run publishes the release. `-DryRun` shows what it would do and changes
nothing. `-LocalTests` also runs step 2 first; it is off by default because CI
has run on this tree and runs again on the tag. `-NoWait` returns right after
the push and prints the run to watch, skipping step 6. Step 3, the document
updates, the GL tests and demos under Psychtoolbox, and reading the generated
release notes stay by hand. After a red tag run, fix the cause, delete the tag
(`git tag -d v0.2.0; git push origin :refs/tags/v0.2.0`) and rerun.

## Before you start

- `git status` is clean on `main`, and the last CI run on `main` is green:
  `gh run list --limit 1`.
- You know the new version. Before 1.0: a new subcommand or helper bumps the
  minor number, a fix bumps the patch number. A change that breaks a script
  that worked before bumps the minor number and gets a line in the release
  notes that says so.

## 1. Set the version

The version lives in one place:

| File | Line |
|---|---|
| `src/core/psychimgui_core.cpp` | `#define PSYCHIMGUI_VERSION_STR "0.1.0"` |

`PsychImGui('Version')` returns it in the `psychimgui` field. The generator
does not stamp the version anywhere, so `build gen` is not needed for a
version change.

## 2. Verify locally

Run both engines. Each command builds, then runs the headless suite.

```
"C:\Program Files\MATLAB\R2023a\bin\matlab.exe" -batch "build test"
"C:\Program Files\GNU Octave\Octave-10.1.0\mingw64\bin\octave-cli.exe" --eval "build test"
```

Expect `==== N passed, 0 failed ====` from both, with the same N.

With Psychtoolbox installed, run the GL tests and the demo in MATLAB:

```matlab
cd tests/gl; test_gl_render; test_gl_demo_gabor; test_gl_phase2; test_gl_phase2('opengl2')
test_gl_contexts; test_gl_stereo; test_gl_implot3d; test_gl_implot3d('opengl2')
PsychImGuiDemo(90)
PsychImGuiStereoDemo(8, 90); PsychImGuiStereoDemo(4, 90, [0 0 800 400])
```

Expect `0 failed` from each test, the demo to print its Gabor pixel
standard deviation, and no `PsychImGuiDemo failed` or
`PsychImGuiStereoDemo failed` line. If the version
bump came with new subcommands, confirm `PsychImGui('Version')` shows the
new number and that `m/PsychImGui.m` was regenerated (`build gen`) so the
help lists them.

## 3. Update the documents

- `SPEC.md`: the status line at the top names the phase that is implemented.
  Anything that changed against the specification gets a row in section 14.
- `README.md`: new subcommands or helpers appear where their group is
  described. The asset table under "Install" matches the table below.
- `DEV.md`: new build options, tests, or CI jobs.
- `PsychImGuiSetup.m`: if you changed `m/PsychImGuiSetup.m`, copy it over the
  root file. `tests/test_setup.m` fails when the two differ.
- `third_party/PINS.md`: only if a submodule or a pinned clone moved. Then
  also confirm that ImPlot, ImPlot3D, and ImGuiFileDialog still compile
  against `third_party/cimgui/imgui`, and run `bash tools/fetch_third_party.sh`
  in a fresh checkout to prove that the pins resolve.

## 4. Push and wait for green

```
git add -A
git commit -m "Release v0.2.0"
git push
gh run watch
```

The release job only runs on a tag, so this push runs the matrix without
publishing. Wait for it to pass before tagging. A tag on a red commit
produces no release, because the release job needs every other job.

## 5. Tag

```
git tag -a v0.2.0 -m "PsychImGui v0.2.0"
git push origin v0.2.0
gh run watch
```

The tag push runs the matrix again. When every job passes, the `release`
job downloads the packages, zips each one, and runs
`gh release create v0.2.0 *.zip --title "PsychImGui v0.2.0" --generate-notes`.
The notes list the commits and pull requests since the previous tag.

## 6. Check the release

```
gh release view v0.2.0
gh release download v0.2.0 --pattern "psychimgui-matlab-windows.zip" --dir %TEMP%\rel
```

Unzip into an empty folder and follow the README install steps literally,
in a fresh MATLAB:

```matlab
addpath('C:\path\to\the\unzipped\folder');
PsychImGuiSetup;
disp(PsychImGui('Version'))
PsychImGuiDemo(90)
```

The `psychimgui` field must show the new version, and the demo must not
print `PsychImGuiDemo failed`. Do the same for one
Octave zip when you changed anything Octave specific.

## What a release contains

| Zip | Built on | Runs on |
|---|---|---|
| `psychimgui-matlab-linux.zip` | MATLAB R2021b, Ubuntu 22.04 | MATLAB R2021b and later on Linux |
| `psychimgui-matlab-windows.zip` | MATLAB R2022b, Windows Server 2022 | MATLAB R2022b and later on Windows |
| `psychimgui-octave-linux-6.4.zip` | Octave 6.4.0 | Octave 6.x through 9.x on Linux |
| `psychimgui-octave-linux-10.zip` | Octave 10.1.0 | Octave 10.x and later on Linux |
| `psychimgui-octave-windows.zip` | Octave 10.1.0 official zip | Octave 10.x on Windows |
| `psychimgui-matlab-macos.zip` | MATLAB R2023b, `macos-latest` | MATLAB R2023b and later on Apple silicon Macs |
| `psychimgui-octave-macos.zip` | Homebrew Octave, `macos-latest` | That Octave and later, on Apple silicon Macs |

Each zip holds `PsychImGuiSetup.m`, `dist/<arch>/PsychImGui.<mexext>`, `m/`
(with `m/private/`, the demos' helpers), `docs/images/psychimgui-demo.png`
(the README screenshot, so the README renders from the unzipped folder),
`README.md`, `SPEC.md`, and `LICENSE`, with no top folder. It is a complete
install for that engine and platform. The `path:` list of each `Upload
package` step in `.github/workflows/ci.yml` sets these files; change the
list there and this paragraph together.

Intel Macs are not covered. The MATLAB floor on macOS is R2023b, the first
release with a native Apple silicon build, and `macos-latest` is Apple silicon,
so both macOS zips hold `maca64` binaries only.

The two macOS jobs are `continue-on-error` until they have passed once, so a
release can still be cut while they are settling in. Check them before you
publish: if either failed, its zip is missing from the release, and the
release notes should say so.

## If the release job fails

1. Read the failing job: `gh run view --log-failed`.
2. Fix on `main`, push, and wait for green.
3. Remove the tag and any partial release, then tag again:

```
gh release delete v0.2.0 --yes
git tag -d v0.2.0
git push --delete origin v0.2.0
git tag -a v0.2.0 -m "PsychImGui v0.2.0"
git push origin v0.2.0
```

Do not reuse a version number for different binaries once a release with
that tag has been downloaded by anyone. Bump the patch number instead.

## Known limits of the process

- The version string is set by hand and is not derived from the tag. If they
  disagree, the tag wins for users, so check step 1.
- Release notes are generated from commit and pull request titles. Write
  titles that read well in a list.
- The release job has never run for real yet; the zip step was exercised
  locally. The first tag is the first end to end test.
