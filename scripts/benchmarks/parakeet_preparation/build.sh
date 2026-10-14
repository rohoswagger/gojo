#!/usr/bin/env bash
set -euo pipefail

runner_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$runner_dir/../../.." && pwd)"
package_dir="$runner_dir/.build/package"
binary="$runner_dir/.build/GojoParakeetValidationBenchmark"
mkdir -p "$package_dir/Sources/GojoParakeetBenchmark"
cp "$repo_dir/Gojo/Dictation/DictationModelValidationCache.swift" "$package_dir/Sources/GojoParakeetBenchmark/DictationModelValidationCache.swift"
python3 "$runner_dir/generate_manifest.py" "$repo_dir/Gojo/Dictation/ParakeetUnifiedDictationTranscriber.swift" "$package_dir"
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 \
  "$repo_dir/Gojo/Dictation/DictationModelValidationCache.swift" \
  "$package_dir/Sources/GojoParakeetBenchmark/PinnedModelManifest.swift" \
  "$runner_dir/Sources/GojoParakeetBenchmark/Main.swift" \
  -o "$binary"
python3 - "$binary" "$package_dir/pinned-manifest.json" "$runner_dir/.build/build-provenance.json" <<'PYTHON'
import hashlib
import json
from pathlib import Path
import subprocess
import sys

binary, manifest, output = map(Path, sys.argv[1:])
provenance = {
    "configuration": "optimized-validation-component",
    "swiftFlags": ["-O", "-swift-version", "5", "-target", "arm64-apple-macosx14.0"],
    "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "toolchain": subprocess.check_output(["swift", "--version"], text=True).strip(),
    "manifest": json.loads(manifest.read_text()),
}
output.write_text(json.dumps(provenance, indent=2) + "\n")
PYTHON
