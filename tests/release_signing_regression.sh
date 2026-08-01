#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RELEASE_SCRIPT="$ROOT/scripts/release.sh"
VERIFY_SCRIPT="$ROOT/scripts/verify-sparkle-entitlements.sh"

resign_block="$(sed -n '/Re-seal the outer app/,/ok "Vendored components re-signed"/p' "$RELEASE_SCRIPT")"
if grep -Fq -- '--entitlements Gojo/Gojo.entitlements' <<<"$resign_block"; then
  echo "release script re-signs the app with the unexpanded entitlement template" >&2
  exit 1
fi
if ! grep -Fq -- '--preserve-metadata=entitlements' <<<"$resign_block"; then
  echo "release script re-seal no longer preserves the entitlements Xcode expanded" >&2
  exit 1
fi
if ! grep -Fq -- 'verify-sparkle-entitlements.sh' "$RELEASE_SCRIPT"; then
  echo "release script no longer runs the Sparkle entitlement verifier" >&2
  exit 1
fi

fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-release-signing-test.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
mock_bin="$fixture_dir/bin"
fixture_app="$fixture_dir/Gojo.app"
mkdir -p "$mock_bin" "$fixture_app/Contents"
touch "$fixture_app/Contents/Info.plist"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\\n" "rohoswagger.gojo"' \
  >"$mock_bin/plutil"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${SPARKLE_TEST_MODE:-good}" == bad ]]; then' \
  '  printf "%s\\n" "<string>\$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>"' \
  '  printf "%s\\n" "<string>\$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>"' \
  'else' \
  '  printf "%s\\n" "<string>rohoswagger.gojo-spks</string>"' \
  '  printf "%s\\n" "<string>rohoswagger.gojo-spki</string>"' \
  'fi' \
  >"$mock_bin/codesign"
chmod +x "$mock_bin/plutil" "$mock_bin/codesign"

# stderr is suppressed: the verifier is *expected* to complain here, and letting
# that message through makes a passing run look like a failing one.
if SPARKLE_TEST_MODE=bad PATH="$mock_bin:$PATH" "$VERIFY_SCRIPT" "$fixture_app" 2>/dev/null; then
  echo "entitlement verifier accepted unexpanded Sparkle service names" >&2
  exit 1
fi

SPARKLE_TEST_MODE=good PATH="$mock_bin:$PATH" "$VERIFY_SCRIPT" "$fixture_app"
