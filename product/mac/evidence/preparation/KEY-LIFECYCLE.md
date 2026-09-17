# Recovery-key lifecycle decisions — 17 September 2026

Independent preparation for PLAN-02; no Stage 02 acceptance. These decisions
resolve the key bootstrap boundary without changing DATA or SECURITY. The
load-only adapter and its component evidence are recorded separately. The bootstrap sequence below is now implemented in `RecoveryBootstrap.swift`; six
focused component checks passed in `keychain-bootstrap/results.json`. Actual signed
app Keychain and document integration remain unobserved.

## Reading a key is not creating an installation

Normal recovery reads address one exact service/account. They neither enumerate
other items nor create, replace, rotate or delete anything. Request the macOS data
protection Keychain explicitly and verify the returned item's accessibility and
nonsynchronizable attributes. Apple documents that this selection applies the
accessibility/access-group model without enabling synchronization:
[data protection Keychain](https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain).

Suppress interactive authentication on ordinary checkpoint reads. An
interaction-not-allowed result can mean authentication is required; it does not
prove that the device is locked. Keep missing, denied/cancelled, interaction
unavailable, malformed and configuration failures distinguishable with fixed
messages. Never render raw Security results or secret bytes in errors. Apple's
current replacement for the deprecated authentication-UI option is a local
authentication context with interaction disabled:
[authentication UI behavior](https://developer.apple.com/documentation/security/ksecuseauthenticationuifail).

## First creation and crash ordering

The application bootstrap component owns a private store root and exclusive
single-writer access. Do not infer a new installation from a missing key or from
`DocumentStore.recover` returning absent for one document. In particular,
`DocumentStore.init` currently creates/migrates SQLite before a key is loaded;
the application must establish bootstrap identity before opening that store.

Use an installation UUID in a small versioned bootstrap marker and as the exact
Keychain account within the environment-specific recovery service. The marker
contains no key or writing. Development and release use separate services and
private roots; Nostr/HWP signing keys are different purposes and entries.

The implemented creation order is:

1. Establish that the dedicated root is new, then durably create a preparing
   marker under exclusive ownership. Unknown existing files, symlinks, malformed
   markers or an existing store without a marker are recovery errors, not a
   license to create replacement state.
2. Query that marker's exact Keychain identity. Create a fresh random 32-byte key
   only for this new, still-empty preparing installation and a definite missing
   result. Add with WhenUnlockedThisDeviceOnly and synchronization disabled.
   Duplicate-item races cause a fresh read and validation of the existing item;
   never delete it to make a retry succeed.
3. Read back and validate the key, then atomically mark the same installation
   ready and synchronize the marker and directory before opening SQLite or
   allowing any encrypted content to be written.

On restart, a preparing marker may resume this sequence only while exclusive
ownership is reacquired and no store/history/outbox material exists. A ready
marker with a missing, denied or unusable key fails closed: preserve all files,
allow source editing/saving and offer explicit recovery/retry. Any reset or
retirement of old private state is a separate user decision with preservation
and deletion consequences. Do not automatically discard an interrupted marker.

The focused checks cover fresh/reopened identity, missing ready key, denied access,
interrupted key creation, unknown existing state and exclusive lease lifetime.
Marker-write/readback/ready-replacement/first-store-open injected faults and actual
power-loss behavior are not measured. Existing checks are not blanket coverage.

## Signing dependency for real verification

The separately inspected Stage 01 binary (`ddac4a3`, evidence `e49557e`) is
ad-hoc signed, has no TeamIdentifier and has no application-identifier or
keychain-access-groups entitlement. This is actual bundle-inspection evidence,
not a Keychain access experiment. Legitimate signing/provisioning must supply the
appropriate application identity before live data-protection Keychain acceptance;
do not insert a fabricated team ID, weaken the policy or fall back to the legacy
Keychain merely to make an ad-hoc test pass. Apple describes the app's accessible
groups in [Keychain access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
and the profile requirement in [this Developer Technical Support answer](https://developer.apple.com/forums/thread/836816).

Actual app access, unavailable/locked-key UI, crash-safe first creation, ordinary
source saving during failure and reopening with the same key remain mandatory
integration observations. A synthetic query test proves neither provisioning nor
actual Keychain persistence. No real Keychain item was read or changed for this
architecture review.
