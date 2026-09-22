# Pinned third-party commits

The dependencies below are git submodules of this repository (see
`.gitmodules`), pinned at the commits in this table. `git clone
--recurse-submodules` fetches them. `tools/fetch_third_party.sh` remains as a
fallback that reproduces the same commits in a checkout without submodules.

| Path | Repository | Commit | Commit date |
|---|---|---|---|
| `third_party/cimgui` | https://github.com/cimgui/cimgui | `125f397e0982fe9466eb0a162de547be5efec849` | 2026-09-14 12:43:54 +0200 |
| `third_party/cimgui/imgui` | https://github.com/ocornut/imgui | `b48d1afbe8ee8b238e2961dc363a949dd7304e23` | 2026-07-31 16:25:00 +0200 |
| `third_party/cimplot` | https://github.com/cimgui/cimplot | `11f13e6cd0f80e83d6409e78592b392967fa7954` | 2026-08-13 12:13:59 +0200 |
| `third_party/cimplot/implot` | https://github.com/epezent/implot | `1351ab2c46d7a05a60f3533047bfba8a953520a1` | 2026-05-10 15:21:10 +0200 |
| `third_party/tracy` | https://github.com/wolfpld/tracy | not cloned | Tracy is optional. See SPEC.md section 9.3. |

Versions: Dear ImGui 1.92.9b (IMGUI_VERSION_NUM 19291), ImPlot 1.1 WIP
(IMPLOT_VERSION_NUM 10100).

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
