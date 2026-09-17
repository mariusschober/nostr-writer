# Recovery scheduling preparation

Reviewed source: `735681c4543a7084cd17925e75f39024f6d46983` on the local,
unmerged `preparation/native-cores` branch. This is independent preparation while
Stage 01 remains unaccepted. It is not Stage 02 acceptance and is not app wiring.

`RecoveryCoordinator` binds one document to one persistence actor. It schedules
an immediate first checkpoint, coalesces only disposable source snapshots, anchors
later deadlines to the oldest pending edit and admits at most one store write at
a time. The configured interval is at most one second. Slow writes expose overdue
recovery; a failed write preserves text and pauses for retry or a new edit.
Memory, durable recovery and saved-file state remain separate.

Close forces the newest source through a cancellable durability waiter. Cancelling
Close does not cancel an already-committing write. Failure reopens editing, a
second simultaneous Close is refused, and success records closed rather than
perpetually closing. Bounded waiters, snapshot bounds and exact acknowledgement
checks protect asynchronous identity. No source recovery result attests capture
history or HWP authority.

## Observed checks

- **PASS:** 34 scheduler tests and two composition tests, zero failures or skips,
  0.100 seconds of XCTest execution. See [raw log](tests.log) and
  [machine-readable results](results.json). One harmless test-local unused-mutation
  warning is retained in the log.
- **PASS:** Real encrypted SQLite close/reopen recovers exact newest unsaved bytes;
  the saved source file remains at its separately acknowledged earlier revision.
- **PASS:** An unavailable injected key prevents recovery acknowledgement while
  ordinary coordinated file saving succeeds. Explicit retry restores recovery.
- **PASS:** All 69 frozen distribution files, 326 source-manifest files and 60
  acceptance definitions remain intact. See [preparation](preparation.json) and
  [protocol](frozen-protocol.json) reports.

The earlier 59 storage tests are retained in the [native files report](../native-files/README.md).
Their implementation files are unchanged. This final checkpoint compiled the whole
package but ran only the 36 new tests; it is not a single 95-test execution.
[Source hashes](source-files.json) include the current storage package and its
Foundation interfaces.

## Remaining acceptance

Virtual-clock tests do not measure the production clock, typing latency or the
app's one-second recovery bound. NSDocument save/close/quit integration, production
Keychain lifecycle, native error/recovery UI, actual sandbox/provider grants,
real iCloud and Google Drive sessions, physical power loss and Intel runtime remain
unmeasured here. Library/search, outbox, capture history and the remaining Stage 02
contract are still required. Stage 01 final UI/VoiceOver/network observations and
hosted CI remain blocked as recorded in its own report. No stage criterion is
promoted by this component evidence.
