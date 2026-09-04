#!/usr/bin/env bash
set -euo pipefail

monitor="Gojo/Dictation/DictationModifierHotKeyMonitor.swift"

fail() {
    printf 'Assertion failed: %s\n' "$1" >&2
    exit 1
}

[[ -f "$monitor" ]] || fail "missing $monitor"

if grep -q 'CFRunLoopGetMain()' "$monitor"; then
    fail "dictation event tap must not be hosted on the main run loop"
fi

if grep -q 'MainActor.assumeIsolated' "$monitor"; then
    fail "event tap callback must not assume MainActor isolation"
fi

grep -q 'Thread {' "$monitor" \
    || fail "event tap host must create a dedicated thread"
grep -q 'CFRunLoopRun()' "$monitor" \
    || fail "event tap host must keep a dedicated run loop alive"
grep -q 'thread.qualityOfService = .userInteractive' "$monitor" \
    || fail "event tap host thread must run at interactive priority"
grep -q 'DictationModifierEventTapHost' "$monitor" \
    || fail "event tap host type is missing"
grep -q 'DictationModifierEventTapInput: Sendable' "$monitor" \
    || fail "callback must decode into a small Sendable semantic input"

ruby <<'RUBY'
monitor = "Gojo/Dictation/DictationModifierHotKeyMonitor.swift"
source = File.read(monitor)

callback = source[/private func dictationModifierEventTapCallback\([\s\S]*?\n\}/]
abort("Assertion failed: missing dictation event tap callback") unless callback
abort("Assertion failed: callback must not call monitor methods directly") if callback.include?("handleEventTapInput")
abort("Assertion failed: callback must not create Tasks") if callback.include?("Task {")

disabled_case = callback[/case \.tapDisabledByTimeout, \.tapDisabledByUserInput:[\s\S]*?\n\n/]
abort("Assertion failed: missing disabled-tap callback path") unless disabled_case
enable_index = disabled_case.index("context.reenableEventTapImmediately()")
forward_index = disabled_case.index("context.forward(.tapDisabled)")
abort("Assertion failed: disabled-tap path must re-enable immediately") unless enable_index
abort("Assertion failed: disabled-tap path must forward disabled semantic input") unless forward_index
abort("Assertion failed: disabled-tap path must re-enable before forwarding") unless enable_index < forward_index

create = source[/private func createEventTap\(\) async -> EventTapStartResult[\s\S]*?private func handleEventTapInput/]
abort("Assertion failed: missing async createEventTap bridge") unless create
abort("Assertion failed: callback bridge must enqueue onto DispatchQueue.main") unless create.include?("DispatchQueue.main.async")
abort("Assertion failed: callback bridge must generation-gate forwarded inputs") unless source.include?("guard generation == eventTapGeneration else { return }")

forward_count = source.scan(/forwardInput\(generation, input\)/).length
abort("Assertion failed: semantic inputs must use one forwarding channel") unless forward_count == 1
RUBY

printf 'dictation event tap host regression passed\n'
