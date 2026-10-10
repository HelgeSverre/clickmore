#!/usr/bin/env bash
# Import release credentials into a temporary GitHub-hosted runner keychain.
# Both Application and Installer identities are required for the app and PKG.
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?This script is for GitHub-hosted runners}"
APPLE_SIGNING_KEYCHAIN="$RUNNER_TEMP/clickmore-signing.keychain-db"
APPLE_NOTARY_KEY_PATH="$RUNNER_TEMP/clickmore-notary.p8"

for name in RUNNER_TEMP APPLE_APPLICATION_CERTIFICATE_BASE64 \
  APPLE_APPLICATION_CERTIFICATE_PASSWORD APPLE_APPLICATION_SIGNING_IDENTITY \
  APPLE_INSTALLER_CERTIFICATE_BASE64 APPLE_INSTALLER_CERTIFICATE_PASSWORD \
  APPLE_INSTALLER_SIGNING_IDENTITY APPLE_NOTARY_KEY_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing release setting: $name (see README.md)" >&2
    exit 1
  fi
done

if [[ -e "$APPLE_SIGNING_KEYCHAIN" || -e "$APPLE_NOTARY_KEY_PATH" ]]; then
  echo "Refusing to overwrite existing signing assets" >&2
  exit 1
fi

certificate="$RUNNER_TEMP/clickmore-signing.p12"
installer="$RUNNER_TEMP/clickmore-installer.p12"
trap 'rm -f "$certificate" "$installer"' EXIT
printf '%s' "$APPLE_APPLICATION_CERTIFICATE_BASE64" | base64 -D > "$certificate"
printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 -D > "$APPLE_NOTARY_KEY_PATH"

keychain_password="$(openssl rand -base64 32)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$APPLE_SIGNING_KEYCHAIN"
security set-keychain-settings -lut 7200 "$APPLE_SIGNING_KEYCHAIN"
security unlock-keychain -p "$keychain_password" "$APPLE_SIGNING_KEYCHAIN"
security import "$certificate" -f pkcs12 -k "$APPLE_SIGNING_KEYCHAIN" \
  -P "$APPLE_APPLICATION_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
if [[ -n "${APPLE_INSTALLER_CERTIFICATE_BASE64:-}" ]]; then
  : "${APPLE_INSTALLER_CERTIFICATE_PASSWORD:?Missing release setting: APPLE_INSTALLER_CERTIFICATE_PASSWORD (see README.md)}"
  printf '%s' "$APPLE_INSTALLER_CERTIFICATE_BASE64" | base64 -D > "$installer"
  security import "$installer" -f pkcs12 -k "$APPLE_SIGNING_KEYCHAIN" \
    -P "$APPLE_INSTALLER_CERTIFICATE_PASSWORD" -T /usr/bin/productbuild -T /usr/bin/pkgbuild -T /usr/bin/security
fi
# After every import, so the signing tools can use each key without a prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$APPLE_SIGNING_KEYCHAIN" >/dev/null

existing_keychains=()
while read -r keychain_path; do
  keychain_path="${keychain_path//\"/}"
  [[ -z "$keychain_path" ]] || existing_keychains+=("$keychain_path")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$APPLE_SIGNING_KEYCHAIN" "${existing_keychains[@]}"

openssl pkey -in "$APPLE_NOTARY_KEY_PATH" -check -noout
printf 'APPLE_NOTARY_KEY_PATH=%s\n' "$APPLE_NOTARY_KEY_PATH" >> "$GITHUB_ENV"
