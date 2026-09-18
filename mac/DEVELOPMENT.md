# Current development builds

The recovered macOS README is a pinned historical snapshot. Current implementation
and acceptance results are in [Stage 02 evidence](../product/mac/evidence/STAGE-02.md).

## Ordinary local build

`mac/scripts/build.sh` keeps the default ad-hoc signature, sandbox and hardened runtime.
It does not claim real encrypted-recovery Keychain access. Ordinary source editing and
saving remain available when private recovery cannot open.

## Owner-signed development build

Use an existing Apple Development signing identity and the owner's explicitly selected
Apple Developer team. Configure those in Xcode's account/signing settings first. Do not
paste a private key, certificate password, recovery key or account password into a prompt.
Review any Apple license agreement yourself. This helper does not accept agreements or
request automatic provisioning/account changes.

Run `mac/scripts/build_signed_development.sh` with `WRITER_DEVELOPMENT_TEAM` set to the
actual team identifier selected in Xcode. The helper refuses a missing/malformed team or
a missing existing Apple Development identity. Xcode selects a matching existing identity;
the built signature must report the supplied team. If provisioning is unavailable, finish
the owner-controlled signing setup in Xcode before retrying the helper.

This is a fixed Debug build into `mac/.build/SignedDevelopment`. The development bundle
identifier and private-store services stay separate from release. The app requests one
Keychain access group matching its own application identifier, using Xcode's resolved
`AppIdentifierPrefix`; it does not assume that prefix is always the current team identifier.
See [Apple's Keychain configuration guidance](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing)
and [the access-group attribute](https://developer.apple.com/documentation/security/ksecattraccessgroup).
The normal ad-hoc build continues to use its original entitlement file.

After building, the helper checks the actual signature/team, resolved application identity,
single matching Keychain group, sandbox, hardened runtime, allowed entitlements, both CPU
architectures and minimum macOS version. Passing this inspection is not proof of real
Keychain runtime behavior, File Provider behavior, HWP authority, Developer ID distribution
or notarization. Those require the stage-specific observations and evidence.

As of the latest Stage 02 checkpoint, the signed path is **NOT MEASURED**: this host has no
valid signing identity and native builds still stop at Xcode 27's license gate. Only helper
syntax, entitlement structure and missing-team refusal have been checked.
