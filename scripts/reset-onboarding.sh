#!/usr/bin/env bash
#
# reset-onboarding.sh — wipe Gojo's user configuration so the onboarding flow
# runs again from the welcome screen on next launch.
#
# Gojo is sandboxed, so its @AppStorage + Defaults values live in the app's
# container, not the legacy ~/Library/Preferences plist. We clear both, drop
# cfprefsd's in-memory cache, and (unless --keep-permissions) reset the TCC
# grants so the permission prompts reappear during onboarding.
#
# Usage:
#   scripts/reset-onboarding.sh                 # reset config + permissions
#   scripts/reset-onboarding.sh --keep-permissions
#

set -euo pipefail

BUNDLE_ID="rohoswagger.gojo"
KEEP_PERMISSIONS=0

for arg in "$@"; do
	case "$arg" in
		--keep-permissions) KEEP_PERMISSIONS=1 ;;
		-h|--help)
			grep '^#' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Stopping any running Gojo"
make -C "$REPO_ROOT" stop >/dev/null 2>&1 || true

echo "==> Clearing defaults (container + legacy)"
CONTAINER_PLIST="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Preferences/$BUNDLE_ID.plist"
LEGACY_PLIST="$HOME/Library/Preferences/$BUNDLE_ID.plist"
rm -f "$CONTAINER_PLIST" "$LEGACY_PLIST"

# cfprefsd caches preferences in memory and would otherwise rewrite the plist
# we just deleted. Drop its cache so the deletion sticks.
killall cfprefsd >/dev/null 2>&1 || true

if [ "$KEEP_PERMISSIONS" -eq 0 ]; then
	echo "==> Resetting TCC permissions"
	for service in Camera Calendar Reminders Accessibility; do
		tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
	done
fi

echo "==> Done. Onboarding will run on next launch."
echo "    Run 'make run' to build + launch."
