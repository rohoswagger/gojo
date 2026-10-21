#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-model-settings.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$repo_root"
artifact_dir="${GOJO_SETTINGS_RENDER_DIR:-$repo_root/.omx/settings-contrast/render}"
mkdir -p "$artifact_dir"

python3 - "$scratch_dir/fixture.swift" <<'PY'
from pathlib import Path
import sys

source = Path('Gojo/components/Settings/SettingsView.swift').read_text()
start = source.index('                Section {', source.index('            if dictation.selectedProvider == .local {'))
end = source.index('\n            }\n\n            experienceSection', start)
section = source[start:end]
assert 'Button(role: .destructive)' in section
assert section.count('.disabled(modelButtonDisabled(for: model.id))') == 1, 'Model actions must retain the production disabled predicate'
assert '.foregroundStyle(modelButtonDisabled(for: model.id) ? Color.secondary : Color.primary)' in section, 'Model action labels must use semantic enabled and disabled colors'
assert '.foregroundStyle(!dictation.canChangeModel ? Color.secondary : Color.primary)' in section, 'Remove labels must use semantic enabled and disabled colors'
assert '.tint(.primary)' in section, 'Action tint must adapt to the appearance'
assert section.count('.disabled(!dictation.canChangeModel)') == 1, 'Remove must retain its production disabled predicate'
helpers_start = source.index('    private func modelButtonTitle')
helpers_end = source.index('\n}\n\nfunc comingSoonTag', helpers_start)
fixture = Path('tests/dictation_model_settings_regression.swift').read_text()
for marker, replacement in [
    ('/* PRODUCTION_MODEL_SECTION */', section),
    ('/* PRODUCTION_MODEL_HELPERS */', source[helpers_start:helpers_end]),
    ('/* PRODUCTION_EXPERIENCE_SECTIONS */', source[source.index('    private var practiceSection:'):source.index('    private var dictationProviderBinding:')]),
]:
    assert fixture.count(marker) == 1
    fixture = fixture.replace(marker, replacement)
Path(sys.argv[1]).write_text(fixture)
PY

swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationPracticeField.swift \
  "$scratch_dir/fixture.swift" -o "$scratch_dir/model-settings-render"
"$scratch_dir/model-settings-render" "$artifact_dir"
