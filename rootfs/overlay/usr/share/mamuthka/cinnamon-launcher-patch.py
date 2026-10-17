#!/usr/bin/python3
"""cinnamon-launcher (Cinnamon 6.0) javítása (Mamuthka linux).

Használat: cinnamon-launcher-patch.py <eredeti cinnamon-launcher> <kimenet>

Ha a cinnamon jellel (SIGSEGV, SIGABRT, ...) összeomlik, a gyári launcher
a metacity-t indítja tartalék ablakkezelőnek, és egy „Cinnamon just crashed”
párbeszédablakban kérdez. Telefonon ez fekete képernyőt jelentett
(hibak.txt 74.): a kérdés gyakran a kijelzőn kívülre vagy egy ablakkezelő
nélküli, üres X-re kerül, és érintéssel nehéz rá válaszolni.

A javítás után összeomlásnál a launcher magától újraindítja a cinnamont
(5 percen belül legfeljebb 3-szor). Ha ennél gyakrabban omlik össze, a
gyári viselkedés jön (metacity + kérdés), így nincs végtelen újraindítás.
Kilépésnél, kijelentkezésnél (SIGTERM, SIGKILL, SIGHUP, SIGINT) nem indít
újra semmit.
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()


def rep(old, new):
    global s
    if s.count(old) != 1:
        sys.exit("cinnamon-launcher-patch: a minta nem pontosan egyszer szerepel: %r" % old[:60])
    s = s.replace(old, new)


rep('''FALLBACK_ARGS = ("--replace",)
''', '''FALLBACK_ARGS = ("--replace",)

# Mamuthka: összeomlás (nem kilépés) után automatikus újraindítás, korláttal.
MAMUTHKA_RESTART_WINDOW = 300   # másodperc
MAMUTHKA_RESTART_MAX = 3
MAMUTHKA_CRASH_SIGNALS = (4, 5, 6, 7, 8, 11, 31)  # ILL TRAP ABRT BUS FPE SEGV SYS


def mamuthka_auto_restart(exit_status):
    import json
    if not os.WIFSIGNALED(exit_status):
        return False
    sig = os.WTERMSIG(exit_status)
    if sig not in MAMUTHKA_CRASH_SIGNALS:
        return False
    path = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp",
                        "mamuthka-cinnamon-restarts")
    now = time.time()
    try:
        with open(path, encoding="utf-8") as f:
            stamps = [float(t) for t in json.load(f)]
    except Exception:
        stamps = []
    stamps = [t for t in stamps if now - MAMUTHKA_RESTART_WINDOW < t <= now]
    if len(stamps) >= MAMUTHKA_RESTART_MAX:
        print("cinnamon-launcher: a cinnamon %d percen belül %d-szor omlott össze, "
              "tartalék mód következik" % (MAMUTHKA_RESTART_WINDOW // 60, len(stamps)))
        return False
    stamps.append(now)
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(stamps, f)
    except Exception:
        pass
    print("cinnamon-launcher: a cinnamon összeomlott (jel: %d), újraindítás "
          "(%d/%d)" % (sig, len(stamps), MAMUTHKA_RESTART_MAX), flush=True)
    time.sleep(1)
    return True
''')

rep('''                if self.killed:
                    # Restart Cinnamon''', '''                if self.killed or mamuthka_auto_restart(exit_status):
                    # Restart Cinnamon''')

open(dst, "w", encoding="utf-8").write(s)
