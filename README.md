# phoni-repo

my sileo repo :)

Tweaks and other stuff for my iPhone 6 on iOS 12.5.8.

## tweaks

[PhoniLock](tweaks/PhoniLock/) — clock/date styles, colors, custom text, and hiding lock-screen elements. Tested on my iPhone 6 (iOS 12.5.8). Xen HTML widgets overlap it, so they aren’t compatible right now.

[DownShot](tweaks/DownShot/) — Power + Volume Down screenshots on iOS 12. First beta, needs testing on a phone.

## how do i add it?

Open [the website](https://realphoni.github.io/phoni-repo/) and press **Add to Sileo**.

Or paste `https://realphoni.github.io/phoni-repo/` into Sileo's sources.

## uploading tweaks

Put the `.deb` in [debs/](debs/) and commit to `main`. GitHub does the rest. Once the workflow finishes, it'll show up on the website and in Sileo.

This is for rootful iOS 12 packages (`iphoneos-arm`). The iPhone 6 binary should be `arm64`.

For updates, bump the package version and upload the new `.deb`.

## credits

My pfp is the repo icon. Colours and some styling came from [my home site](https://github.com/realphoni/home).
