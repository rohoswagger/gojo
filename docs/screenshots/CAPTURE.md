# Gojo marketing screenshots

These are the images the landing page is built around. The page is image-forward:
if a shot is soft, empty, or shows a settings pane instead of the feature, the
whole page reads as low-effort. Treat these as product photography.

Run `./scripts/capture-screenshots.sh` and it walks every shot, validates the
result, and writes normalised PNGs here. `--list` prints the shot table.

## Non-negotiables

- **Capture on a retina MacBook display.** The script rejects anything under the
  per-shot minimum width. Files are saved at 2x and sized down in CSS, so a 1x
  capture is a guaranteed blurry asset — that is exactly the bug this replaces.
- **Real content, never empty state.** The shot this replaced said
  *"Not Playing / Unknown / 0:00"*. A player with nothing playing is not a demo.
  Real track, real filenames, real copied text, real window titles.
- **Nothing personal in frame.** No real names, emails, tokens, client work, or
  private filenames. Clipboard and shelf shots leak the most — stage them.
- **Quiet wallpaper.** Dark, low-contrast, no busy photography. The notch UI has
  to be the highest-contrast thing in frame. `assets/bg.webp` works.
- **Clean menu bar.** Hide everything but the clock, or use a fresh user. Turn
  off notifications (Do Not Disturb) so nothing slides in mid-capture.
- **Include ~16–24px of wallpaper** around the notch surface. The page adds its
  own framing and needs the bleed; a tight crop looks amputated.
- **Light mode off.** The notch surface is dark; keep the system in dark mode so
  the wallpaper and UI agree.

## The shots

Aspect ratios are enforced within ±14%, so you have room — but stay close, or
the page's frames will crop your capture.

### `dictation.png` — flagship, gets the most page space

Hold-to-dictate mid-sentence: waveform active, partial transcript visible,
text landing in a real app behind it (Notes, Mail, Slack). This is the wedge
PRODUCT.md leads with and it currently has **no image at all**, so it deserves
the most staging effort.

Dictate a sentence that shows off local processing — something a cloud service
would be a bad idea for. Trigger is hold-to-talk on the configured modifier
(Settings › Dictation). Have a model already downloaded so there's no
progress bar in frame.

### `media.png`

A real track playing with artwork loaded, scrubber ~40% through, elapsed and
remaining times both non-zero. Pick a record whose art is dark enough not to
blow out the frame. Player tinting on looks better here than off.

### `clipboard.png`

4+ entries of visibly different kinds — a URL, a code snippet, a paragraph, a
hex colour — with one row hovered to show the paste affordance. Nothing private.
Search field empty so the full list reads.

### `shelf.png`

3 files staged, ideally mid-drag with the drop affordance lit. Use files whose
names and icons are self-explanatory (a PDF, a PNG, a zip). Rename them first if
your real filenames are noisy.

### `windows.png`

The **window switcher overlay** — not the settings pane. 4+ real apps with live
previews and titles visible, one selected. This is the shot the old
`app-windows.png` got wrong: it showed a checkbox list, which tells a visitor
nothing about what the feature does.

### `display.png`

Night Shift / brightness control open **in the notch**. Again: the feature
surface, not the settings pane the old `app-display.png` showed. If the warmth
change is visible in the wallpaper, better.

### `settings.png`

One honest settings shot, for the customization section — Settings › Media with
the reorderable control row visible. This replaces a hand-built CSS mockup of
settings that had drifted from the real UI. One real settings pane is fine;
it just can't stand in for the features themselves.

## Retired files

`app-clipboard.png`, `app-display.png`, `app-files.png`, `app-media.png`,
`app-windows.png` were 640×210 and 700×600 **JPEGs with a `.png` extension**,
captured at 1x. Delete them once the shots above exist. `music.png` and
`windows-tab.png` are older 1x PNGs referenced from `README.md`.
