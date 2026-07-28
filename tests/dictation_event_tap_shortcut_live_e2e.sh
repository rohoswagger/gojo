#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"
NOTIFICATION_NAME="rohoswagger.gojo.dictation-event-tap-shortcut-e2e-probe"
LOG_CATEGORY="event-tap-shortcut"
FIXTURE_DIR=""
FIXTURE_PID=""

cleanup() {
  if [[ -n "$FIXTURE_PID" ]] && kill -0 "$FIXTURE_PID" 2>/dev/null; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
  release_dictation_live_lock
}
trap cleanup EXIT INT TERM

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi
acquire_dictation_live_lock

make -C "$ROOT" stop >/dev/null
started_at="$(date '+%Y-%m-%d %H:%M:%S')"
open -g "$APP"

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-dictation-shortcut-e2e.XXXXXX")"
fixture_app="$FIXTURE_DIR/GojoDictationFixture.app"
fixture_binary="$fixture_app/Contents/MacOS/GojoDictationFixture"
fixture_ready="$FIXTURE_DIR/ready"
fixture_text="$FIXTURE_DIR/text"
fixture_log="$FIXTURE_DIR/fixture.log"
mkdir -p "$fixture_app/Contents/MacOS"
swiftc -parse-as-library "$ROOT/tests/dictation_e2e_fixture.swift" -o "$fixture_binary"
plutil -create xml1 "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string GojoDictationFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string rohoswagger.gojo.DictationShortcutFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleName -string GojoDictationFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$fixture_app/Contents/Info.plist"
open -n "$fixture_app" --stdout "$fixture_log" --stderr "$fixture_log" --args \
  "$fixture_ready" "$fixture_text" "rohoswagger.gojo.dictation-shortcut-fixture-unused"

for _ in $(seq 1 1200); do
  [[ -f "$fixture_ready" ]] && break
  sleep 0.05
done
if [[ ! -f "$fixture_ready" ]]; then
  cat "$fixture_log" >&2
  echo "Timed out waiting for the shortcut fixture." >&2
  exit 1
fi
FIXTURE_PID="$(tr -d '[:space:]' < "$fixture_ready")"
if [[ ! "$FIXTURE_PID" =~ ^[0-9]+$ ]] || ! kill -0 "$FIXTURE_PID" 2>/dev/null; then
  cat "$fixture_log" >&2
  echo "The shortcut fixture stopped before the probe started." >&2
  exit 1
fi

ready=false
for _ in $(seq 1 600); do
  if /usr/bin/log show \
      --style compact \
      --start "$started_at" \
      --predicate 'subsystem == "rohoswagger.gojo.dictation" AND category == "shortcut"' \
      | grep -q 'monitor started chord=control+option'; then
    ready=true
    break
  fi
  sleep 0.1
done

if [[ "$ready" != true ]]; then
  echo "Timed out waiting for Gojo to finish launching." >&2
  exit 1
fi

swift "$ROOT/tests/dictation_e2e_focus.swift" GojoDictationFixture
sleep 0.3

swift -e "
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(\"$NOTIFICATION_NAME\"),
    object: nil,
    deliverImmediately: true
)
"

result=""
for _ in $(seq 1 120); do
  sleep 0.1
  result="$(
    /usr/bin/log show \
      --style compact \
      --start "$started_at" \
      --predicate "subsystem == \"rohoswagger.gojo.dictation-e2e\" AND category == \"$LOG_CATEGORY\"" \
      | tail -1
  )"
  if grep -q 'result success=' <<<"$result"; then
    echo "$result"
    grep -q 'result success=true' <<<"$result"
    grep -q 'holdStarted=true holdStopped=true' <<<"$result"
    grep -q 'tapStarted=true tapStopped=true' <<<"$result"
    exit 0
  fi
done

echo "Timed out waiting for the event-tap shortcut probe." >&2
[[ -n "$result" ]] && echo "$result" >&2
exit 1
