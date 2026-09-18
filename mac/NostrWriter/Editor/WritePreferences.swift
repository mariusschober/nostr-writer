import AppKit
import WriterFoundation

/// Native typography and focus preferences. Nothing here rewrites source bytes:
/// the editor's display attributes and these preferences never change `SourceSnapshot`.
enum EditorFontChoice: String, CaseIterable, Sendable {
    case mono, sans, georgia

    var displayName: String {
        switch self {
        case .mono: "System Mono"
        case .sans: "System Sans"
        case .georgia: "Georgia"
        }
    }

    func font(ofSize size: CGFloat) -> NSFont {
        switch self {
        case .mono: .monospacedSystemFont(ofSize: size, weight: .regular)
        case .sans: .systemFont(ofSize: size)
        case .georgia: NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        }
    }
}

/// Voluntary presentation focus. This is not a locked session and imposes no
/// restrictions; Stage 07 owns enforcement, sound and global restrictions.
enum EditorFocusMode: String, CaseIterable, Sendable {
    case off, sentence, paragraph

    var displayName: String {
        switch self {
        case .off: "Off"
        case .sentence: "Sentence"
        case .paragraph: "Paragraph"
        }
    }
}

/// UserDefaults-backed editor preferences with a change notification so the
/// open window can restyle without touching the document.
@MainActor
final class WritePreferences {
    static let didChangeNotification = Notification.Name("WriterWritePreferencesDidChange")

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) { self.defaults = defaults ?? ApplicationEnvironment.defaults }

    var fontChoice: EditorFontChoice {
        get { EditorFontChoice(rawValue: defaults.string(forKey: "editorFontChoice") ?? "") ?? .mono }
        set { defaults.set(newValue.rawValue, forKey: "editorFontChoice"); notify() }
    }

    /// Point size, clamped to the contracted 13...32 range.
    var fontSize: Double {
        get { clamped(defaults.object(forKey: "editorFontSize") as? Double ?? 18, 13, 32) }
        set { defaults.set(clamped(newValue, 13, 32), forKey: "editorFontSize"); notify() }
    }

    /// Preferred measure in characters, clamped to the contracted 50...100 range.
    var measure: Int {
        get { Int(clamped(Double(defaults.object(forKey: "editorMeasure") as? Int ?? 72), 50, 100)) }
        set { defaults.set(Int(clamped(Double(newValue), 50, 100)), forKey: "editorMeasure"); notify() }
    }

    var focusMode: EditorFocusMode {
        get { EditorFocusMode(rawValue: defaults.string(forKey: "editorFocusMode") ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "editorFocusMode"); notify() }
    }

    var typewriterScrolling: Bool {
        get { defaults.bool(forKey: "editorTypewriterScrolling") }
        set { defaults.set(newValue, forKey: "editorTypewriterScrolling"); notify() }
    }

    private func clamped(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
