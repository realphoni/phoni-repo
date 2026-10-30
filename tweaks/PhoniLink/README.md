# PhoniLink

phone calls over Wi-Fi, for my old iPhone and my newer ones :)

This is a separate calling app. The Sileo package puts it on your jailbroken iPhone 6, and the companion IPA is the same app for a phone without a jailbreak.

## trying it

1. Install **PhoniLink** from my Sileo repo on the iPhone 6. Reopen the Home Screen or respring if its icon hasn't appeared.
2. On the other phone, download the [companion IPA](https://realphoni.github.io/phoni-repo/phonilink.html). Re-sign and sideload it with your usual tool. Downloading the IPA alone won't install it.
3. Connect both phones to the same Wi-Fi. Open PhoniLink on both, give each a different name, and turn on nearby calling.
4. Allow **Microphone** and **Local Network** when prompted. Tap the other phone, press Call, then Answer there.
5. Start with the earpieces or headphones, especially if the phones are right next to each other. Speaker, mute, decline, and hang up are in the app.

Both apps need to stay open and unlocked in this beta. Switching apps or locking a phone ends its call and stops nearby calling. Turn it back on after reopening. While nearby calling is on, the screen stays awake; the proximity sensor still blanks it by your ear during a call.

No phone numbers, SIM, account, or internet server. Apple's Multipeer Connectivity chooses the nearby link and can use peer-to-peer Wi-Fi, so this isn't restricted strictly to your router. The session requires encryption, but display names aren't verified identities. Check the name and short suffix on the other phone before calling or answering.

## what this doesn't do yet

It doesn't intercept the Phone app, transfer a cellular call, wake a closed app, or receive calls on the lock screen. There's no PushKit service or background listener. It uses its own call screen rather than CallKit in this first version.

The `.deb` targets rootful iOS 12. The companion uses public APIs with an iOS 12 minimum and needs signing for your newer phone. Neither physical-device audio nor your iOS 27 versions has been verified yet. Compiling an app isn't a compatibility guarantee.

## if the phones don't show up

Keep both apps open, turn nearby calling off and on, and check Local Network permission in Settings on the newer phone. Avoid guest Wi-Fi / client isolation. VPNs and restrictions on local networking can interfere. The phone name can be changed while nearby calling is off.

If the other phone disconnects or audio doesn't arrive, the call times out. A regular phone call or audio interruption ends the PhoniLink call. It never opens the microphone just because someone nearby connects; you have to start or answer a call.

## building it

Use the existing pinned Theos setup from the repo. No private frameworks, Substrate, or special Apple entitlements are needed by the companion.

```sh
python scripts/prepare_phonilink_assets.py
make -C tweaks/PhoniLink package FINALPACKAGE=1
python scripts/package_phonilink_companion.py tweaks/PhoniLink/packages/*.deb tweaks/PhoniLink/packages/PhoniLink-0.1.0-beta1.ipa
python scripts/check_phonilink.py tweaks/PhoniLink/packages/*.deb tweaks/PhoniLink/packages/*.ipa
```

The IPA is ad-hoc signed for packaging and has no Apple provisioning profile. Your sideloading tool replaces its signature and provisions it. Don't install the `.deb` and companion IPA on the same phone.

Audio uses Voice Processing I/O (echo cancellation), 16 kHz mono PCM, 20 ms encrypted unreliable messages, a small playback buffer, and reliable call controls. Audio callbacks only move samples through bounded buffers; networking runs on a separate queue. No recording or analytics.

Before calling this tested: try calls in both directions, decline, hang up from either side, mute, speaker, headphones, Wi-Fi loss, microphone denial, locking, and reopening the app. Check speech both ways with the phones in separate rooms. The automated build checks audio-buffer concurrency, packet validation, package contents, architecture, and signatures; it can't test those phone behaviors.
