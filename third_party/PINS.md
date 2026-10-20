# Pinned third-party commits

The dependencies below are pinned at the commits in this table. cimgui,
cimplot, cimplot3d and ImGuiFileDialog are git submodules of this repository
(see `.gitmodules`), and `git clone --recurse-submodules` fetches them at the
pinned commits; cimplot3d carries implot3d as its own nested submodule.
`tools/fetch_third_party.sh` reproduces every pinned commit in a checkout that
lacks any of them, and CI runs it.

| Path | Repository | Commit | Commit date |
|---|---|---|---|
| `third_party/cimgui` | https://github.com/cimgui/cimgui | `c4461a7eadbd17b6a6a8124a8abbf499aba6318d` | 2026-10-18 14:51:16 +0200 |
| `third_party/cimgui/imgui` | https://github.com/ocornut/imgui | `6d32174508fb8c518e7a832cc1d571fadd5cba76` | 2026-10-15 14:03:51 +0200 |
| `third_party/cimplot` | https://github.com/cimgui/cimplot | `73312c058ec3e10dbe6cb33e0f2145210fb96773` | 2026-10-17 19:42:56 +0200 |
| `third_party/cimplot/implot` | https://github.com/epezent/implot | `851cdbdd60d1dfb64c23e987969694de0f547a6b` | 2026-10-10 17:13:14 +0200 |
| `third_party/cimplot3d` | https://github.com/cimgui/cimplot3d | `f8b28155c8f164c947c95b8ce600ea091a5a9008` | 2026-10-18 16:02:00 +0200 |
| `third_party/cimplot3d/implot3d` | https://github.com/brenocq/implot3d | `a56518b0845cff45d81ccdaf9075d02fc52d5c01` | 2026-10-18 15:39:19 +0200 |
| `third_party/ImGuiFileDialog` | https://github.com/aiekick/ImGuiFileDialog | `d0e97b2adc3d3452d72c750c7305dc0291acd052` | 2026-03-11 21:52:37 +0100 |
| `third_party/tracy` | https://github.com/wolfpld/tracy | `5d542dc09f3d9378d005092a4ad446bd405f819a` (tag `v0.11.1`) | 2024-08-22 20:07:25 +0200 |

Versions: Dear ImGui 1.93.0 (IMGUI_VERSION_NUM 19300, the `master` flavor
without docking, one commit after the `v1.93.0` tag), ImPlot 1.1 WIP
(IMPLOT_VERSION_NUM 10100, 10 commits after `v1.0`), ImPlot3D 0.5 WIP
(IMPLOT3D_VERSION_NUM 500, 15 commits after `v0.4`), ImGuiFileDialog 0.6.9 WIP (`master`, 8 commits after `v0.6.8`), Tracy
0.11.1.

cimgui is pinned at the head of its `master` branch, which bundles Dear
ImGui 1.93.0 without docking. No cimgui commit bundles the `v1.93.0-docking`
tag, and the binding never enables docking. cimplot and cimplot3d are pinned
at their commits regenerated against 1.93. ImPlot3D needs its commit
`a56518b` ("fix: line rendering with ImGui v1.93+"), which is after `v0.4`.
ImGuiFileDialog says it supports Dear ImGui 1.92.3; its `master` compiles
against 1.93.0 unchanged with MSVC 2022. MinGW g++ and g++ on Linux are not
verified against 1.93.0 yet.

Tracy is optional and is not fetched by `tools/fetch_third_party.sh`; only a
build with `PSYCHIMGUI_TRACY=1` needs it, and `.gitignore` keeps the clone
out of the repository.

To restore these clones, from the repository root:

    bash tools/fetch_third_party.sh

or by hand:

    cd third_party
    git clone --recurse-submodules https://github.com/cimgui/cimgui
    git -C cimgui checkout c4461a7eadbd17b6a6a8124a8abbf499aba6318d
    git -C cimgui submodule update --init --recursive
    git clone --recurse-submodules https://github.com/cimgui/cimplot
    git -C cimplot checkout 73312c058ec3e10dbe6cb33e0f2145210fb96773
    git -C cimplot submodule update --init --recursive
    git clone --recurse-submodules https://github.com/cimgui/cimplot3d
    git -C cimplot3d checkout f8b28155c8f164c947c95b8ce600ea091a5a9008
    git -C cimplot3d submodule update --init --recursive
    git clone https://github.com/aiekick/ImGuiFileDialog
    git -C ImGuiFileDialog checkout d0e97b2adc3d3452d72c750c7305dc0291acd052

Tracy, only for a profiling build:

    git clone --branch v0.11.1 https://github.com/wolfpld/tracy.git
