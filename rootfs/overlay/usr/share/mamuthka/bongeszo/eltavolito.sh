#!/bin/sh
# Mamuthka eltávolítása. A profil megmarad, hacsak nem adod: --profil-torles. A policy-t visszaállítja (sudo csak ehhez).
ASSETS="$(cd "$(dirname "$0")" && pwd)"
GPU_JS=x; LAUNCH_ENV=""
. "$ASSETS/kozos.sh"
TORLES=0; [ "${1:-}" = "--profil-torles" ] && TORLES=1
rm -f "${BIN:?}/mamuthka" "${APPS:?}/mamuthka.desktop"
for s in 16 32 48 64 96 128 256 512; do rm -f "${ICONS:?}/${s}x${s}/apps/mamuthka.png"; done
rm -f "${ICONS:?}/scalable/apps/mamuthka.svg"
rm -rf "${DATA:?}"
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$APPS" 2>/dev/null || true; fi
if d=$(firefox_dir) && [ -f "$d/policies.json" ] && grep -q 'addon@darkreader.org' "$d/policies.json"; then
  info "policies.json visszaállítása — jelszót kérhet"
  if [ -f "$d/policies.json.mamuthka-orig" ]; then kell_root mv "$d/policies.json.mamuthka-orig" "$d/policies.json"
  else kell_root rm -f "$d/policies.json"; fi
fi
if [ "$TORLES" = 1 ]; then
  info "profil törlése: $PROFIL"; rm -rf "${PROFIL:?}"
  info "a profiles.ini-ből a Mamuthka bejegyzést töröld (about:profiles)"
else
  info "a profil megmaradt: $PROFIL (törlés: $0 --profil-torles; előbb: ./mentes.sh)"
fi
info "eltávolítva"
