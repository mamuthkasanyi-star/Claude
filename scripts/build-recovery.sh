#!/usr/bin/env bash
# Mamuthka Recovery (saját telepítő/javító) – recovery.img
#
#   build-recovery.sh            ramdisk + kép (a rootfs és a kernel is kell)
#   build-recovery.sh --ramdisk  csak ramdisk (rootfs kell) → out/<eszk>/recovery-ramdisk.cpio.gz
#   build-recovery.sh --image    csak kép (kernel + kész ramdisk kell) → out/<eszk>/recovery.img
. "$(dirname "$0")/lib.sh"

PHASE="${1:-all}"
ROOTFS="${ROOTFS:-$WORK_DIR/rootfs}"
RAMDISK="$OUT_DIR/recovery-ramdisk.cpio.gz"

# Dinamikus program + a függő könyvtárai a rootfs-ből (readelf alapján,
# architektúrától függetlenül).
LIBDIRS="lib/aarch64-linux-gnu usr/lib/aarch64-linux-gnu lib usr/lib"
copy_lib() {
	local name="$1" d
	[ -e "$RD/usr/lib/$name" ] && return 0
	for d in $LIBDIRS; do
		if [ -e "$ROOTFS/$d/$name" ]; then
			cp -L "$ROOTFS/$d/$name" "$RD/usr/lib/$name"
			copy_deps "$RD/usr/lib/$name"
			return 0
		fi
	done
	die "Nem találom a könyvtárat: $name"
}
copy_deps() {
	local n
	for n in $(readelf -d "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
		copy_lib "$n"
	done
}
copy_bin() { # forrás (rootfs-en belül) cél (ramdiskben)
	install -Dm755 "$(readlink -f "$ROOTFS/$1")" "$RD/$2"
	copy_deps "$RD/$2"
}

build_ramdisk() {
	need readelf cpio gzip
	[ -x "$ROOTFS/usr/bin/busybox" ] || die "Nincs kész rootfs: $ROOTFS (build-rootfs.sh)"
	RD="$WORK_DIR/recovery-ramdisk"
	rm -rf "$RD"
	mkdir -p "$RD"/{bin,sbin,dev,proc,sys,tmp,run,config,sysroot,mnt,etc/mamuthka,usr/bin,usr/lib,usr/libexec/gnu,usr/share/rui,usr/share/udhcpc}
	ln -s usr/lib "$RD/lib"

	log "Recovery: busybox, rui"
	install -m755 "$ROOTFS/usr/bin/busybox" "$RD/bin/busybox"
	if [ "$(uname -m)" = aarch64 ]; then CC_ARM=gcc; else CC_ARM=aarch64-linux-gnu-gcc; fi
	need "$CC_ARM"
	"$CC_ARM" -O2 -static -Wall -o "$RD/usr/bin/rui" "$ROOT_DIR/recovery/rui/rui.c"

	log "Recovery: eszközök a rootfs-ből"
	cp -L "$ROOTFS/usr/lib/ld-linux-aarch64.so.1" "$RD/usr/lib/"
	copy_bin usr/sbin/e2fsck        usr/bin/e2fsck
	copy_bin usr/sbin/mke2fs        usr/bin/mke2fs
	ln -s mke2fs "$RD/usr/bin/mkfs.ext4"
	copy_bin usr/sbin/resize2fs     usr/bin/resize2fs
	copy_bin usr/bin/zstd           usr/bin/zstd
	copy_bin usr/bin/wget           usr/bin/wget
	copy_bin usr/sbin/wpa_supplicant usr/bin/wpa_supplicant
	copy_bin usr/sbin/wpa_cli       usr/bin/wpa_cli
	copy_bin usr/bin/tar            usr/libexec/gnu/tar
	copy_bin usr/bin/cp             usr/libexec/gnu/cp
	cp "$ROOTFS/etc/mke2fs.conf" "$RD/etc/"
	install -Dm644 "$ROOTFS/etc/ssl/certs/ca-certificates.crt" "$RD/etc/ssl/certs/ca-certificates.crt"
	zcat "$ROOTFS/usr/share/consolefonts/Lat2-TerminusBold32x16.psf.gz" > "$RD/usr/share/rui/font.psf"

	log "Recovery: Wi-Fi firmware"
	mkdir -p "$RD$FIRMWARE_DIR"
	cp -a "$ROOTFS$FIRMWARE_DIR/." "$RD$FIRMWARE_DIR/"

	log "Recovery: scriptek"
	install -m755 "$ROOT_DIR/recovery/init" "$RD/init"
	install -m755 "$ROOT_DIR/recovery/mamuthka-recovery" "$RD/usr/bin/mamuthka-recovery"
	install -m755 "$ROOT_DIR/recovery/udhcpc.script" "$RD/usr/share/udhcpc/default.script"
	install -Dm644 "$ROOT_DIR/initramfs/usbnet.sh" "$RD/lib/mamuthka/usbnet.sh"
	install -Dm644 "$ROOT_DIR/initramfs/watchdog.sh" "$RD/lib/mamuthka/watchdog.sh"
	install -m644 "$ROOT_DIR/recovery/devices.list" "$RD/etc/mamuthka/devices.list"
	cat > "$RD/etc/mamuthka/recovery.conf" <<-EOF
		OS_ID="$OS_ID"
		RELEASE_REPO="$RELEASE_REPO"
		ROOTFS_LABEL="$ROOTFS_LABEL"
		ROOTFS_PARTNAME="$HEIMDALL_PARTITION_ROOTFS"
		USB_ID_VENDOR="$USB_ID_VENDOR"
		USB_ID_PRODUCT="$USB_ID_PRODUCT"
		USB_NET_IP="$USB_NET_IP"
		USB_NET_CLIENT_IP="$USB_NET_CLIENT_IP"
		USB_PRODUCT_NAME="Mamuthka Recovery"
		export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
		export RUI_FONT=/usr/share/rui/font.psf
	EOF
	echo "nameserver 1.1.1.1" > "$RD/etc/resolv.conf"
	printf 'root:x:0:0:root:/root:/bin/sh\n' > "$RD/etc/passwd"
	printf 'root:x:0:\n' > "$RD/etc/group"

	(cd "$RD" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet | gzip -9) > "$RAMDISK"
	log "Recovery ramdisk: $(du -h "$RAMDISK" | cut -f1)"
}

build_image() {
	[ -f "$RAMDISK" ] || die "Nincs recovery ramdisk: $RAMDISK"
	for f in Image dtb.img dtbo.img; do [ -f "$OUT_DIR/$f" ] || die "Hiányzik: $OUT_DIR/$f (build-kernel.sh)"; done
	log "recovery.img"
	# A recovery_dtbo szándékosan kimarad: a bootloader a recovery indulásakor
	# az érintetlen gyári "dtbo" partíciót alkalmazza az alap dtb-re (mint a
	# normál boot.img), így nincs beégetett, board-revízióhoz kötött overlay.
	mkbootimg \
		--header_version "$BOOTIMG_HEADER_VERSION" \
		--kernel "$OUT_DIR/Image" \
		--ramdisk "$RAMDISK" \
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
		-o "$OUT_DIR/recovery.img"
	[ "${BOOTIMG_APPEND_SEANDROIDENFORCE:-0}" = 1 ] && printf 'SEANDROIDENFORCE' >> "$OUT_DIR/recovery.img"
	size=$(stat -c%s "$OUT_DIR/recovery.img")
	[ "$size" -le "$RECOVERY_PARTITION_SIZE" ] ||
		die "recovery.img túl nagy: $size > $RECOVERY_PARTITION_SIZE"
	log "Kész: $OUT_DIR/recovery.img ($size bájt, max $RECOVERY_PARTITION_SIZE)"
}

case "$PHASE" in
	--ramdisk) build_ramdisk ;;
	--image) build_image ;;
	all) build_ramdisk; build_image ;;
	*) die "Ismeretlen kapcsoló: $PHASE" ;;
esac
