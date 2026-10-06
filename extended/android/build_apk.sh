#!/bin/sh
# Builds "KOReader Extended" Android APKs (unsigned), in KOReader's own Android build container
# (koreader/koandroid, with the Android SDK and NDK r23c), with init.gradle: its own app ID and
# name, next to the official KOReader, and KOReader's in-app updater off.
#
# Usage: extended/android/build_apk.sh /path/to/koreader [arm64] [arm] [x86_64] [x86]
#   (default: arm64). The KOReader source tree must have the extended crengine and the plugin
#   installed (extended/README.md, sections 1 and 3). Needs podman.
#
# Writes KOReader-Crengine-Extended-<KOReader version>-<type>-unsigned.apk in the current directory.
# Then sign each one with your key (every update must be signed with the same key):
#   apksigner sign --ks <keystore> --ks-key-alias <alias> --out <name>.apk <name>-unsigned.apk

set -eu

if [ $# -lt 1 ] || [ ! -x "$1/kodev" ]; then
    echo "usage: $0 /path/to/koreader [arm64] [arm] [x86_64] [x86]" >&2
    exit 2
fi
HERE=$(cd "$(dirname "$0")" && pwd)
KO=$(cd "$1" && pwd)
shift
ARCHS=${*:-arm64}
IMAGE=docker.io/koreader/koandroid:2.0.0-22.04
# The plugin's version (eg. 2026.07.1-extended) names the APKs and is their Android version name
VERSION=$(sed -n 's/^ *version = "\(.*\)",$/\1/p' "$HERE/../plugin/advancedtypography.koplugin/_meta.lua")
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/koreader-android-gradle" # Gradle's downloads, kept between builds
mkdir -p "$CACHE"
OUT=$(pwd)

for arch in $ARCHS; do
    case "$arch" in
        arm64|arm|x86_64|x86) ;;
        *) echo "error: unknown type $arch (arm64, arm, x86_64, x86)" >&2; exit 2 ;;
    esac
    echo "== Building $arch"
    podman run --rm --userns=keep-id:uid=1001,gid=1001 \
        -v "$KO:/home/ko/koreader:z" \
        -v "$HERE:/home/ko/extended-android:ro,z" \
        -v "$CACHE:/home/ko/.gradle:z" \
        -e ANDROID_HOME=/opt/android-sdk-linux \
        -e ANDROID_NDK_HOME=/opt/android-ndk-r23c \
        -e GRADLE_FLAGS="-I /home/ko/extended-android/init.gradle" \
        -e ANDROID_NAME="$VERSION" \
        -w /home/ko/koreader "$IMAGE" \
        bash -c 'export PATH="$ANDROID_HOME/build-tools/30.0.2:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_NDK_HOME:$PATH"; ./kodev release "android-$0"' "$arch"
    mv "$KO/koreader-android-$arch-$VERSION.apk" "$OUT/KOReader-Crengine-Extended-${VERSION%-extended}-$arch-unsigned.apk"
    echo "== $OUT/KOReader-Crengine-Extended-${VERSION%-extended}-$arch-unsigned.apk"
done
