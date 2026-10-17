#!/usr/bin/env bash
# Builds dist/Mac PowerToys.app: universal release binary, Info.plist, icon,
# code signature.
#
#   scripts/build-app.sh
#
# Environment overrides:
#   ARCHS          architectures to build (default: "arm64 x86_64")
#   BUNDLE_ID      CFBundleIdentifier (default: dev.spinzon12.MacPowerToys)
#   BUILD_NUMBER   CFBundleVersion (default: git commit count)
#   SIGN_IDENTITY  codesign identity (default: "-", ad-hoc). With a
#                  "Developer ID Application" identity the build is ready to notarize.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-dev.spinzon12.MacPowerToys}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

WORK="$ROOT/.build/package"
APP="$ROOT/dist/Mac PowerToys.app"

# One scratch path per architecture: with a shared one, both triples write the
# same Products/Release folder and the last build wins.
binaries=()
for arch in $ARCHS; do
    echo "==> Building $arch"
    args=(-c release --package-path "$ROOT" --triple "$arch-apple-macosx14.0" --scratch-path "$WORK/$arch")
    swift build "${args[@]}"
    binaries+=("$(swift build "${args[@]}" --show-bin-path)/mac-powertoys")
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/mac-powertoys"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

echo "==> Rendering icon"
rm -rf "$WORK/AppIcon.iconset"
swift "$ROOT/scripts/make-icon.swift" "$WORK/AppIcon.iconset" >/dev/null
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing ($SIGN_IDENTITY)"
timestamp="--timestamp"
[[ "$SIGN_IDENTITY" == "-" ]] && timestamp="--timestamp=none" # ad-hoc cannot be timestamped
codesign --force --options runtime "$timestamp" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"

echo "==> Done: $APP ($VERSION build $BUILD_NUMBER, $(lipo -archs "$APP/Contents/MacOS/mac-powertoys"))"
