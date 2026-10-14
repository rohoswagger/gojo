# Parakeet preparation

Gojo keeps the selected Parakeet manager loaded. The improvement in this PR removes repeated integrity hashing between installed-model inspection and model loading. It does not change the encoder, decoder, model weights, chunk geometry, compute units, or transcription output.

## Public implementation comparison

[FluidVoice v1.6.11](https://github.com/altic-dev/FluidVoice/blob/v1.6.11/Sources/Fluid/Services/FluidAudioProvider.swift#L468) separates installed-model inspection from loading and reuses the inspection result. Gojo previously hashed each installed model during its status check, then hashed the selected model again during loading. Unified's pinned files total 614,080,920 bytes.

FluidVoice pins [its FluidAudio fork](https://github.com/altic-dev/FluidVoice/blob/v1.6.11/Package.swift) at `eb1e6628998e47022799d305b52c2680d3576801`. Gojo pins upstream FluidAudio 0.15.5 at `19600a485baa4998812e4654b70d2bab8f2c9949`. The fork's incremental sessions and preprocessing lookahead are absent from Gojo's dependency. This PR does not change that dependency or port its incremental pipeline.

Gojo already reuses loaded managers and concurrent load tasks. Its current SDK selects CPU and Neural Engine for Unified's encoder and CPU for its decoder and joint model. Those settings stay in place.

## Validation receipt

Each Parakeet actor owns a `DictationModelValidationCache`. The receipt identifies the folder, required files, and each file's device, inode, mode, size, modification time, and change time. Unchanged files reuse the successful SHA-256 check. Changed or missing files invalidate the receipt. Metadata must match before and after hashing.

Installation remains explicit. Loading requires an installed, validated folder. Removal invalidates the receipt. The existing checksum manifests, byte limits, offline loaders, and allowlisted removal remain in use.

Metadata checks do not prevent a file change after the final check and before Core ML opens it. They preserve a filesystem cache, not an immutable snapshot.

## Regression checks

Run `make test-dictation-model-validation`. The tests use real temporary files and checksum validation. They cover unchanged reuse, atomic replacement, in-place corruption with the original nanosecond modification time restored, deletion, edits during validation, changed requirements, and invalidation.

The cache tests execute the production helper. The offline-policy suite checks adapter wiring and third-party offline flags. Neither replaces a real adapter lifecycle test.

## Validation measurement

On an Apple M4 Pro with 48 GiB memory, validation took a median 1.363 seconds before and 0.676 seconds after. Baseline range was 1.347 to 1.821 seconds. Candidate range was 0.643 to 0.750 seconds. Each side has five alternating fresh-process samples on the same installed Unified files. The host was busy. Filesystem caches stayed warm.

The baseline hashes 1,228,161,840 bytes across two passes. The candidate hashes 614,080,920 bytes once and rechecks file metadata for the second lookup. An unreported sampled run showed SHA compression and file reads in the validation stack. Removing one hash pass explains the approximately halved component cost. This does not measure physical disk reads or establish an end-to-end dictation speedup.

The [measurement artifact](benchmarks/parakeet-validation.json) records each sample, compiler settings, model revision, cache source hash, and binary hash. One preliminary comparison stopped on an interrupted filesystem operation. The full comparison was restarted, with no failed or incomplete samples included in its ten successful runs.

A separate real-model SDK smoke test transcribed the fixed 11-second JFK clip twice with the expected text and zero errors. It did not execute the Gojo adapter lifecycle. Initial Core ML compilation is excluded from the comparison. Parakeet v3 weights were unavailable locally, so v3 has build and shared-cache regression coverage rather than a real-model inference run.

## Reproduce validation timing

Use an already-installed Unified English model. The benchmark does not download models or require FluidAudio to compile. It compiles the production cache with `swiftc -O` and extracts the pinned checksum manifest from the Unified adapter.

```sh
bash scripts/benchmarks/parakeet_preparation/build.sh
python3 scripts/benchmarks/parakeet_preparation/run_benchmark.py \
  --model-folder /path/to/parakeet-unified-en-0.6b-coreml \
  --output-dir /tmp/gojo-parakeet-validation-results
```

Choose a new output directory for each comparison. The runner verifies every checksum and the expected file and byte counts. It records build provenance, host load, per-run logs, and errors. The timed region includes validation only. It excludes model loading, audio processing, inference, and insertion.

The first benchmark design rebuilt the complete SDK, which hit a Swift optimizer deserialization failure. The final benchmark removes that unrelated dependency and measures only the production validation component. Production build flags remain unchanged.
