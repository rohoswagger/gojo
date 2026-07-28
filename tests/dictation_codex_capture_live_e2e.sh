#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
CAPTURE_ATTEMPTS="${GOJO_CODEX_CAPTURE_ATTEMPTS:-10}"
source "$ROOT/tests/dictation_live_lock.sh"

cleanup() {
  release_dictation_live_lock
}
trap cleanup EXIT INT TERM

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi
if [[ ! "$CAPTURE_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || (( CAPTURE_ATTEMPTS > 100 )); then
  echo "GOJO_CODEX_CAPTURE_ATTEMPTS must be between 1 and 100." >&2
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

codex_status=0
codex_pid="$(swift - <<'SWIFT'
import AppKit
import Darwin
import Foundation

func skip(_ message: String) -> Never {
    fputs("dictation-codex-capture-live-e2e-skip: \(message)\n", stderr)
    exit(77)
}

guard let application = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.openai.codex" && !$0.isTerminated
}) else {
    skip("Codex is not running")
}

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
let hasVisibleWindow = windows.contains { window in
    guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
          ownerPID == application.processIdentifier,
          let layer = window[kCGWindowLayer as String] as? Int,
          layer == 0,
          let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsDict),
          bounds.width > 16,
          bounds.height > 16 else {
        return false
    }
    return true
}

guard hasVisibleWindow else {
    skip("Codex has no visible window")
}

application.activate(options: [.activateAllWindows])
usleep(500_000)
print(application.processIdentifier)
SWIFT
)" || codex_status=$?

if [[ "$codex_status" -eq 77 ]]; then
  exit 77
elif [[ "$codex_status" -ne 0 ]]; then
  echo "Failed to locate the running Codex window." >&2
  exit "$codex_status"
fi

swift - "$codex_pid" "$CAPTURE_ATTEMPTS" <<'SWIFT'
import Darwin
import Foundation

guard CommandLine.arguments.count == 3,
      let pid = Int32(CommandLine.arguments[1]),
      let attempts = Int(CommandLine.arguments[2]) else {
    exit(2)
}
for _ in 0..<attempts {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("rohoswagger.gojo.dictation-capture-e2e-probe"),
        object: nil,
        userInfo: ["expectedPID": NSNumber(value: pid)],
        deliverImmediately: true
    )
    usleep(500_000)
}
SWIFT

results=""
for _ in $(seq 1 160); do
  sleep 0.1
  results="$(
    /usr/bin/log show \
      --style compact \
      --start "$started_at" \
      --predicate 'subsystem == "rohoswagger.gojo.dictation-e2e" AND category == "capture"' \
      | grep 'result success=' \
      || true
  )"
  result_count="$(grep -c 'result success=' <<<"$results" || true)"
  if (( result_count >= CAPTURE_ATTEMPTS )); then
    results="$(tail -n "$CAPTURE_ATTEMPTS" <<<"$results")"
    echo "$results"
    python3 - "$codex_pid" "$CAPTURE_ATTEMPTS" "$results" <<'PY'
import re
import sys

pid = sys.argv[1]
attempts = int(sys.argv[2])
lines = sys.argv[3].splitlines()
assert len(lines) == attempts, lines
for line in lines:
    assert "success=true" in line, line
    assert "expectedMatch=true" in line, line
    assert f"pid={pid}" in line, line
    match = re.search(r"windowID=(\d+)", line)
    assert match and int(match.group(1)) > 0, line
PY
    echo "dictation-codex-capture-live-e2e-pass"
    exit 0
  fi
done

echo "Timed out waiting for Codex capture probe." >&2
[[ -n "$results" ]] && echo "$results" >&2
exit 1
