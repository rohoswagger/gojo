#!/usr/bin/env bash
#
# scripts/release.sh — build, sign, notarize, package, and publish a Gojo release.
#
# Usage:
#   scripts/release.sh <version>            # Developer ID signed + notarized release
#   scripts/release.sh <version> --adhoc    # ad-hoc signed, no notarization (no paid account)
#   scripts/release.sh <version> --private  # signed + notarized DMG only: no GitHub
#                                           # Release, no appcast. For paid/paywalled
#                                           # distribution — upload the DMG yourself.
#   DRY_RUN=1 scripts/release.sh <version>  # build the artifacts but don't publish
#
# --adhoc cuts a release with NO Apple Developer account: the app is ad-hoc
# signed (CODE_SIGN_IDENTITY="-"), not notarized. The DMG opens only after the
# user clears quarantine: xattr -dr com.apple.quarantine /Applications/Gojo.app
# Good for free/open-source distribution to technical users; notarize for a
# polished public launch.
#
# Required configuration (set in .env.local at repo root, or via environment):
#   MACOS_SIGNING_IDENTITY                — e.g. "Developer ID Application: Your Name (TEAMID)"
#   APP_STORE_CONNECT_API_KEY             — path to .p8
#   APP_STORE_CONNECT_API_KEY_ID          — 10-char Key ID
#   APP_STORE_CONNECT_API_KEY_ISSUER_ID   — UUID-format Issuer ID
#   SPARKLE_PRIVATE_ED_KEY                — exported Sparkle EdDSA private key: a file path OR the raw key value
#
# Required tools:
#   Xcode (xcrun, codesign, hdiutil, notarytool, stapler)
#   wrangler (via npx), authenticated to Cloudflare (`npx wrangler login`) — publishes the DMG to R2
#   python3
#   curl, tar
#
set -euo pipefail

# -------- helpers --------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

log()   { printf "${BOLD}==> %s${RESET}\n" "$*"; }
info()  { printf "    %s\n" "$*"; }
ok()    { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${RESET} %s\n" "$*" >&2; }
die()   { printf "${RED}✗${RESET} %s\n" "$*" >&2; exit 1; }

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    die "$name is not set. Add it to .env.local or export it."
  fi
}

# -------- 0. Parse args + load env --------

VERSION=""
ADHOC=0
PRIVATE=0
for arg in "$@"; do
  case "$arg" in
    --adhoc) ADHOC=1 ;;
    --private) PRIVATE=1 ;;
    -*) die "Unknown option: $arg" ;;
    *) VERSION="$arg" ;;
  esac
done

[ -z "$VERSION" ] && die "Usage: scripts/release.sh <version> [--adhoc] [--private]"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Version must be semver (X.Y.Z), got: $VERSION"
fi

DRY_RUN="${DRY_RUN:-0}"

if [ "$ADHOC" = "1" ]; then
  warn "--adhoc: ad-hoc-signed build (no Developer ID cert, no notarization)."
  warn "Gatekeeper will block it on download; users must run:"
  warn "  xattr -dr com.apple.quarantine /Applications/Gojo.app"
fi

if [ -f .env.local ]; then
  set -a
  # shellcheck disable=SC1091
  source .env.local
  set +a
  info "Loaded .env.local"
fi

require_env SPARKLE_PRIVATE_ED_KEY

if [ "$ADHOC" != "1" ]; then
  require_env MACOS_SIGNING_IDENTITY
  require_env APP_STORE_CONNECT_API_KEY
  require_env APP_STORE_CONNECT_API_KEY_ID
  require_env APP_STORE_CONNECT_API_KEY_ISSUER_ID
  [ -f "$APP_STORE_CONNECT_API_KEY" ] || die "API key not found: $APP_STORE_CONNECT_API_KEY"
fi

# SPARKLE_PRIVATE_ED_KEY may be either a path to the exported key file, or the
# raw EdDSA private key value itself (e.g. stored inline in .env.local).
# Normalize to a file for sign_update either way.
if [ -f "$SPARKLE_PRIVATE_ED_KEY" ]; then
  SPARKLE_KEY_FILE="$SPARKLE_PRIVATE_ED_KEY"
else
  SPARKLE_KEY_FILE="$(mktemp)"
  chmod 600 "$SPARKLE_KEY_FILE"
  printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" > "$SPARKLE_KEY_FILE"
  trap 'rm -f "$SPARKLE_KEY_FILE"' EXIT
fi

command -v python3 >/dev/null || die "python3 not on PATH"
if [ "$PRIVATE" != "1" ]; then
  # The DMG is published to the Cloudflare R2 bucket via wrangler (fetched with npx).
  command -v npx >/dev/null || die "npx not on PATH (need Node.js for wrangler)"
fi

# -------- 1. Pre-flight checks --------

log "Pre-flight checks for v$VERSION"

# Working tree clean
if [ -n "$(git status --porcelain)" ]; then
  warn "Working tree has uncommitted changes:"
  git status --short
  if [ "$DRY_RUN" != "1" ]; then
    die "Commit or stash before releasing (or run with DRY_RUN=1 to test build only)."
  fi
fi

# On main branch
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ] && [ "$DRY_RUN" != "1" ]; then
  die "Not on main (on '$BRANCH'). Switch to main before releasing."
fi

# Tag doesn't already exist
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  die "Tag v$VERSION already exists locally. Delete it (git tag -d v$VERSION) or pick a different version."
fi
if [ "$DRY_RUN" != "1" ] && git ls-remote --tags origin "refs/tags/v$VERSION" | grep -q .; then
  die "Tag v$VERSION already exists on origin. Delete it (git push origin :refs/tags/v$VERSION) or pick a different version."
fi

# MARKETING_VERSION in pbxproj matches
PROJ_VERSION=$(grep -o 'MARKETING_VERSION = [0-9.]*;' Gojo.xcodeproj/project.pbxproj | head -1 | grep -o '[0-9.]*' | head -1)
if [ "$PROJ_VERSION" != "$VERSION" ]; then
  die "MARKETING_VERSION in project.pbxproj is $PROJ_VERSION, not $VERSION. Bump it first."
fi

# CHANGELOG has entry for this version
if ! grep -qE "^## \[$VERSION\]" CHANGELOG.md; then
  die "CHANGELOG.md has no '## [$VERSION]' section. Promote [Unreleased] before releasing."
fi

# Signing identity is in the keychain (Developer ID path only)
if [ "$ADHOC" != "1" ]; then
  if ! security find-identity -v -p codesigning | grep -q "$MACOS_SIGNING_IDENTITY"; then
    die "Signing identity not found in keychain: $MACOS_SIGNING_IDENTITY"
  fi
fi

ok "All checks passed"

# -------- 2. Build Release --------

log "Building Release v$VERSION"

BUILD_DIR=".build/release"
APP_PATH="$BUILD_DIR/Build/Products/Release/Gojo.app"
BUILD_NUMBER=$(date +%s)  # monotonic-enough for us

if [ "$ADHOC" = "1" ]; then
  # Ad-hoc: sign with "-" (no cert/team/timestamp/hardened-runtime), so it builds
  # without an Apple Developer account. Distributable but not notarized.
  # Hardened runtime forces library validation, which an ad-hoc (teamless) app
  # can't satisfy against vendored frameworks signed by other teams — it crashes
  # on launch. Hardened runtime is only needed for notarization, so disable it.
  SIGN_ARGS=( CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES ENABLE_HARDENED_RUNTIME=NO )
else
  # CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO stops Xcode auto-adding the debug-only
  # get-task-allow entitlement (a `build` invocation is treated as development);
  # notarization rejects get-task-allow in a distribution build.
  SIGN_ARGS=( CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$MACOS_SIGNING_IDENTITY" DEVELOPMENT_TEAM=L6U44C67P5 CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" )
fi

xcodebuild \
  -project Gojo.xcodeproj \
  -scheme Gojo \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  "${SIGN_ARGS[@]}" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build \
  >/tmp/gojo-build.log 2>&1 \
  || (tail -40 /tmp/gojo-build.log; die "Build failed. Full log: /tmp/gojo-build.log")

[ -d "$APP_PATH" ] || die "Build did not produce $APP_PATH"

ok "Built and signed $APP_PATH"

# -------- 2b. Re-sign vendored binaries (Developer ID path only) --------
# Xcode signs the app + its own targets, but pre-built vendored binaries stay
# ad-hoc: Sparkle's nested XPC helpers and the MediaRemoteAdapter test client.
# Notarization requires every Mach-O to carry a Developer ID signature + secure
# timestamp + hardened runtime, so re-sign them inside-out, then re-seal the app.
if [ "$ADHOC" != "1" ]; then
  log "Re-signing vendored components with Developer ID"
  RESIGN=( codesign --force --timestamp --options runtime --preserve-metadata=entitlements --sign "$MACOS_SIGNING_IDENTITY" )
  SPK="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
  for item in \
    "$SPK/XPCServices/Downloader.xpc" \
    "$SPK/XPCServices/Installer.xpc" \
    "$SPK/Autoupdate" \
    "$SPK/Updater.app" \
    "$APP_PATH/Contents/Frameworks/Sparkle.framework" \
    "$APP_PATH/Contents/Resources/MediaRemoteAdapterTestClient"; do
    [ -e "$item" ] && { "${RESIGN[@]}" "$item" || die "re-sign failed: $item"; }
  done
  # Re-seal the outer app (nested hashes changed); keep its own entitlements.
  codesign --force --timestamp --options runtime \
    --entitlements Gojo/Gojo.entitlements \
    --sign "$MACOS_SIGNING_IDENTITY" "$APP_PATH" || die "re-seal failed: $APP_PATH"
  ok "Vendored components re-signed"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>/dev/null \
  || die "Codesign verification failed on $APP_PATH"

ok "Signature verified"

# -------- 3. Notarize app --------

if [ "$ADHOC" = "1" ]; then
  warn "Skipping app notarization (--adhoc)"
else
  log "Notarizing app"

  ZIP_PATH="/tmp/Gojo-$VERSION-app.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

  xcrun notarytool submit "$ZIP_PATH" \
    --key "$APP_STORE_CONNECT_API_KEY" \
    --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_API_KEY_ISSUER_ID" \
    --wait \
    --timeout 30m

  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$ZIP_PATH"

  ok "App notarized and stapled"
fi

# -------- 4. Create styled DMG --------

log "Creating DMG"

DMG_NAME="Gojo-$VERSION.dmg"
DMG_PATH=".build/$DMG_NAME"
rm -f "$DMG_PATH"

# Install the pinned dmgbuild toolchain into an isolated venv so the styled DMG
# (custom background + icon layout, see Configuration/dmg/) builds reproducibly
# without polluting the system Python.
DMG_VENV=".build/dmg-venv"
if [ ! -x "$DMG_VENV/bin/dmgbuild" ]; then
  info "Setting up dmgbuild venv…"
  python3 -m venv "$DMG_VENV"
  "$DMG_VENV/bin/pip" install --quiet --upgrade pip
  "$DMG_VENV/bin/pip" install --quiet --require-hashes -r Configuration/dmg/requirements.txt
fi

PATH="$REPO_ROOT/$DMG_VENV/bin:$PATH" \
  Configuration/dmg/create_dmg.sh "$APP_PATH" "$DMG_PATH" "Gojo $VERSION"

[ -f "$DMG_PATH" ] || die "DMG was not created at $DMG_PATH"

if [ "$ADHOC" = "1" ]; then
  codesign --sign "-" "$DMG_PATH"
else
  codesign --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$DMG_PATH"
fi

ok "DMG created: $DMG_PATH"

# -------- 5. Notarize DMG --------

if [ "$ADHOC" = "1" ]; then
  warn "Skipping DMG notarization (--adhoc)"
else
  log "Notarizing DMG"

  xcrun notarytool submit "$DMG_PATH" \
    --key "$APP_STORE_CONNECT_API_KEY" \
    --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_API_KEY_ISSUER_ID" \
    --wait \
    --timeout 30m

  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  ok "DMG notarized and stapled"
fi

# -------- 6. Sign DMG with Sparkle --------

log "Signing DMG with Sparkle"

SPARKLE_VERSION="2.8.0"
SPARKLE_DIR=".build/sparkle-tools/$SPARKLE_VERSION"
SIGN_UPDATE="$SPARKLE_DIR/bin/sign_update"

if [ ! -x "$SIGN_UPDATE" ]; then
  info "Downloading Sparkle $SPARKLE_VERSION CLI tools…"
  mkdir -p "$SPARKLE_DIR"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$SPARKLE_DIR"
fi

SIGNATURE_LINE=$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY_FILE" "$DMG_PATH")
DMG_SIZE=$(stat -f%z "$DMG_PATH")

ok "Sparkle signature: $SIGNATURE_LINE"

# -------- 7. Update appcast.xml + extract release notes --------

if [ "$PRIVATE" = "1" ]; then
  warn "Skipping appcast update (--private): the public appcast must not list paid builds."
else
  log "Updating appcast.xml"

  python3 .github/scripts/update_appcast.py \
    --appcast docs/appcast.xml \
    --version "$VERSION" \
    --build "$BUILD_NUMBER" \
    --dmg-url "https://downloads.rohoswagger.com/$DMG_NAME" \
    --dmg-size "$DMG_SIZE" \
    --ed-signature-line "$SIGNATURE_LINE" \
    --release-notes-out ".build/release-notes-$VERSION.md"

  ok "appcast.xml updated, release notes at .build/release-notes-$VERSION.md"
fi

# -------- 8. Dry run stops here --------

if [ "$DRY_RUN" = "1" ]; then
  log "DRY_RUN=1 — stopping before publish"
  info "Artifacts:"
  info "  DMG:    $DMG_PATH"
  [ "$PRIVATE" = "1" ] || info "  Notes:  .build/release-notes-$VERSION.md"
  info "Inspect, then re-run without DRY_RUN to publish."
  exit 0
fi

# -------- 8b. Private release stops after tagging --------

if [ "$PRIVATE" = "1" ]; then
  log "Tagging v$VERSION (private release)"
  git tag -a "v$VERSION" -m "Gojo $VERSION (private)"
  git push origin "v$VERSION"

  log "Private release v$VERSION ready"
  info "  DMG:               $DMG_PATH"
  info "  DMG SHA-256:       $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
  info "  DMG size:          $DMG_SIZE bytes"
  info "  Build number:      $BUILD_NUMBER"
  info "  Sparkle signature: $SIGNATURE_LINE"
  info ""
  info "Upload the DMG to your distribution channel. Keep the size, build number,"
  info "and Sparkle signature — a private appcast entry needs all three."
  exit 0
fi

# -------- 9. Upload the DMG to Cloudflare R2 --------

log "Uploading DMG to R2 (gojo-downloads)"

# wrangler picks up its own OAuth login; pin the account so it never prompts.
export CLOUDFLARE_ACCOUNT_ID=54b7185040a2db03ec87bee9cd65135f
R2_PUT=( npx --yes wrangler@4 r2 object put --remote --content-type application/x-apple-diskimage --file "$DMG_PATH" )

# Versioned, immutable object so historical appcast entries keep resolving.
"${R2_PUT[@]}" "gojo-downloads/$DMG_NAME" \
  || die "R2 upload failed for $DMG_NAME (is wrangler authenticated? run: npx wrangler login)"
# Always-latest object for the marketing site's download button.
"${R2_PUT[@]}" "gojo-downloads/Gojo.dmg" \
  || die "R2 upload failed for Gojo.dmg"

ok "DMG uploaded to https://downloads.rohoswagger.com/$DMG_NAME (and /Gojo.dmg)"

# -------- 9b. Tag the release --------

log "Tagging v$VERSION"
git tag -a "v$VERSION" -m "Gojo $VERSION"
git push origin "v$VERSION"

# -------- 10. Commit appcast.xml back to main --------

log "Committing appcast.xml"

git add docs/appcast.xml
git commit -m "chore: appcast for v$VERSION"
git push origin main

ok "appcast.xml committed and pushed"

# -------- Done --------

log "Released Gojo v$VERSION"
info "  Download (versioned): https://downloads.rohoswagger.com/$DMG_NAME"
info "  Download (latest):    https://downloads.rohoswagger.com/Gojo.dmg"
info "  Appcast: https://rohoswagger.github.io/gojo/appcast.xml"
info "  DMG SHA-256: $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
