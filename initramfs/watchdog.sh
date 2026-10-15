# shellcheck shell=sh
# Watchdogok az initramfs-ben és a recovery-ben – csak állapotjelentés.
#
# A kernelforrás (drivers/watchdog/s3c2410_wdt.c) szerint az Exynos hardveres
# watchdogját a driver a probe-ban LEÁLLÍTJA (tmr_atboot = 0), a softdog
# (drivers/watchdog/softdog.c) pedig csak akkor indul el, ha valaki megnyitja a
# /dev/watchdogN eszközt. Azaz alapból egyik sem fut, és nem kell pöcögtetni.
#
# Korábban itt busybox `watchdog` folyamatok nyitották meg az eszközöket: ezzel
# ÉLESÍTETTÜK mindkét watchdogot (20 mp), és ha a pöcögtető bármiért kiesett,
# a telefon újraindult – vagyis a pöcögtetés nem véd, hanem új hibaforrás.
# Ezért most csak naplózunk; ha a /proc/reset_reason WPON-t mutat (watchdog),
# akkor kell ide visszatérni.

start_watchdogs() {
	for w in /dev/watchdog /dev/watchdog[0-9]*; do
		[ -c "$w" ] || continue
		echo "Watchdog: $w jelen van (nem nyitjuk meg, így nem is indul el)"
	done
	if ! ls /dev/watchdog* >/dev/null 2>&1; then
		echo "Watchdog: nincs /dev/watchdog* eszköz"
	fi
}

stop_watchdogs() { :; }
