#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s /path/to/Gojo.app\n' "$0" >&2
  exit 2
fi

app_path="$1"
info_plist="$app_path/Contents/Info.plist"

if [ ! -d "$app_path" ] || [ ! -f "$info_plist" ]; then
  printf 'Sparkle entitlement check requires an app bundle: %s\n' "$app_path" >&2
  exit 1
fi

bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
entitlements="$(codesign -d --entitlements :- "$app_path" 2>/dev/null)"

for service_name in "$bundle_id-spks" "$bundle_id-spki"; do
  if ! grep -Fq "<string>$service_name</string>" <<<"$entitlements"; then
    printf 'Signed app is missing Sparkle sandbox mach-lookup entitlement: %s\n' "$service_name" >&2
    exit 1
  fi
done

if grep -Fq '$(PRODUCT_BUNDLE_IDENTIFIER)' <<<"$entitlements"; then
  printf 'Signed app still contains an unexpanded PRODUCT_BUNDLE_IDENTIFIER entitlement placeholder\n' >&2
  exit 1
fi

printf 'Sparkle sandbox entitlements verified for %s\n' "$bundle_id"
