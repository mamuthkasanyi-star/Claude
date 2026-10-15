#!/usr/bin/env bash
# Teljes build: kernel → rootfs → boot.img → recovery.img → kiadási fájlok.
# Használat:  sudo DEVICE=samsung-a51 ./scripts/build.sh
. "$(dirname "$0")/lib.sh"
need_root

# A kernelt a sudo-t hívó felhasználó fordítja: így a work/…/kernel-out nem lesz
# root tulajdonú, és később a build-kernel.sh sudo nélkül is futtatható.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
	chown "$SUDO_USER" "$OUT_DIR" "$WORK_DIR" "$(dirname "$OUT_DIR")" "$(dirname "$WORK_DIR")"
	sudo -u "$SUDO_USER" env DEVICE="$DEVICE" OUT_DIR="$OUT_DIR" WORK_DIR="$WORK_DIR" \
		${JOBS:+JOBS="$JOBS"} PATH="$PATH" "$ROOT_DIR/scripts/build-kernel.sh"
else
	"$ROOT_DIR/scripts/build-kernel.sh"
fi
"$ROOT_DIR/scripts/build-rootfs.sh"
"$ROOT_DIR/scripts/build-bootimg.sh"
"$ROOT_DIR/scripts/build-recovery.sh"
"$ROOT_DIR/scripts/package-release.sh"
