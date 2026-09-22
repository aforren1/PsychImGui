#!/usr/bin/env bash
#
# Make third_party/ ready to build in a checkout made without submodules.
#
# cimgui and cimplot are submodules of this repository. A clone with
# --recurse-submodules, or `checkout` with `submodules: recursive`, populates
# them and this script does nothing. In a checkout without submodules it clones
# the commits recorded in third_party/PINS.md instead. Run it from the
# repository root, or give that directory as the first argument.
#
#   bash tools/fetch_third_party.sh [repo_root]

set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$root"

pins="third_party/PINS.md"
[ -f "$pins" ] || { echo "fetch_third_party: $pins not found (wrong directory?)" >&2; exit 1; }

if [ -f third_party/cimgui/imgui/imgui.h ] && [ -f third_party/cimplot/implot/implot.h ]; then
    echo "fetch_third_party: third_party is already populated, nothing to do"
    exit 0
fi

# One table row per dependency:
#   | `third_party/cimgui` | https://... | `<40 hex>` | <date> |
pin_field() {   # pin_field <path> <column: url|sha>
    local row
    row="$(grep -F "| \`$1\` |" "$pins" | head -1)"
    [ -n "$row" ] || { echo "fetch_third_party: no PINS.md row for $1" >&2; exit 1; }
    case "$2" in
        url) printf '%s\n' "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}' ;;
        sha) printf '%s\n' "$row" | awk -F'|' '{gsub(/^ +| +$/, "", $4); gsub(/`/, "", $4); print $4}' ;;
    esac
}

clone_pinned() {   # clone_pinned <path>
    local path url sha
    path="$1"
    url="$(pin_field "$path" url)"
    sha="$(pin_field "$path" sha)"
    case "$sha" in
        [0-9a-f]*) : ;;
        *) echo "fetch_third_party: $path has no commit in PINS.md ($sha)" >&2; exit 1 ;;
    esac
    echo "fetch_third_party: $path <- $url @ $sha"
    if [ ! -d "$path/.git" ]; then
        rm -rf "$path"
        git clone --quiet "$url" "$path"
    fi
    git -C "$path" fetch --quiet origin "$sha" 2>/dev/null || git -C "$path" fetch --quiet origin
    git -C "$path" checkout --quiet "$sha"
    git -C "$path" submodule update --quiet --init --recursive
}

mkdir -p third_party
clone_pinned third_party/cimgui
clone_pinned third_party/cimplot

# The nested pins come from each parent's own submodule record, so this only
# reports them. A mismatch means PINS.md and the parent commit disagree.
for nested in third_party/cimgui/imgui third_party/cimplot/implot; do
    want="$(pin_field "$nested" sha || true)"
    have="$(git -C "$nested" rev-parse HEAD)"
    if [ -n "$want" ] && [ "$want" != "$have" ]; then
        echo "fetch_third_party: WARNING $nested is at $have, PINS.md says $want" >&2
    fi
done

test -f third_party/cimgui/imgui/imgui.h
test -f third_party/cimplot/implot/implot.h
echo "fetch_third_party: done"
