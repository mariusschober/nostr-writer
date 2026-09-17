# Recovery verification — 17 September 2026

These are fresh local observations, separate from archived Astra results. No application stage is accepted.

| Check | Result | Evidence |
|---|---|---|
| Recovery-tool corruption regressions | PASS, 6/6, including rejection before executing an altered checker | tools/tests/test_check_preparation.py |
| Repository integrity, current local links and plan/acceptance structure | PASS; 8 plans, 8 starts, 60 mandatory definitions | tools/check_preparation.py |
| All 47 supplied files preserved | PASS, SHA-256 and byte sizes | [Inventory](../../history/astra-pro/RECOVERY-INVENTORY.json) |
| HWP-A 0.2 | PASS, 76/76 | [Log](logs/a02-unittest.log) |
| HWP-A 0.3 | PASS, 100/100 | [Log](logs/a03-unittest.log) |
| Joined HWP v0 | PASS, 178/178 with OpenSSL 3.6.3 | [Log](logs/v0-run-checks-openssl3.log) |
| v0 independent Node verification | PASS, 16 public cases plus binding checks | [Log](logs/node-interop.log) |
| v0 deterministic vectors | PASS, two hash seeds and original bytes agree | [Protocol log](logs/v0-run-checks-openssl3.log) |
| v0 inventory before/after | PASS, 69 original files unchanged | [Before](logs/freeze-before.log), [after](logs/freeze-after.log) |
| Legacy A1 | PASS, 53/53 | [Log](logs/a1-unittest.log) |
| Original foundation experiment | PASS, 33 assertions; original deterministic vector reproduced | [Log](logs/foundation-checks.log) |
| Historical HWP-C1 unit suite | 94 PASS; 1 ERROR: native libsodium unavailable | [Log](logs/c1-unittest.log) |
| HWP-C1 independent Node checker | PASS | [Log](logs/c1-node-interop.log) |
| First v0 run with system LibreSSL | 177 PASS; 1 RFC 3161 chain-validation ERROR; passed with OpenSSL 3 | [Retained diagnostic](logs/v0-run-checks-libressl.log) |
| Existing research/C1/experiment/A1 implementation bytes | PASS, unchanged from remote baseline | [Baseline inventory](../../history/astra-pro/RECOVERY-INVENTORY.json) |
| Mac application / original Swift preparation package | NOT MEASURED / original package missing | [Gap register](MISSING-ARTIFACTS.md) |

[Detailed HWP recovery report](HWP-RECOVERY-REPORT.md) records exact commands, input identities and dependencies. The successful environment uses Python 3.14.3, cryptography 46.0.4, asn1crypto 1.5.1, numpy 2.3.5, scipy 1.17.0, jsonschema 4.26.0, Node 22.16.0, and OpenSSL 3.6.3. Native host: macOS 26.6.2/arm64, Xcode 26.6/Swift 6.3.3. The tests were run without changing recovered source or freeze manifests.

The integrated repository checker passed on the reconciled snapshot. Publication is verified against the actual remote commit/tag and a fresh clone, rather than by treating an upload response as proof of materialization. The recovered HWP-A suites and joined v0 total **354 passing tests**; legacy checks do not supply empirical validation. Native libsodium remains an environment prerequisite for reproducing the full historical C1 suite. No participant sessions, trained human-data models, admitted native capture profiles, production approvals or real proofs were created.
