#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"

FIXTURE_DIR=""
FIXTURE_PID=""
CLIPBOARD_FILE=""
EXPECTED_TEXT='abcdefghijklmnopqrs👨‍👩‍👧‍👦tail'
SENTINEL="gojo-unicode-typing-clipboard-sentinel"

cleanup() {
  if [[ -n "$FIXTURE_PID" ]] && kill -0 "$FIXTURE_PID" 2>/dev/null; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  if [[ -n "$CLIPBOARD_FILE" && -f "$CLIPBOARD_FILE" ]]; then
    pbcopy < "$CLIPBOARD_FILE" || true
  fi
  if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
  release_dictation_live_lock
}
trap cleanup EXIT INT TERM

cd "$ROOT"
acquire_dictation_live_lock

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-unicode-typing-e2e.XXXXXX")"
CLIPBOARD_FILE="$FIXTURE_DIR/clipboard.txt"
pbpaste > "$CLIPBOARD_FILE" || : > "$CLIPBOARD_FILE"
printf '%s' "$SENTINEL" | pbcopy

fixture_app="$FIXTURE_DIR/GojoUnicodeTypingFixture.app"
fixture_binary="$fixture_app/Contents/MacOS/GojoUnicodeTypingFixture"
fixture_ready="$FIXTURE_DIR/ready"
fixture_text="$FIXTURE_DIR/text"
fixture_log="$FIXTURE_DIR/fixture.log"

mkdir -p "$fixture_app/Contents/MacOS"
swiftc \
  -parse-as-library \
  "$ROOT/tests/dictation_unicode_text_fixture.swift" \
  -o "$fixture_binary"
plutil -create xml1 "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string GojoUnicodeTypingFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string rohoswagger.gojo.UnicodeTypingE2EFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleName -string GojoUnicodeTypingFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$fixture_app/Contents/Info.plist"

make -C "$ROOT" stop >/dev/null
open -g "$APP"
sleep 3

open -n "$fixture_app" --stdout "$fixture_log" --stderr "$fixture_log" --args \
  "$fixture_ready" "$fixture_text"

for _ in $(seq 1 1200); do
  [[ -f "$fixture_ready" ]] && break
  sleep 0.05
done
if [[ ! -f "$fixture_ready" ]]; then
  cat "$fixture_log" >&2
  echo "Timed out waiting for the Unicode typing fixture." >&2
  exit 1
fi

FIXTURE_PID="$(tr -d '[:space:]' < "$fixture_ready")"
if [[ ! "$FIXTURE_PID" =~ ^[0-9]+$ ]] || ! kill -0 "$FIXTURE_PID" 2>/dev/null; then
  cat "$fixture_log" >&2
  echo "The Unicode typing fixture stopped before the probe started." >&2
  exit 1
fi

started_at="$(date '+%Y-%m-%d %H:%M:%S')"
swift - "$FIXTURE_PID" "$EXPECTED_TEXT" <<'SWIFT'
import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2,
      let expectedPID = Int32(arguments[0]),
      let application = NSRunningApplication(processIdentifier: expectedPID) else {
    exit(2)
}

application.activate(options: [.activateAllWindows])
usleep(300_000)
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID else {
    exit(3)
}

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("rohoswagger.gojo.dictation-unicode-typing-e2e-probe"),
    object: nil,
    userInfo: [
        "expectedPID": NSNumber(value: expectedPID),
        "transcript": arguments[1],
    ],
    deliverImmediately: true
)
SWIFT

result=""
for _ in $(seq 1 30); do
  sleep 1
  result="$(/usr/bin/log show --style compact --start "$started_at" --predicate 'subsystem == "rohoswagger.gojo.dictation-e2e" AND category == "unicode-typing"' | grep 'result success=' | tail -1 || true)"
  [[ -n "$result" ]] && break
done
if [[ -z "$result" ]]; then
  cat "$fixture_log" >&2
  echo "Timed out waiting for Gojo's Unicode typing result." >&2
  exit 1
fi

echo "$result"
grep -q 'success=true' <<<"$result"
grep -q 'method=application-unicode' <<<"$result"
grep -q 'partialInsertion=false' <<<"$result"

for _ in $(seq 1 100); do
  if [[ -f "$fixture_text" ]] && grep -Fqx "$EXPECTED_TEXT" "$fixture_text"; then
    break
  fi
  sleep 0.05
done
if ! [[ -f "$fixture_text" ]] || ! grep -Fqx "$EXPECTED_TEXT" "$fixture_text"; then
  cat "$fixture_log" >&2
  echo "Unicode typing did not deliver the exact expected string." >&2
  if [[ -f "$fixture_text" ]]; then
    python3 - "$fixture_text" "$EXPECTED_TEXT" <<'PY' >&2
from pathlib import Path
import sys
actual = Path(sys.argv[1]).read_text()
expected = sys.argv[2]
print("actual repr:", repr(actual))
print("expected repr:", repr(expected))
PY
  fi
  exit 1
fi

if [[ "$(pbpaste)" != "$SENTINEL" ]]; then
  echo "Unicode typing unexpectedly changed the clipboard." >&2
  exit 1
fi

echo "dictation-unicode-typing-live-e2e-pass"
