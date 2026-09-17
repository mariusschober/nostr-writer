// Test-only second local process; every path is a caller-owned temporary fixture.
import Foundation
let arguments = CommandLine.arguments
precondition(arguments.count == 3)
let url = URL(fileURLWithPath: arguments[1])
let bytes = Data(base64Encoded: arguments[2])!
var coordinationError: NSError?, writeError: Error?
NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
    do { try bytes.write(to: target, options: .atomic) } catch { writeError = error }
}
if coordinationError != nil || writeError != nil { exit(1) }
