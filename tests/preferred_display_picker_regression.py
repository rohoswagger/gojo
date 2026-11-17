from pathlib import Path
import subprocess
import tempfile

repo_root = Path(__file__).resolve().parents[1]
s = (repo_root / 'Gojo/components/Settings/SettingsView.swift').read_text()
a = s.index('                Picker("Preferred display"')
b = s.index('                .onChange(of: NSScreen.screens)', a)
picker = s[a:b]
probe = ('''import AppKit
import SwiftUI
final class Coordinator: ObservableObject {
 @Published var preferredScreenUUID: String?
 init(_ value: String?) { preferredScreenUUID = value }
}
struct Probe: View {
 @ObservedObject var coordinator: Coordinator
 var screens: [(uuid: String, name: String)]
 var body: some View {
'''+picker+'''
 .pickerStyle(.menu)
 }
}
func buttons(_ view: NSView) -> [NSPopUpButton] {
 (view as? NSPopUpButton).map { [$0] } ?? view.subviews.flatMap(buttons)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
for selection: String? in [nil, "missing", "connected"] {
 let coordinator = Coordinator(selection)
 let host = NSHostingView(rootView: Probe(coordinator: coordinator, screens: [("connected", "Built-in")]))
 let window = NSWindow(contentRect: NSRect(x:0,y:0,width:400,height:100), styleMask: [.borderless], backing:.buffered, defer:false)
 window.contentView = host
 window.orderFrontRegardless()
 RunLoop.current.run(until: Date().addingTimeInterval(0.15))
 host.layoutSubtreeIfNeeded()
 let popup = buttons(host).first!
 print("selection=\\(selection ?? "nil") items=\\(popup.itemTitles) selected=\\(popup.titleOfSelectedItem ?? "nil")")
 let expected = selection == "connected" ? "Built-in" : selection == nil ? "No preferred display" : "Disconnected display"
 precondition(popup.titleOfSelectedItem == expected, "Missing selection tag for \\(selection ?? "nil")")
 precondition(coordinator.preferredScreenUUID == selection, "Preference changed")
 if selection == "missing" {
  host.rootView = Probe(coordinator: coordinator, screens: [("connected", "Built-in"), ("missing", "External")])
  RunLoop.current.run(until: Date().addingTimeInterval(0.15))
  precondition(buttons(host).first?.titleOfSelectedItem == "External", "Reconnected display not selected")
  precondition(buttons(host).first?.itemTitles == ["Built-in", "External"], "Stale disconnected entry")
  host.rootView = Probe(coordinator: coordinator, screens: [("connected", "Built-in")])
  RunLoop.current.run(until: Date().addingTimeInterval(0.15))
  precondition(buttons(host).first?.titleOfSelectedItem == "Disconnected display", "Disconnected selection lost")
  precondition(coordinator.preferredScreenUUID == "missing", "Preference lost after reconnect")
 }
 window.orderOut(nil)
}
print("PASS preferred display selections")
''')

with tempfile.TemporaryDirectory(prefix="gojo-display-picker-") as directory:
    root = Path(directory)
    source = root / "probe.swift"
    binary = root / "probe"
    source.write_text(probe)
    subprocess.run([
        "swiftc", "-module-cache-path", str(root / "cache"),
        "-swift-version", "5", "-warnings-as-errors",
        str(source), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)
