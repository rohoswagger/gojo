# Local dictation architecture

Status: implemented v1 architecture with measured follow-up work, last reviewed 2026-07-23.

## Decision

Gojo dictation is speech-to-text: a global push-to-talk shortcut records the microphone, transcribes on the Mac, and inserts the final text into the currently focused editable control.

Gojo supports two local recognition engines behind a Gojo-owned router. WhisperKit runs Whisper Small and Whisper Large v3. FluidAudio runs Parakeet Unified and Parakeet v3. Recording, permissions, transcript cleanup, focused-field validation, and insertion remain independent of the selected engine.

Whisper Small remains the measured reference model. Whisper Large v3 provides a larger English Whisper option. Parakeet Unified is the recommended English option because it includes punctuation and capitalization, but it must pass Gojo's frozen benchmark before the project claims that it is more accurate in Gojo.

Models are installed only after the user clicks **Download** in Settings. Installing an optional model does not select it. Dictation never downloads a model while handling the shortcut.

Do not make SwiftWhisper or MLX Whisper the v1 dependency. [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) wraps whisper.cpp but its latest release is from 2023. Apple's [MLX Whisper example](https://github.com/ml-explore/mlx-examples/blob/main/whisper/README.md) is Python-oriented rather than a turnkey Swift speech recognizer. [whisper.cpp](https://github.com/ggml-org/whisper.cpp) remains the portability fallback if the Swift packages prove unsuitable.

## Boundaries

The feature should be split into independently testable responsibilities:

1. **Shortcut controller** begins or ends one push-to-talk session. It must reject auto-repeat and overlapping sessions.
2. **Audio recorder** owns microphone permission and produces 16 kHz mono PCM samples. It must never write audio to disk unless a diagnostic mode explicitly says so.
3. **Speech recognizer engine** consumes samples and reports partial and final transcripts. The rest of Gojo must not import an engine SDK directly.
4. **Transcript policy** normalizes whitespace, rejects empty/silence hallucinations, and decides whether partial text is display-only or safe to commit.
5. **Focused-text inserter** snapshots the focused accessibility target, validates that it remains editable, and inserts only the final transcript. Clipboard fallback must restore the prior clipboard contents.
6. **Dictation coordinator** owns the session state machine, cancellation, telemetry counters, and user-visible status.
7. **Model asset store** downloads, verifies, activates, rolls back, and removes models independently of app updates.

The engine-facing contract should express behavior rather than SDK types. It needs operations equivalent to prepare, start, append samples, finish, cancel, and unload; events need listening, partial transcript, final transcript, and failure. Only one session may own the engine at a time.

## Extension rules

Keep these rules when adding models, output formatting, vocabulary, or insertion paths:

- Put decisions in small synchronous policies when possible, then test those policies with compiled Swift behavior tests. Do not add source-string assertions for behavior that can be called directly.
- Keep `DictationController` engine-neutral. Model SDK types belong inside their transcriber adapters.
- Add model identity and engine ownership to `DictationModelID`. Keep the settings descriptor consistent with that mapping. The regression suite checks this invariant.
- Represent mutually exclusive work with one enum state. Do not add parallel booleans or optionals for install, select, and remove operations.
- Keep model downloads behind an explicit settings action. The shortcut path may read cached status, but it must not download or hash model assets.
- Apply output formatting and vocabulary after transcription and before insertion. Do not duplicate formatting inside WhisperKit or FluidAudio adapters.
- Capture the destination before showing dictation UI or requesting microphone access. Revalidate the captured process, window, and field before any insertion side effect.
- Keep client, helper, and insertion focus checks separate. They defend different process and timing boundaries and are not duplicate validation.
- Add one pure behavior test for every decision policy. Add a focused integration test for XPC routing. Reserve live app tests for final system behavior.

## Session state machine

Use explicit states so shortcut, permission, model, and microphone failures cannot leave Gojo recording invisibly:

```text
idle -> requestingPermission -> listening -> transcribing -> inserting -> succeeded
  |              |                |              |             |
  +--------------+----------------+--------------+-------------+-> error
                                 +-------------------------------> idle (cancel)
```

- Shortcut-down enters `requestingPermission` after the selected model passes cached preflight.
- Shortcut-up finishes the active utterance. If model preparation is still running, cancel rather than retaining microphone audio indefinitely.
- Partials may update Gojo's local UI, but v1 inserts only the final transcript. This prevents repeated accessibility edits and unstable partial text in third-party apps.
- Escape, loss of microphone input, shortcut-tap timeout, app termination, and model failure cancel the session and release the audio tap.
- A watchdog must return any non-idle session to idle if audio and recognizer progress both stop.

## Privacy and offline rules

Local/private is a product invariant, not a preference:

- Audio samples and transcripts stay in process and are not sent to Gojo, Argmax, FluidInference, analytics, crash-report attachments, or model hosts.
- Network access is allowed only for an explicit model download or update. A completed model must continue to work with the network disabled.
- Do not persist raw audio by default. A future opt-in improvement corpus must explain retention, allow preview/deletion, and store data locally until the user explicitly exports it.
- Do not log transcript text, accessibility values, clipboard contents, or audio buffers. Operational logs may contain duration, engine/model identifiers, status codes, and timing buckets.
- The app must visibly indicate listening and finalizing, and it must stop recording immediately on cancellation.
- Microphone and Accessibility permissions are requested in context. Lack of either permission must fail closed without changing the target application.

An automated offline test should block outbound traffic after the model is installed and run a full record/transcribe/insert session. A dependency upgrade is not accepted if it adds background model, telemetry, or update requests.

## Model assets and integrity

Gojo does not bundle or automatically install a speech model. Settings offers four explicit downloads: Parakeet Unified, Parakeet v3, Whisper Small, and Whisper Large v3. Each download uses a pinned repository revision, a fixed file list, a byte ceiling, and source-controlled SHA-256 hashes. Normal transcription reads only the verified local snapshot and does not contact a model host.

The Whisper models use Argmax repository revision `97a5bf9bbc74c7d9c12c755d04dea59e672e3808`. Whisper Small is limited to 230 MB and Whisper Large v3 to 626,718,238 bytes. Parakeet Unified uses FluidInference revision `4252711f6f060f9a2f91e5f081a806d7f45eebd8` and an offline INT8 subset limited to 614,080,920 bytes. Parakeet v3 uses FluidInference revision `aed02740059203c4a87495924f685de3722ae9ce` and an INT8 subset limited to 483,105,645 bytes. Each downloadable asset needs a signed-in-source manifest containing:

- stable model identifier and engine identifier;
- upstream repository and immutable revision;
- download URL;
- expected byte length;
- SHA-256 digest for every downloaded archive or file;
- model/runtime license and required notices;
- minimum macOS, architecture, and engine version;
- unpacked byte length and entry-point filenames.

The current Hub client downloads into its content-addressed snapshot cache, after which Gojo enforces the maximum byte count and source-controlled hashes before storing the active path. A future Gojo-owned asset store should add explicit staging, atomic rename, rollback, and deletion without depending on SDK cache layout. Never execute code from a model archive.

The active-model pointer must be rollback-safe. A corrupt, missing, incompatible, or unlicensed model falls back to the last verified model; it must not silently switch to a cloud API. Model deletion should be available in settings and should remove only the exact asset directory recorded in the manifest.

## Distribution and licensing

Gojo is GPLv3, but every engine and model still needs an attribution and redistribution review:

- Argmax OSS is MIT and maintains third-party notices. OpenAI publishes Whisper code and weights under MIT in the [official repository](https://github.com/openai/whisper).
- FluidAudio 0.15.5 is Apache 2.0. Its compiled library also contains fastcluster code under the BSD 2-Clause License.
- The pinned Parakeet Unified and Parakeet v3 Core ML repositories declare CC BY 4.0. Gojo does not bundle these weights. It downloads them only when the user requests a model.
- Moonshine code and English models are MIT. Its non-English models use the Moonshine Community License, which the project describes as non-commercial; therefore they are not v1 distribution candidates.
- whisper.cpp is MIT.
- sherpa-onnx is Apache 2.0, but each model has its own license. A framework license never substitutes for a model-license review.
- MLX and its examples are MIT.

Copy upstream copyright and notice material into Gojo's shipped notices when an engine or model is distributed. Pin exact revisions and archive the license text reviewed for that revision.

## Failure and fallback policy

- No network: use an installed verified model; otherwise explain that the model must be installed before offline dictation is available.
- Model load failure: roll back to the previous verified asset and surface a local error.
- Recognizer failure: preserve the user's focused application and clipboard; do not insert a partial.
- Focus changed during recording: do not insert and require a new dictation session after the user restores the intended target. Never retarget an utterance at completion. A future recovery UI may offer an explicit copy action without automatic retargeting.
- Secure text field: refuse insertion and discard the transcript.
- Accessibility insertion unsupported: an explicitly enabled clipboard-paste fallback may be used, with atomic clipboard save/restore and clear failure reporting.
- Accessibility-opaque terminal: a reviewed bundle may use direct Unicode keyboard events. Gojo must keep the captured process and window active, recheck them before every chunk, and never enable this path globally.

There is no cloud fallback in the local dictation feature. An API-backed mode would be a separate opt-in product with separate privacy language and is outside v1.

## Delivery sequence

1. Land engine-neutral session, audio, insertion, and asset interfaces with fakes.
2. Integrate WhisperKit `small.en` and prove a complete offline push-to-talk session.
3. Run the corpus and gates in [dictation-model-evaluation.md](dictation-model-evaluation.md).
4. Integrate challengers only through the same engine boundary and rerun the identical benchmark.
5. Select the default from measured Gojo results. Keep the other engine only if its support burden is justified by a user-visible tier or fallback.
6. Collect opt-in corrections before considering model adaptation.

The engine decision is revisited when a candidate beats the current default on the same frozen corpus without violating latency, memory, reliability, offline, license, or distribution gates.

## Verified v1 evidence

- The signed Debug app builds with the microphone entitlement and local-only usage string.
- Dedicated controller/audio/XPC/scorer regressions cover rapid key events, cancel/restart teardown, watchdog expiry, sample conversion, secure targets, one-shot focus tokens, paste confirmation, and benchmark math.
- The Debug-only behavioral probe covers the real app/XPC/Accessibility path. Its native fixture verifies the final field value instead of trusting an API return alone.
- An accessibility-opaque two-field fixture covers browser-style Cmd-V insertion. It verifies exact received text, full clipboard restoration, and refusal when focus moves to a second field before insertion.
- The helper revalidates focused-control fingerprints immediately before the sandboxed app posts paste key events. When macOS exposes only a window-level browser target, the app revalidates the captured process and window before clipboard mutation and before every key event.
- Super and Codex use a separate Unicode-event path when they expose only an opaque window through Accessibility. The path is limited to reviewed bundle IDs and splits text without breaking extended grapheme clusters, so dictated text does not need to touch the global clipboard.
- A Debug-only AX-opaque fixture exercises the full Super-style route through target capture, the XPC handoff, window validation, and Unicode events. It received the exact multi-chunk string, including a family emoji at the chunk boundary, without changing the clipboard.
- The live Control + Option probe passed both hold-to-talk and tap-to-toggle. The latest injected-event measurements reached listening in 175 ms and 80 ms respectively; service-side capture and audio startup were about 50 ms after shortcut acceptance.
- A second Debug-only probe synthesized a fixed utterance in memory, ran it through the production transcriber and transcript policy, and verified insertion into TextEdit. Its first model-install run took 244.4 seconds; two verified cached runs took about 2.0 seconds each.
- The pinned model transcribed the repeatable 60-run synthetic fixture at 0.55% WER with 354.5 ms p95 and 369.1 ms p99 final inference latency on the documented M4 Pro environment.

## Remaining risks and next iterations

- macOS privacy consent cannot be granted silently. The shortcut reached the real microphone authorization boundary, but a human must approve Microphone and Accessibility before the first spoken end-to-end run.
- The synthetic corpus does not represent the user's microphone, accent, room noise, AirPods, spontaneous corrections, or silence. Collect consented local-only samples and freeze speaker/session-disjoint development and test splits before making shipment-grade accuracy claims.
- The benchmark measures engine finalization separately from shortcut-to-capture and insertion. Add signposted app timestamps and report complete p50/p95/p99 without logging audio or text.
- Settings can remove each downloaded model independently. Removal is limited to an allowlist under the model's expected cache root and leaves sibling models alone. Previous-version rollback is not available yet.
- Accessibility insertion verifies the resulting value before reporting success. The browser compatibility path cannot read the resulting DOM value through AX, so it reports `verified=false`, restores the clipboard after the paste event, and is covered by a fixture that checks the actual received text.
- Unicode-event insertion also reports `verified=false` because an AX-opaque terminal does not expose its resulting value. It can stop before the next chunk if focus changes, but text already delivered before that change cannot be rolled back. Such failures are marked `partialInsertion` so the app does not tell the user that nothing was added.
- Input-device changes during an utterance still rely on the recorder/watchdog failure path. Add explicit route-change testing across built-in microphones, headsets, sleep/wake, and 1,000 start/stop cycles.
- Intel build compatibility is inherited from the app target, but local-model performance has only been measured on Apple silicon.

## Future screen awareness

Screen awareness stays outside v1. The next design should treat visual context as an explicit, user-controlled input: capture only the active app/window or selected region, show a visible consent indicator, keep OCR/vision local by default, redact secure/protected surfaces, and pass a short context prompt to the same engine boundary. It must never weaken the exact focused-target token or silently redirect a transcript to a field selected after recording began.

## Handy reference review

The v1 design was compared against [`cjpais/Handy` at commit `d861e24b`](https://github.com/cjpais/Handy/tree/d861e24bc825c699ccf7215a430684c6e322131c). Handy validates the overall product shape—configurable push-to-talk, 16 kHz local inference, VAD, a nonactivating status overlay, and explicit model preparation—but Gojo intentionally keeps a narrower and safer boundary:

- Gojo binds each utterance to the exact focused AX element when an app exposes one. Apps with incomplete accessibility bridges use the frontmost application captured at key-down and the same clipboard-paste pattern used by native dictation tools.
- Gojo rejects secure fields when macOS exposes that state and verifies an exact before/selection/after mutation when the target supports it. The application-paste compatibility path restores every clipboard item, not just text.
- Gojo pins the model repository revision and verifies every required file hash; Handy's Hugging Face catalog currently resolves mutable `main` revisions.
- Gojo persists neither audio nor transcript history and never shows dictated text in the success HUD. Handy supports retained recordings/history and optional remote post-processing, which do not fit Gojo's hard-local default.

Ideas adopted into the optimization backlog are staged Downloading/Verifying/Loading progress, retry/quarantine for corrupt model snapshots, microphone activity plus elapsed-time feedback, real noisy/silence fixtures, and key-up-to-visible-insertion timing. A broad model catalog, always-on capture, transcript history, cloud cleanup, and live partial text remain deferred. Handy's Canary 180M and Parakeet Unified recommendations join Moonshine as standalone-harness challengers; none enters the app until it beats the pinned baseline on Gojo's frozen corpus and privacy/reliability gates.

## Parrot reference review

Gojo's terminal insertion path was compared against [`digimata/parrot`](https://github.com/digimata/parrot). Parrot posts UTF-16 strings as Unicode key-down and key-up events at `.cgSessionEventTap` with a nil event source. Gojo adopts that delivery mechanism, but keeps its own stricter target policy: only reviewed AX-opaque bundle IDs can use it, the captured process and window are checked before every chunk, extended grapheme clusters are never split, and partial delivery is reported explicitly.
