# shellcheck shell=sh
# Watchdogok pöcögtetése az initramfs-ben és a recovery-ben.
#
# Az Exynos hardveres watchdogját (s3c2410_wdt) a bootloader elindítja, a
# Samsung kernelben pedig ott a saját szoftveres watchdog is (SEC_DEBUG_SOFTDOG,
# PWDT). Androidon ezeket a userspace pöcögteti; ha senki nem teszi, a telefon
# pár másodperc / perc után újraindul (recovery bootloop).
#
# start_watchdogs: minden /dev/watchdogN eszközre indít egy busybox watchdog
#                  folyamatot (1 mp-enként pöcögtet, 20 mp-es időkorlát).
# stop_watchdogs:  leállítja őket; a busybox kilépéskor „magic close”-t ír
#                  ('V'), így a watchdog kikapcsol, és a rendszer (systemd)
#                  tiszta állapotból veheti át.

start_watchdogs() {
	n=0
	# A watchdog-eszközök néha csak a driverek késői probe-ja után jelennek meg.
	while [ $n -lt 10 ] && ! ls /dev/watchdog* >/dev/null 2>&1; do
		n=$((n + 1)); sleep 0.2
	done
	for w in /dev/watchdog[0-9]*; do
		[ -c "$w" ] || continue
		watchdog -t 1 -T 20 "$w" && echo "Watchdog: $w pöcögtetése (1 mp / 20 mp)" ||
			echo "Watchdog: $w nem nyitható meg"
	done
	# Ha csak a régi stílusú /dev/watchdog van (watchdogN nélkül)
	if ! ls /dev/watchdog[0-9]* >/dev/null 2>&1 && [ -c /dev/watchdog ]; then
		watchdog -t 1 -T 20 /dev/watchdog && echo "Watchdog: /dev/watchdog pöcögtetése"
	fi
}

stop_watchdogs() {
	killall watchdog 2>/dev/null
	sleep 0.3
}
