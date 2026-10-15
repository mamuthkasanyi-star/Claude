#!/usr/bin/env bash
# Mamuthka linux telepítése Samsung Galaxy A51-re Heimdall-lal (Linuxról).
#
# Használat:  ./flash-a51.sh [mappa]
#   A mappában legyen: boot.img és rootfs.img
#   (vagy a GitHub Release-ből letöltött rootfs.img.zst / rootfs.img.zst.part* fájlok).
#
# FIGYELEM: a telefon userdata partíciója (minden adat) felülíródik!
set -euo pipefail

DIR="${1:-.}"
PART_BOOT="${PART_BOOT:-boot}"
PART_ROOTFS="${PART_ROOTFS:-userdata}"

die() { echo "HIBA: $*" >&2; exit 1; }
command -v heimdall >/dev/null || die "Telepítsd a Heimdallt: sudo apt install heimdall-flash"

cd "$DIR"
[ -f boot.img ] || die "Nincs boot.img a(z) $DIR mappában"

if [ ! -f rootfs.img ]; then
	if ls rootfs.img.zst.part* >/dev/null 2>&1; then
		echo "rootfs.img kicsomagolása (részekből)…"
		command -v zstd >/dev/null || die "Telepítsd: sudo apt install zstd"
		cat rootfs.img.zst.part* | zstd -d -o rootfs.img
	elif [ -f rootfs.img.zst ]; then
		echo "rootfs.img kicsomagolása…"
		command -v zstd >/dev/null || die "Telepítsd: sudo apt install zstd"
		zstd -d rootfs.img.zst -o rootfs.img
	else
		die "Nincs rootfs.img (vagy rootfs.img.zst)"
	fi
fi

if [ -f SHA256SUMS ]; then
	echo "Ellenőrzőösszegek…"
	grep -E ' (boot|rootfs)\.img$' SHA256SUMS | sha256sum -c - || die "Sérült fájl!"
fi

cat <<'EOF'

 ┌──────────────────────────────────────────────────────────────┐
 │  Mamuthka linux 🐧 telepítése – Samsung Galaxy A51          │
 ├──────────────────────────────────────────────────────────────┤
 │  1. Kapcsold ki a telefont.                                  │
 │  2. Tartsd nyomva: Hangerő FEL + Hangerő LE,                 │
 │     és közben dugd be az USB-kábelt a gépbe.                 │
 │  3. A figyelmeztető képernyőn nyomd meg röviden a            │
 │     Hangerő FEL gombot → "Downloading..." (Letöltés mód).    │
 │                                                              │
 │  A TELEFONON LÉVŐ ÖSSZES ADAT TÖRLŐDIK (userdata)!           │
 └──────────────────────────────────────────────────────────────┘
EOF
read -r -p "Ha a telefon Letöltés módban van, írd be: IGEN  > " ok
[ "$ok" = "IGEN" ] || die "Megszakítva."

echo "Telefon keresése…"
heimdall detect >/dev/null 2>&1 || die "Nem találom a telefont Letöltés módban (próbáld sudo-val, vagy másik USB-porttal)."

# Egy Letöltés-módbeli munkamenetben csak egy heimdall parancs futhat,
# ezért mindkét partíciót egyszerre írjuk.
echo "Flashelés: $PART_BOOT ← boot.img, $PART_ROOTFS ← rootfs.img (több percig tart)…"
heimdall flash --"$PART_BOOT" boot.img --"$PART_ROOTFS" rootfs.img

cat <<EOF

Kész! A telefon újraindul, és a Mamuthka linux elindul.
Az első indítás 1-2 perccel tovább tart (a rendszer kiterjeszti magát a teljes tárhelyre).

Ha a képernyő sötét marad: USB-kábelen  ssh mamuthka@172.16.42.1  (jelszó: 1234)

Ha a heimdall "partition not found" hibát ad, a PIT-ben nagybetűs a név:
  PART_BOOT=BOOT PART_ROOTFS=USERDATA $0 $DIR
EOF
