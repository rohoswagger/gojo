#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scorer="$repo_root/scripts/benchmarks/score_transcripts.py"
fixture="$repo_root/scripts/benchmarks/fixtures/sample-transcripts.jsonl"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-dictation-benchmark.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

python3 "$scorer" "$fixture" --json > "$test_dir/result.json"

python3 - "$test_dir/result.json" <<'PY'
import json
import math
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    result = json.load(source)

assert result["utterances"] == 4
assert result["reference_words"] == 7
assert result["word_counts"] == {
    "deletions": 0,
    "errors": 4,
    "insertions": 3,
    "substitutions": 1,
}
assert math.isclose(result["wer"], 4 / 7)
assert result["silence_utterances"] == 1
assert result["silence_hallucinations"] == 1
assert result["silence_hallucination_rate"] == 1.0
assert result["latency_ms"] == {
    "count": 4,
    "max": 400.0,
    "mean": 250.0,
    "min": 100.0,
    "p50": 200.0,
    "p95": 400.0,
    "p99": 400.0,
}
assert math.isclose(result["real_time_factor"]["p95"], 0.4)
PY

if python3 "$scorer" "$fixture" --max-wer 0.10 > /dev/null 2>&1; then
    echo "expected WER threshold to fail" >&2
    exit 1
fi

cat > "$test_dir/invalid.jsonl" <<'EOF'
{"id":"missing-hypothesis","reference":"hello"}
EOF

if python3 "$scorer" "$test_dir/invalid.jsonl" > /dev/null 2>&1; then
    echo "expected invalid manifest to fail" >&2
    exit 1
fi

echo "dictation benchmark regression passed"
