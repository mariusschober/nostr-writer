# Reproducible checks

Run from a clean checkout; keep new outputs outside frozen directories.

## Repository integrity (no dependencies)

```sh
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

These validate recovered originals, snapshot hashes, package mappings, agent links and the frozen protocol. They do not accept a Mac implementation stage.

## Joined authoritative protocol

Create a virtual environment at repository root and install the exact pinned requirements:

```sh
python3 -m venv .venv-hwp
.venv-hwp/bin/python -m pip install -r protocol/v0/requirements.txt
```

Use Node.js and **OpenSSL 3**, visible on PATH. Recovery passed with Python 3.14.3, Node 22.16.0 and OpenSSL 3.6.3. The macOS system LibreSSL 3.3.6 produced an RFC 3161 test error. If Homebrew OpenSSL 3 is already installed, select its bin directory for this invocation (Apple silicon default below); do not replace frozen test expectations:

```sh
export PATH="/opt/homebrew/opt/openssl@3/bin:$PATH"
openssl version
cd protocol/v0
../../.venv-hwp/bin/python run_checks.py
node tools/check_interop.mjs
../../.venv-hwp/bin/python tools/check_freeze.py
```

`run_checks.py` without `--write` runs the 178 tests and deterministic/interoperability checks without replacing frozen reports. Never pass `--write` or run the manifest builder inside the freeze. A clean initial checkout already includes the deterministic vector.

## Earlier versions

Use the same Python environment, with each package as its working directory:

```sh
(cd algorithm/v0_2 && ../../.venv-hwp/bin/python -m unittest discover -s tests -v)
(cd algorithm/v0_3 && ../../.venv-hwp/bin/python -m unittest discover -s tests -v)
(cd algorithm && ../.venv-hwp/bin/python -m unittest test_reference -v)
(cd proof/hwp-c-1 && ../../.venv-hwp/bin/python -m unittest discover -s tests -v)
(cd proof/hwp-c-1 && node tools/independent_check.mjs)
```

A0.2 and A0.3 share the import name hwp_a: do not combine their PYTHONPATHs. HWP-C1's cross-backend test additionally needs a discoverable native libsodium. Its archived requirements omit that system dependency. On this recovery host, 94 tests passed and that one test errored because libsodium was absent; no implementation change was made. The independent C1 Node checker passed. See current evidence below before repeating.

The legacy A0.3/C1 report generators and experiments/foundation_checks.py write their output files. Run those only in a disposable copy if regenerating evidence; direct unittest avoids replacing original reports. The 33 foundation checks were run in a disposable copy and reproduced the original deterministic vector.

## Evidence boundaries

[Recovery results](recovery/VERIFICATION.md) list current execution and environment limitations. Archived RESULTS/PREPARATION record earlier runs only. No native app, Swift package, cloud provider, Word/Pages, signing or notarization acceptance was measured. Stage owners produce their own evidence under product/mac/evidence without inheriting these passes.
