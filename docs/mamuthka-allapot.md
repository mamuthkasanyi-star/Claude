# Mamuthka linux – állapot és átadás (handoff)

> Utolsó frissítés: 2026-10-15. Ez a fájl az aktuális fejlesztési állapotot
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

## Diagnózis és eddigi lépések

1. Nem aláírás/zár gond (custom elfogadva).
2. Nem korai DTB-pánik (a recovery UI kirajzolódik → kernel+panel jó).
3. **Vezető gyanú: hardver-watchdog.** `CONFIG_S3C2410_WATCHDOG=y`,
   `WATCHDOG_HANDLE_BOOT_ENABLED=y`, de a recovery/initramfs scriptekben
   SENKI nem pöcögteti a `/dev/watchdog`-ot → az Exynos bootloader által
   indított watchdog a timeout után kemény resetet ad (fix időzítésű loop).

## Elvégzett és felpusholt változások

- `2f93f15` – Kernel `CONFIG_PANIC_TIMEOUT` 5 → 15 (a `mamuthka.config`-ban;
  felülírja a `config-base`-t). Megj.: watchdog-resetet NEM lassít, csak pánikot.
- `09a47f0` – `recovery_dtbo` kivéve a recovery.img-ből
  (`scripts/build-recovery.sh`). A recovery mostantól a gyári `dtbo`
  partíciót használja, mint a normál boot.img. Ez a `recovery_dtbo`
  board-rev eltérésének kizárására szolgáló TESZT.

## Build / release

- Utolsó build: run 38808409340 (`09a47f0`), **conclusion: success**
  (2026-10-15 21:28Z). Az `a51-teszt` release frissült az új recovery.img-mel.
- A workflow minden push után (nem `.md`) automatikusan buildel és az
  `a51-teszt` prerelease-be teszi a fájlokat.

## Következő lépések (prioritás szerint)

1. **Flash-teszt a mostani (recovery_dtbo nélküli) recovery.img-mel.**
   Ha loopol → tovább a 2-re.
2. **Watchdog-kezelés** (valószínű javítás): a `recovery/init` és a fő
   `initramfs/init` nyissa meg és háttérben pöcögtesse a `/dev/watchdog`-ot
   (vagy magic-close `V`-vel tiltsa; `NOWAYOUT` nincs bekapcsolva). Még NINCS
   implementálva – szándékosan kihagyva, hogy a recovery_dtbo-teszt tiszta legyen.
3. **pstore/ramoops** bekapcsolása a kernelben + a recovery mentse ki a
   `/sys/fs/pstore/console-ramoops`-ot. Ez ad post-mortem naplót microSD/UART
   nélkül – a bootloop valódi okának megfogására.
4. Bluetooth-patch (`hci_sock_create()` ki van ürítve a Samsung kernelben;
   `# CONFIG_BT is not set`).
5. Base `dtb.img` board-illesztés ellenőrzése
   (`devices/samsung-a51/kernel/exynos9611.cfg`: `custom0=0 custom1=0xff`).

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
