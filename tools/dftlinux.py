#!/usr/bin/env python3
"""dftlinux – Samsung telefon szerviz-eszköz Linuxra (heimdall/adb/fastboot burkoló).

Funkciók: eszközinfó, újraindítás módokba, firmware-flash, partíciólista,
partíció mentése/írása, ADB logcat, APK telepítés, shell.
Csak a saját, feloldott telefonodon használd.
"""
import argparse, shutil, subprocess, sys


def need(tool):
    if not shutil.which(tool):
        sys.exit(f"Hiányzik: {tool}  (sudo apt install {'heimdall-flash' if tool=='heimdall' else 'adb fastboot'})")


def run(cmd):
    need(cmd[0])
    return subprocess.call(cmd)


def cmd_info(a):
    run(["adb", "devices", "-l"])
    for p in ["ro.product.model", "ro.product.device", "ro.build.version.release",
              "ro.build.version.security_patch", "ro.boot.flash.locked",
              "ro.boot.verifiedbootstate", "ro.serialno", "gsm.version.baseband"]:
        print(f"{p:35}", end="", flush=True)
        run(["adb", "shell", "getprop", p])
    run(["adb", "shell", "dumpsys", "battery"])


def cmd_reboot(a):
    if a.mode == "download":
        run(["adb", "reboot", "download"])
    elif a.mode == "normal":
        run(["adb", "reboot"])
    else:
        run(["adb", "reboot", a.mode])


def cmd_detect(a):
    sys.exit(run(["heimdall", "detect"]))


def cmd_pit(a):
    sys.exit(run(["heimdall", "print-pit", "--no-reboot"]))


def cmd_flash(a):
    cmd = ["heimdall", "flash"]
    for item in a.part:
        name, _, path = item.partition("=")
        if not path:
            sys.exit(f"Hibás formátum: {item} (PARTÍCIÓ=fájl)")
        cmd += [f"--{name}", path]
    if a.no_reboot:
        cmd.append("--no-reboot")
    if not a.yes and input("Biztosan írod? (igen/nem) ") != "igen":
        sys.exit("Megszakítva.")
    sys.exit(run(cmd))


def cmd_download(a):
    sys.exit(run(["heimdall", "download", "--" + a.part, "-o", a.out, "--no-reboot"]))


def cmd_install(a):
    sys.exit(run(["adb", "install", "-r", a.apk]))


def cmd_logcat(a):
    sys.exit(run(["adb", "logcat"]))


def cmd_shell(a):
    sys.exit(run(["adb", "shell"] + a.args))


def cmd_backup(a):
    sys.exit(run(["adb", "backup", "-apk", "-shared", "-all", "-f", a.out]))


def main():
    p = argparse.ArgumentParser(prog="dftlinux", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest="c", required=True)
    s.add_parser("info", help="eszközinfó (adb)").set_defaults(f=cmd_info)
    r = s.add_parser("reboot", help="újraindítás módba")
    r.add_argument("mode", choices=["normal", "download", "recovery", "bootloader"])
    r.set_defaults(f=cmd_reboot)
    s.add_parser("detect", help="Download módú telefon keresése").set_defaults(f=cmd_detect)
    s.add_parser("pit", help="PIT (partíciótábla) kiolvasása").set_defaults(f=cmd_pit)
    f = s.add_parser("flash", help="partíciók írása: dftlinux flash BOOT=boot.img")
    f.add_argument("part", nargs="+")
    f.add_argument("--no-reboot", action="store_true")
    f.add_argument("-y", "--yes", action="store_true")
    f.set_defaults(f=cmd_flash)
    d = s.add_parser("download", help="partíció mentése fájlba")
    d.add_argument("part"); d.add_argument("out"); d.set_defaults(f=cmd_download)
    i = s.add_parser("install", help="APK telepítése"); i.add_argument("apk"); i.set_defaults(f=cmd_install)
    s.add_parser("logcat", help="napló").set_defaults(f=cmd_logcat)
    sh = s.add_parser("shell", help="adb shell"); sh.add_argument("args", nargs="*"); sh.set_defaults(f=cmd_shell)
    b = s.add_parser("backup", help="adb backup"); b.add_argument("out"); b.set_defaults(f=cmd_backup)
    a = p.parse_args(); a.f(a)


if __name__ == "__main__":
    main()
