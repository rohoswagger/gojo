#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
sdk_products="${GOJO_DICTATION_SDK_BUILD_PRODUCTS:-$PWD/.build/DerivedData/Build/Products/Debug}"
if [[ ! -f "$sdk_products/WhisperKit.o" || ! -f "$sdk_products/ArgmaxCore.o" ]]; then
  echo "Build the pinned SDK dependencies or set GOJO_DICTATION_SDK_BUILD_PRODUCTS to their existing products." >&2
  exit 2
fi
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gojo-recognition-lifecycle.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
python3 - "$test_directory" <<'PY'
from pathlib import Path
import re
import sys

root = Path('Gojo/Dictation')
output = Path(sys.argv[1])
for filename, boundary in [
    ('WhisperKitDictationTranscriber.swift', '    private static func cachedModelFolderKey'),
    ('ParakeetUnifiedDictationTranscriber.swift', '    private static let repository'),
    ('ParakeetV3DictationTranscriber.swift', '    private static let repository'),
    ('BarkDictationTranscriber.swift', '    private func cachedModelFolder'),
]:
    source = (root / filename).read_text()
    prefix = source[:source.index(boundary)]
    prefix = re.sub(r'^@preconcurrency import (ArgmaxCore|FluidAudio|WhisperKit)\n', '', prefix, flags=re.M)
    helpers = '''
    private static func cachedModelFolder() -> URL? { URL(fileURLWithPath: "/tmp") }
    private static func clearCachedModelFolder() {}
    private static let modelSHA256: [String: String] = [:]
    private static func validateModel(at folder: URL) throws {}
    private static func removeCachedModel() throws { SDKProbe.deletedInstalledFiles() }
    private func resolvePinnedModelFolder(allowDownload: Bool, onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        onProgress(0.42)
        onProgress(1)
        return URL(fileURLWithPath: "/tmp")
    }
'''
    if filename.startswith('WhisperKit'):
        helpers = '''
    private static func cachedModelFolder(for model: WhisperDictationModel) -> URL? {
        URL(fileURLWithPath: "/tmp")
    }
    private static func removeCachedModel(_ model: WhisperDictationModel) throws {
        SDKProbe.deletedInstalledFiles()
    }
    private static func resolvePinnedModelFolder(
        for model: WhisperDictationModel, allowDownload: Bool,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        onProgress(0.42)
        onProgress(1)
        return URL(fileURLWithPath: "/tmp")
    }
'''
    if filename.startswith('ParakeetV3'):
        helpers += '''
    private static func prepareFluidAudioLayout(for snapshot: URL) throws -> URL { snapshot }
    private static func loadModelsOffline(from folder: URL) async throws -> FakeAsrModels {
        await SDKProbe.shared.load(.parakeetV3Multilingual)
        return FakeAsrModels()
    }
'''
    if filename.startswith('Bark'):
        helpers = '''
    private func cachedModelFolder() -> URL? { URL(fileURLWithPath: "/tmp") }
    private func clearCachedModelFolder() {}
    private func validateModel(at folder: URL) throws {}
    private func removeCachedModel() throws { SDKProbe.deletedInstalledFiles() }
    private func resolvePinnedModelFolder(allowDownload: Bool, onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        onProgress(0.42)
        onProgress(1)
        return URL(fileURLWithPath: "/tmp")
    }
'''
    error = re.search(r'^enum (WhisperKitDictationError|ParakeetDictationError|ParakeetV3DictationError|BarkDictationError):', source, re.M)
    if error is None:
        raise SystemExit(f'Missing production error enum in {filename}')
    (output / filename).write_text('import WhisperKit\n' + prefix + helpers + '}\n' + source[error.start():])
PY
swiftc -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macosx14.0" \
  -I "$sdk_products" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationProtocols.swift \
  Gojo/Dictation/DictationModelPreparation.swift \
  Gojo/Dictation/DictationModelValidationCache.swift \
  Gojo/Dictation/LocalDictationTranscriber.swift \
  "$test_directory/WhisperKitDictationTranscriber.swift" \
  "$test_directory/ParakeetUnifiedDictationTranscriber.swift" \
  "$test_directory/ParakeetV3DictationTranscriber.swift" \
  "$test_directory/BarkDictationTranscriber.swift" \
  tests/dictation_recognition_lifecycle_regression.swift \
  "$sdk_products/WhisperKit.o" "$sdk_products/ArgmaxCore.o" \
  -o "$test_directory/regression"
"$test_directory/regression"
