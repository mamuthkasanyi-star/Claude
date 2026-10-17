#!/bin/bash
# Galaxy A51: futás közbeni képernyőforgatás (xrandr -o left/right/inverted).
# A gyári xf86-video-fbdev 0.5.0 nem ad RandR-forgatást (a DriverFunc nem
# kezeli az RR_GET_INFO/RR_SET_CONFIG-ot), ezért egy kis patch-csel újrafordítjuk:
# a ShadowFB shadow-pixmapját átméretezi, és a shadow-réteg forgatott
# frissítését (shadowUpdateRotatePacked) kapcsolja be. Csak akkor él, ha az
# xorg.conf-ban Option "RandRRotation" "on" – különben a gyári viselkedés.
# Ha a fordítás nem sikerül, a gyári driver marad (a forgatás nem lesz elérhető).
set -euo pipefail
FBV=0.5.0
FBSHA=dcc3d85f378022180e437a9ec00a59b6cb7680ff79c40394d695060af2374699
URL=https://www.x.org/releases/individual/driver/xf86-video-fbdev-$FBV.tar.bz2
PATCH=/usr/share/mamuthka/src/xf86-video-fbdev-randr-rotation.patch
DRV=/usr/lib/xorg/modules/drivers/fbdev_drv.so
B=/tmp/fbdev-build
BDEPS="build-essential pkg-config xserver-xorg-dev patch"

[ -f "$DRV" ] || { echo "!! nincs $DRV – a forgatás kimarad"; exit 0; }
rm -rf "$B"; mkdir -p "$B"
# A build-függőségekből csak az újonnan telepítetteket távolítjuk el utána.
before=$(dpkg-query -W -f='${Package}\n' | sort)
apt-get -y install --no-install-recommends $BDEPS
build() {
	curl -fsSL --retry 3 "$URL" -o "$B/fb.tar.bz2"
	echo "$FBSHA  $B/fb.tar.bz2" | sha256sum -c --quiet -
	tar xf "$B/fb.tar.bz2" -C "$B"
	cd "$B/xf86-video-fbdev-$FBV"
	patch -p1 < "$PATCH"
	./configure --quiet --prefix=/usr --with-xorg-module-dir=/usr/lib/xorg/modules
	make -s -j"$(nproc)"
	test -s src/.libs/fbdev_drv.so
}
if (build); then
	dpkg-divert --local --rename --divert "$DRV.distrib" --add "$DRV" >/dev/null
	install -m644 "$B/xf86-video-fbdev-$FBV/src/.libs/fbdev_drv.so" "$DRV"
	echo "== fbdev_drv.so: RandR-forgatással (a gyári: $DRV.distrib)"
else
	echo "!! a patchelt fbdev nem fordult le – a gyári driver marad"
fi
after=$(dpkg-query -W -f='${Package}\n' | sort)
new=$(comm -13 <(echo "$before") <(echo "$after") | tr '\n' ' ')
[ -n "$new" ] && apt-get -y purge $new >/dev/null
rm -rf "$B"
