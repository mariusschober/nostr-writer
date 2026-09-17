# Pinned inputs and checkout bootstrap

## Authorities

- Preparation base: `mariusschober/nostr-writer@c53e794a11aa801b553af462fe5da33593e12eee`.
- NostrShot source: `mariusschober/NostrShot@cf28e9652dc8eb7bbd85008163071820cd781998`, `mac/`.
- Nostr specifications: `nostr-protocol/nips@a2494f4f81d46684e5814a9bf35e2b1df978f955`.
- Supplied final Human Writing Protocol v0.0.0 definition SHA-256: `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`.
- Original `FREEZE.json` SHA-256: `c04ded3b82a462aa22a7289a5bcbeccd5719124a4718cb5fbd4f47c297993d88`.
- Exact `vectors/interchange.json`: 16,161,774 bytes, SHA-256 `356a1cea43b4e961176cf52855fa4c2f4808e9d37d59a4c781c3967532b96bbe`.

The final freeze, not an intermediate chat progress value, is authoritative. Its 67 inventoried files plus FREEZE.json/FREEZE.sha256 comprise 69 files. Preserve original upstream dates and publication notes, even where they describe an earlier upload failure. New publication status belongs outside the freeze.

## Self-contained bootstrap

The binary parts in `product/mac/inputs/` concatenate into one pinned XZ/USTAR archive containing 68 exact frozen files. The large deterministic vector is generated from the included source rather than stored as 16 MB of hex JSON. An ordinary clone contains everything required; a coding agent needs no conversation attachment or private download link.

```sh
python3 tools/bootstrap_protocol.py --extract-only
python3 -m venv .venv-hwp
.venv-hwp/bin/python -m pip install -r protocol/v0/requirements.txt
.venv-hwp/bin/python tools/bootstrap_protocol.py
```

Bootstrap verifies the transport hash, original inventory hash and every frozen file before materializing anything. It rejects changed existing files. Full mode runs only the original vector generator into a temporary external destination, validates the pinned digest/size, atomically installs that missing vector and runs the original freeze checker. It never runs the manifest builder, modifies normative files, trains a model, invents telemetry or overwrites conflicting input.

The resulting 69 files are byte-identical to the supplied freeze. If generation differs, retain the incorrect result outside the frozen directory, report the difference and stop HWP work rather than repinning it. Agents may commit the verified materialized files for direct browsing; they may not change their content to simplify the port.

The native app does not execute this bootstrap or require Python/Node. These are development oracles. Stage04 ports the exact computation and checks interoperability. A new Swift executable has its own program/release identity; replacing implementation bytes is not an invisible change to an old pinned program.

## NostrShot dependency pins

`swift-secp256k1` 0.23.2: `e70a10e036a55fffea31568f0af92d69b6d449cd`.

`KeyboardShortcuts` 3.0.1: `49c3fc04ea827f816df67843bfcc57286b47ff06`.

Use these for initial adoption. Changes require a recorded compatibility/security reason and tests. Stage01 locks new named dependencies to actual reviewed commits and licenses with macOS14 compatibility. This handoff does not invent uninspected latest tags.

## Preparation evidence

Host: Linux, Swift6.2.1. Forty-seven portable Foundation tests passed. All178 frozen protocol tests passed in partitions, with no failures/errors/skips. The freeze checker and independent Node interoperability check passed; regenerated vectors were identical. No Mac UI/build, real provider lifecycle, native NostrShot build or Developer ID/notarization was run here. Stage01 records actual Xcode/SDK; later Mac-specific claims require native evidence.
