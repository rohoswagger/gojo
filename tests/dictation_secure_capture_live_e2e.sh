#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"

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

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-dictation-secure-capture.XXXXXX")"
fixture_app="$FIXTURE_DIR/GojoSecureDictationCaptureFixture.app"
fixture_binary="$fixture_app/Contents/MacOS/GojoSecureDictationCaptureFixture"
fixture_ready="$FIXTURE_DIR/ready"
fixture_text="$FIXTURE_DIR/text"
fixture_log="$FIXTURE_DIR/fixture.log"
mkdir -p "$fixture_app/Contents/MacOS"
swiftc -parse-as-library "$ROOT/tests/dictation_capture_live_fixture.swift" -o "$fixture_binary"
plutil -create xml1 "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string GojoSecureDictationCaptureFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string rohoswagger.gojo.DictationSecureCaptureFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleName -string GojoSecureDictationCaptureFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$fixture_app/Contents/Info.plist"

open -n "$fixture_app" --stdout "$fixture_log" --stderr "$fixture_log" --args \
  "$fixture_ready" "$fixture_text" secure

for _ in $(seq 1 1200); do
  if [[ -f "$fixture_ready" ]]; then
    break
  fi
  sleep 0.05
done

if [[ ! -f "$fixture_ready" ]]; then
  cat "$fixture_log" >&2
  echo "Timed out waiting for the secure capture fixture." >&2
  exit 1
fi

FIXTURE_PID="$(awk -F= '$1 == "pid" { print $2 }' "$fixture_ready" | tr -d '[:space:]')"
if [[ ! "$FIXTURE_PID" =~ ^[0-9]+$ ]] || ! kill -0 "$FIXTURE_PID" 2>/dev/null; then
  cat "$fixture_log" >&2
  echo "The secure capture fixture stopped before the probe started." >&2
  exit 1
fi

swift - "$FIXTURE_PID" <<'SWIFT'
import Foundation

guard CommandLine.arguments.count == 2,
      let pid = Int32(CommandLine.arguments[1]) else {
    exit(2)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("rohoswagger.gojo.dictation-capture-e2e-probe"),
    object: nil,
    userInfo: ["expectedPID": NSNumber(value: pid)],
    deliverImmediately: true
)
SWIFT

result=""
for _ in $(seq 1 120); do
  sleep 0.1
  result="$(
    /usr/bin/log show \
      --style compact \
      --start "$started_at" \
      --predicate 'subsystem == "rohoswagger.gojo.dictation-e2e" AND category == "capture"' \
      | tail -1
  )"
  if grep -q 'result success=' <<<"$result"; then
    echo "$result"
    grep -q 'success=false' <<<"$result"
    grep -q 'error=secureTextTarget' <<<"$result"
    sleep 0.5
    if [[ "$(cat "$fixture_text")" != "not changed" ]]; then
      echo "Secure fixture text changed unexpectedly." >&2
      cat "$fixture_text" >&2
      exit 1
    fi
    echo "dictation-secure-capture-live-e2e-pass"
    exit 0
  fi
done

echo "Timed out waiting for secure capture probe." >&2
[[ -n "$result" ]] && echo "$result" >&2
exit 1
