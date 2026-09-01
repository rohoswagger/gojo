#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

result="$(python3 "$ROOT/scripts/benchmarks/benchmark_cleanup.py" --validate-only)"
grep -Fq 'cleanup-benchmark-fixture-pass cases=4' <<<"$result"
echo "dictation-cleanup-benchmark-regression-pass"
