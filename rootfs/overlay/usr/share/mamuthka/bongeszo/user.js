// Mamuthka asztali user.js — az Android prefs.js-ből az asztalon értelmes rész + asztali kiegészítések
// (A GPU-prefek külön fájlban: user-gpu-mint.js / user-gpu-a51.js; a telepítő fűzi hozzá.)
// Az oldalak világos témát kapnak, a Dark Reader egységesen sötétíti őket
user_pref("layout.css.prefers-color-scheme.content-override", 1);
// userChrome.css / userContent.css engedélyezése
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
// Sötét böngészőfelület
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.theme.content-theme", 0);
user_pref("browser.in-content.dark-mode", true);
user_pref("ui.systemUsesDarkTheme", 1);
// Üdvözlő / első futás / ajánlók kikapcsolva
user_pref("browser.aboutwelcome.enabled", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.startup.page", 3);
// Telemetria ki
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
// Követés elleni védelem: Szigorú
user_pref("browser.contentblocking.category", "strict");
// Keresés: Google
user_pref("browser.search.defaultenginename", "Google");
// Megjegyzés: a „lapok automatikus bezárása 1 hét” asztali Firefoxban nincs beépítve (lásd README).
// Kihagyva (Android-specifikus): logging.nsHttp, gfx.use-surfacetexture-textures
