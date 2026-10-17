# Mamuthka asztali böngésző (Linux Mint x86_64 + A51 postmarketOS aarch64)

Nem új böngészőmotor: a rendszer Firefoxa fölé tett "Mamuthka" réteg (külön profil, policy, téma, indító), az Android-os Mamuthka (Fennec-alapú) kinézetével és beállításaival.

## Tartalom
| Fájl | Mire jó |
|---|---|
| `policies.json` | Google alapkereső, uBlock Origin + Dark Reader (AMO-ról, kényszerített), uBO egyedi szűrők, telemetria/üdvözlő/első-futás ki |
| `user.js` + `user-gpu-mint.js` / `user-gpu-a51.js` | az Android `prefs.js` asztalra szűrt része + asztali kiegészítések; a telepítő fűzi össze |
| `chrome/userChrome.css`, `userContent.css` | fekete felület, élénk piros (#ff1a1a) hangsúly |
| `extension/` (`theme.json` = ugyanaz) | Firefox-téma manifest (fekete-piros) |
| `ikonok/` | mamut-ikon SVG + PNG 16-512 (a `rokak/mamut.json` kontúrjából, piros mamut fekete alapon) |
| `mamuthka.desktop` | menüelem, http/https/html MIME-kezelő |
| `telepito-mint.sh`, `telepito-a51.sh` | idempotens telepítők; `kozos.sh` a közös rész |
| `mentes.sh`, `eltavolito.sh` | profilmentés (tar.gz); eltávolítás (policy visszaállítással) |
| `darkreader-*`, `ublock-szurok.txt` | a mentett Dark Reader beállítás + globális CSS, uBO szűrők |

## Használat
Másold át a mappát a célgépre, majd (NE rootként):
- Mint: `./telepito-mint.sh`
- A51: `./telepito-a51.sh` (ha nincs Firefox: `apk add firefox-esr`, vagy `FIREFOX_PKG=firefox ./telepito-a51.sh`)

Környezeti változók: `MAMUTHKA_ALAP=1` (alapértelmezett böngésző + MIME), `MAMUTHKA_NINCS_POLICY=1` (nincs sudo/policy), `MAMUTHKA_PROFIL=/út` (profilmappa; alap: `~/.mamuthka/profil`).
Indítás: menü -> Mamuthka, vagy `~/.local/bin/mamuthka` (= `firefox -P Mamuthka`, saját remoting-névvel és ablakosztállyal, így a sima Firefox-szal párhuzamosan fut).
Sudo csak a `policies.json` (a Firefox `distribution/` mappájába) másolásához és a Firefox esetleges telepítéséhez kell.

Első indítás után kézzel (a Firefox nem engedi automatizálni): Dark Reader -> Settings -> Advanced -> Import Settings -> `~/.local/share/mamuthka/darkreader-settings.json`, majd Dev tools -> Dynamic theme editor -> Per site -> `*` -> CSS = `darkreader-globalis-css.txt` tartalma.

## Ismert korlátok
- A policy globális: minden Firefox-profilra érvényes a gépen (kiegészítők kényszerítése, Google kereső, telemetria ki). Ha ez zavar: `MAMUTHKA_NINCS_POLICY=1`, és a kiegészítőket kézzel telepítsd.
- Snap/flatpak Firefox nem támogatott (a policy nem érvényesül); a Mint-szkript megáll snap esetén.
- A "lapok automatikus bezárása 1 hét" asztali Firefoxban nincs; kiegészítő kell hozzá (pl. Auto Tab Discard nem zár, csak szuszpendál) — nincs megoldva.
- A `theme.json`/`extension/` téma aláíratlan: a release Firefox nem telepíti (csak ESR/Developer/Nightly `xpinstall.signatures.required=false`-szal, vagy `about:debugging` ideiglenesen). A téma érdemi része a `userChrome.css` + `user.js`, ami aláírás nélkül is működik.
- A Dark Reader beállításait/globális CSS-ét kézzel kell importálni. uBO egyedi szűrők a policy `3rdparty` részéből jönnek (a szűrők közt van a `ublock-szurok.txt` tartalma).
- Az Android-specifikus prefek (logging.nsHttp, surfacetexture) kimaradtak. A51-en a GPU-erőltetés (webrender.all, force-enabled) szándékosan nincs; Panfrost/Mali alatt tesztelni kell.
- Statikusan ellenőrizve (bash -n/sh -n/dash -n, JSON-parse, desktop-file-validate); élesben még nem futott.

## Mamuthka linux (A51, Ubuntu) — a rendszerképbe építve
A mappa a rendszerben itt van: `/usr/share/mamuthka/bongeszo/` (csak a konfigfájlok; profiladat nincs benne).
- A `policies.json` a build során a `/usr/lib/firefox/distribution/` mappába kerül (a rootfs `setup.sh`).
- Első bejelentkezéskor a `/usr/libexec/mamuthka/bongeszo-setup` (autostart: `mamuthka-bongeszo.desktop`)
  lefuttatja a `telepito-ubuntu.sh`-t `MAMUTHKA_NINCS_POLICY=1 MAMUTHKA_ALAP=1` mellett: profil (`~/.mamuthka/profil`),
  `user.js` (+ `user-gpu-a51.js.ubuntu-llvmpipe`), `chrome/`, `~/.local/bin/mamuthka`, `mamuthka.desktop`, alapértelmezett böngésző.
  A lépés idempotens: a `~/.config/mamuthka/bongeszo.stamp` a konfigfájlok ellenőrzőösszegét tárolja, és csak változáskor fut újra.
- A `/usr/local/bin/mamuthka` indító a panelről is működik az első beállítás előtt: ha még nincs `~/.local/bin/mamuthka`, előbb lefuttatja a beállítást.
- Kézi újrafuttatás: `/usr/libexec/mamuthka/bongeszo-setup --force`.
