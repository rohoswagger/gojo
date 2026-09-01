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

require_match \
  Gojo/Dictation/GojoDictationService.swift \
  'DictationTranscriberRouter,\s*S1MiniDictationPolisher,\s*XPCTextInserter' \
  "the production cleanup stage must use the local S1-mini adapter"

require_match \
  Gojo/Dictation/S1MiniDictationPolisher.swift \
  'func\s+polish\(_\s+transcript:\s+String\).*?let\s+correctedRaw\s*=\s*S1MiniVocabularyPipeline\.prepare.*?guard\s+enabledProvider\(\),\s*await\s+store\.isInstalled\(\)\s+else\s*\{\s*return\s+correctedRaw\s*\}' \
  "cleanup must fall back to deterministic local vocabulary when S1-mini is disabled or unavailable"

require_order \
  Gojo/Dictation/S1MiniDictationPolisher.swift \
  'func\s+install\(\)\s+async\s+throws' \
  'URLSession\.shared\.download' \
  "S1-mini network access must be confined to the explicit install path"

require_match \
  Gojo/Dictation/DictationModels.swift \
  'static\s+let\s+sha256\s*=\s*"3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634"' \
  "S1-mini downloads must be pinned to the published Q4_K_M SHA-256"

require_match \
  Gojo/Dictation/S1MiniDictationPolisher.swift \
  'var\s+reachedEndToken\s*=\s*false.*?llama_vocab_is_eog.*?reachedEndToken\s*=\s*true.*?guard\s+reachedEndToken\s+else\s*\{.*?throw\s+S1MiniPolisherError\.inferenceFailed' \
  "S1-mini cleanup must reject output truncated by its generation budget"

require_match \
  Gojo/Dictation/GojoDictationService.swift \
  'func\s+setCleanupEnabled\(_\s+enabled:\s*Bool\)\s*\{\s*guard\s+s1MiniOperation\s*==\s*nil,\s*!enabled\s*\|\|\s*s1MiniInstalled\s*else\s*\{\s*return\s*\}' \
  "cleanup preference changes must be rejected while S1-mini is installing or removing"

require_match \
  Gojo/components/Settings/SettingsView.swift \
  'Toggle\("Polish English dictated text".*?\.disabled\(\s*!dictation\.s1MiniInstalled\s*\|\|\s*dictation\.s1MiniOperation\s*!=\s*nil\s*\)' \
  "the cleanup toggle must remain disabled for the full S1-mini operation"

require_match \
  Gojo/Dictation/GojoDictationService.swift \
  'guard\s+hasVerifiedOpenRouterModel,\s*availableOpenRouterModels\.contains.*?supportsTranscription' \
  "cloud dictation must require a live catalog-confirmed transcription model"

require_match \
  Gojo/Info.plist \
  'Audio stays on your Mac with local models, or is sent to your selected cloud transcription provider when you enable cloud dictation\.' \
  "microphone privacy copy must distinguish local and explicitly enabled cloud transcription"

echo "dictation-offline-policy-pass"
