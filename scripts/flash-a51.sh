#!/usr/bin/env bash
# Mamuthka linux telepítése Samsung Galaxy A51-re Heimdall-lal (Linuxról).
#
#   sudo ./flash-a51.sh --recovery [mappa]   csak a Mamuthka Recovery (ajánlott):
#                                            utána a recovery Wi-Firől telepíti a rendszert
#   sudo ./flash-a51.sh [mappa]              minden egyszerre: boot + recovery + rendszer
#
# A mappában a GitHub Release fájljai legyenek (boot.img, recovery.img,
# rootfs.img.zst.part*, SHA256SUMS).
set -euo pipefail

MODE=full
if [ "${1:-}" = "--recovery" ]; then MODE=recovery; shift; fi
DIR="${1:-.}"
PART_BOOT="${PART_BOOT:-boot}"
PART_RECOVERY="${PART_RECOVERY:-recovery}"
PART_ROOTFS="${PART_ROOTFS:-userdata}"

die() { echo "HIBA: $*" >&2; exit 1; }
command -v heimdall >/dev/null || die "Telepítsd a Heimdallt: sudo apt install heimdall-flash"

cd "$DIR"
[ -f recovery.img ] || die "Nincs recovery.img a(z) $DIR mappában"

check() {
	[ -f SHA256SUMS ] || return 0
	echo "Ellenőrzőösszegek…"
	grep -E " ($(echo "$@" | sed 's/\./\\./g; s/ /|/g'))$" SHA256SUMS | sha256sum -c - || die "Sérült fájl!"
}

if [ $MODE = full ]; then
	[ -f boot.img ] || die "Nincs boot.img"
	if [ ! -f rootfs.img ]; then
		command -v zstd >/dev/null || die "Telepítsd: sudo apt install zstd"
		if ls rootfs.img.zst.part* >/dev/null 2>&1; then
			echo "rootfs.img kicsomagolása (részekből)…"
			cat rootfs.img.zst.part* | zstd -d -o rootfs.img
		elif [ -f rootfs.img.zst ]; then
			echo "rootfs.img kicsomagolása…"
			zstd -d rootfs.img.zst -o rootfs.img
		else
			die "Nincs rootfs.img (vagy rootfs.img.zst.part*). Csak recovery: $0 --recovery"
		fi
	fi
	check boot.img recovery.img rootfs.img
else
	check recovery.img
fi

cat <<'EOF'

 ┌──────────────────────────────────────────────────────────────┐
 │  Mamuthka linux 🐧 – Samsung Galaxy A51                      │
 ├──────────────────────────────────────────────────────────────┤
 │  1. Kapcsold ki a telefont.                                  │
 │  2. Tartsd nyomva: Hangerő FEL + Hangerő LE,                 │
 │     és közben dugd be az USB-kábelt a gépbe.                 │
 │  3. A figyelmeztető képernyőn nyomd meg röviden a            │
 │     Hangerő FEL gombot → "Downloading..." (Letöltés mód).    │
EOF
if [ $MODE = full ]; then
	echo " │                                                              │"
	echo " │  A TELEFONON LÉVŐ ÖSSZES ADAT TÖRLŐDIK (userdata)!           │"
fi
echo " └──────────────────────────────────────────────────────────────┘"
read -r -p "Ha a telefon Letöltés módban van, írd be: IGEN  > " ok
[ "$ok" = "IGEN" ] || die "Megszakítva."

heimdall detect >/dev/null 2>&1 || die "Nem találom a telefont Letöltés módban (próbáld sudo-val, vagy másik USB-porttal)."

# Egy Letöltés-módbeli munkamenetben csak egy heimdall parancs futhat,
# ezért minden partíciót egyszerre írunk.
if [ $MODE = full ]; then
	echo "Flashelés: boot, recovery, $PART_ROOTFS (több percig tart)…"
	heimdall flash --"$PART_BOOT" boot.img --"$PART_RECOVERY" recovery.img --"$PART_ROOTFS" rootfs.img
	cat <<-EOF

	Kész! A telefon újraindul, és a Mamuthka linux elindul.
	Az első indítás 1-2 perccel tovább tart.
	Ha a képernyő sötét marad: USB-kábelen  ssh mamuthka@172.16.42.1  (jelszó: 1234)
	EOF
else
	echo "Flashelés: recovery…"
	heimdall flash --"$PART_RECOVERY" recovery.img --no-reboot
	cat <<-EOF

	Kész! Most indítsd a telefont a Mamuthka Recovery-be:
	  - tartsd nyomva a Bekapcsoló + Hangerő LE gombot ~7 mp-ig (kilép a Letöltés módból),
	  - amint a kijelző elsötétül, AZONNAL fogd a Bekapcsoló + Hangerő FEL gombot,
	    és tartsd, amíg megjelenik a MAMUTHKA RECOVERY felirat.
	    (Az USB-kábel maradjon bedugva.)
	Ott: "Mamuthka linux telepítése" → Wi-Fi kiválasztása → a rendszer letöltődik és települ.
	EOF
fi

cat <<EOF

Ha a heimdall "partition not found" hibát ad, a PIT-ben nagybetűs a név:
  PART_BOOT=BOOT PART_RECOVERY=RECOVERY PART_ROOTFS=USERDATA $0 $( [ $MODE = recovery ] && echo --recovery ) $DIR
EOF
