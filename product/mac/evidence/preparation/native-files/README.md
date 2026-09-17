# Native file and bookmark preparation

**Component tests PASS; Stage 02 is not accepted.** Source `c74b88bf66b6178274302ebc8a4e128485357268` on the local
`preparation/native-cores` branch. The Stage 01 candidate remains `251a7d1`, pending
final desktop observations and authorized hosted CI. No accepted predecessor is
invented, and all 60 application acceptance requirements remain mandatory.

`CoordinatedSourceFiles` performs bounded exact UTF-8 source reads, exclusive new
copies and coordinated atomic replacements. Writes retain BOM, CRLF, Unicode,
permissions and extended attributes; file and directory synchronization precede a
positive acknowledgement. A late uncertainty after replacement is explicitly
reported. Exact expected bytes are rechecked before replacement. Two coordinated
writers cannot both overwrite the same original version; a stale writer must let
the user resolve the external change. Creating a conflict copy never silently
replaces an existing destination.

These helpers serve separately owned copy/import operations. Do not call them
inside NSDocument read/write accessors; NSDocument owns its own coordination.
A save result names its immutable source revision and actual coordinated URL;
it does not attest cloud upload, private-history durability or human composition.

`ScopedSourceFiles` balances acquired scopes on success, failure and cancellation.
Stored bookmarks resolve without interactive UI or mounting; stale/denied grants
fail explicitly and never auto-renew. Explicit panel-selected URLs may already be
authorized. No provider path, Google API, disk scan or credential is introduced.

## Actual verification

59 tests passed, zero failures/skips, including all 46 earlier encrypted-recovery
tests, nine new file tests and four bookmark-seam tests. Exact source/metadata,
stale writes, simultaneous writers, destination-creation races, before/after
replacement failures, cancellation, invalid UTF-8, size/scalar limits, directories,
symlinks and FIFOs were exercised using disposable local fixtures. An actual second
local process wrote through Foundation coordination; the old-reader save was
refused and both external and local sources were recovered from separate files.

The initial FIFO test exposed Foundation opening the pipe before our callback.
A one-second stack sample identified that wait; opening the disposable FIFO's
writer released the original test process without restarting it. The product fix
now preflights nonregular items before Foundation coordination and retains checks
inside the accessor. Final hostile-input test: 0.013 seconds, without intervention.
No result from the manually released initial run is used as final acceptance.

Actual sandbox grants/provider sessions are **NOT MEASURED**. Bookmark tests inject
resolution and grant decisions; native bookmark APIs compile but that is not live
permission evidence. Coordinator cancellation follows the installed SDK's explicit
thread-safe `cancel()` contract. A narrow immutable cancellation handle is the only
unchecked Sendable wrapper; file coordination itself stays actor-owned.

## Reproduce

```sh
swiftc mac/Packages/WriterStorage/Tools/coordinated_writer.swift -o /private/tmp/nostr-writer-coordinated-writer
NW_COORDINATED_WRITER=/private/tmp/nostr-writer-coordinated-writer swift test --package-path mac/Packages/WriterStorage
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

The full raw log, source hashes and machine-readable limits are alongside this
report. All 69 frozen protocol files, 326 source-of-truth files and 60 acceptance
definitions passed the read-only integrity checks.

## Boundaries and remaining work

These are native file operations, not the full conflict/recovery user flow. Main-app
integration, recovery scheduling, one-session routing, duplicate/derivation metadata,
owned assets, conflict preservation in encrypted recovery, library/search, real
Keychain and provider lifecycle, screenshots and VoiceOver remain mandatory.
Cooperative coordination is not protection against an owner-controlled process that
ignores it. Preflight cannot guarantee a node is never changed afterward. The caller
must have grants sufficient for a sibling temporary file; that sandbox behavior and
physical crash/full-volume durability still require actual integration checks.

Reference API boundaries: [Apple file coordination](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileCoordinators/FileCoordinators.html),
[coordinator cancellation](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel()),
and [balanced security-scoped access](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()).
