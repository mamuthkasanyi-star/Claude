/*
 * rui – Mamuthka Recovery UI
 *
 * Kis, statikusan fordított framebuffer-felület a recovery shell-scriptjeihez.
 * Érintéssel és gombokkal is kezelhető (Hangerő fel/le: léptetés/lapozás,
 * Bekapcsoló hosszan: kiválasztás, röviden: kijelző ki/be). RUI_IDLE
 * másodperc tétlenség után (alapértelmezés 120, 0 = soha) a háttérvilágítás
 * kikapcsol; ilyenkor bármely gomb vagy érintés csak ébreszt.
 *
 *   rui menu  "Cím" "Elem 1" "Elem 2" ...   → kiírja a választott sorszámot (0-tól)
 *   rui msg   "Cím" "Szöveg"                → üzenet "OK" gombbal
 *   rui ask   "Cím" "Szöveg"                → Igen/Nem; kilépési kód 0 = igen
 *   rui input "Cím" [--password]            → képernyő-billentyűzet; kiírja a szöveget
 *   rui pipe  "Cím" ÖSSZES_BÁJT             → stdin → stdout másolás folyamatjelzővel
 *   rui status "Cím" "Szöveg"               → kiírja és azonnal kilép
 *   rui view  "Cím" FÁJL                    → görgethető szövegnézet (napló);
 *                                             a végén nyílik meg
 *   rui reboot [recovery|download|poweroff] → újraindítás (Samsung reboot okkal)
 *
 * Környezet: RUI_FONT (PSF2 betűtípus), RUI_FB (alapértelmezés /dev/fb0),
 * RUI_BATT (akku sysfs-mappa, alapértelmezés /sys/class/power_supply/battery),
 * RUI_BL (háttérvilágítás brightness-fájlja, alapértelmezés az első
 * /sys/class/backlight/ eszköz; "none" = nincs kijelző-kikapcsolás).
 * A szövegekben '\n' sortörést jelent. Minden szöveg a kijelző szélességéhez
 * tördelődik, ami nem fér el, az "…"-vel rövidül (semmi sem lóghat ki).
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/reboot.h>
#include <poll.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <unistd.h>

/* ---------- színek ---------- */
#define C_BG      0x0b1838   /* sötétkék háttér */
#define C_TITLE   0xff2a2a
#define C_TEXT    0xeef0f6
#define C_DIM     0x8090b0
#define C_BTN     0x000000   /* fekete gombok */
#define C_BTN_SEL 0x000000
#define C_BORDER  0x1a1a1a
#define C_GLOW    0xff1010   /* a gombok alól kiszűrődő piros fény */

/* ---------- framebuffer ---------- */
static int fb_fd = -1;
static uint8_t *fb_mem;
static uint32_t *back; /* hátsó puffer, 0xRRGGBB */
static int W, H, bpp, stride;
static struct fb_var_screeninfo vinfo;

static void fb_open(void)
{
	const char *dev = getenv("RUI_FB") ? getenv("RUI_FB") : "/dev/fb0";
	struct fb_fix_screeninfo finfo;
	const char *fake = getenv("RUI_FAKE"); /* teszteléshez: "SZÉLxMAG", RUI_FB egy sima fájl */
	fb_fd = open(dev, O_RDWR | (fake ? O_CREAT : 0), 0644);
	if (fb_fd < 0) { perror(dev); exit(2); }
	if (fake && sscanf(fake, "%dx%d", &W, &H) == 2) {
		memset(&vinfo, 0, sizeof vinfo);
		vinfo.xres = W; vinfo.yres = H; vinfo.bits_per_pixel = bpp = 32; stride = W * 4;
		vinfo.red = (struct fb_bitfield){ 16, 8, 0 };
		vinfo.green = (struct fb_bitfield){ 8, 8, 0 };
		vinfo.blue = (struct fb_bitfield){ 0, 8, 0 };
		if (ftruncate(fb_fd, (off_t)stride * H)) { perror("ftruncate"); exit(2); }
		fb_mem = mmap(NULL, (size_t)stride * H, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd, 0);
		back = calloc((size_t)W * H, 4);
		return;
	}
	/* Nincs FBIOBLANK(UNBLANK): a kijelző már be van kapcsolva, a hívás a
	 * DECON-hackben csak egy 200 ms-os "needs_pan" versenyhelyzetet indítana. */
	if (ioctl(fb_fd, FBIOGET_VSCREENINFO, &vinfo) || ioctl(fb_fd, FBIOGET_FSCREENINFO, &finfo)) {
		perror("fb ioctl"); exit(2);
	}
	W = vinfo.xres; H = vinfo.yres; bpp = vinfo.bits_per_pixel; stride = finfo.line_length;
	fb_mem = mmap(NULL, finfo.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd, 0);
	if (fb_mem == MAP_FAILED) { perror("mmap"); exit(2); }
	back = calloc((size_t)W * H, 4);
}

static inline uint32_t pack(uint32_t c)
{
	uint32_t r = (c >> 16) & 0xff, g = (c >> 8) & 0xff, b = c & 0xff;
	return (r >> (8 - vinfo.red.length)) << vinfo.red.offset |
	       (g >> (8 - vinfo.green.length)) << vinfo.green.offset |
	       (b >> (8 - vinfo.blue.length)) << vinfo.blue.offset |
	       (vinfo.transp.length ? ((0xffu >> (8 - vinfo.transp.length)) << vinfo.transp.offset) : 0);
}

static int blanked; /* a háttérvilágítást mi kapcsoltuk ki */

static void flip(void)
{
	int x, y;
	if (blanked) return; /* sötét kijelzőn felesleges munka */
	uint8_t *base = fb_mem + (size_t)vinfo.yoffset * stride;
	for (y = 0; y < H; y++) {
		uint8_t *row = base + (size_t)y * stride;
		uint32_t *src = back + (size_t)y * W;
		if (bpp == 32) {
			uint32_t *d = (uint32_t *)row;
			for (x = 0; x < W; x++) d[x] = pack(src[x]);
		} else if (bpp == 16) {
			uint16_t *d = (uint16_t *)row;
			for (x = 0; x < W; x++) d[x] = (uint16_t)pack(src[x]);
		}
	}
	/* A DECON parancsmódú panelnél a pan_display váltja ki a frissítést. */
	ioctl(fb_fd, FBIOPAN_DISPLAY, &vinfo);
}

static void rect(int x, int y, int w, int h, uint32_t c)
{
	int i, j;
	if (x < 0) { w += x; x = 0; }
	if (y < 0) { h += y; y = 0; }
	if (x + w > W) w = W - x;
	if (y + h > H) h = H - y;
	for (j = 0; j < h; j++)
		for (i = 0; i < w; i++) back[(size_t)(y + j) * W + x + i] = c;
}

static uint32_t blend(uint32_t a, uint32_t b, int t) /* t: 0..256, b súlya */
{
	uint32_t r = (((a >> 16) & 0xff) * (256 - t) + ((b >> 16) & 0xff) * t) >> 8;
	uint32_t g = (((a >> 8) & 0xff) * (256 - t) + ((b >> 8) & 0xff) * t) >> 8;
	uint32_t bl = ((a & 0xff) * (256 - t) + (b & 0xff) * t) >> 8;
	return r << 16 | g << 8 | bl;
}

/* Piros fény a gomb alatt: lefelé és oldalra halványuló sáv. */
static void glow_under(int x, int y, int w, int h, int strength)
{
	int spread = h / 2, i, j;
	for (j = 0; j < spread; j++) {
		int t = strength * (spread - j) / spread;
		int yy = y + h - spread / 3 + j;
		if (yy < 0 || yy >= H) continue;
		for (i = x - spread / 2; i < x + w + spread / 2; i++) {
			int edge = i < x ? x - i : (i >= x + w ? i - (x + w) + 1 : 0);
			int tt = t * (spread / 2 - edge) / (spread / 2);
			if (i < 0 || i >= W || tt <= 0) continue;
			back[(size_t)yy * W + i] = blend(back[(size_t)yy * W + i], C_GLOW, tt);
		}
	}
}

static void frame(int x, int y, int w, int h, uint32_t fill, uint32_t border)
{
	rect(x, y, w, h, border);
	rect(x + 3, y + 3, w - 6, h - 6, fill);
}

/* ---------- PSF2 betűtípus, UTF-8 ---------- */
struct glyphmap { uint32_t cp; uint32_t idx; };
static uint8_t *font_data;
static uint32_t font_count, font_w, font_h, font_bpg;
static struct glyphmap *gmap;
static size_t gmap_n;
static int scale = 2;

static uint32_t utf8_next(const char **s)
{
	const unsigned char *p = (const unsigned char *)*s;
	uint32_t c = *p++;
	if (c >= 0xf0 && p[0] && p[1] && p[2]) { c = (c & 7) << 18 | (p[0] & 63) << 12 | (p[1] & 63) << 6 | (p[2] & 63); p += 3; }
	else if (c >= 0xe0 && p[0] && p[1]) { c = (c & 15) << 12 | (p[0] & 63) << 6 | (p[1] & 63); p += 2; }
	else if (c >= 0xc0 && p[0]) { c = (c & 31) << 6 | (p[0] & 63); p += 1; }
	*s = (const char *)p;
	return c;
}

static int gcmp(const void *a, const void *b)
{
	uint32_t x = ((const struct glyphmap *)a)->cp, y = ((const struct glyphmap *)b)->cp;
	return x < y ? -1 : x > y;
}

static void font_load(void)
{
	const char *path = getenv("RUI_FONT") ? getenv("RUI_FONT") : "/usr/share/rui/font.psf";
	FILE *f = fopen(path, "rb");
	long len;
	uint8_t *buf;
	uint32_t hdrsize, flags;
	if (!f) { perror(path); exit(2); }
	fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
	buf = malloc(len);
	if (fread(buf, 1, len, f) != (size_t)len) { perror("font"); exit(2); }
	fclose(f);
	if (len < 32 || memcmp(buf, "\x72\xb5\x4a\x86", 4)) { fprintf(stderr, "nem PSF2 betűtípus\n"); exit(2); }
	memcpy(&hdrsize, buf + 8, 4); memcpy(&flags, buf + 12, 4);
	memcpy(&font_count, buf + 16, 4); memcpy(&font_bpg, buf + 20, 4);
	memcpy(&font_h, buf + 24, 4); memcpy(&font_w, buf + 28, 4);
	font_data = buf + hdrsize;
	if (flags & 1) { /* unicode tábla */
		const char *p = (const char *)font_data + (size_t)font_count * font_bpg, *end = (const char *)buf + len;
		uint32_t idx = 0;
		gmap = malloc(sizeof(*gmap) * 4096);
		while (p < end && idx < font_count) {
			unsigned char c = (unsigned char)*p;
			if (c == 0xff) { idx++; p++; continue; }
			if (c == 0xfe) { /* szekvencia – kihagyjuk */
				while (p < end && (unsigned char)*p != 0xff) p++;
				continue;
			}
			if (gmap_n % 4096 == 0 && gmap_n) gmap = realloc(gmap, sizeof(*gmap) * (gmap_n + 4096));
			gmap[gmap_n].cp = utf8_next(&p);
			gmap[gmap_n++].idx = idx;
		}
		qsort(gmap, gmap_n, sizeof(*gmap), gcmp);
	}
	/* Kb. 34 karakter férjen el egy sorban. */
	scale = (W + (int)font_w * 17) / (int)(font_w * 34);
	if (scale < 1) scale = 1;
}

static uint32_t glyph_index(uint32_t cp)
{
	if (gmap_n) {
		size_t lo = 0, hi = gmap_n;
		while (lo < hi) {
			size_t mid = (lo + hi) / 2;
			if (gmap[mid].cp == cp) return gmap[mid].idx;
			if (gmap[mid].cp < cp) lo = mid + 1; else hi = mid;
		}
		return cp == '?' ? 0 : glyph_index('?');
	}
	return cp < font_count ? cp : '?';
}

#define CW ((int)font_w * scale)
#define CH ((int)font_h * scale)

static void draw_char(int x, int y, uint32_t cp, uint32_t c, int sc)
{
	const uint8_t *g = font_data + (size_t)glyph_index(cp) * font_bpg;
	int rowbytes = (font_w + 7) / 8, gx, gy;
	for (gy = 0; gy < (int)font_h; gy++)
		for (gx = 0; gx < (int)font_w; gx++)
			if (g[gy * rowbytes + gx / 8] & (0x80 >> (gx % 8)))
				rect(x + gx * sc, y + gy * sc, sc, sc, c);
}

static int text_len(const char *s)
{
	int n = 0;
	while (*s && *s != '\n') { utf8_next(&s); n++; }
	return n;
}

static int span_len(const char *s, int bytes)
{
	const char *e = s + bytes;
	int n = 0;
	while (s < e && *s) { utf8_next(&s); n++; }
	return n;
}

/* Legfeljebb maxc karakter kiírása (bájthatár: bytes, -1 = sor végéig);
 * ha a szöveg hosszabb, "…" zárja. Visszaadja a kiírt karakterek számát. */
static int draw_span(int x, int y, const char *s, int bytes, int maxc, uint32_t c, int sc)
{
	const char *e = bytes < 0 ? NULL : s + bytes;
	int total = 0, n = 0;
	{ const char *p = s; while (*p && *p != '\n' && (!e || p < e)) { utf8_next(&p); total++; } }
	if (maxc < 1) return 0;
	while (*s && *s != '\n' && (!e || s < e)) {
		if (total > maxc && n == maxc - 1) { draw_char(x, y, 0x2026, c, sc); return n + 1; }
		draw_char(x, y, utf8_next(&s), c, sc);
		x += font_w * sc; n++;
	}
	return n;
}

/* Középre igazított egy sor: ha nem fér el, kisebb betűvel, végül "…"-vel. */
static void draw_text_center(int y, const char *s, uint32_t c, int sc)
{
	int len = text_len(s), maxw = W - (int)font_w * 2, maxc;
	while (sc > 1 && len * (int)font_w * sc > maxw) sc--;
	maxc = maxw / ((int)font_w * sc);
	if (len > maxc) len = maxc;
	draw_span((W - len * (int)font_w * sc) / 2, y, s, -1, maxc, c, sc);
}

/* Szóhatáron tördelés: sor = (kezdet, bájthossz). A túl hosszú szavakat
 * (útvonal, SSID) karakterhatáron vágja. Visszaadja a sorok számát; *rest a
 * maxn sor után megmaradt szöveg (üres = minden elfért). */
struct span { const char *p; int n; };

static int wrap_lines(const char *s, int maxc, struct span *out, int maxn, const char **rest)
{
	int k = 0;
	if (maxc < 1) maxc = 1;
	while (*s && k < maxn) {
		const char *p = s, *lastsp = NULL, *brk;
		int n = 0;
		while (*p && *p != '\n' && n < maxc) {
			if (*p == ' ') lastsp = p;
			utf8_next(&p); n++;
		}
		if (!*p || *p == '\n' || *p == ' ') brk = p;
		else brk = (lastsp && lastsp > s) ? lastsp : p;
		out[k].p = s; out[k].n = (int)(brk - s); k++;
		s = brk;
		if (*s == ' ' || *s == '\n') s++;
	}
	if (rest) *rest = s;
	return k;
}

/* Tördelés tetszőleges hosszra (napló): dinamikus tömb. */
static struct span *wrap_all(const char *s, int maxc, int *n)
{
	int cap = 256, k = 0;
	struct span *v = malloc(sizeof(*v) * cap);
	while (*s) {
		const char *rest;
		if (k + 64 > cap) { cap *= 2; v = realloc(v, sizeof(*v) * cap); }
		k += wrap_lines(s, maxc, v + k, 64, &rest);
		s = rest;
	}
	*n = k;
	return v;
}

/* ---------- akku a jobb felső sarokban ---------- */
static int batt_pct = -1, batt_chg;

static int read_int_file(const char *dir, const char *name, char *buf, size_t sz)
{
	char p[256];
	FILE *f;
	size_t r;
	snprintf(p, sizeof p, "%s/%s", dir, name);
	if (!(f = fopen(p, "r"))) return -1;
	r = fread(buf, 1, sz - 1, f);
	fclose(f);
	buf[r] = 0;
	return 0;
}

/* 1, ha változott a kijelzett érték */
static int batt_read(void)
{
	const char *dir = getenv("RUI_BATT") ? getenv("RUI_BATT") : "/sys/class/power_supply/battery";
	char b[64];
	int pct = -1, chg = 0, changed;
	if (!read_int_file(dir, "capacity", b, sizeof b)) pct = atoi(b);
	if (pct > 100) pct = 100;
	if (!read_int_file(dir, "status", b, sizeof b))
		chg = !strncmp(b, "Charging", 8) || !strncmp(b, "Full", 4);
	changed = pct != batt_pct || chg != batt_chg;
	batt_pct = pct; batt_chg = chg;
	return changed;
}

static void draw_battery(void)
{
	char t[16];
	int fw = (int)font_w, fh = (int)font_h;
	int bw = fw * 2 + fw / 2, bh = fh / 2, x, y = fh / 4, len;
	uint32_t col;
	if (batt_pct < 0) return;
	snprintf(t, sizeof t, "%s%d%%", batt_chg ? "+" : "", batt_pct);
	len = text_len(t);
	x = W - fw - 4 - bw;
	col = batt_chg ? 0x34d058 : (batt_pct <= 15 ? C_TITLE : C_TEXT);
	rect(x, y + fh / 4, bw, bh, C_TEXT);
	rect(x + 2, y + fh / 4 + 2, bw - 4, bh - 4, C_BG);
	rect(x + bw, y + fh / 4 + bh / 4, 4, bh / 2, C_TEXT);
	rect(x + 4, y + fh / 4 + 4, (bw - 8) * batt_pct / 100, bh - 8, col);
	draw_span(x - fw / 2 - len * fw, y, t, -1, len, batt_chg ? 0x34d058 : C_TEXT, 1);
}

static const char *hint = "Hangerő: léptetés · Bekapcs. hosszan: OK, röviden: kijelző";

/* A cím legfeljebb két sorban, középre igazítva (a '\n' is sortörés). */
static void title_bar(const char *title)
{
	struct span ln[2];
	const char *rest;
	int maxc = (W - 2 * CW) / CW, n, i;
	rect(0, 0, W, H, C_BG);
	draw_battery();
	draw_text_center(CH, "MAMUTHKA RECOVERY", C_TITLE, scale + 1);
	rect(W / 10, CH * 3 + CH / 2, W * 8 / 10, 4, C_TITLE);
	n = wrap_lines(title, maxc, ln, 2, &rest);
	for (i = 0; i < n; i++) {
		int y = n == 1 ? CH * 4 + CH / 2 : CH * 4 + i * (CH + CH / 4);
		int len = span_len(ln[i].p, ln[i].n);
		if (i == n - 1 && *rest) { /* maradt szöveg: "…" zárja */
			if (len > maxc - 1) len = maxc - 1;
			draw_span((W - (len + 1) * CW) / 2, y, ln[i].p, ln[i].n, len, C_TEXT, scale);
			draw_char((W - (len + 1) * CW) / 2 + len * CW, y, 0x2026, C_TEXT, scale);
		} else {
			draw_span((W - len * CW) / 2, y, ln[i].p, ln[i].n, len, C_TEXT, scale);
		}
	}
	draw_text_center(H - CH * 2, hint, C_DIM, scale > 1 ? scale - 1 : 1);
}

/* ---------- bemenet ---------- */
struct indev { int fd; int touch; int minx, maxx, miny, maxy; };
static struct indev devs[16];
static int ndev;
static int tx, ty, tdown, press_sent;
static int want_motion; /* 1: UI_PRESS/UI_MOVE is jön (görgetés húzással) */
static double pwr_down;  /* a bekapcsoló lenyomásának ideje */
#define PWR_LONG_S 0.6   /* ennél hosszabb nyomás = OK */

static void input_open(void)
{
	DIR *d = opendir("/dev/input");
	struct dirent *e;
	if (!d) return;
	while ((e = readdir(d)) && ndev < 16) {
		char p[300];
		unsigned long absbits[(ABS_MAX + 64) / 64] = {0};
		struct input_absinfo ai;
		int fd;
		if (strncmp(e->d_name, "event", 5)) continue;
		snprintf(p, sizeof p, "/dev/input/%s", e->d_name);
		fd = open(p, O_RDONLY | O_NONBLOCK);
		if (fd < 0) continue;
		devs[ndev].fd = fd;
		ioctl(fd, EVIOCGBIT(EV_ABS, sizeof absbits), absbits);
		if (absbits[ABS_MT_POSITION_X / 64] & (1UL << (ABS_MT_POSITION_X % 64))) {
			devs[ndev].touch = 1;
			ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ai); devs[ndev].minx = ai.minimum; devs[ndev].maxx = ai.maximum;
			ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ai); devs[ndev].miny = ai.minimum; devs[ndev].maxy = ai.maximum;
		}
		ndev++;
	}
	closedir(d);
}

enum { UI_NONE, UI_UP, UI_DOWN, UI_OK, UI_TAP, UI_PRESS, UI_MOVE, UI_PWR, UI_WAKE };

/* Vár egy eseményre (timeout_ms < 0: korlátlanul); UI_TAP/UI_PRESS/UI_MOVE
 * esetén tx/ty a képernyő-koordináta. */
static int wait_event(int timeout_ms)
{
	struct pollfd pf[16];
	int i, r;
	for (i = 0; i < ndev; i++) { pf[i].fd = devs[i].fd; pf[i].events = POLLIN; }
	for (;;) {
		r = poll(pf, ndev, timeout_ms);
		if (r < 0 && errno == EINTR) continue;
		if (r <= 0) return UI_NONE;
		for (i = 0; i < ndev; i++) {
			struct input_event ev;
			if (!(pf[i].revents & POLLIN)) continue;
			while (read(devs[i].fd, &ev, sizeof ev) == sizeof ev) {
				if (ev.type == EV_KEY && ev.value == 1) {
					if (ev.code == KEY_VOLUMEUP) return UI_UP;
					if (ev.code == KEY_VOLUMEDOWN) return UI_DOWN;
					if (ev.code == KEY_ENTER) return UI_OK;
					if (ev.code == KEY_POWER) pwr_down = ev.time.tv_sec + ev.time.tv_usec / 1e6;
				}
				/* Bekapcsoló: az elengedéskor dől el, rövid vagy hosszú */
				if (ev.type == EV_KEY && ev.value == 0 && ev.code == KEY_POWER && pwr_down > 0) {
					double held = ev.time.tv_sec + ev.time.tv_usec / 1e6 - pwr_down;
					pwr_down = 0;
					return held >= PWR_LONG_S ? UI_OK : UI_PWR;
				}
				if (devs[i].touch && ev.type == EV_ABS) {
					struct indev *d = &devs[i];
					if (ev.code == ABS_MT_POSITION_X && d->maxx > d->minx)
						tx = (ev.value - d->minx) * (long)W / (d->maxx - d->minx + 1);
					else if (ev.code == ABS_MT_POSITION_Y && d->maxy > d->miny)
						ty = (ev.value - d->miny) * (long)H / (d->maxy - d->miny + 1);
					else if (ev.code == ABS_MT_TRACKING_ID) {
						if (ev.value >= 0) tdown = 1;
						else if (tdown) { tdown = 0; press_sent = 0; return UI_TAP; }
					}
				}
				if (devs[i].touch && ev.type == EV_KEY && ev.code == BTN_TOUCH) {
					if (ev.value) tdown = 1;
					else if (tdown) { tdown = 0; press_sent = 0; return UI_TAP; }
				}
				/* A koordináták a SYN_REPORT-tal együtt érvényesek. */
				if (devs[i].touch && ev.type == EV_SYN && ev.code == SYN_REPORT && tdown && want_motion) {
					if (!press_sent) { press_sent = 1; return UI_PRESS; }
					return UI_MOVE;
				}
			}
		}
	}
}

/* ---------- kijelző ki/be (háttérvilágítás) ---------- */
#define BL_SAVE "/tmp/rui-brightness"
static char bl_path[300];
static double last_input;
static int idle_sec = 120;

static double now(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec + tv.tv_usec / 1e6;
}

static int file_get_int(const char *p, int def)
{
	char b[32];
	FILE *f = fopen(p, "r");
	if (!f) return def;
	if (!fgets(b, sizeof b, f)) b[0] = 0;
	fclose(f);
	return b[0] ? atoi(b) : def;
}

static void file_put_int(const char *p, int v)
{
	FILE *f = fopen(p, "w");
	if (f) { fprintf(f, "%d\n", v); fclose(f); }
}

static void bl_init(void)
{
	const char *e = getenv("RUI_BL");
	DIR *d;
	struct dirent *de;
	if (getenv("RUI_IDLE")) idle_sec = atoi(getenv("RUI_IDLE"));
	last_input = now();
	if (e) { if (strcmp(e, "none")) snprintf(bl_path, sizeof bl_path, "%s", e); return; }
	if (!(d = opendir("/sys/class/backlight"))) return;
	while ((de = readdir(d))) {
		if (de->d_name[0] == '.') continue;
		snprintf(bl_path, sizeof bl_path, "/sys/class/backlight/%s/brightness", de->d_name);
		break;
	}
	closedir(d);
}

static void screen_off(void)
{
	int v;
	if (blanked || !bl_path[0]) return;
	v = file_get_int(bl_path, 0);
	if (v > 0) file_put_int(BL_SAVE, v);
	file_put_int(bl_path, 0);
	blanked = 1;
}

static void screen_on(void)
{
	int v = file_get_int(BL_SAVE, 128);
	if (!bl_path[0]) { blanked = 0; return; }
	if (v <= 0) v = 128;
	file_put_int(bl_path, v);
	blanked = 0;
	last_input = now();
}

/* Kezdéskor: a párbeszédablakok bekapcsolják a kijelzőt (értesítés), a
 * státusz/folyamat-képernyők megtartják a sötét állapotot. */
static void bl_start(int interactive)
{
	bl_init();
	if (!bl_path[0] || file_get_int(bl_path, 1) > 0) return;
	if (interactive) screen_on();
	else blanked = 1;
}

/* Esemény a kijelző-kezeléssel együtt.
 *   - rövid bekapcsológomb: kijelző ki;
 *   - sötét kijelzőn bármely gomb/érintés csak ébreszt (UI_WAKE);
 *   - idle_sec tétlenség után kijelző ki.
 * hard = 0: sötét kijelzőnél a timeout_ms-t figyelmen kívül hagyja (nincs
 * fölösleges ébredés); hard = 1: a timeout mindig él (rui pipe). */

static int ui_event(int timeout_ms, int hard)
{
	double deadline = now() + (timeout_ms < 0 ? 0 : timeout_ms / 1000.0);
	for (;;) {
		int ev, t = -1;
		double tn = now();
		if (!blanked && idle_sec > 0 && bl_path[0]) {
			double left = last_input + idle_sec - tn;
			if (left <= 0) { screen_off(); continue; }
			t = (int)(left * 1000) + 1;
		}
		if (timeout_ms >= 0 && (!blanked || hard)) {
			int l = (int)((deadline - tn) * 1000);
			if (l < 0) l = 0;
			if (t < 0 || l < t) t = l;
		}
		ev = wait_event(t);
		if (ev == UI_NONE) {
			if (timeout_ms >= 0 && now() >= deadline && (!blanked || hard)) return UI_NONE;
			continue;
		}
		last_input = now();
		if (blanked) {
			if (ev == UI_PRESS || ev == UI_MOVE) continue; /* az elengedésre ébred */
			screen_on();
			return UI_WAKE;
		}
		if (ev == UI_PWR) { screen_off(); continue; }
		return ev;
	}
}

/* ---------- gombok ---------- */
struct button { int x, y, w, h; const char *label; };

/* A felirat a gomb szélességéhez tördelődik (ha a gomb elég magas, két
 * sorba), különben "…"-vel rövidül. */
static void draw_label(struct button *b)
{
	int pad = b->w >= 4 * CW ? CW : CW / 4;
	int maxc = (b->w - 2 * pad) / CW, rows = b->h >= 2 * CH + CH / 4 ? 2 : 1, n, i, y;
	struct span ln[2];
	const char *rest;
	if (maxc < 1) maxc = 1;
	n = wrap_lines(b->label, maxc, ln, rows, &rest);
	if (!n) return;
	y = b->y + (b->h - n * CH - (n - 1) * (CH / 8)) / 2;
	for (i = 0; i < n; i++, y += CH + CH / 8) {
		int len = span_len(ln[i].p, ln[i].n), x = b->x + pad;
		if (b->w < 4 * CW) x = b->x + (b->w - (len > maxc ? maxc : len) * CW) / 2; /* billentyű: középre */
		if (i == n - 1 && *rest) {
			if (len > maxc - 1) len = maxc - 1;
			draw_span(x, y, ln[i].p, ln[i].n, len, C_TEXT, scale);
			draw_char(x + len * CW, y, 0x2026, C_TEXT, scale);
		} else {
			draw_span(x, y, ln[i].p, ln[i].n, maxc, C_TEXT, scale);
		}
	}
}

static void draw_button(struct button *b, int sel)
{
	glow_under(b->x, b->y, b->w, b->h, sel ? 230 : 130);
	frame(b->x, b->y, b->w, b->h, sel ? C_BTN_SEL : C_BTN, sel ? C_TITLE : C_BORDER);
	draw_label(b);
}

static int hit(struct button *b, int n)
{
	int i;
	for (i = 0; i < n; i++)
		if (tx >= b[i].x && tx < b[i].x + b[i].w && ty >= b[i].y && ty < b[i].y + b[i].h) return i;
	return -1;
}

/* Az akku-kijelzés frissítése ennyi ms-onként (ha nincs bemenet). */
#define BATT_REFRESH_MS 3000

/* Gomblista választás. */
static int choose(struct button *b, int n, int sel, void (*redraw)(void *), void *ctx)
{
	int dirty = 1;
	for (;;) {
		int i, ev;
		if (dirty) {
			if (redraw) redraw(ctx);
			for (i = 0; i < n; i++) draw_button(&b[i], i == sel);
			flip();
		}
		dirty = 1;
		ev = ui_event(BATT_REFRESH_MS, 0);
		if (ev == UI_NONE) { dirty = batt_read(); continue; }
		if (ev == UI_WAKE) { batt_read(); continue; }
		if (ev == UI_UP) sel = (sel + n - 1) % n;
		else if (ev == UI_DOWN) sel = (sel + 1) % n;
		else if (ev == UI_OK) return sel;
		else if (ev == UI_TAP) {
			int h = hit(b, n);
			if (h >= 0) {
				draw_button(&b[h], 1); flip(); usleep(120000);
				return h;
			}
		}
	}
}

/* ---------- görgethető szöveg ---------- */
struct tview {
	const char *title;
	struct span *ln; int n;   /* tördelt sorok */
	int sc, cw, lh;           /* betűméret, karakterszélesség, sormagasság */
	int x, top, bottom, rows, off;
};

static void tv_layout(struct tview *t, const char *text, int sc, int top, int bottom)
{
	t->sc = sc; t->cw = (int)font_w * sc; t->lh = (int)font_h * sc + (int)font_h * sc / 6;
	t->x = CW; t->top = top; t->bottom = bottom;
	/* jobb oldalon hely a görgetősávnak */
	t->ln = wrap_all(text, (W - 2 * CW - CW / 2) / t->cw, &t->n);
	t->rows = (bottom - top) / t->lh;
	if (t->rows < 1) t->rows = 1;
	t->off = 0;
}

static int tv_maxoff(struct tview *t) { return t->n > t->rows ? t->n - t->rows : 0; }

static void tv_clamp(struct tview *t)
{
	if (t->off > tv_maxoff(t)) t->off = tv_maxoff(t);
	if (t->off < 0) t->off = 0;
}

static void tv_draw(struct tview *t)
{
	int i, y = t->top;
	for (i = t->off; i < t->n && i < t->off + t->rows; i++, y += t->lh)
		draw_span(t->x, y, t->ln[i].p, t->ln[i].n, (W - 2 * CW - CW / 2) / t->cw, C_TEXT, t->sc);
	if (t->n > t->rows) { /* görgetősáv */
		int bx = W - CW / 2 - 6, bh = t->bottom - t->top;
		int th = bh * t->rows / t->n, ty0 = t->top + (bh - th) * t->off / tv_maxoff(t);
		if (th < CH) th = CH;
		if (ty0 + th > t->bottom) ty0 = t->bottom - th;
		rect(bx, t->top, 6, bh, C_BORDER);
		rect(bx, ty0, 6, th, C_DIM);
	}
}

/* Képernyő görgethető szöveggel és gombokkal.
 *   keys_page = 1: a hangerőgombok lapoznak, a bekapcsoló a def gombot nyomja;
 *   keys_page = 0: a hangerőgombok a gombok között léptetnek.
 * Érintés: húzás = görgetés, koppintás = gomb. */
static int tv_run(struct tview *t, struct button *b, int nb, int sel, int keys_page, int def,
		  struct button *jump_top, struct button *jump_end)
{
	int dirty = 1, pend = UI_NONE, y0 = 0, off0 = 0, drag = 0, in_text = 0;
	want_motion = 1;
	for (;;) {
		int i, ev;
		if (dirty) {
			title_bar(t->title);
			tv_draw(t);
			for (i = 0; i < nb; i++) draw_button(&b[i], i == (keys_page ? def : sel));
			flip();
		}
		dirty = 1;
		if (pend != UI_NONE) { ev = pend; pend = UI_NONE; }
		else ev = ui_event(BATT_REFRESH_MS, 0);
		switch (ev) {
		case UI_NONE:
			dirty = batt_read();
			break;
		case UI_WAKE:
			batt_read(); drag = 0; in_text = 0;
			break;
		case UI_UP:
			if (keys_page) { t->off -= t->rows - 1; tv_clamp(t); }
			else sel = (sel + nb - 1) % nb;
			break;
		case UI_DOWN:
			if (keys_page) { t->off += t->rows - 1; tv_clamp(t); }
			else sel = (sel + 1) % nb;
			break;
		case UI_OK:
			want_motion = 0;
			return keys_page ? def : sel;
		case UI_PRESS:
			y0 = ty; off0 = t->off; drag = 0;
			in_text = ty >= t->top && ty < t->bottom;
			dirty = 0;
			break;
		case UI_MOVE:
			/* a sorban álló mozgásokat összevonjuk (egy rajzolás) */
			while ((pend = ui_event(0, 1)) == UI_MOVE) ;
			if (!in_text || t->n <= t->rows) { dirty = 0; break; }
			if (!drag && abs(ty - y0) > CH / 2) drag = 1;
			if (!drag) { dirty = 0; break; }
			t->off = off0 - (ty - y0) / t->lh;
			tv_clamp(t);
			break;
		case UI_TAP:
			if (drag) { drag = 0; break; }
			i = hit(b, nb);
			if (i >= 0 && jump_top && &b[i] == jump_top) { t->off = 0; break; }
			if (i >= 0 && jump_end && &b[i] == jump_end) { t->off = tv_maxoff(t); break; }
			if (i >= 0) {
				draw_button(&b[i], 1); flip(); usleep(120000);
				want_motion = 0;
				return i;
			}
			dirty = 0;
			break;
		}
	}
}

/* ---------- parancsok ---------- */
static int cmd_menu(const char *title, int n, char **items)
{
	struct button b[32];
	int i, bh = CH * 3, gap = CH / 2, top = CH * 7;
	if (n > 32) n = 32;
	/* Ha sok elem van, kisebb gombok. */
	while (n * (bh + gap) > H - top - CH * 3 && bh > CH * 2) bh -= CH / 4;
	while (n * (bh + gap) > H - top - CH * 3 && gap > 4) gap--;
	for (i = 0; i < n; i++) {
		b[i].x = CW; b[i].w = W - 2 * CW; b[i].h = bh;
		b[i].y = top + i * (bh + gap); b[i].label = items[i];
	}
	i = choose(b, n, 0, (void (*)(void *))title_bar, (void *)title);
	printf("%d\n", i);
	return 0;
}

static int cmd_msg(const char *title, const char *text, int ask)
{
	struct tview t = { .title = title };
	struct button b[2];
	int bw = (W - 3 * CW) / 2, by = H - CH * 7;
	tv_layout(&t, text, scale, CH * 7, by - CH);
	if (t.n > t.rows) hint = "Húzás, hangerő: görgetés · Bekapcs. hosszan: OK";
	if (ask) {
		b[0] = (struct button){ CW, by, bw, CH * 3, "Igen" };
		b[1] = (struct button){ 2 * CW + bw, by, bw, CH * 3, "Nem" };
		return tv_run(&t, b, 2, 1, 0, 1, NULL, NULL) == 0 ? 0 : 1;
	}
	b[0] = (struct button){ CW, by, W - 2 * CW, CH * 3, "OK" };
	/* egyetlen gomb: a hangerőgombok lapoznak */
	tv_run(&t, b, 1, 0, 1, 0, NULL, NULL);
	return 0;
}

static int cmd_status(const char *title, const char *text)
{
	struct tview t = { .title = title };
	tv_layout(&t, text, scale, CH * 7, H - CH * 3);
	title_bar(title);
	tv_draw(&t);
	flip();
	return 0;
}

/* Napló/fájl görgethető nézetben; a végén nyílik meg (ott a friss hiba). */
static int cmd_view(const char *title, const char *path)
{
	struct tview t = { .title = title };
	struct button b[3];
	FILE *f = fopen(path, "rb");
	char *buf;
	long len = 0, maxlen = 2L << 20;
	int bw = (W - 4 * CW) / 3, by = H - CH * 7, i;
	if (f) { fseek(f, 0, SEEK_END); len = ftell(f); }
	if (len < 0) len = 0;
	if (len > maxlen) { fseek(f, len - maxlen, SEEK_SET); len = maxlen; } /* csak a vége */
	else if (f) fseek(f, 0, SEEK_SET);
	buf = calloc(1, len + 64);
	if (f) { len = (long)fread(buf, 1, len, f); fclose(f); }
	if (!len) snprintf(buf, 64, "(üres vagy nem olvasható: %s)", path);
	/* vezérlőkarakterek (\r, \t, ESC…) helyett szóköz, hogy ne torzuljon */
	for (i = 0; i < len; i++)
		if ((unsigned char)buf[i] < 0x20 && buf[i] != '\n') buf[i] = ' ';
	tv_layout(&t, buf, scale > 1 ? scale - 1 : 1, CH * 7, by - CH / 2);
	t.off = tv_maxoff(&t);
	hint = "Húzás, hangerő: görgetés · Bekapcs. hosszan: vissza";
	b[0] = (struct button){ CW, by, bw, CH * 3, "Teteje" };
	b[1] = (struct button){ 2 * CW + bw, by, bw, CH * 3, "Alja" };
	b[2] = (struct button){ 3 * CW + 2 * bw, by, bw, CH * 3, "Vissza" };
	tv_run(&t, b, 3, 2, 1, 2, &b[0], &b[1]);
	return 0;
}

/* Képernyő-billentyűzet */
static const char *kb_rows[2][4] = {
	{ "1234567890", "qwertzuiop", "asdfghjklé", "yxcvbnm.-_" },
	{ "!@#$%&*()=", "QWERTZUIOP", "ASDFGHJKLÉ", "YXCVBNM,;:" },
};
struct kbctx { const char *title; char *buf; int pw; };

static void redraw_kb(void *p)
{
	struct kbctx *c = p;
	char shown[256];
	size_t i, n = strlen(c->buf);
	title_bar(c->title);
	if (c->pw) { for (i = 0; i < n && i < sizeof shown - 1; i++) shown[i] = '*'; shown[i] = 0; }
	else snprintf(shown, sizeof shown, "%s", c->buf);
	frame(CW, CH * 7, W - 2 * CW, CH * 2, C_BTN, C_BORDER);
	{ /* hosszú szövegnél a vége látszik (ott a kurzor) */
		const char *s = shown;
		int maxc = (W - 4 * CW) / CW, len = text_len(s);
		while (len > maxc) { utf8_next(&s); len--; }
		draw_span(CW * 2, CH * 7 + CH / 2, s, -1, maxc, C_TEXT, scale);
	}
}

static int cmd_input(const char *title, int pw)
{
	char buf[256] = "";
	struct kbctx ctx = { title, buf, pw };
	int shift = 0, kw = W / 10, kh = H * 45 / 100 / 5, top = H / 2 - CH * 2;
	for (;;) {
		struct button b[64];
		char labels[64][8];
		int n = 0, r, k, sel;
		for (r = 0; r < 4; r++) {
			const char *s = kb_rows[shift][r];
			k = 0;
			while (*s) {
				const char *st = s;
				utf8_next(&s);
				snprintf(labels[n], sizeof labels[n], "%.*s", (int)(s - st), st);
				b[n] = (struct button){ k * kw, top + r * kh, kw, kh, labels[n] };
				n++; k++;
			}
		}
		b[n++] = (struct button){ 0, top + 4 * kh, kw * 2, kh, shift ? "abc" : "ABC" };
		b[n++] = (struct button){ kw * 2, top + 4 * kh, kw * 4, kh, "szóköz" };
		b[n++] = (struct button){ kw * 6, top + 4 * kh, kw * 2, kh, "<-" };
		b[n++] = (struct button){ kw * 8, top + 4 * kh, kw * 2, kh, "OK" };
		/* Csak érintéssel értelmes; gombokkal a "Kész" a fallback. */
		sel = choose(b, n, n - 1, redraw_kb, &ctx);
		if (sel == n - 1) break;
		if (sel == n - 4) shift = !shift;
		else if (sel == n - 3) { if (strlen(buf) < sizeof buf - 2) strcat(buf, " "); }
		else if (sel == n - 2) {
			size_t l = strlen(buf);
			while (l && (buf[l - 1] & 0xc0) == 0x80) buf[--l] = 0;
			if (l) buf[--l] = 0;
		} else if (strlen(buf) + strlen(b[sel].label) < sizeof buf - 1) {
			strcat(buf, b[sel].label);
		}
	}
	printf("%s\n", buf);
	return 0;
}

static int cmd_pipe(const char *title, unsigned long long total)
{
	static char buf[1 << 20];
	unsigned long long done = 0;
	double t0 = now(), last = 0;
	int batt_tick = 0;
	ssize_t r;
	hint = "Bekapcsoló röviden: kijelző ki/be";
	for (;;) {
		r = read(0, buf, sizeof buf);
		if (r < 0) { if (errno == EINTR) continue; perror("read"); return 1; }
		if (r == 0) break;
		for (ssize_t off = 0; off < r;) {
			ssize_t w = write(1, buf + off, r - off);
			if (w < 0) { if (errno == EINTR) continue; perror("write"); return 1; }
			off += w;
		}
		done += r;
		/* gombok: rövid bekapcsoló = kijelző ki/be, érintés = ébresztés */
		if (ui_event(0, 1) == UI_WAKE) last = 0;
		if (!blanked && now() - last > 0.5) {
			char line[128];
			int pct = total ? (int)(done * 100 / total) : 0;
			double mbps = done / 1048576.0 / (now() - t0 + 0.001);
			last = now();
			title_bar(title);
			frame(CW, H / 2 - CH * 2, W - 2 * CW, CH * 3, C_BTN, C_BORDER);
			rect(CW + 3, H / 2 - CH * 2 + 3, (W - 2 * CW - 6) * (pct > 100 ? 100 : pct) / 100, CH * 3 - 6, C_TITLE);
			if (!(++batt_tick % 6)) batt_read();
			snprintf(line, sizeof line, "%d%%", pct);
			draw_text_center(H / 2 + CH * 2, line, C_TEXT, scale + 1);
			snprintf(line, sizeof line, "%llu / %llu MiB · %.1f MiB/s", done >> 20, total >> 20, mbps);
			draw_text_center(H / 2 + CH * 4, line, C_TEXT, scale);
			draw_text_center(H / 2 + CH * 6, "Ne kapcsold ki a telefont!", C_DIM, scale);
			flip();
		}
	}
	return 0;
}

static int cmd_reboot(const char *how)
{
	sync();
	if (how && !strcmp(how, "poweroff")) return reboot(RB_POWER_OFF);
	if (how && *how)
		return syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
			       LINUX_REBOOT_CMD_RESTART2, how);
	return reboot(RB_AUTOBOOT);
}

/* "\n" → valódi sortörés a parancssori szövegekben */
static char *unescape(const char *s)
{
	char *o = strdup(s), *d = o;
	for (; *s; s++) {
		if (s[0] == '\\' && s[1] == 'n') { *d++ = '\n'; s++; }
		else *d++ = *s;
	}
	*d = 0;
	return o;
}

int main(int argc, char **argv)
{
	int i, interactive;
	if (argc < 2) {
		fprintf(stderr, "használat: rui menu|msg|ask|input|pipe|status|view|reboot ...\n");
		return 2;
	}
	for (i = 2; i < argc; i++) argv[i] = unescape(argv[i]);
	if (!strcmp(argv[1], "reboot")) return cmd_reboot(argc > 2 ? argv[2] : NULL);

	fb_open();
	font_load();
	batt_read();
	interactive = strcmp(argv[1], "status") && strcmp(argv[1], "pipe");
	bl_start(interactive);
	/* a pipe is figyeli a gombokat (kijelző ki/be a hosszú letöltés alatt) */
	if (strcmp(argv[1], "status")) input_open();

	if (!strcmp(argv[1], "menu") && argc >= 4) return cmd_menu(argv[2], argc - 3, argv + 3);
	if (!strcmp(argv[1], "msg") && argc >= 4) return cmd_msg(argv[2], argv[3], 0);
	if (!strcmp(argv[1], "ask") && argc >= 4) return cmd_msg(argv[2], argv[3], 1);
	if (!strcmp(argv[1], "input") && argc >= 3) return cmd_input(argv[2], argc > 3 && !strcmp(argv[3], "--password"));
	if (!strcmp(argv[1], "pipe") && argc >= 4) return cmd_pipe(argv[2], strtoull(argv[3], NULL, 10));
	if (!strcmp(argv[1], "status") && argc >= 4) return cmd_status(argv[2], argv[3]);
	if (!strcmp(argv[1], "view") && argc >= 4) return cmd_view(argv[2], argv[3]);
	fprintf(stderr, "ismeretlen parancs vagy hiányzó argumentum: %s\n", argv[1]);
	return 2;
}
