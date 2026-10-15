# shellcheck shell=bash
# Közös függvények a build-scriptekhez. Használat: . "$(dirname "$0")/lib.sh"

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-samsung-a51}"
DEVICE_DIR="$ROOT_DIR/devices/$DEVICE"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out/$DEVICE}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/work/$DEVICE}"

[ -d "$DEVICE_DIR" ] || { echo "Ismeretlen eszköz: $DEVICE" >&2; exit 1; }

# shellcheck source=../config/mamuthka.conf
. "$ROOT_DIR/config/mamuthka.conf"
# shellcheck source=../devices/samsung-a51/device.conf
. "$DEVICE_DIR/device.conf"

mkdir -p "$OUT_DIR" "$WORK_DIR"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mHIBA:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
	local c
	for c in "$@"; do
		command -v "$c" >/dev/null 2>&1 || die "Hiányzó program: $c (lásd README: Build-függőségek)"
	done
}

need_root() {
	[ "$(id -u)" = 0 ] || die "Ezt a lépést rootként kell futtatni (sudo)."
}

# Az Ubuntu 24.04 "mkbootimg" csomagja hibás (ModuleNotFoundError: gki),
# ezért a LineageOS mkbootimg.py-t használjuk rögzített commitról.
MKBOOTIMG_REPO="https://github.com/LineageOS/android_system_tools_mkbootimg"
MKBOOTIMG_COMMIT="6f15141210c2a06f947746de99a059a7f1203fe9"   # lineage-22.1
mkbootimg() {
	local dir="$WORK_DIR/tools/mkbootimg"
	if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$MKBOOTIMG_COMMIT" ]; then
		rm -rf "$dir"
		git init -q "$dir"
		git -C "$dir" fetch -q --depth 1 "$MKBOOTIMG_REPO" "$MKBOOTIMG_COMMIT"
		git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
	fi
	python3 "$dir/mkbootimg.py" "$@"
}

# Rögzített commitról tölti le a mkdtboimg.py-t (AOSP libufdt, Apache-2.0).
MKDTBOIMG_URL="https://raw.githubusercontent.com/LineageOS/android_system_libufdt/a64ae44a1b04346271632e3779799f3a17dc3d9a/utils/src/mkdtboimg.py"   # lineage-22.2
mkdtboimg() {
	local tool="$WORK_DIR/tools/mkdtboimg.py"
	if [ ! -f "$tool" ]; then
		mkdir -p "$(dirname "$tool")"
		curl -fsSL "$MKDTBOIMG_URL" -o "$tool.tmp" && mv "$tool.tmp" "$tool"
	fi
	python3 "$tool" "$@"
}
