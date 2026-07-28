# Local dictation model evaluation

Status: benchmark contract, last reviewed 2026-07-17.

This document defines the evidence required to select or change Gojo's local speech-to-text engine. Vendor and project benchmarks are useful for choosing candidates; only results from this harness and Gojo's target hardware decide shipment.

## Candidate matrix

| Candidate | Deployment path | Streaming behavior | Published size information | License review | Evaluation role |
| --- | --- | --- | --- | --- | --- |
| [Argmax OSS WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) `small.en_217MB` | Native Swift package and Core ML on macOS 14+ | Microphone/partial transcription support over Whisper's windowed encoder-decoder | 217 MB model directory is published in the [Argmax model repository](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main) | SDK MIT; Whisper weights MIT; preserve Argmax notices | supported reference model |
| WhisperKit compressed `large-v3` | Same | Same | Current repository includes compressed variants around 626 MB | Same | supported larger English option |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.15.5 with [Parakeet Unified](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml) | Native Swift package and Core ML on macOS 14+ | Current Gojo path uses offline batch transcription | Verified Gojo subset is limited to 614,080,920 bytes | Runtime Apache 2.0; model repository declares CC BY 4.0; preserve FluidInference and NVIDIA attribution | supported and recommended for English; single app-path probe passed, full corpus pending |
| FluidAudio 0.15.5 with [Parakeet v3](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) | Native Swift package and Core ML on macOS 14+ | Current Gojo path uses offline batch transcription | Verified INT8 subset is limited to 483,105,645 bytes | Runtime Apache 2.0; model repository declares CC BY 4.0 | supported for 25 European languages; Gojo benchmark pending |
| [Moonshine Small Streaming](https://github.com/moonshine-ai/moonshine) | Official `moonshine-swift` SPM package, native Swift binding over ONNX Runtime | Incremental encoder/decoder state | Project lists 123M parameters | Code and English model MIT; audit included third-party binaries | primary low-latency challenger |
| Moonshine Medium Streaming | Same | Same | Project lists 245M parameters | Same | accuracy/latency ceiling challenger |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) `small.en` Q5 | C API plus Gojo-owned Swift/XCFramework bridge; Metal/Core ML options | Sliding-window sample, not a native causal recognizer | Unquantized `small.en` is 466 MB in the [official conversion repository](https://huggingface.co/ggerganov/whisper.cpp); record actual Q5 size | MIT | portable fallback/reference |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) streaming English Zipformer | Swift API over ONNX Runtime | Native online transducer | Project lists a 20M English model; record downloaded bytes | Framework Apache 2.0; audit model separately | small-footprint challenger |
| sherpa-onnx Parakeet TDT 0.6B int8 | Same | Listed by sherpa-onnx as non-streaming | 0.6B parameter family; record downloaded bytes | Audit exact NVIDIA model card and attribution | optional quality challenger |
| [MLX Whisper](https://github.com/ml-explore/mlx-examples/blob/main/whisper/README.md) | Python CLI/reference implementation | Whisper windowing | Supports converted and 4-bit weights; record artifact bytes | MIT | research throughput comparison only |

Do not infer disk or memory requirements from parameter count. Record compressed download bytes, unpacked bytes, cold resident memory, and peak resident memory for each exact artifact revision.

Published benchmark results are useful for choosing what to test, but they are not Gojo acceptance evidence. Whisper Large v3, Parakeet Unified, Moonshine, and every later candidate must run through the same frozen corpus and complete app path before their accuracy or latency can be compared.

## Reproducibility record

Every benchmark run must record:

- git revision of Gojo and the benchmark scripts;
- engine package name, immutable revision, build configuration, and compiler/Xcode version;
- model identifier, upstream revision, SHA-256, download bytes, and unpacked bytes;
- Mac identifier, chip, memory, macOS version, power source, and Low Power Mode;
- microphone/input device and sample format;
- decoding, VAD, endpointing, language, prompt, and thread/compute settings;
- whether the model and OS caches were cold or warm;
- corpus manifest revision and normalization mode;
- per-utterance transcript and timing output;
- aggregate metrics plus p50, p95, and p99 latency.

Use Release builds. Close unrelated compute-heavy applications, disable automatic model downloads during timing, and run at least three passes after one warm-up pass. Preserve raw machine-readable results under an ignored local results directory; commit only reviewed summaries that contain no private transcripts.

## Corpus

Keep public evaluation audio separate from private Gojo recordings. Never commit or upload user audio or transcripts without explicit consent.

### Gojo dictation corpus

Begin with 100–200 manually verified utterances from the target user and grow to at least 1,000 before fine-tuning. Include:

- 1–3 second commands and corrections;
- 5–20 second prose and messages;
- hesitations, restarts, filler words, and self-corrections;
- punctuation and capitalization expectations;
- names, Gojo terms, programming terms, URLs, numbers, and symbols;
- built-in microphone, common headset/AirPods input, near/far distance;
- quiet room, fan/keyboard noise, music, and moderate background speech;
- at least 50 silence/non-speech clips.

Split by speaker and recording session. A session may appear in only one of train, development, or test. Freeze the test split before tuning prompts, VAD, decoding, or correction rules.

### Public regression sets

- [LibriSpeech](https://www.openslr.org/12) `test-clean` and `test-other` provide approximately 1,000 hours of aligned read-English source data and standard clean/challenging test splits. They are useful for regression, but not representative enough to select a dictation engine alone.
- [Mozilla Common Voice](https://commonvoice.mozilla.org/terms) English validation/test adds community-contributed speakers, accents, and devices. Mozilla distributes current Common Voice datasets under CC0 through Mozilla Data Collective.
- [GigaSpeech](https://github.com/SpeechColab/GigaSpeech) dev/test may add podcast, YouTube, spontaneous, and noisy speech. Its official repository describes 10,000 transcribed hours and an Apache 2.0 repository license; review the underlying source terms before training or redistributing derived artifacts.

Never train on the selected public or private test partitions.

## Transcript manifest

`scripts/benchmarks/score_transcripts.py` accepts UTF-8 JSON Lines. Required fields are `id`, `reference`, and `hypothesis`; all other fields are preserved by the producer but ignored by the scorer.

```json
{"id":"gojo-0001","reference":"Open Gojo settings.","hypothesis":"open gojo settings","engine":"whisperkit","model":"small.en_217MB","audio_sha256":"...","final_latency_ms":184.2}
```

Recommended producer fields are:

- `corpus`, `split`, and `audio_sha256`;
- `engine`, `engine_revision`, `model`, and `model_sha256`;
- `duration_ms`, `first_partial_ms`, `final_latency_ms`, and `real_time_factor`;
- `peak_resident_bytes`, `cold_start`, and `run_id`;
- decoding/VAD configuration identifiers.

Do not put filesystem paths, user names, raw audio, or unredacted private metadata in committed manifests.

The default scorer applies Unicode NFKC normalization, case-folding, punctuation/symbol removal, and whitespace collapse. WER uses normalized whitespace-delimited words. CER uses the same normalized text with whitespace removed. Use `--normalization none` when punctuation/capitalization behavior is the subject of a separate metric.

## Accuracy metrics

Required:

- aggregate word error rate (WER), including substitution, deletion, and insertion counts;
- aggregate character error rate (CER);
- exact-utterance match rate after the selected normalization;
- proper-noun/domain-term WER on a tagged subset;
- punctuation and capitalization precision/recall/F1 on unnormalized text;
- silence hallucination rate;
- repeated-token/hallucination rate on speech clips.

Aggregate edit counts before dividing by aggregate reference units. Do not average per-utterance WER, because short utterances would be overweighted. Report confidence intervals or at minimum per-session ranges when the corpus has enough sessions.

## Latency, resource, and stability metrics

Measure on the complete Gojo path, not just engine inference:

- shortcut-down to confirmed audio capture;
- speech onset to first stable partial;
- shortcut-up/end-of-speech to final transcript;
- final transcript to completed insertion;
- total real-time factor and engine processing time;
- cold model load and warm resume;
- download and unpacked storage;
- idle, recording, and finalizing CPU/GPU/ANE utilization;
- peak resident memory and energy impact;
- partial churn: edit distance between consecutive partials and final text;
- 1,000 start/stop sessions, cancellation, input-device change, sleep/wake, and app restart;
- full operation with outbound network access blocked after model installation.

Latency results must include p50, p95, and p99. Average alone is insufficient for a push-to-talk interaction.

## Initial shipment gates

The default model must satisfy all gates on supported target hardware:

| Gate | Initial threshold |
| --- | --- |
| Shortcut-down to capture | p95 <= 100 ms |
| Key release to final transcript for <=10 s utterance | p95 <= 500 ms |
| Final transcript to insertion | p95 <= 100 ms |
| Gojo private-corpus normalized WER | <= 10% |
| Silence hallucination rate | <= 0.5% |
| Peak resident memory for default model | <= 1 GiB |
| Push-to-talk reliability | 1,000 cycles without crash, stuck recorder, or leaked audio tap |
| Offline behavior | zero network requests after verified install |
| Privacy | no transcript/audio/target text in logs or diagnostics |
| Licensing | exact engine/model revision and required notices reviewed |

If no candidate meets every gate, improve endpointing, capture, or decoding and rerun. Do not hide a failed local gate with an automatic cloud fallback.

## Training escalation

Do not train an ASR model from scratch for v1. The [Whisper paper](https://arxiv.org/abs/2212.04356) reports training on 680,000 hours of multilingual and multitask supervision. Recreating that robustness would require a separate data, compute, legal, and evaluation program.

Escalate in this order:

1. Classify failures into capture, VAD/endpointing, decoding, vocabulary, punctuation, insertion, and genuine acoustic/model errors.
2. Tune capture, endpointing, language, prompt, and decoding on the development split only.
3. Add a local user dictionary and deterministic correction rules for stable names and terms. Measure regressions.
4. Collect opt-in audio paired with the user's corrected transcript.
5. Fine-tune an existing model only after at least 1,000–5,000 consented in-domain utterances reveal a persistent model error that does not yield to earlier steps.

A fine-tuning proposal must demonstrate a material target-domain gap, define a speaker/session-disjoint holdout, document dataset consent and licenses, and set a no-regression gate on the frozen public and private tests. Prefer parameter-efficient adaptation of an existing English checkpoint. Export through the chosen runtime's documented conversion path and repeat asset-integrity and license review.

Training from scratch is reconsidered only for an unsupported language/license need, a demonstrated footprint target that existing models cannot meet, or a novel streaming requirement that cannot be reached through fine-tuning. That decision requires its own approved data and compute plan.

## Scorer commands

```bash
python3 scripts/benchmarks/score_transcripts.py results.jsonl
python3 scripts/benchmarks/score_transcripts.py results.jsonl --json
python3 scripts/benchmarks/score_transcripts.py results.jsonl \
  --max-wer 0.10 \
  --max-cer 0.08 \
  --max-silence-hallucination-rate 0.005
```

Threshold failure exits non-zero, so the scorer can be used in regression tests. Run its repository test with:

```bash
./tests/dictation_benchmark_regression.sh
```
