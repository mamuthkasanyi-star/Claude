# shellcheck shell=sh
# Az előző indítás nyomainak kimentése és összegzése (bootloop-hibakeresés).
#
# Források (Samsung sec_debug + pstore/ramoops, a DRAM meleg újraindításkor
# megőrzi őket):
#   /proc/reset_reason   – a bootloader által átadott ok (KPON = kernelpánik,
#                          WPON = watchdog, TPON = hő, MPON = gombos reset…)
#   /proc/pwrsrc         – a PMIC be-/kikapcsolási forrásbitjei (WTSR, SMPL…)
#   /proc/auto_comment   – a pánik rövid oka (sec_debug auto comment)
#   /proc/last_kmsg      – az előző kernel naplója
#   /sys/fs/pstore/*     – ramoops: dmesg-ramoops-N (pánik), console-ramoops-0
#
# collect_prev_boot      → $DIAG_DIR (fájlok + osszegzes.txt + panik.txt)
# persist_prev_boot DIR  → a kimentést DIR alá másolja (max. 5 példány marad)
# kmark SZÖVEG           → jelző a kernelnaplóba (a pstore-ban visszaolvasható,
#                          így látszik, melyik lépésnél állt meg az indulás)

DIAG_DIR="${DIAG_DIR:-/tmp/elozo-inditas}"
# Teszteléshez: a források gyökere (üres = valódi /proc, /sys)
DIAG_ROOT="${DIAG_ROOT:-}"

kmark() { echo "mamuthka: $*" > /dev/kmsg 2>/dev/null; }

reset_reason_text() {
	case "$1" in
		KPON) echo "KPON – kernelpánik" ;;
		WPON) echo "WPON – hardveres watchdog" ;;
		TPON) echo "TPON – túlmelegedés (hővédelem)" ;;
		MPON) echo "MPON – kézi reset (gombok)" ;;
		SPON) echo "SPON – SMPL (akku-feszültségesés)" ;;
		DPON) echo "DPON – DVFS/periféria (RST_STAT)" ;;
		PPON) echo "PPON – bekapcsolás" ;;
		RPON) echo "RPON – 'reboot' parancs" ;;
		BPON) echo "BPON – bootloader" ;;
		CPON) echo "CPON – modem (CP) hiba" ;;
		NPON) echo "NPON – normál indítás" ;;
		'')   echo "nincs adat (a bootloader nem adta át)" ;;
		*)    echo "$1" ;;
	esac
}

collect_prev_boot() {
	mkdir -p "$DIAG_DIR"
	[ -n "$DIAG_ROOT" ] || mount -t pstore pstore /sys/fs/pstore 2>/dev/null
	for f in /proc/reset_reason /proc/reset_summary /proc/auto_comment /proc/reset_rwc \
		/proc/pwrsrc /proc/extra /proc/last_kmsg "$DIAG_ROOT"/sys/fs/pstore/*; do
		f="${f#"$DIAG_ROOT"}"
		[ -e "$DIAG_ROOT$f" ] || continue
		cat "$DIAG_ROOT$f" > "$DIAG_DIR/$(echo "${f#/}" | tr / _)" 2>/dev/null
	done
	# Üres fájlok ki
	for f in "$DIAG_DIR"/*; do [ -s "$f" ] || rm -f "$f"; done

	# Hőmérsékletek most (túlmelegedés-gyanú esetén beszédes)
	for z in "$DIAG_ROOT"/sys/class/thermal/thermal_zone*; do
		[ -e "$z/temp" ] && echo "$(cat "$z/type" 2>/dev/null): $(cat "$z/temp" 2>/dev/null)"
	done > "$DIAG_DIR/homerseklet.txt" 2>/dev/null

	reason="$(head -c 40 "$DIAG_DIR/proc_reset_reason" 2>/dev/null | tr -d '\n')"
	logs="$(ls "$DIAG_DIR"/sys_fs_pstore_dmesg* "$DIAG_DIR"/sys_fs_pstore_console* \
		"$DIAG_DIR"/proc_last_kmsg 2>/dev/null)"
	: > "$DIAG_DIR/panik.txt"
	if [ -n "$logs" ]; then
		# Az első végzetes sor és a rá következő 12 (regiszterek, hívási lánc)
		# shellcheck disable=SC2086
		cat $logs | grep -a -m1 -A12 -E \
			'Kernel panic|Internal error|Unable to handle kernel|BUG: |Bad mode|Hard Reset|Watchdog Timer expired|Temperature too high|Attempting .*emergency' \
			> "$DIAG_DIR/panik.txt" 2>/dev/null
		# Az indítás utolsó saját lépése az előző körben
		# shellcheck disable=SC2086
		cat $logs | grep -a 'mamuthka:' | tail -n 1 > "$DIAG_DIR/utolso-lepes.txt" 2>/dev/null
	fi

	{
		echo "Előző újraindulás: $(reset_reason_text "$reason")"
		c="$(head -c 200 "$DIAG_DIR/proc_auto_comment" 2>/dev/null | tr '\n' ' ')"
		[ -n "$c" ] && echo "Ok: $c"
		p="$(head -c 120 "$DIAG_DIR/proc_pwrsrc" 2>/dev/null | tr '\n' ' ')"
		[ -n "$p" ] && echo "PMIC: $p"
		l="$(cat "$DIAG_DIR/utolso-lepes.txt" 2>/dev/null | sed 's/.*mamuthka: //')"
		[ -n "$l" ] && echo "Utolsó lépés: $l"
		if [ -s "$DIAG_DIR/panik.txt" ]; then
			echo
			echo "Pánik az előző indításkor:"
			cut -c1-58 "$DIAG_DIR/panik.txt" | sed 's/^\[[ 0-9.]*\] //'
		elif [ -z "$logs" ]; then
			echo "Nincs előző kernelnapló (pstore/last_kmsg üres)."
		else
			echo "Az előző naplóban nincs pánik-bejegyzés."
		fi
	} > "$DIAG_DIR/osszegzes.txt"
}

# Volt-e összeomlás az előző indításkor? (0 = igen)
prev_boot_crashed() { [ -s "$DIAG_DIR/panik.txt" ]; }

persist_prev_boot() { # célmappa (írható fájlrendszeren)
	[ -d "$DIAG_DIR" ] || return 1
	mkdir -p "$1" 2>/dev/null || return 1
	n=$(ls -d "$1"/inditas-* 2>/dev/null | wc -l)
	d="$1/inditas-$(printf '%03d' $((n + 1)))-$(date +%Y%m%d-%H%M%S 2>/dev/null)"
	cp -a "$DIAG_DIR" "$d" 2>/dev/null || return 1
	# Legfeljebb 5 példány
	ls -d "$1"/inditas-* 2>/dev/null | head -n -5 | while read -r old; do rm -rf "$old"; done
	echo "$d"
}
