#!/usr/bin/env python3
"""dftlinux – Xiaomi Redmi Note 14 4G (MediaTek Helio G99 Ultra) szerviz-eszköz Linuxra.

adb + fastboot + mtkclient (BROM mód) burkoló. Csak saját telefonon használd.
Telepítés: sudo apt install adb fastboot ; pip install mtkclient
"""
import argparse, shutil, subprocess, sys

INSTALL = {"adb": "adb", "fastboot": "fastboot", "mtk": "pip install mtkclient"}


def run(cmd):
    if not shutil.which(cmd[0]):
        sys.exit(f"Hiányzik: {cmd[0]}  ({INSTALL.get(cmd[0], cmd[0])})")
    return subprocess.call(cmd)


def confirm(a, what):
    if not a.yes and input(f"{what} – biztosan? (igen/nem) ") != "igen":
        sys.exit("Megszakítva.")


def info(a):
    run(["adb", "devices", "-l"])
    for p in ["ro.product.model", "ro.product.device", "ro.mi.os.version.name",
              "ro.build.version.release", "ro.build.version.security_patch",
              "ro.boot.verifiedbootstate", "ro.boot.flash.locked", "ro.serialno"]:
        print(f"{p:32}", end="", flush=True)
        run(["adb", "shell", "getprop", p])


def fbinfo(a):
    sys.exit(run(["fastboot", "getvar", "all"]))


def reboot(a):
    if a.mode == "edl":
        sys.exit("A MediaTek nem EDL-t használ: kapcsold ki, tartsd a Hangerő le-t, és USB-zd (BROM).")
    if a.fastboot_mode:
        sys.exit(run(["fastboot", "reboot"] + ([] if a.mode == "normal" else [a.mode])))
    sys.exit(run(["adb", "reboot"] + ([] if a.mode == "normal" else [a.mode])))


def flash(a):
    confirm(a, f"Írás: {a.part} <- {a.img}")
    sys.exit(run(["fastboot", "flash", a.part, a.img]))


def unlock(a):
    confirm(a, "Bootloader-feloldás (MINDEN adat törlődik; előbb a Mi Unlock engedély kell)")
    sys.exit(run(["fastboot", "flashing", "unlock"]))


def lock(a):
    confirm(a, "Bootloader zárása (csak eredeti ROM-mal!)")
    sys.exit(run(["fastboot", "flashing", "lock"]))


def fastbootrom(a):
    confirm(a, f"Fastboot ROM telepítése: {a.dir}")
    sys.exit(run(["bash", f"{a.dir}/flash_all.sh"]))


def brom_dump(a):
    sys.exit(run(["mtk", "r", a.part, a.out]))


def brom_flash(a):
    confirm(a, f"BROM írás: {a.part} <- {a.img}")
    sys.exit(run(["mtk", "w", a.part, a.img]))


def brom_gpt(a):
    sys.exit(run(["mtk", "printgpt"]))


def sideload(a):
    sys.exit(run(["adb", "sideload", a.zip]))


def install(a):
    sys.exit(run(["adb", "install", "-r", a.apk]))


def logcat(a):
    sys.exit(run(["adb", "logcat"]))


def main():
    p = argparse.ArgumentParser(prog="dftlinux", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("-y", "--yes", action="store_true", help="megerősítés nélkül")
    s = p.add_subparsers(dest="c", required=True)
    def add(n, f, h, *args):
        x = s.add_parser(n, help=h); x.set_defaults(f=f)
        for ar in args: x.add_argument(ar)
        return x
    add("info", info, "eszközinfó (adb)")
    add("fbinfo", fbinfo, "fastboot getvar all")
    r = add("reboot", reboot, "újraindítás")
    r.add_argument("mode", choices=["normal", "recovery", "bootloader", "fastboot"])
    r.add_argument("--fastboot-mode", action="store_true", help="fastboot-ból indítsa")
    add("flash", flash, "partíció írása fastbooton", "part", "img")
    add("unlock", unlock, "bootloader feloldása"); add("lock", lock, "bootloader zárása")
    add("fastbootrom", fastbootrom, "kicsomagolt fastboot ROM telepítése", "dir")
    add("brom-gpt", brom_gpt, "partíciótábla (BROM, mtkclient)")
    add("brom-dump", brom_dump, "partíció mentése BROM-on", "part", "out")
    add("brom-flash", brom_flash, "partíció írása BROM-on", "part", "img")
    add("sideload", sideload, "zip sideload recoveryben", "zip")
    add("install", install, "APK telepítése", "apk")
    add("logcat", logcat, "napló")
    a = p.parse_args(); a.f(a)


if __name__ == "__main__":
    main()
