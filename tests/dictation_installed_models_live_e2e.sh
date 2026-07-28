#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/DerivedData/Build/Products/Debug/Gojo.app"
source "$ROOT/tests/dictation_live_lock.sh"
DOMAIN="rohoswagger.gojo"
MODEL_KEY="gojo.dictation.selectedModelID"
ORIGINAL_MODEL=""
ORIGINAL_MODEL_WAS_SET=false

MODELS=(
  "fluidaudio:parakeet-unified-en-0.6b"
  "fluidaudio:parakeet-tdt-0.6b-v3"
  "whisperkit:small.en_217MB"
  "whisperkit:large-v3-v20240930_626MB"
)

restore_selection() {
  make -C "$ROOT" stop >/dev/null 2>&1 || true
  if [[ "$ORIGINAL_MODEL_WAS_SET" == true ]]; then
    defaults write "$DOMAIN" "$MODEL_KEY" -string "$ORIGINAL_MODEL"
  else
    defaults delete "$DOMAIN" "$MODEL_KEY" >/dev/null 2>&1 || true
  fi
  if [[ -d "$APP" ]]; then
    open -g "$APP"
  fi
  release_dictation_live_lock
}
trap restore_selection EXIT INT TERM

if [[ ! -d "$APP" ]]; then
  echo "Build the Debug app first with: make build" >&2
  exit 2
fi
acquire_dictation_live_lock

if ORIGINAL_MODEL="$(defaults read "$DOMAIN" "$MODEL_KEY" 2>/dev/null)"; then
  ORIGINAL_MODEL_WAS_SET=true
fi

wait_for_shortcut_monitor() {
  local started_at="$1"
  for _ in $(seq 1 600); do
    if /usr/bin/log show \
        --style compact \
        --start "$started_at" \
        --predicate 'subsystem == "rohoswagger.gojo.dictation" AND category == "shortcut"' \
        | grep -q 'monitor started chord=control+option'; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_inference_result() {
  local started_at="$1"
  local model="$2"
  local result=""
  for _ in $(seq 1 1200); do
    result="$(
      /usr/bin/log show \
        --style compact \
        --start "$started_at" \
        --predicate 'subsystem == "rohoswagger.gojo.dictation-e2e" AND category == "inference"' \
        | grep -F "model=$model" \
        | tail -1 \
        || true
    )"
    if grep -q 'result success=' <<<"$result"; then
      printf '%s\n' "$result"
      return 0
    fi
    sleep 0.2
  done
  return 1
}

passed=0
not_installed=0

for model in "${MODELS[@]}"; do
  make -C "$ROOT" stop >/dev/null
  defaults write "$DOMAIN" "$MODEL_KEY" -string "$model"
  started_at="$(date '+%Y-%m-%d %H:%M:%S')"
  open -g "$APP"

  if ! wait_for_shortcut_monitor "$started_at"; then
    echo "Model matrix failed to launch Gojo for $model." >&2
    exit 1
  fi

  swift -e '
    import Foundation
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("rohoswagger.gojo.dictation-inference-e2e-probe"),
      object: nil,
      deliverImmediately: true
    )
  '

  if ! result="$(wait_for_inference_result "$started_at" "$model")"; then
    echo "Timed out waiting for inference result for $model." >&2
    exit 1
  fi

  if grep -q 'success=true referenceMatch=true' <<<"$result"; then
    echo "model-pass $model"
    echo "$result"
    passed=$((passed + 1))
    continue
  fi

  if grep -Fq 'Download a voice model in Gojo Settings first.' <<<"$result"; then
    echo "model-not-installed $model"
    not_installed=$((not_installed + 1))
    continue
  fi

  echo "Unexpected inference failure for $model:" >&2
  echo "$result" >&2
  exit 1
done

echo "dictation-installed-models-live-e2e-pass passed=$passed notInstalled=$not_installed"
