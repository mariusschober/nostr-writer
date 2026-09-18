import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 470),
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
    @AppStorage("editorFontChoice") private var fontChoice = EditorFontChoice.mono.rawValue
    @AppStorage("editorFontSize") private var fontSize = 18.0
    @AppStorage("editorMeasure") private var measure = 72
    @AppStorage("editorFocusMode") private var focusMode = EditorFocusMode.off.rawValue
    @AppStorage("editorTypewriterScrolling") private var typewriter = false

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Typeface", selection: $fontChoice) {
                    ForEach(EditorFontChoice.allCases, id: \.rawValue) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }
                .pickerStyle(.menu)
                HStack {
                    Text("Size")
                    Slider(value: $fontSize, in: 13...32, step: 1)
                    Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Measure")
                    Slider(value: Binding(get: { Double(measure) }, set: { measure = Int($0) }), in: 50...100, step: 1)
                    Text("\(measure) chars").monospacedDigit().frame(width: 72, alignment: .trailing)
                }
                Picker("Focus", selection: $focusMode) {
                    ForEach(EditorFocusMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Typewriter scrolling", isOn: $typewriter)
                Text("Presentation only. The exact source bytes are never rewritten by these preferences.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Recording & Privacy") {
                Toggle("Store writing history on this Mac", isOn: Binding(
                    get: { recording == RecordingChoice.requested.rawValue },
                    set: { isOn in
                        let value = (isOn ? RecordingChoice.requested : .off).rawValue
                        guard recording != value else { return }
                        recording = value
                        // Tell every open document immediately. Writing the
                        // preference alone did not stop active recording.
                        NotificationCenter.default.post(name: RecordingConsent.didChangeNotification, object: nil)
                    }))
                Text("History may include deleted text and timing. This choice never authorizes publishing or uploading evidence.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Recording starts prospectively. Deleting local history does not delete your document and cannot revoke an already exported proof.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Human Writing Proof") {
                Text("NOT PROVABLE — no approved Mac capture profile and model are installed.")
                Text("This is not a judgment about who wrote your text.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding()
    }
}
