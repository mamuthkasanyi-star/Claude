# Mamuthka linux – állapot és átadás (handoff)

> Utolsó frissítés: 2026-10-16. Ez a fájl az aktuális fejlesztési állapotot
> és a nyitott feladatokat rögzíti, hogy egy új session folytatni tudja.
> Minden kódváltozás a `claude/remote-control-wo3lxh` ágon van és fel van
> pusholva; a felhős konténer törlődik, a branch nem.

## Projekt

Saját Linux (Ubuntu 24.04 + Cinnamon, magyar) a Samsung Galaxy A51-re
(SM-A515F, Exynos 9611), postmarketOS A51-kernel alapon. Saját „Mamuthka
Recovery", initramfs, USB-hálózatos hibakeresés. Állapot: **0.1 tesztverzió**,
még nincs igazolt sikeres boot valódi telefonon.

- Repó: https://github.com/mamuthkasanyi-star/Claude
- Ág: `claude/remote-control-wo3lxh` (a teljes projekt itt; a `main` üres)
- Release (flashelhető fájlok): https://github.com/mamuthkasanyi-star/Claude/releases/tag/a51-teszt

## Aktuális probléma: recovery bootloop

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

## Build / release

- Utolsó build: run 38808409340 (`09a47f0`), **conclusion: success**
  (2026-10-15 21:28Z). Az `a51-teszt` release frissült az új recovery.img-mel.
- A workflow minden push után (nem `.md`) automatikusan buildel és az
  `a51-teszt` prerelease-be teszi a fájlokat.

- **Párhuzamos auditok (USB, kijelző, rendszerindítás) javításai:**
  `b_sess=1` a gadget indításához (Samsung dwc3-otg), USB_CONFIGFS_UEVENT ki
  + 0006 patch (Ubuntu Touch A51-port), DECON-hibernáció ki, a rui nem hív
  FBIOBLANK-ot, systemd-firstboot maszkolva + /etc/locale.conf, firmware
  user-helper várakozás ki. Részletek: hibak.txt 44–50.

## Következő lépések (prioritás szerint)

0. **Az új recovery.img a RECOVERY partícióra** (ez javítja a recovery-hurkot),
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
