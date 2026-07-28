#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS="$ROOT/scripts/benchmarks/fixtures/synthetic-dictation-corpus.jsonl"
SCORER="$ROOT/scripts/benchmarks/score_transcripts.py"
CLI="${WHISPERKIT_CLI:-}"
MODEL_PATH="${WHISPERKIT_MODEL_PATH:-$HOME/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-small.en_217MB}"
OUTPUT="${1:-$(mktemp -d "${TMPDIR:-/tmp}/gojo-whisperkit-benchmark.XXXXXX")}"

if [[ -z "$CLI" || ! -x "$CLI" ]]; then
  echo "Set WHISPERKIT_CLI to the pinned 1.0.0 whisperkit-cli executable." >&2
  exit 2
fi
if [[ ! -d "$MODEL_PATH" ]]; then
  echo "Set WHISPERKIT_MODEL_PATH to openai_whisper-small.en_217MB." >&2
  exit 2
fi

mkdir -p "$OUTPUT/audio"
while IFS= read -r row; do
  id="$(jq -r .id <<<"$row")"
  voice="$(jq -r .voice <<<"$row")"
  spoken="$(jq -r '.spoken // .reference' <<<"$row")"
  say -v "$voice" -o "$OUTPUT/audio/$id.aiff" "$spoken"
  afconvert -f WAVE -d LEI16@16000 "$OUTPUT/audio/$id.aiff" "$OUTPUT/audio/$id.wav"
  rm "$OUTPUT/audio/$id.aiff"
done < "$CORPUS"

# Warm Core ML and tokenizer caches before the three measured passes.
first_audio="$(find "$OUTPUT/audio" -name '*.wav' -print | sort | head -1)"
"$CLI" transcribe \
  --audio-path "$first_audio" \
  --model-path "$MODEL_PATH" \
  --language en --temperature 0 --temperature-fallback-count 0 \
  --use-prefill-prompt --skip-special-tokens --without-timestamps \
  --chunking-strategy vad >/dev/null

results="$OUTPUT/results.jsonl"
: > "$results"
for pass in 1 2 3; do
  report_dir="$OUTPUT/reports-$pass"
  mkdir -p "$report_dir"
  "$CLI" transcribe \
    --audio-folder "$OUTPUT/audio" \
    --model-path "$MODEL_PATH" \
    --language en --temperature 0 --temperature-fallback-count 0 \
    --use-prefill-prompt --skip-special-tokens --without-timestamps \
    --chunking-strategy vad --concurrent-worker-count 1 \
    --report --report-path "$report_dir" >/dev/null

  while IFS= read -r row; do
    id="$(jq -r .id <<<"$row")"
    reference="$(jq -r .reference <<<"$row")"
    report="$report_dir/$id.json"
    hypothesis="$(jq -r '.text | gsub("Go-jo"; "Gojo") | gsub("Go jo"; "Gojo")' "$report")"
    seconds="$(jq -r .timings.fullPipeline "$report")"
    audio_seconds="$(jq -r .timings.inputAudioSeconds "$report")"
    audio_sha="$(shasum -a 256 "$OUTPUT/audio/$id.wav" | awk '{print $1}')"
    jq -nc \
      --arg id "$id-pass-$pass" \
      --arg reference "$reference" \
      --arg hypothesis "$hypothesis" \
      --arg audio_sha256 "$audio_sha" \
      --argjson final_latency_ms "$(awk -v value="$seconds" 'BEGIN { print value * 1000 }')" \
      --argjson real_time_factor "$(awk -v value="$seconds" -v duration="$audio_seconds" 'BEGIN { print value / duration }')" \
      '{id:$id,reference:$reference,hypothesis:$hypothesis,audio_sha256:$audio_sha256,engine:"WhisperKit",engine_revision:"1.0.0",model:"small.en_217MB",model_revision:"97a5bf9bbc74c7d9c12c755d04dea59e672e3808",final_latency_ms:$final_latency_ms,real_time_factor:$real_time_factor}' \
      >> "$results"
  done < "$CORPUS"
done

python3 "$SCORER" "$results" --json > "$OUTPUT/summary.json"
cat "$OUTPUT/summary.json"
echo "results: $OUTPUT"
