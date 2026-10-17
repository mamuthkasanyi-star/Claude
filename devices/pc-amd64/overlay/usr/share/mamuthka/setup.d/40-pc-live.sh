#!/bin/bash
# PC live-rendszer (casper): a közös setup.sh A51-es lépéseinek visszavonása
# és a live-indítás előkészítése. A setup.sh hívja a chrootban, a végén.
set -euo pipefail
. /etc/mamuthka/device.env
U=mamuthka

echo "== casper: live-felhasználó, gépnév"
install -m644 /usr/share/mamuthka/pc/casper.conf /etc/casper.conf
# A live-felhasználót induláskor a casper hozza létre (üres jelszó, uid 1000,
# sudoers.d/casper NOPASSWD); a setup.sh által létrehozott (1234-es jelszavú,
# jelszócserét kérő) felhasználó ezért törlődik. A felhasználókép a
# /etc/skel-ből kerül az új otthonba; az AccountsService-beállítás marad.
if id "$U" >/dev/null 2>&1; then
	userdel -r "$U" 2>/dev/null || userdel "$U"
fi
rm -rf "/home/$U"
install -m644 /usr/share/mamuthka/bongeszo/ikonok/mamuthka-256.png /etc/skel/.face
# A casper a user-setup-pal hozza létre a felhasználót; ezekbe a csoportokba
# kerüljön (a nem létezőket a user-setup kihagyja).
echo "user-setup passwd/user-default-groups string adm cdrom dip lpadmin plugdev sudo audio video render input netdev dialout bluetooth autologin nopasswdlogin" |
	debconf-set-selections

echo "== A51-es szolgáltatások ki"
# resize-rootfs (userdata kitöltése), usb-network (172.16.42.1), efs (Samsung
# /efs partíció) a PC-n nem értelmezhető; az ssh alapból ki (live, jelszó nélkül).
for s in mamuthka-resize-rootfs mamuthka-usb-network mamuthka-efs ssh mamuthka-ssh-keygen; do
	systemctl disable "$s.service" >/dev/null 2>&1 || true
done
systemctl disable ssh.socket >/dev/null 2>&1 || true
rm -f /usr/lib/systemd/system/mamuthka-resize-rootfs.service \
	/usr/lib/systemd/system/mamuthka-usb-network.service \
	/usr/lib/systemd/system/mamuthka-efs.service \
	/usr/libexec/mamuthka/resize-rootfs /usr/libexec/mamuthka/usb-network /usr/libexec/mamuthka/mount-efs \
	/usr/lib/udev/rules.d/84-mamuthka-usb-unmanaged.rules \
	/usr/share/applications/mamuthka-reboot-recovery.desktop \
	/usr/share/mamuthka/bongeszo/user-gpu-a51.js.ubuntu-llvmpipe
rmdir /efs 2>/dev/null || true
[ -L /vendor/firmware ] && rm -f /vendor/firmware && rmdir /vendor 2>/dev/null || true

echo "== PC-n kellő szolgáltatások vissza"
# A telefonon le voltak tiltva: konzol-billentyűzet, Bluetooth, mobilmodem,
# firmware-frissítés (LVFS).
systemctl unmask keyboard-setup.service blueman-mechanism.service ModemManager.service \
	fwupd-refresh.timer >/dev/null 2>&1 || true
f=/etc/xdg/autostart/blueman.desktop
[ -f "$f" ] && sed -i '/^Hidden=true$/d' "$f"
# A PC kernele modulokkal jön (i2c_dev, zram), és ismeri a YAMA-t és a
# bubblewrap sysctl-jét: a telefonos /dev/null-átirányítások törlése.
for f in /etc/modules-load.d/fwupd-i2c.conf /etc/modules-load.d/20-zram-generator.conf /etc/sysctl.d/*bubblewrap*.conf; do
	[ -L "$f" ] && [ "$(readlink "$f")" = /dev/null ] && rm -f "$f"
done
[ -f /etc/sysctl.d/10-ptrace.conf ] && sed -i 's/^-\(kernel\.yama\)/\1/' /etc/sysctl.d/10-ptrace.conf

echo "== gschema (PC-felülírás)"
glib-compile-schemas /usr/share/glib-2.0/schemas

echo "== initramfs (casper)"
ls /boot/vmlinuz-* >/dev/null
update-initramfs -u -k all
# Ellenőrzés: a casper-szkriptek benne vannak-e az initrd-ben.
for i in /boot/initrd.img-*; do
	lsinitramfs "$i" | grep -q 'scripts/casper$' || { echo "!! $i: nincs benne a casper" >&2; exit 1; }
done
echo "== 40-pc-live.sh kész"
