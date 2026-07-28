# Local dictation benchmark results

Status: implementation evidence, last verified 2026-07-23.

These measurements validate Gojo's Whisper Small reference model and record one production-path Parakeet Unified correctness probe. They do not cover Whisper Large v3 or Parakeet v3 and are not a replacement for a shipment-grade private microphone corpus. The complete protocol and gates live in [dictation-model-evaluation.md](./dictation-model-evaluation.md).

## Environment

| Item | Value |
| --- | --- |
| Device | MacBook Pro, Apple M4 Pro, 48 GB memory |
| macOS | 26.5 |
| Toolchain | Xcode 26.3 |
| Engine | Argmax OSS Swift / WhisperKit 1.0.0 |
| Model | `small.en_217MB` |
| Model repository revision | `97a5bf9bbc74c7d9c12c755d04dea59e672e3808` |
| Mode | English, VAD chunking, no timestamps, temperature 0 |

## Correctness probe

The pinned `whisperkit-cli` executable transcribed a locally synthesized 16 kHz utterance:

- reference: `Gojo local dictation should type this sentence into the focused text field.`
- hypothesis: `Gojo Local Dictation should type this sentence into the focused text field.`
- normalized WER: 0%
- normalized CER: 0%
- cloud/API use: none

The run used the same `small.en_217MB` model identifier and WhisperKit 1.0.0 revision pinned by the app. Case-only differences disappear under the committed scorer's default normalization.

### Parakeet Unified app-path probe

The signed Debug app synthesized the same fixed utterance in memory and passed it through the selected production FluidAudio backend:

- model: `fluidaudio:parakeet-unified-en-0.6b`
- pinned repository revision: `4252711f6f060f9a2f91e5f081a806d7f45eebd8`
- hypothesis: `Gojo Local Dictation should type this sentence into the focused text field`
- normalized word match: 100%
- warm resident inference: 689.8 to 873.4 ms in the latest repeated app probes
- cloud/API use: none

The hypothesis changed capitalization and omitted the final period. Those differences disappear under the committed scorer's default normalization. This is a single integration check, not a corpus benchmark or evidence that Parakeet Unified beats Whisper Small.

### Production-path integration evidence

The 2026-07-23 release gate exercised the signed Debug app and its real XPC/Accessibility boundaries:

| Probe | Result |
| --- | --- |
| Control + Option hold-to-talk | started and stopped successfully; 175 ms event-injection-to-listening |
| Control + Option tap-to-toggle | started and stopped successfully; 80 ms event-injection-to-listening |
| Parakeet Unified local inference | normalized reference match; 689.8 ms |
| Native field insertion | exact field content; `verified=true`; Accessibility method |
| Model plus native insertion | normalized reference match; exact field content; 828.8 ms inference |
| Accessibility-opaque field insertion | exact field content; application-paste method; original clipboard restored |
| Focus moved to a second opaque field | insertion refused; neither field changed; clipboard preserved |
| Opaque-field repetition | three consecutive stable success and focus-move-refusal cycles |

The GUI fixtures persist the received field value to disk, so these probes do not treat a success return or log line as proof of insertion. The synthetic audio probe covers the production recognizer and transcript policy without using a cloud API. Real microphone quality remains a separate manual and corpus-level validation requirement.

## Timing probe

| Measurement | Result | Interpretation |
| --- | --- | --- |
| First CLI install/load/transcription | about 44.9 s | Includes the one-time model download and process/model initialization. |
| New CLI process with model cached | about 5.29 s | Still includes fresh process and model loading; it is not Gojo's resident-model steady-state latency. |
| First app-path model probe | about 244.4 s | Includes Gojo's one-time 217 MB download, per-file integrity verification, Core ML preparation, inference, and verified TextEdit insertion. |
| Repeated resident app probe | about 2.0 s | Production transcriber from the verified cache through transcript policy and verified XPC/Accessibility insertion in the already-running process. |
| Restarted cached app probe | 2.0–33.7 s observed | No model download; includes process startup, all-file hash verification, Core ML load/prewarm, inference, and insertion. The variance needs a larger measured distribution. |

Gojo retains the initialized model actor in memory during normal dictation sessions. The app-path probes prove integration and cache reuse, but their single fixed synthesized sentence is not a representative latency distribution. The restarted-process result also shows that Core ML cold/prewarm variance can dominate even with the model downloaded. End-to-end p50/p95/p99 measurements on a private real-microphone corpus are still required before making a shipment-grade interaction-latency claim.

## Repeatable 20-utterance synthetic corpus

The committed benchmark runner synthesizes 20 dictation-style utterances with four built-in macOS voices, warms the model once, and performs three measured passes with one inference worker. The expected text intentionally reflects normal dictation formatting (for example spoken numbers becoming digits and a spoken URL becoming URL punctuation). Gojo's deterministic `Go-jo` → `Gojo` domain correction is applied before scoring.

Run it with:

```bash
WHISPERKIT_CLI=/path/to/pinned/whisperkit-cli \
  scripts/benchmarks/run_synthetic_whisperkit_benchmark.sh
```

The reviewed result is committed as [`whisperkit-small-en-synthetic-summary.json`](../scripts/benchmarks/fixtures/whisperkit-small-en-synthetic-summary.json). On the environment above:

| Metric | Result |
| --- | --- |
| Measured utterances | 60 (20 × 3 passes) |
| Normalized WER | 0.55% |
| Normalized CER | 0.11% |
| Exact normalized match | 95% |
| Final inference p50 | 292.5 ms |
| Final inference p95 | 354.5 ms |
| Final inference p99 | 369.1 ms |
| Mean real-time factor | 0.088 |
| Model bytes | 217,878,408 |

An initial run scored 12.5% WER because its references treated spoken forms such as “seven four two…” as the desired output rather than the formatted digits the recognizer correctly produced. References were corrected before freezing this synthetic fixture; no hypothesis was hand-edited. The remaining caveats are explicit in the summary: synthetic speech is not a user microphone corpus, engine timing excludes capture/insertion, and silence coverage is still outstanding.

## Decision

`small.en_217MB` remains Gojo's measured correctness baseline. It is free, local, natively packaged for Swift and Core ML, and passed the current reproducible synthetic fixture.

Parakeet Unified is available as the recommended English choice based on its architecture, upstream results, and the passing production-path probe above. Gojo has not yet run it through the same frozen corpus, so this document does not claim that it beats Whisper Small in the app. The next benchmark should compare all four offered models on identical audio and record accuracy, finalization latency, cold load time, memory, and offline behavior.

Training from scratch is not justified. The next optimization loop is to measure resident-app latency, compare the installed models on identical audio, tune endpointing and decoding, add a local user dictionary, and consider fine-tuning only after a consented correction corpus demonstrates persistent acoustic or model errors.
