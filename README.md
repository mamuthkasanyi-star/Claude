# Mamuthka linux 🐧

Saját Linux-rendszer **Samsung Galaxy A51**-re (SM-A515F, Exynos 9611):
Ubuntu 24.04 alap, **Cinnamon** asztal, magyar nyelv.

> Állapot: **0.1 – első tesztverzió**. Még nem futott valódi telefonon;
> az első indításnál számíts hibákra (lásd [Hibakeresés](#hibakeresés)).

## Mi van benne?

| | |
|---|---|
| Asztal | Cinnamon, sötét téma (Yaru-dark), pingvines háttér és boot-logó, 2× méretezés |
| Bejelentkezés | automatikus (`mamuthka`), képernyőzár a jelszóval |
| Nyelv | magyar felület és billentyűzet, Europe/Budapest |
| Programok | Firefox (nem snap), Szoftverek (GNOME Software + **Flathub**), terminál, git, Python, SSH |
| Érintés | Onboard képernyő-billentyűzet (szövegmezőnél feljön) |
| Kivetítés | Távoli asztal (VNC, menü: *Távoli asztal be/ki*), GNOME Network Displays (Miracast, kísérleti) |
| Rendszer | zram swap, automatikus biztonsági frissítések, USB-hálózat + SSH hibakereséshez |

### Hardver – mi várható?

| Működik várhatóan | Kísérleti / bizonytalan | Nem működik (Androidos zárt driver kell) |
|---|---|---|
| kijelző, érintés, USB-hálózat, Wi-Fi, akkumulátor, gombok, tárhely | hang, automatikus forgatás, Miracast, alvó mód | mobilhálózat (hívás/SMS/adat), kamera, GPU-gyorsítás, ujjlenyomat, NFC, Bluetooth* |

\* A Samsung kernelben a Bluetooth socket kódja ki van ürítve, ezért ki van kapcsolva; javítható patch-csel.
A grafika szoftveresen renderelődik (a Mali GPU-hoz csak androidos driver van), ezért lassabb, mint Androidon.

## Telepítés (Linuxról, Heimdall)

**Előfeltétel:** feloldott bootloader (OEM unlock). Ha már futott rajta postmarketOS, ez megvan.
**A telefonon lévő összes adat törlődik.**

1. Töltsd le a legfrissebb [kiadás](../../releases) összes fájlját egy mappába
   (`boot.img`, `rootfs.img.zst.part00`, `…part01`, …, `flash-a51.sh`, `SHA256SUMS`).
2. Telepítsd az eszközöket:
   ```sh
   sudo apt install heimdall-flash zstd
   ```
3. Indítsd a telefont **Letöltés módba**: kikapcsolva tartsd nyomva a
   *Hangerő fel + Hangerő le* gombot, és közben dugd be az USB-kábelt, majd nyomd meg a *Hangerő fel*-et.
4. Futtasd:
   ```sh
   chmod +x flash-a51.sh
   sudo ./flash-a51.sh
   ```

Az első indulás 1–2 perccel tovább tart. Kezdő jelszó: **1234** – az első
bejelentkezéskor a rendszer kéri a megváltoztatását.

## Hibakeresés

Ha a képernyő sötét marad vagy nem indul a felület, USB-kábelen a telefon hálózati
eszközként jelenik meg:

```sh
ssh mamuthka@172.16.42.1        # jelszó: 1234 (jelszóval csak USB-n lehet belépni)
journalctl -b                    # rendszernapló
cat /var/log/mamuthka-initramfs.log
```

Ha a rendszer el sem indul, az initramfs hibakereső módba lép:
`telnet 172.16.42.1` (napló: `/tmp/init.log`).
Ha mindig az initramfs-ben akarsz megállni egy kicsit, hozd létre a rendszeren az
`/etc/mamuthka-debug` fájlt.

Hibajelentéshez a legjobb: `journalctl -b > naplo.txt` és a `dmesg > dmesg.txt` kimenete.

**Vissza Androidra:** a gyári firmware-t (A515FXXU…) Odinnal vagy Heimdall-lal
kell visszaflashelni.

## Build (saját gépen)

A GitHub Actions minden feltöltés után automatikusan buildel, és a
[`a51-teszt`](../../releases/tag/a51-teszt) kiadásba teszi a fájlokat.
Helyben (Ubuntu 24.04):

```sh
sudo apt install clang lld llvm gcc-aarch64-linux-gnu bc flex bison libssl-dev \
  debootstrap qemu-user-static binfmt-support e2fsprogs python3-pil \
  fonts-dejavu-core cpio zstd curl file git
sudo ./scripts/build.sh            # kernel + rootfs + boot.img + kiadási fájlok
```

Részlépések: `scripts/build-kernel.sh`, `build-rootfs.sh` (root), `build-bootimg.sh`, `package-release.sh`.
Kimenet: `out/samsung-a51/`.

## Felépítés

```
config/mamuthka.conf          közös beállítások (név, felhasználó, nyelv, téma)
devices/samsung-a51/          eszközfüggő rész
  device.conf                 boot.img paraméterek, partíciók, firmware, USB
  kernel/                     kernelkonfig, patchek, DTB-leírók
  overlay/                    eszközfüggő rendszerfájlok (Xorg, NetworkManager)
initramfs/init                busybox init: rendszer megkeresése, USB-hálózat, hibakereső mód
rootfs/                       csomaglista, beállító script, közös rendszerfájlok
scripts/                      build- és flash-scriptek
```

Új eszköz: új `devices/<név>/` mappa saját `device.conf`-fal, kernellel és overlay-jel.

## Források és köszönet

- postmarketOS `samsung-a51` port (Hendra Manudinata) – kernel, patchek, konfig
- map220v – DECON framebuffer javítások
- dima-xd/ubuntu-touch-sm-a515f – valódi készüléken mért boot-paraméterek
- LineageOS universal9611 eszközfák
