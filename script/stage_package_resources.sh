#!/usr/bin/env bash
# Stage SwiftPM resources in the standard signed macOS app location.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:?Build directory required}"
APP_BUNDLE="${2:?App bundle required}"
RESOURCE_NAME="PermissionFlow_PermissionFlow.bundle"
test -d "$BUILD_DIR/$RESOURCE_NAME"
mkdir -p "$APP_BUNDLE/Contents/Resources"
ditto "$BUILD_DIR/$RESOURCE_NAME" "$APP_BUNDLE/Contents/Resources/$RESOURCE_NAME"
cp "$ROOT_DIR/Resources/ThirdPartyNotices.txt" "$APP_BUNDLE/Contents/Resources/ThirdPartyNotices.txt"
