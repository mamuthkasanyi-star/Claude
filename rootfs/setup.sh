#!/bin/bash
# A rendszer beállítása a chrootban. A build-rootfs.sh hívja, a változókat
# környezeti változóként kapja (config/mamuthka.conf, devices/*/device.conf).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

rm -f /etc/resolv.conf
cp /etc/resolv.conf.build /etc/resolv.conf

echo "== APT források"
cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: $MIRROR
Suites: $UBUNTU_SUITE $UBUNTU_SUITE-updates $UBUNTU_SUITE-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
rm -f /etc/apt/sources.list

# Nincs Ubuntu kernel (saját kernelünk van) és nincs snap (a 4.14-es kernelen
# nem működik megbízhatóan) – lásd /etc/apt/preferences.d/mamuthka.
cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

"${APT[@]}" update
"${APT[@]}" install locales tzdata software-properties-common gnupg ca-certificates curl

echo "== Nyelv, időzóna, billentyűzet"
sed -i "s/^# *\($LOCALE\)/\1/" /etc/locale.gen
grep -q "^$LOCALE" /etc/locale.gen || echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/default/locale
# A systemd-firstboot az /etc/locale.conf-ot keresi; nélküle első indításkor
# interaktívan kérdezne a konzolon (billentyűzet nincs) → az indulás megáll.
echo "LANG=$LOCALE" > /etc/locale.conf
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone
cat > /etc/default/keyboard <<EOF
XKBMODEL="pc105"
XKBLAYOUT="$XKB_LAYOUT"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

echo "== Firefox (Mozilla PPA, nem snap)"
add-apt-repository -y -n ppa:mozillateam/ppa
"${APT[@]}" update

echo "== Csomagok telepítése"
# shellcheck disable=SC2046
"${APT[@]}" install $(grep -v '^\s*#' /etc/mamuthka/packages.list | xargs) $DEVICE_PACKAGES

echo "== Flathub"
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# Külön apt-hívás: a magyar nyelvi csomag hiánya ne vigye magával a Firefoxot.
if "${APT[@]}" install firefox; then
	"${APT[@]}" install firefox-locale-hu || echo "!! firefox-locale-hu nem érhető el (a Firefox angolul indul)"
else
	echo "!! A Firefox nem érhető el a PPA-ból erre az architektúrára, Flatpakból telepítem"
	flatpak install -y --system --noninteractive flathub org.mozilla.firefox ||
		echo "!! Flatpak Firefox telepítés sikertelen – első induláskor a Szoftverekből telepíthető"
fi

echo "== Mamuthka böngésző (Firefox-réteg)"
# Az assetek: /usr/share/mamuthka/bongeszo (overlay). A rendszerszintű
# policies.json nem csomagtulajdon, a Firefox-frissítés nem írja felül.
# A felhasználói profilt első bejelentkezéskor a bongeszo-setup hozza létre
# (/etc/xdg/autostart/mamuthka-bongeszo.desktop) – profiladat nincs a képben.
B=/usr/share/mamuthka/bongeszo
if [ -d /usr/lib/firefox ]; then
	install -Dm644 "$B/policies.json" /usr/lib/firefox/distribution/policies.json
fi
for s in 16 32 48 64 96 128 256 512; do
	install -Dm644 "$B/ikonok/mamuthka-$s.png" "/usr/share/icons/hicolor/${s}x${s}/apps/mamuthka.png"
done
install -Dm644 "$B/ikonok/mamuthka.svg" /usr/share/icons/hicolor/scalable/apps/mamuthka.svg
gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
# Panel ablaklistájának gyári rögzített indítói: Firefox helyett Mamuthka.
GWL=/usr/share/cinnamon/applets/grouped-window-list@cinnamon.org/settings-schema.json
[ -f "$GWL" ] && sed -i 's/"firefox\.desktop"/"mamuthka.desktop"/' "$GWL"

echo "== Rendszernév és márka"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1	localhost
127.0.1.1	$HOSTNAME
::1	localhost ip6-localhost ip6-loopback
EOF
# Az os-release-t elterelve írjuk felül, hogy a base-files frissítése ne írja vissza.
dpkg-divert --local --rename --add /usr/lib/os-release >/dev/null
cat > /usr/lib/os-release <<EOF
PRETTY_NAME="$OS_NAME $OS_VERSION"
NAME="$OS_NAME"
VERSION_ID="$OS_VERSION"
VERSION="$OS_VERSION (Ubuntu 24.04 alap)"
VERSION_CODENAME=$UBUNTU_SUITE
ID=$OS_ID
ID_LIKE="ubuntu debian"
UBUNTU_CODENAME=$UBUNTU_SUITE
HOME_URL="https://github.com/mamuthkasanyi-star/Claude"
LOGO=mamuthka-logo
EOF
ln -sf ../usr/lib/os-release /etc/os-release

echo "== Felhasználó: $USERNAME"
for g in autologin nopasswdlogin; do getent group "$g" >/dev/null || groupadd -r "$g"; done
if ! id "$USERNAME" >/dev/null 2>&1; then
	useradd -m -s /bin/bash -c "$USER_FULLNAME" "$USERNAME"
fi
for g in sudo adm video audio input render plugdev netdev dialout autologin; do
	getent group "$g" >/dev/null && usermod -aG "$g" "$USERNAME"
done
echo "$USERNAME:$USER_PASSWORD" | chpasswd
# Az első bejelentkezéskor a rendszer kéri a jelszó megváltoztatását
# (/etc/xdg/autostart/mamuthka-first-login.desktop).
install -d -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config" "/home/$USERNAME/.config/mamuthka"
install -o "$USERNAME" -g "$USERNAME" /dev/null "/home/$USERNAME/.config/mamuthka/change-password"
passwd -l root >/dev/null

echo "== Cinnamon alapbeállítások"
sed -i -e "s/@UI_SCALE@/$UI_SCALE/" -e "s/@GTK_THEME@/$GTK_THEME/g" -e "s/@ICON_THEME@/$ICON_THEME/" \
	/usr/share/glib-2.0/schemas/90_mamuthka.gschema.override
glib-compile-schemas /usr/share/glib-2.0/schemas

# cinnamon-screensaver 6.0: a Stage.update_geometry() a (már fizikai pixelben
# kapott) képernyőméretet még egyszer felszorozza a skálával → 2×-es
# (2160×4800) zárképernyő-ablak, amit a cinnamon llvmpipe-pal folyamatosan
# rajzol: ~450% CPU, kikapcsolt kijelzőnél is (hibak.txt 61.). Elterelve
# javítjuk; egy csomagfrissítés az eredetit a .distrib néven telepíti.
SS=/usr/share/cinnamon-screensaver/stage.py
if [ -f "$SS" ] && [ "$(grep -c 'self\.rect\.\(width\|height\) \*= scale' "$SS")" = 2 ]; then
	dpkg-divert --local --rename --divert "$SS.distrib" --add "$SS" >/dev/null
	sed -e '/self\.rect\.\(width\|height\) \*= scale/d' "$SS.distrib" > "$SS"
	chmod 644 "$SS"
	python3 -m py_compile "$SS" && rm -rf /usr/share/cinnamon-screensaver/__pycache__/stage.*
else
	echo "!! cinnamon-screensaver stage.py: a javítandó sorok nem találhatók (megváltozott a csomag?)"
fi
sed -i "s/@USERNAME@/$USERNAME/" /etc/lightdm/lightdm.conf.d/50-mamuthka.conf

echo "== Boot-logó (Plymouth)"
if command -v plymouth-set-default-theme >/dev/null; then
	plymouth-set-default-theme mamuthka || true
fi
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
	/usr/share/plymouth/themes/mamuthka/mamuthka.plymouth 200 || true
update-alternatives --set default.plymouth /usr/share/plymouth/themes/mamuthka/mamuthka.plymouth || true

echo "== Szolgáltatások"
systemctl enable lightdm NetworkManager ssh mamuthka-ssh-keygen mamuthka-resize-rootfs mamuthka-usb-network \
	mamuthka-efs unattended-upgrades
systemctl set-default graphical.target
# Ezek telefonon nem kellenek vagy hibát okoznak a régi kernellel.
# blueman-mechanism: a kernelben nincs RFKILL/Bluetooth (ImportError: RfKill).
systemctl mask systemd-firstboot.service systemd-networkd-wait-online.service NetworkManager-wait-online.service \
	snapd.service snapd.socket ModemManager.service blueman-mechanism.service >/dev/null 2>&1 || true
# Firmware-frissítés (LVFS) Samsung telefonra nincs; a napi időzítő csak ébreszt.
systemctl mask fwupd-refresh.timer >/dev/null 2>&1 || true
# A hangot a PipeWire (pipewire-pulse) adja; a vele együtt települt PulseAudio
# ugyanarra a socketre indulna (versengés, hibák a naplóban).
systemctl --global mask pulseaudio.service pulseaudio.socket >/dev/null 2>&1 || true
systemctl --global enable pipewire-pulse.socket >/dev/null 2>&1 || true
# Automatikus indítás tiltása a munkamenetben (Cinnamon nem nézi a
# X-GNOME-HiddenUnderSystemd kulcsot).
# Telefonon fölösleges háttérfolyamatok: GNOME Szoftverek háttérszolgáltatás
# (~150 MB RAM, frissítés-keresés), KDE-s xdg-user-dirs, Wacom/smartcard/
# nyomtató-értesítő plugin (nincs ilyen hardver / CUPS).
for d in pulseaudio blueman org.gnome.Software xdg-user-dirs-kde cinnamon-settings-daemon-wacom \
	cinnamon-settings-daemon-smartcard cinnamon-settings-daemon-print-notifications; do
	f=/etc/xdg/autostart/$d.desktop
	[ -f "$f" ] && ! grep -q '^Hidden=true' "$f" && echo "Hidden=true" >> "$f"
done
# Beépített (nem modul) driverek: nincs /lib/modules, a modprobe hibát írna.
#   i2c_dev (fwupd), zram (zram-generator; a zram-swap ettől működik)
for f in fwupd-i2c.conf 20-zram-generator.conf; do
	ln -sfn /dev/null "/etc/modules-load.d/$f"
done
# Nem létező sysctl-kulcsok a 4.14-es kernelen (nincs YAMA, és az
# unprivileged_userns_clone Debian-kiegészítés): a „-” előtag mellett a
# systemd-sysctl nem jelez hibát.
[ -f /etc/sysctl.d/10-ptrace.conf ] && sed -i 's/^\(kernel\.yama\)/-\1/' /etc/sysctl.d/10-ptrace.conf
for f in /usr/lib/sysctl.d/*bubblewrap*.conf; do
	[ -f "$f" ] && ln -sfn /dev/null "/etc/sysctl.d/$(basename "$f")"
done
mkdir -p /efs

# Az S-Boot a firmware_class.path=/vendor/firmware útvonalat adja át.
mkdir -p /vendor
ln -sfn /lib/firmware /vendor/firmware

echo "== Takarítás"
rm -f /usr/sbin/policy-rc.d
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /tmp/* /var/tmp/*
rm -f /etc/ssh/ssh_host_*   # első induláskor generálódnak (mamuthka-ssh-keygen)
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id
if [ -e /usr/lib/systemd/system/systemd-resolved.service ]; then
	ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
else
	# Üres fájl marad (nem törlés), hogy a NetworkManager megindulásáig se
	# hiányozzon; a NetworkManager felülírja.
	rm -f /etc/resolv.conf
	: > /etc/resolv.conf
fi
echo "== setup.sh kész"
