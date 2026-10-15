#!/bin/sh
# Mamuthka – adatgyűjtő a telefonon futó postmarketOS-ről.
#
# A telefonon (pmOS alatt) futtasd:
#   sudo sh pmos-gyujto.sh
# Eredmény: ~/pmos-gyujtes-<dátum>.tar.gz  → ezt töltsd fel a repó
# sajat/pmos/ mappájába (vagy küldd el).
#
# Jelszavakat, Wi-Fi-kulcsokat, SSH-kulcsokat NEM gyűjt.

OUT="${HOME:-/root}/pmos-gyujtes-$(date +%Y%m%d-%H%M)"
mkdir -p "$OUT"
cd "$OUT" || exit 1

run() { # fájlnév parancs...
	f="$1"; shift
	echo "\$ $*" > "$f"
	"$@" >> "$f" 2>&1
}

echo "Gyűjtés: $OUT"

# Rendszer és kernel
run uname.txt uname -a
run cmdline.txt cat /proc/cmdline
run os-release.txt cat /etc/os-release
[ -e /proc/config.gz ] && zcat /proc/config.gz > kernel-config.txt
run deviceinfo.txt sh -c 'cat /usr/share/deviceinfo/deviceinfo /etc/deviceinfo 2>/dev/null'
run dmesg.txt dmesg
run lsmod.txt sh -c 'lsmod 2>/dev/null || cat /proc/modules'

# Csomagok és módosított fájlok
run apk-world.txt cat /etc/apk/world
run apk-installed.txt apk info -v
run apk-audit.txt apk audit --system
run apk-repos.txt cat /etc/apk/repositories

# Szolgáltatások (OpenRC és/vagy systemd)
run openrc.txt rc-status -a
run systemd-enabled.txt systemctl list-unit-files --state=enabled
run systemd-failed.txt systemctl --failed

# Hardver
run partitions.txt sh -c 'cat /proc/partitions; echo; for u in /sys/class/block/*/uevent; do grep -H PARTNAME "$u"; done'
run mounts.txt cat /proc/mounts
run df.txt df -h
run input.txt cat /proc/bus/input/devices
run framebuffer.txt sh -c 'for f in /sys/class/graphics/fb*/*; do [ -f "$f" ] && echo "$f: $(cat "$f" 2>/dev/null | head -c 200)"; done'
run backlight.txt sh -c 'for d in /sys/class/backlight/*; do echo "$d: $(cat $d/brightness)/$(cat $d/max_brightness)"; done'
run power.txt sh -c 'for d in /sys/class/power_supply/*; do echo "== $d"; cat "$d/uevent"; done'
run sound.txt sh -c 'cat /proc/asound/cards; aplay -l 2>/dev/null; amixer 2>/dev/null | head -100'
run iio.txt sh -c 'for d in /sys/bus/iio/devices/*; do echo "== $d $(cat $d/name 2>/dev/null)"; ls "$d"; done'
run net.txt ip addr
run wifi.txt sh -c 'iw dev 2>/dev/null; rfkill list 2>/dev/null'
run nm-connections.txt sh -c 'nmcli -t -f NAME,TYPE connection show 2>/dev/null'
run usb-gadget.txt sh -c 'find /sys/kernel/config/usb_gadget /config/usb_gadget -maxdepth 4 2>/dev/null; ls /sys/class/udc; ls /sys/class/android_usb/android0 2>/dev/null'
run firmware.txt sh -c 'find /lib/firmware -type f | head -300'
run thermal.txt sh -c 'for t in /sys/class/thermal/thermal_zone*; do echo "$t $(cat $t/type) $(cat $t/temp)"; done'
run bluetooth.txt sh -c 'hciconfig -a 2>/dev/null; bluetoothctl list 2>/dev/null'

# Grafika / felület
run xorg.txt sh -c 'ls /etc/X11/xorg.conf.d/ 2>/dev/null; cat /etc/X11/xorg.conf.d/* 2>/dev/null; tail -200 /var/log/Xorg.0.log 2>/dev/null'

# Saját módosítások: /etc változásai, /usr/local, saját scriptek listája
mkdir -p etc-modositott
for f in $(apk audit --system 2>/dev/null | awk '{print $2}'); do
	case "$f" in
		etc/shadow*|etc/gshadow*|etc/ssh/ssh_host_*|etc/NetworkManager/system-connections/*|etc/wpa_supplicant*) continue ;;
	esac
	[ -f "/$f" ] && mkdir -p "etc-modositott/$(dirname "$f")" && cp -p "/$f" "etc-modositott/$f" 2>/dev/null
done
[ -d /usr/local ] && tar -czf usr-local.tar.gz -C / usr/local 2>/dev/null
run home-scripts.txt sh -c 'find /home -maxdepth 4 -type f \( -name "*.sh" -o -name "*.py" -o -path "*/bin/*" -o -path "*/.config/autostart/*" \) 2>/dev/null'

cd .. && tar -czf "$OUT.tar.gz" "$(basename "$OUT")" && rm -rf "$OUT"
echo
echo "Kész: $OUT.tar.gz"
echo "Töltsd fel a repó sajat/pmos/ mappájába (a dokumentumot is: docs/pmos-javitasok.md)."
