# Dictation permission hardening

The approved six-step change separates OS permission, helper connectivity and actual input readiness. It preserves the helper's strict caller requirement and adds no dependencies.

## Final design

1. `scripts/dev.py` builds with a validated team signing identity, checks both signatures and performs a real helper handshake. Both verification and ordinary launch use explicit-path LaunchServices. The Release probe runs before normal application initialization and returns nonce-bound JSON through inherited stdout. It cannot open a supplied result path.
2. Typed helper, Accessibility and shortcut states replace false-on-transport-error permission decisions in Settings, onboarding and dictation. The existing intercepting event-tap host moves to the authenticated helper. The app keeps gesture and session policy. Reverse XPC sends semantic timing events, never raw key content.
3. Monitor-owned reconciliation survives canceled view tasks. Activation, wake and reconnect recover passively. Explicit Accessibility setup can return to a retryable state. Leases, callback acknowledgements, pending events and stopped requests have bounded lifetimes or sizes.
4. Settings and capture share one unresolved microphone authorization task. Capture cancellation does not cancel the OS decision. Every capture/resume boundary rechecks permission, and stale session replies cannot start capture or insert text.
5. Listening requires a delivered audio buffer. One bounded rebuild handles missing input. Settings separates permission from readiness and provides an explicit microphone test with no transcription or insertion. A shared admission reservation prevents the test from racing accepted dictation startup.
6. `make test-permissions` runs permission, capture, controller, helper, service-admission, rendered Settings and signing regressions in CI. Release tooling requires the signed helper handshake before notarization.

## Review and verification

Independent microphone review reproduced two diagnostic admission windows. Both are covered by failing old-guard mutations and passing production-method tests. Claude Opus 5.5 security review reproduced canceled Settings refresh disabling the shortcut. That defect and the probe boundary findings were corrected. The second security review approved with follow-ups. Claude Opus 5.5 approved the final incremental fixes in a third pass with no blocking findings. Its retry-lifetime, HUD-preference and CI-coverage findings received small fixes and new regression proof before the final rerun.

The final source manifests and detailed local logs are under `.omx/permissions/`. Signed Debug and Release builds, Debug static analysis, actual Release entitlements and both LaunchServices helper handshakes passed. `make test-permissions test-accessibility-menu test-release-signing` passed. All 31 signing regressions passed against the actual signed Debug app. Credential-free CI deliberately skips the certificate-dependent positive artifact test.

Five Settings states were rendered from the production SwiftUI section and checked with OCR. This proves component labels and layout. It does not prove desktop navigation or fresh OS dialogs. Capture and cancellation checks use deterministic fake engines, not physical recordings.

## Evidence limits and runtime

The final LaunchServices handshakes report a healthy helper and `accessibilityAuthorized=false`. Earlier direct-executable results reported true and are superseded as evidence of Gojo's grant. They prove transport only. Gojo still needs the user's one-time Accessibility approval. Physical keybind, real microphone routing and fresh privacy prompts remain unverified.

The old task-owned dev processes were replaced during implementation. At final handoff the earlier prototype was no longer running, and the supported launcher refused to start over an existing `/Applications/Gojo.app` instance. That installed instance was left alone. The verified Debug bundle remains at `/tmp/gojo-permission-build/Build/Products/Debug/Gojo.app`.

## Remaining minor tradeoffs

Onboarding still treats a single helper timeout as an unavailable helper and ends that setup attempt. The user can retry. If macOS shows no Accessibility prompt, the pending state ends on app reactivation. Open Accessibility Settings stays available.

A four-second reverse-callback acknowledgement deadline invalidates the owning helper connection. This bounds an unresponsive client but can cancel dictation or insertion during an app main-thread stall. Semantic key-down timing crosses XPC while idle because existing tap-to-talk and voice-stop gestures require it. Key content never crosses. After a HUD startup transport error, interception waits for an Accessibility change or a preference toggle. The saved setting is preserved. An active shortcut retains its last confirmed readiness while status checks time out, so a connected but wedged helper can temporarily appear ready during retries.

The runtime snapshot cannot establish who launched the installed app or why the prototype exited. The final launcher refused the collision and did not stop that installed instance. No final dev build is running.

There was no permission database reset, silent approval, paid inference, release, version tag, deployment or merge. The original dirty checkout was not edited. The append-only TSV records decisions and corrections.
