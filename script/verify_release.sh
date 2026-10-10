#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
OUTPUT_DIR="$ROOT_DIR/dist/releases/$VERSION"
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clickmore-release.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
(cd "$OUTPUT_DIR" && shasum -a 256 -c SHA256SUMS)
PKG="$OUTPUT_DIR/ClickMore-$VERSION-universal.pkg"
pkgutil --check-signature "$PKG"
xcrun stapler validate "$PKG"
spctl --assess --type install --verbose=2 "$PKG"
ditto -x -k "$OUTPUT_DIR/ClickMore-$VERSION-universal.zip" "$VERIFY_DIR/zip"
pkgutil --expand-full "$PKG" "$VERIFY_DIR/pkg"
APP="$VERIFY_DIR/zip/ClickMore.app"
PKG_APP="$VERIFY_DIR/pkg/ClickMore-component.pkg/Payload/Applications/ClickMore.app"
for bundle in "$APP" "$PKG_APP"; do
  # Older immutable releases predate the permission helper.
  if [[ -f "$bundle/Contents/Resources/ThirdPartyNotices.txt" ]]; then
    test -d "$bundle/Contents/Resources/PermissionFlow_PermissionFlow.bundle"
  fi
  codesign --verify --strict --verbose=2 "$bundle"
  lipo "$bundle/Contents/MacOS/ClickMore" -verify_arch arm64 x86_64
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")" = "$VERSION"
  xcrun stapler validate "$bundle"
  spctl --assess --type execute --verbose=2 "$bundle"
done
diff -rq "$APP" "$PKG_APP"
echo "PKG and ZIP contain the same valid, notarized universal app."
