import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 330),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView().defaultAppStorage(ApplicationEnvironment.defaults))
        super.init(window: window)
        window.center()
    }
    required init?(coder: NSCoder) { nil }
}

private struct SettingsView: View {
    @AppStorage("recordingChoice") private var recording = RecordingChoice.off.rawValue
    var body: some View {
        Form {
            Section("Recording & Privacy") {
                Toggle("Store writing history on this Mac", isOn: Binding(
                    get: { recording == RecordingChoice.requested.rawValue },
                    set: { recording = ($0 ? RecordingChoice.requested : .off).rawValue }))
                Text("History may include deleted text and timing. This choice never authorizes publishing or uploading evidence.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Recording storage is not yet available in this development shell.")
                    .font(.callout)
            }
            Section("Human Writing Proof") {
                Text("NOT PROVABLE — no approved Mac capture profile and model are installed.")
                Text("This is not a judgment about who wrote your text.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding()
    }
}
