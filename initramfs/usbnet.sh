# shellcheck shell=sh
# USB-hálózat a telefon és a gép között: a beépített g_ether (RNDIS/ECM, usb0),
# ha az foglalja az UDC-t; különben configfs NCM, ha nem megy: RNDIS.
# Ugyanaz a sorrend, mint a postmarketOS initramfs-ben, mert ezzel a
# kernellel az bizonyítottan működik. Változók: USB_ID_VENDOR, USB_ID_PRODUCT,
# USB_NET_IP, USB_NET_CLIENT_IP, USB_PRODUCT_NAME.

# A USB-gadget hálózati interfésze (pl. usb0, rndis0, ncm0) a /sys/class/net
# alapján: elsőként az, amelynek a device-a a gadget; ha ilyen nincs, a szokásos
# nevek közül az első létező. Kimenet: az interfész neve (vagy üres).
usb_gadget_iface() {
	for d in /sys/class/net/*; do
		[ -e "$d" ] || continue
		case "$(readlink -f "$d/device" 2>/dev/null)" in
			*/gadget) echo "${d##*/}"; return 0 ;;
		esac
	done
	for i in usb0 rndis0 ncm0; do
		[ -e "/sys/class/net/$i" ] && { echo "$i"; return 0; }
	done
	return 1
}

setup_usb_network() {
	[ -e /tmp/.usb_done ] && return
	touch /tmp/.usb_done
	# Jelzők a kernelnaplóba: ha az USB-beállítás közben omlik össze a kernel,
	# a következő indításkor a pstore-ból látszik, melyik lépésnél.
	km() { echo "mamuthka: USB $*" > /dev/kmsg 2>/dev/null; }

	SYS=/sys/class/android_usb/android0
	if [ -e "$SYS" ]; then
		echo "USB: android_usb (rndis)"
		echo 0 > "$SYS/enable"
		echo "${USB_ID_VENDOR#0x}" > "$SYS/idVendor"
		echo "${USB_ID_PRODUCT#0x}" > "$SYS/idProduct"
		echo rndis > "$SYS/functions"
		echo 1 > "$SYS/enable"
	fi

	G=/config/usb_gadget/g1
	# A USB-vezérlő (dwc3) a korai indulásnál még nem mindig jelent meg:
	# legfeljebb 10 mp-ig várunk rá.
	n=0
	while [ $n -lt 50 ] && [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do
		n=$((n + 1)); sleep 0.2
	done
	UDC="$(ls /sys/class/udc 2>/dev/null | head -1)"
	echo "USB: UDC='${UDC:-nincs}' ($((n * 2 / 10)) mp várakozás), configfs: $([ -d /config/usb_gadget ] && echo van || echo NINCS)"
	# A kernelbe épített g_ether (CONFIG_USB_ETH=y) már 1 mp-nél lefoglalja az
	# UDC-t (RNDIS + CDC ECM, usb0 interfész). Ilyenkor a configfs-gadget
	# UDC-bekötése úgyis hibával tér vissza, az ncm-funkció sosem bindol – ezért
	# hozzá sem nyúlunk (hibak.txt 54.).
	BUSY=""
	[ -n "$UDC" ] && BUSY="$(cat "/sys/class/udc/$UDC/function" 2>/dev/null)"
	if [ -n "$BUSY" ]; then
		echo "USB: az UDC-t már a beépített '$BUSY' gadget használja (configfs kihagyva)"
		km "UDC foglalt: $BUSY (beépített gadget, configfs kihagyva)"
	elif [ -d /config/usb_gadget ] && [ -n "$UDC" ]; then
		echo "USB: configfs ($UDC)"
		km "configfs gadget létrehozása ($UDC)"
		mkdir -p "$G/strings/0x409"
		echo "$USB_ID_VENDOR" > "$G/idVendor"
		echo "$USB_ID_PRODUCT" > "$G/idProduct"
		echo "Samsung" > "$G/strings/0x409/manufacturer"
		echo "${USB_PRODUCT_NAME:-Mamuthka linux}" > "$G/strings/0x409/product"
		echo "mamuthka" > "$G/strings/0x409/serialnumber"
		FUNC=ncm.usb0
		[ -d "$G/functions/$FUNC" ] || mkdir "$G/functions/$FUNC" 2>/dev/null ||
			{ FUNC=rndis.usb0; mkdir -p "$G/functions/$FUNC"; }
		mkdir -p "$G/configs/c.1/strings/0x409"
		echo "USB network" > "$G/configs/c.1/strings/0x409/configuration"
		ln -s "$G/functions/$FUNC" "$G/configs/c.1/" 2>/dev/null
		km "funkció: $FUNC"
		[ -n "$(cat "$G/UDC")" ] && echo "" > "$G/UDC"
		km "UDC bekötése"
		if echo "$UDC" > "$G/UDC"; then
			km "UDC bekötve"
		else
			km "UDC bekötése SIKERTELEN"
		fi
	fi
	if [ -n "$UDC" ]; then
		# A Samsung dwc3-otg a gadgetet csak akkor indítja el (PHY, RUN/STOP),
		# ha a VBUS-session jelző 1; ezt Androidon az usb_notify lánc állítja
		# (10 mp indítási késleltetéssel). Itt közvetlenül állítjuk a driver
		# sysfs kapcsolójával (drivers/usb/dwc3/otg.c: b_sess) – enélkül a
		# gépen soha nem jelenik meg az USB-eszköz. A beépített g_ether-nek is kell.
		B_SESS="/sys/class/udc/$UDC/device/b_sess"
		if [ -w "$B_SESS" ]; then
			km "b_sess=1"
			echo 1 > "$B_SESS"
			echo "USB: b_sess=1, otg állapot: $(cat "/sys/class/udc/$UDC/device/state" 2>/dev/null)"
			km "otg: $(cat "/sys/class/udc/$UDC/device/state" 2>/dev/null)"
		else
			echo "USB: nincs b_sess kapcsoló ($B_SESS)"
		fi
	fi

	# Az interfészt a /sys/class/net alapján keressük: az a gadget-hálózati
	# eszköz, amelynek a "device"-a a USB-gadget. A configfs "ifname"
	# attribútumát NEM olvassuk: bindolatlan ncm-nél ez kernel-Oopsot okozott
	# (gether_get_ifname, NULL net → PANIC_ON_OOPS → bootloop, hibak.txt 54.).
	IFACE=""
	n=0
	while [ $n -lt 15 ] && [ -z "$IFACE" ]; do
		IFACE="$(usb_gadget_iface)"
		[ -n "$IFACE" ] || { n=$((n + 1)); sleep 0.2; }
	done
	for i in $IFACE usb0 rndis0 ncm0; do
		if ifconfig "$i" "$USB_NET_IP" netmask 255.255.255.0 up 2>/dev/null; then
			IFACE="$i"; break
		fi
	done
	echo "USB: interfész $IFACE, IP $USB_NET_IP"
	km "interfész $IFACE kész"
	# Egyetlen kliensnek oszt címet.
	cat > /tmp/udhcpd.conf <<-EOF
		start $USB_NET_CLIENT_IP
		end $USB_NET_CLIENT_IP
		interface $IFACE
		max_leases 1
		lease_file /tmp/udhcpd.leases
		option subnet 255.255.255.0
	EOF
	touch /tmp/udhcpd.leases
	udhcpd /tmp/udhcpd.conf
}
