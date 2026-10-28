#!/usr/bin/env bash
set -euo pipefail
# Run as the normal build user. Dependencies must already be available.
export THEOS="${THEOS:-$PWD/.build-tools/theos}"
THEOS_REV=6e7b8c40e0f5f9f5b2377800dc1e42cd2560d24a
SDK_REV=0222fd5413cf4b9af096f37b4621afa2688572f7
mkdir -p "$(dirname "$THEOS")"
if [[ ! -f "$THEOS/makefiles/common.mk" ]]; then
  git clone --recursive https://github.com/theos/theos.git "$THEOS"
  git -C "$THEOS" checkout "$THEOS_REV"
  git -C "$THEOS" submodule update --init --recursive
fi
if [[ ! -d "$THEOS/sdks/iPhoneOS12.4.sdk" ]]; then
  sdk_source="$(dirname "$THEOS")/sdks"
  if [[ ! -d "$sdk_source/.git" ]]; then
    git clone --filter=blob:none --no-checkout https://github.com/theos/sdks.git "$sdk_source"
  fi
  git -C "$sdk_source" sparse-checkout init --cone
  git -C "$sdk_source" sparse-checkout set iPhoneOS12.4.sdk
  git -C "$sdk_source" checkout "$SDK_REV"
  cp -a "$sdk_source/iPhoneOS12.4.sdk" "$THEOS/sdks/"
fi
if [[ "$(uname -s)" == Linux && ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]]; then
  mkdir -p "$THEOS/toolchain"
  curl --fail --location --retry 3 https://github.com/L1ghtmann/llvm-project/releases/download/test-210562a/iOSToolchain-x86_64.tar.xz | tar -xJ -C "$THEOS/toolchain"
fi
echo "Theos ready: $THEOS"
