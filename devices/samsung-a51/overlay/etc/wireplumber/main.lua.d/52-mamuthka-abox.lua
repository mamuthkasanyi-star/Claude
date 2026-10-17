-- Mamuthka linux (Galaxy A51, hibak.txt 84.): az ABOX RDMA-pointere durva lépésű, a PipeWire
-- időzítő-alapú ütemezése (tsched) ezt elakadásnak veszi, és ~165 ms-onként
-- újraindítja a lejátszást (szaggatás, „RDMA disable timeout”). IRQ-alapú
-- ütemezés, rögzített periódussal.
table.insert(alsa_monitor.rules, {
  matches = { { { "node.name", "matches", "alsa_output.platform-sound*" } } },
  apply_properties = {
    ["api.alsa.disable-tsched"] = true,
    ["api.alsa.period-size"] = 1024,
    ["api.alsa.period-num"] = 4,
    ["api.alsa.headroom"] = 0,
    ["audio.format"] = "S16LE",
    ["audio.rate"] = 48000,
    ["session.suspend-timeout-seconds"] = 5,
  },
})
