#!/usr/bin/env bash
set -euo pipefail

state="${1:-idle}"
case "$state" in
  idle|listening|preparing|pausing|paused|processing|success|error|permission|recovery|end|inspect|snapshot|fade-test) ;;
  *) echo "Usage: $0 [idle|listening|preparing|pausing|paused|processing|success|error|recovery|end|inspect|snapshot|fade-test]" >&2; exit 2 ;;
esac

swift - "$state" <<'SWIFT'
import Foundation

DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("rohoswagger.gojo.dictation-panel-preview"),
    object: nil,
    userInfo: ["state": CommandLine.arguments[1]],
    deliverImmediately: true
)
SWIFT
