# Native protocol and offline command-line preparation

**Component checks PASS; Stage 04 is not accepted.** Source commit `698172efc847d9370d0cef37f6f008bebc8ee426` on
`preparation/native-cores`. This work remains separate from the frozen Stage 01
candidate `251a7d1`; Stage 01 still needs final desktop observations and hosted CI.
No stage prerequisites or any of the 60 acceptance requirements have been waived.

## Implemented and reviewed

Native release/policy/capture admission, exact authenticated record reconstruction,
complete scope and inherited-origin binding, private transcript opening, actual
algorithm recomputation, conditional evaluator signing and atomic proof finalization
now use the earlier wire and deterministic algorithm implementations. Finalization
recomputes the candidate before retaining it. The offline `hwp-verify` CLI supports
separately identified V and R; an R request cannot fall back to attestation.
Independent policy bytes and an explicit pin are required. Bundled source is checked
against installed immutable anchors, never executed or fetched.

The distributable resources contain only protocol/algorithm definition anchors and
the frozen empty production policy. Public synthetic authorities and signing seeds
are confined to tests. A synthetic positive remains TEST-ONLY / NOT PROVABLE; it
cannot create an authentic product badge. The native capture recorder and product
proof experience are still mandatory later integration work.

Disclosure review fixed repeated-block allocation amplification, bounded decoded
bytes before retention, added cancellable fresh salts and removed a malformed-field
force unwrap. Regression cases reject missing opening fields without trapping.
Oracle generation uses the actual reference dependencies; regeneration produced the
same 600,015-byte disclosure fixture (SHA-256 `71e4967f7c5ef90bb15d712008e9395ce75db636c8ac4c19023b0639f0c81036`).

## Observed evidence

- 44 native package tests, zero failures, 140.021 seconds. Includes the preceding
  wire/algorithm tests, eight disclosure tests and five complete protocol tests.
- All 16 frozen cases compared in three verification configurations; successful
  full results match canonical CBOR exactly. Failure classifications match; wording
  is not a normative identity. Nine producer computations and private lineages match
  exactly; seven nonqualifying computations refuse issuance.
- 59 command-line/interoperability checks passed: 32 V/R vector executions,
  11 argument/file/mode rejection checks, 12 bounded malformed parser inputs and
  four native-to-Python/Node interoperability checks. Python recomputes the native
  signed result; Node verifies its public attestation. Dishonest evaluator evidence
  remains admitted only as test attestation and fails actual recomputation.
- Complete 1,250-opening disclosure crosses the private transport in five blocks;
  changed salt/event/count/order and unrelated blocks reject. A sub-2 MiB shared-block
  attack declaring 1,024,000 openings is refused before expansion.
- All 69 frozen protocol files, 326 source-of-truth files and 60 acceptance definitions
  retain their authoritative bytes/definitions. Required read-only checks passed.

The exact newly issued **public synthetic** sample is retained beside this report
because CryptoKit signatures are not assumed byte-deterministic. No real writing,
credentials, participant traces or approved empirical reports appear in it.

## Reproduce

From the preparation checkout, with the existing reference Python environment:

```sh
HWP_NATIVE_PROTOCOL_SAMPLE=/private/tmp/nostr-writer-native-protocol-sample swift test --package-path mac/Packages/WriterHWP
/Users/schober/Projects/'Nostr Writer'/.venv-hwp/bin/python mac/Packages/WriterHWP/Tools/check_native_protocol.py --binary mac/Packages/WriterHWP/.build/debug/hwp-verify --native-sample /private/tmp/nostr-writer-native-protocol-sample
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

`results.json` records commands, result counts, limitations and exact sample hashes.
`source-files.json` pins the tested source. Raw logs are retained. The first
interoperability invocation used system Python without `cryptography`; rerunning
with the existing oracle environment passed, with no product-source change.

## Remaining acceptance

Stage 04 still requires the accepted Stage 03 capture capability findings, real
capture integration, asynchronous revision-bound UI, cancellation observations,
consented encrypted private evidence handling, full substitution/fuzz/performance
coverage and actual app/device checks. No empirical accuracy or production authority
is inferred from these tests. The full eight-stage application goal remains open.
