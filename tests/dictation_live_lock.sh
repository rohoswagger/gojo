#!/usr/bin/env bash

DICTATION_LIVE_LOCK_FILE="${TMPDIR:-/tmp}/gojo-dictation-live-e2e.lock"

if [[ "${GOJO_DICTATION_LIVE_LOCK_HELD:-0}" != "1" ]]; then
  if env GOJO_DICTATION_LIVE_LOCK_HELD=1 \
      /usr/bin/lockf -t 300 "$DICTATION_LIVE_LOCK_FILE" /usr/bin/env bash "$0" "$@"; then
    exit 0
  else
    status=$?
    if [[ "$status" -eq 75 ]]; then
      echo "Timed out waiting for another dictation live E2E test to finish." >&2
    fi
    exit "$status"
  fi
fi

acquire_dictation_live_lock() { :; }
release_dictation_live_lock() { :; }
