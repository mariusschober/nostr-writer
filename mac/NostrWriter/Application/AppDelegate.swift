import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let recoveryLibrary = RecoveryLibrary()
    private var settings: NSWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let mode = ProcessInfo.processInfo.environment["NW_TEST_APPEARANCE"] {
            if mode == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
            if mode == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
        }
        #endif
        NSApp.mainMenu = AppMenus.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        if NSDocumentController.shared.documents.isEmpty {
            NSDocumentController.shared.newDocument(nil)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    @objc func showSettings(_ sender: Any?) {
        if settings == nil { settings = SettingsWindowController() }
        settings?.showWindow(sender)
    }

    @objc func showWriterHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Writing and writing history"
        alert.informativeText = "Write offline without an account. Recording is optional and may retain deleted text locally. It is separate from publishing or disclosing evidence.\n\nNOT PROVABLE does not mean AI-written. No approved Mac capture profile or model is installed. A Nostr signature does not prove human composition."
        alert.addButton(withTitle: "Back to Writing")
        alert.runModal()
    }
}
