#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path

lock = Path("tests/dictation_live_lock.sh").read_text()
assert "/usr/bin/lockf -t 300" in lock
assert "GOJO_DICTATION_LIVE_LOCK_HELD=1" in lock
assert '/usr/bin/env bash "$0" "$@"' in lock
assert 'if [[ "$status" -eq 75 ]]' in lock
assert "rm -rf" not in lock
assert "release_dictation_live_lock()" in lock

scripts = [
    "tests/dictation_live_e2e.sh",
    "tests/dictation_event_tap_shortcut_live_e2e.sh",
    "tests/dictation_opaque_paste_live_e2e.sh",
    "tests/dictation_real_microphone_live_e2e.sh",
    "tests/dictation_codex_capture_live_e2e.sh",
    "tests/dictation_secure_capture_live_e2e.sh",
    "tests/dictation_multidisplay_capture_live_e2e.sh",
    "tests/dictation_inference_live_e2e.sh",
    "tests/dictation_installed_models_live_e2e.sh",
]

for script_path in scripts:
    script = Path(script_path).read_text()
    assert 'source "$ROOT/tests/dictation_live_lock.sh"' in script, script_path
    assert "acquire_dictation_live_lock" in script, script_path
    assert "release_dictation_live_lock" in script, script_path
PY

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-live-lock-regression.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT
worker="$temp_dir/worker.sh"
events="$temp_dir/events"

cat > "$worker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$1"
label="$2"
events="$3"
source "$ROOT/tests/dictation_live_lock.sh"
acquire_dictation_live_lock
printf 'start:%s\n' "$label" >> "$events"
sleep 0.2
printf 'end:%s\n' "$label" >> "$events"
release_dictation_live_lock
SH
chmod +x "$worker"

"$worker" "$ROOT" first "$events" &
first_pid=$!
"$worker" "$ROOT" second "$events" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"

python3 - "$events" <<'PY'
from pathlib import Path
import sys

events = Path(sys.argv[1]).read_text().splitlines()
assert len(events) == 4, events
assert events[0].startswith("start:"), events
active = events[0].split(":", 1)[1]
assert events[1] == f"end:{active}", events
other = "second" if active == "first" else "first"
assert events[2:] == [f"start:{other}", f"end:{other}"], events
PY

echo "dictation-live-harness-regression-pass"
