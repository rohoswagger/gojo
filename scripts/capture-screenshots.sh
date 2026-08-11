#!/usr/bin/env bash
#
# Capture retina marketing screenshots for the Gojo landing page.
#
#   ./scripts/capture-screenshots.sh            # walk every shot
#   ./scripts/capture-screenshots.sh media      # redo one shot
#   ./scripts/capture-screenshots.sh --list     # show the shot list
#
# Each shot is captured interactively (drag a selection), then validated and
# normalised: true 8-bit PNG, metadata stripped, retina density enforced.
# See docs/screenshots/CAPTURE.md for the exact app state each shot needs.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/docs/screenshots"

# Open-notch strips run about 3.2:1; the settings window is about 1.17:1.
# Minimums are set from the known-good 2x captures already in docs/screenshots.
#
# name|min capture width|target aspect (w/h)|what to stage
SHOTS=(
  "dictation|1280|3.25|MISSING. Hold-to-dictate live activity mid-sentence, waveform moving"
  "display|1280|3.25|MISSING. Night Shift / brightness control open in the notch"
  "media|1280|3.25|Real track playing, art loaded, scrubber part-way through"
  "clipboard|1280|3.25|4+ entries of different kinds, one row hovered"
  "shelf|1280|3.25|3 files staged, one mid-drag if you can"
  "windows|1280|3.25|Window switcher with 4+ real apps and a live preview showing"
  "settings-dictation|1360|1.17|Settings > Dictation: models installed, status healthy"
  "settings-nightshift|1360|1.17|Settings > Night Shift: schedule and location filled in"
)

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; BLD=$'\033[1m'; RST=$'\033[0m'

die() { printf '%s%s%s\n' "$RED" "$*" "$RST" >&2; exit 1; }

command -v screencapture >/dev/null || die "screencapture not found (macOS only)"
python3 -c 'import PIL' 2>/dev/null || die "Pillow required: uv pip install pillow"

if [[ "${1:-}" == "--list" ]]; then
  printf '%s%-11s %-7s %-7s %s%s\n' "$BLD" NAME MIN-W ASPECT STAGE "$RST"
  for s in "${SHOTS[@]}"; do
    IFS='|' read -r n w a d <<<"$s"
    printf '%-11s %-7s %-7s %s\n' "$n" "$w" "$a" "$d"
  done
  exit 0
fi

mkdir -p "$OUT"

# Normalise + validate a capture in place. Fails loudly rather than shipping
# an asset that will look soft on the site.
normalise() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys, os
from PIL import Image

path, min_w, target_ar = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
im = Image.open(path)
w, h = im.size
ar = w / h

problems = []
if w < min_w:
    problems.append(f"width {w}px is below the {min_w}px retina minimum "
                    f"(capture on a retina display, or select a larger region)")
if abs(ar - target_ar) / target_ar > 0.14:
    problems.append(f"aspect {ar:.2f} is far from the target {target_ar:.2f} "
                    f"(expected about {round(h * target_ar)}x{h})")
if problems:
    print("FAIL")
    for p in problems:
        print("  - " + p)
    sys.exit(1)

# True 8-bit RGBA PNG, no EXIF, no colour-profile bloat.
im.convert("RGBA").save(path, "PNG", optimize=True)
print(f"OK {w}x{h} (displays at {w // 2}x{h // 2}) {os.path.getsize(path) // 1024}KB")
PY
}

capture_one() {
  IFS='|' read -r name min_w aspect desc <<<"$1"
  local dest="$OUT/$name.png"

  printf '\n%s%s%s  %s\n' "$BLD" "$name" "$RST" "$DIM$desc$RST"
  [[ -f "$dest" ]] && printf '%s  replacing existing %s%s\n' "$DIM" "$name.png" "$RST"

  read -r -p "  Stage it, then press ⏎ to select the region (s to skip): " reply
  [[ "$reply" == "s" ]] && { printf '%s  skipped%s\n' "$YEL" "$RST"; return 0; }

  local tmp; tmp="$(mktemp -t "gojo-$name").png"
  # -i interactive, -o no window shadow, -r no screen-scaling fixup.
  if ! screencapture -i -o -r "$tmp" || [[ ! -s "$tmp" ]]; then
    printf '%s  cancelled%s\n' "$YEL" "$RST"; rm -f "$tmp"; return 0
  fi

  if out="$(normalise "$tmp" "$min_w" "$aspect")"; then
    mv "$tmp" "$dest"
    printf '%s  ✓ %s%s\n' "$GRN" "$out" "$RST"
  else
    printf '%s  ✗ %s%s\n' "$RED" "$out" "$RST"
    rm -f "$tmp"
    read -r -p "  Retry? [Y/n] " again
    [[ "$again" == "n" ]] || capture_one "$1"
  fi
}

if [[ $# -gt 0 ]]; then
  for want in "$@"; do
    found=
    for s in "${SHOTS[@]}"; do
      [[ "${s%%|*}" == "$want" ]] && { capture_one "$s"; found=1; }
    done
    [[ -n "$found" ]] || die "unknown shot '$want' (try --list)"
  done
else
  printf '%sCapturing %d shots.%s Details per shot: docs/screenshots/CAPTURE.md\n' \
    "$BLD" "${#SHOTS[@]}" "$RST"
  for s in "${SHOTS[@]}"; do capture_one "$s"; done
fi

printf '\n%sDone.%s Files land in docs/screenshots/ at 2x and are sized down in CSS.\n' "$GRN" "$RST"
