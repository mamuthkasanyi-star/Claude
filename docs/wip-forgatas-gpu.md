# WIP: forgatás és GPU (2026-10-17 délután)

**Frissítés 14:30:** a forgatás élő próbája sikeres (hibak.txt 82.), a
repóban alapból BE. Nyitott: irány és érintés user-ellenőrzése. A GPU
lentebb.

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

## GPU (hibak.txt 72.) – 2026-10-17 este: alapból BE

**Kész:** a Cinnamon (Muffin/Cogl GLES2) a telefon GPU-ján rajzol
(Mali-G72, gyári `libGLES_mali.so` r38p1-01bet0, libhybris x11 platform,
XShm-másolás). Élőben kipróbálva: állóban és fekvőben (left/right/normal)
ép a kép; a Cinnamon üresjáratban ~6% CPU (llvmpipe-pal több száz %).

- `devices/samsung-a51/gpu/gpu-build.sh` (CI, rootfs-job): droidian/libhybris
  9cfe3f58 + halium/android-headers halium-13.0 217a38e9, release build a
  `/usr/lib/mamuthka/gpu` alá; a gyári Android-könyvtárak (`blobok.txt`) a
  tadiphone-dumpból sha512-ellenőrzéssel; `/vendor/lib64` symlink.
- Patchek: `0001` (bionic `__ctype_get_mb_cur_max` TLS-szegfault),
  `0002` (x11: az XShm-kép újralétrehozása átméretezéskor – enélkül forgatás
  után szétesett a kép).
- Indító: `/usr/local/bin/cinnamon` → `/usr/lib/mamuthka/gpu/cinnamon-gpu.env`.
  A `gpu-env-takarito.so` az első kirajzolás után törli a GPU-változókat, így
  a Cinnamonból indított programok a Mesa-t használják.

**Kapcsoló:** `/etc/mamuthka/grafika.conf` (felhasználónként
`~/.config/mamuthka/grafika.conf`): `GPU=1` (alap) / `GPU=0` (llvmpipe).
Tartalék: ha a GPU-s Cinnamon összeomlik, a cinnamon-launcher a munkamenet
végéig llvmpipe-pal indítja újra (`MAMUTHKA_GPU_TILTVA=1`), és 90 s-on
belüli újraindításkor az indító is llvmpipe-ra vált.

**Nyitott (nem GPU-hiba):** a zárolt képernyő (cinnamon-screensaver) forgatáskor
nem méreteződik át („Screen rect … and 1 monitor rects … DO NOT add up,
skipping change notification”), így fekvőben csak egy része takar.
