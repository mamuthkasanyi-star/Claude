#!/usr/bin/env bash
# Kiadási fájlok: boot.img, rootfs.img.zst (1,9 GiB-os részekre bontva, mert
# a GitHub Release fájlonként legfeljebb 2 GiB-ot enged), flash script, SHA256SUMS.
# Kimenet: out/<eszköz>/release/
. "$(dirname "$0")/lib.sh"
need zstd sha256sum split

REL="$OUT_DIR/release"
rm -rf "$REL"
mkdir -p "$REL"

cp "$OUT_DIR/boot.img" "$REL/"
(cd "$OUT_DIR" && sha256sum boot.img rootfs.img) > "$REL/SHA256SUMS"

log "rootfs.img tömörítése (zstd)"
zstd -T0 -19 --long=27 -q -f "$OUT_DIR/rootfs.img" -o "$REL/rootfs.img.zst"
size=$(stat -c%s "$REL/rootfs.img.zst")
if [ "$size" -gt 2000000000 ]; then
	log "Feldarabolás (${size} bájt)"
	split -b 1900M -d -a 2 "$REL/rootfs.img.zst" "$REL/rootfs.img.zst.part"
	rm "$REL/rootfs.img.zst"
fi

cp "$ROOT_DIR/scripts/flash-a51.sh" "$REL/"
cp "$OUT_DIR/kernel.config" "$REL/kernel-config.txt"
log "Kész: $REL"
ls -la "$REL"
