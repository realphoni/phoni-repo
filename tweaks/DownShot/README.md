# DownShot

Power + Volume Down screenshots for iOS 12 :)

For rootful iPhone 6 / iOS 12.5.8. First beta, not tested on a physical phone yet.

## using it

Install **DownShot** from [my repo](https://realphoni.github.io/phoni-repo/) and
respring. Quickly press **Power + Volume Down** together to take a screenshot.
No settings page. Uninstall it in Sileo to remove the extra shortcut.

The original **Home + Power** shortcut is retained. DownShot adds an alternative
two-button chord to the actual screenshot recognizer; it doesn't change the
device's home-button type or replace its screenshot saving/preview implementation.
It doesn't capture screenshots in the background.

## testing this beta

Please check a screenshot from the home screen and an app, both button orders,
ordinary Volume Down, ordinary Power, and the original Home + Power combination.
Native screenshot timing is used, so press the buttons together and release
promptly. Other tweaks that remap hardware buttons may conflict.

Compiled and package-checked locally and in GitHub Actions. The physical button
behavior still needs testing on-device; this is not a claim of compatibility
with every iOS 12 jailbreak or button-remapping tweak.

## building

With Theos and the patched iOS 12.4 SDK:

```sh
make package FINALPACKAGE=1
```

Builds arm64 into a rootful `iphoneos-arm` package. Source hooks are limited to
the native screenshot recognizer identified through the hardware-button
controllers and its Volume Down precedence. Native timing and screenshot
actions remain in charge. The added chord is idempotent across controller setup.

API reference: [iOS 12.4 SpringBoard runtime declarations](https://github.com/xybp888/iOS-Header/tree/master/12.4/SpringBoard).
