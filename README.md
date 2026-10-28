# Phoni Repo

My Sileo repo for my own tweaks and other stuff, focused on iPhone 6 / iOS 12.5.8.

**Website and Sileo source:** https://realphoni.github.io/phoni-repo/

On your jailbroken phone, open the website and tap **Add to Sileo**, or paste that
URL into Sileo → Sources → +. This is a flat APT repo, not just a website.

## Publish your own tweak

1. Build your tweak into a **rootful `.deb`**. For iPhone 6, compile the binary for
   `arm64` and use Debian `Architecture: iphoneos-arm`. Theos' rootless scheme is
   for newer iOS versions and isn't the target here.
2. Open [debs/](https://github.com/realphoni/phoni-repo/tree/main/debs) on GitHub,
   choose **Add file → Upload files**, and upload the `.deb`. Commit to `main`.
   Use filenames without spaces, e.g. `com.phoni.mytweak_1.0.0_iphoneos-arm.deb`.
3. Wait for [Build Sileo repo and publish Pages](https://github.com/realphoni/phoni-repo/actions)
   to turn green. The website reads your real package metadata, so your tweak
   appears automatically with its name, version, description, and download link.
4. Refresh Sources in Sileo. Your package is available to install.

The repo starts empty. No sample or third-party tweaks are presented as yours.
Adding the source works before you publish your first package.

## Package metadata

Put accurate metadata in the package's `DEBIAN/control` (or your Theos `control`):

```text
Package: com.phoni.mytweak
Name: My Tweak
Version: 1.0.0
Architecture: iphoneos-arm
Description: Describe what this tweak actually changes.
Maintainer: Phoni
Author: Phoni
Section: Tweaks
Depends: mobilesubstrate, firmware (>= 12.0), firmware (<< 13.0)
```

Use the firmware bounds and dependencies your tweak actually supports. This
example targets iOS 12; a metadata range alone doesn't prove compatibility.
Use `Section: Themes` or `Section: Utilities` to appear under those website filters.
Architecture-independent resources can use `Architecture: all`.

The builder generates `Filename`, size, hashes, and default website/Sileo
depictions. Optional `Icon`, `Depiction`, and `SileoDepiction` fields in your
package override those defaults. For custom screenshots and descriptions, put
your depiction files under `site/` and reference their published absolute URLs.

## Update a tweak

Increase `Version`, rebuild the `.deb`, and upload it to `debs/`. Keep the old
version if you want it available for downgrade. The website displays the newest
Debian version and the Sileo index includes all uploaded versions. To withdraw a
release, remove its `.deb` and wait for deployment to complete.

## Local preview

Python 3.10+; no pip dependencies are needed. From the repository folder:

```sh
python -m unittest discover -s tests -v
python scripts/build_repo.py
python -m http.server 8080 --directory dist --bind 127.0.0.1
```

Open http://127.0.0.1:8080. The build output must be empty on each run; delete
only your generated `dist/` directory before rebuilding, or choose a new output:
`python scripts/build_repo.py --output dist-preview`.
Packages with zstd-compressed control archives need `dpkg-deb` available locally;
GitHub Actions already has it. Package payloads aren't executed during indexing.

## Hosting

GitHub Settings → Pages → Source must be **GitHub Actions**. Pushes to `main`
build and deploy the complete site, `.deb` files, flat `Packages`, `Packages.gz`,
`Packages.bz2`, `Release`, icons, and native Sileo depictions. Generated files
aren't committed back to the source branch. Sileo clients connect directly to
the public Pages URL; there is no login in front of package downloads.

To move the repo, update `repo.json`, the source links in `site/`, and the Pages
configuration together. HTTPS protects transport; this starter does not create
an APT signing key or signed Release file.

## Credits

Cube logo, mint palette, and glass styling reused/adapted from
[my home site](https://github.com/realphoni/home). See [ASSETS.md](ASSETS.md).
Developer references: [Theos packaging](https://theos.dev/docs/packaging),
[Theos rootless architecture notes](https://theos.dev/docs/rootless), and
[Sileo native depictions](https://developer.getsileo.app/native-depictions).
