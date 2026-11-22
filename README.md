# Nostr Writer

A native Mac writing application in development, with exact source preservation, local document recovery, a Markdown editor and consented local writing history. Nostr publishing and native Human Writing Protocol (HWP) integration are later stages.

The recorded stage ledgers accept Stages 01 and 02. **Stage 03 remains blocked and unaccepted**, with real on-device dictation still awaiting owner input. See [current implementation status](IMPLEMENTATION.md) and [Stage 03 evidence](product/mac/evidence/STAGE-03.md). This is not a completed or released app.

## Start here

1. Read [AGENTS.md](AGENTS.md) and [IMPLEMENTATION.md](IMPLEMENTATION.md).
2. Open the [Mac workspace](mac/README.md) and [development guide](mac/DEVELOPMENT.md).
3. Use the [product contract and stage sequence](product/mac/README.md) with the [recorded acceptance status](product/mac/evidence/STATUS.json). Finish the outstanding Stage 03 observations before Stage 04.

A clone contains the full 69-file frozen protocol, including its 16 MB interoperability vector. No ChatGPT attachment or materialization job is required.

```sh
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

These are read-only standard-library checks. See [test instructions](docs/VERIFICATION.md) and [observed recovery results](docs/recovery/VERIFICATION.md).

## Repository map

| Path | Meaning |
|---|---|
| [mac](mac/README.md) | Native Xcode app, Swift packages, tests and build scripts |
| [product/mac](product/mac/README.md) | Product contracts, eight plans and starts, 60 mandatory criteria and stage evidence |
| [protocol/v0](protocol/v0/README.md) | **Authoritative joined HWP v0.0.0**, immutable original distribution |
| [algorithm/v0_3](algorithm/v0_3/README.md) | Complete HWP-A 0.3 baseline and adversarial audit |
| [algorithm/v0_2](algorithm/v0_2/README.md) | Earlier HWP-A 0.2, isolated from other versions |
| [algorithm](algorithm/README.md) | Original A1 source and version index |
| [proof/hwp-c-1](proof/hwp-c-1/README.md) | Historical cryptographic core candidate |
| [research/hwp](research/hwp/01-foundation.md), [experiments](experiments/README.md) | Original research and synthetic checks |
| [history/astra-pro](history/astra-pro/README.md) | All supplied replies, exact files/ZIPs, mappings and hashes |
| [RECONCILIATION.md](RECONCILIATION.md) | Published/missing/recovered status and remaining gaps |

Original WriterFoundation source/tests were **not supplied or recoverable from the committed corrupt transport**. Stage 01 implemented a new package from the contracts; its evidence is separate from the archived 47-pass claim. [Recovery gap register](docs/recovery/MISSING-ARTIFACTS.md).

## Claim boundaries

Frozen source locator: [human-writing-protocol-v0](https://github.com/mariusschober/nostr-writer/tree/human-writing-protocol-v0).

Frozen definition: `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`. Production approvals remain empty. Conformance fixtures cannot authorize real HUMAN-WRITTEN certificates; NOT PROVABLE never means AI-generated. Recovery and unit tests do not establish detector accuracy, trusted native capture, independent security review or Mac application completion.
