#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
from pathlib import Path
import re
host = Path('GojoXPCHelper/DictationHotkeyTapService.swift').read_text()
monitor = Path('Gojo/Dictation/DictationModifierHotKeyMonitor.swift').read_text()
client = Path('Gojo/XPCHelperClient/XPCHelperClient.swift').read_text()
main = Path('GojoXPCHelper/main.swift').read_text()
helper = Path('GojoXPCHelper/GojoXPCHelper.swift').read_text()
assert 'CGEvent.tapCreate(' not in monitor, 'The sandboxed app must not own the intercepting tap'
assert 'CFRunLoopGetMain()' not in host
assert 'MainActor.assumeIsolated' not in host
assert 'Thread {' in host and 'CFRunLoopRun()' in host
assert 'thread.qualityOfService = .userInteractive' in host
callback = re.search(r'private func dictationModifierEventTapCallback\([\s\S]*?\n\}', host).group()
assert 'handleEventTapInput' not in callback and 'Task {' not in callback
start = callback.index('case .tapDisabledByTimeout, .tapDisabledByUserInput:')
disabled = callback[start:callback.index('case .flagsChanged:', start)]
assert disabled.index('context.reenableEventTapImmediately()') < disabled.index('context.forward(.tapDisabled(')
assert 'context.consumeSpace(type: type, event: event)' in callback
assert 'suppressSpaceUp' in host and 'keyboardEventAutorepeat' in host
assert 'deliveryQueue.async' in host, 'Tap delivery must not wait on the app'
assert 'guard desiredEnabled, let contiguous = eventGate.accept(event)' in monitor
assert 'connectionGeneration.owns(generation)' in client
assert 'conn.exportedObject = receiver' in client
assert 'newConnection.remoteObjectInterface = NSXPCInterface(with: GojoXPCHelperInputProtocol.self)' in main
assert 'exportedObject.attach(connection: newConnection)' in main
assert main.count('exportedObject?.connectionDidEnd()') == 2
assert 'remoteObjectProxyWithErrorHandler({ _ in acknowledge(false) })' in helper, 'Reverse-send errors must fail the current delivery'
assert 'reenabled: reenabled, with: { acknowledge(true) })' in helper, 'App reply must acknowledge successful delivery'
assert 'DistributedNotificationCenter' not in host, 'Dictation input must stay on the authenticated connection'
assert 'DispatchSemaphore' not in host, 'Tap diagnostics must not block the caller thread'
PY
bash tests/dictation_helper_lease_regression.sh
printf 'dictation event tap host structural and injected lifecycle regressions passed\n'

grep -Fq 'monitor started chord=control+option' Gojo/Dictation/DictationModifierHotKeyMonitor.swift \
  || fail "live dictation harnesses require the actual-ready startup marker"
