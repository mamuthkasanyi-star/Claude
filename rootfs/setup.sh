#!/bin/bash
# A rendszer beállítása a chrootban. A build-rootfs.sh hívja, a változókat
# környezeti változóként kapja (config/mamuthka.conf, devices/*/device.conf).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)

cp /etc/resolv.conf.build /etc/resolv.conf 2>/dev/null || true

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

if ! "${APT[@]}" install firefox firefox-locale-hu 2>/dev/null && ! "${APT[@]}" install firefox; then
	echo "!! A Firefox nem érhető el a PPA-ból erre az architektúrára, Flatpakból telepítem"
	flatpak install -y --system --noninteractive flathub org.mozilla.firefox ||
		echo "!! Flatpak Firefox telepítés sikertelen – első induláskor a Szoftverekből telepíthető"
fi

echo "== Flathub"
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

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
sed -i "s/@USERNAME@/$USERNAME/" /etc/lightdm/lightdm.conf.d/50-mamuthka.conf

echo "== Boot-logó (Plymouth)"
if command -v plymouth-set-default-theme >/dev/null; then
	plymouth-set-default-theme mamuthka || true
fi
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth \
	/usr/share/plymouth/themes/mamuthka/mamuthka.plymouth 200 || true
update-alternatives --set default.plymouth /usr/share/plymouth/themes/mamuthka/mamuthka.plymouth || true

echo "== Szolgáltatások"
systemctl enable lightdm NetworkManager ssh mamuthka-ssh-keygen mamuthka-resize-rootfs mamuthka-usb-network unattended-upgrades
systemctl set-default graphical.target
# Ezek telefonon nem kellenek vagy hibát okoznak a régi kernellel
systemctl mask systemd-networkd-wait-online.service NetworkManager-wait-online.service \
	snapd.service snapd.socket ModemManager.service >/dev/null 2>&1 || true

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
	rm -f /etc/resolv.conf
fi
echo "== setup.sh kész"
