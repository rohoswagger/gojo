#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

require_match() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! perl -0we 'my $pattern = shift; my $source = <>; exit($source =~ /$pattern/s ? 0 : 1)' \
    "$pattern" "$file"; then
    echo "offline policy regression failed: $description" >&2
    echo "  file: $file" >&2
    exit 1
  fi
}

require_order() {
  local file="$1"
  local first="$2"
  local second="$3"
  local description="$4"

  if ! perl -0we '
    my ($first, $second) = @ARGV;
    my $source = <STDIN>;
    my $first_index = $source =~ /$first/s ? $-[0] : -1;
    my $second_index = $source =~ /$second/s ? $-[0] : -1;
    exit($first_index >= 0 && $second_index >= 0 && $first_index < $second_index ? 0 : 1);
  ' "$first" "$second" < "$file"; then
    echo "offline policy regression failed: $description" >&2
    echo "  file: $file" >&2
    exit 1
  fi
}

require_match \
  Gojo/Dictation/DictationModels.swift \
  'enum\s+DictationModelRequest:.*?case\s+settingsDownload.*?case\s+transcription.*?var\s+allowsDownload:\s*Bool\s*\{\s*self\s*==\s*\.settingsDownload\s*\}' \
  "only Settings-initiated model requests may download"

require_match \
  Gojo/Dictation/WhisperKitDictationTranscriber.swift \
  'private\s+func\s+loadSelectedModel\(\)\s+async\s+throws\s+->\s+WhisperKit.*?resolvePinnedModelFolder\(\s*for:\s*requestedModel,\s*allowDownload:\s*DictationModelRequest\.transcription\.allowsDownload\s*\).*?WhisperKitConfig\([^)]*download:\s*false[^)]*\)' \
  "Whisper transcription loads must use the no-download request policy and disable WhisperKit downloads"

require_order \
  Gojo/Dictation/WhisperKitDictationTranscriber.swift \
  'guard\s+allowDownload\s+else\s*\{\s*throw\s+WhisperKitDictationError\.modelNotInstalled\s*\}' \
  'let\s+hub\s*=\s*HubApiWrapper' \
  "Whisper resolver must reject transcription requests before creating a Hub API client"

require_match \
  Gojo/Dictation/ParakeetUnifiedDictationTranscriber.swift \
  'init\(\)\s*\{\s*ModelHub\.offlineMode\s*=\s*true\s*\}' \
  "Parakeet Unified must force FluidAudio offline mode on initialization"

require_match \
  Gojo/Dictation/ParakeetUnifiedDictationTranscriber.swift \
  'private\s+func\s+loadManager\(\)\s+async\s+throws\s+->\s+UnifiedAsrManager.*?resolvePinnedModelFolder\(\s*allowDownload:\s*DictationModelRequest\.transcription\.allowsDownload\s*\).*?manager\.loadModels\(from:\s*modelFolder\)' \
  "Parakeet Unified transcription loads must use the no-download request policy"

require_order \
  Gojo/Dictation/ParakeetUnifiedDictationTranscriber.swift \
  'guard\s+allowDownload\s+else\s*\{\s*throw\s+WhisperKitDictationError\.modelNotInstalled\s*\}' \
  'let\s+hub\s*=\s*HubApiWrapper' \
  "Parakeet Unified resolver must reject transcription requests before creating a Hub API client"

require_match \
  Gojo/Dictation/ParakeetV3DictationTranscriber.swift \
  'init\(\)\s*\{\s*ModelHub\.offlineMode\s*=\s*true\s*\}' \
  "Parakeet v3 must force FluidAudio offline mode on initialization"

require_match \
  Gojo/Dictation/ParakeetV3DictationTranscriber.swift \
  'private\s+func\s+loadManager\(\)\s+async\s+throws\s+->\s+AsrManager.*?resolvePinnedModelFolder\(\s*allowDownload:\s*DictationModelRequest\.transcription\.allowsDownload\s*\).*?loadModelsOffline\(from:\s*modelFolder\)' \
  "Parakeet v3 transcription loads must use the no-download request policy"

require_match \
  Gojo/Dictation/ParakeetV3DictationTranscriber.swift \
  'private\s+static\s+func\s+loadModelsOffline\(from\s+modelFolder:\s+URL\)\s+async\s+throws\s+->\s+AsrModels\s*\{\s*ModelHub\.offlineMode\s*=\s*true\s*.*?AsrModels\.load\(' \
  "Parakeet v3 must re-assert FluidAudio offline mode immediately before loading models"

require_order \
  Gojo/Dictation/ParakeetV3DictationTranscriber.swift \
  'guard\s+allowDownload\s+else\s*\{\s*throw\s+WhisperKitDictationError\.modelNotInstalled\s*\}' \
  'let\s+hub\s*=\s*HubApiWrapper' \
  "Parakeet v3 resolver must reject transcription requests before creating a Hub API client"

require_match \
  Gojo/Dictation/LocalDictationTranscriber.swift \
  'func\s+transcribe\(_\s+audio:\s+DictationAudio\)\s+async\s+throws\s+->\s+String\s*\{(?!.*install\()' \
  "the router transcription path must not call install"

echo "dictation-offline-policy-pass"
