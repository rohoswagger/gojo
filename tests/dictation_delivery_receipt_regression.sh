#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-delivery-receipt.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT
swiftc -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macosx14.0" \
 Gojo/Dictation/DictationModels.swift Gojo/Dictation/DictationSessionPlan.swift Gojo/Dictation/DictationDeliveryWriter.swift tests/dictation_delivery_receipt_regression.swift -o "$binary_path"
"$binary_path"
