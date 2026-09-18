import AppKit
import WriterFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let recoveryLibrary = RecoveryLibrary()
    lazy var libraryModel = WriterLibraryModel(recovery: recoveryLibrary)
    private var settings: NSWindowController?
    private var textImporter: TextImportController?
    private var terminating = false

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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceWillSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        if NSDocumentController.shared.documents.isEmpty {
            NSDocumentController.shared.newDocument(nil)
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        // Defer even an empty-document callback until after terminateLater is
        // returned. Native close negotiation retains Save/Discard/Cancel and
        // each WriterDocument's bounded recovery flush.
        Task { @MainActor in
            NSDocumentController.shared.closeAllDocuments(withDelegate: self,
                didCloseAllSelector: #selector(documentsClosed(_:didCloseAll:contextInfo:)), contextInfo: nil)
        }
        return .terminateLater
    }

    @objc private func documentsClosed(_ controller: NSDocumentController, didCloseAll: Bool, contextInfo: UnsafeMutableRawPointer?) {
        terminating = false
        NSApp.reply(toApplicationShouldTerminate: didCloseAll)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The detailed-history journal is application-scoped: only termination
        // closes it, so closing one document never stops recording in others.
        let library = recoveryLibrary
        Task { await library.closeSharedHistoryJournal() }
    }

    @objc func importTextCopy(_ sender: Any?) {
        guard textImporter == nil else { textImporter?.showWindow(sender); return }
        textImporter = TextImportController(library: recoveryLibrary) { [weak self] in self?.textImporter = nil }
        textImporter?.chooseSource()
    }

    func applicationWillResignActive(_ notification: Notification) { checkpointDocuments(.interruption) }

    @objc private func workspaceWillSleep(_ notification: Notification) { checkpointDocuments(.sleep) }

    private func checkpointDocuments(_ boundary: ObservationBoundary) {
        for document in NSDocumentController.shared.documents.compactMap({ $0 as? WriterDocument }) {
            document.checkpointForInterruption(boundary)
        }
    }

    @objc func showSettings(_ sender: Any?) {
        if settings == nil { settings = SettingsWindowController() }
        settings?.showWindow(sender)
    }

    /// Shows the shared native Spelling and Grammar panel for the writing view.
    @objc func showSpellingAndGrammar(_ sender: Any?) {
        NSSpellChecker.shared.spellingPanel.orderFront(sender)
    }

    @objc func showWriterHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Writing and writing history"
        alert.informativeText = "Write offline without an account. Recording is optional and may retain deleted text locally. It is separate from publishing or disclosing evidence.\n\nNOT PROVABLE does not mean AI-written. No approved Mac capture profile or model is installed. A Nostr signature does not prove human composition."
        alert.addButton(withTitle: "Back to Writing")
        alert.runModal()
    }
}
