# Pinned inputs and checkout verification

Updated 17 September 2026; original archived in history/astra-pro/originals/Chat 6/INPUTS.md.

- Original preparation base: c53e794a11aa801b553af462fe5da33593e12eee.
- Inspected recovery base: 262cb213cda8e533a958fe21915a2406138b6f9c.
- NostrShot: mariusschober/NostrShot@cf28e9652dc8eb7bbd85008163071820cd781998, mac/.
- NIPs: nostr-protocol/nips@a2494f4f81d46684e5814a9bf35e2b1df978f955.
- HWP definition: 58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4.
- FREEZE.json SHA-256: c04ded3b82a462aa22a7289a5bcbeccd5719124a4718cb5fbd4f47c297993d88.
- Interoperability vector: 16,161,774 bytes; SHA-256 356a1cea43b4e961176cf52855fa4c2f4808e9d37d59a4c781c3967532b96bbe.

All 69 original frozen files are directly committed. The new bootstrap verifies without writing. No transport chunks or vector regeneration are needed.

```sh
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
python3 -m venv .venv-hwp
.venv-hwp/bin/python -m pip install -r protocol/v0/requirements.txt
```

Continue with docs/VERIFICATION.md. Python/Node are development oracles, not release-app dependencies. Preserve frozen dates/results/publication notes. Restore exact missing bytes from Git/original ZIP, never bless a changed digest or run the manifest builder.

Pinned NostrShot Package.swift was retrieved and confirms P256K/swift-secp256k1 0.23.2 and KeyboardShortcuts 3.0.1. Original recorded revisions are e70a10e036a55fffea31568f0af92d69b6d449cd and 49c3fc04ea827f816df67843bfcc57286b47ff06; Stage 01 checks Package.resolved before adoption. Verify and lock other named dependencies then.

Foundation source/tests are missing. Read RECOVERY-NOTES.md and implement in Stage 01; historical preparation passes are not new implementation evidence.
