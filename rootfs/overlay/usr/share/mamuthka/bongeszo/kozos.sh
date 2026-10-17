# Mamuthka asztali telepítő — közös függvények (POSIX sh; source-olja a telepito-*.sh)
# Várt változók a hívótól: ASSETS (szkriptmappa), GPU_JS (user-gpu-*.js), LAUNCH_ENV (extra env az indítóba)
set -eu
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/mamuthka"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
BIN="$HOME/.local/bin"
PROFIL="${MAMUTHKA_PROFIL:-$HOME/.mamuthka/profil}"
PNAME="Mamuthka"
POLDIRS="/usr/lib/firefox/distribution /usr/lib/firefox-esr/distribution /usr/lib64/firefox/distribution /opt/firefox/distribution"

info() { printf '[mamuthka] %s\n' "$*"; }
hiba() { printf '[mamuthka] HIBA: %s\n' "$*" >&2; exit 1; }

kell_root() {  # parancs futtatása rootként; sudo-t csak szükség esetén kér
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  elif command -v doas >/dev/null 2>&1; then doas "$@"
  else hiba "root jog kell ehhez: $*"; fi
}

firefox_bin() {
  for c in firefox firefox-esr; do
    p=$(command -v "$c" 2>/dev/null || true)
    if [ -n "$p" ]; then echo "$p"; return 0; fi
  done
  return 1
}

firefox_dir() {  # a policies.json célmappája (distribution/)
  for d in $POLDIRS; do
    base=$(dirname "$d")
    if [ -f "$base/application.ini" ] || [ -f "$base/omni.ja" ] || [ -f "$base/browser/omni.ja" ]; then echo "$d"; return 0; fi
  done
  return 1
}

policy_telepit() {
  d=$(firefox_dir) || hiba "nem találom a Firefox telepítési mappáját (distribution/). Snap/flatpak Firefox nem támogatott."
  src="$ASSETS/policies.json"
  if [ -f "$d/policies.json" ] && cmp -s "$src" "$d/policies.json"; then info "policies.json már naprakész ($d)"; return 0; fi
  if [ -f "$d/policies.json" ] && [ ! -f "$d/policies.json.mamuthka-orig" ] && ! grep -q 'addon@darkreader.org' "$d/policies.json"; then
    info "meglévő policies.json mentése: $d/policies.json.mamuthka-orig"
    kell_root cp -p "$d/policies.json" "$d/policies.json.mamuthka-orig"
  fi
  info "policies.json telepítése ($d) — jelszót kérhet"
  kell_root mkdir -p "$d"
  kell_root cp "$src" "$d/policies.json"
  kell_root chmod 644 "$d/policies.json"
  info "FIGYELEM: a policy MINDEN Firefox-profilra érvényes ezen a gépen (nem csak a Mamuthkára)."
}

profil_letrehoz() {
  FF=$(firefox_bin) || hiba "nincs Firefox"
  ini="$HOME/.mozilla/firefox/profiles.ini"
  # Firefox 147+: XDG-mappa (~/.config/mozilla/firefox)
  [ -f "$ini" ] || [ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox/profiles.ini" ] || ini="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox/profiles.ini"
  if [ -f "$ini" ] && grep -q "^Name=$PNAME\$" "$ini"; then
    mkdir -p "$PROFIL"; info "Mamuthka profil már bejegyezve ($PROFIL)"; return 0
  fi
  mkdir -p "$(dirname "$PROFIL")"
  "$FF" --headless -CreateProfile "$PNAME $PROFIL" >/dev/null 2>&1 || true
  mkdir -p "$PROFIL"
  [ -f "$ini" ] || [ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox/profiles.ini" ] || ini="${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox/profiles.ini"
  grep -q "^Name=$PNAME\$" "$ini" 2>/dev/null || info "megjegyzés: a profiles.ini-be bejegyzés nem sikerült; ellenőrizd: about:profiles"
}

profil_beallit() {
  mkdir -p "$PROFIL/chrome"
  if [ -f "$PROFIL/user.js" ] && [ ! -f "$PROFIL/user.js.mamuthka-orig" ] && ! grep -q 'Mamuthka asztali user.js' "$PROFIL/user.js"; then
    cp -p "$PROFIL/user.js" "$PROFIL/user.js.mamuthka-orig"
  fi
  cat "$ASSETS/user.js" "$ASSETS/$GPU_JS" > "$PROFIL/user.js"
  cp "$ASSETS/chrome/userChrome.css" "$ASSETS/chrome/userContent.css" "$PROFIL/chrome/"
  info "user.js + chrome/ a profilban: $PROFIL"
}

kiegeszitok_fajlok() {
  mkdir -p "$DATA"
  cp "$ASSETS/darkreader-settings.json" "$ASSETS/darkreader-globalis-css.txt" "$ASSETS/ublock-szurok.txt" "$DATA/"
  rm -rf "${DATA:?}/tema-kiegeszito"
  cp -r "$ASSETS/extension" "$DATA/tema-kiegeszito"
}

ikonok_asztal() {
  mkdir -p "$APPS" "$BIN" "$ICONS/scalable/apps"
  for s in 16 32 48 64 96 128 256 512; do
    mkdir -p "$ICONS/${s}x${s}/apps"
    cp "$ASSETS/ikonok/mamuthka-$s.png" "$ICONS/${s}x${s}/apps/mamuthka.png"
  done
  cp "$ASSETS/ikonok/mamuthka.svg" "$ICONS/scalable/apps/mamuthka.svg"
  FF=$(firefox_bin) || hiba "nincs Firefox"
  cat > "$BIN/mamuthka" <<EOF
#!/bin/sh
# Mamuthka indító (generálta a telepítő) — külön profil + külön remoting-név, hogy ne keveredjen a sima Firefox-szal
export MOZ_APP_REMOTINGNAME=Mamuthka
${LAUNCH_ENV:-}
exec "$FF" -P "$PNAME" --class Mamuthka --name Mamuthka "\$@"
EOF
  chmod +x "$BIN/mamuthka"
  sed "s#^Exec=mamuthka#Exec=$BIN/mamuthka#" "$ASSETS/mamuthka.desktop" > "$APPS/mamuthka.desktop"
  if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$APPS" 2>/dev/null || true; fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -f -t "$ICONS" 2>/dev/null || true; fi
}

alapertelmezett() {
  if [ "${MAMUTHKA_ALAP:-0}" = 1 ] && command -v xdg-settings >/dev/null 2>&1; then
    xdg-settings set default-web-browser mamuthka.desktop || true
    for m in x-scheme-handler/http x-scheme-handler/https text/html; do xdg-mime default mamuthka.desktop "$m" || true; done
    info "alapértelmezett böngésző: Mamuthka"
  else
    info "alapértelmezett böngészőnek nem állítottam be (kérd: MAMUTHKA_ALAP=1 ./telepito-...sh)"
  fi
}

utolso_uzenet() {
  cat <<EOF

[mamuthka] Kész. Indítás: menüből "Mamuthka", vagy: $BIN/mamuthka
Kézi lépések első indítás után (a Firefox nem engedi automatizálni):
  1. Dark Reader: ikon -> Settings -> Advanced -> Import Settings -> $DATA/darkreader-settings.json
     majd Dev tools -> Dynamic theme editor -> Per site -> "*" -> CSS: $DATA/darkreader-globalis-css.txt tartalma
  2. A kiegészítők (uBlock Origin, Dark Reader) a policy-ból maguktól települnek (internet kell).
  3. Opcionális téma: $DATA/tema-kiegeszito (lásd README).
Eltávolítás: ./eltavolito.sh   Mentés: ./mentes.sh
EOF
}

telepit_mind() {
  [ "$(id -u)" -ne 0 ] || hiba "ne rootként futtasd (a profil a felhasználóé)"
  [ -f "$ASSETS/policies.json" ] || hiba "hiányzik: $ASSETS/policies.json"
  profil_letrehoz
  profil_beallit
  kiegeszitok_fajlok
  ikonok_asztal
  if [ "${MAMUTHKA_NINCS_POLICY:-0}" = 1 ]; then info "policy kihagyva (MAMUTHKA_NINCS_POLICY=1): a kiegészítőket kézzel kell telepíteni"; else policy_telepit; fi
  alapertelmezett
  utolso_uzenet
}
