# Benchmark dictation with fixed audio

Use this workflow to freeze audio once, collect complete results from a local engine adapter, and compare compatible runs. The tools reuse `score_transcripts.py` for WER, CER, exact matches, and silence hallucinations. They use only the Python standard library.

The bundled adapter runs an installed WhisperKit CLI. Other engines, including Parakeet and local cleanup, can use the same batch adapter protocol. This workflow does not execute Gojo's microphone capture, target selection, or text insertion. It does not establish end-to-end dictation latency or production controller parity.

## Check the infrastructure

```sh
make test-dictation-benchmark
```

This command runs offline on macOS and Linux without building Gojo, loading models, or requesting network inference. The protocol fixture in the tests proves collection, validation, and regression gates. Its transcript and timing values are test data, not ASR measurements. The independent GitHub Actions workflow runs the same checks.

## Freeze a corpus

For your own recordings, create a JSONL source file. Relative audio paths resolve from the source file. Audio must be PCM16, mono, 16 kHz WAV.

```jsonl
{"id":"speech-1","reference":"Hello world.","audio_path":"recordings/speech.wav"}
{"id":"silence-1","type":"silence","reference":"","duration_seconds":1}
```

```sh
python3 scripts/benchmarks/dictation_benchmark.py prepare recordings.jsonl \
  --output .build/benchmarks/corpus
```

To generate the existing synthetic speech corpus on macOS instead, explicitly enable synthesis. The requested system voices must already be available.

```sh
make benchmark-dictation-prepare BENCHMARK_SYNTHESIZE=1
```

Preparation copies or generates audio and records its content hash, reference, sample count, and duration in `corpus.json`. Reuse that directory for baseline and candidate runs. Preparation refuses an existing output directory. Runs verify the frozen files before and after adapter execution. Changed audio or references require a new corpus and cannot silently enter a comparison.

Synthetic speech is useful for repeatability. It does not represent microphone noise, accents, or conversational speech. Add consented recordings before drawing conclusions about those conditions. The existing synthetic corpus has no silence case; add an explicit silence row if you need that acceptance gate.

## Configure the installed WhisperKit CLI

Set `WHISPERKIT_CLI`, `WHISPERKIT_MODEL_PATH`, and `WHISPERKIT_TOKENIZER_PATH` to existing local assets. The tokenizer directory must contain the locally usable tokenizer files. No setup command downloads models or installs a CLI.

Generate a run configuration from the repository root.

```sh
python3 - <<'PY'
import json
import os
from pathlib import Path
import sys

root = Path.cwd()
config = {
    "schema_version": 1,
    "adapter": [sys.executable, str(root / "scripts/benchmarks/whisperkit_adapter.py")],
    "engine": {"id": "WhisperKit", "revision": "local-binary"},
    "model": {"id": "local-whisper", "revision": "local-files", "path": os.environ["WHISPERKIT_MODEL_PATH"]},
    "normalization": "basic",
    "repeats": 5,
    "warmup": 1,
    "process_lifecycle": "per_case",
    "concurrency": 1,
    "build_mode": "release",
    "configuration": {"language": "en"},
    "metric_definitions": {
        "engine_pipeline": {"unit": "ms", "definition": "WhisperKit CLI timings.fullPipeline multiplied by 1000"},
        "subprocess_wall": {"unit": "ms", "definition": "Monotonic elapsed time around each sandboxed WhisperKit CLI process, including launch, loading, inference, and report writing"}
    },
    "primary_metric": "engine_pipeline",
    "timeout_seconds": 1800,
    "adapter_config": {
        "cli_path": os.environ["WHISPERKIT_CLI"],
        "cli_revision": "local-binary",
        "tokenizer_path": os.environ["WHISPERKIT_TOKENIZER_PATH"],
        "case_timeout_seconds": 120
    }
}
output = root / ".build/benchmarks/whisperkit.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(config, indent=2) + "\n")
PY
```

Engine/model revisions and build mode are declarations. Supply verified versions and the actual CLI build mode when available. The run separately records measured executable, adapter-script, model-tree, and tokenizer asset hashes. A declared revision string does not prove a binary or model came from that revision.

The WhisperKit adapter requires macOS `sandbox-exec` and denies network access to the CLI. Missing CLI, model, or tokenizer prerequisites fail explicitly. CLI reports and diagnostics remain in the run directory. The adapter retains raw transcript text, including spelling differences that older scripts rewrote before scoring.

Each WhisperKit invocation starts a new process. Rehearsal calls can condition OS caches, but do not retain a loaded model for later processes. These results use `model_state=unknown`, never `warm`. `engine_pipeline` is a producer-reported SDK boundary. `subprocess_wall` also includes startup and loading. Neither is keyboard-release-to-insertion time.

## Collect and inspect results

Use a unique output directory for each run.

```sh
make benchmark-dictation \
  BENCHMARK_CONFIG=.build/benchmarks/whisperkit.json \
  BENCHMARK_OUTPUT=.build/benchmarks/baseline

make benchmark-dictation-report BENCHMARK_RUN=.build/benchmarks/baseline
```

The run retains `run.json`, normalized `results.jsonl`, `summary.json`, the adapter's original stdout/stderr, and its artifacts. The run record includes the frozen corpus, exact case/repeat plan, host, source revision and working-tree fingerprint, semantic settings, timing definitions, and measured asset hashes. Fingerprinting happens outside adapter timing. Separate run observations record start/end load averages and wall/monotonic collection durations without changing the stable host comparison key.

Report recomputes its summary from the saved records. The `basic` normalization ignores case, punctuation, and symbols. Use `none` when those differences matter, such as formatting or code dictation; it still collapses whitespace. Missing, duplicate, unexpected, invalid, timed-out, and failed results cannot pass. Rehearsals remain recorded but are excluded from measured accuracy and latency. Unknown stages stay unavailable rather than becoming zero. First-use, warm-session, and unknown model states have separate timing buckets. Raw and final accuracy are separate when every measured result supplies `raw_hypothesis`.

Keep run directories local. Transcripts, recordings, commands, and host metadata can contain private information. Nothing uploads results automatically. Review and redact any artifacts you choose to share.

## Compare a candidate

Run the candidate against the same corpus into a new directory, then compare.

```sh
make benchmark-dictation \
  BENCHMARK_CONFIG=.build/benchmarks/whisperkit.json \
  BENCHMARK_OUTPUT=.build/benchmarks/candidate

python3 scripts/benchmarks/dictation_benchmark.py compare \
  .build/benchmarks/baseline .build/benchmarks/candidate \
  --max-wer-increase 0 --max-p95-increase 0.10
```

`--max-wer-increase` is an absolute WER change. `0.01` permits one percentage point. `--max-p95-increase` is fractional growth, so `0.10` permits ten percent. Zero means no increase. Absolute gates include `--max-wer`, `--max-cer`, `--max-silence-hallucination-rate`, and `--max-p95-ms`. Requested metrics that are unavailable fail the gate. Without thresholds, comparison reports compatibility and deltas without an accuracy or speed budget.

Comparisons require the same frozen corpus, complete plan, normalization, timing boundaries, lifecycle, concurrency, and semantic settings. Latency gates also require a matching host and declared build mode. Source revisions and executable hashes can differ because candidate implementations are expected to change; the output lists provenance changes. Model identity and content must match unless you explicitly use `--allow-model-change`.

Measure on an otherwise idle machine where possible. Record at least five repetitions and inspect spread alongside p50/p95. A small difference within run variation is inconclusive. For before/after performance work, alternate candidate and baseline collection order across independent runs. The runner records order and samples; it does not make an uncontrolled machine or changing cache state comparable.

## Connect another engine

Put all language, decoding, prompt, and cleanup choices in `configuration`. Reserve `adapter_config` for operational paths, revisions, and timeouts. Custom adapters must honor this distinction; the harness cannot infer semantic effects from arbitrary executable arguments. Review provenance differences when comparing changed producers.

An adapter is an executable argv array, never a shell command. It receives one JSON request on stdin with `schema_version`, `run_id`, `cases`, the ordered `plan`, `config`, and `artifact_dir`. Cases contain verified absolute audio paths and metadata. Reference text stays with the harness.

Emit one JSON object per planned item on stdout, in plan order. Send diagnostic logs to stderr. A successful row supplies `schema_version`, `item_id`, `case_id`, `repeat`, `phase`, `hypothesis`, `timings_ms`, and `model_state`. A failed row supplies a nonempty `error` instead of `hypothesis`. Timing stages must be declared in the configuration and use finite, nonnegative milliseconds. Optional `raw_hypothesis` preserves the ASR text before cleanup.

A persistent adapter can identify a model session through `session_id`, label its first planned execution `first`, and label subsequent executions in that same session `warm`. Per-case subprocess adapters must use `unknown`. Rehearsal success alone is not evidence that a different process retains model state.

A future production Gojo adapter must also distinguish successful cleanup inference from fallback. The current S1 polisher returns raw text on several fallback paths, and best-effort ASR `prepare()` suppresses load errors. An ordinary return from either method cannot prove the stage executed. Missing stage telemetry must remain unavailable.

Custom adapters are responsible for their engine's network and model-loading policy. The harness does not sandbox arbitrary executables. The bundled WhisperKit adapter supplies its own network-denied wrapper.
