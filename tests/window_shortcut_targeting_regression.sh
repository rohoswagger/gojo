#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-window-shortcut.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT

cat > "$scratch_dir/KeyboardShortcuts.swift" <<'SWIFT'
@MainActor
public enum KeyboardShortcuts {
    public enum Name: Hashable {
        case windowLeftHalf, windowRightHalf, windowTopHalf, windowBottomHalf, windowMaximize, windowZoom
    }

    private static var handlers: [Name: () -> Void] = [:]

    public static func onKeyDown(for name: Name, action: @escaping () -> Void) {
        handlers[name] = action
    }

    public static func press(_ name: Name) {
        handlers[name]?()
    }
}
SWIFT

cd "$repo_root"
swiftc -module-cache-path "$scratch_dir/module-cache" \
  -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -emit-module -emit-library -module-name KeyboardShortcuts \
  "$scratch_dir/KeyboardShortcuts.swift" -o "$scratch_dir/libKeyboardShortcuts.dylib"

swiftc -module-cache-path "$scratch_dir/module-cache" \
  -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -I "$scratch_dir" -L "$scratch_dir" -lKeyboardShortcuts \
  -Xlinker -rpath -Xlinker "$scratch_dir" \
  Gojo/WindowManagement/WindowAction.swift \
  Gojo/WindowManagement/WindowFrameCalculator.swift \
  Gojo/WindowManagement/WindowHistoryStore.swift \
  Gojo/WindowManagement/WindowLayoutPreview.swift \
  Gojo/WindowManagement/WindowPowerState.swift \
  Gojo/WindowManagement/WindowActionExecutor.swift \
  Gojo/WindowManagement/WindowShortcutController.swift \
  tests/window_shortcut_targeting_regression.swift \
  -o "$scratch_dir/window-shortcut-regression"
"$scratch_dir/window-shortcut-regression"
