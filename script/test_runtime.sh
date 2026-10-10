#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:---self-test}"
case "$MODE" in --self-test|--integration-test) ;; *) echo "Use --self-test or --integration-test" >&2; exit 2 ;; esac
APP_BUNDLE="${CLICKMORE_TEST_APP:-$ROOT_DIR/dist/ClickMore.app}"
if [[ -z "${CLICKMORE_TEST_APP:-}" ]]; then
  ./script/build_and_run.sh --build
else
  test -x "$APP_BUNDLE/Contents/MacOS/ClickMore"
  pkill -x ClickMore >/dev/null 2>&1 || true
fi
mkdir -p test-results
REPORT_PATH="$ROOT_DIR/test-results/runtime.json"
rm -f "$REPORT_PATH"
if [ "$MODE" = "--integration-test" ]; then
  TARGET_BUNDLE="$ROOT_DIR/dist/ClickMore Test Target.app"
  TARGET_REPORT="$ROOT_DIR/test-results/target.json"
  pkill -x ClickMoreTestTarget >/dev/null 2>&1 || true
  trap 'pkill -x ClickMoreTestTarget >/dev/null 2>&1 || true' EXIT
  mkdir -p "$TARGET_BUNDLE/Contents/MacOS" "$TARGET_BUNDLE/Contents/Resources"
  cp "$APP_BUNDLE/Contents/MacOS/ClickMore" "$TARGET_BUNDLE/Contents/MacOS/ClickMoreTestTarget"
  cp "$APP_BUNDLE/Contents/Info.plist" "$TARGET_BUNDLE/Contents/Info.plist"
  plutil -replace CFBundleExecutable -string ClickMoreTestTarget "$TARGET_BUNDLE/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string no.liseth.clickmore.test-target "$TARGET_BUNDLE/Contents/Info.plist"
  plutil -replace CFBundleName -string ClickMoreTestTarget "$TARGET_BUNDLE/Contents/Info.plist"
  codesign --force --sign - "$TARGET_BUNDLE"
  rm -f "$TARGET_REPORT"
  open -n "$TARGET_BUNDLE" --args --test-target --target-report "$TARGET_REPORT"
  for attempt in {1..50}; do
    if [ -f "$TARGET_REPORT" ]; then break; fi
    sleep 0.1
  done
  test -f "$TARGET_REPORT"
  open -n "$APP_BUNDLE" --args "$MODE" --target-report "$TARGET_REPORT" --report "$REPORT_PATH"
else
  open -n "$APP_BUNDLE" --args "$MODE" --report "$REPORT_PATH"
fi
for attempt in {1..50}; do
  if [ -f "$REPORT_PATH" ]; then break; fi
  sleep 0.1
done
if [ ! -f "$REPORT_PATH" ]; then
  echo "ClickMore did not produce its verification report." >&2
  exit 1
fi
cat "$REPORT_PATH"
test "$(plutil -extract passed raw -o - "$REPORT_PATH")" = "true"
