#!/usr/bin/env bash
# Ubuntu 24.04 + Cinnamon rendszer (rootfs) építése és ext4 képpé alakítása.
# Rootként kell futtatni. x86_64 gépen qemu-user-static emulációt használ,
# arm64 gépen (pl. GitHub ubuntu-24.04-arm runner) natívan fut.
# Kimenet: out/<eszköz>/rootfs.img
. "$(dirname "$0")/lib.sh"

need_root
need debootstrap mkfs.ext4 python3 curl sha512sum

ROOTFS="$WORK_DIR/rootfs"
TARGET_ARCH="$DEVICE_ARCH"
case "$TARGET_ARCH" in
	arm64) MIRROR="$UBUNTU_MIRROR_ARM64"; QEMU=qemu-aarch64-static; HOST_MATCH=aarch64 ;;
	amd64) MIRROR="$UBUNTU_MIRROR_AMD64"; QEMU=""; HOST_MATCH=x86_64 ;;
	*) die "Nem támogatott architektúra: $TARGET_ARCH" ;;
esac
[ "$(uname -m)" = "$HOST_MATCH" ] && QEMU=""

cleanup() {
	for m in dev/pts dev proc sys run; do
		mountpoint -q "$ROOTFS/$m" 2>/dev/null && umount -l "$ROOTFS/$m"
	done
	return 0
}
trap cleanup EXIT

if [ ! -e "$ROOTFS/.stage-debootstrap" ]; then
	log "debootstrap $UBUNTU_SUITE/$TARGET_ARCH ($MIRROR)"
	rm -rf "$ROOTFS"
	mkdir -p "$ROOTFS"
	if [ -n "$QEMU" ]; then
		need "$QEMU"
		[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] ||
			die "Nincs qemu-aarch64 binfmt regisztráció (apt install qemu-user-static binfmt-support)"
		debootstrap --arch="$TARGET_ARCH" --foreign --components=main,universe \
			"$UBUNTU_SUITE" "$ROOTFS" "$MIRROR"
		install -D "$(command -v "$QEMU")" "$ROOTFS/usr/bin/$QEMU"
		chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
	else
		debootstrap --arch="$TARGET_ARCH" --components=main,universe \
			"$UBUNTU_SUITE" "$ROOTFS" "$MIRROR"
	fi
	touch "$ROOTFS/.stage-debootstrap"
fi

log "Fájlok másolása (közös + eszköz overlay)"
cp -a "$ROOT_DIR/rootfs/overlay/." "$ROOTFS/"
[ -d "$DEVICE_DIR/overlay" ] && cp -a "$DEVICE_DIR/overlay/." "$ROOTFS/"
mkdir -p "$ROOTFS/etc/mamuthka"
cp "$ROOT_DIR/rootfs/packages.list" "$ROOTFS/etc/mamuthka/packages.list"
cat > "$ROOTFS/etc/mamuthka/device.env" <<EOF
DEVICE="$DEVICE"
DEVICE_NAME="$DEVICE_NAME"
USB_NET_IP="$USB_NET_IP"
USB_NET_CLIENT_IP="$USB_NET_CLIENT_IP"
ROOTFS_LABEL="$ROOTFS_LABEL"
EOF

log "Grafikák (háttérkép, boot-logó)"
python3 "$ROOT_DIR/scripts/gen-artwork.py" "$ROOTFS" "$SCREEN_WIDTH" "$SCREEN_HEIGHT"

log "Firmware letöltése"
fwdir="$ROOTFS$FIRMWARE_DIR/mx140"
mkdir -p "$fwdir"
: > "$fwdir/mx"   # a postmarketOS csomagban is üres fájl
echo "$FIRMWARE_FILES" | while read -r name sum; do
	[ -n "$name" ] || continue
	if [ ! -f "$fwdir/$name" ] || ! echo "$sum  $fwdir/$name" | sha512sum -c --quiet - 2>/dev/null; then
		curl -fsSL "$FIRMWARE_BASE_URL/$name" -o "$fwdir/$name"
		echo "$sum  $fwdir/$name" | sha512sum -c --quiet - || die "Hibás firmware ellenőrzőösszeg: $name"
	fi
done

log "Rendszer beállítása chrootban (csomagok telepítése – sokáig tart)"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t tmpfs tmpfs "$ROOTFS/run"
# DNS a chrootban: a systemd-resolved csomag a /etc/resolv.conf-ot a
# /run/systemd/resolve/stub-resolv.conf-ra irányítja, ezért azt is feltöltjük.
mkdir -p "$ROOTFS/run/systemd/resolve"
for f in stub-resolv.conf resolv.conf; do
	cat /etc/resolv.conf > "$ROOTFS/run/systemd/resolve/$f"
done
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf.build"
install -m755 "$ROOT_DIR/rootfs/setup.sh" "$ROOTFS/tmp/setup.sh"
chroot "$ROOTFS" /usr/bin/env -i \
	PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 \
	OS_NAME="$OS_NAME" OS_ID="$OS_ID" OS_VERSION="$OS_VERSION" \
	HOSTNAME="$HOSTNAME" USERNAME="$USERNAME" USER_FULLNAME="$USER_FULLNAME" \
	USER_PASSWORD="$USER_PASSWORD" LOCALE="$LOCALE" TIMEZONE="$TIMEZONE" \
	XKB_LAYOUT="$XKB_LAYOUT" CONSOLE_KEYMAP="$CONSOLE_KEYMAP" \
	UBUNTU_SUITE="$UBUNTU_SUITE" MIRROR="$MIRROR" \
	UI_SCALE="$UI_SCALE" GTK_THEME="$GTK_THEME" ICON_THEME="$ICON_THEME" \
	DEVICE_PACKAGES="$DEVICE_PACKAGES" \
	/bin/bash /tmp/setup.sh
rm -f "$ROOTFS/tmp/setup.sh" "$ROOTFS/etc/resolv.conf.build"
cleanup
[ -n "$QEMU" ] && rm -f "$ROOTFS/usr/bin/$QEMU"
rm -f "$ROOTFS/.stage-debootstrap"

log "ext4 kép készítése"
used_mb=$(du -sxm "$ROOTFS" | cut -f1)
img_mb=$(( used_mb * 115 / 100 + 768 ))
rm -f "$OUT_DIR/rootfs.img"
truncate -s "${img_mb}M" "$OUT_DIR/rootfs.img"
# orphan_file: a 4.14-es kernel nem ismeri (e2fsprogs 1.47 alapból bekapcsolja).
# -d: loop-mount nélkül tölti fel a képet. Az első induláskor a rendszer
# a teljes partícióra kiterjeszti (mamuthka-resize-rootfs.service).
mkfs.ext4 -q -F -L "$ROOTFS_LABEL" -O ^orphan_file,^metadata_csum_seed -E root_owner=0:0 \
	-d "$ROOTFS" "$OUT_DIR/rootfs.img"
e2fsck -fy "$OUT_DIR/rootfs.img" >/dev/null || true

# busybox az initramfs-hez (statikus, a rootfs busybox-static csomagjából)
cp "$ROOTFS/usr/bin/busybox" "$OUT_DIR/busybox"

log "Kész: $OUT_DIR/rootfs.img (${img_mb} MiB, ebből ${used_mb} MiB adat)"
