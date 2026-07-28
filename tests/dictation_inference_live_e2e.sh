#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"

cleanup() {
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

swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("rohoswagger.gojo.dictation-inference-e2e-probe"), object: nil, deliverImmediately: true)'

for _ in $(seq 1 180); do
  result="$(/usr/bin/log show --style compact --start "$started_at" --predicate 'subsystem == "rohoswagger.gojo.dictation-e2e" AND category == "inference"' | tail -1)"
  if grep -q 'result success=' <<<"$result"; then
    echo "$result"
    grep -q 'success=true referenceMatch=true' <<<"$result"
    exit
  fi
  sleep 1
done

echo "Timed out waiting for local model inference." >&2
exit 1
