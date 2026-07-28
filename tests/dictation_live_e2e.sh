#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"
TARGET_KIND="${1:-native}"
PROBE_KIND="${2:-insertion}"
FIXTURE_DIR=""
FIXTURE_PID=""

case "$PROBE_KIND" in
  insertion)
    log_category="insertion"
    expected_text="Gojo local dictation end to end."
    attempts=30
    notification_name="rohoswagger.gojo.dictation-e2e-probe"
    ;;
  model)
    log_category="model"
    expected_text="Gojo local dictation should type this sentence into the focused text field."
    attempts=180
    notification_name="rohoswagger.gojo.dictation-model-e2e-probe"
    ;;
  *)
    echo "Usage: $0 [native|browser] [insertion|model]" >&2
    exit 2
    ;;
esac

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

focus_native_fixture_and_post() {
  local notification="$1"
  local probe_kind="$2"
  swift - "$notification" "$probe_kind" <<'SWIFT'
import AppKit
import CoreGraphics
import Darwin

let owner = "GojoDictationFixture"
guard CommandLine.arguments.count == 3,
      let application = NSWorkspace.shared.runningApplications.first(where: {
          $0.localizedName == owner
      }) else {
    exit(4)
}
application.activate(options: [.activateAllWindows])
usleep(200_000)

let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []
let ownerWindows = windows.compactMap { window -> (window: [String: Any], area: Double)? in
    guard (window[kCGWindowOwnerName as String] as? String) == owner,
          ((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = (bounds["Width"] as? NSNumber)?.doubleValue,
          let height = (bounds["Height"] as? NSNumber)?.doubleValue,
          width >= 200,
          height >= 150 else {
        return nil
    }
    return (window, width * height)
}
guard let window = ownerWindows.max(by: { $0.area < $1.area })?.window,
      let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
      let x = (rawBounds["X"] as? NSNumber)?.doubleValue,
      let y = (rawBounds["Y"] as? NSNumber)?.doubleValue,
      let width = (rawBounds["Width"] as? NSNumber)?.doubleValue else {
    exit(3)
}

let point = CGPoint(x: x + width / 2, y: y + 140)
let down = CGEvent(
    mouseEventSource: nil,
    mouseType: .leftMouseDown,
    mouseCursorPosition: point,
    mouseButton: .left
)!
let up = CGEvent(
    mouseEventSource: nil,
    mouseType: .leftMouseUp,
    mouseCursorPosition: point,
    mouseButton: .left
)!
down.post(tap: .cghidEventTap)
usleep(50_000)
up.post(tap: .cghidEventTap)
usleep(100_000)

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(CommandLine.arguments[1]),
    object: nil,
    userInfo: ["expectedPID": NSNumber(value: application.processIdentifier)],
    deliverImmediately: true
)

let iterations = CommandLine.arguments[2] == "model" ? 500 : 180
for _ in 0..<iterations {
    application.activate(options: [.activateAllWindows])
    down.post(tap: .cghidEventTap)
    usleep(2_000)
    up.post(tap: .cghidEventTap)
    usleep(8_000)
}
SWIFT
}

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi
acquire_dictation_live_lock
# Always exercise the just-built binary rather than a process that may still
# have the same path but an older image mapped in memory.
make -C "$ROOT" stop >/dev/null
open -g "$APP"
sleep 3
started_at="$(date '+%Y-%m-%d %H:%M:%S')"

case "$TARGET_KIND" in
  native)
    FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-dictation-e2e.XXXXXX")"
    fixture_app="$FIXTURE_DIR/GojoDictationFixture.app"
    fixture_binary="$fixture_app/Contents/MacOS/GojoDictationFixture"
    fixture_ready="$FIXTURE_DIR/ready"
    fixture_text="$FIXTURE_DIR/text"
    fixture_log="$FIXTURE_DIR/fixture.log"
    mkdir -p "$fixture_app/Contents/MacOS"
    swiftc -parse-as-library "$ROOT/tests/dictation_e2e_fixture.swift" -o "$fixture_binary"
    plutil -create xml1 "$fixture_app/Contents/Info.plist"
    plutil -insert CFBundleExecutable -string GojoDictationFixture "$fixture_app/Contents/Info.plist"
    plutil -insert CFBundleIdentifier -string rohoswagger.gojo.DictationE2EFixture "$fixture_app/Contents/Info.plist"
    plutil -insert CFBundleName -string GojoDictationFixture "$fixture_app/Contents/Info.plist"
    plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
    plutil -insert CFBundleShortVersionString -string 1.0 "$fixture_app/Contents/Info.plist"
    echo "fixture_app=$fixture_app"
    open -n "$fixture_app" --stdout "$fixture_log" --stderr "$fixture_log" --args \
      "$fixture_ready" "$fixture_text" "$notification_name"

    for _ in $(seq 1 1200); do
      if [[ -f "$fixture_ready" ]]; then
        break
      fi
      sleep 0.05
    done
    if [[ ! -f "$fixture_ready" ]]; then
      FIXTURE_PID="$(pgrep -f "$fixture_binary" | head -1 || true)"
      cat "$fixture_log" >&2
      echo "Timed out waiting for the native dictation fixture." >&2
      exit 1
    fi
    FIXTURE_PID="$(tr -d '[:space:]' < "$fixture_ready")"
    if [[ ! "$FIXTURE_PID" =~ ^[0-9]+$ ]] || ! kill -0 "$FIXTURE_PID" 2>/dev/null; then
      cat "$fixture_log" >&2
      echo "The native dictation fixture stopped before the probe started." >&2
      exit 1
    fi
    focus_native_fixture_and_post "$notification_name" "$PROBE_KIND"
    ;;
  browser)
    open -a Safari "$ROOT/tests/fixtures/dictation-e2e.html"
    focus_owner="Safari"
    ;;
  *)
    echo "Usage: $0 [native|browser] [insertion|model]" >&2
    exit 2
    ;;
esac

if [[ "$TARGET_KIND" == "browser" ]]; then
  sleep 2
  swift "$ROOT/tests/dictation_e2e_focus.swift" Safari
  sleep 1
fi

if [[ "$TARGET_KIND" == "browser" ]]; then
  swift -e "import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name(\"$notification_name\"), object: nil, deliverImmediately: true)"
fi

for _ in $(seq 1 "$attempts"); do
  sleep 1
  result="$(/usr/bin/log show --style compact --start "$started_at" --predicate "subsystem == \"rohoswagger.gojo.dictation-e2e\" AND category == \"$log_category\"" | tail -1)"
  if grep -q 'result success=' <<<"$result"; then
    if [[ "$TARGET_KIND" == "native" ]]; then
      if [[ "$PROBE_KIND" == "model" ]]; then
        required_result='success=true'
      else
        required_result='success=true'
      fi
      if ! grep -q "$required_result" <<<"$result"; then
        echo "$result" >&2
        exit 1
      fi
      if [[ "$PROBE_KIND" == "model" ]] && ! grep -q 'referenceMatch=true' <<<"$result"; then
        echo "$result" >&2
        exit 1
      fi
      echo "$result"
      for _ in $(seq 1 20); do
        if [[ -f "$fixture_text" ]]; then
          if [[ "$PROBE_KIND" == "insertion" ]] && grep -Fq "$expected_text" "$fixture_text"; then
            exit 0
          fi
          if [[ "$PROBE_KIND" == "model" ]] && python3 - "$fixture_text" "$expected_text" <<'PY'
import re
import sys
from pathlib import Path

normalize = lambda value: re.findall(r"[\w]+", value.casefold(), flags=re.UNICODE)
actual = Path(sys.argv[1]).read_text()
expected = normalize(sys.argv[2])
raise SystemExit(0 if normalize(actual)[:len(expected)] == expected else 1)
PY
          then
            exit 0
          fi
        fi
        sleep 0.05
      done
      echo "The helper reported success, but the native fixture did not contain the expected text." >&2
      [[ -f "$fixture_text" ]] && sed -n '1,10p' "$fixture_text" >&2
      exit 1
    fi
    echo "$result"
    if [[ "$PROBE_KIND" == "model" ]]; then
      grep -q 'success=true verified=true referenceMatch=true' <<<"$result"
    else
      grep -q 'success=true verified=true' <<<"$result"
    fi
    exit
  fi
done

echo "Timed out waiting for the $PROBE_KIND probe." >&2
if [[ -n "${result:-}" ]]; then
  echo "$result" >&2
fi
exit 1
