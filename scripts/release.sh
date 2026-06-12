#!/usr/bin/env bash
#
# Build, sign, notarize, package, and publish a TingMo release.
#
# Usage:
#   ./scripts/release.sh v0.1.0                # full release, publishes to GitHub
#   ./scripts/release.sh v0.1.0 --no-publish   # build + notarize + DMG only (local test)
#
# Required environment variables (put them in scripts/.env.release, which is gitignored):
#   DEVELOPMENT_TEAM      10-char Team ID
#   SIGNING_IDENTITY      e.g. "Developer ID Application: Name (TEAMID)"
#   APPLE_ID              Apple ID email used for notarization
#   APPLE_APP_PASSWORD    app-specific password from appleid.apple.com
#   APPLE_TEAM_ID         same as DEVELOPMENT_TEAM
#
# Prerequisites:
#   - Xcode (with the signing identity in your login keychain)
#   - gh CLI (authenticated: `gh auth login`)
#   - create-dmg (`brew install create-dmg`)

set -euo pipefail

TAG=""
PUBLISH=1
for arg in "$@"; do
  case "$arg" in
    --no-publish) PUBLISH=0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) TAG="$arg" ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag> [--no-publish]   (e.g. $0 v0.1.0)" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG does not exist locally. Create and push it first:" >&2
  echo "  git tag $TAG && git push origin $TAG" >&2
  exit 1
fi

for tool in create-dmg gh xcrun; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

# Derive app version from the tag; build number increments with history.
VERSION="${TAG#v}"
BUILD_NUMBER="$(git rev-list --count "$TAG")"

# Load env file if present
if [[ -f scripts/.env.release ]]; then
  set -a
  # shellcheck disable=SC1091
  source scripts/.env.release
  set +a
fi

: "${DEVELOPMENT_TEAM:?missing}"
: "${SIGNING_IDENTITY:?missing}"
: "${APPLE_ID:?missing}"
: "${APPLE_APP_PASSWORD:?missing}"
: "${APPLE_TEAM_ID:?missing}"

SCHEME="TingMo"
CONFIGURATION="Release"
PROJECT="TingMo.xcodeproj"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/TingMo.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/TingMo-${TAG}.dmg"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"

echo "==> Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  ARCHS=arm64 \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

echo "==> Preparing ExportOptions.plist"
sed "s/\$(DEVELOPMENT_TEAM)/$DEVELOPMENT_TEAM/g" \
  Config/ExportOptions.plist > "$EXPORT_PLIST"

echo "==> Exporting archive"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

APP_PATH="$EXPORT_DIR/$SCHEME.app"
ZIP_PATH="$BUILD_DIR/$SCHEME.zip"

echo "==> Notarizing app"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$APP_PATH"

echo "==> Creating DMG"
create-dmg \
  --volname "TingMo" \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "$SCHEME.app" 175 190 \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$DMG_PATH"

if (( PUBLISH )); then
  echo "==> Publishing GitHub release for $TAG"
  gh release create "$TAG" "$DMG_PATH" \
    --title "$TAG" \
    --generate-notes
else
  echo "==> Skipping GitHub release (--no-publish)"
fi

echo "==> Done. DMG: $DMG_PATH"
