# Nostr Writer supplied artifact recovery evidence

Date: 2026-09-17

Repository: `/private/tmp/nostr-writer-reconcile-20260917`

Scope was limited to `algorithm/v0_2/`, missing files under `algorithm/v0_3/`, `protocol/v0/`, and this validation directory. No Git index, commit, push, or unrelated repository file was changed.

## Archive audit and recovery mapping

Before extraction, every member name from all three ZIP files was inspected. All archives passed the same checks: no absolute paths, no `..` traversal components, no backslash paths, no duplicate members, and no symlinks. The full inventories and audit results are in `archive-audit.log`.

| Source archive | Archive entries | Destination mapping | Existing comparison | Recovered result |
| --- | ---: | --- | --- | --- |
| `HWP-A-0.2.0 (1).zip` | 43 | strip `algorithm/` -> `algorithm/v0_2/` | 0 same, 43 missing, 0 different | 43 files; exact directory match |
| `HWP-A-0.3.0 (1).zip` | 38 | `algorithm/v0_3/` -> `algorithm/v0_3/`; ignore archive `algorithm/README.md` | 18 same, 19 missing, 0 different; ignored parent README was also byte-identical | 37 files in version subtree; exact directory match |
| `Chat 5/Human-Writing-Protocol-v0.zip` | 69 | preserve `protocol/v0/` | 0 same, 69 missing, 0 different | 69 files; exact directory match |

Only missing files were copied (`rsync -a --ignore-existing`). Final `diff -qr` comparisons against isolated staged extraction trees passed for all three destinations. `git diff --exit-code -- algorithm/v0_2 algorithm/v0_3 protocol/v0` returned 0, confirming the 18 already tracked v0.3 files remained unchanged.

Archive SHA-256 values:

- v0.2 ZIP: `d57cb993593cbdf4beb90180853cdaa08a793081ebf1a5d08e79e9628b26d229`
- v0.3 ZIP: `8da86d0d12d6800c759f88f570898dd7e3874ba6727076dd852627f52a6a5211`
- protocol v0 ZIP: `5588ffcf0ff4bf108a15a206f96ecc9db86692089839b62b068cb9d24b6f8de0`

## Current validation environment

- Python `3.14.3`
- Node `v22.16.0`
- OpenSSL `3.6.3` for the successful protocol run
- `cryptography 46.0.4`
- `asn1crypto 1.5.1`
- `numpy 2.3.5`
- `scipy 1.17.0`
- `jsonschema 4.26.0`

Dependencies were installed only in `/private/tmp/nostr-writer-validation/venv` from the frozen protocol requirements.

## Current observed checks

The archive-provided `run_checks.py` files were read before execution. The v0.3 runner writes tracked artifacts, so the current v0.3 suite was run directly with `unittest`. Protocol v0's runner defaults to read-only behavior unless passed `--write`; it was run without `--write`.

1. Freeze inventory before tests:
   - Command: `python tools/check_freeze.py`
   - Result: PASS, 67 inventoried payload files plus `FREEZE.json` and `FREEZE.sha256` = 69 distribution files.
   - Protocol-definition SHA-256: `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`
   - `FREEZE.json` SHA-256: `c04ded3b82a462aa22a7289a5bcbeccd5719124a4718cb5fbd4f47c297993d88`

2. HWP-A v0.2:
   - Command: `PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests -v`
   - Result: PASS, 76/76 tests, 0 failures, 0 errors, 0 skipped; 1.260 seconds reported by unittest.

3. HWP-A v0.3:
   - Command: `PYTHONDONTWRITEBYTECODE=1 python -m unittest discover -s tests -v`
   - Result: PASS, 100/100 tests, 0 failures, 0 errors, 0 skipped; 2.799 seconds reported by unittest.

4. Frozen protocol v0:
   - Command: `PATH=/opt/homebrew/opt/openssl@3/bin:/usr/local/bin:/usr/bin:/bin PYTHONDONTWRITEBYTECODE=1 python run_checks.py`
   - Result: PASS, 178/178 tests, 0 failures, 0 errors, 0 skipped; deterministic vectors matched across hash seeds 0 and 987 and the frozen file; 14.431 seconds reported by unittest.
   - A first diagnostic run using macOS system `LibreSSL 3.3.6` executed all 178 tests but produced one RFC 3161 chain-validation error (`test_valid_token`). No source was changed. Re-running with already installed OpenSSL 3.6.3 passed all 178. Both logs are retained to keep the environment distinction explicit.

5. Independent Node verifier, run separately:
   - Command: `node tools/check_interop.mjs`
   - Result: PASS under Node v22.16.0; 16 public cases, 12 canonical-CBOR cases, 7 rejected-CBOR cases, 1,250 private-event commitments, 1 normalized record, 1 lineage commitment, and 4 inclusion paths.

6. Freeze inventory after tests:
   - Command: `python tools/check_freeze.py`
   - Result: PASS with the same 67-file payload inventory and the same protocol/freeze digests. The before/after logs are byte-identical.

## Historical claims versus current observation

The archives contain saved outputs that report 76 tests for v0.2, 100 for v0.3, and 178 for final protocol v0. Those are historical artifact claims. The results above are fresh executions in the environment listed here. Older references to 174 tests or a `559e...` digest were not used as acceptance evidence.

## Claim boundaries carried by the recovered protocol

The current run reports zero real human sessions, zero models trained on real human data, zero evaluated native capture paths, zero empirically approved releases, and zero real human-writing proofs issued. The separate Node verifier checks class-V attestation and binding behavior; it is not an independent behavioral implementation. These limitations are part of the recovered artifact's own current report, not newly inferred product claims.

## Evidence files

- `archive-audit.log`: full ZIP inventories and path/duplicate/symlink audit
- `digest-checks.log`: archive, freeze, and protocol-definition digests
- `a02-unittest.log`: current 76-test run
- `a03-unittest.log`: current 100-test run
- `v0-run-checks-openssl3.log`: successful current 178-test protocol run
- `v0-run-checks-libressl.log`: retained diagnostic failure under system LibreSSL
- `node-interop.log`: separate Node verifier run
- `freeze-before.log`, `freeze-after.log`: immutable-inventory checks

