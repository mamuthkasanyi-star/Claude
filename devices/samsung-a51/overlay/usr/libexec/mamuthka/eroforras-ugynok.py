#!/usr/bin/python3
# -*- coding: utf-8 -*-
"""Mamuthka linux – erőforrás-ügynök (Galaxy A51).

Csak olvasó HTTP-szolgáltatás (python3 stdlib), amely a telefon
erőforrás-használatát JSON-ban adja ki az „A51 Figyelő” Android-appnak:

  GET /api/v1/allapot    pillanatkép (JSON)
  GET /api/v1/folyam     Server-Sent Events, másodpercenként egy „allapot”
  GET /api/v1/elozmeny   az utolsó 5 perc tömör mintái (görbékhez)

Biztonság:
  - semmit nem ír, nem indít (a hangerőt a felhasználó wpctl-jével olvassa);
  - csak privát IPv4-címekről fogad kérést (127/8, 10/8, 172.16/12 – benne az
    USB-háló 172.16.42.0/24 –, 192.168/16), a többit a kapcsolat felvétele után
    azonnal bontja;
  - IP-nkénti kéréskorlát, korlátozott számú egyidejű kapcsolat és folyam;
  - folyamatoknál csak név (comm), pid és felhasználó – parancssor és
    környezet soha (titkot tartalmazhat). A cinnamon környezetéből kizárólag a
    COGL_DRIVER értékét olvassa.

Erőforrásigény: a görbékhez szükséges alapmintát mindig gyűjti (~20 sysfs-
fájl/s), a drágább részeket (folyamatlista, Wi-Fi, hangerő, lemezterület)
csak akkor, ha van kliens.
"""

import collections
import fcntl
import ipaddress
import json
import os
import pwd
import re
import socket
import struct
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERZIO = "1.0"
PORT = int(os.environ.get("MAMUTHKA_EROFORRAS_PORT", "8790"))
CIM = os.environ.get("MAMUTHKA_EROFORRAS_CIM", "0.0.0.0")
ELOZMENY_HOSSZ = 300          # minta (1 s-onként → 5 perc)
TOP_N = 15
AKTIV_TURES = 10.0            # s: ennyi ideig számít „aktívnak” egy kérés után
MAX_KAPCSOLAT = 24            # egyidejű kapcsolat összesen
MAX_FOLYAM = 8                # egyidejű SSE-folyam összesen
MAX_FOLYAM_IP = 3             # egyidejű SSE-folyam IP-nként
KERES_KORLAT = (60, 60.0)     # IP-nként legfeljebb 60 kérés 60 s alatt
FOLYAM_MAX_IDO = 6 * 3600     # egy SSE-kapcsolat legfeljebb ennyi s-ig él

ENGEDETT_HALOK = [ipaddress.ip_network(n) for n in
                  ("127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]

CLK_TCK = os.sysconf("SC_CLK_TCK")
LAPMERET = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1

MALI = "/sys/class/misc/mali0/device"
KGPU = "/sys/kernel/gpu"


# ---------------------------------------------------------------- segédek

def olvas_b(ut, meret=65536, egeszet=False):
    """Nyers bájtok; alacsony szintű os.open/os.read (a beépített open()
    pufferelt objektumai a sok kis sysfs/proc fájlnál feleslegesen drágák).
    Egy sysfs-attribútum egyetlen read()-del megjön; a /proc többlapos fájljai
    (seq_file) viszont olvasásonként legfeljebb egy lapot adnak: ezeknél
    egeszet=True, és a fájl végéig olvasunk."""
    fd = os.open(ut, os.O_RDONLY | os.O_CLOEXEC)
    try:
        adat = os.read(fd, meret)
        if egeszet and adat:
            darabok = [adat]
            while True:
                d = os.read(fd, meret)
                if not d:
                    break
                darabok.append(d)
            adat = b"".join(darabok)
        return adat
    finally:
        os.close(fd)


def olvas(ut, alap=None, egeszet=False):
    try:
        return olvas_b(ut, egeszet=egeszet).decode(errors="replace").strip()
    except OSError:
        return alap


_SZAM = re.compile(rb"-?\d+")
_LEMEZ = re.compile(r"sd[a-z]+|mmcblk\d+|nvme\d+n\d+|zram\d+|dm-\d+")


def olvas_int(ut, alap=None):
    try:
        m = _SZAM.search(olvas_b(ut, 4096))
    except OSError:
        return alap
    return int(m.group(0)) if m else alap


def felhasznalonev(uid, _gyors={}):
    n = _gyors.get(uid)
    if n is None:
        try:
            n = pwd.getpwuid(uid).pw_name
        except (KeyError, OverflowError, ValueError):
            n = str(uid)
        _gyors[uid] = n
    return n


def ipv4_cim(ifnev):
    """Az interfész IPv4-címe (SIOCGIFADDR), vagy None."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        r = fcntl.ioctl(s.fileno(), 0x8915, struct.pack("256s", ifnev[:15].encode()))
        return socket.inet_ntoa(r[20:24])
    except OSError:
        return None
    finally:
        s.close()


def kerekit(x, n=1):
    return None if x is None else round(x, n)


# ---------------------------------------------------------------- gyűjtő

class Gyujto:
    def __init__(self):
        self.zar = threading.Condition()
        self.sorszam = 0
        self.allapot_json = b"{}"
        self.teljes = False
        self.cinnamon_pid = None
        self.elozmeny = collections.deque(maxlen=ELOZMENY_HOSSZ)
        self.utolso_igeny = 0.0
        self.folyamok = 0
        self._elozo_cpu = None
        self._elozo_net = None
        self._elozo_disk = None
        self._elozo_proc = {}
        self._elozo_proc_ido = None
        self._ido = None
        self._gyors = {}           # ritkán frissülő részek: kulcs → (idő, érték)
        self._statikus = self._statikus_adatok()

    # -- ritka frissítés gyorsítótárral
    def _ritkan(self, kulcs, periodus, fv):
        most = time.monotonic()
        e = self._gyors.get(kulcs)
        if e is None or most - e[0] >= periodus:
            try:
                ertek = fv()
            except Exception as hiba:  # egy hibás forrás ne állítsa le a többit
                ertek = {"hiba": type(hiba).__name__}
            self._gyors[kulcs] = (most, ertek)
            return ertek
        return e[1]

    def aktiv(self):
        return self.folyamok > 0 or time.monotonic() - self.utolso_igeny < AKTIV_TURES

    def _statikus_adatok(self):
        osr = {}
        for sor in (olvas("/etc/os-release", "") or "").splitlines():
            if "=" in sor:
                k, v = sor.split("=", 1)
                osr[k] = v.strip().strip('"')
        magok = []
        for i in range(NCPU):
            b = f"/sys/devices/system/cpu/cpu{i}/cpufreq/"
            magok.append({
                "max_mhz": (olvas_int(b + "cpuinfo_max_freq", 0) or 0) // 1000,
                "min_mhz": (olvas_int(b + "cpuinfo_min_freq", 0) or 0) // 1000,
                "klaszter": olvas(b + "related_cpus", str(i)),
            })
        gpu_model = olvas(MALI + "/gpuinfo") or olvas(KGPU + "/gpu_model") or ""
        dvfs = sorted(int(x) // 1000 for x in (olvas(MALI + "/dvfs_table", "") or "").split() if x.isdigit())
        return {
            "nev": socket.gethostname(),
            "os": osr.get("PRETTY_NAME", ""),
            "kernel": os.uname().release,
            "magok": magok,
            "gpu_modell": gpu_model,
            "gpu_frekvenciak_mhz": dvfs,
            "gpu_max_mhz": (olvas_int(KGPU + "/gpu_max_clock", 0) or (dvfs[-1] * 1000 if dvfs else 0)) // 1000,
        }

    # -- CPU
    def _cpu(self, dt):
        akt = {}
        for sor in olvas("/proc/stat", "", egeszet=True).splitlines():
            if not sor.startswith("cpu"):
                break
            r = sor.split()
            ert = list(map(int, r[1:9]))
            tetlen = ert[3] + ert[4]          # idle + iowait
            akt[r[0]] = (sum(ert), tetlen)
        szaz = {}
        if self._elozo_cpu:
            for k, (ossz, tetlen) in akt.items():
                e = self._elozo_cpu.get(k)
                if e and ossz > e[0]:
                    szaz[k] = max(0.0, min(100.0, 100.0 * (1 - (tetlen - e[1]) / (ossz - e[0]))))
        self._elozo_cpu = akt
        magok = []
        for i in range(NCPU):
            b = f"/sys/devices/system/cpu/cpu{i}/"
            online = (self._ritkan(f"online{i}", 5, lambda u=b + "online": olvas(u, "1")) == "1") if i else True
            khz = olvas_int(b + "cpufreq/scaling_cur_freq") if online else None
            st = self._statikus["magok"][i]
            magok.append({
                "id": i,
                "online": online and f"cpu{i}" in akt,
                "szazalek": kerekit(szaz.get(f"cpu{i}")),
                "mhz": khz // 1000 if khz else None,
                "max_mhz": st["max_mhz"],
                "klaszter": st["klaszter"],
            })
        la = (olvas("/proc/loadavg", "0 0 0 0/0") or "").split()
        fut, ossz = (la[3].split("/") + ["0"])[:2]
        return {
            "osszes": kerekit(szaz.get("cpu")),
            "magok": magok,
            "load": [float(x) for x in la[:3]],
            "futo": int(fut),
            "szalak": int(ossz),
        }

    # -- GPU
    def _gpu_folyamatok(self):
        lista = []
        for sor in (olvas(KGPU + "/gpu_memory", "", egeszet=True) or "").splitlines()[1:]:
            r = sor.split()
            if len(r) >= 3 and r[0].isdigit():
                pid = int(r[0])
                nev = olvas(f"/proc/{pid}/comm")
                if nev is None:
                    continue
                try:
                    uid = os.stat(f"/proc/{pid}").st_uid
                except OSError:
                    uid = -1
                lista.append({"pid": pid, "nev": nev, "user": felhasznalonev(uid),
                              "memoria_bajt": int(r[2])})
        lista.sort(key=lambda x: -x["memoria_bajt"])
        return lista

    def _cinnamon_mod(self):
        # A pid-et a folyamatlista találja meg (nem kell külön végigjárni /proc-ot).
        pid = self.cinnamon_pid
        if pid is not None and olvas(f"/proc/{pid}/comm") != "cinnamon":
            pid = self.cinnamon_pid = None
        if pid is None:
            return {"fut": False}
        cogl = None
        try:
            for t in olvas_b(f"/proc/{pid}/environ", egeszet=True).split(b"\0"):
                if t.startswith(b"COGL_DRIVER="):
                    cogl = t[12:].decode(errors="replace")[:32]
        except OSError:
            pass
        try:
            maps = olvas_b(f"/proc/{pid}/maps", 1 << 16, egeszet=True)
        except OSError:
            maps = b""
        mali = b"mali" in maps
        szoftveres = b"llvmpipe" in maps or b"swrast" in maps
        mod = "Mali GPU" if mali else ("szoftveres (llvmpipe)" if szoftveres else "ismeretlen")
        return {"fut": True, "pid": pid, "cogl_driver": cogl, "mali": mali, "mod": mod}

    def _gpu(self, teljes):
        util = olvas_int(MALI + "/utilization")
        if util is None:
            util = olvas_int(KGPU + "/gpu_busy")
        clk = olvas_int(MALI + "/clock")
        if clk is None:
            clk = olvas_int(KGPU + "/gpu_clock")
        tmu = olvas(KGPU + "/gpu_tmu")
        try:
            hom = float(tmu) if tmu is not None else None
        except ValueError:
            hom = None
        g = {
            "szazalek": util,
            "mhz": (clk // 1000 if clk and clk > 10000 else clk),
            "max_mhz": self._statikus["gpu_max_mhz"],
            "homerseklet": hom,
            "modell": self._statikus["gpu_modell"],
            "bekapcsolva": olvas(MALI + "/power_state") == "1",
        }
        if teljes:
            fl = self._ritkan("gpu_folyamatok", 2, self._gpu_folyamatok)
            g["folyamatok"] = fl
            g["memoria_bajt"] = sum(x["memoria_bajt"] for x in fl) if isinstance(fl, list) else None
            c = self._ritkan("cinnamon", 30, self._cinnamon_mod)
            if not c.get("fut") and self.cinnamon_pid:
                self._gyors.pop("cinnamon", None)
                c = self._ritkan("cinnamon", 30, self._cinnamon_mod)
            g["cinnamon"] = c
        return g

    # -- memória
    def _memoria(self, teljes):
        mi = {}
        for sor in olvas("/proc/meminfo", "", egeszet=True).splitlines():
            k, v = sor.split(":", 1)
            mi[k] = int(v.split()[0]) * 1024
        ossz = mi.get("MemTotal", 0)
        eler = mi.get("MemAvailable", mi.get("MemFree", 0))
        m = {
            "osszes": ossz,
            "elerheto": eler,
            "hasznalt": ossz - eler,
            "szabad": mi.get("MemFree", 0),
            "gyorsitotar": mi.get("Cached", 0) + mi.get("Buffers", 0),
            "megosztott": mi.get("Shmem", 0),
            "swap_osszes": mi.get("SwapTotal", 0),
            "swap_hasznalt": mi.get("SwapTotal", 0) - mi.get("SwapFree", 0),
        }
        if teljes:
            m["zram"] = self._ritkan("zram", 5, self._zram)
        return m

    def _zram(self):
        lista = []
        for d in sorted(os.listdir("/sys/block")):
            if not d.startswith("zram"):
                continue
            mm = (olvas(f"/sys/block/{d}/mm_stat", "") or "").split()
            alg = olvas(f"/sys/block/{d}/comp_algorithm", "") or ""
            m = re.search(r"\[(\w+)\]", alg)
            z = {"nev": d, "meret": olvas_int(f"/sys/block/{d}/disksize", 0),
                 "algoritmus": m.group(1) if m else alg}
            if len(mm) >= 3:
                z.update({"eredeti": int(mm[0]), "tomoritett": int(mm[1]), "mem_hasznalt": int(mm[2])})
            lista.append(z)
        return lista

    # -- hőmérsékletek
    def _zonak(self):
        z = []
        i = 0
        while os.path.isdir(f"/sys/class/thermal/thermal_zone{i}"):
            b = f"/sys/class/thermal/thermal_zone{i}"
            z.append((b + "/temp", olvas(b + "/type", f"zone{i}")))
            i += 1
        return z

    def _homersekletek(self):
        lista = []
        for ut, nev in self._ritkan("zonak", 300, self._zonak):
            t = olvas_int(ut)
            if t is not None:
                lista.append({"nev": nev, "c": kerekit(t / 1000.0 if abs(t) > 200 else float(t))})
        return lista

    # -- lemez
    def _lemez_io(self, dt):
        akt = {}
        for sor in olvas("/proc/diskstats", "", egeszet=True).splitlines():
            r = sor.split()
            nev = r[2]
            if not nev.startswith(("loop", "ram")) and _LEMEZ.fullmatch(nev):
                akt[nev] = (int(r[5]) * 512, int(r[9]) * 512, int(r[12]))  # olv, ír, ms foglalt
        lista = []
        e = self._elozo_disk
        for nev, (o, w, ms) in akt.items():
            if w == 0 and o < (16 << 20):    # érintetlen LUN-ok (boot, rpmb…) kimaradnak
                continue
            d = {"nev": nev, "olvasva": o, "irva": w}
            if e and nev in e and dt:
                po, pw, pms = e[nev]
                d["olvasas_bps"] = max(0, int((o - po) / dt))
                d["iras_bps"] = max(0, int((w - pw) / dt))
                d["foglaltsag"] = kerekit(min(100.0, max(0.0, (ms - pms) / (dt * 10.0))))
            lista.append(d)
        self._elozo_disk = akt
        return lista

    def _fajlrendszerek(self):
        lista = []
        latott = set()
        for sor in olvas("/proc/1/mounts", "", egeszet=True).splitlines():
            r = sor.split()
            if not r[0].startswith("/dev/") or r[0] in latott or r[0].startswith("/dev/loop"):
                continue
            latott.add(r[0])
            try:
                st = os.statvfs(r[1].replace("\\040", " "))
            except OSError:
                continue
            ossz = st.f_blocks * st.f_frsize
            if ossz == 0:
                continue
            lista.append({"csatolas": r[1], "eszkoz": r[0], "tipus": r[2],
                          "osszes": ossz, "szabad": st.f_bavail * st.f_frsize,
                          "hasznalt": (st.f_blocks - st.f_bfree) * st.f_frsize,
                          "csak_olvashato": "ro" in r[3].split(",")})
        return lista

    # -- hálózat
    def _halozat(self, dt, teljes):
        akt = {}
        for sor in olvas("/proc/net/dev", "", egeszet=True).splitlines()[2:]:
            nev, adat = sor.split(":", 1)
            nev = nev.strip()
            r = adat.split()
            akt[nev] = (int(r[0]), int(r[8]))
        e = self._elozo_net
        lista = []
        ossz_rx = ossz_tx = 0
        for nev, (rx, tx) in akt.items():
            if nev == "lo":
                continue
            allapot = self._ritkan("op_" + nev, 5, lambda n=nev: olvas(f"/sys/class/net/{n}/operstate", "unknown"))
            if rx == 0 and tx == 0 and allapot != "up":
                continue
            d = {"nev": nev, "allapot": allapot, "rx_ossz": rx, "tx_ossz": tx}
            if e and nev in e and dt:
                d["rx_bps"] = max(0, int((rx - e[nev][0]) / dt))
                d["tx_bps"] = max(0, int((tx - e[nev][1]) / dt))
                ossz_rx += d["rx_bps"]
                ossz_tx += d["tx_bps"]
            if teljes:
                d["ip"] = self._ritkan("ip_" + nev, 10, lambda n=nev: ipv4_cim(n))
            lista.append(d)
        self._elozo_net = akt
        h = {"interfeszek": lista, "rx_bps": ossz_rx, "tx_bps": ossz_tx}
        if teljes:
            h["wifi"] = self._wifi()
        return h

    def _wifi(self):
        w = None
        for sor in (olvas("/proc/net/wireless", "", egeszet=True) or "").splitlines()[2:]:
            nev, adat = sor.split(":", 1)
            nev = nev.strip()
            if self._ritkan("op_" + nev, 5, lambda n=nev: olvas(f"/sys/class/net/{n}/operstate", "unknown")) != "up":
                continue
            r = adat.split()
            try:
                w = {"interfesz": nev, "minoseg": int(float(r[1])), "jel_dbm": int(float(r[2]))}
            except (ValueError, IndexError):
                continue
            break
        if w is None:
            return None
        w.update(self._ritkan("iw_" + w["interfesz"], 10, lambda n=w["interfesz"]: self._iw_link(n)))
        return w

    def _iw_link(self, nev):
        try:
            p = subprocess.run(["iw", "dev", nev, "link"], capture_output=True, text=True, timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            return {}
        d = {}
        for sor in p.stdout.splitlines():
            sor = sor.strip()
            if sor.startswith("SSID:"):
                d["ssid"] = sor[5:].strip()[:64]
            elif sor.startswith("freq:"):
                d["frekvencia_mhz"] = int(float(sor[5:].split()[0]))
            elif sor.startswith("signal:"):
                d["jel_dbm"] = int(sor[7:].split()[0])
            elif sor.startswith("tx bitrate:"):
                d["tx_mbps"] = float(sor[11:].split()[0])
            elif sor.startswith("rx bitrate:"):
                d["rx_mbps"] = float(sor[11:].split()[0])
        f = d.get("frekvencia_mhz")
        if f:
            d["sav"] = "2,4 GHz" if f < 3000 else ("5 GHz" if f < 5925 else "6 GHz")
        return d

    # -- akku
    def _akku(self):
        b = "/sys/class/power_supply/battery"
        if not os.path.isdir(b):
            return None
        aram = olvas_int(b + "/current_now")
        aram_atl = olvas_int(b + "/current_avg")
        # A Samsung-driver mA-ben ad, a szabványos µA-ben.
        def ma(x):
            return None if x is None else (x / 1000.0 if abs(x) > 20000 else float(x))
        fesz = olvas_int(b + "/voltage_now")
        fesz_v = None if fesz is None else (fesz / 1e6 if fesz > 100000 else fesz / 1000.0)
        hom = olvas_int(b + "/temp")
        tolto = None
        for ps, nev in (("ac", "hálózati"), ("usb", "USB"), ("wireless", "vezeték nélküli")):
            if olvas_int(f"/sys/class/power_supply/{ps}/online", 0) == 1:
                tolto = nev
        a = {
            "szazalek": olvas_int(b + "/capacity"),
            "allapot": olvas(b + "/status"),
            "egeszseg": olvas(b + "/health"),
            "aram_ma": kerekit(ma(aram)),
            "aram_atlag_ma": kerekit(ma(aram_atl)),
            "feszultseg_v": kerekit(fesz_v, 3),
            "homerseklet": kerekit(hom / 10.0) if hom is not None else None,
            "tolto": tolto,
            "toltes_tipus": olvas(b + "/charge_type"),
        }
        if a["aram_ma"] is not None and fesz_v:
            a["teljesitmeny_w"] = kerekit(a["aram_ma"] * fesz_v / 1000.0, 2)
        return a

    # -- képernyő, hang
    def _kepernyo(self):
        for d in sorted(os.listdir("/sys/class/backlight")) if os.path.isdir("/sys/class/backlight") else []:
            b = f"/sys/class/backlight/{d}"
            f = olvas_int(b + "/brightness", 0)
            blp = olvas_int(b + "/bl_power", 0)
            return {"be": f > 0 and blp == 0, "fenyero": f, "max": olvas_int(b + "/max_brightness")}
        return None

    def _hang(self):
        # A PipeWire a bejelentkezett felhasználóé: wpctl az ő nevében (csak olvas).
        try:
            uidok = sorted(int(u) for u in os.listdir("/run/user") if u.isdigit() and int(u) >= 1000)
        except OSError:
            uidok = []
        for uid in uidok:
            rt = f"/run/user/{uid}"
            if not os.path.exists(rt + "/pipewire-0"):
                continue
            try:
                pw = pwd.getpwuid(uid)
                p = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                                   capture_output=True, text=True, timeout=3,
                                   user=uid, group=pw.pw_gid, extra_groups=[],
                                   env={"XDG_RUNTIME_DIR": rt, "PATH": "/usr/bin:/bin"},
                                   cwd="/")
            except (OSError, KeyError, subprocess.TimeoutExpired):
                continue
            m = re.search(r"Volume:\s*([\d.]+)", p.stdout)
            if m:
                return {"hangero": int(round(float(m.group(1)) * 100)), "nemitva": "MUTED" in p.stdout}
        return None

    # -- folyamatok
    def _folyamatok(self):
        most = time.monotonic()
        dt = (most - self._elozo_proc_ido) if self._elozo_proc_ido else None
        uj = {}
        lista = []
        for p in os.listdir("/proc"):
            if not p.isdigit():
                continue
            try:
                s = olvas_b(f"/proc/{p}/stat", 1024)
            except OSError:
                continue
            i = s.find(b"(")
            j = s.rfind(b")")
            if i < 0 or j < 0:
                continue
            nev = s[i + 1:j]
            r = s[j + 2:].split(None, 23)
            try:
                ticks = int(r[11]) + int(r[12])
                rss = int(r[21]) * LAPMERET
                kezdet = int(r[19])
            except (IndexError, ValueError):
                continue
            pid = int(p)
            if nev == b"cinnamon":
                self.cinnamon_pid = pid
            kulcs = (pid, kezdet)
            uj[kulcs] = ticks
            cpu = None
            if dt:
                e = self._elozo_proc.get(kulcs)
                if e is not None:
                    cpu = max(0.0, (ticks - e) / (dt * CLK_TCK) * 100.0)
            lista.append((pid, nev, r[0], cpu or 0.0, rss))
        self._elozo_proc = uj
        self._elozo_proc_ido = most

        def kimenet(x):
            # A felhasználót csak a kiadott (≤ 2×TOP_N) folyamatnál nézzük meg.
            try:
                uid = os.stat(f"/proc/{x[0]}").st_uid
            except OSError:
                uid = -1
            return {"pid": x[0], "nev": x[1].decode(errors="replace"), "user": felhasznalonev(uid),
                    "allapot": x[2].decode(), "cpu": kerekit(x[3] / NCPU, 1),
                    "cpu_mag": kerekit(x[3], 1), "rss_bajt": x[4]}
        cpu_szerint = sorted(lista, key=lambda x: (-x[3], -x[4]))[:TOP_N]
        ram_szerint = sorted(lista, key=lambda x: -x[4])[:TOP_N]
        return {"szama": len(lista),
                "cpu_szerint": [kimenet(x) for x in cpu_szerint],
                "ram_szerint": [kimenet(x) for x in ram_szerint]}

    # -- egy kör
    def gyujt(self):
        most = time.monotonic()
        dt = (most - self._ido) if self._ido else None
        self._ido = most
        teljes = self.aktiv()
        a = {"v": 1, "ido": int(time.time() * 1000), "teljes": teljes}

        def biztos(kulcs, fv, *arg):
            try:
                a[kulcs] = fv(*arg)
            except Exception as hiba:
                a[kulcs] = None
                print(f"!! {kulcs}: {hiba!r}", file=sys.stderr, flush=True)

        biztos("cpu", self._cpu, dt)
        biztos("gpu", self._gpu, teljes)
        biztos("memoria", self._memoria, teljes)
        biztos("homersekletek", self._homersekletek)
        biztos("halozat", self._halozat, dt, teljes)
        biztos("akku", self._akku)
        lemez_io = None
        try:
            lemez_io = self._lemez_io(dt)
        except Exception as hiba:
            print(f"!! lemez: {hiba!r}", file=sys.stderr, flush=True)
        if teljes:
            st = self._statikus
            up = olvas("/proc/uptime", "0").split()[0]
            a["gep"] = {"nev": st["nev"], "os": st["os"], "kernel": st["kernel"],
                        "uptime_s": int(float(up)), "ugynok": VERZIO}
            a["lemez"] = {"eszkozok": lemez_io,
                          "fajlrendszerek": self._ritkan("fs", 5, self._fajlrendszerek)}
            biztos("kepernyo", self._kepernyo)
            a["hang"] = self._ritkan("hang", 5, self._hang)
            # A folyamatlista a legdrágább rész (~300 /proc/<pid>/stat): 2 s-onként.
            # Kliens nélküli időszak után az első kör csak alapvonal (a CPU-%
            # két minta különbsége), a lista a következő körben jön.
            if self._elozo_proc_ido is None:
                try:
                    self._folyamatok()
                except Exception as hiba:
                    print(f"!! folyamatok: {hiba!r}", file=sys.stderr, flush=True)
                a["folyamatok"] = None
            else:
                a["folyamatok"] = self._ritkan("folyamatok", 1.9, self._folyamatok)
        else:
            # Kliens nélkül nincs folyamatlista; a következő aktív körben az
            # első CPU-érték ezért még hiányozhat (nincs előző minta).
            self._elozo_proc = {}
            self._elozo_proc_ido = None
            self._gyors.pop("folyamatok", None)

        # Tömör minta a görbékhez.
        cpu = a.get("cpu") or {}
        mem = a.get("memoria") or {}
        gpu = a.get("gpu") or {}
        hal = a.get("halozat") or {}
        akku = a.get("akku") or {}
        minta = {
            "t": a["ido"],
            "cpu": cpu.get("osszes"),
            "magok": [m.get("szazalek") for m in cpu.get("magok", [])],
            "mhz": [m.get("mhz") for m in cpu.get("magok", [])],
            "gpu": gpu.get("szazalek"),
            "gpu_mhz": gpu.get("mhz"),
            "ram": mem.get("hasznalt"),
            "swap": mem.get("swap_hasznalt"),
            "hom": {h["nev"]: h["c"] for h in (a.get("homersekletek") or [])},
            "rx": hal.get("rx_bps"),
            "tx": hal.get("tx_bps"),
            "olv": sum(d.get("olvasas_bps", 0) for d in (lemez_io or []) if not d["nev"].startswith("zram")),
            "ir": sum(d.get("iras_bps", 0) for d in (lemez_io or []) if not d["nev"].startswith("zram")),
            "akku_ma": akku.get("aram_ma"),
        }
        if gpu.get("homerseklet") is not None:
            minta["hom"]["GPU"] = gpu["homerseklet"]
        if akku.get("homerseklet") is not None:
            minta["hom"]["akku"] = akku["homerseklet"]
        a["statikus"] = {"magok": len(self._statikus["magok"]),
                         "gpu_frekvenciak_mhz": self._statikus["gpu_frekvenciak_mhz"]}
        adat = json.dumps(a, ensure_ascii=False, separators=(",", ":")).encode()
        with self.zar:
            self.allapot_json = adat
            # „Teljes” = minden rész megvan, a folyamatlistával együtt.
            self.teljes = teljes and a.get("folyamatok") is not None
            if dt is not None:
                self.elozmeny.append(minta)
            self.sorszam += 1
            self.zar.notify_all()

    def fut(self):
        kov = time.monotonic()
        while True:
            try:
                self.gyujt()
            except Exception as hiba:
                print(f"!! gyűjtés: {hiba!r}", file=sys.stderr, flush=True)
            kov += 1.0
            var = kov - time.monotonic()
            if var < 0:           # lemaradtunk (pl. alvás után): nincs pótlás
                kov = time.monotonic()
                var = 0.2
            time.sleep(var)

    def elozmeny_json(self):
        with self.zar:
            m = list(self.elozmeny)
        return json.dumps({"v": 1, "lepes_ms": 1000, "mintak": m},
                          ensure_ascii=False, separators=(",", ":")).encode()


# ---------------------------------------------------------------- HTTP

class Korlat:
    def __init__(self):
        self.zar = threading.Lock()
        self.keresek = collections.defaultdict(collections.deque)
        self.folyam_ip = collections.Counter()
        self.kapcsolatok = 0

    def keres(self, ip):
        n, ablak = KERES_KORLAT
        most = time.monotonic()
        with self.zar:
            q = self.keresek[ip]
            while q and most - q[0] > ablak:
                q.popleft()
            if len(q) >= n:
                return False
            q.append(most)
            if len(self.keresek) > 256:          # elfelejtett IP-k takarítása
                for k in [k for k, v in self.keresek.items() if not v]:
                    del self.keresek[k]
            return True


GY = Gyujto()
KORLAT = Korlat()


def engedett(ip):
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    if a.version == 6 and a.ipv4_mapped:
        a = a.ipv4_mapped
    return a.version == 4 and any(a in h for h in ENGEDETT_HALOK)


class Kiszolgalo(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 16

    def verify_request(self, request, client_address):
        if not engedett(client_address[0]):
            return False
        with KORLAT.zar:
            if KORLAT.kapcsolatok >= MAX_KAPCSOLAT:
                return False
            KORLAT.kapcsolatok += 1
        return True

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            with KORLAT.zar:
                KORLAT.kapcsolatok -= 1


class Kezelo(BaseHTTPRequestHandler):
    server_version = "mamuthka-eroforras/" + VERZIO
    sys_version = ""
    protocol_version = "HTTP/1.1"
    timeout = 15

    def log_message(self, fmt, *args):
        pass                      # nincs kérésnapló (kíméli a lemezt)

    def _valasz(self, kod, adat, tipus="application/json; charset=utf-8", fej=True):
        self.send_response(kod)
        self.send_header("Content-Type", tipus)
        self.send_header("Content-Length", str(len(adat)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if fej:
            self.wfile.write(adat)

    def _hiba(self, kod, uzenet):
        self._valasz(kod, json.dumps({"hiba": uzenet}, ensure_ascii=False).encode())

    def do_HEAD(self):
        self.do_GET(fej=False)

    def do_GET(self, fej=True):
        ip = self.client_address[0]
        if not KORLAT.keres(ip):
            self.close_connection = True
            return self._hiba(429, "túl sok kérés")
        ut = self.path.split("?", 1)[0].rstrip("/") or "/"
        if ut == "/api/v1/allapot":
            GY.utolso_igeny = time.monotonic()
            # Ha eddig nem volt kliens, a teljes adatot a következő kör adja.
            with GY.zar:
                GY.zar.wait_for(lambda: GY.teljes, timeout=4.0)
                adat = GY.allapot_json
            return self._valasz(200, adat, fej=fej)
        if ut == "/api/v1/elozmeny":
            GY.utolso_igeny = time.monotonic()
            return self._valasz(200, GY.elozmeny_json(), fej=fej)
        if ut == "/api/v1/folyam" and fej:
            return self._folyam(ip)
        if ut in ("/", "/api", "/api/v1"):
            return self._valasz(200, json.dumps({
                "szolgaltatas": "Mamuthka erőforrás-ügynök", "verzio": VERZIO,
                "vegpontok": ["/api/v1/allapot", "/api/v1/folyam", "/api/v1/elozmeny"]},
                ensure_ascii=False).encode(), fej=fej)
        return self._hiba(404, "nincs ilyen végpont")

    def do_POST(self):
        self.close_connection = True
        self._hiba(405, "csak olvasható")

    do_PUT = do_DELETE = do_PATCH = do_POST

    def _folyam(self, ip):
        with KORLAT.zar:
            if GY.folyamok >= MAX_FOLYAM or KORLAT.folyam_ip[ip] >= MAX_FOLYAM_IP:
                ok = False
            else:
                ok = True
                GY.folyamok += 1
                KORLAT.folyam_ip[ip] += 1
        if not ok:
            self.close_connection = True
            return self._hiba(429, "túl sok egyidejű folyam")
        self.close_connection = True
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            self.wfile.write(b"retry: 2000\n\n")
            self.wfile.flush()
            kezdet = time.monotonic()
            utolso = -1
            with GY.zar:           # az első esemény már teljes adatot vigyen
                GY.zar.wait_for(lambda: GY.teljes, timeout=4.0)
            while time.monotonic() - kezdet < FOLYAM_MAX_IDO:
                with GY.zar:
                    if GY.sorszam == utolso:
                        GY.zar.wait(3.0)
                    if GY.sorszam == utolso:
                        adat = None
                    else:
                        utolso = GY.sorszam
                        adat = GY.allapot_json
                if adat is None:
                    self.wfile.write(b": eletjel\n\n")
                else:
                    self.wfile.write(b"event: allapot\nid: %d\ndata: " % utolso + adat + b"\n\n")
                self.wfile.flush()
        except (OSError, ValueError):
            pass
        finally:
            with KORLAT.zar:
                GY.folyamok -= 1
                KORLAT.folyam_ip[ip] -= 1
                if KORLAT.folyam_ip[ip] <= 0:
                    del KORLAT.folyam_ip[ip]


def main():
    try:
        os.nice(5)
    except OSError:
        pass
    threading.Thread(target=GY.fut, name="gyujto", daemon=True).start()
    srv = Kiszolgalo((CIM, PORT), Kezelo)
    print(f"Mamuthka erőforrás-ügynök {VERZIO}: {CIM}:{PORT}", flush=True)
    srv.serve_forever(poll_interval=1.0)


if __name__ == "__main__":
    main()
