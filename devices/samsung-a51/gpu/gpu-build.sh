#!/bin/bash
# Mamuthka linux – Galaxy A51 GPU (Mali-G72 MP3, gyári Android-meghajtó a
# libhybris-szel). Lefordítja a (patchelt) libhybris-t, letölti és ellenőrzi
# a gyári Android-könyvtárakat, és mindezt egy kimeneti gyökérbe teszi, amelyet
# a build-rootfs.sh a rootfs-re másol:
#
#   /usr/lib/mamuthka/gpu/lib/            libhybris (EGL/GLES + x11 platform)
#   /usr/lib/mamuthka/gpu/lib/gpu-env-takarito.so
#   /usr/lib/mamuthka/gpu/android/        gyári vendor/system/apex könyvtárak
#   /usr/lib/mamuthka/gpu/10_libhybris.json  glvnd EGL vendor (csak a Cinnamonnak)
#   /vendor/lib64 -> /usr/lib/mamuthka/gpu/android/vendor/lib64
#
# A Cinnamont a /usr/local/bin/cinnamon indító kapcsolja GPU-módba
# (/etc/mamuthka/grafika.conf: GPU=1; GPU=0 = llvmpipe).
#
# Használat: gpu-build.sh <kimeneti gyökér>   (natív arm64-en, Ubuntu 24.04)
# Függőségek: build-essential autoconf automake libtool pkg-config git curl unzip
#   e2fsprogs (debugfs) libwayland-dev libwayland-egl-backend-dev wayland-protocols
#   libx11-dev libx11-xcb-dev libxcb1-dev libxcb-dri3-dev libxcb-present-dev
#   libxext-dev libglvnd-dev
set -euo pipefail

OUT=$(realpath -m "${1:?Használat: gpu-build.sh <kimeneti gyökér>}")
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
. "$HERE/../device.conf"

PREFIX=/usr/lib/mamuthka/gpu
LH_URL=https://github.com/droidian/libhybris
LH_COMMIT=9cfe3f583156881f5971b158011a197ca5a0f6df      # droidian ág
AH_URL=https://github.com/halium/android-headers
AH_COMMIT=217a38e92cc64a96b4d1ac7469f30827d84485d3      # halium-13.0 ág
DUMP_BASE=${VENDOR_FIRMWARE_BASE_URL%/vendor}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

klon() { # <url> <commit> <könyvtár>
	git init -q "$3"
	git -C "$3" fetch -q --depth 1 "$1" "$2"
	git -C "$3" checkout -q FETCH_HEAD
	echo "$(basename "$1") $(git -C "$3" log -1 --format='%H %cd')"
}

echo "==> android-headers + libhybris"
klon "$AH_URL" "$AH_COMMIT" "$WORK/ah"
make -s -C "$WORK/ah" PREFIX="$WORK/ah-inst" install
AH_INC=$(dirname "$(find "$WORK/ah-inst" -name android-config.h | head -1)")
[ -f "$AH_INC/android-config.h" ] || { echo "HIBA: android-headers telepítése" >&2; exit 1; }

klon "$LH_URL" "$LH_COMMIT" "$WORK/lh"
for p in "$HERE"/libhybris-patches/*.patch; do
	echo "patch: $(basename "$p")"
	git -C "$WORK/lh" apply "$p"
done

A=$PREFIX/android
HLDP=$A/vendor/lib64:$A/vendor/lib64/egl:$A/vendor/lib64/hw:$A/apex/com.android.runtime/lib64/bionic:$A/apex/com.android.runtime/lib64:$A/apex/com.android.vndk.v33/lib64:$A/system/lib64
(
	cd "$WORK/lh/hybris"
	NOCONFIGURE=1 ./autogen.sh >/dev/null
	./configure -q --prefix="$PREFIX" --libdir="$PREFIX/lib" --sysconfdir=/etc \
		--enable-wayland --with-android-headers="$AH_INC" \
		--enable-property-cache --enable-experimental --enable-glvnd \
		--enable-arch=arm64 --enable-mali-quirks \
		--with-default-hybris-ld-library-path="$HLDP"
	make -s -j"$(nproc)"
	make -s DESTDIR="$WORK/inst" install
)
mkdir -p "$OUT$PREFIX"
cp -a "$WORK/inst$PREFIX/lib" "$OUT$PREFIX/"
# Csak a futáshoz kellő rész: a fejlécek, .la, pkg-config és tesztprogramok nem.
find "$OUT$PREFIX/lib" -name '*.la' -delete
rm -rf "$OUT$PREFIX/lib/pkgconfig"
mkdir -p "$OUT$PREFIX/bin"
for t in test_egl_configs getprop; do
	[ -x "$WORK/inst$PREFIX/bin/$t" ] && cp -a "$WORK/inst$PREFIX/bin/$t" "$OUT$PREFIX/bin/"
done

echo "==> gpu-env-takarito.so"
gcc -O2 -Wall -shared -fPIC -o "$OUT$PREFIX/lib/gpu-env-takarito.so" "$HERE/gpu-env-takarito.c" -ldl

cat > "$OUT$PREFIX/10_libhybris.json" <<EOF
{
    "file_format_version" : "1.0.0",
    "ICD" : {
        "library_path" : "$PREFIX/lib/libEGL_libhybris.so.0"
    }
}
EOF

echo "==> gyári Android-könyvtárak ($DUMP_BASE)"
mkdir -p "$WORK/dl"
n=0
while read -r src dst sum; do
	case "$src" in ''|'#'*) continue ;; esac
	f="$WORK/dl/$(echo "$src" | tr / _)"
	curl -fsSL --retry 5 --retry-delay 5 -o "$f" "$DUMP_BASE/$src"
	echo "$sum  $f" | sha512sum -c --quiet - || { echo "HIBA: sha512 eltér: $src" >&2; exit 1; }
	case "$src" in
	*.apex)
		img="$WORK/dl/payload.img"
		unzip -p "$f" apex_payload.img > "$img"
		mkdir -p "$OUT$A/$dst"
		for d in lib64 etc; do
			debugfs -R "rdump $d $OUT$A/$dst" "$img" 2>/dev/null
		done
		[ -d "$OUT$A/$dst/lib64" ] || { echo "HIBA: $src kibontása" >&2; exit 1; }
		rm -f "$img" ;;
	*)
		install -D -m 0644 "$f" "$OUT$A/$dst" ;;
	esac
	rm -f "$f"
	n=$((n + 1))
done < "$HERE/blobok.txt"
# Az APEX-ekben lévő, máshová mutató (itt lógó) symlinkek törlése.
find "$OUT$A" -xtype l -delete
# A libhybris gralloc-betöltője property-k híján a „default” modult keresi.
ln -sfn gralloc.exynos9611.so "$OUT$A/vendor/lib64/hw/gralloc.default.so"
# A Mali-meghajtó és a HAL-ok a /vendor/lib64 alatt is keresnek.
mkdir -p "$OUT/vendor"
ln -sfn "$A/vendor/lib64" "$OUT/vendor/lib64"
echo "==> kész: $n gyári fájl, $(du -sh "$OUT$PREFIX" | cut -f1) ($OUT)"
