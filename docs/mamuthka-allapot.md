# Mamuthka linux – állapot és átadás (handoff)

> Utolsó frissítés: 2026-10-17. Ez a fájl az aktuális fejlesztési állapotot
> és a nyitott feladatokat rögzíti, hogy egy új session folytatni tudja.
> Minden kódváltozás a `claude/remote-control-wo3lxh` ágon van és fel van
> pusholva; a felhős konténer törlődik, a branch nem.

## Projekt

Saját Linux (Ubuntu 24.04 + Cinnamon, magyar) a Samsung Galaxy A51-re
(SM-A515F, Exynos 9611), postmarketOS A51-kernel alapon. Saját „Mamuthka
Recovery", initramfs, USB-hálózatos hibakeresés. Állapot: **0.1 tesztverzió**;
a `97bc0e1` óta a rendszer valódi telefonon elindul (systemd, ssh), az asztal
még nem jött fel (javítás: lásd lent, 2026-10-17).

- Repó: https://github.com/mamuthkasanyi-star/Claude
- Ág: `claude/remote-control-wo3lxh` (a teljes projekt itt; a `main` üres)
- Release (flashelhető fájlok): https://github.com/mamuthkasanyi-star/Claude/releases/tag/a51-teszt

## Új kör (2026-10-17 délután, a 8f04dd3 után) – hibak.txt 73–81

A 687aaf2-es forgatás élesben hibás volt (73.). Ebben a körben (flash nélkül,
a telefonon root-írás nélkül):

- **Forgatás (73.):** az fbdev-patch RandR 1.2-es xf86Crtc-réteget kapott
  (egy CRTC, „DSI-1” kimenet, képernyőméret 1080×1080 … 2400×2400). Élő
  próba nem-root teszt-X-szel a :5-ön (/dev/fb0 visszaolvasás): mind a négy
  irány, a muffin-féle sorrend (crtc ki → méret → crtc be) és a hibás méret
  elutasítása rendben. A daemon `xrandr --output DSI-1 --rotate`.
- **Crash → fekete (74.):** metacity a csomagokban + cinnamon-launcher
  auto-újraindítás (5 perc / 3 alkalom).
- **Képernyővédő (75., 77.):** `--hold` D-Bus-szolgáltatás (nincs percenkénti
  kilépés); a cs-backup-locker 2160×4800-as ablaka miatti ~390% CPU →
  GDK_SCALE=1 (élőben mérve: 387% → 4%).
- **Kernel-napló (78., 79.):** 0014 (DPP op-timer hexdump ki), 0015 (SSP
  állapotsor és „[M]” → pr_debug).
- **Egyéb:** grip_sensor ignore (76.), magyar locale mindenhol + sshd
  AcceptEnv ki (80.), kapcsolható llvmpipe-hangolás `/etc/mamuthka/grafika.conf`
  (81., alapból ki).
- **GPU:** pontos hiánylista a 72. pontban (libhybris A13-linkerrel, a gyári
  system-könyvtárak, binder/allocator HAL).

Flash után ellenőrizendő: `xrandr -q` (DSI-1, „normal left inverted right”),
forgatás a telefon elfordításával, képernyővédő alatt `top` (cinnamon < 10%),
`dmesg | grep -c dpp_dump`, `dmesg | grep -c "\[M\]"`, `locale` ssh-n,
`busctl --user status org.cinnamon.ScreenSaver` (percek múlva ugyanaz a PID).

## Új kör (2026-10-17 délelőtt, a 76e2d56 után) – hibak.txt 66–72

A 76e2d56 fut (boot 9 s, 0 failed, oops nincs). Ebben a körben (flash nélkül,
a telefonon csak olvasva):

- **Automatikus forgatás (66.):** patchelt fbdev (RandR 1.1, ShadowFB-forgatás,
  a rootfs-buildben fordul), `mamuthka-sensorhub.service` (CHUB poweron),
  `mamuthka-forgatas` daemon (accel → `xrandr -o`, xinput-mátrix). Élő próba
  nem volt (root kellett volna).
- **Bootlog:** abox extra firmware-ek az initramfs-ben (67.); wlbt hcf/mac.txt
  ártalmatlan (68.); abox_dump kártya ki a WirePlumberből, UCM nyitott (69.);
  fps_et7xx/SSP debug-timer, decon_setcolreg, keyboard-setup, RFKILL (70.).
- **Fogyasztás (71.):** a képernyővédő másodperces órája miatt a cinnamon
  kikapcsolt kijelzővel ~108% CPU-t vitt → a képernyővédő-óra `%H:%M`.
- **GPU (72.):** az EGL-próba nem készült el; az akadályok listája a 72.
  pontban, a `/dev/ion` jogosultsága előkészítve (`70-a51-gpu.rules`).

Flash után ellenőrizendő: `xrandr -q` (a „left/right” a forgatási listában),
`systemctl status mamuthka-sensorhub`, `cat /sys/class/sensors/accelerometer_sensor/raw_data`,
`journalctl --user -b | grep mamuthka-forgatas`, képernyővédő alatt `top`
(cinnamon CPU), `dmesg | grep -c "Direct firmware load"`, `ls -l /dev/rfkill /dev/ion`.

## Aktuális állapot (2026-10-17): a rendszer elindul – asztal, hang, recovery

A `97bc0e1` boot+recovery+rootfs-szel a Mamuthka linux elindul (systemd
running, `ssh mamuthka@172.16.42.1`, kijelző 1080×2400). A leletek és a
javítások részletesen: hibak.txt 56–59. Röviden:

- **Asztal:** az Xorg a vt7-en a `VT_WAITACTIVE`-ban állt, mert a Plymouth a
  tty1-et KD_GRAPHICS módban hagyta (a kernel ilyenkor eldobja a VT-váltást).
  Javítás: `lightdm.service.d/mamuthka-vt.conf` → `/usr/libexec/mamuthka/vt-reset`.
- **Hang/CPU:** hiányzó ABOX-firmware → uevent-vihar (udevd ~100%), wireplumber-
  terhelés. A gyári vendor-firmware-ek (hang-DSP, MFC, Wi-Fi reg DB, log-strings)
  most a buildben töltődnek le a gyári dumpból, sha512-vel ellenőrizve
  (`device.conf: VENDOR_FIRMWARE_FILES`); a repóba blob nem kerül. A v4l2/
  libcamera figyelő ki (`/etc/wireplumber/main.lua.d/51-mamuthka.lua`; ugyanitt
  a hangkártya kikapcsolásának módja, ha a DSP mégsem indulna).
- **Kijelzőre írt kernelhibák:** a bootloader loglevel=4-et fűz a cmdline
  végére → `kernel.printk = 3 4 1 3` (initramfs + sysctl.d).
- **Kernel (0009 patch, audit=0):** a hamis load ~16 és a hung_task-jelzések
  (tzdev-szálak, simpleinteractive) megszűnnek; kauditd-áradat ki.
- **Wi-Fi MAC:** az `efs` partíció csak olvasva (`ro,noload`) az `/efs`-re
  (`mamuthka-efs.service`), a driver onnan veszi a gyári MAC-et.
- **Userspace:** a rootfs-ben az `/etc`, `/usr`… tulajdonosa 1001 volt (a CI
  `cp -a`-ja) → javítva; modules-load/sysctl-hibák, PulseAudio-PipeWire ütközés,
  blueman, jackdbus rendbe téve.
- **Recovery:** a Wi-Fi a busybox-wget miatt „nem csatlakozott” (a GNU wget
  most teljes útvonallal fut); a telnet a házirend-útválasztás miatt csak
  USB-ről érhető el (Wi-Fi-ről nem); felület: kétsoros fejléc, tördelés/„…”,
  görgethető Diagnosztika (húzás, hangerő, Teteje/Alja), akku-% a jobb felső
  sarokban, kijelző ki/be a bekapcsológomb rövid nyomására és 120 s
  tétlenség után; a Wi-Fi a használat után lekapcsol.

### Recovery – kezelés (új)

| Gomb / mozdulat | Hatás |
|---|---|
| Hangerő fel/le | léptetés a menüben; a naplóban lapozás |
| Bekapcsoló hosszan (≥0,6 s) | OK / kiválasztás |
| Bekapcsoló röviden | kijelző ki/be |
| Érintés | választás; sötét kijelzőn csak ébreszt |
| Húzás (napló) | görgetés |

A tétlenségi idő a `RUI_IDLE` környezeti változóval állítható (másodperc,
alapértelmezés 120, 0 = soha).

## GPU-gyorsítás – felderítés és terv (2026-10-17)

**Kernel-oldal (felderítve, működik):** Mali-G72 MP3 (r0p1), Arm kbase
`r38p1-01bet0`, `/dev/mali0` létrejön. A kernelben megvan, ami az Android-
userspace-hez kell: binder/hwbinder/vndbinder, ashmem, ION (Exynos). DRM/KMS
**nincs**: a kijelzőt a DECON fbdev (`/dev/fb0`) hajtja, `/dev/dri` nincs. A
G3D DT-figyelmeztetések ártalmatlanok. **A gyári A515FXXU7HWF1
`libGLES_mali.so` verziója pontosan `r38p1-01bet0`** – egyezik a kernel
kbase-ével, tehát a gyári blob kernel-módosítás nélkül beszélhet a GPU-val.

**Lehetőségek:**

| Út | Mit ad | Kockázat | Becslés |
|---|---|---|---|
| **A) libhybris + gyári Mali-blob** (Halium-szerű: Android 13 vendor-HAL-ok LXC-ben, gralloc/hwcomposer) | Hardveres EGL/GLES. Wayland-héjjal (Phosh/Lomiri) bizonyítottan járható (van Ubuntu Touch A51-port); Xorg/Cinnamon alatt csak `xf86-video-hwcomposer` + glamor-hybris úton, bizonytalan | közepes–magas (Cinnamon/muffin GLX-et vár, a blob csak GLES) | EGL-próba: 3–5 nap; Wayland-asztal: 1–2 hét; Cinnamon gyorsítva: 2–4 hét, nem garantált |
| **B) Mesa panfrost kbase-backenddel** (Icecream95 kísérleti ága) | Nyílt Mesa GL a kbase fölött | magas: 2022 óta nem karbantartott, nincs megjelenítési út DRM nélkül | 4–8+ hét, kutatási munka |
| **C) mainline panfrost DRM** | Tiszta upstream GPU-driver | nagyon magas: 4.14-re backport (drm_sched, io-pgtable), a kbase-t ki kell venni, a DECON-hoz nincs KMS-driver (csak render-node) | hónapok |

**Javaslat:** az A) út, először egy kockázatmentes EGL-próbával (libhybris
`test_egl_configs`/`test_glesv2` a gyári bloból, a rendszer és a kernel
módosítása nélkül). Ha az megy, döntés: Wayland-héj (gyors siker) vagy
Cinnamon-gyorsítás (hosszabb, bizonytalan). Nagy kernelmunka egyik úthoz sem
kell az A) esetén.

**Állapot 2026-10-17 délután:** az EGL-próba nem készült el; a pontos
hiánylista a hibak.txt 72. pontjában (libhybris Android 13-as bionic-
linkerrel, a gyári system/vendor könyvtárai, binder-jogok, gralloc-allocator
HAL). A blob NEEDED-listája: libnativewindow, libutils, libgralloctypes,
liblog, libion_exynos, libbase, libz, libcutils, libhidlbase, libhardware,
libc++, libc, libm, libdl. Kapcsolható llvmpipe-hangolás:
`/etc/mamuthka/grafika.conf` (`LP_NUM_THREADS`, alapból ki).

**Most beépítve (gyors és biztonságos):** Cinnamon animációk és ablakeffektek
ki (`90_mamuthka.gschema.override`) – az llvmpipe-kompozitor kevesebb CPU-t visz.

## Korábbi probléma: recovery bootloop (megoldva)

Tünet: a recovery **kirajzolja a felületet, majd pár másodperc múlva újraindul**
(loop). Mivel a `recovery/init` `while :;` ciklusban fut, ez NEM „kill init"
pánik.

Készülék Letöltés módból beolvasott állapota:
- OEM_LOCK: OFF(U)  → bootloader feloldva
- Current binary: custom  → a bootloader elfogadja és indítja a saját képet (tehát NEM aláírás/zár a hiba)
- KG STATUS: CHECKING (00)  → EUX nyílt készüléken valószínűleg ártalmatlan
- FRP LOCK: OFF, Warranty void: 1  → normális feloldott állapot
- RP SWREV: B:8 K:8 S:8  → anti-rollback 8; **visszaállításhoz csak U8+ gyári firmware!**
- Carrier id: EUX  → eur_open variáns (az a51.cfg eur_open overlay-családja a helyes)
- microSD: NINCS. UART: NINCS.

## GYÖKÉROK MEGTALÁLVA (2026-10-16, pstore-napló)

A telefonról kiolvasott `last_kmsg` / `console-ramoops-0` alapján (a mi
recovery.img-nk indult: kernel 0x1cd5000, ramdisk 0xb7d800):

1. A `09a47f0` commit kivette a `recovery_dtbo`-t a recovery.img-ből. Az S-Boot
   recovery-indításnál viszont NEM a `dtbo` partíciót, hanem a recovery.img
   beágyazott recovery_dtbo-ját alkalmazza → overlay nélküli alap-DT
   (`Machine model: samsung,armv8`).
2. Nincs `lcd_info` → a dsim video módba esik, 0×0 felbontás, a framebuffer
   0 bájt, `failed reserved mem device init: -19` → a `decon_probe` hibaágra fut.
3. A hibaág `kthread_stop()`-ja a vsync-szálra örökre vár (a szál
   `wait_event` feltételében nincs `kthread_should_stop()`) → PID 1 D állapot.
4. A tzdev ACSD-indítása időtúllép → `Kernel panic - not syncing: tzdev:
   iwsock error. result=11` (~5,4 mp) → újraindulás. Ez a „loop".

Ellenpróba: a TWRP recovery.img (recovery_dtbo 476800 B) ugyanezen a telefonon
`Samsung A51 EUR OPEN REV02` modellt, `/s6e3fa9` panelt, 1080 px-et,
parancsmódot és 2592000 B framebuffert kap. A boot.img DT-táblájának
`custom1` mezője (0x000000ff vs. TWRP 0xff000000) nem ok: a gyári boot.img
és a pmOS is 0x000000ff, és a naplóban az UFDT a DTB- és a DTBO-bejegyzést is
megtalálta („DT Overlay Complete!"). Részletek: hibak.txt 51–53.

## 2. hiba (2026-10-16 este, a 038e399 flash után): USB ifname-Oops

A kijelző már működik (a recovery_dtbo-javítás bevált), de 3,7 mp-nél
kernel-Oops → újraindulás. Ok: a config-base `CONFIG_USB_ETH=y` miatt a beépített
**g_ether** már 1,06 mp-nél lefoglalja az UDC-t; a configfs-gadget UDC-bekötése
hibával tér vissza, az ncm sosem bindol (`opts->net == NULL`), és a usbnet.sh
`cat functions/*/ifname` sora `gether_get_ifname(NULL)`-t hív → Oops →
PANIC_ON_OOPS. Javítás: 0008 kernelpatch (NULL-védelem minden u_ether
configfs-segédben), a usbnet.sh és a rootfs usb-network a `/sys/class/net`
alapján keresi az interfészt, és foglalt UDC-nél nem hozza létre a
configfs-gadgetet. Hálózat ezután a g_ether `usb0`-ján (RNDIS) – a gép ezt
már látta. Részletek: hibak.txt 54–55.

## Diagnózis és eddigi lépések (korábbi)

1. Nem aláírás/zár gond (custom elfogadva).
2. Nem korai DTB-pánik (a recovery UI kirajzolódik → kernel+panel jó).
3. **A watchdog-gyanú a kernelforrás alapján elvetve** (2026-10-15 este):
   - `drivers/watchdog/s3c2410_wdt.c`: `tmr_atboot = 0`, a probe
     `s3c2410wdt_stop()`-ot hív → a hardveres watchdog a kernel indulásakor
     LEÁLL, senkinek nem kell pöcögtetnie.
   - `drivers/watchdog/softdog.c` (SEC_DEBUG_SOFTDOG_PWDT): csak akkor indul,
     ha valaki megnyitja a `/dev/watchdogN`-t.
   - A korábbi busybox `watchdog` pöcögtetés tehát maga ÉLESÍTETTE mindkét
     watchdogot (20 mp) – nem védett, hanem új hibaforrás volt; kivéve.
   - Crash key (`sec_crash_key.c`) csak `androidboot.force_upload` mellett
     aktív; a hard-reset-hook (Power+Hangerő− 6 mp) csak hosszú nyomásra.
4. **Marad: kernelpánik.** A Samsung `debug-snapshot` a pánik után AZONNAL
   újraindít (`CONFIG_DEBUG_SNAPSHOT_PANIC_REBOOT`, `exynos_post_panic_exit`
   → `arm_pm_restart`), ezért a pánik szövege sosem látszott, és a
   `PANIC_TIMEOUT` hatástalan volt. Pánikgyanús pont: az USB-gadget
   beállítása (a UI kirajzolása UTÁN, és a gépen sosem jelent meg USB-eszköz).

## Elvégzett és felpusholt változások

- `2f93f15` – `CONFIG_PANIC_TIMEOUT` 5 → 15. `09a47f0` – `recovery_dtbo`
  kivéve a recovery.img-ből. `52695dc` – diagnosztika a recovery-ben
  (reset-ok a képernyőn, kmsg-napló) és watchdog-pöcögtetés (utóbbi azóta
  visszavonva, lásd fent).
- **Bootloop-diagnosztika (ez a commit):**
  - Kernel: `# CONFIG_DEBUG_SNAPSHOT_PANIC_REBOOT is not set`,
    `# …WATCHDOG_RESET is not set`, `CONFIG_PANIC_ON_OOPS=y`,
    `CONFIG_PANIC_TIMEOUT=20`, cmdline `consoleblank=0`. Új patch
    (`0005-debug-snapshot-do-not-spin-forever-after-panic.patch`): a
    `dbg_snapshot_post_panic()` PANIC_REBOOT nélkül nem pörög örökké, hanem
    visszatér → a pánik szövege 20 mp-ig a kijelzőn marad (console=tty0),
    utána újraindul. A pstore/ramoops (`log_pstore`, 2 MiB) és a
    `/proc/last_kmsg` a következő indításkor visszaadja a naplót.
  - `initramfs/diag.sh` (recovery + initramfs): kimenti az előző indítás
    nyomait (`/proc/reset_reason`, `pwrsrc`, `auto_comment`, `last_kmsg`,
    `/sys/fs/pstore/*`), kikeresi a pánik sorait (`panik.txt`), és az
    „Utolsó lépés” jelzőt (`mamuthka: …` sorok a kmsg-ben); az összegzés a
    recovery indítóképernyőjén 20 mp-ig látszik, és a *Diagnosztika*
    menüben is. A nyomokat a telepített rendszer `/var/log/mamuthka/`
    mappájába is menti (recovery és initramfs egyaránt).
  - A recovery NEM köti le többé az fbcon-t, csak `dmesg -n 1`: így a pánik
    szövege a felületre íródik.
  - `/sbin/poweroff|reboot|halt` a ramdiskekben (a hővédelmi
    `orderly_poweroff` ezt hívja).

- **Bootloop gyökérok-javítás (2026-10-16):**
  - `build-recovery.sh`: `--recovery_dtbo dtbo.img` vissza (kötelező), és a
    build leáll, ha a kész recovery.img headerében `recovery_dtbo_size == 0`.
  - `build-bootimg.sh`: a build leáll, ha a boot.img-ben recovery_dtbo van
    (normál indításnál a `dtbo` partíció érvényes, azt nem kell bántani).
  - Kernel: `0007-dpu20-decon-probe-error-path-must-not-hang.patch` – a
    vsync-szál kilép `kthread_stop()`-ra, az err_res ág nem `kfree()`-zi a
    devm-memóriát. Panelhiba esetén kijelző nélkül, de tovább indul.
  - `flash-a51.sh`: `HEIMDALL=` változó, sparse rootfs (img2simg),
    figyelmeztetés 2.0.x heimdall esetén (USERDATA-időtúllépés).

- **USB ifname-Oops javítás (2026-10-16 este):**
  `0008-usb-u_ether-configfs-attributes-must-not-oops-on-unbound-ncm.patch`; `initramfs/usbnet.sh`
  (initramfs + recovery) és `rootfs/.../usb-network` nem olvas ifname-et,
  `/sys/class/net/*/device → …/gadget` alapján keres; foglalt UDC (g_ether)
  esetén a configfs kimarad, a `b_sess=1` mindkét esetben megy.

## Build / release

- Run 38966758573 (`038e399`, recovery_dtbo + 0007): **success**, a kijelző a
  telefonon igazoltan működik.
- Korábbi build: run 38808409340 (`09a47f0`), **conclusion: success**
  (2026-10-15 21:28Z). Az `a51-teszt` release frissült az új recovery.img-mel.
- A workflow minden push után (nem `.md`) automatikusan buildel és az
  `a51-teszt` prerelease-be teszi a fájlokat.

- **Párhuzamos auditok (USB, kijelző, rendszerindítás) javításai:**
  `b_sess=1` a gadget indításához (Samsung dwc3-otg), USB_CONFIGFS_UEVENT ki
  + 0006 patch (Ubuntu Touch A51-port), DECON-hibernáció ki, a rui nem hív
  FBIOBLANK-ot, systemd-firstboot maszkolva + /etc/locale.conf, firmware
  user-helper várakozás ki. Részletek: hibak.txt 44–50.

## Következő lépések (prioritás szerint)

**2026-10-17:** a legújabb release-ből a BOOT (kernel: 0009, audit=0, printk az
initramfs-ben), a RECOVERY (Wi-Fi-, telnet-, felület-javítás) és a USERDATA
(sparse rootfs: asztal, firmware-ek, efs) is írandó; USERDATA csak a 120 s
timeoutos heimdall 2.2.x-szel. Utána ellenőrizni: az asztal feljön-e
(`journalctl -b -u lightdm`, `/var/log/Xorg.0.log`), `dmesg | grep -i calliope`,
`aplay -l`, `cat /proc/loadavg`, `ip link show wlan0` (gyári MAC), a recovery-
ben a Wi-Fi-telepítőút.


0. **A legújabb boot.img a BOOT-ra és recovery.img a RECOVERY-re** (mindkettőben
   benne van az ifname-javítás; a USERDATA-rootfs usb-network szkriptje is
   változott, de az csak a teljes rendszerindításnál számít, az initramfs-hurkot
   a boot.img egyedül javítja). Várható: a gépen RNDIS-eszköz (g_ether) marad,
   `ping 172.16.42.1`.
   Korábbi pont: **Az új recovery.img a RECOVERY partícióra** (ez javítja a recovery-hurkot),
   az új boot.img a BOOT-ra. A DTBO partíciót NEM kell írni (a gyári jó).
   USERDATA csak sparse képpel és 120 s timeoutos heimdall 2.2.x-szel.
   Ellenőrzés: a recovery-ben `dmesg | grep -i "machine model\|resolution"`
   → `REV02`, `xres(1080)`.
1. (korábbi) **Flash-teszt az új boot.img + recovery.img-gel.** Ha a recovery megint
   újraindul: a következő induláskor az indítóképernyő kiírja az okot
   (KPON = kernelpánik, WPON = watchdog, TPON = hő, MPON = gombos reset) és
   a pánik első sorait → **fotó**. (A pánik szövege magán a pánik-képernyőn
   nem látszik: parancsmódú panel, pánikkor az utolsó kép marad.)
   Új gyanú (DECON-audit): kijelző-hibernáció + pmOS-hack → ITMON-pánik;
   a hibernáció ezért ki van kapcsolva.
2. A fotó alapján a tényleges hibás driver javítása (várhatóan USB gadget /
   dwc3, vagy DECON). A `mamuthka: USB …` jelzők mutatják, melyik lépésnél.
3. Ha a rendszer már indul: `journalctl -b` és `/var/log/mamuthka/`.
4. Bluetooth-patch (`hci_sock_create()` ki van ürítve; `# CONFIG_BT is not set`).
5. Base `dtb.img` board-illesztés: ellenőrizve, a `custom1=0xff` a gyárival
   egyezik, a bootloader megtalálja (hibak.txt 51.).

## Egyéb várható hibák (előzetes)

- initramfs nem találja a rootfs-t (`mamuthka_root` label / `userdata`
  PARTNAME) → initramfs debug. A flash-szkript dokumentálja a nagybetűs
  `USERDATA` PIT-felülírást.
- Wi-Fi (SCSC mx140) nem jön fel a recovery-ben → az „A) Wi-Fi" telepítőút
  elhasal; kerülő: „B) minden USB-n".
- Érintés nem reagál (panel-/touch-verzió) → recovery kezelés Hangerő±/Bekapcsoló.
- Fekete képernyő / rossz panel (több panelszállító, csak szoftveres render).
- AVB/vbmeta: a `flash-a51.sh` nem nyúl hozzá; feloldott BL-en általában OK,
  de ha kikényszeríti a verity-t, letiltott `vbmeta.img` kellhet.
- Első rendszerindulás lassú (rootfs ~111 GiB-re tágul a userdata-n).

## Hibakeresési hozzáférés

USB-kábelen a telefon hálózati eszközként jön fel:
- Recovery: `telnet 172.16.42.1` (napló: `/tmp/recovery.log`)
- Rendszer: `ssh mamuthka@172.16.42.1` (jelszó kezdetben 1234), `journalctl -b`
- initramfs (ha a rendszer el sem indul): `telnet 172.16.42.1` (`/tmp/init.log`)

## Megjegyzés az ütemezett ellenőrzésről

A build-figyelő ütemezett ellenőrzés a RÉGI sessionhöz van kötve
(trigger_id: trig_01YFrzYpJu642qKuXQk3qcPJ), az új sessionbe nem jön át, és
nem is szükséges – a build már sikeres.
