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
  if [[ -n "$CLIPBOARD_FILE" && -f "$CLIPBOARD_FILE" ]]; then
    clipboard_state restore "$CLIPBOARD_FILE" || status=1
  fi
  if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
  release_dictation_live_lock
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$ROOT"
acquire_dictation_live_lock

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi

FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gojo-unicode-typing-e2e.XXXXXX")"
CLIPBOARD_FILE="$FIXTURE_DIR/clipboard.plist"
clipboard_state save "$CLIPBOARD_FILE"
printf '%s' "$SENTINEL" | pbcopy
clipboard_state save "$FIXTURE_DIR/sentinel.plist"

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
open -g --env GOJO_LICENSE=lifetime "$APP"
sleep 3

open -n --env GOJO_LICENSE=lifetime "$fixture_app" --stdout "$fixture_log" --stderr "$fixture_log" --args \
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
  if [[ -f "$fixture_text" ]] && cmp -s "$fixture_text" <(printf '%s' "$EXPECTED_TEXT"); then
    break
  fi
  sleep 0.05
done
if ! [[ -f "$fixture_text" ]] || ! cmp -s "$fixture_text" <(printf '%s' "$EXPECTED_TEXT"); then
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

clipboard_state check "$FIXTURE_DIR/sentinel.plist"

echo "dictation-unicode-typing-live-e2e-pass"
