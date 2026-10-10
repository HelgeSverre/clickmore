#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/ClickMore.app"
cd "$ROOT_DIR"

case "$MODE" in
  run|--verify|--logs|--telemetry|--debug|--build) ;;
  *) echo "Usage: $0 [--build|--verify|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
pkill -x ClickMore >/dev/null 2>&1 || true
# Xcode's SwiftPM backend resolves package resources inside a signed macOS app.
BUILD_ARGS=(--build-system xcode --scratch-path .build/development)
swift build "${BUILD_ARGS[@]}" --product ClickMore
BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/ClickMore" "$APP_BUNDLE/Contents/MacOS/ClickMore"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
if [ -f Resources/ClickMore.icns ]; then
  cp Resources/ClickMore.icns "$APP_BUNDLE/Contents/Resources/ClickMore.icns"
fi
./script/stage_package_resources.sh "$BUILD_DIR" "$APP_BUNDLE"
SIGN_IDENTITY="${CLICKMORE_SIGN_IDENTITY:--}"
SIGN_IDENTITIES="$(security find-identity -v -p codesigning)"
if [ "$SIGN_IDENTITY" = "-" ] && [[ "$SIGN_IDENTITIES" == *'Apple Development:'* ]]; then
  SIGN_IDENTITY="Apple Development"
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier no.liseth.clickmore "$APP_BUNDLE"

case "$MODE" in
  --build) echo "Built $APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/ClickMore" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "no.liseth.clickmore"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x ClickMore >/dev/null
    echo "ClickMore is running."
    ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
