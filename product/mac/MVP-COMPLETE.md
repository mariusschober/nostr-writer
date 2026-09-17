# One definition of complete

> Recovered historical preparation; read the [current recovery notice](RECOVERY-NOTES.md) before relying on source availability or test claims.

**Nostr Writer Mac MVP is complete only when every mandatory M01–M60 in `contracts/acceptance.json` passes against the same release commit, all eight implementation stages have accepted evidence, and the signed/notarized/stapled distributable passes a clean-user install.** There is no separate softer “architecture complete”, “feature complete except tests” or “MVP complete but unsigned” result.

The release is a macOS14+ native document application for arm64 and x86_64 where the OS supports the hardware. Runtime coverage includes minimum macOS14, current macOS on Apple silicon, and a supported Intel14–26 version. macOS27's device support must not be misrepresented as Intel support. The host Xcode requirement is distinct from the app deployment target.

A user can install without a development toolchain, immediately write offline, save locally/iCloud Drive/Google Drive for desktop, recover interrupted work, use long-form editing and transparent assistance, optionally enter safely escapable disciplined sessions with four offline sounds, export polished PDF and real editable DOCX, publish short/long Nostr events, maintain encrypted NIP37 drafts and inspect exact passage provenance/HWP status. No app account or company backend is required for ordinary writing, local proof checking or document recovery.

## HWP completion is not invented scientific approval

The complete native frozen P/V/R implementation must pass cross-language conformance and adversarial integration tests. The app's default production approval set remains empty, so its own unapproved observations receive NOT PROVABLE and **no HWP signature**. Known assistance is usable but may leave its changed wording unproved. TEST-ONLY fixtures never become production human claims. A production build must not unlock certification through a hidden flag, a self-signed local issuer or bundled test policy.

The app must genuinely implement issuance and verification conditional on independently admissible future evidence; an always-NP stub does not pass. Activating an empirically approved release/capture profile is a separate evidence/governance process, not something the final coding agent fabricates to make this checklist green. Help and feature copy state this availability plainly. A conventional Nostr event signature is not HWP.

## Required evidence and blockers

Every acceptance row records a test or observed run, platform/tool versions, input fixture identity and evidence location. Screenshots alone do not verify interaction, mocked relay tests alone do not establish third-party interoperability, a build alone does not establish actual provider storage and an unsigned archive alone does not establish notarized distribution. Automated tests use disposable synthetic identities; manual credentials stay outside the repository.

All blocking failures include data loss, mislabelled proof, private-data/key exposure, unescapable app-owned lock, corrupt/repair-required required exports, broken required provider lifecycle, missing mandatory feature and unverified release signing. Owner-only Developer ID/team/account access may remain BLOCKED while all obtainable implementation work proceeds; no credentials are invented and the single completion definition remains unmet until actual validation occurs.

Nonblocking documented limitations are the explicit current HWP empirical unavailability, finite/local capture limits, platform-owner ability to escape focus, relay retention/deletion uncertainty, nonidentical DOCX pagination, and lack of bespoke cross-platform apps/cloud backend/ZK/C2PA rendering certification. These are intentional truth boundaries, not hidden missing implementations.

## Performance gates

Measure a release build on M1/8GB or a slower supported Mac with exact fixture/hardware/OS recorded:100k-word typing p95 input-to-frame≤50ms while saving; no HWP/export/network main-thread stall>100ms; warm local document open≤3s; warm app-to-editable-window≤2s; idle without sound/network<1% of one CPU core averaged60s. HWP/export cancellation responds≤1s, obeying declared resources without a weaker accepting fallback. Investigate violations, not replace the baseline with faster hardware to hide them.

Final `product/mac/evidence/RELEASE.json` contains all60rows, releasecommit, artifactSHA256, platform matrix and signing/notarization evidence. All statuses must be PASS, with no missing rows or orphaned source revisions. `RELEASE.md` explains exact known limitations without overclaiming science or platform guarantees.
