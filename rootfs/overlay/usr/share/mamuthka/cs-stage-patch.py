#!/usr/bin/python3
"""cinnamon-screensaver 6.0 stage.py javítása (Mamuthka linux).

Használat: cs-stage-patch.py <eredeti stage.py> <kimenet>

1. update_geometry(): a get_screen_geometry() már a teljes képernyőt adja,
   a skálával (2) való újabb szorzás 2160×4800-as stage-ablakot eredményez,
   amit a cinnamon llvmpipe-pal rajzol (~450% CPU, hibak.txt 61.).
2. position_overlay_child(): álló kijelzőn, lebegő widgetek nélkül
   (floating-widgets=false) az óra vízszintesen középen, az alja a
   háttérkép mamutfeje (a képernyő ~27%-a) fölött – ébren és alvó
   állapotban is.
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()


def rep(old, new):
    global s
    if s.count(old) != 1:
        sys.exit("cs-stage-patch: a minta nem pontosan egyszer szerepel: %r" % old[:60])
    s = s.replace(old, new)


rep("""            scale = status.screen.get_global_scale()
            self.rect.width *= scale
            self.rect.height *= scale
""", "")

rep("""        if isinstance(child, ClockWidget) or isinstance(child, AlbumArt):
""", """        if isinstance(child, ClockWidget) and not settings.get_allow_floating():
            # Mamuthka: álló kijelzőn az óra középen, a háttérkép mamutfeje
            # (a képernyő ~27%-a) fölött; ébren és alvó állapotban is.
            if status.Awake:
                current_monitor = status.screen.get_mouse_monitor()
            else:
                current_monitor = child.current_monitor
            monitor_rect = status.screen.get_monitor_geometry(current_monitor)
            if monitor_rect.height > monitor_rect.width:
                min_rect, nat_rect = child.get_preferred_size()
                label = getattr(child, "label", None)
                if label is not None:
                    label.set_justify(Gtk.Justification.CENTER)
                allocation.width = int(min(nat_rect.width, monitor_rect.width))
                allocation.height = int(min(nat_rect.height, monitor_rect.height * 0.25))
                allocation.x = int(monitor_rect.x + (monitor_rect.width - allocation.width) / 2)
                allocation.y = int(monitor_rect.y + max(monitor_rect.height * 0.01,
                                                        monitor_rect.height * 0.255 - allocation.height))
                return True

        if isinstance(child, ClockWidget) or isinstance(child, AlbumArt):
""")

compile(s, dst, "exec")
with open(dst, "w", encoding="utf-8") as f:
    f.write(s)
