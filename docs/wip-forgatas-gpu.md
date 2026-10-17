# WIP: forgatás és GPU (2026-10-17 délután)

Mindkettő félkész, élesben NINCS bekapcsolva.

## Forgatás (hibak.txt 73.)

**Hol tartunk:**
- A driver-patch kész:
  `devices/samsung-a51/overlay/usr/share/mamuthka/src/xf86-video-fbdev-randr-rotation.patch`.
  Ez RandR 1.2-es xf86Crtc-réteg: egy CRTC, „DSI-1” kimenet, a képernyőméret
  1080×1080 … 2400×2400, a forgatást a ShadowFB végzi. A rootfs-buildben
  fordul (`setup.d/50-fbdev-forgatas.sh`).
- A `mamuthka-forgatas` daemon `xrandr --output DSI-1 --rotate …`-t használ.
- Kipróbálva csak nem-root teszt-X-en, a :5-ön (/dev/fb0 visszaolvasással):
  - mind a négy irány helyes;
  - a muffin-féle sorrend (crtc ki → méret → crtc be) helyes;
  - a rossz méretet elutasítja;
  - --off/--auto helyes;
  - nincs crash.
- Az élő :0-n, Cinnamonnal NEM volt kipróbálva, mert a driver cseréje
  root-írást igényel.
- **Alapból KI**, két kapcsoló van:
  - `10-a51-fbdev.conf`: `Option "RandRRotation" "off"`. Ilyenkor a
    patchelt driver a gyári fbdev-vel azonos módon fut, minden új kódút
    `rrRotation` mögött van.
  - `/etc/mamuthka/forgatas.conf`: `enabled=0`.

**Következő lépés (élő próba, root kell, a user futtatja):**
1. A tesztelt driver a telefonon: `/home/mamuthka/xtest/pkg/mod/drivers/fbdev_drv.so`
   (vagy a következő buildből). Telepítés:
   `sudo install -m644 <so> /usr/lib/xorg/modules/drivers/fbdev_drv.so`
   (a gyári `.distrib` néven megvan, a dpkg-divert már létezik).
2. `sudo sed -i 's/"RandRRotation" "off"/"RandRRotation" "on"/' /etc/X11/xorg.conf.d/10-a51-fbdev.conf`,
   `sudo sed -i 's/^enabled=0/enabled=1/' /etc/mamuthka/forgatas.conf`,
   `rm -f ~/.config/mamuthka-forgatas.off`, `sudo systemctl restart lightdm`.
3. Ellenőrzés:
   - `xrandr -q`: DSI-1, „normal left inverted right”;
   - a telefon elfordítása: a kép és az érintés is forog;
   - `journalctl --user -b | grep mamuthka-forgatas`.
4. Visszaállítás, ha baj van:
   - "RandRRotation" "off" (vagy `sudo cp …/fbdev_drv.so.distrib …/fbdev_drv.so`);
   - `sudo systemctl restart lightdm`.
5. Ha az élő próba jó, a két alapértéket "on"/`enabled=1`-re kell állítani a
   repóban.

## GPU (hibak.txt 72.)

**Hol tartunk:** az EGL-próba még nem készült el, a pontos hiánylista a
hibak.txt 72. pontjában van.
- A gyári `libGLES_mali.so` (r38p1-01bet0) megegyezik a kernel kbase-ével.
- A /dev/mali0 és a /dev/ion jogosultsága rendben van.
- A binder-eszközök jogosultsága 0600 root.

**Hiányzik:**
- libhybris arm64-re, Android 13-as bionic-linkerrel (Droidian-ág, android-headers-33);
- a gyári A515FXXU7HWF1 system/vendor könyvtárai (lpunpack super.img → linker64 + 14 NEEDED lib);
- ablakos rajzoláshoz hwservicemanager + gralloc allocator HAL.

**Következő lépés:**
1. libhybris CI-build;
2. user-ként `test_egl` pbufferrel, a rendszer módosítása nélkül.

A kapcsolható llvmpipe-hangolás (`/etc/mamuthka/grafika.conf`,
`LP_NUM_THREADS`) kész, alapból ki van kapcsolva.
