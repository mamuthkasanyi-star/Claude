/*
 * rui – Mamuthka Recovery UI
 *
 * Kis, statikusan fordított framebuffer-felület a recovery shell-scriptjeihez.
 * Érintéssel és gombokkal is kezelhető (Hangerő fel/le: léptetés,
 * Bekapcsoló: kiválasztás).
 *
 *   rui menu  "Cím" "Elem 1" "Elem 2" ...   → kiírja a választott sorszámot (0-tól)
 *   rui msg   "Cím" "Szöveg"                → üzenet "OK" gombbal
 *   rui ask   "Cím" "Szöveg"                → Igen/Nem; kilépési kód 0 = igen
 *   rui input "Cím" [--password]            → képernyő-billentyűzet; kiírja a szöveget
 *   rui pipe  "Cím" ÖSSZES_BÁJT             → stdin → stdout másolás folyamatjelzővel
 *   rui status "Cím" "Szöveg"               → kiírja és azonnal kilép
 *   rui reboot [recovery|download|poweroff] → újraindítás (Samsung reboot okkal)
 *
 * Környezet: RUI_FONT (PSF2 betűtípus), RUI_FB (alapértelmezés /dev/fb0).
 * A szövegekben '\n' sortörést jelent.
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
	ioctl(fb_fd, FBIOBLANK, FB_BLANK_UNBLANK);
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

static void flip(void)
{
	int x, y;
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

/* Egy sor kiírása; visszaadja a kiírt karakterek számát. */
static void draw_text(int x, int y, const char *s, uint32_t c, int sc)
{
	while (*s && *s != '\n') {
		draw_char(x, y, utf8_next(&s), c, sc);
		x += font_w * sc;
	}
}

static void draw_text_center(int y, const char *s, uint32_t c, int sc)
{
	draw_text((W - text_len(s) * (int)font_w * sc) / 2, y, s, c, sc);
}

/* Tördelt szöveg (szóhatáron); visszaadja a következő szabad y-t. */
static int draw_wrapped(int x, int y, int maxw, const char *s, uint32_t c)
{
	int maxc = maxw / CW;
	char line[512];
	while (*s) {
		const char *p = s, *lastsp = NULL, *brk;
		int n = 0;
		while (*p && *p != '\n' && n < maxc) {
			if (*p == ' ') lastsp = p;
			utf8_next(&p); n++;
		}
		brk = (*p && *p != '\n' && lastsp) ? lastsp : p;
		snprintf(line, sizeof line, "%.*s", (int)(brk - s), s);
		draw_text(x, y, line, c, scale);
		y += CH + CH / 3;
		s = brk;
		if (*s == ' ' || *s == '\n') s++;
	}
	return y;
}

static void title_bar(const char *title)
{
	rect(0, 0, W, H, C_BG);
	draw_text_center(CH, "MAMUTHKA RECOVERY", C_TITLE, scale + 1);
	rect(W / 10, CH * 3 + CH / 2, W * 8 / 10, 4, C_TITLE);
	draw_text_center(CH * 4 + CH / 2, title, C_TEXT, scale);
	draw_text_center(H - CH * 2, "Hangerő fel/le: léptetés · Bekapcsoló: OK", C_DIM, scale > 1 ? scale - 1 : 1);
}

/* ---------- bemenet ---------- */
struct indev { int fd; int touch; int minx, maxx, miny, maxy; };
static struct indev devs[16];
static int ndev;
static int tx, ty, tdown;

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

enum { EV_NONE, EV_UP, EV_DOWN, EV_OK, EV_TAP };

/* Vár egy eseményre; EV_TAP esetén tx/ty a képernyő-koordináta. */
static int wait_event(int timeout_ms)
{
	struct pollfd pf[16];
	int i, r;
	for (i = 0; i < ndev; i++) { pf[i].fd = devs[i].fd; pf[i].events = POLLIN; }
	for (;;) {
		r = poll(pf, ndev, timeout_ms);
		if (r < 0 && errno == EINTR) continue;
		if (r <= 0) return EV_NONE;
		for (i = 0; i < ndev; i++) {
			struct input_event ev;
			if (!(pf[i].revents & POLLIN)) continue;
			while (read(devs[i].fd, &ev, sizeof ev) == sizeof ev) {
				if (ev.type == EV_KEY && ev.value == 1) {
					if (ev.code == KEY_VOLUMEUP) return EV_UP;
					if (ev.code == KEY_VOLUMEDOWN) return EV_DOWN;
					if (ev.code == KEY_POWER || ev.code == KEY_ENTER) return EV_OK;
				}
				if (devs[i].touch && ev.type == EV_ABS) {
					struct indev *d = &devs[i];
					if (ev.code == ABS_MT_POSITION_X && d->maxx > d->minx)
						tx = (ev.value - d->minx) * (long)W / (d->maxx - d->minx + 1);
					else if (ev.code == ABS_MT_POSITION_Y && d->maxy > d->miny)
						ty = (ev.value - d->miny) * (long)H / (d->maxy - d->miny + 1);
					else if (ev.code == ABS_MT_TRACKING_ID) {
						if (ev.value >= 0) tdown = 1;
						else if (tdown) { tdown = 0; return EV_TAP; }
					}
				}
				if (devs[i].touch && ev.type == EV_KEY && ev.code == BTN_TOUCH) {
					if (ev.value) tdown = 1;
					else if (tdown) { tdown = 0; return EV_TAP; }
				}
			}
		}
	}
}

/* ---------- gombok ---------- */
struct button { int x, y, w, h; const char *label; };

static void draw_button(struct button *b, int sel)
{
	glow_under(b->x, b->y, b->w, b->h, sel ? 230 : 130);
	frame(b->x, b->y, b->w, b->h, sel ? C_BTN_SEL : C_BTN, sel ? C_TITLE : C_BORDER);
	draw_text(b->x + CW, b->y + (b->h - CH) / 2, b->label, C_TEXT, scale);
}

static int hit(struct button *b, int n)
{
	int i;
	for (i = 0; i < n; i++)
		if (tx >= b[i].x && tx < b[i].x + b[i].w && ty >= b[i].y && ty < b[i].y + b[i].h) return i;
	return -1;
}

/* Gomblista választás; top = az első gomb y-ja. */
static int choose(struct button *b, int n, int sel, void (*redraw)(void *), void *ctx)
{
	for (;;) {
		int i, ev;
		if (redraw) redraw(ctx);
		for (i = 0; i < n; i++) draw_button(&b[i], i == sel);
		flip();
		ev = wait_event(-1);
		if (ev == EV_UP) sel = (sel + n - 1) % n;
		else if (ev == EV_DOWN) sel = (sel + 1) % n;
		else if (ev == EV_OK) return sel;
		else if (ev == EV_TAP) {
			int h = hit(b, n);
			if (h >= 0) {
				draw_button(&b[h], 1); flip(); usleep(120000);
				return h;
			}
		}
	}
}

/* ---------- parancsok ---------- */
struct textctx { const char *title, *text; };

static void redraw_text(void *p)
{
	struct textctx *c = p;
	title_bar(c->title);
	if (c->text) draw_wrapped(CW, CH * 7, W - 2 * CW, c->text, C_TEXT);
}

static int cmd_menu(const char *title, int n, char **items)
{
	struct button b[32];
	struct textctx ctx = { title, NULL };
	int i, bh = CH * 3, gap = CH / 2, top = CH * 7;
	if (n > 32) n = 32;
	/* Ha sok elem van, kisebb gombok. */
	while (n * (bh + gap) > H - top - CH * 3 && bh > CH * 2) bh -= CH / 4;
	for (i = 0; i < n; i++) {
		b[i].x = CW; b[i].w = W - 2 * CW; b[i].h = bh;
		b[i].y = top + i * (bh + gap); b[i].label = items[i];
	}
	i = choose(b, n, 0, redraw_text, &ctx);
	printf("%d\n", i);
	return 0;
}

static int cmd_msg(const char *title, const char *text, int ask)
{
	struct textctx ctx = { title, text };
	struct button b[2];
	int bw = (W - 3 * CW) / 2, by = H - CH * 7;
	if (ask) {
		b[0] = (struct button){ CW, by, bw, CH * 3, "Igen" };
		b[1] = (struct button){ 2 * CW + bw, by, bw, CH * 3, "Nem" };
		return choose(b, 2, 1, redraw_text, &ctx) == 0 ? 0 : 1;
	}
	b[0] = (struct button){ CW, by, W - 2 * CW, CH * 3, "OK" };
	choose(b, 1, 0, redraw_text, &ctx);
	return 0;
}

static int cmd_status(const char *title, const char *text)
{
	struct textctx ctx = { title, text };
	redraw_text(&ctx);
	flip();
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
	draw_text(CW * 2, CH * 7 + CH / 2, shown, C_TEXT, scale);
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

static double now(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec + tv.tv_usec / 1e6;
}

static int cmd_pipe(const char *title, unsigned long long total)
{
	static char buf[1 << 20];
	unsigned long long done = 0;
	double t0 = now(), last = 0;
	ssize_t r;
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
		if (now() - last > 0.5) {
			char line[128];
			int pct = total ? (int)(done * 100 / total) : 0;
			double mbps = done / 1048576.0 / (now() - t0 + 0.001);
			last = now();
			title_bar(title);
			frame(CW, H / 2 - CH * 2, W - 2 * CW, CH * 3, C_BTN, C_BORDER);
			rect(CW + 3, H / 2 - CH * 2 + 3, (W - 2 * CW - 6) * (pct > 100 ? 100 : pct) / 100, CH * 3 - 6, C_BTN_SEL);
			snprintf(line, sizeof line, "%d%%  –  %llu / %llu MiB  (%.1f MiB/s)", pct,
				 done >> 20, total >> 20, mbps);
			draw_text_center(H / 2 + CH * 2, line, C_TEXT, scale);
			draw_text_center(H / 2 + CH * 4, "Ne kapcsold ki a telefont!", C_DIM, scale);
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
	int i;
	if (argc < 2) {
		fprintf(stderr, "használat: rui menu|msg|ask|input|pipe|status|reboot ...\n");
		return 2;
	}
	for (i = 2; i < argc; i++) argv[i] = unescape(argv[i]);
	if (!strcmp(argv[1], "reboot")) return cmd_reboot(argc > 2 ? argv[2] : NULL);

	fb_open();
	font_load();
	if (strcmp(argv[1], "status") && strcmp(argv[1], "pipe")) input_open();

	if (!strcmp(argv[1], "menu") && argc >= 4) return cmd_menu(argv[2], argc - 3, argv + 3);
	if (!strcmp(argv[1], "msg") && argc >= 4) return cmd_msg(argv[2], argv[3], 0);
	if (!strcmp(argv[1], "ask") && argc >= 4) return cmd_msg(argv[2], argv[3], 1);
	if (!strcmp(argv[1], "input") && argc >= 3) return cmd_input(argv[2], argc > 3 && !strcmp(argv[3], "--password"));
	if (!strcmp(argv[1], "pipe") && argc >= 4) return cmd_pipe(argv[2], strtoull(argv[3], NULL, 10));
	if (!strcmp(argv[1], "status") && argc >= 4) return cmd_status(argv[2], argv[3]);
	fprintf(stderr, "ismeretlen parancs vagy hiányzó argumentum: %s\n", argv[1]);
	return 2;
}
