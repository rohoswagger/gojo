# Issues & Fixes

## Closed Notch Architecture (2026-04-09)

**Decision:** There is exactly one closed mini-notch presentation. It is the compact form of the notch and may expand into the full notch on hover.

**Allowed triggers for the mini-notch:**
- Active media state
- Clipboard copy feedback
- Toast / transient notification feedback

**Disallowed behavior:** Hovering near the top edge must not create a second "teaser" mini-notch or an empty revealed notch. That produces two closed-notch entry paths and breaks the intended architecture.

**Implementation rule:** The closed notch should be driven only by meaningful activity state. Pointer hover may expand an existing mini-notch into the large notch, but hover alone must not manufacture a separate mini-notch state.

## File Staging Drop Architecture (2026-04-09)

**Problem:** The notch visually reacted to file drags, but drops could still fall through to the underlying app, for example opening the file in the browser instead of staging it.

**Root cause:** Drag detection and drop acceptance were treated as the same system. They are not. A global drag observer can open the notch and switch the UI into file-staging mode, but it does not own the drop. The actual drop target must be a live SwiftUI/AppKit surface that macOS can route the drag session into.

### Upstream reference architecture

Gojo should follow the same structural split used in `gojo`:

1. A drag detector only observes the global drag session and updates notch state.
2. The actual file import is handled by broad `onDrop` surfaces, not by the detector.
3. The closed notch should expose a full-frame transparent drop layer while a valid drag session is active.
4. The expanded shelf/panel should also accept drops directly.
5. `NSItemProvider` decoding must accept multiple payload shapes (`fileURL`, `url`, plain text path/url strings, and raw data that decodes into a file URL string).

### Implementation rule

- Never rely on hover or drag-observer callbacks alone to stage files.
- The drag observer is responsible for revealing/activating the staging UI.
- A real drop surface is responsible for loading `NSItemProvider`s and persisting staged files.
- If drag-and-drop regresses, verify input routing first, then provider decoding.

### Proven working approach in Gojo

After multiple failed attempts to make the main notch window own Finder drops directly, the working solution was a **dedicated drag-only shell window**.

How it works:

1. `DragObserver` watches the global drag pasteboard and mouse movement.
2. When a valid file drag starts, Gojo shows a separate `DragShellWindow`.
3. That window contains a plain AppKit `NSView` drag destination (`DragShellDropView`) registered for `.fileURL`.
4. The drag shell is the only active drop target for the proof of concept.
5. On successful drop, the shell extracts file URLs from `draggingPasteboard`, hands them to `FileStagingModule.stageFiles(...)`, expands the notch, and hides itself.

Why this worked:

- The main notch window, SwiftUI `onDrop`, and hosted-view overlays never received drag callbacks reliably in this app.
- The dedicated drag shell is a plain AppKit window with a plain AppKit drop view, which macOS routed correctly.
- This separates **drag acceptance** from the main notch architecture and avoids fighting notch hover/click-through behavior.

### Important takeaway

If Finder drops stop working again, do **not** assume the problem is provider decoding first.
Check this order:

1. Did the global drag detector fire?
2. Did the drag shell window appear?
3. Did `DragShellDropView.draggingEntered` fire?
4. Did `DragShellDropView.performDragOperation` extract URLs?
5. Did `FileStagingModule.stageFiles(...)` add staged files?

### Design rule going forward

- Treat the dedicated drag shell as an isolated subsystem.
- Do not re-entangle Finder drop ownership with the main notch window unless there is strong evidence it can be done without regressions.
- The notch can react visually before/after drop, but the drag shell owns the actual drop.

## Clipboard Module Layout Shift (2026-04-08)

**Problem:** Switching between the media tab and clipboard tab caused visible layout shift — the notch shell resized because the clipboard content wasn't constrained to the same dimensions as other modules.

**Root cause:** The clipboard expanded view had its own inner container with extra padding and background (`containerInset: 10`, rounded rect background), while the media module rendered directly into the available space provided by `StandardExpandedModuleLayout`. The clipboard content also lacked a fixed height constraint, allowing it to push the notch shell larger than the standard size.

### How expanded module layout works

The notch panel has a **fixed expanded size** defined in `NotchPanel.swift`:
- `expandedPanelWidth: 560`
- `expandedPanelHeight: 184`

All expanded module content is wrapped by `NotchContentView.expandedContent` which applies uniform padding:
- Horizontal: `12pt`
- Top: `8pt`
- Bottom: `8pt`

(`NotchContentView.swift:9-13`, `ExpandedNotchMetrics`)

Within that padded area, modules use `StandardExpandedModuleLayout` (`GojoModule.swift:83`), which provides a consistent `HStack` with optional leading sidebar. Key metrics in `StandardExpandedModuleMetrics` (`GojoModule.swift:74-81`):
- `leadingWidth: 126` — sidebar/album art width
- `contentHeight: 100`
- `spacing: 18`

**Critical constraint:** The media module pins its content column height to `StandardExpandedModuleMetrics.leadingWidth` (126pt) at `NotchHubModule.swift:547`. Any module that doesn't constrain to this height will cause layout shift.

### Fix applied

1. Removed the clipboard's inner container background, border, and extra padding — content now renders directly into the layout like media does.
2. Added explicit height constraint matching the standard: `.frame(height: StandardExpandedModuleMetrics.leadingWidth)` with `.clipped()` on the clipboard content VStack (`ClipboardModule.swift:449-451`).

### Rules for new modules

- Never add wrapper containers with their own padding inside `StandardExpandedModuleLayout` — use the space as-is.
- Always constrain content height to `StandardExpandedModuleMetrics.leadingWidth` (126pt) if the content can grow (e.g. scroll views, lists).
- The notch corner radius token is `Gojo.Radius.notch` (18pt) in `DesignTokens.swift:108`.
