# Recovery Keychain reader component evidence

Source checkpoint `0a1a806` on local `preparation/native-cores`. This is unmerged
independent preparation, not accepted Stage 02. Stage 01 remains at `e49557e`,
awaiting hosted CI and observed spoken VoiceOver navigation.

Astra implemented and reviewed this small adapter directly. The attempted worker
could not verify the requested DeepSeek identity and was stopped before editing.

`KeychainRecoveryKey` implements the real `SecItemCopyMatching` read path for one
configured service/account/access group. The API has no add, update or deletion
operation. An actor keeps blocking Keychain work off the editor's actor. A fresh
query and noninteractive authentication context are used on every read; a formerly
available key is not cached through later denial. Returned identity,
WhenUnlockedThisDeviceOnly, synchronization-disabled and exactly 32-byte key
requirements are checked before returning a symmetric key.

Missing, denied/cancelled, interaction-unavailable, malformed and signing failures
remain explicit fixed-message errors. The interaction result does not establish
whether the device was actually locked. Query identity is bounded and rejects
empty, wildcard/control-containing or oversized values. No real item is queried
by the tests, and no key material is logged or retained in these artifacts.

## Observed checks

Run once from this worktree:

```
swift test --package-path mac/Packages/WriterStorage --filter KeychainRecoveryKeyTests
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

- **PASS:** package compilation, six filtered tests, zero failures; test execution
  0.011 seconds after a 3.70-second build. Raw output: `tests.log`.
- **PASS:** query attributes, off-main execution, no caching across denial,
  distinct failure categories with no internal retry, wrong policy/identity/key
  rejection, bounded exact identity and native result decoding.
- **PASS:** 69 frozen protocol files, 326 recovery-manifest files and 60 acceptance
  criteria unchanged. Raw outputs: `preparation.json` and `frozen-protocol.json`.
- The package compile reports an existing never-mutated-variable warning in
  `RecoveryCoordinatorTests.swift:961`. That unrelated source was not changed.

No previous passing suite was rerun. The focused test invocation recompiles the
package/test target but executes only the six new reader tests. These checks use
an injected read-only response seam; they do not establish that a signed app can
access the actual Keychain.

## Mandatory remaining work

**NOT MEASURED:** legitimate signed/provisioned app access, actual unavailable or
locked Keychain behavior, crash-safe first key creation, real persistence across
app restart and its recovery UI. See [key lifecycle decisions](../KEY-LIFECYCLE.md)
for safe initialization order and the actual Stage 01 signing limitation.

M07–M13 are not accepted by this component report. Ordinary source saving during
recovery failure has earlier composition evidence, but the new reader's actual
native behavior and full app attachment still need Stage 02 evidence.
