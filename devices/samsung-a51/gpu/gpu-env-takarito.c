/* Mamuthka linux – a GPU-s (libhybris) környezeti változók eltakarítása a
 * Cinnamonból az első kirajzolás után.
 *
 * A Cinnamon (muffin/cogl) a libhybris EGL-t a környezeti változók alapján
 * tölti be (COGL_DRIVER, EGL_PLATFORM, HYBRIS_*, LIBEGL/LIBGLESV2,
 * __EGL_VENDOR_LIBRARY_FILENAMES). Ezeket a menüből indított programok is
 * örökölnék, és akkor ők is a libhybris-t használnák. Az első
 * eglSwapBuffers után minden szükséges könyvtár betöltődött, ezért a
 * változókat innen törölni lehet (a dinamikus linker az LD_LIBRARY_PATH-t
 * induláskor már elmentette).
 *
 * Fordítás: gcc -O2 -shared -fPIC -o gpu-env-takarito.so gpu-env-takarito.c -ldl
 * Használat: LD_PRELOAD=.../gpu-env-takarito.so cinnamon --replace
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef unsigned int EGLBoolean;
typedef void *EGLDisplay, *EGLSurface;
typedef int EGLint;
typedef void (*fn_t)(void);

static const char *valtozok[] = {
	"MAMUTHKA_GPU_ENV", "COGL_DRIVER", "EGL_PLATFORM", "LIBEGL", "LIBGLESV2",
	"HYBRIS_LIBGLESV1", "HYBRIS_LD_LIBRARY_PATH", "HYBRIS_LINKER_DIR",
	"HYBRIS_ANDROID_SDK_VERSION", "HYBRIS_EGLPLATFORM_DIR", "HYBRIS_LOGGING_LEVEL",
	"__EGL_VENDOR_LIBRARY_FILENAMES", "LD_PRELOAD", NULL
};
static int kesz;

static void takarit(void)
{
	if (kesz)
		return;
	kesz = 1;
	/* Az LD_LIBRARY_PATH-t csak akkor töröljük, ha a GPU-indító állította be
	 * (MAMUTHKA_GPU_LDPATH=1), különben a felhasználóé marad. */
	const char *l = getenv("MAMUTHKA_GPU_LDPATH");
	if (l && strcmp(l, "1") == 0) {
		const char *orig = getenv("MAMUTHKA_GPU_LDPATH_EREDETI");
		if (orig && *orig)
			setenv("LD_LIBRARY_PATH", orig, 1);
		else
			unsetenv("LD_LIBRARY_PATH");
		unsetenv("MAMUTHKA_GPU_LDPATH");
		unsetenv("MAMUTHKA_GPU_LDPATH_EREDETI");
	}
	for (int i = 0; valtozok[i]; i++)
		unsetenv(valtozok[i]);
	fprintf(stderr, "mamuthka-gpu: a libhybris környezeti változói törölve (a gyermekfolyamatok a Mesa-t használják)\n");
}

EGLBoolean eglSwapBuffers(EGLDisplay d, EGLSurface s)
{
	static EGLBoolean (*valodi)(EGLDisplay, EGLSurface);
	if (!valodi)
		valodi = (EGLBoolean (*)(EGLDisplay, EGLSurface))dlsym(RTLD_NEXT, "eglSwapBuffers");
	EGLBoolean r = valodi(d, s);
	takarit();
	return r;
}

static EGLBoolean (*valodi_dmg)(EGLDisplay, EGLSurface, EGLint *, EGLint);
static EGLBoolean swap_dmg(EGLDisplay d, EGLSurface s, EGLint *r, EGLint n)
{
	EGLBoolean v = valodi_dmg(d, s, r, n);
	takarit();
	return v;
}

fn_t eglGetProcAddress(const char *nev)
{
	static fn_t (*valodi)(const char *);
	if (!valodi)
		valodi = (fn_t (*)(const char *))dlsym(RTLD_NEXT, "eglGetProcAddress");
	fn_t f = valodi(nev);
	if (f && nev && (strcmp(nev, "eglSwapBuffersWithDamageKHR") == 0 ||
			 strcmp(nev, "eglSwapBuffersWithDamageEXT") == 0)) {
		valodi_dmg = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLint *, EGLint))f;
		return (fn_t)swap_dmg;
	}
	if (f && nev && strcmp(nev, "eglSwapBuffers") == 0)
		return (fn_t)eglSwapBuffers;
	return f;
}
