#!/usr/bin/env bash
# initramfs + boot.img összeállítása.
# Bemenet: out/<eszköz>/{Image,dtb.img}, valamint egy statikus arm64 busybox
#          (alapértelmezés: out/<eszköz>/busybox, ezt a build-rootfs.sh készíti).
# Kimenet: out/<eszköz>/boot.img
. "$(dirname "$0")/lib.sh"

need git python3 cpio gzip file

BUSYBOX="${BUSYBOX:-$OUT_DIR/busybox}"
[ -f "$OUT_DIR/Image" ] || die "Nincs kernel: futtasd előbb a build-kernel.sh-t"
[ -f "$OUT_DIR/dtb.img" ] || die "Nincs dtb.img: futtasd előbb a build-kernel.sh-t"
[ -f "$BUSYBOX" ] || die "Nincs statikus busybox: $BUSYBOX (build-rootfs.sh készíti el)"
file -L "$BUSYBOX" 2>/dev/null | grep -q 'statically linked' ||
	log "Figyelem: a busybox nem tűnik statikusnak ($BUSYBOX)"

log "initramfs"
IRD="$WORK_DIR/initramfs"
rm -rf "$IRD"
mkdir -p "$IRD"/{bin,sbin,dev,proc,sys,tmp,etc,config,sysroot,run}
install -m755 "$BUSYBOX" "$IRD/bin/busybox"
install -m755 "$ROOT_DIR/initramfs/init" "$IRD/init"
cat > "$IRD/etc/mamuthka-initramfs.conf" <<EOF
ROOTFS_LABEL="$ROOTFS_LABEL"
ROOTFS_PARTNAME="$HEIMDALL_PARTITION_ROOTFS"
USB_ID_VENDOR="$USB_ID_VENDOR"
USB_ID_PRODUCT="$USB_ID_PRODUCT"
USB_NET_IP="$USB_NET_IP"
USB_NET_CLIENT_IP="$USB_NET_CLIENT_IP"
EOF
(cd "$IRD" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet | gzip -9) > "$OUT_DIR/initramfs.cpio.gz"

log "boot.img (header v$BOOTIMG_HEADER_VERSION)"
mkbootimg \
	--header_version "$BOOTIMG_HEADER_VERSION" \
	--kernel "$OUT_DIR/Image" \
	--ramdisk "$OUT_DIR/initramfs.cpio.gz" \
	--dtb "$OUT_DIR/dtb.img" \
	--base "$BOOTIMG_BASE" \
	--pagesize "$BOOTIMG_PAGESIZE" \
	--kernel_offset "$BOOTIMG_KERNEL_OFFSET" \
	--ramdisk_offset "$BOOTIMG_RAMDISK_OFFSET" \
	--second_offset "$BOOTIMG_SECOND_OFFSET" \
	--tags_offset "$BOOTIMG_TAGS_OFFSET" \
	--dtb_offset "$BOOTIMG_DTB_OFFSET" \
	--os_version "$BOOTIMG_OS_VERSION" \
	--os_patch_level "$BOOTIMG_OS_PATCH_LEVEL" \
	--board "$BOOTIMG_BOARD" \
	--cmdline "$BOOTIMG_CMDLINE" \
	-o "$OUT_DIR/boot.img"

[ "${BOOTIMG_APPEND_SEANDROIDENFORCE:-0}" = 1 ] && printf 'SEANDROIDENFORCE' >> "$OUT_DIR/boot.img"

size=$(stat -c%s "$OUT_DIR/boot.img")
[ "$size" -le "$BOOT_PARTITION_SIZE" ] ||
	die "boot.img túl nagy: $size bájt > $BOOT_PARTITION_SIZE (a partíció csendben levágná)"

log "Kész: $OUT_DIR/boot.img ($size bájt, max $BOOT_PARTITION_SIZE)"
