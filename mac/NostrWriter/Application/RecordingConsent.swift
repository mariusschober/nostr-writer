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
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) { self.defaults = defaults ?? ApplicationEnvironment.defaults }
    var hasChosen: Bool { defaults.string(forKey: "recordingChoice") != nil }
    var choice: RecordingChoice {
        RecordingChoice(rawValue: defaults.string(forKey: "recordingChoice") ?? "") ?? .off
    }
    func choose(_ value: RecordingChoice) { defaults.set(value.rawValue, forKey: "recordingChoice") }
}
