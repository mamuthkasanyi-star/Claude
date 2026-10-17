#!/bin/sh
# Mamuthka telepítő — A51, Mamuthka linux (Ubuntu 24.04, aarch64, Xorg fbdev + llvmpipe).
# Idempotens. A rendszer-Firefox (Mozilla PPA) és a policies.json a rendszerképben
# már benne van, ezért ezt elég MAMUTHKA_NINCS_POLICY=1 mellett, sudo nélkül futtatni
# (az első bejelentkezéskor a /usr/libexec/mamuthka/bongeszo-setup ezt teszi).
ASSETS="$(cd "$(dirname "$0")" && pwd)"
GPU_JS=user-gpu-a51.js.ubuntu-llvmpipe
# Xorg + érintőképernyő; Wayland ki
LAUNCH_ENV='export MOZ_ENABLE_WAYLAND=0 MOZ_USE_XINPUT2=1'
. "$ASSETS/kozos.sh"
firefox_bin >/dev/null || hiba "nincs Firefox (sudo apt install firefox — a Mozilla PPA-ból)"
telepit_mind
