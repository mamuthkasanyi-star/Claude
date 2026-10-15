# pmOS-javítások átvétele a Mamuthka linuxba

Ezt a dokumentumot **te töltöd ki** a laptopon. A `[ ]` jelölőkbe tegyél `x`-et,
a `…` helyére írd a választ. Ahol nem tudod, hagyd üresen – a gyűjtőscript
eredményéből a legtöbb kideríthető.

## 0. Gyors út: automatikus adatgyűjtés

A telefonon, a mostani pmOS alatt:

```sh
# a scriptet a repóból töltsd le: scripts/pmos-gyujto.sh
sudo sh pmos-gyujto.sh
```

Az eredmény (`~/pmos-gyujtes-<dátum>.tar.gz`) mehet a repó **`sajat/pmos/`** mappájába.
Jelszavakat, Wi-Fi-kulcsokat, SSH-kulcsokat a script nem gyűjt.

## 1. Hova töltsd fel a saját kódjaidat?

| Mit | Hova a repóban |
|---|---|
| Ez a kitöltött dokumentum | `docs/pmos-javitasok.md` (felülírod) |
| A gyűjtőscript eredménye | `sajat/pmos/` |
| Kernel-patchek (`.patch`) | `devices/samsung-a51/kernel/patches/` |
| Kernelkonfig módosítások (`CONFIG_...=y` sorok) | `devices/samsung-a51/kernel/mamuthka.config` végére, vagy ide írd a 4. pontba |
| Rendszerfájlok, amik a telepített rendszerbe kellenek (pl. `/etc/...`, `/usr/local/bin/...`) | `sajat/rootfs/` – **ugyanazzal az útvonallal**, pl. `sajat/rootfs/usr/local/bin/sajat.sh` |
| Saját programok, scriptek forrása | `sajat/kod/` |
| Firmware-fájlok | `sajat/firmware/` (+ írd le a 6. pontban, honnan valók) |

A `sajat/rootfs/` tartalmát a build egy az egyben bemásolja az új rendszerbe.

## 2. Alapadatok

- pmOS verzió / csatorna (pl. v24.12, edge): …
- Kernel (`uname -a`): …
- Felület pmOS alatt (Phosh, XFCE, konzol…): …
- Saját buildelt kernel? `[ ]` igen `[ ]` nem – ha igen, forrás/commit: …

## 3. Mi működik most a pmOS-en? (ami nálad ki van próbálva)

| Hardver | Működik | Nem | Javítottad te? Hogyan? |
|---|---|---|---|
| Kijelző | [ ] | [ ] | … |
| Fényerő-állítás | [ ] | [ ] | … |
| Érintés | [ ] | [ ] | … |
| Wi-Fi | [ ] | [ ] | … |
| Bluetooth | [ ] | [ ] | … |
| Hang (hangszóró / fülhallgató / mikrofon) | [ ] | [ ] | … |
| Akkumulátor-kijelzés, töltés | [ ] | [ ] | … |
| USB-hálózat / SSH | [ ] | [ ] | … |
| Gombok (hangerő, bekapcsoló) | [ ] | [ ] | … |
| Gyorsulásmérő / forgatás | [ ] | [ ] | … |
| Közelség-, fényérzékelő | [ ] | [ ] | … |
| Rezgés | [ ] | [ ] | … |
| microSD | [ ] | [ ] | … |
| Kamera | [ ] | [ ] | … |
| Mobilhálózat (hívás, SMS, adat) | [ ] | [ ] | … |
| GPS | [ ] | [ ] | … |
| Ujjlenyomat, NFC | [ ] | [ ] | … |
| Alvó mód / felébresztés | [ ] | [ ] | … |
| GPU-gyorsítás | [ ] | [ ] | … |

## 4. Kernel-módosítások

- Patchek (fájlnév + egy mondat, mit javít):
  - …
- Konfig-változások (`CONFIG_...` sorok, és miért):
  - …
- Kernel-paraméterek (`/proc/cmdline` extra elemei, amik kellettek):
  - …

## 5. Rendszer-módosítások (fájlok, beállítások)

Minden, amit kézzel átírtál vagy létrehoztál (`/etc`, `/usr/local`, szolgáltatások, udev-szabályok…):

| Fájl | Mit csinál / miért kell |
|---|---|
| … | … |

Engedélyezett/letiltott szolgáltatások:
- …

Telepített extra csomagok, amik nélkül valami nem működne:
- …

## 6. Firmware

| Fájl | Hova kell (útvonal) | Honnan van (gyári firmware, dump, saját…) |
|---|---|---|
| … | … | … |

## 7. Saját programok, scriptek, amiket az új rendszerben is használni akarsz

| Név | Mit csinál | Indítás módja (kézi / induláskor / időzítve) | Hova tetted a repóban |
|---|---|---|---|
| … | … | … | … |

## 8. AI / szerver (bigbossfm.hu/aichat)

- Mit csinál a szerver, milyen API-t ad (URL, kérés/válasz formátum)? …
- Kell-e a telefonon kliens? `[ ]` igen `[ ]` nem – mit tudjon: …
- Kell-e kulcs/jelszó? (**ne ide írd** – csak azt, hogy kell-e) …

## 9. Ismert hibák, amiket még nem sikerült megoldani

- …

## 10. Egyéb kérések az új rendszerhez

- …
