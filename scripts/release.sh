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

required_tools=(create-dmg xcrun)
# gh is only needed when this script publishes the release itself. In CI the
# workflow uploads the DMG, so gh is absent and must not be required.
if (( PUBLISH )); then
  required_tools+=(gh)
fi
for tool in "${required_tools[@]}"; do
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

# The sherpa-onnx static library is not committed; without it the link step
# fails late, after the slow archive. Fail fast with an actionable message.
if [[ ! -d "$ROOT/.deps/sherpa-onnx/build-swift-macos/sherpa-onnx.xcframework" ]]; then
  echo "Missing sherpa-onnx xcframework. Run ./scripts/build-sherpa-onnx.sh first." >&2
  exit 1
fi

# In CI the certificate lives in a temporary keychain rather than the login
# keychain, and xcodebuild only searches the user's keychain list.
KEYCHAIN_ARGS=()
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
  KEYCHAIN_ARGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp --keychain $SIGNING_KEYCHAIN")
else
  KEYCHAIN_ARGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp")
fi

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
  "${KEYCHAIN_ARGS[@]}"

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

# create-dmg emits an unsigned disk image. Notarization would still succeed —
# it validates the signed .app inside — but Gatekeeper rejects the container
# itself with "source=no usable signature", so the DMG must be signed too.
echo "==> Signing DMG"
codesign --force \
  --sign "$SIGNING_IDENTITY" \
  --timestamp \
  ${SIGNING_KEYCHAIN:+--keychain "$SIGNING_KEYCHAIN"} \
  "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait
xcrun stapler staple "$DMG_PATH"

# Gatekeeper's actual verdict, not just "the ticket attached". This is the check
# that catches an unsigned or improperly signed container.
echo "==> Verifying DMG"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

if (( PUBLISH )); then
  echo "==> Publishing GitHub release for $TAG"
  gh release create "$TAG" "$DMG_PATH" \
    --title "$TAG" \
    --generate-notes
else
  echo "==> Skipping GitHub release (--no-publish)"
fi

echo "==> Done. DMG: $DMG_PATH"
