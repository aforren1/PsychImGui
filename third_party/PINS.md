# Pinned third-party commits

The dependencies below are pinned at the commits in this table. cimgui,
cimplot, cimplot3d and ImGuiFileDialog are git submodules of this repository
(see `.gitmodules`), and `git clone --recurse-submodules` fetches them at the
pinned commits; cimplot3d carries implot3d as its own nested submodule.
`tools/fetch_third_party.sh` reproduces every pinned commit in a checkout that
lacks any of them, and CI runs it.

| Path | Repository | Commit | Commit date |
|---|---|---|---|
| `third_party/cimgui` | https://github.com/cimgui/cimgui | `125f397e0982fe9466eb0a162de547be5efec849` | 2026-09-14 12:43:54 +0200 |
| `third_party/cimgui/imgui` | https://github.com/ocornut/imgui | `b48d1afbe8ee8b238e2961dc363a949dd7304e23` | 2026-07-31 16:25:00 +0200 |
| `third_party/cimplot` | https://github.com/cimgui/cimplot | `11f13e6cd0f80e83d6409e78592b392967fa7954` | 2026-08-13 12:13:59 +0200 |
| `third_party/cimplot/implot` | https://github.com/epezent/implot | `1351ab2c46d7a05a60f3533047bfba8a953520a1` | 2026-05-10 15:21:10 +0200 |
| `third_party/cimplot3d` | https://github.com/cimgui/cimplot3d | `8d04820c009357e791e30a004e410c6eb98522d1` | 2026-08-13 12:14:25 +0200 |
| `third_party/cimplot3d/implot3d` | https://github.com/brenocq/implot3d | `41ae3e447c0de20ecab95d38a4b4dc0835a3efc2` | 2026-04-05 08:17:45 +0200 |
| `third_party/ImGuiFileDialog` | https://github.com/aiekick/ImGuiFileDialog | `d0e97b2adc3d3452d72c750c7305dc0291acd052` | 2026-03-11 21:52:37 +0100 |
| `third_party/tracy` | https://github.com/wolfpld/tracy | `5d542dc09f3d9378d005092a4ad446bd405f819a` (tag `v0.11.1`) | 2024-08-22 20:07:25 +0200 |

Versions: Dear ImGui 1.92.9b (IMGUI_VERSION_NUM 19291), ImPlot 1.1 WIP
(IMPLOT_VERSION_NUM 10100), ImPlot3D 0.4 (tag `v0.4`, IMPLOT3D_VERSION_NUM
401), ImGuiFileDialog 0.6.9 WIP (`master`, 8 commits after `v0.6.8`), Tracy
0.11.1.

cimplot3d is pinned at its newest commit, generated the same day as the
cimplot pin, and its `definitions.json` describes the ImPlot3D `v0.4` in its
`implot3d` submodule. ImPlot3D 0.4 compiles against Dear ImGui 1.92.9b
unchanged. ImGuiFileDialog says it supports Dear ImGui 1.92.3; its `master`
compiles against 1.92.9b unchanged with MSVC 2022, MinGW g++ 14, and g++ 11.

Tracy is optional and is not fetched by `tools/fetch_third_party.sh`; only a
build with `PSYCHIMGUI_TRACY=1` needs it, and `.gitignore` keeps the clone
out of the repository.

To restore these clones, from the repository root:

    bash tools/fetch_third_party.sh

or by hand:

    cd third_party
    git clone --recurse-submodules https://github.com/cimgui/cimgui
    git -C cimgui checkout 125f397e0982fe9466eb0a162de547be5efec849
    git -C cimgui submodule update --init --recursive
    git clone --recurse-submodules https://github.com/cimgui/cimplot
    git -C cimplot checkout 11f13e6cd0f80e83d6409e78592b392967fa7954
    git -C cimplot submodule update --init --recursive
    git clone --recurse-submodules https://github.com/cimgui/cimplot3d
    git -C cimplot3d checkout 8d04820c009357e791e30a004e410c6eb98522d1
    git -C cimplot3d submodule update --init --recursive
    git clone https://github.com/aiekick/ImGuiFileDialog
    git -C ImGuiFileDialog checkout d0e97b2adc3d3452d72c750c7305dc0291acd052

Tracy, only for a profiling build:

    git clone --branch v0.11.1 https://github.com/wolfpld/tracy.git
