#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"
FIXTURE_DIR=""
FIXTURE_PID=""
CLIPBOARD_DIR=""
CLIPBOARD_FILE=""
SENTINEL="gojo-opaque-paste-clipboard-sentinel"
STABLE_TEXT="Gojo opaque paste reached the target."
ACTIVE_CURSOR_TEXT="Gojo pasted at the active cursor."

clipboard_state() {
  swift - "$1" "$2" <<'SWIFT'
import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let url = URL(fileURLWithPath: arguments[1])
let pasteboard = NSPasteboard.general

func snapshot() throws -> [[String: Data]] {
    try (pasteboard.pasteboardItems ?? []).map { item in
        var dataByType: [String: Data] = [:]
        for type in item.types {
            guard let data = item.data(forType: type) else {
                throw NSError(domain: "ClipboardSnapshot", code: 1)
            }
            dataByType[type.rawValue] = data
        }
        return dataByType
    }
}

do {
    if arguments[0] == "save" {
        let data = try PropertyListSerialization.data(
            fromPropertyList: snapshot(), format: .binary, options: 0
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } else {
        let data = try Data(contentsOf: url)
        guard let saved = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [[String: Data]] else {
            throw NSError(domain: "ClipboardSnapshot", code: 2)
        }
        if arguments[0] == "restore" {
            let items = saved.map { dataByType in
                let item = NSPasteboardItem()
                for (type, data) in dataByType {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
                return item
            }
            pasteboard.clearContents()
            guard items.isEmpty || pasteboard.writeObjects(items) else {
                throw NSError(domain: "ClipboardSnapshot", code: 3)
            }
        }
        let current = try snapshot()
        guard current == saved else {
            FileHandle.standardError.write(Data(
                "Clipboard item data changed (before=\(saved.count) items, after=\(current.count) items).\n".utf8
            ))
            for index in 0..<max(saved.count, current.count) {
                let before = saved.indices.contains(index) ? saved[index] : [:]
                let after = current.indices.contains(index) ? current[index] : [:]
                for type in Set(before.keys).union(after.keys).sorted() where before[type] != after[type] {
                    FileHandle.standardError.write(Data("Changed clipboard type: \(type)\n".utf8))
                }
            }
            throw NSError(domain: "ClipboardSnapshot", code: 4)
        }
    }
} catch {
    FileHandle.standardError.write(Data("Could not preserve, verify, or restore all clipboard item types.\n".utf8))
    exit(1)
}
SWIFT
}

cleanup() {
  local status=$?
  if [[ -n "$FIXTURE_PID" ]] && kill -0 "$FIXTURE_PID" 2>/dev/null; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
  if [[ -n "$CLIPBOARD_FILE" && -f "$CLIPBOARD_FILE" ]]; then
    clipboard_state restore "$CLIPBOARD_FILE" || status=1
  fi
  if [[ -n "$CLIPBOARD_DIR" && -d "$CLIPBOARD_DIR" ]]; then
    rm -rf "$CLIPBOARD_DIR"
  fi
  release_dictation_live_lock
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi
acquire_dictation_live_lock
CLIPBOARD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-opaque-clipboard.XXXXXX")"
CLIPBOARD_FILE="$CLIPBOARD_DIR/clipboard.plist"
clipboard_state save "$CLIPBOARD_FILE"

make -C "$ROOT" stop >/dev/null
open -g --env GOJO_LICENSE=lifetime "$APP"
sleep 3

wait_for_result() {
  local started_at="$1"
  local scenario="$2"
  local attempts="$3"
  local result=""
  for _ in $(seq 1 "$attempts"); do
    sleep 1
    result="$(/usr/bin/log show --style compact --start "$started_at" --predicate 'subsystem == "rohoswagger.gojo.dictation-e2e" AND category == "opaque-paste"' | grep "scenario=$scenario" | tail -1 || true)"
    if grep -q 'result success=' <<<"$result"; then
      echo "$result"
      return 0
    fi
  done
  echo "Timed out waiting for opaque-paste $scenario result." >&2
  [[ -n "$result" ]] && echo "$result" >&2
  return 1
}

assert_insertion_clipboard() {
  local result="$1"
  local transcript="$2"
  grep -q 'verified=false' <<<"$result"
  grep -q 'clipboardRestored=false' <<<"$result"
  if grep -q 'method=application-unicode' <<<"$result"; then
    clipboard_state check "$CLIPBOARD_DIR/sentinel.plist"
  elif grep -q 'method=application-paste' <<<"$result"; then
    if [[ "$(pbpaste)" != "$transcript" ]]; then
      echo "Unverified opaque paste should leave the transcript on the clipboard." >&2
      return 1
    fi
  else
    echo "Opaque insertion did not use a guarded application method." >&2
    return 1
  fi
}

text_matches() {
  [[ -f "$1" ]] && cmp -s "$1" <(printf '%s' "$2")
}

focus_fixture_window() {
  local fixture_mode="${1:-stable}"
  osascript -e 'tell application "GojoOpaquePasteFixture" to activate' >/dev/null 2>&1 || true
  sleep 0.2
  swift - "$fixture_mode" "$SENTINEL" "$CLIPBOARD_DIR/sentinel.plist" <<'SWIFT'
import AppKit
import CoreGraphics
import Darwin

let owner = "GojoOpaquePasteFixture"
guard let application = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == owner
}) else {
    exit(4)
}
application.activate(options: [.activateAllWindows])
usleep(300_000)

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

let point = CGPoint(x: x + width / 2, y: y + 120)
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
usleep(100_000)
up.post(tap: .cghidEventTap)
usleep(300_000)
let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"
if frontmost != owner {
    FileHandle.standardError.write(Data("Expected \(owner) to be frontmost, got \(frontmost).\n".utf8))
    exit(5)
}
let arguments = Array(CommandLine.arguments.dropFirst())
let pasteboard = NSPasteboard.general
guard pasteboard.string(forType: .string) == arguments[1] else {
    FileHandle.standardError.write(Data("Clipboard changed before the opaque insertion probe.\n".utf8))
    exit(6)
}
let sentinelItems = try (pasteboard.pasteboardItems ?? []).map { item -> [String: Data] in
    var dataByType: [String: Data] = [:]
    for type in item.types {
        guard let data = item.data(forType: type) else {
            throw NSError(domain: "ClipboardSnapshot", code: 1)
        }
        dataByType[type.rawValue] = data
    }
    return dataByType
}
let sentinelData = try PropertyListSerialization.data(
    fromPropertyList: sentinelItems, format: .binary, options: 0
)
let sentinelURL = URL(fileURLWithPath: arguments[2])
try sentinelData.write(to: sentinelURL, options: .atomic)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sentinelURL.path)
let moveFocus = arguments[0] != "stable"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("rohoswagger.gojo.dictation-opaque-paste-e2e-probe"),
    object: nil,
    userInfo: [
        "moveFocusAfterCapture": NSNumber(value: moveFocus),
        "expectedPID": NSNumber(value: application.processIdentifier),
    ],
    deliverImmediately: true
)
SWIFT
}

launch_fixture() {
  local fixture_mode="${1:-stable}"
  FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-opaque-paste-e2e.XXXXXX")"
  local fixture_app="$FIXTURE_DIR/GojoOpaquePasteFixture.app"
  local fixture_binary="$fixture_app/Contents/MacOS/GojoOpaquePasteFixture"
  fixture_ready="$FIXTURE_DIR/ready"
  fixture_first_text="$FIXTURE_DIR/first-text"
  fixture_second_text="$FIXTURE_DIR/second-text"
  fixture_log="$FIXTURE_DIR/fixture.log"
  mkdir -p "$fixture_app/Contents/MacOS"
  swiftc -parse-as-library "$ROOT/tests/dictation_opaque_paste_fixture.swift" -o "$fixture_binary"
  plutil -create xml1 "$fixture_app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string GojoOpaquePasteFixture "$fixture_app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string rohoswagger.gojo.OpaquePasteE2EFixture "$fixture_app/Contents/Info.plist"
  plutil -insert CFBundleName -string GojoOpaquePasteFixture "$fixture_app/Contents/Info.plist"
  plutil -insert CFBundlePackageType -string APPL "$fixture_app/Contents/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$fixture_app/Contents/Info.plist"

  open -n --env GOJO_LICENSE=lifetime "$fixture_app" --stdout "$fixture_log" --stderr "$fixture_log" --args \
    "$fixture_ready" "$fixture_first_text" "$fixture_second_text" \
    "rohoswagger.gojo.dictation-opaque-paste-e2e-probe" "$fixture_mode"

  for _ in $(seq 1 1200); do
    [[ -f "$fixture_ready" ]] && break
    sleep 0.05
  done
  if [[ ! -f "$fixture_ready" ]]; then
    cat "$fixture_log" >&2
    echo "Timed out waiting for the opaque paste fixture." >&2
    exit 1
  fi
  FIXTURE_PID="$(tr -d '[:space:]' < "$fixture_ready")"
  if [[ ! "$FIXTURE_PID" =~ ^[0-9]+$ ]] || ! kill -0 "$FIXTURE_PID" 2>/dev/null; then
    cat "$fixture_log" >&2
    echo "The opaque paste fixture stopped before the probe started." >&2
    exit 1
  fi
  focus_fixture_window "$fixture_mode"
}

stop_fixture() {
  if [[ -n "$FIXTURE_PID" ]] && kill -0 "$FIXTURE_PID" 2>/dev/null; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
  FIXTURE_PID=""
  if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
  FIXTURE_DIR=""
}

printf '%s' "$SENTINEL" | pbcopy
stable_started_at="$(date '+%Y-%m-%d %H:%M:%S')"
launch_fixture stable
stable_result="$(wait_for_result "$stable_started_at" stable 30)"
echo "$stable_result"
grep -q 'success=true' <<<"$stable_result"
assert_insertion_clipboard "$stable_result" "$STABLE_TEXT"

for _ in $(seq 1 40); do
  if text_matches "$fixture_first_text" "$STABLE_TEXT"; then
    break
  fi
  sleep 0.05
done
if ! text_matches "$fixture_first_text" "$STABLE_TEXT"; then
  echo "Stable opaque paste did not reach the first field." >&2
  [[ -f "$fixture_log" ]] && cat "$fixture_log" >&2
  [[ -f "$fixture_first_text" ]] && sed -n '1,10p' "$fixture_first_text" >&2
  exit 1
fi
if [[ -s "$fixture_second_text" ]]; then
  echo "Stable opaque paste unexpectedly modified the second field." >&2
  sed -n '1,10p' "$fixture_second_text" >&2
  exit 1
fi
stop_fixture

printf '%s' "$SENTINEL" | pbcopy
focus_started_at="$(date '+%Y-%m-%d %H:%M:%S')"
launch_fixture same-window
focus_result="$(wait_for_result "$focus_started_at" focus-move 30)"
echo "$focus_result"
grep -q 'success=true' <<<"$focus_result"
assert_insertion_clipboard "$focus_result" "$ACTIVE_CURSOR_TEXT"

for _ in $(seq 1 40); do
  if text_matches "$fixture_second_text" "$ACTIVE_CURSOR_TEXT"; then
    break
  fi
  sleep 0.05
done
if [[ -s "$fixture_first_text" ]]; then
  echo "Same-window focus-move opaque paste modified the original field." >&2
  [[ -f "$fixture_log" ]] && cat "$fixture_log" >&2
  exit 1
fi
if ! text_matches "$fixture_second_text" "$ACTIVE_CURSOR_TEXT"; then
  echo "Same-window focus-move opaque paste did not reach the newly active second field." >&2
  [[ -f "$fixture_log" ]] && cat "$fixture_log" >&2
  [[ -f "$fixture_second_text" ]] && sed -n '1,10p' "$fixture_second_text" >&2
  exit 1
fi
stop_fixture

printf '%s' "$SENTINEL" | pbcopy
switch_started_at="$(date '+%Y-%m-%d %H:%M:%S')"
launch_fixture window-switch
switch_result="$(wait_for_result "$switch_started_at" focus-move 30)"
echo "$switch_result"
grep -q 'success=false' <<<"$switch_result"
grep -q 'error=focusChanged' <<<"$switch_result"

sleep 0.5
if [[ -s "$fixture_first_text" ]]; then
  echo "Window-switch opaque paste incorrectly modified the original field." >&2
  exit 1
fi
if [[ -s "$fixture_second_text" ]]; then
  echo "Window-switch opaque paste incorrectly modified another-window field." >&2
  exit 1
fi
clipboard_state check "$CLIPBOARD_DIR/sentinel.plist"

echo "dictation-opaque-paste-live-e2e-pass"
