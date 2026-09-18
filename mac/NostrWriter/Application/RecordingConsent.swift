import Foundation

enum RecordingChoice: String, Sendable { case off, requested }

@MainActor
enum ApplicationEnvironment {
    static var defaults: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["NW_TEST_DEFAULTS"],
           suite.hasPrefix("com.mariusschober.nostrwriter.tests."),
           let defaults = UserDefaults(suiteName: suite) { return defaults }
        #endif
        return .standard
    }
}

@MainActor
final class RecordingConsent {
    /// Posted whenever the owner's recording choice actually changes.
    ///
    /// Detailed-history recording is a living state, not a setting read once at
    /// document open: turning it off must stop every open document immediately,
    /// and turning it on may start them. Open documents observe this rather
    /// than polling `UserDefaults`.
    static let didChangeNotification = Notification.Name("RecordingConsentDidChangeNotification")

    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) { self.defaults = defaults ?? ApplicationEnvironment.defaults }
    var hasChosen: Bool { defaults.string(forKey: "recordingChoice") != nil }
    var choice: RecordingChoice {
        RecordingChoice(rawValue: defaults.string(forKey: "recordingChoice") ?? "") ?? .off
    }

    /// Persists the choice and notifies open documents only on a real change,
    /// so repeated writes of the same value never trigger a spurious restart.
    func choose(_ value: RecordingChoice) {
        let previous = choice
        defaults.set(value.rawValue, forKey: "recordingChoice")
        guard previous != value else { return }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
