#!/bin/sh
# Mamuthka telepítő — PC, Mamuthka linux live (Ubuntu 24.04, x86_64, Xorg + Mesa).
# Idempotens. A rendszer-Firefox (Mozilla PPA) és a policies.json a rendszerképben
# már benne van, ezért ezt elég MAMUTHKA_NINCS_POLICY=1 mellett, sudo nélkül futtatni
# (az első bejelentkezéskor a /usr/libexec/mamuthka/bongeszo-setup ezt teszi).
# (A közös, A51-es telepito-ubuntu.sh-t írja felül: ott szoftveres WebRender.)
ASSETS="$(cd "$(dirname "$0")" && pwd)"
GPU_JS=user-gpu-pc.js
# Xorg; Wayland ki
LAUNCH_ENV='export MOZ_ENABLE_WAYLAND=0 MOZ_USE_XINPUT2=1'
. "$ASSETS/kozos.sh"
firefox_bin >/dev/null || hiba "nincs Firefox (sudo apt install firefox — a Mozilla PPA-ból)"
telepit_mind
