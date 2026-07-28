#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"
REFERENCE="Gojo local microphone dictation works."
FIXTURE_DIR=""
FIXTURE_PID=""
FOCUS_KEEPER_PID=""
OLD_VOLUME=""
DICTATION_ACTIVE=false

cleanup() {
  if [[ "$DICTATION_ACTIVE" == true ]]; then
    post_dictation_control up "$FIXTURE_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$OLD_VOLUME" ]]; then
    osascript -e "set volume output volume $OLD_VOLUME" >/dev/null 2>&1 || true
  fi
  if [[ -n "$FOCUS_KEEPER_PID" ]] && kill -0 "$FOCUS_KEEPER_PID" 2>/dev/null; then
    kill "$FOCUS_KEEPER_PID" 2>/dev/null || true
    wait "$FOCUS_KEEPER_PID" 2>/dev/null || true
  fi
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

skip() {
  echo "dictation-real-microphone-live-e2e-skip: $*" >&2
  exit 77
}

post_dictation_control() {
  local direction="$1"
  local expected_pid="${2:-}"
  swift - "$direction" "$expected_pid" <<'SWIFT'
import Foundation

guard CommandLine.arguments.count == 3 else { exit(2) }

switch CommandLine.arguments[1] {
case "down", "up":
    var userInfo: [String: Any] = ["action": CommandLine.arguments[1]]
    if let expectedPID = Int32(CommandLine.arguments[2]), expectedPID > 0 {
        userInfo["expectedPID"] = NSNumber(value: expectedPID)
    }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("rohoswagger.gojo.dictation-real-microphone-shortcut-e2e"),
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
    )
default:
    exit(2)
}
SWIFT
}

focus_native_fixture() {
  swift - <<'SWIFT'
import AppKit
import CoreGraphics
import Darwin

let owner = "GojoDictationFixture"
guard let application = NSWorkspace.shared.runningApplications.first(where: {
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
SWIFT
}

keep_native_fixture_focused() {
  local expected_pid="$1"
  swift - "$expected_pid" <<'SWIFT' &
import AppKit
import CoreGraphics
import Darwin

guard CommandLine.arguments.count == 2,
      let pid = Int32(CommandLine.arguments[1]),
      let application = NSRunningApplication(processIdentifier: pid) else {
    exit(2)
}

for _ in 0..<2_000 {
    if application.isTerminated {
        exit(0)
    }
    application.activate(options: [.activateAllWindows])
    usleep(10_000)
}
SWIFT
  FOCUS_KEEPER_PID=$!
}

latest_pipeline_log() {
  /usr/bin/log show \
    --style compact \
    --start "$started_at" \
    --predicate 'subsystem == "rohoswagger.gojo.dictation" AND category == "pipeline"' \
    | tail -1
}

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi

command -v say >/dev/null || skip "macOS say is unavailable"

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

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-dictation-real-mic-e2e.XXXXXX")"
fixture_app="$FIXTURE_DIR/GojoDictationFixture.app"
fixture_binary="$fixture_app/Contents/MacOS/GojoDictationFixture"
fixture_ready="$FIXTURE_DIR/ready"
fixture_text="$FIXTURE_DIR/text"
fixture_log="$FIXTURE_DIR/fixture.log"
mkdir -p "$fixture_app/Contents/MacOS"
swiftc -parse-as-library "$ROOT/tests/dictation_e2e_fixture.swift" -o "$fixture_binary"
plutil -create xml1 "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleExecutable -string GojoDictationFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string rohoswagger.gojo.DictationRealMicrophoneFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleName -string GojoDictationFixture "$fixture_app/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.0 "$fixture_app/Contents/Info.plist"

open -n "$fixture_app" --stdout "$fixture_log" --stderr "$fixture_log" --args \
  "$fixture_ready" "$fixture_text" "rohoswagger.gojo.dictation-real-microphone-unused"
for _ in $(seq 1 1200); do
  [[ -f "$fixture_ready" ]] && break
  sleep 0.05
done
if [[ ! -f "$fixture_ready" ]]; then
  cat "$fixture_log" >&2
  echo "Timed out waiting for the native dictation fixture." >&2
  exit 1
fi
FIXTURE_PID="$(tr -d '[:space:]' < "$fixture_ready")"
if [[ ! "$FIXTURE_PID" =~ ^[0-9]+$ ]] || ! kill -0 "$FIXTURE_PID" 2>/dev/null; then
  cat "$fixture_log" >&2
  echo "The native dictation fixture stopped before the test started." >&2
  exit 1
fi

focus_native_fixture
keep_native_fixture_focused "$FIXTURE_PID"
sleep 0.6

OLD_VOLUME="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null || true)"
osascript -e 'set volume output volume 70' >/dev/null 2>&1 || true

post_dictation_control down "$FIXTURE_PID"
DICTATION_ACTIVE=true

listening=false
for _ in $(seq 1 80); do
  if /usr/bin/log show \
      --style compact \
      --start "$started_at" \
      --predicate 'subsystem == "rohoswagger.gojo.dictation" AND category == "latency"' \
      | grep -q 'stage=listeningPublished'; then
    listening=true
    break
  fi
  pipeline="$(latest_pipeline_log || true)"
  if grep -q 'Download a voice model' <<<"$pipeline"; then
    skip "no local voice model is installed"
  fi
  sleep 0.1
done
if [[ "$listening" != true ]]; then
  pipeline="$(latest_pipeline_log || true)"
  if grep -q 'Download a voice model' <<<"$pipeline"; then
    skip "no local voice model is installed"
  fi
  echo "Gojo did not start listening after Control and Option." >&2
  [[ -n "$pipeline" ]] && echo "$pipeline" >&2
  exit 1
fi

say -r 160 "$REFERENCE"
sleep 0.25

post_dictation_control up "$FIXTURE_PID"
DICTATION_ACTIVE=false

audio_log=""
for _ in $(seq 1 120); do
  audio_log="$(
    /usr/bin/log show \
      --style compact \
      --start "$started_at" \
      --predicate 'subsystem == "rohoswagger.gojo.dictation" AND category == "pipeline" AND eventMessage CONTAINS "audioCaptured"' \
      | tail -1
  )"
  [[ -n "$audio_log" ]] && break
  sleep 0.25
done
if [[ -z "$audio_log" ]]; then
  echo "Timed out waiting for the microphone capture summary." >&2
  exit 1
fi

peak="$(python3 - "$audio_log" <<'PY'
import re
import sys
match = re.search(r"peak=([0-9.eE+-]+)", sys.argv[1])
print(match.group(1) if match else "")
PY
)"
duration="$(python3 - "$audio_log" <<'PY'
import re
import sys
match = re.search(r"duration=([0-9.eE+-]+)", sys.argv[1])
print(match.group(1) if match else "")
PY
)"
if [[ -z "$peak" || -z "$duration" ]]; then
  echo "Could not parse microphone capture summary." >&2
  echo "$audio_log" >&2
  exit 1
fi
python3 - "$peak" "$duration" <<'PY' || skip "microphone did not capture an audible signal"
import sys
peak = float(sys.argv[1])
duration = float(sys.argv[2])
raise SystemExit(0 if peak >= 0.01 and duration >= 0.5 else 1)
PY

final_pipeline=""
for _ in $(seq 1 180); do
  final_pipeline="$(latest_pipeline_log || true)"
  if grep -q 'state=succeeded' <<<"$final_pipeline"; then
    break
  fi
  if grep -q 'state=error' <<<"$final_pipeline"; then
    echo "$audio_log" >&2
    echo "$final_pipeline" >&2
    exit 1
  fi
  sleep 0.5
done
if ! grep -q 'state=succeeded' <<<"$final_pipeline"; then
  echo "Timed out waiting for dictation to finish." >&2
  echo "$audio_log" >&2
  [[ -n "$final_pipeline" ]] && echo "$final_pipeline" >&2
  exit 1
fi

for _ in $(seq 1 40); do
  if [[ -f "$fixture_text" ]] && python3 - "$fixture_text" "$REFERENCE" <<'PY'
import re
import sys
from pathlib import Path

actual = Path(sys.argv[1]).read_text()
reference = sys.argv[2]
normalize = lambda value: re.findall(r"[\w]+", value.casefold(), flags=re.UNICODE)
actual_words = normalize(actual)
reference_words = normalize(reference)
required_anchor = ["local", "microphone", "dictation"]

def edit_distance(lhs: list[str], rhs: list[str]) -> int:
    previous = list(range(len(rhs) + 1))
    for left_index, left_word in enumerate(lhs, start=1):
        current = [left_index]
        for right_index, right_word in enumerate(rhs, start=1):
            current.append(min(
                current[-1] + 1,
                previous[right_index] + 1,
                previous[right_index - 1] + (left_word != right_word),
            ))
        previous = current
    return previous[-1]

candidate = actual_words[:len(reference_words)]
maximum_errors = max(1, int(len(reference_words) * 0.4))
within_error_budget = (
    len(candidate) >= max(3, len(reference_words) - maximum_errors)
    and edit_distance(candidate, reference_words) <= maximum_errors
)
contains_anchor = any(
    actual_words[index:index + len(required_anchor)] == required_anchor
    for index in range(len(actual_words) - len(required_anchor) + 1)
)
recognizable = within_error_budget or contains_anchor
raise SystemExit(0 if recognizable else 1)
PY
  then
    echo "$audio_log"
    echo "$final_pipeline"
    echo "dictation-real-microphone-live-e2e-pass"
    exit 0
  fi
  sleep 0.25
done

echo "Gojo succeeded, but the fixture did not contain a recognizable microphone transcript." >&2
echo "$audio_log" >&2
echo "$final_pipeline" >&2
[[ -f "$fixture_text" ]] && sed -n '1,10p' "$fixture_text" >&2
exit 1
