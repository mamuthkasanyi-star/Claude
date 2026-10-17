-- Mamuthka linux (Galaxy A51): alap hangerő 40% (a köbös/felületi skálán 0.40,
-- lineárisan 0.4^3 = 0.064). Csak addig érvényes, amíg a felhasználó nem állít
-- mást: a WirePlumber az útvonal hangerejét ezután
-- ~/.local/state/wireplumber/default-routes alatt tárolja (élőben kipróbálva).
device_defaults.properties["default-volume"] = 0.064
