# Reproduce the foundation checks

These are synthetic checks of selected cryptographic mechanics, exact-byte handling, range coverage, and statistical calculations. They are not a trained detector, a complete protocol verifier, a security audit, or evidence that human composition can be distinguished from an adaptive simulation.

From the repository root, using Python 3.10 or later:

```sh
python -m venv .venv
. .venv/bin/activate
python -m pip install -r experiments/requirements.txt
python experiments/foundation_checks.py
```

On Windows, activate the virtual environment using its platform-specific activation command. The published run used Python 3.13.5 and cryptography 46.0.4. The dependency pin reproduces the tested version; it is not a claim that the version will remain appropriate indefinitely.

The script writes `vectors.json` and `results.json` beside itself and fails with an assertion if a check fails. Cryptographic vectors are deterministic. Environment-version fields in results naturally differ on other environments.

**The private seed and salts in the vectors are deliberately public test fixtures. Never use them for real signing or private commitments.** The miniature signed record has the result NOT PROVABLE and the role `research_fixture`. It is not a HUMAN-WRITTEN certificate.

See [research results](../research/hwp/07-results.md) for the interpretation and all unperformed validation work.
