#!/usr/bin/env bash
# Builds the app and packages it for download:
#   dist/MacToys-<version>.zip   (ditto, keeps signature and attributes)
#   dist/MacToys-<version>.dmg   (drag-to-Applications window)
#   dist/SHA256SUMS
#
#   scripts/package-release.sh
#
# Same environment overrides as scripts/build-app.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DIST="$ROOT/dist"
APP="$DIST/MacToys.app"
NAME="MacToys-$VERSION"

"$ROOT/scripts/build-app.sh"

echo "==> Zipping"
rm -f "$DIST/$NAME.zip"
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip" # Apple's notarization form; no __MACOSX/

echo "==> Building disk image"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$NAME.dmg"
hdiutil create -quiet -volname "MacToys $VERSION" -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO "$DIST/$NAME.dmg"
hdiutil verify -quiet "$DIST/$NAME.dmg"

echo "==> Checksums"
(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS && cat SHA256SUMS)
echo "==> Done: $DIST"
