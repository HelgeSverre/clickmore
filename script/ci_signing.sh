#!/usr/bin/env bash
# Import only the release identities into an ephemeral runner Keychain.
set -euo pipefail
: "${RUNNER_TEMP:?This script is for GitHub-hosted runners}"
: "${CLICKMORE_APP_P12_BASE64:?}"
: "${CLICKMORE_INSTALLER_P12_BASE64:?}"
: "${CLICKMORE_P12_PASSWORD:?}"
: "${CLICKMORE_NOTARY_APPLE_ID:?}"
: "${CLICKMORE_NOTARY_PASSWORD:?}"
: "${CLICKMORE_NOTARY_TEAM_ID:?}"
umask 077
KEYCHAIN="$RUNNER_TEMP/clickmore-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
echo "::add-mask::$KEYCHAIN_PASSWORD"
printf '%s' "$CLICKMORE_APP_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/clickmore-application.p12"
printf '%s' "$CLICKMORE_INSTALLER_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/clickmore-installer.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
for certificate in "$RUNNER_TEMP/clickmore-application.p12" "$RUNNER_TEMP/clickmore-installer.p12"; do
  security import "$certificate" -P "$CLICKMORE_P12_PASSWORD" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/productsign
done
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
xcrun notarytool store-credentials clickmore-ci --keychain "$KEYCHAIN" \
  --apple-id "$CLICKMORE_NOTARY_APPLE_ID" --team-id "$CLICKMORE_NOTARY_TEAM_ID" \
  --password "$CLICKMORE_NOTARY_PASSWORD"
printf 'CLICKMORE_NOTARY_PROFILE=clickmore-ci\nCLICKMORE_NOTARY_KEYCHAIN=%s\n' "$KEYCHAIN" >> "$GITHUB_ENV"
rm -f "$RUNNER_TEMP/clickmore-application.p12" "$RUNNER_TEMP/clickmore-installer.p12"
