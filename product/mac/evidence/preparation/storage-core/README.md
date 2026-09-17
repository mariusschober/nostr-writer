# Source recovery core - independent preparation

Status: **46 package tests PASS; Stage 02 NOT ACCEPTED**. This source is isolated on
`preparation/native-cores`, based on Stage 01 checkpoint `251a7d1`. The app candidate
on `implementation/stage-01` has not changed. No external push occurred.

See [core decisions and limitations](../../../../../mac/Packages/WriterStorage/CORE-NOTES.md).
`tests.log` records the current full suite executed in this worktree after parent review.
`source-files.json` identifies the exact package inputs. Tests use synthetic temporary
SQLite files and in-memory keys; no owner documents, Keychain entries or provider files
were changed. The native core uses platform SQLite with no new third-party package.

Review repaired recovery/close races across asynchronous key loading, false available
key status after a database read error, unsafe main-file-only migration copying, missing
macOS fullfsync configuration, unbounded recovery inputs, nonrolling recovery retention,
and advancing past a damaged latest checkpoint. New checkpoint pruning is transactional
and applies only to disposable source recovery copies. Detailed private history remains
separate and subject to explicit deletion consent.

SQLite's [fullfsync documentation](https://sqlite.org/pragma.html#pragma_fullfsync)
describes the macOS-specific sync setting; the test reads back the effective values.
This does not claim a physical power-failure experiment. The disk-full test uses actual
SQLITE_FULL through a temporary page limit, not exhaustion of the user's physical disk.

Full Stage 02 acceptance still requires the accepted Stage 01 predecessor, app/Keychain
integration, coordinated source saves and lifecycle checkpoints, local library/recovery
UI, native conflict behavior and actual iCloud/Google Drive observations. No later stage
or acceptance row is waived. The frozen inputs and all 60 criteria remain unchanged.
