-- Mamuthka linux (Samsung Galaxy A51)
--
-- Kamera nincs támogatva: a v4l2/libcamera figyelő a ~80 /dev/video*
-- eszközt (fimc-is szenzorok, mfc, scaler) folyamatosan nyitogatta →
-- fimc_is-hibák a kernelnaplóban, „Túl sok nyitott fájl”, CPU-terhelés
-- (hibak.txt 56.). Visszakapcsolás: ezt a fájlt töröld, majd
--   systemctl --user restart wireplumber
if v4l2_monitor then
  v4l2_monitor.enabled = false
end
if libcamera_monitor then
  libcamera_monitor.enabled = false
end

-- A hangkártya (Exynos9610-Audio) engedélyezve marad: a rendszer már
-- tartalmazza az ABOX DSP gyári firmware-ét (calliope_*.bin). Ha mégis
-- „Invalid calliope state” hibák és magas wireplumber-CPU jelentkezne,
-- az alábbi sorok elől vedd ki a „--” jelet, ez kikapcsolja a kártyát:
--
-- table.insert(alsa_monitor.rules, {
--   matches = { { { "device.name", "matches", "alsa_card.platform-sound*" } } },
--   apply_properties = { ["device.disabled"] = true },
-- })
