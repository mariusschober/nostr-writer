# Nostr Writer

A native Mac writing application with optional Nostr publishing and experimental Human Writing Protocol (HWP) integration. **Application implementation has not started.** This repository contains the recovered research, executable reference protocols, and Mac implementation contract.

## Start here

1. Read [AGENTS.md](AGENTS.md) and [IMPLEMENTATION.md](IMPLEMENTATION.md).
2. Read the [Mac handoff](product/mac/README.md) and its recovery notice.
3. Execute [Stage 01](product/mac/plans/PLAN-01-FOUNDATION.md) using [START 01](product/mac/starts/START-01.md), then the remaining stages in order.

A clone contains the full 69-file frozen protocol, including its 16 MB interoperability vector. No ChatGPT attachment or materialization job is required.

```sh
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

These are read-only standard-library checks. See [test instructions](docs/VERIFICATION.md) and [observed recovery results](docs/recovery/VERIFICATION.md).

## Repository map

| Path | Meaning |
|---|---|
| [product/mac](product/mac/README.md) | Product/UX/architecture, eight plans and starts, 60 mandatory criteria |
| [protocol/v0](protocol/v0/README.md) | **Authoritative joined HWP v0.0.0**, immutable original distribution |
| [algorithm/v0_3](algorithm/v0_3/README.md) | Complete HWP-A 0.3 baseline and adversarial audit |
| [algorithm/v0_2](algorithm/v0_2/README.md) | Earlier HWP-A 0.2, isolated from other versions |
| [algorithm](algorithm/README.md) | Original A1 source and version index |
| [proof/hwp-c-1](proof/hwp-c-1/README.md) | Historical cryptographic core candidate |
| [research/hwp](research/hwp/01-foundation.md), [experiments](experiments/README.md) | Original research and synthetic checks |
| [history/astra-pro](history/astra-pro/README.md) | All supplied replies, exact files/ZIPs, mappings and hashes |
| [RECONCILIATION.md](RECONCILIATION.md) | Published/missing/recovered status and remaining gaps |

Original WriterFoundation source/tests were **not supplied or recoverable from the committed corrupt transport**. Stage 01 implements these contracts. The archived 47-pass Swift claim is not evidence for code in this checkout. [Gap register](docs/recovery/MISSING-ARTIFACTS.md).

## Claim boundaries

Frozen source locator: [human-writing-protocol-v0](https://github.com/mariusschober/nostr-writer/tree/human-writing-protocol-v0).

Frozen definition: `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`. Production approvals remain empty. Conformance fixtures cannot authorize real HUMAN-WRITTEN certificates; NOT PROVABLE never means AI-generated. Recovery and unit tests do not establish detector accuracy, trusted native capture, independent security review or Mac application completion.
