# macOS dictation parity review

Reviewed official documentation on October 13, 2026. Competitor behavior below is documented, not independently tested. Gojo behavior is grounded in the current source. Verification of the new voice mode is recorded separately.

## Pause submission is a separate requirement

Wispr Flow documents hold/release and hands-free toggle. It inserts completed dictation after stopping. Its silence warnings do not establish automatic submission after a natural pause. See [hands-free](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free), [microphone troubleshooting](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues), and [what Flow does](https://docs.wisprflow.ai/articles/2772472373-what-is-flow).

Superwhisper documents explicit recording stop plus realtime preview with supported models. Preview does not establish automatic insertion into another app after each pause. Its silence-removal setting filters quiet audio. See [realtime](https://superwhisper.com/docs/common-issues/realtime), [recording window](https://superwhisper.com/docs/get-started/interface-rec-window), and [essential settings](https://superwhisper.com/docs/get-started/essential-settings).

Gojo's requested voice mode keeps capture active, commits speech after a pause, and inserts utterances in order. It is a product requirement, not a verified claim about either competitor.

## Capability comparison

| Capability | Wispr Flow | Superwhisper | Gojo before this change |
| --- | --- | --- | --- |
| Activation | Hold, hands-free toggle, custom keyboard and mouse bindings | Toggle, hold, per-mode bindings | Fixed Control+Option, hold or tap |
| Continuous pause insertion | Not established in current docs | Not established in current docs | Missing |
| Realtime preview | Completed text after stop | Supported Nova, Scribe, and Parakeet models | Missing; whole-buffer adapters |
| Recognition | Cloud processing | Local and cloud models | Four local models and OpenRouter |
| Cleanup | Fillers, grammar, punctuation, formatting, Backtrack | Task-specific AI modes; raw-text fallback | Optional local S1-mini, safe raw fallback |
| Styles and app context | App/site categories and surrounding-text context | Per-mode app/site rules and optional selection/clipboard context | Three global styles; no app context |
| Custom commands | Command Mode and Transforms beta | Super formatting commands and Custom modes | Missing |
| Vocabulary and snippets | Dictionary, learned spelling, formatted snippets | Vocabulary hints and deterministic replacements | Deterministic Unicode-aware replacements, 250 entries |
| Languages | 100+, detection per session | Model-dependent; translation options | Parakeet v3 multilingual; Whisper hardcodes English |
| History and retry | Original/formatted text, retained audio, retry, paste-last | Local originals, AI output, audio, search, reprocess | Missing |
| Microphone control | Input selection and test, disconnect recovery | Preferred/excluded inputs and system audio | System-default AVAudioEngine input |
| Long sessions | 19-minute warning, 20-minute finalization | Long recordings depend on model/resources | 120-second capture watchdog |
| Accessibility | Vendor-tested VoiceOver with disclosed gaps | Vendor claims VoiceOver/switch support | Permission checks; notch activity hidden from AX |

## Sources for each capability

- Activation and permissions: [Wispr shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts), [Wispr installation](https://docs.wisprflow.ai/articles/7682075140-how-to-install-wispr-flow-on-mac), [Superwhisper settings](https://superwhisper.com/docs/get-started/essential-settings), [Superwhisper quickstart](https://superwhisper.com/docs/get-started/quickstart).
- Cleanup and instructions: [Wispr formatting and Backtrack](https://docs.wisprflow.ai/articles/5373093536-How-do-I-use-Smart-Formatting-%26-Backtrack), [Wispr commands](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode), [Wispr Transforms](https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta), [Superwhisper built-in modes](https://superwhisper.com/docs/modes/built-in), [Superwhisper custom modes](https://superwhisper.com/docs/modes/custom).
- Context and style: [Wispr context](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness), [Wispr styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles), [Superwhisper modes](https://superwhisper.com/docs/modes/modes), [Superwhisper context timing](https://superwhisper.com/docs/common-issues/context).
- Vocabulary and languages: [Wispr snippets](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets), [Wispr languages](https://docs.wisprflow.ai/articles/3191899797), [Superwhisper vocabulary](https://superwhisper.com/docs/get-started/interface-vocabulary), [Superwhisper voice models](https://superwhisper.com/docs/models/voice).
- Recovery and hardware: [Wispr retry](https://docs.wisprflow.ai/articles/2503460374-Retry-failed-transcriptions), [Superwhisper history](https://superwhisper.com/docs/get-started/history), [Superwhisper microphones](https://superwhisper.com/docs/common-issues/microphone-and-system-audio), [Wispr session limit](https://docs.wisprflow.ai/articles/4841123325-longer-dictation-sessions-now-up-to-20-minutes).
- Accessibility: [Wispr accessibility](https://docs.wisprflow.ai/articles/3941699399-keyboard-and-screen-reader-accessibility-in-wispr-flow), [Superwhisper accessibility](https://superwhisper.com/for-accessibility).

## Privacy and latency need separate proof

Wispr uses cloud processing. Model-improvement opt-out, cloud storage, context, and local retention are separate controls. Its older Privacy Mode wording should not replace the newer [data controls](https://wisprflow.ai/data-controls) and [current settings](https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow).

Superwhisper's offline behavior depends on both recognition and cleanup models. Pairing local recognition with cloud cleanup still sends text externally. See [language models](https://superwhisper.com/docs/models/language) and [sensitive data](https://superwhisper.com/docs/security/sensitive-data). Gojo's local recognition and S1-mini cleanup can run locally; selecting OpenRouter sends audio to that provider.

Neither source set establishes a numeric macOS latency SLA. Gojo cannot claim speed parity without comparable hardware, model, warm/cold, and network measurements. Pause timeout is one part of total delay; inference, cleanup, and insertion add to it.

## Verification contract

The first voice-mode unit must prove silence produces no request, shorter pauses stay in one utterance, sustained pauses commit exactly once, and stop flushes once. It must capture speech while an earlier inference is blocked, serialize insertions, bound pending audio, reject stale completions after cancel, and preserve target safety. Existing hold/tap tests must remain green.

Broader parity remains open until app rules, commands, language selection, realtime preview, history/retry, and input-device handling have explicit behavior tests. A matrix entry is not evidence that a feature works.

## Implemented voice mode

Settings > Dictation now offers a compact floating workspace and Voice mode. Hold Control+Option for push-to-talk. Press Space while holding both keys, or use the microphone icon, to start locked voice mode. A speech pause commits an utterance while capture continues during transcription and cleanup. The waveform pauses the microphone; the play icon resumes it. Repeat Control+Option then Space, or use the checkmark, to finish and drain the final utterance. Escape or the cross cancels pending work. Pause choices are 0.6, 0.9, and 1.5 seconds. Voice mode has no automatic session timeout; screen lock and sleep cancel it.

The existing controller owns one bounded queue and serial insertion. Capture classifies raw mono energy in 10 ms frames, retains 200 ms of preroll, and splits sustained speech at 20 seconds. Normalization runs outside the audio tap. Voice mode captures an independent target lease at each phrase boundary and inserts serially. Same-field identities preserve spacing between phrases. A later focus change cannot redirect a phrase into another field. Uninserted text remains in a copyable recovery buffer, with a soft limit that finishes capture and drains accepted work. Follow-focus capture rejects opaque targets that lack verifiable field identity. Push-to-talk one-shot and fallback behavior is preserved.

The detector uses a fixed RMS threshold of 0.004. Sustained noise above that threshold can be classified as speech. Quiet speech below it can be missed. This implementation does not establish neural voice-activity detection, realtime transcript preview, or competitor speed parity. Some opaque editors cannot safely support automatic focus-following. Their phrases are retained for copying; window identity alone is insufficient to authorize a delayed phrase.

A new microphone harness requires two ordered, recognizable insertions before Stop and checks that Stop does not duplicate them. Run `make test-dictation-voice-mode-live` after authorizing the Debug app. The current environment denied Accessibility, so this live check skipped with exit code 77. The native settings controls were inspected directly, including changing the pause duration and restoring the original preferences.

Deterministic tests cover pause timing at 16, 44.1, and 48 kHz, silence suppression, short-pause merging, capacity errors, duration splits, short final tails, ordered insertion during blocked inference, stop flush, cancellation, startup races, retained destination release, both mode-switch restart directions, shortcut rearming, and session-limit flush. Full integrated verification uses `make test-dictation`.

## Work still needed for broader parity

The immediate continuous dictation loop is implemented. Broader macOS parity remains open for custom shortcuts, app-specific styles and context, commands and custom instructions, history and retry, selectable input devices and disconnect recovery, user-facing language/translation controls, realtime preview, and broader screen-reader and keyboard auditing of the floating controls. Those are separate features that need acceptance tests. Mobile, meeting transcription, account sync, billing, and enterprise administration are outside this change.

## Decisions from poteto mode

- Experience First selected uninterrupted capture so speaking can continue during inference.
- Model the Domain separated capture lifetime from ordered utterance work.
- Foundational Thinking established sample and destination ownership before the settings control.
- Laziness Protocol kept one controller and shared transcription and insertion paths.
- Separate Before Serializing Shared State assigned each implementation file to one owner and isolated audio accumulation from inference.
- Never Block on the Human selected an opt-in mode and a reversible 0.9-second default.
- Sequence Work into Verifiable Units preserved the baseline, then checked segmentation, controller behavior, integration, and the live boundary.
- Test Behavior, Not Implementation used literal inserted text, forced inference delays, and real sample boundaries.
- Prove It Works required a real build and UI inspection, reproduced reviewer findings, and labeled unauthorized live insertion as unverified.
