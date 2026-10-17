#!/usr/bin/python3
"""cinnamon-screensaver 6.0 manager.py javítása (Mamuthka linux).

Használat: cs-manager-patch.py <eredeti manager.py> <kimenet>

A cs-backup-locker (a képernyővédő alatti tartalék zár-ablak) a méretét az
X-képernyő pixelméretéből veszi (DisplayWidth/Height), de GDK-koordinátaként
adja át; 2-es skálánál ezért 2160×4800-as, átlátszó (ARGB) ablak lesz belőle.
Ezt a muffin llvmpipe-pal másodpercenként többször újrakompozitálja: a
cinnamon ~390% CPU-t visz, amíg a képernyővédő fut, kikapcsolt kijelzőnél is
(mérés 2026-10-17: 387% → 4%, ha az ablak 1080×2400; hibak.txt 77.).

Javítás: a tartalék-zár GDK_SCALE=1-gyel indul (a szövege GDK_DPI_SCALE=2-vel
ugyanakkora marad), így az ablak pontosan a képernyő méretű – forgatás után is.
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()


def rep(old, new):
    global s
    if s.count(old) != 1:
        sys.exit("cs-manager-patch: a minta nem pontosan egyszer szerepel: %r" % old[:60])
    s = s.replace(old, new)


rep("""            self.fb_pid = GLib.spawn_async(argv)[0]
""", """            # Mamuthka: GDK_SCALE=1, különben 2-es skálánál 2×2-szeres méretű
            # ablak (hibak.txt 77.).
            envp = ["%s=%s" % kv for kv in os.environ.items()
                    if kv[0] not in ("GDK_SCALE", "GDK_DPI_SCALE")]
            envp += ["GDK_SCALE=1", "GDK_DPI_SCALE=%d" % max(1, round(self.stage.get_scale_factor()))]
            self.fb_pid = GLib.spawn_async(argv, envp=envp)[0]
""")

open(dst, "w", encoding="utf-8").write(s)
