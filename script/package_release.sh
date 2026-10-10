#!/usr/bin/env bash
# Build universal, sign, notarize, and staple both the app and installer.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 [major.minor.patch]" >&2; exit 2
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit all changes before packaging a release." >&2; exit 1
fi
SOURCE_COMMIT="$(git rev-parse HEAD)"
APP_IDENTITY="${CLICKMORE_RELEASE_APP_IDENTITY:-Developer ID Application: Liseth Solutions AS (9Z2L5FBZS3)}"
PKG_IDENTITY="${CLICKMORE_RELEASE_PKG_IDENTITY:-Developer ID Installer: Liseth Solutions AS (9Z2L5FBZS3)}"
NOTARY_PROFILE="${CLICKMORE_NOTARY_PROFILE:-}"
if [[ -z "$NOTARY_PROFILE" && -f "$ROOT_DIR/.clickmore-release.json" ]]; then
  NOTARY_PROFILE="$(plutil -extract notaryProfile raw -o - "$ROOT_DIR/.clickmore-release.json")"
fi
NOTARY_PROFILE="${NOTARY_PROFILE:-clickmore-notary}"
WORK_DIR="$ROOT_DIR/.build/release-package/$VERSION"
OUTPUT_DIR="$ROOT_DIR/dist/releases/$VERSION"
APP_BUNDLE="$WORK_DIR/payload/Applications/ClickMore.app"
PKG_NAME="ClickMore-$VERSION-universal.pkg"
ZIP_NAME="ClickMore-$VERSION-universal.zip"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${CLICKMORE_NOTARY_KEYCHAIN:-}" ]]; then
  NOTARY_ARGS+=(--keychain "$CLICKMORE_NOTARY_KEYCHAIN")
fi
# Fail before building if the credentials or either private key are unavailable.
xcrun notarytool history "${NOTARY_ARGS[@]}" --output-format json > "$WORK_DIR/notary-history.json"
IDENTITIES="$(security find-identity -v -p basic)"
for identity in "$APP_IDENTITY" "$PKG_IDENTITY"; do
  if [[ "$IDENTITIES" != *"\"$identity\""* ]]; then
    echo "Missing signing identity/private key: $identity" >&2; exit 1
  fi
done
echo "Building ClickMore $VERSION for Apple Silicon and Intel…"
if ! swift build --scratch-path .build/release-universal -c release --arch arm64 --arch x86_64 --product ClickMore > "$WORK_DIR/build.log" 2>&1; then
  cat "$WORK_DIR/build.log" >&2; exit 1
fi
BUILD_DIR="$(swift build --scratch-path .build/release-universal -c release --arch arm64 --arch x86_64 --show-bin-path)"
# Only remove this version's generated payload, never the development bundle.
rm -rf "$WORK_DIR/payload"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/ClickMore" "$APP_BUNDLE/Contents/MacOS/ClickMore"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/ClickMore.icns "$APP_BUNDLE/Contents/Resources/ClickMore.icns"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_BUNDLE/Contents/Info.plist"
if [[ -n "${CLICKMORE_BUILD_NUMBER:-}" ]]; then
  plutil -replace CFBundleVersion -string "$CLICKMORE_BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
lipo "$APP_BUNDLE/Contents/MacOS/ClickMore" -verify_arch arm64 x86_64
codesign --force --options runtime --timestamp --sign "$APP_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

submit() {
  local artifact="$1" report="$2" status submission
  echo "Submitting $(basename "$artifact") to Apple…"
  xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait --output-format json > "$report"
  status="$(plutil -extract status raw -o - "$report")"
  submission="$(plutil -extract id raw -o - "$report")"
  xcrun notarytool log "$submission" "${NOTARY_ARGS[@]}" "$report.log.json"
  if [[ "$status" != "Accepted" ]]; then
    echo "Apple notarization returned $status. See $report.log.json" >&2; exit 1
  fi
  echo "Apple accepted $submission"
}

# ZIP cannot carry a staple: notarize its contents, staple the app, then re-zip.
ditto -c -k --keepParent "$APP_BUNDLE" "$WORK_DIR/submission.zip"
submit "$WORK_DIR/submission.zip" "$WORK_DIR/app-notarization.json"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
ditto -c -k --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/$ZIP_NAME"

# Disable relocation so an update always goes to /Applications, even if a
# development copy with the same bundle identifier exists elsewhere.
pkgbuild --analyze --root "$WORK_DIR/payload" "$WORK_DIR/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$WORK_DIR/components.plist"
pkgbuild --root "$WORK_DIR/payload" --component-plist "$WORK_DIR/components.plist" \
  --identifier no.liseth.clickmore --version "$VERSION" --install-location / \
  --ownership recommended "$WORK_DIR/ClickMore-component.pkg"
sed "s/@VERSION@/$VERSION/g" Resources/Distribution.xml > "$WORK_DIR/Distribution.xml"
productbuild --distribution "$WORK_DIR/Distribution.xml" --package-path "$WORK_DIR" \
  --sign "$PKG_IDENTITY" --timestamp "$OUTPUT_DIR/$PKG_NAME"
submit "$OUTPUT_DIR/$PKG_NAME" "$WORK_DIR/pkg-notarization.json"
xcrun stapler staple "$OUTPUT_DIR/$PKG_NAME"
xcrun stapler validate "$OUTPUT_DIR/$PKG_NAME"
pkgutil --check-signature "$OUTPUT_DIR/$PKG_NAME"
spctl --assess --type install --verbose=2 "$OUTPUT_DIR/$PKG_NAME"
cp "$WORK_DIR/app-notarization.json" "$OUTPUT_DIR/app-notarization.json"
cp "$WORK_DIR/pkg-notarization.json" "$OUTPUT_DIR/pkg-notarization.json"
printf 'version=%s\ncommit=%s\narchitectures=arm64,x86_64\n' "$VERSION" "$SOURCE_COMMIT" > "$OUTPUT_DIR/BUILD_INFO"
(cd "$OUTPUT_DIR" && shasum -a 256 "$PKG_NAME" "$ZIP_NAME" > SHA256SUMS)
echo "Verified release artifacts: $OUTPUT_DIR"
