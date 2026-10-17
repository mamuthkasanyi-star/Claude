#!/usr/bin/env bash
# Mamuthka linux PC live ISO (amd64): a közös rendszerépítés (build-rootfs.sh,
# DEVICE=pc-amd64) után casper live-képet és hibrid (UEFI + BIOS) ISO-t készít.
# Rootként kell futtatni:  sudo -E DEVICE=pc-amd64 ./scripts/build-pc-live.sh
# Gazdagép-függőségek (Ubuntu 24.04): debootstrap e2fsprogs python3-pil curl
#   squashfs-tools xorriso mtools dosfstools grub-common grub-pc-bin
#   grub-efi-amd64-bin uuid-runtime; az aláírt shim/GRUB-ot (Secure Boot) a
#   szkript maga tölti le (apt-get download, telepítés nélkül).
# Kimenet: out/pc-amd64/<LIVE_ISO_NAME> és .sha256
export DEVICE="${DEVICE:-pc-amd64}"
. "$(dirname "$0")/lib.sh"

[ "$DEVICE_ARCH" = amd64 ] || die "Ez a szkript csak PC-re (amd64) való, nem: $DEVICE"
need_root
need mksquashfs xorriso grub-mkimage mkfs.vfat mcopy mmd mdir uuidgen apt-get dpkg-deb

ROOTFS="$WORK_DIR/rootfs"
ISO="$WORK_DIR/iso"
LMP="$LIVE_MEDIA_PATH"
ISO_FILE="$OUT_DIR/$LIVE_ISO_NAME"
GRUB_PC=/usr/lib/grub/i386-pc
[ -f "$GRUB_PC/boot_hybrid.img" ] || die "Nincs $GRUB_PC (apt install grub-pc-bin)"
[ -d /usr/lib/grub/x86_64-efi ] || die "Nincs /usr/lib/grub/x86_64-efi (apt install grub-efi-amd64-bin)"

if [ "${SKIP_ROOTFS:-0}" != 1 ]; then
	log "Rendszer építése (build-rootfs.sh, $DEVICE)"
	"$ROOT_DIR/scripts/build-rootfs.sh"
fi
# A telefonos ext4 kép és a busybox itt nem kell (a live-rendszer squashfs).
rm -f "$OUT_DIR/rootfs.img" "$OUT_DIR/busybox"

log "Ellenőrzés: a live-rendszer kellékei"
KVER=$(find "$ROOTFS/boot" -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' | sed 's/^vmlinuz-//' | sort -V | tail -n1)
[ -n "$KVER" ] || die "Nincs kernel a rendszerben (linux-image-generic?)"
[ -f "$ROOTFS/boot/initrd.img-$KVER" ] || die "Nincs initrd: initrd.img-$KVER"
if command -v lsinitramfs >/dev/null; then
	lsinitramfs "$ROOTFS/boot/initrd.img-$KVER" > "$WORK_DIR/initrd.lst"
else
	chroot "$ROOTFS" lsinitramfs "/boot/initrd.img-$KVER" > "$WORK_DIR/initrd.lst"
fi
grep -Eq '(^|/)scripts/casper$' "$WORK_DIR/initrd.lst" || die "Az initrd-ben nincs casper (40-pc-live.sh hiba?)"
grep -Eq '(^|/)etc/casper.conf$' "$WORK_DIR/initrd.lst" || die "Az initrd-ben nincs /etc/casper.conf"
grep -Eq '(^|/)plymouth/themes/mamuthka/' "$WORK_DIR/initrd.lst" || log "Figyelem: a mamuthka Plymouth-téma nincs az initrd-ben"
grep -q '^export FLAVOUR="Mamuthka"' "$ROOTFS/etc/casper.conf" || die "Hibás /etc/casper.conf"
! grep -q "^$USERNAME:" "$ROOTFS/etc/passwd" || die "A(z) $USERNAME felhasználó benne maradt (a casper hozza létre)"
[ -x "$ROOTFS/usr/lib/user-setup/user-setup-apply" ] || die "Nincs user-setup"
[ -f "$ROOTFS/usr/share/backgrounds/mamuthka/wallpaper-landscape.png" ] || die "Nincs háttérkép"
log "Kernel: $KVER"

log "ISO-fa összeállítása"
rm -rf "$ISO"
mkdir -p "$ISO/$LMP" "$ISO/.disk" "$ISO/boot/grub/i386-pc" "$ISO/boot/grub/fonts" "$ISO/mamuthka-efi"
cp "$ROOTFS/boot/vmlinuz-$KVER" "$ISO/$LMP/vmlinuz"
cp "$ROOTFS/boot/initrd.img-$KVER" "$ISO/$LMP/initrd"
chroot "$ROOTFS" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO/$LMP/filesystem.manifest"
printf '%s' "$(du -sx --block-size=1 "$ROOTFS" | cut -f1)" > "$ISO/$LMP/filesystem.size"

CASPER_UUID=$(uuidgen)
BUILD_DATE=$(date -u +%Y%m%d)
echo "$OS_NAME $OS_VERSION \"PC live\" - amd64 ($BUILD_DATE)" > "$ISO/.disk/info"
echo "$CASPER_UUID" > "$ISO/.disk/casper-uuid-generic"
# Egyedi jelölőfájl: a GRUB ez alapján találja meg a saját adathordozóját
# (egy másik telepítő-pendrive /.disk/info-ja így nem zavarhat be).
: > "$ISO/.disk/mamuthka-$CASPER_UUID"
cat > "$ISO/$LMP/README.txt" <<EOF
Mamuthka linux $OS_VERSION – PC live (amd64), $BUILD_DATE
Kernel: $KVER
casper-uuid: $CASPER_UUID
Kernelparaméterek: boot=casper live-media-path=$LMP uuid=$CASPER_UUID [persistent]
EOF

log "squashfs (xz – sokáig tart)"
mksquashfs "$ROOTFS" "$ISO/$LMP/filesystem.squashfs" -noappend -comp xz -Xbcj x86 -b 1M \
	-wildcards -e 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*' 'var/tmp/*' -quiet
du -h "$ISO/$LMP/filesystem.squashfs"

log "GRUB-menü"
# Közös menü UEFI-hez és BIOS-hoz. Nincs insmod: az aláírt (Secure Boot)
# GRUB-ban a szükséges modulok be vannak építve, külső modult nem tölt be.
cp /usr/share/grub/unicode.pf2 "$ISO/boot/grub/fonts/" 2>/dev/null || true
KP="boot=casper live-media-path=$LMP uuid=$CASPER_UUID"
cat > "$ISO/boot/grub/grub.cfg" <<EOF
# Mamuthka linux – PC live ($BUILD_DATE)
search --no-floppy --set=root --file /.disk/mamuthka-$CASPER_UUID
set default=0
set timeout=10
set timeout_style=menu
# Ékezetek: Secure Boot alatt az aláírt GRUB (lockdown) nem tölt be
# betűkészletet, a firmware szöveges konzolja pedig nem ismeri az ő/ű/–
# jelet – ilyenkor ö/- jelenik meg helyettük (csak grafikus terminálon ő/–).
set o="ö"; set d="-"
if loadfont /boot/grub/fonts/unicode.pf2; then
	set gfxmode=auto
	insmod all_video
	insmod gfxterm
	if terminal_output gfxterm; then set o="ő"; set d="–"; fi
fi
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "Mamuthka linux \$d él\${o} rendszer" {
	set gfxpayload=keep
	linux /$LMP/vmlinuz $KP quiet splash
	initrd /$LMP/initrd
}
menuentry "Mamuthka linux \$d él\${o} rendszer, változások meg\${o}rzése (writable/casper-rw)" {
	set gfxpayload=keep
	linux /$LMP/vmlinuz $KP persistent quiet splash
	initrd /$LMP/initrd
}
menuentry "Mamuthka linux \$d biztonságos grafika (nomodeset)" {
	linux /$LMP/vmlinuz $KP nopersistent nomodeset
	initrd /$LMP/initrd
}
menuentry "Mamuthka linux \$d szöveges indítás (hibakereséshez)" {
	linux /$LMP/vmlinuz $KP nopersistent systemd.unit=multi-user.target
	initrd /$LMP/initrd
}
if [ "\$grub_platform" = "efi" ]; then
	menuentry "UEFI firmware-beállítások" {
		fwsetup
	}
fi
menuentry "Újraindítás" {
	reboot
}
menuentry "Kikapcsolás" {
	halt
}
EOF

log "BIOS: El Torito + hibrid MBR (grub-pc)"
cp "$GRUB_PC"/*.mod "$GRUB_PC"/*.lst "$ISO/boot/grub/i386-pc/"
grub-mkimage -O i386-pc-eltorito -p /boot/grub -o "$ISO/boot/grub/i386-pc/eltorito.img" \
	biosdisk iso9660 part_msdos part_gpt normal search search_fs_file configfile linux echo test
cp "$GRUB_PC/boot_hybrid.img" "$WORK_DIR/boot_hybrid.img"

log "UEFI: aláírt shim + GRUB (Secure Boot)"
EFIDEB="$WORK_DIR/efi-deb"
rm -rf "$EFIDEB"; mkdir -p "$EFIDEB/x"
(cd "$EFIDEB" && apt-get download shim-signed grub-efi-amd64-signed)
for d in "$EFIDEB"/*.deb; do dpkg-deb -x "$d" "$EFIDEB/x"; done
SHIM="$EFIDEB/x/usr/lib/shim/shimx64.efi.signed.latest"
[ -f "$SHIM" ] || SHIM="$EFIDEB/x/usr/lib/shim/shimx64.efi.signed"
MM="$EFIDEB/x/usr/lib/shim/mmx64.efi"
GCD="$EFIDEB/x/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed"
GRUBX="$EFIDEB/x/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
for f in "$SHIM" "$MM" "$GCD" "$GRUBX"; do [ -f "$f" ] || die "Hiányzik: $f"; done
# A pendrive-telepítő (mamuthka-usb-telepit.sh) innen veszi a saját ESP-je
# fájljait: grubx64.efi = a /EFI/ubuntu prefixű aláírt GRUB.
cp "$SHIM" "$ISO/mamuthka-efi/shimx64.efi"
cp "$MM" "$ISO/mamuthka-efi/mmx64.efi"
cp "$GRUBX" "$ISO/mamuthka-efi/grubx64.efi"
cp "$GCD" "$ISO/mamuthka-efi/gcdx64.efi"
(cd "$EFIDEB" && ls -1 ./*.deb) > "$ISO/mamuthka-efi/FORRAS.txt"

# efi.img: \EFI\BOOT\BOOTX64.EFI = shim, grubx64.efi = gcdx64 (prefix
# /boot/grub). Az efi.img saját /boot/grub/grub.cfg-je a jelölőfájl alapján
# átvált az ISO-fa menüjére (CD-ről és dd-vel írt pendrive-ról is).
EFIIMG="$WORK_DIR/efi.img"
rm -f "$EFIIMG"
efi_kb=2048
for f in "$SHIM" "$MM" "$GCD"; do efi_kb=$(( efi_kb + $(stat -c %s "$f") / 1024 + 64 )); done
truncate -s "${efi_kb}K" "$EFIIMG"
mkfs.vfat -n MAMUTHKAEFI "$EFIIMG" >/dev/null
mmd -i "$EFIIMG" ::/EFI ::/EFI/BOOT ::/boot ::/boot/grub
mcopy -i "$EFIIMG" "$SHIM" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$EFIIMG" "$GCD" ::/EFI/BOOT/grubx64.efi
mcopy -i "$EFIIMG" "$MM" ::/EFI/BOOT/mmx64.efi
cat > "$WORK_DIR/efi-grub.cfg" <<EOF
search --no-floppy --set=root --file /.disk/mamuthka-$CASPER_UUID
set prefix=(\$root)/boot/grub
configfile (\$root)/boot/grub/grub.cfg
EOF
mcopy -i "$EFIIMG" "$WORK_DIR/efi-grub.cfg" ::/boot/grub/grub.cfg
mcopy -i "$EFIIMG" "$WORK_DIR/efi-grub.cfg" ::/EFI/BOOT/grub.cfg
mdir -i "$EFIIMG" -/ :: | tail -n 12 || true
# Az ISO9660-fán is legyen meg (néhány firmware a fát nézi, nem a partíciót).
mkdir -p "$ISO/EFI/BOOT"
cp "$SHIM" "$ISO/EFI/BOOT/BOOTX64.EFI"
cp "$GCD" "$ISO/EFI/BOOT/grubx64.efi"
cp "$MM" "$ISO/EFI/BOOT/mmx64.efi"
cp "$EFIIMG" "$ISO/boot/grub/efi.img"

log "Ellenőrzőösszegek (md5sum.txt)"
(cd "$ISO" && find . -type f ! -name md5sum.txt ! -path './boot/grub/i386-pc/*' -print0 |
	LC_ALL=C sort -z | xargs -0 md5sum > md5sum.txt)

log "Hibrid ISO (xorriso)"
rm -f "$ISO_FILE"
xorriso -as mkisofs -r -V "$LIVE_VOLUME_ID" -o "$ISO_FILE" -J -joliet-long -l -iso-level 3 \
	--grub2-mbr "$WORK_DIR/boot_hybrid.img" \
	--protective-msdos-label -partition_cyl_align off -partition_offset 16 --mbr-force-bootable \
	-append_partition 2 0xef "$EFIIMG" -appended_part_as_gpt \
	-c /boot.catalog \
	-b /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
	-eltorito-alt-boot -e '--interval:appended_partition_2:all::' -no-emul-boot \
	"$ISO"
(cd "$OUT_DIR" && sha256sum "$LIVE_ISO_NAME" > "$LIVE_ISO_NAME.sha256")
cp "$ISO/$LMP/README.txt" "$OUT_DIR/$LIVE_ISO_NAME.txt"
xorriso -indev "$ISO_FILE" -report_el_torito plain -report_system_area plain 2>/dev/null | tail -n 30 || true
log "Kész: $ISO_FILE ($(du -h "$ISO_FILE" | cut -f1)); casper-uuid: $CASPER_UUID"
