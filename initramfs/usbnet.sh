# shellcheck shell=sh
# USB-hálózat a telefon és a gép között (NCM, ha nem megy: RNDIS).
# Ugyanaz a sorrend, mint a postmarketOS initramfs-ben, mert ezzel a
# kernellel az bizonyítottan működik. Változók: USB_ID_VENDOR, USB_ID_PRODUCT,
# USB_NET_IP, USB_NET_CLIENT_IP, USB_PRODUCT_NAME.

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
	if [ -d /config/usb_gadget ] && [ -n "$UDC" ]; then
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
		echo "$UDC" > "$G/UDC"
		km "UDC bekötve"
	fi

	sleep 1
	IFACE="$(cat "$G/functions/"*/ifname 2>/dev/null | head -1)"
	for i in $IFACE rndis0 usb0; do
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
