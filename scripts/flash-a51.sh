#!/usr/bin/env bash
# Mamuthka linux telepítése Samsung Galaxy A51-re Heimdall-lal (Linuxról).
#
#   sudo ./flash-a51.sh --recovery [mappa]   csak a Mamuthka Recovery (ajánlott):
#                                            utána a recovery Wi-Firől telepíti a rendszert
#   sudo ./flash-a51.sh [mappa]              minden egyszerre: boot + recovery + rendszer
#
# A mappában a GitHub Release fájljai legyenek (boot.img, recovery.img,
# rootfs.img.zst.part*, SHA256SUMS).
#
# Teljes flasheléshez (USERDATA, ~4 GiB) a Debian/Ubuntu heimdall 2.0.x NEM
# elég: a telefon írás közben >19 s-ra megáll, a 2.0.2 pedig ~240 MiB-nál
# „Failed to send file part packet”-tel elszáll. Kell: Heimdall 2.2.x
# (git.sr.ht/~grimler/Heimdall) kDefaultTimeoutSend/Receive = 120000-rel
# fordítva, és sparse kép (img2simg, android-sdk-libsparse-utils):
#   sudo HEIMDALL=/út/heimdall ./flash-a51.sh [mappa]
set -euo pipefail

MODE=full
if [ "${1:-}" = "--recovery" ]; then MODE=recovery; shift; fi
DIR="${1:-.}"
# A PIT-nevek; a kiadásban a device.conf HEIMDALL_PARTITION_* értékei (@…@).
PART_BOOT="${PART_BOOT:-@PART_BOOT@}"
PART_RECOVERY="${PART_RECOVERY:-@PART_RECOVERY@}"
PART_ROOTFS="${PART_ROOTFS:-@PART_ROOTFS@}"
# Közvetlenül a repóból futtatva (kitöltetlen @…@): a device.conf értékei.
case "$PART_BOOT" in @*) PART_BOOT=BOOT ;; esac
case "$PART_RECOVERY" in @*) PART_RECOVERY=RECOVERY ;; esac
case "$PART_ROOTFS" in @*) PART_ROOTFS=USERDATA ;; esac

die() { echo "HIBA: $*" >&2; exit 1; }
HEIMDALL="${HEIMDALL:-heimdall}"
command -v "$HEIMDALL" >/dev/null || die "Telepítsd a Heimdallt: sudo apt install heimdall-flash (vagy HEIMDALL=/út/heimdall)"

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
		# A részek listája a manifest.txt-ből (a kiadásban maradhatnak régi,
		# már nem használt részek is, ezeket nem szabad hozzáfűzni).
		parts=""
		[ -f manifest.txt ] && parts="$(awk '$1 ~ /^rootfs\.img\.zst/ {print $1}' manifest.txt | sort)"
		[ -n "$parts" ] || parts="$(ls rootfs.img.zst.part* 2>/dev/null || true)"
		if [ -n "$parts" ]; then
			# shellcheck disable=SC2086
			for p in $parts; do [ -f "$p" ] || die "Hiányzik: $p (töltsd le a kiadásból)"; done
			# shellcheck disable=SC2086
			grep -q "rootfs\.img\.zst" SHA256SUMS 2>/dev/null && check $parts
			echo "rootfs.img kicsomagolása (részekből)…"
			# shellcheck disable=SC2086
			cat $parts | zstd -d -o rootfs.img
		elif [ -f rootfs.img.zst ]; then
			echo "rootfs.img kicsomagolása…"
			zstd -d rootfs.img.zst -o rootfs.img
		else
			die "Nincs rootfs.img (vagy rootfs.img.zst.part*). Csak recovery: $0 --recovery"
		fi
	fi
	check boot.img recovery.img rootfs.img
	# A USERDATA-t sparse képként írjuk: kisebb átvitel, és ezzel ment át
	# kipróbáltan (2026-10-16). Az img2simg az android-sdk-libsparse-utils-ban van.
	ROOTFS_FLASH=rootfs.img
	if command -v img2simg >/dev/null; then
		if [ ! -f rootfs.sparse.img ] || [ rootfs.img -nt rootfs.sparse.img ]; then
			echo "Sparse kép készítése (img2simg)…"
			img2simg rootfs.img rootfs.sparse.img.tmp && mv rootfs.sparse.img.tmp rootfs.sparse.img
		fi
		ROOTFS_FLASH=rootfs.sparse.img
	else
		echo "FIGYELEM: nincs img2simg (sudo apt install android-sdk-libsparse-utils) – nyers képet írok." >&2
	fi
	hv="$("$HEIMDALL" version 2>/dev/null || true)"
	case "$hv" in
		v1.*|v2.0.*|"")
			cat >&2 <<-EOF

			FIGYELEM: heimdall ${hv:-ismeretlen verzió}. A 2.0.x a USERDATA írásánál
			időtúllépéssel elszáll (~240 MiB-nál „Failed to send file part packet”),
			mert a telefon írás közben 20 mp-nél tovább nem válaszol. Használj
			120 s-os timeouttal fordított Heimdall 2.2.x-et (HEIMDALL=/út/heimdall),
			vagy a ./flash-a51.sh --recovery módot (a rendszert a recovery tölti le).
			EOF
			read -r -p "Mégis folytatod ezzel a heimdall-lal? (IGEN/nem) > " go
			[ "$go" = "IGEN" ] || die "Megszakítva."
			;;
	esac
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

"$HEIMDALL" detect >/dev/null 2>&1 || die "Nem találom a telefont Letöltés módban (próbáld sudo-val, vagy másik USB-porttal)."

# Egy Letöltés-módbeli munkamenetben csak egy heimdall parancs futhat,
# ezért minden partíciót egyszerre írunk.
if [ $MODE = full ]; then
	echo "Flashelés: boot, recovery, $PART_ROOTFS (több percig tart)…"
	"$HEIMDALL" flash --"$PART_BOOT" boot.img --"$PART_RECOVERY" recovery.img --"$PART_ROOTFS" "$ROOTFS_FLASH"
	cat <<-EOF

	(Ha a heimdall a „USERDATA upload successful” után a munkamenet zárásánál
	megakad, az ártalmatlan: várj 1-2 percet, utána szakítsd meg Ctrl+C-vel,
	és indítsd újra a telefont: Bekapcsoló + Hangerő LE ~7 mp.)

	Kész! A telefon újraindul, és a Mamuthka linux elindul.
	Az első indítás 1-2 perccel tovább tart.
	Ha a képernyő sötét marad: USB-kábelen  ssh mamuthka@172.16.42.1  (jelszó: 1234)
	EOF
else
	echo "Flashelés: recovery…"
	"$HEIMDALL" flash --"$PART_RECOVERY" recovery.img --no-reboot
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

Ha a heimdall "partition not found" hibát ad, nézd meg a PIT-neveket
($HEIMDALL print-pit --no-reboot), és add meg őket, pl. kisbetűvel:
  sudo PART_BOOT=boot PART_RECOVERY=recovery PART_ROOTFS=userdata $0 $( [ $MODE = recovery ] && echo --recovery ) $DIR
EOF
