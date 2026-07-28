#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-unicode-typing-regression.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$ROOT"

sources=(
  Gojo/WindowManagement/WindowTargetResolver.swift
  tests/dictation_unicode_typing_regression.swift
)

if [[ -f Gojo/Dictation/DictationUnicodeTextInjector.swift ]]; then
  sources=(
    Gojo/WindowManagement/WindowTargetResolver.swift
    Gojo/Dictation/DictationUnicodeTextInjector.swift
    tests/dictation_unicode_typing_regression.swift
  )
fi

swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  "${sources[@]}" \
  -o "$binary_path"
"$binary_path"

helper_source="GojoXPCHelper/GojoXPCHelper.swift"
client_source="Gojo/XPCHelperClient/XPCHelperClient.swift"

grep -Fq "case applicationUnicode" "$helper_source"
grep -Fq '"error": "applicationUnicodeRequired"' "$helper_source"
grep -Fq "opaqueTextTargetKind(" "$helper_source"
grep -Fq "guardedUnicodeTypingBundleIDs" "$helper_source"
grep -Fq "insertUnicode(" "$client_source"
grep -Fq '"method": "application-unicode"' "$client_source"
grep -Fq "DictationUnicodeTextInjector.post(" "$client_source"
grep -Fq '"partialInsertion": true' "$client_source"
grep -Fq '"partialInsertion"' "Gojo/Dictation/GojoDictationService.swift"
grep -Fq "isTargetProcessFrontmost(target.pid)" "$client_source"
grep -Fq "isCapturedWindowFrontmost(" "$client_source"
