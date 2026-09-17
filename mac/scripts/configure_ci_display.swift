import AppKit
import CoreGraphics
import Foundation

// Disposable hosted-runner setup, never app behavior or a local screen override.
// A 1024x768 CI desktop clamps the required 1120x760 document window to 1024x674.
guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
    fputs("Refusing to change a display outside GitHub Actions.\n", stderr)
    exit(2)
}

func visibleSizeIsSufficient() -> Bool {
    guard let screen = NSScreen.main else { return false }
    print("Main display frame: \(screen.frame); usable frame: \(screen.visibleFrame)")
    return screen.visibleFrame.width >= 1120 && screen.visibleFrame.height >= 760
}

if visibleSizeIsSufficient() { exit(0) }
let display = CGMainDisplayID()
let modes = (CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode]) ?? []
let candidates = modes.filter { $0.width >= 1280 && $0.height >= 900 }
    .sorted { ($0.width * $0.height, $0.pixelWidth * $0.pixelHeight) < ($1.width * $1.height, $1.pixelWidth * $1.pixelHeight) }
guard let selected = candidates.first else {
    fputs("Hosted display has no mode large enough for mandatory 1120x760 UI acceptance.\n", stderr)
    print("Available display modes: \(modes.map { "\($0.width)x\($0.height)" }.joined(separator: ", "))")
    exit(1)
}
print("Selecting hosted display mode \(selected.width)x\(selected.height)")
// CGDisplaySetDisplayMode is process-scoped: macOS restores the old mode when
// this setup script exits. Commit only to this disposable login session so
// the later XCTest process sees the same usable display.
var configuration: CGDisplayConfigRef?
let begin = CGBeginDisplayConfiguration(&configuration)
guard begin == .success, let configuration else {
    fputs("Cannot begin hosted display configuration (\(begin.rawValue)).\n", stderr)
    exit(1)
}
let configure = CGConfigureDisplayWithDisplayMode(configuration, display, selected, nil)
guard configure == .success else {
    CGCancelDisplayConfiguration(configuration)
    fputs("Cannot select hosted display mode (\(configure.rawValue)).\n", stderr)
    exit(1)
}
let result = CGCompleteDisplayConfiguration(configuration, .forSession)
guard result == .success else {
    fputs("Hosted display configuration failed (\(result.rawValue)).\n", stderr)
    exit(1)
}
// Let AppKit receive the screen-configuration notification once. No test retry.
RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
guard visibleSizeIsSufficient() else {
    fputs("Hosted usable display remains too small for mandatory UI acceptance.\n", stderr)
    exit(1)
}
