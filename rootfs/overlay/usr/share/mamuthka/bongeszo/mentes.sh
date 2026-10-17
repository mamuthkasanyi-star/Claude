#!/bin/sh
# Mamuthka profil mentése (gyorsítótár nélkül) ~/mamuthka-mentes-DATUM.tar.gz-be
set -eu
PROFIL="${MAMUTHKA_PROFIL:-$HOME/.mamuthka/profil}"
[ -d "$PROFIL" ] || { echo "nincs profil: $PROFIL" >&2; exit 1; }
OUT="$HOME/mamuthka-mentes-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$OUT" --exclude='cache2' --exclude='startupCache' --exclude='shader-cache' --exclude='storage/temporary' -C "$(dirname "$PROFIL")" "$(basename "$PROFIL")"
echo "mentve: $OUT"
