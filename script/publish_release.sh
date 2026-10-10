#!/usr/bin/env bash
# Publish already notarized artifacts and update the public Homebrew tap.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
TAG="v$VERSION"
OUTPUT_DIR="$ROOT_DIR/dist/releases/$VERSION"
if [[ -n "$(git status --porcelain)" ]] || [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Publish from a clean main branch." >&2; exit 1
fi
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test "$(sed -n 's/^commit=//p' "$OUTPUT_DIR/BUILD_INFO")" = "$(git rev-parse HEAD)"
./script/verify_release.sh "$VERSION"
gh auth status >/dev/null

if git rev-parse "$TAG" >/dev/null 2>&1; then
  test "$(git rev-parse "$TAG^{commit}")" = "$(git rev-parse HEAD)"
else
  git tag -a "$TAG" -m "ClickMore $VERSION"
fi
git push origin "$TAG"
if ! gh release view "$TAG" --repo HelgeSverre/clickmore >/dev/null 2>&1; then
  cat > "$OUTPUT_DIR/release-notes.md" <<EOF
ClickMore turns one click on a floating trigger into an ordered click at every connected spot.

### Install

- **Homebrew:** \`brew install --cask helgesverre/tap/clickmore\`
- **PKG:** download \`ClickMore-$VERSION-universal.pkg\` and follow Installer.
- **ZIP:** extract and move \`ClickMore.app\` into Applications.

Supports macOS 14 or later, on Apple Silicon and Intel. The app and installer are Developer ID signed, notarized by Apple, and stapled. Enable ClickMore in System Settings → Privacy & Security → Accessibility to click other apps.

Option-drag creates spots; Command-drag moves the whole layout. Both modifiers can be rebound in Settings. This release also includes clear-all, VoiceOver actions, and improved routing tested with clustered layouts of up to 64 spots.

SHA256SUMS verifies both downloads. BUILD_INFO identifies the source commit. The README includes an animated walkthrough and setup instructions.
EOF
  gh release create "$TAG" --repo HelgeSverre/clickmore --verify-tag --title "ClickMore $VERSION" \
    --notes-file "$OUTPUT_DIR/release-notes.md" \
    "$OUTPUT_DIR/ClickMore-$VERSION-universal.pkg" \
    "$OUTPUT_DIR/ClickMore-$VERSION-universal.zip" "$OUTPUT_DIR/SHA256SUMS" "$OUTPUT_DIR/BUILD_INFO"
else
  # Published versions are immutable: a retry must match the uploaded checksums.
  EXISTING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clickmore-published.XXXXXX")"
  trap 'rm -rf "$EXISTING_DIR"' EXIT
  gh release download "$TAG" --repo HelgeSverre/clickmore --pattern SHA256SUMS --dir "$EXISTING_DIR"
  cmp "$OUTPUT_DIR/SHA256SUMS" "$EXISTING_DIR/SHA256SUMS"
fi

TAP_DIR="${CLICKMORE_TAP_DIR:-$ROOT_DIR/.build/homebrew-tap-release}"
if [[ ! -d "$TAP_DIR/.git" ]]; then
  gh repo clone HelgeSverre/homebrew-tap "$TAP_DIR"
fi
test -z "$(git -C "$TAP_DIR" status --porcelain)"
git -C "$TAP_DIR" checkout main
git -C "$TAP_DIR" pull --ff-only origin main
ZIP_SHA="$(shasum -a 256 "$OUTPUT_DIR/ClickMore-$VERSION-universal.zip" | awk '{print $1}')"
mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/clickmore.rb" <<EOF
cask "clickmore" do
  version "$VERSION"
  sha256 "$ZIP_SHA"

  url "https://github.com/HelgeSverre/clickmore/releases/download/v#{version}/ClickMore-#{version}-universal.zip"
  name "ClickMore"
  desc "Floating trigger that clicks multiple screen positions in sequence"
  homepage "https://github.com/HelgeSverre/clickmore"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "ClickMore.app"

  uninstall quit: "no.liseth.clickmore"

  caveats <<~EOS
    Enable ClickMore in System Settings → Privacy & Security → Accessibility.
    Launch it from Applications; its controls live in the menu bar and floating overlay.
  EOS
end
EOF
brew style "$TAP_DIR/Casks/clickmore.rb"
if ! git -C "$TAP_DIR" diff --quiet -- Casks/clickmore.rb || [[ -n "$(git -C "$TAP_DIR" ls-files --others --exclude-standard Casks/clickmore.rb)" ]]; then
  git -C "$TAP_DIR" add Casks/clickmore.rb
  git -C "$TAP_DIR" commit -m "Update ClickMore to $VERSION"
  git -C "$TAP_DIR" push origin main
fi
echo "Published https://github.com/HelgeSverre/clickmore/releases/tag/$TAG and helgesverre/tap/clickmore."
