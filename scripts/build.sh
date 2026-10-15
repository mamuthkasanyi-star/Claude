#!/usr/bin/env bash
# Teljes build: kernel → rootfs → boot.img → recovery.img → kiadási fájlok.
# Használat:  sudo DEVICE=samsung-a51 ./scripts/build.sh
. "$(dirname "$0")/lib.sh"
need_root

"$ROOT_DIR/scripts/build-kernel.sh"
"$ROOT_DIR/scripts/build-rootfs.sh"
"$ROOT_DIR/scripts/build-bootimg.sh"
"$ROOT_DIR/scripts/build-recovery.sh"
"$ROOT_DIR/scripts/package-release.sh"
