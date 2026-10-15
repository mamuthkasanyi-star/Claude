#!/usr/bin/env bash
# Kernel + DTB fordítása (clang, arm64 keresztfordítás).
# Kimenet: out/<eszköz>/Image, dtb.img, dtbo.img, kernel.config, kernel.release
. "$(dirname "$0")/lib.sh"

need git clang make bc flex bison python3 curl aarch64-linux-gnu-as

SRC="$WORK_DIR/kernel-src"
KOUT="$WORK_DIR/kernel-out"
JOBS="${JOBS:-$(nproc)}"

# A .mamuthka-patched jelző csak akkor jön létre, ha minden patch rendben
# felment; nélküle (pl. félbeszakadt futás után) a forrást újra letöltjük.
if [ ! -d "$SRC/.git" ] || [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$KERNEL_COMMIT" ] ||
	[ ! -e "$SRC/.mamuthka-patched" ]; then
	log "Kernelforrás letöltése ($KERNEL_COMMIT)"
	rm -rf "$SRC"
	git init -q "$SRC"
	git -C "$SRC" remote add origin "$KERNEL_REPO"
	git -C "$SRC" fetch -q --depth 1 origin "$KERNEL_COMMIT"
	git -C "$SRC" -c advice.detachedHead=false checkout -q FETCH_HEAD

	log "Patchek alkalmazása"
	for p in "$DEVICE_DIR"/kernel/patches/*.patch; do
		echo "  $(basename "$p")"
		git -C "$SRC" apply "$p"
	done

	# Ugyanaz, mint a postmarketOS-ben: a régi Samsung kód modern clanggal
	# rengeteg figyelmeztetést ad, ezeket ne kezeljük hibaként.
	find "$SRC" -type f \( -name Makefile -o -name Kbuild \) -print0 |
		xargs -0 sed -i -e 's/-Werror-/-W/g' -e 's/-Werror//g'
	touch "$SRC/.mamuthka-patched"
fi

# A beépített firmware-eket (ACPM, érintőpanel) a Makefile a forrásfából várja, de O= esetén csak
# a kimeneti mappában jönne létre – előre elkészítjük (Intel HEX → bináris).
find "$SRC/firmware" -name '*.fw.ihex' | while read -r f; do
	[ -e "${f%.ihex}" ] || objcopy -I ihex -O binary "$f" "${f%.ihex}"
done

# LOCALVERSION= (üres): a sed-del módosított Makefile-ok miatt "piszkos" a git
# fa, és a setlocalversion különben "+" jelet fűzne a verzióhoz.
MAKE=(make -C "$SRC" O="$KOUT" ARCH=arm64 -j"$JOBS" LOCALVERSION=
	CC=clang HOSTCC=clang
	CROSS_COMPILE=aarch64-linux-gnu- CLANG_TRIPLE=aarch64-linux-gnu-
	KBUILD_BUILD_USER=mamuthka KBUILD_BUILD_HOST=mamuthka-linux)

log "Konfiguráció: config-base + mamuthka.config"
mkdir -p "$KOUT"
# merge_config.sh: a mamuthka.config értékei felülírják a bázist (duplikált
# sorok és "override: reassigning" figyelmeztetések nélkül).
(cd "$KOUT" && "$SRC/scripts/kconfig/merge_config.sh" -m -O "$KOUT" \
	"$DEVICE_DIR/kernel/config-base" "$DEVICE_DIR/kernel/mamuthka.config" >/dev/null)
"${MAKE[@]}" olddefconfig >/dev/null

# Ellenőrzés: minden kért opció tényleg bekerült-e.
missing=0
while IFS= read -r line; do
	case "$line" in
		CONFIG_*=*) grep -qxF "$line" "$KOUT/.config" || { echo "  nem érvényesült: $line"; missing=1; } ;;
		"# CONFIG_"*" is not set")
			opt="${line#\# }"; opt="${opt%% *}"
			if grep -q "^$opt=" "$KOUT/.config"; then echo "  nem kapcsolt ki: $opt"; missing=1; fi ;;
	esac
done < "$DEVICE_DIR/kernel/mamuthka.config"
[ "$missing" = 0 ] || log "Figyelem: néhány opció nem érvényesült (függőség hiányzik a kernelben)."

log "Fordítás ($JOBS szálon) – ez 20-60 perc is lehet"
"${MAKE[@]}" Image dtbs

log "DTB kép (dt_table) készítése"
cp "$KOUT/arch/arm64/boot/Image" "$OUT_DIR/Image"
mkdtboimg cfg_create "$OUT_DIR/dtb.img" "$DEVICE_DIR/kernel/exynos9611.cfg" \
	-d "$KOUT/arch/arm64/boot/dts/exynos"
# dtbo.img: csak a recovery.img "recovery_dtbo" részéhez kell (a dtbo partíció
# érintetlen marad).
mkdtboimg cfg_create "$OUT_DIR/dtbo.img" "$DEVICE_DIR/kernel/a51.cfg" \
	-d "$KOUT/arch/arm64/boot/dts/samsung"
cp "$KOUT/.config" "$OUT_DIR/kernel.config"
"${MAKE[@]}" -s --no-print-directory kernelrelease > "$OUT_DIR/kernel.release"

log "Kész: $OUT_DIR/Image ($(du -h "$OUT_DIR/Image" | cut -f1)), dtb.img, kernel $(cat "$OUT_DIR/kernel.release")"
