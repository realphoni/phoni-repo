# PhoniLock

my first tweak :) change the lock-screen clock, date, colors, and add your own text.

Tested and working on my rootful iPhone 6 on iOS 12.5.8.

Known issue: Xen HTML widgets overlap PhoniLock. This version is not compatible with Xen HTML.

## using it

Install from [my Sileo repo](https://realphoni.github.io/phoni-repo/), respring when
Sileo asks, then open **Settings → PhoniLock**. It's off by default so installing
it doesn't immediately change your lock screen. Choose a style and switch it on.

- System, 12-hour, 12-hour with AM/PM, or 24-hour clock.
- Thin, light, regular, bold, monospaced-digit, rounded-look, or serif fonts.
- Separate clock/date/custom-text sizes and hex colors.
- Date format, custom text, left/center/right alignment, spacing, and vertical offset.
- Hide the clock, date, custom text, unlock hint, page dots, or lock glyph where present.
- Settings preview, live preference updates, and a reset button.

Everything stays in the existing clock area. Large text automatically scales to
fit; this version doesn't reposition notifications or replace the wallpaper.
Charging/status subtitles take priority over the date and custom text unless you
enable **Hide system subtitle**. Notifications, media controls, Touch ID, and
passcode behavior are left alone. Some hiding switches only affect elements
that exist in your lock-screen layout.

Colors use `#RRGGBB`, e.g. `#46FFB4`. Date formats use Unicode date patterns:
`EEEE, MMMM d` → Wednesday, October 28; `dd/MM/yyyy` → 28/10/2026.

## if something goes wrong

Turn PhoniLock off in Settings, or reset it. If SpringBoard won't stay open,
boot your jailbreak without tweak injection / in safe mode and uninstall
PhoniLock in Sileo. Don't run another clock/lock-screen customizer alongside it
while testing this first beta. Keep a working device backup.

## building

Theos with the patched iOS 12.4 SDK, `arm64` binaries, rootful `iphoneos-arm` package.
From this folder, with `THEOS` pointing to your Theos directory:

```sh
make package FINALPACKAGE=1
```

Build setup is in `scripts/prepare-theos.sh` at the repository root. Requires
the normal Theos build dependencies. Package version lives in `control`.
Built `.deb` files go in `debs/` at the repository root for publication.

## implementation notes

The overlay uses the iOS 12 `SBFLockScreenDateView`'s own date updates rather
than a background timer. View fields are checked before access, and native
hidden states are restored when disabled. Preferences are read and written
through CFPreferences with Darwin notifications. The native authentication
and notification controllers are not hooked.

Header reference: [iOS 12.4 runtime declarations](https://github.com/xybp888/iOS-Header/tree/master/12.4).
Build tools: [Theos](https://theos.dev/docs/installation-linux).
