# Pre-release cleanup

Base: `7f0f97d`, after PRs #69, #70 and #71. The original working checkout and its unrelated dictation changes were left alone. No app version, tag, signing identity, permission, deployment or published artifact changed.

The audit covered the tracked native UI/lifecycle, dictation/XPC, utility features, website and release tooling. Changes remove unreachable code and reuse the existing window frame calculator, history operation and release literal. They add no dependencies. The website also drops its unused motion dependency.

Native PR: https://github.com/rohoswagger/gojo/pull/72. Website/tooling PR: https://github.com/rohoswagger/gojo/pull/73. They are independent main-based changes.

## Review units

- Native UI: delete ten unreachable files and unused members, retaining dynamic selectors, observers, previews and preference values.
- Dictation: remove the unconstructed OpenRouter cleanup implementation and internal unused aliases. Keep the live S1 Mini/transcription path, XPC protocol contracts, application-paste compatibility and audio lifecycle.
- Utilities: remove dead members and duplicate forwarding code. Use the existing frame calculator and restore-history operation, protected by the window-history regression in `make test-window`.
- Website: correct stale download facts to the already-published 1.6.0 DMG, share the literal release module with the verifier, remove fourteen unreachable components and their exclusive CSS/helpers/dependency.
- Release tooling: remove unused XML serializer setup after capturing literal appcast CLI output in a deterministic regression.

## Verification

The native Debug build and static analyzer pass. Local dictation, window/history, Windows UI/focus, flux, Alt-Tab, search, accessibility-menu, signing, notch hover/layout/paint, microphone permission and clipboard-model regressions pass. An ad-hoc signed Release build passes; its actual app bundle passes `scripts/verify-sparkle-entitlements.sh`.

The website passes frozen pnpm installation, lint, typecheck with unused checks, full build and its verifiers. All 65 exported BODY trees and 12 hydrated desktop routes match the baseline captured after the release-facts correction. The appcast CLI tests pass before and after pruning; an enclosure-length mutation fails. A mismatched native-version negative control still fails the press verifier.

The published 1.6.0 DMG measured 17,399,815 bytes with SHA-256 `65f3291ee7f613269ea550cf24dd5ab69f170f85c529771b62be3c3038a9da8a`.

The first integrated build caught a mistaken deletion of `GojoViewModel.animation`. It was restored because Shelf reads it. The corrected source passed the complete build and regression sequence. Native independent review found no unresolved correctness or comment issues.

## Retained risks and deferrals

Existing native compiler warnings remain; comparison against the baseline found no new warning categories. Tests do not exercise every native interaction, physical display, real microphone/model inference, Shelf drag, Quick Look, EventKit permission, viewport or web interactive state. Production signing, notarization, packaging and publishing were not performed.

Published preview state, the Shelf view wrapper, dragged-slot writes, Calendar fetch repetition, availability fallbacks, live cleanup-model predicates, XPC compatibility and a security-scoped folder filter remain. Their removal needs stronger behavior evidence than static reachability. Unsafe clipboard-history smoke scripts were not run against real user data.

The append-only TSV records decisions and corrections. Its `.omx/cleanup/` evidence references are local run artifacts in `/tmp/gojo-pre-release-cleanup`; commands above and committed regression scripts are the rerunnable PR evidence.

## Final review follow-up

Claude Opus 5.5 found no web/tooling code blocker, but caught an unintended app launch during inspection. Selecting Gojo by name started the installed app alongside the original dev build. The initial termination attempt did not quit it. The installed app was then quit through its menu, but the following CUA inspection apparently relaunched it under new PIDs. A fixed-PID check missed that restart. Root stopped the new processes directly without further CUA access; repeated scans by installed application path were empty while the original dev instance remained alive. This check provided no additional native UI coverage.

The review also prompted removal of remaining dead article selectors, filename/URL consistency checks for release metadata, appcast regression wiring into the existing release-signing target, and removal of stale current-version wording in the public dictation architecture record. The trail records the model-routing fallback, project record edits, dependency pruning, negative controls and retained candidates.

Claude Opus 5.5 approved the follow-up code in round two. Its remaining process-state flag was resolved by direct cleanup and repeated path-based absence checks, superseding the earlier fixed-PID claim. Both PRs are open for review. Native CI Debug, Release and signing checks passed before this audit-only update. Website CI signing passed and its builds were still in progress at the final status check; all local gates passed. No merge or tag was performed.
